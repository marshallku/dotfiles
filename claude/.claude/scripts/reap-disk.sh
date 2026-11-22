#!/usr/bin/env bash
# reap-disk.sh — find disk that piles up by itself and move it to the trash. Linux and macOS.
#
#   reap-disk.sh              dry run: list candidates and what would be reclaimed
#   reap-disk.sh --apply      move `trash` candidates to the trash; `list` candidates stay
#   reap-disk.sh --quiet      no table, summary line only (scheduled runs)
#
# Built-in targets (all regenerable, all moved to the trash, never deleted):
#   chrome-clone   macOS: $TMPDIR/../X/com.google.Chrome.code_sign_clone/* older than 1 h with no
#                  file open (lsof). Chrome leaves a multi-GB copy per launch when killed.
#   claude-scratch Claude Code session scratchpads (/tmp/claude-<uid>/<project>/<session>) with
#                  nothing modified for 3 days.
# Listed only (never moved — a human decides):
#   worktree       linked git worktrees under the roots in ~/.config/reap-disk/worktree-roots
#                  (default ~/dev ~/workspace) that are clean and whose branch is merged
#                  (an ancestor of origin's default branch, or a merged PR per gh).
#   docker         reclaimable build cache (`docker system df`).
# Private, machine-local targets (company agent temp dirs and the like):
#   ~/.config/reap-disk/targets, one `<path glob> <days>` per line (`#` comments). Matches with
#   nothing modified for <days> days are trash candidates.
#
# Writes ~/.claude/state/reap-disk.json {ts, mode, reclaimable_kb, reclaimed_kb, items[]} for the
# statusline/AIDE. Scheduled daily by reap-disk-install.sh (launchd / systemd --user), because a
# clean-up a person has to remember to run does not run.

set -uo pipefail

. "$(dirname "$0")/../hooks/_lib.sh"

APPLY=0
QUIET=0
for arg in "$@"; do
    case "$arg" in
        --apply) APPLY=1 ;;
        --quiet) QUIET=1 ;;
        -h|--help) awk 'NR > 1 && !/^#/ { exit } NR > 1' "$0"; exit 0 ;;
        *) echo "[reap-disk] unknown argument: $arg" >&2; exit 2 ;;
    esac
done

CONFIG_DIR="${REAP_DISK_CONFIG:-$HOME/.config/reap-disk}"
STATE_FILE="${REAP_DISK_STATE:-$HOME/.claude/state/reap-disk.json}"
CHROME_MIN_AGE_MIN=60
SCRATCH_DAYS=3
GH_SECONDS=10
ITEMS=$(mktemp "${TMPDIR:-/tmp}/reap-disk.XXXXXX") || exit 2
trap 'rm -f "$ITEMS"' EXIT

size_kb() { du -sk "$1" 2>/dev/null | awk '{print $1+0}'; }
# Nothing under PATH was modified within DAYS days. A find that fails (an unreadable subdirectory
# can hide a recent file) proves nothing, so it counts as busy.
idle_for_days() {
    local recent
    recent=$(find "$1" -mtime "-$2" -print -quit 2>/dev/null) || return 1
    [ -z "$recent" ]
}

# unique_dest DIR NAME — a path in DIR that does not exist yet (moves never overwrite).
unique_dest() {
    local dir="$1" base="$2" n=0 candidate
    while :; do
        candidate="$dir/$base.$(date +%Y%m%d%H%M%S).$$.$n"
        [ -e "$candidate" ] || { printf '%s\n' "$candidate"; return 0; }
        n=$(( n + 1 ))
    done
}
# move_new SRC DEST — mv that refuses to replace an existing DEST.
move_new() { [ ! -e "$2" ] && mv -n "$1" "$2" && [ ! -e "$1" ]; }
add() { printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$(size_kb "$2")" "$3" >> "$ITEMS"; }

trash_path() {
    local path="$1"
    # Tests (and anyone who wants a staging area) can redirect the trash.
    if [ -n "${REAP_DISK_TRASH_DIR:-}" ]; then
        mkdir -p "$REAP_DISK_TRASH_DIR" && move_new "$path" "$(unique_dest "$REAP_DISK_TRASH_DIR" "$(basename "$path")")"
        return
    fi
    if [ "$(uname -s)" = Darwin ]; then
        if [ -x /usr/bin/trash ]; then /usr/bin/trash "$path" 2>/dev/null && return 0; fi
        mkdir -p "$HOME/.Trash" && move_new "$path" "$(unique_dest "$HOME/.Trash" "$(basename "$path")")"
        return
    fi
    if command -v gio >/dev/null 2>&1 && gio trash "$path" 2>/dev/null; then return 0; fi
    # freedesktop.org trash spec, home trash only.
    local trash="${XDG_DATA_HOME:-$HOME/.local/share}/Trash" name
    mkdir -p "$trash/files" "$trash/info" || return 1
    name=$(basename "$(unique_dest "$trash/files" "$(basename "$path")")")
    printf '[Trash Info]\nPath=%s\nDeletionDate=%s\n' "$path" "$(date +%Y-%m-%dT%H:%M:%S)" \
        > "$trash/info/$name.trashinfo" || return 1
    move_new "$path" "$trash/files/$name" || { rm -f "$trash/info/$name.trashinfo"; return 1; }
}

scan_chrome_clones() {
    [ "$(uname -s)" = Darwin ] || return 0
    local root="${REAP_DISK_CHROME_ROOT:-${TMPDIR:-/tmp}/../X/com.google.Chrome.code_sign_clone}" dir
    [ -d "$root" ] || return 0
    # In use = this user's processes hold a file open inside the copy; Chrome runs from
    # /Applications, so its command line never names the clone. No lsof, or a non-zero exit
    # (partial output), skips the target.
    command -v lsof >/dev/null 2>&1 || return 0
    local open real
    open=$(lsof -n -Fn -u "$(id -u)" 2>/dev/null) || return 0
    open=$(printf '%s\n' "$open" | sed -n 's/^n//p')
    for dir in "$root"/*; do
        [ -d "$dir" ] || continue
        [ -n "$(find "$dir" -maxdepth 0 -mmin "+$CHROME_MIN_AGE_MIN" 2>/dev/null)" ] || continue
        # lsof prints resolved paths (/private/var/… on macOS).
        real=$(cd "$dir" 2>/dev/null && pwd -P) || continue
        # Here-string, not a pipe: grep -q exits on the first match, and under pipefail the
        # writer's SIGPIPE would turn "in use" into "not in use".
        grep -qF -- "$real/" <<< "$open" && continue
        add chrome-clone "$dir" trash
    done
}

scan_claude_scratch() {
    local root="${REAP_DISK_SCRATCH_ROOT:-/tmp/claude-$(id -u)}" session
    [ -d "$root" ] || return 0
    for session in "$root"/*/*; do
        [ -d "$session" ] || continue
        idle_for_days "$session" "$SCRATCH_DAYS" && add claude-scratch "$session" trash
    done
}

scan_config_targets() {
    local file="$CONFIG_DIR/targets" pattern days match
    [ -f "$file" ] || return 0
    while read -r pattern days _ || [ -n "$pattern" ]; do
        case "$pattern" in ''|'#'*) continue ;; esac
        case "$days" in ''|*[!0-9]*) echo "[reap-disk] skip '$pattern': days must be a number" >&2; continue ;; esac
        pattern="${pattern/#\~/$HOME}"
        # Glob expansion of a user-written pattern; nothing matched leaves it unexpanded.
        for match in $pattern; do
            [ -e "$match" ] || continue
            idle_for_days "$match" "$days" && add config "$match" trash
        done
    done < "$file"
}

worktree_merged() {
    local wt="$1" branch="$2" base
    base=$(git -C "$wt" symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null)
    if [ -n "$base" ] && git -C "$wt" merge-base --is-ancestor "$branch" "$base" 2>/dev/null; then
        return 0
    fi
    command -v gh >/dev/null 2>&1 || return 1
    local merged
    merged=$( cd "$wt" && portable_timeout "$GH_SECONDS" gh pr list --head "$branch" --state merged \
        --json number --jq length 2>/dev/null )
    [ "${merged:-0}" -gt 0 ] 2>/dev/null
}

scan_worktrees() {
    command -v git >/dev/null 2>&1 || return 0
    local roots_file="$CONFIG_DIR/worktree-roots" roots=() root repo line wt branch
    if [ -f "$roots_file" ]; then
        while read -r root || [ -n "$root" ]; do
            case "$root" in ''|'#'*) continue ;; esac
            roots+=("${root/#\~/$HOME}")
        done < "$roots_file"
    else
        roots=("$HOME/dev" "$HOME/workspace")
    fi
    for root in "${roots[@]}"; do
        for repo in "$root"/*/; do
            [ -d "$repo/.git" ] || continue
            wt=""
            while IFS= read -r line; do
                case "$line" in
                    "worktree "*) wt="${line#worktree }"; branch="" ;;
                    "branch refs/heads/"*) branch="${line#branch refs/heads/}" ;;
                    "")
                        if [ -n "$wt" ] && [ -n "$branch" ] && [ "$wt/" != "$repo" ] && [ -d "$wt" ] \
                            && [ -z "$(git -C "$wt" status --porcelain 2>/dev/null)" ] \
                            && worktree_merged "$wt" "$branch"; then
                            add worktree "$wt" list
                        fi
                        wt="" ;;
                esac
            done < <(git -C "$repo" worktree list --porcelain 2>/dev/null; echo)
        done
    done
}

scan_docker() {
    command -v docker >/dev/null 2>&1 || return 0
    local reclaim
    reclaim=$(portable_timeout 15 docker system df --format '{{.Type}}\t{{.Reclaimable}}' 2>/dev/null \
        | awk -F'\t' '$1 == "Build Cache" {print $2}')
    case "$reclaim" in ""|0B|"0B "*) return 0 ;; esac
    printf 'docker\tbuild cache (docker builder prune): %s\t0\tlist\n' "$reclaim" >> "$ITEMS"
}

scan_chrome_clones
scan_claude_scratch
scan_config_targets
scan_worktrees
scan_docker

RECLAIMABLE=0
RECLAIMED=0
REPORT=$(mktemp "${TMPDIR:-/tmp}/reap-disk.XXXXXX") || exit 2
trap 'rm -f "$ITEMS" "$REPORT"' EXIT
while IFS=$'\t' read -r target path kb action; do
    result="$action"
    if [ "$action" = trash ]; then
        RECLAIMABLE=$(( RECLAIMABLE + kb ))
        if [ "$APPLY" = 1 ]; then
            if trash_path "$path"; then
                result=trashed
                RECLAIMED=$(( RECLAIMED + kb ))
            else
                result=failed
            fi
        fi
    fi
    printf '%s\t%s\t%s\t%s\n' "$target" "$path" "$kb" "$result" >> "$REPORT"
    [ "$QUIET" = 1 ] || printf '%-15s %8s MB  %-8s %s\n' "$target" "$(( kb / 1024 ))" "$result" "$path"
done < "$ITEMS"

MODE=$([ "$APPLY" = 1 ] && echo apply || echo dry-run)
mkdir -p "$(dirname "$STATE_FILE")" 2>/dev/null
jq -Rn --arg ts "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" --arg mode "$MODE" \
    --argjson reclaimable "$RECLAIMABLE" --argjson reclaimed "$RECLAIMED" '
    {ts: $ts, mode: $mode, reclaimable_kb: $reclaimable, reclaimed_kb: $reclaimed,
     items: [inputs | split("\t") | {target: .[0], path: .[1], kb: (.[2] | tonumber? // 0), result: .[3]}]}
' < "$REPORT" > "$STATE_FILE.tmp" 2>/dev/null && mv -f "$STATE_FILE.tmp" "$STATE_FILE"
hook_event reap-disk run mode="$MODE" reclaimable_kb="$RECLAIMABLE" reclaimed_kb="$RECLAIMED"

if [ "$APPLY" = 1 ]; then
    echo "reap-disk: moved $(( RECLAIMED / 1024 )) MB to the trash ($(wc -l < "$REPORT" | tr -d " ") candidates)"
else
    echo "reap-disk: $(( RECLAIMABLE / 1024 )) MB reclaimable (dry run; --apply moves it to the trash)"
fi
