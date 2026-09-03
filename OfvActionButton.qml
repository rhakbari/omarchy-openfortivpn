import QtQuick
import qs.Commons

// Full-width button for the panel's primary actions (import, retry).
Rectangle {
  id: button

  required property color foreground
  required property color dim
  required property string fontFamily
  property string label: ""
  property string iconText: ""

  signal activated()

  height: Style.space(38)
  radius: Style.cornerRadius > 0 ? Style.space(6) : Style.space(3)
  color: mouse.containsMouse && enabled
    ? Qt.rgba(foreground.r, foreground.g, foreground.b, 0.10)
    : "transparent"
  border.width: 1
  border.color: dim
  opacity: enabled ? 1 : 0.45

  Behavior on color { ColorAnimation { duration: 90 } }

  Row {
    anchors.centerIn: parent
    spacing: Style.space(8)

    Text {
      anchors.verticalCenter: parent.verticalCenter
      visible: button.iconText !== ""
      text: button.iconText
      color: button.foreground
      font.family: button.fontFamily
      font.pixelSize: Style.font.bodySmall
    }
    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: button.label
      textFormat: Text.PlainText
      color: button.foreground
      font.family: button.fontFamily
      font.pixelSize: Style.font.body
    }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    enabled: button.enabled
    onClicked: button.activated()
  }
}
