import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "./js"
import "./components"
import "./views"

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

    property string destinationMode: ""
    property string destinationOperation: "move"
    property var destinationSources: []
    property var destinationSourceRepoId: ""
    property string destinationSourcePath: "/"
    property var destinationSourceHistory: []
    property bool destinationSubmitting: false
    property int navigationGeneration: 0
    property int sessionGeneration: 0
    property int connectionTestGeneration: 0
    property int loginGeneration: 0
    property var navigationTiming: ({})
    property int navigationTimingSequence: 0
    function beginNavigationTiming(label, cacheHit) {
        root.navigationTimingSequence++
        root.navigationTiming = { label: label, startedAt: Date.now(), cacheHit: cacheHit === true }
        console.log("SEAFILE_TIMING navigation_start label=" + label + " cache=" + (cacheHit ? "hit" : "miss"))
    }
    function navigationPhase(phase, startedAt) {
        console.log("SEAFILE_TIMING navigation_phase phase=" + phase + " duration_ms=" + Math.max(0, Date.now() - startedAt))
    }
    function navigationComplete(startedAt, rows) {
        root.navigationPhase("first_visible_model", startedAt)
        console.log("SEAFILE_TIMING navigation_complete rows=" + rows + " total_ms=" + Math.max(0, Date.now() - startedAt))
    }

    property int activeTransferCount: 0
    property bool hasTransferFailures: false
    property var fileTransfers: ({})
    property int transferRevision: 0
    property bool showTransfers: false

    // ===== SEARCH STATE =====
    property string searchQuery: ""
    property string searchState: "idle"
    property var searchResults: []
    property string searchErrorMessage: ""
    property int searchGeneration: 0
    property bool searchActive: false
    property int searchPendingCount: 0
    property bool searchTruncated: false

    // ===== HISTORY / TRASH STATE =====
    property bool showHistory: false
    property bool showTrash: false
    property var historyFile: null
    property var historyFileName: ""
    property var historyFilePath: ""
    property var historyRepoId: ""
    property int historyGeneration: 0

    // ===== SELECTION STATE =====
    property var selectedItems: []
    property var selectionAnchor: null

    // ===== UX PREFERENCES =====
    property bool singleClickOpen: setting("singleClickOpen", false)
    // Directories before files when sorting by Name/Size/Modified. Type sorting
    // keeps its own logical semantics regardless of this switch.
    property bool foldersFirst: setting("foldersFirst", true)

    // Single source of truth for the displayed version, kept in step with
    // manifest.json by scripts/test_v11_remediation.py.
    readonly property string pluginVersion: "1.1.0"

    function selectionKeyForItem(item) {
        return SelectionHelper.makeKey(item)
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

    function selectRange(item, visibleItems) {
        var items = visibleItems || root.currentItems
        var anchor = root.selectionAnchor
        if (!anchor) {
            anchor = items.length > 0 ? items[0] : null
        }
        root.selectedItems = SelectionHelper.rangeSelect(root.selectedItems, anchor, item, items)
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

    // Favorites persist per account, so every mutation writes the scoped store
    // (plus the one-time legacy-migration markers) back to settings. The legacy
    // pre-1.1 blob is kept under its own key so it can be imported exactly once.
    function persistFavorites() {
        setting("favoritesStore", Favorites.saveToSettings())
        setting("favoritesLegacyMigrated", Favorites.saveMigratedKeys())
        // GLOBAL migration-complete marker: once set, no other account ever
        // imports the pre-1.1 legacy blob on a later startup.
        setting("favoritesLegacyMigratedGlobally", Favorites.saveGloballyMigrated())
    }

    // Quick Access targets in v1.1 are libraries (from the Libraries root) and
    // folders (inside a library). Files are deliberately not favoriteable.
    function canAddToFavorites(item) {
        if (!item) return false
        if (!root.currentRepo) return true
        return item.type === "dir"
    }

    function addToFavorites(item) {
        if (!item) return
        if (!root.currentRepo) {
            var libResult = Favorites.addLibrary(item.id, item.name)
            if (libResult.error) root.showToast(libResult.error, "error")
            else if (libResult.changed) { root.persistFavorites(); root.showToast("Added to Quick Access") }
            return
        }
        if (item.type !== "dir") {
            root.showToast("Only libraries and folders can be added to Quick Access", "warning")
            return
        }
        // Identity is the folder's own FULL path, not its parent, so sibling
        // folders with the same name under different parents stay distinct.
        var fullPath = root.currentPath === "/" ? "/" + item.name : root.currentPath + "/" + item.name
        var folderResult = Favorites.addFolder(root.currentRepo.id, root.currentRepo.name, fullPath, item.name)
        if (folderResult.error) root.showToast(folderResult.error, "error")
        else if (folderResult.changed) { root.persistFavorites(); root.showToast("Added to Quick Access") }
    }

    // Accepts either a favorite record (Home's Quick Access rows) or a browsed
    // item (context menu). A favorite record carries its own identity, so
    // removal works while currentRepo is null - identity is never derived from
    // the browsing context.
    function removeFromFavorites(entry) {
        if (!entry) return
        var result
        if (entry.type === "library" || entry.type === "folder") {
            result = Favorites.removeEntry(entry)
        } else if (root.currentRepo) {
            if (entry.type === "dir") {
                var dirFullPath = root.currentPath === "/" ? "/" + entry.name : root.currentPath + "/" + entry.name
                result = Favorites.removeFolder(root.currentRepo.id, dirFullPath)
            } else {
                result = Favorites.removeLibrary(root.currentRepo.id)
            }
        } else {
            return
        }
        if (result.error) { root.showToast(result.error, "error"); return }
        if (result.changed) { root.persistFavorites(); root.showToast("Removed from Quick Access") }
    }

    // Resolve a favorite to a concrete destination. A stale library or folder
    // produces feedback without crashing, and the entry stays removable.
    function openFavorite(entry) {
        if (!entry) return
        var repo = null
        for (var i = 0; i < root.libraries.length; i++) {
            if (root.libraries[i].id === entry.repoId) { repo = root.libraries[i]; break }
        }
        if (!repo) {
            root.showToast("Library is no longer available. You can remove this entry from Quick Access.", "error")
            return
        }
        root.clearSelection()
        root.currentRepo = repo
        if (entry.type === "library") {
            root.pathHistory = [{ name: repo.name, path: "/", repoId: repo.id }]
            root.loadFolder(repo.id, "/")
            return
        }
        var fullPath = Favorites.normalizePath(entry.path)
        if (fullPath === "") {
            root.showToast("This Quick Access entry has no folder path", "error")
            return
        }
        root.buildPathHistory(repo, fullPath)
        root.loadFolder(repo.id, fullPath)
    }

    // Build a breadcrumb chain for an absolute folder path.
    function buildPathHistory(repo, fullPath) {
        var history = [{ name: repo.name, path: "/", repoId: repo.id }]
        var normalized = Favorites.normalizePath(fullPath)
        if (normalized !== "") {
            var segments = normalized.split("/").filter(function(seg) { return seg !== "" })
            var acc = ""
            for (var i = 0; i < segments.length; i++) {
                acc += "/" + segments[i]
                history.push({ name: segments[i], path: acc, repoId: repo.id })
            }
        }
        root.pathHistory = history
    }

    function handleBackClick() {
        if (root.destinationSubmitting) return
        if (root.showTransfers) { root.showTransfers = false }
        else if (root.showHistory) { root.historyGeneration++; root.showHistory = false; historyLoader.sourceComponent = undefined }
        else if (root.showTrash) { root.showTrash = false; trashLoader.sourceComponent = undefined }
        else if (settingsLoader.sourceComponent) { root.closeSettings() }
        else { root.goBack() }
    }

    // Closes the topmost open modal, if any. Returns true when a dialog was
    // dismissed so Escape can close dialogs before it closes the panel.
    function closeTopDialog() {
        if (root.destinationMode) { root.cancelDestinationMode(); return true }
        if (shareLoader.item) { root.cancelShare(); return true }
        if (uploadLoader.item) { root.cancelFilePicker(); return true }
        if (confirmLoader.item) { root.cancelDelete(); return true }
        if (renameLoader.item) { root.cancelRename(); return true }
        if (createFolderLoader.item) { root.cancelCreateFolder(); return true }
        if (historyLoader.item) { root.historyGeneration++; root.showHistory = false; historyLoader.sourceComponent = undefined; return true }
        if (trashLoader.item) { root.showTrash = false; trashLoader.sourceComponent = undefined; return true }
        if (settingsLoader.item) { root.closeSettings(); return true }
        // Transfers surface: Escape returns to the underlying view (Libraries
        // root or the browser), never closes the whole panel.
        if (root.showTransfers) { root.showTransfers = false; return true }
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
            var key = SelectionHelper.makeKey(item)
            validKeys[key] = true
        }
        root.selectedItems = root.selectedItems.filter(function(item) {
            var key = SelectionHelper.makeKey(item)
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
        function onTransferError(message) {
            root.showToast(message, "error")
        }
    }

    Timer {
        id: searchDebounceTimer
        interval: 300
        repeat: false
        onTriggered: root.executeSearch()
    }

    function open() {
        // Refresh connectivity state immediately so a stale "Offline" banner
        // clears as soon as the panel is shown (server reachable).
        connectionService.forceCheck()
        // Load libraries if empty (e.g., panel was recreated after being closed).
        if (!root.libraries || root.libraries.length === 0) {
            root.loadLibraries()
        }
        panelController.show()
    }
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

    // Own the IPC target (manageIpc:false above) — same pattern as the
    // shell's dropbox/network panels: base-Panel handlers plus extras.
    IpcHandler {
        target: root.ipcTarget
        function open(): void { root.open() }
        function close(): void { root.close() }
        function show(): void { root.open() }
        function hide(): void { root.close() }
        function toggle(): void { root.toggle() }
        function status(): string { return root.state }
    }

    // Rename target: the single selected item, else the list's current item.
    function renameTarget() {
        if (!root.currentRepo) return null
        if (root.selectedItems.length === 1) return root.selectedItems[0]
        var list = root.activeFileList()
        if (!list) return null
        if (list.currentItem) return list.currentItem.item
        if (list.count > 0) {
            list.currentIndex = 0
            return list.itemAtIndex(0)
        }
        return null
    }

    function showItemContextMenu(item, x, y) {
        if (!item || root.destinationMode) return
        if (!root.currentRepo) root.clearSelection()
        else if (!root.isItemSelected(item)) root.selectOnly(item)
        contextMenu.item = item
        contextMenu.isDir = item.type === "dir"
        contextMenu.libraryMode = root.currentRepo === null
        contextMenu.selectionCount = root.selectedItems.length > 0 ? root.selectedItems.length : 1
        if (root.currentRepo) {
            // Type is part of favorite identity, and a folder is keyed by its
            // own full path rather than by its parent directory.
            if (item.type === "dir") {
                var dirFullPath = root.currentPath === "/" ? "/" + item.name : root.currentPath + "/" + item.name
                contextMenu.isFavorite = Favorites.isFolderFavorite(root.currentRepo.id, dirFullPath)
            } else {
                // Files are not Quick Access targets in v1.1.
                contextMenu.isFavorite = false
            }
        } else {
            contextMenu.isFavorite = Favorites.isLibraryFavorite(item.id)
        }
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

    function updateConnectionServiceUrl() {
        connectionService.setServerUrl(root.serverUrl)
    }

    KeyboardPanel {
        id: panel
        anchorItem: root.anchorItem
        owner: root.hostWidget || root
        bar: root.bar
        open: panelController.open
        focusTarget: keyCatcher
        contentWidth: panel.fittedContentWidth(Style.space(480))
        contentHeight: panel.fittedContentHeight(content.implicitHeight)

        PanelKeyCatcher {
            id: keyCatcher
            anchors.fill: parent
            blocked: root.textInputActive
            onCloseRequested: {
                if (root.closeTopDialog()) return
                root.close()
            }
            // dialogOpen guard: while any modal/view is up (even ones without
            // a text field, e.g. the delete confirmation), panel-level
            // navigation and item actions must stay inert — only Escape
            // (via closeTopDialog above) acts on them.
            onMoveRequested: function(dx, dy) {
                if (root.state !== "browse" || root.searchActive || root.dialogOpen || root.showTransfers || root.destinationSubmitting) return
                var list = root.activeFileList()
                if (!list) return
                if (dx < 0) { root.goBack(); return }
                if (dx > 0) {
                    if (list.currentItem && list.currentItem.item.type === "dir") root.onItemClicked(list.currentItem.item)
                    return
                }
                if (dy > 0) list.incrementCurrentIndex()
                else if (dy < 0) list.decrementCurrentIndex()
            }
            onActivateRequested: {
                if (root.state !== "browse" || root.searchActive || root.dialogOpen || root.showTransfers || root.destinationSubmitting) return
                var list = root.activeFileList()
                if (!list || !list.currentItem) return
                var item = list.currentItem.item
                if (item && item.type === "dir") root.onItemClicked(item)
                else if (item && !root.destinationMode) root.openFile(item)
            }
            onDeleteRequested: {
                if (root.state !== "browse" || root.searchActive || root.dialogOpen || root.destinationMode || root.showTransfers) return
                if (root.selectedItems.length > 0) { root.deleteItems(); return }
                var list = root.activeFileList()
                if (!list || !list.currentItem) return
                root.pickDelete(list.currentItem.item)
            }

            Shortcut {
                sequence: "F2"
                enabled: root.state === "browse" && !root.searchActive && !root.dialogOpen && !root.destinationMode && !root.showTransfers && root.currentRepo !== null
                onActivated: {
                    var target = root.renameTarget()
                    if (target) root.pickRename(target)
                }
            }

            Shortcut {
                sequence: "Ctrl+A"
                enabled: root.state === "browse" && !root.searchActive && !root.dialogOpen && !root.destinationMode && !root.showTransfers && root.currentRepo !== null
                onActivated: root.selectAll()
            }

            Shortcut {
                sequence: "Delete"
                enabled: root.state === "browse" && !root.searchActive && !root.dialogOpen && !root.destinationMode && !root.showTransfers && root.currentRepo !== null
                onActivated: {
                    if (root.selectedItems.length > 0) { root.deleteItems(); return }
                    var list = root.activeFileList()
                    if (!list || !list.currentItem) return
                    root.pickDelete(list.currentItem.item)
                }
            }

            // Single context menu at panel level, parented to the window
            // overlay so the file list never clips it.
            ContextMenu {
                id: contextMenu
                bar: root.bar
                onOpenClicked: function(item) { if (item) item.type === "dir" ? root.onItemClicked(item) : root.openFile(item) }
                onDownloadClicked: function(item) { root.downloadFile(item) }
                onRenameClicked: function(item) { root.pickRename(item) }
                onMoveClicked: function(item) { root.moveItems(item) }
                onCopyClicked: function(item) { root.copyItems(item) }
                onShareClicked: function(item) { root.pickShare(item) }
                onHistoryClicked: function(item) { root.openHistory(item) }
                onDeleteClicked: function(item) {
                    if (root.selectedItems.length > 1) root.deleteItems()
                    else if (item) root.pickDelete(item)
                }
                onAddToFavoritesClicked: function(item) { root.addToFavorites(item) }
                onRemoveFromFavoritesClicked: function(item) { root.removeFromFavorites(item) }
            }

            Column {
                id: content
                width: parent.width
                spacing: 0

                Toast {
                    id: toast
                    width: parent.width
                    bar: root.bar
                }

                ToolBar {
                    id: toolBar
                    width: parent.width
                    bar: root.bar
                    overlay: keyCatcher.Overlay.overlay
                    visible: root.state !== "login"
                    title: root.settingsOpen ? "Settings" : (root.showTransfers ? "Transfers" : (root.searchActive ? "Search" : (root.currentRepo ? root.currentRepo.name : "Libraries")))
                    showBack: root.state === "browse" && !root.searchActive && (!root.dialogOpen || root.settingsOpen) && (root.pathHistory.length > 0 || root.settingsOpen || root.showTransfers)
                    // While the Transfers surface is active the underlying
                    // browser view is hidden, so only intentional global actions
                    // (Back, Logout, Settings, the Transfers indicator) stay on.
                    showRefresh: root.state === "browse" && !root.searchActive && !root.dialogOpen && !root.destinationMode && !root.showTransfers
                    showUpload: root.state === "browse" && !root.searchActive && !root.dialogOpen && !root.destinationMode && !root.showTransfers
                    showCreateFolder: root.state === "browse" && !root.searchActive && !root.dialogOpen && !root.destinationMode && !root.showTransfers && root.currentRepo !== null
                    showSearch: root.state === "browse" && !root.dialogOpen && !root.destinationMode && !root.showTransfers
                    showLogout: root.state === "browse" && !root.dialogOpen && !root.destinationMode
                    showTransfers: root.state === "browse" && !root.dialogOpen && !root.destinationMode
                    showTrash: root.state === "browse" && !root.dialogOpen && !root.destinationMode && !root.showTransfers
                    showSettings: root.state === "browse" && !root.dialogOpen && !root.destinationMode
                    activeTransferCount: root.activeTransferCount
                    hasTransferFailures: root.hasTransferFailures
                    showOffline: !connectionService.online
                    searchActive: root.searchActive
                    searchQuery: root.searchQuery
                    selectionCount: root.selectedItems.length
                    hasTrashItems: root.hasTrashItems
                    destinationMode: root.destinationMode
                    destinationOperation: root.destinationOperation
                    destinationCount: root.destinationSources.length
                    destinationPath: root.destinationMode !== "" && root.currentRepo ? root.currentRepo.name + (root.currentPath !== "/" ? " / " + root.currentPath.substring(1) : "") : ""
                    onBackClicked: root.handleBackClick
                    onRefreshClicked: root.refresh
                    onUploadClicked: root.pickFileForUpload
                    onCreateFolderClicked: root.pickCreateFolder
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
                    onDestinationCancel: root.cancelDestinationMode
                    onDestinationConfirm: root.confirmDestination
                }

                Loader {
                    id: stateLoader
                    sourceComponent: root.state === "login" ? loginComponent : (root.currentRepo ? browserComponent : homeComponent)
                    width: parent.width
                    visible: !root.dialogOpen && !root.showTransfers
                    height: visible ? implicitHeight : 0
                }
                Loader {
                    id: destinationBarLoader
                    sourceComponent: root.destinationMode ? destinationBarComponent : undefined
                    width: parent.width
                    height: item ? item.implicitHeight : 0
                }
                Loader { id: createFolderLoader; sourceComponent: undefined; width: parent.width; height: item ? item.implicitHeight : 0 }
                Loader { id: renameLoader; sourceComponent: undefined; width: parent.width; height: item ? item.implicitHeight : 0 }
                Loader { id: confirmLoader; sourceComponent: undefined; width: parent.width; height: item ? item.implicitHeight : 0 }
                Loader { id: shareLoader; sourceComponent: undefined; width: parent.width; height: item ? item.implicitHeight : 0 }
                Loader { id: uploadLoader; sourceComponent: undefined; width: parent.width; height: item ? item.implicitHeight : 0 }
                Loader { id: historyLoader; sourceComponent: undefined; width: parent.width; height: item ? item.implicitHeight : 0 }
                Loader { id: trashLoader; sourceComponent: undefined; width: parent.width; height: item ? item.implicitHeight : 0 }
                Loader { id: settingsLoader; sourceComponent: undefined; width: parent.width; height: item ? item.implicitHeight : 0 }

                // Panel-level Transfers surface. It lives here rather than
                // inside BrowserView so it works from the Libraries root, where
                // currentRepo is null and BrowserView is not even instantiated.
                // This is the only TransferManager in the app, so there is a
                // single source of transfer state.
                Loader {
                    id: transfersLoader
                    sourceComponent: root.state === "browse" && root.showTransfers ? transfersComponent : undefined
                    width: parent.width
                    visible: root.state === "browse" && root.showTransfers && !root.dialogOpen && !root.searchActive
                    height: visible && item ? item.implicitHeight : 0
                }

                Component {
                    id: loginComponent
                    LoginDialog {
                        id: loginDialog
                        bar: root.bar
                        serverField.text: root.serverUrl
                        depErrorMessage: root.depErrorMessage
                        onLogin: function(url, email, pass) { root.doLogin(url, email, pass) }
                        onDismiss: function() { root.close() }
                    }
                }

                Component {
                    id: destinationBarComponent
                    Item {
                        id: destBar
                        width: parent.width
                        height: childrenRect.height
                        property alias cancelButton: cancelBtn
                        property alias actionButton: actionBtn
                        Column {
                            width: parent.width
                            spacing: 0
                            Item {
                                width: parent.width
                                height: Style.space(8)
                            }
                            Text {
                                width: parent.width
                                text: (root.destinationOperation === "move" ? "Moving " : "Copying ") + root.destinationSources.length + (root.destinationSources.length === 1 ? " item to:" : " items to:")
                                color: root.bar.foreground
                                font.family: root.bar.fontFamily
                                font.pixelSize: Style.font.caption
                                horizontalAlignment: Text.AlignHCenter
                                textFormat: Text.PlainText
                            }
                            Text {
                                width: parent.width
                                text: Models.boundedDisplayText(root.currentRepo ? root.currentRepo.name + (root.currentPath === "/" ? " /" : " / " + root.currentPath.substring(1)) : "", 4096)
                                color: Qt.darker(root.bar.foreground, 1.3)
                                font.family: root.bar.fontFamily
                                font.pixelSize: Style.font.caption
                                font.bold: true
                                elide: Text.ElideMiddle
                                horizontalAlignment: Text.AlignHCenter
                                textFormat: Text.PlainText
                            }
                            Row {
                                width: parent.width
                                height: implicitHeight
                                spacing: Style.space(8)
                        Button {
                                    id: cancelBtn
                            text: "Cancel"
                                    width: parent.width / 2 - Style.space(4)
                                    height: Style.space(32)
                                    enabled: !root.destinationSubmitting
                                    onClicked: root.cancelDestinationMode()
                                }
                        Button {
                                    id: actionBtn
                            text: root.destinationOperation === "move" ? "Move here" : "Copy here"
                                    width: parent.width / 2 - Style.space(4)
                                    height: Style.space(32)
                            enabled: !root.destinationSubmitting && !root.loading
                            onClicked: root.confirmDestination()
                                }
                            }
                        }
                    }
                }

                Component {
                    id: homeComponent
                    HomeView {
                        id: homeView
                        width: parent.width
                        bar: root.bar
                        libraries: root.libraries
                        currentRepo: root.currentRepo
                        currentPath: root.currentPath
                        pathHistory: root.pathHistory
                        loading: root.loading
                        errorMessage: root.errorMessage
                        selectedItems: root.selectedItems
                        selectionAnchor: root.selectionAnchor
                        destinationMode: root.destinationMode
                        onItemClicked: function(item) { root.onItemClicked(item) }
                        onNavigateToPath: function(index) { root.navigateToPath(index) }
                        onRefresh: function() { root.refresh() }
                        onToggleSelection: root.destinationMode || !root.currentRepo ? function() {} : root.toggleSelection
                        onSelectRange: root.destinationMode || !root.currentRepo ? function() {} : root.selectRange
                        onSelectOnly: root.destinationMode ? function() {} : root.selectOnly
                        onPositionClicked: root.positionOn
                        onContextMenuRequested: root.showItemContextMenu
                        onDownloadClicked: function(item) { root.destinationMode ? null : root.downloadFile(item) }
                        onOpenClicked: function(item) { root.destinationMode ? null : root.openFile(item) }
                        onRenameClicked: function(item) { root.destinationMode ? null : root.pickRename(item) }
                        onMoveClicked: function(item) { root.destinationMode ? null : root.beginDestinationMode("move", [item]) }
                        onDeleteClicked: function(item) { root.destinationMode ? null : root.pickDelete(item) }
                        onShareClicked: function(item) { root.destinationMode ? null : root.pickShare(item) }
                        onHistoryClicked: root.openHistory
                        onAddToFavorites: function(item) { root.addToFavorites(item) }
                        onRemoveFromFavorites: function(item) { root.removeFromFavorites(item) }
                        onFavoriteClicked: function(entry) { root.openFavorite(entry) }
                        onRemoveFavorite: function(entry) { root.removeFromFavorites(entry) }
                        onTransferCancel: function(transfer) { TransferService.cancelTransfer(transfer.id) }
                        activeTransfers: TransferService.getActiveTransfers()
                        activeCount: root.activeTransferCount
                    }
                }

                Component {
                    id: browserComponent
                    BrowserView {
                        id: browserView
                        width: parent.width
                        bar: root.bar
                        currentItems: root.currentItems
                        pathHistory: root.pathHistory
                        libraries: root.libraries
                        loading: root.loading
                        errorMessage: root.errorMessage
                        searchActive: root.searchActive
                        searchState: root.searchState
                        searchResults: root.searchResults
                        searchErrorMessage: root.searchErrorMessage
                        searchTruncated: root.searchTruncated
                        maxSearchResults: root.maxSearchResults
                        showTransfers: root.showTransfers
                        transferRevision: root.transferRevision
                        selectedItems: root.selectedItems
                        selectionAnchor: root.selectionAnchor
                        currentRepo: root.currentRepo
                        currentPath: root.currentPath
                        destinationMode: root.destinationMode
                        connectionService: connectionService
                        searchPendingCount: root.searchPendingCount
                        onItemClicked: function(item) { root.onItemClicked(item) }
                        onDownloadClicked: function(item) { root.destinationMode ? null : root.downloadFile(item) }
                        onOpenClicked: function(item) { root.destinationMode ? null : root.openFile(item) }
                        onRenameClicked: function(item) { root.destinationMode ? null : root.pickRename(item) }
                        onMoveClicked: function(item) { root.destinationMode ? null : root.beginDestinationMode("move", [item]) }
                        onDeleteClicked: function(item) { root.destinationMode ? null : root.pickDelete(item) }
                        onShareClicked: function(item) { root.destinationMode ? null : root.pickShare(item) }
                        onHistoryClicked: root.openHistory
                        onSearchResultClicked: function(result) { root.onSearchResultClicked(result) }
                        onNavigateToPath: function(index) { root.navigateToPath(index) }
                        onRefresh: function() { root.refresh() }
                        onToggleSelection: root.destinationMode || !root.currentRepo ? function() {} : root.toggleSelection
                        onSelectRange: root.destinationMode || !root.currentRepo ? function() {} : root.selectRange
                        onSelectOnly: root.destinationMode ? function() {} : root.selectOnly
                        onPositionClicked: root.positionOn
                        onContextMenuRequested: root.showItemContextMenu
                        onSearchRetry: function() { root.executeSearch() }
                        singleClickOpen: root.singleClickOpen
                        foldersFirst: root.foldersFirst
                    }
                }
            }
        }

    }

    // The navigable FileList is owned by whichever view the state Loader is
    // currently showing. It is DERIVED on demand from stateLoader.item rather
    // than cached: caching a Loader child would keep a pointer to an object
    // destroyed as soon as the view changes. Returns null when the login view
    // is active, when the loaded view exposes no list, or when the Loader has
    // no item - so every caller must null-check.
    function activeFileList() {
        var view = stateLoader.item
        if (!view) return null
        var list = view.activeFileList
        return (list === undefined || list === null) ? null : list
    }

    readonly property bool settingsOpen: settingsLoader.item !== null
    readonly property bool dialogOpen: settingsLoader.item !== null || createFolderLoader.item !== null || renameLoader.item !== null || confirmLoader.item !== null || shareLoader.item !== null || uploadLoader.item !== null || historyLoader.item !== null || trashLoader.item !== null

    // True while keyboard input belongs to a text-editing surface: the search
    // bar, the login form, settings, or the editable field of any open dialog.
    // Drives PanelKeyCatcher.blocked so h/j/k/l/x, arrows, Enter, Space,
    // Delete and Escape reach the focused control instead of being interpreted
    // as panel-level navigation/actions while the user is typing. Each editor
    // surface exposes its own declarative `editing` flag (any of its fields
    // focused); this binding is the single central condition — the same
    // mode-derived pattern the shell's network panel uses for its passphrase
    // editor. Loaders recreate items on open, so `editing` resets per dialog.
    function _loaderEditing(loader) {
        return loader.item !== null && loader.item.editing === true
    }

    readonly property bool textInputActive:
        root.searchActive
        || (root.state === "login" && _loaderEditing(stateLoader))
        || _loaderEditing(createFolderLoader)
        || _loaderEditing(renameLoader)
        || _loaderEditing(uploadLoader)
        || _loaderEditing(shareLoader)
        || _loaderEditing(settingsLoader)

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
        id: confirmComponent
        ConfirmDialog {
            bar: root.bar
            // Canonical item-context shape: { items: [...], isDir }. The legacy
            // { item } field is honored only as a safety fallback.
            message: Models.boundedDisplayText((function() {
                var d = root.deleteItemData
                if (!d) return "Are you sure?"
                var list = d.items && d.items.length > 0 ? d.items : (d.item ? [d.item] : [])
                if (list.length === 0) return "Delete selection?"
                if (list.length > 1) return "Delete " + list.length + " item(s)?"
                var it = list[0]
                return "Delete " + (it.type === "dir" ? "folder" : "file") + " \"" + (it.name || "") + "\"?"
            })(), 4096)
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
            onFilesSelected: function(paths) {
                if (!paths || paths.length === 0) return
                // The picker emits raw filesystem paths. They must be passed
                // through verbatim: turning them into file:// URLs and then
                // decodeURIComponent()ing them corrupts real filenames such as
                // "100% termine.txt" or a literal "foo%20bar.txt".
                for (var i = 0; i < paths.length; i++) {
                    var path = paths[i]
                    if (typeof path !== "string" || path === "") continue
                    root.startUpload(path)
                }
                root.cancelFilePicker()
            }
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
                var repoId = root.historyRepoId
                var filePath = root.historyFilePath
                var fileName = root.historyFileName
                var serverUrl = root.serverUrl
                var token = Auth.getToken()
                var session = root.sessionGeneration
                var generation = root.historyGeneration
                SeafileAPI.downloadRevision(repoId, filePath, revision.commitId, function(success, data, error) {
                    if (session !== root.sessionGeneration || generation !== root.historyGeneration) return
                    if (success && typeof data === "string" && data !== "") {
                        SafePath.getDownloadsDir(function(dir) {
                            if (session !== root.sessionGeneration || generation !== root.historyGeneration || !dir) return
                            TransferService.startDownload(
                                { name: fileName + " (rev " + revision.commitId.substring(0, 8) + ")", type: "file" },
                                token, serverUrl, repoId, dir, filePath, data
                            )
                        })
                        root.showHistory = false
                        historyLoader.sourceComponent = undefined
                        root.showToast("Downloading historical revision...")
                    } else {
                        root.showToast("Failed to download revision: " + error, "error")
                    }
                })
            }
            onClose: function() { root.historyGeneration++; root.showHistory = false; historyLoader.sourceComponent = undefined }
            onError: function(message) { root.showToast(message, "error") }
        }
    }

    Component {
        id: trashComponent
        TrashPanel {
            bar: root.bar
            repoId: root.currentRepo ? root.currentRepo.id : ""
            onClose: function() { root.showTrash = false; trashLoader.sourceComponent = undefined }
            onError: function(message) { root.showToast(message, "error") }
        }
    }

    Component {
        id: transfersComponent
        TransferManager {
            bar: root.bar
            transferRevision: root.transferRevision
            onCancel: function(transfer) { TransferService.cancelTransfer(transfer.id) }
            onRetry: function(transfer) {
                TransferService.retryTransfer(transfer.id, Auth.getToken(), Auth.getServerUrl())
            }
            onRetryAllFailed: function() {
                var token = Auth.getToken()
                var baseUrl = Auth.getServerUrl()
                var failed = TransferService.getFailedTransfers()
                for (var i = 0; i < failed.length; i++) {
                    TransferService.retryTransfer(failed[i].id, token, baseUrl)
                }
            }
            onClearCompleted: function() { TransferService.clearCompleted() }
            onClearFailed: function() { TransferService.clearFailed() }
            onClearAllCompleted: function() { TransferService.clearCompleted() }
            onClearAllFailed: function() { TransferService.clearFailed() }
            onClearTransfer: function(transfer) { TransferService.clearTransfer(transfer.id) }
            onOpen: function(transfer) {
                var url = Models.toFileUrl(transfer.destPath)
                if (!Qt.openUrlExternally(url)) root.showToast("Could not open file", "error")
            }
            onShowInFolder: function(transfer) {
                var url = Models.toParentFileUrl(transfer.destPath)
                if (!Qt.openUrlExternally(url)) root.showToast("Could not open folder", "error")
            }
        }
    }

    Component {
        id: settingsComponent
        SettingsDialog {
            bar: root.bar
            serverUrl: root.serverUrl
            pluginVersion: root.pluginVersion
            autoLogin: setting("autoLogin", true)
            singleClickOpen: setting("singleClickOpen", false)
            sortColumn: setting("sortColumn", "name")
            sortAscending: setting("sortAscending", true)
            foldersFirst: root.foldersFirst
            notifyEnabled: setting("notifyEnabled", true)
            onClose: function() { root.closeSettings() }
            onLogout: function() { root.doLogout() }
            onClearCache: function() { root.clearCache() }
            onChangeServer: root.changeServerUrl
            onTestConnection: root.testConnection
            onAutoLoginToggled: function(enabled) { setting("autoLogin", enabled) }
            onSingleClickOpenToggled: function(enabled) { setting("singleClickOpen", enabled) }
            onSortColumnChange: function(col) { setting("sortColumn", col) }
            onSortAscendingChange: function(asc) { setting("sortAscending", asc) }
            onFoldersFirstToggled: function(enabled) {
                setting("foldersFirst", enabled)
                root.foldersFirst = enabled
            }
            onNotifyToggled: function(enabled) { setting("notifyEnabled", enabled) }
        }
    }

    // ===== AUTH =====

    function doLogin(url, email, password) {
        if (root.loading) return
        var loginAttempt = ++root.loginGeneration
        var normalized = normalizeUrl(url)
        if (!normalized) {
            root.loading = false
            root.errorMessage = "Invalid URL format. Use https://domain.com"
            return
        }
        var policy = UrlPolicy.validateForAuth(normalized)
        if (!policy.valid) {
            root.loading = false
            root.errorMessage = policy.error
            return
        }
        if (policy.warning) {
            root.showToast(policy.warning, "warning")
        }
        root.loading = true
        root.errorMessage = ""
        Cache.setScope(normalized, email)
        SeafileAPI.setBaseUrl(normalized)
        SeafileAPI.auth(email, password, function(success, token, error) {
            if (loginAttempt !== root.loginGeneration) return
            if (success) {
                SeafileAPI.setToken(token)
                Auth.storeToken(token, normalized, email).then(function() {
                    if (loginAttempt !== root.loginGeneration) return
                    root.loading = false
                    root.serverUrl = normalized
                    Cache.setScope(normalized, email)
                    connectionService.setServerUrl(normalized)
                    connectionService.forceCheck()
                    // Activate this account's Quick Access scope and persist the
                    // migration marker in case a legacy blob was absorbed.
                    Favorites.setAccountKey(normalized, email)
                    root.persistFavorites()
                    root.state = "browse"
                    root.loadLibraries()
                }).catch(function(err) {
                    if (loginAttempt !== root.loginGeneration) return
                    root.loading = false
                    SeafileAPI.setToken("")
                    Auth.clearSession().catch(function() {})
                    root.errorMessage = "Failed to store credentials: " + err
                })
            } else {
                root.loading = false
                root.errorMessage = error || "Authentication failed"
            }
        })
    }

    // ===== BROWSING =====

    function loadLibraries() {
        var generation = ++root.navigationGeneration
        var startedAt = Date.now()
        var cached = Cache.getLibraries()
        root.beginNavigationTiming("libraries", !!cached)
        if (cached && !root.forceRefresh) {
            root.libraries = cached
            root.currentItems = cached
            root.navigationPhase("model", startedAt)
            root.loading = false
            root.errorMessage = ""
            root.navigationComplete(startedAt, cached.length)
            return
        }
        root.loading = true
        root.errorMessage = ""
        root.currentRepo = null
        root.currentPath = "/"
        root.pathHistory = []
        SeafileAPI.listLibraries(function(success, data, error) {
            if (generation !== root.navigationGeneration) return
            root.loading = false
            if (success) {
                root.libraries = data
                root.navigationPhase("model", startedAt)
                root.currentItems = data
                Cache.setLibraries(data)
                root.navigationComplete(startedAt, data.length)
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
                srcParentDir: path,
                fullPath: prefix + it.name
            })
        }
        return out
    }

    function loadFolder(repoId, path) {
        var generation = ++root.navigationGeneration
        var startedAt = Date.now()
        root.currentPath = path
        root.errorMessage = ""
        var cached = Cache.getFolder(repoId, path)
        root.beginNavigationTiming("folder", !!cached)
        if (cached && !root.forceRefresh) {
            root.currentItems = root.enrichItems(repoId, path, cached)
            root.navigationPhase("model", startedAt)
            root.currentPath = path
            root.loading = false
            root.navigationComplete(startedAt, cached.length)
            return
        }
        root.loading = true
        root.errorMessage = ""
        SeafileAPI.listFolder(repoId, path, function(success, data, error) {
            if (generation !== root.navigationGeneration) return
            root.loading = false
            if (success) {
                Cache.setFolder(repoId, path, data)
                root.currentItems = root.enrichItems(repoId, path, data)
                root.navigationPhase("model", startedAt)
                root.currentPath = path
                root.navigationComplete(startedAt, data.length)
            } else {
                root.errorMessage = error || "Failed to load folder"
            }
        })
    }

    function onItemClicked(item) {
        if (root.destinationSubmitting || root.loading) return
        if (root.destinationMode) {
            if (item.type === "dir") {
                root.clearSelection()
                if (root.currentRepo && root.currentRepo.id === root.destinationSourceRepoId) {
                    var newPath = root.currentPath === "/" ? "/" + item.name : root.currentPath + "/" + item.name
                    root.pathHistory.push({ name: item.name, path: newPath, repoId: root.currentRepo.id })
                    root.loadFolder(root.currentRepo.id, newPath)
                }
            }
            return
        }
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

    function goBack() {
        if (root.destinationSubmitting) return
        root.clearSelection()
        if (root.destinationMode) {
            if (root.pathHistory.length <= 1) {
                return
            }
            root.pathHistory.pop()
            var previous = root.pathHistory[root.pathHistory.length - 1]
            if (root.pathHistory.length === 1) {
                root.loadFolder(root.currentRepo.id, "/")
            } else {
                root.loadFolder(root.currentRepo.id, previous.path)
            }
            return
        }
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
        if (root.destinationSubmitting) return
        if (root.destinationMode) {
            if (index >= root.pathHistory.length - 1) return
            root.pathHistory = root.pathHistory.slice(0, index + 1)
            var target = root.pathHistory[index]
            if (index === 0) {
                root.loadFolder(root.currentRepo.id, "/")
            } else {
                root.loadFolder(root.currentRepo.id, target.path)
            }
            return
        }
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
            root.searchGeneration++
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
            root.searchGeneration++
            searchDebounceTimer.stop()
            root.searchQuery = ""
            root.searchResults = []
            root.searchState = "idle"
        } else {
            root.clearSelection()
        }
    }

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
        var failedCount = 0
        var firstError = ""

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
                } else {
                    failedCount++
                    if (!firstError) firstError = error || "Search request failed"
                }

                if (root.searchPendingCount === 0 || totalResultsCount >= root.maxSearchResults) {
                    if (totalResultsCount >= root.maxSearchResults && (root.searchPendingCount > 0 || queue.length > 0)) root.searchTruncated = true
                    if (failedCount > 0) {
                        root.searchErrorMessage = failedCount + " librar" + (failedCount === 1 ? "y" : "ies") + " failed: " + firstError
                        root.searchState = "error"
                    } else if (root.searchResults.length === 0) {
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
            root.buildPathHistory(repo, result.path)
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
            root.buildPathHistory(repoFile, parentPath)
            root.loadFolder(repoFile.id, parentPath)
        }
    }

    // ===== TRANSFERS =====

    function pickFileForUpload() { uploadLoader.sourceComponent = uploadComponent }
    function cancelFilePicker() { uploadLoader.sourceComponent = undefined }
    // The manual path field accepts either a plain filesystem path or a
    // file:// URL the user pasted. Only the pasted-URL form is decoded.
    function normalizeUserPath(rawPath) {
        if (typeof rawPath !== "string") return ""
        var trimmed = rawPath.trim()
        if (trimmed.indexOf("file://") === 0) {
            try {
                return decodeURIComponent(trimmed.substring(7))
            } catch (e) {
                return trimmed.substring(7)
            }
        }
        return trimmed
    }

    function confirmUpload(filePath) {
        uploadLoader.sourceComponent = undefined
        var normalized = root.normalizeUserPath(filePath)
        if (normalized === "") { root.showToast("Enter a file path to upload", "error"); return }
        startUpload(normalized)
    }

    function startUpload(localFilePath) {
        if (!root.currentRepo) { root.errorMessage = "No library selected"; return }
        var token = Auth.getToken()
        if (!token) { root.errorMessage = "Not authenticated"; return }
        var fileName = localFilePath.split("/").pop()
        TransferService.startUpload(localFilePath, token, root.serverUrl, root.currentRepo.id, root.currentPath, fileName)
    }

    function openFile(item) {
        if (!item || item.type !== "file") return
        if (!root.currentRepo) { root.errorMessage = "No library selected"; return }
        var token = Auth.getToken()
        if (!token) { root.errorMessage = "Not authenticated"; return }
        var fullPath = root.currentPath === "/" ? "/" + item.name : root.currentPath + "/" + item.name
        TransferService.startOpen(item, token, root.serverUrl, root.currentRepo.id, fullPath)
    }

    function downloadFile(item) {
        if (!item || item.type !== "file") return
        if (!root.currentRepo) { root.errorMessage = "No library selected"; return }
        var token = Auth.getToken()
        if (!token) { root.errorMessage = "Not authenticated"; return }
        var session = root.sessionGeneration
        var serverUrl = root.serverUrl
        var repoId = root.currentRepo.id
        var file = { name: item.name, type: item.type }
        var fullPath = root.currentPath === "/" ? "/" + item.name : root.currentPath + "/" + item.name
        SafePath.getDownloadsDir(function(dir) {
            if (session !== root.sessionGeneration) return
            if (!dir) { root.errorMessage = "No download directory available"; return }
            TransferService.startDownload(file, token, serverUrl, repoId, dir, fullPath)
        })
    }

    function handleTransferCompletion(transfer) {
        if (transfer.state === "completed") {
            if (transfer.type === "upload") {
                Cache.invalidatePath(transfer.repoId, transfer.destUploadPath)
                if (root.currentRepo && root.currentRepo.id === transfer.repoId && root.currentPath === transfer.destUploadPath) root.refresh()
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
        root.loginGeneration++
        root.sessionGeneration++
        root.navigationGeneration++
        root.searchGeneration++
        root.connectionTestGeneration++
        root.historyGeneration++
        searchDebounceTimer.stop()
        TransferService.logoutCleanup()
        Auth.clearSession().catch(function(error) {
            root.showToast("Signed out, but stored credentials could not be fully cleared: " + error, "error")
        })
        SeafileAPI.setToken("")
        Cache.clear()
        contextMenu.close()
        createFolderLoader.sourceComponent = undefined
        renameLoader.sourceComponent = undefined
        confirmLoader.sourceComponent = undefined
        shareLoader.sourceComponent = undefined
        uploadLoader.sourceComponent = undefined
        historyLoader.sourceComponent = undefined
        trashLoader.sourceComponent = undefined
        settingsLoader.sourceComponent = undefined
        root.state = "login"
        root.loading = false
        root.serverUrl = ""
        connectionService.setServerUrl("")
        // Drop the active Quick Access scope. Persisted entries are untouched,
        // so signing back into this account restores them; another account sees
        // only its own.
        Favorites.clearActiveScope()
        root.showTransfers = false
        root.currentRepo = null
        root.currentPath = "/"
        root.pathHistory = []
        root.libraries = []
        root.currentItems = []
        root.searchQuery = ""
        root.searchResults = []
        root.searchActive = false
        root.searchState = "idle"
        root.showHistory = false
        root.showTrash = false
        root.destinationMode = ""
        root.destinationSources = []
        root.destinationSourceRepoId = ""
        root.destinationSourcePath = "/"
        root.destinationSourceHistory = []
        root.destinationSubmitting = false
        root.errorMessage = ""
    }

    function openSettings() {
        settingsLoader.sourceComponent = settingsComponent
    }

    function closeSettings() {
        root.connectionTestGeneration++
        settingsLoader.sourceComponent = undefined
    }

    function clearCache() {
        Cache.clear()
        SafePath.clearPersistentCache(function(result) {
            if (result.complete) {
                root.showToast("Cache cleared", "success")
            } else if (result.protected) {
                root.showToast("Memory cache cleared; active files remain", "warning")
            } else {
                root.showToast("Memory cache cleared; persistent cache cleanup could not complete", "warning")
            }
        })
    }

    function changeServerUrl(newUrl, apply) {
        var normalized = normalizeUrl(newUrl)
        if (!normalized) {
            root.showToast("Invalid URL format", "error")
            return
        }
        var policy = UrlPolicy.validateForAuth(normalized)
        if (!policy.valid) {
            root.showToast(policy.error, "error")
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
            settingsDialog.connectionTestMessage = "Testing connection..."
        }

        var generation = ++root.connectionTestGeneration
        var xhr = new XMLHttpRequest()
        var testUrl = normalized + "/api2/ping/"
        xhr.open("GET", testUrl, true)
        xhr.timeout = 10000
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                var dialog = settingsLoader.item
                if (!dialog || dialog !== settingsDialog || generation !== root.connectionTestGeneration) return
                dialog.connectionTestRunning = false
                if (xhr.status >= 200 && xhr.status < 300) {
                    dialog.connectionTestSuccess = true
                    dialog.connectionTestMessage = "Connection successful"
                    // Clear offline state - successful connection means we're online
                    connectionService.forceCheck()
                } else if (xhr.status === 0) {
                    dialog.connectionTestSuccess = false
                    dialog.connectionTestMessage = "Connection failed: Network error"
                } else {
                    dialog.connectionTestSuccess = false
                    dialog.connectionTestMessage = "Connection failed: HTTP " + xhr.status
                }
            }
        }
        xhr.ontimeout = function() {
            var dialog = settingsLoader.item
            if (!dialog || dialog !== settingsDialog || generation !== root.connectionTestGeneration) return
            dialog.connectionTestRunning = false
            dialog.connectionTestSuccess = false
            dialog.connectionTestMessage = "Connection timed out"
        }
        xhr.onerror = function() {
            var dialog = settingsLoader.item
            if (!dialog || dialog !== settingsDialog || generation !== root.connectionTestGeneration) return
            dialog.connectionTestRunning = false
            dialog.connectionTestSuccess = false
            dialog.connectionTestMessage = "Connection error"
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
        if (!folderName || folderName.trim() === "") { if (createFolderLoader.item) createFolderLoader.item.errorText._raw = "Folder name cannot be empty"; return }
        if (folderName !== folderName.trim()) { if (createFolderLoader.item) createFolderLoader.item.errorText._raw = "Folder names cannot start or end with spaces"; return }
        createFolderLoader.sourceComponent = undefined
        var token = Auth.getToken()
        if (!token) { root.errorMessage = "Not authenticated"; return }
        var repoId = root.currentRepo.id
        var parentPath = root.currentPath
        var session = root.sessionGeneration
        root.loading = true
        root.errorMessage = ""
        SeafileAPI.createFolder(repoId, parentPath, folderName, token, function(success, error) {
            if (session !== root.sessionGeneration) return
            root.loading = false
            if (success) {
                Cache.invalidatePath(repoId, parentPath)
                if (root.currentRepo && root.currentRepo.id === repoId && root.currentPath === parentPath) root.refresh()
                root.showToast("Folder created")
            } else {
                root.errorMessage = error || "Failed to create folder"
            }
        })
    }

    // ===== RENAME =====

    property var renameItemData: null

    function pickRename(item) {
        if (!item || !root.currentRepo) return
        root.renameItemData = { items: [item], isDir: item.type === "dir" }
        renameLoader.sourceComponent = renameComponent
    }

    function cancelRename() { renameLoader.sourceComponent = undefined; root.renameItemData = null }

    function confirmRename(newName) {
        if (!newName || newName.trim() === "") { if (renameLoader.item) renameLoader.item.errorText._raw = "Name cannot be empty"; return }
        if (newName !== newName.trim()) { if (renameLoader.item) renameLoader.item.errorText._raw = "Names cannot start or end with spaces"; return }
        var d = root.renameItemData
        var item = d && d.items && d.items.length > 0 ? d.items[0] : null
        if (!item || !root.currentRepo) { cancelRename(); return }
        if (newName === item.name) { cancelRename(); return }
        renameLoader.sourceComponent = undefined
        var token = Auth.getToken()
        if (!token) { root.errorMessage = "Not authenticated"; return }
        var isDir = d.isDir || item.type === "dir"
        var parentPath = root.currentPath
        var repoId = root.currentRepo.id
        var session = root.sessionGeneration
        root.loading = true
        root.errorMessage = ""
        if (isDir) {
            SeafileAPI.renameFolder(repoId, parentPath, item.name, newName, token, function(success, error) {
                if (session !== root.sessionGeneration) return
                root.loading = false
                if (success) { Cache.invalidatePath(repoId, parentPath); if (root.currentRepo && root.currentRepo.id === repoId && root.currentPath === parentPath) root.refresh(); root.showToast("Renamed to " + newName) }
                else { root.errorMessage = error || "Failed to rename folder" }
            })
        } else {
            var fullPath = root.currentPath === "/" ? "/" + item.name : root.currentPath + "/" + item.name
            SeafileAPI.renameFile(repoId, fullPath, newName, token, function(success, error) {
                if (session !== root.sessionGeneration) return
                root.loading = false
                if (success) { Cache.invalidatePath(repoId, parentPath); if (root.currentRepo && root.currentRepo.id === repoId && root.currentPath === parentPath) root.refresh(); root.showToast("Renamed to " + newName) }
                else { root.errorMessage = error || "Failed to rename file" }
            })
        }
    }

    // ===== MOVE / COPY =====

    function beginDestinationMode(operation, snapshot) {
        if (!root.currentRepo || root.destinationMode) return
        var sources = snapshot ? snapshot.slice() : root.selectedItems.slice()
        if (sources.length === 0) return
        root.destinationOperation = operation
        root.destinationSources = sources
        root.destinationSourceRepoId = root.currentRepo ? root.currentRepo.id : ""
        root.destinationSourcePath = root.currentPath
        root.destinationSourceHistory = root.pathHistory.slice()
        root.destinationSubmitting = false
        root.destinationMode = operation
        root.selectedItems = []
    }

    function cancelDestinationMode() {
        if (root.destinationSubmitting) return
        var sourceRepoId = root.destinationSourceRepoId
        var sourcePath = root.destinationSourcePath
        var sourceHistory = root.destinationSourceHistory.slice()
        root.destinationMode = ""
        root.destinationSources = []
        root.destinationSourceRepoId = ""
        root.destinationSourcePath = "/"
        root.destinationSourceHistory = []
        root.destinationSubmitting = false
        root.pathHistory = sourceHistory
        root.currentPath = sourcePath
        if (!root.currentRepo || root.currentRepo.id !== sourceRepoId) {
            root.loadLibraries()
        } else {
            root.loadFolder(root.currentRepo.id, sourcePath)
        }
    }

    function confirmDestination() {
        if (root.destinationSubmitting || root.loading) return
        if (!root.currentRepo) {
            root.errorMessage = "No library open"
            return
        }
        if (root.currentRepo.id !== root.destinationSourceRepoId) {
            root.errorMessage = "Cannot move/copy across libraries"
            return
        }
        var token = Auth.getToken()
        if (!token) { root.errorMessage = "Not authenticated"; return }
        var sources = root.destinationSources.slice()
        if (sources.length === 0) return
        var destPath = root.currentPath
        var allSameParent = true
        for (var i = 0; i < sources.length; i++) {
            var srcP = sources[i].srcParentDir || "/"
            if (srcP !== destPath) { allSameParent = false; break }
        }
        if (allSameParent) {
            root.showToast("Already in this folder")
            root.cancelDestinationMode()
            return
        }
        for (var j = 0; j < sources.length; j++) {
            var source = sources[j]
            if (source.type === "dir" && (destPath === source.fullPath || destPath.indexOf(source.fullPath + "/") === 0)) {
                root.errorMessage = "Cannot " + root.destinationOperation + " a folder into itself"
                return
            }
        }

        var operation = root.destinationOperation
        var sourceRepoId = root.destinationSourceRepoId
        var sourcePath = root.destinationSourcePath
        var destinationRepoId = root.currentRepo.id
        var session = root.sessionGeneration
        root.destinationSubmitting = true
        root.loading = true
        root.errorMessage = ""
        var done = function(success, error) {
            if (session !== root.sessionGeneration) return
            root.destinationSubmitting = false
            root.loading = false
            if (success) {
                Cache.invalidatePath(sourceRepoId, sourcePath)
                Cache.invalidatePath(destinationRepoId, destPath)
                root.destinationMode = ""
                root.destinationSources = []
                root.destinationSourceRepoId = ""
                root.destinationSourcePath = "/"
                root.destinationSourceHistory = []
                if (root.currentRepo && root.currentRepo.id === destinationRepoId && root.currentPath === destPath) root.refresh()
                root.showToast(operation === "move" ? "Moved" : "Copied")
            } else {
                // A failed request can still have reached the server; discard the
                // snapshot rather than allowing a duplicate retry against stale state.
                Cache.invalidatePath(sourceRepoId, sourcePath)
                Cache.invalidatePath(destinationRepoId, destPath)
                root.destinationMode = ""
                root.destinationSources = []
                root.destinationSourceRepoId = ""
                root.destinationSourcePath = "/"
                root.destinationSourceHistory = []
                if (root.currentRepo && root.currentRepo.id === destinationRepoId && root.currentPath === destPath) root.refresh()
                root.errorMessage = error || "Failed to " + operation
            }
        }
        if (sources.length === 1) {
            var item = sources[0]
            var srcParent = item.srcParentDir || "/"
            if (operation === "move") {
                if (item.type === "dir") SeafileAPI.moveFolder(sourceRepoId, item.name, srcParent, destinationRepoId, destPath, token, done)
                else SeafileAPI.moveFile(sourceRepoId, item.fullPath, destPath, token, done)
            } else {
                if (item.type === "dir") SeafileAPI.copyFolder(sourceRepoId, item.name, srcParent, destinationRepoId, destPath, token, done)
                else SeafileAPI.copyFile(sourceRepoId, item.fullPath, destinationRepoId, destPath, item.name, token, done)
            }
        } else {
            if (operation === "move") SeafileAPI.moveItems(sources, destinationRepoId, destPath, done)
            else SeafileAPI.copyItems(sources, destinationRepoId, destPath, done)
        }
    }

    function moveItems() {
        if (!root.currentRepo) { root.errorMessage = "Open a library before moving items"; return }
        if (root.selectedItems.length === 0) return
        root.beginDestinationMode("move")
    }

    function copyItems() {
        if (!root.currentRepo) { root.errorMessage = "Open a library before copying items"; return }
        if (root.selectedItems.length === 0) return
        root.beginDestinationMode("copy")
    }

    // ===== DELETE =====

    property var deleteItemData: null

    function pickDelete(item) {
        if (!item) return
        if (!root.currentRepo) { root.errorMessage = "Libraries cannot be deleted from this view"; return }
        root.deleteItemData = { items: [item], isDir: item.type === "dir" }
        confirmLoader.sourceComponent = confirmComponent
    }

    function deleteItems() {
        if (!root.currentRepo || root.selectedItems.length === 0) return
        root.deleteItemData = { items: root.selectedItems.slice(), isDir: false }
        confirmLoader.sourceComponent = confirmComponent
    }

    function cancelDelete() { confirmLoader.sourceComponent = undefined; root.deleteItemData = null }

    function confirmDelete() {
        var data = root.deleteItemData
        if (!data) { confirmLoader.sourceComponent = undefined; return }
        confirmLoader.sourceComponent = undefined
        if (!root.currentRepo) { root.errorMessage = "Libraries cannot be deleted from this view"; root.deleteItemData = null; return }
        var token = Auth.getToken()
        if (!token) { root.errorMessage = "Not authenticated"; root.deleteItemData = null; return }
        var items = (data.items && data.items.length > 0) ? data.items : []
        root.deleteItemData = null
        if (items.length === 0) return

        if (items.length === 1) {
            var item = items[0]
            var isDir = data.isDir || item.type === "dir"
            var repoId = root.currentRepo.id
            var parentPath = root.currentPath
            var session = root.sessionGeneration
            var fullPath = item.fullPath || (parentPath === "/" ? "/" + item.name : parentPath + "/" + item.name)
            root.loading = true
            root.errorMessage = ""
            if (isDir && fullPath === "/") {
                root.errorMessage = "Cannot delete root directory"
                root.loading = false
                return
            }
            var done = function(success, error) {
                if (session !== root.sessionGeneration) return
                root.loading = false
                if (success) { Cache.invalidatePath(repoId, parentPath); if (root.currentRepo && root.currentRepo.id === repoId && root.currentPath === parentPath) root.refresh(); root.showToast("Deleted") }
                else { root.errorMessage = error || "Failed to delete" }
            }
            if (isDir) SeafileAPI.deleteFolder(repoId, fullPath, token, done)
            else SeafileAPI.deleteFile(repoId, fullPath, token, done)
            return
        }

        // Batch delete: sequential, keep failures selected
        root.loading = true
        root.errorMessage = ""
        root.clearSelection()
        var results = { success: 0, failed: [] }
        var index = 0
        var repoId = root.currentRepo.id
        var parentPath = root.currentPath
        var session = root.sessionGeneration

        function deleteNext() {
            if (session !== root.sessionGeneration) return
            if (index >= items.length) {
                root.loading = false
                var msg = results.success + " deleted"
                if (results.failed.length > 0) msg += ", " + results.failed.length + " failed"
                root.showToast(msg, results.failed.length > 0 ? "error" : "success")
                Cache.invalidatePath(repoId, parentPath)
                if (root.currentRepo && root.currentRepo.id === repoId && root.currentPath === parentPath) {
                    root.refresh()
                    if (results.failed.length > 0) root.selectedItems = results.failed
                }
                return
            }
            var it = items[index]
            var path = it.fullPath || (parentPath === "/" ? "/" + it.name : parentPath + "/" + it.name)
            var step = function(success, error) {
                if (success) results.success++
                else results.failed.push(it)
                index++
                deleteNext()
            }
            if (it.type === "dir") SeafileAPI.deleteFolder(repoId, path, token, step)
            else SeafileAPI.deleteFile(repoId, path, token, step)
        }
        deleteNext()
    }

    // ===== SHARE =====

    property var shareItemData: null

    function pickShare(item) {
        if (!item || !root.currentRepo) return
        var fullPath = root.currentPath === "/" ? "/" + item.name : root.currentPath + "/" + item.name
        root.shareItemData = { item: item, isDir: item.type === "dir", fullPath: fullPath }
        shareLoader.sourceComponent = shareComponent
    }

    function cancelShare() { shareLoader.sourceComponent = undefined; root.shareItemData = null }

    function openHistory(item) {
        if (!root.currentRepo || !item || item.type !== "file") return
        root.historyGeneration++
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
        SeafileAPI.setConnectionService(connectionService)
        updateConnectionServiceUrl()

        // Load favorites from settings: the account-scoped store, the legacy
        // pre-1.1 blob (imported once into the first signed-in account), the
        // migration markers that prevent re-import, and the GLOBAL marker. The
        // global marker is authoritative: once migration completed anywhere,
        // the legacy blob is retired and no later account imports it. The blob
        // historically lived under `favorites`; if the new `favoritesLegacy`
        // key is empty we fall back to it so no pre-1.1 favorites are lost.
        var legacyRaw = setting("favoritesLegacy", "[]")
        if (!legacyRaw || legacyRaw === "[]" || legacyRaw === "{}") {
            legacyRaw = setting("favorites", "[]")
        }
        Favorites.loadFromSettings(
            setting("favoritesStore", "{}"),
            legacyRaw,
            setting("favoritesLegacyMigrated", "[]"),
            setting("favoritesLegacyMigratedGlobally", "false")
        )

        var startupLoginGeneration = root.loginGeneration
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

            if (startupLoginGeneration !== root.loginGeneration || root.state !== "login") return
            if (!setting("autoLogin", true)) return
            var loginAttempt = ++root.loginGeneration
            Auth.isAuthenticated().then(function(authenticated) {
                if (loginAttempt !== root.loginGeneration || root.state !== "login") return
                if (authenticated && !hasRequiredMissing) {
                    var token = Auth.getToken()
                    var serverUrl = Auth.getServerUrl()
                    var policy = UrlPolicy.validateForAuth(serverUrl)
                    if (!policy.valid) {
                        root.errorMessage = "Stored server URL requires HTTPS. Update the server URL in Settings."
                        Auth.cachedToken = ""
                        Auth.cachedServerUrl = ""
                        Auth.cachedEmail = ""
                        return
                    }
                    root.serverUrl = serverUrl
                    Cache.setScope(serverUrl, Auth.getEmail())
                    SeafileAPI.setBaseUrl(serverUrl)
                    SeafileAPI.setToken(token)
                    connectionService.setServerUrl(serverUrl)
                    // Auto-login activates the same account scope as a manual
                    // login, so Quick Access is identical either way.
                    Favorites.setAccountKey(serverUrl, Auth.getEmail())
                    root.persistFavorites()
                    root.state = "browse"
                    root.loadLibraries()
                }
            })
        })

        root.activeTransferCount = TransferService.getActiveCount()
        root.hasTransferFailures = TransferService.hasFailures()
    }
}
