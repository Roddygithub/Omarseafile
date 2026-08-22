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
    }

    ScrollBar.vertical: ScrollBar {
        policy: ScrollBar.AsNeeded
    }
}
