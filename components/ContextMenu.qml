import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui

Popup {
    id: root

    property var item: null
    property bool isDir: false
    property int selectionCount: 1
    property QtObject bar: null
    property var onOpenClicked: null
    property var onDownloadClicked: null
    property var onRenameClicked: null
    property var onMoveClicked: null
    property var onCopyClicked: null
    property var onDeleteClicked: null
    property var onShareClicked: null
    property var onHistoryClicked: null

    readonly property bool batchMode: selectionCount > 1

    width: Style.space(180)
    implicitHeight: column.implicitHeight + topPadding + bottomPadding
    padding: Style.space(4)
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside | Popup.CloseOnPressOutsideParent

    function run(handler, arg) {
        if (!handler) return
        if (arg === undefined) handler()
        else handler(arg)
        root.close()
    }

    Column {
        id: column
        width: parent.width
        spacing: Style.space(2)

        Button {
            width: parent.width
            text: "Open"
            visible: !root.batchMode && root.isDir && root.onOpenClicked !== null
            onClicked: root.run(root.onOpenClicked, root.item)
        }

        Button {
            width: parent.width
            text: "Download"
            visible: !root.batchMode && !root.isDir && root.onDownloadClicked !== null
            onClicked: root.run(root.onDownloadClicked, root.item)
        }

        Button {
            width: parent.width
            text: "Share"
            visible: !root.batchMode && root.onShareClicked !== null
            onClicked: root.run(root.onShareClicked, root.item)
        }

        Button {
            width: parent.width
            text: "Rename"
            visible: !root.batchMode && root.onRenameClicked !== null
            onClicked: root.run(root.onRenameClicked, root.item)
        }

        Button {
            width: parent.width
            text: root.batchMode ? "Move " + root.selectionCount + " items" : "Move"
            visible: root.onMoveClicked !== null
            onClicked: root.run(root.onMoveClicked, root.batchMode ? undefined : root.item)
        }

        Button {
            width: parent.width
            text: root.batchMode ? "Copy " + root.selectionCount + " items" : "Copy"
            visible: root.onCopyClicked !== null
            onClicked: root.run(root.onCopyClicked, root.batchMode ? undefined : root.item)
        }

        Button {
            width: parent.width
            text: "History"
            visible: !root.batchMode && !root.isDir && root.onHistoryClicked !== null
            onClicked: root.run(root.onHistoryClicked, root.item)
        }

        Button {
            width: parent.width
            text: "Delete"
            visible: root.onDeleteClicked !== null
            onClicked: root.run(root.onDeleteClicked, root.batchMode ? undefined : root.item)
        }
    }
}
