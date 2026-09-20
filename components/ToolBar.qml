import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui
import "../js"

Item {
    id: root
    required property var bar
    property var overlay: null
    property string title: ""
    property bool showBack: false
    property bool showRefresh: false
    property bool showUpload: false
    property bool showCreateFolder: false
    property bool showOffline: false
    property bool showSearch: false
    property bool showLogout: false
    property bool showTransfers: false
    property bool showTrash: false
    property bool showSettings: false
    property int activeTransferCount: 0
    property bool hasTransferFailures: false
    property int selectionCount: 0
    property bool hasTrashItems: false
    property var onTransfersClicked: null
    property var onTrashClicked: null
    property var onMoveBatch: null
    property var onCopyBatch: null
    property var onDeleteBatch: null
    property var onClearSelection: null
    property string searchQuery: ""
    property bool searchActive: false
    property var onBackClicked: null
    property var onRefreshClicked: null
    property var onUploadClicked: null
    property var onCreateFolderClicked: null
    property var onSearchChanged: null
    property var onSearchActiveToggled: null
    property var onLogoutClicked: null
    property var onSettingsClicked: null
    property string destinationMode: ""
    property int destinationCount: 0
    property string destinationOperation: ""
    property string destinationPath: ""
    property var onDestinationCancel: null
    property var onDestinationConfirm: null

    implicitHeight: row.implicitHeight
    width: parent.width

    // Overflow menu state
    property bool overflowOpen: false

    Row {
        id: row
        spacing: Style.space(5)

        // Fixed buttons that must always be accessible
        readonly property int _fixedWidth: backButton.implicitWidth
            + (searchActive ? searchField.implicitWidth : searchButton.implicitWidth)
            + (selectionCount > 0 ? batchActionBar.implicitWidth : 0)
            + transferIndicator.implicitWidth
            + offlineIndicator.implicitWidth
            + overflowButton.implicitWidth
            + Style.space(8) * 6

        Button {
            id: backButton
            text: Icons.chevronLeft
            visible: root.showBack
            tooltipText: "Back"
            onClicked: {
                if (root.onBackClicked) root.onBackClicked()
            }
        }

        Text {
            id: titleLabel
            text: Models.boundedDisplayText(root.title, 1024)
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.title
            font.bold: true
            elide: Text.ElideRight
            width: Math.max(Style.space(60), row.width - row._fixedWidth)
            height: parent.height
            verticalAlignment: Text.AlignVCenter
            visible: !root.searchActive && root.selectionCount === 0
            textFormat: Text.PlainText
        }

        BatchActionBar {
            id: batchActionBar
            bar: root.bar
            count: root.selectionCount
            visible: root.selectionCount > 0 && root.destinationMode === ""
            onMove: function() { if (root.onMoveBatch) root.onMoveBatch() }
            onCopy: function() { if (root.onCopyBatch) root.onCopyBatch() }
            onDelete: function() { if (root.onDeleteBatch) root.onDeleteBatch() }
            onClear: function() { if (root.onClearSelection) root.onClearSelection() }
        }

        TextField {
            id: searchField
            width: root.searchActive ? Math.max(Style.space(80), row.width - row._fixedWidth) : 0
            height: row.height
            visible: root.searchActive
            placeholderText: "Search..."
            text: root.searchQuery
            color: root.bar.foreground
            placeholderTextColor: Qt.darker(root.bar.foreground, 1.4)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.body
            background: Rectangle {
                color: Qt.darker(root.bar.background, 1.2)
                radius: Style.space(4)
                border.color: Qt.darker(root.bar.background, 1.4)
                border.width: 1
            }
            onTextChanged: {
                root.searchQuery = text
                if (root.onSearchChanged) root.onSearchChanged(text)
            }
            Keys.onEscapePressed: {
                root.searchActive = false
                root.searchQuery = ""
                if (root.onSearchActiveToggled) root.onSearchActiveToggled(false)
            }
        }

        Button {
            id: searchButton
            text: root.searchActive ? Icons.times : Icons.search
            visible: root.showSearch && !root.searchActive
            tooltipText: "Search"
            onClicked: {
                root.searchActive = true
                if (root.onSearchActiveToggled) root.onSearchActiveToggled(true)
                searchField.forceActiveFocus()
            }
        }

        // Primary action: Upload - always visible when not searching/batch
        Button {
            id: uploadButton
            text: Icons.upload
            visible: root.showUpload && !root.searchActive && root.selectionCount === 0
            tooltipText: "Upload file"
            onClicked: {
                if (root.onUploadClicked) root.onUploadClicked()
            }
        }

        // Transfer indicator (always visible when transfers exist)
        Item {
            id: transferIndicator
            width: Style.space(28)
            height: row.height
            visible: root.showTransfers && (root.activeTransferCount > 0 || root.hasTransferFailures)

            Text {
                id: transfersIcon
                text: Icons.exchange
                color: root.hasTransferFailures ? Color.urgent : root.bar.foreground
                font.family: Icons.family
                font.pixelSize: Style.font.title
                anchors.centerIn: parent
            }

            Text {
                id: transfersBadge
                text: root.activeTransferCount
                color: Color.background
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                visible: root.activeTransferCount > 0
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.topMargin: Style.space(2)
                anchors.rightMargin: Style.space(2)
                z: 1
                textFormat: Text.PlainText
            }

            Rectangle {
                visible: root.activeTransferCount > 0
                radius: width / 2
                color: Color.accent
                width: transfersBadge.implicitWidth + Style.space(4)
                height: transfersBadge.implicitHeight + Style.space(2)
                anchors.centerIn: transfersBadge
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: { if (root.onTransfersClicked) root.onTransfersClicked() }
            }
        }

        // Offline indicator
        Item {
            id: offlineIndicator
            width: root.showOffline ? Style.space(24) : 0
            height: row.height
            visible: root.showOffline

            Text {
                id: offlineIcon
                text: Icons.ban
                color: Color.urgent
                font.family: Icons.family
                font.pixelSize: Style.font.title
                anchors.centerIn: parent
            }
        }

        // Overflow menu button - always visible as the last fixed button
        Button {
            id: overflowButton
            text: Icons.ellipsisV
            tooltipText: "More actions"
            onClicked: {
                root.overflowOpen = !root.overflowOpen
            }
        }

    }

    // Custom Omarseafile-styled overflow menu (Popup, not native Menu)
    OverflowMenu {
        id: overflowMenu
        bar: root.bar
        showCreateFolder: root.showCreateFolder
        showRefresh: root.showRefresh
        showTransfers: root.showTransfers
        showTrash: root.showTrash
        showSettings: root.showSettings
        showLogout: root.showLogout
        selectionCount: root.selectionCount
        searchActive: root.searchActive
        onCreateFolderClicked: root.onCreateFolderClicked
        onRefreshClicked: root.onRefreshClicked
        onTransfersClicked: root.onTransfersClicked
        onTrashClicked: root.onTrashClicked
        onSettingsClicked: root.onSettingsClicked
        onLogoutClicked: root.onLogoutClicked
        onAboutToShow: {
            // Reparent to the overlay and anchor to the overflow button.
            overflowMenu.parent = root.overlay
            var pt = overflowButton.mapToItem(root.overlay, 0, 0)
            overflowMenu.x = pt.x + overflowButton.width - overflowMenu.width
            overflowMenu.y = pt.y + overflowButton.height + Style.space(2)
        }
        onOpened: root.overflowOpen = true
        onClosed: root.overflowOpen = false
    }

    onOverflowOpenChanged: {
        if (root.overflowOpen) overflowMenu.open()
        else overflowMenu.close()
    }
}