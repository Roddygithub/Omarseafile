pragma Singleton
import QtQuick

QtObject {
    id: root

    property var cache: ({})
    property int defaultTtl: 30000
    property int maxEntries: 100

    function get(key) {
        var entry = root.cache[key]
        if (!entry) return null
        if (Date.now() > entry.expiresAt) {
            root.remove(key)
            return null
        }
        return entry.data
    }

    function set(key, data, ttl) {
        if (Object.keys(root.cache).length >= root.maxEntries) {
            var oldestKey = null
            var oldestTime = Date.now()
            for (var k in root.cache) {
                if (root.cache[k].timestamp < oldestTime) {
                    oldestTime = root.cache[k].timestamp
                    oldestKey = k
                }
            }
            if (oldestKey) root.remove(oldestKey)
        }
        root.cache[key] = {
            data: data,
            timestamp: Date.now(),
            expiresAt: Date.now() + (ttl || root.defaultTtl)
        }
    }

    function remove(key) {
        delete root.cache[key]
    }

    function invalidatePrefix(prefix) {
        for (var k in root.cache) {
            if (k.startsWith(prefix)) {
                root.remove(k)
            }
        }
    }

    function invalidateRepo(repoId) {
        root.invalidatePrefix("repo:" + repoId + ":")
        root.remove("repo:" + repoId + ":libs")
    }

    function invalidatePath(repoId, path) {
        root.invalidatePrefix("repo:" + repoId + ":" + path.replace(/\//g, ":"))
    }

    function clear() {
        root.cache = ({})
    }

    function getLibraries() {
        return root.get("repo:global:libs")
    }

    function setLibraries(data) {
        root.set("repo:global:libs", data)
    }

    function getFolder(repoId, path) {
        var key = "repo:" + repoId + ":" + (path === "/" ? "root" : path.replace(/\//g, ":"))
        return root.get(key)
    }

    function setFolder(repoId, path, data) {
        var key = "repo:" + repoId + ":" + (path === "/" ? "root" : path.replace(/\//g, ":"))
        root.set(key, data)
    }

    function hasValidCache(key) {
        var entry = root.cache[key]
        if (!entry) return false
        return Date.now() <= entry.expiresAt
    }
}