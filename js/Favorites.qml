pragma Singleton
import QtQuick

QtObject {
    id: root

    // Favorites are stored as an array of objects:
    // { type: "library", repoId: "...", repoName: "..." }
    // { type: "folder", repoId: "...", repoName: "...", path: "/path", name: "..." }
    property var favorites: []

    function load() {
        var stored = setting("favorites", "[]")
        try {
            root.favorites = JSON.parse(stored)
            if (!Array.isArray(root.favorites)) root.favorites = []
        } catch (e) {
            root.favorites = []
        }
    }

    function save() {
        setting("favorites", JSON.stringify(root.favorites))
    }

    function addLibrary(repoId, repoName) {
        // Check if already exists
        for (var i = 0; i < root.favorites.length; i++) {
            var fav = root.favorites[i]
            if (fav.type === "library" && fav.repoId === repoId) return false
        }
        root.favorites.push({ type: "library", repoId: repoId, repoName: repoName })
        root.save()
        return true
    }

    function addFolder(repoId, repoName, path, name) {
        // Check if already exists
        for (var i = 0; i < root.favorites.length; i++) {
            var fav = root.favorites[i]
            if (fav.type === "folder" && fav.repoId === repoId && fav.path === path) return false
        }
        root.favorites.push({ type: "folder", repoId: repoId, repoName: repoName, path: path, name: name })
        root.save()
        return true
    }

    function remove(index) {
        if (index >= 0 && index < root.favorites.length) {
            root.favorites.splice(index, 1)
            root.save()
            return true
        }
        return false
    }

    function removeById(repoId, path) {
        for (var i = 0; i < root.favorites.length; i++) {
            var fav = root.favorites[i]
            if (fav.repoId === repoId && (fav.path || "") === (path || "")) {
                root.favorites.splice(i, 1)
                root.save()
                return true
            }
        }
        return false
    }

    function isFavorite(repoId, path) {
        for (var i = 0; i < root.favorites.length; i++) {
            var fav = root.favorites[i]
            if (fav.repoId === repoId && (fav.path || "") === (path || "")) return true
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

    // Called on startup to load favorites
    Component.onCompleted: root.load()
}