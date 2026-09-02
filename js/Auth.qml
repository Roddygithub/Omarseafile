pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root

    readonly property string attrService: "service"
    readonly property string attrKey: "key"
    readonly property string valService: "seafile"
    readonly property string keyToken: "auth-token"
    readonly property string keyServer: "server-url"
    readonly property string keyEmail: "user-email"
    property var _sessionMutationTail: null

    function _queueSessionMutation(mutation) {
        var previous = root._sessionMutationTail || Promise.resolve()
        var result = previous.then(mutation, mutation)
        root._sessionMutationTail = result.then(function() {}, function() {})
        return result
    }

    // Factory: one short-lived Process per secret-tool invocation with timeout.
    property Component procFactory: Component {
        Process {
            id: proc
            property var onDone: null
            property string inputPayload: ""
            stdinEnabled: true
            stdout: StdioCollector {}
            stderr: StdioCollector {}

            onStarted: {
                if (inputPayload !== "") {
                    proc.write(inputPayload)
                    proc.stdinEnabled = false
                }
            }

            onExited: function(exitCode, exitStatus) {
                var code = exitCode
                var text = proc.stdout.text.trim()
                var cb = proc.onDone
                proc.destroy()
                if (cb) cb(code, text)
            }
        }
    }

    // Run one command, resolve(stdoutText) on success, reject(Error) on failure.
    // `lookupIsSoft`: exit code 1 means "not found" and resolves with "".
    function _run(cmd, input, lookupIsSoft) {
        return new Promise(function(resolve, reject) {
            var proc = root.procFactory.createObject(root, {
                inputPayload: (input !== undefined && input !== null) ? input : "",
                onDone: function(exitCode, text) {
                    if (timer) timer.stop()
                    if (exitCode === 0) { resolve(text); return }
                    if (lookupIsSoft && exitCode === 1) { resolve(""); return }
                    reject(new Error(cmd.join(" ") + " failed (exit " + exitCode + ")"))
                }
            })
            proc.command = cmd
            proc.running = true
            var timer = Qt.createQmlObject('import QtQuick; Timer { interval: 30000; repeat: false; onTriggered: { if (targetProcess) targetProcess.kill() } }', root)
            timer.targetProcess = proc
            timer.start()
        })
    }

    function storeToken(token, serverUrl, email) {
        var steps = [
            { cmd: ["secret-tool", "store", "--label=Seafile Auth Token", root.attrService, root.valService, root.attrKey, root.keyToken], input: token },
            { cmd: ["secret-tool", "store", "--label=Seafile Server URL", root.attrService, root.valService, root.attrKey, root.keyServer], input: serverUrl },
            { cmd: ["secret-tool", "store", "--label=Seafile User Email", root.attrService, root.valService, root.attrKey, root.keyEmail], input: email }
        ]
        var index = 0
        return root._queueSessionMutation(function() {
            root.cachedToken = token
            root.cachedServerUrl = serverUrl
            root.cachedEmail = email
            return new Promise(function(resolve, reject) {
                function next() {
                    if (index >= steps.length) { resolve(); return }
                    var step = steps[index]
                    index++
                    root._run(step.cmd, step.input, false).then(next, reject)
                }
                next()
            })
        })
    }

    // ===== SYNCHRONOUS CACHE =====
    // Synchronous callers read the cache populated by login or the serialized
    // startup lookup; getters never start a stale background keyring read.
    property string cachedToken: ""
    property string cachedServerUrl: ""
    property string cachedEmail: ""

    function _lookup(keyAttr) {
        return root._run(["secret-tool", "lookup", root.attrService, root.valService, root.attrKey, keyAttr], null, true)
    }

    function getToken() {
        return root.cachedToken
    }

    function getServerUrl() {
        return root.cachedServerUrl
    }

    function getEmail() {
        return root.cachedEmail
    }

    function clearSession() {
        var keys = [root.keyToken, root.keyServer, root.keyEmail]
        var index = 0
        return root._queueSessionMutation(function() {
            root.cachedToken = ""
            root.cachedServerUrl = ""
            root.cachedEmail = ""
            return new Promise(function(resolve, reject) {
                var firstError = null
                function next() {
                    if (index >= keys.length) {
                        if (firstError) reject(firstError)
                        else resolve()
                        return
                    }
                    var key = keys[index]
                    index++
                    root._run(["secret-tool", "clear", root.attrService, root.valService, root.attrKey, key], null, true).then(next, function(error) {
                        if (!firstError) firstError = error
                        next()
                    })
                }
                next()
            })
        })
    }

    function isAuthenticated() {
        if (root.cachedToken !== "" && root.cachedServerUrl !== "" && root.cachedEmail !== "") return Promise.resolve(true)
        return root._queueSessionMutation(function() {
            return root._lookup(root.keyToken).then(function(token) {
                root.cachedToken = token
                if (token === "") return false
                return root._lookup(root.keyServer).then(function(u) {
                    root.cachedServerUrl = u
                    return root._lookup(root.keyEmail).then(function(e) {
                        root.cachedEmail = e
                        return u !== "" && e !== ""
                    })
                })
            })
        })
    }

    function validateSession(token) {
        if (!token) return false
        return token.length > 20
    }

    function checkDependency(cmd) {
        return new Promise(function(resolve) {
            var proc = root.procFactory.createObject(root, {
                onDone: function(exitCode, text) { resolve(exitCode === 0) }
            })
            proc.command = ["which", cmd]
            proc.running = true
        })
    }

    function checkDependencies() {
        return new Promise(function(resolve) {
            var checks = [
                { cmd: "curl", name: "curl", install: "sudo pacman -S curl", required: true },
                { cmd: "secret-tool", name: "secret-tool (libsecret)", install: "sudo pacman -S libsecret", required: true },
                { cmd: "wl-copy", name: "wl-copy (wl-clipboard)", install: "sudo pacman -S wl-clipboard", required: false }
            ]
            var missing = []
            var index = 0
            function checkNext() {
                if (index >= checks.length) { resolve(missing); return }
                checkDependency(checks[index].cmd).then(function(exists) {
                    if (!exists) missing.push(checks[index])
                    index++
                    checkNext()
                })
            }
            checkNext()
        })
    }
}
