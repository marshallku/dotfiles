import QtQuick
import Quickshell

// Hover tooltip hung under a bar pill. A popup surface rather than an item:
// the bar window is only as tall as the bar, so anything drawn below it would
// be clipped.
PopupWindow {
    id: tip

    required property Item target
    property string text
    property bool hovered: false

    // A short delay keeps a pointer sweeping across the bar from flashing
    // every tooltip it crosses.
    property bool armed: false
    onHoveredChanged: {
        if (hovered)
            delay.restart();
        else {
            delay.stop();
            armed = false;
        }
    }
    Timer {
        id: delay
        interval: 400
        onTriggered: tip.armed = true
    }

    visible: armed && text !== ""
    color: "transparent"
    anchor.item: target
    anchor.edges: Edges.Bottom
    anchor.gravity: Edges.Bottom
    anchor.adjustment: PopupAdjustment.Slide | PopupAdjustment.FlipY

    implicitWidth: box.implicitWidth
    implicitHeight: box.implicitHeight + 6

    Rectangle {
        id: box

        anchors.bottom: parent.bottom
        implicitWidth: label.implicitWidth + 24
        implicitHeight: label.implicitHeight + 16
        radius: 12
        color: Qt.rgba(12 / 255, 12 / 255, 24 / 255, 0.95)
        border.width: 1
        border.color: Qt.rgba(180 / 255, 160 / 255, 1, 0.15)

        Text {
            id: label
            anchors.centerIn: parent
            text: BarData.markup(tip.text)
            textFormat: Text.StyledText
            color: "#e2e0f0"
            font.family: Theme.mono
            font.pixelSize: 11
        }
    }
}
