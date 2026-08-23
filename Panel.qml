import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Ui
import "./js"
import "./components"

Panel {
    id: root
    moduleName: "roddy.seafile"
    ipcTarget: "roddy.seafile"
    manageIpc: false

    property QtObject hostWidget: null
    property var anchorItem: null
    property var bar: null

    property string state: "login"
    property string serverUrl: ""
    property var currentRepo: null
    property string currentPath: "/"
    property var pathHistory: []
    property var libraries: []
    property var currentItems: []
    property bool loading: false
    property string errorMessage: ""
    property string depErrorMessage: ""
    property bool depsChecked: false
    property bool forceRefresh: false

    property int activeTransferCount: 0
    property bool hasTransferFailures: false
    property var fileTransfers: ({})
    property int transferRevision: 0
    property bool showTransfers: false

    // ===== HISTORY / TRASH STATE =====
    property bool showHistory: false
    property bool showTrash: false
    property var historyFile: null
    property var historyFileName: ""
    property var historyFilePath: ""
    property var historyRepoId: ""

    // ===== SELECTION STATE =====
    property var selectedItems: []
    property var selectionAnchor: null

    function selectionKey(item) {
        if (!item) return ""
        return (item.repoId || item.repoId) + ":" + (item.fullPath || item.path || item.name) + ":" + (item.type || (item.isDir ? "dir" : "file"))
    }

    function isSelected(item) {
        if (!item) return false
        var key = item.repoId + ":" + (item.fullPath || item.path || item.name) + ":" + (item.type || (item.isDir ? "dir" : "file"))
        for (var i = 0; i < root.selectedItems.length; i++) {
            var sel = root.selectedItems[i]
            var selKey = sel.repoId + ":" + (sel.fullPath || sel.path || sel.name) + ":" + (sel.type || (sel.isDir ? "dir" : "file"))
            if (sel.repoId === item.repoId && (sel.fullPath || sel.path || sel.name) === (item.fullPath || item.path || item.name)) {
                return true
            }
        }
        return false
    }

    function selectionKeyForItem(item) {
        if (!item) return ""
        var repoId = item.repoId || ""
        var path = item.fullPath || item.path || item.name || ""
        var type = item.type || (item.isDir ? "dir" : "file")
        return repoId + ":" + path + ":" + type
    }

    function isItemSelected(item) {
        var key = root.selectionKeyForItem(item)
        if (!key) return false
        for (var i = 0; i < root.selectedItems.length; i++) {
            if (root.selectionKeyForItem(root.selectedItems[i]) === key) return true
        }
        return false
    }

    function toggleSelection(item) {
        var key = root.selectionKeyForItem(item)
        if (!key) return
        root.selectedItems = SelectionHelper.toggleSelection(root.selectedItems, item)
        root.selectionAnchor = item
    }

    function selectOnly(item) {
        if (!item) return
        root.selectedItems = [item]
        root.selectionAnchor = item
    }

    function selectRange(item) {
        var anchor = root.selectionAnchor
        if (!anchor) {
            anchor = root.currentItems.length > 0 ? root.currentItems[0] : null
        }
        root.selectedItems = SelectionHelper.rangeSelect(root.selectedItems, anchor, item, root.currentItems)
        root.selectionAnchor = item
    }

    // Plain click on a file: clear batch selection but keep the file as the
    // Shift+click range anchor and keyboard cursor position.
    function positionOn(item) {
        root.selectedItems = []
        root.selectionAnchor = item
    }

    function hasTrashItems() {
        if (!root.currentRepo) return false
        var trash = TransferService.getFailedTransfers()
        return trash.length > 0
    }

    function selectAll() {
        root.selectedItems = root.currentItems.slice()
    }

    function clearSelection() {
        root.selectedItems = []
        root.selectionAnchor = null
    }

    function handleBackClick() {
        if (root.showTransfers) { root.showTransfers = false }
        else if (root.showHistory) { root.showHistory = false; historyLoader.sourceComponent = undefined }
        else if (root.showTrash) { root.showTrash = false; trashLoader.sourceComponent = undefined }
        else if (settingsLoader.sourceComponent) { root.closeSettings() }
        else { root.goBack() }
    }

    // Closes the topmost open modal, if any. Returns true when a dialog was
    // dismissed so Escape can close dialogs before it closes the panel.
    function closeTopDialog() {
        if (shareLoader.item) { root.cancelShare(); return true }
        if (copyLoader.item) { root.cancelCopy(); return true }
        if (uploadLoader.item) { root.cancelFilePicker(); return true }
        if (confirmLoader.item) { root.cancelDelete(); return true }
        if (moveLoader.item) { root.cancelMove(); return true }
        if (renameLoader.item) { root.cancelRename(); return true }
        if (createFolderLoader.item) { root.cancelCreateFolder(); return true }
        if (settingsLoader.item) { root.closeSettings(); return true }
        return false
    }

    function showTrashPanel() {
        root.openTrash()
    }

    function pruneSelection() {
        if (!root.currentItems || root.currentItems.length === 0) {
            root.selectedItems = []
            return
        }
        var validKeys = {}
        for (var i = 0; i < root.currentItems.length; i++) {
            var item = root.currentItems[i]
            var key = item.repoId + ":" + (item.fullPath || item.path || item.name) + ":" + (item.type || (item.isDir ? "dir" : "file"))
            validKeys[key] = true
        }
        root.selectedItems = root.selectedItems.filter(function(item) {
            var key = item.repoId + ":" + (item.fullPath || item.path || item.name) + ":" + (item.type || (item.isDir ? "dir" : "file"))
            return validKeys[key] === true
        })
    }

    Connections {
        target: TransferService
        function onTransfersChanged() {
            root.activeTransferCount = TransferService.getActiveCount()
            root.hasTransferFailures = TransferService.hasFailures()
            var active = TransferService.getActiveTransfers()
            var map = {}
            for (var i = 0; i < active.length; i++) {
                var t = active[i]
                if (t.repoId === (root.currentRepo ? root.currentRepo.id : "")) {
                    map[t.id] = t
                    if (t.fileName) map["name:" + t.fileName] = t
                }
            }
            root.fileTransfers = map
            root.transferRevision++
        }
        function onTransferStateChanged(transfer) {
            if (transfer.state === "completed" || transfer.state === "failed" || transfer.state === "cancelled" || transfer.state === "auth_failed") {
                root.handleTransferCompletion(transfer)
            }
        }
    }

    // Search state
    property string searchQuery: ""
    property string searchState: "idle"
    property var searchResults: []
    property string searchErrorMessage: ""
    property int searchGeneration: 0
    property bool searchActive: false
    property int searchPendingCount: 0

    Timer {
        id: searchDebounceTimer
        interval: 300
        repeat: false
        onTriggered: root.executeSearch()
    }

    function open() { panelController.show() }
    function close() { panelController.hide() }
    function toggle() { panelController.open ? close() : open() }
    function closeForPopoutSwitch() { if (panelController.open) panelController.hide() }
    function toggleTransfersView() {
        root.showTransfers = !root.showTransfers
    }

    function showToast(message, type) {
        toast.show(message, type || "success")
    }

    PanelController { id: panelController }

    // Rename target: the single selected item, else the list's current item.
    function renameTarget() {
        if (!root.currentRepo) return null
        if (root.selectedItems.length === 1) return root.selectedItems[0]
        var list = root.fileListRef
        if (!list) return null
        if (list.currentItem) return list.currentItem.item
        if (list.count > 0) {
            list.currentIndex = 0
            return list.itemAtIndex(0)
        }
        return null
    }

    function showItemContextMenu(item, x, y) {
        if (!item) return
        if (!root.isItemSelected(item)) root.selectOnly(item)
        contextMenu.item = item
        contextMenu.isDir = item.type === "dir"
        contextMenu.selectionCount = root.selectedItems.length > 0 ? root.selectedItems.length : 1
        // Parent to the keyboard-panel window's overlay: never clipped by the
        // file list, and rendered in the window that owns pointer/keyboard.
        contextMenu.parent = keyCatcher.Overlay.overlay
        contextMenu.x = Math.max(0, Math.min(x, contextMenu.parent.width - contextMenu.width))
        contextMenu.y = Math.max(0, Math.min(y, contextMenu.parent.height - contextMenu.implicitHeight))
        contextMenu.open()
    }

    ConnectionService {
        id: connectionService
        serverUrl: root.serverUrl
    }

    KeyboardPanel {
        id: panel
        anchorItem: root.anchorItem
        owner: root.hostWidget || root
        bar: root.bar
        open: panelController.open
        focusTarget: keyCatcher
        contentWidth: panel.fittedContentWidth(Style.space(400))
        contentHeight: panel.fittedContentHeight(content.implicitHeight)

        PanelKeyCatcher {
            id: keyCatcher
            anchors.fill: parent
            blocked: root.searchActive
            onCloseRequested: {
                if (root.closeTopDialog()) return
                root.close()
            }
            onMoveRequested: function(dx, dy) {
                if (root.state !== "browse" || root.searchActive) return
                var list = root.fileListRef
                if (!list) return
                if (dy > 0) list.incrementCurrentIndex()
                else if (dy < 0) list.decrementCurrentIndex()
            }
            onActivateRequested: {
                if (root.state !== "browse" || root.searchActive) return
                var list = root.fileListRef
                if (!list || !list.currentItem) return
                var item = list.currentItem.item
                if (item.type === "dir") root.onItemClicked(item)
                else root.onDownloadClicked(item)
            }
            onDeleteRequested: {
                if (root.state !== "browse" || root.searchActive) return
                var list = root.fileListRef
                if (!list || !list.currentItem) return
                root.pickDelete(list.currentItem.item)
            }

            // Window-level shortcuts. They must live inside the KeyboardPanel
            // window (key events land here, not in the bar window), and they
            // fire before focus-item delivery, so they work even though the
            // PanelKeyCatcher holds active focus. Disabled while a text field
            // or dialog owns the UI so editing keys pass through untouched.
            Shortcut {
                sequence: "F2"
                enabled: root.state === "browse" && !root.searchActive && !root.dialogOpen && !root.showTransfers && root.currentRepo !== null
                onActivated: {
                    var target = root.renameTarget()
                    if (target) root.pickRename(target)
                }
            }

            Shortcut {
                sequence: "Ctrl+A"
                enabled: root.state === "browse" && !root.searchActive && !root.dialogOpen && root.currentRepo !== null
                onActivated: root.selectAll()
            }

            // The shell's PanelKeyCatcher only maps "x" to deleteRequested —
            // bind the real Delete key here so it deletes the positioned item.
            Shortcut {
                sequence: "Delete"
                enabled: root.state === "browse" && !root.searchActive && !root.dialogOpen && !root.showTransfers && root.currentRepo !== null
                onActivated: {
                    var list = root.fileListRef
                    if (!list || !list.currentItem) return
                    root.pickDelete(list.currentItem.item)
                }
            }

            // Single context menu at panel level, parented to the window
            // overlay so the file list never clips it.
            ContextMenu {
                id: contextMenu
                bar: root.bar
                onOpenClicked: root.onItemClicked
                onDownloadClicked: root.onDownloadClicked
                onRenameClicked: root.pickRename
                onMoveClicked: root.moveItems
                onCopyClicked: root.copyItems
                onShareClicked: root.pickShare
                onHistoryClicked: root.openHistory
                onDeleteClicked: function(item) {
                    if (item) root.pickDelete(item)
                    else root.deleteItems()
                }
            }

            Column {
                id: content
                width: parent.width
                spacing: 0
                focus: true

                Toast {
                    id: toast
                    width: parent.width
                    bar: root.bar
                }

                ToolBar {
                    id: toolBar
                    width: parent.width
                    bar: root.bar
                    title: root.state === "login" ? "Seafile" : (root.settingsOpen ? "Settings" : (root.searchActive ? "Search" : (root.currentRepo ? root.currentRepo.name : "Libraries")))
                    showBack: root.state === "browse" && !root.searchActive && (!root.dialogOpen || root.settingsOpen) && (root.pathHistory.length > 0 || root.settingsOpen)
                    showRefresh: root.state === "browse" && !root.searchActive && !root.dialogOpen
                    showUpload: root.state === "browse" && !root.searchActive && !root.dialogOpen
                    showSearch: root.state === "browse" && !root.dialogOpen
                    showLogout: root.state === "browse" && !root.dialogOpen
                    showTransfers: root.state === "browse" && !root.dialogOpen
                    showTrash: root.state === "browse" && !root.dialogOpen
                    showSettings: root.state === "browse" && !root.dialogOpen
                    activeTransferCount: root.activeTransferCount
                    hasTransferFailures: root.hasTransferFailures
                    showOffline: !connectionService.online
                    searchActive: root.searchActive
                    searchQuery: root.searchQuery
                    selectionCount: root.selectedItems.length
                    hasTrashItems: root.hasTrashItems
                    onBackClicked: root.handleBackClick
                    onRefreshClicked: root.refresh
                    onUploadClicked: root.pickFileForUpload
                    onSearchChanged: root.onSearchQueryChanged
                    onSearchActiveToggled: root.onSearchActiveToggle
                    onLogoutClicked: root.doLogout
                    onTransfersClicked: root.toggleTransfersView
                    onTrashClicked: root.showTrashPanel
                    onSettingsClicked: root.openSettings
                    onMoveBatch: root.moveItems
                    onCopyBatch: root.copyItems
                    onDeleteBatch: root.deleteItems
                    onClearSelection: root.clearSelection
                }

                Loader {
                    id: stateLoader
                    sourceComponent: root.state === "login" ? loginComponent : browseComponent
                    width: parent.width
                    visible: !root.dialogOpen
                    height: visible ? implicitHeight : 0
                }
                Loader { id: createFolderLoader; sourceComponent: undefined; width: parent.width; height: item ? item.implicitHeight : 0 }
                Loader { id: renameLoader; sourceComponent: undefined; width: parent.width; height: item ? item.implicitHeight : 0 }
                Loader { id: moveLoader; sourceComponent: undefined; width: parent.width; height: item ? item.implicitHeight : 0 }
                Loader { id: confirmLoader; sourceComponent: undefined; width: parent.width; height: item ? item.implicitHeight : 0 }
                Loader { id: shareLoader; sourceComponent: undefined; width: parent.width; height: item ? item.implicitHeight : 0 }
                Loader { id: uploadLoader; sourceComponent: undefined; width: parent.width; height: item ? item.implicitHeight : 0 }
                Loader { id: historyLoader; sourceComponent: undefined; width: parent.width; height: item ? item.implicitHeight : 0 }
                Loader { id: trashLoader; sourceComponent: undefined; width: parent.width; height: item ? item.implicitHeight : 0 }
                Loader { id: copyLoader; sourceComponent: undefined; width: parent.width; height: item ? item.implicitHeight : 0 }
                Loader { id: settingsLoader; sourceComponent: undefined; width: parent.width; height: item ? item.implicitHeight : 0 }

                Component {
                    id: loginComponent
                    LoginDialog {
                        id: loginDialog
                        bar: root.bar
                        serverField.text: root.serverUrl
                        depErrorMessage: root.depErrorMessage
                        onLogin: function(url, email, pass) { root.doLogin(url, email, pass) }
                    }
                }

                Component {
                    id: browseComponent
                    Column {
                        width: parent.width
                        spacing: 0

                        Breadcrumbs {
                            id: breadcrumbs
                            width: parent.width
                            height: visible ? implicitHeight : 0
                            path: root.pathHistory
                            bar: root.bar
                            visible: !root.searchActive
                            onSegmentClicked: function(index) { root.navigateToPath(index) }
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
                            onRetry: function() { root.refresh() }
                        }

                        OfflineBanner {
                            id: offlineBanner
                            width: parent.width
                            visible: !connectionService.online
                            message: "Offline - " + root.serverUrl + " unreachable"
                            bar: root.bar
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
                            anchors.horizontalCenter: parent.horizontalCenter
                            topPadding: Style.space(4)
                        }

                        ErrorOverlay {
                            id: searchErrorOverlay
                            width: parent.width
                            showError: root.searchActive && root.searchState === "error"
                            message: root.searchErrorMessage
                            bar: root.bar
                            onRetry: function() { root.executeSearch() }
                        }

                        FileList {
                            id: fileList
                            width: parent.width
                            bar: root.bar
                            Component.onCompleted: root.fileListRef = fileList
                            Component.onDestruction: if (root.fileListRef === fileList) root.fileListRef = null
                            height: fileList.contentHeight > 0 ? Math.min(fileList.contentHeight, Style.space(420)) : Style.space(120)
                            items: root.currentItems
                            focus: true
                            findTransfer: TransferService.findTransfer
                            transferRevision: root.transferRevision
                            onItemClicked: function(item) { root.onItemClicked(item) }
                            onDownloadClicked: function(item) { root.onDownloadClicked(item) }
                            onRenameClicked: function(item) { root.pickRename(item) }
                            onMoveClicked: function(item) { root.pickMove(item) }
                            onDeleteClicked: function(item) { root.pickDelete(item) }
                            onShareClicked: function(item) { root.pickShare(item) }
                            onHistoryClicked: root.openHistory
                            visible: !root.loading && root.errorMessage === "" && !root.searchActive && !root.showTransfers
                            selectedItems: root.selectedItems
                            selectionAnchor: root.selectionAnchor
                            onSelectionToggle: root.toggleSelection
                            onSelectionRange: root.selectRange
                            onSelectOnly: root.selectOnly
                            onPositionClicked: root.positionOn
                            onContextMenuRequested: root.showItemContextMenu
                        }

                        SearchResults {
                            id: searchResultsList
                            width: parent.width
                            height: visible ? (contentHeight > 0 ? Math.min(contentHeight, Style.space(420)) : Style.space(120)) : 0
                            results: root.searchResults
                            bar: root.bar
                            visible: root.searchActive && root.searchState !== "loading"
                            onResultClicked: function(result) { root.onSearchResultClicked(result) }
                            onResultRightClicked: function(result, mouse) { root.onSearchResultClicked(result) }
                        }

                        TransferManager {
                            id: transferManager
                            width: parent.width
                            height: visible ? Style.space(360) : 0
                            bar: root.bar
                            visible: root.showTransfers && !root.searchActive
                            transferRevision: root.transferRevision
                            onCancel: function(transfer) { TransferService.cancelTransfer(transfer.id) }
                            onRetry: function(transfer) {
                                var token = Auth.getToken()
                                var baseUrl = Auth.getServerUrl()
                                TransferService.retryTransfer(transfer.id, token, baseUrl)
                            }
                            onClearCompleted: function() { TransferService.clearCompleted() }
                            onClearFailed: function() { TransferService.clearFailed() }
                            onOpen: function(transfer) {
                                var url = Models.toFileUrl(transfer.destPath)
                                var success = Qt.openUrlExternally(url)
                                if (!success) root.showToast("Could not open file", "error")
                                root.showTransfers = false
                            }
                            onShowInFolder: function(transfer) {
                                var url = Models.toParentFileUrl(transfer.destPath)
                                var success = Qt.openUrlExternally(url)
                                if (!success) root.showToast("Could not open folder", "error")
                                root.showTransfers = false
                            }
                        }
                    }
                }
            }
        }

    }

    property var fileListRef: null

    readonly property bool settingsOpen: settingsLoader.item !== null
    readonly property bool dialogOpen: settingsLoader.item !== null || createFolderLoader.item !== null || renameLoader.item !== null || moveLoader.item !== null || confirmLoader.item !== null || shareLoader.item !== null || uploadLoader.item !== null || historyLoader.item !== null || trashLoader.item !== null || copyLoader.item !== null

    // ===== DIALOG LOADERS =====

    Component {
        id: createFolderComponent
        CreateFolderDialog {
            bar: root.bar
            onCreate: function() { root.confirmCreateFolder(nameField.text) }
            onCancel: function() { root.cancelCreateFolder() }
        }
    }

    Component {
        id: renameComponent
        RenameDialog {
            bar: root.bar
            title: {
                var d = root.renameItemData
                if (!d || d.items.length === 0) return "Rename"
                return d.items[0].type === "dir" ? "Rename Folder" : "Rename File"
            }
            nameField.text: root.renameItemData && root.renameItemData.items.length > 0 ? (root.renameItemData.items[0].name || "") : ""
            onRename: function() { root.confirmRename(nameField.text) }
            onCancel: function() { root.cancelRename() }
        }
    }

    Component {
        id: moveComponent
        MoveDialog {
            bar: root.bar
            title: {
                var d = root.moveItemData
                if (!d || !d.items || d.items.length === 0) return "Move"
                return d.items[0].type === "dir" ? "Move Folder" : "Move File"
            }
            destField.text: root.currentPath
            onMove: function() { root.confirmMove(destField.text) }
            onCancel: function() { root.cancelMove() }
        }
    }

    Component {
        id: copyComponent
        CopyDialog {
            bar: root.bar
            title: "Copy To"
            destField.text: root.currentPath
            onCopy: function() { root.confirmCopy(destField.text) }
            onCancel: function() { root.cancelCopy() }
        }
    }

    Component {
        id: confirmComponent
        ConfirmDialog {
            bar: root.bar
            // Canonical item-context shape: { items: [...], isDir }. The legacy
            // { item } field is honored only as a safety fallback.
            message: {
                var d = root.deleteItemData
                if (!d) return "Are you sure?"
                var list = d.items && d.items.length > 0 ? d.items : (d.item ? [d.item] : [])
                if (list.length === 0) return "Delete selection?"
                if (list.length > 1) return "Delete " + list.length + " item(s)?"
                var it = list[0]
                return "Delete " + (it.type === "dir" ? "folder" : "file") + " \"" + (it.name || "") + "\"?"
            }
            onConfirm: function() { root.confirmDelete() }
            onCancel: function() { root.cancelDelete() }
        }
    }

    Component {
        id: shareComponent
        ShareDialog {
            bar: root.bar
            item: root.shareItemData ? root.shareItemData.item : null
            repoId: root.currentRepo ? root.currentRepo.id : ""
            repoName: root.currentRepo ? root.currentRepo.name : ""
            itemPath: root.shareItemData ? root.shareItemData.fullPath : ""
            isDir: root.shareItemData ? root.shareItemData.isDir : false
            onDone: function() { root.cancelShare() }
            onCancel: function() { root.cancelShare() }
            onToast: function(msg) { root.showToast(msg) }
        }
    }

    Component {
        id: uploadComponent
        UploadDialog {
            bar: root.bar
            onUpload: function() { root.confirmUpload(pathField.text) }
            onCancel: function() { root.cancelFilePicker() }
        }
    }

    Component {
        id: historyComponent
        HistoryPanel {
            bar: root.bar
            repoId: root.historyRepoId
            filePath: root.historyFilePath
            fileName: root.historyFileName
            onDownloadRevision: function(revision) {
                SeafileAPI.downloadRevision(root.historyRepoId, root.historyFilePath, revision.commitId, function(success, data, error) {
                    if (success) {
                        TransferService.startDownload(
                            { name: root.historyFileName + " (rev " + revision.commitId.substring(0, 8) + ")", type: "file" },
                            Auth.getToken(), root.serverUrl, root.historyRepoId,
                            root.getDownloadsDir(), root.historyFilePath
                        )
                        root.showHistory = false
                        root.showToast("Downloading historical revision...")
                    } else {
                        root.showToast("Failed to download revision: " + error, "error")
                    }
                })
            }
            onClose: function() { root.showHistory = false; historyLoader.sourceComponent = undefined }
        }
    }

    Component {
        id: trashComponent
        TrashPanel {
            bar: root.bar
            repoId: root.currentRepo ? root.currentRepo.id : ""
            onRestoreFolder: function(trashItem) {
                SeafileAPI.restoreFolder(root.currentRepo.id, trashItem.parentDir, trashItem.objName, function(success, error) {
                    if (success) {
                        root.showTrash = false
                        root.showToast("Folder restored")
                        Cache.invalidatePath(root.currentRepo.id, trashItem.parentDir)
                        root.refresh()
                    } else {
                        root.showToast("Failed to restore folder: " + error, "error")
                    }
                })
            }
            onClose: function() { root.showTrash = false; trashLoader.sourceComponent = undefined }
        }
    }

    Component {
        id: settingsComponent
        SettingsDialog {
            bar: root.bar
            serverUrl: root.serverUrl
            pluginVersion: "0.9.0"
            autoLogin: setting("autoLogin", true)
            onClose: function() { root.closeSettings() }
            onLogout: function() { root.doLogout() }
            onClearCache: function() { root.clearCache() }
            onChangeServer: root.changeServerUrl
            onTestConnection: root.testConnection
            onAutoLoginToggled: function(enabled) { setting("autoLogin", enabled) }
        }
    }

    // ===== AUTH =====

    function doLogin(url, email, password) {
        var normalized = normalizeUrl(url)
        if (!normalized) {
            root.loading = false
            root.errorMessage = "Invalid URL format. Use https://domain.com or http://ip:port"
            return
        }
        if (normalized.startsWith("http://")) {
            root.showToast("Warning: Using HTTP — credentials sent in cleartext", "error")
        }
        root.loading = true
        root.errorMessage = ""
        SeafileAPI.setBaseUrl(normalized)
        SeafileAPI.auth(email, password, function(success, token, error) {
            root.loading = false
            if (success) {
                SeafileAPI.setToken(token)
                Auth.storeToken(token, normalized, email).then(function() {
                    root.serverUrl = normalized
                    connectionService.setServerUrl(normalized)
                    connectionService.forceCheck()
                    root.state = "browse"
                    root.loadLibraries()
                }).catch(function(err) {
                    root.errorMessage = "Failed to store credentials: " + err
                })
            } else {
                root.errorMessage = error || "Authentication failed"
            }
        })
    }

    // ===== BROWSING =====

    function loadLibraries() {
        var cached = Cache.getLibraries()
        if (cached && !root.forceRefresh) {
            root.libraries = cached
            root.currentItems = cached
            return
        }
        root.loading = true
        root.errorMessage = ""
        root.currentRepo = null
        root.currentPath = "/"
        root.pathHistory = []
        SeafileAPI.listLibraries(function(success, data, error) {
            root.loading = false
            if (success) {
                root.libraries = data
                root.currentItems = data
                Cache.setLibraries(data)
            } else {
                root.errorMessage = error || "Failed to load libraries"
            }
        })
    }

    // Items arrive from the API without repo/full-path identity; selection,
    // delete and move all need a stable unique key, so enrich each entry.
    function enrichItems(repoId, path, items) {
        var prefix = path === "/" ? "/" : path + "/"
        var out = []
        for (var i = 0; i < items.length; i++) {
            var it = items[i]
            out.push({
                name: it.name,
                type: it.type,
                size: it.size,
                mtime: it.mtime,
                sizeFormatted: it.sizeFormatted,
                repoId: repoId,
                fullPath: prefix + it.name
            })
        }
        return out
    }

    function loadFolder(repoId, path) {
        var cached = Cache.getFolder(repoId, path)
        if (cached && !root.forceRefresh) {
            root.currentItems = root.enrichItems(repoId, path, cached)
            root.currentPath = path
            return
        }
        root.loading = true
        root.errorMessage = ""
        SeafileAPI.listFolder(repoId, path, function(success, data, error) {
            root.loading = false
            if (success) {
                Cache.setFolder(repoId, path, data)
                root.currentItems = root.enrichItems(repoId, path, data)
                root.currentPath = path
            } else {
                root.errorMessage = error || "Failed to load folder"
            }
        })
    }

    function onItemClicked(item) {
        if (item.type === "dir") {
            root.clearSelection()
            if (root.currentRepo) {
                var newPath = root.currentPath === "/" ? "/" + item.name : root.currentPath + "/" + item.name
                root.pathHistory.push({ name: item.name, path: newPath, repoId: root.currentRepo.id })
                root.loadFolder(root.currentRepo.id, newPath)
            } else {
                root.currentRepo = item
                root.pathHistory = [{ name: item.name, path: "/", repoId: item.id }]
                root.loadFolder(item.id, "/")
            }
        }
    }

    function onDownloadClicked(item) {
        if (item.type === "file") {
            var token = Auth.getToken()
            if (!token) { root.errorMessage = "Not authenticated"; return }
            var fullPath = root.currentPath === "/" ? "/" + item.name : root.currentPath + "/" + item.name
            TransferService.startDownload(item, token, root.serverUrl, root.currentRepo.id, getDownloadsDir(), fullPath)
        }
    }

    function goBack() {
        root.clearSelection()
        if (root.pathHistory.length <= 1) {
            root.currentRepo = null
            root.currentPath = "/"
            root.pathHistory = []
            root.loadLibraries()
        } else {
            root.pathHistory.pop()
            var previous = root.pathHistory[root.pathHistory.length - 1]
            if (root.pathHistory.length === 1) {
                root.loadFolder(root.currentRepo.id, "/")
            } else {
                root.loadFolder(root.currentRepo.id, previous.path)
            }
        }
    }

    function navigateToPath(index) {
        root.clearSelection()
        if (index >= root.pathHistory.length - 1) return
        root.pathHistory = root.pathHistory.slice(0, index + 1)
        var target = root.pathHistory[index]
        if (index === 0) {
            root.loadFolder(root.currentRepo.id, "/")
        } else {
            root.loadFolder(root.currentRepo.id, target.path)
        }
    }

    function refresh() {
        root.clearSelection()
        root.forceRefresh = true
        if (root.state === "browse") {
            if (root.currentRepo) {
                Cache.invalidatePath(root.currentRepo.id, root.currentPath)
                root.loadFolder(root.currentRepo.id, root.currentPath)
            } else {
                Cache.invalidateRepo("global")
                root.loadLibraries()
            }
        }
        root.forceRefresh = false
    }

    // ===== SEARCH =====

    function onSearchQueryChanged(query) {
        root.searchQuery = query
        if (query.length < 2) {
            searchDebounceTimer.stop()
            root.searchResults = []
            root.searchState = query.length === 0 ? "idle" : "debounce"
            return
        }
        root.searchState = "debounce"
        searchDebounceTimer.restart()
    }

    function onSearchActiveToggle(active) {
        root.searchActive = active
        if (!active) {
            searchDebounceTimer.stop()
            root.searchQuery = ""
            root.searchResults = []
            root.searchState = "idle"
        } else {
            root.clearSelection()
        }
    }

    property bool searchTruncated: false

    readonly property int maxSearchResults: 100

    function executeSearch() {
        searchDebounceTimer.stop()
        var query = root.searchQuery.trim()
        if (query.length < 2) {
            root.searchState = "idle"
            return
        }

        var generation = ++root.searchGeneration
        root.searchState = "loading"
        root.searchErrorMessage = ""
        root.searchTruncated = false

        // Global search: always cover every non-encrypted library. Results
        // carry repoId so a click navigates into the right library/folder.
        var reposToSearch = []
        for (var i = 0; i < root.libraries.length; i++) {
            if (root.libraries[i].encrypted !== true) {
                reposToSearch.push(root.libraries[i])
            }
        }

        if (reposToSearch.length === 0) {
            root.searchState = "empty"
            return
        }

        root.searchPendingCount = reposToSearch.length
        root.searchResults = []
        root.searchTruncated = false

        var maxConcurrent = 4
        var queue = reposToSearch.slice()
        var running = 0
        var totalResultsCount = 0

        function searchNext() {
            if (queue.length === 0) return
            if (totalResultsCount >= root.maxSearchResults) return

            var repo = queue.shift()
            running++

            SeafileAPI.search(query, repo.id, function(success, results, error) {
                if (generation !== root.searchGeneration) return

                running--
                root.searchPendingCount--

                if (success && results) {
                    var remaining = root.maxSearchResults - totalResultsCount
                    var resultsToAdd = results
                    if (results.length > remaining) {
                        resultsToAdd = results.slice(0, remaining)
                        root.searchTruncated = true
                    }
                    for (var j = 0; j < resultsToAdd.length; j++) {
                        resultsToAdd[j].repoName = repo.name
                    }
                    totalResultsCount += resultsToAdd.length
                    root.searchResults = root.searchResults.concat(resultsToAdd)
                }

                if (root.searchPendingCount === 0 || totalResultsCount >= root.maxSearchResults) {
                    if (root.searchResults.length === 0) {
                        root.searchState = "empty"
                    } else {
                        root.searchState = "results"
                    }
                }

                if (totalResultsCount < root.maxSearchResults) {
                    searchNext()
                }
            })
        }

        var initialBatch = Math.min(maxConcurrent, queue.length)
        for (var k = 0; k < initialBatch; k++) {
            searchNext()
        }
        if (initialBatch === 0) searchNext()
    }

    function onSearchResultClicked(result) {
        root.clearSelection()
        if (result.type === "folder") {
            var repo = null
            for (var i = 0; i < root.libraries.length; i++) {
                if (root.libraries[i].id === result.repoId) {
                    repo = root.libraries[i]
                    break
                }
            }
            if (!repo) return

            root.searchActive = false
            root.searchQuery = ""
            root.searchResults = []
            root.searchState = "idle"

            root.currentRepo = repo
            root.pathHistory = [{ name: repo.name, path: "/", repoId: repo.id }]
            if (result.path !== "/") {
                var segments = result.path.split("/").filter(function(s) { return s !== "" })
                var accPath = ""
                for (var j = 0; j < segments.length; j++) {
                    accPath += "/" + segments[j]
                    root.pathHistory.push({ name: segments[j], path: accPath, repoId: repo.id })
                }
            }
            root.loadFolder(repo.id, result.path)
        } else if (result.type === "file") {
            var repoFile = null
            for (var k = 0; k < root.libraries.length; k++) {
                if (root.libraries[k].id === result.repoId) {
                    repoFile = root.libraries[k]
                    break
                }
            }
            if (!repoFile) return

            root.searchActive = false
            root.searchQuery = ""
            root.searchResults = []
            root.searchState = "idle"

            root.currentRepo = repoFile
            var parentPath = result.parentPath
            root.pathHistory = [{ name: repoFile.name, path: "/", repoId: repoFile.id }]
            if (parentPath !== "/") {
                var segs = parentPath.split("/").filter(function(s) { return s !== "" })
                var ap = ""
                for (var m = 0; m < segs.length; m++) {
                    ap += "/" + segs[m]
                    root.pathHistory.push({ name: segs[m], path: ap, repoId: repoFile.id })
                }
            }
            root.loadFolder(repoFile.id, parentPath)
        }
    }

    // ===== TRANSFERS =====

    function pickFileForUpload() { uploadLoader.sourceComponent = uploadComponent }
    function cancelFilePicker() { uploadLoader.sourceComponent = undefined }
    function confirmUpload(filePath) { uploadLoader.sourceComponent = undefined; startUpload(filePath) }

    // ===== COPY =====

    function pickCopy() {
        if (!root.currentRepo) { root.errorMessage = "No library selected"; return }
        if (root.selectedItems.length === 0) { root.errorMessage = "No items selected"; return }
        copyLoader.sourceComponent = copyComponent
    }

    function cancelCopy() { copyLoader.sourceComponent = undefined }

    function confirmCopy(destPath) {
        if (!destPath || destPath.trim() === "") { root.errorMessage = "Destination path cannot be empty"; return }
        copyLoader.sourceComponent = undefined
        var token = Auth.getToken()
        if (!token) { root.errorMessage = "Not authenticated"; return }
        var destPathTrimmed = destPath.trim()
        root.loading = true
        root.errorMessage = ""

        if (root.moveItemData.items && root.moveItemData.items.length > 1) {
            // Batch copy
            SeafileAPI.copyItems(root.moveItemData.items, root.currentRepo.id, destPathTrimmed, function(success, error) {
                root.loading = false
                if (success) {
                    Cache.invalidatePath(root.currentRepo.id, destPathTrimmed)
                    root.refresh()
                    root.showToast(root.moveItemData.items.length + " items copied")
                    root.clearSelection()
                } else {
                    root.errorMessage = error || "Failed to copy items"
                }
            })
        } else {
            // Single item copy
            var item = root.moveItemData.items[0]
            var token = Auth.getToken()
            var baseUrl = root.serverUrl
            if (item.type === "dir") {
                SeafileAPI.copyFolder(root.currentRepo.id, item.name, root.currentPath, root.currentRepo.id, destPathTrimmed, token, function(success, error) {
                    root.loading = false
                    if (success) {
                        Cache.invalidatePath(root.currentRepo.id, destPathTrimmed)
                        root.refresh()
                        root.showToast("Folder copied")
                    } else {
                        root.errorMessage = error || "Failed to copy folder"
                    }
                })
            } else {
                var fullPath = root.currentPath === "/" ? "/" + item.name : root.currentPath + "/" + item.name
                SeafileAPI.copyFile(root.currentRepo.id, fullPath, root.currentRepo.id, destPathTrimmed, item.name, token, function(success, error) {
                    root.loading = false
                    if (success) {
                        Cache.invalidatePath(root.currentRepo.id, destPathTrimmed)
                        root.refresh()
                        root.showToast("File copied")
                    } else {
                        root.errorMessage = error || "Failed to copy file"
                    }
                })
            }
        }
    }

    function startUpload(localFilePath) {
        if (!root.currentRepo) { root.errorMessage = "No library selected"; return }
        var token = Auth.getToken()
        if (!token) { root.errorMessage = "Not authenticated"; return }
        var fileName = localFilePath.split("/").pop()
        TransferService.startUpload(localFilePath, token, root.serverUrl, root.currentRepo.id, root.currentPath, fileName)
    }

    function getDownloadsDir() { return Quickshell.env("HOME") + "/Downloads" }

    function handleTransferCompletion(transfer) {
        if (transfer.state === "completed") {
            if (transfer.type === "upload") {
                Cache.invalidatePath(root.currentRepo.id, root.currentPath)
                root.refresh()
                root.showToast("Uploaded " + transfer.fileName)
            } else if (transfer.type === "download") {
                root.showToast("Downloaded " + transfer.fileName)
            }
        } else if (transfer.state === "auth_failed") {
            root.doLogout()
        } else if (transfer.state === "failed") {
            root.showToast("Transfer failed: " + (transfer.error || "unknown error"), "error")
        }
    }

    function doLogout() {
        TransferService.logoutCleanup()
        Auth.clearSession()
        SeafileAPI.setToken("")
        Cache.clear()
        root.state = "login"
        root.serverUrl = ""
        root.currentRepo = null
        root.currentPath = "/"
        root.pathHistory = []
        root.libraries = []
        root.currentItems = []
        root.searchQuery = ""
        root.searchResults = []
        root.searchActive = false
        root.searchState = "idle"
        root.errorMessage = ""
    }

    function openSettings() {
        settingsLoader.sourceComponent = settingsComponent
    }

    function closeSettings() {
        settingsLoader.sourceComponent = undefined
    }

    function clearCache() {
        Cache.clear()
        root.showToast("Cache cleared")
    }

    function changeServerUrl(newUrl, apply) {
        var normalized = normalizeUrl(newUrl)
        if (!normalized) {
            root.showToast("Invalid URL format", "error")
            return
        }
        if (apply && normalized !== root.serverUrl) {
            root.doLogout()
            root.serverUrl = normalized
            root.errorMessage = "Server changed. Please log in again."
        }
    }

    function normalizeUrl(url) {
        try {
            var u = new URL(url)
            if (u.protocol !== "http:" && u.protocol !== "https:") return null
            u.pathname = u.pathname.replace(/\/+$/, "")
            return u.toString()
        } catch (e) {
            return null
        }
    }

    function testConnection(url) {
        var normalized = normalizeUrl(url)
        if (!normalized) {
            root.showToast("Invalid URL format", "error")
            return
        }
        // Update the connection test result in settings dialog
        var settingsDialog = settingsLoader.item
        if (settingsDialog) {
            settingsDialog.connectionTestRunning = true
            settingsDialog.connectionTestSuccess = false
            settingsDialog.connectionTestResult.text = "Testing connection..."
        }

        var xhr = new XMLHttpRequest()
        var testUrl = normalized + "/api2/ping/"
        xhr.open("GET", testUrl, true)
        xhr.timeout = 10000
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                var dialog = settingsLoader.item
                if (!dialog) return
                dialog.connectionTestRunning = false
                if (xhr.status >= 200 && xhr.status < 300) {
                    dialog.connectionTestSuccess = true
                    dialog.connectionTestResult.text = "Connection successful"
                } else if (xhr.status === 0) {
                    dialog.connectionTestSuccess = false
                    dialog.connectionTestResult.text = "Connection failed: Network error"
                } else {
                    dialog.connectionTestSuccess = false
                    dialog.connectionTestResult.text = "Connection failed: HTTP " + xhr.status
                }
            }
        }
        xhr.ontimeout = function() {
            var dialog = settingsLoader.item
            if (!dialog) return
            dialog.connectionTestRunning = false
            dialog.connectionTestSuccess = false
            dialog.connectionTestResult.text = "Connection timed out"
        }
        xhr.onerror = function() {
            var dialog = settingsLoader.item
            if (!dialog) return
            dialog.connectionTestRunning = false
            dialog.connectionTestSuccess = false
            dialog.connectionTestResult.text = "Connection error"
        }
        xhr.send()
    }

    // ===== CREATE FOLDER =====

    function pickCreateFolder() {
        if (!root.currentRepo) { root.errorMessage = "No library selected"; return }
        createFolderLoader.sourceComponent = createFolderComponent
    }

    function cancelCreateFolder() { createFolderLoader.sourceComponent = undefined }

    function confirmCreateFolder(folderName) {
        if (!folderName || folderName.trim() === "") { root.errorMessage = "Folder name cannot be empty"; return }
        createFolderLoader.sourceComponent = undefined
        var token = Auth.getToken()
        if (!token) { root.errorMessage = "Not authenticated"; return }
        root.loading = true
        root.errorMessage = ""
        SeafileAPI.createFolder(root.currentRepo.id, root.currentPath, folderName.trim(), token, function(success, error) {
            root.loading = false
            if (success) {
                Cache.invalidatePath(root.currentRepo.id, root.currentPath)
                root.refresh()
                root.showToast("Folder created")
            } else {
                root.errorMessage = error || "Failed to create folder"
            }
        })
    }

    // ===== RENAME =====

    property var renameItemData: null

    function pickRename(item) {
        if (!item) return
        root.renameItemData = { items: [item], isDir: item.type === "dir" }
        renameLoader.sourceComponent = renameComponent
    }

    function cancelRename() { renameLoader.sourceComponent = undefined; root.renameItemData = null }

    function confirmRename(newName) {
        if (!newName || newName.trim() === "") { root.errorMessage = "Name cannot be empty"; return }
        var d = root.renameItemData
        var item = d && d.items && d.items.length > 0 ? d.items[0] : null
        if (!item) { cancelRename(); return }
        if (newName === item.name) { cancelRename(); return }
        renameLoader.sourceComponent = undefined
        var token = Auth.getToken()
        if (!token) { root.errorMessage = "Not authenticated"; return }
        var isDir = d.isDir || item.type === "dir"
        var parentPath = root.currentPath
        root.loading = true
        root.errorMessage = ""
        if (isDir) {
            SeafileAPI.renameFolder(root.currentRepo.id, parentPath, item.name, newName.trim(), token, function(success, error) {
                root.loading = false
                if (success) { Cache.invalidatePath(root.currentRepo.id, parentPath); root.refresh(); root.showToast("Renamed to " + newName.trim()) }
                else { root.errorMessage = error || "Failed to rename folder" }
            })
        } else {
            var fullPath = root.currentPath === "/" ? "/" + item.name : root.currentPath + "/" + item.name
            SeafileAPI.renameFile(root.currentRepo.id, fullPath, newName.trim(), token, function(success, error) {
                root.loading = false
                if (success) { Cache.invalidatePath(root.currentRepo.id, parentPath); root.refresh(); root.showToast("Renamed to " + newName.trim()) }
                else { root.errorMessage = error || "Failed to rename file" }
            })
        }
    }

    // ===== MOVE =====

    property var moveItemData: null

    function pickMove(item) {
        if (!item) return
        root.moveItemData = { items: [item], isDir: item.type === "dir" }
        moveLoader.sourceComponent = moveComponent
    }

    function cancelMove() { moveLoader.sourceComponent = undefined; root.moveItemData = null }

function confirmMove(destPath) {
        if (!destPath || destPath.trim() === "") { root.errorMessage = "Destination path cannot be empty"; return }
        moveLoader.sourceComponent = undefined
        var token = Auth.getToken()
        if (!token) { root.errorMessage = "Not authenticated"; return }
        var items = root.moveItemData.items || []
        var isBatch = items.length > 1
        var destPathTrimmed = destPath.trim()
        root.loading = true
        root.errorMessage = ""

        if (isBatch) {
            // Batch move
            SeafileAPI.moveItems(root.moveItemData.items, root.currentRepo.id, destPathTrimmed, function(success, error) {
                root.loading = false
                if (success) {
                    Cache.invalidatePath(root.currentRepo.id, root.currentPath)
                    Cache.invalidatePath(root.currentRepo.id, destPath.trim())
                    root.refresh()
                    root.showToast(root.moveItemData.items.length + " items moved")
                    root.clearSelection()
                } else {
                    root.errorMessage = error || "Failed to move items"
                }
            })
        } else {
            // Single item move
            var item = items[0]
            var isDir = root.moveItemData.isDir || item.type === "dir"
            var srcPath = root.currentPath === "/" ? "/" + item.name : root.currentPath + "/" + item.name
            if (isDir) {
                SeafileAPI.moveFolder(root.currentRepo.id, item.name, root.currentPath, root.currentRepo.id, destPathTrimmed, token, function(success, error) {
                    root.loading = false
                    if (success) {
                        Cache.invalidatePath(root.currentRepo.id, root.currentPath)
                        Cache.invalidatePath(root.currentRepo.id, destPathTrimmed)
                        root.refresh()
                        root.showToast("Moved successfully")
                    } else { root.errorMessage = error || "Failed to move folder" }
                })
            } else {
                SeafileAPI.moveFile(root.currentRepo ? root.currentRepo.id : "", srcPath, destPathTrimmed, token, function(success, error) {
                    root.loading = false
                    if (success) {
                        Cache.invalidatePath(root.currentRepo.id, root.currentPath)
                        Cache.invalidatePath(root.currentRepo.id, destPathTrimmed)
                        root.refresh()
                        root.showToast("Moved successfully")
                    } else { root.errorMessage = error || "Failed to move file" }
                })
            }
        }
    }

    // ===== DELETE =====

    property var deleteItemData: null

    function pickDelete(item) {
        if (!item) return
        root.deleteItemData = { items: [item], isDir: item.type === "dir" }
        confirmLoader.sourceComponent = confirmComponent
    }

    function cancelDelete() { confirmLoader.sourceComponent = undefined; root.deleteItemData = null }

    function confirmDelete() {
        var data = root.deleteItemData
        if (!data) { confirmLoader.sourceComponent = undefined; return }
        confirmLoader.sourceComponent = undefined
        var token = Auth.getToken()
        if (!token) { root.errorMessage = "Not authenticated"; root.deleteItemData = null; return }
        var items = (data.items && data.items.length > 0) ? data.items : []
        root.deleteItemData = null
        if (items.length === 0) return

        if (items.length === 1) {
            var item = items[0]
            var isDir = data.isDir || item.type === "dir"
            var fullPath = item.fullPath || (root.currentPath === "/" ? "/" + item.name : root.currentPath + "/" + item.name)
            root.loading = true
            root.errorMessage = ""
            if (isDir && fullPath === "/") {
                root.errorMessage = "Cannot delete root directory"
                root.loading = false
                return
            }
            var done = function(success, error) {
                root.loading = false
                if (success) { Cache.invalidatePath(root.currentRepo.id, root.currentPath); root.refresh(); root.showToast("Deleted") }
                else { root.errorMessage = error || "Failed to delete" }
            }
            if (isDir) SeafileAPI.deleteFolder(root.currentRepo.id, fullPath, token, done)
            else SeafileAPI.deleteFile(root.currentRepo ? root.currentRepo.id : "", fullPath, token, done)
            return
        }

        // Batch delete: sequential, keep failures selected
        root.loading = true
        root.errorMessage = ""
        root.clearSelection()
        var results = { success: 0, failed: [] }
        var index = 0

        function deleteNext() {
            if (index >= items.length) {
                root.loading = false
                var msg = results.success + " deleted"
                if (results.failed.length > 0) msg += ", " + results.failed.length + " failed"
                root.showToast(msg, results.failed.length > 0 ? "error" : "success")
                if (results.failed.length > 0) root.selectedItems = results.failed
                Cache.invalidatePath(root.currentRepo.id, root.currentPath)
                root.refresh()
                return
            }
            var it = items[index]
            var path = it.fullPath || (root.currentPath === "/" ? "/" + it.name : root.currentPath + "/" + it.name)
            var step = function(success, error) {
                if (success) results.success++
                else results.failed.push(it)
                index++
                deleteNext()
            }
            if (it.type === "dir") SeafileAPI.deleteFolder(root.currentRepo.id, path, token, step)
            else SeafileAPI.deleteFile(root.currentRepo.id, path, token, step)
        }
        deleteNext()
    }

    // ===== SHARE =====

    property var shareItemData: null

    function pickShare(item) {
        var fullPath = root.currentPath === "/" ? "/" + item.name : root.currentPath + "/" + item.name
        root.shareItemData = { item: item, isDir: item.type === "dir", fullPath: fullPath }
        shareLoader.sourceComponent = shareComponent
    }

    function cancelShare() { shareLoader.sourceComponent = undefined; root.shareItemData = null }

    // ===== BATCH OPERATIONS =====

    function moveItems() {
        if (!root.currentRepo || root.selectedItems.length === 0) return
        root.moveItemData = { items: root.selectedItems.slice(), isDir: false }
        moveLoader.sourceComponent = moveComponent
    }

    function copyItems() {
        if (!root.currentRepo || root.selectedItems.length === 0) return
        root.moveItemData = { items: root.selectedItems.slice(), isDir: false }
        copyLoader.sourceComponent = copyComponent
    }

    function deleteItems() {
        if (root.selectedItems.length === 0) return
        root.deleteItemData = { items: root.selectedItems.slice(), isDir: false }
        confirmLoader.sourceComponent = confirmComponent
    }

    function openHistory(item) {
        if (!root.currentRepo || !item || item.type !== "file") return
        root.historyRepoId = root.currentRepo.id
        root.historyFileName = item.name
        root.historyFilePath = root.currentPath === "/" ? "/" + item.name : root.currentPath + "/" + item.name
        root.showHistory = true
        historyLoader.sourceComponent = historyComponent
    }

    function openTrash() {
        if (!root.currentRepo) {
            root.showToast("Open a library to browse its trash", "error")
            return
        }
        root.showTrash = true
        trashLoader.sourceComponent = trashComponent
    }

    // ===== INIT =====

    Component.onCompleted: {
        Auth.checkDependencies().then(function(missing) {
                        var hasRequiredMissing = false
            for (var i = 0; i < missing.length; i++) {
                if (missing[i].required) hasRequiredMissing = true
            }
            if (missing.length > 0) {
                var msg = "Missing dependencies:\n"
                for (var j = 0; j < missing.length; j++) {
                    msg += "  • " + missing[j].name + " — install: " + missing[j].install + (missing[j].required ? " (required)" : " (optional)") + "\n"
                }
                root.depErrorMessage = msg
            }
            root.depsChecked = true

            Auth.isAuthenticated().then(function(authenticated) {
                    if (authenticated && !hasRequiredMissing) {
                    var token = Auth.getToken()
                    var serverUrl = Auth.getServerUrl()
                    root.serverUrl = serverUrl
                    SeafileAPI.setBaseUrl(serverUrl)
                    SeafileAPI.setToken(token)
                    connectionService.setServerUrl(serverUrl)
                    root.state = "browse"
                    root.loadLibraries()
                }
            })
        })

        root.activeTransferCount = TransferService.getActiveCount()
        root.hasTransferFailures = TransferService.hasFailures()
    }
}
