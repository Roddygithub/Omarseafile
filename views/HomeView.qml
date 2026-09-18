import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui
import "../js"
import "../components"

Item {
    id: root
    required property QtObject bar
    required property var libraries
    required property var currentRepo
    required property string currentPath
    required property var pathHistory
    required property bool loading
    required property string errorMessage
    required property var selectedItems
    required property var selectionAnchor
    required property string destinationMode

    required property var onItemClicked
    required property var onNavigateToPath
    required property var onRefresh
    required property var onToggleSelection
    required property var onSelectRange
    required property var onSelectOnly
    required property var onPositionClicked
    required property var onContextMenuRequested
    required property var onAddToFavorites
    required property var onRemoveFromFavorites
    required property var onDownloadClicked
    required property var onOpenClicked
    required property var onRenameClicked
    required property var onMoveClicked
    required property var onDeleteClicked
    required property var onShareClicked
    required property var onHistoryClicked

    width: parent.width
    implicitHeight: content.implicitHeight

    Column {
        id: content
        width: parent.width
        spacing: 0

        // Quick Access Section
        Column {
            id: quickAccessSection
            width: parent.width
            visible: Favorites.getLibraries().length > 0 || Favorites.getFolders().length > 0
            spacing: Style.space(4)

            Row {
                height: Style.space(24)
                Text {
                    text: "QUICK ACCESS"
                    color: Qt.darker(root.bar.foreground, 1.3)
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                    font.letterSpacing: 1
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            Repeater {
                model: Favorites.getLibraries()
                delegate: Item {
                    required property var modelData
                    width: parent.width
                    required property QtObject bar
                    required property var onClicked
                    required property var onRemoveFromFavorites

                    property bool isLibrary: modelData.type === "library"
                    property string displayName: isLibrary ? modelData.repoName : (modelData.name || modelData.path)

                    implicitHeight: row.implicitHeight

                    Row {
                        id: row
                        anchors.fill: parent
                        anchors.leftMargin: Style.space(12)
                        anchors.rightMargin: Style.space(12)
                        spacing: Style.space(12)
                        height: Math.max(icon.implicitHeight, nameLabel.implicitHeight) + Style.space(6)

                        Text {
                            id: icon
                            text: "\uf02d"
                            color: root.bar.foreground
                            font.family: "Noto Sans"
                            font.pixelSize: Style.font.title
                            width: Style.space(24)
                            horizontalAlignment: Text.AlignHCenter
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Text {
                            id: nameLabel
                            text: Models.boundedDisplayText(displayName, 1024)
                            color: root.bar.foreground
                            font.family: root.bar.fontFamily
                            font.pixelSize: Style.font.body
                            elide: Text.ElideRight
                            width: parent ? parent.width - icon.width - removeBtn.width - Style.space(36) : 0
                            anchors.verticalCenter: parent.verticalCenter
                            textFormat: Text.PlainText
                        }

                        Button {
                            id: removeBtn
                            text: "\uf00d"
                            width: Style.space(24)
                            height: Style.space(24)
                                                        tooltipText: "Remove from Quick Access"
                            onClicked: {
                                if (root.onRemoveFromFavorites) root.onRemoveFromFavorites(modelData)
                            }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (root.onClicked) root.onClicked()
                        }
                    }
                }
            }

            Repeater {
                model: Favorites.getFolders()
                delegate: Item {
                    required property var modelData
                    width: parent.width
                    required property QtObject bar
                    required property var onClicked
                    required property var onRemoveFromFavorites

                    property bool isLibrary: modelData.type === "library"
                    property string displayName: isLibrary ? modelData.repoName : (modelData.name || modelData.path)

                    implicitHeight: row.implicitHeight

                    Row {
                        id: row
                        anchors.fill: parent
                        anchors.leftMargin: Style.space(12)
                        anchors.rightMargin: Style.space(12)
                        spacing: Style.space(12)
                        height: Math.max(icon.implicitHeight, nameLabel.implicitHeight) + Style.space(6)

                        Text {
                            id: icon
                            text: "\uf02d"
                            color: root.bar.foreground
                            font.family: "Noto Sans"
                            font.pixelSize: Style.font.title
                            width: Style.space(24)
                            horizontalAlignment: Text.AlignHCenter
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Text {
                            id: nameLabel
                            text: Models.boundedDisplayText(displayName, 1024)
                            color: root.bar.foreground
                            font.family: root.bar.fontFamily
                            font.pixelSize: Style.font.body
                            elide: Text.ElideRight
                            width: parent ? parent.width - icon.width - removeBtn.width - Style.space(36) : 0
                            anchors.verticalCenter: parent.verticalCenter
                            textFormat: Text.PlainText
                        }

                        Button {
                            id: removeBtn
                            text: "\uf00d"
                            width: Style.space(24)
                            height: Style.space(24)
                                                        tooltipText: "Remove from Quick Access"
                            onClicked: {
                                if (root.onRemoveFromFavorites) root.onRemoveFromFavorites(modelData)
                            }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (root.onClicked) root.onClicked()
                        }
                    }
                }
            }
        }

        // Recent Section (placeholder - could be extended with recent files tracking)
        Column {
            id: recentSection
            width: parent.width
            visible: false  // TODO: implement recent files tracking
            spacing: Style.space(4)

            Row {
                height: Style.space(24)
                Text {
                    text: "RECENT"
                    color: Qt.darker(root.bar.foreground, 1.3)
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                    font.letterSpacing: 1
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            EmptyState {
                bar: root.bar
                icon: "\uf017"
                title: "No recent items"
                subtitle: "Recently accessed files will appear here"
                width: parent.width
                visible: true
            }
        }

        // Transfers Section
        Column {
            id: transfersSection
            width: parent.width
            visible: TransferService.getActiveCount() > 0
            spacing: Style.space(4)

            Row {
                height: Style.space(24)
                Text {
                    text: "ACTIVE TRANSFERS"
                    color: Qt.darker(root.bar.foreground, 1.3)
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                    font.letterSpacing: 1
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            Repeater {
                model: TransferService.getActiveTransfers()
                delegate: Item {
                    required property var modelData
                    width: parent.width
                    required property QtObject bar
                    required property var onCancel
                    required property var onOpen

                    property bool isDownload: modelData.type === "download"
                    property bool isActive: modelData.state === "pending" || modelData.state === "downloading" || modelData.state === "uploading" || modelData.state === "opening" || modelData.state === "cancelling"

                    implicitHeight: row.implicitHeight

                    Row {
                        id: row
                        anchors.fill: parent
                        anchors.leftMargin: Style.space(12)
                        anchors.rightMargin: Style.space(12)
                        spacing: Style.space(12)
                        height: Style.space(28)

                        Text {
                            id: typeIcon
                            text: isDownload ? "\uf019" : "\uf093"
                            color: root.bar.foreground
                            font.family: "Noto Sans"
                            font.pixelSize: Style.font.body
                            width: Style.space(20)
                            horizontalAlignment: Text.AlignHCenter
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Text {
                            id: nameLabel
                            text: Models.boundedDisplayText(modelData.fileName || "Unknown", 1024)
                            color: root.bar.foreground
                            font.family: root.bar.fontFamily
                            font.pixelSize: Style.font.body
                            elide: Text.ElideRight
                            width: parent.width - typeIcon.width - progressBar.width - cancelBtn.width - Style.space(36)
                            anchors.verticalCenter: parent.verticalCenter
                            textFormat: Text.PlainText
                        }

                        ProgressBar {
                            id: progressBar
                            width: Style.space(80)
                            height: Style.space(4)
                            from: 0
                            to: 1
                            value: modelData.progress
                            visible: isActive
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Button {
                            id: cancelBtn
                            text: "\uf00d"
                            width: Style.space(24)
                            height: Style.space(24)
                                                        visible: isActive
                            tooltipText: "Cancel transfer"
                            onClicked: root.onCancel
                        }
                    }
                }
            }
        }

        // Libraries Section (shown when at root level with no currentRepo)
        Column {
            id: librariesSection
            width: parent.width
            visible: root.libraries && root.libraries.length > 0 && !root.currentRepo
            spacing: Style.space(4)

            Row {
                height: Style.space(24)
                Text {
                    text: "LIBRARIES"
                    color: Qt.darker(root.bar.foreground, 1.3)
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                    font.letterSpacing: 1
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            FileList {
                id: librariesFileList
                width: parent.width
                bar: root.bar
                height: librariesFileList.contentHeight > 0 ? Math.min(librariesFileList.contentHeight, Style.space(420)) : Style.space(120)
                items: root.libraries
                focus: true
                findTransfer: TransferService.findTransfer
                transferRevision: 0
                onItemClicked: root.onItemClicked
                onDownloadClicked: function(item) { root.destinationMode ? null : root.onDownloadClicked(item) }
                onOpenClicked: function(item) { root.destinationMode ? null : root.onOpenClicked(item) }
                onRenameClicked: root.onRenameClicked
                onMoveClicked: root.onMoveClicked
                onDeleteClicked: root.onDeleteClicked
                onShareClicked: root.onShareClicked
                onHistoryClicked: root.onHistoryClicked
                visible: !root.loading && root.errorMessage === ""
                selectedItems: root.selectedItems
                selectionAnchor: root.selectionAnchor
                onSelectionToggle: root.destinationMode || !root.currentRepo ? root.onToggleSelection : function() {}
                onSelectionRange: root.destinationMode || !root.currentRepo ? root.onSelectRange : function() {}
                onSelectOnly: root.destinationMode ? function() {} : root.onSelectOnly
                onPositionClicked: root.onPositionClicked
                onContextMenuRequested: root.onContextMenuRequested
                singleClickOpen: false
            }
        }

        // Empty state when no favorites and no libraries
        EmptyState {
            id: emptyState
            bar: root.bar
            icon: "\uf02d"
            title: "Quick Access"
            subtitle: "Pin libraries and folders for quick access\nRight-click an item in the browser and select \"Add to Quick Access\""
            width: parent.width
            visible: Favorites.getLibraries().length === 0 && Favorites.getFolders().length === 0 && TransferService.getActiveCount() === 0 && !(root.libraries && root.libraries.length > 0)
            anchors.fill: parent
        }
    }
}