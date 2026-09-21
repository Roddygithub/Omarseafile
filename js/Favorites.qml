pragma Singleton
import QtQuick

// Quick Access ("favorites") store.
//
// Identity
//   library favorite : type + repoId
//   folder  favorite : type + repoId + normalized FULL folder path
// Sibling folders under the same parent therefore stay distinct, and a
// library favorite can never collide with a root-level folder favorite.
//
// Reactivity
//   Every mutation reassigns a fresh array/object. QML's var properties only
//   emit changed() on reassignment, so push()/splice() alone would silently
//   leave bound models stale.
//
// Account scope
//   Entries live under an account key derived from the normalized server URL
//   plus the authenticated email. Never the token or password. The active key
//   is "" while signed out, which yields an empty in-memory view.
QtObject {
    id: root

    // accountKey -> array of favorite records
    property var store: ({})
    // account keys whose legacy unscoped `favorites` blob was already absorbed
    property var legacyMigratedKeys: []
    // account key currently signed in; "" means signed out
    property string activeKey: ""
    // bumped on every mutation so bindings that read through helper functions
    // re-evaluate even when the underlying array identity is unchanged
    property int revision: 0

    // Legacy (pre-1.1) unscoped blob, retained only so it can be migrated once.
    property var _legacyEntries: []

    // ===== IDENTITY =====

    // Folder paths are stored normalized: "" for the library root, otherwise a
    // single leading slash, no trailing slash and no duplicate separators.
    function normalizePath(path) {
        if (path === null || path === undefined) return ""
        var p = String(path)
        if (p === "" || p === "/") return ""
        var segments = p.split("/")
        var out = []
        for (var i = 0; i < segments.length; i++) {
            if (segments[i] !== "" && segments[i] !== ".") out.push(segments[i])
        }
        if (out.length === 0) return ""
        return "/" + out.join("/")
    }

    // Full path of a folder favorite, built from its parent directory and name.
    function folderFullPath(parentPath, name) {
        var parent = root.normalizePath(parentPath)
        var leaf = name === null || name === undefined ? "" : String(name)
        return parent === "" ? "/" + leaf : parent + "/" + leaf
    }

    // Stable identity for a record. Type is always part of the key.
    function keyFor(record) {
        if (!record) return ""
        if (record.type === "library") return "library|" + (record.repoId || "")
        if (record.type === "folder") return "folder|" + (record.repoId || "") + "|" + root.normalizePath(record.path)
        return ""
    }

    // Account identity. URL + email only — never a token or password.
    // Only the scheme and hostname are lowercased: a URL path/subpath is
    // case-sensitive and must be preserved exactly.
    function makeAccountKey(serverUrl, email) {
        var raw = serverUrl === null || serverUrl === undefined ? "" : String(serverUrl).trim()
        var id = email === null || email === undefined ? "" : String(email).trim().toLowerCase()
        var url = ""
        if (raw !== "") {
            var parsed
            try {
                parsed = new URL(raw)
                var scheme = parsed.protocol.replace(":", "").toLowerCase()
                var host = parsed.hostname.toLowerCase()
                var port = parsed.port ? ":" + parsed.port : ""
                var path = parsed.pathname.replace(/\/+$/, "")
                var search = parsed.search || ""
                var hash = parsed.hash || ""
                url = scheme + "://" + host + port + path + search + hash
            } catch (e) {
                // Not a parseable URL: fall back to lowercasing the scheme and
                // authority only, preserving any path verbatim.
                var m = /^([a-z][a-z0-9+.-]*):\/\/([^/]+)/i.exec(raw)
                if (m) {
                    url = m[1].toLowerCase() + "://" + m[2].toLowerCase() + raw.substring(m.index + m[0].length)
                } else {
                    url = raw.toLowerCase()
                }
            }
        }
        if (url === "" && id === "") return ""
        return url + "|" + id
    }

    // ===== ACCOUNT LIFECYCLE =====

    function _readStore(raw) {
        if (!raw) return {}
        if (typeof raw === "string") {
            try {
                raw = JSON.parse(raw)
            } catch (e) {
                return {}
            }
        }
        if (typeof raw !== "object" || Array.isArray(raw)) return {}
        var out = {}
        for (var k in raw) {
            if (Array.isArray(raw[k])) out[k] = root._sanitizeList(raw[k])
        }
        return out
    }

    // Drops records without a usable identity so a corrupt blob cannot wedge
    // the Quick Access list.
    function _sanitizeList(list) {
        var out = []
        for (var i = 0; i < list.length; i++) {
            var rec = list[i]
            if (!rec || typeof rec !== "object") continue
            if (rec.type !== "library" && rec.type !== "folder") continue
            if (!rec.repoId) continue
            out.push({
                type: rec.type,
                repoId: String(rec.repoId),
                repoName: rec.repoName === undefined || rec.repoName === null ? "" : String(rec.repoName),
                path: rec.type === "folder" ? root.normalizePath(rec.path) : "",
                name: rec.name === undefined || rec.name === null ? "" : String(rec.name)
            })
        }
        return out
    }

    // Called by Panel where `setting` is available.
    function loadFromSettings(storeJson, legacyJson, migratedJson) {
        root.store = root._readStore(storeJson)
        var migrated = []
        try {
            var parsedMigrated = migratedJson ? JSON.parse(migratedJson) : []
            if (Array.isArray(parsedMigrated)) {
                for (var i = 0; i < parsedMigrated.length; i++) migrated.push(String(parsedMigrated[i]))
            }
        } catch (e) {
            migrated = []
        }
        root.legacyMigratedKeys = migrated

        var legacy = []
        try {
            var parsedLegacy = legacyJson ? JSON.parse(legacyJson) : []
            if (Array.isArray(parsedLegacy)) legacy = root._sanitizeList(parsedLegacy)
        } catch (e) {
            legacy = []
        }
        root._legacyEntries = legacy
    }

    // Called by Panel where `setting` is available.
    function saveToSettings() {
        return JSON.stringify(root.store)
    }

    function saveMigratedKeys() {
        return JSON.stringify(root.legacyMigratedKeys)
    }

    function hasLegacyEntries() {
        return root._legacyEntries.length > 0
    }

    // Activate the account scope. Deterministic one-time migration: a legacy
    // unscoped blob is absorbed into this account the first time it is seen,
    // and never imported again for that key.
    function setAccountKey(serverUrl, email) {
        var key = root.makeAccountKey(serverUrl, email)
        if (key === "") return
        root.activeKey = key
        var already = root.legacyMigratedKeys.indexOf(key) !== -1
        if (root._legacyEntries.length === 0 || already) {
            root.revision++
            return
        }
        var merged = root._mergedList(root.store[key] || [], root._legacyEntries)
        var next = {}
        for (var k in root.store) next[k] = root.store[k]
        next[key] = merged
        root.store = next
        var keys = root.legacyMigratedKeys.slice()
        keys.push(key)
        root.legacyMigratedKeys = keys
        root._legacyEntries = []
        root.revision++
    }

    // Logout: forget the active scope. The persisted store is untouched, so
    // signing back in restores exactly this account's entries.
    function clearActiveScope() {
        root.activeKey = ""
        root.revision++
    }

    function _mergedList(existing, incoming) {
        var out = []
        var seen = {}
        var i
        for (i = 0; i < existing.length; i++) {
            var ek = root.keyFor(existing[i])
            if (ek === "" || seen[ek] === true) continue
            seen[ek] = true
            out.push(existing[i])
        }
        for (i = 0; i < incoming.length; i++) {
            var ik = root.keyFor(incoming[i])
            if (ik === "" || seen[ik] === true) continue
            seen[ik] = true
            out.push(incoming[i])
        }
        return out
    }

    function _currentList() {
        if (root.activeKey === "") return []
        var list = root.store[root.activeKey]
        return Array.isArray(list) ? list : []
    }

    function _replaceCurrent(list) {
        var next = {}
        for (var k in root.store) next[k] = root.store[k]
        next[root.activeKey] = list
        root.store = next
        root.revision++
    }

    // ===== QUERIES =====

    function all() {
        // Read revision so callers that depend on the whole set re-evaluate.
        var rev = root.revision
        void rev
        return root._currentList().slice()
    }

    function find(type, repoId, path) {
        var target = root.keyFor({ type: type, repoId: repoId, path: path })
        if (target === "") return null
        var list = root._currentList()
        for (var i = 0; i < list.length; i++) {
            if (root.keyFor(list[i]) === target) return list[i]
        }
        return null
    }

    function isLibraryFavorite(repoId) {
        return root.find("library", repoId, "") !== null
    }

    // Folder identity is the FULL path, so siblings never collide.
    function isFolderFavorite(repoId, fullPath) {
        return root.find("folder", repoId, fullPath) !== null
    }

    // Context-menu probe. `path` is the full path for folders and "" for a
    // library-root entry.
    function isFavorite(type, repoId, path) {
        return root.find(type, repoId, path) !== null
    }

    function getLibraries() {
        var rev = root.revision
        void rev
        var out = []
        var list = root._currentList()
        for (var i = 0; i < list.length; i++) {
            if (list[i].type === "library") out.push(list[i])
        }
        return out
    }

    function getFolders() {
        var rev = root.revision
        void rev
        var out = []
        var list = root._currentList()
        for (var i = 0; i < list.length; i++) {
            if (list[i].type === "folder") out.push(list[i])
        }
        return out
    }

    function count() {
        return root.getLibraries().length + root.getFolders().length
    }

    // ===== MUTATIONS =====
    // Every mutator returns { changed: bool, error: string } so the caller can
    // persist only on a real change and surface a useful message otherwise.

    function addLibrary(repoId, repoName) {
        if (root.activeKey === "") return { changed: false, error: "Not signed in" }
        if (!repoId) return { changed: false, error: "Missing library identity" }
        if (root.isLibraryFavorite(repoId)) return { changed: false, error: "" }
        var list = root._currentList().slice()
        list.push({ type: "library", repoId: String(repoId), repoName: repoName || "", path: "", name: repoName || "" })
        root._replaceCurrent(list)
        return { changed: true, error: "" }
    }

    // `fullPath` must be the folder's own full path, not its parent.
    function addFolder(repoId, repoName, fullPath, name) {
        if (root.activeKey === "") return { changed: false, error: "Not signed in" }
        if (!repoId) return { changed: false, error: "Missing library identity" }
        var path = root.normalizePath(fullPath)
        if (path === "") return { changed: false, error: "Folder path cannot be the library root" }
        if (root.isFolderFavorite(repoId, path)) return { changed: false, error: "" }
        var leaf = name || path.substring(path.lastIndexOf("/") + 1)
        var list = root._currentList().slice()
        list.push({ type: "folder", repoId: String(repoId), repoName: repoName || "", path: path, name: leaf })
        root._replaceCurrent(list)
        return { changed: true, error: "" }
    }

    // Identity comes from the record itself, never from the current browsing
    // context — removal must work from Home while currentRepo is null.
    function removeEntry(entry) {
        if (root.activeKey === "") return { changed: false, error: "Not signed in" }
        var target = root.keyFor(entry)
        if (target === "") return { changed: false, error: "Not a Quick Access entry" }
        var list = root._currentList()
        var next = []
        var removed = false
        for (var i = 0; i < list.length; i++) {
            if (!removed && root.keyFor(list[i]) === target) { removed = true; continue }
            next.push(list[i])
        }
        if (!removed) return { changed: false, error: "Entry not found" }
        root._replaceCurrent(next)
        return { changed: true, error: "" }
    }

    function removeLibrary(repoId) {
        return root.removeEntry({ type: "library", repoId: repoId, path: "" })
    }

    function removeFolder(repoId, fullPath) {
        return root.removeEntry({ type: "folder", repoId: repoId, path: fullPath })
    }

    // Library-root context-menu probe/removal helper (path "" === the library).
    function removeById(repoId, path) {
        var normalized = root.normalizePath(path)
        if (normalized === "") return root.removeLibrary(repoId)
        return root.removeFolder(repoId, normalized)
    }

    function clearActive() {
        if (root.activeKey === "") return { changed: false, error: "Not signed in" }
        if (root._currentList().length === 0) return { changed: false, error: "" }
        root._replaceCurrent([])
        return { changed: true, error: "" }
    }
}
