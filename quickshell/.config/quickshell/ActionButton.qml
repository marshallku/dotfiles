import QtQuick

Rectangle {
    id: button
    property string text
    property bool active: false
    signal clicked
    implicitWidth: label.implicitWidth + 24
    implicitHeight: 32
    radius: 10
    color: active ? Theme.surface1 : area.containsMouse ? Theme.surface0 : Qt.rgba(1, 1, 1, 0.035)
    border.color: active ? Theme.mauve : Theme.cardBorder
    border.width: 1
    Text {
        id: label
        anchors.centerIn: parent
        text: button.text
        color: button.active ? Theme.text : Theme.subtext0
        font.family: Theme.sans
        font.pixelSize: 12
    }
    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        onClicked: button.clicked()
    }
}
