import QtQuick
import qs.Commons
import qs.Ui

// One equalizer band: a vertical slider, since Omarchy's PanelSlider is
// horizontal only and an equalizer is the one place the upright shape carries
// meaning — ten of them side by side are the curve. Built from the same track,
// fill and knob as PanelSlider so it belongs to the same panel, with the fill
// growing from the centre rather than the bottom: a band is a boost or a cut
// from flat, not an amount of something.
Item {
  id: root

  property QtObject bar: null
  property real value: 0
  property real minimum: -12
  property real maximum: 12
  property real step: 1
  property bool dragging: false
  property real liveValue: value
  property color trackColor: bar ? Style.selectedFillFor(bar.foreground, Color.accent) : "#333"
  // Not the full foreground. Eleven of these side by side at full brightness,
  // each a bright bar against a dark track, set up a black-and-white flicker
  // between them that the eye reads before it reads the curve. Pulled back far
  // enough that the shape comes first and the bars stop fighting each other.
  property color fillColor: bar ? Qt.darker(bar.foreground, 1.45) : Color.foreground
  property color knobColor: bar ? Qt.darker(bar.foreground, 1.3) : Color.foreground
  property real trackWidth: Math.max(4, Math.round(Style.spacing.controlHeight * 0.11))
  property real knobSize: Math.max(12, Math.round(Style.spacing.controlHeight * 0.32))

  onValueChanged: if (!dragging) liveValue = value

  signal moved(real value)
  signal released(real value)

  implicitWidth: Math.max(Style.space(18), knobSize + Style.spacing.sm)
  implicitHeight: Style.space(110)

  readonly property real range: Math.max(0.0001, maximum - minimum)
  // 0 at the bottom, 1 at the top, and 0.5 where the band does nothing.
  readonly property real progress: Math.max(0, Math.min(1, (liveValue - minimum) / range))
  readonly property real middle: Math.max(0, Math.min(1, (0 - minimum) / range))
  readonly property bool _hot: mouseArea.containsMouse || root.dragging

  Rectangle {
    id: track
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    width: root.trackWidth
    radius: width / 2
    color: root.trackColor
  }

  // From the centre line to wherever the band sits, up or down.
  Rectangle {
    anchors.horizontalCenter: track.horizontalCenter
    width: track.width
    radius: track.radius
    color: root.fillColor
    y: track.y + track.height * (1 - Math.max(root.progress, root.middle))
    height: track.height * Math.abs(root.progress - root.middle)

    Behavior on y {
      enabled: !root.dragging
      NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
    }
    Behavior on height {
      enabled: !root.dragging
      NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
    }
  }

  BorderSurface {
    id: knob
    width: root.knobSize
    height: root.knobSize
    radius: root.knobSize / 2
    color: root._hot ? (root.bar ? root.bar.foreground : Color.foreground) : root.knobColor
    borderSpec: Border.flat(root.bar ? root.bar.background : "#101315", Math.max(1, Style.space(2)))
    anchors.horizontalCenter: track.horizontalCenter
    y: Math.max(0, Math.min(track.height - height, track.height * (1 - root.progress) - height / 2))
    scale: root._hot ? 1.15 : 1.0

    Behavior on y {
      enabled: !root.dragging
      NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
    }
    Behavior on scale {
      NumberAnimation { duration: 110; easing.type: Easing.OutCubic }
    }
  }

  MouseArea {
    id: mouseArea
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton | Qt.RightButton

    // Upside down against the screen: the top of the track is the most boost.
    function valueFromY(y) {
      var clamped = Math.max(0, Math.min(track.height, y))
      var raw = root.minimum + (1 - clamped / track.height) * root.range
      return Math.max(root.minimum, Math.min(root.maximum, raw))
    }

    onPressed: function(mouse) {
      if (mouse.button !== Qt.LeftButton) return
      root.dragging = true
      var next = valueFromY(mouse.y)
      root.liveValue = next
      root.moved(next)
    }
    // Right-click puts one band back to flat, as double-clicking a fader does.
    onClicked: function(mouse) {
      if (mouse.button !== Qt.RightButton) return
      root.liveValue = 0
      root.moved(0)
      root.released(0)
    }
    onPositionChanged: function(mouse) {
      if (!root.dragging) return
      var next = valueFromY(mouse.y)
      root.liveValue = next
      root.moved(next)
    }
    onReleased: function(mouse) {
      if (mouse.button !== Qt.LeftButton) return
      root.dragging = false
      root.released(root.liveValue)
      root.liveValue = root.value
    }
    onWheel: function(wheel) {
      var delta = wheel.angleDelta.y > 0 ? root.step : -root.step
      var next = Math.max(root.minimum, Math.min(root.maximum, root.liveValue + delta))
      root.liveValue = next
      root.moved(next)
      root.released(next)
    }
  }
}
