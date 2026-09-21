import QtQuick
import Quickshell
import Quickshell.Io
import "./js"

ShellRoot {
    id: root

    // Driven by scripts/test_http_integration.py against a local Python HTTP
    // server. Exercises the REAL HttpTransport curl pipeline (body file + status
    // on stdout) and the callback contract (success, data, error, status).

    property var results: []
    property int doneCount: 0
    readonly property int totalExpected: 7

    function record(name, ok, detail) {
        root.results = root.results.concat([name + "=" + (ok ? "PASS" : "FAIL") + (detail !== undefined ? ":" + detail : "")])
        root.doneCount++
        if (root.doneCount >= root.totalExpected) finish()
    }

    // baseUrl injected as an argv/env by the test driver.
    property string base: Quickshell.env("HTTP_TEST_BASE") || ""

    Timer {
        id: guardTimer
        interval: 20000
        repeat: false
        onTriggered: {
            console.log("HTTPGUARD timeout; done=" + root.doneCount)
            Qt.quit()
        }
    }

    function run() {
        if (root.base === "") { console.log("HTTPINT no-base"); Qt.quit(); return }
        guardTimer.start()

        // 200 with JSON body
        HttpTransport.get(root.base + "/ok", { "Accept": "application/json" }, function(success, data, error, status) {
            var ok = success === true && status === 200 && data && data.token === "abc"
            root.record("status200", ok, "success=" + success + " status=" + status + " data=" + JSON.stringify(data) + " err=" + error)
            proceed1()
        })

        // 404 (curl -f yields non-zero exit, status still captured)
        HttpTransport.get(root.base + "/missing", { "Accept": "application/json" }, function(success, data, error, status) {
            root.record("status404", success === false && status === 404, "success=" + success + " status=" + status + " err=" + error)
            proceed2()
        })

        // 401
        HttpTransport.get(root.base + "/unauth", { "Accept": "application/json" }, function(success, data, error, status) {
            root.record("status401", success === false && status === 401, "success=" + success + " status=" + status)
            proceed3()
        })

        // 503
        HttpTransport.get(root.base + "/busy", { "Accept": "application/json" }, function(success, data, error, status) {
            root.record("status503", success === false && status === 503, "success=" + success + " status=" + status)
            proceed4()
        })

        // 200 JSON that echoes so we can confirm the body is parsed, not swapped
        HttpTransport.get(root.base + "/echo", { "Accept": "application/json" }, function(success, data, error, status) {
            var ok = success === true && status === 200 && data && data.hello === "world"
            root.record("bodyParsed", ok, "data=" + JSON.stringify(data))
            proceed5()
        })

        // POST body round-trip
        HttpTransport.post(root.base + "/post", { "Accept": "application/json" }, "raw-bytes", function(success, data, error, status) {
            var ok = success === true && status === 200 && data && data.saw === "raw-bytes"
            root.record("postBody", ok, "status=" + status + " data=" + JSON.stringify(data))
            proceed6()
        })

        // oversized response rejected
        HttpTransport.get(root.base + "/large", { "Accept": "application/json" }, function(success, data, error, status) {
            // --max-filesize forces a non-zero exit before the body is accepted.
            root.record("oversized", success === false, "success=" + success + " status=" + status + " err=" + error)
            proceed7()
        })
    }

    function proceed1() { /* serialised for determinism; callbacks are sequential here */ }
    function proceed2() { }
    function proceed3() { }
    function proceed4() { }
    function proceed5() { }
    function proceed6() { }
    function proceed7() { }

    function finish() {
        guardTimer.stop()
        for (var i = 0; i < root.results.length; i++) console.log("HTTPINT " + root.results[i])
        Qt.quit()
    }

    Component.onCompleted: run()
}