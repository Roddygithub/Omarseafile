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

    readonly property var safeItem: item || {}
    property bool isDir: safeItem.type === "dir"
    property var activeTransfer: root.findTransfer(root.item)
    property bool isDownloading: activeTransfer !== null && activeTransfer.type === "download" && (activeTransfer.state === "pending" || activeTransfer.state === "downloading")
    property bool isUploading: activeTransfer !== null && activeTransfer.type === "upload" && (activeTransfer.state === "pending" || activeTransfer.state === "uploading")
    property real transferProgress: activeTransfer ? activeTransfer.progress : 0
    property string transferSpeed: activeTransfer ? activeTransfer.speed : ""
    property bool isSelected: root.selected

    onTransferRevisionChanged: root.activeTransfer = root.findTransfer(root.item)


    implicitHeight: row.implicitHeight
    width: parent.width

    Rectangle {
        anchors.fill: parent
        color: root.ListView.isCurrentItem ? Color.accent : "transparent"
        opacity: root.ListView.isCurrentItem ? 0.18 : 0
        visible: root.ListView.isCurrentItem
    }

    // Batch-selection row highlight — distinct from the keyboard cursor.
    Rectangle {
        anchors.fill: parent
        color: root.isSelected ? Color.accent : "transparent"
        opacity: root.isSelected && !root.ListView.isCurrentItem ? 0.10 : 0
        visible: root.isSelected
    }

    Row {
        id: row
        anchors.fill: parent
        anchors.leftMargin: Style.space(12)
        anchors.rightMargin: Style.space(12)
        spacing: Style.space(12)
        height: Math.max(icon.implicitHeight, nameLabel.implicitHeight) + Style.space(6)

        Text {
            id: icon
            text: root.isDir ? "\uf07b" : "\uf15b"
            color: root.isSelected ? Color.accent : (root.bar ? root.bar.foreground : Color.foreground)
            font.family: "Noto Sans"
            font.pixelSize: Style.font.title
            width: Style.space(24)
            horizontalAlignment: Text.AlignHCenter
            anchors.verticalCenter: parent.verticalCenter
        }

        Text {
            id: nameLabel
            text: safeItem.name || ""
            color: root.isSelected ? Color.accent : (root.bar ? root.bar.foreground : Color.foreground)
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.body
            elide: Text.ElideRight
            width: parent ? parent.width - icon.width - sizeLabel.width - (dateLabel.visible ? dateLabel.width : 0) - transferWidth - Style.space(36) : 0
            anchors.verticalCenter: parent.verticalCenter
        }

        Item {
            id: transferInfo
            width: transferWidth
            height: parent.height
            visible: root.isDownloading || root.isUploading

            Row {
                anchors.fill: parent
                spacing: Style.space(8)

                ProgressBar {
                    id: progressBar
                    width: Style.space(70)
                    height: Style.space(6)
                    from: 0
                    to: 1
                    value: root.transferProgress
                    anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                    id: speedLabel
                    text: root.transferSpeed
                    color: Qt.darker(root.bar ? root.bar.foreground : Color.foreground, 1.4)
                    font.family: root.bar ? root.bar.fontFamily : Style.font.family
                    font.pixelSize: Style.font.caption
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }

        Text {
            id: sizeLabel
            text: (root.isDownloading || root.isUploading) ? "" : (safeItem.type === "dir" ? (safeItem.sizeFormatted || "") : Models.formatSize(safeItem.size))
            color: Qt.darker(root.bar ? root.bar.foreground : Color.foreground, 1.4)
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.caption
            width: Style.space(80)
            horizontalAlignment: Text.AlignRight
            anchors.verticalCenter: parent.verticalCenter
            visible: !root.isDownloading && !root.isUploading
        }

        Text {
            id: dateLabel
            text: (root.isDownloading || root.isUploading || !safeItem.mtime) ? "" : Models.formatDate(safeItem.mtime)
            color: Qt.darker(root.bar ? root.bar.foreground : Color.foreground, 1.4)
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.caption
            width: visible ? Style.space(150) : 0
            horizontalAlignment: Text.AlignRight
            elide: Text.ElideRight
            anchors.verticalCenter: parent.verticalCenter
            visible: !root.isDownloading && !root.isUploading
        }
    }

    readonly property int transferWidth: (root.isDownloading || root.isUploading) ? Style.space(130) : 0

MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        // Accept every button: some touchpads deliver a right-click as
        // middle (or another button). Left = primary action, anything
        // else = context menu.
        acceptedButtons: Qt.AllButtons
        onClicked: function(mouse) {
            if (mouse.button !== Qt.LeftButton) {
                // Right/middle/other buttons open the context menu.
                var pos = mapToItem(Overlay.overlay, mouse.x, mouse.y)
                if (root.onContextMenuRequested) root.onContextMenuRequested(root.item, pos.x, pos.y)
            } else {
                // Some keyboards/layouts send Meta (Super/Cmd) where Ctrl is
                // intended — accept both for selection modifiers.
                var accel = Qt.ControlModifier | Qt.MetaModifier
                if (mouse.modifiers & accel) {
                    if (root.onSelectionToggle) root.onSelectionToggle(root.item)
                } else if (mouse.modifiers & Qt.ShiftModifier) {
                    if (root.onSelectionRange) root.onSelectionRange(root.item)
                } else if (root.isDir) {
                    // Plain click on a folder/library navigates into it.
                    if (root.onItemClicked) root.onItemClicked(root.item)
                } else {
                    // Plain click on a file opens it with the default application.
                    if (root.onOpenClicked) root.onOpenClicked(root.item)
                }
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