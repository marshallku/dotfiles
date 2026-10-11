import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

Scope {
    LazyLoader {
        active: DesktopState.sidebarOpen
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
            WlrLayershell.namespace: "quickshell-sidebar"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

            MouseArea {
                anchors.fill: parent
                onClicked: DesktopState.sidebarOpen = false
            }

            Rectangle {
                id: panel
                width: Math.min(480, win.width - 32)
                anchors {
                    top: parent.top
                    bottom: parent.bottom
                    right: parent.right
                    margins: 12
                    topMargin: 52
                }
                radius: 24
                color: Qt.rgba(0.07, 0.07, 0.11, 0.96)
                border.color: Theme.cardBorder
                border.width: 1
                focus: true
                Keys.onEscapePressed: DesktopState.sidebarOpen = false
                Component.onCompleted: forceActiveFocus()
                opacity: 0
                transform: Translate {
                    id: slide
                    x: 36
                }
                ParallelAnimation {
                    running: true
                    NumberAnimation {
                        target: panel
                        property: "opacity"
                        to: 1
                        duration: 180
                    }
                    NumberAnimation {
                        target: slide
                        property: "x"
                        to: 0
                        duration: 220
                        easing.type: Easing.OutCubic
                    }
                }
                MouseArea {
                    anchors.fill: parent
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 18
                    spacing: 16
                    RowLayout {
                        Layout.fillWidth: true
                        ColumnLayout {
                            spacing: 3
                            Text {
                                text: "Your workspace"
                                color: Theme.text
                                font.family: Theme.sans
                                font.pixelSize: 23
                                font.weight: Font.DemiBold
                            }
                            Text {
                                text: Qt.formatDateTime(new Date(Data.now), "dddd, MMMM d")
                                color: Theme.subtext0
                                font.family: Theme.sans
                                font.pixelSize: 12
                            }
                        }
                        Item {
                            Layout.fillWidth: true
                        }
                        ActionButton {
                            text: "Esc  ✕"
                            onClicked: DesktopState.sidebarOpen = false
                        }
                    }
                    Flickable {
                        id: scroll
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        contentWidth: width
                        contentHeight: cards.implicitHeight
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        ScrollBar.vertical: ScrollBar {}
                        ColumnLayout {
                            id: cards
                            width: scroll.width
                            spacing: 14
                            AgentsCard {
                                Layout.fillWidth: true
                            }
                            HomelabCard {
                                Layout.fillWidth: true
                            }
                            NotificationCard {
                                Layout.fillWidth: true
                            }
                        }
                    }
                }
            }
        }
    }
}
