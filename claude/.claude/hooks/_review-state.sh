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

review_state_path() {
    printf '%s/.claude/state/review-base-%s-%s' "$HOME" "$(repo_hash "$1")" \
        "$(printf '%s' "$2" | portable_md5)"
}

# The baseline is the working tree at session start, not HEAD: changes that were
# already uncommitted when the session opened are not this session's work. An
# approval advances it to the reviewed staged tree. It only drives reminders; the
# commit gate judges the index against HEAD and needs no baseline.
review_init_baseline() {
    local path tree
    path=$(review_state_path "$1" "$2")
    mkdir -p "$(dirname "$path")"
    [ -s "$path" ] && return 0
    tree=$(review_snapshot "$1") || return 1
    # noclobber preserves the original baseline on resume/compact.
    (set -o noclobber; printf '%s\n' "$tree" > "$path") 2>/dev/null || [ -s "$path" ]
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
    [ "$approval" = "$(review_stop_approval_id "$1" "$2")" ] || return 1
    [ "$seen" = "$3" ] && return 0
    [ $(( now - at )) -lt "${AUTO_REVIEW_STOP_COOLDOWN:-1200}" ]
}

review_stop_approval_id() {
    local path
    path=$(review_state_path "$1" "$2")
    if [ -s "$path" ]; then portable_md5 < "$path"; else printf 'none\n'; fi
}

review_stop_record() {
    printf '%s %s %s\n' "$3" "$(date +%s)" "$(review_stop_approval_id "$1" "$2")" > "$(review_stop_state_path "$1" "$2")"
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

# review_session_paths <repo> <session>
# Repo-relative paths this session wrote through Edit/Write (dirty-<session>.log).
review_session_paths() {
    local log="$HOME/.claude/state/dirty-$2.log"
    [ -f "$log" ] || return 0
    _review_resolve "$1" "$log"
}

# Logged paths may go through symlinks (~/.claude -> dotfiles); Git reports the
# physical toplevel, so resolve before stripping the repository prefix.
_review_resolve() {
    local repo="$1" path
    shift
    cat "$@" 2>/dev/null | LC_ALL=C sort -u | while IFS= read -r path; do
        [ -n "$path" ] || continue
        path=$(realpath -m -- "$path" 2>/dev/null || _review_realpath "$path")
        case "$path" in "$repo"/*) printf '%s\n' "${path#"$repo"/}" ;; esac
    done | LC_ALL=C sort -u
}

# Portable `realpath -m` (macOS realpath has no -m): follows a symlinked file,
# then resolves the nearest existing ancestor and keeps the missing tail.
_review_realpath() {
    local path="$1" link dir tail="" hops=0
    while [ -L "$path" ] && [ $hops -lt 40 ]; do
        link=$(readlink "$path") || break
        case "$link" in /*) path="$link" ;; *) path="$(dirname -- "$path")/$link" ;; esac
        hops=$((hops + 1))
    done
    dir=$(dirname -- "$path")
    while [ ! -d "$dir" ] && [ "$dir" != / ]; do
        tail="/$(basename -- "$dir")$tail"
        dir=$(dirname -- "$dir")
    done
    dir=$(cd -P -- "$dir" 2>/dev/null && pwd -P) || { printf '%s' "$1"; return; }
    printf '%s%s/%s' "${dir%/}" "$tail" "$(basename -- "$path")"
}

# Repositories this session wrote to through Edit/Write, plus its cwd repository.
review_session_repos() {
    local session="$1" cwd="$2" path dir
    {
        git -C "$cwd" rev-parse --show-toplevel 2>/dev/null
        LC_ALL=C sort -u "$HOME/.claude/state/dirty-$session.log" 2>/dev/null | while IFS= read -r path; do
            dir=$(dirname -- "$path")
            while [ ! -d "$dir" ] && [ "$dir" != / ]; do dir=$(dirname -- "$dir"); done
            git -C "$dir" rev-parse --show-toplevel 2>/dev/null
        done
    } | awk 'NF && !seen[$0]++'
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

# review_session_range <repo> <session>
# Print "<base> <tree>" for this session's reminder scope: its baseline (HEAD in a
# repository it has none for, e.g. a second repo) against the working tree.
review_session_range() {
    local base tree
    base=$(review_baseline "$1" "$2" 2>/dev/null) || base=$(review_head_tree "$1") || return 1
    git -C "$1" cat-file -e "${base}^{tree}" 2>/dev/null || return 1
    tree=$(review_snapshot "$1") || return 1
    printf '%s %s\n' "$base" "$tree"
}

# review_required <repo> <session> [staged|session]
# Repository changes, not tool calls or line counts, determine review eligibility.
#   staged  (commit gate): what save.sh commits, HEAD -> index. Bash edits leave no
#           log, so every staged path counts whoever wrote it.
#   session (Stop/prompt reminders): files this session wrote through Edit/Write
#           that changed since its baseline. Other sessions' edits never count.
review_required() {
    local repo="$1" session="$2" scope="${3:-staged}" base tree path listed=$'\n'
    [ ! -f "$HOME/.claude/state/codex-delegate-pending-$(repo_hash "$repo")" ] || return 0
    if [ "$scope" = session ]; then
        read -r base tree < <(review_session_range "$repo" "$session") || return 1
        listed+="$(review_session_paths "$repo" "$session")"$'\n'
        [ "$listed" != $'\n\n' ] || return 1
    else
        base=$(review_head_tree "$repo") || return 1
        tree=$(review_index_tree "$repo") || return 1
    fi
    while IFS= read -r -d '' path; do
        [ "$scope" != session ] || [[ "$listed" == *$'\n'"$path"$'\n'* ]] || continue
        review_path_needs_review "$repo" "$path" && return 0
    done < <(git -C "$repo" diff --name-only -z "$base" "$tree")
    return 1
}

# review_session_fingerprint <repo> <session>
# Identity of this session's pending work, for reminder de-duplication. A whole
# working-tree snapshot changed on every edit by another session, re-arming them.
review_session_fingerprint() {
    local base tree path
    local -a paths=()
    read -r base tree < <(review_session_range "$1" "$2") || { printf 'none\n'; return; }
    while IFS= read -r path; do paths+=("$path"); done < <(review_session_paths "$1" "$2")
    [ ${#paths[@]} -gt 0 ] || { printf 'none\n'; return; }
    git -C "$1" diff --no-ext-diff --no-textconv "$base" "$tree" -- "${paths[@]}" | portable_md5
}
