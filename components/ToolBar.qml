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
    property bool showOffline: false
    property bool showSearch: false
    property bool showLogout: false
    property bool showTransfers: false
    property int activeTransferCount: 0
    property bool hasTransferFailures: false
    property var onTransfersClicked: null
    property string searchQuery: ""
    property bool searchActive: false
    property var onBackClicked: null
    property var onRefreshClicked: null
    property var onUploadClicked: null
    property var onSearchChanged: null
    property var onSearchActiveChanged: null
    property var onLogoutClicked: null

    implicitHeight: row.implicitHeight
    width: parent.width

    Row {
        id: row
        anchors.fill: parent
        anchors.leftMargin: Style.space(12)
        anchors.rightMargin: Style.space(12)
        spacing: Style.space(8)

        Button {
            id: backButton
            text: "\uf053"
            font.family: "Noto Sans"
            font.pixelSize: Style.font.title
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
            width: parent.width - backButton.width - searchField.width - searchButton.width - refreshButton.width - uploadButton.width - offlineIndicator.width - Style.space(24)
            anchors.verticalCenter: parent.verticalCenter
            visible: !root.searchActive
        }

        TextField {
            id: searchField
            width: root.searchActive ? parent.width - backButton.width - searchButton.width - refreshButton.width - uploadButton.width - offlineIndicator.width - Style.space(24) : 0
            height: row.height
            visible: root.searchActive
            placeholderText: "Search..."
            text: root.searchQuery
            color: root.bar.foreground
            placeholderColor: Qt.darker(root.bar.foreground, 1.4)
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
                if (root.onSearchActiveChanged) root.onSearchActiveChanged(false)
            }
        }

        Button {
            id: searchButton
            text: root.searchActive ? "\uf00d" : "\uf002"
            font.family: "Noto Sans"
            font.pixelSize: Style.font.title
            visible: root.showSearch
            onClicked: {
                root.searchActive = !root.searchActive
                if (!root.searchActive) {
                    root.searchQuery = ""
                }
                if (root.onSearchActiveChanged) root.onSearchActiveChanged(root.searchActive)
                if (root.searchActive) {
                    searchField.forceActiveFocus()
                }
            }
        }

        Button {
            id: uploadButton
            text: "\uf093"
            font.family: "Noto Sans"
            font.pixelSize: Style.font.title
            visible: root.showUpload && !root.searchActive
            tooltipText: "Upload file"
            onClicked: {
                if (root.onUploadClicked) root.onUploadClicked()
            }
        }

        Button {
            id: refreshButton
            text: "\uf021"
            font.family: "Noto Sans"
            font.pixelSize: Style.font.title
            visible: root.showRefresh && !root.searchActive
            onClicked: {
                if (root.onRefreshClicked) root.onRefreshClicked()
            }
        }

        Button {
            id: logoutButton
            text: "\uf08b"
            font.family: "Noto Sans"
            font.pixelSize: Style.font.title
            visible: root.showLogout && !root.searchActive
            tooltipText: "Logout"
            onClicked: {
                if (root.onLogoutClicked) root.onLogoutClicked()
            }
        }

        Item {
            id: transfersButton
            width: Style.space(28)
            height: row.height
            visible: root.showTransfers && !root.searchActive

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
                font.pixelSize: Style.font.tiny
                font.bold: true
                visible: root.activeTransferCount > 0
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.topMargin: Style.space(2)
                anchors.rightMargin: Style.space(2)
                background: Rectangle {
                    radius: width / 2
                    color: Color.accent
                    width: transfersBadge.implicitWidth + Style.space(4)
                    height: transfersBadge.implicitHeight + Style.space(2)
                    anchors.centerIn: transfersBadge
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: { if (root.onTransfersClicked) root.onTransfersClicked() }
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