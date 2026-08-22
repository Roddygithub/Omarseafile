import QtQuick
import qs.Commons
import qs.Ui

Column {
    id: root
    required property var bar
    required property var repoId
    required property var onRestoreFolder
    required property var onClose

    width: parent.width
    spacing: 0

    function loadTrash() {
        SeafileAPI.listTrash(root.repoId, function(success, data, error) {
            if (success) {
                root.trashData = data
            } else {
                root.showToast("Failed to load trash: " + error, "error")
            }
        })
    }

    property var trashData: []

    Component.onCompleted: {
        root.loadTrash()
    }

    Column {
        width: parent.width
        spacing: 0

        // Header
        Row {
            width: parent.width
            height: Style.space(40)
            anchors.leftMargin: Style.space(12)
            spacing: Style.space(8)

            Text {
                text: "Trash"
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.title
                font.bold: true
                anchors.verticalCenter: parent.verticalCenter
                elide: Text.ElideRight
                width: parent.width - Style.space(24)
            }
        }

        // Trash list
        ListView {
            id: trashList
            width: parent.width
            height: parent.height - Style.space(40) - Style.space(40)
            clip: true
            spacing: Style.space(4)
            model: root.trashData

            delegate: Item {
                width: parent.width
                height: row.implicitHeight + Style.space(8)
                required property var modelData

                property var trashItem: modelData
                property bool isDir: modelData.isDir === true

                Row {
                    id: row
                    anchors.fill: parent
                    anchors.leftMargin: Style.space(12)
                    anchors.rightMargin: Style.space(12)
                    spacing: Style.space(12)
                    height: Math.max(icon.implicitHeight, nameLabel.implicitHeight) + Style.space(8)

                    Text {
                        id: icon
                        text: root.isDir ? "\uf07b" : "\uf15b"
                        color: root.bar.foreground
                        font.family: "Noto Sans"
                        font.pixelSize: Style.font.title
                        width: Style.space(24)
                        horizontalAlignment: Text.AlignHCenter
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Column {
                        width: parent.width - icon.width - actionColumn.width - Style.space(24)
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Style.space(2)

                        Text {
                            id: nameLabel
                            text: trashItem.objName
                            color: root.bar.foreground
                            font.family: root.bar.fontFamily
                            font.pixelSize: Style.font.body
                            elide: Text.ElideRight
                            width: parent.width
                        }

                        Text {
                            id: detailLabel
                            text: {
                                var parts = []
                                if (trashItem.deletedTime) {
                                    var date = new Date(trashItem.deletedTime * 1000)
                                    parts.push(date.toLocaleDateString() + " " + date.toLocaleTimeString())
                                }
                                if (!root.isDir && trashItem.size) {
                                    parts.push(Models.formatSize(trashItem.size))
                                }
                                parts.push(root.isDir ? "Folder" : "File")
                                return parts.join(" \u2022 ")
                            }
                            color: Qt.darker(root.bar.foreground, 1.4)
                            font.family: root.bar.fontFamily
                            font.pixelSize: Style.font.caption
                            elide: Text.ElideRight
                            width: parent.width
                            visible: text !== ""
                        }
                    }

                    Column {
                        id: actionColumn
                        width: Style.space(100)
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Style.space(4)

                        Button {
                            id: restoreBtn
                            text: "Restore"
                            font.family: root.bar.fontFamily
                            font.pixelSize: Style.font.caption
                            visible: modelData.isDir
                            onClicked: {
                                if (root.onRestoreFolder) root.onRestoreFolder(trashItem)
                            }
                        }

                        Text {
                            id: fileRestoreLabel
                            text: "Restore not available"
                            color: Qt.darker(root.bar.foreground, 1.4)
                            font.family: root.bar.fontFamily
                            font.pixelSize: Style.font.caption
                            horizontalAlignment: Text.AlignHCenter
                            visible: !modelData.isDir
                        }
                    }
                }
            }
        }

        // Empty state
        Text {
            width: parent.width
            text: "Trash is empty"
            color: Qt.darker(root.bar.foreground, 1.4)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
            horizontalAlignment: Text.AlignHCenter
            topPadding: Style.space(16)
            bottomPadding: Style.space(16)
            visible: root.trashData.length === 0
        }
    }

    // Bottom close button
    Button {
        width: parent.width
        height: Style.space(40)
        text: "Close"
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.body
        onClicked: {
            if (root.onClose) root.onClose()
        }
    }
}