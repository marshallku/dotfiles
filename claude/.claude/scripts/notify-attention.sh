#!/usr/bin/env bash
# Cross-platform OS notification + attention-queue producer.
#
# Used by:
#   - hooks/notify-stop.sh       (Claude Stop event)
#   - hooks/notify-notification.sh (Claude Notification event: permission / idle)
#   - hooks/notify-codex.sh      (codex agent-turn-complete)
#
# Side effects:
#   1. Appends a JSON line to $XDG_CACHE_HOME/claude-attention/queue.jsonl
#      so `jump-attention.sh` can switch to the source tmux session by hotkey,
#      independent of the OS notification's click action (notification can
#      auto-dismiss; the queue entry stays for 1h).
#   2. Dispatches a platform notification:
#        - macOS: terminal-notifier (click → activate term + tmux switch-client),
#                 osascript fallback (no click action).
#        - Linux: dunstify (default-action → focus term + tmux switch-client),
#                 notify-send fallback (no click action).

set -u

. "$(dirname "$0")/../hooks/_lib.sh"

kind=""
source_app=""
title=""
body=""
session_id=""
hook_cwd=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --kind) kind="$2"; shift 2 ;;
        --source) source_app="$2"; shift 2 ;;
        --title) title="$2"; shift 2 ;;
        --body) body="$2"; shift 2 ;;
        --session) session_id="$2"; shift 2 ;;
        --cwd) hook_cwd="$2"; shift 2 ;;
        *) shift ;;
    esac
done

[[ -z "$kind" || -z "$source_app" || -z "$title" ]] && {
    echo "notify-attention: missing required --kind/--source/--title" >&2
    exit 2
}

# --- tmux detection ---
tmux_session=""
tmux_window_idx=""
tmux_window_name=""
tmux_target=""
tmux_socket=""
tmux_bin=""
tmux_client_pid=""
terminal_pid=""

find_terminal_pid() {
    local pid="${1:-}"
    [[ -z "$pid" ]] && return
    local depth=0 comm
    while [[ -n "$pid" && "$pid" != "1" && "$pid" != "0" && "$depth" -lt 12 ]]; do
        comm=$(ps -o comm= -p "$pid" 2>/dev/null | awk '{print $1}')
        case "$comm" in
            kitty|ghostty|alacritty|foot|wezterm-gui|wezterm|st|urxvt|rxvt|xterm|\
konsole|terminator|tilix|nestty|turm|sakura|hyper|tilda|guake|gnome-terminal*|\
io.elementary.terminal|qterminal|cool-retro-term|Terminal|iTerm2|WezTerm)
                echo "$pid"
                return
                ;;
        esac
        pid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
        depth=$((depth + 1))
    done
}

if [[ -n "${TMUX:-}" ]] && command -v tmux >/dev/null 2>&1; then
    tmux_session=$(tmux display-message -p '#S' 2>/dev/null) || tmux_session=""
    tmux_window_idx=$(tmux display-message -p '#I' 2>/dev/null) || tmux_window_idx=""
    tmux_window_name=$(tmux display-message -p '#W' 2>/dev/null) || tmux_window_name=""
    if [[ -n "$tmux_session" && -n "$tmux_window_idx" ]]; then
        tmux_target="${tmux_session}:${tmux_window_idx}"
        tmux_socket="${TMUX%%,*}"
        tmux_bin=$(command -v tmux)
        tmux_client_pid=$(tmux display-message -p '#{client_pid}' 2>/dev/null) || tmux_client_pid=""
        terminal_pid=$(find_terminal_pid "$tmux_client_pid")
    fi
fi

# --- queue push ---
queue_dir="${XDG_CACHE_HOME:-$HOME/.cache}/claude-attention"
queue_file="$queue_dir/queue.jsonl"
mkdir -p "$queue_dir"

now=$(date +%s)
entry=$(jq -nc \
    --argjson ts "$now" \
    --arg kind "$kind" \
    --arg source "$source_app" \
    --arg title "$title" \
    --arg body "$body" \
    --arg session_id "$session_id" \
    --arg cwd "$hook_cwd" \
    --arg tmux_session "$tmux_session" \
    --arg tmux_window_idx "$tmux_window_idx" \
    --arg tmux_window_name "$tmux_window_name" \
    --arg tmux_target "$tmux_target" \
    --arg tmux_socket "$tmux_socket" \
    --arg tmux_bin "$tmux_bin" \
    --arg tmux_client_pid "$tmux_client_pid" \
    --arg terminal_pid "$terminal_pid" \
    '{ts:$ts, kind:$kind, source:$source, title:$title, body:$body,
      session_id:$session_id, cwd:$cwd,
      tmux_session:$tmux_session, tmux_window_idx:$tmux_window_idx,
      tmux_window_name:$tmux_window_name, tmux_target:$tmux_target,
      tmux_socket:$tmux_socket, tmux_bin:$tmux_bin,
      tmux_client_pid:$tmux_client_pid, terminal_pid:$terminal_pid}' 2>/dev/null)

if [[ -n "$entry" ]]; then
    # Trim entries older than 1h before appending. Atomic via temp+rename.
    cutoff=$((now - 3600))
    if [[ -f "$queue_file" ]]; then
        awk -v c="$cutoff" '
            match($0, /"ts":[0-9]+/) {
                ts = substr($0, RSTART+5, RLENGTH-5) + 0
                if (ts >= c) print
            }' "$queue_file" > "${queue_file}.tmp" 2>/dev/null \
            && mv "${queue_file}.tmp" "$queue_file"
    fi
    printf '%s\n' "$entry" >> "$queue_file"
fi

# --- notification dispatch ---
applescript_escape() {
    printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

sh_squote() {
    local s=${1//\'/\'\\\'\'}
    printf "'%s'" "$s"
}

# subtitle line that gets appended to body (Linux) or set as --subtitle (macOS)
subtitle=""
[[ -n "$tmux_target" ]] && subtitle="tmux: ${tmux_target}${tmux_window_name:+ ${tmux_window_name}}"

tmux_switch_cmd() {
    [[ -z "$tmux_target" || -z "$tmux_bin" || -z "$tmux_socket" ]] && return
    local q_socket q_target q_bin
    q_socket=$(sh_squote "$tmux_socket")
    q_target=$(sh_squote "$tmux_target")
    q_bin=$(sh_squote "$tmux_bin")
    if [[ -n "$tmux_client_pid" ]]; then
        printf '%s' "ctty=\$(${q_bin} -S ${q_socket} list-clients -F '#{client_tty} #{client_pid}' 2>/dev/null | awk -v p='${tmux_client_pid}' '\$2==p {print \$1; exit}'); ${q_bin} -S ${q_socket} switch-client \${ctty:+-c \"\$ctty\"} -t ${q_target} >/dev/null 2>&1"
    else
        printf '%s' "${q_bin} -S ${q_socket} switch-client -t ${q_target} >/dev/null 2>&1"
    fi
}

focus_terminal_linux() {
    local pid="${1:-}"
    [[ -z "$pid" ]] && return
    if [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]] && command -v hyprctl >/dev/null 2>&1; then
        hyprctl dispatch focuswindow "pid:$pid" >/dev/null 2>&1 && return
    fi
    if command -v wmctrl >/dev/null 2>&1; then
        local wid
        wid=$(wmctrl -lp 2>/dev/null | awk -v p="$pid" '$3 == p { print $1; exit }')
        [[ -n "$wid" ]] && wmctrl -ia "$wid" >/dev/null 2>&1
    fi
}

case "$(uname -s)" in
    Darwin)
        bundle=""
        case "${TERM_PROGRAM:-}" in
            iTerm.app) bundle="com.googlecode.iterm2" ;;
            Apple_Terminal) bundle="com.apple.Terminal" ;;
            WezTerm) bundle="com.github.wez.wezterm" ;;
            ghostty) bundle="com.mitchellh.ghostty" ;;
            *) bundle="${__CFBundleIdentifier:-}" ;;
        esac
        if command -v terminal-notifier >/dev/null 2>&1; then
            args=(-title "$title" -message "$body" -sound Glass)
            [[ -n "$subtitle" ]] && args+=(-subtitle "$subtitle")
            switch=$(tmux_switch_cmd)
            if [[ -n "$switch" ]]; then
                exec_cmd=""
                [[ -n "$bundle" ]] && exec_cmd="/usr/bin/osascript -e 'tell application id \"${bundle}\" to activate' >/dev/null 2>&1; "
                exec_cmd+="$switch"
                args+=(-execute "$exec_cmd")
            elif [[ -n "$bundle" ]]; then
                args+=(-activate "$bundle")
            fi
            terminal-notifier "${args[@]}" >/dev/null 2>&1 || true
        elif command -v osascript >/dev/null 2>&1; then
            osascript -e "display notification \"$(applescript_escape "$body")\" with title \"$(applescript_escape "$title")\"${subtitle:+ subtitle \"$(applescript_escape "$subtitle")\"}" >/dev/null 2>&1 || true
        fi
        ;;
    Linux)
        (
            full_body="$body"
            [[ -n "$subtitle" ]] && full_body+=$'\n'"$subtitle"
            action=""
            if command -v dunstify >/dev/null 2>&1 && [[ -n "$tmux_target" ]]; then
                action=$(dunstify -a "claude-attention" -u normal -t 8000 \
                    --action="default,Jump to session" \
                    "$title" "$full_body" 2>/dev/null) || true
            elif command -v dunstify >/dev/null 2>&1; then
                dunstify -a "claude-attention" -u normal -t 8000 "$title" "$full_body" >/dev/null 2>&1 || true
            elif command -v notify-send >/dev/null 2>&1; then
                notify-send -a "claude-attention" -u normal -t 8000 "$title" "$full_body" >/dev/null 2>&1 || true
            fi
            if [[ "$action" == "default" ]]; then
                focus_terminal_linux "$terminal_pid"
                switch=$(tmux_switch_cmd)
                [[ -n "$switch" ]] && bash -c "$switch"
            fi
        ) </dev/null >/dev/null 2>&1 &
        ;;
esac

exit 0
