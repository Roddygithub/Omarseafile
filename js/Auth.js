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

    function storeToken(token, serverUrl, email) {
        var proc = Process {
            command: ["secret-tool", "store", "--label=Seafile Auth Token", root.attrService, root.valService, root.attrKey, root.keyToken]
            stdinEnabled: true
        }
        proc.stdin.write(token)
        proc.stdin.close()
        proc.waitForFinished()

        if (serverUrl) {
            var proc2 = Process {
                command: ["secret-tool", "store", "--label=Seafile Server URL", root.attrService, root.valService, root.attrKey, root.keyServer]
                stdinEnabled: true
            }
            proc2.stdin.write(serverUrl)
            proc2.stdin.close()
            proc2.waitForFinished()
        }

        if (email) {
            var proc3 = Process {
                command: ["secret-tool", "store", "--label=Seafile User Email", root.attrService, root.valService, root.attrKey, root.keyEmail]
                stdinEnabled: true
            }
            proc3.stdin.write(email)
            proc3.stdin.close()
            proc3.waitForFinished()
        }
    }

    function getToken() {
        var proc = Process {
            command: ["secret-tool", "lookup", root.attrService, root.valService, root.attrKey, root.keyToken]
        }
        proc.waitForFinished()
        return proc.stdout.trim()
    }

    function getServerUrl() {
        var proc = Process {
            command: ["secret-tool", "lookup", root.attrService, root.valService, root.attrKey, root.keyServer]
        }
        proc.waitForFinished()
        return proc.stdout.trim()
    }

    function getEmail() {
        var proc = Process {
            command: ["secret-tool", "lookup", root.attrService, root.valService, root.attrKey, root.keyEmail]
        }
        proc.waitForFinished()
        return proc.stdout.trim()
    }

    function clearSession() {
        Process.run(["secret-tool", "clear", root.attrService, root.valService, root.attrKey, root.keyToken])
        Process.run(["secret-tool", "clear", root.attrService, root.valService, root.attrKey, root.keyServer])
        Process.run(["secret-tool", "clear", root.attrService, root.valService, root.attrKey, root.keyEmail])
    }

    function isAuthenticated() {
        var token = getToken()
        return token !== "" && token !== undefined
    }

    function validateSession(token) {
        if (!token) return false
        return token.length > 20
    }
}