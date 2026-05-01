#!/usr/bin/env bash
# codex-delegate.sh — Hand a sub-task to Codex with write access.
# Defaults to background execution (returns a job id immediately) and
# workspace-write sandbox (codex can edit files in the cwd repo).
#
# Usage:
#   codex-delegate.sh "Investigate failing test in src/foo.test.ts and apply the smallest safe fix."
#   codex-delegate.sh --foreground "Add a missing null check in src/auth.ts:42"
#   codex-delegate.sh --readonly "Diagnose the regression but do not edit anything."
#   codex-delegate.sh --status                 # list jobs in this workspace
#   codex-delegate.sh --status <job-id>        # show one job
#   codex-delegate.sh --result <job-id>        # show final output
#   codex-delegate.sh --cancel <job-id>        # cancel a running job
#   codex-delegate.sh --tail <job-id>          # follow the job log live
#
# By default the prompt is wrapped with operating instructions for codex
# (apply minimum-viable change, leave a summary, no scope creep). Pass
# --raw to send the prompt unwrapped.
#
# Environment overrides:
#   CODEX_DELEGATE_MODEL  — model passed to companion (--model)
#   CODEX_DELEGATE_EFFORT — reasoning effort (none|minimal|low|medium|high|xhigh)

set -euo pipefail

. "$(dirname "$0")/../hooks/_lib.sh"

COMPANION="$(dirname "$0")/codex-companion.sh"
if [[ ! -x "$COMPANION" ]]; then
    echo "[codex-delegate] companion wrapper missing: $COMPANION" >&2
    exit 2
fi

MODE="run"
RUN_BACKGROUND=1
WRITE=1
RAW=0
JOB_ID=""

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
        --status)
            MODE="status"
            shift
            if [[ $# -gt 0 && "$1" != --* ]]; then
                JOB_ID="$1"
                shift
            fi
            ;;
        --result)
            MODE="result"
            shift
            if [[ $# -gt 0 && "$1" != --* ]]; then
                JOB_ID="$1"
                shift
            fi
            ;;
        --cancel)
            MODE="cancel"
            shift
            if [[ $# -gt 0 && "$1" != --* ]]; then
                JOB_ID="$1"
                shift
            fi
            ;;
        --tail)
            MODE="tail"
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

# Lifecycle commands first (don't need a prompt).
case "$MODE" in
    status)
        if [[ -n "$JOB_ID" ]]; then
            exec "$COMPANION" status "$JOB_ID"
        else
            exec "$COMPANION" status
        fi
        ;;
    result)
        if [[ -z "$JOB_ID" ]]; then
            echo "[codex-delegate] --result needs a job id" >&2
            exit 2
        fi
        exec "$COMPANION" result "$JOB_ID"
        ;;
    cancel)
        if [[ -z "$JOB_ID" ]]; then
            echo "[codex-delegate] --cancel needs a job id" >&2
            exit 2
        fi
        exec "$COMPANION" cancel "$JOB_ID"
        ;;
    tail)
        if [[ -z "$JOB_ID" ]]; then
            echo "[codex-delegate] --tail needs a job id" >&2
            exit 2
        fi
        # Ask the companion for the log path instead of recomputing the
        # workspace hash. Companion's hash uses fs.realpathSync.native on
        # the path (no trailing newline); reproducing that in shell across
        # macOS/Linux is fiddly and we already had a hash mismatch bug.
        LOG_FILE=$("$COMPANION" status "$JOB_ID" 2>/dev/null \
            | awk -F': ' '/^  Log: /{print $2; exit}')
        if [[ -z "$LOG_FILE" || ! -f "$LOG_FILE" ]]; then
            echo "[codex-delegate] could not resolve log file for $JOB_ID" >&2
            "$COMPANION" status "$JOB_ID" >&2 || true
            exit 2
        fi
        exec tail -f "$LOG_FILE"
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
    SCOPE_HINT="You may edit files in the cwd repo to complete this task."
    if [[ "$WRITE" -eq 0 ]]; then
        SCOPE_HINT="Read-only sandbox: investigate and propose a diff but do not modify any files."
    fi
    PROMPT=$(cat <<EOF
You are completing a delegated sub-task on behalf of another agent.
Apply the principles in AGENTS.md.

${SCOPE_HINT}

Operating rules:
- Make the smallest viable change. No refactors, renames, or cleanups
  beyond what the task requires.
- If the task is ambiguous, pick the most likely interpretation and
  state your assumption in the final summary instead of stalling.
- After finishing, end your reply with a "## Summary" section listing:
  the files you touched, what you changed, what you intentionally
  did not change, and any follow-ups for the calling agent.
- Run the project's tests / typecheck if they exist and the change
  could plausibly affect them. Report the result.
- Never push, commit, or modify git remotes. Leave changes uncommitted.

--- TASK ---
${INPUT_TEXT}
--- END TASK ---
EOF
)
fi

WRITE_FLAG=()
[[ "$WRITE" -eq 1 ]] && WRITE_FLAG=(--write)

BG_FLAG=()
[[ "$RUN_BACKGROUND" -eq 1 ]] && BG_FLAG=(--background)

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
if [[ "$WRITE" -eq 1 ]]; then
    REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || true)
    if [[ -n "$REPO_ROOT" ]]; then
        REPO_HASH=$(repo_hash "$REPO_ROOT")
        STATE_DIR="$HOME/.claude/state"
        mkdir -p "$STATE_DIR"
        rm -f "$STATE_DIR/reviewed-$REPO_HASH"
        touch "$STATE_DIR/codex-delegate-pending-$REPO_HASH"
    fi
fi

MODEL_ARGS=()
if [[ -n "${CODEX_DELEGATE_MODEL:-}" ]]; then
    MODEL_ARGS=(--model "$CODEX_DELEGATE_MODEL")
fi

EFFORT_ARGS=()
if [[ -n "${CODEX_DELEGATE_EFFORT:-}" ]]; then
    EFFORT_ARGS=(--effort "$CODEX_DELEGATE_EFFORT")
fi

exec "$COMPANION" task \
    ${BG_FLAG[@]+"${BG_FLAG[@]}"} \
    ${WRITE_FLAG[@]+"${WRITE_FLAG[@]}"} \
    ${MODEL_ARGS[@]+"${MODEL_ARGS[@]}"} \
    ${EFFORT_ARGS[@]+"${EFFORT_ARGS[@]}"} \
    --fresh \
    "$PROMPT" </dev/null
