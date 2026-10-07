import QtQuick

// One bar module: rounded translucent pill, hover tint, tooltip, and the
// left/right/middle click + scroll bindings. Hidden while
// `text` is empty, which is how the scripts ask to be hidden.
Rectangle {
    id: pill

    property string text
    property string tooltip
    property color textColor: "#e2e0f0"
    property bool dim: false
    property bool bold: false
    readonly property bool hovered: area.containsMouse

    signal clicked(int button)
    signal scrolled(int step) // +1 up, -1 down

    visible: text !== ""
    implicitWidth: label.implicitWidth + 16
    implicitHeight: 28
    radius: 4
    color: hovered ? Qt.rgba(16 / 255, 16 / 255, 32 / 255, 0.7) : Qt.rgba(8 / 255, 8 / 255, 16 / 255, 0.5)
    border.width: 1
    border.color: Qt.rgba(180 / 255, 160 / 255, 1, hovered ? 0.15 : 0.06)
    opacity: dim && !hovered ? 0.7 : 1

    Behavior on color {
        ColorAnimation {
            duration: 200
        }
    }

    Text {
        id: label
        anchors.centerIn: parent
        text: BarData.markup(pill.text)
        textFormat: Text.StyledText
        color: pill.textColor
        font.family: Theme.mono
        font.pixelSize: 12
        font.weight: pill.bold ? Font.DemiBold : Font.Normal
    }

    MouseArea {
        id: area

        // Touchpads deliver many small deltas; fire one step per notch (120).
        property int wheelAccum: 0

        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onClicked: mouse => pill.clicked(mouse.button)
        onWheel: wheel => {
            wheelAccum += wheel.angleDelta.y;
            while (Math.abs(wheelAccum) >= 120) {
                const step = wheelAccum > 0 ? 1 : -1;
                wheelAccum -= step * 120;
                pill.scrolled(step);
            }
        }
    }

    BarTooltip {
        target: pill
        text: pill.tooltip
        hovered: pill.hovered
    }
}
