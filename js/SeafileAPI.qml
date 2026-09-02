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
                if (!Array.isArray(data)) { callback(false, null, "Invalid server response"); return }
                var libraries = data.map(function(repo) {
                    return {
                        id: repo.id,
                        name: repo.name,
                        type: "dir",
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
                if (!Array.isArray(data)) { callback(false, null, "Invalid server response"); return }
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
                if (!Array.isArray(data)) { callback(false, null, "Invalid server response"); return }
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
        HttpTransport.post(baseUrl + "/api/v2.1/share-links/",
            { "Authorization": "Token " + token, "Content-Type": "application/json" },
            JSON.stringify(body),
            function(success, data, error) {
                if (success) {
                    if (!data || typeof data.link !== "string" || typeof data.token !== "string") {
                        callback(false, null, "Invalid server response")
                        return
                    }
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
                        permissions: data.permissions || {},
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
                        if (!data || !Array.isArray(data.data)) throw new Error("missing data")
                        var results = (data.data || []).map(function(item) {
                            if (!item || typeof item.path !== "string") throw new Error("invalid result")
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
                if (!data || !Array.isArray(data.commits)) { callback(false, null, "Invalid server response"); return }
                var history = (data.commits || []).map(function(commit) {
                    return {
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
                    }
                })
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
                if (!data || !Array.isArray(data.data)) { callback(false, null, "Invalid server response"); return }
                var trash = (data.data || []).map(function(item) {
                    return {
                        parentDir: item.parent_dir,
                        objName: item.obj_name,
                        deletedTime: item.deleted_time,
                        commitId: item.commit_id,
                        isDir: item.is_dir,
                        size: item.size || 0,
                        objId: item.obj_id || ""
                    }
                })
                callback(true, trash, null)
            } else {
                callback(false, null, error)
            }
        })
    }

}
