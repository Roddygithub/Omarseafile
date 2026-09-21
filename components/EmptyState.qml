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

    // Column is a positioner; Qt only forbids fill/centerIn/verticalCenter/
    // top/bottom anchors on its direct children. horizontalCenter is permitted,
    // so each child centres itself in the full-width Column, which in turn
    // spans the parent — this is what actually centres the whole block.
    Column {
        id: column
        width: parent.width
        spacing: Style.space(12)

        Text {
            text: root.icon
            font.family: Icons.family
            font.pixelSize: 48
            color: Qt.darker(root.bar.foreground, 1.5)
            anchors.horizontalCenter: parent.horizontalCenter
        }

        Text {
            text: Models.boundedDisplayText(root.title, 1024)
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.body
            font.bold: true
            textFormat: Text.PlainText
            anchors.horizontalCenter: parent.horizontalCenter
        }

        Text {
            text: Models.boundedDisplayText(root.subtitle, 1024)
            color: Qt.darker(root.bar.foreground, 1.4)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
            visible: root.subtitle !== ""
            textFormat: Text.PlainText
            anchors.horizontalCenter: parent.horizontalCenter
        }

        Button {
            width: implicitWidth + Style.space(24)
            text: root.actionText
            visible: root.action !== null && root.actionText !== ""
            anchors.horizontalCenter: parent.horizontalCenter
            onClicked: {
                if (root.action) root.action()
            }
        }
    }
}