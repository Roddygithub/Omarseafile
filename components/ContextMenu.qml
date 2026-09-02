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

    signal openClicked(var item)
    signal downloadClicked(var item)
    signal renameClicked(var item)
    signal moveClicked(var item)
    signal copyClicked(var item)
    signal deleteClicked(var item)
    signal shareClicked(var item)
    signal historyClicked(var item)

    readonly property bool batchMode: selectionCount > 1

    width: Style.space(180)
    implicitHeight: column.implicitHeight + topPadding + bottomPadding
    padding: Style.space(4)
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside | Popup.CloseOnPressOutsideParent

    Column {
        id: column
        width: parent.width
        spacing: Style.space(2)

        Button {
            width: parent.width
            text: "Open"
            visible: !root.batchMode && !root.isDir
            onClicked: {
                root.openClicked(root.item)
                root.close()
            }
        }

        Button {
            width: parent.width
            text: "Open"
            visible: !root.batchMode && root.isDir
            onClicked: {
                root.openClicked(root.item)
                root.close()
            }
        }

        Button {
            width: parent.width
            text: "Download"
            visible: !root.batchMode && !root.isDir
            onClicked: {
                root.downloadClicked(root.item)
                root.close()
            }
        }

        Button {
            width: parent.width
            text: "Share"
            visible: !root.batchMode
            onClicked: {
                root.shareClicked(root.item)
                root.close()
            }
        }

        Button {
            width: parent.width
            text: "Rename"
            visible: !root.batchMode
            onClicked: {
                root.renameClicked(root.item)
                root.close()
            }
        }

        Button {
            width: parent.width
            text: root.batchMode ? "Move " + root.selectionCount + " items" : "Move"
            visible: !root.batchMode
            onClicked: {
                root.moveClicked(root.item)
                root.close()
            }
        }

        Button {
            width: parent.width
            text: root.batchMode ? "Copy " + root.selectionCount + " items" : "Copy"
            visible: !root.batchMode
            onClicked: {
                root.copyClicked(root.item)
                root.close()
            }
        }

        Button {
            width: parent.width
            text: "History"
            visible: !root.batchMode && !root.isDir
            onClicked: {
                root.historyClicked(root.item)
                root.close()
            }
        }

        Button {
            width: parent.width
            text: "Delete"
            visible: true
            onClicked: {
                root.deleteClicked(root.item)
                root.close()
            }
        }
    }
}
