import QtQuick
import qs.Commons
import qs.Ui
import "../js"

Column {
    id: root
    required property var bar
    required property var repoId
    required property string filePath
    required property string fileName
    required property var onDownloadRevision
    required property var onClose
    property var onError: null
    property var historyData: []

    width: parent.width
    spacing: 0

    function loadHistory() {
        SeafileAPI.getFileHistory(root.repoId, root.filePath, function(success, data, error) {
            if (success) {
                root.historyData = data
            } else {
                if (root.onError) root.onError("Failed to load history: " + error)
            }
        })
    }

    Component.onCompleted: {
        root.loadHistory()
    }

    Column {
        width: parent.width
        spacing: 0

        // Header
        Row {
            width: parent.width
            height: Style.space(40)
            spacing: Style.space(8)

            Text {
                text: Models.boundedDisplayText("History: " + root.fileName, 1024)
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.title
                font.bold: true
                height: parent.height
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
                width: parent.width - Style.space(24)
                textFormat: Text.PlainText
            }
        }

        // History list + empty state overlaid in a plain Item (anchors on a
        // direct Column child are invalid, so the overlay container is an Item).
        Item {
            width: parent.width
            height: historyList.height

            ListView {
                id: historyList
                width: parent.width
                height: root.historyData.length === 0 ? Style.space(160) : Math.min(contentHeight, Style.space(360))
                clip: true
                spacing: Style.space(4)
                model: root.historyData

                delegate: Item {
                    width: parent.width
                    height: row.implicitHeight + Style.space(8)
                    required property var modelData

                    property var revision: modelData
                    property bool isCurrent: String(modelData.version) === "1"

                    Row {
                        id: row
                        spacing: Style.space(12)
                        height: Math.max(icon.implicitHeight, timeLabel.implicitHeight) + Style.space(8)

                        Text {
                            id: icon
                            text: Icons.clock
                            color: root.bar.foreground
                            font.family: Icons.family
                            font.pixelSize: Style.font.title
                            width: Style.space(24)
                            horizontalAlignment: Text.AlignHCenter
                            height: parent.height
                            verticalAlignment: Text.AlignVCenter
                        }

                        Column {
                            width: parent.width - icon.width - actionColumn.width - Style.space(24)
                            spacing: Style.space(2)

                            Text {
                                id: timeLabel
                                text: {
                                    var date = new Date(revision.ctime * 1000)
                                    return date.toLocaleDateString() + " " + date.toLocaleTimeString()
                                }
                                color: isCurrent ? Color.accent : root.bar.foreground
                                font.family: root.bar.fontFamily
                                font.pixelSize: Style.font.body
                                font.bold: isCurrent
                                elide: Text.ElideRight
                                width: parent.width
                                textFormat: Text.PlainText
                            }

                            Text {
                                id: descLabel
                                text: Models.boundedDisplayText(revision.desc || "", 1024)
                                color: Qt.darker(root.bar.foreground, 1.4)
                                font.family: root.bar.fontFamily
                                font.pixelSize: Style.font.caption
                                elide: Text.ElideRight
                                width: parent.width
                                visible: revision.desc && revision.desc !== ""
                                textFormat: Text.PlainText
                            }

                            Text {
                                id: sizeLabel
                                text: "Size: " + Models.formatSize(revision.revFileSize)
                                color: Qt.darker(root.bar.foreground, 1.4)
                                font.family: root.bar.fontFamily
                                font.pixelSize: Style.font.caption
                                visible: revision.revFileSize
                                textFormat: Text.PlainText
                            }
                        }

                        Column {
                            id: actionColumn
                            width: Style.space(80)
                            spacing: Style.space(4)

                            Button {
                                id: downloadBtn
                                text: "Download"
                                visible: !isCurrent
                                onClicked: {
                                    if (root.onDownloadRevision) root.onDownloadRevision(revision)
                                }
                            }

                            Text {
                                id: currentLabel
                                text: "Current"
                                color: Color.accent
                                font.family: root.bar.fontFamily
                                font.pixelSize: Style.font.caption
                                font.bold: true
                                horizontalAlignment: Text.AlignHCenter
                                visible: isCurrent
                            }
                        }
                    }
                }
            }

            // Empty state, overlaid and centered on the overlay Item.
            EmptyState {
                id: emptyState
                bar: root.bar
                icon: Icons.clock
                title: "No history"
                subtitle: "File revisions will appear here"
                width: parent.width
                anchors.centerIn: parent
                visible: root.historyData.length === 0
            }
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