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
    // Explicit APIs consumed by the delegates below. Declaring a
    // `required property` inside a delegate for something the Repeater never
    // supplies is a load-time failure, so delegates call these instead.
    required property var onFavoriteClicked
    required property var onRemoveFavorite
    required property var onTransferCancel
    // Panel already recomputes these on TransferService.transfersChanged, so
    // binding them in makes this section reactive. Calling
    // TransferService.getActiveTransfers() directly inside a binding is not -
    // the service exposes no notifyable property to depend on.
    required property var activeTransfers
    required property int activeCount
    required property var onDownloadClicked
    required property var onOpenClicked
    required property var onRenameClicked
    required property var onMoveClicked
    required property var onDeleteClicked
    required property var onShareClicked
    required property var onHistoryClicked

    width: parent.width
    implicitHeight: content.implicitHeight

    // The FileList Panel drives with the keyboard. Exposed through the view
    // API so Panel never needs a lexical id from inside this component.
    readonly property var activeFileList: librariesSection.visible ? librariesFileList : null

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
                    height: parent.height
                    verticalAlignment: Text.AlignVCenter
                }
            }

            Repeater {
                model: Favorites.getLibraries()
                delegate: Item {
                    // Only modelData is a real model role here; everything else
                    // comes from HomeView's root callbacks.
                    required property var modelData
                    width: parent.width

                    property string displayName: modelData.repoName || modelData.name || ""

                    implicitHeight: row.implicitHeight

                    Row {
                        id: row
                        spacing: Style.space(12)
                        height: Math.max(icon.implicitHeight, nameLabel.implicitHeight) + Style.space(6)

                        Text {
                            id: icon
                            text: Icons.book
                            color: root.bar.foreground
                            font.family: Icons.family
                            font.pixelSize: Style.font.title
                            width: Style.space(24)
                            horizontalAlignment: Text.AlignHCenter
                            height: parent.height
                            verticalAlignment: Text.AlignVCenter
                        }

                        Text {
                            id: nameLabel
                            text: Models.boundedDisplayText(displayName, 1024)
                            color: root.bar.foreground
                            font.family: root.bar.fontFamily
                            font.pixelSize: Style.font.body
                            elide: Text.ElideRight
                            width: parent ? parent.width - icon.width - removeBtn.width - Style.space(36) : 0
                            height: parent.height
                            verticalAlignment: Text.AlignVCenter
                            textFormat: Text.PlainText
                        }

                        Button {
                            id: removeBtn
                            text: Icons.times
                            width: Style.space(24)
                            height: Style.space(24)
                            tooltipText: "Remove from Quick Access"
                            // Sits above the row MouseArea, so removing an entry
                            // never also navigates.
                            onClicked: {
                                if (root.onRemoveFavorite) root.onRemoveFavorite(modelData)
                            }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        // The remove button is a later sibling stacked on top and
                        // accepts its own presses, so the row only sees clicks
                        // that miss it.
                        onClicked: {
                            if (root.onFavoriteClicked) root.onFavoriteClicked(modelData)
                        }
                    }
                }
            }

            Repeater {
                model: Favorites.getFolders()
                delegate: Item {
                    required property var modelData
                    width: parent.width

                    property string displayName: modelData.name || modelData.path || ""

                    implicitHeight: row.implicitHeight

                    Row {
                        id: row
                        spacing: Style.space(12)
                        height: Math.max(icon.implicitHeight, nameLabel.implicitHeight) + Style.space(6)

                        Text {
                            id: icon
                            text: Icons.book
                            color: root.bar.foreground
                            font.family: Icons.family
                            font.pixelSize: Style.font.title
                            width: Style.space(24)
                            horizontalAlignment: Text.AlignHCenter
                            height: parent.height
                            verticalAlignment: Text.AlignVCenter
                        }

                        Text {
                            id: nameLabel
                            text: Models.boundedDisplayText(displayName, 1024)
                            color: root.bar.foreground
                            font.family: root.bar.fontFamily
                            font.pixelSize: Style.font.body
                            elide: Text.ElideRight
                            width: parent ? parent.width - icon.width - removeBtn.width - Style.space(36) : 0
                            height: parent.height
                            verticalAlignment: Text.AlignVCenter
                            textFormat: Text.PlainText
                        }

                        Button {
                            id: removeBtn
                            text: Icons.times
                            width: Style.space(24)
                            height: Style.space(24)
                            tooltipText: "Remove from Quick Access"
                            onClicked: {
                                if (root.onRemoveFavorite) root.onRemoveFavorite(modelData)
                            }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (root.onFavoriteClicked) root.onFavoriteClicked(modelData)
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
                    height: parent.height
                    verticalAlignment: Text.AlignVCenter
                }
            }

            EmptyState {
                bar: root.bar
                icon: Icons.clock
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
            visible: root.activeCount > 0
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
                    height: parent.height
                    verticalAlignment: Text.AlignVCenter
                }
            }

            Repeater {
                model: root.activeTransfers
                delegate: Item {
                    required property var modelData
                    width: parent.width

                    property bool isDownload: modelData.type === "download"
                    // "queued" and "validating" are active: the upload is
                    // accepted and cancellable before its first byte moves.
                    property bool isActive: modelData.state === "queued" || modelData.state === "validating" || modelData.state === "pending" || modelData.state === "downloading" || modelData.state === "uploading" || modelData.state === "opening" || modelData.state === "cancelling"
                    property bool isQueued: modelData.state === "queued"

                    implicitHeight: row.implicitHeight

                    Row {
                        id: row
                        spacing: Style.space(12)
                        height: Style.space(28)

                        Text {
                            id: typeIcon
                            text: isDownload ? Icons.download : Icons.upload
                            color: root.bar.foreground
                            font.family: Icons.family
                            font.pixelSize: Style.font.body
                            width: Style.space(20)
                            horizontalAlignment: Text.AlignHCenter
                            height: parent.height
                            verticalAlignment: Text.AlignVCenter
                        }

                        Text {
                            id: nameLabel
                            text: Models.boundedDisplayText((isQueued ? "Queued - " : "") + (modelData.fileName || "Unknown"), 1024)
                            color: root.bar.foreground
                            font.family: root.bar.fontFamily
                            font.pixelSize: Style.font.body
                            elide: Text.ElideRight
                            width: parent.width - typeIcon.width - progressBar.width - cancelBtn.width - Style.space(36)
                            height: parent.height
                            verticalAlignment: Text.AlignVCenter
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
                            height: parent.height
                        }

                        Button {
                            id: cancelBtn
                            text: Icons.times
                            width: Style.space(24)
                            height: Style.space(24)
                            visible: isActive
                            tooltipText: "Cancel transfer"
                            // Was `onClicked: root.onCancel`, which evaluated the
                            // callback without ever calling it - cancel did
                            // nothing. Queued transfers are cancellable too.
                            onClicked: {
                                if (root.onTransferCancel) root.onTransferCancel(modelData)
                            }
                        }
                    }
                }
            }
        }

        // Libraries Section (shown when at root level with no currentRepo)
        // No section header needed - toolbar title shows "Libraries"
        Column {
            id: librariesSection
            width: parent.width
            visible: root.libraries && root.libraries.length > 0 && !root.currentRepo
            spacing: Style.space(4)

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
            icon: Icons.book
            title: "Quick Access"
            subtitle: "Pin libraries and folders for quick access\nRight-click an item in the browser and select \"Add to Quick Access\""
            width: parent.width
            visible: Favorites.getLibraries().length === 0 && Favorites.getFolders().length === 0 && root.activeCount === 0 && !(root.libraries && root.libraries.length > 0)
            width: parent.width
            height: parent.height
        }
    }
}