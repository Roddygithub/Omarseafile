import QtQuick
import qs.Commons
import qs.Ui
import "../js"

Column {
    id: root
    required property var bar
    required property var repoId
    required property var onClose
    property var onError: null

    width: parent.width
    spacing: 0

    function loadTrash() {
        SeafileAPI.listTrash(root.repoId, function(success, data, error) {
            if (success) {
                root.trashData = data
            } else {
                if (root.onError) root.onError("Failed to load trash: " + error)
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
                        text: isDir ? "\uf07b" : "\uf15b"
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
                            text: Models.boundedDisplayText(trashItem.objName, 1024)
                            color: root.bar.foreground
                            font.family: root.bar.fontFamily
                            font.pixelSize: Style.font.body
                            elide: Text.ElideRight
                            width: parent.width
                            textFormat: Text.PlainText
                        }

                        Text {
                            id: detailLabel
                            text: Models.boundedDisplayText((function() {
                                var parts = []
                                if (trashItem.deletedTime) {
                                    var date = new Date(trashItem.deletedTime * 1000)
                                    parts.push(date.toLocaleDateString() + " " + date.toLocaleTimeString())
                                }
                                if (!isDir && trashItem.size) {
                                    parts.push(Models.formatSize(trashItem.size))
                                }
                                parts.push(isDir ? "Folder" : "File")
                                return parts.join(" \u2022 ")
                            })(), 1024)
                            color: Qt.darker(root.bar.foreground, 1.4)
                            font.family: root.bar.fontFamily
                            font.pixelSize: Style.font.caption
                            elide: Text.ElideRight
                            width: parent.width
                            visible: text !== ""
                            textFormat: Text.PlainText
                        }
                    }

                    Column {
                        id: actionColumn
                        width: Style.space(100)
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Style.space(4)

                        Text {
                            id: fileRestoreLabel
                            text: "Restore unavailable"
                            color: Qt.darker(root.bar.foreground, 1.4)
                            font.family: root.bar.fontFamily
                            font.pixelSize: Style.font.caption
                            horizontalAlignment: Text.AlignHCenter
                        }
                    }
                }
            }
        }

        // Empty state
        EmptyState {
                id: emptyState
                bar: root.bar
                icon: "\uf1f8"
                title: "Trash is empty"
                subtitle: "Deleted items appear here"
                width: parent.width
                height: trashList.height
                anchors.centerIn: trashList
                visible: root.trashData.length === 0
            }
    }

    // Bottom close button
    Button {
        width: parent.width
        height: Style.space(40)
        text: "Close"
        onClicked: {
            if (root.onClose) root.onClose()
        }
    }
}
