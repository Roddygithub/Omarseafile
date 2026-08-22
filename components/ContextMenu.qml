import QtQuick
import qs.Commons
import qs.Ui

Popup {
    id: root
    property var item: null
    property var onRenameClicked: null
    property var onMoveClicked: null
    property var onDeleteClicked: null
    property var onShareClicked: null
    property bool isDir: false

    width: parent.width
    implicitHeight: column.implicitHeight
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside | Popup.CloseOnPressOutsideParent

    Column {
        id: column
        width: parent.width
        spacing: Style.space(2)

        Button {
            id: shareBtn
            width: parent.width
            text: "Share"
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.body
            visible: root.onShareClicked !== null
            onClicked: {
                if (root.onShareClicked) root.onShareClicked(root.item)
                root.close()
            }
        }

        Button {
            id: renameBtn
            width: parent.width
            text: "Rename"
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.body
            onClicked: {
                if (root.onRenameClicked) root.onRenameClicked(root.item)
                root.close()
            }
        }

        Button {
            id: moveBtn
            width: parent.width
            text: "Move"
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.body
            visible: root.onMoveClicked !== null
            onClicked: {
                if (root.onMoveClicked) root.onMoveClicked(root.item)
                root.close()
            }
        }

        Button {
            id: deleteBtn
            width: parent.width
            text: "Delete"
            color: Color.urgent
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.body
            onClicked: {
                if (root.onDeleteClicked) root.onDeleteClicked(root.item)
                root.close()
            }
        }
    }
}