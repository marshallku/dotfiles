#!/usr/bin/env bash
# codex-review.sh — Wraps `codex exec` to run a cross-check review with a
# strict VERDICT output contract. Runs in a read-only sandbox so codex
# cannot modify any files.
#
# Usage:
#   codex-review.sh                         # HEAD vs main (or origin/main)
#   codex-review.sh --base develop          # HEAD vs given base
#   codex-review.sh --uncommitted           # working tree changes
#   codex-review.sh --focus security        # focused review
#   codex-review.sh --focus performance --base develop
#
# Environment overrides:
#   CODEX_REVIEW_MODEL   — override model passed to `codex exec -m`
#   CODEX_REVIEW_TIMEOUT — seconds before the review is aborted (default 300)
#
# Exit codes:
#   0 = VERDICT: APPROVED
#   1 = VERDICT: REVISE
#   2 = codex error, usage error, or no VERDICT line parsed

set -euo pipefail

BASE="main"
MODE="branch"
FOCUS=""
TIMEOUT="${CODEX_REVIEW_TIMEOUT:-300}"

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
        -h|--help)
            sed -n '2,22p' "$0"
            exit 0
            ;;
        *)
            echo "[codex-review] unknown argument: $1" >&2
            exit 2
            ;;
    esac
done

if ! command -v codex >/dev/null 2>&1; then
    echo "[codex-review] codex CLI not found in PATH" >&2
    exit 2
fi

if ! git rev-parse --show-toplevel >/dev/null 2>&1; then
    echo "[codex-review] not inside a git repository" >&2
    exit 2
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

MODEL_ARGS=()
if [[ -n "${CODEX_REVIEW_MODEL:-}" ]]; then
    MODEL_ARGS=(-m "$CODEX_REVIEW_MODEL")
fi

# Build the prompt
PROMPT=$(cat <<EOF
You are a senior engineer performing an independent code review.

Scope: ${DIFF_DESC}
${FOCUS_LINE}

Follow the review principles in AGENTS.md strictly. Classify findings as CRITICAL, INFORMATIONAL, or SUPPRESS. Read files outside the diff when enum completeness, interface compatibility, or caller impact matters.

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
OUTPUT=$(timeout "$TIMEOUT" codex exec --skip-git-repo-check -s read-only "${MODEL_ARGS[@]}" "$PROMPT" 2>&1)
STATUS=$?
set -e

if [[ $STATUS -eq 124 ]]; then
    echo "[codex-review] timed out after ${TIMEOUT}s" >&2
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

case "$VERDICT_LINE" in
    "VERDICT: APPROVED")
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
