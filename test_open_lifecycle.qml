import QtQuick
import Quickshell
import Quickshell.Io
import "./js"

ShellRoot {
    id: root

    readonly property double reservation: TransferService.maxTransferBytes + TransferService.safetyMarginBytes
    readonly property double sentinelReservation: 7
    property var failureProbe: null
    property var cancelProbe: null
    property var successProbe: null
    property var successProcess: null
    property bool failureHandled: false
    property bool cancelHandled: false
    property bool handoffCompleted: false
    property bool openingCacheProtected: false
    property bool lateExitSafe: false
    property bool cacheReleased: false

    function probe(id, path, cacheName) {
        return {
            id: id,
            type: "download",
            state: "opening",
            fileName: id,
            cacheName: cacheName || "",
            cachePath: path,
            process: null,
            _reserved: true,
            _reservedBytes: root.reservation
        }
    }

    function startProbe(transfer) {
        TransferService.transfers = [transfer]
        TransferService._activeReservedBytes = root.reservation + root.sentinelReservation
        TransferService.openCachedFile(transfer)
    }

    function releasedOnce(transfer) {
        return !transfer._reserved && TransferService._activeReservedBytes === root.sentinelReservation
    }

    function maybeFinishHandoff() {
        if (root.handoffCompleted && root.openingCacheProtected && root.successProcess.running) {
            root.successProcess.running = false
        }
    }

    property Component fileProbeComponent: Component {
        Process {
            property var callback: null
            onExited: function(exitCode) {
                var cb = callback
                destroy()
                if (cb) cb(exitCode === 0)
            }
        }
    }

    function fileExists(path, callback) {
        var proc = fileProbeComponent.createObject(root, { callback: callback })
        proc.command = ["test", "-f", path]
        proc.running = true
    }

    Connections {
        target: TransferService
        function onTransferStateChanged(transfer) {
            if (transfer === root.failureProbe && transfer.state === "failed") {
                root.failureHandled = root.releasedOnce(transfer)
                root.cancelProbe = root.probe("cancel", "/probe-cancel")
                root.startProbe(root.cancelProbe)
                Qt.callLater(function() { TransferService.cancelTransfer(root.cancelProbe.id) })
            } else if (transfer === root.cancelProbe && transfer.state === "cancelled") {
                root.cancelHandled = root.releasedOnce(transfer)
                root.successProbe = root.probe("success", root.cachePath, root.cacheName)
                root.startProbe(root.successProbe)
                root.successProcess = root.successProbe.process
                SafePath.clearPersistentCache(function(result) {
                    root.fileExists(root.cachePath, function(exists) {
                        root.openingCacheProtected = !result.complete && result.protected && exists
                            && root.successProbe.state === "opening"
                        root.maybeFinishHandoff()
                    })
                })
            } else if (transfer === root.successProbe && transfer.state === "completed") {
                root.handoffCompleted = root.successProcess.running && root.releasedOnce(transfer)
                root.maybeFinishHandoff()
            }
        }
    }

    Connections {
        target: root.successProcess
        function onExited() {
            root.lateExitSafe = root.successProbe.state === "completed" && root.releasedOnce(root.successProbe)
            SafePath.clearPersistentCache(function(result) {
                root.fileExists(root.cachePath, function(exists) {
                    root.cacheReleased = result.complete && !result.protected && !exists
                    console.log("OPEN_LIFECYCLE failureHandled=" + root.failureHandled
                        + " cancelHandled=" + root.cancelHandled
                        + " handoffCompleted=" + root.handoffCompleted
                        + " openingCacheProtected=" + root.openingCacheProtected
                        + " lateExitSafe=" + root.lateExitSafe
                        + " cacheReleased=" + root.cacheReleased)
                    Qt.quit()
                })
            })
        }
    }

    property string cachePath: ""
    property string cacheName: "open_lifecycle_probe"

    Component.onCompleted: {
        SafePath.getCacheDir(function(result) {
            root.cachePath = result.path + "/" + root.cacheName
            root.failureProbe = root.probe("failure", "/probe-failure")
            root.startProbe(root.failureProbe)
        })
    }
}
