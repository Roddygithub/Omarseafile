import QtQuick
import qs.Commons
import qs.Ui

Item {
    id: root
    property QtObject bar: null
    property string message: "Are you sure?"
    property var onConfirm: null
    property var onCancel: null

    width: parent.width
    implicitHeight: column.implicitHeight

    Column {
        id: column
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Style.space(16)
        width: Math.min(parent.width, Style.space(400))

        Text {
            text: "Confirm"
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.display
            font.bold: true
        }

        Text {
            text: root.message
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.body
            wrapMode: Text.WordWrap
            width: parent.width
        }

        Row {
            spacing: Style.space(12)

            Button {
                id: cancelButton
                width: parent.width / 2 - Style.space(6)
                text: "Cancel"
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.body
                onClicked: {
                    if (root.onCancel) root.onCancel()
                }
            }

            Button {
                id: confirmButton
                width: parent.width / 2 - Style.space(6)
                text: "Delete"
                color: Color.urgent
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.body
                onClicked: {
                    if (root.onConfirm) root.onConfirm()
                }
            }
        }
    }
}