import QtQuick

// Thin horizontal gauge. The fill animates on every value change, which is
// most of the widget's motion — keep it cheap (a single Rectangle width).
Item {
    id: meter

    property real value: 0 // 0–100, null → empty/grey
    property color color: Theme.level(value)

    implicitHeight: 5

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: Theme.surface0
    }

    Rectangle {
        height: parent.height
        radius: height / 2
        color: meter.color
        width: parent.width * Math.max(0, Math.min(100, meter.value || 0)) / 100

        Behavior on width {
            NumberAnimation {
                duration: 700
                easing.type: Easing.OutCubic
            }
        }
        Behavior on color {
            ColorAnimation {
                duration: 400
            }
        }
    }
}
