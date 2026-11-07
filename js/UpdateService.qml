pragma Singleton
import QtQuick
import Quickshell.Io

QtObject {
    id: root
    readonly property var manifest: {
        try { return JSON.parse(manifestFile.text()) } catch (e) { return ({}) }
    }
    property bool enabled: false
    onEnabledChanged: {
        if (enabled) Qt.callLater(root.check)
        else checker.running = false
    }
    property string availableVersion: ""
    readonly property bool available: enabled && availableVersion !== ""
    readonly property string command: "omarchy plugin update " + (manifest.id || "")
    readonly property string notice: available ? L10n.t("Update available: v%1 — %2", [availableVersion, command]) : ""

    function check() {
        if (!root.enabled || checker.running || !manifest.id || !manifest.version) return
        checker.command = ["python3", decodeURIComponent(Qt.resolvedUrl("check_update.py").toString().replace(/^file:\/\//, "")),
            manifest.id, manifest.version,
            L10n.t("%1 update available", [manifest.name]),
            L10n.t("Version %1 is available. Run: %2")]
        checker.running = true
    }
    property FileView manifestFile: FileView {
        path: decodeURIComponent(Qt.resolvedUrl("../manifest.json").toString().replace(/^file:\/\//, ""))
        blockLoading: true
        printErrors: false
    }
    property Process checker: Process {
        stdout: StdioCollector {
            onStreamFinished: {
                var candidate = text.trim()
                root.availableVersion = /^\d{1,3}\.\d{1,3}\.\d{1,3}$/.test(candidate) ? candidate : ""
            }
        }
    }
    property Timer deadline: Timer {
        interval: 30000
        running: checker.running
        onTriggered: checker.signal(15)
    }
    property Timer daily: Timer {
        interval: 24 * 60 * 60 * 1000
        repeat: true
        running: root.enabled
        onTriggered: root.check()
    }
    Component.onCompleted: Qt.callLater(root.check)
}
