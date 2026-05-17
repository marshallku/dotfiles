#!/usr/bin/env bash
# intent-finalize.sh <intent-file>
#
# Validates the intent file schema, computes content_hash + dedupe_key,
# creates the ack marker, and registers the session→intent mapping so
# intent-capture.sh allows subsequent edits.
#
# Schema requirements (v1):
#   - acceptance_criteria  ≥1 entry (theater wedge)
#   - out_of_scope         ≥1 entry (negative space)
#   - assumptions          ≥1 entry (do-more-than-asked counter)
#   - goal / summary / commit_summary  non-empty
#   - verification.e2e ∈ {required, not_applicable, deferred}
#   - verification.reason set when e2e = deferred
#
# Exit codes:
#   0 — finalized, ack marker set
#   2 — schema validation failed (gate stays closed, fix and re-run)

set -euo pipefail

. "$(dirname "$0")/../hooks/_lib.sh"

INTENT_FILE="${1:?Usage: intent-finalize.sh <intent-file>}"

if [ ! -f "$INTENT_FILE" ]; then
    echo "[intent-finalize] file not found: $INTENT_FILE" >&2
    exit 2
fi

# Extract frontmatter (between first two --- lines)
FRONTMATTER=$(awk '/^---$/{c++; if(c==2)exit; next} c==1' "$INTENT_FILE")

# Count list entries under a top-level key (lines starting with "  - ")
count_list_entries() {
    local key="$1"
    awk -v k="^${key}:$" '
        $0 ~ k { flag=1; next }
        flag && /^[a-z_]+:/ { flag=0 }
        flag && /^  - .+/ { count++ }
        END { print count+0 }
    ' <<< "$FRONTMATTER"
}

# Get scalar value for a top-level key (one-line value after "key: ")
get_scalar() {
    local key="$1"
    awk -v k="^${key}: " '$0 ~ k { sub(k, ""); print; exit }' <<< "$FRONTMATTER"
}

# Get scalar inside the `verification:` block (`  e2e: ...`, `  reason: ...`)
get_verification_field() {
    local field="$1"
    awk -v f="^  ${field}: " '
        /^verification:$/ { flag=1; next }
        flag && /^[a-z_]+:/ && !/^  / { flag=0 }
        flag && $0 ~ f { sub(f, ""); print; exit }
    ' <<< "$FRONTMATTER"
}

ERRORS=()

[ "$(count_list_entries acceptance_criteria)" -ge 1 ] || ERRORS+=("acceptance_criteria must have ≥1 entry")
[ "$(count_list_entries out_of_scope)"        -ge 1 ] || ERRORS+=("out_of_scope must have ≥1 entry")
[ "$(count_list_entries assumptions)"         -ge 1 ] || ERRORS+=("assumptions must have ≥1 entry")

GOAL=$(get_scalar goal)
SUMMARY=$(get_scalar summary)
COMMIT_SUMMARY=$(get_scalar commit_summary)

[ -n "$GOAL" ] && [ "$GOAL" != "<1-2 lines describing what and why>" ] \
    || ERRORS+=("goal must be filled in (non-empty, not the template placeholder)")
[ -n "$SUMMARY" ] && [[ "$SUMMARY" != "<"* ]] \
    || ERRORS+=("summary must be filled in (non-empty, not the template placeholder)")
[ -n "$COMMIT_SUMMARY" ] && [[ "$COMMIT_SUMMARY" != "<"* ]] \
    || ERRORS+=("commit_summary must be filled in (non-empty, not the template placeholder)")

E2E=$(get_verification_field e2e)
case "$E2E" in
    required|not_applicable|deferred)
        if [ "$E2E" = "deferred" ]; then
            REASON=$(get_verification_field reason)
            if [ -z "$REASON" ] || [ "$REASON" = "null" ]; then
                ERRORS+=("verification.reason must be set when verification.e2e is 'deferred'")
            fi
        fi
        ;;
    *)
        ERRORS+=("verification.e2e must be one of: required, not_applicable, deferred (got: '$E2E')")
        ;;
esac

if [ ${#ERRORS[@]} -gt 0 ]; then
    echo "[intent-finalize] schema validation failed:" >&2
    for e in "${ERRORS[@]}"; do
        echo "  - $e" >&2
    done
    echo "[intent-finalize] Fix the intent file and re-run." >&2
    exit 2
fi

# Compute content_hash over the immutable intent payload:
#   - frontmatter EXCLUDING content_hash / dedupe_key
#   - body BEFORE the `## Notes` section (Notes is append-only mutable)
PAYLOAD=$(awk '
    /^## Notes/ { exit }
    /^content_hash:/ { next }
    /^dedupe_key:/ { next }
    { print }
' "$INTENT_FILE")

CONTENT_HASH="sha256:$(printf '%s' "$PAYLOAD" | sha256sum | awk '{print $1}')"

CANONICAL_URL=$(get_scalar canonical_url)
DEDUPE_KEY="sha256:$(printf '%s%s' "$CANONICAL_URL" "$CONTENT_HASH" | sha256sum | awk '{print $1}')"

# Update content_hash / dedupe_key in place (only those two lines)
TMPFILE=$(mktemp)
trap 'rm -f "$TMPFILE"' EXIT
awk -v ch="$CONTENT_HASH" -v dk="$DEDUPE_KEY" '
    /^content_hash:/ { print "content_hash: " ch; next }
    /^dedupe_key:/   { print "dedupe_key: "   dk; next }
    { print }
' "$INTENT_FILE" > "$TMPFILE"
mv "$TMPFILE" "$INTENT_FILE"
trap - EXIT

# Ack marker
ACK_DIR="$HOME/.claude/state/intent-acks"
mkdir -p "$ACK_DIR"
BASENAME=$(basename "$INTENT_FILE" .md)
ACK_FILE="$ACK_DIR/${BASENAME}.ack"
touch "$ACK_FILE"

# Register session→intent mapping for intent-capture.sh fast path
SESSION_ID=$(get_scalar source_id)
REPO_HASH=""
if REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null); then
    REPO_HASH=$(repo_hash "$REPO_ROOT")
fi

STATE_DIR="$HOME/.claude/state"
mkdir -p "$STATE_DIR"
if [ -n "$REPO_HASH" ] && [ -n "$SESSION_ID" ]; then
    echo "$INTENT_FILE" > "$STATE_DIR/intent-active-${SESSION_ID}-${REPO_HASH}.path"
fi

echo "[intent-finalize] OK"
echo "  file:         $INTENT_FILE"
echo "  content_hash: $CONTENT_HASH"
echo "  dedupe_key:   $DEDUPE_KEY"
echo "  ack:          $ACK_FILE"
if [ -n "$REPO_HASH" ]; then
    echo "  active:       $STATE_DIR/intent-active-${SESSION_ID}-${REPO_HASH}.path"
fi
