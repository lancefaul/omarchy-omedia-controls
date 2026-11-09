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
  // A new title starts again from the beginning. Text that only ticks, such as
  // a running time, keeps scrolling instead, or it would never get past the
  // start.
  property bool restartOnTextChange: true
  // Held still (running false), scroll while the pointer is over it, so the
  // whole text can still be read. Off by default: the bar's own title area
  // handles its pointer itself.
  property bool scrollOnHover: false

  // The width the text wants, for callers that size to it.
  readonly property real contentWidth: label.implicitWidth
  readonly property bool overflowing: label.implicitWidth > width + 1
  readonly property bool scrolling: (running || hoverArea.containsMouse) && overflowing && visible

  // The whole text for a screen reader, whatever is on screen.
  Accessible.role: Accessible.StaticText
  Accessible.name: text

  MouseArea {
    id: hoverArea
    anchors.fill: parent
    enabled: root.scrollOnHover
    hoverEnabled: true
    acceptedButtons: Qt.NoButton
  }

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
    // Never both. Text that is allowed to scroll says the whole thing by
    // scrolling, so an ellipsis on it would be a second, contradictory answer
    // to the same question — and it shows up for real in the frame after a
    // track change, before the new text has been measured and the glide has
    // started. Only text that has been told not to move is cut short.
    elide: root.running || hoverArea.containsMouse ? Text.ElideNone : Text.ElideRight
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
    if (!restartOnTextChange) return
    label.x = 0
    if (scrolling) ticker.restart()
  }
  onWidthChanged: if (scrolling) ticker.restart()
}
