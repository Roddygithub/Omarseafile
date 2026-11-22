import QtQuick
import QtQuick.Controls
import Quickshell.Io

// A TextField that never hands a foreign clipboard offer to Qt.
//
// Qt's native paste retrieves the whole offer before it can be measured, so
// every route that reaches it is intercepted here: Ctrl+V, Shift+Insert,
// middle-click (PRIMARY) and text drops. The paste is read through wl-paste
// with a byte cap and an absolute deadline; an oversized, truncated, late or
// failed transfer inserts nothing at all.
TextField {
    id: root

    // Characters accepted from one paste; the transfer cap is its UTF-8 worst case.
    property int pasteLimit: 2000
    readonly property int pasteBytes: pasteLimit * 4 + 1
    property bool pasteBusy: false

    function requestPaste(primary) {
        if (root.pasteBusy || root.readOnly) return
        root.pasteBusy = true
        reader.primary = primary === true
        reader.running = true
        pasteDeadline.restart()
    }

    function applyPaste(text) {
        var clean = (text || "").replace(/[\r\n]+/g, " ").trim()
        if (clean === "") return
        if (clean.length > root.pasteLimit) return  // oversized: refuse, never truncate
        if (root.selectedText.length > 0) root.remove(root.selectionStart, root.selectionEnd)
        root.insert(root.cursorPosition, clean)
    }

    // Only when this route is reached; nothing else touches the clipboard.
    Keys.onPressed: function(event) {
        var isPaste = event.matches(StandardKey.Paste)
            || (event.key === Qt.Key_Insert && (event.modifiers & Qt.ShiftModifier))
        if (isPaste) {
            event.accepted = true
            root.requestPaste(false)
        }
    }

    Process {
        id: reader
        property bool primary: false
        // Head caps the bytes *before* they reach the collector, and the shell
        // variable holds only what head released.
        command: ["/bin/sh", "-c",
            "out=$(wl-paste --no-newline " + (primary ? "--primary " : "") + "2>/dev/null | head -c "
            + root.pasteBytes + "); n=$(printf '%s' \"$out\" | wc -c); "
            + "[ \"$n\" -lt " + root.pasteBytes + " ] || exit 3; printf '%s' \"$out\""]
        stdout: StdioCollector {
            waitForEnd: true
        }
        onExited: function(exitCode) {
            pasteDeadline.stop()
            pasteKill.stop()
            root.pasteBusy = false
            if (exitCode === 0) root.applyPaste(stdout.text)
        }
    }

    // Termination is a request: escalate so a wedged wl-paste cannot hold the
    // single paste slot forever.
    Timer {
        id: pasteDeadline
        interval: 1000
        onTriggered: {
            if (!reader.running) return
            reader.signal(15)
            pasteKill.restart()
        }
    }

    Timer {
        id: pasteKill
        interval: 500
        onTriggered: {
            if (reader.running) reader.signal(9)
        }
    }

    // Middle-click pastes PRIMARY through the native path otherwise.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.MiddleButton
        onPressed: function(mouse) {
            root.forceActiveFocus()
            root.requestPaste(true)
            mouse.accepted = true
        }
    }

    // A dropped text offer would be retrieved whole by Qt: swallow the drop.
    DropArea {
        anchors.fill: parent
        onEntered: function(drag) { drag.accepted = true }
        onDropped: function(drop) { drop.accepted = true }
    }
}
