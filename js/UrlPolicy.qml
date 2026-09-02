pragma Singleton
import QtQuick

QtObject {
    id: root

    readonly property string loopbackHostname: "localhost"
    readonly property var loopbackAddresses: ["127.0.0.1", "::1"]

    function isLoopbackHost(host) {
        if (!host) return false
        if (host === root.loopbackHostname) return true
        for (var i = 0; i < root.loopbackAddresses.length; i++) {
            if (host === root.loopbackAddresses[i]) return true
        }
        return false
    }

    function validateForAuth(url) {
        if (!url || typeof url !== "string") {
            return { valid: false, error: "Empty URL" }
        }
        var parsed
        try {
            parsed = new URL(url)
        } catch (e) {
            return { valid: false, error: "Invalid URL format" }
        }
        var scheme = parsed.protocol.replace(":", "")
        var host = parsed.hostname

        if (scheme === "https") {
            return { valid: true }
        }
        if (scheme === "http" && root.isLoopbackHost(host)) {
            return { valid: true, warning: "Loopback HTTP — not recommended for production" }
        }
        return { valid: false, error: "Cleartext HTTP not allowed for authentication. Use HTTPS or loopback (http://localhost, http://127.0.0.1)." }
    }
}