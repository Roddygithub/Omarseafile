pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root

    readonly property int maxBasenameLength: 255

    property Component _mkdirFactory: Component {
        Process {
            property var onDone: null
            onExited: function(exitCode) {
                var cb = onDone
                destroy()
                if (cb) cb(exitCode === 0)
            }
        }
    }

    property Component _realpathFactory: Component {
        Process {
            property var onDone: null
            stdout: StdioCollector {}
            onExited: function(exitCode) {
                var cb = onDone
                var out = stdout.text.trim()
                destroy()
                if (cb) cb(exitCode === 0 ? out : null)
            }
        }
    }

    property Component _statFactory: Component {
        Process {
            property var onDone: null
            stdout: StdioCollector {}
            onExited: function(exitCode) {
                var cb = onDone
                var out = stdout.text.trim()
                destroy()
                if (cb) cb(exitCode === 0 ? out : null)
            }
        }
    }

    property Component _mktempFactory: Component {
        Process {
            property var onDone: null
            stdout: StdioCollector {}
            onExited: function(exitCode) {
                var cb = onDone
                var out = stdout.text.trim()
                destroy()
                if (cb) cb(exitCode === 0 ? out : null)
            }
        }
    }

    function sanitizeBasename(name) {
        if (!name || typeof name !== "string") {
            return { valid: false, error: "Empty filename" }
        }
        var trimmed = name.trim()
        if (trimmed === "") {
            return { valid: false, error: "Filename is whitespace only" }
        }
        if (trimmed === "." || trimmed === "..") {
            return { valid: false, error: "Reserved filename: " + trimmed }
        }
        if (trimmed.indexOf("/") !== -1 || trimmed.indexOf("\\") !== -1) {
            return { valid: false, error: "Path separators not allowed in filename" }
        }
        if (trimmed.indexOf("\0") !== -1) {
            return { valid: false, error: "NUL character not allowed" }
        }
        for (var i = 0; i < trimmed.length; i++) {
            var code = trimmed.charCodeAt(i)
            if (code < 0x20 || code === 0x7F) {
                return { valid: false, error: "Control characters not allowed" }
            }
        }
        if (trimmed.length > 255) {
            return { valid: false, error: "Filename exceeds maximum length of 255" }
        }
        return { valid: true, sanitized: trimmed }
    }

    function secureJoin(baseDir, name, callback) {
        validateDirectory(baseDir, function(baseResult) {
            if (!baseResult.valid) { callback(baseResult); return }
            var nameResult = sanitizeBasename(name)
            if (!nameResult.valid) { callback(nameResult); return }
            callback({ valid: true, path: baseResult.resolved + "/" + nameResult.sanitized, base: baseResult.resolved, name: nameResult.sanitized })
        })
    }

    function validateDirectory(dir, callback) {
        if (!dir || typeof dir !== "string") {
            callback({ valid: false, error: "Empty directory" })
            return
        }
        var expanded = dir
        if (dir.startsWith("~")) {
            var home = Qt.Quickshell.env("HOME")
            if (home) expanded = home + dir.substring(1)
        }
        var proc = _realpathFactory.createObject(root, {
            onDone: function(path) {
                if (!path) { callback({ valid: false, error: "Cannot resolve directory" }); return }
                callback({ valid: true, resolved: path })
            }
        })
        proc.command = ["realpath", "-m", "--", expanded]
        proc.running = true
    }

    function getRuntimeSubdir(subdir, callback) {
        var runtimeDir = Qt.Quickshell.env("XDG_RUNTIME_DIR")
        if (!runtimeDir) {
            callback({ valid: false, error: "XDG_RUNTIME_DIR not set" })
            return
        }
        var proc = _statFactory.createObject(root, {
            onDone: function(out) {
                if (!out) { callback({ valid: false, error: "Cannot stat XDG_RUNTIME_DIR" }); return }
                var parts = out.split(" ")
                var uid = parseInt(parts[0], 10)
                var mode = parts[1]
                if (uid !== Qt.Quickshell.env("UID")) {
                    callback({ valid: false, error: "XDG_RUNTIME_DIR not owned by current user" })
                    return
                }
                // Check mode - should not be world/group writable
                var perm = parseInt(mode.slice(-3), 8)
                if (perm & 0o022) {
                    callback({ valid: false, error: "XDG_RUNTIME_DIR has unsafe permissions" })
                    return
                }
                var dir = Qt.Quickshell.env("XDG_RUNTIME_DIR") + "/omarseafile"
                var mk = _mkdirFactory.createObject(root, {
                    onDone: function(ok) {
                        if (!ok) { callback({ valid: false, error: "Cannot create runtime subdir" }); return }
                        // Verify subdir mode and ownership after creation
                        var verify = _statFactory.createObject(root, {
                            onDone: function(out2) {
                                if (!out2) { callback({ valid: false, error: "Cannot verify runtime subdir" }); return }
                                var parts2 = out2.split(" ")
                                var uid2 = parseInt(parts2[0], 10)
                                var mode2 = parts2[1]
                                var perm2 = parseInt(mode2.slice(-3), 8)
                                if (uid2 !== Qt.Quickshell.env("UID") || perm2 !== 0o700) {
                                    callback({ valid: false, error: "Runtime subdir has incorrect ownership or permissions" })
                                    return
                                }
                                callback({ valid: true, path: Qt.Quickshell.env("XDG_RUNTIME_DIR") + "/omarseafile" })
                            }
                        })
                        verify.command = ["stat", "-c", "%u %A", Qt.Quickshell.env("XDG_RUNTIME_DIR") + "/omarseafile"]
                        verify.running = true
                    }
                })
                mk.command = ["mkdir", "-p", "-m", "0700", "--", Qt.Quickshell.env("XDG_RUNTIME_DIR") + "/omarseafile"]
                mk.running = true
            }
        })
        proc.command = ["stat", "-c", "%u %A", Qt.Quickshell.env("XDG_RUNTIME_DIR")]
        proc.running = true
    }

    function createSecureTempFile(dir, prefix, callback) {
        var prefixSafe = prefix.replace(/[^a-zA-Z0-9_-]/g, "_")
        var proc = _mktempFactory.createObject(root, {
            onDone: function(path) {
                if (!path) {
                    callback({ valid: false, error: "Failed to create secure temp file" })
                } else {
                    callback({ valid: true, path: path })
                }
            }
        })
        proc.command = ["mktemp", "--", dir + "/" + prefix.replace(/[^a-zA-Z0-9_-]/g, "_") + "_XXXXXX"]
        proc.running = true
    }
}