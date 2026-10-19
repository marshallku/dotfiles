#!/usr/bin/env bash
# Git trees retain review inputs without changing the user's index or branches.

review_head_tree() {
    local tree
    tree=$(git -C "$1" rev-parse --verify 'HEAD^{tree}' 2>/dev/null) || tree=$(git -C "$1" mktree </dev/null) || return 1
    printf '%s\n' "$tree"
}

review_snapshot() (
    set -e
    cd "$1" || return 1
    local scratch
    scratch=$(mktemp -d "${TMPDIR:-/tmp}/review-index.XXXXXX") || return 1
    trap 'rm -rf "$scratch"' EXIT
    git ls-files --stage -z > "$scratch/staged" || return 1
    export GIT_INDEX_FILE="$scratch/index"
    git read-tree "$(review_head_tree "$PWD")" || return 1
    git update-index -z --index-info < "$scratch/staged" || return 1
    git add -A -- . || return 1
    git write-tree
)

review_state_path() {
    printf '%s/.claude/state/review-base-%s-%s' "$HOME" "$(repo_hash "$1")" \
        "$(printf '%s' "$2" | portable_md5)"
}

review_init_baseline() {
    local path
    path=$(review_state_path "$1" "$2")
    mkdir -p "$(dirname "$path")"
    # noclobber preserves the original baseline on resume/compact.
    (set -o noclobber; review_head_tree "$1" > "$path") 2>/dev/null || [ -s "$path" ]
}

review_baseline() {
    local path
    path=$(review_state_path "$1" "$2")
    if [ ! -s "$path" ]; then
        echo '[review] No session baseline. Use --base <known-start-commit> or --uncommitted explicitly.' >&2
        return 1
    fi
    cat "$path"
}

# All staged changes must contain exactly the reviewed version. This permits
# staging after review but rejects partial staging of an intermediate version.
review_index_matches() (
    set -o pipefail
    local repo="$1" tree="$2" path
    git -C "$repo" diff --cached --name-only -z "$(review_head_tree "$repo")" | while IFS= read -r -d '' path; do
        git -C "$repo" diff --quiet --cached "$tree" -- "$path" || return 1
    done
)

review_expected_reviewer() {
    local repo="$1" session="$2" marker="$HOME/.claude/state/reviewed-$(repo_hash "$1")"
    if [ -f "$HOME/.claude/state/codex-delegate-pending-$(repo_hash "$repo")" ]; then
        printf 'both\n'
        return
    fi
    # Delegation can mix both authors. Keep both approvals on that exact snapshot.
    if [ -s "$marker" ] && jq -e --arg repo "$repo" --arg session "$session" \
        '.version == 2 and .repo == $repo and .session == $session and .origin == "codex-delegate"' \
        "$marker" >/dev/null 2>&1 \
        && [ "$(jq -r '.tree' "$marker")" = "$(review_snapshot "$repo")" ]; then
        printf 'both\n'
        return
    fi
    printf '%s\n' "${HARNESS_REQUIRED_REVIEWER:-codex}"
}

review_has_provider() {
    jq -e --arg reviewer "$2" '
        (.reviewers // [(.reviewer // "codex")]) as $reviewers |
        if $reviewer == "both" then ($reviewers | index("codex") != null and index("claude") != null)
        else ($reviewers | index($reviewer) != null) end' "$1" >/dev/null 2>&1
}

review_approval_valid() {
    local marker="$1" session="$2" repo="$3" tree
    [ -s "$marker" ] || return 1
    [ ! -d "$HOME/.claude/state/codex-delegate-active-$(repo_hash "$repo")" ] || return 1
    jq -e --arg session "$session" --arg repo "$repo" \
        '.version == 2 and .scope == "full" and .repo == $repo and .session == $session' \
        "$marker" >/dev/null 2>&1 || return 1
    review_has_provider "$marker" "$(review_expected_reviewer "$repo" "$session")" || return 1
    tree=$(jq -r '.tree' "$marker")
    [ "$tree" = "$(review_snapshot "$repo")" ] || return 1
    review_index_matches "$repo" "$tree"
}

# Stop reminders. Commit is the hard gate; a Stop block is only a reminder, and each
# one costs a full turn that re-reads the whole context. An orchestrator waiting on
# subagents stops dozens of times per work unit (one session: 295 blocks in a week,
# almost all answered "not yet"). So remind once per unreviewed snapshot, and at
# most once per AUTO_REVIEW_STOP_COOLDOWN seconds (default 1200) while changes keep
# landing. A new approval since the last reminder re-arms it for the next work unit.
review_stop_state_path() {
    printf '%s/.claude/state/review-stop-%s-%s' "$HOME" "$(repo_hash "$1")" \
        "$(printf '%s' "$2" | portable_md5)"
}

# review_stop_suppressed <repo> <session> <tree> [grace-seconds]
# A record younger than grace-seconds is ignored: notify-stop runs concurrently with
# the Stop hook that may have just written it for this very Stop.
review_stop_suppressed() {
    local path seen at approval now
    path=$(review_stop_state_path "$1" "$2")
    [ -s "$path" ] || return 1
    read -r seen at approval < "$path" || return 1
    case "$at" in ''|*[!0-9]*) return 1 ;; esac
    now=$(date +%s)
    [ $(( now - at )) -ge "${4:-0}" ] || return 1
    # Compare approval identity, not timestamps: an approval in the same second as
    # the reminder must not count as "after" it.
    [ "$approval" = "$(review_stop_approval_id "$1")" ] || return 1
    [ "$seen" = "$3" ] && return 0
    [ $(( now - at )) -lt "${AUTO_REVIEW_STOP_COOLDOWN:-1200}" ]
}

review_stop_approval_id() {
    local marker="$HOME/.claude/state/reviewed-$(repo_hash "$1")"
    if [ -s "$marker" ]; then portable_md5 < "$marker"; else printf 'none\n'; fi
}

review_stop_record() {
    printf '%s %s %s\n' "$3" "$(date +%s)" "$(review_stop_approval_id "$1")" > "$(review_stop_state_path "$1" "$2")"
}

# What save.sh would publish when this session never captured a baseline for the
# repo (a commit in a second repo): save.sh pushes to origin/<branch>, so the
# merge-base with that ref bounds the outgoing changes. Eligibility only — the
# review itself still needs an explicit --base. No such ref -> no answer.
review_publish_base() {
    local branch
    branch=$(git -C "$1" symbolic-ref --short HEAD 2>/dev/null) || return 1
    git -C "$1" rev-parse --verify -q "refs/remotes/origin/$branch" >/dev/null || return 1
    git -C "$1" merge-base "refs/remotes/origin/$branch" HEAD 2>/dev/null
}

# .reviewignore at the repo root: one bash glob per line (`*` crosses `/`),
# `#` comments. Matching paths are data written by automation (bot memory,
# sync metadata) and count like documentation. Protected paths are decided
# before this is consulted, and .reviewignore itself always needs review.
review_ignored() {
    local repo="$1" path="$2" pattern
    [ -f "$repo/.reviewignore" ] || return 1
    while IFS= read -r pattern || [ -n "$pattern" ]; do
        pattern="${pattern%%#*}"
        pattern="${pattern#"${pattern%%[![:space:]]*}"}"
        pattern="${pattern%"${pattern##*[![:space:]]}"}"
        [ -n "$pattern" ] || continue
        # shellcheck disable=SC2053
        [[ "$path" == $pattern ]] && return 0
    done < "$repo/.reviewignore"
    return 1
}

# Repository changes, not tool calls or line counts, determine review eligibility.
# Documentation-only work may skip; executable/config/dependency changes do not.
review_required() {
    local repo="$1" session="$2" base tree path marker
    marker="$HOME/.claude/state/reviewed-$(repo_hash "$repo")"
    [ ! -f "$HOME/.claude/state/codex-delegate-pending-$(repo_hash "$repo")" ] || return 0
    # An approval from the wrong family must not disappear behind its advanced baseline.
    if [ -s "$marker" ] && jq -e --arg repo "$repo" --arg session "$session" \
        '.version == 2 and .repo == $repo and .session == $session' "$marker" >/dev/null 2>&1 \
        && ! review_has_provider "$marker" "$(review_expected_reviewer "$repo" "$session")"; then
        return 0
    fi
    base=$(review_baseline "$repo" "$session" 2>/dev/null) \
        || base=$(review_publish_base "$repo") || return 0
    git -C "$repo" cat-file -e "${base}^{tree}" 2>/dev/null || return 0
    tree=$(review_snapshot "$repo") || return 0
    review_index_matches "$repo" "$tree" || return 0
    while IFS= read -r -d '' path; do
        case "$path" in
            */SKILL.md|AGENTS.md|*/AGENTS.md|CLAUDE.md|*/CLAUDE.md|.claude/*|.codex/*|*/.claude/*|*/.codex/*|.reviewignore) return 0 ;;
            *.md|*.rst|LICENSE|LICENSE.*) ;;
            *) review_ignored "$repo" "$path" || return 0 ;;
        esac
    done < <(git -C "$repo" diff --name-only -z "$base" "$tree")
    return 1
}
