pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

Singleton {
    id: root

    property bool sidebarOpen: false
    property bool launcherOpen: false
    property var notifications: []
    property bool paused: false
    property int waiting: 0
    property int displayed: 0
    property string notificationError: ""
    property var clipboard: []
    property string clipboardError: ""
    property var pendingActions: []
    readonly property string helper: Quickshell.shellDir + "/scripts/desktop.py"

    function focusedScreen() {
        const monitor = Hyprland.focusedMonitor;
        return Quickshell.screens.find(screen => monitor && screen.name === monitor.name) || Quickshell.screens[0] || null;
    }

    function showSidebar() {
        launcherOpen = false;
        sidebarOpen = true;
        refreshNotifications();
    }

    function showLauncher() {
        sidebarOpen = false;
        launcherOpen = true;
        refreshClipboard();
    }

    function refreshNotifications() {
        if (!notificationPoll.running)
            notificationPoll.running = true;
    }

    function refreshClipboard() {
        if (!clipboardPoll.running)
            clipboardPoll.running = true;
    }

    function action(args) {
        pendingActions = pendingActions.concat([args]);
        runNextAction();
    }

    function runNextAction() {
        if (actionProcess.running || pendingActions.length === 0)
            return;
        const args = pendingActions[0];
        pendingActions = pendingActions.slice(1);
        actionProcess.command = [helper].concat(args);
        actionProcess.running = true;
    }

    function parse(text) {
        try {
            return JSON.parse(text);
        } catch (error) {
            return {
                ok: false,
                error: "Desktop helper returned invalid data"
            };
        }
    }

    Process {
        id: notificationPoll
        command: [root.helper, "notifications"]
        stdout: StdioCollector {
            onStreamFinished: {
                const value = root.parse(text);
                root.notificationError = value.ok ? "" : value.error;
                if (!value.ok)
                    return;
                root.notifications = value.items;
                root.paused = value.paused;
                root.waiting = value.waiting;
                root.displayed = value.displayed;
            }
        }
    }

    Process {
        id: clipboardPoll
        command: [root.helper, "clipboard"]
        stdout: StdioCollector {
            onStreamFinished: {
                const value = root.parse(text);
                root.clipboardError = value.ok ? "" : value.error;
                root.clipboard = value.ok ? value.items : [];
            }
        }
    }

    Process {
        id: actionProcess
        stdout: StdioCollector {
            onStreamFinished: {
                const value = root.parse(text);
                if (!value.ok)
                    console.warn("Desktop action failed:", value.error);
            }
        }
        onExited: {
            root.refreshNotifications();
            root.refreshClipboard();
            Qt.callLater(root.runNextAction);
        }
    }

    Timer {
        interval: 2000
        running: root.sidebarOpen
        repeat: true
        onTriggered: root.refreshNotifications()
    }

    IpcHandler {
        target: "sidebar"
        function toggle(): void {
            if (root.sidebarOpen)
                root.sidebarOpen = false;
            else
                root.showSidebar();
        }
        function close(): void {
            root.sidebarOpen = false;
        }
    }
}
