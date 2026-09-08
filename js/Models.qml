pragma Singleton
import QtQuick

QtObject {
    id: root

    function parseLibraries(data) {
        return data.map(function(repo) {
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
    }

    function parseFiles(data) {
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
        return items
    }

    function formatSize(bytes) {
        if (bytes < 1024) return bytes + " B"
        if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1) + " KB"
        if (bytes < 1024 * 1024 * 1024) return (bytes / (1024 * 1024)).toFixed(1) + " MB"
        return (bytes / (1024 * 1024 * 1024)).toFixed(1) + " GB"
    }

    function formatDate(timestamp) {
        if (!timestamp) return ""
        var date = new Date(timestamp * 1000)
        var y = date.getFullYear()
        var m = ("0" + (date.getMonth() + 1)).slice(-2)
        var d = ("0" + date.getDate()).slice(-2)
        var h = ("0" + date.getHours()).slice(-2)
        var mi = ("0" + date.getMinutes()).slice(-2)
        return y + "-" + m + "-" + d + " " + h + ":" + mi
    }

    // Safe file:// URL construction from absolute POSIX path
    // Encodes each path component separately with encodeURIComponent
    function toFileUrl(path) {
        var parts = path.split('/').filter(function(p) { return p !== '' })
        var encodedParts = parts.map(function(p) { return encodeURIComponent(p) })
        return 'file:///' + encodedParts.join('/')
    }

    // Parent directory file:// URL for "Show in Folder"
    function toParentFileUrl(path) {
        var lastSlash = path.lastIndexOf('/')
        var parentPath = '/'
        if (lastSlash > 0) {
            parentPath = path.substring(0, lastSlash)
        }
        return root.toFileUrl(parentPath)
    }

    // Display-text bounding: convert to string, enforce a character ceiling,
    // append "…" on truncation. null/undefined → "". Never interprets HTML;
    // pair with textFormat: Text.PlainText at the sink.
    function boundedDisplayText(value, maxChars) {
        if (value === null || value === undefined) return ""
        if (maxChars <= 0) return ""
        var s = String(value)
        if (s.length <= maxChars) return s
        return s.substring(0, maxChars - 1) + "\u2026"
    }
}