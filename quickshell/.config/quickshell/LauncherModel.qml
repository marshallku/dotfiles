pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "LauncherSearch.js" as Search

Singleton {
    id: root
    property string query: ""
    property string scope: "All"
    property string calculation: ""
    property int selected: 0

    readonly property var actions: [
        {
            title: "Notification center",
            subtitle: "Agents, homelab & notifications",
            icon: "󰂚",
            action: "sidebar"
        },
        {
            title: "Clipboard history",
            subtitle: "Search copied text & images",
            icon: "󰅍",
            action: "clipboard"
        },
        {
            title: "Lock screen",
            subtitle: "Lock now · display off after 30s idle",
            icon: "󰌾",
            action: "lock"
        },
        {
            title: "Power menu",
            subtitle: "Lock, suspend, log out & shut down",
            icon: "󰐥",
            action: "power"
        },
    ]

    readonly property var rows: {
        const output = [];
        for (const app of DesktopEntries.applications.values) {
            if (app.noDisplay)
                continue;
            output.push({
                title: app.name,
                subtitle: app.genericName || app.comment || app.id,
                category: "Apps",
                icon: "󰀻",
                appIcon: app.icon,
                app,
                search: [app.name, app.genericName, app.id].concat(app.keywords || []).join(" "),
                priority: 2
            });
        }
        for (const window of ToplevelManager.toplevels.values) {
            output.push({
                title: window.title || window.appId,
                subtitle: "Switch to " + window.appId,
                category: "Windows",
                icon: "󰖯",
                window,
                priority: 0,
                search: window.title + " " + window.appId
            });
        }
        for (const item of actions)
            output.push(Object.assign({
                category: "Actions",
                priority: 1
            }, item));
        if (scope === "Clipboard") {
            for (const item of DesktopState.clipboard)
                output.push({
                    title: item.text,
                    subtitle: "Copy to clipboard · then paste with Ctrl+V",
                    category: "Clipboard",
                    icon: "󰅍",
                    clipboardId: item.id,
                    priority: 0
                });
        }
        return output;
    }

    readonly property var results: {
        const filtered = Search.filterRows({
            rows,
            query,
            scope
        });
        if (calculation && scope === "All")
            filtered.unshift({
                title: calculation,
                subtitle: "Calculation · Enter to copy",
                category: "Calculator",
                icon: "󰃬"
            });
        return filtered;
    }

    onQueryChanged: {
        selected = 0;
        calculation = "";
        calculatorDelay.restart();
    }
    onScopeChanged: selected = 0
    onResultsChanged: selected = Math.min(selected, Math.max(0, results.length - 1))

    function show(category) {
        query = "";
        scope = category || "All";
        selected = 0;
        DesktopState.showLauncher();
    }

    function activate(index) {
        const row = results[index];
        if (!row)
            return;
        if (row.action === "clipboard") {
            scope = "Clipboard";
            query = "";
            return;
        }
        DesktopState.launcherOpen = false;
        if (row.app) {
            if (row.app.runInTerminal) {
                Quickshell.execDetached({
                    command: ["kitty", "-e"].concat(row.app.command),
                    workingDirectory: row.app.workingDirectory
                });
            } else {
                row.app.execute();
            }
        } else if (row.window) {
            row.window.activate();
        } else if (row.clipboardId) {
            DesktopState.action(["clipboard-copy", row.clipboardId]);
        } else if (row.category === "Calculator") {
            DesktopState.action(["copy-text", row.title]);
        } else if (row.action === "sidebar") {
            DesktopState.showSidebar();
        } else if (row.action === "lock") {
            Quickshell.execDetached([Quickshell.env("HOME") + "/.config/hypr/scripts/session-control.sh", "request-lock"]);
        } else if (row.action === "power") {
            Quickshell.execDetached(["qs", "ipc", "call", "power", "open"]);
        }
    }

    Process {
        id: calculator
        property string expression: ""
        stdout: StdioCollector {
            onStreamFinished: {
                const value = DesktopState.parse(text);
                if (calculator.expression === root.query)
                    root.calculation = value.ok ? value.result : "";
            }
        }
        onExited: {
            if (expression !== root.query)
                calculatorDelay.restart();
        }
    }
    Timer {
        id: calculatorDelay
        interval: 120
        onTriggered: {
            const expression = root.query.replace(/^=\s*/, "");
            if (!/^[\d\s+*/%().-]+$/.test(expression) || !/\d/.test(expression) || calculator.running)
                return;
            calculator.expression = root.query;
            calculator.command = [DesktopState.helper, "calculate", expression];
            calculator.running = true;
        }
    }

    IpcHandler {
        target: "launcher"
        function toggle(): void {
            if (DesktopState.launcherOpen)
                DesktopState.launcherOpen = false;
            else
                root.show("All");
        }
        function clipboard(): void {
            root.show("Clipboard");
        }
        function search(text: string): void {
            root.show("All");
            root.query = text;
        }
        function close(): void {
            DesktopState.launcherOpen = false;
        }
    }
}
