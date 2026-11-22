#!/usr/bin/env bash
# Shared portability helpers for hooks and scripts.
# Source with: . "$(dirname "$0")/_lib.sh" (hooks)
#           or: . "$(dirname "$0")/../hooks/_lib.sh" (scripts)

# Portable md5 — prints the hex digest of stdin.
# Linux: md5sum; macOS: md5 -q
portable_md5() {
    if command -v md5sum >/dev/null 2>&1; then
        md5sum | awk '{print $1}'
    elif command -v md5 >/dev/null 2>&1; then
        md5 -q
    else
        echo "[_lib] no md5 implementation found" >&2
        return 1
    fi
}

# 12-char repo hash used by the cross-review marker system.
repo_hash() {
    printf '%s' "$1" | portable_md5 | head -c 12
}

# portable_timeout <secs> <cmd...>: timeout, else gtimeout, else perl. Exit 124 on timeout,
# 127 when no implementation exists (so callers can tell "missing binary" from "failed").
# A command that survives SIGTERM is SIGKILLed PORTABLE_TIMEOUT_KILL_AFTER (15) seconds later.
portable_timeout() {
    local secs="$1"; shift
    local grace="${PORTABLE_TIMEOUT_KILL_AFTER:-15}" bin rc
    if command -v timeout >/dev/null 2>&1; then
        bin=timeout
    elif command -v gtimeout >/dev/null 2>&1; then
        bin=gtimeout
    elif command -v perl >/dev/null 2>&1; then
        # macOS without Homebrew on PATH (ssh, launchd) has neither binary but has perl.
        # Same contract as `timeout -k`: its own process group gets TERM at the deadline and
        # KILL after the grace, so descendants cannot outlive it or hold the output pipe open.
        perl -e '
            my ($secs, $grace) = (shift, shift);
            my $pid = fork() // exit 127;
            if (!$pid) { setpgrp(0, 0); exec @ARGV or exit 127 }
            $SIG{ALRM} = sub {
                kill "TERM", -$pid;
                # Wait for the whole group, not just the direct child: a descendant that
                # ignores TERM would otherwise keep running (and hold the output pipe).
                for (1 .. $grace * 10) {
                    waitpid($pid, 1);
                    exit 124 unless kill 0, -$pid;
                    select(undef, undef, undef, 0.1);
                }
                kill "KILL", -$pid; waitpid($pid, 0); exit 124;
            };
            alarm $secs;
            waitpid($pid, 0);
            exit($? & 127 ? 128 + ($? & 127) : $? >> 8);
        ' "$secs" "$grace" "$@"
        return $?
    else
        echo "[_lib] no timeout binary found (install coreutils: 'brew install coreutils')" >&2
        return 127
    fi
    rc=0
    "$bin" -k "$grace" "$secs" "$@" || rc=$?
    # The kill-after path exits 137; callers read 124 as "timed out", so keep that contract.
    [ "$rc" -eq 137 ] && rc=124
    return "$rc"
}

portable_mtime() {
    stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || echo 0
}

portable_fmtdate() {
    local epoch="$1"
    local fmt="${2:-%Y-%m-%d %H:%M}"
    date -d "@$epoch" +"$fmt" 2>/dev/null || date -r "$epoch" +"$fmt" 2>/dev/null || echo ""
}

# Per-repository handoff file, so a session is handed only its own repository's state.
# latest.md holds hand-written handoffs and sessions outside any repository.
handoff_repo_path() {
    local repo
    repo=$(git -C "$1" rev-parse --show-toplevel 2>/dev/null) || return 1
    printf '%s/.claude/handoffs/repo-%s.md\n' "$HOME" "$(repo_hash "$repo")"
}

# handoff_publish <written-temp-file> <cwd>
# Installs the writer's own content as its repo handoff and as latest.md, each by atomic
# rename; never copy from the shared latest.md, which another repo's session may have written.
# Best-effort; always returns 0.
handoff_publish() {
    local tmp="$1" repo_file
    if repo_file=$(handoff_repo_path "$2"); then
        cp "$tmp" "$repo_file.$$" 2>/dev/null && mv -f "$repo_file.$$" "$repo_file" 2>/dev/null
    fi
    mv -f "$tmp" "$HOME/.claude/handoffs/latest.md" 2>/dev/null || rm -f "$tmp" 2>/dev/null
    return 0
}

. "$(dirname "${BASH_SOURCE[0]}")/_review-state.sh"

# Path to notify-codex.sh. Anchored to the deployed ~/.claude/hooks location
# (same convention as ~/.codex/config.toml's absolute notify path); BASH_SOURCE
# is unreliable when this lib is sourced, so don't derive from it.
_NOTIFY_CODEX_SH="$HOME/.claude/hooks/notify-codex.sh"

# notify_codex_done <summary> [cwd]
# Notifies the user of a codex run that produced no turn: pre-flight exits, timeouts, spawn
# failures. Not for the success path: a completed `codex exec` turn already runs the
# config.toml `notify` program, so this would double-ping. Goes through notify-codex.sh, so
# the notify-codex-disabled marker applies. Best-effort and backgrounded; never fails the caller.
notify_codex_done() {
    local summary="$1"
    local cwd="${2:-$PWD}"
    [[ -f "$_NOTIFY_CODEX_SH" ]] || return 0
    command -v jq >/dev/null 2>&1 || return 0
    local payload
    payload=$(jq -n --arg cwd "$cwd" --arg tid "codex-wrapper" --arg msg "$summary" \
        '{type:"agent-turn-complete", cwd:$cwd, "turn-id":$tid, "last-assistant-message":$msg}' 2>/dev/null) || return 0
    bash "$_NOTIFY_CODEX_SH" "$payload" >/dev/null 2>&1 &
    return 0
}

# hook_permission deny <reason>
# The one PreToolUse decision shape Claude Code honours; a top-level {permissionDecision} is
# ignored and the tool runs. Every PreToolUse hook decides through this (test_hook_contract.py).
# Never pass `ask`: it stalls autonomous loops waiting for a human. Deny with the alternative
# in the reason, or allow and record decision=flagged.
hook_permission() {
    jq -cn --arg d "$1" --arg r "$2" \
        '{hookSpecificOutput:{hookEventName:"PreToolUse", permissionDecision:$d, permissionDecisionReason:$r}}'
}

# Appended to every Stop-hook block reason: the reason is the turn's last input, so without
# it the model replies to the English hook in English instead of in the user's language.
STOP_REPLY_NOTE="When you reply after doing this, write to the user in the language of their last message, not to this hook."

# The harness's one timestamp format and event stream; do not hand-roll another log().
# Both are best-effort and always return 0: hooks run under `set -e`, so a logging failure
# must not take down the hook it observes.
#   hook_log   <component> <message...>      human line -> hooks-debug.log
#   hook_event <component> <event> [k=v ...] JSONL record -> hook-events.jsonl
HOOK_LOG_FILE="${HOOK_LOG_FILE:-$HOME/.claude/hooks-debug.log}"
HOOK_EVENT_LOG="${HOOK_EVENT_LOG:-$HOME/.claude/state/hook-events.jsonl}"

hook_log() {
    local component="${1:-unknown}"; shift || true
    printf '[%s] %s: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$component" "$*" \
        >> "$HOOK_LOG_FILE" 2>/dev/null || true
    return 0
}

# Structured sibling of hook_log. Extra fields are passed as key=value; keys
# must be [A-Za-z0-9_] (anything else is dropped rather than risking a jq syntax
# error that would lose the whole record). Values are passed via --arg, so they
# are never interpreted as jq.
hook_event() {
    command -v jq >/dev/null 2>&1 || return 0
    local component="${1:-unknown}" event="${2:-unknown}"
    shift 2 2>/dev/null || true

    local jq_args=(-c -n
        --arg ts "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
        --arg component "$component"
        --arg event "$event")
    local filter='{ts:$ts, component:$component, event:$event}'

    local kv key val
    for kv in "$@"; do
        [ "$kv" = "${kv#*=}" ] && continue
        key="${kv%%=*}"
        val="${kv#*=}"
        case "$key" in ''|*[!a-zA-Z0-9_]*) continue ;; esac
        jq_args+=(--arg "f_$key" "$val")
        filter="$filter + {\"$key\": \$f_$key}"
    done

    mkdir -p "$(dirname "$HOOK_EVENT_LOG")" 2>/dev/null || true
    jq "${jq_args[@]}" "$filter" >> "$HOOK_EVENT_LOG" 2>/dev/null || true
    return 0
}
