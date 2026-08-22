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
    property var checkTimer: null

    function setServerUrl(url) {
        root.serverUrl = url.replace(/\/+$/, "")
    }

    function start() {
        if (root.checkTimer) return
        root.checkTimer = Timer {
            interval: root.checkInterval
            running: true
            repeat: true
            triggeredOnStart: true
            onTriggered: root.checkConnectivity()
        }
    }

    function stop() {
        if (root.checkTimer) {
            root.checkTimer.stop()
            root.checkTimer = null
        }
    }

    function checkConnectivity() {
        if (!root.serverUrl) return

        var xhr = new XMLHttpRequest()
        var url = root.serverUrl + "/api2/ping/"
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

    function onlineChanged() {
        // Signal handled by Panel.qml via property binding
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