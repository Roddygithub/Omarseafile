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
            if (t.fileName === fileItem.name && (t.fullPath === fullPath || t.fullPath === "/" + fileItem.name)) return t
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

    // ===== AUTH HEADER FILE MANAGEMENT =====

    property Component _fileViewFactory: Component {
        FileView {
            atomicWrites: true
        }
    }

    property Process _cleanupProcess: Process {}

    function createAuthHeaderFile(token) {
        var runtimeDir = Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"
        var tempFile = runtimeDir + "/seafile_auth_" + Date.now() + "_" + Math.random().toString(36).substr(2, 9) + ".txt"
        var fv = _fileViewFactory.createObject(root)
        if (!fv) return null
        fv.path = tempFile
        fv.setText("Authorization: Token " + token)
        fv.waitForJob()
        fv.destroy()
        _cleanupProcess.command = ["chmod", "600", tempFile]
        _cleanupProcess.running = true
        return tempFile
    }

    function cleanupAuthHeaderFile(filePath) {
        if (!filePath) return
        _cleanupProcess.command = ["rm", "-f", filePath]
        _cleanupProcess.running = true
    }

    function cleanupTransferAuthFile(transfer) {
        if (transfer.authHeaderFile) {
            cleanupAuthHeaderFile(transfer.authHeaderFile)
            transfer.authHeaderFile = undefined
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

    function startDownload(fileItem, token, baseUrl, repoId, destDir, fullPath) {
        var download = {
            id: Date.now() + Math.random(),
            type: "download",
            state: "pending",
            fileName: fileItem.name,
            fullPath: fullPath,
            destDir: destDir,
            destPath: "",
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
            authHeaderFile: null
        }

        root.transfers.push(download)
        root.transfersChanged()
        root.getDownloadLinkAndExecute(download)
        return download
    }

    function getDownloadLinkAndExecute(download) {
        var xhr = new XMLHttpRequest()
        var path = download.fullPath || "/" + download.fileName
        var url = download.baseUrl.replace(/\/+$/, "") + "/api2/repos/" + download.repoId + "/file/?p=" + encodeURIComponent(path) + "&reuse=1"
        xhr.open("GET", url, true)
        xhr.setRequestHeader("Authorization", "Token " + download.token)
        xhr.setRequestHeader("Accept", "application/json")
        xhr.timeout = 10000
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                if (xhr.status >= 200 && xhr.status < 300) {
                    var link = JSON.parse(xhr.responseText)
                    download.downloadLink = link
                    download.destPath = root.resolveDestPath(download.destDir, download.fileName)
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
                    setTimeout(function() { root.getDownloadLinkAndExecute(download) }, delay)
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
        var authHeaderFile = createAuthHeaderFile(download.token)
        if (!authHeaderFile) {
            download.state = "failed"
            download.error = "Failed to create auth header file"
            root.sanitizeForHistory(download)
            root.transferStateChanged(download)
            root.transfersChanged()
            return
        }
        download.authHeaderFile = authHeaderFile

        var curlProc = downloadProcessComponent.createObject(root)
        if (!curlProc) {
            download.state = "failed"
            download.error = "Failed to create download process"
            root.sanitizeForHistory(download)
            root.transferStateChanged(download)
            root.transfersChanged()
            cleanupAuthHeaderFile(authHeaderFile)
            download.authHeaderFile = undefined
            return
        }

        curlProc.transferRef = download
        curlProc.command = [
            "curl",
            "-L",
            "-f",
            "-H", "@" + authHeaderFile,
            "-H", "Accept: */*",
            "--progress-bar",
            "--output", download.destPath,
            download.downloadLink
        ]

        download.process = curlProc
        curlProc.running = true
    }

    function handleDownloadExited(exitCode, download) {
        cleanupTransferAuthFile(download)

        if (exitCode === 0) {
            download.state = "completed"
            download.progress = 1.0
            download.speed = ""
            root.sanitizeForHistory(download)
            root.pruneHistory()
        } else if (download.state !== "cancelled") {
            if (download.retryCount < root.maxRetries) {
                download.retryCount++
                var delay = Math.min(root.retryBaseDelay * Math.pow(2, download.retryCount - 1), root.maxRetryDelay)
                download.state = "pending"
                root.transferRetryStarted(download)
                root.transferStateChanged(download)
                root.transfersChanged()
                setTimeout(function() { root.executeCurlDownload(download) }, delay)
                return
            }
            download.state = "failed"
            download.error = "Download failed (exit code: " + exitCode + ")"
            root.sanitizeForHistory(download)
            Qt.callLater(function() { Qt.deleteFile(download.destPath) })
        }
        download.process = null
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
            authHeaderFile: null
        }

        root.transfers.push(upload)
        root.transfersChanged()
        root.getUploadLinkAndExecute(upload)
        return upload
    }

    function getUploadLinkAndExecute(upload) {
        var xhr = new XMLHttpRequest()
        var url = upload.baseUrl.replace(/\/+$/, "") + "/api2/repos/" + upload.repoId + "/upload-link/?p=" + encodeURIComponent(upload.destUploadPath)
        xhr.open("GET", url, true)
        xhr.setRequestHeader("Authorization", "Token " + upload.token)
        xhr.setRequestHeader("Accept", "application/json")
        xhr.timeout = 10000
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                if (xhr.status >= 200 && xhr.status < 300) {
                    var link = JSON.parse(xhr.responseText)
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
                    setTimeout(function() { root.getUploadLinkAndExecute(upload) }, delay)
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
        var authHeaderFile = createAuthHeaderFile(upload.token)
        if (!authHeaderFile) {
            upload.state = "failed"
            upload.error = "Failed to create auth header file"
            root.sanitizeForHistory(upload)
            root.transferStateChanged(upload)
            root.transfersChanged()
            return
        }
        upload.authHeaderFile = authHeaderFile

        var curlProc = uploadProcessComponent.createObject(root)
        if (!curlProc) {
            upload.state = "failed"
            upload.error = "Failed to create upload process"
            root.sanitizeForHistory(upload)
            root.transferStateChanged(upload)
            root.transfersChanged()
            cleanupAuthHeaderFile(authHeaderFile)
            upload.authHeaderFile = undefined
            return
        }

        curlProc.transferRef = upload
        curlProc.command = [
            "curl",
            "-L",
            "-f",
            "-H", "@" + authHeaderFile,
            "-H", "Accept: application/json",
            "--progress-bar",
            "-F", "file=@" + upload.srcPath,
            "-F", "parent_dir=" + upload.destUploadPath,
            "-F", "replace=0",
            upload.uploadLink + "?ret-json=1"
        ]

        upload.process = curlProc
        curlProc.running = true
    }

    function handleUploadExited(exitCode, upload) {
        cleanupTransferAuthFile(upload)

        if (exitCode === 0) {
            upload.state = "completed"
            upload.progress = 1.0
            upload.speed = ""
            root.sanitizeForHistory(upload)
            root.pruneHistory()
        } else if (upload.state !== "cancelled") {
            if (upload.retryCount < root.maxRetries) {
                upload.retryCount++
                var delay = Math.min(root.retryBaseDelay * Math.pow(2, upload.retryCount - 1), root.maxRetryDelay)
                upload.state = "pending"
                root.transferRetryStarted(upload)
                root.transferStateChanged(upload)
                root.transfersChanged()
                setTimeout(function() { root.executeCurlUpload(upload) }, delay)
                return
            }
            upload.state = "failed"
            upload.error = "Upload failed (exit code: " + exitCode + ")"
            root.sanitizeForHistory(upload)
        }
        upload.process = null
        root.transferStateChanged(upload)
        root.transfersChanged()
    }

    // ===== CANCEL =====

    function cancelTransfer(transferId) {
        for (var i = 0; i < root.transfers.length; i++) {
            var t = root.transfers[i]
            if (t.id === transferId) {
                if (t.process) {
                    t.state = "cancelled"
                    t.process.running = false
                    t.process = null
                    if (t.destPath && t.type === "download") {
                        Qt.callLater(function() { Qt.deleteFile(t.destPath) })
                    }
                }
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

    // ===== LOGOUT CLEANUP =====

    function logoutCleanup() {
        for (var i = 0; i < root.transfers.length; i++) {
            var t = root.transfers[i]
            if (t.process) {
                t.state = "cancelled"
                t.process.kill()
                t.process = null
                if (t.destPath && t.type === "download") {
                    Qt.callLater(function() { Qt.deleteFile(t.destPath) })
                }
            }
            cleanupTransferAuthFile(t)
        }
        root.transfers = []
        root.transfersChanged()
    }
}