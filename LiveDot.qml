import QtQuick

// A small dot that pulses slowly beside a LIVE label, so a live stream reads
// as live by motion as well as by colour. Animates only while visible, which
// for the popup means only while it is open.
Rectangle {
  id: root

  property real size: 6
  // Off, the dot is steady (the popup's "Moving text" setting, audit #3).
  property bool animated: true

  width: size
  height: size
  radius: size / 2

  SequentialAnimation on opacity {
    running: root.visible && root.animated
    loops: Animation.Infinite
    alwaysRunToEnd: false

    NumberAnimation { from: 1; to: 0.25; duration: 1000; easing.type: Easing.InOutSine }
    NumberAnimation { from: 0.25; to: 1; duration: 1000; easing.type: Easing.InOutSine }
  }

  onVisibleChanged: if (!visible) opacity = 1
  onAnimatedChanged: if (!animated) opacity = 1
}
