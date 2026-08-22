import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "./js/Auth.js" as Auth
import "./js/SeafileAPI.js" as SeafileAPI
import "./js/Models.js" as Models
import "./js/TransferService.js" as TransferService
import "./js/Cache.js" as Cache
import "./js/ConnectionService.js" as ConnectionService
import "./js/SelectionHelper.js" as SelectionHelper
import "./components/LoginDialog.qml" as LoginDialog
import "./components/FileList.qml" as FileList
import "./components/Breadcrumbs.qml" as Breadcrumbs
import "./components/LoadingIndicator.qml" as LoadingIndicator
import "./components/ErrorOverlay.qml" as ErrorOverlay
import "./components/UploadDialog.qml" as UploadDialog
import "./components/CreateFolderDialog.qml" as CreateFolderDialog
import "./components/RenameDialog.qml" as RenameDialog
import "./components/MoveDialog.qml" as MoveDialog
import "./components/ConfirmDialog.qml" as ConfirmDialog
import "./components/ShareDialog.qml" as ShareDialog
import "./components/SearchResults.qml" as SearchResults
import "./components/Toast.qml" as Toast
import "./components/TransferManager.qml" as TransferManager
import "./components/CopyDialog.qml" as CopyDialog
import "./components/HistoryPanel.qml" as HistoryPanel
import "./components/TrashPanel.qml" as TrashPanel
import "./components/SettingsDialog.qml" as SettingsDialog

Panel {
    id: root
    moduleName: "roddy.seafile"
    ipcTarget: "roddy.seafile"
    manageIpc: false

    property QtObject hostWidget: null
    property var anchorItem: null
    property var bar: null

    property string state: Auth.isAuthenticated() ? "browse" : "login"
    property string serverUrl: Auth.getServerUrl() || ""
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

    property int activeTransferCount: TransferService.getActiveCount()
    property bool hasTransferFailures: TransferService.hasFailures()
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
        var idx = -1
        for (var i = 0; i < root.selectedItems.length; i++) {
            if (root.selectionKeyForItem(root.selectedItems[i]) === key) {
                idx = i
                break
            }
        }
        if (idx >= 0) {
            root.selectedItems.splice(idx, 1)
        } else {
            root.selectedItems.push(item)
        }
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
    function toggle() { opened ? close() : open() }
    function closeForPopoutSwitch() { if (panelController.open) panelController.hide() }
    function toggleTransfersView() { root.showTransfers = !root.showTransfers }

    function showToast(message, type) {
        toast.show(message, type || "success")
    }

    PanelController { id: panelController }

    ConnectionService {
        id: connectionService
        serverUrl: root.serverUrl
    }

    KeyboardPanel {
        id: panel
        anchorItem: root.anchorItem
        owner: root.hostWidget || root
        bar: root.bar
        open: root.opened
        focusTarget: keyCatcher
        contentWidth: panel.fittedContentWidth(Style.space(400))
        contentHeight: panel.fittedContentHeight(content.implicitHeight, Style.space(500))

        PanelKeyCatcher {
            id: keyCatcher
            anchors.fill: parent
            blocked: root.searchActive
            onCloseRequested: root.close()
            onMoveRequested: function(dx, dy) {
                if (root.state !== "browse" || root.searchActive) return
                var list = fileList
                if (dy > 0) list.incrementCurrentIndex()
                else if (dy < 0) list.decrementCurrentIndex()
            }
            onActivateRequested: {
                if (root.state !== "browse" || root.searchActive) return
                var list = fileList
                if (!list.currentItem) return
                var item = list.currentItem.item
                if (item.type === "dir") root.onItemClicked(item)
                else root.onDownloadClicked(item)
            }
            onDeleteRequested: {
                if (root.state !== "browse" || root.searchActive) return
                var list = fileList
                if (!list.currentItem) return
                root.pickDelete(list.currentItem.item)
            }

            Column {
                id: content
                width: parent.width
                spacing: 0
                focus: true
                Keys.onPressed: function(event) {
                    if (root.searchActive || root.state !== "browse") return
                    if (event.key === Qt.Key_F2) {
                        var list = fileList
                        if (!list.currentItem) return
                        if (root.selectedItems.length === 1 && root.isItemSelected(list.currentItem.item)) {
                            root.pickRename(list.currentItem.item)
                        } else {
                            root.pickRename(list.currentItem.item)
                        }
                        event.accepted = true
                    } else if (event.key === Qt.Key_A && (event.modifiers & Qt.ControlModifier)) {
                        // Ctrl+A for Select All
                        root.selectAll()
                        event.accepted = true
                    }
                }

                Toast {
                    id: toast
                    width: parent.width
                    bar: root.bar
                }

                ToolBar {
                    id: toolBar
                    width: parent.width
                    bar: root.bar
                    title: root.state === "login" ? "Seafile" : (root.searchActive ? "Search" : (root.currentRepo ? root.currentRepo.name : "Libraries"))
                    showBack: root.state === "browse" && root.pathHistory.length > 0 && !root.searchActive
                    showRefresh: root.state === "browse" && !root.searchActive
                    showUpload: root.state === "browse" && !root.searchActive
                    showSearch: root.state === "browse"
                    showLogout: root.state === "browse"
                    showTransfers: root.state === "browse"
                    showTrash: root.state === "browse"
                    showSettings: root.state === "browse"
                    activeTransferCount: root.activeTransferCount
                    hasTransferFailures: root.hasTransferFailures()
                    showOffline: !connectionService.online
                    searchActive: root.searchActive
                    searchQuery: root.searchQuery
                    selectionCount: root.selectedItems.length
                    hasTrashItems: root.hasTrashItems()
                    onBackClicked: {
                        if (root.showTransfers) { root.showTransfers = false }
                        else if (root.showHistory) { root.showHistory = false }
                        else if (root.showTrash) { root.showTrash = false }
                        else if (settingsLoader.sourceComponent) { root.closeSettings() }
                        else { root.goBack() }
                    }
                    onRefreshClicked: root.refresh()
                    onUploadClicked: root.pickFileForUpload()
                    onSearchChanged: root.onSearchQueryChanged(query)
                    onSearchActiveChanged: root.onSearchActiveToggle(active)
                    onLogoutClicked: root.doLogout()
                    onTransfersClicked: root.toggleTransfersView()
                    onTrashClicked: root.showTrash()
                    onSettingsClicked: root.openSettings()
                    onMoveBatch: root.moveItems
                    onCopyBatch: root.copyItems
                    onDeleteBatch: root.deleteItems
                    onClearSelection: root.clearSelection
                }

                Loader {
                    id: stateLoader
                    sourceComponent: root.state === "login" ? loginComponent : browseComponent
                }

                Component {
                    id: loginComponent
                    LoginDialog {
                        id: loginDialog
                        bar: root.bar
                        serverField.text: root.serverUrl
                        emailField.text: Auth.getEmail() || ""
                        depErrorMessage: root.depErrorMessage
                        onLogin: root.doLogin(serverField.text, emailField.text, passwordField.text)
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
                            path: root.pathHistory
                            bar: root.bar
                            visible: !root.searchActive
                            onSegmentClicked: root.navigateToPath(index)
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
                            visible: root.errorMessage !== "" && !root.searchActive
                            message: root.errorMessage
                            bar: root.bar
                            onRetry: root.refresh()
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
                            height: implicitHeight + Style.space(8)
                            visible: root.searchActive && (root.searchState === "loading" || root.searchState === "results" || root.searchState === "empty")
                            text: root.searchState === "loading"
                                ? "Searching across libraries..."
                                : (root.searchState === "results"
                                    ? root.searchResults.length + " result(s) found"
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
                            visible: root.searchActive && root.searchState === "error"
                            message: root.searchErrorMessage
                            bar: root.bar
                            onRetry: root.executeSearch()
                        }

                        FileList {
                            id: fileList
                            width: parent.width
                            height: parent.height - toolBar.height - (breadcrumbs.visible ? breadcrumbs.height : 0) - (root.loading ? loadingIndicator.height : 0) - (root.errorMessage && !root.searchActive ? errorOverlay.height : 0) - (!connectionService.online ? offlineBanner.height : 0) - (searchStatusText.visible ? searchStatusText.height : 0) - (searchErrorOverlay.visible ? searchErrorOverlay.height : 0)
                            items: root.currentItems
                            focus: true
                            findTransfer: root.findTransfer
                            transferRevision: root.transferRevision
                            onItemClicked: root.onItemClicked(item)
                            onDownloadClicked: root.onDownloadClicked(item)
                            onRenameClicked: root.pickRename(item)
                            onMoveClicked: root.pickMove(item)
                            onDeleteClicked: root.pickDelete(item)
                            onShareClicked: root.pickShare(item)
                            onHistoryClicked: root.showHistory
                            visible: !root.loading && root.errorMessage === "" && !root.searchActive && !root.showTransfers
                            selectedItems: root.selectedItems
                            selectionAnchor: root.selectionAnchor
                            onSelectionToggle: root.onSelectionToggle
                            onSelectionRange: root.onSelectionRange
                        }

                        SearchResults {
                            id: searchResultsList
                            width: parent.width
                            height: parent.height - toolBar.height - (searchStatusText.visible ? searchStatusText.height : 0) - (searchErrorOverlay.visible ? searchErrorOverlay.height : 0) - (!connectionService.online ? offlineBanner.height : 0)
                            results: root.searchResults
                            bar: root.bar
                            visible: root.searchActive && root.searchState !== "loading"
                            onResultClicked: root.onSearchResultClicked(result)
                        }

                        TransferManager {
                            id: transferManager
                            width: parent.width
                            height: parent.height - toolBar.height - (breadcrumbs.visible ? breadcrumbs.height : 0)
                            bar: root.bar
                            visible: root.showTransfers && !root.searchActive
                            transferRevision: root.transferRevision
                            onCancel: function(transfer) { TransferService.cancelTransfer(transfer.id) }
                            onRetry: function(transfer) {
                                var token = Auth.getToken()
                                var baseUrl = Auth.getServerUrl()
                                TransferService.retryTransfer(transfer.id, token, baseUrl)
                            }
                            onClearCompleted: TransferService.clearCompleted()
                            onClearFailed: TransferService.clearFailed()
                        }
                    }
                }
            }
        }
    }

    // ===== DIALOG LOADERS =====

    Loader { id: createFolderLoader; sourceComponent: undefined }
    Component {
        id: createFolderComponent
        CreateFolderDialog {
            bar: root.bar
            onCreate: root.confirmCreateFolder(nameField.text)
            onCancel: root.cancelCreateFolder()
        }
    }

    Loader { id: renameLoader; sourceComponent: undefined }
    Component {
        id: renameComponent
        RenameDialog {
            bar: root.bar
            title: root.renameItemData.isDir ? "Rename Folder" : "Rename File"
            nameField.text: root.renameItemData.item.name
            onRename: root.confirmRename(nameField.text)
            onCancel: root.cancelRename()
        }
    }

    Loader { id: moveLoader; sourceComponent: undefined }
    Component {
        id: moveComponent
        MoveDialog {
            bar: root.bar
            title: root.moveItemData.isDir ? "Move Folder" : "Move File"
            destField.text: root.currentPath
            onMove: root.confirmMove(destField.text)
            onCancel: root.cancelMove()
        }
    }

    Loader { id: confirmLoader; sourceComponent: undefined }
    Component {
        id: confirmComponent
        ConfirmDialog {
            bar: root.bar
            message: "Delete " + (root.deleteItemData.isDir ? "folder" : "file") + " \"" + root.deleteItemData.item.name + "\"?"
            onConfirm: root.confirmDelete()
            onCancel: root.cancelDelete()
        }
    }

    Loader { id: shareLoader; sourceComponent: undefined }
    Component {
        id: shareComponent
        ShareDialog {
            bar: root.bar
            item: root.shareItemData.item
            repoId: root.currentRepo ? root.currentRepo.id : ""
            repoName: root.currentRepo ? root.currentRepo.name : ""
            itemPath: root.shareItemData.fullPath
            isDir: root.shareItemData.isDir
            onDone: root.cancelShare()
            onCancel: root.cancelShare()
            onToast: function(msg) { root.showToast(msg) }
        }
    }

    Loader { id: uploadLoader; sourceComponent: undefined }
    Component {
        id: uploadComponent
        UploadDialog {
            bar: root.bar
            onUpload: root.confirmUpload(pathField.text)
            onCancel: root.cancelFilePicker()
        }
    }

    Loader { id: historyLoader; sourceComponent: undefined }
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
            onClose: function() { root.showHistory = false }
        }
    }

    Loader { id: trashLoader; sourceComponent: undefined }
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
            onClose: function() { root.showTrash = false }
        }
    }

    Loader { id: settingsLoader; sourceComponent: undefined }
    Component {
        id: settingsComponent
        SettingsDialog {
            bar: root.bar
            serverUrl: root.serverUrl
            accountEmail: Auth.getEmail()
            pluginVersion: "0.8.0"
            autoLogin: setting("autoLogin", true)
            onClose: root.closeSettings()
            onLogout: root.doLogout()
            onClearCache: root.clearCache()
            onChangeServer: root.changeServerUrl
            onTestConnection: root.testConnection
            onAutoLoginChanged: function(enabled) { setting("autoLogin", enabled) }
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
                Auth.storeToken(token, normalized, email)
                root.serverUrl = normalized
                connectionService.setServerUrl(normalized)
                connectionService.forceCheck()
                root.state = "browse"
                root.loadLibraries()
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

    function loadFolder(repoId, path) {
        var cached = Cache.getFolder(repoId, path)
        if (cached && !root.forceRefresh) {
            root.currentItems = cached
            root.currentPath = path
            return
        }
        root.loading = true
        root.errorMessage = ""
        SeafileAPI.listFolder(repoId, path, function(success, data, error) {
            root.loading = false
            if (success) {
                root.currentItems = data
                root.currentPath = path
                Cache.setFolder(repoId, path, data)
            } else {
                root.errorMessage = error || "Failed to load folder"
            }
        })
    }

    function onItemClicked(item) {
        if (item.type === "dir") {
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
            fileList.forceActiveFocus()
        } else {
            root.clearSelection()
        }
    }

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

        var reposToSearch = []
        if (root.currentRepo) {
            reposToSearch = [root.currentRepo]
        } else {
            for (var i = 0; i < root.libraries.length; i++) {
                if (root.libraries[i].encrypted !== true) {
                    reposToSearch.push(root.libraries[i])
                }
            }
        }

        if (reposToSearch.length === 0) {
            root.searchState = "empty"
            return
        }

        root.searchPendingCount = reposToSearch.length
        root.searchResults = []

        var maxConcurrent = 4
        var queue = reposToSearch.slice()
        var running = 0

        function searchNext() {
            if (queue.length === 0) return
            var repo = queue.shift()
            running++

            SeafileAPI.searchFilesInRepo(query, repo.id, function(success, results, error) {
                if (generation !== root.searchGeneration) return

                running--
                root.searchPendingCount--

                if (success && results) {
                    for (var j = 0; j < results.length; j++) {
                        results[j].repoName = repo.name
                    }
                    root.searchResults = root.searchResults.concat(results)
                }

                if (root.searchPendingCount === 0) {
                    if (root.searchResults.length === 0) {
                        root.searchState = "empty"
                    } else {
                        root.searchState = "results"
                    }
                }

                searchNext()
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
                SeafileAPI.copyFile(root.currentRepo.id, fullPath, destPathTrimmed, token, baseUrl, function(success, error) {
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

    function cancelCopy() { copyLoader.sourceComponent = undefined }

    function startUpload(localFilePath) {
        var token = Auth.getToken()
        if (!token) { root.errorMessage = "Not authenticated"; return }
        var fileName = localFilePath.split("/").pop()
        TransferService.startUpload(localFilePath, token, root.serverUrl, root.currentRepo.id, root.currentPath, fileName)
    }

    function getDownloadsDir() { return Qt.getenv("HOME") + "/Downloads" }

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
            if (u.pathname === "") u.pathname = "/"
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
        root.renameItemData = { item: item, isDir: item.type === "dir" }
        renameLoader.sourceComponent = renameComponent
    }

    function cancelRename() { renameLoader.sourceComponent = undefined; root.renameItemData = null }

    function confirmRename(newName) {
        if (!newName || newName.trim() === "") { root.errorMessage = "Name cannot be empty"; return }
        if (newName === root.renameItemData.item.name) { cancelRename(); return }
        renameLoader.sourceComponent = undefined
        var token = Auth.getToken()
        if (!token) { root.errorMessage = "Not authenticated"; return }
        var isDir = root.renameItemData.isDir
        var item = root.renameItemData.item
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
        root.moveItemData = { item: item, isDir: item.type === "dir" }
        moveLoader.sourceComponent = moveComponent
    }

    function cancelMove() { moveLoader.sourceComponent = undefined; root.moveItemData = null }

function confirmMove(destPath) {
        if (!destPath || destPath.trim() === "") { root.errorMessage = "Destination path cannot be empty"; return }
        moveLoader.sourceComponent = undefined
        var token = Auth.getToken()
        if (!token) { root.errorMessage = "Not authenticated"; return }
        var items = root.moveItemData.items
        var isBatch = items && items.length > 1
        var destPathTrimmed = destPath.trim()
        root.loading = true
        root.errorMessage = ""

        if (items && items.length > 1) {
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
            // Single item move (existing logic)
            var item = root.moveItemData.item
            var isDir = root.moveItemData.isDir
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
                var srcPath = root.currentPath === "/" ? "/" + item.name : root.currentPath + "/" + item.name
                SeafileAPI.moveFile(root.currentRepo.id, srcPath, destPathTrimmed, token, function(success, error) {
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
    }

    // ===== DELETE =====

    property var deleteItemData: null

    function pickDelete(item) {
        root.deleteItemData = { item: item, isDir: item.type === "dir" }
        confirmLoader.sourceComponent = confirmComponent
    }

    function cancelDelete() { confirmLoader.sourceComponent = undefined; root.deleteItemData = null }

    function confirmDelete() {
        if (root.deleteItemData.items && root.deleteItemData.items.length > 1) {
            // Batch delete - handled by deleteItems()
            root.deleteItems()
            return
        }
        confirmLoader.sourceComponent = undefined
        var token = Auth.getToken()
        if (!token) { root.errorMessage = "Not authenticated"; return }
        var item = root.deleteItemData.item
        var isDir = root.deleteItemData.isDir
        var fullPath = root.currentPath === "/" ? "/" + item.name : root.currentPath + "/" + item.name
        root.loading = true
        root.errorMessage = ""
        if (isDir) {
            if (fullPath === "/") { root.errorMessage = "Cannot delete root directory"; root.loading = false; root.deleteItemData = null; return }
            SeafileAPI.deleteFolder(root.currentRepo.id, fullPath, token, function(success, error) {
                root.loading = false
                if (success) { Cache.invalidatePath(root.currentRepo.id, root.currentPath); root.refresh(); root.showToast("Deleted") }
                else { root.errorMessage = error || "Failed to delete folder" }
            })
        } else {
            SeafileAPI.deleteFile(root.currentRepo.id, fullPath, token, function(success, error) {
                root.loading = false
                if (success) { Cache.invalidatePath(root.currentRepo.id, root.currentPath); root.refresh(); root.showToast("Deleted") }
                else { root.errorMessage = error || "Failed to delete file" }
            })
        }
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
    moveLoader.sourceComponent = moveComponent
    root.moveItemData = { items: root.selectedItems.slice(), isDir: false }
}

function copyItems() {
    if (!root.currentRepo || root.selectedItems.length === 0) return
    copyLoader.sourceComponent = copyComponent
    root.moveItemData = { items: root.selectedItems.slice(), isDir: false }
}

function deleteItems() {
    if (root.selectedItems.length === 0) return
    var token = Auth.getToken()
    if (!token) { root.errorMessage = "Not authenticated"; return }

    var itemsToDelete = root.selectedItems.slice()
    var msg = "Delete " + root.selectedItems.length + " item(s)?"
    confirmLoader.sourceComponent = confirmComponent
    root.deleteItemData = { items: root.selectedItems.slice(), isDir: false }
    root.confirmDelete = function() {
        confirmLoader.sourceComponent = undefined
        root.loading = true
        root.errorMessage = ""
        var itemsToDelete = root.selectedItems.slice()
        root.clearSelection()
        var token = Auth.getToken()
        if (!token) { root.errorMessage = "Not authenticated"; root.loading = false; return }

        var results = { success: [], failed: [] }
        var index = 0

        function deleteNext() {
            if (index >= itemsToDelete.length) {
                root.loading = false
                var msg = results.success.length + " deleted"
                if (results.failed.length > 0) {
                    msg += ", " + results.failed.length + " failed"
                }
                root.showToast(msg, results.failed.length > 0 ? "error" : "success")
                if (results.failed.length > 0) {
                    root.selectedItems = results.failed
                } else {
                    root.clearSelection()
                }
                Cache.invalidatePath(root.currentRepo.id, root.currentPath)
                root.refresh()
                return
            }

            var item = itemsToDelete[index]
            if (item.type === "dir") {
                SeafileAPI.deleteFolder(root.currentRepo.id, item.fullPath, Auth.getToken(), function(success, error) {
                    if (success) {
                        results.success.push(item)
                    } else {
                        results.failed.push({ item: item, error: error })
                    }
                    index++
                    deleteNext()
                })
            } else {
                SeafileAPI.deleteFile(root.currentRepo.id, item.fullPath, token, function(success, error) {
                    if (success) {
                        results.success.push(item)
                    } else {
                        results.failed.push({ item: item, error: error })
                    }
                    index++
                    deleteNext()
                })
            }
            index = 0
            results = { success: [], failed: [] }
            deleteNext()
        }
    }

    function moveItems() {
        if (!root.currentRepo || root.selectedItems.length === 0) return
        moveLoader.sourceComponent = moveComponent
        root.moveItemData = { items: root.selectedItems.slice(), isDir: false }
    }

    function copyItems() {
        if (!root.currentRepo || root.selectedItems.length === 0) return
        copyLoader.sourceComponent = copyComponent
        root.moveItemData = { items: root.selectedItems.slice(), isDir: false }
    }

    function deleteItems() {
        if (root.selectedItems.length === 0) return
        var token = Auth.getToken()
        if (!token) { root.errorMessage = "Not authenticated"; return }

        var itemsToDelete = root.selectedItems.slice()
        var confirmMsg = "Delete " + root.selectedItems.length + " item(s)?"
        confirmLoader.sourceComponent = confirmComponent
        root.deleteItemData = { items: root.selectedItems.slice(), isDir: false }
        root.confirmDelete = function() {
            confirmLoader.sourceComponent = undefined
            root.loading = true
            root.errorMessage = ""
            var itemsToDelete = root.selectedItems.slice()
            root.clearSelection()
            var token = Auth.getToken()
            if (!token) { root.errorMessage = "Not authenticated"; root.loading = false; return }

            var results = { success: [], failed: [] }
            var index = 0

            function deleteNext() {
                if (index >= itemsToDelete.length) {
                    root.loading = false
                    var msg = results.success.length + " deleted"
                    if (results.failed.length > 0) {
                        msg += ", " + results.failed.length + " failed"
                    }
                    root.showToast(msg, results.failed.length > 0 ? "error" : "success")
                    if (results.failed.length > 0) {
                        root.selectedItems = results.failed
                    } else {
                        root.clearSelection()
                    }
                    Cache.invalidatePath(root.currentRepo.id, root.currentPath)
                    root.refresh()
                    return
                }

                var item = itemsToDelete[index]
                if (item.type === "dir") {
                    SeafileAPI.deleteFolder(root.currentRepo.id, item.fullPath, Auth.getToken(), function(success, error) {
                        if (success) {
                            results.success.push(item)
                        } else {
                            results.failed.push({ item: item, error: error })
                        }
                        index++
                        deleteNext()
                    })
                } else {
                    SeafileAPI.deleteFile(root.currentRepo.id, item.fullPath, token, function(success, error) {
                        if (success) {
                            results.success.push(item)
                        } else {
                            results.failed.push({ item: item, error: error })
                        }
                        index++
                        deleteNext()
                    })
                }
                index = 0
                results = { success: [], failed: [] }
                deleteNext()
            }
        }
    }

    function showHistory(item) {
        if (!root.currentRepo || !item || item.type !== "file") return
        root.historyRepoId = root.currentRepo.id
        root.historyFileName = item.name
        root.historyFilePath = root.currentPath === "/" ? "/" + item.name : root.currentPath + "/" + item.name
        root.historyRepoId = root.currentRepo.id
        root.showHistory = true
    }

    function showTrash() {
        if (!root.currentRepo) return
        root.showTrash = true
    }

    // ===== INIT =====

    property bool depsChecked: false
    property string depErrorMessage: ""

    Component.onCompleted: {
        var missing = Auth.checkDependencies()
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

        if (Auth.isAuthenticated() && !hasRequiredMissing) {
            SeafileAPI.setBaseUrl(root.serverUrl)
            SeafileAPI.setToken(Auth.getToken())
            connectionService.setServerUrl(root.serverUrl)
            root.state = "browse"
            root.loadLibraries()
        }
    }
}
