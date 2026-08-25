import QtQuick
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
    property string depErrorMessage: ""
    property var onLogin: null
    property var onDismiss: null

Component.onCompleted: {
        var email = Auth.getEmail()
        if (email) emailField.text = email
    }

    // True while any login field owns keyboard focus. The panel's key catcher
    // reads this to stop interpreting typing (h/j/k/l/x, arrows, Enter,
    // Space, Escape) as panel shortcuts.
    readonly property bool editing: serverField.activeFocus || emailField.activeFocus || passwordField.activeFocus

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
            text: root.depErrorMessage
        }

        TextField {
            id: serverField
            width: parent.width
            placeholderText: "Server URL (e.g. https://seafile.example.com)"
            text: ""
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.body
            // Escape from the login form closes the whole panel — no dialog
            // sits above the form. Same pattern as the shell network panel's
            // credential fields.
            Keys.onEscapePressed: function(event) {
                event.accepted = true
                if (root.onDismiss) root.onDismiss()
            }
        }

        TextField {
            id: emailField
            width: parent.width
            placeholderText: "Email"
            text: ""
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.body
            Keys.onEscapePressed: function(event) {
                event.accepted = true
                if (root.onDismiss) root.onDismiss()
            }
        }

        TextField {
            id: passwordField
            width: parent.width
            placeholderText: "Password"
            echoMode: TextField.Password
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.body
            Keys.onEscapePressed: function(event) {
                event.accepted = true
                if (root.onDismiss) root.onDismiss()
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
        }

        Button {
            id: loginButton
            width: parent.width
            text: "Connect"
            onClicked: {
                if (root.onLogin) root.onLogin(serverField.text, emailField.text, passwordField.text)
            }
        }
    }
}