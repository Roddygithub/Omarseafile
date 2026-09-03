pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root

    property int connectTimeoutMs: 5000
    property int totalTimeoutMs: 30000
    property int maxCollectionItems: 1000
    property int maxStringLength: 10000
    property int maxResponseBytes: 10 * 1024 * 1024

    property Component _requestFactory: Component {
        Process {
            property var onDone: null
            property var headerFilePath: ""
            property var bodyFilePath: ""
            stdout: StdioCollector {}
            stderr: StdioCollector {}
            onExited: function(exitCode, exitStatus) {
                var cb = onDone
                var out = stdout.text
                var err = stderr.text
                destroy()
                if (cb) cb(exitCode, out, err)
            }
        }
    }

    function request(method, url, headers, body, callback) {
        var config = {
            method: method,
            url: url,
            headers: headers || ({}),
            body: body,
            timeoutMs: root.totalTimeoutMs
        }

        var authHeader = config.headers ? config.headers["Authorization"] : null
        var hasBody = config.body !== undefined && config.body !== null && config.body !== ""

        SafePath.getRuntimeSubdir("http", function(httpResult) {
            if (!httpResult.valid) { callback(false, null, "Runtime dir unavailable: " + httpResult.error); return }

            var curlArgs = [
                "curl", "-q", "-f", "-s", "-S",
                "--connect-timeout", Math.ceil(root.connectTimeoutMs / 1000).toString(),
                "--max-time", Math.ceil(root.totalTimeoutMs / 1000).toString(),
                "--speed-limit", "1",
                "--speed-time", "30",
                "--no-location",
                "--max-filesize", root.maxResponseBytes.toString()
            ]

            for (var h in config.headers) {
                if (h.toLowerCase() !== "authorization") {
                    curlArgs.push("-H", h + ": " + config.headers[h])
                }
            }

            if (authHeader) {
                var configContent = "header = \"Authorization: " + authHeader.replace(/"/g, "\\\"") + "\"\n"
                SafePath.createSecureFile(httpResult.path, "curl_hdr", configContent, function(hdrResult) {
                    if (!hdrResult.valid) { callback(false, null, "Header file failed: " + hdrResult.error); return }
                    runRequest(hdrResult.path)
                })
            } else {
                runRequest("")
            }

            function runRequest(headerFile) {
                if (hasBody) {
                    SafePath.createSecureFile(httpResult.path, "curl_body", config.body, function(bodyResult) {
                        if (!bodyResult.valid) {
                            cleanup(headerFile)
                            callback(false, null, "Body file failed: " + bodyResult.error); return
                        }
                        execute(headerFile, bodyResult.path, curlArgs.slice())
                    })
                } else {
                    execute(headerFile, "", curlArgs.slice())
                }
            }

            function execute(hdrFile, bodyFile, args) {
                if (hdrFile) {
                    args.push("--config", hdrFile)
                }
                if (bodyFile) {
                    args.push("--data-binary", "@" + bodyFile)
                }
                args.push("-X", config.method)
                args.push(config.url)

                var proc = _requestFactory.createObject(root, {
                    onDone: function(exitCode, out, err) {
                        cleanup(hdrFile)
                        cleanup(bodyFile)
                        if (exitCode === 0) {
                            var data = null
                            try { data = out ? JSON.parse(out) : null } catch (e) {
                                callback(false, null, "Invalid JSON response"); return
                            }
                            var validation = validateResponse(data)
                            if (!validation.valid) { callback(false, null, validation.error); return }
                            callback(true, validation.data, null)
                        } else if (exitCode === 63 || exitCode === 23) {
                            // 63: max-filesize exceeded (curl 7.56.0+); 23: write error (older curl)
                            callback(false, null, "Response too large (exceeds " + root.maxResponseBytes + " bytes)")
                        } else {
                            callback(false, null, "Request failed (exit " + exitCode + "): " + (err || "unknown"))
                        }
                    }
                })
                proc.command = args
                proc.running = true
            }

            function cleanup(path) {
                if (!path) return
                var c = Qt.createComponent("dummy").createObject(root, {
                    command: ["rm", "-f", "--", path],
                    running: true
                })
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
        if (data === null || data === undefined) {
            return { valid: true, data: null }
        }
        if (Array.isArray(data)) {
            var collValidation = validateCollection(data)
            if (!collValidation.valid) return { valid: false, error: collValidation.error }
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
        for (var key in obj) {
            var val = obj[key]
            if (typeof val === "string") {
                var strValidation = validateString(val)
                if (!strValidation.valid) return { valid: false, error: "Field '" + key + "': " + strValidation.error }
            } else if (Array.isArray(val)) {
                var collValidation = validateCollection(val)
                if (!collValidation.valid) return { valid: false, error: "Field '" + key + "': " + collValidation.error }
                for (var i = 0; i < val.length; i++) {
                    if (typeof val[i] === "object" && val[i] !== null) {
                        var nestedValidation = validateObject(val[i])
                        if (!nestedValidation.valid) return { valid: false, error: "Field '" + key + "[" + i + "]': " + nestedValidation.error }
                    }
                }
            } else if (typeof val === "object" && val !== null) {
                var nestedValidation = validateObject(val)
                if (!nestedValidation.valid) return { valid: false, error: "Field '" + key + "': " + nestedValidation.error }
            }
        }
        return { valid: true }
    }
}
