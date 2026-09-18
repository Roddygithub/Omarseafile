pragma Singleton
import QtQuick

QtObject {
    id: root

    // Favorites are stored as an array of objects:
    // { type: "library", repoId: "...", repoName: "..." }
    // { type: "folder", repoId: "...", repoName: "...", path: "/path", name: "..." }
    property var favorites: []

    // Called by Panel where `setting` is available
    function loadFromSettings(storedJson) {
        try {
            root.favorites = JSON.parse(storedJson)
            if (!Array.isArray(root.favorites)) root.favorites = []
        } catch (e) {
            root.favorites = []
        }
    }

    // Called by Panel where `setting` is available
    function saveToSettings() {
        return JSON.stringify(root.favorites)
    }

    function addLibrary(repoId, repoName) {
        // Check if already exists
        for (var i = 0; i < root.favorites.length; i++) {
            var fav = root.favorites[i]
            if (fav.type === "library" && fav.repoId === repoId) return false
        }
        root.favorites.push({ type: "library", repoId: repoId, repoName: repoName })
        return true
    }

    function addFolder(repoId, repoName, path, name) {
        // Normalize path: ensure empty string for root, otherwise use parent path
        var normPath = (path === "/" || path === "") ? "" : path
        // Check if already exists
        for (var i = 0; i < root.favorites.length; i++) {
            var fav = root.favorites[i]
            if (fav.type === "folder" && fav.repoId === repoId && (fav.path || "") === normPath) return false
        }
        root.favorites.push({ type: "folder", repoId: repoId, repoName: repoName, path: normPath, name: name })
        return true
    }

    function remove(index) {
        if (index >= 0 && index < root.favorites.length) {
            root.favorites.splice(index, 1)
            return true
        }
        return false
    }

    function removeById(repoId, path) {
        var normPath = (path === "/" || path === "") ? "" : path
        for (var i = 0; i < root.favorites.length; i++) {
            var fav = root.favorites[i]
            if (fav.repoId === repoId && (fav.path || "") === normPath) {
                root.favorites.splice(i, 1)
                return true
            }
        }
        return false
    }

    function isFavorite(repoId, path) {
        var normPath = (path === "/" || path === "") ? "" : path
        for (var i = 0; i < root.favorites.length; i++) {
            var fav = root.favorites[i]
            if (fav.repoId === repoId && (fav.path || "") === normPath) return true
        }
        return false
    }

    function getLibraries() {
        var result = []
        for (var i = 0; i < root.favorites.length; i++) {
            if (root.favorites[i].type === "library") result.push(root.favorites[i])
        }
        return result
    }

    function getFolders() {
        var result = []
        for (var i = 0; i < root.favorites.length; i++) {
            if (root.favorites[i].type === "folder") result.push(root.favorites[i])
        }
        return result
    }
}