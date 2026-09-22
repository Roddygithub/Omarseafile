pragma Singleton
import QtQuick

QtObject {
    id: root

    property var cache: ({})
    property int defaultTtl: 30000
    property int maxEntries: 100
    // JSON tuples preserve server/account/resource/path boundaries; the local
    // generation prevents reuse across logins, even for the same account.
    property string scope: "anonymous"
    property double sessionGeneration: 0
    function scopedKey(key) { return JSON.stringify([root.sessionGeneration, root.scope, key]) }

    function get(key) {
        var entry = root.cache[root.scopedKey(key)]
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
            var oldestTime = Infinity
            for (var k in root.cache) {
                if (root.cache[k].timestamp < oldestTime) {
                    oldestTime = root.cache[k].timestamp
                    oldestKey = k
                }
            }
            if (oldestKey) delete root.cache[oldestKey]
        }
        root.cache[root.scopedKey(key)] = {
            data: data,
            timestamp: Date.now(),
            expiresAt: Date.now() + (ttl || root.defaultTtl)
        }
    }

    function remove(key) {
        delete root.cache[root.scopedKey(key)]
    }

    function invalidateRepo(repoId) {
        root.invalidatePath(repoId, "/")
        if (repoId === "global") root.remove(JSON.stringify(["libraries"]))
    }

    function invalidatePath(repoId, path) {
        for (var k in root.cache) {
            var scoped = JSON.parse(k)
            if (scoped[0] !== root.sessionGeneration || scoped[1] !== root.scope) continue
            // Generic get/set keys are also supported; only folder tuples
            // participate in path invalidation.
            var resource
            try { resource = JSON.parse(scoped[2]) } catch (e) { continue }
            if (!Array.isArray(resource)) continue
            if (resource[0] === "folder" && resource[1] === repoId
                && (path === "/" || resource[2] === path || resource[2].startsWith(path + "/"))) {
                delete root.cache[k]
            }
        }
    }

    function clear() {
        root.cache = ({})
        root.sessionGeneration++
    }

    function setScope(serverUrl, account) {
        root.clear()
        // No credentials are included or persisted.
        root.scope = JSON.stringify([String(serverUrl || ""), String(account || "")])
    }

    function getLibraries() {
        return root.get(JSON.stringify(["libraries"]))
    }

    function setLibraries(data) {
        root.set(JSON.stringify(["libraries"]), data)
    }

    function getFolder(repoId, path) {
        return root.get(JSON.stringify(["folder", repoId, path]))
    }

    function setFolder(repoId, path, data) {
        root.set(JSON.stringify(["folder", repoId, path]), data)
    }

    function hasValidCache(key) {
        var entry = root.cache[root.scopedKey(key)]
        if (!entry) return false
        return Date.now() <= entry.expiresAt
    }
}