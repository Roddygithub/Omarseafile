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

    signal transfersChanged()
    signal transferProgressChanged(var transfer)
    signal transferStateChanged(var transfer)
    signal transferRetryStarted(var transfer)

    // ===== DERIVED QUERIES =====

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
        var baseName = fileName
        var ext = ""
        var dotIndex = fileName.lastIndexOf(".")
        if (dotIndex > 0) {
            baseName = fileName.substring(0, dotIndex)
            ext = fileName.substring(dotIndex)
        }
        var finalName = fileName
        var counter = 1
        while (Qt.fileExists(dir + "/" + finalName)) {
            finalName = baseName + " (" + counter + ")" + ext
            counter++
        }
        return dir + "/" + finalName
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
            endTime: null
        }

        root.transfers.push(download)
        root.transfersChanged()
        root.getDownloadLinkAndExecute(download)
        return download
    }

    function getDownloadLinkAndExecute(download) {
        var xhr = new XMLHttpRequest()
        var path = download.fullPath || "/" + download.fileName
        var url = download.baseUrl + "/api2/repos/" + download.repoId + "/file/?p=" + encodeURIComponent(path) + "&reuse=1"
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
        var curlProc = Process {
            command: [
                "curl",
                "-L",
                "-f",
                "-H", "Authorization: Token " + download.token,
                "-H", "Accept: */*",
                "--progress-bar",
                "--output", download.destPath,
                download.downloadLink
            ]
            stderrEnabled: true
        }

        download.process = curlProc

        curlProc.onStdErrChanged: {
            var stderr = curlProc.stderr
            if (stderr) {
                root.parseProgress(stderr, download)
                root.transferProgressChanged(download)
            }
        }

        curlProc.onExited: function(exitCode) {
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

        curlProc.run()
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
            endTime: null
        }

        root.transfers.push(upload)
        root.transfersChanged()
        root.getUploadLinkAndExecute(upload)
        return upload
    }

    function getUploadLinkAndExecute(upload) {
        var xhr = new XMLHttpRequest()
        var url = upload.baseUrl + "/api2/repos/" + upload.repoId + "/upload-link/?p=" + encodeURIComponent(upload.destUploadPath)
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
        var curlProc = Process {
            command: [
                "curl",
                "-L",
                "-f",
                "-H", "Authorization: Token " + upload.token,
                "-H", "Accept: application/json",
                "--progress-bar",
                "-F", "file=@" + upload.srcPath,
                "-F", "parent_dir=" + upload.destUploadPath,
                "-F", "replace=0",
                upload.uploadLink + "?ret-json=1"
            ]
            stderrEnabled: true
        }

        upload.process = curlProc

        curlProc.onStdErrChanged: {
            var stderr = curlProc.stderr
            if (stderr) {
                root.parseProgress(stderr, upload)
                root.transferProgressChanged(upload)
            }
        }

        curlProc.onExited: function(exitCode) {
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

        curlProc.run()
    }

    // ===== CANCEL =====

    function cancelTransfer(transferId) {
        for (var i = 0; i < root.transfers.length; i++) {
            var t = root.transfers[i]
            if (t.id === transferId) {
                if (t.process) {
                    t.state = "cancelled"
                    t.process.kill()
                    t.process = null
                    if (t.destPath && t.type === "download") {
                        Qt.callLater(function() { Qt.deleteFile(t.destPath) })
                    }
                }
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
        root.transfers = root.transfers.filter(function(t) {
            return t.state !== "completed"
        })
        root.transfersChanged()
    }

    function clearFailed() {
        root.transfers = root.transfers.filter(function(t) {
            return t.state !== "failed" && t.state !== "cancelled" && t.state !== "auth_failed"
        })
        root.transfersChanged()
    }

    function clearAllTerminal() {
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
        }
        root.transfers = []
        root.transfersChanged()
    }
}
