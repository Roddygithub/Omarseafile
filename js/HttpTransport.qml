pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root

    property int maxResponseBytes: 10 * 1024 * 1024
    property int connectTimeoutMs: 5000
    property int totalTimeoutMs: 30000
    property int maxCollectionItems: 1000
    property int maxStringLength: 10000

    property Component _requestFactory: Component {
        Process {
            property var onDone: null
            property var requestConfig: null
            stdout: StdioCollector { maxBytes: root.maxResponseBytes }
            stderr: StdioCollector { maxBytes: 1024 * 1024 }
            onExited: function(exitCode, exitStatus) {
                var cb = onDone
                var out = stdout.text
                var err = stderr.text
                destroy()
                if (cb) cb(exitCode, out, err)
            }
        }
    }

    property Component _timeoutFactory: Component {
        Timer {
            property var targetProcess: null
            repeat: false
            onTriggered: {
                if (targetProcess) {
                    try { targetProcess.kill() } catch (e) {}
                }
            }
        }
    }

    function request(method, url, headers, body, callback) {
        var config = {
            method: method,
            url: url,
            headers: headers || ({}),
            body: body,
            timeoutMs: root.totalTimeoutMs,
            maxBytes: root.maxResponseBytes
        }
        var proc = requestFactory.createObject(root, {
            onDone: function(exitCode, out, err) {
                if (exitCode === 0) {
                    var data = null
                    try {
                        data = out ? JSON.parse(out) : null
                    } catch (e) {
                        callback(false, null, "Invalid JSON response")
                        return
                    }
                    callback(true, data, null)
                } else {
                    callback(false, null, "Request failed (exit " + exitCode + "): " + (err || "unknown"))
                }
            }
        })
        var args = ["curl", "-q", "-f", "-s", "-S"]
        args.push("--connect-timeout", Math.ceil(root.connectTimeoutMs / 1000))
        args.push("--max-time", Math.ceil(root.totalTimeoutMs / 1000))
        args.push("--max-filesize", root.maxResponseBytes)
        args.push("--speed-limit", "1")
        args.push("--speed-time", "30")
        args.push("--no-location")
        for (var h in config.headers) {
            args.push("-H", h + ": " + config.headers[h])
        }
        args.push("-X", config.method)
        if (config.body) {
            args.push("-d", config.body)
        }
        args.push(config.url)
        proc.command = args
        proc.running = true
    }

    function get(url, headers, callback) { root.request("GET", url, headers, null, callback) }
    function post(url, headers, body, callback) { root.request("POST", url, headers, body, callback) }
    function put(url, headers, body, callback) { root.request("PUT", url, headers, body, callback) }
    function del(url, headers, callback) { root.request("DELETE", url, headers, null, callback) }

    function validateCollection(arr, maxItems) {
        if (!Array.isArray(arr)) return { valid: false, error: "Not an array" }
        var limit = maxItems || root.maxCollectionItems
        if (arr.length > limit) return { valid: false, error: "Collection exceeds max items (" + limit + ")" }
        return { valid: true }
    }

    function validateString(str, maxLen) {
        if (typeof str !== "string") return { valid: false, error: "Not a string" }
        var limit = maxLen || root.maxStringLength
        if (str.length > limit) return { valid: false, error: "String exceeds max length" }
        return { valid: true }
    }

    function sanitizeCollection(arr, itemValidator, maxItems) {
        var limit = maxItems || root.maxCollectionItems
        var out = []
        for (var i = 0; i < Math.min(arr.length, limit); i++) {
            if (itemValidator) {
                var v = itemValidator(arr[i])
                if (v.valid) out.push(v.value || arr[i])
            } else {
                out.push(arr[i])
            }
        }
        return out
    }
}