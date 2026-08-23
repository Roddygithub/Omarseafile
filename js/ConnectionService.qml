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

    property Timer connectionCheckTimer: Timer {
        interval: root.checkInterval
        repeat: true
        triggeredOnStart: true
        onTriggered: root.checkConnectivity()
    }

    function setServerUrl(url) {
        root.serverUrl = url.replace(/\/+$/, "")
    }

    function start() {
        if (root.connectionCheckTimer.running) return
        root.connectionCheckTimer.start()
    }

    function stop() {
        root.connectionCheckTimer.stop()
    }

    function checkConnectivity() {
        if (!root.serverUrl) return

        var xhr = new XMLHttpRequest()
        var url = root.serverUrl.replace(/\/+$/, "") + "/api2/ping/"
        xhr.open("GET", url, true)
        xhr.timeout = 5000
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                var wasOnline = root.online
                if (xhr.status >= 200 && xhr.status < 500) {
                    root.consecutiveFailures = 0
                    if (!root.online) {
                        root.online = true
                        onlineChanged()
                    }
                } else {
                    root.handleFailure()
                }
            }
        }
        xhr.ontimeout = function() {
            root.handleFailure()
        }
        xhr.onerror = function() {
            root.handleFailure()
        }
        xhr.send()
    }

    function handleFailure() {
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