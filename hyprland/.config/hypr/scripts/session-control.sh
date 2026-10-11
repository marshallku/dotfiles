#!/usr/bin/env bash
set -euo pipefail

scripts="$(dirname "$(readlink -f "$0")")"

presence() {
    if [[ -x "$HOME/.local/bin/coctl" ]]; then
        "$HOME/.local/bin/coctl" presence "$1" || printf 'Unable to update copad presence\n' >&2
    fi
}

case "${1:-}" in
    away)
        presence away
        ;;
    request-lock)
        systemctl --user import-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP HYPRLAND_INSTANCE_SIGNATURE \
            || printf 'Unable to import session environment\n' >&2
        systemctl --user start hypridle.service || printf 'Unable to start hypridle; locking directly\n' >&2
        exec "$0" lock
        ;;
    lock)
        exec 9>"${XDG_RUNTIME_DIR:?}/desktop-lock.lock"
        flock -n 9 || exit 0
        if pidof hyprlock >/dev/null; then
            exit 0
        fi
        presence away
        systemctl --user start hypridle-locked.service || printf 'Unable to start lock-screen idle timer\n' >&2
        if hyprlock; then
            "$0" unlocked
        else
            systemctl --user stop hypridle-locked.service || printf 'Unable to stop lock-screen idle timer\n' >&2
            notify-send -u critical 'Screen lock failed' 'hyprlock exited unsuccessfully. Check the session logs.'
            exit 1
        fi
        ;;
    locked)
        systemctl --user start hypridle-locked.service
        presence away
        ;;
    unlocked)
        systemctl --user stop hypridle-locked.service
        "$scripts/hypr-do.sh" dpms on || printf 'Unable to wake displays\n' >&2
        presence active
        ;;
    resumed)
        if ! pidof hyprlock >/dev/null; then
            presence active
        fi
        ;;
    *)
        printf 'Usage: %s request-lock|lock|locked|unlocked|away|resumed\n' "$0" >&2
        exit 64
        ;;
esac
