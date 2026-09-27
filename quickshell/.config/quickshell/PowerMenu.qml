import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland

// Power menu overlay. Toggled over IPC (`qs ipc call power toggle`, bound in
// hyprland.lua) on whichever monitor has focus at that moment.
//
// Keyboard: ←/→ or h/l to move, Enter/Space to pick, Esc/q to close, or the
// the hint letter under an action (h/l are taken by navigation). Logout / reboot / shutdown need a second press
// (the button turns red and says "again"); the arm resets on close.
//
// POWER_MENU_DRYRUN=1 in quickshell's environment logs the command instead of
// running it — for testing the flow without powering anything off.
Scope {
    id: root

    property bool open: false
    property int selected: 0
    property int armed: -1

    readonly property bool dryRun: Quickshell.env("POWER_MENU_DRYRUN") === "1"
    readonly property string hyprDo: Quickshell.env("HOME") + "/.config/hypr/scripts/hypr-do.sh"

    readonly property var actions: [
        {
            key: "k",
            label: "Lock",
            icon: "󰌾",
            confirm: false,
            cmd: ["hyprlock"]
        },
        {
            key: "s",
            label: "Suspend",
            icon: "󰤄",
            confirm: false,
            cmd: ["systemctl", "suspend"]
        },
        {
            key: "e",
            label: "Logout",
            icon: "󰍃",
            confirm: true,
            cmd: [hyprDo, "exit"]
        },
        {
            key: "r",
            label: "Reboot",
            icon: "󰜉",
            confirm: true,
            cmd: ["systemctl", "reboot"]
        },
        {
            key: "p",
            label: "Shutdown",
            icon: "󰐥",
            confirm: true,
            cmd: ["systemctl", "poweroff"]
        }
    ]

    function show() {
        selected = 0;
        armed = -1;
        open = true;
    }

    function hide() {
        open = false;
        armed = -1;
    }

    function activate(i) {
        const a = actions[i];
        if (!a)
            return;
        if (a.confirm && armed !== i) {
            selected = i;
            armed = i;
            return;
        }
        hide();
        if (dryRun) {
            console.log("power-menu dry-run:", JSON.stringify(a.cmd));
            return;
        }
        Quickshell.execDetached(a.cmd);
    }

    function focusedScreen() {
        const mon = Hyprland.focusedMonitor;
        const screens = Quickshell.screens;
        for (let i = 0; i < screens.length; i++) {
            if (mon && screens[i].name === mon.name)
                return screens[i];
        }
        return screens.length > 0 ? screens[0] : null;
    }

    IpcHandler {
        target: "power"

        function toggle(): void {
            if (root.open)
                root.hide();
            else
                root.show();
        }
        function open(): void {
            root.show();
        }
        function close(): void {
            root.hide();
        }
    }

    // A Loader, not `visible`: the surface (and its exclusive keyboard grab)
    // exists only while open, and is recreated on the monitor focused now.
    LazyLoader {
        active: root.open

        PanelWindow {
            id: win

            screen: root.focusedScreen()
            color: "transparent"
            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "quickshell-power"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

            Rectangle {
                id: scrim
                anchors.fill: parent
                color: Qt.rgba(0.04, 0.04, 0.07, 0.55)
                opacity: 0
                Component.onCompleted: opacity = 1
                Behavior on opacity {
                    NumberAnimation {
                        duration: 220
                        easing.type: Easing.OutCubic
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: root.hide()
                }
            }

            Item {
                id: keys
                anchors.fill: parent
                focus: true

                Keys.onPressed: event => {
                    const n = root.actions.length;
                    switch (event.key) {
                    case Qt.Key_Escape:
                    case Qt.Key_Q:
                        root.hide();
                        break;
                    case Qt.Key_Left:
                    case Qt.Key_H:
                        root.selected = (root.selected + n - 1) % n;
                        root.armed = -1;
                        break;
                    case Qt.Key_Right:
                    case Qt.Key_L:
                    case Qt.Key_Tab:
                        root.selected = (root.selected + 1) % n;
                        root.armed = -1;
                        break;
                    case Qt.Key_Return:
                    case Qt.Key_Enter:
                    case Qt.Key_Space:
                        // A held key must not arm and then fire the
                        // confirmation: only a second physical press counts.
                        if (!event.isAutoRepeat)
                            root.activate(root.selected);
                        break;
                    default:
                        if (!event.isAutoRepeat) {
                            const i = root.actions.findIndex(a => a.key === event.text.toLowerCase());
                            if (i >= 0)
                                root.activate(i);
                        }
                    }
                    event.accepted = true;
                }
            }

            RowLayout {
                id: buttons
                anchors.centerIn: parent
                spacing: 18

                scale: 0.9
                opacity: 0
                Component.onCompleted: {
                    scale = 1;
                    opacity = 1;
                }
                Behavior on scale {
                    NumberAnimation {
                        duration: 320
                        easing.type: Easing.OutBack
                    }
                }
                Behavior on opacity {
                    NumberAnimation {
                        duration: 220
                    }
                }

                Repeater {
                    model: root.actions

                    Rectangle {
                        id: btn

                        required property var modelData
                        required property int index
                        readonly property bool isSelected: root.selected === index
                        readonly property bool isArmed: root.armed === index

                        implicitWidth: 120
                        implicitHeight: 132
                        radius: 20
                        color: isArmed ? Qt.rgba(0.95, 0.55, 0.66, 0.22) : isSelected ? Qt.rgba(0.80, 0.65, 0.97, 0.18) : Theme.cardBg
                        border.width: isSelected ? 2 : 1
                        border.color: isArmed ? Theme.red : isSelected ? Theme.mauve : Theme.cardBorder
                        scale: isSelected ? 1.06 : 1

                        Behavior on color {
                            ColorAnimation {
                                duration: 180
                            }
                        }
                        Behavior on scale {
                            NumberAnimation {
                                duration: 180
                                easing.type: Easing.OutCubic
                            }
                        }

                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: 10

                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: btn.modelData.icon
                                color: btn.isArmed ? Theme.red : btn.isSelected ? Theme.mauve : Theme.text
                                font.family: Theme.mono
                                font.pixelSize: 38
                            }
                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: btn.isArmed ? "again" : btn.modelData.label
                                color: btn.isArmed ? Theme.red : Theme.subtext1
                                font.family: Theme.sans
                                font.pixelSize: 13
                                font.weight: Font.DemiBold
                            }
                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: btn.modelData.key
                                color: Theme.overlay0
                                font.family: Theme.mono
                                font.pixelSize: 10
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            onEntered: {
                                if (root.selected !== btn.index) {
                                    root.selected = btn.index;
                                    root.armed = -1;
                                }
                            }
                            onClicked: root.activate(btn.index)
                        }
                    }
                }
            }
        }
    }
}
