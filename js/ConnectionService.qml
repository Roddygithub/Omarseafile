import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root

    property bool online: true
    property string serverUrl: ""
    property int checkInterval: 30000
    property int maxConsecutiveFailures: 3
    // The probe is a liveness check: a short deadline and a small answer cap.
    property int probeTimeoutMs: 5000
    property int probeMaxBytes: 65536

    property int consecutiveFailures: 0
    property int probeGeneration: 0

    property Timer connectionCheckTimer: Timer {
        interval: root.checkInterval
        repeat: true
        triggeredOnStart: true
        onTriggered: root.checkConnectivity()
    }

    function setServerUrl(url) {
        var nextUrl = url.replace(/\/+$/, "")
        if (nextUrl !== root.serverUrl) root.probeGeneration++
        root.serverUrl = nextUrl
    }

    function start() {
        if (root.connectionCheckTimer.running) return
        root.connectionCheckTimer.start()
    }

    function stop() {
        root.connectionCheckTimer.stop()
    }

    function finalizeProbe(probe, callback) {
        if (probe.finalized) return false
        probe.finalized = true
        callback()
        return true
    }

    // The probe needs the status code and nothing else. curl discards the body
    // (-o /dev/null) under --max-time, so the shared shell retains no response
    // bytes at all, unlike a QML XMLHttpRequest that accumulates whatever the
    // server streams.
    property Component probeFactory: Component {
        Process {
            property var onDone: null
            stdout: StdioCollector {
                waitForEnd: true
            }
            onExited: function(exitCode) {
                var cb = onDone
                var out = stdout.text
                destroy()
                if (cb) cb(exitCode, out)
            }
        }
    }

    function checkConnectivity() {
        if (!root.serverUrl) return

        var generation = ++root.probeGeneration
        var probe = { finalized: false }
        function finalize(callback) { return root.finalizeProbe(probe, callback) }
        var url = root.serverUrl.replace(/\/+$/, "") + "/api2/ping/"
        var proc = root.probeFactory.createObject(root, {
            onDone: function(exitCode, out) {
                finalize(function() {
                    var text = (out || "").trim()
                    var status = /^[0-9]{3}$/.test(text) ? parseInt(text, 10) : 0
                    if (status >= 200 && status < 500) root.handleResponse(generation, status)
                    else root.handleFailure(generation)
                })
            }
        })
        if (!proc) {
            finalize(function() { root.handleFailure(generation) })
            return
        }
        proc.command = ["curl", "-q", "-s", "-o", "/dev/null", "-w", "%{http_code}",
            "--max-time", Math.ceil(root.probeTimeoutMs / 1000).toString(),
            "--no-location", "--", url]
        proc.running = true
    }

    function handleResponse(generation, status) {
        if (generation !== root.probeGeneration) return
        if (status >= 200 && status < 500) {
            root.consecutiveFailures = 0
            if (!root.online) {
                root.online = true
                onlineChanged()
            }
        } else {
            root.handleFailure(generation)
        }
    }

    function handleFailure(generation) {
        if (generation !== root.probeGeneration) return
        root.consecutiveFailures++
        if (root.consecutiveFailures >= root.maxConsecutiveFailures && root.online) {
            root.online = false
            onlineChanged()
        }
    }

    function forceCheck() {
        root.consecutiveFailures = 0
        root.checkConnectivity()
    }

    // Called by successful Seafile API requests to record connectivity success
    function recordSuccess() {
        if (root.consecutiveFailures > 0 || !root.online) {
            root.consecutiveFailures = 0
            if (!root.online) {
                root.online = true
                onlineChanged()
            }
        }
    }

    Component.onCompleted: {
        root.start()
    }

    Component.onDestruction: {
        root.stop()
    }
}
