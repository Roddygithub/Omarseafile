import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui
import "../js"
import "../components"

Item {
    id: root
    required property QtObject bar
    required property var currentItems
    required property var pathHistory
    required property var libraries
    required property bool loading
    required property string errorMessage
    required property bool searchActive
    required property string searchState
    required property var searchResults
    required property string searchErrorMessage
    required property bool searchTruncated
    required property int maxSearchResults
    required property bool showTransfers
    required property int transferRevision
    required property var selectedItems
    required property var selectionAnchor
    required property var currentRepo
    required property string currentPath
    required property var destinationMode
    required property ConnectionService connectionService
    required property bool singleClickOpen
    required property bool foldersFirst

    required property var onItemClicked
    required property var onDownloadClicked
    required property var onOpenClicked
    required property var onRenameClicked
    required property var onMoveClicked
    required property var onDeleteClicked
    required property var onShareClicked
    required property var onHistoryClicked
    required property var onSearchResultClicked
    required property var onNavigateToPath
    required property var onRefresh
    required property var onToggleSelection
    required property var onSelectRange
    required property var onSelectOnly
    required property var onPositionClicked
    required property var onContextMenuRequested

    width: parent.width
    implicitHeight: content.implicitHeight

    // The FileList Panel drives with the keyboard, exposed through the view API
    // so Panel never reaches for a lexical id inside this component. Null while
    // a search or the transfers surface owns the content area.
    readonly property var activeFileList: fileList.visible ? fileList : null

    Column {
        id: content
        width: parent.width
        spacing: 0

        Breadcrumbs {
            id: breadcrumbs
            width: parent.width
            height: visible ? implicitHeight : 0
            path: root.pathHistory
            bar: root.bar
            visible: !root.searchActive
            onSegmentClicked: function(index) { root.onNavigateToPath(index) }
        }

        LoadingIndicator {
            id: loadingIndicator
            width: parent.width
            visible: root.loading
            message: root.searchActive ? "Searching..." : "Loading..."
            bar: root.bar
        }

        ErrorOverlay {
            id: errorOverlay
            width: parent.width
            showError: root.errorMessage !== "" && !root.searchActive
            message: root.errorMessage
            bar: root.bar
            onRetry: root.onRefresh
        }

        OfflineBanner {
            id: offlineBanner
            width: parent.width
            visible: offlineBannerVisible
            message: "Offline - unreachable"
            bar: root.bar
            readonly property bool offlineBannerVisible: root.connectionService && !root.connectionService.online
        }

        Text {
            id: searchStatusText
            width: parent.width
            height: visible ? contentHeight + topPadding : 0
            visible: root.searchActive && (root.searchState === "loading" || root.searchState === "results" || root.searchState === "empty")
            text: root.searchState === "loading"
                ? ("Searching " + (root.libraries.length - root.searchPendingCount) + " of " + root.libraries.length + " libraries...")
                : (root.searchState === "results"
                    ? (root.searchTruncated
                        ? "Showing first " + root.maxSearchResults + " results. Refine your search."
                        : root.searchResults.length + " result(s) found")
                    : "No results found")
            color: Qt.darker(root.bar.foreground, 1.4)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
            horizontalAlignment: Text.AlignHCenter
            topPadding: Style.space(4)
            textFormat: Text.PlainText
        }

        ErrorOverlay {
            id: searchErrorOverlay
            width: parent.width
            showError: root.searchActive && root.searchState === "error"
            message: root.searchErrorMessage
            bar: root.bar
            onRetry: function() { root.onSearchRetry() }
        }

        FileList {
            id: fileList
            width: parent.width
            bar: root.bar
            height: fileList.contentHeight > 0 ? Math.min(fileList.contentHeight, Style.space(420)) : Style.space(120)
            items: root.currentItems
            focus: true
            findTransfer: TransferService.findTransfer
            transferRevision: root.transferRevision
            onItemClicked: root.onItemClicked
            onDownloadClicked: root.onDownloadClicked
            onOpenClicked: root.onOpenClicked
            onRenameClicked: root.onRenameClicked
            onMoveClicked: root.onMoveClicked
            onDeleteClicked: root.onDeleteClicked
            onShareClicked: root.onShareClicked
            onHistoryClicked: root.onHistoryClicked
            visible: !root.loading && root.errorMessage === "" && !root.searchActive && !root.showTransfers
            selectedItems: root.selectedItems
            selectionAnchor: root.selectionAnchor
            onSelectionToggle: root.onToggleSelection
            onSelectionRange: root.onSelectRange
            onSelectOnly: root.onSelectOnly
            onPositionClicked: root.onPositionClicked
            onContextMenuRequested: root.onContextMenuRequested
            singleClickOpen: root.singleClickOpen
            foldersFirst: root.foldersFirst
        }

        SearchResults {
            id: searchResultsList
            width: parent.width
            height: visible ? (contentHeight > 0 ? Math.min(contentHeight, Style.space(420)) : Style.space(120)) : 0
            results: root.searchResults
            bar: root.bar
            visible: root.searchActive && root.searchState !== "loading"
            onResultClicked: root.onSearchResultClicked
        }

        // The TransferManager now lives at Panel level (see Panel.qml's
        // transfersLoader) so that Transfers works from the Libraries root,
        // where currentRepo is null and this view is not instantiated. Keeping
        // a second instance here would duplicate transfer state.

        // Details panel - shows info for selected item(s)
        DetailsPanel {
            id: detailsPanel
            width: parent.width
            bar: root.bar
            selectedItems: root.selectedItems
            currentRepo: root.currentRepo
            currentPath: root.currentPath
            visible: root.selectedItems.length > 0 && !root.loading && !root.searchActive && !root.showTransfers
            onDownload: function(item) { root.onDownloadClicked(item) }
            onOpen: function(item) { root.onOpenClicked(item) }
            onShare: function(item) { root.onShareClicked(item) }
            onHistory: function(item) { root.onHistoryClicked(item) }
            onRename: function(item) { root.onRenameClicked(item) }
            onMove: function(item) { root.onMoveClicked(item) }
            onDelete: function(item) { root.onDeleteClicked(item) }
            onItemClicked: function(item) { root.onItemClicked(item) }
        }
    }

    function showToast(message, type) {
        // Toast is handled by parent Panel
        console.warn("BrowserView.showToast not connected:", message)
    }

    required property int searchPendingCount
    required property var onSearchRetry
}