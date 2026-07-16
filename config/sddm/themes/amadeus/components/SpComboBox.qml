import QtQuick 2.0
import Qt5Compat.GraphicalEffects

FocusScope {
    id: container
    width: 250
    height: 40
    signal activated(int index)

    property var model
    property int currentIndex: 0
    property string currentText: "Select Session"
    property real maxDelegateWidth: 0

    property color color: "black"
    property color textColor: "#debf54"
    property color borderColor: "black"
    property color focusColor: "#debf54"
    property color hoverColor: "#e6b656"
    property color glowColor: "#60e6b656"
    property alias radius: mainButton.radius
    property font font
    property int borderWidth: 1

    property bool expanded: false

    onCurrentIndexChanged: {
        updateCurrentText();
    }

    function updateCurrentText() {
        if (listRepeater && currentIndex >= 0 && currentIndex < listRepeater.count) {
            var item = listRepeater.itemAt(currentIndex);
            if (item) {
                container.currentText = item.textValue;
            }
        }
    }

    // Main button (collapsed view)
    Rectangle {
        id: mainButton
        anchors.fill: parent
        color: container.color
        border.color: container.expanded ? container.focusColor : (mouseArea.containsMouse ? container.focusColor : container.borderColor)
        border.width: container.borderWidth

        Text {
            id: mainText
            anchors.centerIn: parent
            text: container.currentText + " ▼"
            color: container.textColor
            font: container.font
        }

        Glow {
            anchors.fill: mainText
            radius: 16
            samples: 33
            color: container.glowColor
            source: mainText
            visible: container.expanded || mouseArea.containsMouse || container.activeFocus
        }

        MouseArea {
            id: mouseArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                container.expanded = !container.expanded;
                container.focus = true;
            }
        }
    }

    // Dropdown list expanding upwards
    Rectangle {
        id: dropdownMenu
        width: parent.width
        height: container.expanded ? (listRepeater.count * parent.height) : 0
        anchors.bottom: mainButton.top
        anchors.left: mainButton.left
        color: container.color
        border.color: container.focusColor
        border.width: container.expanded ? container.borderWidth : 0
        visible: container.expanded && listRepeater.count > 0
        clip: true

        Behavior on height {
            NumberAnimation { duration: 150; easing.type: Easing.OutQuad }
        }

        Column {
            width: parent.width
            Repeater {
                id: listRepeater
                model: container.model

                delegate: Rectangle {
                    width: dropdownMenu.width
                    height: container.height
                    color: itemMouseArea.containsMouse ? "#121212" : container.color
                    property string textValue: name

                    border.color: itemMouseArea.containsMouse ? container.focusColor : "transparent"
                    border.width: 1

                    Text {
                        id: delegateText
                        anchors.centerIn: parent
                        text: name
                        color: itemMouseArea.containsMouse ? container.hoverColor : container.textColor
                        font: container.font
                    }

                    Glow {
                        anchors.fill: delegateText
                        radius: 8
                        samples: 17
                        color: container.glowColor
                        source: delegateText
                        visible: itemMouseArea.containsMouse
                    }

                    MouseArea {
                        id: itemMouseArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            container.currentIndex = index;
                            container.expanded = false;
			    container.activated(index);
                        }
                    }

                    Component.onCompleted: {
                        if (delegateText.implicitWidth > container.maxDelegateWidth) {
                            container.maxDelegateWidth = delegateText.implicitWidth;
                        }
                        if (index === container.currentIndex) {
                            container.currentText = name;
                        }
                    }
                }
            }
        }
    }

    onActiveFocusChanged: {
        if (!container.activeFocus) {
            container.expanded = false;
        }
    }

    Keys.onPressed: {
        if (event.key === Qt.Key_Down) {
            if (!container.expanded) {
                container.expanded = true;
            } else if (listRepeater.count > 0) {
                container.currentIndex = (container.currentIndex + 1) % listRepeater.count;
            }
            event.accepted = true;
        } else if (event.key === Qt.Key_Up) {
            if (!container.expanded) {
                container.expanded = true;
            } else if (listRepeater.count > 0) {
                container.currentIndex = (container.currentIndex - 1 + listRepeater.count) % listRepeater.count;
            }
            event.accepted = true;
        } else if (event.key === Qt.Key_Escape) {
            container.expanded = false;
            event.accepted = true;
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (container.expanded) {
                container.expanded = false;
                event.accepted = true;
		container.activated(container.currentIndex);
            }
        }
    }

    Component.onCompleted: {
        if (model) {
            currentIndex = model.lastIndex;
            updateCurrentText();
        }
    }
}
