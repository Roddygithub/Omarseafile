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
    readonly property int maxTransferStderrBytes: 65536
    readonly property double safetyMarginBytes: 268435456  // 256 MiB
    // QML int is signed 32-bit: reservation totals must remain IEEE-754 numbers.
    readonly property double _reservationPerTransfer: root.maxTransferBytes + root.safetyMarginBytes
    property double _activeReservedBytes: 0
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

    function findTransfer(fileItem) {
        if (!fileItem) return null
        var fullPath = fileItem.fullPath || fileItem.path || fileItem.name || ""
        for (var i = 0; i < root.transfers.length; i++) {
            var t = root.transfers[i]
            if (t.state !== "pending" && t.state !== "downloading" && t.state !== "uploading" && t.state !== "opening" && t.state !== "cancelling") continue
            if (t.repoId === fileItem.repoId && t.fileName === fileItem.name && (t.fullPath === fullPath || t.fullPath === "/" + fileItem.name)) return t
        }
        return null
    }

    function getActiveTransfers() {
        return root.transfers.filter(function(t) {
            return t.state === "pending" || t.state === "downloading" || t.state === "uploading" || t.state === "opening" || t.state === "cancelling"
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

    function isRetryableError(status, errorMsg) {
        if (status === 0) return true
        if (status === 408) return true
        if (status >= 500 && status < 600) return true
        if (errorMsg && errorMsg.includes("network")) return true
        if (errorMsg && errorMsg.includes("timeout")) return true
        if (errorMsg && errorMsg.includes("connection")) return true
        return false
    }

    function isAuthError(status) {
        return status === 401 || status === 403
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
        var match = line.match(/(\d+\.?\d*)%/)
        if (match) {
            transfer.progress = parseFloat(match[1]) / 100.0
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
        SafePath.secureJoin(destDir, fileItem.name, function(destResult) {
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
                curlConfigFile: null
            }

            root.transfers.push(download)
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
            function(success, data, error) {
                if (download.state === "cancelled") return
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
                } else if (root.isAuthError(error)) {
                    download.state = "auth_failed"
                    download.error = "Authentication failed"
                    root.sanitizeForHistory(download)
                    root.transferStateChanged(download)
                    root.transfersChanged()
                } else if (root.isRetryableError(0, error) && download.retryCount < root.maxRetries) {
                    download.retryCount++
                    var delay = Math.min(root.retryBaseDelay * Math.pow(2, download.retryCount - 1), root.maxRetryDelay)
                    download.state = "pending"
                    root.transferRetryStarted(download)
                    root.transferStateChanged(download)
                    root.transfersChanged()
                    scheduleRetry(delay, function() { root.getDownloadLinkAndExecute(download) })
                } else {
                    download.state = "failed"
                    download.error = error || "Download link request failed"
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
            if (download.retryCount < root.maxRetries) {
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
        } else {
            download.state = "failed"
            download.error = "Download target already exists or could not be finalized"
            deleteFile(download.tempPath)
            root.sanitizeForHistory(download)
        }
        root.transferStateChanged(download)
        root.transfersChanged()
    }

    // ===== UPLOAD =====

    function startUpload(localFilePath, token, baseUrl, repoId, destPath, fileName) {
        // Validate upload source: absolute path, regular file, not symlink, size limit
        if (!localFilePath || typeof localFilePath !== "string" || !localFilePath.startsWith("/")) {
            var errTransfer = { error: "Upload source must be an absolute path", state: "failed" }
            root.reportError("Invalid upload source: must be absolute path")
            return
        }
        var statProc = _statFactory.createObject(root, {
            onDone: function(out) {
                if (!out) {
                    var errTransfer = { error: "Upload source does not exist or cannot be accessed", state: "failed" }
                    root.reportError("Invalid upload source: " + errTransfer.error)
                    return
                }
                var parts = out.split(" ")
                var ftype = parts[0]
                var size = parseInt(parts[1], 10)
                if (ftype !== "regular file") {
                    var errTransfer = { error: "Upload source must be a regular file (not symlink, directory, device, FIFO, or socket)", state: "failed" }
                    root.reportError("Invalid upload source: " + errTransfer.error)
                    return
                }
                if (size > root.maxUploadBodyBytes) {
                    var errTransfer = { error: "Upload source exceeds maximum size of " + root.maxUploadBodyBytes + " bytes", state: "failed" }
                    root.reportError("Upload too large: " + errTransfer.error)
                    return
                }

                var nameResult = SafePath.sanitizeBasename(fileName)
                if (!nameResult.valid) {
                    var errTransfer = { error: nameResult.error, state: "failed" }
                    root.reportError("Invalid filename: " + nameResult.error)
                    return
                }

                var upload = {
                    id: Date.now() + Math.random(),
                    type: "upload",
                    state: "pending",
                    srcPath: localFilePath,
                    destUploadPath: destPath,
                    fileName: nameResult.sanitized,
                    repoId: repoId,
                    repoName: "",
                    token: token,
                    baseUrl: baseUrl,
                    process: null,
                    uploadLink: null,
                    progress: 0,
                    speed: "",
                    error: "",
                    retryCount: 0,
                    startTime: Date.now(),
                    endTime: null,
                    authHeaderFile: null,
                    curlConfigFile: null
                }

                root.transfers.push(upload)
                root.transfersChanged()
                root.getUploadLinkAndExecute(upload)
                return upload
            }
        })
        statProc.command = ["stat", "-c", "%F %s", "--", localFilePath]
        statProc.running = true
    }

    function getUploadLinkAndExecute(upload) {
        if (upload.state === "cancelled") return
        var policy = root._authUrlPolicy(upload.baseUrl)
        if (!policy.valid) {
            upload.state = "failed"
            upload.error = policy.error
            root.sanitizeForHistory(upload)
            root.transferStateChanged(upload)
            root.transfersChanged()
            return
        }
        var url = upload.baseUrl.replace(/\/+$/, "") + "/api2/repos/" + upload.repoId + "/upload-link/?p=" + encodeURIComponent(upload.destUploadPath)
        HttpTransport.get(url, { "Authorization": "Token " + upload.token, "Accept": "application/json" },
            function(success, data, error) {
                if (upload.state === "cancelled") return
                if (success) {
                    if (typeof data !== "string" || data === "") {
                        upload.state = "failed"
                        upload.error = "Invalid server response"
                        root.sanitizeForHistory(upload)
                        root.transferStateChanged(upload)
                        root.transfersChanged()
                        return
                    }
                    var vUrl = UrlPolicy.validateTransferUrl(data)
                    if (!vUrl.valid) {
                        upload.state = "failed"
                        upload.error = "Invalid upload URL: " + vUrl.error
                        root.sanitizeForHistory(upload)
                        root.transferStateChanged(upload)
                        root.transfersChanged()
                        return
                    }
                    upload.uploadLink = data
                    upload.state = "uploading"
                    root.transferStateChanged(upload)
                    root.transfersChanged()
                    root.executeCurlUpload(upload)
                } else if (root.isAuthError(error)) {
                    upload.state = "auth_failed"
                    upload.error = "Authentication failed"
                    root.sanitizeForHistory(upload)
                    root.transferStateChanged(upload)
                    root.transfersChanged()
                } else if (root.isRetryableError(0, error) && upload.retryCount < root.maxRetries) {
                    upload.retryCount++
                    var delay = Math.min(root.retryBaseDelay * Math.pow(2, upload.retryCount - 1), root.maxRetryDelay)
                    upload.state = "pending"
                    root.transferRetryStarted(upload)
                    root.transferStateChanged(upload)
                    root.transfersChanged()
                    scheduleRetry(delay, function() { root.getUploadLinkAndExecute(upload) })
                } else {
                    upload.state = "failed"
                    upload.error = error || "Upload link request failed"
                    root.sanitizeForHistory(upload)
                    root.transferStateChanged(upload)
                    root.transfersChanged()
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
                upload.state = "failed"
                upload.error = "Failed to create auth header file"
                root.sanitizeForHistory(upload)
                root.transferStateChanged(upload)
                root.transfersChanged()
                return
            }
            upload.authHeaderFile = authHeaderFile
            createCurlConfigFile(uploadUrl, function(curlConfigFile) {
                if (upload.state !== "pending" && upload.state !== "uploading") { deleteFile(curlConfigFile); return }
                if (!curlConfigFile) {
                    upload.state = "failed"
                    upload.error = "Failed to create curl configuration"
                    root.sanitizeForHistory(upload)
                    root.transferStateChanged(upload)
                    root.transfersChanged()
                    return
                }
                upload.curlConfigFile = curlConfigFile
                var curlProc = uploadProcessComponent.createObject(root)
                if (!curlProc) {
                    upload.state = "failed"
                    upload.error = "Failed to create upload process"
                    root.sanitizeForHistory(upload)
                    root.transferStateChanged(upload)
                    root.transfersChanged()
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
                upload.state = "failed"
                upload.error = "Failed to create curl configuration"
                root.sanitizeForHistory(upload)
                root.transferStateChanged(upload)
                root.transfersChanged()
                return
            }
            upload.curlConfigFile = curlConfigFile
            var curlProc = uploadProcessComponent.createObject(root)
            if (!curlProc) {
                upload.state = "failed"
                upload.error = "Failed to create upload process"
                root.sanitizeForHistory(upload)
                root.transferStateChanged(upload)
                root.transfersChanged()
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
        }
        root.transferStateChanged(upload)
        root.transfersChanged()
    }

    // ===== CANCEL (with process group kill) =====

    function cancelTransfer(transferId) {
        for (var i = 0; i < root.transfers.length; i++) {
            var t = root.transfers[i]
            if (t.id === transferId) {
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

                cleanupTransferAuthFile(t)

                root.transfers.splice(i, 1)
                root.transfersChanged()

                if (!token || !baseUrl) return false

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
            curlConfigFile: null
        }
        root.transfers.push(download)
        root.transfersChanged()
        // Recover abandoned cache entries before admitting a new persistent file.
        SafePath.evictCache(function(ok) {
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
            function(success, data, error) {
                if (download.state === "cancelled") return
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
                } else if (root.isAuthError(error)) {
                    download.state = "auth_failed"
                    download.error = "Authentication failed"
                    root.sanitizeForHistory(download)
                    root.transferStateChanged(download)
                    root.transfersChanged()
                } else if (root.isRetryableError(0, error) && download.retryCount < root.maxRetries) {
                    download.retryCount++
                    var delay = Math.min(root.retryBaseDelay * Math.pow(2, download.retryCount - 1), root.maxRetryDelay)
                    download.state = "pending"
                    root.transferRetryStarted(download)
                    root.transferStateChanged(download)
                    root.transfersChanged()
                    scheduleRetry(delay, function() { root.getDownloadLinkAndOpen(download) })
                } else {
                    download.state = "failed"
                    download.error = error || "Download link request failed"
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
            onExited: function(exitCode) {
                var t = transferRef
                destroy()
                if (!t) return
                t.process = null
                if (t.state === "cancelling") {
                    root.finishCancelled(t)
                } else if (t.state === "opening" && exitCode === 0) {
                    root.releaseOpenCache(t)
                    t.state = "completed"
                    root.sanitizeForHistory(t)
                    root.pruneHistory()
                } else if (t.state === "opening") {
                    root.releaseOpenCache(t)
                    t.state = "failed"
                    t.error = "Cached file could not be opened by the default application"
                    root.sanitizeForHistory(t)
                } else {
                    return
                }
                root.transferStateChanged(t)
                root.transfersChanged()
            }
        }
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
        proc.command = ["xdg-open", transfer.cachePath]
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
        var active = root.transfers.slice()
        for (var i = 0; i < active.length; i++) root.cancelTransfer(active[i].id)
        root.transfers = []
        root.transfersChanged()
    }
}
