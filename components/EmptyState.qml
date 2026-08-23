import QtQuick
import qs.Commons
import qs.Ui

Item {
    id: root
    required property var bar
    property string icon: "\uf07b"
    property string title: "Empty"
    property string subtitle: ""
    property var action: null
    property string actionText: ""

    width: parent.width
    implicitHeight: column.implicitHeight

    Column {
        id: column
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Style.space(12)

        Text {
            text: root.icon
            font.family: "Noto Sans"
            font.pixelSize: 48
            color: Qt.darker(root.bar.foreground, 1.5)
            anchors.horizontalCenter: parent.horizontalCenter
        }

        Text {
            text: root.title
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.body
            font.bold: true
            anchors.horizontalCenter: parent.horizontalCenter
        }

        Text {
            text: root.subtitle
            color: Qt.darker(root.bar.foreground, 1.4)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
            anchors.horizontalCenter: parent.horizontalCenter
            visible: root.subtitle !== ""
        }

        Button {
            width: implicitWidth + Style.space(24)
            text: root.actionText
            visible: root.action !== null && root.actionText !== ""
            onClicked: {
                if (root.action) root.action()
            }
            anchors.horizontalCenter: parent.horizontalCenter
        }
    }
}