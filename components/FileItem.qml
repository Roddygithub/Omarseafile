import QtQuick
import qs.Commons
import qs.Ui
import "../js/Models.js" as Models

Item {
    id: root
    required property var item
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
    required property bool selected
    property QtObject bar: null

    property bool isDir: item.type === "dir"
    property var activeTransfer: root.findTransfer(root.item)
    property bool isDownloading: activeTransfer !== null && activeTransfer.type === "download" && (activeTransfer.state === "pending" || activeTransfer.state === "downloading")
    property bool isUploading: activeTransfer !== null && activeTransfer.type === "upload" && (activeTransfer.state === "pending" || activeTransfer.state === "uploading")
    property real transferProgress: activeTransfer ? activeTransfer.progress : 0
    property string transferSpeed: activeTransfer ? activeTransfer.speed : ""
    property bool isSelected: root.selected

    onTransferRevisionChanged: root.activeTransfer = root.findTransfer(root.item)

    implicitHeight: row.implicitHeight
    width: parent.width

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
            color: root.isSelected ? Color.accent : root.bar.foreground
            font.family: "Noto Sans"
            font.pixelSize: Style.font.title
            width: Style.space(24)
            horizontalAlignment: Text.AlignHCenter
            anchors.verticalCenter: parent.verticalCenter
        }

        Text {
            id: nameLabel
            text: item.name
            color: root.isSelected ? Color.accent : root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.body
            elide: Text.ElideRight
            width: parent.width - icon.width - sizeLabel.width - transferWidth - Style.space(36)
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
                    width: Style.space(120)
                    height: Style.space(6)
                    from: 0
                    to: 1
                    value: root.transferProgress
                    anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                    id: speedLabel
                    text: root.transferSpeed
                    color: Qt.darker(root.bar.foreground, 1.4)
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.caption
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }

        Text {
            id: sizeLabel
            text: (root.isDownloading || root.isUploading) ? "" : (root.isDir ? "" : Models.formatSize(item.size))
            color: Qt.darker(root.bar.foreground, 1.4)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
            width: Style.space(80)
            horizontalAlignment: Text.AlignRight
            anchors.verticalCenter: parent.verticalCenter
            visible: !root.isDownloading && !root.isUploading
        }
    }

    readonly property int transferWidth: (root.isDownloading || root.isUploading) ? Style.space(200) : 0

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: {
            if (mouse.button === Qt.LeftButton) {
                if (mouse.modifiers & Qt.ControlModifier) {
                    if (root.onSelectionToggle) root.onSelectionToggle(root.item)
                } else if (mouse.modifiers & Qt.ShiftModifier) {
                    if (root.onSelectionRange) root.onSelectionRange(root.item)
                } else {
                    if (root.selected) {
                        if (root.onSelectionToggle) root.onSelectionToggle(root.item)
                    } else {
                        if (root.isDir) {
                            if (root.onItemClicked) root.onItemClicked(root.item)
                        } else {
                            if (root.onDownloadClicked) root.onDownloadClicked(root.item)
                        }
                    }
                }
            } else if (mouse.button === Qt.RightButton) {
                if (root.onRenameClicked || root.onMoveClicked || root.onDeleteClicked || root.onShareClicked) {
                    root.showContextMenu(mouse)
                }
            }
        }

function showContextMenu(mouse) {
            var menu = Qt.createComponent("ContextMenu.qml")
            if (menu.status === Component.Ready) {
                var popup = menu.createObject(root, {
                    x: mouse.x,
                    y: mouse.y,
                    width: Style.space(180),
                    item: root.item,
                    onRenameClicked: root.onRenameClicked,
                    onMoveClicked: root.onMoveClicked,
                    onDeleteClicked: root.onDeleteClicked,
                    onShareClicked: root.onShareClicked,
                    onCopyClicked: root.onCopyClicked,
                    onHistoryClicked: root.onHistoryClicked,
                    isDir: root.isDir
                })
                popup.open()
            }
        }
        }
    }
}