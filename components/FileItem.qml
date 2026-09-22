import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui
import "../js"

Item {
    id: root
    required property var item
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
    required property bool selected
    property int itemIndex: -1
    property QtObject bar: null
    property bool singleClickOpen: false

    readonly property var safeItem: item || {}

    function iconForItem(value) {
        if (!value || value.type === "dir") return Icons.folder
        var name = String(value.name || "").toLowerCase()
        var dot = name.lastIndexOf(".")
        var ext = dot >= 0 ? name.substring(dot + 1) : ""
        if (ext === "pdf") return Icons.filePdf
        if (["doc", "docx", "odt", "rtf"].indexOf(ext) >= 0) return Icons.fileWord
        if (["xls", "xlsx", "ods", "csv"].indexOf(ext) >= 0) return Icons.fileExcel
        if (["ppt", "pptx", "odp"].indexOf(ext) >= 0) return Icons.filePowerpoint
        if (["png", "jpg", "jpeg", "gif", "webp", "svg"].indexOf(ext) >= 0) return Icons.fileImage
        if (["zip", "tar", "gz", "bz2", "7z", "rar"].indexOf(ext) >= 0) return Icons.fileArchive
        if (["c", "cpp", "h", "hpp", "js", "qml", "py", "sh", "json", "xml", "html", "css"].indexOf(ext) >= 0) return Icons.fileCode
        return Icons.file
    }

    // Single guarded read of the ListView attached property. `ListView` is an
    // attached object that is null when the delegate is not parented to a view
    // (e.g. while being reparented or measured), so EVERY use must go through
    // these two - reading root.ListView.isCurrentItem directly throws.
    readonly property var _listView: root.ListView
    readonly property bool isCurrent: root._listView ? root._listView.isCurrentItem === true : false
    property bool isDir: safeItem.type === "dir"
    property var activeTransfer: root.findTransfer(root.item)
    property bool isDownloading: activeTransfer !== null && activeTransfer.type === "download" && (activeTransfer.state === "pending" || activeTransfer.state === "downloading")
    property bool isUploading: activeTransfer !== null && activeTransfer.type === "upload" && (activeTransfer.state === "pending" || activeTransfer.state === "uploading")
    property real transferProgress: activeTransfer ? activeTransfer.progress : 0
    // activeTransfer.speed may be absent on a freshly registered (queued)
    // transfer, and assigning undefined to a string property is a binding error.
    property string transferSpeed: (activeTransfer && activeTransfer.speed) ? activeTransfer.speed : ""
    property bool isSelected: root.selected

    onTransferRevisionChanged: root.activeTransfer = root.findTransfer(root.item)

    implicitHeight: row.implicitHeight
    width: parent ? parent.width : 0

    // Keyboard cursor highlight
    Rectangle {
        anchors.fill: parent
        color: root.isCurrent ? Color.accent : "transparent"
        opacity: root.isCurrent ? 0.18 : 0
        visible: root.isCurrent
    }

    // Batch-selection row highlight — distinct from the keyboard cursor.
    Rectangle {
        anchors.fill: parent
        color: root.isSelected ? Color.accent : "transparent"
        opacity: root.isSelected && !root.isCurrent ? 0.16 : 0
        visible: root.isSelected
    }

    Rectangle {
        width: Style.space(3)
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        color: Color.accent
        visible: root.isSelected || root.isCurrent
        opacity: root.isCurrent ? 1 : 0.8
    }

    Rectangle {
        anchors.fill: parent
        color: "transparent"
        border.color: Color.accent
        border.width: root.isCurrent ? Style.spacing.hairline : 0
        visible: root.isCurrent
    }

    // Hover highlight
    Rectangle {
        anchors.fill: parent
        color: root.bar ? (root.bar.foreground || Color.foreground) : Color.foreground
        opacity: mouseArea.containsMouse ? 0.04 : 0
        visible: mouseArea.containsMouse
        Behavior on opacity { NumberAnimation { duration: 100 } }
    }

    Row {
        id: row
        spacing: Style.space(12)
        height: Math.max(icon.implicitHeight, nameLabel.implicitHeight) + Style.space(6)

        Text {
            id: icon
            text: root.iconForItem(root.safeItem)
            color: root.isSelected || root.isDir ? Color.accent : (root.bar ? (root.bar.foreground || Color.foreground) : Color.foreground)
            font.family: Icons.family
            font.pixelSize: Style.font.title
            width: Style.space(24)
            horizontalAlignment: Text.AlignHCenter
            height: parent.height
            verticalAlignment: Text.AlignVCenter
        }

        Text {
            id: nameLabel
            text: Models.boundedDisplayText(safeItem.name || "", 1024)
            color: root.isSelected ? Color.accent : (root.bar ? (root.bar.foreground || Color.foreground) : Color.foreground)
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.body
            elide: Text.ElideRight
            width: parent ? parent.width - icon.width - sizeLabel.width - (dateLabel.visible ? dateLabel.width : 0) - transferWidth - Style.space(36) : 0
            height: parent.height
            verticalAlignment: Text.AlignVCenter
            textFormat: Text.PlainText
            ToolTip.visible: mouseArea.containsMouse && truncated
            ToolTip.delay: 500
            ToolTip.text: safeItem.name || ""
        }

        Item {
            id: transferInfo
            width: transferWidth
            height: parent.height
            visible: root.isDownloading || root.isUploading

            Row {
                spacing: Style.space(8)

                ProgressBar {
                    id: progressBar
                    width: Style.space(70)
                    height: Style.space(6)
                    from: 0
                    to: 1
                    value: root.transferProgress
                }

                Text {
                    id: speedLabel
                    text: root.transferSpeed
                    color: Qt.darker(root.bar ? (root.bar.foreground || Color.foreground) : Color.foreground, 1.4)
                    font.family: root.bar ? root.bar.fontFamily : Style.font.family
                    font.pixelSize: Style.font.caption
                    height: parent.height
                    verticalAlignment: Text.AlignVCenter
                    textFormat: Text.PlainText
                }
            }
        }

        Text {
            id: sizeLabel
            text: (root.isDownloading || root.isUploading) ? "" : (safeItem.type === "dir" ? (safeItem.sizeFormatted || "") : Models.formatSize(safeItem.size))
            color: Qt.darker(root.bar ? (root.bar.foreground || Color.foreground) : Color.foreground, 1.4)
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.caption
            width: Style.space(80)
            horizontalAlignment: Text.AlignRight
            height: parent.height
            verticalAlignment: Text.AlignVCenter
            visible: !root.isDownloading && !root.isUploading
            textFormat: Text.PlainText
        }

        Text {
            id: dateLabel
            text: (root.isDownloading || root.isUploading || !safeItem.mtime) ? "" : Models.formatDate(safeItem.mtime)
            color: Qt.darker(root.bar ? (root.bar.foreground || Color.foreground) : Color.foreground, 1.4)
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.caption
            width: visible ? Style.space(150) : 0
            horizontalAlignment: Text.AlignRight
            elide: Text.ElideRight
            height: parent.height
            verticalAlignment: Text.AlignVCenter
            visible: !root.isDownloading && !root.isUploading
            textFormat: Text.PlainText
        }
    }

    readonly property int transferWidth: (root.isDownloading || root.isUploading) ? Style.space(130) : 0

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.AllButtons
        onClicked: function(mouse) {
            if (mouse.button !== Qt.LeftButton) {
                // Right/middle/other buttons open the context menu.
                var pos = mapToItem(Overlay.overlay, mouse.x, mouse.y)
                if (root.onContextMenuRequested) root.onContextMenuRequested(root.item, pos.x, pos.y)
                return
            }

            // Ensure keyboard focus follows click
            if (root._listView && root._listView.view) {
                root._listView.view.currentIndex = root.itemIndex
                root._listView.view.forceActiveFocus()
            }

            var accel = Qt.ControlModifier | Qt.MetaModifier
            if (mouse.modifiers & accel) {
                // Ctrl/Cmd + click = toggle selection
                if (root.onSelectionToggle) root.onSelectionToggle(root.item)
            } else if (mouse.modifiers & Qt.ShiftModifier) {
                // Shift + click = range selection
                if (root.onSelectionRange) root.onSelectionRange(root.item)
            } else {
                // Plain click = focus/select (positionOn)
                if (root.onPositionClicked) root.onPositionClicked(root.item)

                // Single-click-open mode: activate immediately
                if (root.singleClickOpen) {
                    if (root.isDir) {
                        if (root.onItemClicked) root.onItemClicked(root.item)
                    } else {
                        if (root.onOpenClicked) root.onOpenClicked(root.item)
                    }
                }
                // Otherwise double-click handles activation (see onDoubleClicked)
            }
        }
        onDoubleClicked: function(mouse) {
            if (mouse.button !== Qt.LeftButton) return
            if (root.isDir) {
                if (root.onItemClicked) root.onItemClicked(root.item)
            } else {
                if (root.onOpenClicked) root.onOpenClicked(root.item)
            }
        }
    }
}