#!/usr/bin/env bash
# Reap idle codex app-server-broker processes.
#
# Why this exists: the codex-plugin-cc broker (app-server-broker.mjs) is spawned
# detached (reparents to pid 1) and holds a persistent codex "app-server" child
# — one broker+app-server pair (~85-290MB) per workspace. It has NO idle timeout
# upstream (only broker/shutdown RPC + SIGTERM handlers that nobody triggers), so
# once the Claude session that spawned it dies the pair lives until reboot. Over
# days these accumulate (observed: 11 pairs, ~1.7GB, oldest 8d). This reaps any
# broker that has stayed idle >= CODEX_BROKER_IDLE_TTL seconds.
#
# Safety: "idle" is measured by client connections on the broker's unix socket.
# An in-flight request/stream holds a connection for its whole duration, so a
# broker with only its own listener fd (1 ref) has nothing in flight. We require
# sustained idleness (TTL) AND re-check immediately before SIGTERM (narrows, but
# cannot fully close, the check→kill race — see the recheck below). SIGTERM
# triggers the broker's own clean shutdown (kills the app-server child, unlinks
# socket+pidfile); if it does not exit we SIGKILL it AND its captured child so no
# app-server is left dangling. A reaped-but-still-wanted broker simply respawns on
# the next codex call (~2-3s) — that is exactly the broker-reuse contract.
#
# Idleness is SAMPLED at each run, not observed continuously: the stored timestamp
# means "first seen idle at a run," and requests that begin and end entirely between
# two runs are invisible. So a broker used in every inter-run gap can be reaped as if
# continuously idle. This is an accepted tradeoff — truly continuous observation would
# need a daemon, and a wrongly-reaped broker just respawns on the next call (~2-3s),
# which is exactly the broker-reuse contract. Keep the run interval well under the TTL
# to shrink the window.
#
# Portability: must run under macOS /bin/bash 3.2 (launchd), so NO associative
# arrays, mapfile, or other bash-4-isms. Also runs cross-platform via session-start.sh.
#
# Env:
#   CODEX_BROKER_IDLE_TTL   seconds a broker must stay idle before reaping (default 1800)
# Flags:
#   --dry-run   report what would be reaped, kill nothing
#   --verbose   log per-broker decisions
set -euo pipefail

IDLE_TTL="${CODEX_BROKER_IDLE_TTL:-1800}"
STATE_DIR="$HOME/.claude/state"
STATE_FILE="$STATE_DIR/codex-broker-idle.tsv"
LOCK_DIR="$STATE_DIR/.codex-broker-reaper.lock"

DRY_RUN=0
VERBOSE=0
for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=1 ;;
        --verbose) VERBOSE=1 ;;
        *) echo "unknown flag: $arg" >&2; exit 2 ;;
    esac
done

mkdir -p "$STATE_DIR"
now="$(date +%s)"
log() { [ "$VERBOSE" -eq 1 ] && echo "$*" || true; }

# BEST-EFFORT single-instance lock. mkdir is the atomic primitive (no flock on macOS).
# The holder records pid + process start time; any later run treats a lock whose owner
# is dead OR whose pid was recycled (start time differs) as stale and steals it, so the
# reaper never wedges after a crash (C5, round4-C1). `ps -o lstart=` and mkdir avoid
# stat/date, so behaviour is identical under GNU (interactive) and BSD (launchd) userlands.
#
# It is NOT a perfect mutex: portable shell without flock/atomic-CAS cannot fully close
# the stale-steal and mkdir→write_lock_id windows, so two runs can very rarely proceed
# together. That is deliberately tolerated — the reap operations (kill, rm -rf, state
# `mv`) are idempotent, and the only way concurrency can bite is a resurrected idle
# timer reaping a broker a cycle early, which merely triggers a ~2-3s respawn (the
# broker-reuse contract). A perfect lock is not worth more machinery for that outcome.
proc_start() { ps -o lstart= -p "$1" 2>/dev/null | sed 's/^ *//;s/ *$//'; }
write_lock_id() { printf '%s\n%s\n' "$$" "$(proc_start "$$")" > "$LOCK_DIR/id"; }
acquire_lock() {
    if mkdir "$LOCK_DIR" 2>/dev/null; then
        write_lock_id
        return 0
    fi
    local h_pid h_start i
    h_pid="$(sed -n 1p "$LOCK_DIR/id" 2>/dev/null || true)"
    h_start="$(sed -n 2p "$LOCK_DIR/id" 2>/dev/null || true)"
    # A missing/partial id may just mean a live holder is a few ms into acquiring
    # (mkdir then write_lock_id is not atomic). Retry briefly before ruling it stale,
    # so we never steal from a mid-acquire holder — which would let two runs proceed
    # concurrently and race the final state `mv` into resurrecting a stale idle timer
    # (round8-C2). A holder that truly crashed between mkdir and write stays empty
    # through the retries and is then correctly stolen.
    if [ -z "$h_pid" ] || [ -z "$h_start" ]; then
        for i in 1 2 3 4 5; do
            sleep 0.05
            h_pid="$(sed -n 1p "$LOCK_DIR/id" 2>/dev/null || true)"
            h_start="$(sed -n 2p "$LOCK_DIR/id" 2>/dev/null || true)"
            [ -n "$h_pid" ] && [ -n "$h_start" ] && break
        done
    fi
    # Back off ONLY on positive proof of a live owner: pid present AND its current
    # start time matches the recorded one. Everything else is stale — dead holder,
    # recycled pid, or a still-empty id from a crash mid-acquire — so steal it.
    if [ -n "$h_pid" ] && [ -n "$h_start" ] && [ "$(proc_start "$h_pid")" = "$h_start" ]; then
        return 1
    fi
    rm -rf "$LOCK_DIR" 2>/dev/null || true
    if mkdir "$LOCK_DIR" 2>/dev/null; then
        write_lock_id
        log "recovered stale lock (stale holder pid=${h_pid:-none})"
        return 0
    fi
    return 1
}
acquire_lock || exit 0
# Only release the lock if WE still own it — never clobber a lock a concurrent run
# has since stolen (round2-C1). The lock is best-effort: all reap operations below
# (kill, rm -rf, atomic state `mv`) are idempotent, so even two concurrent runs are
# safe; the lock merely avoids redundant work.
trap '[ "$(sed -n 1p "$LOCK_DIR/id" 2>/dev/null || true)" = "$$" ] && rm -rf "$LOCK_DIR" 2>/dev/null || true' EXIT

# lsof is the idle signal source; without it we cannot judge idleness safely.
if ! command -v lsof >/dev/null 2>&1; then
    log "lsof not available — skipping reap (cannot measure idleness)"
    exit 0
fi

# Refs to a broker's socket path in the global unix-socket table.
#   >1  == a client is connected (in flight)
#    1  == listener fd only (idle)
#    0  == lsof did not even see the live broker's own listener → output untrusted
# We FAIL CLOSED: callers treat 0 as "active/untrusted" and never reap on it (C1).
sock_refs() {
    lsof -U 2>/dev/null | grep -Fc -- "$1" || true
}

# Identity guards against PID reuse (round2-C3): a PID we enumerated can exit and be
# recycled before/between our signals. Re-confirm the target is still the exact
# broker (its command line names both the broker script AND its unique socket) or a
# codex app-server, immediately before every destructive signal.
is_broker() {  # <pid> <sock>
    local c
    c="$(ps -p "$1" -o command= 2>/dev/null || true)"
    [ -n "$c" ] || return 1
    printf '%s' "$c" | grep -q 'app-server-broker\.mjs' || return 1
    printf '%s' "$c" | grep -Fq -- "$2" || return 1
    return 0
}
is_appserver() {  # <pid>
    local c
    c="$(ps -p "$1" -o command= 2>/dev/null || true)"
    [ -n "$c" ] || return 1
    printf '%s' "$c" | grep -q 'codex.*app-server'
}

tmp_state="$(mktemp "$STATE_DIR/.codex-broker-idle.XXXXXX")"

# Enumerate live brokers: "<pid> <unix-socket-path>" (unix endpoints only).
brokers="$(ps -eo pid,command \
    | grep '[a]pp-server-broker.mjs' \
    | sed -nE 's/^[[:space:]]*([0-9]+).*unix:([^[:space:]]+broker\.sock).*/\1 \2/p' || true)"

reaped=0
while read -r pid sock; do
    [ -n "${pid:-}" ] && [ -n "${sock:-}" ] || continue
    refs="$(sock_refs "$sock")"

    # 0 refs == lsof could not see this live broker's own listener → untrusted; skip.
    # >1 refs == in flight. Either way: not safe to reap, drop any idle record.
    if [ "${refs:-0}" -ne 1 ]; then
        log "skip     pid=$pid refs=$refs (active/untrusted)  $sock"
        continue
    fi

    since="$(awk -F'\t' -v p="$pid" -v s="$sock" '$1==p && $2==s{print $3; exit}' "$STATE_FILE" 2>/dev/null || true)"
    [ -n "$since" ] || since="$now"
    idle_for=$(( now - since ))

    if [ "$idle_for" -lt "$IDLE_TTL" ]; then
        log "idle     pid=$pid idle=${idle_for}s (<${IDLE_TTL}s) — tracking"
        printf '%s\t%s\t%s\n' "$pid" "$sock" "$since" >> "$tmp_state"
        continue
    fi

    if [ "$DRY_RUN" -eq 1 ]; then
        echo "[dry-run] would reap broker pid=$pid idle=${idle_for}s  $sock"
        continue
    fi

    # Capture the app-server child(ren) now — with start time — so we can clean them
    # up if the broker has to be SIGKILLed (which bypasses shutdown() and would
    # otherwise orphan them — C4), while surviving PID reuse in the sweep (round5-C2).
    # NEWLINE-separated "pid|start-time" records — the start time contains spaces,
    # so records must be split on newlines only, never by word-splitting (round6-C1).
    children=""
    for c in $(pgrep -P "$pid" 2>/dev/null || true); do
        children="$children$c|$(proc_start "$c")
"
    done

    # Do the (slower) PID-identity guard FIRST so that the idleness re-check is the
    # very last operation before SIGTERM — nothing runs between it and the kill,
    # keeping the check→kill race as tight as a shell allows (round2-C3 identity +
    # round3-C1 ordering; the race can be narrowed, not fully closed, in shell).
    if ! is_broker "$pid" "$sock"; then
        log "raced    pid=$pid no longer the broker for $sock — skipping"
        continue
    fi
    if [ "$(sock_refs "$sock")" -ne 1 ]; then
        log "raced    pid=$pid no longer idle-trusted before reap — keeping"
        continue
    fi
    kill -TERM "$pid" 2>/dev/null || true

    for _ in $(seq 1 15); do
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.2
    done
    # Only SIGKILL if it is STILL this broker (not a recycled pid).
    if kill -0 "$pid" 2>/dev/null && is_broker "$pid" "$sock"; then
        kill -KILL "$pid" 2>/dev/null || true
    fi

    # Guarantee no dangling app-server whichever path the broker died by (C4):
    # sweep the captured children, killing only those that are STILL the same codex
    # app-server — command class AND original start time must match, so a recycled
    # PID is never signalled (round2-C3 + round5-C2 identity).
    while IFS= read -r entry; do
        [ -n "$entry" ] || continue
        c="${entry%%|*}"; cstart="${entry#*|}"
        [ -n "$c" ] || continue
        is_appserver "$c" || continue
        [ "$(proc_start "$c")" = "$cstart" ] || continue
        kill -TERM "$c" 2>/dev/null || true
        for _ in 1 2 3 4 5; do kill -0 "$c" 2>/dev/null || break; sleep 0.2; done
        if kill -0 "$c" 2>/dev/null && is_appserver "$c" && [ "$(proc_start "$c")" = "$cstart" ]; then
            kill -KILL "$c" 2>/dev/null || true
        fi
    done <<< "$children"

    # Verify the broker is actually gone before touching its dir or claiming success.
    # SIGKILL is uncatchable so this is normally a no-op, but never delete a live
    # broker's dir or falsely report a reap if the kill somehow failed (round5-C1).
    if is_broker "$pid" "$sock"; then
        log "warn     pid=$pid survived kill — leaving dir intact, not reporting reaped"
        continue
    fi
    dir="$(dirname "$sock")"
    case "$(basename "$dir")" in
        cxc-*) rm -rf "$dir" 2>/dev/null || true ;;
    esac

    echo "reaped broker pid=$pid idle=${idle_for}s  $dir"
    reaped=$(( reaped + 1 ))
done <<< "$brokers"

# GC orphan temp dirs whose broker died without cleaning up (crash / SIGKILL /
# reboot survivors). Remove a dir ONLY on positive proof of a dead codex broker:
# it must contain a broker.pid naming a process that is no longer alive. A stale
# unix-socket NODE outlives its process, so `-S` is NOT a liveness test (C6). We do
# NOT delete pidfile-less dirs — those are either a broker still initializing (dir
# created before broker.pid is written) or not ours (round2-C2).
for base in "${TMPDIR:-/tmp}" /var/folders/*/*/T /tmp; do
    for dir in "$base"/cxc-*; do
        [ -d "$dir" ] || continue
        [ -f "$dir/broker.pid" ] || continue           # no ownership proof → leave alone
        bpid="$(cat "$dir/broker.pid" 2>/dev/null || true)"
        [ -n "$bpid" ] || continue                     # unreadable → leave alone
        kill -0 "$bpid" 2>/dev/null && continue        # broker still alive → keep
        if [ "$DRY_RUN" -eq 1 ]; then
            echo "[dry-run] would GC orphan dir  $dir"
        else
            rm -rf "$dir" 2>/dev/null || true          # named pid is dead → safe to GC
        fi
    done
done

# A dry run must not mutate the idle-timer state (round4-I1): reap-eligible brokers
# are intentionally omitted from tmp_state, so committing it would reset their timers.
if [ "$DRY_RUN" -eq 1 ]; then
    rm -f "$tmp_state"
else
    mv -f "$tmp_state" "$STATE_FILE"
fi

[ "$reaped" -gt 0 ] && log "reaped $reaped broker(s)"
exit 0
