pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root

    readonly property int maxBasenameLength: 255
    readonly property int maxCacheBytes: 1073741824  // 1 GiB (fits in int32)
    property var _protectedCacheNames: []

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
            var home = Quickshell.env("HOME")
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
        if (!subdir || !/^[A-Za-z0-9_-]{1,64}$/.test(subdir)) {
            callback({ valid: false, error: "Invalid runtime subdirectory" })
            return
        }
        var runtimeDir = Quickshell.env("XDG_RUNTIME_DIR")
        if (!runtimeDir) {
            callback({ valid: false, error: "XDG_RUNTIME_DIR not set" })
            return
        }
        var uidProc = _statFactory.createObject(root, {
            onDone: function(expectedUidOutput) {
                if (!expectedUidOutput || !/^\d+$/.test(expectedUidOutput)) {
                    callback({ valid: false, error: "Cannot determine current user UID" })
                    return
                }
                var expectedUid = parseInt(expectedUidOutput, 10)
                var proc = _statFactory.createObject(root, {
                    onDone: function(out) {
                        var parts = out ? out.split(" ") : []
                        if (parts.length !== 2 || !/^\d+$/.test(parts[0]) || !/^[0-7]+$/.test(parts[1])) {
                            callback({ valid: false, error: "Cannot stat XDG_RUNTIME_DIR" })
                            return
                        }
                        var uid = parseInt(parts[0], 10)
                        var perm = parseInt(parts[1], 8)
                        if (uid !== expectedUid) {
                            callback({ valid: false, error: "XDG_RUNTIME_DIR not owned by current user" })
                            return
                        }
                        if (perm & 0o022) {
                            callback({ valid: false, error: "XDG_RUNTIME_DIR has unsafe permissions" })
                            return
                        }
                        var dir = runtimeDir + "/omarseafile/" + subdir
                        var mk = _mkdirFactory.createObject(root, {
                            onDone: function(ok) {
                                if (!ok) { callback({ valid: false, error: "Cannot create runtime subdir" }); return }
                                var verify = _statFactory.createObject(root, {
                                    onDone: function(out2) {
                                        var parts2 = out2 ? out2.split(" ") : []
                                        if (parts2.length !== 2 || !/^\d+$/.test(parts2[0]) || !/^[0-7]+$/.test(parts2[1])) {
                                            callback({ valid: false, error: "Cannot verify runtime subdir" })
                                            return
                                        }
                                        var uid2 = parseInt(parts2[0], 10)
                                        var perm2 = parseInt(parts2[1], 8)
                                        if (uid2 !== expectedUid || perm2 !== 0o700) {
                                            callback({ valid: false, error: "Runtime subdir has incorrect ownership or permissions" })
                                            return
                                        }
                                        callback({ valid: true, path: dir })
                                    }
                                })
                                verify.command = ["stat", "-c", "%u %a", dir]
                                verify.running = true
                            }
                        })
                        mk.command = ["mkdir", "-p", "-m", "0700", "--", dir]
                        mk.running = true
                    }
                })
                proc.command = ["stat", "-c", "%u %a", runtimeDir]
                proc.running = true
            }
        })
        uidProc.command = ["id", "-u"]
        uidProc.running = true
    }

    function getCacheDir(callback) {
        var cacheRoot = Quickshell.env("XDG_CACHE_HOME")
        if (!cacheRoot) {
            var home = Quickshell.env("HOME")
            if (!home) {
                callback({ valid: false, error: "No cache directory available" })
                return
            }
            cacheRoot = home + "/.cache"
        }
        if (!cacheRoot.startsWith("/")) {
            callback({ valid: false, error: "XDG_CACHE_HOME must be absolute" })
            return
        }
        // Create the configured root on first use, then canonicalize it before
        // checking ownership and permissions. Existing symlinks resolve before
        // validation and cannot become Omarseafile's private directory.
        var ensure = _mkdirFactory.createObject(root, {
            onDone: function(ok) {
                if (!ok) { callback({ valid: false, error: "Cannot create cache root" }); return }
                var checkRoot = _statFactory.createObject(root, {
                    onDone: function(kind) {
                        if (kind !== "directory") { callback({ valid: false, error: "Cache root must be a directory" }); return }
                        var canonicalize = _realpathFactory.createObject(root, {
                            onDone: function(path) {
                                if (!path) { callback({ valid: false, error: "Cannot resolve cache directory" }); return }
                                root._getCacheDirAt(path, callback)
                            }
                        })
                        canonicalize.command = ["realpath", "-e", "--", cacheRoot]
                        canonicalize.running = true
                    }
                })
                checkRoot.command = ["stat", "-c", "%F", "--", cacheRoot]
                checkRoot.running = true
            }
        })
        ensure.command = ["mkdir", "-p", "-m", "0700", "--", cacheRoot]
        ensure.running = true
    }

    function getDownloadsDir(callback) {
        var home = Quickshell.env("HOME")
        var proc = _realpathFactory.createObject(root, {
            onDone: function(path) {
                callback(path && path.startsWith("/") ? path : (home ? home + "/Downloads" : null))
            }
        })
        proc.command = ["xdg-user-dir", "DOWNLOAD"]
        proc.running = true
    }

    function _getCacheDirAt(cacheRoot, callback) {
        var uidProc = _statFactory.createObject(root, {
            onDone: function(expectedUidOutput) {
                if (!expectedUidOutput || !/^\d+$/.test(expectedUidOutput)) {
                    callback({ valid: false, error: "Cannot determine current user UID" })
                    return
                }
                var expectedUid = parseInt(expectedUidOutput, 10)
                var proc = _statFactory.createObject(root, {
                    onDone: function(out) {
                        var parts = out ? out.split(" ") : []
                        if (parts.length !== 2 || !/^\d+$/.test(parts[0]) || !/^[0-7]+$/.test(parts[1])) {
                            callback({ valid: false, error: "Cannot stat cache directory" })
                            return
                        }
                        var uid = parseInt(parts[0], 10)
                        var perm = parseInt(parts[1], 8)
                        if (uid !== expectedUid || perm & 0o022) {
                            callback({ valid: false, error: "Cache directory has unsafe ownership or permissions" })
                            return
                        }
                        var dir = cacheRoot + "/omarseafile"
                        var mk = _mkdirFactory.createObject(root, {
                            onDone: function(ok) {
                                if (!ok) { callback({ valid: false, error: "Cannot create cache directory" }); return }
                                var verify = _statFactory.createObject(root, {
                                    onDone: function(out2) {
                                        var parts2 = out2 ? out2.split(" ") : []
                                        if (parts2.length !== 2 || !/^\d+$/.test(parts2[0]) || !/^[0-7]+$/.test(parts2[1])) {
                                            callback({ valid: false, error: "Cannot verify cache directory" })
                                            return
                                        }
                                        if (parseInt(parts2[0], 10) !== expectedUid || parseInt(parts2[1], 8) !== 0o700) {
                                            callback({ valid: false, error: "Cache directory has incorrect ownership or permissions" })
                                            return
                                        }
                                        callback({ valid: true, path: dir })
                                    }
                                })
                                verify.command = ["stat", "-c", "%u %a", dir]
                                verify.running = true
                            }
                        })
                        mk.command = ["mkdir", "-p", "-m", "0700", "--", dir]
                        mk.running = true
                    }
                })
                proc.command = ["stat", "-c", "%u %a", cacheRoot]
                proc.running = true
            }
        })
        uidProc.command = ["id", "-u"]
        uidProc.running = true
    }

    property Component _evictCacheFactory: Component {
        Process {
            property var onDone: null
            onExited: function(exitCode) {
                var cb = onDone
                destroy()
                if (cb) cb(exitCode === 0)
            }
        }
    }

    function _validCacheName(name) {
        return typeof name === "string" && /^[A-Za-z0-9._-]{1,128}$/.test(name)
    }

    function protectCache(name) {
        if (!_validCacheName(name) || root._protectedCacheNames.indexOf(name) !== -1) return
        root._protectedCacheNames = root._protectedCacheNames.concat([name])
    }

    function releaseCache(name, callback) {
        if (!_validCacheName(name)) { if (callback) callback(true); return }
        root._protectedCacheNames = root._protectedCacheNames.filter(function(protectedName) {
            return protectedName !== name
        })
        getCacheDir(function(cacheResult) {
            if (!cacheResult.valid) { if (callback) callback(false); return }
            var proc = _evictCacheFactory.createObject(root, {
                onDone: function(ok) { if (callback) callback(ok) }
            })
            proc.command = ["rm", "-f", "--", cacheResult.path + "/.active_" + name]
            proc.running = true
        })
    }

    // Evict oldest cache files until total size <= maxCacheBytes.
    // Delegates to scripts/cache_evict.py which uses a held O_DIRECTORY|O_NOFOLLOW
    // directory FD, lstat semantics, and PID-backed active-download markers.
    function evictCache(protectedNames, callback, maxBytes) {
        if (typeof protectedNames === "function") {
            callback = protectedNames
            protectedNames = []
        }
        protectedNames = protectedNames || []
        var effectiveProtected = root._protectedCacheNames.slice()
        for (var i = 0; i < protectedNames.length; i++) {
            if (effectiveProtected.indexOf(protectedNames[i]) === -1) effectiveProtected.push(protectedNames[i])
        }
        getCacheDir(function(cacheResult) {
            if (!cacheResult.valid) { if (callback) callback(false); return }
            var scriptsBase = Qt.resolvedUrl("../scripts")
            var helper = scriptsBase + "/cache_evict.py"
            var evictProc = _evictCacheFactory.createObject(root, {
                onDone: function(ok) {
                    if (callback) callback(ok)
                }
            })
            evictProc.command = [
                "python3",
                helper.replace(/^file:\/\//, ""),
                cacheResult.path,
                String(maxBytes === undefined ? root.maxCacheBytes : maxBytes)
            ].concat(effectiveProtected)
            evictProc.running = true
        })
    }

    // Clear only safe, non-active files in Omarseafile's private cache.
    function clearPersistentCache(callback) {
        root.evictCache([], function(ok) {
            if (callback) callback(ok || root._protectedCacheNames.length > 0)
        }, 0)
    }

    // Atomic writer: single Python process using mkstemp for exclusive creation,
    // mode 0600 enforced on the open fd, content via stdin, path via stdout
    property Component _atomicTimeoutFactory: Component {
        Timer {
            property var targetProcess: null
            interval: 30000
            repeat: false
            onTriggered: {
                if (targetProcess) targetProcess.running = false
            }
        }
    }

    property Component _atomicWriterFactory: Component {
        Process {
            id: atomicProc
            property var onDone: null
            property string writeContent: ""
            property var writeTimeout: null
            stdinEnabled: true
            stdout: StdioCollector {}
            onStarted: {
                atomicProc.write(writeContent)
                atomicProc.stdinEnabled = false
                writeTimeout = root._atomicTimeoutFactory.createObject(root, { targetProcess: atomicProc })
                writeTimeout.start()
            }
            onExited: function(exitCode) {
                if (writeTimeout) {
                    writeTimeout.stop()
                    writeTimeout.destroy()
                    writeTimeout = null
                }
                var cb = onDone
                var out = stdout.text.trim()
                destroy()
                if (cb) cb(exitCode === 0 ? out : null)
            }
        }
    }

    // Creates a secure temp file atomically: single writer process using mkstemp
    // dir: subdirectory under omarseafile/ (e.g., "secrets", "transfers", "cache", "http")
    // prefix: filename prefix
    // content: file content to write atomically via stdin
    // callback(result): { valid: true, path } or { valid: false, error }
    function createSecureFile(dir, prefix, content, callback) {
        getRuntimeSubdir(dir, function(runtimeResult) {
            if (!runtimeResult.valid) { callback({ valid: false, error: runtimeResult.error }); return }
            var safePrefix = prefix.replace(/[^a-zA-Z0-9_-]/g, "_")
            var proc = _atomicWriterFactory.createObject(root, {
                onDone: function(path) {
                    if (!path) {
                        callback({ valid: false, error: "Atomic write failed" })
                    } else {
                        callback({ valid: true, path: path })
                    }
                }
            })
            var scriptsBase = Qt.resolvedUrl("../scripts")
            var scriptPath = scriptsBase + "/atomic_write.py"
            proc.command = [
                "python3",
                scriptPath.replace(/^file:\/\//, ""),
                runtimeResult.path, safePrefix
            ]
            proc.writeContent = content === undefined || content === null ? "" : String(content)
            proc.running = true
        })
    }
}
