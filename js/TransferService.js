import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root

    property var activeTransfers: []

    property int maxRetries: 3
    property int retryBaseDelay: 2000
    property int maxRetryDelay: 30000

    // ===== COMMON =====

    function cancelTransfer(transferId) {
        for (var i = 0; i < root.activeTransfers.length; i++) {
            var t = root.activeTransfers[i]
            if (t.id === transferId) {
                if (t.process) {
                    t.state = "cancelled"
                    t.process.kill()
                    t.process = null
                    if (t.destPath && t.type === "download") Qt.callLater(function() { Qt.deleteFile(t.destPath) })
                }
                transferProgressChanged(t)
                return true
            }
        }
        return false
    }

    function transferProgressChanged(transfer) {
        // Signal handled by Panel.qml via property binding
    }

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
        if (status === 0) return true // network error
        if (status === 408) return true // timeout
        if (status >= 500 && status < 600) return true // server errors
        if (errorMsg && errorMsg.includes("network")) return true
        if (errorMsg && errorMsg.includes("timeout")) return true
        if (errorMsg && errorMsg.includes("connection")) return true
        return false
    }

    function isAuthError(status) {
        return status === 401 || status === 403
    }

    function getActiveTransfers() {
        return root.activeTransfers.filter(function(t) {
            return t.state === "downloading" || t.state === "uploading" || t.state === "pending"
        })
    }

    function clearCompleted() {
        root.activeTransfers = root.activeTransfers.filter(function(t) {
            return t.state === "downloading" || t.state === "uploading" || t.state === "pending"
        })
    }

    // ===== DOWNLOAD =====

    function startDownload(fileItem, token, baseUrl, repoId, destDir, fullPath) {
        var download = {
            id: Date.now() + Math.random(),
            type: "download",
            fileItem: fileItem,
            token: token,
            baseUrl: baseUrl,
            repoId: repoId,
            destDir: destDir,
            fullPath: fullPath,
            state: "pending",
            bytesReceived: 0,
            bytesTotal: 0,
            progress: 0,
            speed: 0,
            error: "",
            process: null,
            startTime: Date.now(),
            fileName: fileItem.name,
            destPath: "",
            retryCount: 0
        }

        root.activeTransfers.push(download)
        root.getDownloadLinkAndExecute(download)
        return download
    }

    function getDownloadLinkAndExecute(download) {
        var xhr = new XMLHttpRequest()
        var path = download.fullPath || "/" + download.fileItem.name
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
                    transferProgressChanged(download)
                    root.executeCurlDownload(download)
                } else if (root.isAuthError(xhr.status)) {
                    download.state = "auth_failed"
                    download.error = "Authentication failed"
                    transferProgressChanged(download)
                } else if (root.isRetryableError(xhr.status, root.parseError(xhr)) && download.retryCount < 3) {
                    download.retryCount++
                    var delay = Math.min(2000 * Math.pow(2, download.retryCount - 1), 30000)
                    setTimeout(function() { root.getDownloadLinkAndExecute(download) }, delay)
                } else {
                    download.state = "failed"
                    download.error = root.parseError(xhr)
                    transferProgressChanged(download)
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
                transferProgressChanged(download)
            }
        }

        curlProc.onExited: function(exitCode) {
            if (exitCode === 0) {
                download.state = "completed"
                download.bytesReceived = download.bytesTotal
                download.progress = 1.0
            } else if (download.state !== "cancelled") {
                if (download.retryCount < 3) {
                    download.retryCount++
                    var delay = Math.min(2000 * Math.pow(2, download.retryCount - 1), 30000)
                    setTimeout(function() { root.executeCurlDownload(download) }, delay)
                    return
                }
                download.state = "failed"
                download.error = "Download failed (exit code: " + exitCode + ")"
                Qt.callLater(function() { Qt.deleteFile(download.destPath) })
            }
            download.process = null
            transferProgressChanged(download)
        }

        curlProc.run()
    }

    // ===== UPLOAD =====

    function startUpload(localFilePath, token, baseUrl, repoId, destPath, fileName) {
        var upload = {
            id: Date.now() + Math.random(),
            type: "upload",
            srcPath: localFilePath,
            token: token,
            baseUrl: baseUrl,
            repoId: repoId,
            destPath: destPath,
            fileName: fileName,
            state: "pending",
            bytesSent: 0,
            bytesTotal: 0,
            progress: 0,
            speed: 0,
            error: "",
            process: null,
            startTime: Date.now(),
            retryCount: 0
        }

        root.activeTransfers.push(upload)
        root.getUploadLinkAndExecute(upload)
        return upload
    }

    function getUploadLinkAndExecute(upload) {
        var xhr = new XMLHttpRequest()
        var url = upload.baseUrl + "/api2/repos/" + upload.repoId + "/upload-link/?p=" + encodeURIComponent(upload.destPath)
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
                    transferProgressChanged(upload)
                    root.executeCurlUpload(upload)
                } else if (root.isAuthError(xhr.status)) {
                    upload.state = "auth_failed"
                    upload.error = "Authentication failed"
                    transferProgressChanged(upload)
                } else if (root.isRetryableError(xhr.status, root.parseError(xhr)) && upload.retryCount < 3) {
                    upload.retryCount++
                    var delay = Math.min(2000 * Math.pow(2, upload.retryCount - 1), 30000)
                    setTimeout(function() { root.getUploadLinkAndExecute(upload) }, delay)
                } else {
                    upload.state = "failed"
                    upload.error = root.parseError(xhr)
                    transferProgressChanged(upload)
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
                "-F", "parent_dir=" + upload.destPath,
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
                transferProgressChanged(upload)
            }
        }

        curlProc.onExited: function(exitCode) {
            if (exitCode === 0) {
                upload.state = "completed"
                upload.bytesSent = upload.bytesTotal
                upload.progress = 1.0
            } else if (upload.state !== "cancelled") {
                if (upload.retryCount < 3) {
                    upload.retryCount++
                    var delay = Math.min(2000 * Math.pow(2, upload.retryCount - 1), 30000)
                    setTimeout(function() { root.executeCurlUpload(upload) }, delay)
                    return
                }
                upload.state = "failed"
                upload.error = "Upload failed (exit code: " + exitCode + ")"
            }
            upload.process = null
            transferProgressChanged(upload)
        }

        curlProc.run()
    }

    function cancelTransfer(transferId) {
        for (var i = 0; i < root.activeTransfers.length; i++) {
            var t = root.activeTransfers[i]
            if (t.id === transferId) {
                if (t.process) {
                    t.state = "cancelled"
                    t.process.kill()
                    t.process = null
                    if (t.destPath && t.type === "download") Qt.callLater(function() { Qt.deleteFile(t.destPath) })
                }
                transferProgressChanged(t)
                return true
            }
        }
        return false
    }

    function transferProgressChanged(transfer) {
        // Signal handled by Panel.qml via property binding
    }

    function parseProgress(line, transfer) {
        var match = line.match(/(\d+\.?\d*)%/)
        if (match) {
            var pct = parseFloat(match[1]) / 100.0
            transfer.progress = pct
        }

        var speedMatch = line.match(/(\d+\.?\d*)\s*([KMGT]?B\/s)/)
        if (speedMatch) {
            transfer.speed = speedMatch[1] + " " + speedMatch[2]
        }
    }

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
        if (status === 0) return true // network error
        if (status === 408) return true // timeout
        if (status >= 500 && status < 600) return true // server errors
        if (errorMsg && errorMsg.includes("network")) return true
        if (errorMsg && errorMsg.includes("timeout")) return true
        if (errorMsg && errorMsg.includes("connection")) return true
        return false
    }

    function isAuthError(status) {
        return status === 401 || status === 403
    }

    function getActiveTransfers() {
        return root.activeTransfers.filter(function(t) {
            return t.state === "downloading" || t.state === "uploading" || t.state === "pending"
        })
    }

    function clearCompleted() {
        root.activeTransfers = root.activeTransfers.filter(function(t) {
            return t.state === "downloading" || t.state === "uploading" || t.state === "pending"
        })
    }
}