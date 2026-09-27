#!/usr/bin/env bash
# codex-review.sh — Cross-check review with a strict VERDICT output contract.
# Routes through codex-exec.sh so progress streams to the user (instead of
# silent capture). Read-only sandbox.
#
# Usage:
#   codex-review.sh                              # HEAD vs main (or origin/main)
#   codex-review.sh --base develop               # HEAD vs given base
#   codex-review.sh --uncommitted                # working tree changes
#   codex-review.sh --session <id>               # work-unit changes in this repository
#   codex-review.sh --files f1.ts,f2.ts          # specific files (comma-sep)
#   codex-review.sh --focus security             # focused review
#   codex-review.sh --context "user asked to..." # inline intent brief
#   codex-review.sh --context-file /tmp/brief.md # intent brief from file
#   codex-review.sh --intent-file ~/docs/sources/sessions/.../intent.md  # structured
#                                                # SourceItem intent (preferred:
#                                                # changes the review framing to
#                                                # code-vs-intent comparison)
#   codex-review.sh --resume ...                 # VERDICT-loop round 2+: resume
#                                                # the previous review thread so
#                                                # codex keeps its prior analysis
#                                                # and reasons only about the
#                                                # fixes (big token saving). Round
#                                                # 1 must run WITHOUT --resume.
#
# --session compares the captured work-unit baseline with a repository snapshot,
# including committed, unstaged and untracked changes. --base overrides baseline.
# --resume sends only changes since the previous review snapshot plus responses.
# Narrow --files / --focus reviews never grant a repository-wide approval.
# --response-file F supplies accepted/rebutted findings and verification results.
#
# Environment overrides:
#   CODEX_REVIEW_MODEL   — override model passed to codex (-m)
#   CODEX_REVIEW_TIMEOUT — seconds before the review is aborted (default 540)
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
INTENT_FILE=""
SESSION_ID=""
FILE_LIST=""
RESUME=0
RESPONSE_FILE=""
TIMEOUT="${CODEX_REVIEW_TIMEOUT:-540}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --base|--session|--files|--focus|--context|--context-file|--intent-file|--response-file)
            [[ $# -ge 2 ]] || { echo "[codex-review] $1 requires a value" >&2; exit 2; } ;;
    esac
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
        --intent-file)
            INTENT_FILE="$2"
            shift 2
            ;;
        --response-file)
            RESPONSE_FILE="$2"
            shift 2
            ;;
        --resume)
            RESUME=1
            shift
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

# Intent file takes precedence — it carries structured fields the prompt
# can index against (goal / acceptance_criteria / out_of_scope / assumptions).
# When supplied, the review reframes from "is this good code?" to "does this
# diff match the captured intent?".
INTENT_GOAL=""
INTENT_AC=""
INTENT_OOS=""
INTENT_ASSUMP=""
INTENT_E2E=""
INTENT_COMMIT_SUMMARY=""
INTENT_AVAILABLE=0
if [[ -n "$INTENT_FILE" ]]; then
    if [[ ! -f "$INTENT_FILE" ]]; then
        echo "[codex-review] intent file not found: $INTENT_FILE" >&2
        exit 2
    fi
    # Extract frontmatter once, then pull fields out of it with awk.
    INTENT_FM=$(awk '/^---$/{c++; if(c==2)exit; next} c==1' "$INTENT_FILE")
    INTENT_GOAL=$(awk '/^goal: /{sub(/^goal: /, ""); print; exit}' <<< "$INTENT_FM")
    INTENT_COMMIT_SUMMARY=$(awk '/^commit_summary: /{sub(/^commit_summary: /, ""); print; exit}' <<< "$INTENT_FM")
    INTENT_AC=$(awk '/^acceptance_criteria:$/{f=1; next} f && /^[a-z_]+:/{f=0} f && /^  - /' <<< "$INTENT_FM")
    INTENT_OOS=$(awk '/^out_of_scope:$/{f=1; next} f && /^[a-z_]+:/{f=0} f && /^  - /' <<< "$INTENT_FM")
    INTENT_ASSUMP=$(awk '/^assumptions:$/{f=1; next} f && /^[a-z_]+:/{f=0} f && /^  - /' <<< "$INTENT_FM")
    INTENT_E2E=$(awk '/^verification:$/{f=1; next} f && /^[a-z_]+:/ && !/^  /{f=0} f && /^  e2e: /{sub(/^  e2e: /, ""); print; exit}' <<< "$INTENT_FM")
    if [[ -z "$INTENT_GOAL" || -z "$INTENT_AC" || -z "$INTENT_OOS" ]]; then
        echo "[codex-review] intent file missing required fields (goal / acceptance_criteria / out_of_scope): $INTENT_FILE" >&2
        exit 2
    fi
    INTENT_AVAILABLE=1
fi

RUNNER="$(cd "$(dirname "$0")" && pwd)/codex-exec.sh"
if [[ ! -x "$RUNNER" ]]; then
    echo "[codex-review] runner missing: $RUNNER" >&2
    exit 2
fi

if ! git rev-parse --show-toplevel >/dev/null 2>&1; then
    echo "[codex-review] not inside a git repository" >&2
    exit 2
fi

RESPONSE=""
if [[ -n "$RESPONSE_FILE" ]]; then
    RESPONSE=$(cat "$RESPONSE_FILE") || exit 2
fi

INVOCATION_DIR="$PWD"
REVIEW_REPO_ROOT=$(git rev-parse --show-toplevel)
cd "$REVIEW_REPO_ROOT"
STATE_DIR="$HOME/.claude/state"
mkdir -p "$STATE_DIR"
REPO_HASH=$(repo_hash "$REVIEW_REPO_ROOT")
THREAD_KEY="review-${REPO_HASH}-$(printf '%s' "${SESSION_ID:-manual}" | portable_md5)"
REVIEW_STATE="$STATE_DIR/${THREAD_KEY}.json"
LOCK_DIR="$STATE_DIR/${THREAD_KEY}.lock"
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    echo "[codex-review] Review already running for this repo/session: $LOCK_DIR" >&2
    exit 2
fi
PROMPT_FILE=""
STDOUT_FILE=""
trap 'rm -f "$PROMPT_FILE" "$STDOUT_FILE"; rmdir "$LOCK_DIR"' EXIT
REVIEW_TREE=$(review_snapshot "$REVIEW_REPO_ROOT") || exit 2

mark_repo_reviewed() {
    [[ "$MODE" != "files" && -z "$FOCUS" ]] || return 0
    if [[ "$REVIEW_TREE" != "$(review_snapshot "$REVIEW_REPO_ROOT")" ]]; then
        echo '[codex-review] Files changed during review; approval not published. Re-review current changes.' >&2
        return 1
    fi
    review_index_matches "$REVIEW_REPO_ROOT" "$REVIEW_TREE" || {
        echo '[codex-review] Staged content differs from reviewed files. Stage the reviewed versions and re-run.' >&2
        return 1
    }
    local tmp
    tmp=$(mktemp "$STATE_DIR/.reviewed.XXXXXX")
    jq -n --arg repo "$REVIEW_REPO_ROOT" --arg session "$SESSION_ID" --arg tree "$REVIEW_TREE" \
        '{version:2, scope:"full", repo:$repo, session:$session, tree:$tree}' > "$tmp"
    mv -f "$tmp" "$STATE_DIR/reviewed-$REPO_HASH"
    if [[ -n "$SESSION_ID" ]]; then
        tmp=$(mktemp "$STATE_DIR/.review-base.XXXXXX")
        printf '%s\n' "$REVIEW_TREE" > "$tmp"
        mv -f "$tmp" "$(review_state_path "$REVIEW_REPO_ROOT" "$SESSION_ID")"
    fi
    rm -f "$STATE_DIR/codex-delegate-pending-$REPO_HASH"
}

# Auto-detect the comparison branch for branch/files queries.
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

TARGET_FILES=()
case "$MODE" in
    session)
        if [[ -n "$BASE" ]]; then
            REVIEW_BASE=$(git rev-parse "${BASE}^{tree}") || exit 2
        else
            REVIEW_BASE=$(review_baseline "$REVIEW_REPO_ROOT" "$SESSION_ID") || exit 2
        fi
        DIFF_DESC="work unit in session ${SESSION_ID}; all repository changes since ${REVIEW_BASE}"
        ;;
    uncommitted)
        REVIEW_BASE=$(review_head_tree "$REVIEW_REPO_ROOT")
        DIFF_DESC="uncommitted repository changes including untracked files"
        ;;
    branch|files)
        detect_base
        REVIEW_BASE=$(git merge-base "$BASE" HEAD) || exit 2
        DIFF_DESC="repository snapshot vs merge-base of ${BASE} and HEAD"
        if [[ "$MODE" == "files" ]]; then
            [[ -n "$FILE_LIST" ]] || { echo '[codex-review] --files requires paths' >&2; exit 2; }
            IFS=',' read -ra TARGET_FILES <<< "$FILE_LIST"
            for i in "${!TARGET_FILES[@]}"; do
                [[ "${TARGET_FILES[$i]}" == /* ]] || TARGET_FILES[$i]="$INVOCATION_DIR/${TARGET_FILES[$i]}"
            done
            DIFF_DESC="selected files: ${FILE_LIST}"
        fi
        ;;
esac
RAW_DIFF=$(git diff --no-ext-diff --no-textconv "$REVIEW_BASE" "$REVIEW_TREE" -- "${TARGET_FILES[@]}") || exit 2
DIFF="$RAW_DIFF"

# Strip well-known package-manager lock files from a git-diff stream.
# Lock-file bodies can dominate the prompt. Replace them with a change summary;
# the reviewer can inspect versions, sources and integrity from the Git trees.
filter_lock_files() {
    awk '
        BEGIN {
            keep = 1
            stripped = 0
            lock_re = "(^|/)(package-lock\\.json|yarn\\.lock|pnpm-lock\\.yaml|bun\\.lockb|bun\\.lock|npm-shrinkwrap\\.json|Cargo\\.lock|Pipfile\\.lock|poetry\\.lock|uv\\.lock|composer\\.lock|Gemfile\\.lock|go\\.sum|mix\\.lock|flake\\.lock|pubspec\\.lock|Podfile\\.lock)( |$)"
        }
        /^diff --git / {
            if ($0 ~ lock_re) {
                keep = 0
                stripped++
            } else {
                keep = 1
                print
            }
            next
        }
        keep { print }
        END {
            if (stripped > 0) {
                print "[codex-review] filtered " stripped " lock-file diff(s) from review" > "/dev/stderr"
            }
        }
    '
}

DIFF=$(filter_lock_files <<< "$DIFF")
if [[ "$DIFF" != "$RAW_DIFF" ]]; then
    DIFF+=$'\nDependency/lock-file changes (inspect relevant versions, sources and integrity from snapshot):\n'
    DIFF+=$(git diff --stat "$REVIEW_BASE" "$REVIEW_TREE" -- "${TARGET_FILES[@]}")
fi

if [[ -z "$RAW_DIFF" && "$RESUME" == "0" && -z "$CONTEXT" && "$INTENT_AVAILABLE" == "0" && ! -f "$REVIEW_STATE" ]]; then
    echo "## Summary" >&2
    echo "No diff to review (${DIFF_DESC})." >&2
    echo ""
    echo "VERDICT: APPROVED"
    # Mark reviewed only for auto-scoped modes (uncommitted, branch). For an
    # explicit --files request that resolves to empty diffs, the user asked
    # about a narrow set; granting the wider repo's reviewed/pending marker
    # would be an unauthorized gate bypass.
    if [[ "$MODE" != "files" ]]; then
        mark_repo_reviewed || exit 2
    fi
    notify_codex_done "VERDICT: APPROVED (no diff to review)" "$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")"
    exit 0
fi

FOCUS_LINE=""
if [[ -n "$FOCUS" ]]; then
    FOCUS_LINE="Focus exclusively on: $FOCUS. Ignore everything outside this focus area."
fi

CONTEXT_SECTION=""
INTENT_CHECK=""
if [[ "$INTENT_AVAILABLE" = "1" ]]; then
    # Structured intent — the review is now primarily a code-vs-intent
    # comparison. Each acceptance_criteria must be verifiable in the diff;
    # each out_of_scope must NOT be touched; assumptions must hold.
    CONTEXT_SECTION=$(cat <<EOF

--- TASK INTENT (captured before implementation, SourceItem at ${INTENT_FILE}) ---
Goal: ${INTENT_GOAL}
Commit summary (will be in git log): ${INTENT_COMMIT_SUMMARY}

Acceptance criteria (every item must be verifiable from the diff):
${INTENT_AC}

Out of scope (the diff must NOT touch any of these):
${INTENT_OOS}

Author assumptions (flag if any are violated by the diff):
${INTENT_ASSUMP}

E2E verification declared: ${INTENT_E2E}
--- END TASK INTENT ---
EOF
)
    INTENT_CHECK="
This review is primarily a CODE-VS-INTENT comparison, not a generic quality pass.

For each acceptance_criteria item, locate the change in the diff that satisfies it. If you cannot, raise it as CRITICAL with the label [INTENT-MISMATCH] and the unmet criterion.

For each out_of_scope item, scan the diff for any touch on it. Any violation is CRITICAL [INTENT-MISMATCH].

If any author assumption is invalidated by the diff (e.g. assumption said \"X stays unchanged\" but X was changed), raise CRITICAL [INTENT-MISMATCH].

Generic code-quality issues outside the intent should be tagged [CODE-DEFECT] in CRITICAL and be limited to genuine breakage (security / correctness / type safety). Suppress style, naming, future-improvement noise per AGENTS.md."
elif [[ -n "$CONTEXT" ]]; then
    CONTEXT_SECTION=$(cat <<EOF

--- TASK CONTEXT (from the author) ---
${CONTEXT}
--- END TASK CONTEXT ---
EOF
)
    INTENT_CHECK="
Also judge intent-vs-implementation alignment: does the diff actually do what the Task Context says the author intended? If there is a material mismatch between stated intent and actual code (missing requirement, silent scope creep, subtly different semantics), raise it as CRITICAL with the label [INTENT-MISMATCH]. Other CRITICAL findings get [CODE-DEFECT]."
else
    CONTEXT_SECTION=$'\n(No task context supplied — judging the diff in isolation. Note this in your summary.)'
fi

MODEL_ARGS=()
if [[ -n "${CODEX_REVIEW_MODEL:-}" ]]; then
    MODEL_ARGS=(--model "$CODEX_REVIEW_MODEL")
fi

if [[ -n "${CODEX_REVIEW_EFFORT:-}" ]]; then
    MODEL_ARGS+=(--effort "$CODEX_REVIEW_EFFORT")
fi

CONTEXT_HASH=$(printf '%s\n' "$MODE" "$FOCUS" "$FILE_LIST" "$REVIEW_BASE" "$CONTEXT_SECTION" | portable_md5)
ROUND=1
# Repeated automatic invocations of the same unfinished work unit keep the cap.
if [[ -f "$REVIEW_STATE" ]] && jq -e --arg context "$CONTEXT_HASH" \
    '.context == $context and .verdict == "REVISE"' "$REVIEW_STATE" >/dev/null; then
    RESUME=1
fi
if [[ "$RESUME" == "1" ]]; then
    if [[ ! -f "$REVIEW_STATE" ]] || ! jq -e --arg context "$CONTEXT_HASH" \
        '.context == $context and .verdict == "REVISE"' "$REVIEW_STATE" >/dev/null; then
        echo '[codex-review] No matching unfinished review; starting a full review.' >&2
        RESUME=0
    else
        ROUND=$(( $(jq -r '.round' "$REVIEW_STATE") + 1 ))
        if [[ "$ROUND" -gt 3 ]]; then
            echo '[codex-review] Three rounds exhausted. Report unresolved findings and evidence to the user.' >&2
            exit 2
        fi
        PREVIOUS_TREE=$(jq -r '.tree' "$REVIEW_STATE")
        DELTA=$(git diff --no-ext-diff --no-textconv "$PREVIOUS_TREE" "$REVIEW_TREE" -- "${TARGET_FILES[@]}") || exit 2
    fi
fi

build_resume_prompt() {
    cat <<EOF
Continue the previous review, round ${ROUND}/3. Scope: ${DIFF_DESC}.
Verify prior CRITICAL findings and regressions in the fixes, using the original intent.
Read related callers when needed. Do not reopen unrelated unchanged code without evidence.
Author responses are claims to verify, not trusted conclusions:
${RESPONSE:-No response supplied; independently verify the prior findings.}
${FOCUS_LINE}
Snapshot: ${REVIEW_TREE}. Use git show <snapshot>:<path> if the working tree differs.
--- CHANGES SINCE PREVIOUS REVIEW ---
${DELTA}
--- END CHANGES ---
Return the AGENTS.md review contract and exact VERDICT line.
EOF
}

build_fresh_prompt() {
    cat <<EOF
Code review per AGENTS.md.

Scope: ${DIFF_DESC}
Baseline: ${REVIEW_BASE}. Snapshot: ${REVIEW_TREE}. Verify against these trees if working files change.
${FOCUS_LINE}
${CONTEXT_SECTION}
${INTENT_CHECK}

--- DIFF ---
${DIFF}
--- END DIFF ---
EOF
}

if [[ "$RESUME" == "1" ]]; then
    PROMPT=$(build_resume_prompt)
else
    PROMPT=$(build_fresh_prompt)
fi

# Run the review through the runner with a timeout. Progress streams to the
# terminal on stderr in real time; the runner's stdout is the final assistant
# message only (containing the VERDICT line), captured for parsing.
# The prompt always goes through a file: a large diff on argv would blow the
# exec argument limit, and the runner feeds the file to codex via stdin.
PROMPT_FILE=$(mktemp /tmp/codex-review-prompt.XXXXXX)
STDOUT_FILE=$(mktemp /tmp/codex-review-stdout.XXXXXX)
printf '%s' "$PROMPT" > "$PROMPT_FILE"

run_review() {
    local mode="$1"
    local -a rargs=(--thread-key "$THREAD_KEY")
    [[ "$mode" == "resume" ]] && rargs+=(--resume)
    : > "$STDOUT_FILE"
    set +e
    CODEX_REVIEW_ID="$THREAD_KEY" CODEX_REVIEW_UNIT="$CONTEXT_HASH" CODEX_REVIEW_ROUND="$ROUND" CODEX_REVIEW_SNAPSHOT="$REVIEW_TREE" \
    "$RUNNER" --prompt-file "$PROMPT_FILE" --timeout "$TIMEOUT" \
        ${rargs[@]+"${rargs[@]}"} ${MODEL_ARGS[@]+"${MODEL_ARGS[@]}"} </dev/null \
        >"$STDOUT_FILE"
    STATUS=$?
    set -e
    OUTPUT=$(cat "$STDOUT_FILE")
}

# Round 2+ resumes the previous review thread by id; round 1 starts fresh.
if [[ "$RESUME" == "1" ]]; then
    run_review resume
else
    run_review fresh
fi

# Graceful fallback: --resume with no usable thread (round 1 never ran, or the
# rollout was GC'd) exits 3. Don't hard-fail the review — rebuild the full
# fresh prompt (with the context/intent the resume prompt omitted) and retry
# fresh so the commit gate is not blocked by a missing thread.
if [[ "$RESUME" == "1" && $STATUS -eq 3 ]]; then
    echo "[codex-review] no resumable thread found; falling back to a fresh review" >&2
    RESUME=0
    PROMPT=$(build_fresh_prompt)
    printf '%s' "$PROMPT" > "$PROMPT_FILE"
    run_review fresh
fi

# Resolved above (THREAD_KEY) — reused so every terminal path can ping (a
# backgrounded review that times out must still notify, not finish silently).
REVIEW_CWD="$REVIEW_REPO_ROOT"

if [[ $STATUS -eq 124 ]]; then
    echo "[codex-review] timed out after ${TIMEOUT}s" >&2
    notify_codex_done "codex review TIMED OUT (${TIMEOUT}s)" "$REVIEW_CWD"
    exit 2
fi

if [[ $STATUS -eq 127 ]]; then
    echo "[codex-review] timeout binary missing — install GNU coreutils ('brew install coreutils' on macOS)" >&2
    notify_codex_done "codex review ERROR (timeout binary missing)" "$REVIEW_CWD"
    exit 2
fi

if [[ $STATUS -ne 0 ]]; then
    echo "[codex-review] codex run failed with status $STATUS" >&2
    echo "$OUTPUT" >&2
    notify_codex_done "codex review FAILED (status $STATUS)" "$REVIEW_CWD"
    exit 2
fi

echo "$OUTPUT"

# Parse the final verdict — check the last 20 lines so conversational preamble does not confuse us
VERDICT_LINE=$(echo "$OUTPUT" | tail -n 20 | grep -E "^VERDICT: (APPROVED|REVISE)$" | tail -n 1 || true)

# No manual ping here: a completed codex turn fires the `notify` program from
# ~/.codex/config.toml with the final message (which carries the VERDICT line).
# The app-server path swallowed that event; `codex exec` does not. The explicit
# notify_codex_done calls that remain cover only the paths where no codex turn
# completes — empty diff, timeout, spawn failure.

STATE_TMP=$(mktemp "$STATE_DIR/.review-round.XXXXXX")
jq -n --arg tree "$REVIEW_TREE" --arg context "$CONTEXT_HASH" --argjson round "$ROUND" \
    --arg verdict "${VERDICT_LINE#VERDICT: }" \
    '{tree:$tree, context:$context, round:$round, verdict:$verdict}' > "$STATE_TMP"
mv -f "$STATE_TMP" "$REVIEW_STATE"

case "$VERDICT_LINE" in
    "VERDICT: APPROVED")
        # Mark reviewed only for auto-scoped reviews (uncommitted, session,
        # branch). An explicit --files request is a narrow query that does
        # not cover the entire working tree; granting the repo-wide gate
        # marker on its APPROVED would let unrelated unreviewed changes
        # slip past pre-commit-gate.sh.
        if [[ "$MODE" != "files" ]]; then
            mark_repo_reviewed || exit 2
        fi
        # COPAD_HOOK_PUBLISH: claude.review_approved $(jq -n --arg s "$SESSION_ID" --arg m "$MODE" '{session:$s,mode:$m}')
        # Redirect coctl's ack ({"queued":true}) away from stdout so it does not
        # trail the VERDICT in the review output the caller reads.
        command -v coctl >/dev/null && coctl event publish claude.review_approved --quiet "$(jq -n --arg s "$SESSION_ID" --arg m "$MODE" '{session:$s,mode:$m}')" >/dev/null 2>&1 &
        # COPAD_HOOK_PUBLISH_END
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
