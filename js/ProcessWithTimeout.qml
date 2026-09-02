pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root

    property int defaultTimeoutMs: 30000
    property int defaultMaxOutputBytes: 1024 * 1024

    property Component _processFactory: Component {
        Process {
            property var onDone: null
            property int timeoutMs: 30000
            property int maxOutputBytes: 1024 * 1024
            property bool setsidUsed: false
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

    property Component _timeoutTimerFactory: Component {
        Timer {
            property var targetProcess: null
            property int timeoutMs: 30000
            repeat: false
            onTriggered: {
                if (targetProcess) {
                    try {
                        var pgid = targetProcess.processId
                        if (pgid) {
                            var killProc = Qt.createComponent("dummy").createObject({ command: ["kill", "-TERM", "-" + pgid], running: true })
                        } else {
                            targetProcess.kill()
                        }
                    } catch (e) {
                        try { targetProcess.kill() } catch (e) {}
                    }
                }
            }
        }
    }

    function run(cmd, input, timeoutMs, maxOutputBytes, callback) {
        var proc = _processFactory.createObject(root, {
            onDone: function(exitCode, out, err) {
                if (timer) timer.stop()
                if (!timer) return
                callback(exitCode === 0 ? out : null, exitCode === 0 ? null : (err || "exit " + exitCode))
            }
        })
        proc.command = cmd
        proc.stdinEnabled = !!input
        if (input !== undefined && input !== null) {
            proc.onStarted = function() { proc.write(input); proc.stdinEnabled = false }
        }
        var timeout = timeoutMs || root.defaultTimeoutMs
        var maxOut = maxOutputBytes || root.defaultMaxOutputBytes
        // Use setsid to create a new process group
        proc.command = ["setsid"] + cmd
        proc.running = true
        var timer = _timeoutTimerFactory.createObject(root, { interval: timeout, targetProcess: proc })
        timer.start()
    }
}