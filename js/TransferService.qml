pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root

    // ===== REGISTRY =====

    property var transfers: []
    property int maxRetries: 3
    property int retryBaseDelay: 2000
    property int maxRetryDelay: 30000
    property int maxHistory: 50

    // ===== TRANSFER LIMITS =====
    property int maxTransferBytes: 1024 * 1024 * 1024
    property int maxUploadResponseBytes: 64 * 1024
    property int maxUploadBodyBytes: 1024 * 1024 * 1024  // 1 GiB
    property int connectTimeoutMs: 10000
    property int totalTimeoutMs: 30 * 60 * 1000
    property int stallSpeedBytes: 1
    property int stallTimeMs: 30000
    // xdg-open may stay alive with terminal handlers; only its initial
    // launch window is part of the Open Local transfer contract.
    readonly property int openHandoffTimeoutMs: 1000
    readonly property int maxTransferStderrBytes: 65536
    readonly property double safetyMarginBytes: 268435456  // 256 MiB
    // QML int is signed 32-bit: reservation totals must remain IEEE-754 numbers.
    readonly property double _reservationPerTransfer: root.maxTransferBytes + root.safetyMarginBytes
    property double _activeReservedBytes: 0

    // ===== BOUNDED UPLOAD QUEUE =====
    // At most maxConcurrentUploads stat/curl pipelines run at once; the rest
    // wait in submission order and are started as active ones terminate.
    property int maxConcurrentUploads: 3
    property int maxQueuedUploads: 100
    property int sessionEpoch: 0
    readonly property string _transferOutputHelper: Qt.resolvedUrl("../scripts/transfer_output.py").toString().replace(/^file:\/\//, "")
    readonly property string _secureFinalizeHelper: Qt.resolvedUrl("../scripts/secure_finalize.py").toString().replace(/^file:\/\//, "")

    // ===== SIGNALS =====

    signal transferProgressChanged(var transfer)
    signal transferStateChanged(var transfer)
    signal transferRetryStarted(var transfer)
    signal transferError(string message)

    function reportError(message) {
        root.transferError(message)
    }

    // Send desktop notification using notify-send
    function notify(title, message, urgency) {
        if (!setting("notifyEnabled", true)) return
        var proc = _notifyFactory.createObject(root)
        if (!proc) return
        proc.command = ["notify-send", "-u", urgency || "normal", "-a", "Omarseafile", title, message]
        proc.running = true
    }

    property Component _notifyFactory: Component {
        Process {
            onExited: destroy()
        }
    }

    // ===== PROCESS FACTORY =====

    property Component downloadProcessComponent: Component {
        Process {
            property var transferRef: null
            property var pgid: 0
            stdout: StdioCollector {}
            stderr: StdioCollector {
                onTextChanged: {
                    if (transferRef && text) {
                        root.parseProgress(text, transferRef)
                        root.transferProgressChanged(transferRef)
                    }
                }
            }
            onStarted: {
                // Command is launched via setsid, so processId is a dedicated
                // session/group leader and is a valid PGID for group kill.
                pgid = processId
            }
            onExited: function(exitCode, exitStatus) {
                if (transferRef) {
                    root.handleDownloadExited(exitCode, transferRef)
                }
            }
        }
    }

    property Component _statFactory: Component {
        Process {
            property var onDone: null
            stdout: StdioCollector {}
            onExited: function(exitCode) {
                var cb = onDone
                var out = stdout.text.trim()
                destroy()
                if (cb) cb(exitCode === 0 ? out : null)
            }
        }
    }

    property Component openDownloadProcessComponent: Component {
        Process {
            property var transferRef: null
            property var pgid: 0
            stdout: StdioCollector {}
            stderr: StdioCollector {
                onTextChanged: {
                    if (transferRef && text) {
                        root.parseProgress(text, transferRef)
                        root.transferProgressChanged(transferRef)
                    }
                }
            }
            onStarted: {
                // Command is launched via setsid, so processId is a dedicated
                // session/group leader and is a valid PGID for group kill.
                pgid = processId
            }
            onExited: function(exitCode, exitStatus) {
                if (transferRef) {
                    root.handleOpenDownloadExited(exitCode, transferRef)
                }
            }
        }
    }

    property Component uploadProcessComponent: Component {
        Process {
            property var transferRef: null
            property var pgid: 0
            // Response is producer-side bounded by curl --max-filesize
            // (maxUploadResponseBytes) before it reaches this collector.
            stdout: StdioCollector {}
            stderr: StdioCollector {
                onTextChanged: {
                    if (transferRef && text) {
                        root.parseProgress(text, transferRef)
                        root.transferProgressChanged(transferRef)
                    }
                }
            }
            onStarted: {
                // Command is launched via setsid, so processId is a dedicated
                // session/group leader and is a valid PGID for group kill.
                pgid = processId
            }
            onExited: function(exitCode, exitStatus) {
                if (transferRef) {
                    root.handleUploadExited(exitCode, transferRef)
                }
            }
        }
    }

    // ===== DERIVED QUERIES =====

    // Non-terminal states. "queued" and "validating" are included so a transfer
    // is always visible and cancellable from the moment it is accepted.
    function isActiveState(state) {
        return state === "queued" || state === "validating" || state === "pending"
            || state === "downloading" || state === "uploading"
            || state === "opening" || state === "cancelling"
    }

    function findTransfer(fileItem) {
        if (!fileItem) return null
        var fullPath = fileItem.fullPath || fileItem.path || fileItem.name || ""
        for (var i = 0; i < root.transfers.length; i++) {
            var t = root.transfers[i]
            if (!root.isActiveState(t.state)) continue
            if (t.repoId === fileItem.repoId && t.fileName === fileItem.name && (t.fullPath === fullPath || t.fullPath === "/" + fileItem.name)) return t
        }
        return null
    }

    function getActiveTransfers() {
        return root.transfers.filter(function(t) {
            return root.isActiveState(t.state)
        })
    }

    // Uploads that currently own a stat/curl pipeline.
    function getRunningUploadCount() {
        var n = 0
        for (var i = 0; i < root.transfers.length; i++) {
            var t = root.transfers[i]
            if (t.type === "upload" && (t.state === "validating" || t.state === "pending" || t.state === "uploading")) n++
        }
        return n
    }

    function getQueuedUploads() {
        return root.transfers.filter(function(t) {
            return t.type === "upload" && t.state === "queued"
        })
    }

    function getCompletedTransfers() {
        return root.transfers.filter(function(t) {
            return t.state === "completed"
        })
    }

    function getFailedTransfers() {
        return root.transfers.filter(function(t) {
            return t.state === "failed" || t.state === "cancelled" || t.state === "auth_failed"
        })
    }

    function getActiveCount() {
        return root.getActiveTransfers().length
    }

    function getCompletedCount() {
        return root.getCompletedTransfers().length
    }

    function getFailedCount() {
        return root.getFailedTransfers().length
    }

    function hasActive() {
        return root.getActiveCount() > 0
    }

    function hasFailures() {
        return root.getFailedCount() > 0
    }

    function getAggregateProgress() {
        var active = root.getActiveTransfers()
        if (active.length === 0) return 0
        var total = 0
        for (var i = 0; i < active.length; i++) {
            total += active[i].progress
        }
        return total / active.length
    }

    // ===== COMMON =====

    // Defense-in-depth: reject non-loopback HTTP before token-bearing transfer requests.
    function _authUrlPolicy(baseUrl) {
        if (!baseUrl) return { valid: false, error: "No server URL configured" }
        return UrlPolicy.validateForAuth(baseUrl)
    }

    // ===== CONCURRENT DISK RESERVATION =====
    // Each download/Open Local reserves maxTransferBytes + safetyMargin bytes
    // before starting its helper. The helper's fstatvfs admission subtracts
    // active reservations from free space, so concurrent transfers cannot
    // collectively exhaust disk. Reservations are released exactly once on the
    // terminal path (success, failure, cancellation, start failure, logout).

    function _reserveTransferCapacity(transfer) {
        if (transfer._reserved) return true
        transfer._reserved = true
        transfer._reservedBytes = root._reservationPerTransfer
        root._activeReservedBytes += transfer._reservedBytes
        return true
    }

    function _releaseTransferCapacity(transfer) {
        if (transfer._reserved) {
            root._activeReservedBytes -= transfer._reservedBytes
            if (root._activeReservedBytes < 0) root._activeReservedBytes = 0
            transfer._reserved = false
            transfer._reservedBytes = 0
        }
    }

    function _currentlyReservedBytes(transfer) {
        // Bytes reserved by OTHER active transfers (excluding this transfer) so
        // a new admission is checked against aggregate reservations that exist
        // on the target filesystem from concurrent transfers.
        return Math.max(0, root._activeReservedBytes - (transfer._reservedBytes || 0))
    }

    function parseError(response) {
        if (!response) return "Unknown error"
        if (typeof response === "string") return response
        if (typeof response === "object") {
            if (response.non_field_errors) return response.non_field_errors.join(", ")
            if (response.detail) return response.detail
            if (response.error_msg) return response.error_msg
            if (response.error) return response.error
        }
        return "Unknown error"
    }

    // Coerce an HTTP status into the canonical numeric form. Anything that is
    // not a real status becomes 0, which means "no HTTP response was observed"
    // and is treated as a transport failure. Status is never inferred by
    // parsing human-readable error text.
    function normalizeStatus(status) {
        var n
        if (typeof status === "number" && isFinite(status)) n = Math.floor(status)
        else if (typeof status === "string") {
            var t = status.trim()
            if (!/^[0-9]{3}$/.test(t)) return 0
            n = parseInt(t, 10)
        } else return 0
        if (n <= 0 || n > 599) return 0
        return n
    }

    // Retryable: no HTTP response at all (0), request timeout (408),
    // Too Early (425), rate limited (429), and any 5xx. Ordinary permanent 4xx
    // such as 400, 404, 409 and 422 deliberately fall through to false so they
    // are not blindly retried with exponential backoff.
    function isRetryableStatus(status) {
        var n = root.normalizeStatus(status)
        if (n === 0) return true
        if (n === 408) return true
        if (n === 425) return true
        if (n === 429) return true
        if (n >= 500 && n < 600) return true
        return false
    }

    // Back-compatible name. The message is accepted but ignored: a message can
    // never raise or lower retryability, only the status decides.
    function isRetryableError(status, errorMsg) {
        return root.isRetryableStatus(status)
    }

    function isAuthError(status) {
        var n = root.normalizeStatus(status)
        return n === 401 || n === 403
    }

    // Build a user-facing message that carries the real status when there is
    // one, without ever guessing a status from the message text.
    function _httpFailureMessage(error, status, fallback) {
        var n = root.normalizeStatus(status)
        if (n === 0) return error || fallback
        return (error || fallback) + " (HTTP " + n + ")"
    }

    function curlFileForm(path) {
        return "file=@\"" + path.replace(/\\/g, "\\\\").replace(/\"/g, "\\\"") + "\""
    }

// Validates secure_output.py helper stdout: single basename line matching exactly [A-Za-z0-9_-]+
    // plus: max 128 chars, expected prefix, no multiline, no whitespace, no path separators, no "." or ".."
    function validateHelperOutput(outText, expectedPrefix) {
        if (!outText) return { valid: false, error: "Empty helper output" }
        var trimmed = outText.trim()
        if (trimmed !== outText) return { valid: false, error: "Helper output has leading/trailing whitespace" }
        if (trimmed.indexOf("\n") !== -1 || trimmed.indexOf("\r") !== -1) return { valid: false, error: "Helper output contains multiple lines" }
        if (trimmed.length > 128) return { valid: false, error: "Helper output exceeds maximum length" }
        if (trimmed === "" || trimmed === "." || trimmed === "..") return { valid: false, error: "Invalid basename" }
        if (trimmed.indexOf("/") !== -1 || trimmed.indexOf("\\") !== -1) return { valid: false, error: "Path separators not allowed in basename" }
        for (var i = 0; i < trimmed.length; i++) {
            var code = trimmed.charCodeAt(i)
            // Only allow A-Z (0x41-0x5A), a-z (0x61-0x7A), 0-9 (0x30-0x39), _ (0x5F), - (0x2D)
            if (!((code >= 0x41 && code <= 0x5A) || (code >= 0x61 && code <= 0x7A) || (code >= 0x30 && code <= 0x39) || code === 0x5F || code === 0x2D)) {
                return { valid: false, error: "Invalid character in basename" }
            }
        }
        if (expectedPrefix && !trimmed.startsWith(expectedPrefix + "_")) {
            return { valid: false, error: "Basename does not match expected prefix" }
        }
        return { valid: true, basename: trimmed }
    }

    // Secret/config temp files are created exclusively through the hardened
    // SafePath.createSecureFile + scripts/atomic_write.py path (see
    // createAuthHeaderFile / createCurlConfigFile below). No mktemp/sh-cat
    // pathname writers remain here.

    property Component _retryTimerFactory: Component {
        Timer {
            property var callback: null
            repeat: false
            onTriggered: {
                var cb = callback
                destroy()
                if (cb) cb()
            }
        }
    }

    property Component _finalizeDownloadProcessFactory: Component {
        Process {
            property var transferRef: null
            onExited: function(exitCode) {
                var t = transferRef
                destroy()
                if (t) root.handleDownloadFinalized(exitCode, t)
            }
        }
    }

    property Component _finalizeOpenDownloadProcessFactory: Component {
        Process {
            property var transferRef: null
            onExited: function(exitCode) {
                var t = transferRef
                destroy()
                if (t) root.handleOpenDownloadFinalized(exitCode, t)
            }
        }
    }

    property Component _cleanupProcessFactory: Component {
        Process {
            onExited: destroy()
        }
    }

    function runCleanup(command) {
        var proc = _cleanupProcessFactory.createObject(root)
        if (!proc) return
        proc.command = command
        proc.running = true
    }

    function deleteFile(filePath) {
        if (!filePath) return
        runCleanup(["rm", "-f", "--", filePath])
    }

    function scheduleRetry(delay, callback) {
        var timer = _retryTimerFactory.createObject(root, { interval: delay, callback: callback })
        if (timer) timer.start()
    }

    // ===== SECURE HEADER/CONFIG FILE CREATION =====

    function createAuthHeaderFile(token, callback) {
        SafePath.createSecureFile("secrets", "seafile_auth", "Authorization: Token " + token, function(result) {
            callback(result.valid ? result.path : null)
        })
    }

    function createCurlConfigFile(url, callback) {
        SafePath.createSecureFile("secrets", "seafile_curl", "url = " + JSON.stringify(url), function(result) {
            callback(result.valid ? result.path : null)
        })
    }

    function cleanupAuthHeaderFile(filePath) {
        deleteFile(filePath)
    }

    function cleanupTransferAuthFile(transfer) {
        if (transfer.authHeaderFile) {
            deleteFile(transfer.authHeaderFile)
            transfer.authHeaderFile = undefined
        }
    }

    function cleanupTransferConfigFile(transfer) {
        if (transfer.curlConfigFile) {
            deleteFile(transfer.curlConfigFile)
            transfer.curlConfigFile = undefined
        }
    }

    // ===== PROGRESS PARSING =====

    function parseProgress(line, transfer) {
        var matches = line.match(/(\d+\.?\d*)%/g)
        if (matches && matches.length > 0) {
            var value = parseFloat(matches[matches.length - 1]) / 100.0
            transfer.progress = Math.max(0, Math.min(1, value))
        }
        var speedMatch = line.match(/(\d+\.?\d*)\s*([KMGT]?B\/s)/)
        if (speedMatch) {
            transfer.speed = speedMatch[1] + " " + speedMatch[2]
        }
    }

    // ===== HISTORY MANAGEMENT =====

    function sanitizeForHistory(transfer) {
        root._releaseTransferCapacity(transfer)
        transfer.token = undefined
        transfer.process = null
        transfer.downloadLink = undefined
        transfer.uploadLink = undefined
        if (transfer.authHeaderFile) {
            deleteFile(transfer.authHeaderFile)
        }
        transfer.authHeaderFile = undefined
        if (transfer.curlConfigFile) {
            deleteFile(transfer.curlConfigFile)
        }
        transfer.curlConfigFile = undefined
        transfer.endTime = Date.now()
        return transfer
    }

    function finishCancelled(transfer) {
        // A cancelled upload frees its concurrency slot.
        if (transfer && transfer.type === "upload") root._pumpUploadQueue()
        root.releaseOpenCache(transfer)
        transfer.state = "cancelled"
        root.sanitizeForHistory(transfer)
    }

    function releaseOpenCache(transfer, callback) {
        if (!transfer || !transfer.cacheName) { if (callback) callback(true); return }
        SafePath.releaseCache(transfer.cacheName, callback)
    }

    function pruneHistory() {
        var terminal = root.transfers.filter(function(t) {
            return t.state === "completed" || t.state === "failed" || t.state === "cancelled" || t.state === "auth_failed"
        })
        if (terminal.length > root.maxHistory) {
            var toRemove = terminal.length - root.maxHistory
            var removeIds = {}
            for (var i = 0; i < toRemove; i++) {
                removeIds[terminal[i].id] = true
            }
            root.transfers = root.transfers.filter(function(t) {
                return !removeIds[t.id]
            })
            root.transfersChanged()
        }
    }

    // ===== SAFE PATH RESOLUTION =====

    function resolveDestPath(dir, fileName, callback) {
        SafePath.secureJoin(dir, fileName, callback)
    }

    // ===== DOWNLOAD =====

    function startDownload(fileItem, token, baseUrl, repoId, destDir, fullPath, downloadLink) {
        var epoch = root.sessionEpoch
        SafePath.secureJoin(destDir, fileItem.name, function(destResult) {
            if (epoch !== root.sessionEpoch) return
            if (!destResult.valid) {
                var errTransfer = { error: destResult.error, state: "failed" }
                root.reportError("Invalid destination: " + destResult.error)
                return
            }

            var download = {
                id: Date.now() + Math.random(),
                type: "download",
                state: "pending",
                fileName: fileItem.name,
                fullPath: fullPath,
                destDir: destDir,
                destPath: destResult.path,
                tempPath: "",
                repoId: repoId,
                repoName: "",
                token: token,
                baseUrl: baseUrl,
                process: null,
                downloadLink: null,
                progress: 0,
                speed: "",
                error: "",
                retryCount: 0,
                startTime: Date.now(),
                endTime: null,
                authHeaderFile: null,
                curlConfigFile: null,
                epoch: epoch
            }

            var downloads = root.transfers.slice()
            downloads.push(download)
            root.transfers = downloads
            root.transfersChanged()

            if (typeof downloadLink === "string" && downloadLink !== "") {
                var vUrl = UrlPolicy.validateTransferUrl(downloadLink)
                if (!vUrl.valid) {
                    download.state = "failed"
                    download.error = "Invalid download URL: " + vUrl.error
                    root.sanitizeForHistory(download)
                    root.transferStateChanged(download)
                    root.transfersChanged()
                    return
                }
                download.downloadLink = downloadLink
                download.state = "downloading"
                root.transferStateChanged(download)
                root.transfersChanged()
                root.executeCurlDownload(download)
            } else {
                root.getDownloadLinkAndExecute(download)
            }
            return download
        })
    }

    function getDownloadLinkAndExecute(download) {
        if (download.state === "cancelled") return
        var policy = root._authUrlPolicy(download.baseUrl)
        if (!policy.valid) {
            download.state = "failed"
            download.error = policy.error
            root.sanitizeForHistory(download)
            root.transferStateChanged(download)
            root.transfersChanged()
            return
        }
        var path = download.fullPath || "/" + download.fileName
        var url = download.baseUrl.replace(/\/+$/, "") + "/api2/repos/" + download.repoId + "/file/?p=" + encodeURIComponent(path) + "&reuse=1"
        HttpTransport.get(url, { "Authorization": "Token " + download.token, "Accept": "application/json" },
            function(success, data, error, status) {
                if (download.epoch !== undefined && download.epoch !== root.sessionEpoch) return
                if (download.state === "cancelled" || download.state === "cancelling") return
                if (success) {
                    if (typeof data !== "string" || data === "") {
                        download.state = "failed"
                        download.error = "Invalid server response"
                        root.sanitizeForHistory(download)
                        root.transferStateChanged(download)
                        root.transfersChanged()
                        return
                    }
                    var vUrl = UrlPolicy.validateTransferUrl(data)
                    if (!vUrl.valid) {
                        download.state = "failed"
                        download.error = "Invalid download URL: " + vUrl.error
                        root.sanitizeForHistory(download)
                        root.transferStateChanged(download)
                        root.transfersChanged()
                        return
                    }
                    download.downloadLink = data
                    download.state = "downloading"
                    root.transferStateChanged(download)
                    root.transfersChanged()
                    root.executeCurlDownload(download)
                } else if (root.isAuthError(status)) {
                    download.state = "auth_failed"
                    download.error = "Authentication failed (HTTP " + status + ")"
                    root.sanitizeForHistory(download)
                    root.transferStateChanged(download)
                    root.transfersChanged()
                } else if (root.isRetryableStatus(status) && download.retryCount < root.maxRetries) {
                    download.retryCount++
                    var delay = Math.min(root.retryBaseDelay * Math.pow(2, download.retryCount - 1), root.maxRetryDelay)
                    download.state = "pending"
                    root.transferRetryStarted(download)
                    root.transferStateChanged(download)
                    root.transfersChanged()
                    scheduleRetry(delay, function() {
                        if (download.epoch !== undefined && download.epoch !== root.sessionEpoch) return
                        if (download.state === "cancelled" || download.state === "cancelling") return
                        root.getDownloadLinkAndExecute(download)
                    })
                } else {
                    download.state = "failed"
                    download.error = root._httpFailureMessage(error, status, "Download link request failed")
                    root.sanitizeForHistory(download)
                    root.transferStateChanged(download)
                    root.transfersChanged()
                }
            }
        )
    }

    function executeCurlDownload(download) {
        if (download.state !== "pending" && download.state !== "downloading") return

        // Only attach auth header if transfer URL is same-origin as Seafile base
        var attachAuth = UrlPolicy.shouldAttachAuth(download.downloadLink, download.baseUrl)

        if (!attachAuth) {
            // Cross-origin: no auth header
            executeCurlDownloadNoAuth(download)
            return
        }

        createAuthHeaderFile(download.token, function(authHeaderFile) {
            if (download.state !== "pending" && download.state !== "downloading") {
                cleanupAuthHeaderFile(authHeaderFile)
                return
            }
            if (!authHeaderFile) {
                download.state = "failed"
                download.error = "Failed to create auth header file"
                root.sanitizeForHistory(download)
                root.transferStateChanged(download)
                root.transfersChanged()
                return
            }
            download.authHeaderFile = authHeaderFile
            createCurlConfigFile(download.downloadLink, function(curlConfigFile) {
                if (download.state !== "pending" && download.state !== "downloading") { deleteFile(curlConfigFile); return }
                if (!curlConfigFile) {
                    download.state = "failed"
                    download.error = "Failed to create curl configuration"
                    root.sanitizeForHistory(download)
                    root.transferStateChanged(download)
                    root.transfersChanged()
                    return
                }
                download.curlConfigFile = curlConfigFile
                var curlProc = downloadProcessComponent.createObject(root)
                if (!curlProc) {
                    root._releaseTransferCapacity(download)
                    download.state = "failed"
                    download.error = "Failed to create download process"
                    root.sanitizeForHistory(download)
                    root.transferStateChanged(download)
                    root.transfersChanged()
                    return
                }
                curlProc.transferRef = download
                root._reserveTransferCapacity(download)
                var scriptsBase = Qt.resolvedUrl("../scripts")
                var outputHelper = scriptsBase + "/secure_output.py"
                curlProc.command = [
                    "setsid", "python3",
                    outputHelper.replace(/^file:\/\//, ""),
                    download.destDir, "dl",
                    "--max-stderr-bytes", root.maxTransferStderrBytes,
                    "--max-transfer-bytes", root.maxTransferBytes,
                    "--safety-margin", "268435456",
                    "--already-reserved-bytes", String(root._currentlyReservedBytes(download)),
                    "--",
                    "curl",
                    "-q",
                    "-f",
                    "-H", "@" + authHeaderFile,
                    "-H", "Accept: */*",
                    "--progress-bar",
                    "--config", curlConfigFile,
                    "--max-filesize", root.maxTransferBytes,
                    "--connect-timeout", Math.ceil(root.connectTimeoutMs / 1000),
                    "--max-time", Math.ceil(root.totalTimeoutMs / 1000),
                    "--speed-limit", root.stallSpeedBytes,
                    "--speed-time", Math.ceil(root.stallTimeMs / 1000),
                    "--no-location"
                ]
                download.process = curlProc
                curlProc.running = true
            })
        })
    }

    // Cross-origin download: no auth header attached
    function executeCurlDownloadNoAuth(download) {
        if (download.state !== "pending" && download.state !== "downloading") return
        createCurlConfigFile(download.downloadLink, function(curlConfigFile) {
            if (download.state !== "pending" && download.state !== "downloading") { deleteFile(curlConfigFile); return }
            if (!curlConfigFile) {
                download.state = "failed"
                download.error = "Failed to create curl configuration"
                root.sanitizeForHistory(download)
                root.transferStateChanged(download)
                root.transfersChanged()
                return
            }
            download.curlConfigFile = curlConfigFile
            var curlProc = downloadProcessComponent.createObject(root)
            if (!curlProc) {
                root._releaseTransferCapacity(download)
                download.state = "failed"
                download.error = "Failed to create download process"
                root.sanitizeForHistory(download)
                root.transferStateChanged(download)
                root.transfersChanged()
                return
            }
            curlProc.transferRef = download
            root._reserveTransferCapacity(download)
            var scriptsBase = Qt.resolvedUrl("../scripts")
            var outputHelper = scriptsBase + "/secure_output.py"
            curlProc.command = [
                "setsid", "python3",
                outputHelper.replace(/^file:\/\//, ""),
                download.destDir, "dl",
                "--max-stderr-bytes", root.maxTransferStderrBytes,
                "--max-transfer-bytes", root.maxTransferBytes,
                "--safety-margin", "268435456",
                "--already-reserved-bytes", String(root._currentlyReservedBytes(download)),
                "--",
                "curl",
                "-q",
                "-f",
                "-H", "Accept: */*",
                "--progress-bar",
                "--config", curlConfigFile,
                "--max-filesize", root.maxTransferBytes,
                "--connect-timeout", Math.ceil(root.connectTimeoutMs / 1000),
                "--max-time", Math.ceil(root.totalTimeoutMs / 1000),
                "--speed-limit", root.stallSpeedBytes,
                "--speed-time", Math.ceil(root.stallTimeMs / 1000),
                "--no-location"
            ]
            download.process = curlProc
            curlProc.running = true
        })
    }

    function handleDownloadExited(exitCode, download) {
        var process = download.process
        download.process = null
        var outText = process ? process.stdout.text : ""
        if (process) process.destroy()
        cleanupTransferAuthFile(download)
        cleanupTransferConfigFile(download)

        if (download.state === "cancelling") {
            deleteFile(download.tempPath)
            root.finishCancelled(download)
        } else if (exitCode === 0) {
            var validation = root.validateHelperOutput(outText, "dl")
            if (!validation.valid) {
                download.state = "failed"
                download.error = "Invalid helper output: " + validation.error
                root.sanitizeForHistory(download)
            } else {
                var tempPath = download.destDir + "/" + validation.basename
                download.tempPath = tempPath
                root.finalizeDownload(download)
                return
            }
        } else {
            if (exitCode !== 22 && download.retryCount < root.maxRetries) {
                download.retryCount++
                var delay = Math.min(root.retryBaseDelay * Math.pow(2, download.retryCount - 1), root.maxRetryDelay)
                download.state = "pending"
                root.transferRetryStarted(download)
                root.transferStateChanged(download)
                root.transfersChanged()
                scheduleRetry(delay, function() { root.executeCurlDownload(download) })
                return
            }
            download.state = "failed"
            download.error = "Download failed (exit code: " + exitCode + ")"
            root.sanitizeForHistory(download)
        }
        deleteFile(download.tempPath)
        root.transferStateChanged(download)
        root.transfersChanged()
    }

    function finalizeDownload(download) {
        var proc = _finalizeDownloadProcessFactory.createObject(root)
        if (!proc) {
            download.state = "failed"
            download.error = "Failed to finalize download"
            deleteFile(download.tempPath)
            root.sanitizeForHistory(download)
            root.transferStateChanged(download)
            root.transfersChanged()
            return
        }
        proc.transferRef = download
        proc.command = ["sh", "-c", "mv -nT -- \"$1\" \"$2\" && test ! -e \"$1\"", "sh", download.tempPath, download.destPath]
        download.process = proc
        proc.running = true
    }

    function handleDownloadFinalized(exitCode, download) {
        download.process = null
        if (download.state === "cancelling") {
            deleteFile(download.tempPath)
            root.finishCancelled(download)
        } else if (exitCode === 0) {
            download.state = "completed"
            download.progress = 1.0
            download.speed = ""
            root.sanitizeForHistory(download)
            root.pruneHistory()
            root.notify("Download completed", download.fileName, "low")
        } else {
            download.state = "failed"
            download.error = "Download target already exists or could not be finalized"
            deleteFile(download.tempPath)
            root.sanitizeForHistory(download)
            root.notify("Download failed", download.fileName, "critical")
        }
        root.transferStateChanged(download)
        root.transfersChanged()
    }

    // ===== UPLOAD =====

    function parseUploadStat(out) {
        if (typeof out !== "string") return null
        var parts = out.trim().split(":")
        if (parts.length !== 2 || !/^[0-9a-fA-F]+$/.test(parts[0]) || !/^[0-9]+$/.test(parts[1])) return null
        return {
            regular: (parseInt(parts[0], 16) & 0xF000) === 0x8000,
            size: Number(parts[1])
        }
    }

    // Accepts an upload request. The transfer is registered SYNCHRONOUSLY,
    // before any asynchronous validation, so logout/cancel can always see it
    // and invalidate it. Previously the stat preflight ran first and the
    // transfer only appeared afterwards, which let a logout slip past and a
    // stale callback resurrect the upload with the old token.
    function startUpload(localFilePath, token, baseUrl, repoId, destPath, fileName) {
        if (!localFilePath || typeof localFilePath !== "string" || !localFilePath.startsWith("/")) {
            root.reportError("Invalid upload source: must be absolute path")
            return null
        }
        var pendingQueued = root.getQueuedUploads().length
        if (pendingQueued >= root.maxQueuedUploads) {
            root.reportError("Upload queue is full (" + root.maxQueuedUploads + " waiting). Try again shortly.")
            return null
        }

        var upload = {
            id: Date.now() + Math.random(),
            type: "upload",
            state: "queued",
            srcPath: localFilePath,
            destUploadPath: destPath,
            fileName: fileName || localFilePath.split("/").pop(),
            repoId: repoId,
            repoName: "",
            token: token,
            baseUrl: baseUrl,
            process: null,
            statProcess: null,
            uploadLink: null,
            progress: 0,
            speed: "",
            error: "",
            retryCount: 0,
            startTime: Date.now(),
            endTime: null,
            authHeaderFile: null,
            curlConfigFile: null,
            // Captured at creation. Every later continuation compares against
            // root.sessionEpoch and bails out if a logout happened meanwhile.
            epoch: root.sessionEpoch
        }

        var list = root.transfers.slice()
        list.push(upload)
        root.transfers = list
        root.transfersChanged()

        root._pumpUploadQueue()
        return upload
    }

    // ===== UPLOAD SCHEDULER =====

    function _pumpUploadQueue() {
        while (root.getRunningUploadCount() < root.maxConcurrentUploads) {
            var next = null
            for (var i = 0; i < root.transfers.length; i++) {
                var t = root.transfers[i]
                // transfers[] keeps submission order, so the first queued entry
                // is the oldest one. Stale entries (from a previous session) are
                // skipped rather than started - and skipping is what keeps this
                // loop terminating, because _beginUploadValidation refuses a
                // stale transfer and would otherwise never change its state.
                if (t.type !== "upload" || t.state !== "queued") continue
                if (t.epoch !== undefined && t.epoch !== root.sessionEpoch) continue
                next = t
                break
            }
            if (!next) return
            var before = next.state
            root._beginUploadValidation(next)
            if (next.state === before) return
        }
    }

    // Validation Process belongs to the transfer, so cancel/logout can stop it.
    function _beginUploadValidation(upload) {
        if (upload.epoch !== root.sessionEpoch) return
        if (upload.state !== "queued") return
        upload.state = "validating"
        root.transferStateChanged(upload)
        root.transfersChanged()

        var proc = _statFactory.createObject(root, {
            onDone: function(out) {
                upload.statProcess = null
                // A logout or a cancel while stat was running invalidates this
                // continuation entirely - no curl, no resurrected transfer.
                if (upload.epoch !== root.sessionEpoch) return
                if (upload.state === "cancelled" || upload.state === "cancelling") return
                if (upload.state !== "validating") return

                if (!out) {
                    root._failUpload(upload, "Upload source does not exist or cannot be accessed")
                    return
                }
                var statResult = root.parseUploadStat(out)
                if (!statResult) {
                    root._failUpload(upload, "Upload source: file metadata could not be validated")
                    return
                }
                if (!statResult.regular) {
                    root._failUpload(upload, "Upload source must be a regular file (not symlink, directory, device, FIFO, or socket)")
                    return
                }
                if (statResult.size > root.maxUploadBodyBytes) {
                    root._failUpload(upload, "Upload source exceeds maximum size of " + root.maxUploadBodyBytes + " bytes")
                    return
                }
                var nameResult = SafePath.sanitizeBasename(upload.fileName)
                if (!nameResult.valid) {
                    root._failUpload(upload, nameResult.error)
                    return
                }
                upload.fileName = nameResult.sanitized
                upload.state = "pending"
                root.transferStateChanged(upload)
                root.transfersChanged()
                root.getUploadLinkAndExecute(upload)
            }
        })
        if (!proc) {
            root._failUpload(upload, "Failed to validate upload source")
            return
        }
        upload.statProcess = proc
        proc.command = ["stat", "-c", "%f:%s", "--", upload.srcPath]
        proc.running = true
    }

    function _failUpload(upload, message) {
        root._finishUploadFailure(upload, "Invalid upload source: " + message)
    }

    // Single choke point for an upload that failed before curl ran (or at the
    // link-resolution stage). It retires the transfer, sanitizes history,
    // emits signals, releases the concurrency slot, and pumps the queue exactly
    // once so the next queued upload starts even though this one never owned a
    // curl pipeline. Every early terminal failure path routes here.
    function _finishUploadFailure(upload, message) {
        if (!upload) return
        if (upload.state !== "queued" && upload.state !== "validating"
            && upload.state !== "pending" && upload.state !== "uploading") {
            // Already terminal: do not double-pump.
            return
        }
        upload.state = "failed"
        upload.error = message
        root.reportError(message)
        root.sanitizeForHistory(upload)
        root.transferStateChanged(upload)
        root.transfersChanged()
        root._uploadSettled(upload)
    }

    // Releases a finished upload's slot and starts the next queued one.
    function _uploadSettled(upload) {
        if (upload) upload.process = null
        root._pumpUploadQueue()
    }

    function getUploadLinkAndExecute(upload) {
        if (upload.state === "cancelled") return
        var policy = root._authUrlPolicy(upload.baseUrl)
        if (!policy.valid) {
            root._finishUploadFailure(upload, policy.error)
            return
        }
        var url = upload.baseUrl.replace(/\/+$/, "") + "/api2/repos/" + upload.repoId + "/upload-link/?p=" + encodeURIComponent(upload.destUploadPath)
        HttpTransport.get(url, { "Authorization": "Token " + upload.token, "Accept": "application/json" },
            function(success, data, error, status) {
                if (upload.epoch !== root.sessionEpoch) return
                if (upload.state === "cancelled" || upload.state === "cancelling") return
                if (success) {
                    if (typeof data !== "string" || data === "") {
                        root._finishUploadFailure(upload, "Invalid server response")
                        return
                    }
                    var vUrl = UrlPolicy.validateTransferUrl(data)
                    if (!vUrl.valid) {
                        root._finishUploadFailure(upload, "Invalid upload URL: " + vUrl.error)
                        return
                    }
                    upload.uploadLink = data
                    upload.state = "uploading"
                    root.transferStateChanged(upload)
                    root.transfersChanged()
                    root.executeCurlUpload(upload)
                } else if (root.isAuthError(status)) {
                    upload.state = "auth_failed"
                    upload.error = "Authentication failed (HTTP " + status + ")"
                    root.sanitizeForHistory(upload)
                    root.transferStateChanged(upload)
                    root.transfersChanged()
                    root._uploadSettled(upload)
                } else if (root.isRetryableStatus(status) && upload.retryCount < root.maxRetries) {
                    upload.retryCount++
                    var delay = Math.min(root.retryBaseDelay * Math.pow(2, upload.retryCount - 1), root.maxRetryDelay)
                    upload.state = "pending"
                    root.transferRetryStarted(upload)
                    root.transferStateChanged(upload)
                    root.transfersChanged()
                    scheduleRetry(delay, function() {
                        if (upload.epoch !== root.sessionEpoch) return
                        if (upload.state === "cancelled" || upload.state === "cancelling") return
                        root.getUploadLinkAndExecute(upload)
                    })
                } else {
                    upload.state = "failed"
                    // Permanent failure (e.g. 400/404/409/422): no blind retry.
                    upload.error = root._httpFailureMessage(error, status, "Upload link request failed")
                    root.sanitizeForHistory(upload)
                    root.transferStateChanged(upload)
                    root.transfersChanged()
                    root._uploadSettled(upload)
                }
            }
        )
    }

    function executeCurlUpload(upload) {
        if (upload.state !== "pending" && upload.state !== "uploading") return

        // Only attach auth header if transfer URL is same-origin as Seafile base
        var uploadUrl = upload.uploadLink + (upload.uploadLink.indexOf("?") === -1 ? "?" : "&") + "ret-json=1"
        var attachAuth = UrlPolicy.shouldAttachAuth(uploadUrl, upload.baseUrl)

        if (!attachAuth) {
            // Cross-origin: no auth header
            executeCurlUploadNoAuth(upload)
            return
        }

        createAuthHeaderFile(upload.token, function(authHeaderFile) {
            if (upload.state !== "pending" && upload.state !== "uploading") {
                cleanupAuthHeaderFile(authHeaderFile)
                return
            }
            if (!authHeaderFile) {
                root._finishUploadFailure(upload, "Failed to create auth header file")
                return
            }
            upload.authHeaderFile = authHeaderFile
            createCurlConfigFile(uploadUrl, function(curlConfigFile) {
                if (upload.state !== "pending" && upload.state !== "uploading") { deleteFile(curlConfigFile); return }
                if (!curlConfigFile) {
                    root._finishUploadFailure(upload, "Failed to create curl configuration")
                    return
                }
                upload.curlConfigFile = curlConfigFile
                var curlProc = uploadProcessComponent.createObject(root)
                if (!curlProc) {
                    root._finishUploadFailure(upload, "Failed to create upload process")
                    return
                }
                curlProc.transferRef = upload
                curlProc.command = [
                    "setsid", "python3", root._transferOutputHelper,
                    root.maxTransferStderrBytes, "--",
                    "curl",
                    "-q",
                    "-f",
                    "-H", "@" + authHeaderFile,
                    "-H", "Accept: application/json",
                    "--progress-bar",
                    "--form", root.curlFileForm(upload.srcPath),
                    "--form-string", "parent_dir=" + upload.destUploadPath,
                    "--form-string", "replace=0",
                    "--config", curlConfigFile,
                    "--max-filesize", root.maxUploadResponseBytes,
                    "--connect-timeout", Math.ceil(root.connectTimeoutMs / 1000),
                    "--max-time", Math.ceil(root.totalTimeoutMs / 1000),
                    "--speed-limit", root.stallSpeedBytes,
                    "--speed-time", Math.ceil(root.stallTimeMs / 1000),
                    "--no-location"
                ]
                upload.process = curlProc
                curlProc.running = true
            })
        })
    }

    // Cross-origin upload: no auth header attached
function executeCurlUploadNoAuth(upload) {
        if (upload.state !== "pending" && upload.state !== "uploading") return
        var uploadUrl = upload.uploadLink + (upload.uploadLink.indexOf("?") === -1 ? "?" : "&") + "ret-json=1"
        createCurlConfigFile(uploadUrl, function(curlConfigFile) {
            if (upload.state !== "pending" && upload.state !== "uploading") { deleteFile(curlConfigFile); return }
            if (!curlConfigFile) {
                root._finishUploadFailure(upload, "Failed to create curl configuration")
                return
            }
            upload.curlConfigFile = curlConfigFile
            var curlProc = uploadProcessComponent.createObject(root)
            if (!curlProc) {
                root._finishUploadFailure(upload, "Failed to create upload process")
                return
            }
            curlProc.transferRef = upload
            curlProc.command = [
                "setsid", "python3", root._transferOutputHelper,
                root.maxTransferStderrBytes, "--",
                "curl",
                "-q",
                "-f",
                "-H", "Accept: application/json",
                "--progress-bar",
                "--form", root.curlFileForm(upload.srcPath),
                "--form-string", "parent_dir=" + upload.destUploadPath,
                "--form-string", "replace=0",
                "--config", curlConfigFile,
                "--max-filesize", root.maxUploadResponseBytes,
                "--connect-timeout", Math.ceil(root.connectTimeoutMs / 1000),
                "--max-time", Math.ceil(root.totalTimeoutMs / 1000),
                "--speed-limit", root.stallSpeedBytes,
                "--speed-time", Math.ceil(root.stallTimeMs / 1000),
                "--no-location"
            ]
            upload.process = curlProc
            curlProc.running = true
        })
    }

    function handleUploadExited(exitCode, upload) {
        var process = upload.process
        upload.process = null
        cleanupTransferAuthFile(upload)
        cleanupTransferConfigFile(upload)

        if (upload.state === "cancelling") {
            if (process) process.destroy()
            root.finishCancelled(upload)
        } else if (exitCode === 0) {
            var response
            try {
                response = JSON.parse(process ? process.stdout.text : "")
            } catch (e) {}
            if (process) process.destroy()
            if (Array.isArray(response) && response.length > 0 && response.length <= 10) {
                var item = response[0]
                if (item && typeof item === "object" && typeof item.name === "string" && item.name.length > 0 && item.name.length <= 1024) {
                    upload.fileName = item.name
                    upload.state = "completed"
                    upload.progress = 1.0
                    upload.speed = ""
                    root.sanitizeForHistory(upload)
                    root.pruneHistory()
                } else {
                    upload.state = "failed"
                    upload.error = "Upload server response was invalid"
                    root.sanitizeForHistory(upload)
                }
            } else {
                upload.state = "failed"
                upload.error = "Upload server response was invalid"
                root.sanitizeForHistory(upload)
            }
        } else if (upload.state !== "cancelled" && exitCode === 63) {
            if (process) process.destroy()
            upload.state = "failed"
            upload.error = "Upload response too large (exceeds " + root.maxUploadResponseBytes + " bytes)"
            root.sanitizeForHistory(upload)
        } else if (upload.state !== "cancelled") {
            if (process) process.destroy()
            upload.state = "failed"
            upload.error = "Upload outcome is unknown after curl failed (exit code: " + exitCode + "); verify the server before retrying"
            root.sanitizeForHistory(upload)
            root.notify("Upload failed", upload.fileName, "critical")
        }
        if (upload.state === "completed") {
            root.notify("Upload completed", upload.fileName, "low")
        }
        root.transferStateChanged(upload)
        root.transfersChanged()
        // This upload no longer occupies a concurrency slot; start the next one.
        root._pumpUploadQueue()
    }

    // ===== CANCEL (with process group kill) =====

    function cancelTransfer(transferId) {
        for (var i = 0; i < root.transfers.length; i++) {
            var t = root.transfers[i]
            if (t.id === transferId) {
                // Still waiting for a scheduler slot: nothing was started, so
                // it can be retired immediately without any process work.
                if (t.state === "queued") {
                    t.state = "cancelled"
                    t.endTime = Date.now()
                    root.sanitizeForHistory(t)
                    root.transferStateChanged(t)
                    root.transfersChanged()
                    root._pumpUploadQueue()
                    return true
                }
                // Validation in flight: stop it, then retire. The stat Process
                // belongs to the transfer, and the preflight continuation is
                // additionally gated on state and session epoch.
                if (t.state === "validating") {
                    if (t.statProcess) {
                        try { t.statProcess.running = false } catch (e) {}
                        try { t.statProcess.destroy() } catch (e) {}
                        t.statProcess = null
                    }
                    t.state = "cancelled"
                    t.endTime = Date.now()
                    root.sanitizeForHistory(t)
                    root.transferStateChanged(t)
                    root.transfersChanged()
                    root._pumpUploadQueue()
                    return true
                }
                if (t.process) {
                    t.state = "cancelling"
                    try {
                        var pgid = t.process.pgid
                        if (pgid > 0) {
                            root.runCleanup(["kill", "-TERM", "-" + pgid])
                        } else {
                            t.process.running = false
                        }
                    } catch (e) {
                        try { t.process.running = false } catch (e) {}
                    }
                    // The Process onExited handler owns terminal cleanup and release.
                    root.transferStateChanged(t)
                    root.transfersChanged()
                    return true
                }
                t.state = "cancelled"
                if (t.type === "download" && t.tempPath) deleteFile(t.tempPath)
                root.releaseOpenCache(t)
                cleanupTransferAuthFile(t)
                root.sanitizeForHistory(t)
                root.transferStateChanged(t)
                root.transfersChanged()
                return true
            }
        }
        return false
    }

    // ===== MANUAL RETRY =====

    function retryTransfer(transferId, token, baseUrl) {
        for (var i = 0; i < root.transfers.length; i++) {
            var t = root.transfers[i]
            if (t.id === transferId) {
                var isTerminal = t.state === "completed" || t.state === "failed" || t.state === "cancelled" || t.state === "auth_failed"
                if (!isTerminal) return false

                var type = t.type
                var fileName = t.fileName
                var repoId = t.repoId
                if (!token || !baseUrl) return false
                if (type === "upload" && root.getQueuedUploads().length >= root.maxQueuedUploads) return false
                if (type === "upload" && (!t.srcPath || !t.srcPath.startsWith("/"))) return false

                cleanupTransferAuthFile(t)

                root.transfers.splice(i, 1)
                root.transfersChanged()

                if (type === "download") {
                    root.startDownload(
                        { name: fileName, type: "file" },
                        token, baseUrl, repoId,
                        t.destDir, t.fullPath
                    )
                } else {
                    root.startUpload(
                        t.srcPath, token, baseUrl, repoId,
                        t.destUploadPath, fileName
                    )
                }
                return true
            }
        }
        return false
    }

    // ===== CLEAR =====

    function clearCompleted() {
        for (var i = 0; i < root.transfers.length; i++) {
            var t = root.transfers[i]
            if (t.state === "completed") {
                cleanupTransferAuthFile(t)
            }
        }
        root.transfers = root.transfers.filter(function(t) {
            return t.state !== "completed"
        })
        root.transfersChanged()
    }

    function clearFailed() {
        for (var i = 0; i < root.transfers.length; i++) {
            var t = root.transfers[i]
            if (t.state === "failed" || t.state === "cancelled" || t.state === "auth_failed") {
                cleanupTransferAuthFile(t)
            }
        }
        root.transfers = root.transfers.filter(function(t) {
            return t.state !== "failed" && t.state !== "cancelled" && t.state !== "auth_failed"
        })
        root.transfersChanged()
    }

    function clearAllTerminal() {
        for (var i = 0; i < root.transfers.length; i++) {
            var t = root.transfers[i]
            if (t.state === "completed" || t.state === "failed" || t.state === "cancelled" || t.state === "auth_failed") {
                cleanupTransferAuthFile(t)
            }
        }
        root.transfers = root.transfers.filter(function(t) {
            return t.state === "pending" || t.state === "downloading" || t.state === "uploading" || t.state === "opening"
        })
        root.transfersChanged()
    }

    // Remove a single TERMINAL transfer from history. Batch "Clear All" actions
    // keep clearing whole categories; this targets exactly one transfer.
    function clearTransfer(transferId) {
        for (var i = 0; i < root.transfers.length; i++) {
            var t = root.transfers[i]
            if (t.id === transferId) {
                var terminal = t.state === "completed" || t.state === "failed" || t.state === "cancelled" || t.state === "auth_failed"
                if (!terminal) return false
                cleanupTransferAuthFile(t)
                var next = root.transfers.filter(function(x) { return x.id !== t.id })
                root.transfers = next
                root.transfersChanged()
                return true
            }
        }
        return false
    }

    // ===== OPEN FILE (DOWNLOAD TO CACHE + XDG-OPEN) =====

    function startOpen(fileItem, token, baseUrl, repoId, fullPath) {
        var download = {
            id: Date.now() + Math.random(),
            type: "download",
            state: "pending",
            fileName: fileItem.name,
            fullPath: fullPath,
            cacheDir: "",
            cachePath: "",
            cacheName: "",
            tempPath: "",
            tempName: "",
            repoId: repoId,
            repoName: "",
            token: token,
            baseUrl: baseUrl,
            process: null,
            downloadLink: null,
            progress: 0,
            speed: "",
            error: "",
            retryCount: 0,
            startTime: Date.now(),
            endTime: null,
            authHeaderFile: null,
            curlConfigFile: null,
            epoch: root.sessionEpoch
        }
        var openDownloads = root.transfers.slice()
        openDownloads.push(download)
        root.transfers = openDownloads
        root.transfersChanged()
        // Recover abandoned cache entries before admitting a new persistent file.
        SafePath.evictCache(function(ok) {
            if (download.epoch !== root.sessionEpoch) return
            if (download.state !== "pending") return
            if (!ok) {
                download.state = "failed"
                download.error = "Cache recovery could not free enough space"
                root.sanitizeForHistory(download)
                root.transferStateChanged(download)
                root.transfersChanged()
                return
            }
            root._startOpenAfterRecovery(download)
        })
        return download
    }

    function _startOpenAfterRecovery(download) {
        SafePath.getCacheDir(function(cacheResult) {
            if (download.state !== "pending") return
            if (!cacheResult.valid) {
                download.state = "failed"
                download.error = "Cache directory unavailable: " + cacheResult.error
                root.sanitizeForHistory(download)
                root.transferStateChanged(download)
                root.transfersChanged()
                return
            }
            SafePath.secureJoin(cacheResult.path, download.fileName, function(nameResult) {
                if (download.state !== "pending") return
                if (!nameResult.valid) {
                    download.state = "failed"
                    download.error = "Invalid filename: " + nameResult.error
                    root.sanitizeForHistory(download)
                    root.transferStateChanged(download)
                    root.transfersChanged()
                    return
                }
                var extensionMatch = /\.([A-Za-z0-9]{1,16})$/.exec(nameResult.name)
                var cacheName = "open_" + Date.now() + "_" + Math.random().toString(36).substr(2, 9)
                    + (extensionMatch ? "." + extensionMatch[1] : "")
                download.cacheDir = cacheResult.path
                download.cacheName = cacheName
                download.cachePath = cacheResult.path + "/" + cacheName
                root.getDownloadLinkAndOpen(download)
            })
        })
    }

    function getDownloadLinkAndOpen(download) {
        if (download.state === "cancelled") return
        var policy = root._authUrlPolicy(download.baseUrl)
        if (!policy.valid) {
            download.state = "failed"
            download.error = policy.error
            root.sanitizeForHistory(download)
            root.transferStateChanged(download)
            root.transfersChanged()
            return
        }
        var path = download.fullPath || "/" + download.fileName
        var url = download.baseUrl.replace(/\/+$/, "") + "/api2/repos/" + download.repoId + "/file/?p=" + encodeURIComponent(path) + "&reuse=1"
        HttpTransport.get(url, { "Authorization": "Token " + download.token, "Accept": "application/json" },
            function(success, data, error, status) {
                if (download.epoch !== undefined && download.epoch !== root.sessionEpoch) return
                if (download.state === "cancelled" || download.state === "cancelling") return
                if (success) {
                    if (typeof data !== "string" || data === "") {
                        download.state = "failed"
                        download.error = "Invalid server response"
                        root.sanitizeForHistory(download)
                        root.transferStateChanged(download)
                        root.transfersChanged()
                        return
                    }
                    var vUrl = UrlPolicy.validateTransferUrl(data)
                    if (!vUrl.valid) {
                        download.state = "failed"
                        download.error = "Invalid download URL: " + vUrl.error
                        root.sanitizeForHistory(download)
                        root.transferStateChanged(download)
                        root.transfersChanged()
                        return
                    }
                    download.downloadLink = data
                    download.state = "downloading"
                    root.transferStateChanged(download)
                    root.transfersChanged()
                    root.executeCurlOpenDownload(download)
                } else if (root.isAuthError(status)) {
                    download.state = "auth_failed"
                    download.error = "Authentication failed (HTTP " + status + ")"
                    root.sanitizeForHistory(download)
                    root.transferStateChanged(download)
                    root.transfersChanged()
                } else if (root.isRetryableStatus(status) && download.retryCount < root.maxRetries) {
                    download.retryCount++
                    var delay = Math.min(root.retryBaseDelay * Math.pow(2, download.retryCount - 1), root.maxRetryDelay)
                    download.state = "pending"
                    root.transferRetryStarted(download)
                    root.transferStateChanged(download)
                    root.transfersChanged()
                    scheduleRetry(delay, function() {
                        if (download.epoch !== undefined && download.epoch !== root.sessionEpoch) return
                        if (download.state === "cancelled" || download.state === "cancelling") return
                        root.getDownloadLinkAndOpen(download)
                    })
                } else {
                    download.state = "failed"
                    download.error = root._httpFailureMessage(error, status, "Download link request failed")
                    root.sanitizeForHistory(download)
                    root.transferStateChanged(download)
                    root.transfersChanged()
                }
            }
        )
    }

    function executeCurlOpenDownload(download) {
        if (download.state !== "pending" && download.state !== "downloading") return

        // Only attach auth header if transfer URL is same-origin as Seafile base
        var attachAuth = UrlPolicy.shouldAttachAuth(download.downloadLink, download.baseUrl)

        if (!attachAuth) {
            // Cross-origin: no auth header
            executeCurlOpenDownloadNoAuth(download)
            return
        }

        createAuthHeaderFile(download.token, function(authHeaderFile) {
            if (download.state !== "pending" && download.state !== "downloading") {
                cleanupAuthHeaderFile(authHeaderFile)
                return
            }
            if (!authHeaderFile) {
                download.state = "failed"
                download.error = "Failed to create auth header file"
                root.sanitizeForHistory(download)
                root.transferStateChanged(download)
                root.transfersChanged()
                return
            }
            download.authHeaderFile = authHeaderFile
            createCurlConfigFile(download.downloadLink, function(curlConfigFile) {
                if (download.state !== "pending" && download.state !== "downloading") { deleteFile(curlConfigFile); return }
                if (!curlConfigFile) {
                    download.state = "failed"
                    download.error = "Failed to create curl configuration"
                    root.sanitizeForHistory(download)
                    root.transferStateChanged(download)
                    root.transfersChanged()
                    return
                }
                download.curlConfigFile = curlConfigFile
                var curlProc = openDownloadProcessComponent.createObject(root)
                if (!curlProc) {
                    root._releaseTransferCapacity(download)
                    download.state = "failed"
                    download.error = "Failed to create download process"
                    root.sanitizeForHistory(download)
                    root.transferStateChanged(download)
                    root.transfersChanged()
                    return
                }
                curlProc.transferRef = download
                root._reserveTransferCapacity(download)
                var scriptsBase = Qt.resolvedUrl("../scripts")
                var outputHelper = scriptsBase + "/secure_output.py"
                curlProc.command = [
                    "setsid", "python3",
                    outputHelper.replace(/^file:\/\//, ""),
                    download.cacheDir, "dl",
                    "--active-marker",
                    "--max-stderr-bytes", root.maxTransferStderrBytes,
                    "--max-transfer-bytes", root.maxTransferBytes,
                    "--safety-margin", "268435456",
                    "--already-reserved-bytes", String(root._currentlyReservedBytes(download)),
                    "--",
                    "curl",
                    "-q",
                    "-f",
                    "-H", "@" + authHeaderFile,
                    "-H", "Accept: */*",
                    "--progress-bar",
                    "--config", curlConfigFile,
                    "--max-filesize", root.maxTransferBytes,
                    "--connect-timeout", Math.ceil(root.connectTimeoutMs / 1000),
                    "--max-time", Math.ceil(root.totalTimeoutMs / 1000),
                    "--speed-limit", root.stallSpeedBytes,
                    "--speed-time", Math.ceil(root.stallTimeMs / 1000),
                    "--no-location"
                ]
                download.process = curlProc
                curlProc.running = true
            })
        })
    }

    // Cross-origin open download: no auth header attached
    function executeCurlOpenDownloadNoAuth(download) {
        if (download.state !== "pending" && download.state !== "downloading") return
        createCurlConfigFile(download.downloadLink, function(curlConfigFile) {
            if (download.state !== "pending" && download.state !== "downloading") { deleteFile(curlConfigFile); return }
            if (!curlConfigFile) {
                download.state = "failed"
                download.error = "Failed to create curl configuration"
                root.sanitizeForHistory(download)
                root.transferStateChanged(download)
                root.transfersChanged()
                return
            }
            download.curlConfigFile = curlConfigFile
            var curlProc = openDownloadProcessComponent.createObject(root)
            if (!curlProc) {
                root._releaseTransferCapacity(download)
                download.state = "failed"
                download.error = "Failed to create download process"
                root.sanitizeForHistory(download)
                root.transferStateChanged(download)
                root.transfersChanged()
                return
            }
            curlProc.transferRef = download
            root._reserveTransferCapacity(download)
            var scriptsBase = Qt.resolvedUrl("../scripts")
            var outputHelper = scriptsBase + "/secure_output.py"
            curlProc.command = [
                "setsid", "python3",
                    outputHelper.replace(/^file:\/\//, ""),
                    download.cacheDir, "dl",
                    "--active-marker",
                    "--max-stderr-bytes", root.maxTransferStderrBytes,
                "--max-transfer-bytes", root.maxTransferBytes,
                "--safety-margin", "268435456",
                "--already-reserved-bytes", String(root._currentlyReservedBytes(download)),
                "--",
                "curl",
                "-q",
                "-f",
                "-H", "Accept: */*",
                "--progress-bar",
                "--config", curlConfigFile,
                "--max-filesize", root.maxTransferBytes,
                "--connect-timeout", Math.ceil(root.connectTimeoutMs / 1000),
                "--max-time", Math.ceil(root.totalTimeoutMs / 1000),
                "--speed-limit", root.stallSpeedBytes,
                "--speed-time", Math.ceil(root.stallTimeMs / 1000),
                "--no-location"
            ]
            download.process = curlProc
            curlProc.running = true
        })
    }

    function handleOpenDownloadExited(exitCode, download) {
        var process = download.process
        download.process = null
        var outText = process ? process.stdout.text : ""
        if (process) process.destroy()
        root.cleanupTransferAuthFile(download)
        root.cleanupTransferConfigFile(download)

        if (download.state === "cancelling") {
            root.cleanupOpenTemp(download)
            root.finishCancelled(download)
        } else if (exitCode === 0) {
            var validation = root.validateHelperOutput(outText, "dl")
            if (!validation.valid) {
                download.state = "failed"
                download.error = "Invalid helper output: " + validation.error
                root.sanitizeForHistory(download)
            } else {
                var tempPath = download.cacheDir + "/" + validation.basename
                download.tempPath = tempPath
                download.tempName = validation.basename
                root.finalizeOpenDownload(download)
                return
            }
        } else {
            if (download.retryCount < root.maxRetries) {
                download.retryCount++
                var delay = Math.min(root.retryBaseDelay * Math.pow(2, download.retryCount - 1), root.maxRetryDelay)
                download.state = "pending"
                root.transferRetryStarted(download)
                root.transferStateChanged(download)
                root.transfersChanged()
                root.scheduleRetry(delay, function() { root.executeCurlOpenDownload(download) })
                return
            }
            download.state = "failed"
            download.error = "Download failed (exit code: " + exitCode + ")"
            root.sanitizeForHistory(download)
        }
        root.deleteFile(download.tempPath)
        root.transferStateChanged(download)
        root.transfersChanged()
    }

    function finalizeOpenDownload(download) {
        var proc = _finalizeOpenDownloadProcessFactory.createObject(root)
        if (!proc) {
            download.state = "failed"
            download.error = "Failed to finalize download"
            root.cleanupOpenTemp(download)
            root.sanitizeForHistory(download)
            root.transferStateChanged(download)
            root.transfersChanged()
            return
        }
        proc.transferRef = download
        proc.command = ["python3", root._secureFinalizeHelper, download.cacheDir,
            download.tempName, download.cacheName]
        download.process = proc
        proc.running = true
    }

    function handleOpenDownloadFinalized(exitCode, download) {
        download.process = null
        if (download.state === "cancelling") {
            // Only a successful finalizer owns cachePath; a failed finalizer
            // may have encountered an existing entry with the same name.
            root.cleanupOpenTemp(download, exitCode === 0)
            root.finishCancelled(download)
        } else if (exitCode === 0) {
            download.state = "opening"
            download.progress = 1.0
            download.speed = ""
            download.destPath = download.cachePath
            root.openCachedFile(download)
            // Keep the just-opened cache path out of this eviction pass.
            SafePath.evictCache([download.cacheName], function(ok) {
                if (!ok) {
                    // Eviction failed but download succeeded; log and continue
                    console.warn("Cache eviction failed, continuing")
                }
            })
        } else {
            download.state = "failed"
            download.error = "Cache file already exists or could not be finalized"
            root.cleanupOpenTemp(download)
            root.sanitizeForHistory(download)
        }
        root.transferStateChanged(download)
        root.transfersChanged()
    }

    property Component openCachedFileComponent: Component {
        Process {
            property var transferRef: null
            property var handoffTimer: null
            property var pgid: 0
            onStarted: {
                pgid = processId
                var proc = this
                handoffTimer = root._retryTimerFactory.createObject(root, {
                    interval: root.openHandoffTimeoutMs,
                    callback: function() {
                        proc.handoffTimer = null
                        root.completeOpenHandoff(proc.transferRef, proc)
                    }
                })
                if (handoffTimer) handoffTimer.start()
            }
            onExited: function(exitCode) {
                var t = transferRef
                var proc = this
                if (handoffTimer) {
                    handoffTimer.stop()
                    handoffTimer.destroy()
                    handoffTimer = null
                }
                destroy()
                root.handleOpenCachedFileExited(exitCode, t, proc)
            }
        }
    }

    function completeOpenHandoff(transfer, process) {
        if (!transfer || transfer.state !== "opening" || transfer.process !== process) return
        transfer.process = null
        root.releaseOpenCache(transfer)
        transfer.state = "completed"
        root.sanitizeForHistory(transfer)
        root.pruneHistory()
        root.transferStateChanged(transfer)
        root.transfersChanged()
    }

    function handleOpenCachedFileExited(exitCode, transfer, process) {
        if (!transfer) return
        if (transfer.process === process) transfer.process = null
        if (transfer.state === "cancelling") {
            root.finishCancelled(transfer)
        } else if (transfer.state === "opening" && exitCode === 0) {
            root.releaseOpenCache(transfer)
            transfer.state = "completed"
            root.sanitizeForHistory(transfer)
            root.pruneHistory()
        } else if (transfer.state === "opening") {
            root.releaseOpenCache(transfer)
            transfer.state = "failed"
            transfer.error = "Cached file could not be opened by the default application"
            root.sanitizeForHistory(transfer)
        } else {
            return
        }
        root.transferStateChanged(transfer)
        root.transfersChanged()
    }

    function openCachedFile(transfer) {
        SafePath.protectCache(transfer.cacheName)
        var proc = openCachedFileComponent.createObject(root)
        if (!proc) {
            root.releaseOpenCache(transfer)
            transfer.state = "failed"
            transfer.error = "Could not start the default application"
            root.sanitizeForHistory(transfer)
            root.transferStateChanged(transfer)
            root.transfersChanged()
            return
        }
        // Resolve the user's MIME handler, then let UWSM honor its desktop
        // entry semantics (including Terminal=true) through the configured
        // default terminal. Keep the path as an argv value throughout.
        proc.command = ["setsid", "bash", "-c",
            "mime=$(xdg-mime query filetype \"$1\") && desktop=$(xdg-mime query default \"$mime\") && exec uwsm-app -- \"$desktop\" \"$1\"",
            "omarseafile-open", transfer.cachePath]
        proc.transferRef = transfer
        transfer.process = proc
        proc.running = true
    }

    function cleanupOpenTemp(download, removeCache) {
        root.deleteFile(download.tempPath)
        if (download.cacheDir && download.tempName) {
            root.deleteFile(download.cacheDir + "/.active_" + download.tempName)
        }
        root.releaseOpenCache(download)
        if (removeCache && download.cachePath) root.deleteFile(download.cachePath)
    }

    // ===== LOGOUT CLEANUP =====

    function logoutCleanup() {
        // Bump first: any in-flight continuation that captured an older epoch
        // (stat preflight, upload-link request, scheduled retry) becomes inert
        // the moment this runs, so nothing can resurrect a transfer or reuse
        // the old credentials afterwards.
        root.sessionEpoch++
        var active = root.transfers.slice()
        for (var i = 0; i < active.length; i++) {
            // Retire anything the epoch bump orphaned (a queued upload that will
            // never be scheduled) so it cannot linger in a non-terminal state.
            if (active[i].state === "queued" || active[i].state === "validating") {
                if (active[i].statProcess) {
                    try { active[i].statProcess.running = false } catch (e) {}
                    try { active[i].statProcess.destroy() } catch (e) {}
                    active[i].statProcess = null
                }
                active[i].state = "cancelled"
                active[i].endTime = Date.now()
            }
            root.cancelTransfer(active[i].id)
        }
        root.transfers = []
        root.transfersChanged()
    }
}
