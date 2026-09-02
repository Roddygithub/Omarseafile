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
            property var headerFile: null
            stdinEnabled: true
            stdout: StdioCollector { maxBytes: root.maxResponseBytes }
            stderr: StdioCollector { maxBytes: 1024 * 1024 }
            onStarted: {
                if (headerFile) {
                    write("@" + headerFile)
                }
                if (requestConfig.body !== undefined && requestConfig.body !== null) {
                    write(requestConfig.body)
                }
                stdinEnabled = false
            }
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
        var proc = _requestFactory.createObject(root, {
            onDone: function(exitCode, out, err) {
                if (exitCode === 0) {
                    var data = null
                    try {
                        data = out ? JSON.parse(out) : null
                    } catch (e) {
                        callback(false, null, "Invalid JSON response")
                        return
                    }
                    // Validate response
                    var validation = validateResponse(data)
                    if (!validation.valid) {
                        callback(false, null, validation.error)
                        return
                    }
                    callback(true, validation.data, null)
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
        // NO Authorization header in argv - will use header file via stdin
        for (var h in config.headers) {
            // Skip Authorization header - handled via header file
            if (h.toLowerCase() !== "authorization") {
                args.push("-H", h + ": " + config.headers[h])
            }
        }
        args.push("-X", config.method)
        if (config.body) {
            args.push("-d", config.body)
        }
        args.push(config.url)
        proc.requestConfig = config
        // Create header file for Authorization
        var authHeader = config.headers ? config.headers["Authorization"] : null
        if (authHeader) {
            SafePath.createSecureTempFile("http_headers", function(result) {
                if (!result.valid) { callback(false, null, "Failed to create header file"); return }
                var headerFile = result.path
                var proc2 = Qt.createComponent("dummy").createObject({
                    command: ["sh", "-c", "cat > \"$1\"", "sh", headerFile],
                    running: true
                })
                if (!proc2) { callback(false, null, "Failed to create header file process"); return }
                proc2.onExited = function(exitCode) {
                    if (exitCode !== 0) { callback(false, null, "Failed to write header file"); return }
                    // Write auth header to file
                    var writeProc = Qt.createComponent("dummy").createObject({
                        command: ["sh", "-c", "printf '%s\\n' \"$1\" > \"$2\"", "sh", authHeader, headerFile],
                        running: true
                    })
                    if (!writeProc) { callback(false, null, "Failed to create write process"); return }
                    writeProc.onExited = function(exitCode2) {
                        if (exitCode2 !== 0) { callback(false, null, "Failed to write auth header"); return }
                        proc.headerFile = headerFile
                        proc.running = true
                    }
                }
            }) else {
                proc.running = true
            }
        })
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

    function validateResponse(data) {
        // Basic response validation
        if (data === null || data === undefined) {
            return { valid: true, data: null }
        }
        if (Array.isArray(data)) {
            var collValidation = validateCollection(data)
            if (!collValidation.valid) return { valid: false, error: collValidation.error }
            // Validate each item
            for (var i = 0; i < data.length; i++) {
                if (typeof data[i] === "object" && data[i] !== null) {
                    var objValidation = validateObject(data[i])
                    if (!objValidation.valid) return { valid: false, error: "Item " + i + ": " + objValidation.error }
                }
            }
            return { valid: true, data: data }
        }
        if (typeof data === "object") {
            var objValidation = validateObject(data)
            if (!objValidation.valid) return { valid: false, error: objValidation.error }
            return { valid: true, data: data }
        }
        return { valid: true, data: data }
    }

    function validateObject(obj) {
        // Limit string lengths in object
        for (var key in obj) {
            var val = obj[key]
            if (typeof val === "string") {
                var strValidation = validateString(val)
                if (!strValidation.valid) return { valid: false, error: "Field '" + key + "': " + strValidation.error }
            } else if (typeof val === "object" && val !== null) {
                var nestedValidation = validateObject(val)
                if (!nestedValidation.valid) return { valid: false, error: "Field '" + key + "': " + nestedValidation.error }
            }
        }
        return { valid: true }
    }
}