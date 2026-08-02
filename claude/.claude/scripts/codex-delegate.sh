#!/usr/bin/env bash
# codex-delegate.sh — Hand a sub-task to Codex with write access.
# Defaults to background execution (returns a job id immediately) and
# workspace-write sandbox (codex can edit files in the cwd repo).
#
# Usage:
#   codex-delegate.sh "Investigate failing test in src/foo.test.ts and apply the smallest safe fix."
#   codex-delegate.sh --foreground "Add a missing null check in src/auth.ts:42"
#   codex-delegate.sh --readonly "Diagnose the regression but do not edit anything."
#   codex-delegate.sh --status                 # list jobs in this repo
#   codex-delegate.sh --status <job-id>        # show one job
#   codex-delegate.sh --result <job-id>        # show final output
#   codex-delegate.sh --cancel <job-id>        # cancel a running job
#   codex-delegate.sh --tail <job-id>          # follow the job log live
#
# By default the prompt is wrapped with operating instructions for codex
# (apply minimum-viable change, leave a summary, no scope creep). Pass
# --raw to send the prompt unwrapped.
#
# Jobs are plain files under ~/.claude/state/codex-jobs/<repo-hash>/:
#   <id>.meta    key=value job record (pid, process group, start marker, …)
#   <id>.log     rendered progress stream (what --tail follows)
#   <id>.out     final assistant message (what --result prints)
#   <id>.prompt  the exact prompt sent
# A background job is its own process group (setsid), so --cancel signals the
# whole group — codex plus any tool command it spawned. Liveness is checked
# against the recorded process start time as well as the pid, so a recycled
# pid can never make a finished job look alive or get signalled by --cancel.
#
# Environment overrides:
#   CODEX_DELEGATE_MODEL    — model passed to codex (-m)
#   CODEX_DELEGATE_EFFORT   — reasoning effort (none|minimal|low|medium|high|xhigh)
#   CODEX_DELEGATE_TIMEOUT  — seconds before the job is aborted (default 3600)

set -euo pipefail

. "$(dirname "$0")/../hooks/_lib.sh"

RUNNER="$(dirname "$0")/codex-exec.sh"
if [[ ! -x "$RUNNER" ]]; then
    echo "[codex-delegate] runner missing: $RUNNER" >&2
    exit 2
fi

MODE="run"
RUN_BACKGROUND=1
WRITE=1
RAW=0
JOB_ID=""
TIMEOUT="${CODEX_DELEGATE_TIMEOUT:-3600}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --foreground|--wait)
            RUN_BACKGROUND=0
            shift
            ;;
        --background)
            RUN_BACKGROUND=1
            shift
            ;;
        --readonly|--read-only)
            WRITE=0
            shift
            ;;
        --raw)
            RAW=1
            shift
            ;;
        --status|--result|--cancel|--tail)
            MODE="${1#--}"
            shift
            if [[ $# -gt 0 && "$1" != --* ]]; then
                JOB_ID="$1"
                shift
            fi
            ;;
        -h|--help)
            sed -n '2,20p' "$0"
            exit 0
            ;;
        --)
            shift
            break
            ;;
        *)
            break
            ;;
    esac
done

# Jobs are scoped to the repo they were launched in, so --status in one repo
# never lists another repo's work.
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || true)
if [[ -n "$REPO_ROOT" ]]; then
    JOB_SCOPE=$(repo_hash "$REPO_ROOT")
else
    JOB_SCOPE="no-repo"
fi
JOB_DIR="$HOME/.claude/state/codex-jobs/$JOB_SCOPE"

meta_get() {
    # meta_get <meta-file> <key> — last value wins (the job wrapper appends
    # exit_status/finished_at after the header was written).
    awk -F= -v k="$2" '$1 == k { sub(/^[^=]*=/, ""); v = $0 } END { print v }' "$1" 2>/dev/null
}

# A job is alive only if the recorded pid still exists AND was started at the
# recorded time. Without the second check a recycled pid would report a
# finished job as running — and let --cancel signal an unrelated process.
job_alive() {
    local meta="$1"
    local pid marker now_marker
    pid=$(meta_get "$meta" pid)
    marker=$(meta_get "$meta" start_marker)
    [[ -z "$pid" ]] && return 1
    kill -0 "$pid" 2>/dev/null || return 1
    now_marker=$(ps -o lstart= -p "$pid" 2>/dev/null | tr -s ' ' | sed 's/^ *//;s/ *$//')
    [[ -n "$marker" && "$now_marker" == "$marker" ]]
}

job_state() {
    local meta="$1"
    if job_alive "$meta"; then
        echo "running"
        return 0
    fi
    local st
    st=$(meta_get "$meta" exit_status)
    if [[ -z "$st" ]]; then
        # No recorded exit and no live process. Distinguish a deliberate
        # --cancel from a job that died on its own (reboot, SIGKILL).
        if [[ -n "$(meta_get "$meta" cancelled_at)" ]]; then
            echo "cancelled"
        else
            echo "interrupted"
        fi
    elif [[ "$st" == "0" ]]; then
        echo "completed"
    else
        echo "failed(exit $st)"
    fi
}

resolve_job() {
    local id="$1"
    if [[ -z "$id" ]]; then
        echo "[codex-delegate] this command needs a job id" >&2
        exit 2
    fi
    if [[ ! -f "$JOB_DIR/$id.meta" ]]; then
        echo "[codex-delegate] unknown job: $id (looked in $JOB_DIR)" >&2
        exit 2
    fi
}

case "$MODE" in
    status)
        if [[ -n "$JOB_ID" ]]; then
            resolve_job "$JOB_ID"
            META="$JOB_DIR/$JOB_ID.meta"
            echo "Job:     $JOB_ID"
            echo "State:   $(job_state "$META")"
            echo "Started: $(meta_get "$META" started_at)"
            echo "Write:   $(meta_get "$META" write)"
            echo "Task:    $(meta_get "$META" summary)"
            echo "Log:     $JOB_DIR/$JOB_ID.log"
            echo "Out:     $JOB_DIR/$JOB_ID.out"
            exit 0
        fi
        shopt -s nullglob
        METAS=("$JOB_DIR"/*.meta)
        shopt -u nullglob
        if [[ ${#METAS[@]} -eq 0 ]]; then
            echo "No codex-delegate jobs for this repo ($JOB_DIR)"
            exit 0
        fi
        for META in "${METAS[@]}"; do
            id=$(basename "$META" .meta)
            printf '%-28s %-16s %s\n' "$id" "$(job_state "$META")" "$(meta_get "$META" summary)"
        done
        exit 0
        ;;
    result)
        resolve_job "$JOB_ID"
        OUT="$JOB_DIR/$JOB_ID.out"
        STATE=$(job_state "$JOB_DIR/$JOB_ID.meta")
        if [[ "$STATE" == "running" ]]; then
            echo "[codex-delegate] job $JOB_ID is still running — use --tail to follow it" >&2
            exit 2
        fi
        if [[ ! -s "$OUT" ]]; then
            echo "[codex-delegate] job $JOB_ID produced no final message (state: $STATE); see $JOB_DIR/$JOB_ID.log" >&2
            exit 2
        fi
        cat "$OUT"
        exit 0
        ;;
    cancel)
        resolve_job "$JOB_ID"
        META="$JOB_DIR/$JOB_ID.meta"
        if ! job_alive "$META"; then
            echo "[codex-delegate] job $JOB_ID is not running (state: $(job_state "$META"))" >&2
            exit 0
        fi
        PGID=$(meta_get "$META" pgid)
        # Signal the whole process group so codex and its tool commands die
        # together. job_alive already verified this pid/group is really ours.
        kill -TERM "-$PGID" 2>/dev/null || kill -TERM "$(meta_get "$META" pid)" 2>/dev/null || true
        printf 'cancelled_at=%s\n' "$(date +%Y-%m-%dT%H:%M:%S%z)" >> "$META"
        echo "[codex-delegate] sent SIGTERM to job $JOB_ID"
        exit 0
        ;;
    tail)
        resolve_job "$JOB_ID"
        LOG="$JOB_DIR/$JOB_ID.log"
        # The log already holds rendered progress lines (codex-exec.sh does the
        # formatting), so this is a plain follow. `-F` survives rotation, and
        # `-n +1` replays from the start for a job attached to after the fact.
        exec tail -n +1 -F "$LOG"
        ;;
esac

# Run mode — needs a prompt.
INPUT_TEXT="$*"
if [[ -z "$INPUT_TEXT" ]]; then
    echo "Usage: $0 [--foreground|--readonly|--raw] <task description>" >&2
    echo "       $0 --status [job-id]" >&2
    echo "       $0 --result <job-id>" >&2
    echo "       $0 --cancel <job-id>" >&2
    echo "       $0 --tail <job-id>" >&2
    exit 2
fi

if [[ "$RAW" -eq 1 ]]; then
    PROMPT="$INPUT_TEXT"
else
    # Delegation-specific imperatives (write-capable agent must not expand
    # scope, must report back). AGENTS.md "What NOT to do" forbids
    # *suggesting* rewrites in reviews — it does NOT constrain a write-capable
    # delegate from doing incidental refactors, so we keep that rule inline.
    SCOPE_HINT="You may edit files in the cwd repo."
    [[ "$WRITE" -eq 0 ]] && SCOPE_HINT="Read-only: propose a diff, do not modify files."
    PROMPT=$(cat <<EOF
Delegated sub-task per AGENTS.md. ${SCOPE_HINT} Make the smallest viable change — no refactors, renames, or cleanups beyond what the task requires. If ambiguous, pick the most likely interpretation and state the assumption. Run tests/typecheck if relevant. Do not commit/push. End with a ## Summary section listing touched files, what changed, what was intentionally not changed, and follow-ups for the calling agent.

--- TASK ---
${INPUT_TEXT}
--- END TASK ---
EOF
)
fi

# Two safety actions when delegating with write access. Codex edits files
# outside Claude's Edit/Write tools, so track-edit.sh never fires — without
# these, pre-commit-gate.sh would let a stale `reviewed-<repo-hash>` marker
# through after codex made changes, AND its file-count early-exit would
# allow commits when Claude itself touched 0 files this session.
# 1. Invalidate `reviewed-<repo-hash>` marker — forces re-review even if
#    Claude's own edits already passed cross-review earlier.
# 2. Touch `codex-delegate-pending-<repo-hash>` marker — pre-commit-gate
#    treats this as proof the change is non-trivial, bypassing the
#    file-count early-exit and forcing the marker check (which then fails
#    until the next cross-review APPROVED clears the pending flag).
# Pessimistic by design: both happen even if codex ends up making no edits;
# user runs /cross-review to restore the marker and clear the pending flag.
if [[ "$WRITE" -eq 1 && -n "$REPO_ROOT" ]]; then
    STATE_DIR="$HOME/.claude/state"
    mkdir -p "$STATE_DIR"
    rm -f "$STATE_DIR/reviewed-$JOB_SCOPE"
    touch "$STATE_DIR/codex-delegate-pending-$JOB_SCOPE"
fi

RUN_ARGS=(--timeout "$TIMEOUT")
[[ "$WRITE" -eq 1 ]] && RUN_ARGS+=(--write)
[[ -n "${CODEX_DELEGATE_MODEL:-}" ]] && RUN_ARGS+=(--model "$CODEX_DELEGATE_MODEL")
[[ -n "${CODEX_DELEGATE_EFFORT:-}" ]] && RUN_ARGS+=(--effort "$CODEX_DELEGATE_EFFORT")

mkdir -p "$JOB_DIR"
JOB_ID="job-$(date +%Y%m%dT%H%M%S)-$$"
META="$JOB_DIR/$JOB_ID.meta"
LOG="$JOB_DIR/$JOB_ID.log"
OUT="$JOB_DIR/$JOB_ID.out"
PROMPT_PATH="$JOB_DIR/$JOB_ID.prompt"

printf '%s' "$PROMPT" > "$PROMPT_PATH"
{
    printf 'id=%s\n' "$JOB_ID"
    printf 'started_at=%s\n' "$(date +%Y-%m-%dT%H:%M:%S%z)"
    printf 'cwd=%s\n' "${REPO_ROOT:-$PWD}"
    printf 'write=%s\n' "$WRITE"
    # Single-line task preview for --status listings.
    printf 'summary=%s\n' "$(printf '%s' "$INPUT_TEXT" | tr '\n' ' ' | cut -c1-100)"
} > "$META"

RUN_ARGS+=(--prompt-file "$PROMPT_PATH")

if [[ "$RUN_BACKGROUND" -eq 0 ]]; then
    # Foreground: progress streams to the terminal on stderr; the final
    # message lands in the job file and is echoed once codex is done.
    set +e
    "$RUNNER" ${RUN_ARGS[@]+"${RUN_ARGS[@]}"} </dev/null > "$OUT"
    STATUS=$?
    set -e
    printf 'exit_status=%s\nfinished_at=%s\n' "$STATUS" "$(date +%Y-%m-%dT%H:%M:%S%z)" >> "$META"
    cat "$OUT"
    echo "[codex-delegate] job $JOB_ID (foreground, exit $STATUS)" >&2
    exit $STATUS
fi

# Background: setsid gives the job its own process group (pid == pgid), which
# is what makes --cancel able to take down codex and its tool commands. The
# wrapper records the exit status so --status can tell completed from failed.
#
# The wrapper's OWN stdio must be detached (>/dev/null 2>&1 </dev/null) on top
# of the inner per-command redirects. Without that it inherits the caller's
# stdout, so a caller doing `JOB=$(codex-delegate.sh …)` blocks in command
# substitution until the whole job finishes — the exact opposite of "returns a
# job id immediately".
CODEX_JOB_OUT="$OUT" CODEX_JOB_LOG="$LOG" CODEX_JOB_META="$META" \
setsid bash -c '
    "$@" > "$CODEX_JOB_OUT" 2> "$CODEX_JOB_LOG"
    printf "exit_status=%s\nfinished_at=%s\n" "$?" "$(date +%Y-%m-%dT%H:%M:%S%z)" >> "$CODEX_JOB_META"
' codex-delegate-job "$RUNNER" ${RUN_ARGS[@]+"${RUN_ARGS[@]}"} </dev/null >/dev/null 2>&1 &
JOB_PID=$!

# Record identity for liveness checks. `ps -o lstart=` pins the process start
# time so a recycled pid cannot impersonate this job.
{
    printf 'pid=%s\n' "$JOB_PID"
    printf 'pgid=%s\n' "$(ps -o pgid= -p "$JOB_PID" 2>/dev/null | tr -d ' ' || echo "$JOB_PID")"
    printf 'start_marker=%s\n' "$(ps -o lstart= -p "$JOB_PID" 2>/dev/null | tr -s ' ' | sed 's/^ *//;s/ *$//')"
} >> "$META"

echo "$JOB_ID"
echo "[codex-delegate] started in background — follow with: $0 --tail $JOB_ID" >&2
