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
    property int connectTimeoutMs: 10000
    property int totalTimeoutMs: 30 * 60 * 1000
    property int stallSpeedBytes: 1
    property int stallTimeMs: 30000
    readonly property int maxTransferStderrBytes: 65536
    readonly property string _transferOutputHelper: Qt.resolvedUrl("../scripts/transfer_output.py").toString().replace(/^file:\/\//, "")

    // ===== SIGNALS =====

    signal transferProgressChanged(var transfer)
    signal transferStateChanged(var transfer)
    signal transferRetryStarted(var transfer)

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
            if (t.state !== "pending" && t.state !== "downloading" && t.state !== "uploading") continue
            if (t.repoId === fileItem.repoId && t.fileName === fileItem.name && (t.fullPath === fullPath || t.fullPath === "/" + fileItem.name)) return t
        }
        return null
    }

    function getActiveTransfers() {
        return root.transfers.filter(function(t) {
            return t.state === "pending" || t.state === "downloading" || t.state === "uploading"
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

    function deleteFile(filePath) {
        if (!filePath) return
        Qt.createComponent("dummy").createObject({ command: ["rm", "-f", "--", filePath], running: true })
    }

    function scheduleRetry(delay, callback) {
        var timer = _retryTimerFactory.createObject(root, { interval: delay, callback: callback })
        if (timer) timer.start()
    }

    // ===== SECURE HEADER/CONFIG FILE CREATION =====

    function createAuthHeaderFile(token, callback) {
        SafePath.getRuntimeSubdir("secrets", function(runtimeResult) {
            if (!runtimeResult.valid) { callback(null); return }
            SafePath.createSecureFile(runtimeResult.path, "seafile_auth", "Authorization: Token " + token, callback)
        })
    }

    function createCurlConfigFile(url, callback) {
        SafePath.getRuntimeSubdir("secrets", function(runtimeResult) {
            if (!runtimeResult.valid) { callback(null); return }
            SafePath.createSecureFile(runtimeResult.path, "seafile_curl", "url = " + JSON.stringify(url), callback)
        })
    }

    function cleanupAuthHeaderFile(filePath) {
        Qt.createComponent("dummy").createObject({ command: ["rm", "-f", "--", filePath], running: true })
    }

    function cleanupTransferAuthFile(transfer) {
        if (transfer.authHeaderFile) {
            Qt.createComponent("dummy").createObject({ command: ["rm", "-f", "--", transfer.authHeaderFile], running: true })
            transfer.authHeaderFile = undefined
        }
    }

    function cleanupTransferConfigFile(transfer) {
        if (transfer.curlConfigFile) {
            Qt.createComponent("dummy").createObject({ command: ["rm", "-f", "--", transfer.curlConfigFile], running: true })
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
        transfer.token = undefined
        transfer.process = null
        transfer.downloadLink = undefined
        transfer.uploadLink = undefined
        if (transfer.authHeaderFile) {
            Qt.createComponent("dummy").createObject({ command: ["rm", "-f", "--", transfer.authHeaderFile], running: true })
        }
        transfer.authHeaderFile = undefined
        if (transfer.curlConfigFile) {
            Qt.createComponent("dummy").createObject({ command: ["rm", "-f", "--", transfer.curlConfigFile], running: true })
        }
        transfer.curlConfigFile = undefined
        transfer.endTime = Date.now()
        return transfer
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
                root.showToast("Invalid destination: " + destResult.error, "error")
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
                    download.state = "failed"
                    download.error = "Failed to create download process"
                    root.sanitizeForHistory(download)
                    root.transferStateChanged(download)
                    root.transfersChanged()
                    return
                }
                curlProc.transferRef = download
                var scriptsBase = Qt.resolvedUrl("../scripts")
                var outputHelper = scriptsBase + "/secure_output.py"
                curlProc.command = [
                    "setsid", "python3",
                    outputHelper.replace(/^file:\/\//, ""),
                    download.destDir, "dl",
                    "--max-stderr-bytes", root.maxTransferStderrBytes,
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
                download.state = "failed"
                download.error = "Failed to create download process"
                root.sanitizeForHistory(download)
                root.transferStateChanged(download)
                root.transfersChanged()
                return
            }
            curlProc.transferRef = download
            var scriptsBase = Qt.resolvedUrl("../scripts")
            var outputHelper = scriptsBase + "/secure_output.py"
            curlProc.command = [
                "setsid", "python3",
                outputHelper.replace(/^file:\/\//, ""),
                download.destDir, "dl",
                "--max-stderr-bytes", root.maxTransferStderrBytes,
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

        if (download.state === "cancelled") {
            deleteFile(download.tempPath)
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
        if (download.state === "cancelled") {
            deleteFile(download.tempPath)
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
        var nameResult = SafePath.sanitizeBasename(fileName)
        if (!nameResult.valid) {
            var errTransfer = { error: nameResult.error, state: "failed" }
            root.showToast("Invalid filename: " + nameResult.error, "error")
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

    function getUploadLinkAndExecute(upload) {
        if (upload.state === "cancelled") return
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

        if (upload.state === "cancelled") {
            if (process) process.destroy()
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
                t.state = "cancelled"
                if (t.process) {
                    try {
                        var pgid = t.process.pgid
                        if (pgid > 0) {
                            var killProc = Qt.createComponent("dummy").createObject({ command: ["kill", "-TERM", "-" + pgid], running: true })
                        } else {
                            t.process.kill()
                        }
                    } catch (e) {
                        try { t.process.kill() } catch (e) {}
                    }
                    t.process.destroy()
                    t.process = null
                }
                if (t.type === "download" && t.tempPath) deleteFile(t.tempPath)
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
            return t.state === "pending" || t.state === "downloading" || t.state === "uploading"
        })
        root.transfersChanged()
    }

    // ===== OPEN FILE (DOWNLOAD TO CACHE + XDG-OPEN) =====

    function startOpen(fileItem, token, baseUrl, repoId, fullPath) {
        SafePath.getRuntimeSubdir("cache", function(cacheResult) {
            if (!cacheResult.valid) {
                root.showToast("Cache directory unavailable: " + cacheResult.error, "error")
                return
            }
            SafePath.secureJoin(cacheResult.path, fileItem.name, function(nameResult) {
                if (!nameResult.valid) {
                    root.showToast("Invalid filename: " + nameResult.error, "error")
                    return
                }
                var uniqueSuffix = Date.now() + "_" + Math.random().toString(36).substr(2, 9)
                var cachePath = cacheResult.path + "/" + uniqueSuffix + "_" + nameResult.sanitized
                var tempPath = ""

                var download = {
                    id: Date.now() + Math.random(),
                    type: "download",
                    state: "pending",
                    fileName: fileItem.name,
                    fullPath: fullPath,
                    cacheDir: cacheResult.path,
                    cachePath: cachePath,
                    tempPath: tempPath,
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
                root.getDownloadLinkAndOpen(download)

                return download
            })
        })
    }

    function getDownloadLinkAndOpen(download) {
        if (download.state === "cancelled") return
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
                    download.state = "failed"
                    download.error = "Failed to create download process"
                    root.sanitizeForHistory(download)
                    root.transferStateChanged(download)
                    root.transfersChanged()
                    return
                }
                curlProc.transferRef = download
                var scriptsBase = Qt.resolvedUrl("../scripts")
                var outputHelper = scriptsBase + "/secure_output.py"
                curlProc.command = [
                    "setsid", "python3",
                    outputHelper.replace(/^file:\/\//, ""),
                    download.cacheDir, "dl",
                    "--max-stderr-bytes", root.maxTransferStderrBytes,
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
                download.state = "failed"
                download.error = "Failed to create download process"
                root.sanitizeForHistory(download)
                root.transferStateChanged(download)
                root.transfersChanged()
                return
            }
            curlProc.transferRef = download
            var scriptsBase = Qt.resolvedUrl("../scripts")
            var outputHelper = scriptsBase + "/secure_output.py"
            curlProc.command = [
                "setsid", "python3",
                outputHelper.replace(/^file:\/\//, ""),
                download.cacheDir, "dl",
                "--max-stderr-bytes", root.maxTransferStderrBytes,
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

        if (download.state === "cancelled") {
            root.deleteFile(download.tempPath)
        } else if (exitCode === 0) {
            var validation = root.validateHelperOutput(outText, "dl")
            if (!validation.valid) {
                download.state = "failed"
                download.error = "Invalid helper output: " + validation.error
                root.sanitizeForHistory(download)
            } else {
                var tempPath = download.cacheDir + "/" + validation.basename
                download.tempPath = tempPath
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
            root.deleteFile(download.tempPath)
            root.sanitizeForHistory(download)
            root.transferStateChanged(download)
            root.transfersChanged()
            return
        }
        proc.transferRef = download
        // Non-overwriting move: mv -n (do not overwrite existing file)
        // The cache target should be unique; collision is treated as failure.
        proc.command = ["sh", "-c", "mkdir -p -m 0700 -- \"$(dirname \"$2\")\" && mv -n -- \"$1\" \"$2\" && test ! -e \"$1\" && chmod 600 -- \"$2\"", "sh", download.tempPath, download.cachePath]
        download.process = proc
        proc.running = true
    }

    function handleOpenDownloadFinalized(exitCode, download) {
        download.process = null
        if (download.state === "cancelled") {
            root.deleteFile(download.tempPath)
        } else if (exitCode === 0) {
            download.state = "completed"
            download.progress = 1.0
            download.speed = ""
            download.destPath = download.cachePath
            root.sanitizeForHistory(download)
            root.pruneHistory()
            root.openCachedFile(download)
        } else {
            download.state = "failed"
            download.error = "Cache file already exists or could not be finalized"
            root.deleteFile(download.tempPath)
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
                if (exitCode !== 0 && t) {
                    // Error surfaced by caller via transfer error state
                }
            }
        }
    }

    function openCachedFile(transfer) {
        var proc = openCachedFileComponent.createObject(root)
        if (!proc) return
        proc.command = ["xdg-open", transfer.cachePath]
        proc.transferRef = transfer
        proc.running = true
    }

    // ===== LOGOUT CLEANUP =====

    function logoutCleanup() {
        for (var i = 0; i < root.transfers.length; i++) {
            var t = root.transfers[i]
            t.state = "cancelled"
            if (t.process) {
                try {
                    var pgid = t.process.pgid
                    if (pgid > 0) {
                        Qt.createComponent("dummy").createObject({ command: ["kill", "-TERM", "-" + pgid], running: true })
                    } else {
                        t.process.kill()
                    }
                } catch (e) {
                    try { t.process.kill() } catch (e) {}
                }
                t.process.destroy()
                t.process = null
            }
            if (t.type === "download" && t.tempPath) deleteFile(t.tempPath)
            root.sanitizeForHistory(t)
        }
        root.transfers = []
        root.transfersChanged()
    }
}
