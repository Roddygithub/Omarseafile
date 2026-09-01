import QtQuick
import qs.Commons
import qs.Ui

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

    Row {
        id: row
        anchors.fill: parent
        anchors.leftMargin: Style.space(12)
        anchors.rightMargin: Style.space(12)
        spacing: Style.space(8)

        // AUDIT-FIX: reserve width for ALL action buttons so the title cannot push them off-card
        readonly property int _fixedButtons: (backButton.visible ? backButton.width : 0)
            + (searchButton.visible ? searchButton.width : 0)
            + (uploadButton.visible ? uploadButton.width : 0)
            + (createFolderButton.visible ? createFolderButton.width : 0)
            + (refreshButton.visible ? refreshButton.width : 0)
            + (settingsButton.visible ? settingsButton.width : 0)
            + (logoutButton.visible ? logoutButton.width : 0)
            + (transfersButton.visible ? transfersButton.width : 0)
            + (trashButton.visible ? trashButton.width : 0)
            + (offlineIndicator.visible ? offlineIndicator.width : 0)
            + (batchActionBar.visible ? batchActionBar.width : 0)
        readonly property int _visibleCount: (backButton.visible ? 1 : 0) + (searchButton.visible ? 1 : 0)
            + (uploadButton.visible ? 1 : 0) + (createFolderButton.visible ? 1 : 0) + (refreshButton.visible ? 1 : 0) + (settingsButton.visible ? 1 : 0)
            + (logoutButton.visible ? 1 : 0) + (transfersButton.visible ? 1 : 0) + (trashButton.visible ? 1 : 0)
            + (offlineIndicator.visible ? 1 : 0) + (batchActionBar.visible ? 1 : 0) + (searchField.visible ? 1 : 0)

        Button {
            id: backButton
            text: "\uf053"
            visible: root.showBack
            onClicked: {
                if (root.onBackClicked) root.onBackClicked()
            }
        }

        Text {
            id: titleLabel
            text: root.title
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.title
            font.bold: true
            elide: Text.ElideRight
            width: Math.max(Style.space(24), row.width - row._fixedButtons - Style.space(8) * Math.max(0, row._visibleCount - 1))
            anchors.verticalCenter: parent.verticalCenter
            visible: !root.searchActive && root.selectionCount === 0
        }

        BatchActionBar {
            id: batchActionBar
            bar: root.bar
            count: root.selectionCount
            visible: root.selectionCount > 0 && root.destinationMode === ""
            // property var targets: assign callable function EXPRESSIONS.
            // A bare block `{ ... }` would be evaluated as a binding body at
            // creation (ghost calls) and leave the property undefined (dead buttons).
            onMove: function() { if (root.onMoveBatch) root.onMoveBatch() }
            onCopy: function() { if (root.onCopyBatch) root.onCopyBatch() }
            onDelete: function() { if (root.onDeleteBatch) root.onDeleteBatch() }
            onClear: function() { if (root.onClearSelection) root.onClearSelection() }
        }

        TextField {
            id: searchField
            width: root.searchActive ? Math.max(Style.space(60), row.width - row._fixedButtons - Style.space(8) * Math.max(0, row._visibleCount - 1)) : 0
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
            visible: root.showSearch
            onClicked: {
                root.searchActive = !root.searchActive
                if (!root.searchActive) {
                    root.searchQuery = ""
                }
                if (root.onSearchActiveToggled) root.onSearchActiveToggled(root.searchActive)
                if (root.searchActive) {
                    searchField.forceActiveFocus()
                }
            }
        }

        Button {
            id: uploadButton
            text: "\uf093"
            visible: root.showUpload && !root.searchActive && !batchActionBar.visible
            tooltipText: "Upload file"
            onClicked: {
                if (root.onUploadClicked) root.onUploadClicked()
            }
        }

        Button {
            id: createFolderButton
            text: "+"
            visible: root.showCreateFolder && !root.searchActive && !batchActionBar.visible
            tooltipText: "New folder"
            onClicked: {
                if (root.onCreateFolderClicked) root.onCreateFolderClicked()
            }
        }

        Button {
            id: refreshButton
            text: "\uf021"
            visible: root.showRefresh && !root.searchActive && !batchActionBar.visible
            onClicked: {
                if (root.onRefreshClicked) root.onRefreshClicked()
            }
        }

        Button {
            id: settingsButton
            text: "\uf013"
            visible: root.showSettings && !root.searchActive
            tooltipText: "Settings"
            onClicked: {
                if (root.onSettingsClicked) root.onSettingsClicked()
            }
        }

        Button {
            id: logoutButton
            text: "\uf08b"
            visible: root.showLogout && !root.searchActive && !batchActionBar.visible
            tooltipText: "Logout"
            onClicked: {
                if (root.onLogoutClicked) root.onLogoutClicked()
            }
        }

        Item {
            id: transfersButton
            width: Style.space(28)
            height: row.height
            visible: root.showTransfers && !root.searchActive && !batchActionBar.visible

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

        Item {
            id: trashButton
            width: Style.space(28)
            height: row.height
            visible: root.showTrash && !root.searchActive && !batchActionBar.visible

            Text {
                id: trashIcon
                text: "\uf1f8"
                color: root.hasTrashItems ? Color.urgent : root.bar.foreground
                font.family: "Noto Sans"
                font.pixelSize: Style.font.title
                anchors.centerIn: parent
            }

            Text {
                id: trashBadge
                text: "0"
                color: Color.background
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                visible: root.selectionCount > 0
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.topMargin: Style.space(2)
                anchors.rightMargin: Style.space(2)
                z: 1
            }

            Rectangle {
                visible: root.selectionCount > 0
                radius: width / 2
                color: Color.accent
                width: trashBadge.implicitWidth + Style.space(4)
                height: trashBadge.implicitHeight + Style.space(2)
                anchors.centerIn: trashBadge
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: { if (root.onTrashClicked) root.onTrashClicked() }
            }
        }

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

    }
}
