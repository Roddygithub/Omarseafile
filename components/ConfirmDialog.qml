import QtQuick
import qs.Commons
import qs.Ui
import "../js"

Item {
    id: root
    property QtObject bar: null
    property string message: "Are you sure?"
    property string confirmText: "Delete"
    property var onConfirm: null
    property var onCancel: null

    width: parent.width
    implicitHeight: column.implicitHeight
    height: implicitHeight

    Component.onCompleted: cancelButton.forceActiveFocus()

    Rectangle {
        anchors.fill: parent
        color: Qt.darker(root.bar ? root.bar.background : Color.background, 1.1)
        border.color: Color.accent
        border.width: Style.spacing.hairline
        radius: Style.cornerRadius
    }

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
            text: Models.boundedDisplayText(root.message, 4096)
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.body
            wrapMode: Text.WordWrap
            width: parent.width
            textFormat: Text.PlainText
        }

        Row {
            spacing: Style.space(12)
            width: parent.width

            Button {
                id: cancelButton
                width: parent.width / 2 - Style.space(6)
                text: "Cancel"
                Keys.onEscapePressed: function(event) {
                    event.accepted = true
                    if (root.onCancel) root.onCancel()
                }
                onClicked: {
                    if (root.onCancel) root.onCancel()
                }
            }

            Button {
                id: confirmButton
                width: parent.width / 2 - Style.space(6)
                text: root.confirmText
                color: Color.urgent
                onClicked: {
                    if (root.onConfirm) root.onConfirm()
                }
            }
        }
    }
}
