import QtQuick
import QtTest
import "components"

TestCase {
    id: tests
    name: "LoginDialog"
    width: 500
    height: 500
    // Quickshell hosts the item; unlike qmltestrunner it does not set windowShown.
    when: ready
    property bool ready: false
    property var calls: []
    property int dismissals: 0
    Timer { interval: 100; running: true; onTriggered: tests.ready = true }
    TestResult { id: results }
    onCompletedChanged: if (completed) {
        console.log("LOGIN_RESULTS", results.passCount, results.failCount, results.skipCount)
        console.log(results.failCount === 0 ? "LOGIN_KEYBOARD_OK" : "LOGIN_KEYBOARD_FAILED")
    }

    LoginDialog {
        id: dialog
        bar: QtObject {
            property color foreground: "white"
            property string fontFamily: "sans-serif"
        }
        onLogin: function(url, email, password) { tests.calls.push([url, email, password]) }
        onDismiss: function() { tests.dismissals++ }
    }

    function init() {
        calls = []
        dismissals = 0
        dialog.loading = false
        dialog.serverField.text = "https://example.invalid"
        dialog.emailField.text = "user@example.invalid"
        dialog.passwordField.text = "test-password"
    }

    function test_keys_data() {
        var rows = []
        for (var field of ["serverField", "emailField", "passwordField"])
            for (var key of [Qt.Key_Return, Qt.Key_Enter])
                rows.push({tag: field + "-" + key, field: field, key: key})
        return rows
    }

    function test_keys(data) {
        dialog[data.field].forceActiveFocus()
        verify(dialog.editing)
        keyClick(data.key)
        // No busy-state side effect in the callback: duplicate wiring cannot hide.
        compare(calls.length, 1)
        compare(calls[0], ["https://example.invalid", "user@example.invalid", "test-password"])

        dialog.loading = true
        keyClick(data.key)
        compare(calls.length, 1)
        verify(!dialog.loginButton.enabled)
        dialog.loading = false
        keyClick(data.key)
        compare(calls.length, 2)

        for (var field of ["serverField", "emailField", "passwordField"]) {
            var saved = dialog[field].text
            dialog[field].text = field === "passwordField" ? "" : "   "
            keyClick(data.key)
            compare(calls.length, 2)
            dialog[field].text = saved
        }
        keyClick(Qt.Key_Escape)
        compare(dismissals, 1)
        compare(calls.length, 2)
    }

    function test_read_only_paste_and_password_editing() {
        verify(dialog.serverField.readOnly)
        verify(dialog.emailField.readOnly)
        verify(dialog.passwordField.readOnly)
        compare(dialog.pasteByteLength("a"), 1)
        compare(dialog.pasteByteLength("é"), 2)
        compare(dialog.pasteByteLength("🙂"), 4)
        verify(dialog.pasteByteLength("x".repeat(dialog.pasteMaxBytes + 1)) > dialog.pasteMaxBytes)

        dialog.passwordField.forceActiveFocus()
        dialog.passwordField.cursorPosition = dialog.passwordField.length
        keyClick(Qt.Key_X)
        compare(dialog.passwordField.text, "test-passwordx")
        keyClick(Qt.Key_Backspace)
        compare(dialog.passwordField.text, "test-password")
    }

    function test_guarded_paste_never_hangs() {
        dialog.serverField.text = ""
        dialog.validationMessage = ""
        dialog.serverField.forceActiveFocus()
        // Clipboard reads happen only after an explicit shortcut and run in a
        // bounded helper process; the headless harness has no clipboard.
        keyClick(Qt.Key_V, Qt.ControlModifier)
        verify(dialog.pasteReadInFlight)
        var waited = 0
        while (dialog.pasteReadInFlight && waited < 8000) {
            wait(250)
            waited += 250
        }
        verify(!dialog.pasteReadInFlight)
        compare(dialog.validationMessage !== "", true)
        verify(dialog.editing)
    }
}
