import QtQuick
import Quickshell
import Quickshell.Io
import "./js"

ShellRoot {
    id: root
    property bool freshCache: false
    property bool pendingOpenCancelled: false
    property var openProbe: null
    property var cancelProbe: null
    property var logoutProbe: null
    property var successProbe: null
    property bool xdgOpenFailed: false
    property bool xdgOpenCancel: false
    property bool xdgOpenLogout: false
    property bool xdgOpenReleased: false
    property bool xdgOpenSuccess: false
    property bool accountSwitchSafe: false
    property bool openingCacheProtected: false
    property bool protectionReleased: false
    property bool protectedClearResult: false
    property bool postReleaseClearResult: false
    property bool successOpenComplete: false
    property string runtimeCacheDir: ""
    property var protectedProbe: null

    Panel {
        id: accountPanel
        visible: false
    }

    Timer {
        id: completionTimer
        interval: 1000
        repeat: false
        onTriggered: {
            console.log("REMEDIATION reserved=" + root.reserved + " released=" + root.released + " deep=" + root.deepValid + " libraryKeys=" + root.libraryKeysUnique + " visualRange=" + root.visualRange + " freshCache=" + root.freshCache + " pendingOpenCancelled=" + root.pendingOpenCancelled + " xdgOpenFailed=" + root.xdgOpenFailed + " xdgOpenCancel=" + root.xdgOpenCancel + " xdgOpenLogout=" + root.xdgOpenLogout + " xdgOpenReleased=" + root.xdgOpenReleased + " xdgOpenSuccess=" + root.xdgOpenSuccess + " accountSwitchSafe=" + root.accountSwitchSafe + " openingCacheProtected=" + root.openingCacheProtected + " protectionReleased=" + root.protectionReleased + " protectedClearResult=" + root.protectedClearResult + " postReleaseClearResult=" + root.postReleaseClearResult)
            Qt.quit()
        }
    }

    property double reserved: 0
    property double released: 0
    property bool deepValid: true
    property bool libraryKeysUnique: false
    property int visualRange: 0

    function openProbeTransfer(id, path) {
        return {
            id: id,
            type: "download",
            state: "opening",
            fileName: id,
            cachePath: path,
            process: null,
            _reserved: true,
            _reservedBytes: TransferService.maxTransferBytes + TransferService.safetyMarginBytes
        }
    }

    function startProbe(transfer) {
        TransferService.transfers = [transfer]
        TransferService._activeReservedBytes = transfer._reservedBytes
        TransferService.openCachedFile(transfer)
    }

    function finishIfReady() {
        if (root.freshCache && root.xdgOpenFailed && root.xdgOpenCancel && root.xdgOpenLogout && root.xdgOpenReleased && root.xdgOpenSuccess && root.accountSwitchSafe && root.openingCacheProtected && root.protectionReleased && root.protectedClearResult && root.postReleaseClearResult) completionTimer.start()
    }

    property Component fileProbeComponent: Component {
        Process {
            property var onDone: null
            onExited: function(exitCode) {
                var cb = onDone
                destroy()
                if (cb) cb(exitCode === 0)
            }
        }
    }

    function fileExists(path, callback) {
        var proc = fileProbeComponent.createObject(root, { onDone: callback })
        proc.command = ["test", "-f", path]
        proc.running = true
    }

    function startCacheProtectionProbe() {
        if (!root.runtimeCacheDir || !root.successOpenComplete || root.protectedProbe) return
        root.protectedProbe = root.openProbeTransfer("open-runtime-protected", root.runtimeCacheDir + "/open_runtime_protected")
        root.protectedProbe.cacheDir = root.runtimeCacheDir
        root.protectedProbe.cacheName = "open_runtime_protected"
        TransferService.transfers = [root.protectedProbe]
        TransferService.openCachedFile(root.protectedProbe)
        SafePath.clearPersistentCache(function(result) {
            root.fileExists(root.protectedProbe.cachePath, function(exists) {
                root.protectedClearResult = !result.complete && result.protected
                root.openingCacheProtected = root.protectedClearResult && exists && root.protectedProbe.state === "opening"
                TransferService.cancelTransfer(root.protectedProbe.id)
            })
        })
    }

    function checkProductionRelease() {
        root.fileExists(root.protectedProbe.cacheDir + "/.active_" + root.protectedProbe.cacheName, function(markerExists) {
            if (markerExists) {
                markerReleaseTimer.start()
                return
            }
            SafePath.clearPersistentCache(function(result) {
                root.fileExists(root.protectedProbe.cachePath, function(exists) {
                    root.postReleaseClearResult = result.complete && !result.protected && !exists
                    root.protectionReleased = root.postReleaseClearResult
                    root.finishIfReady()
                })
            })
        })
    }

    Timer {
        id: markerReleaseTimer
        interval: 10
        repeat: false
        onTriggered: root.checkProductionRelease()
    }

    Timer {
        id: cancelTimer
        interval: 50
        repeat: false
        onTriggered: TransferService.cancelTransfer(root.cancelProbe.id)
    }

    Timer {
        id: logoutTimer
        interval: 50
        repeat: false
        onTriggered: TransferService.logoutCleanup()
    }

    Timer {
        id: accountSwitchTimer
        interval: 1500
        repeat: false
        onTriggered: {
            root.accountSwitchSafe = !TransferService.transfers.some(function(transfer) { return transfer.fileName === "session-a.txt" })
            root.finishIfReady()
        }
    }

    Connections {
        target: TransferService
        function onTransferStateChanged(transfer) {
            if (transfer === root.protectedProbe && transfer.state === "cancelled") {
                root.checkProductionRelease()
            } else if (transfer === root.openProbe && transfer.state === "failed") {
                root.xdgOpenFailed = true
                root.cancelProbe = root.openProbeTransfer("open-cancel", "/probe-cancel")
                root.startProbe(root.cancelProbe)
                cancelTimer.start()
            } else if (transfer === root.cancelProbe && transfer.state === "cancelled") {
                root.xdgOpenCancel = true
                root.xdgOpenReleased = TransferService._activeReservedBytes === 0 && !transfer._reserved
                root.logoutProbe = root.openProbeTransfer("open-logout", "/probe-logout")
                root.startProbe(root.logoutProbe)
                logoutTimer.start()
            } else if (transfer === root.logoutProbe && transfer.state === "cancelled") {
                root.xdgOpenLogout = true
                root.xdgOpenReleased = root.xdgOpenReleased && TransferService._activeReservedBytes === 0 && !transfer._reserved
                root.successProbe = root.openProbeTransfer("open-success", "/probe-success")
                root.startProbe(root.successProbe)
            } else if (transfer === root.successProbe && transfer.state === "completed") {
                root.xdgOpenSuccess = true
                root.xdgOpenReleased = root.xdgOpenReleased && TransferService._activeReservedBytes === 0 && !transfer._reserved
                root.successOpenComplete = true
                root.startCacheProtectionProbe()
                root.finishIfReady()
            }
        }
    }

    Component.onCompleted: {
        TransferService._activeReservedBytes = 0
        TransferService._activeReservedBytes = 2 * (TransferService.maxTransferBytes + TransferService.safetyMarginBytes)
        root.reserved = TransferService._activeReservedBytes
        TransferService._activeReservedBytes = 0

        var nested = {}
        var cursor = nested
        for (var i = 0; i < 40; i++) {
            cursor.child = {}
            cursor = cursor.child
        }
        root.deepValid = HttpTransport.validateResponse(nested).valid
        var libraries = [
            { id: "repo-a", name: "Same", type: "dir" },
            { id: "repo-b", name: "Same", type: "dir" }
        ]
        root.libraryKeysUnique = SelectionHelper.makeKey(libraries[0]) !== SelectionHelper.makeKey(libraries[1])
        var visual = [
            { repoId: "r", fullPath: "/c", type: "file" },
            { repoId: "r", fullPath: "/b", type: "file" },
            { repoId: "r", fullPath: "/a", type: "file" }
        ]
        root.visualRange = SelectionHelper.rangeSelect([], visual[0], visual[2], visual).length
        var pendingOpen = TransferService.startOpen({ name: "pending.txt", type: "file" }, "FAKE", "https://example.invalid", "repo", "/pending.txt")
        TransferService.logoutCleanup()
        root.pendingOpenCancelled = pendingOpen.state === "cancelled" && TransferService.transfers.length === 0
        root.openProbe = root.openProbeTransfer("open-failure", "/probe-failure")
        TransferService.openCachedFile(root.openProbe)
        Auth.cachedToken = "SENTINEL_SESSION_A"
        accountPanel.currentRepo = { id: "repo-a" }
        accountPanel.currentPath = "/"
        accountPanel.serverUrl = "https://server-a.invalid"
        accountPanel.downloadFile({ name: "session-a.txt", type: "file" })
        accountPanel.sessionGeneration++
        accountPanel.currentRepo = { id: "repo-b" }
        accountPanel.serverUrl = "https://server-b.invalid"
        Auth.cachedToken = "SENTINEL_SESSION_B"
        accountSwitchTimer.start()
        SafePath.getCacheDir(function(cacheResult) {
            root.freshCache = cacheResult.valid
            if (cacheResult.valid) root.runtimeCacheDir = cacheResult.path
            root.startCacheProtectionProbe()
            root.finishIfReady()
        })
    }
}
