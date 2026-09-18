import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui
import "../js"

Item {
    id: root
    required property var bar
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
        anchors.fill: parent
        anchors.leftMargin: Style.space(10)
        anchors.rightMargin: Style.space(10)
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
            text: "\uf053"
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
            anchors.verticalCenter: parent.verticalCenter
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
            text: root.searchActive ? "\uf00d" : "\uf002"
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
            text: "\uf093"
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
                text: "\uf0ec"
                color: root.hasTransferFailures ? Color.urgent : root.bar.foreground
                font.family: "Noto Sans"
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
                text: "\uf05e"
                color: Color.urgent
                font.family: "Noto Sans"
                font.pixelSize: Style.font.title
                anchors.centerIn: parent
            }
        }

        // Overflow menu button - always visible as the last fixed button
        Button {
            id: overflowButton
            text: "\uf142"
            tooltipText: "More actions"
            onClicked: {
                root.overflowOpen = !root.overflowOpen
            }
        }

    }

    // Overflow Menu
    Menu {
        id: overflowMenu
        x: overflowButton.x + overflowButton.width - width
        y: row.y + row.height
        visible: root.overflowOpen
        focus: root.overflowOpen

        MenuItem {
            text: "New folder"
            visible: root.showCreateFolder && !root.searchActive && root.selectionCount === 0
            enabled: root.onCreateFolderClicked !== null
            onTriggered: {
                if (root.onCreateFolderClicked) root.onCreateFolderClicked()
                root.overflowOpen = false
            }
        }

        MenuItem {
            text: "Refresh"
            visible: root.showRefresh && !root.searchActive && root.selectionCount === 0
            enabled: root.onRefreshClicked !== null
            onTriggered: {
                if (root.onRefreshClicked) root.onRefreshClicked()
                root.overflowOpen = false
            }
        }

        MenuItem {
            text: "Transfers"
            visible: root.showTransfers && root.selectionCount === 0
            enabled: root.onTransfersClicked !== null
            onTriggered: {
                if (root.onTransfersClicked) root.onTransfersClicked()
                root.overflowOpen = false
            }
        }

        MenuItem {
            text: "Trash"
            visible: root.showTrash && root.selectionCount === 0
            enabled: root.onTrashClicked !== null
            onTriggered: {
                if (root.onTrashClicked) root.onTrashClicked()
                root.overflowOpen = false
            }
        }

        MenuSeparator { }

        MenuItem {
            text: "Settings"
            visible: root.showSettings && root.selectionCount === 0
            enabled: root.onSettingsClicked !== null
            onTriggered: {
                if (root.onSettingsClicked) root.onSettingsClicked()
                root.overflowOpen = false
            }
        }

        MenuItem {
            text: "Logout"
            visible: root.showLogout && root.selectionCount === 0
            enabled: root.onLogoutClicked !== null
            onTriggered: {
                if (root.onLogoutClicked) root.onLogoutClicked()
                root.overflowOpen = false
            }
        }
    }

    // Close overflow menu when clicking outside
    MouseArea {
        anchors.fill: parent
        visible: root.overflowOpen
        onClicked: root.overflowOpen = false
    }

    // Close overflow on Escape
    Keys.onEscapePressed: {
        if (root.overflowOpen) {
            root.overflowOpen = false
            event.accepted = true
        }
    }
}