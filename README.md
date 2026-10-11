# ConfigurationFiles

```bash
# Normal packages
stow hyprland

# System packages
sudo stow --target=/ keyd
```

## Hyprland

### Sound

```bash
sudo pacman -S pipewire pipewire-alsa pipewire-pulse pipewire-jack wireplumber
```

### Screenshot

```bash
sudo pacman -S grim slurp wl-clipboard   
```

### SDDM

```bash
sudo pacman -S qt5-quickcontrols2 qt5-graphicaleffects
```

## Claude

```bash
stow claude
bash install-claude.sh   # check prerequisites (codex, jq, node) + register MCP
bash install-codex.sh    # link shared skills + Codex hook adapter; then trust via /hooks
```

## Desktop shell

Hyprland uses the local Quickshell shell and comux/copad agent widgets.

| Shortcut | Action |
| --- | --- |
| Super+Space | Search apps, open windows, calculations and desktop actions |
| Super+Shift+V | Search clipboard history; Enter copies, then Ctrl+V pastes |
| Super+N | Right sidebar with widgets and notifications together |
| Super+L | Lock through the shared session controller |
| Super+W | Power menu; its Lock action uses the same lock path |

The clock also opens the sidebar. Clear history removes all archived notifications.
Agents show at most three entries, prioritizing
sessions that need attention or are working, with a count of additional agents.
Launcher categories switch with Left/Right or Tab; Up/Down
select a result, Enter runs it, and Escape closes the panel. Calculations accept
arithmetic such as `12 * (8 + 3)`; Enter copies the result. Terminal applications
use Kitty because the copad GUI has no command execution CLI flag.

For a new machine or after pulling desktop updates, use the installer from any
clone directory (run as your desktop user, never with sudo):

```bash
bash install-desktop.sh --install-packages  # install official Arch dependencies and deploy config
# If dependencies are already installed:
bash install-desktop.sh
bash install-desktop.sh --check             # read-only checks, nonzero on missing requirements
```

Use an up-to-date Arch installation; this is a repeatable configuration installer,
not a pinned OS image. Package installation uses `sudo pacman -S --needed` without
refreshing repositories; perform your normal full system update first. It includes
Nerd/CJK/emoji fonts, Korean input, screenshot/media tools, and the PyGObject/GTK
libraries used by the music popup. The core desktop helper itself uses Python's
standard library. `cliphist` can also be installed manually in `~/.local/bin`.

All eight desktop packages are stowed together, including wallpaper, Kitty and
fcitx5. A simulation checks conflicts first; existing regular config files are
never adopted or overwritten. Move conflicting files aside yourself and retry.
Machine-local `~/.config/hypr/monitors_local.lua` is preserved; absent layouts use
preferred/auto outputs. Empty wallpaper folders get a neutral Catppuccin PNG;
existing `.current` files and valid links are preserved. The clone can live outside
`~/dotfiles`. These configs require the standard `~/.config` location.

Log out and back into Hyprland after installation to activate everything. The
installer reloads unit definitions when a user systemd manager is reachable, but
never starts/stops services, restarts the shell, imports another session's
environment, or locks the screen. Super+R only restarts Quickshell (needed when new
QML types were added); it does not migrate idle or clipboard services. Installation
checks and the optional current-session IPC check are reported separately.

Private `copad`, `comux` and `coctl` binaries are optional: terminal shortcuts fall
back to Kitty, and agent/usage readings may be unavailable. Pretendard and Bibata
are optional; the shell uses Noto Sans CJK KR when Pretendard is absent. Grafana
credentials, Tailscale/VPN login, display-manager setup, hardware drivers and a
Polkit authentication agent remain host-specific setup. No credentials are copied.
The system-wide `fonts/` package is deliberately excluded from home Stow.

While locked, an additional hypridle service powers displays off after 30 seconds
of inactivity, even if a browser inhibits idle. Input wakes the displays; unlock
stops that service and marks copad presence active. The lock controller starts
hyprlock directly so a slow or failed hypridle startup cannot lose the lock request;
its process lifecycle also starts/stops the short timer if compositor hooks are missed.
If the locker fails, the short timer stops and presence stays away until a successful
unlock, since a failed locker can leave the compositor's session lock held.
The ordinary unlocked idle
timeouts remain 5 minutes for away, 30 minutes for display power and 35 minutes
for automatic locking. Lock-screen presence changes follow actual compositor
lock/unlock events rather than keystrokes on the password prompt.

Notifications keep dunst's existing popups/actions. The sidebar shows up to 100
dismissed notifications, can show one again or remove it, and toggles Do not
disturb. Notifications still on screen are counted; queued notifications are
released by turning Do not disturb off. History lasts for the dunst process.

Clipboard history stores text and images locally in `~/.cache/cliphist/db` (up to
cliphist's default 750 entries). The launcher searches the 100 latest previews.
Content marked sensitive by its source is skipped. `cliphist wipe` clears history.

Checks:

```bash
python -m unittest discover -s tests -v
python -m unittest discover -s quickshell/.config/quickshell/scripts/__tests__
python -m unittest discover -s hyprland/.config/hypr/scripts/__tests__
node quickshell/.config/quickshell/__tests__/launcher-search.cjs
Hyprland --verify-config
```
