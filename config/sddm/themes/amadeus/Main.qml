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

  signal tryLogin()

  onTryLogin : {
    loginSequence.start()
    sddm.login(amadeus_username.text, amadeus_password.text, amadeus_session.currentIndex);
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
  
  Loader {
      id: vkloader
      source: "vk.qml"
  }

  Connections {
    target: sddm

    onLoginSucceeded: {
    }

    onLoginFailed: {
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
    id: bg
    anchors.fill: parent
    source: isPrimary ? "amadeus-background.png" : "amadeus-secondary.png"
    fillMode: Image.PreserveAspectFit

    clip: true
    focus: true
    smooth: true
  }

  SpTextBox {
    id: amadeus_username

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

    x: 1870/amadeus_root.scalingX + diffX - width
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


  AnimatedImage {
    id: splashGif
    source: "kurisu.gif"

    anchors.centerIn: parent

    opacity: 0.0
    scale: 0.5

  SequentialAnimation {
    id: loginSequence
    ParallelAnimation {
      NumberAnimation {
        target: splashGif
        property: "opacity"
        from: 0.0
        to: 1.0
        duration: 1000
        easing.type: Easing.OutExpo
      }
      NumberAnimation {
        target: splashGif
        property: "scale"
        from: 0.5
        to: 1.0
        duration: 1000
        easing.type: Easing.OutExpo
      }
    }

    PauseAnimation {
      duration: 500
    }

    ParallelAnimation {
      NumberAnimation {
        target: splashGif
        property: "opacity"
        from: 1.0
        to: 0.0
        duration: 1000
        easing.type: Easing.InExpo
      }
      NumberAnimation {
        target: splashGif
        property: "scale"
        from: 1.0
        to: 0.5
        duration: 1000
        easing.type: Easing.InExpo
      }
    }
  }
  }
}
