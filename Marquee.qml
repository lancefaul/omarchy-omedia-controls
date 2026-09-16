import QtQuick

// One line of text that scrolls when it does not fit, the way Winamp's title
// ticker does: hold at the start, glide to the end, hold, jump back. Elided
// while `running` is false, so a caller decides when motion is worth its
// cost — the popup scrolls only while open, the bar only under the pointer.
Item {
  id: root

  property string text: ""
  property color color: "white"
  property alias font: label.font
  property bool running: true
  // Glide speed in pixels per second, and the hold at each end.
  property real speed: 40
  property int holdMs: 1800

  // The width the text wants, for callers that size to it.
  readonly property real contentWidth: label.implicitWidth
  readonly property bool overflowing: label.implicitWidth > width + 1
  readonly property bool scrolling: running && overflowing && visible

  implicitWidth: label.implicitWidth
  implicitHeight: label.implicitHeight
  clip: true

  Text {
    id: label
    anchors.verticalCenter: parent.verticalCenter
    textFormat: Text.PlainText
    text: root.text
    color: root.color
    width: root.scrolling ? implicitWidth : root.width
    elide: root.scrolling ? Text.ElideNone : Text.ElideRight
  }

  SequentialAnimation {
    id: ticker
    running: root.scrolling
    loops: Animation.Infinite

    PropertyAction { target: label; property: "x"; value: 0 }
    PauseAnimation { duration: root.holdMs }
    NumberAnimation {
      target: label
      property: "x"
      to: root.width - label.implicitWidth
      duration: Math.max(1, (label.implicitWidth - root.width) / Math.max(1, root.speed) * 1000)
    }
    PauseAnimation { duration: root.holdMs }
  }

  onScrollingChanged: if (!scrolling) label.x = 0
  // A new title starts from the beginning rather than mid-glide.
  onTextChanged: {
    label.x = 0
    if (scrolling) ticker.restart()
  }
  onWidthChanged: if (scrolling) ticker.restart()
}
