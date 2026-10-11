import QtQuick
import QtQuick.Layouts

Card {
    title: "Notifications"
    icon: "󰂚"
    error: DesktopState.notificationError

    RowLayout {
        Layout.fillWidth: true
        ActionButton {
            text: DesktopState.paused ? "󰂛  Do not disturb" : "󰂚  Notifications on"
            active: DesktopState.paused
            onClicked: DesktopState.action(["notification-action", "pause"])
        }
        Item {
            Layout.fillWidth: true
        }
        Text {
            text: DesktopState.waiting > 0 ? DesktopState.waiting + " queued" : DesktopState.displayed > 0 ? DesktopState.displayed + " on screen" : ""
            color: Theme.overlay1
            font.family: Theme.sans
            font.pixelSize: 11
        }
        ActionButton {
            text: "Clear history"
            enabled: DesktopState.notifications.length > 0
            opacity: enabled ? 1 : 0.45
            onClicked: DesktopState.action(["notification-action", "history-clear"])
        }
    }

    Text {
        visible: DesktopState.notifications.length === 0
        Layout.fillWidth: true
        Layout.topMargin: 12
        text: DesktopState.waiting > 0 ? "Turn off Do not disturb to show queued notifications." : "You're all caught up. Dismissed notifications appear here."
        wrapMode: Text.WordWrap
        color: Theme.overlay1
        font.family: Theme.sans
        font.pixelSize: 12
    }

    Repeater {
        model: DesktopState.notifications
        Rectangle {
            id: notification
            required property var modelData
            Layout.fillWidth: true
            implicitHeight: content.implicitHeight + 24
            radius: 12
            color: Qt.rgba(1, 1, 1, 0.035)
            border.color: modelData.critical ? Theme.red : Theme.cardBorder

            ColumnLayout {
                id: content
                anchors.fill: parent
                anchors.margins: 12
                spacing: 6
                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        Layout.fillWidth: true
                        text: notification.modelData.app || "Notification"
                        textFormat: Text.PlainText
                        color: Theme.mauve
                        font.family: Theme.sans
                        font.pixelSize: 11
                        elide: Text.ElideRight
                    }
                    Text {
                        text: Theme.ago(notification.modelData.time, Data.now)
                        color: Theme.overlay1
                        font.family: Theme.mono
                        font.pixelSize: 10
                    }
                }
                Text {
                    Layout.fillWidth: true
                    text: notification.modelData.summary
                    textFormat: Text.PlainText
                    color: Theme.text
                    font.family: Theme.sans
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    wrapMode: Text.WordWrap
                }
                Text {
                    Layout.fillWidth: true
                    visible: text !== ""
                    text: notification.modelData.body
                    textFormat: Text.PlainText
                    color: Theme.subtext0
                    font.family: Theme.sans
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                    maximumLineCount: 5
                    elide: Text.ElideRight
                }
                RowLayout {
                    ActionButton {
                        text: "Show again"
                        onClicked: DesktopState.action(["notification-action", "history-pop", String(notification.modelData.id)])
                    }
                    Item {
                        Layout.fillWidth: true
                    }
                    ActionButton {
                        text: "Dismiss"
                        onClicked: DesktopState.action(["notification-action", "history-rm", String(notification.modelData.id)])
                    }
                }
            }
        }
    }
}
