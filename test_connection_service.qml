import QtQuick
import Quickshell
import "./js"

ShellRoot {
    id: root
    property string baseUrl: ""
    property string scenario: ""
    property bool done: false

    ConnectionService {
        id: service
    }

    function finish(label, expected) {
        var actual = service.online
        print(label + " online=" + actual + " failures=" + service.consecutiveFailures)
        if (actual !== expected) Qt.quit()
        else {
            root.done = true
            Qt.quit()
        }
    }

    Component.onCompleted: {
        service.stop()
        service.maxConsecutiveFailures = 1
        service.online = true
        service.consecutiveFailures = 0
        service.setServerUrl(root.baseUrl + "/A")
        if (root.scenario === "offline-after-online") {
            service.forceCheck()
            laterTimer.interval = 30
            laterTimer.restart()
        } else if (root.scenario === "online-after-offline") {
            service.forceCheck()
            laterTimer.interval = 30
            laterTimer.restart()
        } else if (root.scenario === "timeout-stale") {
            service.forceCheck()
            laterTimer.interval = 30
            laterTimer.restart()
        } else if (root.scenario === "error-stale") {
            service.forceCheck()
            laterTimer.interval = 30
            laterTimer.restart()
        }
    }

    Timer {
        id: laterTimer
        repeat: false
        onTriggered: {
            if (root.scenario === "error-stale")
                service.setServerUrl(root.baseUrl + "/B")
            else
                service.setServerUrl(root.baseUrl + "/B")
            service.forceCheck()
            resultTimer.restart()
        }
    }

    Timer {
        id: resultTimer
        interval: root.scenario === "timeout-stale" ? 5700 : 700
        repeat: false
        onTriggered: {
            var expected = root.scenario === "offline-after-online" ? true : false
            root.finish(root.scenario, expected)
        }
    }
}
