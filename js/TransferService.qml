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

    // ===== SIGNALS =====

    signal transferProgressChanged(var transfer)
    signal transferStateChanged(var transfer)
    signal transferRetryStarted(var transfer)

    // ===== PROCESS FACTORY =====

    property Component downloadProcessComponent: Component {
        Process {
            property var transferRef: null
            stderr: StdioCollector {
                onTextChanged: {
                    if (transferRef && text) {
                        root.parseProgress(text, transferRef)
                        root.transferProgressChanged(transferRef)
                    }
                }
            }
            onExited: function(exitCode, exitStatus) {
                if (transferRef) {
                    root.handleDownloadExited(exitCode, transferRef)
                }
            }
        }
    }

    property Component uploadProcessComponent: Component {
        Process {
            property var transferRef: null
            stdout: StdioCollector {}
            stderr: StdioCollector {
                onTextChanged: {
                    if (transferRef && text) {
                        root.parseProgress(text, transferRef)
                        root.transferProgressChanged(transferRef)
                    }
                }
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

    function parseError(xhr) {
        try {
            var response = JSON.parse(xhr.responseText)
            if (response.non_field_errors) return response.non_field_errors.join(", ")
            if (response.detail) return response.detail
            if (response.error_msg) return response.error_msg
            return "Error " + xhr.status
        } catch (e) {
            return "Error " + xhr.status + ": " + xhr.responseText
        }
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

    function resolveDestPath(dir, fileName) {
        return dir + "/" + fileName
    }

    function curlFileForm(path) {
        return "file=@\"" + path.replace(/\\/g, "\\\\").replace(/\"/g, "\\\"") + "\""
    }

    // ===== AUTH HEADER FILE MANAGEMENT =====

    property Component _authHeaderProcessFactory: Component {
        Process {
            id: proc
            property var onDone: null
            property string inputPayload: ""
            stdinEnabled: true

            onStarted: {
                proc.write(inputPayload)
                proc.stdinEnabled = false
            }
            onExited: function(exitCode, exitStatus) {
                var cb = proc.onDone
                proc.destroy()
                if (cb) cb(exitCode)
            }
        }
    }

    property Component _deleteProcessFactory: Component {
        Process {
            id: proc
            onExited: proc.destroy()
        }
    }

    property Component _finalizeDownloadProcessFactory: Component {
        Process {
            property var transferRef: null
            onExited: function(exitCode, exitStatus) {
                var transfer = transferRef
                destroy()
                if (transfer) root.handleDownloadFinalized(exitCode, transfer)
            }
        }
    }

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

    function deleteFile(filePath) {
        if (!filePath) return
        var proc = _deleteProcessFactory.createObject(root)
        if (!proc) return
        proc.command = ["rm", "-f", "--", filePath]
        proc.running = true
    }

    function scheduleRetry(delay, callback) {
        var timer = _retryTimerFactory.createObject(root, { interval: delay, callback: callback })
        if (timer) timer.start()
    }

    function createAuthHeaderFile(token, callback) {
        var runtimeDir = Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"
        var tempFile = runtimeDir + "/seafile_auth_" + Date.now() + "_" + Math.random().toString(36).substr(2, 9) + ".txt"
        var proc = _authHeaderProcessFactory.createObject(root, {
            inputPayload: "Authorization: Token " + token,
            onDone: function(exitCode) {
                if (exitCode === 0) {
                    callback(tempFile)
                } else {
                    deleteFile(tempFile)
                    callback(null)
                }
            }
        })
        if (!proc) {
            callback(null)
            return
        }
        // Create the file under a restrictive umask before any token is written.
        proc.command = ["sh", "-c", "umask 077; cat > \"$1\"", "sh", tempFile]
        proc.running = true
    }

    function createCurlConfigFile(url, callback) {
        var runtimeDir = Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"
        var tempFile = runtimeDir + "/seafile_curl_" + Date.now() + "_" + Math.random().toString(36).substr(2, 9) + ".conf"
        var proc = _authHeaderProcessFactory.createObject(root, {
            inputPayload: "url = " + JSON.stringify(url),
            onDone: function(exitCode) {
                if (exitCode === 0) callback(tempFile)
                else { deleteFile(tempFile); callback(null) }
            }
        })
        if (!proc) { callback(null); return }
        proc.command = ["sh", "-c", "umask 077; cat > \"$1\"", "sh", tempFile]
        proc.running = true
    }

    function cleanupAuthHeaderFile(filePath) {
        deleteFile(filePath)
    }

    function cleanupTransferAuthFile(transfer) {
        if (transfer.authHeaderFile) {
            cleanupAuthHeaderFile(transfer.authHeaderFile)
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
        transfer.token = undefined
        transfer.process = null
        transfer.downloadLink = undefined
        transfer.uploadLink = undefined
        if (transfer.authHeaderFile) {
            cleanupAuthHeaderFile(transfer.authHeaderFile)
        }
        transfer.authHeaderFile = undefined
        cleanupTransferConfigFile(transfer)
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

    // ===== DOWNLOAD =====

    function startDownload(fileItem, token, baseUrl, repoId, destDir, fullPath, downloadLink) {
        var download = {
            id: Date.now() + Math.random(),
            type: "download",
            state: "pending",
            fileName: fileItem.name,
            fullPath: fullPath,
            destDir: destDir,
            destPath: "",
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
            download.downloadLink = downloadLink
            download.destPath = root.resolveDestPath(download.destDir, download.fileName)
            download.tempPath = download.destPath + ".part-" + download.id
            download.state = "downloading"
            root.transferStateChanged(download)
            root.transfersChanged()
            root.executeCurlDownload(download)
        } else {
            root.getDownloadLinkAndExecute(download)
        }
        return download
    }

    function getDownloadLinkAndExecute(download) {
        if (download.state === "cancelled") return
        var xhr = new XMLHttpRequest()
        var path = download.fullPath || "/" + download.fileName
        var url = download.baseUrl.replace(/\/+$/, "") + "/api2/repos/" + download.repoId + "/file/?p=" + encodeURIComponent(path) + "&reuse=1"
        xhr.open("GET", url, true)
        xhr.setRequestHeader("Authorization", "Token " + download.token)
        xhr.setRequestHeader("Accept", "application/json")
        xhr.timeout = 10000
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                if (download.state === "cancelled") return
                if (xhr.status >= 200 && xhr.status < 300) {
                    var link
                    try { link = JSON.parse(xhr.responseText) } catch (e) { link = null }
                    if (typeof link !== "string" || link === "") {
                        download.state = "failed"
                        download.error = "Invalid server response"
                        root.sanitizeForHistory(download)
                        root.transferStateChanged(download)
                        root.transfersChanged()
                        return
                    }
                    download.downloadLink = link
                    download.destPath = root.resolveDestPath(download.destDir, download.fileName)
                    download.tempPath = download.destPath + ".part-" + download.id
                    download.state = "downloading"
                    root.transferStateChanged(download)
                    root.transfersChanged()
                    root.executeCurlDownload(download)
                } else if (root.isAuthError(xhr.status)) {
                    download.state = "auth_failed"
                    download.error = "Authentication failed"
                    root.sanitizeForHistory(download)
                    root.transferStateChanged(download)
                    root.transfersChanged()
                } else if (root.isRetryableError(xhr.status, root.parseError(xhr)) && download.retryCount < root.maxRetries) {
                    download.retryCount++
                    var delay = Math.min(root.retryBaseDelay * Math.pow(2, download.retryCount - 1), root.maxRetryDelay)
                    download.state = "pending"
                    root.transferRetryStarted(download)
                    root.transferStateChanged(download)
                    root.transfersChanged()
                    scheduleRetry(delay, function() { root.getDownloadLinkAndExecute(download) })
                } else {
                    download.state = "failed"
                    download.error = root.parseError(xhr)
                    root.sanitizeForHistory(download)
                    root.transferStateChanged(download)
                    root.transfersChanged()
                }
            }
        }
        xhr.send()
    }

    function executeCurlDownload(download) {
        if (download.state !== "pending" && download.state !== "downloading") return
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
                curlProc.command = [
                    "curl",
                    "-q",
                    "-f",
                    "-H", "@" + authHeaderFile,
                    "-H", "Accept: */*",
                    "--progress-bar",
                    "--output", download.tempPath,
                    "--config", curlConfigFile
                ]
                download.process = curlProc
                curlProc.running = true
            })
        })
    }

    function handleDownloadExited(exitCode, download) {
        var process = download.process
        download.process = null
        if (process) process.destroy()
        cleanupTransferAuthFile(download)
        cleanupTransferConfigFile(download)

        if (download.state === "cancelled") {
            deleteFile(download.tempPath)
        } else if (exitCode === 0) {
            root.finalizeDownload(download)
            return
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
        var upload = {
            id: Date.now() + Math.random(),
            type: "upload",
            state: "pending",
            srcPath: localFilePath,
            destUploadPath: destPath,
            fileName: fileName,
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
        var xhr = new XMLHttpRequest()
        var url = upload.baseUrl.replace(/\/+$/, "") + "/api2/repos/" + upload.repoId + "/upload-link/?p=" + encodeURIComponent(upload.destUploadPath)
        xhr.open("GET", url, true)
        xhr.setRequestHeader("Authorization", "Token " + upload.token)
        xhr.setRequestHeader("Accept", "application/json")
        xhr.timeout = 10000
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                if (upload.state === "cancelled") return
                if (xhr.status >= 200 && xhr.status < 300) {
                    var link
                    try { link = JSON.parse(xhr.responseText) } catch (e) { link = null }
                    if (typeof link !== "string" || link === "") {
                        upload.state = "failed"
                        upload.error = "Invalid server response"
                        root.sanitizeForHistory(upload)
                        root.transferStateChanged(upload)
                        root.transfersChanged()
                        return
                    }
                    upload.uploadLink = link
                    upload.state = "uploading"
                    root.transferStateChanged(upload)
                    root.transfersChanged()
                    root.executeCurlUpload(upload)
                } else if (root.isAuthError(xhr.status)) {
                    upload.state = "auth_failed"
                    upload.error = "Authentication failed"
                    root.sanitizeForHistory(upload)
                    root.transferStateChanged(upload)
                    root.transfersChanged()
                } else if (root.isRetryableError(xhr.status, root.parseError(xhr)) && upload.retryCount < root.maxRetries) {
                    upload.retryCount++
                    var delay = Math.min(root.retryBaseDelay * Math.pow(2, upload.retryCount - 1), root.maxRetryDelay)
                    upload.state = "pending"
                    root.transferRetryStarted(upload)
                    root.transferStateChanged(upload)
                    root.transfersChanged()
                    scheduleRetry(delay, function() { root.getUploadLinkAndExecute(upload) })
                } else {
                    upload.state = "failed"
                    upload.error = root.parseError(xhr)
                    root.sanitizeForHistory(upload)
                    root.transferStateChanged(upload)
                    root.transfersChanged()
                }
            }
        }
        xhr.send()
    }

    function executeCurlUpload(upload) {
        if (upload.state !== "pending" && upload.state !== "uploading") return
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
            createCurlConfigFile(upload.uploadLink + (upload.uploadLink.indexOf("?") === -1 ? "?" : "&") + "ret-json=1", function(curlConfigFile) {
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
                    "curl",
                    "-q",
                    "-f",
                    "-H", "@" + authHeaderFile,
                    "-H", "Accept: application/json",
                    "--progress-bar",
                    "--form", root.curlFileForm(upload.srcPath),
                    "--form-string", "parent_dir=" + upload.destUploadPath,
                    "--form-string", "replace=0",
                    "--config", curlConfigFile
                ]
                upload.process = curlProc
                curlProc.running = true
            })
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
            if (Array.isArray(response) && response.length > 0 && typeof response[0].name === "string" && response[0].name.length > 0) {
                upload.fileName = response[0].name
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
        } else if (upload.state !== "cancelled") {
            if (process) process.destroy()
            upload.state = "failed"
            upload.error = "Upload outcome is unknown after curl failed (exit code: " + exitCode + "); verify the server before retrying"
            root.sanitizeForHistory(upload)
        }
        root.transferStateChanged(upload)
        root.transfersChanged()
    }

    // ===== CANCEL =====

    function cancelTransfer(transferId) {
        for (var i = 0; i < root.transfers.length; i++) {
            var t = root.transfers[i]
            if (t.id === transferId) {
                t.state = "cancelled"
                if (t.process) {
                    t.process.kill()
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
        var cacheDir = Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache")
        cacheDir = cacheDir + "/omarseafile"
        // Unique cache filename per open to avoid collisions and ensure fresh content
        var uniqueSuffix = Date.now() + "_" + Math.random().toString(36).substr(2, 9)
        var cachePath = cacheDir + "/" + uniqueSuffix + "_" + fileItem.name
        var tempPath = cachePath + ".part-" + Date.now()

        var download = {
            id: Date.now() + Math.random(),
            type: "download",
            state: "pending",
            fileName: fileItem.name,
            fullPath: fullPath,
            cacheDir: cacheDir,
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
    }

    function getDownloadLinkAndOpen(download) {
        if (download.state === "cancelled") return
        var xhr = new XMLHttpRequest()
        var path = download.fullPath || "/" + download.fileName
        var url = download.baseUrl.replace(/\/+$/, "") + "/api2/repos/" + download.repoId + "/file/?p=" + encodeURIComponent(path) + "&reuse=1"
        xhr.open("GET", url, true)
        xhr.setRequestHeader("Authorization", "Token " + download.token)
        xhr.setRequestHeader("Accept", "application/json")
        xhr.timeout = 10000
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                if (download.state === "cancelled") return
                if (xhr.status >= 200 && xhr.status < 300) {
                    var link
                    try { link = JSON.parse(xhr.responseText) } catch (e) { link = null }
                    if (typeof link !== "string" || link === "") {
                        download.state = "failed"
                        download.error = "Invalid server response"
                        root.sanitizeForHistory(download)
                        root.transferStateChanged(download)
                        root.transfersChanged()
                        return
                    }
                    download.downloadLink = link
                    download.state = "downloading"
                    root.transferStateChanged(download)
                    root.transfersChanged()
                    root.executeCurlOpenDownload(download)
                } else if (root.isAuthError(xhr.status)) {
                    download.state = "auth_failed"
                    download.error = "Authentication failed"
                    root.sanitizeForHistory(download)
                    root.transferStateChanged(download)
                    root.transfersChanged()
                } else if (root.isRetryableError(xhr.status, root.parseError(xhr)) && download.retryCount < root.maxRetries) {
                    download.retryCount++
                    var delay = Math.min(root.retryBaseDelay * Math.pow(2, download.retryCount - 1), root.maxRetryDelay)
                    download.state = "pending"
                    root.transferRetryStarted(download)
                    root.transferStateChanged(download)
                    root.transfersChanged()
                    root.scheduleRetry(delay, function() { root.getDownloadLinkAndOpen(download) })
                } else {
                    download.state = "failed"
                    download.error = root.parseError(xhr)
                    root.sanitizeForHistory(download)
                    root.transferStateChanged(download)
                    root.transfersChanged()
                }
            }
        }
        xhr.send()
    }

    function executeCurlOpenDownload(download) {
        if (download.state !== "pending" && download.state !== "downloading") return
        root.createAuthHeaderFile(download.token, function(authHeaderFile) {
            if (download.state !== "pending" && download.state !== "downloading") {
                root.cleanupAuthHeaderFile(authHeaderFile)
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
            root.createCurlConfigFile(download.downloadLink, function(curlConfigFile) {
                if (download.state !== "pending" && download.state !== "downloading") { root.deleteFile(curlConfigFile); return }
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
                curlProc.command = [
                    "curl",
                    "-q",
                    "-f",
                    "-H", "@" + authHeaderFile,
                    "-H", "Accept: */*",
                    "--progress-bar",
                    "--output", download.tempPath,
                    "--config", curlConfigFile
                ]
                download.process = curlProc
                curlProc.running = true
            })
        })
    }

    function handleOpenDownloadExited(exitCode, download) {
        var process = download.process
        download.process = null
        if (process) process.destroy()
        root.cleanupTransferAuthFile(download)
        root.cleanupTransferConfigFile(download)

        if (download.state === "cancelled") {
            root.deleteFile(download.tempPath)
        } else if (exitCode === 0) {
            root.finalizeOpenDownload(download)
            return
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
        var proc = _finalizeDownloadProcessFactory.createObject(root)
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
        proc.command = ["sh", "-c", "mkdir -p -m 0700 -- \"$(dirname \"$1\")\" && mv -f -- \"$1\" \"$2\" && chmod 600 -- \"$2\"", "sh", download.tempPath, download.cachePath]
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
                t.process.kill()
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
