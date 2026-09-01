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
            anchors.leftMargin: Style.space(12)
            spacing: Style.space(8)

            Text {
                text: "History: " + root.fileName
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.title
                font.bold: true
                anchors.verticalCenter: parent.verticalCenter
                elide: Text.ElideRight
                width: parent.width - Style.space(24)
            }
        }

        // History list
        ListView {
            id: historyList
            width: parent.width
            height: parent.height - Style.space(40)
            clip: true
            spacing: Style.space(4)
            model: root.historyData

            delegate: Item {
                width: parent.width
                height: row.implicitHeight + Style.space(8)
                required property var modelData

                property var revision: modelData
                property bool isCurrent: modelData.version === 1

                Row {
                    id: row
                    anchors.fill: parent
                    anchors.leftMargin: Style.space(12)
                    anchors.rightMargin: Style.space(12)
                    spacing: Style.space(12)
                    height: Math.max(icon.implicitHeight, timeLabel.implicitHeight) + Style.space(8)

                    Text {
                        id: icon
                        text: "\uf017"
                        color: root.bar.foreground
                        font.family: "Noto Sans"
                        font.pixelSize: Style.font.title
                        width: Style.space(24)
                        horizontalAlignment: Text.AlignHCenter
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Column {
                        width: parent.width - icon.width - actionColumn.width - Style.space(24)
                        spacing: Style.space(2)
                        anchors.verticalCenter: parent.verticalCenter

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
                        }

                        Text {
                            id: descLabel
                            text: revision.desc || ""
                            color: Qt.darker(root.bar.foreground, 1.4)
                            font.family: root.bar.fontFamily
                            font.pixelSize: Style.font.caption
                            elide: Text.ElideRight
                            width: parent.width
                            visible: revision.desc && revision.desc !== ""
                        }

                        Text {
                            id: sizeLabel
                            text: "Size: " + Models.formatSize(revision.revFileSize)
                            color: Qt.darker(root.bar.foreground, 1.4)
                            font.family: root.bar.fontFamily
                            font.pixelSize: Style.font.caption
                            visible: revision.revFileSize
                        }
                    }

                    Column {
                        id: actionColumn
                        width: Style.space(80)
                        anchors.verticalCenter: parent.verticalCenter
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

        // Empty state
        EmptyState {
                id: emptyState
                bar: root.bar
                icon: "\uf017"
                title: "No history"
                subtitle: "File revisions will appear here"
                width: parent.width
                height: historyList.height
                anchors.centerIn: historyList
                visible: root.historyData.length === 0
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
