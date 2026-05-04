#!/usr/bin/env bash
# Stop hook: OS notification when a turn finishes.
# - macOS: terminal-notifier (osascript fallback). Click activates the terminal app
#   AND switches the tmux client to the originating session:window.
# - Linux: dunstify (preferred) or notify-send. Click focuses the tmux-hosting
#   terminal window (hyprctl/wmctrl) AND switches the tmux client to session:window.
#
# Opt out: touch ~/.claude/state/notify-stop-disabled

set -u

[[ -f "$HOME/.claude/state/notify-stop-disabled" ]] && exit 0

. "$(dirname "$0")/_lib.sh"

input=$(cat 2>/dev/null || true)
session=$(echo "$input" | jq -r '.session_id // ""' 2>/dev/null)
hook_cwd=$(echo "$input" | jq -r '.cwd // ""' 2>/dev/null)
transcript=$(echo "$input" | jq -r '.transcript_path // ""' 2>/dev/null)
stop_active=$(echo "$input" | jq -r '.stop_hook_active // false' 2>/dev/null)

# Suppress on the first Stop fire if auto-cross-review is going to block it.
# Block-fire Claude continues, runs codex-review, re-Stops with stop_hook_active=true
# — that is the real "turn finished" moment to notify on.
if [[ "$stop_active" != "true" ]] && auto_review_would_block "$session" "$hook_cwd" "$transcript"; then
    exit 0
fi

cwd_name=$(basename "${hook_cwd:-$PWD}")
title="Claude · $cwd_name"
summary="Turn finished"

applescript_escape() {
    printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

sh_squote() {
    local s=${1//\'/\'\\\'\'}
    printf "'%s'" "$s"
}

find_terminal_pid() {
    local pid="${1:-}"
    [[ -z "$pid" ]] && return
    local depth=0 comm
    while [[ -n "$pid" && "$pid" != "1" && "$pid" != "0" && "$depth" -lt 12 ]]; do
        comm=$(ps -o comm= -p "$pid" 2>/dev/null | awk '{print $1}')
        case "$comm" in
            kitty|ghostty|alacritty|foot|wezterm-gui|wezterm|st|urxvt|rxvt|xterm|\
konsole|terminator|tilix|turm|sakura|hyper|tilda|guake|gnome-terminal*|\
io.elementary.terminal|qterminal|cool-retro-term|Terminal|iTerm2|WezTerm)
                echo "$pid"
                return
                ;;
        esac
        pid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
        depth=$((depth + 1))
    done
}

tmux_target=""
tmux_socket=""
tmux_bin=""
tmux_client_pid=""
terminal_pid=""
if [[ -n "${TMUX:-}" ]] && command -v tmux >/dev/null 2>&1; then
    session=$(tmux display-message -p '#S' 2>/dev/null) || session=""
    widx=$(tmux display-message -p '#I' 2>/dev/null) || widx=""
    wname=$(tmux display-message -p '#W' 2>/dev/null) || wname=""
    if [[ -n "$session" && -n "$widx" ]]; then
        tmux_target="${session}:${widx}"
        summary="[${tmux_target} ${wname}] turn finished"
        tmux_socket="${TMUX%%,*}"
        tmux_bin=$(command -v tmux)
        tmux_client_pid=$(tmux display-message -p '#{client_pid}' 2>/dev/null) || tmux_client_pid=""
        terminal_pid=$(find_terminal_pid "$tmux_client_pid")
    fi
fi

tmux_switch() {
    [[ -z "$tmux_target" || -z "$tmux_bin" || -z "$tmux_socket" ]] && return
    local ctty=""
    if [[ -n "$tmux_client_pid" ]]; then
        ctty=$("$tmux_bin" -S "$tmux_socket" list-clients -F '#{client_tty} #{client_pid}' 2>/dev/null \
            | awk -v p="$tmux_client_pid" '$2 == p { print $1; exit }')
    fi
    if [[ -n "$ctty" ]]; then
        "$tmux_bin" -S "$tmux_socket" switch-client -c "$ctty" -t "$tmux_target" 2>/dev/null
    else
        "$tmux_bin" -S "$tmux_socket" switch-client -t "$tmux_target" 2>/dev/null
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
            args=(-title "$title" -message "$summary" -sound Glass)
            [[ -n "$tmux_target" ]] && args+=(-subtitle "tmux: $tmux_target")
            if [[ -n "$tmux_target" && -n "$tmux_bin" && -n "$tmux_socket" ]]; then
                # On click: activate terminal app, then switch tmux client to target.
                # -execute takes precedence over -activate, so chain both in shell.
                q_socket=$(sh_squote "$tmux_socket")
                q_target=$(sh_squote "$tmux_target")
                q_bin=$(sh_squote "$tmux_bin")
                exec_cmd=""
                [[ -n "$bundle" ]] && exec_cmd="/usr/bin/osascript -e 'tell application id \"${bundle}\" to activate' >/dev/null 2>&1; "
                if [[ -n "$tmux_client_pid" ]]; then
                    exec_cmd+="ctty=\$(${q_bin} -S ${q_socket} list-clients -F '#{client_tty} #{client_pid}' 2>/dev/null | awk -v p='${tmux_client_pid}' '\$2==p {print \$1; exit}'); "
                    exec_cmd+="${q_bin} -S ${q_socket} switch-client \${ctty:+-c \"\$ctty\"} -t ${q_target} >/dev/null 2>&1"
                else
                    exec_cmd+="${q_bin} -S ${q_socket} switch-client -t ${q_target} >/dev/null 2>&1"
                fi
                args+=(-execute "$exec_cmd")
            elif [[ -n "$bundle" ]]; then
                args+=(-activate "$bundle")
            fi
            terminal-notifier "${args[@]}" >/dev/null 2>&1 || true
        elif command -v osascript >/dev/null 2>&1; then
            osascript -e "display notification \"$(applescript_escape "$summary")\" with title \"$(applescript_escape "$title")\"" >/dev/null 2>&1 || true
        fi
        ;;
    Linux)
        (
            body="$summary"
            [[ -n "$tmux_target" ]] && body+=$'\n'"tmux: $tmux_target"
            action=""
            if command -v dunstify >/dev/null 2>&1 && [[ -n "$tmux_target" ]]; then
                action=$(dunstify -a claude-code -u normal -t 8000 \
                    --action="default,Return to tmux" \
                    "$title" "$body" 2>/dev/null) || true
            elif command -v dunstify >/dev/null 2>&1; then
                dunstify -a claude-code -u normal -t 8000 "$title" "$body" >/dev/null 2>&1 || true
            elif command -v notify-send >/dev/null 2>&1; then
                notify-send -a claude-code -u normal -t 8000 "$title" "$body" >/dev/null 2>&1 || true
            fi
            if [[ "$action" == "default" ]]; then
                focus_terminal_linux "$terminal_pid"
                tmux_switch
            fi
        ) </dev/null >/dev/null 2>&1 &
        ;;
esac

exit 0
