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
    property bool forceRefresh: false

    property int activeTransferCount: TransferService.getActiveCount()
    property bool hasTransferFailures: TransferService.hasFailures()
    property var fileTransfers: ({})
    property int transferRevision: 0
    property bool showTransfers: false

    function findTransfer(item) {
        if (!item) return null
        var id = item.id
        if (id && root.fileTransfers[id]) return root.fileTransfers[id]
        if (item.name) {
            for (var key in root.fileTransfers) {
                var t = root.fileTransfers[key]
                if (t.fileName === item.name) return t
            }
        }
        return null
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
                        root.pickRename(list.currentItem.item)
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
                    activeTransferCount: root.activeTransferCount
                    hasTransferFailures: root.hasTransferFailures
                    showOffline: !connectionService.online
                    searchActive: root.searchActive
                    searchQuery: root.searchQuery
                    onBackClicked: {
                        if (root.showTransfers) { root.showTransfers = false }
                        else { root.goBack() }
                    }
                    onRefreshClicked: root.refresh()
                    onUploadClicked: root.pickFileForUpload()
                    onSearchChanged: root.onSearchQueryChanged(query)
                    onSearchActiveChanged: root.onSearchActiveToggle(active)
                    onLogoutClicked: root.doLogout()
                    onTransfersClicked: root.toggleTransfersView()
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
                            visible: !root.loading && root.errorMessage === "" && !root.searchActive && !root.showTransfers
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

    // ===== AUTH =====

    function doLogin(url, email, password) {
        root.loading = true
        root.errorMessage = ""
        SeafileAPI.setBaseUrl(url)
        SeafileAPI.auth(email, password, function(success, token, error) {
            root.loading = false
            if (success) {
                SeafileAPI.setToken(token)
                Auth.storeToken(token, url, email)
                root.serverUrl = url
                connectionService.setServerUrl(url)
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
        var item = root.moveItemData.item
        var isDir = root.moveItemData.isDir
        var srcPath = root.currentPath === "/" ? "/" + item.name : root.currentPath + "/" + item.name
        root.loading = true
        root.errorMessage = ""
        if (isDir) {
            SeafileAPI.moveFolder(root.currentRepo.id, item.name, root.currentPath, root.currentRepo.id, destPath.trim(), token, function(success, error) {
                root.loading = false
                if (success) {
                    Cache.invalidatePath(root.currentRepo.id, root.currentPath)
                    Cache.invalidatePath(root.currentRepo.id, destPath.trim())
                    root.refresh()
                    root.showToast("Moved successfully")
                } else { root.errorMessage = error || "Failed to move folder" }
            })
        } else {
            SeafileAPI.moveFile(root.currentRepo.id, srcPath, destPath.trim(), token, function(success, error) {
                root.loading = false
                if (success) {
                    Cache.invalidatePath(root.currentRepo.id, root.currentPath)
                    Cache.invalidatePath(root.currentRepo.id, destPath.trim())
                    root.refresh()
                    root.showToast("Moved successfully")
                } else { root.errorMessage = error || "Failed to move file" }
            })
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

    // ===== INIT =====

    Component.onCompleted: {
        if (Auth.isAuthenticated()) {
            SeafileAPI.setBaseUrl(root.serverUrl)
            SeafileAPI.setToken(Auth.getToken())
            connectionService.setServerUrl(root.serverUrl)
            root.state = "browse"
            root.loadLibraries()
        }
    }
}
