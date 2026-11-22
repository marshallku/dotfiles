#!/usr/bin/env bash
# reap-disk-install.sh — run reap-disk.sh --apply --quiet once a day, as the user.
#
#   reap-disk-install.sh            install (or refresh) the daily job
#   reap-disk-install.sh --remove   remove it
#   reap-disk-install.sh --print    print the unit/plist that would be written, change nothing
#
# macOS: ~/Library/LaunchAgents/<LABEL>.plist (launchd, daily 12:30, also catches up after sleep).
# Linux: ~/.config/systemd/user/reap-disk.{service,timer} (OnCalendar=daily, Persistent=true).
# Runs with the user's own permissions, because agent turns are denied recursive deletes; it only
# ever moves things to the trash (see reap-disk.sh).

set -euo pipefail

LABEL="com.dotfiles.reap-disk"
SCRIPT="$HOME/.claude/scripts/reap-disk.sh"
LOG="$HOME/.claude/state/reap-disk.log"
HOUR=12
MINUTE=30

MODE="install"
case "${1:-}" in
    "") ;;
    --remove) MODE="remove" ;;
    --print) MODE="print" ;;
    *) echo "usage: $0 [--remove|--print]" >&2; exit 2 ;;
esac

[ "$MODE" != install ] || [ -f "$SCRIPT" ] || { echo "[reap-disk-install] $SCRIPT missing (stow claude first)" >&2; exit 1; }

# bash >= 4 is required by the harness; launchd and systemd do not read the login PATH.
BASH_BIN=""
for candidate in /opt/homebrew/bin/bash /usr/local/bin/bash /usr/bin/bash /bin/bash "$(command -v bash)"; do
    [ -x "$candidate" ] || continue
    if "$candidate" -c '[ "${BASH_VERSINFO[0]}" -ge 4 ]' 2>/dev/null; then BASH_BIN="$candidate"; break; fi
done
[ "$MODE" = remove ] || [ -n "$BASH_BIN" ] || { echo "[reap-disk-install] no bash >= 4 found" >&2; exit 1; }
JOB_PATH="$(dirname "${BASH_BIN:-/bin/bash}"):/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

if [ "$(uname -s)" = Darwin ]; then
    PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
    plist() {
        cat <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$BASH_BIN</string>
        <string>$SCRIPT</string>
        <string>--apply</string>
        <string>--quiet</string>
    </array>
    <key>EnvironmentVariables</key>
    <dict><key>PATH</key><string>$JOB_PATH</string></dict>
    <key>StartCalendarInterval</key>
    <dict><key>Hour</key><integer>$HOUR</integer><key>Minute</key><integer>$MINUTE</integer></dict>
    <key>StandardOutPath</key><string>$LOG</string>
    <key>StandardErrorPath</key><string>$LOG</string>
    <key>LowPriorityIO</key><true/>
    <key>Nice</key><integer>10</integer>
</dict>
</plist>
EOF
    }
    case "$MODE" in
        print) plist ;;
        remove)
            launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
            rm -f "$PLIST"
            echo "removed $PLIST" ;;
        install)
            # The trip wire flags a LaunchAgent naming a missing ~/.claude path: create the log now.
            mkdir -p "$(dirname "$PLIST")" "$(dirname "$LOG")" && : >> "$LOG"
            plist > "$PLIST.tmp" && mv -f "$PLIST.tmp" "$PLIST"
            launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
            launchctl bootstrap "gui/$(id -u)" "$PLIST"
            echo "installed $PLIST (daily $HOUR:$MINUTE; log $LOG)" ;;
    esac
    exit 0
fi

command -v systemctl >/dev/null 2>&1 || { echo "[reap-disk-install] systemctl not found" >&2; exit 1; }
UNIT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
service() {
    cat <<EOF
[Unit]
Description=Move regenerable disk clutter to the trash (dotfiles reap-disk.sh)

[Service]
Type=oneshot
Environment=PATH=$JOB_PATH
ExecStart=$BASH_BIN $SCRIPT --apply --quiet
StandardOutput=append:$LOG
StandardError=append:$LOG
Nice=10
IOSchedulingClass=idle
EOF
}
timer() {
    cat <<EOF
[Unit]
Description=Daily reap-disk.sh

[Timer]
OnCalendar=*-*-* $HOUR:$MINUTE:00
Persistent=true

[Install]
WantedBy=timers.target
EOF
}
case "$MODE" in
    print) service; echo "---"; timer ;;
    remove)
        systemctl --user disable --now reap-disk.timer 2>/dev/null || true
        rm -f "$UNIT_DIR/reap-disk.service" "$UNIT_DIR/reap-disk.timer"
        systemctl --user daemon-reload
        echo "removed reap-disk.timer" ;;
    install)
        mkdir -p "$UNIT_DIR" "$(dirname "$LOG")" && : >> "$LOG"
        service > "$UNIT_DIR/reap-disk.service"
        timer > "$UNIT_DIR/reap-disk.timer"
        systemctl --user daemon-reload
        systemctl --user enable --now reap-disk.timer
        echo "installed reap-disk.timer (daily $HOUR:$MINUTE; log $LOG)" ;;
esac
