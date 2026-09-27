import QtQuick
import QtQuick.Layouts

// Frosted card with a title row. `stale`/`error` render a badge instead of
// hiding data: last-good values stay visible but visibly out of date.
Rectangle {
    id: card

    property string title
    property string icon
    property bool stale: false
    property string error: ""
    property real lastOk: 0
    default property alias content: body.data

    implicitHeight: layout.implicitHeight + Theme.pad * 2
    radius: Theme.radius
    color: Theme.cardBg
    border.color: Theme.cardBorder
    border.width: 1

    // Fade + rise in on first show.
    opacity: 0
    transform: Translate {
        id: rise
        y: 12
    }
    Component.onCompleted: intro.start()
    ParallelAnimation {
        id: intro
        NumberAnimation {
            target: card
            property: "opacity"
            to: 1
            duration: 500
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: rise
            property: "y"
            to: 0
            duration: 600
            easing.type: Easing.OutCubic
        }
    }

    ColumnLayout {
        id: layout
        anchors.fill: parent
        anchors.margins: Theme.pad
        spacing: 10

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Text {
                text: card.icon
                color: Theme.mauve
                font.family: Theme.mono
                font.pixelSize: 15
            }
            Text {
                text: card.title
                color: Theme.text
                font.family: Theme.sans
                font.pixelSize: 14
                font.weight: Font.DemiBold
                font.letterSpacing: 0.4
            }
            Item {
                Layout.fillWidth: true
            }
            Rectangle {
                visible: card.error !== ""
                radius: 6
                color: Qt.rgba(0.95, 0.55, 0.66, 0.15)
                implicitWidth: badge.implicitWidth + 12
                implicitHeight: badge.implicitHeight + 4
                Text {
                    id: badge
                    anchors.centerIn: parent
                    text: card.stale ? "stale " + Theme.ago(card.lastOk, Data.now) : card.error
                    color: Theme.red
                    font.family: Theme.mono
                    font.pixelSize: 10
                    elide: Text.ElideRight
                }
            }
        }

        ColumnLayout {
            id: body
            Layout.fillWidth: true
            spacing: 6
        }
    }
}
