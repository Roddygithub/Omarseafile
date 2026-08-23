import QtQuick
import qs.Commons
import qs.Ui

Item {
    id: root
    property QtObject bar: null
    property alias nameField: nameField
    property alias renameButton: renameButton
    property alias cancelButton: cancelButton
    property alias errorText: errorText
    property string title: "Rename"
    property var onRename: null
    property var onCancel: null

    width: parent.width
    implicitHeight: column.implicitHeight
    height: implicitHeight

    Column {
        id: column
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Style.space(16)
        width: Math.min(parent.width, Style.space(400))

        Text {
            text: root.title
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.display
            font.bold: true
        }

        TextField {
            id: nameField
            width: parent.width
            placeholderText: "New name"
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.body
        }

        Text {
            id: errorText
            width: parent.width
            color: Color.urgent
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
            visible: text !== ""
            wrapMode: Text.WordWrap
        }

        Row {
            spacing: Style.space(12)
            width: parent.width

            Button {
                id: cancelButton
                width: parent.width / 2 - Style.space(6)
                text: "Cancel"
                onClicked: {
                    if (root.onCancel) root.onCancel()
                }
            }

            Button {
                id: renameButton
                width: parent.width / 2 - Style.space(6)
                text: "Rename"
                onClicked: {
                    if (root.onRename) root.onRename()
                }
            }
        }
    }
}