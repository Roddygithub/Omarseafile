import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "./js"
import "./components"
import "./js/UrlPolicy.qml"
import "./js/SafePath.qml"

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
        if (root.destinationSubmitting) return
        if (root.showTransfers) { root.showTransfers = false }
        else if (root.showHistory) { root.showHistory = false; historyLoader.sourceComponent = undefined }
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
        if (historyLoader.item) { root.showHistory = false; historyLoader.sourceComponent = undefined; return true }
        if (trashLoader.item) { root.showTrash = false; trashLoader.sourceComponent = undefined; return true }
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
        if (!item || root.destinationMode) return
        if (!root.isItemSelected(item)) root.selectOnly(item)
        contextMenu.item = item
        contextMenu.isDir = item.type === "dir"
        contextMenu.selectionCount = root.selectedItems.length > 0 ? root.selectedItems.length : 1
        // Disconnect previous connections to avoid duplicates
        try { contextMenu.openClicked.disconnect(root.openFile) } catch (e) {}
        try { contextMenu.openClicked.disconnect(root.onItemClicked) } catch (e) {}
        try { contextMenu.downloadClicked.disconnect(root.onDownloadClicked) } catch (e) {}
        try { contextMenu.shareClicked.disconnect(root.pickShare) } catch (e) {}
        try { contextMenu.renameClicked.disconnect(root.pickRename) } catch (e) {}
        try { contextMenu.moveClicked.disconnect(root.moveItems) } catch (e) {}
        try { contextMenu.copyClicked.disconnect(root.copyItems) } catch (e) {}
        try { contextMenu.deleteClicked.disconnect(root.deleteItems) } catch (e) {}
        try { contextMenu.historyClicked.disconnect(root.openHistory) } catch (e) {}
        try { contextMenu.deleteClicked.disconnect(root.deleteItems) } catch (e) {}

        // Connect signals
        if (item.type === "dir") {
            contextMenu.openClicked.connect(root.onItemClicked)
        } else {
            contextMenu.openClicked.connect(root.openFile)
        }
        contextMenu.downloadClicked.connect(root.onDownloadClicked)
        contextMenu.shareClicked.connect(root.pickShare)
        contextMenu.renameClicked.connect(root.pickRename)
        contextMenu.moveClicked.connect(root.moveItems)
        contextMenu.copyClicked.connect(root.copyItems)
        contextMenu.deleteClicked.connect(root.deleteItems)
        contextMenu.historyClicked.connect(root.openHistory)
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
                var list = root.fileListRef
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
                var list = root.fileListRef
                if (!list || !list.currentItem) return
                var item = list.currentItem.item
                if (item && item.type === "dir") root.onItemClicked(item)
                else if (item && !root.destinationMode) root.openFile(item)
            }
            onDeleteRequested: {
                if (root.state !== "browse" || root.searchActive || root.dialogOpen || root.destinationMode || root.showTransfers) return
                if (root.selectedItems.length > 0) { root.deleteItems(); return }
                var list = root.fileListRef
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
                onOpenClicked: function(item) { item.type === "dir" ? root.onItemClicked(item) : root.openFile(item) }
                onDownloadClicked: root.downloadFile
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
                    showRefresh: root.state === "browse" && !root.searchActive && !root.dialogOpen && !root.destinationMode
                    showUpload: root.state === "browse" && !root.searchActive && !root.dialogOpen && !root.destinationMode
                    showCreateFolder: root.state === "browse" && !root.searchActive && !root.dialogOpen && !root.destinationMode && root.currentRepo !== null
                    showSearch: root.state === "browse" && !root.dialogOpen && !root.destinationMode
                    showLogout: root.state === "browse" && !root.dialogOpen && !root.destinationMode
                    showTransfers: root.state === "browse" && !root.dialogOpen && !root.destinationMode
                    showTrash: root.state === "browse" && !root.dialogOpen && !root.destinationMode
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
                    sourceComponent: root.state === "login" ? loginComponent : browseComponent
                    width: parent.width
                    visible: !root.dialogOpen
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
                            }
                            Text {
                                width: parent.width
                                text: root.currentRepo ? root.currentRepo.name + (root.currentPath === "/" ? " /" : " / " + root.currentPath.substring(1)) : ""
                                color: Qt.darker(root.bar.foreground, 1.3)
                                font.family: root.bar.fontFamily
                                font.pixelSize: Style.font.caption
                                font.bold: true
                                elide: Text.ElideMiddle
                                horizontalAlignment: Text.AlignHCenter
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
                            onDownloadClicked: function(item) { root.destinationMode ? null : root.downloadFile(item) }
                            onOpenClicked: function(item) { root.destinationMode ? null : root.openFile(item) }
                            onRenameClicked: function(item) { root.destinationMode ? null : root.pickRename(item) }
                            onMoveClicked: function(item) { root.destinationMode ? null : root.beginDestinationMode("move", [item]) }
                            onDeleteClicked: function(item) { root.destinationMode ? null : root.pickDelete(item) }
                            onShareClicked: function(item) { root.destinationMode ? null : root.pickShare(item) }
                            onHistoryClicked: root.openHistory
                            visible: !root.loading && root.errorMessage === "" && !root.searchActive && !root.showTransfers
                            selectedItems: root.selectedItems
                            selectionAnchor: root.selectionAnchor
                            onSelectionToggle: root.destinationMode ? function() {} : root.toggleSelection
                            onSelectionRange: root.destinationMode ? function() {} : root.selectRange
                            onSelectOnly: root.destinationMode ? function() {} : root.selectOnly
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
                var repoId = root.historyRepoId
                var filePath = root.historyFilePath
                var fileName = root.historyFileName
                var serverUrl = root.serverUrl
                var token = Auth.getToken()
                var session = root.sessionGeneration
                SeafileAPI.downloadRevision(repoId, filePath, revision.commitId, function(success, data, error) {
                    if (session !== root.sessionGeneration) return
                    if (success && typeof data === "string" && data !== "") {
                        TransferService.startDownload(
                            { name: fileName + " (rev " + revision.commitId.substring(0, 8) + ")", type: "file" },
                            token, serverUrl, repoId,
                            root.getDownloadsDir(), filePath, data
                        )
                        root.showHistory = false
                        historyLoader.sourceComponent = undefined
                        root.showToast("Downloading historical revision...")
                    } else {
                        root.showToast("Failed to download revision: " + error, "error")
                    }
                })
            }
            onClose: function() { root.showHistory = false; historyLoader.sourceComponent = undefined }
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
        id: settingsComponent
        SettingsDialog {
            bar: root.bar
            serverUrl: root.serverUrl
            pluginVersion: "1.0.0"
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
        if (root.loading) return
        var loginAttempt = ++root.loginGeneration
        var normalized = normalizeUrl(url)
        if (!normalized) {
            root.loading = false
            root.errorMessage = "Invalid URL format. Use https://domain.com or http://ip:port"
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
        SeafileAPI.setBaseUrl(normalized)
        SeafileAPI.auth(email, password, function(success, token, error) {
            if (loginAttempt !== root.loginGeneration) return
            if (success) {
                SeafileAPI.setToken(token)
                Auth.storeToken(token, normalized, email).then(function() {
                    if (loginAttempt !== root.loginGeneration) return
                    root.loading = false
                    root.serverUrl = normalized
                    connectionService.setServerUrl(normalized)
                    connectionService.forceCheck()
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
        var cached = Cache.getLibraries()
        if (cached && !root.forceRefresh) {
            root.libraries = cached
            root.currentItems = cached
            root.loading = false
            root.errorMessage = ""
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
                srcParentDir: path,
                fullPath: prefix + it.name
            })
        }
        return out
    }

    function loadFolder(repoId, path) {
        var generation = ++root.navigationGeneration
        root.currentPath = path
        root.errorMessage = ""
        var cached = Cache.getFolder(repoId, path)
        if (cached && !root.forceRefresh) {
            root.currentItems = root.enrichItems(repoId, path, cached)
            root.currentPath = path
            root.loading = false
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
                root.currentPath = path
            } else {
                root.errorMessage = error || "Failed to load folder"
            }
        })
    }

    function onItemClicked(item) {
        if (root.destinationSubmitting) return
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

    function onDownloadClicked(item) {
        if (item.type === "file") {
            var token = Auth.getToken()
            if (!token) { root.errorMessage = "Not authenticated"; return }
            var fullPath = root.currentPath === "/" ? "/" + item.name : root.currentPath + "/" + item.name
            SafePath.secureJoin(getDownloadsDir(), item.name, function(result) {
                if (!result.valid) {
                    root.showToast("Invalid filename: " + result.error, "error")
                    return
                }
                TransferService.startDownload(item, token, root.serverUrl, root.currentRepo.id, getDownloadsDir(), fullPath)
            })
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
        if (!root.currentRepo) { root.errorMessage = "No library selected"; return }
        var token = Auth.getToken()
        if (!token) { root.errorMessage = "Not authenticated"; return }
        var fileName = localFilePath.split("/").pop()
        TransferService.startUpload(localFilePath, token, root.serverUrl, root.currentRepo.id, root.currentPath, fileName)
    }

    function getDownloadsDir() { return Quickshell.env("HOME") + "/Downloads" }

    function getCacheDir() {
        var base = Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache")
        return base + "/omarseafile"
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
        var fullPath = root.currentPath === "/" ? "/" + item.name : root.currentPath + "/" + item.name
        TransferService.startDownload(item, token, root.serverUrl, root.currentRepo.id, getDownloadsDir(), fullPath)
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
        if (!folderName || folderName.trim() === "") { root.errorMessage = "Folder name cannot be empty"; return }
        if (folderName !== folderName.trim()) { root.errorMessage = "Folder names cannot start or end with spaces"; return }
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
        if (!item) return
        root.renameItemData = { items: [item], isDir: item.type === "dir" }
        renameLoader.sourceComponent = renameComponent
    }

    function cancelRename() { renameLoader.sourceComponent = undefined; root.renameItemData = null }

    function confirmRename(newName) {
        if (!newName || newName.trim() === "") { root.errorMessage = "Name cannot be empty"; return }
        if (newName !== newName.trim()) { root.errorMessage = "Names cannot start or end with spaces"; return }
        var d = root.renameItemData
        var item = d && d.items && d.items.length > 0 ? d.items[0] : null
        if (!item) { cancelRename(); return }
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
        var fullPath = root.currentPath === "/" ? "/" + item.name : root.currentPath + "/" + item.name
        root.shareItemData = { item: item, isDir: item.type === "dir", fullPath: fullPath }
        shareLoader.sourceComponent = shareComponent
    }

    function cancelShare() { shareLoader.sourceComponent = undefined; root.shareItemData = null }

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
