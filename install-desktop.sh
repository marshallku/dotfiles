#!/usr/bin/env bash
# Repeatable desktop configuration for an already installed, updated Arch system.
set -euo pipefail

repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
check=false
install_packages=false
for arg in "$@"; do
    case "$arg" in
        --check) check=true ;;
        --install-packages) install_packages=true ;;
        --help|-h)
            cat <<'HELP'
Usage: bash install-desktop.sh [--check | --install-packages]
  Default: verify dependencies, safely stow desktop settings, initialize wallpaper,
           set imv/mpv as default image/video apps, reload user unit definitions
           if reachable. Log out/in to activate.
  --check: read-only dependency/link/config checks; nonzero if setup is incomplete.
  --install-packages: install required official Arch packages with sudo pacman.
Run as your desktop user, after a normal full Arch update. No AUR/private binaries
are installed. Existing conflicting files are never adopted or overwritten.
The script never locks the screen or starts/stops/reloads the running desktop.
HELP
            exit 0 ;;
        *) printf 'Unknown option: %s\n' "$arg" >&2; exit 2 ;;
    esac
done
fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
warn() { printf 'NOTE: %s\n' "$*"; }
[[ "$check" == false || "$install_packages" == false ]] || fail '--check cannot install packages'
[[ $EUID -ne 0 ]] || fail 'Run as your desktop user, not root'
[[ "${XDG_CONFIG_HOME:-$HOME/.config}" == "$HOME/.config" ]] || fail 'This desktop requires XDG_CONFIG_HOME=$HOME/.config'
command -v pacman >/dev/null || fail 'This installer targets Arch Linux with pacman'
packages=(
    stow hyprland quickshell hypridle hyprlock hyprpaper dunst python wl-clipboard cliphist
    kitty jq curl libnotify dbus procps-ng util-linux iproute2 fontconfig
    ttf-jetbrains-mono-nerd noto-fonts-cjk noto-fonts-emoji inter-font adwaita-cursors
    grim slurp imagemagick brightnessctl playerctl libpulse pipewire pipewire-pulse wireplumber
    pavucontrol htop dolphin imv mpv xdg-utils firefox fcitx5 fcitx5-hangul fcitx5-gtk fcitx5-qt
    python-gobject gtk3 gtk-layer-shell wofi qt5ct kvantum
)
if "$install_packages"; then
    sudo pacman -S --needed "${packages[@]}"
fi
errors=0
missing() { printf 'MISSING: %s\n' "$*"; errors=$((errors + 1)); }
commands=(stow Hyprland hyprctl qs hypridle hyprlock hyprpaper dunstctl python wl-paste wl-copy
    kitty jq curl notify-send dbus-update-activation-environment pidof flock ip fc-match
    grim slurp magick brightnessctl playerctl pactl pavucontrol htop dolphin imv mpv xdg-mime firefox fcitx5 wofi)
for cmd in "${commands[@]}"; do
    command -v "$cmd" >/dev/null || missing "$cmd"
done
if ! command -v cliphist >/dev/null && [[ ! -x "$HOME/.local/bin/cliphist" ]]; then
    missing cliphist
fi
for spec in 'hyprland 0.56.2' 'quickshell 0.3.2' 'hypridle 0.1.8'; do
    read -r package minimum <<< "$spec"
    if installed=$(pacman -Q "$package" 2>/dev/null); then
        version=${installed#* }
        [[ $(vercmp "$version" "$minimum") -ge 0 ]] || missing "$package >= $minimum (installed $version)"
    else
        missing "$package >= $minimum"
    fi
done
for font in ttf-jetbrains-mono-nerd noto-fonts-cjk noto-fonts-emoji inter-font; do
    pacman -Q "$font" >/dev/null 2>&1 || missing "$font"
done
if command -v python >/dev/null; then
    python -c 'import gi; gi.require_version("Gtk", "3.0"); gi.require_version("GtkLayerShell", "0.1"); from gi.repository import Gtk, GtkLayerShell' \
        2>/dev/null || missing 'python-gobject / gtk3 / gtk-layer-shell (music popup)'
fi
if (( errors > 0 )); then
    printf '\nInstall missing dependencies using:\n  bash %q --install-packages\n' "$repo/install-desktop.sh"
    exit 1
fi
# Without explicit defaults Dolphin picks whichever installed app ranks first (gimp, a browser, ...).
# Only formats Arch's imv decodes (no FreeImage backend): Netpbm, TGA, ICO and svgz are left alone.
image_types=(image/png image/jpeg image/pjpeg image/gif image/webp image/bmp image/x-bmp image/x-ms-bmp
    image/tiff image/svg+xml image/heic image/heif image/avif image/jxl image/qoi image/x-qoi)
video_types=(video/mp4 video/x-matroska video/webm video/quicktime video/x-msvideo video/avi video/vnd.avi
    video/mpeg video/ogg video/x-flv video/x-ms-wmv video/3gpp video/3gpp2 video/mp2t video/x-m4v
    application/x-matroska)
default_apps=("imv-dir.desktop|${image_types[*]}" "mpv.desktop|${video_types[*]}")
stow_packages=(hyprland hypridle hyprlock hyprpaper quickshell dunst kitty fcitx5)
stow_args=(--dir="$repo" --target="$HOME" --no-folding '--ignore=(^|/)(__tests__|__pycache__)(/|$)')
# One simulation across every package: abort before creating any links on conflict.
stow "${stow_args[@]}" --simulate "${stow_packages[@]}" || fail 'Stow conflict; move conflicting files aside manually and retry'
if ! "$check"; then
    stow "${stow_args[@]}" "${stow_packages[@]}"
    for pair in "${default_apps[@]}"; do
        IFS='|' read -r app types <<< "$pair"
        for type in $types; do
            xdg-mime default "$app" "$type"
        done
    done
    WALLPAPER_DIR="$HOME/Pictures/Wallpapers" "$repo/hyprland/.config/hypr/scripts/wallpaper.sh" ensure
    if systemctl --user show-environment >/dev/null 2>&1; then
        systemctl --user daemon-reload
    else
        warn 'No user systemd manager reachable; unit definitions will load at next login'
    fi
fi
links=(
    'hypr/hyprland.lua|hyprland/.config/hypr/hyprland.lua'
    'hypr/hypridle.conf|hypridle/.config/hypr/hypridle.conf'
    'hypr/hypridle-locked.conf|hypridle/.config/hypr/hypridle-locked.conf'
    'hypr/hyprlock.conf|hyprlock/.config/hypr/hyprlock.conf'
    'hypr/hyprpaper.conf|hyprpaper/.config/hypr/hyprpaper.conf'
    'quickshell/shell.qml|quickshell/.config/quickshell/shell.qml'
    'quickshell/Sidebar.qml|quickshell/.config/quickshell/Sidebar.qml'
    'dunst/dunstrc|dunst/.config/dunst/dunstrc'
    'kitty/kitty.conf|kitty/.config/kitty/kitty.conf'
    'fcitx5/profile|fcitx5/.config/fcitx5/profile'
    'systemd/user/clipboard-history.service|quickshell/.config/systemd/user/clipboard-history.service'
    'systemd/user/hypridle-locked.service|hypridle/.config/systemd/user/hypridle-locked.service'
)
for pair in "${links[@]}"; do
    IFS='|' read -r target source <<< "$pair"
    [[ -f "$HOME/.config/$target" && "$(readlink -f "$HOME/.config/$target")" == "$repo/$source" ]] || missing "link: ~/.config/$target"
done
for pair in "${default_apps[@]}"; do
    IFS='|' read -r app types <<< "$pair"
    wrong=()
    for type in $types; do
        [[ "$(xdg-mime query default "$type")" == "$app" ]] || wrong+=("$type")
    done
    (( ${#wrong[@]} == 0 )) || missing "default app $app for: ${wrong[*]}"
done
[[ ! -L "$HOME/.config/hypr" ]] || missing '~/.config/hypr must be a real directory for machine-local monitor settings'
[[ -f "$HOME/Pictures/Wallpapers/.current" ]] || missing 'wallpaper: ~/Pictures/Wallpapers/.current'
if (( errors == 0 )); then
    Hyprland --verify-config || missing 'Hyprland configuration validation'
    # Unit parsing needs a runtime directory, but not a logged-in user manager.
    python - "$HOME/.config/systemd/user/clipboard-history.service" \
        "$HOME/.config/systemd/user/hypridle-locked.service" <<'PY' || missing 'systemd unit validation'
import os
import subprocess
import sys
import tempfile

with tempfile.TemporaryDirectory(prefix="desktop-unit-check.") as runtime:
    env = dict(os.environ, XDG_RUNTIME_DIR=runtime)
    result = subprocess.run(["systemd-analyze", "--user", "verify", *sys.argv[1:]], env=env)
    sys.exit(result.returncode)
PY
fi
for tool in copad comux coctl; do
    [[ -x "$HOME/.local/bin/$tool" ]] || warn "Optional ~/.local/bin/$tool absent (Kitty fallback; agent/usage data may be unavailable)"
done
[[ -f "$HOME/.config/hypr/monitors_local.lua" ]] || warn 'No local monitor layout; Hyprland will use preferred/auto outputs'
[[ -r "$HOME/.config/grafana-homelab/config" ]] || warn 'Grafana credentials are machine-local; homelab metrics unavailable until configured'
warn 'Pretendard/Bibata are optional personal fonts/theme; standard font/cursor fallbacks apply'
if "$check" && [[ -n "${WAYLAND_DISPLAY:-}" && -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
    for unit in hypridle.service clipboard-history.service; do
        systemctl --user is-active --quiet "$unit" \
            || missing "service inactive: $unit; log out/in to complete session handoff"
    done
    if ipc=$(qs ipc show 2>/dev/null) && [[ "$ipc" == *'target launcher'* && "$ipc" == *'target sidebar'* ]]; then
        warn 'Running shell exposes launcher/sidebar IPC (separate from installed config validation)'
    else
        missing 'running shell IPC; restart Quickshell with Super+R or log out/in'
    fi
fi
(( errors == 0 )) || exit 1
printf '\nDesktop configuration checks passed.\n'
if ! "$check"; then
    printf 'Log out and back into Hyprland to start services and load the new shell.\n'
    printf 'Super+R only restarts Quickshell; it does not migrate idle/clipboard services.\n'
fi
