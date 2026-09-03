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

    // Validate a server-provided URL before it becomes a transfer target.
    // Rejects: non-string, empty, >8192, non-HTTPS (except loopback HTTP),
    // credentials/userinfo, javascript:/file: schemes, unparseable URLs.
    function validateTransferUrl(url) {
        if (!url || typeof url !== "string") {
            return { valid: false, error: "URL must be a non-empty string" }
        }
        if (url.length > 8192) {
            return { valid: false, error: "URL exceeds maximum length" }
        }
        var parsed
        try {
            parsed = new URL(url)
        } catch (e) {
            return { valid: false, error: "URL is malformed" }
        }
        var scheme = parsed.protocol.replace(":", "")
        var host = parsed.hostname

        // Reject javascript: and file: schemes
        if (scheme === "javascript" || scheme === "file") {
            return { valid: false, error: "Unsupported URL scheme: " + scheme }
        }

        // HTTPS is always allowed
        if (scheme === "https") {
            // Reject userinfo (credentials in URL)
            if (parsed.username || parsed.password) {
                return { valid: false, error: "URL must not contain credentials" }
            }
            return { valid: true }
        }

        // HTTP only allowed for loopback
        if (scheme === "http" && root.isLoopbackHost(host)) {
            if (parsed.username || parsed.password) {
                return { valid: false, error: "URL must not contain credentials" }
            }
            return { valid: true, warning: "Loopback HTTP transfer" }
        }

        return { valid: false, error: "Transfer URL must use HTTPS (or loopback HTTP)" }
    }

    // Extract origin (scheme + hostname + port) from a URL string.
    // Returns null on parse failure.
    function _extractOrigin(url) {
        if (!url || typeof url !== "string") return null
        try {
            var parsed = new URL(url)
            var scheme = parsed.protocol.replace(":", "")
            var host = parsed.hostname || ""
            var port = parsed.port || ""
            // Normalize default ports: http->80, https->443
            if (port === "" || port === "0") {
                port = scheme === "https" ? "443" : "80"
            }
            return scheme + "://" + host.toLowerCase() + ":" + port
        } catch (e) {
            return null
        }
    }

    // Determine whether a transfer URL is same-origin as the configured Seafile base.
    // Returns { sameOrigin: bool, reason: string }
    function checkTransferOrigin(transferUrl, baseUrl) {
        var transferOrigin = _extractOrigin(transferUrl)
        var baseOrigin = _extractOrigin(baseUrl)

        if (!transferOrigin) {
            return { sameOrigin: false, reason: "Transfer URL is malformed" }
        }
        if (!baseOrigin) {
            return { sameOrigin: false, reason: "Base URL is malformed" }
        }

        if (transferOrigin === baseOrigin) {
            return { sameOrigin: true, reason: "Same origin" }
        }

        return { sameOrigin: false, reason: "Cross-origin: " + transferOrigin + " vs " + baseOrigin }
    }

    // Should the Seafile Authorization header be attached to a transfer request?
    // Only when the transfer URL is same-origin as the configured Seafile base.
    // This prevents credential leakage to cross-origin storage servers.
    function shouldAttachAuth(transferUrl, baseUrl) {
        var check = checkTransferOrigin(transferUrl, baseUrl)
        return check.sameOrigin
    }
}