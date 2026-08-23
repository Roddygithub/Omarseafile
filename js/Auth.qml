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

    // Factory: one short-lived Process per secret-tool invocation.
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
                    if (exitCode === 0) { resolve(text); return }
                    if (lookupIsSoft && exitCode === 1) { resolve(""); return }
                    reject(new Error(cmd.join(" ") + " failed (exit " + exitCode + ")"))
                }
            })
            proc.command = cmd
            proc.running = true
        })
    }

    function storeToken(token, serverUrl, email) {
        root.cachedToken = token
        root.cachedServerUrl = serverUrl
        root.cachedEmail = email
        var steps = [
            { cmd: ["secret-tool", "store", "--label=Seafile Auth Token", root.attrService, root.valService, root.attrKey, root.keyToken], input: token },
            { cmd: ["secret-tool", "store", "--label=Seafile Server URL", root.attrService, root.valService, root.attrKey, root.keyServer], input: serverUrl },
            { cmd: ["secret-tool", "store", "--label=Seafile User Email", root.attrService, root.valService, root.attrKey, root.keyEmail], input: email }
        ]
        var index = 0
        return new Promise(function(resolve, reject) {
            function next() {
                if (index >= steps.length) { resolve(); return }
                var step = steps[index]
                index++
                root._run(step.cmd, step.input, false).then(next, reject)
            }
            next()
        })
    }

    // ===== SYNCHRONOUS CACHE =====
    // Restores the pre-0.9 synchronous calling contract: getToken()/getServerUrl()/getEmail()
    // return the cached value immediately; the keyring is refreshed in the background.
    property string cachedToken: ""
    property string cachedServerUrl: ""
    property string cachedEmail: ""

    function _lookup(keyAttr) {
        return root._run(["secret-tool", "lookup", root.attrService, root.valService, root.attrKey, keyAttr], null, true)
    }

    function getToken() {
        root._lookup(root.keyToken).then(function(t) { root.cachedToken = t })
        return root.cachedToken
    }

    function getServerUrl() {
        root._lookup(root.keyServer).then(function(u) { root.cachedServerUrl = u })
        return root.cachedServerUrl
    }

    function getEmail() {
        root._lookup(root.keyEmail).then(function(e) { root.cachedEmail = e })
        return root.cachedEmail
    }

    function clearSession() {
        root.cachedToken = ""
        root.cachedServerUrl = ""
        root.cachedEmail = ""
        var keys = [root.keyToken, root.keyServer, root.keyEmail]
        var index = 0
        return new Promise(function(resolve) {
            function next() {
                if (index >= keys.length) { resolve(); return }
                var key = keys[index]
                index++
                root._run(["secret-tool", "clear", root.attrService, root.valService, root.attrKey, key], null, true).then(next, next)
            }
            next()
        })
    }

    function isAuthenticated() {
        if (root.cachedToken !== "") return Promise.resolve(true)
        return root._lookup(root.keyToken).then(function(token) {
            root.cachedToken = token
            if (token === "") return false
            return root._lookup(root.keyServer).then(function(u) {
                root.cachedServerUrl = u
                return root._lookup(root.keyEmail).then(function(e) {
                    root.cachedEmail = e
                    return true
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
