import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root

    property bool online: true
    property string serverUrl: ""
    property int checkInterval: 30000
    property int retryDelay: 5000
    property int maxConsecutiveFailures: 3

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

    function checkConnectivity() {
        if (!root.serverUrl) return

        var generation = ++root.probeGeneration
        var probe = { finalized: false }
        function finalize(callback) { return root.finalizeProbe(probe, callback) }
        var xhr = new XMLHttpRequest()
        var url = root.serverUrl.replace(/\/+$/, "") + "/api2/ping/"
        xhr.open("GET", url, true)
        xhr.timeout = 5000
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE)
                finalize(function() { root.handleResponse(generation, xhr.status) })
        }
        xhr.ontimeout = function() {
            finalize(function() { root.handleFailure(generation) })
        }
        xhr.onerror = function() {
            finalize(function() { root.handleFailure(generation) })
        }
        xhr.send()
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

    function isOnline() {
        return root.online
    }

    Component.onCompleted: {
        root.start()
    }

    Component.onDestruction: {
        root.stop()
    }
}