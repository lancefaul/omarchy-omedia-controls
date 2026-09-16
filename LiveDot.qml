import QtQuick

// A small dot that pulses slowly beside a LIVE label, so a live stream reads
// as live by motion as well as by colour. Animates only while visible, which
// for the popup means only while it is open.
Rectangle {
  id: root

  property real size: 6

  width: size
  height: size
  radius: size / 2

  SequentialAnimation on opacity {
    running: root.visible
    loops: Animation.Infinite
    alwaysRunToEnd: false

    NumberAnimation { from: 1; to: 0.25; duration: 1000; easing.type: Easing.InOutSine }
    NumberAnimation { from: 0.25; to: 1; duration: 1000; easing.type: Easing.InOutSine }
  }

  onVisibleChanged: if (!visible) opacity = 1
}
