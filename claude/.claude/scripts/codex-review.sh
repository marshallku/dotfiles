#!/usr/bin/env bash
# codex-review.sh — Cross-check review with a strict VERDICT output contract.
# Routes through the codex-companion app-server runtime so progress phases
# stream to the user (instead of silent capture). Read-only sandbox.
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
#   CODEX_REVIEW_MODEL   — override model passed to the companion (--model)
#   CODEX_REVIEW_TIMEOUT — seconds before the review is aborted (default 1200)
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
TIMEOUT="${CODEX_REVIEW_TIMEOUT:-1200}"

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
        --intent-file)
            INTENT_FILE="$2"
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

COMPANION="$(dirname "$0")/codex-companion.sh"
if [[ ! -x "$COMPANION" ]]; then
    echo "[codex-review] companion wrapper missing: $COMPANION" >&2
    exit 2
fi

if ! git rev-parse --show-toplevel >/dev/null 2>&1; then
    echo "[codex-review] not inside a git repository" >&2
    exit 2
fi

# Defined early so that empty-diff APPROVED early-exits below can call it.
# On APPROVED: mark the current repo as reviewed so pre-commit-gate.sh lets
# subsequent save.sh / git commit / git push through. Also clear any pending
# codex-delegate marker for this repo — the review just covered whatever
# codex wrote (or confirmed it wrote nothing), so the gate-bypass flag is
# no longer needed.
mark_repo_reviewed() {
    local repo_root
    repo_root=$(git rev-parse --show-toplevel 2>/dev/null || echo "")
    [ -z "$repo_root" ] && return 0
    local repo_hash_v
    repo_hash_v=$(repo_hash "$repo_root")
    local state_dir="$HOME/.claude/state"
    mkdir -p "$state_dir"
    touch "$state_dir/reviewed-$repo_hash_v"
    rm -f "$state_dir/codex-delegate-pending-$repo_hash_v"
}

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

    # 4. Untracked new file: synthetic diff vs /dev/null. Otherwise files
    #    that were created (e.g. by /codex-delegate) but never committed
    #    return empty here and slip through the empty-DIFF early-exit.
    if [[ -f "$file" ]]; then
        d=$(git diff --no-index --binary -- /dev/null "$file" 2>/dev/null || true)
        if [[ -n "$d" ]]; then echo "$d"; return 0; fi
    fi

    return 1
}

# Resolve file list for session/files modes
TARGET_FILES=()
FILES_SUMMARY=""

if [[ "$MODE" == "session" ]]; then
    DIRTY_LOG="$HOME/.claude/state/dirty-${SESSION_ID}.log"
    if [[ ! -f "$DIRTY_LOG" ]]; then
        # Fallback: a /codex-delegate --write only session never invokes
        # track-edit.sh, so no dirty log exists, but the working tree still
        # has codex's writes that need review. Treat as --uncommitted so the
        # gate's "run --session ${SESSION}" instruction Just Works for that
        # case instead of hard-failing.
        echo "[codex-review] no dirty log for session ${SESSION_ID}; falling back to --uncommitted" >&2
        MODE="uncommitted"
    else
        REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "")
        while IFS= read -r f; do
            # Scope to current repo
            if [[ -n "$REPO_ROOT" ]] && [[ "$f" != "${REPO_ROOT}/"* ]]; then
                continue
            fi
            TARGET_FILES+=("$f")
        done < <(sort -u "$DIRTY_LOG")
    fi

elif [[ "$MODE" == "files" ]]; then
    IFS=',' read -ra TARGET_FILES <<< "$FILE_LIST"
fi

# Collect diffs based on mode
if [[ "$MODE" == "session" || "$MODE" == "files" ]]; then
    if [[ ${#TARGET_FILES[@]} -eq 0 ]]; then
        # No targets to review. For session mode this is the cross-repo edge
        # case: the dirty log exists (other repo touched) but has zero entries
        # for the cwd repo. Falling through to APPROVED would clear the
        # delegate-pending marker for the cwd repo without actually reviewing
        # codex's working-tree writes — exactly the bypass we are trying to
        # close. Fall back to --uncommitted instead so the cwd repo's working
        # tree is what gets reviewed.
        if [[ "$MODE" == "session" ]]; then
            echo "[codex-review] no session-tracked files for this repo; falling back to --uncommitted" >&2
            MODE="uncommitted"
        else
            # explicit --files mode with empty list. This is a caller error
            # (or empty-set query). Do NOT mark reviewed — that would clear
            # the repo's reviewed/pending markers without ever reviewing the
            # actual working tree, granting a free gate bypass.
            echo "[codex-review] --files mode requires at least one file" >&2
            exit 2
        fi
    fi
fi

# Branch the diff collection on (possibly fallback-adjusted) MODE.
if [[ "$MODE" == "session" || "$MODE" == "files" ]]; then

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
    # `git diff HEAD` excludes untracked files. A /codex-delegate that only
    # creates new files would show an empty diff here and bypass review via
    # the empty-DIFF path below. Append a synthetic diff for each untracked
    # file (vs /dev/null) so they actually get reviewed.
    DIFF=$(git diff HEAD)
    while IFS= read -r untracked; do
        [ -z "$untracked" ] && continue
        # --no-index always exits 1 when files differ; swallow it.
        u_diff=$(git diff --no-index --binary -- /dev/null "$untracked" 2>/dev/null || true)
        if [[ -n "$u_diff" ]]; then
            DIFF="${DIFF}"$'\n'"${u_diff}"
        fi
    done < <(git ls-files --others --exclude-standard 2>/dev/null)
    DIFF_DESC="uncommitted working tree changes (incl. untracked files)"

else
    detect_base
    DIFF=$(git diff "${BASE}...HEAD")
    DIFF_DESC="HEAD vs ${BASE}"
fi

# Strip well-known package-manager lock files from a git-diff stream.
# Lock-file diffs are pure dependency-resolver output — reviewing them line by
# line burns codex tokens with zero signal, and a single dep bump can dominate
# the entire diff. We drop the whole `diff --git` block for each match.
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

if [[ -z "$DIFF" ]]; then
    echo "## Summary" >&2
    echo "No diff to review (${DIFF_DESC})." >&2
    echo ""
    echo "VERDICT: APPROVED"
    # Mark reviewed only for auto-scoped modes (uncommitted, branch). For an
    # explicit --files request that resolves to empty diffs, the user asked
    # about a narrow set; granting the wider repo's reviewed/pending marker
    # would be an unauthorized gate bypass.
    if [[ "$MODE" != "files" ]]; then
        mark_repo_reviewed
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

# Build the prompt
FILES_SECTION=""
if [[ -n "$FILES_SUMMARY" ]]; then
    FILES_SECTION="${FILES_SUMMARY}
"
fi

# Review role + classification scheme + VERDICT contract live in
# ~/.codex/AGENTS.md "Code Review Principles" / "Review Output Contract".
# Auto-loaded — don't restate. We only supply scope + context + diff.
#
# RESUME rounds (VERDICT-loop round 2+) reuse the prior review thread via the
# companion's --resume-last. Codex already holds round 1's diff, its analysis,
# and the task context/intent, so we DON'T resend CONTEXT_SECTION / INTENT_CHECK
# (would just re-bill tokens codex already has). We send a short continuation
# framing + the freshly-recomputed diff so codex reasons only about the fixes
# instead of re-analysing the whole change from scratch. The diff is still
# embedded (not "go run git diff yourself") to preserve exact review scope
# across all collection strategies — committed, uncommitted, and untracked.
build_resume_prompt() {
    cat <<EOF
Continuation of the code review in this thread. I have applied fixes for your previous findings.

Below is the UPDATED diff for the same scope (${DIFF_DESC}). Compared with the diff you reviewed earlier in this thread: confirm each prior CRITICAL is resolved, and check the fixes introduced no regressions. Apply the same contract/intent as before — re-issue VERDICT: APPROVED or VERDICT: REVISE per AGENTS.md.
${FOCUS_LINE}

--- UPDATED DIFF ---
${DIFF}
--- END UPDATED DIFF ---
EOF
}

build_fresh_prompt() {
    cat <<EOF
Code review per AGENTS.md.

Scope: ${DIFF_DESC}
${FOCUS_LINE}
${FILES_SECTION}${CONTEXT_SECTION}
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

# Run review through the companion (app-server runtime) with a timeout.
# Progress phases stream to stderr in real time; final assistant message
# (containing the VERDICT line) is captured from stdout for parsing.
# Use --prompt-file rather than passing the prompt as argv: a large diff
# pushes the argv past the size that node's spawnSync can hand to its
# `codex --version` / `codex app-server --help` probes, and the probe
# failures surface as a confusing "Codex CLI is not installed" error.
PROMPT_FILE=$(mktemp /tmp/codex-review-prompt.XXXXXX)
STDERR_FILE=$(mktemp /tmp/codex-review-stderr.XXXXXX)
trap 'rm -f "$PROMPT_FILE" "$STDERR_FILE"' EXIT
printf '%s' "$PROMPT" > "$PROMPT_FILE"

# Run the companion once. Captures stdout into OUTPUT (for VERDICT parsing) and
# mirrors stderr to both the terminal (live progress phases) and STDERR_FILE
# (so we can detect the "no resumable thread" error, which the companion writes
# to stderr — not stdout). $1 selects resume vs fresh.
run_review() {
    local mode="$1"
    local -a rargs=()
    [[ "$mode" == "resume" ]] && rargs=(--resume-last)
    : > "$STDERR_FILE"
    set +e
    OUTPUT=$(portable_timeout "$TIMEOUT" "$COMPANION" task --prompt-file "$PROMPT_FILE" \
        ${rargs[@]+"${rargs[@]}"} ${MODEL_ARGS[@]+"${MODEL_ARGS[@]}"} </dev/null \
        2> >(tee "$STDERR_FILE" >&2))
    STATUS=$?
    set -e
}

# Round 2+ resumes the previous review thread; round 1 starts fresh. The
# companion's --resume-last picks the newest task thread for this workspace
# (it cannot target a specific thread id), so any interleaved codex call
# between rounds would hijack the resume. Inside a VERDICT loop Claude only
# edits files between rounds, so the newest thread is the prior review.
if [[ "$RESUME" == "1" ]]; then
    run_review resume
else
    run_review fresh
fi

# Graceful fallback: --resume with no prior thread (e.g. --resume passed on
# round 1, or the thread was GC'd) makes the companion exit non-zero with
# "No previous Codex task thread" on stderr. Don't hard-fail the review —
# rebuild the full fresh prompt (with the context/intent the resume prompt
# omitted) and retry fresh so the commit gate is not blocked by a missing
# thread. Any other failure falls through to the error handling below.
if [[ "$RESUME" == "1" && $STATUS -ne 0 ]] && grep -q "No previous Codex task thread" "$STDERR_FILE"; then
    echo "[codex-review] no resumable thread found; falling back to a fresh review" >&2
    PROMPT=$(build_fresh_prompt)
    printf '%s' "$PROMPT" > "$PROMPT_FILE"
    run_review fresh
fi

# Computed before any exit branch so every terminal path can ping (a
# backgrounded review that times out must still notify, not finish silently).
REVIEW_CWD=$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")

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
    echo "[codex-review] companion task failed with status $STATUS" >&2
    echo "$OUTPUT" >&2
    notify_codex_done "codex review FAILED (status $STATUS)" "$REVIEW_CWD"
    exit 2
fi

echo "$OUTPUT"

# Parse the final verdict — check the last 20 lines so conversational preamble does not confuse us
VERDICT_LINE=$(echo "$OUTPUT" | tail -n 20 | grep -E "^VERDICT: (APPROVED|REVISE)" | tail -n 1 || true)

# Ping the user that the (possibly backgrounded) review finished. The app-server
# path does not honor ~/.codex/config.toml notify, so the wrapper must do it.
notify_codex_done "${VERDICT_LINE:-codex review done (no verdict)}" "$REVIEW_CWD"

case "$VERDICT_LINE" in
    "VERDICT: APPROVED")
        # Mark reviewed only for auto-scoped reviews (uncommitted, session,
        # branch). An explicit --files request is a narrow query that does
        # not cover the entire working tree; granting the repo-wide gate
        # marker on its APPROVED would let unrelated unreviewed changes
        # slip past pre-commit-gate.sh.
        if [[ "$MODE" != "files" ]]; then
            mark_repo_reviewed
        fi
        # COPAD_HOOK_PUBLISH: claude.review_approved $(jq -n --arg s "$SESSION_ID" --arg m "$MODE" '{session:$s,mode:$m}')
        command -v coctl >/dev/null && coctl event publish claude.review_approved --quiet "$(jq -n --arg s "$SESSION_ID" --arg m "$MODE" '{session:$s,mode:$m}')" &
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
