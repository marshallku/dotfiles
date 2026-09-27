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
    base=$(review_baseline "$repo" "$session" 2>/dev/null) || return 0
    git -C "$repo" cat-file -e "${base}^{tree}" 2>/dev/null || return 0
    tree=$(review_snapshot "$repo") || return 0
    review_index_matches "$repo" "$tree" || return 0
    while IFS= read -r -d '' path; do
        case "$path" in
            */SKILL.md|AGENTS.md|*/AGENTS.md|CLAUDE.md|*/CLAUDE.md|.claude/*|.codex/*|*/.claude/*|*/.codex/*) return 0 ;;
            *.md|*.rst|LICENSE|LICENSE.*) ;;
            *) return 0 ;;
        esac
    done < <(git -C "$repo" diff --name-only -z "$base" "$tree")
    return 1
}
