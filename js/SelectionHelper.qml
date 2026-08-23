pragma Singleton
import QtQuick

QtObject {
    id: root

    // ===== STABLE KEY GENERATION =====

    function makeKey(item) {
        if (!item) return ""
        var repoId = item.repoId || item.parentRepoId || ""
        var fullPath = item.fullPath || item.path || (item.name && item.parentPath ? item.parentPath + "/" + item.name : "")
        var type = item.type || (item.isDir ? "dir" : "file")
        return repoId + ":" + fullPath + ":" + type
    }

    // ===== CORE SELECTION OPERATIONS =====

    function isSelected(selectedItems, item) {
        var key = makeKey(item)
        if (!key) return false
        for (var i = 0; i < selectedItems.length; i++) {
            if (makeKey(selectedItems[i]) === key) return true
        }
        return false
    }

    function toggleSelection(selectedItems, item) {
        var key = makeKey(item)
        if (!key) return selectedItems

        var idx = -1
        for (var i = 0; i < selectedItems.length; i++) {
            if (makeKey(selectedItems[i]) === key) {
                idx = i
                break
            }
        }

        var result = selectedItems.slice()
        if (idx >= 0) {
            result.splice(idx, 1)
        } else {
            result.push(item)
        }
        return result
    }

    function rangeSelect(selectedItems, anchor, target, allItems) {
        if (!anchor || !target || !allItems || allItems.length === 0) return selectedItems

        var anchorIdx = -1
        var targetIdx = -1
        for (var i = 0; i < allItems.length; i++) {
            if (makeKey(allItems[i]) === makeKey(anchor)) anchorIdx = i
            if (makeKey(allItems[i]) === makeKey(target)) targetIdx = i
        }

        if (anchorIdx < 0 || targetIdx < 0) return selectedItems

        var start = Math.min(anchorIdx, targetIdx)
        var end = Math.max(anchorIdx, targetIdx)

        var result = selectedItems.slice()
        var rangeKeys = {}
        for (var i = start; i <= end; i++) {
            rangeKeys[makeKey(allItems[i])] = true
        }

        // Remove any existing range items
        var filtered = []
        for (var i = 0; i < result.length; i++) {
            if (!rangeKeys[makeKey(result[i])]) {
                filtered.push(result[i])
            }
        }
        result = filtered

        // Add range items
        for (var i = start; i <= end; i++) {
            result.push(allItems[i])
        }

        return result
    }

    function selectAll(selectedItems, items) {
        var result = items.slice()
        return result
    }

    function clearSelection(selectedItems) {
        return []
    }

    function pruneSelection(selectedItems, currentItems) {
        if (!currentItems || currentItems.length === 0) return []

        var validKeys = {}
        for (var i = 0; i < currentItems.length; i++) {
            validKeys[makeKey(currentItems[i])] = true
        }

        var result = []
        for (var i = 0; i < selectedItems.length; i++) {
            if (validKeys[makeKey(selectedItems[i])]) {
                result.push(selectedItems[i])
            }
        }
        return result
    }

    function getSelectionCount(selectedItems) {
        return selectedItems.length
    }

    // ===== SERIALIZATION (for persistence if needed) =====

    function serialize(selectedItems) {
        var keys = []
        for (var i = 0; i < selectedItems.length; i++) {
            keys.push(makeKey(selectedItems[i]))
        }
        return keys
    }

    function deserialize(keys, currentItems) {
        var result = []
        var itemMap = {}
        for (var i = 0; i < currentItems.length; i++) {
            itemMap[makeKey(currentItems[i])] = currentItems[i]
        }
        for (var i = 0; i < keys.length; i++) {
            if (itemMap[keys[i]]) {
                result.push(itemMap[keys[i]])
            }
        }
        return result
    }
}