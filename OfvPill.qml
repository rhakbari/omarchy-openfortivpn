import QtQuick
import qs.Commons

// Compact pill button used for the per-profile row actions.
//
// `tone` picks the palette role rather than a literal colour, so the control
// stays correct under every Omarchy theme: "normal" follows the bar foreground,
// "accent" marks the affirmative action, "urgent" the destructive one.
Rectangle {
  id: pill

  required property color foreground
  required property color dim
  required property string fontFamily
  property color accentColor: Color.accent
  property color urgentColor: Color.urgent
  property string label: ""
  property string tone: "normal"
  property bool filled: false

  signal activated()

  readonly property color toneColor: tone === "accent" ? accentColor
    : tone === "urgent" ? urgentColor
    : foreground

  implicitWidth: labelItem.implicitWidth + Style.space(18)
  implicitHeight: Style.space(26)
  radius: Style.cornerRadius > 0 ? Style.space(13) : Style.space(3)

  color: {
    if (!enabled) return "transparent"
    if (filled) return Qt.rgba(toneColor.r, toneColor.g, toneColor.b, mouse.containsMouse ? 0.28 : 0.18)
    return mouse.containsMouse ? Qt.rgba(foreground.r, foreground.g, foreground.b, 0.12) : "transparent"
  }

  border.width: 1
  border.color: filled
    ? Qt.rgba(toneColor.r, toneColor.g, toneColor.b, 0.55)
    : (tone === "normal" ? dim : Qt.rgba(toneColor.r, toneColor.g, toneColor.b, 0.5))
  opacity: enabled ? 1 : 0.4

  Behavior on color { ColorAnimation { duration: 90 } }

  Text {
    id: labelItem
    anchors.centerIn: parent
    text: pill.label
    textFormat: Text.PlainText
    color: pill.toneColor
    font.family: pill.fontFamily
    font.pixelSize: Style.font.caption
    font.bold: pill.filled
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    enabled: pill.enabled
    onClicked: pill.activated()
  }
}
