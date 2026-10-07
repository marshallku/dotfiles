import QtQuick
import Quickshell
import Quickshell.Hyprland

// Every workspace on every bar, "<id> <icon>" each.
// "Active" means shown on this bar's monitor, so each monitor marks its own.
Rectangle {
    id: root

    required property var screen
    readonly property HyprlandMonitor monitor: Hyprland.monitorFor(screen)
    readonly property var ordered: Hyprland.workspaces.values.filter(ws => ws.id > 0).sort((a, b) => a.id - b.id)

    implicitWidth: row.implicitWidth + 12
    implicitHeight: 28
    radius: 4
    color: Qt.rgba(12 / 255, 12 / 255, 12 / 255, 0.5)

    // Below the buttons so it only sees the wheel; clicks land on a button.
    MouseArea {
        property int wheelAccum: 0

        anchors.fill: parent
        acceptedButtons: Qt.NoButton
        onWheel: wheel => {
            wheelAccum += wheel.angleDelta.y;
            while (Math.abs(wheelAccum) >= 120) {
                const step = wheelAccum > 0 ? 1 : -1;
                wheelAccum -= step * 120;
                BarData.focusWorkspace(step > 0 ? "e-1" : "e+1");
            }
        }
    }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 4

        Repeater {
            model: root.ordered

            Rectangle {
                id: button

                required property HyprlandWorkspace modelData
                readonly property bool active: root.monitor !== null && root.monitor.activeWorkspace === modelData
                readonly property bool urgent: modelData.urgent

                implicitWidth: label.implicitWidth + 16
                implicitHeight: label.implicitHeight + 4
                radius: 12
                color: urgent ? Qt.rgba(224 / 255, 108 / 255, 117 / 255, 0.15) : area.containsMouse ? Qt.rgba(1, 1, 1, 0.05) : "transparent"

                Behavior on color {
                    ColorAnimation {
                        duration: 200
                    }
                }

                Text {
                    id: label
                    anchors.centerIn: parent
                    // nf-md alert_circle / circle_slice_8 / circle_outline
                    text: button.modelData.id + " " + (button.urgent ? "󰀨" : button.active ? "󰮯" : "󰧞")
                    color: area.containsMouse ? "#a6a6a6" : button.urgent ? "#e06c75" : button.active ? "#a8fff0" : "#e5c07b"
                    font.family: Theme.mono
                    font.pixelSize: 12

                    Behavior on color {
                        ColorAnimation {
                            duration: 200
                        }
                    }
                }

                MouseArea {
                    id: area
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: BarData.focusWorkspace(button.modelData.id)
                }
            }
        }
    }
}
