#!/bin/bash
# User-level macOS settings for a headless box where agents run UI tests
# (XCUITest) on the live screen. Every setting here removes a modal dialog that
# otherwise blocks the run until someone clears it by hand.
#
# User-level only: no sudo, no SIP, no TCC edits. Grants that macOS keeps behind
# System Settings are printed at the end as a checklist. Idempotent.
# Run after `stow bin zsh`.

set -e

if [ "$(uname -s)" != "Darwin" ]; then
    echo "✗ macOS only"
    exit 1
fi

# "<app> quit unexpectedly" (UserNotificationCenter) after a test app crashes.
# `server` still writes the .ips report to ~/Library/Logs/DiagnosticReports but
# never shows the dialog; verified on macOS 26.5. `none` would drop the reports.
defaults write com.apple.CrashReporter DialogType -string server
echo "✓ crash reporter dialog: $(defaults read com.apple.CrashReporter DialogType)"

# Gatekeeper first-launch prompt for binary-only casks after `brew upgrade`.
# The zsh `brew` wrapper repeats this after every install/upgrade.
if command -v brew >/dev/null 2>&1 && command -v brew-release-quarantine >/dev/null 2>&1; then
    brew-release-quarantine
    echo "✓ binary-only casks released from quarantine"
else
    echo "→ skipped cask quarantine release (brew or brew-release-quarantine not on PATH)"
fi

echo
echo "Status of settings that need sudo or System Settings:"
automationmodetool 2>/dev/null | sed 's/^/  /' || true
echo "  $(DevToolsSecurity -status 2>/dev/null)"
echo "  $(sysadminctl -screenLock status 2>&1 | sed 's/.*\] //')"
cat <<'EOF'

Grant once in System Settings (TCC prompts cannot be pre-answered without MDM):
  Privacy & Security > Full Disk Access > + Ghostty
    (Full Disk Access supersedes "would like to access data from other apps",
     and children of Ghostty — agents, xcodebuild — inherit its grants)
EOF
