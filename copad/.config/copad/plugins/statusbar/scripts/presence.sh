#!/usr/bin/env bash
# copad statusbar module: presence indicator. Shows AWAY only — when the
# user has toggled away, copad's external notification sinks (Discord
# etc.) are armed, which is the state worth a visible reminder. Blank
# when active so the default state stays clean. copad-native: nothing
# else surfaces this toggle.
#
# coctl by absolute path (daemon PATH lacks ~/.local/bin).
set -u

coctl="$HOME/.local/bin/coctl"
[[ -x "$coctl" ]] || exit 0

state=$("$coctl" presence status 2>/dev/null | head -n1 | tr -d '[:space:]')
[[ "$state" == "away" ]] || exit 0

# U+F04B2 sleep glyph + trailing space.
printf '{"text":"󰒲 away ","tooltip":"away — external notification sinks armed"}\n'
