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
            property var headerFilePath: ""
            property var bodyFilePath: ""
            property bool haveAuth: false
            property bool haveBody: false
            stdinEnabled: true
            stdout: StdioCollector {}
            stderr: StdioCollector {}
            onStarted: {
                if (haveAuth && headerFilePath) {
                    // curl reads config from stdin when we pass --config -
                    // but we'll use --config @- approach: config is passed via stdin after auth header
                    // Actually, let's use a different approach: write auth header to file, reference it in config
                }
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

    function request(method, url, headers, body, callback) {
        var config = {
            method: method,
            url: url,
            headers: headers || ({}),
            body: body,
            timeoutMs: root.totalTimeoutMs,
            maxBytes: root.maxResponseBytes
        }

        // Extract auth header if present
        var authHeader = config.headers ? config.headers["Authorization"] : null

        // Build curl args
        var args = ["curl", "-q", "-f", "-s", "-S"]
        args.push("--connect-timeout", Math.ceil(root.connectTimeoutMs / 1000))
        args.push("--max-time", Math.ceil(root.totalTimeoutMs / 1000))
        args.push("--max-filesize", root.maxResponseBytes)
        args.push("--speed-limit", "1")
        args.push("--speed-time", "30")
        args.push("--no-location")

        // Add non-auth headers
        for (var h in config.headers) {
            if (h.toLowerCase() !== "authorization") {
                args.push("-H", h + ": " + config.headers[h])
            }
        }
        args.push("-X", config.method)
        if (config.body) {
            args.push("--data-binary", "@-")
        }
        args.push(config.url)

        // Create secure temp files for auth header and config
        SafePath.getRuntimeSubdir("http", function(httpResult) {
            if (!httpResult.valid) { callback(false, null, "Runtime dir unavailable: " + httpResult.error); return }

            SafePath.createSecureFile(httpResult.path, "curl_auth", authHeader || "", function(authFileResult) {
                if (!authFileResult.valid) { callback(false, null, "Auth file failed: " + authFileResult.error); return }
                var authFile = authFileResult.path

                // Build curl config content
                var configContent = ""
                if (authHeader) {
                    configContent += "header = \"Authorization: " + authHeader.replace(/"/g, "\\\"") + "\"\n"
                }
                configContent += "url = " + JSON.stringify(config.url) + "\n"

                SafePath.createSecureFile(httpResult.path, "curl_cfg", configContent, function(cfgFileResult) {
                    if (!cfgFileResult.valid) {
                        Qt.createComponent("dummy").createObject({ command: ["rm", "-f", "--", authFile], running: true })
                        callback(false, null, "Config file failed: " + cfgFileResult.error); return
                    }
                    var cfgFile = cfgFileResult.path

                    // Build body file if needed
                    var hasBody = config.body !== undefined && config.body !== null && config.body !== ""
                    if (hasBody) {
                        SafePath.createSecureFile(httpResult.path, "curl_body", config.body, function(bodyFileResult) {
                            if (!bodyFileResult.valid) {
                                cleanupFiles(); callback(false, null, "Body file failed: " + bodyFileResult.error); return
                            }
                            runCurl(authFile, cfgFile, bodyFileResult.path, true)
                        })
                    } else {
                        runCurl(authFile, cfgFile, "", false)
                    }

                    function cleanupFiles() {
                        Qt.createComponent("dummy").createObject({ command: ["rm", "-f", "--", authFile], running: true })
                        Qt.createComponent("dummy").createObject({ command: ["rm", "-f", "--", cfgFile], running: true })
                        if (hasBody) Qt.createComponent("dummy").createObject({ command: ["rm", "-f", "--", bodyFileResult.path], running: true })
                    }

                    function runCurl(authFile, cfgFile, bodyFile, hasBodyData) {
                        var proc = _requestFactory.createObject(root, {
                            onDone: function(exitCode, out, err) {
                                cleanupFiles()
                                if (exitCode === 0) {
                                    var data = null
                                    try { data = out ? JSON.parse(out) : null } catch (e) {
                                        callback(false, null, "Invalid JSON response"); return
                                    }
                                    var validation = validateResponse(data)
                                    if (!validation.valid) { callback(false, null, validation.error); return }
                                    callback(true, validation.data, null)
                                } else {
                                    callback(false, null, "Request failed (exit " + exitCode + "): " + (err || "unknown"))
                                }
                            }
                        })
                        var finalArgs = []
                        for (var i = 0; i < args.length; i++) {
                            finalArgs.push(args[i])
                        }
                        finalArgs.push("--config", cfgFile)
                        if (hasBodyData) {
                            finalArgs.push("--data-binary", "@" + bodyFile)
                        }
                        proc.command = finalArgs
                        proc.running = true
                    }
                })
            })
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
            } else if (typeof val === "object" && val !== null) {
                var nestedValidation = validateObject(val)
                if (!nestedValidation.valid) return { valid: false, error: "Field '" + key + "': " + nestedValidation.error }
            }
        }
        return { valid: true }
    }
}