pragma Singleton
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

    // ===== VALIDATION BOUNDS =====
    readonly property int _maxItems: 1000
    readonly property int _maxName: 1024
    readonly property int _maxPath: 4096
    readonly property int _maxId: 512
    readonly property int _maxToken: 4096
    readonly property int _maxUrl: 8192
    readonly property int _maxPermission: 128
    readonly property int _maxEmail: 320
    readonly property int _maxDescription: 4096

    // ===== VALIDATION HELPERS =====

    function _boundedString(value, max, allowEmpty) {
        if (typeof value !== "string") return { valid: false, error: "Expected string" }
        if (!allowEmpty && value.length === 0) return { valid: false, error: "String must not be empty" }
        if (value.length > max) return { valid: false, error: "String exceeds max length " + max }
        return { valid: true }
    }

    function _optionalBoundedString(value, max) {
        if (value === undefined || value === null) return { valid: true }
        return _boundedString(value, max, true)
    }

    function _safeBoolean(value) {
        if (typeof value !== "boolean") return { valid: false, error: "Expected boolean" }
        return { valid: true }
    }

    function _safeNonNegativeNumber(value) {
        if (typeof value !== "number" || isNaN(value)) return { valid: false, error: "Expected number" }
        if (value < 0) return { valid: false, error: "Number must be non-negative" }
        return { valid: true }
    }

    function _safeTimestamp(value) {
        if (typeof value !== "number" || isNaN(value)) return { valid: false, error: "Expected timestamp number" }
        return { valid: true }
    }

    function _safeArray(value, limit) {
        if (!Array.isArray(value)) return { valid: false, error: "Expected array" }
        var max = limit || _maxItems
        if (value.length > max) return { valid: false, error: "Array exceeds max items " + max }
        return { valid: true }
    }

    function _hasControlChars(s) {
        for (var i = 0; i < s.length; i++) {
            var c = s.charCodeAt(i)
            if (c < 0x20 || c === 0x7F) return true
        }
        return false
    }

    function auth(username, password, callback) {
        var url = baseUrl + "/api2/auth-token/"
        HttpTransport.post(url, { "Content-Type": "application/x-www-form-urlencoded" },
            "username=" + encodeURIComponent(username) + "&password=" + encodeURIComponent(password),
            function(success, data, error) {
                if (success) {
                    if (!data || typeof data.token !== "string" || data.token === "") {
                        callback(false, null, "Invalid server response")
                        return
                    }
                    if (data.token.length > _maxToken) {
                        callback(false, null, "Token exceeds maximum length")
                        return
                    }
                    if (_hasControlChars(data.token)) {
                        callback(false, null, "Token contains invalid characters")
                        return
                    }
                    callback(true, data.token, null)
                } else {
                    callback(false, null, error || "Authentication failed")
                }
            }
        )
    }

    function listLibraries(callback) {
        request("GET", "/api2/repos/", null, function(success, data, error) {
            if (success) {
                var arrResult = _safeArray(data)
                if (!arrResult.valid) { callback(false, null, arrResult.error); return }
                var libraries = []
                for (var i = 0; i < data.length; i++) {
                    var repo = data[i]
                    if (!repo || typeof repo !== "object") { callback(false, null, "Invalid library item at index " + i); return }
                    var vId = _boundedString(repo.id, _maxId)
                    if (!vId.valid) { callback(false, null, "Library id: " + vId.error); return }
                    var vName = _boundedString(repo.name, _maxName)
                    if (!vName.valid) { callback(false, null, "Library name: " + vName.error); return }
                    var vSize = _safeNonNegativeNumber(repo.size)
                    if (!vSize.valid) { callback(false, null, "Library size: " + vSize.error); return }
                    var vSizeFmt = _optionalBoundedString(repo.size_formatted, _maxName)
                    if (!vSizeFmt.valid) { callback(false, null, "Library size_formatted: " + vSizeFmt.error); return }
                    var vMtime = _safeTimestamp(repo.mtime)
                    if (!vMtime.valid) { callback(false, null, "Library mtime: " + vMtime.error); return }
                    var vPerm = _boundedString(repo.permission, _maxPermission)
                    if (!vPerm.valid) { callback(false, null, "Library permission: " + vPerm.error); return }
                    var vEnc = _safeBoolean(repo.encrypted)
                    if (!vEnc.valid) { callback(false, null, "Library encrypted: " + vEnc.error); return }
                    libraries.push({
                        id: repo.id,
                        name: repo.name,
                        type: "dir",
                        size: repo.size,
                        sizeFormatted: repo.size_formatted,
                        mtime: repo.mtime,
                        permission: repo.permission,
                        encrypted: repo.encrypted
                    })
                }
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
                var arrResult = _safeArray(data)
                if (!arrResult.valid) { callback(false, null, arrResult.error); return }
                var items = []
                for (var i = 0; i < data.length; i++) {
                    var item = data[i]
                    if (!item || typeof item !== "object") { callback(false, null, "Invalid folder item at index " + i); return }
                    var vType = _boundedString(item.type, 32)
                    if (!vType.valid) { callback(false, null, "Item type: " + vType.error); return }
                    var vName = _boundedString(item.name, _maxName)
                    if (!vName.valid) { callback(false, null, "Item name: " + vName.error); return }
                    var vId = _optionalBoundedString(item.id, _maxId)
                    if (!vId.valid) { callback(false, null, "Item id: " + vId.error); return }
                    var vMtime = _safeTimestamp(item.mtime)
                    if (!vMtime.valid) { callback(false, null, "Item mtime: " + vMtime.error); return }
                    var vPerm = _optionalBoundedString(item.permission, _maxPermission)
                    if (!vPerm.valid) { callback(false, null, "Item permission: " + vPerm.error); return }
                    var vSize = _safeNonNegativeNumber(item.size || 0)
                    if (!vSize.valid) { callback(false, null, "Item size: " + vSize.error); return }
                    var vStarred = _safeBoolean(item.starred || false)
                    if (!vStarred.valid) { callback(false, null, "Item starred: " + vStarred.error); return }
                    items.push({
                        type: item.type,
                        name: item.name,
                        id: item.id,
                        mtime: item.mtime,
                        permission: item.permission,
                        size: item.size || 0,
                        starred: item.starred || false
                    })
                }
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
                var vUrl = UrlPolicy.validateTransferUrl(data)
                if (!vUrl.valid) { callback(false, null, "Invalid download URL: " + vUrl.error); return }
                callback(true, data, null)
            } else {
                callback(false, null, error)
            }
        })
    }

    function createFolder(repoId, parentPath, folderName, token, callback) {
        var createName = parentPath === "/" ? folderName : "Omarseafile temporary " + Date.now() + " " + Math.random().toString(36).substring(2, 8)
        var fullPath = "/" + createName
        var url = "/api2/repos/" + repoId + "/dir/?p=" + encodeURIComponent(fullPath)
        HttpTransport.post(baseUrl + url, { "Authorization": "Token " + token, "Content-Type": "application/x-www-form-urlencoded" },
            "operation=mkdir",
            function(success, data, error) {
                if (success) {
                    if (parentPath === "/") {
                        callback(true, null)
                    } else {
                        moveFolder(repoId, createName, "/", repoId, parentPath, token, function(success, error) {
                            if (!success) {
                                callback(false, "Temporary folder " + createName + " was created at the library root but could not be moved: " + error)
                                return
                            }
                            renameFolder(repoId, parentPath, createName, folderName, token, function(renameSuccess, renameError) {
                                callback(renameSuccess, renameSuccess ? null : "Temporary folder " + createName + " was moved into place but could not be renamed: " + renameError)
                            })
                        })
                    }
                } else {
                    callback(false, error || "Create folder failed")
                }
            }
        )
    }

    function renameFile(repoId, filePath, newName, token, callback) {
        var url = baseUrl + "/api/v2.1/repos/" + repoId + "/file/?p=" + encodeURIComponent(filePath)
        HttpTransport.post(url, { "Authorization": "Token " + token, "Content-Type": "application/x-www-form-urlencoded" },
            "operation=rename&oldname=" + encodeURIComponent(filePath) + "&newname=" + encodeURIComponent(newName),
            function(success, data, error) {
                if (success) callback(true, null)
                else callback(false, error || "Rename failed")
            }
        )
    }

    function renameFolder(repoId, parentPath, oldName, newName, token, callback) {
        var parent = parentPath === "/" ? "" : parentPath
        var fullPath = parent + "/" + oldName
        var url = baseUrl + "/api2/repos/" + repoId + "/dir/?p=" + encodeURIComponent(fullPath)
        HttpTransport.post(url, { "Authorization": "Token " + token, "Content-Type": "application/x-www-form-urlencoded" },
            "operation=rename&newname=" + encodeURIComponent(newName),
            function(success, data, error) {
                if (success) callback(true, null)
                else callback(false, error || "Rename failed")
            }
        )
    }

    function moveFile(repoId, filePath, destPath, token, callback) {
        var url = baseUrl + "/api/v2.1/repos/" + repoId + "/file/?p=" + encodeURIComponent(filePath)
        HttpTransport.post(url, { "Authorization": "Token " + token, "Content-Type": "application/x-www-form-urlencoded" },
            "operation=move&dst_repo=" + encodeURIComponent(repoId) + "&dst_dir=" + encodeURIComponent(destPath),
            function(success, data, error) {
                if (success) callback(true, null)
                else callback(false, error || "Move failed")
            }
        )
    }

    function deleteFile(repoId, filePath, token, callback) {
        var url = baseUrl + "/api/v2.1/repos/" + repoId + "/file/?p=" + encodeURIComponent(filePath)
        HttpTransport.del(url, { "Authorization": "Token " + token }, function(success, data, error) {
            if (success) callback(true, null)
            else callback(false, error || "Delete failed")
        })
    }

    function deleteFolder(repoId, folderPath, token, callback) {
        var url = baseUrl + "/api2/repos/" + repoId + "/dir/?p=" + encodeURIComponent(folderPath)
        HttpTransport.del(url, { "Authorization": "Token " + token }, function(success, data, error) {
            if (success) callback(true, null)
            else callback(false, error || "Delete failed")
        })
    }

    function moveFolder(repoId, folderName, srcParentPath, destRepoId, destParentPath, token, callback) {
        var url = baseUrl + "/api/v2.1/repos/sync-batch-move-item/"
        var body = JSON.stringify({
            src_repo_id: repoId,
            src_parent_dir: srcParentPath,
            src_dirents: [folderName],
            dst_repo_id: destRepoId,
            dst_parent_dir: destParentPath
        })
        HttpTransport.post(url, { "Authorization": "Token " + token, "Content-Type": "application/json" }, body,
            function(success, data, error) {
                if (success) {
                    if (confirmedMutation({ responseText: JSON.stringify(data) })) callback(true, null)
                    else callback(false, "Server did not confirm move")
                } else {
                    callback(false, error || "Move failed")
                }
            }
        )
    }

    function parseError(error) {
        if (!error) return "Unknown error"
        if (typeof error === "string") return error
        return "Unknown error"
    }

    function confirmedMutation(response) {
        try {
            var data = typeof response === "string" ? JSON.parse(response) : response
            return data && data.success === true
        } catch (e) {
            return false
        }
    }

    function request(method, path, body, callback) {
        if (!token) {
            callback(false, null, "No authentication token")
            return
        }
        var headers = {
            "Authorization": "Token " + token,
            "Accept": "application/json"
        }
        if (body && method !== "GET") {
            headers["Content-Type"] = "application/json"
        }
        HttpTransport.request(method, baseUrl + path, headers, body ? JSON.stringify(body) : null, callback)
    }

    // ===== SHARE LINKS =====

    function listShareLinks(repoId, path, callback) {
        var url = "/api/v2.1/share-links/?repo_id=" + encodeURIComponent(repoId)
        if (path) {
            url += "&path=" + encodeURIComponent(path)
        }
        request("GET", url, null, function(success, data, error) {
            if (success) {
                var arrResult = _safeArray(data)
                if (!arrResult.valid) { callback(false, null, arrResult.error); return }
                var links = []
                for (var i = 0; i < data.length; i++) {
                    var link = data[i]
                    if (!link || typeof link !== "object") { callback(false, null, "Invalid share link at index " + i); return }
                    var vToken = _boundedString(link.token, _maxToken)
                    if (!vToken.valid) { callback(false, null, "Share link token: " + vToken.error); return }
                    var vLink = _boundedString(link.link, _maxUrl)
                    if (!vLink.valid) { callback(false, null, "Share link link: " + vLink.error); return }
                    var vRepoId = _boundedString(link.repo_id, _maxId)
                    if (!vRepoId.valid) { callback(false, null, "Share link repo_id: " + vRepoId.error); return }
                    var vRepoName = _optionalBoundedString(link.repo_name, _maxName)
                    if (!vRepoName.valid) { callback(false, null, "Share link repo_name: " + vRepoName.error); return }
                    var vPath = _boundedString(link.path, _maxPath)
                    if (!vPath.valid) { callback(false, null, "Share link path: " + vPath.error); return }
                    var vObjName = _optionalBoundedString(link.obj_name, _maxName)
                    if (!vObjName.valid) { callback(false, null, "Share link obj_name: " + vObjName.error); return }
                    var vIsDir = _safeBoolean(link.is_dir)
                    if (!vIsDir.valid) { callback(false, null, "Share link is_dir: " + vIsDir.error); return }
                    var vViewCnt = _safeNonNegativeNumber(link.view_cnt)
                    if (!vViewCnt.valid) { callback(false, null, "Share link view_cnt: " + vViewCnt.error); return }
                    var vCtime = _safeTimestamp(link.ctime)
                    if (!vCtime.valid) { callback(false, null, "Share link ctime: " + vCtime.error); return }
                    var vExpireDate = _optionalBoundedString(link.expire_date, 64)
                    if (!vExpireDate.valid) { callback(false, null, "Share link expire_date: " + vExpireDate.error); return }
                    var vIsExpired = _safeBoolean(link.is_expired)
                    if (!vIsExpired.valid) { callback(false, null, "Share link is_expired: " + vIsExpired.error); return }
                    var perms = link.permissions || {}
                    if (typeof perms !== "object" || perms === null) { callback(false, null, "Share link permissions: expected object"); return }
                    var vPassword = _optionalBoundedString(link.password, _maxToken)
                    if (!vPassword.valid) { callback(false, null, "Share link password: " + vPassword.error); return }
                    var vCanEdit = _safeBoolean(link.can_edit)
                    if (!vCanEdit.valid) { callback(false, null, "Share link can_edit: " + vCanEdit.error); return }
                    links.push({
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
                        permissions: perms,
                        password: link.password || "",
                        can_edit: link.can_edit
                    })
                }
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
        HttpTransport.post(baseUrl + "/api/v2.1/share-links/",
            { "Authorization": "Token " + token, "Content-Type": "application/json" },
            JSON.stringify(body),
            function(success, data, error) {
                if (success) {
                    if (!data || typeof data !== "object") { callback(false, null, "Invalid server response"); return }
                    var vToken = _boundedString(data.token, _maxToken)
                    if (!vToken.valid) { callback(false, null, "Share link token: " + vToken.error); return }
                    var vLink = _boundedString(data.link, _maxUrl)
                    if (!vLink.valid) { callback(false, null, "Share link link: " + vLink.error); return }
                    var vUrl = UrlPolicy.validateTransferUrl(data.link)
                    if (!vUrl.valid) { callback(false, null, "Share link URL: " + vUrl.error); return }
                    var vRepoId = _optionalBoundedString(data.repo_id, _maxId)
                    if (!vRepoId.valid) { callback(false, null, "Share link repo_id: " + vRepoId.error); return }
                    var vRepoName = _optionalBoundedString(data.repo_name, _maxName)
                    if (!vRepoName.valid) { callback(false, null, "Share link repo_name: " + vRepoName.error); return }
                    var vPath = _optionalBoundedString(data.path, _maxPath)
                    if (!vPath.valid) { callback(false, null, "Share link path: " + vPath.error); return }
                    var vObjName = _optionalBoundedString(data.obj_name, _maxName)
                    if (!vObjName.valid) { callback(false, null, "Share link obj_name: " + vObjName.error); return }
                    var vIsDir = _safeBoolean(data.is_dir)
                    if (!vIsDir.valid) { callback(false, null, "Share link is_dir: " + vIsDir.error); return }
                    var vViewCnt = _safeNonNegativeNumber(data.view_cnt)
                    if (!vViewCnt.valid) { callback(false, null, "Share link view_cnt: " + vViewCnt.error); return }
                    var vCtime = _safeTimestamp(data.ctime)
                    if (!vCtime.valid) { callback(false, null, "Share link ctime: " + vCtime.error); return }
                    var vExpireDate = _optionalBoundedString(data.expire_date, 64)
                    if (!vExpireDate.valid) { callback(false, null, "Share link expire_date: " + vExpireDate.error); return }
                    var vIsExpired = _safeBoolean(data.is_expired)
                    if (!vIsExpired.valid) { callback(false, null, "Share link is_expired: " + vIsExpired.error); return }
                    var perms = data.permissions || {}
                    if (typeof perms !== "object" || perms === null) { callback(false, null, "Share link permissions: expected object"); return }
                    var vPassword = _optionalBoundedString(data.password, _maxToken)
                    if (!vPassword.valid) { callback(false, null, "Share link password: " + vPassword.error); return }
                    var vCanEdit = _safeBoolean(data.can_edit)
                    if (!vCanEdit.valid) { callback(false, null, "Share link can_edit: " + vCanEdit.error); return }
                    callback(true, {
                        token: data.token,
                        link: data.link,
                        repo_id: data.repo_id,
                        repo_name: data.repo_name,
                        path: data.path,
                        obj_name: data.obj_name,
                        is_dir: data.is_dir,
                        view_cnt: data.view_cnt,
                        ctime: data.ctime,
                        expire_date: data.expire_date,
                        is_expired: data.is_expired,
                        permissions: perms,
                        password: data.password || "",
                        can_edit: data.can_edit
                    }, null)
                } else {
                    callback(false, null, error || "Create share link failed")
                }
            }
        )
    }

    function deleteShareLink(shareToken, callback) {
        HttpTransport.del(baseUrl + "/api/v2.1/share-links/" + encodeURIComponent(shareToken) + "/",
            { "Authorization": "Token " + token },
            function(success, data, error) {
                if (success) {
                    if (confirmedMutation(data)) callback(true, null)
                    else callback(false, "Server did not confirm share-link revocation")
                } else {
                    callback(false, error || "Delete share link failed")
                }
            }
        )
    }

    // ===== COPY =====

    function copyFile(repoId, filePath, dstRepoId, dstDir, newName, token, callback) {
        var url = baseUrl + "/api/v2.1/repos/" + repoId + "/file/?p=" + encodeURIComponent(filePath)
        HttpTransport.post(url, { "Authorization": "Token " + token, "Content-Type": "application/x-www-form-urlencoded" },
            "operation=copy&dst_repo=" + encodeURIComponent(dstRepoId) + "&dst_dir=" + encodeURIComponent(dstDir) + "&newname=" + encodeURIComponent(newName),
            function(success, data, error) {
                if (success) callback(true, null)
                else callback(false, error || "Copy failed")
            }
        )
    }

    function copyFolder(repoId, folderName, srcParentDir, dstRepoId, dstParentDir, token, callback) {
        var url = baseUrl + "/api/v2.1/repos/sync-batch-copy-item/"
        var body = JSON.stringify({
            src_repo_id: repoId,
            src_parent_dir: srcParentDir,
            src_dirents: [folderName],
            dst_repo_id: dstRepoId,
            dst_parent_dir: dstParentDir
        })
        HttpTransport.post(url, { "Authorization": "Token " + token, "Content-Type": "application/json" }, body,
            function(success, data, error) {
                if (success) {
                    if (confirmedMutation(data)) callback(true, null)
                    else callback(false, "Server did not confirm copy")
                } else {
                    callback(false, error || "Copy failed")
                }
            }
        )
    }

    function copyItems(items, dstRepoId, dstParentDir, callback) {
        if (!items || items.length === 0) {
            callback(false, "No items to copy")
            return
        }

        var groups = {}
        for (var i = 0; i < items.length; i++) {
            var item = items[i]
            var key = item.repoId + ":" + (item.srcParentDir || "/")
            if (!groups[key]) {
                groups[key] = {
                    src_repo_id: item.repoId,
                    src_parent_dir: item.srcParentDir || "/",
                    src_dirents: [],
                    dst_repo_id: dstRepoId,
                    dst_parent_dir: dstParentDir
                }
            }
            groups[key].src_dirents.push(item.name)
        }

        var groupKeys = Object.keys(groups)
        var completed = 0
        var hasError = false

        function checkComplete() {
            completed++
            if (completed === groupKeys.length) {
                callback(!hasError, hasError ? "Some items may have copied; one or more source folders failed" : null)
            }
        }

        function sendGroup(group) {
            HttpTransport.post(baseUrl + "/api/v2.1/repos/sync-batch-copy-item/",
                { "Authorization": "Token " + token, "Content-Type": "application/json" },
                JSON.stringify(group),
                function(success, data, error) {
                    if (success) {
                        if (!confirmedMutation(data)) hasError = true
                    } else {
                        hasError = true
                    }
                    checkComplete()
                }
            )
        }
        for (var key in groups) sendGroup(groups[key])
    }

    function moveItems(items, dstRepoId, dstParentDir, callback) {
        if (!items || items.length === 0) {
            callback(false, "No items to move")
            return
        }

        var groups = {}
        for (var i = 0; i < items.length; i++) {
            var item = items[i]
            var key = item.repoId + ":" + (item.srcParentDir || "/")
            if (!groups[key]) {
                groups[key] = {
                    src_repo_id: item.repoId,
                    src_parent_dir: item.srcParentDir || "/",
                    src_dirents: [],
                    dst_repo_id: dstRepoId,
                    dst_parent_dir: dstParentDir
                }
            }
            groups[key].src_dirents.push(item.name)
        }

        var groupKeys = Object.keys(groups)
        var completed = 0
        var hasError = false

        function checkComplete() {
            completed++
            if (completed === groupKeys.length) {
                callback(!hasError, hasError ? "Some items may have moved; one or more source folders failed" : null)
            }
        }

        function sendGroup(group) {
            HttpTransport.post(baseUrl + "/api/v2.1/repos/sync-batch-move-item/",
                { "Authorization": "Token " + token, "Content-Type": "application/json" },
                JSON.stringify(group),
                function(success, data, error) {
                    if (success) {
                        if (!confirmedMutation(data)) hasError = true
                    } else {
                        hasError = true
                    }
                    checkComplete()
                }
            )
        }
        for (var key in groups) sendGroup(groups[key])
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

    function search(query, repoId, callback) {
        var url = "/api/v2.1/search-file/?q=" + encodeURIComponent(query) + "&repo_id=" + encodeURIComponent(repoId)
        HttpTransport.get(baseUrl + url, { "Authorization": "Token " + token, "Accept": "application/json" },
            function(success, data, error) {
                if (success) {
                    try {
                        if (!data || typeof data !== "object") throw new Error("missing data")
                        var arrResult = _safeArray(data.data)
                        if (!arrResult.valid) throw new Error(arrResult.error)
                        var results = []
                        for (var i = 0; i < data.data.length; i++) {
                            var item = data.data[i]
                            if (!item || typeof item !== "object") throw new Error("Invalid search result at index " + i)
                            var vPath = _boundedString(item.path, _maxPath)
                            if (!vPath.valid) throw new Error("Search result path: " + vPath.error)
                            var vSize = _safeNonNegativeNumber(item.size || 0)
                            if (!vSize.valid) throw new Error("Search result size: " + vSize.error)
                            var vMtime = _safeTimestamp(item.mtime)
                            if (!vMtime.valid) throw new Error("Search result mtime: " + vMtime.error)
                            var vType = _optionalBoundedString(item.type, 32)
                            if (!vType.valid) throw new Error("Search result type: " + vType.error)
                            var pathParts = item.path.split("/")
                            var name = pathParts.pop()
                            var parentPath = pathParts.join("/") || "/"
                            results.push({
                                name: name,
                                path: item.path,
                                parentPath: parentPath,
                                size: item.size || 0,
                                mtime: item.mtime,
                                type: item.type,
                                repoId: repoId
                            })
                        }
                        callback(true, results, null)
                    } catch (e) {
                        callback(false, null, "Failed to parse search response")
                    }
                } else {
                    callback(false, null, error || "Search failed")
                }
            }
        )
    }

    // ===== FILE HISTORY =====

    function getFileHistory(repoId, path, callback) {
        var url = "/api2/repos/" + repoId + "/file/history/?p=" + encodeURIComponent(path)
        request("GET", url, null, function(success, data, error) {
            if (success) {
                if (!data || typeof data !== "object") { callback(false, null, "Invalid server response"); return }
                var arrResult = _safeArray(data.commits)
                if (!arrResult.valid) { callback(false, null, "commits: " + arrResult.error); return }
                var history = []
                for (var i = 0; i < data.commits.length; i++) {
                    var commit = data.commits[i]
                    if (!commit || typeof commit !== "object") { callback(false, null, "Invalid commit at index " + i); return }
                    var vId = _boundedString(commit.id, _maxId)
                    if (!vId.valid) { callback(false, null, "Commit id: " + vId.error); return }
                    var vCreatorName = _optionalBoundedString(commit.creator_name, _maxName)
                    if (!vCreatorName.valid) { callback(false, null, "Commit creator_name: " + vCreatorName.error); return }
                    var vCtime = _safeTimestamp(commit.ctime)
                    if (!vCtime.valid) { callback(false, null, "Commit ctime: " + vCtime.error); return }
                    var vDesc = _optionalBoundedString(commit.desc, _maxDescription)
                    if (!vDesc.valid) { callback(false, null, "Commit desc: " + vDesc.error); return }
                    var vRevFileSize = _safeNonNegativeNumber(commit.rev_file_size)
                    if (!vRevFileSize.valid) { callback(false, null, "Commit rev_file_size: " + vRevFileSize.error); return }
                    var vRevFileId = _optionalBoundedString(commit.rev_file_id, _maxId)
                    if (!vRevFileId.valid) { callback(false, null, "Commit rev_file_id: " + vRevFileId.error); return }
                    var vVersion = _optionalBoundedString(commit.version, 32)
                    if (!vVersion.valid) { callback(false, null, "Commit version: " + vVersion.error); return }
                    var vCreator = _optionalBoundedString(commit.creator, _maxName)
                    if (!vCreator.valid) { callback(false, null, "Commit creator: " + vCreator.error); return }
                    var vCreatorContactEmail = _optionalBoundedString(commit.creator_contact_email, _maxEmail)
                    if (!vCreatorContactEmail.valid) { callback(false, null, "Commit creator_contact_email: " + vCreatorContactEmail.error); return }
                    var vCreatorEmail = _optionalBoundedString(commit.creator_email, _maxEmail)
                    if (!vCreatorEmail.valid) { callback(false, null, "Commit creator_email: " + vCreatorEmail.error); return }
                    var vRepoId = _optionalBoundedString(commit.repo_id, _maxId)
                    if (!vRepoId.valid) { callback(false, null, "Commit repo_id: " + vRepoId.error); return }
                    var vRepoName = _optionalBoundedString(commit.repo_name, _maxName)
                    if (!vRepoName.valid) { callback(false, null, "Commit repo_name: " + vRepoName.error); return }
                    history.push({
                        commitId: commit.id,
                        id: commit.id,
                        creatorName: commit.creator_name,
                        ctime: commit.ctime,
                        desc: commit.desc,
                        revFileSize: commit.rev_file_size,
                        revFileId: commit.rev_file_id,
                        version: commit.version,
                        creator: commit.creator,
                        creatorContactEmail: commit.creator_contact_email,
                        creatorEmail: commit.creator_email,
                        repoId: commit.repo_id,
                        repoName: commit.repo_name,
                        creatorName: commit.creator_name
                    })
                }
                callback(true, history, null)
            } else {
                callback(false, null, error)
            }
        })
    }

    function downloadRevision(repoId, path, commitId, callback) {
        var url = "/api2/repos/" + repoId + "/file/revision/?p=" + encodeURIComponent(path) + "&commit_id=" + encodeURIComponent(commitId)
        request("GET", url, null, function(success, data, error) {
            if (success) {
                if (typeof data !== "string" || data === "") { callback(false, null, "Invalid server response"); return }
                var vUrl = UrlPolicy.validateTransferUrl(data)
                if (!vUrl.valid) { callback(false, null, "Invalid revision URL: " + vUrl.error); return }
                callback(true, data, null)
            } else {
                callback(false, null, error)
            }
        })
    }

    // ===== TRASH =====

    function listTrash(repoId, callback) {
        var url = "/api/v2.1/repos/" + repoId + "/trash/"
        request("GET", url, null, function(success, data, error) {
            if (success) {
                if (!data || typeof data !== "object") { callback(false, null, "Invalid server response"); return }
                var arrResult = _safeArray(data.data)
                if (!arrResult.valid) { callback(false, null, "data: " + arrResult.error); return }
                var trash = []
                for (var i = 0; i < data.data.length; i++) {
                    var item = data.data[i]
                    if (!item || typeof item !== "object") { callback(false, null, "Invalid trash item at index " + i); return }
                    var vParentDir = _optionalBoundedString(item.parent_dir, _maxPath)
                    if (!vParentDir.valid) { callback(false, null, "Trash parent_dir: " + vParentDir.error); return }
                    var vObjName = _boundedString(item.obj_name, _maxName)
                    if (!vObjName.valid) { callback(false, null, "Trash obj_name: " + vObjName.error); return }
                    var vDeletedTime = _optionalBoundedString(item.deleted_time, 64)
                    if (!vDeletedTime.valid) { callback(false, null, "Trash deleted_time: " + vDeletedTime.error); return }
                    var vCommitId = _optionalBoundedString(item.commit_id, _maxId)
                    if (!vCommitId.valid) { callback(false, null, "Trash commit_id: " + vCommitId.error); return }
                    var vIsDir = _safeBoolean(item.is_dir)
                    if (!vIsDir.valid) { callback(false, null, "Trash is_dir: " + vIsDir.error); return }
                    var vSize = _safeNonNegativeNumber(item.size || 0)
                    if (!vSize.valid) { callback(false, null, "Trash size: " + vSize.error); return }
                    var vObjId = _optionalBoundedString(item.obj_id, _maxId)
                    if (!vObjId.valid) { callback(false, null, "Trash obj_id: " + vObjId.error); return }
                    trash.push({
                        parentDir: item.parent_dir,
                        objName: item.obj_name,
                        deletedTime: item.deleted_time,
                        commitId: item.commit_id,
                        isDir: item.is_dir,
                        size: item.size || 0,
                        objId: item.obj_id || ""
                    })
                }
                callback(true, trash, null)
            } else {
                callback(false, null, error)
            }
        })
    }

}
