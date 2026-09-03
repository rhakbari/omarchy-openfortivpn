import QtQuick
import qs.Commons

// One label/value line in the connection-details block. The dotted leader keeps
// the values right-aligned in a column without needing a real grid.
Item {
  id: row

  required property color foreground
  required property color dim
  required property string fontFamily
  property string label: ""
  property string value: ""

  width: parent ? parent.width : 0
  implicitHeight: Math.max(labelText.implicitHeight, valueText.implicitHeight)

  Text {
    id: labelText
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    text: row.label
    textFormat: Text.PlainText
    color: row.dim
    font.family: row.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  Text {
    id: valueText
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    // Never let a long value crowd out its own label.
    width: Math.min(implicitWidth, row.width - labelText.implicitWidth - Style.space(16))
    horizontalAlignment: Text.AlignRight
    text: row.value
    textFormat: Text.PlainText
    color: row.foreground
    elide: Text.ElideLeft
    font.family: row.fontFamily
    font.pixelSize: Style.font.bodySmall
  }
}
