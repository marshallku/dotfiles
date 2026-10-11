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

Dependencies: `quickshell`, `dunst`, `python`, `wl-clipboard`, `cliphist`,
`hypridle`, `hyprlock`, `kitty`, `jq` and `comux`/`coctl` in `~/.local/bin`.
Install cliphist with `sudo pacman -S cliphist`, or without root:

```bash
GOBIN="$HOME/.local/bin" go install go.senan.xyz/cliphist@v0.7.0
stow --restow hyprland hypridle hyprlock quickshell dunst
systemctl --user daemon-reload
```

Hyprland imports the Wayland environment and starts the idle and clipboard
services on login. For an existing session, stop the old standalone hypridle
before `systemctl --user start hypridle.service clipboard-history.service`.

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
python -m unittest discover -s quickshell/.config/quickshell/scripts/__tests__
python -m unittest discover -s hyprland/.config/hypr/scripts/__tests__
node quickshell/.config/quickshell/__tests__/launcher-search.cjs
Hyprland --verify-config
```
