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
        var date = new Date(timestamp * 1000)
        return date.toLocaleDateString() + " " + date.toLocaleTimeString()
    }
}