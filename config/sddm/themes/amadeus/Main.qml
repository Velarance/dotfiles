// Copyright © 2018 Michał Szczepaniak <m.szczepaniak.000@gmail.com>
// This work is free. You can redistribute it and/or modify it under the
// terms of the Do What The Fuck You Want To Public License, Version 2,
// as published by Sam Hocevar. See the COPYING file for more details.

import QtQuick 2.0
import SddmComponents 2.0
import "./components"

Rectangle {
  id  : amadeus_root

  property var scalingX: 1920/bg.paintedWidth
  property var scalingY: 1080/bg.paintedHeight
  property var diffX: (amadeus_root.width - bg.paintedWidth)/2
  property var diffY: (amadeus_root.height - bg.paintedHeight)/2
  property var inputColor: "#debf54"
  property var glow: "#60e6b656"
  property bool isPrimary: (config.MirrorScreens === "true") || primaryScreen
  property bool authenticating: false

  signal tryLogin()

  function dismissLoginError() {
    errorSequence.stop()
    loginError.opacity = 0.0
  }

  onTryLogin: {
    if (authenticating)
      return
    dismissLoginError()
    authenticating = true
    failureRestore.stop()
    submitTransition.start()
    sddm.login(amadeus_username.text, amadeus_password.text, amadeus_session.currentIndex)
  }

  FontLoader {
    id: takao_mincho
    source: "fonts/TakaoMincho.ttf"
  }

  TextConstants { id: textConstants }

  ListModel {
    id: powerModel
    ListElement { name: "System" }
    ListElement { name: "Sleep" }
    ListElement { name: "Restart" }
    ListElement { name: "Shut Down" }
  }

  Connections {
    target: sddm

    function onLoginFailed() {
      amadeus_root.authenticating = false
      errorSequence.stop()
      submitTransition.stop()
      loginError.opacity = 0.0
      amadeus_username.text = ""
      amadeus_password.text = ""
      if (isPrimary)
        amadeus_username.forceActiveFocus()
      failureRestore.start()
      errorSequence.start()
    }
  }

  Repeater {
    model: screenModel

    Item {
      Rectangle {
        x       : geometry.x
        y       : geometry.y
        width   : geometry.width
        height  : geometry.height
        color   : "black"
      }
    }
  }

  Image {
    id: secondaryBackground
    anchors.fill: parent
    source: "amadeus-secondary.png"
    fillMode: Image.PreserveAspectFit
    smooth: true
  }

  Item {
    id: primaryLayer
    anchors.fill: parent
    visible: isPrimary
    opacity: 1.0

  Image {
    id: bg
    anchors.fill: parent
    source: "amadeus-background.png"
    fillMode: Image.PreserveAspectFit

    clip: true
    focus: true
    smooth: true
  }

  Item {
    id: uiLayer
    anchors.fill: parent
    enabled: !amadeus_root.authenticating

  Loader {
    id: vkloader
    source: "vk.qml"
  }

  SpTextBox {
    id: amadeus_username
    onTextChanged: amadeus_root.dismissLoginError()

    x: 683/amadeus_root.scalingX + diffX
    y: 633/amadeus_root.scalingY + diffY

    width: 560/amadeus_root.scalingX
    height: 42/amadeus_root.scalingY

    visible: isPrimary
    color: "black"
    borderColor: "black"
    focusColor: "#000"
    hoverColor: "#000"
    textColor: inputColor
    glowColor: glow

    font.family: takao_mincho.name
    font.pixelSize: 27/amadeus_root.scalingY
    font.letterSpacing: 1.4
    font.bold: true

    KeyNavigation.tab: amadeus_password
  }

  SpTextBox {
    id: amadeus_password
    onTextChanged: amadeus_root.dismissLoginError()

    x: 683/amadeus_root.scalingX + diffX
    y: 699/amadeus_root.scalingY + diffY

    width: 560/amadeus_root.scalingX
    height: 46/amadeus_root.scalingY

    echoMode: TextInput.Password

    visible: isPrimary
    color: "black"
    borderColor: "black"
    focusColor: "#000"
    hoverColor: "#000"
    textColor: inputColor
    glowColor: glow

    font.family: takao_mincho.name
    font.pixelSize: 27/amadeus_root.scalingY

    KeyNavigation.tab: amadeus_session
    KeyNavigation.backtab: amadeus_username

    Keys.onPressed: {
      if ((event.key === Qt.Key_Return) || (event.key === Qt.Key_Enter)) {
        amadeus_root.tryLogin()

        event.accepted = true;
      }
    }
  }

  Text {
    id: loginError
    x: 683/amadeus_root.scalingX + diffX
    y: 765/amadeus_root.scalingY + diffY
    width: 560/amadeus_root.scalingX
    text: "incorrect data"
    color: "#e06c75"
    opacity: 0.0
    horizontalAlignment: Text.AlignHCenter
    font.family: takao_mincho.name
    font.pixelSize: 22/amadeus_root.scalingY
    font.bold: true
  }

  MouseArea {
      id: amadeus_login

      x       : 1254/amadeus_root.scalingX + diffX
      y       : 695/amadeus_root.scalingY + diffY
      width   : 50/amadeus_root.scalingX
      height  : 50/amadeus_root.scalingY

      cursorShape: Qt.PointingHandCursor

      hoverEnabled: true
      enabled: true

      acceptedButtons: Qt.LeftButton

      onClicked: { amadeus_root.tryLogin() }
  }

  SpComboBox {
    id: amadeus_session

    width: Math.max(300/amadeus_root.scalingX, amadeus_session.maxDelegateWidth + 130/amadeus_root.scalingX)
    height: 40/amadeus_root.scalingY

    x: (amadeus_root.width - width)/2
    y: 920/amadeus_root.scalingY + diffY

    model: sessionModel

    visible: isPrimary
    color: "black"
    borderColor: "#555555"
    focusColor: "#555555"
    hoverColor: "#000"
    borderWidth: 2
    textColor: inputColor
    glowColor: glow

    font.family: takao_mincho.name
    font.pixelSize: 22/amadeus_root.scalingY
    font.letterSpacing: 1.2
    font.bold: true

    KeyNavigation.tab: amadeus_power
    KeyNavigation.backtab: amadeus_password
  }

  SpComboBox {
    id: amadeus_power

    width: Math.max(200/amadeus_root.scalingX, amadeus_power.maxDelegateWidth + 80/amadeus_root.scalingX)
    height: 40/amadeus_root.scalingY

    x: 1858/amadeus_root.scalingX + diffX - width
    y: 1000/amadeus_root.scalingY + diffY

    model: powerModel

    visible: isPrimary
    color: "black"
    borderColor: "#555555"
    focusColor: "#555555"
    hoverColor: "#000"
    borderWidth: 2
    textColor: inputColor
    glowColor: glow

    font.family: takao_mincho.name
    font.pixelSize: 22/amadeus_root.scalingY
    font.letterSpacing: 1.2
    font.bold: true

    KeyNavigation.tab: amadeus_username
    KeyNavigation.backtab: amadeus_session

    onActivated: {
      if (index === 0) return;

      if (index === 1) {
        sddm.suspend();
      } else if (index === 2) {
        sddm.reboot();
      } else if (index === 3) {
        sddm.powerOff();
      }

      currentIndex = 0;
    }
  }

  Component.onCompleted: {
    if (amadeus_username.text === "")
      amadeus_username.focus = true
    else
      amadeus_password.focus = true
  }
  }
  }

  NumberAnimation {
    id: submitTransition
    target: primaryLayer
    property: "opacity"
    to: 0.0
    duration: 120
    easing.type: Easing.OutCubic
  }

  NumberAnimation {
    id: failureRestore
    target: primaryLayer
    property: "opacity"
    to: 1.0
    duration: 140
    easing.type: Easing.OutCubic
  }

  SequentialAnimation {
    id: errorSequence
    NumberAnimation {
      target: loginError
      property: "opacity"
      from: 0.0
      to: 1.0
      duration: 120
      easing.type: Easing.OutCubic
    }
    PauseAnimation { duration: 2120 }
    NumberAnimation {
      target: loginError
      property: "opacity"
      from: 1.0
      to: 0.0
      duration: 260
      easing.type: Easing.InCubic
    }
  }
}
