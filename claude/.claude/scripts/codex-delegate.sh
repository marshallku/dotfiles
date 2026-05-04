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
# --tail by default pretty-prints the log (codex's spoken text prefixed
# with 💬, reasoning summaries with 🧠, commands with ▶, results with ✓,
# turn lifecycle with 🟢/🔵, errors with ❌). Set CODEX_DELEGATE_TAIL_RAW=1
# to see the raw companion log instead.
#
# Environment overrides:
#   CODEX_DELEGATE_MODEL    — model passed to companion (--model)
#   CODEX_DELEGATE_EFFORT   — reasoning effort (none|minimal|low|medium|high|xhigh)
#   CODEX_DELEGATE_TAIL_RAW — 1 → bypass --tail's awk pretty-printer

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
        # Default: pretty-printed view that strips ISO timestamps and shows
        # codex's messages, reasoning, commands, and turn lifecycle as
        # readable lines. Set CODEX_DELEGATE_TAIL_RAW=1 to see the raw
        # companion log (useful for debugging the wrapper itself).
        if [[ "${CODEX_DELEGATE_TAIL_RAW:-0}" == "1" ]]; then
            exec tail -f "$LOG_FILE"
        fi
        # `tail -F` (capital) follows by name and survives log rotation.
        # Try to force line buffering so awk receives lines as they arrive,
        # but fall back gracefully when neither stdbuf (Linux/coreutils) nor
        # gstdbuf (macOS via brew install coreutils) is available — plain
        # tail works too, just with some kernel-pipe buffering. The `|| true`
        # is required because awk exits on the [final] marker, which leaves
        # tail writing into a closed pipe → SIGPIPE → exit 141 under
        # `set -euo pipefail`.
        # `-n +1` reads the entire log from the start, then follows.
        # Without this, tail's default 10-line window misses the
        # "[<ts>] Final output" header for completed jobs whose rendered
        # body is more than 9 lines long, and the awk auto-exit never
        # fires → --tail hangs forever when attached after completion.
        TAIL_CMD=(tail -n +1 -F "$LOG_FILE")
        if command -v stdbuf >/dev/null 2>&1; then
            TAIL_CMD=(stdbuf -oL tail -n +1 -F "$LOG_FILE")
        elif command -v gstdbuf >/dev/null 2>&1; then
            TAIL_CMD=(gstdbuf -oL tail -n +1 -F "$LOG_FILE")
        fi
        # Companion writes both timestamped progress lines (e.g.
        # "[2026-05-01T08:10:11.521Z] Assistant message captured: …") AND
        # raw body text (the assistant's actual reply). The body can
        # contain phrases like "Final output" or "Turn completed" that
        # would falsely trigger a substring match. Anchor every pattern
        # to a literal "[ISO_TIMESTAMP] " prefix so model body text never
        # acts as control input. (Hardcoded inside the awk script — passing
        # the regex via -v ts= would have awk's variable parser strip one
        # level of escape and break the [/] char-class characters.)
        # Event types in the companion log we care about:
        #   - Assistant message captured: ...  → codex's spoken text (💬)
        #   - Reasoning summary captured: ...  → reasoning trace (🧠)
        #   - Running command: / Command completed: ... → tool calls (▶/✓)
        #   - Turn started / Turn <status>.  → turn lifecycle (🟢/🔵/🟠)
        #     where <status> is "completed", "failed", "cancelled", or other
        #   - Codex error: ...                 → hard runtime error (❌)
        #   - Final output                     → always written when the
        #     runner finishes, success OR failure. Outcome must be inferred
        #     from the most recent "Turn X." line, NOT from "Final output"
        #     itself, otherwise failed/cancelled jobs report as success.
        "${TAIL_CMD[@]}" 2>/dev/null | awk '
            /^\[20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9:.Z+-]+\] Final output$/ {
                if (last_turn == "completed" || last_turn == "") {
                    print "[final marker — codex done]"
                } else {
                    print "[final marker — codex " last_turn "]"
                }
                exit
            }
            /^\[20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9:.Z+-]+\] Codex error: / {
                sub(/^\[[^]]*\] Codex error: /, "❌ ");
                print; fflush();
                print "[final marker — codex errored]"; exit
            }
            /^\[20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9:.Z+-]+\] Assistant message captured: / {
                sub(/^\[[^]]*\] Assistant message captured: /, "💬 ");
                print; fflush(); next
            }
            /^\[20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9:.Z+-]+\] Reasoning summary captured: / {
                sub(/^\[[^]]*\] Reasoning summary captured: /, "🧠 ");
                print; fflush(); next
            }
            /^\[20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9:.Z+-]+\] Running command: / {
                sub(/^\[[^]]*\] Running command: /, "▶ ");
                sub(/\/usr\/bin\/zsh -lc /, "");
                print; fflush(); next
            }
            /^\[20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9:.Z+-]+\] Command completed: / {
                if (match($0, /\(exit [0-9]+\)/)) {
                    print "  ✓ " substr($0, RSTART, RLENGTH);
                    fflush();
                }
                next
            }
            /^\[20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9:.Z+-]+\] Turn started/ {
                print "🟢 turn started"; fflush(); next
            }
            # Match ONLY the strict status form `Turn <single-word>.`
            # emitted by codex.mjs. Anything broader (e.g. the
            # "Turn completion inferred ..." informational line) would
            # otherwise be misread as a status value and corrupt the
            # final marker.
            /^\[20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9:.Z+-]+\] Turn [a-z]+\.$/ {
                line = $0;
                sub(/^\[[^]]*\] Turn /, "", line);
                sub(/\.$/, "", line);
                last_turn = line;
                if (last_turn == "completed") {
                    print "🔵 turn completed";
                } else {
                    print "🟠 turn " last_turn;
                }
                fflush(); next
            }
        ' || true
        exit 0
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
