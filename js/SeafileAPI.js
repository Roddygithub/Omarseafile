import QtQuick

QtObject {
    id: root

    property string baseUrl: ""
    property string token: ""

    function setBaseUrl(url) {
        baseUrl = url.replace(/\/+$/, "")
    }

    function setToken(t) {
        token = t
    }

    function auth(username, password, callback) {
        var xhr = new XMLHttpRequest()
        var url = baseUrl + "/api2/auth-token/"
        xhr.open("POST", url, true)
        xhr.setRequestHeader("Content-Type", "application/x-www-form-urlencoded")
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                if (xhr.status === 200) {
                    var response = JSON.parse(xhr.responseText)
                    callback(true, response.token, null)
                } else {
                    var error = parseError(xhr)
                    callback(false, null, error)
                }
            }
        }
        xhr.send("username=" + encodeURIComponent(username) + "&password=" + encodeURIComponent(password))
    }

    function listLibraries(callback) {
        request("GET", "/api2/repos/", null, function(success, data, error) {
            if (success) {
                var libraries = data.map(function(repo) {
                    return {
                        id: repo.id,
                        name: repo.name,
                        size: repo.size,
                        sizeFormatted: repo.size_formatted,
                        mtime: repo.mtime,
                        permission: repo.permission,
                        encrypted: repo.encrypted
                    }
                })
                callback(true, libraries, null)
            } else {
                callback(false, null, error)
            }
        })
    }

    function listFolder(repoId, path, callback) {
        var url = "/api2/repos/" + repoId + "/dir/"
        if (path && path !== "/") {
            url += "?p=" + encodeURIComponent(path)
        }
        request("GET", url, null, function(success, data, error) {
            if (success) {
                var items = data.map(function(item) {
                    return {
                        type: item.type,
                        name: item.name,
                        id: item.id,
                        mtime: item.mtime,
                        permission: item.permission,
                        size: item.size || 0,
                        starred: item.starred || false
                    }
                })
                items.sort(function(a, b) {
                    if (a.type !== b.type) return a.type === "dir" ? -1 : 1
                    return a.name.localeCompare(b.name)
                })
                callback(true, items, null)
            } else {
                callback(false, null, error)
            }
        })
    }

    function getDownloadLink(repoId, path, reuse, callback) {
        var url = "/api2/repos/" + repoId + "/file/?p=" + encodeURIComponent(path)
        if (reuse) url += "&reuse=1"
        request("GET", url, null, function(success, data, error) {
            if (success) {
                callback(true, data, null)
            } else {
                callback(false, null, error)
            }
        })
    }

    function createFolder(repoId, parentPath, folderName, token, callback) {
        var url = "/api/v2.1/repos/" + repoId + "/dir/?p=" + encodeURIComponent(parentPath)
        var xhr = new XMLHttpRequest()
        xhr.open("POST", url, true)
        xhr.setRequestHeader("Authorization", "Token " + token)
        xhr.setRequestHeader("Content-Type", "application/x-www-form-urlencoded")
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                if (xhr.status >= 200 && xhr.status < 300) {
                    callback(true, null)
                } else {
                    callback(false, parseError(xhr))
                }
            }
        }
        xhr.send("operation=mkdir&dir_name=" + encodeURIComponent(folderName))
    }

    function renameFile(repoId, filePath, newName, token, callback) {
        var url = "/api/v2.1/repos/" + repoId + "/file/?p=" + encodeURIComponent(filePath)
        var xhr = new XMLHttpRequest()
        xhr.open("POST", url, true)
        xhr.setRequestHeader("Authorization", "Token " + token)
        xhr.setRequestHeader("Content-Type", "application/x-www-form-urlencoded")
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                if (xhr.status >= 200 && xhr.status < 300) {
                    callback(true, null)
                } else {
                    callback(false, parseError(xhr))
                }
            }
        }
        xhr.send("operation=rename&oldname=" + encodeURIComponent(filePath) + "&newname=" + encodeURIComponent(newName))
    }

    function renameFolder(repoId, parentPath, oldName, newName, token, callback) {
        var url = "/api/v2.1/repos/" + repoId + "/dir/?p=" + encodeURIComponent(parentPath)
        var xhr = new XMLHttpRequest()
        xhr.open("POST", url, true)
        xhr.setRequestHeader("Authorization", "Token " + token)
        xhr.setRequestHeader("Content-Type", "application/x-www-form-urlencoded")
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                if (xhr.status >= 200 && xhr.status < 300) {
                    callback(true, null)
                } else {
                    callback(false, parseError(xhr))
                }
            }
        }
        xhr.send("operation=rename&oldname=" + encodeURIComponent(oldName) + "&newname=" + encodeURIComponent(newName))
    }

    function moveFile(repoId, filePath, destPath, token, callback) {
        var url = "/api/v2.1/repos/" + repoId + "/file/?p=" + encodeURIComponent(filePath)
        var xhr = new XMLHttpRequest()
        xhr.open("POST", url, true)
        xhr.setRequestHeader("Authorization", "Token " + token)
        xhr.setRequestHeader("Content-Type", "application/x-www-form-urlencoded")
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                if (xhr.status >= 200 && xhr.status < 300) {
                    callback(true, null)
                } else {
                    callback(false, parseError(xhr))
                }
            }
        }
        xhr.send("operation=move&dst_repo=" + encodeURIComponent(repoId) + "&dst_dir=" + encodeURIComponent(destPath))
    }

    function deleteFile(repoId, filePath, token, callback) {
        var url = "/api/v2.1/repos/" + repoId + "/file/?p=" + encodeURIComponent(filePath)
        var xhr = new XMLHttpRequest()
        xhr.open("DELETE", url, true)
        xhr.setRequestHeader("Authorization", "Token " + token)
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                if (xhr.status >= 200 && xhr.status < 300) {
                    callback(true, null)
                } else {
                    callback(false, parseError(xhr))
                }
            }
        }
        xhr.send()
    }

    function deleteFolder(repoId, folderPath, token, callback) {
        var url = "/api2/repos/" + repoId + "/dir/?p=" + encodeURIComponent(folderPath)
        var xhr = new XMLHttpRequest()
        xhr.open("DELETE", url, true)
        xhr.setRequestHeader("Authorization", "Token " + token)
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                if (xhr.status >= 200 && xhr.status < 300) {
                    callback(true, null)
                } else {
                    callback(false, parseError(xhr))
                }
            }
        }
        xhr.send()
    }

    function moveFolder(repoId, folderName, srcParentPath, destRepoId, destParentPath, token, callback) {
        var url = "/api/v2.1/repos/async-batch-move-item/"
        var xhr = new XMLHttpRequest()
        xhr.open("POST", url, true)
        xhr.setRequestHeader("Authorization", "Token " + token)
        xhr.setRequestHeader("Content-Type", "application/json")
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                if (xhr.status >= 200 && xhr.status < 300) {
                    callback(true, null)
                } else {
                    callback(false, parseError(xhr))
                }
            }
        }
        var body = JSON.stringify({
            src_repo_id: repoId,
            src_parent_dir: srcParentPath,
            src_dirents: [folderName],
            dst_repo_id: destRepoId,
            dst_parent_dir: destParentPath
        })
        xhr.send(body)
    }

    function getDownloadLink(repoId, path, reuse, callback) {
        var url = "/api2/repos/" + repoId + "/file/?p=" + encodeURIComponent(path)
        if (reuse) url += "&reuse=1"
        request("GET", url, null, function(success, data, error) {
            if (success) {
                callback(true, data, null)
            } else {
                callback(false, null, error)
            }
        })
    }

    function request(method, path, body, callback) {
        if (!token) {
            callback(false, null, "No authentication token")
            return
        }
        var xhr = new XMLHttpRequest()
        var url = baseUrl + path
        xhr.open(method, url, true)
        xhr.setRequestHeader("Authorization", "Token " + token)
        xhr.setRequestHeader("Accept", "application/json")
        if (body && method !== "GET") {
            xhr.setRequestHeader("Content-Type", "application/json")
        }
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                if (xhr.status >= 200 && xhr.status < 300) {
                    var data = xhr.responseText ? JSON.parse(xhr.responseText) : null
                    callback(true, data, null)
                } else {
                    var error = parseError(xhr)
                    callback(false, null, error)
                }
            }
        }
        xhr.send(body ? JSON.stringify(body) : null)
    }

    // ===== SHARE LINKS =====

    function listShareLinks(repoId, path, callback) {
        var url = "/api/v2.1/share-links/?repo_id=" + encodeURIComponent(repoId)
        if (path) {
            url += "&path=" + encodeURIComponent(path)
        }
        request("GET", url, null, function(success, data, error) {
            if (success) {
                var links = data.map(function(link) {
                    return {
                        token: link.token,
                        link: link.link,
                        repo_id: link.repo_id,
                        repo_name: link.repo_name,
                        path: link.path,
                        obj_name: link.obj_name,
                        is_dir: link.is_dir,
                        view_cnt: link.view_cnt,
                        ctime: link.ctime,
                        expire_date: link.expire_date,
                        is_expired: link.is_expired,
                        permissions: link.permissions || {},
                        password: link.password || "",
                        can_edit: link.can_edit
                    }
                })
                callback(true, links, null)
            } else {
                callback(false, null, error)
            }
        })
    }

    function createShareLink(repoId, path, options, callback) {
        var body = {
            repo_id: repoId,
            path: path
        }
        if (options.password) {
            body.password = options.password
        }
        if (options.expire_days) {
            body.expire_days = String(options.expire_days)
        }
        if (options.permissions) {
            body.permissions = options.permissions
        }
        var xhr = new XMLHttpRequest()
        xhr.open("POST", baseUrl + "/api/v2.1/share-links/", true)
        xhr.setRequestHeader("Authorization", "Token " + token)
        xhr.setRequestHeader("Content-Type", "application/json")
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                if (xhr.status >= 200 && xhr.status < 300) {
                    var response = JSON.parse(xhr.responseText)
                    callback(true, {
                        token: response.token,
                        link: response.link,
                        repo_id: response.repo_id,
                        repo_name: response.repo_name,
                        path: response.path,
                        obj_name: response.obj_name,
                        is_dir: response.is_dir,
                        view_cnt: response.view_cnt,
                        ctime: response.ctime,
                        expire_date: response.expire_date,
                        is_expired: response.is_expired,
                        permissions: response.permissions || {},
                        password: response.password || "",
                        can_edit: response.can_edit
                    }, null)
                } else {
                    callback(false, null, parseError(xhr))
                }
            }
        }
        xhr.send(JSON.stringify(body))
    }

    function deleteShareLink(shareToken, callback) {
        var xhr = new XMLHttpRequest()
        xhr.open("DELETE", baseUrl + "/api/v2.1/share-links/" + encodeURIComponent(shareToken) + "/", true)
        xhr.setRequestHeader("Authorization", "Token " + token)
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                if (xhr.status >= 200 && xhr.status < 300) {
                    callback(true, null)
                } else {
                    callback(false, parseError(xhr))
                }
            }
        }
        xhr.send()
    }

    // ===== COPY =====

    function copyFile(repoId, filePath, dstRepoId, dstDir, newName, callback) {
        var url = "/api/v2.1/repos/" + repoId + "/file/?p=" + encodeURIComponent(filePath)
        var xhr = new XMLHttpRequest()
        xhr.open("POST", baseUrl + url, true)
        xhr.setRequestHeader("Authorization", "Token " + token)
        xhr.setRequestHeader("Content-Type", "application/x-www-form-urlencoded")
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                if (xhr.status >= 200 && xhr.status < 300) {
                    var response = JSON.parse(xhr.responseText)
                    callback(true, response, null)
                } else {
                    callback(false, null, parseError(xhr))
                }
            }
        }
        var body = "operation=copy&dst_repo=" + encodeURIComponent(dstRepoId) + "&dst_dir=" + encodeURIComponent(dstDir) + "&newname=" + encodeURIComponent(newName)
        xhr.send(body)
    }

    function copyFolder(repoId, folderName, srcParentDir, dstRepoId, dstParentDir, callback) {
        var url = baseUrl + "/api/v2.1/repos/sync-batch-copy-item/"
        var xhr = new XMLHttpRequest()
        xhr.open("POST", url, true)
        xhr.setRequestHeader("Authorization", "Token " + token)
        xhr.setRequestHeader("Content-Type", "application/json")
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                if (xhr.status >= 200 && xhr.status < 300) {
                    callback(true, null)
                } else {
                    callback(false, parseError(xhr))
                }
            }
        }
        var body = JSON.stringify({
            src_repo_id: repoId,
            src_parent_dir: srcParentDir,
            src_dirents: [folderName],
            dst_repo_id: dstRepoId,
            dst_parent_dir: dstParentDir
        })
        xhr.send(body)
    }

    function copyItems(items, dstRepoId, dstParentDir, callback) {
        if (!items || items.length === 0) {
            callback(false, null, "No items to copy")
            return
        }

        var groups = {}
        for (var i = 0; i < items.length; i++) {
            var item = items[i]
            var key = item.repoId + ":" + (item.srcParentDir || "/")
            if (!groups[key]) {
                groups[key] = {
                    srcRepoId: item.repoId,
                    srcParentDir: item.srcParentDir || "/",
                    srcDirents: [],
                    dstRepoId: dstRepoId,
                    dstParentDir: dstParentDir
                }
            }
            groups[key].srcDirents.push(item.name)
        }

        var groupKeys = Object.keys(groups)
        var completed = 0
        var hasError = false

        function checkComplete() {
            completed++
            if (completed === groupKeys.length) {
                if (!hasError) {
                    callback(true, null)
                }
            }
        }

        for (var key in groups) {
            var group = groups[key]
            var xhr = new XMLHttpRequest()
            var url = baseUrl + "/api/v2.1/repos/sync-batch-copy-item/"
            xhr.open("POST", url, true)
            xhr.setRequestHeader("Authorization", "Token " + token)
            xhr.setRequestHeader("Content-Type", "application/json")
            xhr.onreadystatechange = function() {
                if (xhr.readyState === XMLHttpRequest.DONE) {
                    if (xhr.status >= 200 && xhr.status < 300) {
                        // success
                    } else {
                        hasError = true
                    }
                    checkComplete()
                }
            }
            xhr.send(JSON.stringify(group))
        }
    }

    function moveItems(items, dstRepoId, dstParentDir, callback) {
        if (!items || items.length === 0) {
            callback(false, null, "No items to move")
            return
        }

        var groups = {}
        for (var i = 0; i < items.length; i++) {
            var item = items[i]
            var key = item.repoId + ":" + (item.srcParentDir || "/")
            if (!groups[key]) {
                groups[key] = {
                    srcRepoId: item.repoId,
                    srcParentDir: item.srcParentDir || "/",
                    srcDirents: [],
                    dstRepoId: dstRepoId,
                    dstParentDir: dstParentDir
                }
            }
            groups[key].srcDirents.push(item.name)
        }

        var groupKeys = Object.keys(groups)
        var completed = 0
        var hasError = false

        function checkComplete() {
            completed++
            if (completed === groupKeys.length) {
                if (!hasError) {
                    callback(true, null)
                }
            }
        }

        for (var key in groups) {
            var group = groups[key]
            var xhr = new XMLHttpRequest()
            var url = baseUrl + "/api/v2.1/repos/sync-batch-move-item/"
            xhr.open("POST", url, true)
            xhr.setRequestHeader("Authorization", "Token " + token)
            xhr.setRequestHeader("Content-Type", "application/json")
            xhr.onreadystatechange = function() {
                if (xhr.readyState === XMLHttpRequest.DONE) {
                    if (xhr.status >= 200 && xhr.status < 300) {
                        // success
                    } else {
                        hasError = true
                    }
                    checkComplete()
                }
            }
            xhr.send(JSON.stringify(group))
        }
    }

    function deleteItemsSequentially(items, callback) {
        if (!items || items.length === 0) {
            callback(false, null, "No items to delete")
            return
        }

        var results = { success: [], failed: [] }
        var index = 0

        function deleteNext() {
            if (index >= items.length) {
                callback(true, results, null)
                return
            }

            var item = items[index]
            if (item.type === "dir") {
                deleteFolder(item.repoId, item.fullPath, token, function(success, error) {
                    if (success) {
                        results.success.push(item)
                    } else {
                        results.failed.push({ item: item, error: error })
                    }
                    index++
                    deleteNext()
                })
            } else {
                deleteFile(item.repoId, item.fullPath, token, function(success, error) {
                    if (success) {
                        results.success.push(item)
                    } else {
                        results.failed.push({ item: item, error: error })
                    }
                    index++
                    deleteNext()
                })
            }
        }

        deleteNext()
    }
        var url = "/api/v2.1/search-file/?q=" + encodeURIComponent(query) + "&repo_id=" + encodeURIComponent(repoId)
        var xhr = new XMLHttpRequest()
        xhr.open("GET", baseUrl + url, true)
        xhr.setRequestHeader("Authorization", "Token " + token)
        xhr.setRequestHeader("Accept", "application/json")
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                if (xhr.status >= 200 && xhr.status < 300) {
                    try {
                        var response = JSON.parse(xhr.responseText)
                        var results = (response.data || []).map(function(item) {
                            var pathParts = item.path.split("/")
                            var name = pathParts.pop()
                            var parentPath = pathParts.join("/") || "/"
                            return {
                                name: name,
                                path: item.path,
                                parentPath: parentPath,
                                size: item.size || 0,
                                mtime: item.mtime,
                                type: item.type,
                                repoId: repoId
                            }
                        })
                        callback(true, results, null)
                    } catch (e) {
                        callback(false, null, "Failed to parse search response")
                    }
                } else {
                    var error = parseError(xhr)
                    callback(false, null, error)
                }
            }
        }
        xhr.send()
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
}