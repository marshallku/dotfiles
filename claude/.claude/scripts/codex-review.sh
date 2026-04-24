#!/usr/bin/env bash
# codex-review.sh — Wraps `codex exec` to run a cross-check review with a
# strict VERDICT output contract. Runs in a read-only sandbox so codex
# cannot modify any files.
#
# Usage:
#   codex-review.sh                              # HEAD vs main (or origin/main)
#   codex-review.sh --base develop               # HEAD vs given base
#   codex-review.sh --uncommitted                # working tree changes
#   codex-review.sh --focus security             # focused review
#   codex-review.sh --context "user asked to..." # inline intent brief
#   codex-review.sh --context-file /tmp/brief.md # intent brief from file
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
            sed -n '2,26p' "$0"
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

# Auto-detect default branch if not specified via --base
if [[ -z "$BASE" ]]; then
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
fi

# Resolve the diff
if [[ "$MODE" == "uncommitted" ]]; then
    DIFF=$(git diff HEAD)
    DIFF_DESC="uncommitted working tree changes"
else
    if ! git rev-parse --verify "$BASE" >/dev/null 2>&1; then
        if git rev-parse --verify "origin/$BASE" >/dev/null 2>&1; then
            BASE="origin/$BASE"
        else
            echo "[codex-review] base branch '$BASE' not found (tried origin/$BASE)" >&2
            exit 2
        fi
    fi
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
PROMPT=$(cat <<EOF
You are a senior engineer performing an independent code review.

Scope: ${DIFF_DESC}
${FOCUS_LINE}
${CONTEXT_SECTION}

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

# Run codex in read-only sandbox with a timeout so a stuck session does not hang the skill
set +e
OUTPUT=$(portable_timeout "$TIMEOUT" codex exec --skip-git-repo-check -s read-only ${MODEL_ARGS[@]+"${MODEL_ARGS[@]}"} "$PROMPT" 2>&1)
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
