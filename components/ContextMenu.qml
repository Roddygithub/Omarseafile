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
    property var onCopyClicked: null
    property var onHistoryClicked: null
    property bool isDir: false
    property int selectionCount: 1

    width: parent.width
    implicitHeight: column.implicitHeight
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside | Popup.CloseOnPressOutsideParent

    Column {
        id: column
        width: parent.width
        spacing: Style.space(2)

        // Batch mode actions (when selectionCount > 1)
        Button {
            id: batchMoveBtn
            width: parent.width
            text: "Move"
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.body
            visible: root.selectionCount > 1 && root.onMoveClicked !== null
            onClicked: {
                if (root.onMoveClicked) root.onMoveClicked()
                root.close()
            }
        }

        Button {
            id: batchCopyBtn
            width: parent.width
            text: "Copy"
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.body
            visible: root.selectionCount > 1 && root.onCopyClicked !== null
            onClicked: {
                if (root.onCopyClicked) root.onCopyClicked()
                root.close()
            }
        }

        Button {
            id: batchDeleteBtn
            width: parent.width
            text: "Delete"
            color: Color.urgent
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.body
            visible: root.selectionCount > 1 && root.onDeleteClicked !== null
            onClicked: {
                if (root.onDeleteClicked) root.onDeleteClicked()
                root.close()
            }
        }

        // Single item actions (when selectionCount === 1)
        Button {
            id: shareBtn
            width: parent.width
            text: "Share"
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.body
            visible: root.selectionCount === 1 && root.onShareClicked !== null
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
            visible: root.selectionCount === 1
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
            visible: root.selectionCount === 1 && root.onMoveClicked !== null
            onClicked: {
                if (root.onMoveClicked) root.onMoveClicked(root.item)
                root.close()
            }
        }

        Button {
            id: copyBtn
            width: parent.width
            text: "Copy"
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.body
            visible: root.selectionCount === 1 && root.onCopyClicked !== null
            onClicked: {
                if (root.onCopyClicked) root.onCopyClicked(root.item)
                root.close()
            }
        }

        Button {
            id: historyBtn
            width: parent.width
            text: "History"
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.body
            visible: root.selectionCount === 1 && root.onHistoryClicked !== null
            onClicked: {
                if (root.onHistoryClicked) root.onHistoryClicked(root.item)
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
            visible: root.selectionCount === 1
            onClicked: {
                if (root.onDeleteClicked) root.onDeleteClicked(root.item)
                root.close()
            }
        }
    }
}