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
            stdout: StdioCollector { maxBytes: 1024 * 1024 }
            stderr: StdioCollector { maxBytes: 1024 * 1024 }
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
        var proc = processFactory.createObject(root, {
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
        var timer = timeoutTimerFactory.createObject(root, { interval: timeout, targetProcess: proc })
        if (input !== undefined && input !== null) {
            proc.stdinEnabled = true
        }
        proc.running = true
    }
}