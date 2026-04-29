#!/usr/bin/env bash
# codex-review.sh — Wraps `codex exec` to run a cross-check review with a
# strict VERDICT output contract. Runs in a read-only sandbox so codex
# cannot modify any files.
#
# Usage:
#   codex-review.sh                              # HEAD vs main (or origin/main)
#   codex-review.sh --base develop               # HEAD vs given base
#   codex-review.sh --uncommitted                # working tree changes
#   codex-review.sh --session <id>               # session dirty-log files only
#   codex-review.sh --files f1.ts,f2.ts          # specific files (comma-sep)
#   codex-review.sh --focus security             # focused review
#   codex-review.sh --context "user asked to..." # inline intent brief
#   codex-review.sh --context-file /tmp/brief.md # intent brief from file
#
# --session and --files collect diffs per-file, trying (in order):
#   1. uncommitted changes (git diff HEAD -- <file>)
#   2. committed changes vs base (git diff <base>...HEAD -- <file>)
#   3. last commit that touched the file (git log -1 -p -- <file>)
# This ensures review works regardless of whether changes are committed.
#
# Intent context is strongly recommended. Without it, codex can only judge
# "is this good code" — not "does this implement what the user asked for".
# The skill / Stop hook flow will instruct Claude to write a short brief.
#
# Environment overrides:
#   CODEX_REVIEW_MODEL   — override model passed to `codex exec -m`
#   CODEX_REVIEW_TIMEOUT — seconds before the review is aborted (default 420)
#
# Exit codes:
#   0 = VERDICT: APPROVED
#   1 = VERDICT: REVISE
#   2 = codex error, usage error, or no VERDICT line parsed

set -euo pipefail

. "$(dirname "$0")/../hooks/_lib.sh"

BASE=""
MODE="branch"
FOCUS=""
CONTEXT=""
CONTEXT_FILE=""
SESSION_ID=""
FILE_LIST=""
TIMEOUT="${CODEX_REVIEW_TIMEOUT:-420}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --base)
            BASE="$2"
            shift 2
            ;;
        --uncommitted)
            MODE="uncommitted"
            shift
            ;;
        --session)
            MODE="session"
            SESSION_ID="$2"
            shift 2
            ;;
        --files)
            MODE="files"
            FILE_LIST="$2"
            shift 2
            ;;
        --focus)
            FOCUS="$2"
            shift 2
            ;;
        --context)
            CONTEXT="$2"
            shift 2
            ;;
        --context-file)
            CONTEXT_FILE="$2"
            shift 2
            ;;
        -h|--help)
            sed -n '2,34p' "$0"
            exit 0
            ;;
        *)
            echo "[codex-review] unknown argument: $1" >&2
            exit 2
            ;;
    esac
done

# Resolve context input
if [[ -n "$CONTEXT_FILE" ]]; then
    if [[ ! -f "$CONTEXT_FILE" ]]; then
        echo "[codex-review] context file not found: $CONTEXT_FILE" >&2
        exit 2
    fi
    CONTEXT=$(cat "$CONTEXT_FILE")
fi

if ! command -v codex >/dev/null 2>&1; then
    echo "[codex-review] codex CLI not found in PATH" >&2
    exit 2
fi

if ! git rev-parse --show-toplevel >/dev/null 2>&1; then
    echo "[codex-review] not inside a git repository" >&2
    exit 2
fi

# Auto-detect default branch when needed (branch mode, or session/files fallback)
detect_base() {
    if [[ -n "$BASE" ]]; then return 0; fi
    BASE=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||') \
        || BASE=""
    if [[ -z "$BASE" ]]; then
        for candidate in main master; do
            if git rev-parse --verify "$candidate" >/dev/null 2>&1 \
                || git rev-parse --verify "origin/$candidate" >/dev/null 2>&1; then
                BASE="$candidate"
                break
            fi
        done
    fi
    if [[ -z "$BASE" ]]; then
        echo "[codex-review] could not detect default branch (tried main, master)" >&2
        exit 2
    fi
    # Resolve to origin/ if local branch doesn't exist
    if ! git rev-parse --verify "$BASE" >/dev/null 2>&1; then
        if git rev-parse --verify "origin/$BASE" >/dev/null 2>&1; then
            BASE="origin/$BASE"
        fi
    fi
}

# Collect diff for a single file, trying multiple strategies.
# Prints the diff to stdout. Returns 1 if no diff found.
collect_file_diff() {
    local file="$1"
    local d=""

    # 1. Uncommitted changes (staged + unstaged)
    d=$(git diff HEAD -- "$file" 2>/dev/null || true)
    if [[ -n "$d" ]]; then echo "$d"; return 0; fi

    # 2. Committed changes vs base branch
    detect_base
    d=$(git diff "${BASE}...HEAD" -- "$file" 2>/dev/null || true)
    if [[ -n "$d" ]]; then echo "$d"; return 0; fi

    # 3. Last commit that touched this file
    d=$(git log -1 -p --format="" -- "$file" 2>/dev/null || true)
    if [[ -n "$d" ]]; then echo "$d"; return 0; fi

    return 1
}

# Resolve file list for session/files modes
TARGET_FILES=()
FILES_SUMMARY=""

if [[ "$MODE" == "session" ]]; then
    DIRTY_LOG="$HOME/.claude/state/dirty-${SESSION_ID}.log"
    if [[ ! -f "$DIRTY_LOG" ]]; then
        echo "[codex-review] no dirty log for session $SESSION_ID" >&2
        exit 2
    fi
    REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "")
    while IFS= read -r f; do
        # Scope to current repo
        if [[ -n "$REPO_ROOT" ]] && [[ "$f" != "${REPO_ROOT}/"* ]]; then
            continue
        fi
        TARGET_FILES+=("$f")
    done < <(sort -u "$DIRTY_LOG")

elif [[ "$MODE" == "files" ]]; then
    IFS=',' read -ra TARGET_FILES <<< "$FILE_LIST"
fi

# Collect diffs based on mode
if [[ "$MODE" == "session" || "$MODE" == "files" ]]; then
    if [[ ${#TARGET_FILES[@]} -eq 0 ]]; then
        echo "## Summary" >&2
        echo "No files to review." >&2
        echo ""
        echo "VERDICT: APPROVED"
        exit 0
    fi

    DIFF=""
    SUMMARY_LINES=""
    DIFF_SOURCE_DESC=""
    for file in "${TARGET_FILES[@]}"; do
        file_diff=$(collect_file_diff "$file" || true)
        if [[ -n "$file_diff" ]]; then
            DIFF="${DIFF}${file_diff}"$'\n'
            rel_path="${file#"$(git rev-parse --show-toplevel 2>/dev/null)/"}"
            SUMMARY_LINES="${SUMMARY_LINES}- ${rel_path}"$'\n'
        fi
    done
    FILE_TOTAL=${#TARGET_FILES[@]}
    if [[ "$MODE" == "session" ]]; then
        DIFF_DESC="session ${SESSION_ID} (${FILE_TOTAL} files touched)"
    else
        DIFF_DESC="specified files (${FILE_TOTAL} files)"
    fi
    FILES_SUMMARY="## Files in scope (${FILE_TOTAL} files)
${SUMMARY_LINES}"

elif [[ "$MODE" == "uncommitted" ]]; then
    DIFF=$(git diff HEAD)
    DIFF_DESC="uncommitted working tree changes"

else
    detect_base
    DIFF=$(git diff "${BASE}...HEAD")
    DIFF_DESC="HEAD vs ${BASE}"
fi

if [[ -z "$DIFF" ]]; then
    echo "## Summary" >&2
    echo "No diff to review (${DIFF_DESC})." >&2
    echo ""
    echo "VERDICT: APPROVED"
    exit 0
fi

FOCUS_LINE=""
if [[ -n "$FOCUS" ]]; then
    FOCUS_LINE="Focus exclusively on: $FOCUS. Ignore everything outside this focus area."
fi

CONTEXT_SECTION=""
INTENT_CHECK=""
if [[ -n "$CONTEXT" ]]; then
    CONTEXT_SECTION=$(cat <<EOF

--- TASK CONTEXT (from the author) ---
${CONTEXT}
--- END TASK CONTEXT ---
EOF
)
    INTENT_CHECK="
Also judge intent-vs-implementation alignment: does the diff actually do what the Task Context says the author intended? If there is a material mismatch between stated intent and actual code (missing requirement, silent scope creep, subtly different semantics), raise it as CRITICAL with the label [INTENT-MISMATCH]."
else
    CONTEXT_SECTION=$'\n(No task context supplied — judging the diff in isolation. Note this in your summary.)'
fi

MODEL_ARGS=()
if [[ -n "${CODEX_REVIEW_MODEL:-}" ]]; then
    MODEL_ARGS=(-m "$CODEX_REVIEW_MODEL")
fi

# Build the prompt
FILES_SECTION=""
if [[ -n "$FILES_SUMMARY" ]]; then
    FILES_SECTION="${FILES_SUMMARY}
"
fi

PROMPT=$(cat <<EOF
You are a senior engineer performing an independent code review.

Scope: ${DIFF_DESC}
${FOCUS_LINE}
${FILES_SECTION}${CONTEXT_SECTION}

Follow the review principles in AGENTS.md strictly. Classify findings as CRITICAL, INFORMATIONAL, or SUPPRESS. Read files outside the diff when enum completeness, interface compatibility, or caller impact matters.
${INTENT_CHECK}

End your response with exactly one line: either "VERDICT: APPROVED" or "VERDICT: REVISE".
APPROVED = zero CRITICAL findings.
REVISE   = at least one CRITICAL finding.

--- DIFF ---
${DIFF}
--- END DIFF ---
EOF
)

# Run codex in read-only sandbox with a timeout so a stuck session does not hang the skill.
# stdin must be redirected from /dev/null — codex exec reads stdin until EOF when stdin is
# a non-tty pipe (e.g. when invoked from a Claude background task), which makes the process
# hang long after the turn's task_complete event has fired, producing false timeouts.
set +e
OUTPUT=$(portable_timeout "$TIMEOUT" codex exec --skip-git-repo-check -s read-only ${MODEL_ARGS[@]+"${MODEL_ARGS[@]}"} "$PROMPT" </dev/null 2>&1)
STATUS=$?
set -e

if [[ $STATUS -eq 124 ]]; then
    echo "[codex-review] timed out after ${TIMEOUT}s" >&2
    exit 2
fi

if [[ $STATUS -eq 127 ]]; then
    echo "[codex-review] timeout binary missing — install GNU coreutils ('brew install coreutils' on macOS)" >&2
    exit 2
fi

if [[ $STATUS -ne 0 ]]; then
    echo "[codex-review] codex exec failed with status $STATUS" >&2
    echo "$OUTPUT" >&2
    exit 2
fi

echo "$OUTPUT"

# Parse the final verdict — check the last 20 lines so conversational preamble does not confuse us
VERDICT_LINE=$(echo "$OUTPUT" | tail -n 20 | grep -E "^VERDICT: (APPROVED|REVISE)" | tail -n 1 || true)

# On APPROVED: mark the current repo as reviewed so pre-commit-gate.sh lets
# subsequent save.sh / git commit / git push through.
mark_repo_reviewed() {
    local repo_root
    repo_root=$(git rev-parse --show-toplevel 2>/dev/null || echo "")
    [ -z "$repo_root" ] && return 0
    local repo_hash_v
    repo_hash_v=$(repo_hash "$repo_root")
    local state_dir="$HOME/.claude/state"
    mkdir -p "$state_dir"
    touch "$state_dir/reviewed-$repo_hash_v"
}

case "$VERDICT_LINE" in
    "VERDICT: APPROVED")
        mark_repo_reviewed
        exit 0
        ;;
    "VERDICT: REVISE")
        exit 1
        ;;
    *)
        echo "[codex-review] no VERDICT line found in output" >&2
        exit 2
        ;;
esac
