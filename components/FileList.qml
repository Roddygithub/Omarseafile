import QtQuick
import qs.Commons
import qs.Ui

ListView {
    id: root
    required property var items
    required property var onItemClicked
    required property var onDownloadClicked
    required property var onRenameClicked
    required property var onMoveClicked
    required property var onDeleteClicked
    required property var onShareClicked
    required property var onHistoryClicked
    required property var findTransfer
    required property int transferRevision
    required property var onSelectionToggle
    required property var onSelectionRange
    required property var selectedItems
    required property var selectionAnchor

    width: parent.width
    height: parent.height
    clip: true
    spacing: Style.space(2)
    keyNavigationEnabled: true
    highlightFollowsCurrentItem: true

    model: root.items

    delegate: FileItem {
        required property var item: modelData
        required property var onItemClicked: root.onItemClicked
        required property var onDownloadClicked: root.onDownloadClicked
        required property var onRenameClicked: root.onRenameClicked
        required property var onMoveClicked: root.onMoveClicked
        required property var onDeleteClicked: root.onDeleteClicked
        required property var onShareClicked: root.onShareClicked
        required property var onHistoryClicked: root.onHistoryClicked
        required property var findTransfer: root.findTransfer
        required property int transferRevision: root.transferRevision
        required property var onSelectionToggle: root.onSelectionToggle
        required property var onSelectionRange: root.onSelectionRange
        required property bool selected: {
            for (var i = 0; i < root.selectedItems.length; i++) {
                if (root.selectedItems[i].id === modelData.id && root.selectedItems[i].repoId === modelData.repoId) {
                    return true
                }
            }
            return false
        }
        required property var selectionAnchor: root.selectionAnchor
    }

    ScrollBar.vertical: ScrollBar {
        policy: ScrollBar.AsNeeded
    }
}