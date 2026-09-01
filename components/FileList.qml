import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui
import "../js"

ListView {
    id: root
    property QtObject bar: null
    required property var items
    required property var onItemClicked
    required property var onDownloadClicked
    required property var onOpenClicked
    required property var onRenameClicked
    required property var onMoveClicked
    required property var onDeleteClicked
    required property var onShareClicked
    required property var onHistoryClicked
    required property var findTransfer
    required property int transferRevision
    required property var onSelectionToggle
    required property var onSelectionRange
    required property var onSelectOnly
    required property var onPositionClicked
    required property var onContextMenuRequested
    required property var selectedItems
    required property var selectionAnchor
    property var onSortChanged: null

    property string sortColumn: "name"
    property bool sortAscending: true

    width: parent.width
    height: parent.height
    clip: true
    spacing: Style.space(2)
    keyNavigationEnabled: true
    highlightFollowsCurrentItem: true

    // Sorted model for display
    property var sortedItems: {
        var items = root.items.slice()
        items.sort(function(a, b) {
            var aIsDir = a.type === "dir"
            var bIsDir = b.type === "dir"
            if (root.sortColumn !== "type" && aIsDir !== bIsDir) {
                return aIsDir ? -1 : 1
            }
            var valA, valB
            switch (root.sortColumn) {
                case "name": valA = a.name.toLowerCase(); valB = b.name.toLowerCase(); break
                case "size": valA = a.size || 0; valB = b.size || 0; break
                case "date": valA = a.mtime || 0; valB = b.mtime || 0; break
                case "type": valA = a.type === "dir" ? 0 : 1; valB = b.type === "dir" ? 0 : 1; break
            }
            if (valA < valB) return root.sortAscending ? -1 : 1
            if (valA > valB) return root.sortAscending ? 1 : -1
            return a.name.localeCompare(b.name)
        })
        return items
    }

    function toggleSort(column) {
        if (root.sortColumn === column) {
            root.sortAscending = !root.sortAscending
        } else {
            root.sortColumn = column
            root.sortAscending = true
        }
        if (root.onSortChanged) root.onSortChanged()
    }

    model: root.sortedItems


delegate: FileItem {
                            required property var modelData
                            required property int index
                            item: modelData
                            itemIndex: index
                            bar: root.bar
                            onItemClicked: root.onItemClicked
                            onDownloadClicked: root.onDownloadClicked
                            onOpenClicked: root.onOpenClicked
                            onRenameClicked: root.onRenameClicked
                            onMoveClicked: root.onMoveClicked
                            onDeleteClicked: root.onDeleteClicked
                            onShareClicked: root.onShareClicked
                            onHistoryClicked: root.onHistoryClicked
                            findTransfer: root.findTransfer
                            transferRevision: root.transferRevision
                            onSelectionToggle: root.onSelectionToggle
                            onSelectionRange: root.onSelectionRange
                            onSelectOnly: root.onSelectOnly
                            onPositionClicked: root.onPositionClicked
                            onContextMenuRequested: root.onContextMenuRequested
        selected: {
            for (var i = 0; i < root.selectedItems.length; i++) {
                if (SelectionHelper.makeKey(root.selectedItems[i]) === SelectionHelper.makeKey(modelData)) {
                    return true
                }
            }
            return false
        }
    }

    header: Item {
        id: sortHeader
        visible: root.items.length > 0
        width: root.width
        height: visible ? Style.space(24) : 0

        Row {
            anchors.fill: parent
            anchors.leftMargin: Style.space(12)
            anchors.rightMargin: Style.space(12)
            spacing: Style.space(12)

            // Icon column = Type sort (matches FileItem icon column)
            MouseArea {
                width: Style.space(24)
                height: parent.height
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: { root.toggleSort("type"); }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.sortColumn === "type" ? (root.sortAscending ? "▲" : "▼") : ""
                    color: Color.accent
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.caption
                }
            }

            // Name column (flex)
            MouseArea {
                width: parent.width - Style.space(24) - Style.space(80) - Style.space(150) - Style.space(36)
                height: parent.height
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: { root.toggleSort("name"); }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    text: root.sortColumn === "name" ? (root.sortAscending ? "Name ▲" : "Name ▼") : "Name"
                    color: root.sortColumn === "name" ? Color.accent : root.bar.foreground
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: root.sortColumn === "name"
                    elide: Text.ElideRight
                }
            }

            // Size column (matches FileItem sizeLabel)
            MouseArea {
                width: Style.space(80)
                height: parent.height
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: { root.toggleSort("size"); }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    horizontalAlignment: Text.AlignRight
                    text: root.sortColumn === "size" ? (root.sortAscending ? "Size ▲" : "Size ▼") : "Size"
                    color: root.sortColumn === "size" ? Color.accent : root.bar.foreground
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: root.sortColumn === "size"
                }
            }

            // Modified date column (matches FileItem dateLabel)
            MouseArea {
                width: Style.space(150)
                height: parent.height
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: { root.toggleSort("date"); }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    horizontalAlignment: Text.AlignRight
                    text: root.sortColumn === "date" ? (root.sortAscending ? "Modified ▲" : "Modified ▼") : "Modified"
                    color: root.sortColumn === "date" ? Color.accent : root.bar.foreground
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: root.sortColumn === "date"
                    elide: Text.ElideRight
                }
            }
        }
    }

    ScrollBar.vertical: ScrollBar {
        policy: ScrollBar.AsNeeded
    }
}
