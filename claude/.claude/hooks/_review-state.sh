#!/usr/bin/env bash
# Git trees retain review inputs without changing the user's index or branches.

review_head_tree() {
    local tree
    tree=$(git -C "$1" rev-parse --verify 'HEAD^{tree}' 2>/dev/null) || tree=$(git -C "$1" mktree </dev/null) || return 1
    printf '%s\n' "$tree"
}

# review_snapshot <repo>
# The working tree as a tree object, built in a scratch index.
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

# The tree save.sh would commit: the real index, written through a copy so the
# user's index file (and its cache-tree) is never touched.
review_index_tree() (
    set -e
    cd "$1" || return 1
    local scratch index
    scratch=$(mktemp -d "${TMPDIR:-/tmp}/review-index.XXXXXX") || return 1
    trap 'rm -rf "$scratch"' EXIT
    index=$(git rev-parse --git-path index) || return 1
    [ ! -f "$index" ] || cp "$index" "$scratch/index"
    GIT_INDEX_FILE="$scratch/index" git write-tree
)

# One approval per reviewed staged tree. Content-addressed, so sessions sharing a
# repository never overwrite each other's approval and any session may commit a
# tree that was reviewed.
review_marker_path() {
    printf '%s/.claude/state/reviewed-%s-%s\n' "$HOME" "$(repo_hash "$1")" "$2"
}

# review_expected_reviewer <repo> [tree]
# Delegation can mix both authors: keep both approvals on that exact staged tree.
review_expected_reviewer() {
    local repo="$1" tree="${2:-}" marker
    if [ -f "$HOME/.claude/state/codex-delegate-pending-$(repo_hash "$repo")" ]; then
        printf 'both\n'
        return
    fi
    [ -n "$tree" ] || tree=$(review_index_tree "$repo") || tree=""
    marker=$(review_marker_path "$repo" "$tree")
    if [ -n "$tree" ] && [ -s "$marker" ] && jq -e '.origin == "codex-delegate"' "$marker" >/dev/null 2>&1; then
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

# review_approval_valid <repo>
# The commit is HEAD -> index. It is approved when that exact pair was reviewed,
# by whichever session; unstaged edits from any session do not matter.
review_approval_valid() {
    local repo="$1" tree base marker
    [ ! -d "$HOME/.claude/state/codex-delegate-active-$(repo_hash "$repo")" ] || return 1
    tree=$(review_index_tree "$repo") || return 1
    base=$(review_head_tree "$repo") || return 1
    marker=$(review_marker_path "$repo" "$tree")
    [ -s "$marker" ] || return 1
    jq -e --arg repo "$repo" --arg tree "$tree" --arg base "$base" \
        '.version == 3 and .scope == "staged" and .repo == $repo and .tree == $tree and .base == $base' \
        "$marker" >/dev/null 2>&1 || return 1
    review_has_provider "$marker" "$(review_expected_reviewer "$repo" "$tree")"
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

# review_path_needs_review <repo> <path>
# Documentation-only work may skip; executable/config/dependency changes do not.
review_path_needs_review() {
    case "$2" in
        */SKILL.md|AGENTS.md|*/AGENTS.md|CLAUDE.md|*/CLAUDE.md|.claude/*|.codex/*|*/.claude/*|*/.codex/*|.reviewignore) return 0 ;;
        *.md|*.rst|LICENSE|LICENSE.*) return 1 ;;
        *) ! review_ignored "$1" "$2" ;;
    esac
}

# review_required <repo>
# Repository changes, not tool calls or line counts, determine review eligibility:
# what save.sh commits, HEAD -> index. Bash edits leave no log, so every staged
# path counts whoever wrote it.
review_required() {
    local repo="$1" base tree path
    [ ! -f "$HOME/.claude/state/codex-delegate-pending-$(repo_hash "$repo")" ] || return 0
    base=$(review_head_tree "$repo") || return 1
    tree=$(review_index_tree "$repo") || return 1
    while IFS= read -r -d '' path; do
        review_path_needs_review "$repo" "$path" && return 0
    done < <(git -C "$repo" diff --name-only -z "$base" "$tree")
    return 1
}
