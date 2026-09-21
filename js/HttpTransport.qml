pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root

    property int connectTimeoutMs: 10000
    property int totalTimeoutMs: 30000
    property int maxCollectionItems: 1000
    property int maxStringLength: 10000
    property int maxResponseBytes: 10 * 1024 * 1024
    property int maxStderrBytes: 65536
    property int maxValidationDepth: 32
    readonly property string _transferOutputHelper: Qt.resolvedUrl("../scripts/transfer_output.py").toString().replace(/^file:\/\//, "")

    property Component _requestFactory: Component {
        Process {
            property var onDone: null
            property var headerFilePath: ""
            property var bodyFilePath: ""
            property var responseBodyPath: ""
            stdout: StdioCollector {}
            stderr: StdioCollector {}
            onExited: function(exitCode, exitStatus) {
                var cb = onDone
                var statusText = stdout.text
                var err = stderr.text
                var bodyPath = responseBodyPath
                destroy()
                if (!cb) return
                // Hand the raw pieces to request()'s scope: curl wrote the body
                // into a private file (-o) and the status to stdout (-w). The
                // caller reads the body file back and parses the status. This
                // is the correct curl contract - -o is the body sink, -w is
                // stdout.
                cb(exitCode, statusText, err, bodyPath)
            }
        }
    }

    // Reads the response body curl wrote via `-o`. Returns "" when the file is
    // missing or unreadable (no response body observed). The path always comes
    // from SafePath.createSecureFile and is passed as an argv element, never
    // through a shell.
    function _readBodyFile(path, callback) {
        if (!path) { callback(""); return }
        var proc = root._fileReaderFactory.createObject(root, {
            onDone: function(text) {
                callback(text === undefined || text === null ? "" : text)
            }
        })
        if (!proc) { callback(""); return }
        proc.command = ["cat", "--", path]
        proc.running = true
    }

    function _statusFromText(text) {
        if (typeof text !== "string") return 0
        var trimmed = text.trim()
        if (!/^[0-9]{3}$/.test(trimmed)) return 0
        var n = parseInt(trimmed, 10)
        // curl reports 000 when it never received an HTTP response.
        if (n === 0) return 0
        return n
    }

    property Component _fileReaderFactory: Component {
        Process {
            property var onDone: null
            stdout: StdioCollector {}
            onExited: function(exitCode) {
                var cb = onDone
                var out = stdout.text
                destroy()
                if (cb) cb(exitCode === 0 ? out : "")
            }
        }
    }

    property Component _cleanupProcessFactory: Component {
        Process {
            onExited: destroy()
        }
    }

    function request(method, url, headers, body, callback) {
        var finished = false
        // The 4th argument is the real HTTP status (0 == no HTTP response was
        // observed, i.e. a transport failure). Callers written against the old
        // 3-argument contract simply ignore it.
        function finish(success, data, error, status) {
            if (finished) return
            finished = true
            callback(success, data, error, typeof status === "number" ? status : 0)
        }
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
            if (!httpResult.valid) { finish(false, null, "Runtime dir unavailable: " + httpResult.error, 0); return }

            // curl semantics:
            //   -o FILE          writes the HTTP BODY into FILE
            //   -w "%{http_code}" writes the HTTP STATUS to stdout
            // We honour that contract: the body lands in a private response
            // file (bounded producer-side by --max-filesize), and the status
            // comes back on stdout, which _requestFactory parses. This is the
            // opposite of an earlier implementation that swapped the two.
            SafePath.createSecureFile("http", "curl_resp", "", function(respResult) {
                if (!respResult.valid) { finish(false, null, "Response file failed: " + respResult.error, 0); return }
                var responseBodyFile = respResult.path

                var curlArgs = [
                    "curl", "-q", "-f", "-s", "-S",
                    "--connect-timeout", Math.ceil(root.connectTimeoutMs / 1000).toString(),
                    "--max-time", Math.ceil(root.totalTimeoutMs / 1000).toString(),
                    "--speed-limit", "1",
                    "--speed-time", "30",
                    "--no-location",
                    "--max-filesize", root.maxResponseBytes.toString(),
                    "-o", responseBodyFile,
                    "-w", "%{http_code}"
                ]

                for (var h in config.headers) {
                    if (h.toLowerCase() !== "authorization") {
                        curlArgs.push("-H", h + ": " + config.headers[h])
                    }
                }

                if (authHeader) {
                    var configContent = "header = \"Authorization: " + authHeader.replace(/\"/g, "\\\"") + "\"\n"
                    SafePath.createSecureFile("http", "curl_hdr", configContent, function(hdrResult) {
                        if (!hdrResult.valid) { cleanup(responseBodyFile); finish(false, null, "Header file failed: " + hdrResult.error, 0); return }
                        runRequest(hdrResult.path)
                    })
                } else {
                    runRequest("")
                }

                function runRequest(headerFile) {
                    if (hasBody) {
                        SafePath.createSecureFile("http", "curl_body", config.body, function(bodyResult) {
                            if (!bodyResult.valid) {
                                cleanup(headerFile)
                                cleanup(responseBodyFile)
                                finish(false, null, "Body file failed: " + bodyResult.error, 0); return
                            }
                            execute(headerFile, bodyResult.path, curlArgs.slice())
                        })
                    } else {
                        execute(headerFile, "", curlArgs.slice())
                    }
                }

                function execute(hdrFile, reqBodyFile, args) {
                    if (hdrFile) {
                        args.push("--config", hdrFile)
                    }
                    if (reqBodyFile) {
                        args.push("--data-binary", "@" + reqBodyFile)
                    }
                    args = ["setsid", "python3", root._transferOutputHelper,
                        root.maxStderrBytes.toString(), "--"].concat(args)
                    args.push("-X", config.method)
                    args.push(config.url)

                    var proc = _requestFactory.createObject(root, {
                        responseBodyPath: responseBodyFile,
                        onDone: function(exitCode, statusText, err, respBodyPath) {
                            cleanup(hdrFile)
                            cleanup(reqBodyFile)
                            var status = root._statusFromText(statusText)
                            // Read the body file back (root scope has the helpers
                            // the Process closure cannot see).
                            root._readBodyFile(respBodyPath, function(respBody) {
                                cleanup(responseBodyFile)
                                if (exitCode === 0) {
                                    try {
                                        var data = respBody ? JSON.parse(respBody) : null
                                        var validation = validateResponse(data)
                                        if (!validation.valid) { finish(false, null, validation.error, status); return }
                                        finish(true, validation.data, null, status)
                                    } catch (e) {
                                        finish(false, null, "Invalid JSON response", status)
                                    }
                                } else if (exitCode === 63 || exitCode === 23) {
                                    // 63: max-filesize exceeded (curl 7.56.0+); 23: write error (older curl)
                                    finish(false, null, "Response too large (exceeds " + root.maxResponseBytes + " bytes)", status)
                                } else {
                                    // Pass the real status through. Callers decide
                                    // retryability from it, never from `err` text.
                                    finish(false, null, "Request failed (exit " + exitCode + "): " + (err || "unknown"), status)
                                }
                            })
                        }
                    })
                    if (!proc) {
                        cleanup(hdrFile)
                        cleanup(reqBodyFile)
                        cleanup(responseBodyFile)
                        finish(false, null, "Failed to create request process", 0)
                        return
                    }
                    proc.command = args
                    proc.running = true
                }

                function cleanup(path) {
                    if (!path) return
                    var proc = root._cleanupProcessFactory.createObject(root)
                    if (!proc) return
                    proc.command = ["rm", "-f", "--", path]
                    proc.running = true
                }
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
        return validateValue(data, 0)
    }

    function validateValue(data, depth) {
        if (depth > root.maxValidationDepth) return { valid: false, error: "Response nesting exceeds maximum depth" }
        if (data === null || data === undefined) {
            return { valid: true, data: null }
        }
        if (Array.isArray(data)) {
            var collValidation = validateCollection(data)
            if (!collValidation.valid) return { valid: false, error: collValidation.error }
            for (var i = 0; i < data.length; i++) {
                var itemValidation = validateValue(data[i], depth + 1)
                if (!itemValidation.valid) return { valid: false, error: "Item " + i + ": " + itemValidation.error }
            }
            return { valid: true, data: data }
        }
        if (typeof data === "object") {
            var objValidation = validateObject(data, depth + 1)
            if (!objValidation.valid) return { valid: false, error: objValidation.error }
            return { valid: true, data: data }
        }
        return { valid: true, data: data }
    }

    function validateObject(obj, depth) {
        if (depth > root.maxValidationDepth) return { valid: false, error: "Response nesting exceeds maximum depth" }
        for (var key in obj) {
            var val = obj[key]
            if (typeof val === "string") {
                var strValidation = validateString(val)
                if (!strValidation.valid) return { valid: false, error: "Field '" + key + "': " + strValidation.error }
            } else if (Array.isArray(val)) {
                var collValidation = validateCollection(val)
                if (!collValidation.valid) return { valid: false, error: "Field '" + key + "': " + collValidation.error }
                for (var i = 0; i < val.length; i++) {
                    var nestedValidation = validateValue(val[i], depth + 1)
                    if (!nestedValidation.valid) return { valid: false, error: "Field '" + key + "[" + i + "]': " + nestedValidation.error }
                }
            } else if (typeof val === "object" && val !== null) {
                var nestedValidation = validateObject(val, depth + 1)
                if (!nestedValidation.valid) return { valid: false, error: "Field '" + key + "': " + nestedValidation.error }
            }
        }
        return { valid: true }
    }
}
