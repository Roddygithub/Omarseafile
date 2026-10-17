import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui
import "../js"

Item {
    id: root
    property QtObject bar: null
    property alias emailField: emailField
    property alias passwordField: passwordField
    property alias serverField: serverField
    property alias loginButton: loginButton
    property alias errorText: errorText
    property string serverUrl: ""
    property string depErrorMessage: ""
    property string errorMessage: ""
    property string validationMessage: ""
    property bool loading: false
    property var onLogin: null
    property var onDismiss: null
    property bool pasteReadInFlight: false
    property var pasteTarget: null
    readonly property int pasteMaxBytes: 16384
    readonly property string pasteDeadlineSeconds: "2"

    Component.onCompleted: {
        var email = Auth.getEmail()
        if (email) emailField.text = email
        serverField.forceActiveFocus()
    }

    function submit() {
        if (root.loading) return
        if (!serverField.text.trim()) {
            root.validationMessage = "Enter your Seafile server URL."
            serverField.forceActiveFocus()
            return
        }
        if (!emailField.text.trim()) {
            root.validationMessage = "Enter your email address."
            emailField.forceActiveFocus()
            return
        }
        if (!passwordField.text) {
            root.validationMessage = "Enter your password."
            passwordField.forceActiveFocus()
            return
        }
        root.validationMessage = ""
        if (root.onLogin) root.onLogin(serverField.text, emailField.text.trim(), passwordField.text)
    }

    // Keep Qt's TextInput read-only: affected Qt versions inspect clipboard
    // contents whenever an editable TextInput sees a clipboard change.
    function isPasteShortcut(event) {
        return ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_V)
            || ((event.modifiers & Qt.ShiftModifier) && event.key === Qt.Key_Insert)
    }

    function pasteByteLength(text) {
        var encoded = encodeURIComponent(text)
        return encoded.length - (encoded.match(/%[0-9A-F]{2}/g) || []).length * 2
    }

    function requestPaste(field, primary) {
        if (root.loading || root.pasteReadInFlight) return
        root.validationMessage = ""
        root.pasteTarget = field
        root.pasteReadInFlight = true
        pasteProcess.command = ["bash", "-c", "set -o pipefail; timeout -s KILL "
            + root.pasteDeadlineSeconds + " wl-paste " + (primary ? "--primary " : "")
            + "--no-newline --type text/plain | head -c " + (root.pasteMaxBytes + 1)]
        pasteProcess.running = true
    }

    function insertText(field, text) {
        var start = field.selectionStart
        var end = field.selectionEnd
        var position = start >= 0 ? start : field.cursorPosition
        if (start >= 0 && end > start) field.remove(start, end)
        field.insert(position, text)
        field.cursorPosition = position + text.length
        field.deselect()
        root.validationMessage = ""
    }

    function handleKeys(field, event) {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.submit()
            event.accepted = true
        } else if (root.isPasteShortcut(event)) {
            root.requestPaste(field, false)
            event.accepted = true
        } else if (event.key === Qt.Key_Menu
                   || (event.key === Qt.Key_F10 && (event.modifiers & Qt.ShiftModifier))) {
            event.accepted = true
        } else if (event.key === Qt.Key_Backspace || event.key === Qt.Key_Delete) {
            var start = field.selectionStart
            var end = field.selectionEnd
            if (start < 0 || end <= start) {
                start = field.cursorPosition
                end = start
                if (event.key === Qt.Key_Backspace && start > 0) start--
                else if (event.key === Qt.Key_Delete && end < field.length) end++
            }
            if (end > start) field.remove(start, end)
            field.cursorPosition = start
            field.deselect()
            root.validationMessage = ""
            event.accepted = true
        } else if (event.text && event.text.length > 0
                   && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))) {
            root.insertText(field, event.text)
            event.accepted = true
        }
    }

    function finishPaste(exitCode) {
        root.pasteReadInFlight = false
        var field = root.pasteTarget
        root.pasteTarget = null
        var text = pasteProcess.stdout.text
        if (root.pasteByteLength(text) > root.pasteMaxBytes) {
            root.validationMessage = "Clipboard content exceeds the 16 KiB limit."
        } else if (exitCode !== 0) {
            root.validationMessage = exitCode === 124 || exitCode === 137
                ? "Clipboard read timed out."
                : (exitCode === 127 ? "Paste unavailable: install wl-clipboard (wl-paste)."
                   : "Paste unavailable (exit " + exitCode + ").")
        } else if (field) {
            root.insertText(field, text)
        }
    }

    function handlePrimaryPaste(field, mouse) {
        mouse.accepted = true
        if (mouse.button === Qt.MiddleButton) {
            field.cursorPosition = field.positionAt(mouse.x, mouse.y)
            field.forceActiveFocus()
            root.requestPaste(field, true)
        }
    }

    function handlePasswordMouse(mouse) {
        root.handlePrimaryPaste(passwordField, mouse)
    }

    function handlePlainMouse(field, mouse) {
        root.handlePrimaryPaste(field, mouse)
    }

    readonly property bool editing: serverField.activeFocus || emailField.activeFocus || passwordField.activeFocus

    Process {
        id: pasteProcess
        stdout: StdioCollector {}
        onExited: function(exitCode) { root.finishPaste(exitCode) }
    }

    width: parent ? Math.max(parent.width, 300) : 380
    implicitHeight: column.implicitHeight

    Column {
        id: column
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Style.space(16)
        width: Math.min(parent.width, Style.space(380))

        Text {
            text: "Seafile"
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.display
            font.bold: true
        }

        Text {
            text: "Connect to your Seafile server"
            color: Qt.darker(root.bar.foreground, 1.4)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.body
            wrapMode: Text.WordWrap
            width: parent.width
        }

        Text {
            width: parent.width
            color: Color.urgent
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
            visible: root.depErrorMessage !== ""
            wrapMode: Text.WordWrap
            text: Models.boundedDisplayText(root.depErrorMessage, 4096)
            textFormat: Text.PlainText
        }

        TextField {
            id: serverField
            width: parent.width
            placeholderText: "Server URL (e.g. https://seafile.example.com)"
            Accessible.name: "Seafile server URL"
            text: root.serverUrl
            readOnly: true
            cursorVisible: activeFocus
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.body
            onTextChanged: root.validationMessage = ""
            Keys.priority: Keys.BeforeItem
            Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Escape) {
                    event.accepted = true
                    if (root.onDismiss) root.onDismiss()
                } else root.handleKeys(serverField, event)
            }
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.MiddleButton | Qt.RightButton
                onPressed: function(mouse) { root.handlePlainMouse(serverField, mouse) }
            }
        }

        TextField {
            id: emailField
            width: parent.width
            placeholderText: "Email"
            Accessible.name: "Email address"
            readOnly: true
            cursorVisible: activeFocus
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.body
            onTextChanged: root.validationMessage = ""
            Keys.priority: Keys.BeforeItem
            Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Escape) {
                    event.accepted = true
                    if (root.onDismiss) root.onDismiss()
                } else root.handleKeys(emailField, event)
            }
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.MiddleButton | Qt.RightButton
                onPressed: function(mouse) { root.handlePlainMouse(emailField, mouse) }
            }
        }

        TextField {
            id: passwordField
            width: parent.width
            placeholderText: "Password"
            Accessible.name: "Password"
            echoMode: TextField.Password
            readOnly: true
            cursorVisible: activeFocus
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.body
            onTextChanged: root.validationMessage = ""
            Keys.priority: Keys.BeforeItem
            Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Escape) {
                    event.accepted = true
                    if (root.onDismiss) root.onDismiss()
                } else root.handleKeys(passwordField, event)
            }
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.MiddleButton | Qt.RightButton
                onPressed: function(mouse) { root.handlePasswordMouse(mouse) }
            }
        }

        Text {
            id: errorText
            width: parent.width
            color: Color.urgent
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
            visible: text !== ""
            wrapMode: Text.WordWrap
            textFormat: Text.PlainText
            text: Models.boundedDisplayText(root.validationMessage || errorText._raw, 4096)
            property string _raw: root.errorMessage
        }

        Button {
            id: loginButton
            width: parent.width
            text: root.loading ? "Connecting…" : "Connect"
            Accessible.name: root.loading ? "Connecting to Seafile" : "Connect to Seafile"
            enabled: !root.loading
            onClicked: root.submit()
        }
    }
}
