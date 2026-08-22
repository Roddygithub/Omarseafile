import QtQuick
import qs.Commons
import qs.Ui

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

    width: parent.width
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
        }

        TextField {
            id: emailField
            width: parent.width
            placeholderText: "Email"
            text: ""
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.body
        }

        TextField {
            id: passwordField
            width: parent.width
            placeholderText: "Password"
            echoMode: TextField.Password
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.body
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
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.body
            onClicked: {
                if (root.onLogin) root.onLogin()
            }
        }
    }
}