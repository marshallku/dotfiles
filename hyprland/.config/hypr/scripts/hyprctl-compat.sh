#!/usr/bin/env bash
# Shared hyprctl shims for the hyprlang -> Lua config transition.
#
# Hyprland 0.55 deprecated the .conf config format (hyprlang) and 0.57 removes
# it outright (commit a9902ea6). Under the Lua config manager hyprctl's
# subcommands change shape:
#
#   legacy:  hyprctl dispatch submap reset
#   lua:     hyprctl dispatch 'hl.dsp.submap("reset")'
#
#   legacy:  hyprctl keyword monitor "DP-1,disable"
#   lua:     hyprctl eval 'hl.monitor({ output = "DP-1", disabled = true })'
#            ("keyword can't work with non-legacy parsers. Use eval.")
#
# Which form a running instance accepts is fixed when the compositor starts, so
# a machine that has hyprland.lua on disk but has not restarted yet still needs
# the legacy form. These helpers try Lua first and fall back, which keeps every
# call site working across the restart and across a rollback.
#
# hyprctl exits 0 even when it rejects a request, so they branch on its stdout.

# Error replies that mean "wrong config manager, try the other form".
_hypr_rejected() {
    case "$1" in
        "Invalid dispatcher"* | "Bad dispatcher"* | *"only supported with"* | *"can't work with non-legacy"*)
            return 0
            ;;
    esac
    return 1
}

# hypr_dispatch <lua-expression> <legacy-dispatcher> [legacy-args...]
#
# A rejected Lua expression is a no-op, so attempting it first is free.
hypr_dispatch() {
    local lua="$1"
    shift

    if _hypr_rejected "$(hyprctl dispatch "$lua" 2>/dev/null)"; then
        hyprctl dispatch "$@" >/dev/null 2>&1
        return
    fi
}

# hypr_submap <name>   — "reset" leaves the current submap.
hypr_submap() {
    hypr_dispatch "hl.dsp.submap(\"$1\")" submap "$1"
}

# hypr_exec <command>  — spawn as a compositor child so it inherits the session.
hypr_exec() {
    hypr_dispatch "hl.dsp.exec_cmd(\"$1\")" exec "$1"
}

# hypr_focus_window <selector>  — e.g. "pid:1234". Returns non-zero if unfocused.
hypr_focus_window() {
    hypr_dispatch "hl.dsp.focus({ window = \"$1\" })" focuswindow "$1"
}

# hypr_monitor_apply <output> <spec>
#
# <spec> is the hyprlang monitor tail: "disable", or "MODE,POSITION,SCALE"
# (e.g. "3440x1440@99.99,0x0,1" / "preferred,auto,1"). Returns non-zero when
# neither form was accepted, so callers can report instead of silently no-oping.
hypr_monitor_apply() {
    local output="$1" spec="$2" lua out

    if [ "$spec" = "disable" ]; then
        lua="hl.monitor({ output = \"$output\", disabled = true })"
    else
        local mode="${spec%%,*}" rest="${spec#*,}"
        local position="${rest%%,*}" scale="${rest#*,}"
        lua="hl.monitor({ output = \"$output\", mode = \"$mode\", position = \"$position\", scale = $scale })"
    fi

    out="$(hyprctl eval "$lua" 2>/dev/null)"

    if ! _hypr_rejected "$out"; then
        case "$out" in
            *error* | *Error* | *ERROR*) return 1 ;;
            *) return 0 ;;
        esac
    fi

    out="$(hyprctl keyword monitor "$output,$spec" 2>/dev/null)"
    [ "$out" = "ok" ]
}
