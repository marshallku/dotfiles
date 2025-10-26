import QtQuick 2.0
// import QtGraphicalEffects 1.0
import SddmComponents 2.0

Rectangle {
    id: container
    width: 1920
    height: 1080

    LayoutMirroring.enabled: Qt.locale().textDirection == Qt.RightToLeft
    LayoutMirroring.childrenInherit: true

    property int sessionIndex: session.index
    property string selectedUser: userModel.lastUser

    TextConstants { id: textConstants }

    Connections {
        target: sddm
        function onLoginSucceeded() {
            // Login successful
        }

        function onLoginFailed() {
            txtMessage.text = textConstants.loginFailed
            password.text = ""
            password.focus = true
        }
    }

    Background {
        id: backgroundImage
        anchors.fill: parent
        source: config.background
        fillMode: Image.PreserveAspectCrop
        onStatusChanged: {
            if (status == Image.Error && source != config.defaultBackground) {
                source = config.defaultBackground
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        color: "transparent"

        // Main panel with blur
        Item {
            id: mainPanel
            anchors.centerIn: parent
            width: 400
            height: 380

            // Blur effect background
            //ShaderEffectSource {
            //     id: effectSource
            //     sourceItem: backgroundImage
            //     anchors.fill: parent
            //     sourceRect: Qt.rect(mainPanel.x, mainPanel.y, mainPanel.width, mainPanel.height)
            // }

            // FastBlur {
            //     id: blur
            //     anchors.fill: parent
            //     source: effectSource
            //     radius: 64
            // }

            Rectangle {
                anchors.fill: parent
                color: "#cc2e3440"
                radius: 10
            }

            Column {
                anchors.centerIn: parent
                spacing: 20
                width: parent.width - 60

                // Clock
                Column {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 5

                    Text {
                        id: timeLabel
                        anchors.horizontalCenter: parent.horizontalCenter
                        color: "#eceff4"
                        font.pixelSize: 48
                        font.bold: true

                        function updateTime() {
                            text = Qt.formatTime(new Date(), "hh:mm")
                        }
                    }

                    Text {
                        id: dateLabel
                        anchors.horizontalCenter: parent.horizontalCenter
                        color: "#d8dee9"
                        font.pixelSize: 16

                        function updateDate() {
                            text = Qt.formatDate(new Date(), Qt.DefaultLocaleLongDate)
                        }
                    }

                    Timer {
                        interval: 1000
                        running: true
                        repeat: true
                        onTriggered: {
                            timeLabel.updateTime()
                            dateLabel.updateDate()
                        }
                        Component.onCompleted: {
                            timeLabel.updateTime()
                            dateLabel.updateDate()
                        }
                    }
                }

                // User slider
                Item {
                    width: parent.width
                    height: 86

                    ListView {
                        id: usersList
                        anchors.fill: parent
                        orientation: ListView.Horizontal
                        model: userModel
                        currentIndex: userModel.lastIndex
                        spacing: 15
                        clip: true
                        focus: false

                        delegate: Item {
                            width: 70
                            height: 70

                            Rectangle {
                                anchors.centerIn: parent
                                width: 65
                                height: 65
                                radius: 32.5
                                color: "transparent"
                                border.color: usersList.currentIndex === index ? "#88c0d0" : "#5e81ac"
                                border.width: 3

                                Image {
                                    id: userAvatar
                                    anchors.fill: parent
                                    anchors.margins: 3
                                    source: "file://" + icon
                                    fillMode: Image.PreserveAspectCrop
                                    smooth: true

                                    layer.enabled: true
                                    // layer.effect: OpacityMask {
                                    //     maskSource: Rectangle {
                                    //         width: userAvatar.width
                                    //         height: userAvatar.height
                                    //         radius: width / 2
                                    //     }
                                    // }

                                    onStatusChanged: {
                                        if (status == Image.Error) {
                                            source = config.defaultAvatar || ""
                                        }
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: {
                                        usersList.currentIndex = index
                                        selectedUser = name
                                        password.focus = true
                                    }
                                }
                            }

                            Text {
                                anchors.top: parent.bottom
                                anchors.topMargin: 5
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: name
                                color: usersList.currentIndex === index ? "#88c0d0" : "#d8dee9"
                                font.pixelSize: 12
                                font.bold: usersList.currentIndex === index
                            }
                        }

                        // Update selectedUser when index changes
                        onCurrentIndexChanged: {
                            positionViewAtIndex(currentIndex, ListView.Center)
                            // Access the name property from the model at current index
                            var item = userModel.data(userModel.index(currentIndex, 0), 257) // 257 is UserRoles.Name
                            if (item)
                                selectedUser = item
                        }
                    }

                    // Previous user button
                    Rectangle {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        width: 30
                        height: 30
                        radius: 15
                        color: "#5e81ac"
                        visible: usersList.currentIndex > 0

                        Text {
                            anchors.centerIn: parent
                            text: "‹"
                            color: "#eceff4"
                            font.pixelSize: 20
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                if (usersList.currentIndex > 0) {
                                    usersList.currentIndex--
                                }
                            }
                        }
                    }

                    // Next user button
                    Rectangle {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        width: 30
                        height: 30
                        radius: 15
                        color: "#5e81ac"
                        visible: usersList.currentIndex < usersList.count - 1

                        Text {
                            anchors.centerIn: parent
                            text: "›"
                            color: "#eceff4"
                            font.pixelSize: 20
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                if (usersList.currentIndex < usersList.count - 1) {
                                    usersList.currentIndex++
                                }
                            }
                        }
                    }
                }

                // Password input
                PasswordBox {
                    id: password
                    width: parent.width
                    height: 40
                    font.pixelSize: 14
                    color: "#eceff4"
                    borderColor: "#5e81ac"
                    focusColor: "#88c0d0"
                    hoverColor: "#81a1c1"
                    tooltipBG: "#5e81ac"

                    KeyNavigation.backtab: rebootButton
                    KeyNavigation.tab: session

                    Keys.onPressed: {
                        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            sddm.login(selectedUser, password.text, sessionIndex)
                            event.accepted = true
                        }
                        else if (event.key === Qt.Key_Left) {
                            if (usersList.currentIndex > 0) {
                                usersList.currentIndex--
                            }
                        }
                        else if (event.key === Qt.Key_Right) {
                            if (usersList.currentIndex < usersList.count - 1) {
                                usersList.currentIndex++
                            }
                        }
                    }
                }

                // Error message
                Text {
                    id: txtMessage
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: ""
                    font.pixelSize: 12
                    color: "#bf616a"
                }

                // Login button
                Button {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: textConstants.login
                    width: 120
                    height: 35

                    color: "#5e81ac"
                    activeColor: "#88c0d0"
                    pressedColor: "#81a1c1"

                    onClicked: sddm.login(selectedUser, password.text, sessionIndex)

                    KeyNavigation.backtab: layoutBox
                    KeyNavigation.tab: shutdownButton
                }
            }
        }

        // Top bar - Session selector
        Rectangle {
            id: topBar
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 50
            color: "#cc2e3440"

            Row {
                anchors.left: parent.left
                anchors.margins: 15
                anchors.verticalCenter: parent.verticalCenter
                spacing: 10

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: textConstants.session
                    color: "#eceff4"
                    font.pixelSize: 14
                }

                ComboBox {
                    id: session
                    anchors.verticalCenter: parent.verticalCenter
                    width: 200
                    arrowIcon: "angle-down.png"
                    model: sessionModel
                    index: sessionModel.lastIndex
                    color: "#4c566a"
                    textColor: "#eceff4"
                    borderColor: "#5e81ac"
                    focusColor: "#88c0d0"
                    hoverColor: "#81a1c1"

                    KeyNavigation.backtab: password
                    KeyNavigation.tab: layoutBox
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: textConstants.layout
                    color: "#eceff4"
                    font.pixelSize: 14
                }

                LayoutBox {
                    id: layoutBox
                    anchors.verticalCenter: parent.verticalCenter
                    width: 100
                    color: "#4c566a"
                    textColor: "#eceff4"
                    borderColor: "#5e81ac"
                    focusColor: "#88c0d0"
                    hoverColor: "#81a1c1"

                    KeyNavigation.backtab: session
                    KeyNavigation.tab: password
                }
            }
        }

        // Bottom bar - Power buttons
        Row {
            anchors.bottom: parent.bottom
            anchors.right: parent.right
            anchors.margins: 15
            spacing: 10

            Button {
                id: shutdownButton
                text: textConstants.shutdown
                height: 35
                width: 100
                color: "#bf616a"
                activeColor: "#d08770"
                pressedColor: "#a3515a"
                visible: sddm.canPowerOff

                onClicked: sddm.powerOff()

                KeyNavigation.backtab: password
                KeyNavigation.tab: rebootButton
            }

            Button {
                id: rebootButton
                text: textConstants.reboot
                height: 35
                width: 100
                color: "#d08770"
                activeColor: "#ebcb8b"
                pressedColor: "#a86951"
                visible: sddm.canReboot

                onClicked: sddm.reboot()

                KeyNavigation.backtab: shutdownButton
                KeyNavigation.tab: password
            }
        }
    }

    Component.onCompleted: {
        password.focus = true
    }
}