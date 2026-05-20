#!/usr/bin/env bash
# fzf picker over the attention queue.
#
# Default invocation (no args): launch fzf with list + preview + bindings.
# Subcommands (used internally by fzf's reload/preview/execute hooks):
#   list                   one line per fresh entry, TS-prefixed (TAB-delimited)
#   preview <ts>           detail view of a single entry
#   delete <ts>            remove entry with given ts from queue (in place)
#   jump <ts>              remove entry then exec `tmx switch <session>`
#
# Bindings inside fzf:
#   Enter         jump to selected entry (consumes the entry)
#   Ctrl-D / Del  delete the selected entry without jumping, reload list
#   Esc           cancel, no change

set -u

queue="${XDG_CACHE_HOME:-$HOME/.cache}/claude-attention/queue.jsonl"
self="$(readlink -f "$0" 2>/dev/null || echo "$0")"

human_age() {
    local secs="$1"
    if   (( secs < 60 ));    then echo "${secs}s"
    elif (( secs < 3600 ));  then echo "$((secs/60))m"
    elif (( secs < 86400 )); then echo "$((secs/3600))h"
    else                          echo "$((secs/86400))d"
    fi
}

cmd_list() {
    [[ -f "$queue" ]] || return 0
    local now cutoff
    now=$(date +%s)
    cutoff=$((now - 3600))
    # `tac` is GNU-only — macOS BSD coreutils don't ship it. Reverse via
    # awk so the picker shows newest-first on every platform.
    #
    # Field separator is ASCII Unit Separator ( / \037) rather than
    # TAB: bash's `read` treats tab as whitespace and collapses consecutive
    # ones, so an empty `tmux_session` would shift later fields and break
    # `human_age` (it sees the body text where it expects an integer and
    # `set -u` trips inside `(( secs < 60 ))`). US is non-whitespace and
    # cannot appear in JSON string content, so empty fields stay empty.
    awk '{ lines[NR] = $0 } END { for (i = NR; i > 0; i--) print lines[i] }' "$queue" \
      | jq -rc --argjson now "$now" --argjson cutoff "$cutoff" '
            select(.ts >= $cutoff)
            | "\(.ts)\(.source)·\(.kind)\(.tmux_session // "?")\($now - .ts)\((.body // "") | gsub("\n"; " ") | .[0:80])"
        ' 2>/dev/null \
      | while IFS=$'\037' read -r ts label session age body; do
            [[ -n "$session" ]] || session="—"
            printf "%s\t%-18s %-18s %4s  %s\n" \
                "$ts" "[$label]" "$session" "$(human_age "$age")" "$body"
        done
}

cmd_preview() {
    local ts="${1:-}"
    [[ -z "$ts" || ! -f "$queue" ]] && return 0
    jq -r --argjson ts "$ts" '
        select(.ts == $ts) |
        "Title:    \(.title // "")\n" +
        "Source:   \(.source // "?") · \(.kind // "?")\n" +
        "Session:  \(.tmux_session // "(none)")\n" +
        "Window:   \(.tmux_target // "(none)")\n" +
        "Cwd:      \(.cwd // "(none)")\n" +
        "When:     \(.ts | strftime("%H:%M:%S"))\n" +
        "---\n\(.body // "")"
    ' "$queue" 2>/dev/null
}

# Remove the queue entry with exactly this ts. Substring-anchored so we don't
# match e.g. ts 123 inside ts 1234567.
cmd_delete() {
    local ts="${1:-}"
    [[ -z "$ts" || ! -f "$queue" ]] && return 0
    awk -v t="\"ts\":${ts}," '
        # match either "ts":N, (followed by another field) or rare end-of-object case
        index($0, t) { next }
        { print }
    ' "$queue" > "${queue}.tmp" && mv "${queue}.tmp" "$queue"
}

cmd_jump() {
    local ts="${1:-}"
    [[ -z "$ts" || ! -f "$queue" ]] && return 0
    local session
    session=$(jq -r --argjson ts "$ts" 'select(.ts == $ts) | .tmux_session // ""' "$queue" 2>/dev/null)
    cmd_delete "$ts"
    [[ -z "$session" ]] && return 0
    if command -v tmx >/dev/null 2>&1; then
        exec tmx switch "$session"
    elif [[ -n "${TMUX:-}" ]]; then
        exec tmux switch-client -t "$session"
    else
        exec tmux attach-session -t "$session"
    fi
}

main() {
    if ! command -v fzf >/dev/null 2>&1; then
        echo "fzf not found; install fzf to use the picker" >&2
        exit 1
    fi
    if [[ ! -f "$queue" ]] || [[ -z "$(cmd_list)" ]]; then
        echo "no attention pending"
        # give the user 1.5s to see the message before the tmux popup closes
        sleep 1.5
        exit 0
    fi
    local selected ts
    selected=$(cmd_list | fzf \
        --ansi \
        --delimiter=$'\t' \
        --with-nth=2 \
        --no-multi \
        --reverse \
        --header='Enter: jump   Ctrl-D / Del: delete   Esc: cancel' \
        --preview="$self preview {1}" \
        --preview-window=right:55%:wrap \
        --bind="ctrl-d:execute-silent($self delete {1})+reload($self list)" \
        --bind="del:execute-silent($self delete {1})+reload($self list)")
    [[ -z "$selected" ]] && exit 0
    ts=$(printf '%s' "$selected" | cut -f1)
    [[ -z "$ts" ]] && exit 0
    cmd_jump "$ts"
}

case "${1:-}" in
    list)    shift; cmd_list ;;
    preview) shift; cmd_preview "$@" ;;
    delete)  shift; cmd_delete "$@" ;;
    jump)    shift; cmd_jump "$@" ;;
    *)       main ;;
esac
