import QtQuick
import qs.Commons
import qs.Ui
import "../js"

Item {
    id: root
    required property var bar
    property string icon: Icons.folder
    property string title: "Empty"
    property string subtitle: ""
    property var action: null
    property string actionText: ""

    width: parent.width
    implicitHeight: column.implicitHeight

    // Column is a positioner: it manages its children's positions, so setting
    // anchors on them is invalid and makes Qt warn while ignoring the anchor.
    // horizontalAlignment is the supported way to centre them.
    Column {
        id: column
        spacing: Style.space(12)
        horizontalAlignment: Qt.AlignHCenter

        Text {
            text: root.icon
            font.family: Icons.family
            font.pixelSize: 48
            color: Qt.darker(root.bar.foreground, 1.5)
        }

        Text {
            text: Models.boundedDisplayText(root.title, 1024)
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.body
            font.bold: true
            textFormat: Text.PlainText
        }

        Text {
            text: Models.boundedDisplayText(root.subtitle, 1024)
            color: Qt.darker(root.bar.foreground, 1.4)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
            visible: root.subtitle !== ""
            textFormat: Text.PlainText
        }

        Button {
            width: implicitWidth + Style.space(24)
            text: root.actionText
            visible: root.action !== null && root.actionText !== ""
            onClicked: {
                if (root.action) root.action()
            }
        }
    }
}