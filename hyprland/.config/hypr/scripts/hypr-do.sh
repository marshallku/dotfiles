#!/usr/bin/env bash
# Executable front end for hyprctl-compat.sh.
#
# Exists because several hyprctl call sites are not shell scripts — waybar's
# config.jsonc, copad's config.toml, hypridle.conf — and so cannot source a
# library. They run this instead:
#
#   ~/.config/hypr/scripts/hypr-do.sh workspace 3
#
# A separate file rather than a `$0`-guarded block inside the library: zsh
# rewrites "$0" to the sourced file's name (FUNCTION_ARGZERO), so that guard
# fires on a plain `. hyprctl-compat.sh` and is not worth the cleverness.
set -u

# shellcheck source=hyprctl-compat.sh
. "$(dirname "$(readlink -f "$0")")/hyprctl-compat.sh"

verb="${1:-}"
[ $# -gt 0 ] && shift

case "$verb" in
    workspace)    hypr_workspace "$1" ;;
    dpms)         hypr_dpms "$1" "${2:-}" ;;
    submap)       hypr_submap "$1" ;;
    exec)         hypr_exec "$*" ;;
    focus-window) hypr_focus_window "$1" ;;
    resize-px)    hypr_resize_px "$1" "$2" "$3" ;;
    monitor)      hypr_monitor_apply "$1" "$2" ;;
    *)
        cat >&2 <<'USAGE'
usage: hypr-do.sh <verb> [args]

  workspace ID                 focus a workspace (3, "e+1", a name)
  dpms on|off|toggle [MON]     set display power
  submap NAME                  enter a submap ("reset" leaves)
  exec CMD                     spawn CMD as a compositor child
  focus-window SELECTOR        focus a window ("pid:1234", "class:foo")
  resize-px DX DY SELECTOR     nudge a window by pixels
  monitor OUTPUT SPEC          re-commit an output ("disable" or "MODE,POS,SCALE")
USAGE
        exit 64
        ;;
esac
