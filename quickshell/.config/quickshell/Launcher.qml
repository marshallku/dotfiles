import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

Scope {
    // Instantiate the model and its IPC handler before the first open.
    readonly property var model: LauncherModel

    LazyLoader {
        active: DesktopState.launcherOpen
        PanelWindow {
            id: win
            screen: DesktopState.focusedScreen()
            color: "transparent"
            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "quickshell-launcher"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

            MouseArea {
                anchors.fill: parent
                onClicked: DesktopState.launcherOpen = false
            }

            Rectangle {
                id: panel
                width: Math.min(720, win.width - 48)
                height: Math.min(580, win.height - 120)
                anchors.horizontalCenter: parent.horizontalCenter
                y: Math.max(48, (win.height - height) * 0.3)
                radius: 22
                color: Qt.rgba(0.07, 0.07, 0.11, 0.97)
                border.color: Theme.cardBorder
                border.width: 1
                opacity: 0
                scale: 0.98
                ParallelAnimation {
                    running: true
                    NumberAnimation {
                        target: panel
                        property: "opacity"
                        to: 1
                        duration: 140
                    }
                    NumberAnimation {
                        target: panel
                        property: "scale"
                        to: 1
                        duration: 180
                        easing.type: Easing.OutCubic
                    }
                }
                MouseArea {
                    anchors.fill: parent
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 12
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.minimumHeight: 44
                        Item {
                            Layout.preferredWidth: 26
                            Layout.preferredHeight: 26
                            Rectangle {
                                x: 2
                                y: 2
                                width: 16
                                height: 16
                                radius: 8
                                color: "transparent"
                                border.color: Theme.mauve
                                border.width: 2
                            }
                            Rectangle {
                                x: 16
                                y: 16
                                width: 10
                                height: 2
                                radius: 1
                                color: Theme.mauve
                                rotation: 45
                                transformOrigin: Item.TopLeft
                            }
                        }
                        TextField {
                            id: search
                            Layout.fillWidth: true
                            text: LauncherModel.query
                            placeholderText: LauncherModel.scope === "Clipboard" ? "Search clipboard history…" : "Search apps, windows & commands…"
                            color: Theme.text
                            placeholderTextColor: Theme.overlay1
                            font.family: Theme.sans
                            font.pixelSize: 20
                            background: Item {}
                            selectByMouse: true
                            onTextEdited: LauncherModel.query = text
                            Component.onCompleted: forceActiveFocus()
                            Keys.onPressed: event => {
                                if (event.key === Qt.Key_Escape) {
                                    DesktopState.launcherOpen = false;
                                } else if (event.key === Qt.Key_Down || event.key === Qt.Key_Up) {
                                    const count = LauncherModel.results.length;
                                    if (count > 0) {
                                        LauncherModel.selected = (LauncherModel.selected + count + (event.key === Qt.Key_Down ? 1 : -1)) % count;
                                        results.positionViewAtIndex(LauncherModel.selected, ListView.Contain);
                                    }
                                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                    if (!event.isAutoRepeat)
                                        LauncherModel.activate(LauncherModel.selected);
                                } else if (event.key === Qt.Key_Tab
                                        || (event.modifiers === Qt.NoModifier
                                            && (event.key === Qt.Key_Left || event.key === Qt.Key_Right))) {
                                    const categories = ["All", "Apps", "Windows", "Actions", "Clipboard"];
                                    const step = event.key === Qt.Key_Left ? -1 : 1;
                                    LauncherModel.scope = categories[(categories.indexOf(LauncherModel.scope)
                                            + step + categories.length) % categories.length];
                                } else {
                                    return;
                                }
                                event.accepted = true;
                            }
                        }
                        Text {
                            text: "esc"
                            color: Theme.overlay1
                            font.family: Theme.mono
                            font.pixelSize: 11
                        }
                    }
                    RowLayout {
                        spacing: 6
                        Repeater {
                            model: ["All", "Apps", "Windows", "Actions", "Clipboard"]
                            ActionButton {
                                required property string modelData
                                text: modelData
                                active: LauncherModel.scope === modelData
                                onClicked: {
                                    LauncherModel.scope = modelData;
                                    search.forceActiveFocus();
                                }
                            }
                        }
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 1
                        color: Theme.surface0
                    }
                    ListView {
                        id: results
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        spacing: 4
                        model: LauncherModel.results
                        currentIndex: LauncherModel.selected
                        boundsBehavior: Flickable.StopAtBounds
                        ScrollBar.vertical: ScrollBar {}
                        delegate: Rectangle {
                            id: row
                            required property var modelData
                            required property int index
                            width: results.width
                            height: 60
                            radius: 12
                            color: index === LauncherModel.selected ? Theme.surface0 : hover.containsMouse ? Theme.mantle : "transparent"
                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 10
                                spacing: 12
                                Item {
                                    Layout.preferredWidth: 30
                                    Layout.preferredHeight: 30
                                    Image {
                                        anchors.fill: parent
                                        source: row.modelData.appIcon ? Quickshell.iconPath(row.modelData.appIcon, true) : ""
                                        visible: status === Image.Ready
                                        sourceSize.width: 30
                                        sourceSize.height: 30
                                    }
                                    Text {
                                        anchors.centerIn: parent
                                        visible: !row.modelData.appIcon
                                        text: row.modelData.icon
                                        font.family: Theme.mono
                                        font.pixelSize: 23
                                        color: row.modelData.category === "Calculator" ? Theme.green : Theme.mauve
                                    }
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 3
                                    Text {
                                        Layout.fillWidth: true
                                        text: row.modelData.title
                                        textFormat: Text.PlainText
                                        elide: Text.ElideRight
                                        color: Theme.text
                                        font.family: Theme.sans
                                        font.pixelSize: 14
                                        font.weight: Font.Medium
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        text: row.modelData.subtitle
                                        textFormat: Text.PlainText
                                        elide: Text.ElideRight
                                        color: Theme.subtext0
                                        font.family: Theme.sans
                                        font.pixelSize: 11
                                    }
                                }
                                Text {
                                    text: row.modelData.category
                                    color: Theme.overlay1
                                    font.family: Theme.sans
                                    font.pixelSize: 10
                                }
                            }
                            MouseArea {
                                id: hover
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: LauncherModel.activate(row.index)
                            }
                        }
                        Text {
                            anchors.centerIn: parent
                            visible: LauncherModel.results.length === 0
                            text: LauncherModel.scope === "Clipboard" ? DesktopState.clipboardError || "No copied items yet" : "No results"
                            color: Theme.overlay1
                            font.family: Theme.sans
                            font.pixelSize: 14
                        }
                    }
                    RowLayout {
                        Text {
                            text: "↑↓ navigate   ↵ open / copy   ←→ / Tab category"
                            color: Theme.overlay1
                            font.family: Theme.mono
                            font.pixelSize: 10
                        }
                        Item {
                            Layout.fillWidth: true
                        }
                        Text {
                            text: LauncherModel.results.length + " results"
                            color: Theme.overlay1
                            font.family: Theme.mono
                            font.pixelSize: 10
                        }
                    }
                }
            }
        }
    }
}
