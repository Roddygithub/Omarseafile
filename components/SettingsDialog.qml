import QtQuick
import qs.Commons
import qs.Ui

Item {
    id: root
    required property var bar
    property var onClose: null
    property var onLogout: null
    property var onClearCache: null
    property var onChangeServer: null
    property var onTestConnection: null
    property var onAutoLoginChanged: null

    width: parent.width
    implicitHeight: column.implicitHeight

    property string serverUrl: ""
    property string accountEmail: ""
    property string pluginVersion: "0.8.0"
    property bool autoLogin: true

    Column {
        id: column
        spacing: Style.space(20)
        width: Math.min(parent.width, Style.space(420))
        anchors.horizontalCenter: parent.horizontalCenter

        Text {
            text: "Settings"
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.display
            font.bold: true
        }

        Rectangle {
            width: parent.width
            height: Style.spacing.hairline
            color: root.bar.foreground
            opacity: 0.12
        }

        // Connection Section
        Column {
            spacing: Style.space(12)
            width: parent.width

            Text {
                text: "Connection"
                color: Qt.darker(root.bar.foreground, 1.3)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.letterSpacing: 1
            }

            TextField {
                id: serverUrlField
                width: parent.width
                placeholderText: "https://seafile.example.com"
                text: root.serverUrl
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.body
                background: Rectangle {
                    color: Qt.darker(root.bar.background, 1.2)
                    radius: Style.cornerRadius
                    border.color: Qt.darker(root.bar.background, 1.4)
                    border.width: 1
                }
                onTextChanged: {
                    if (root.onChangeServer) root.onChangeServer(text)
                }
            }

            Row {
                spacing: Style.space(8)
                Button {
                    id: testConnectionButton
                    width: parent.width / 2 - Style.space(4)
                    text: "Test Connection"
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.body
                    onClicked: {
                        if (root.onTestConnection) root.onTestConnection(serverUrlField.text)
                    }
                }
                Button {
                    id: applyServerButton
                    width: parent.width / 2 - Style.space(4)
                    text: "Apply Server"
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.body
                    onClicked: {
                        if (root.onChangeServer) root.onChangeServer(serverUrlField.text, true)
                    }
                }
            }

            Text {
                id: connectionTestResult
                width: parent.width
                color: root.connectionTestSuccess ? Style.green : (root.connectionTestRunning ? Qt.darker(root.bar.foreground, 1.3) : Color.urgent)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
                visible: text !== ""
            }

            property bool connectionTestRunning: false
            property bool connectionTestSuccess: false
        }

        Rectangle {
            width: parent.width
            height: Style.spacing.hairline
            color: root.bar.foreground
            opacity: 0.12
        }

        // Account Section
        Column {
            spacing: Style.space(12)
            width: parent.width

            Text {
                text: "Account"
                color: Qt.darker(root.bar.foreground, 1.3)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.letterSpacing: 1
            }

            Item {
                width: parent.width
                height: Style.space(36)
                Row {
                    anchors.fill: parent
                    spacing: Style.space(12)
                    Text {
                        text: "\uf007"
                        font.family: "Noto Sans"
                        font.pixelSize: Style.font.title
                        color: Qt.darker(root.bar.foreground, 1.4)
                        anchors.verticalCenter: parent.verticalCenter
                        width: Style.space(24)
                    }
                    Text {
                        text: root.accountEmail || "Not signed in"
                        color: root.bar.foreground
                        font.family: root.bar.fontFamily
                        font.pixelSize: Style.font.body
                        elide: Text.ElideRight
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }
        }

        Rectangle {
            width: parent.width
            height: Style.spacing.hairline
            color: root.bar.foreground
            opacity: 0.12
        }

        // Preferences Section
        Column {
            spacing: Style.space(12)
            width: parent.width

            Text {
                text: "Preferences"
                color: Qt.darker(root.bar.foreground, 1.3)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.letterSpacing: 1
            }

            Row {
                width: parent.width
                spacing: Style.space(8)
                Text {
                    text: "Auto-login"
                    color: root.bar.foreground
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.body
                    anchors.verticalCenter: parent.verticalCenter
                }
                Switch {
                    id: autoLoginSwitch
                    checked: root.autoLogin
                    onToggled: {
                        if (root.onAutoLoginChanged) root.onAutoLoginChanged(checked)
                    }
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }

        Rectangle {
            width: parent.width
            height: Style.spacing.hairline
            color: root.bar.foreground
            opacity: 0.12
        }

        // Data Section
        Column {
            spacing: Style.space(12)
            width: parent.width

            Text {
                text: "Data"
                color: Qt.darker(root.bar.foreground, 1.3)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.letterSpacing: 1
            }

            Row {
                spacing: Style.space(8)
                Button {
                    id: clearCacheButton
                    width: parent.width / 2 - Style.space(4)
                    text: "Clear Cache"
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.body
                    onClicked: {
                        if (root.onClearCache) root.onClearCache()
                    }
                }
                Button {
                    id: logoutButton
                    width: parent.width / 2 - Style.space(4)
                    text: "Logout"
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.body
                    color: Color.urgent
                    onClicked: {
                        if (root.onLogout) root.onLogout()
                    }
                }
            }
        }

        Rectangle {
            width: parent.width
            height: Style.spacing.hairline
            color: root.bar.foreground
            opacity: 0.12
        }

        // About Section
        Column {
            spacing: Style.space(8)
            width: parent.width

            Text {
                text: "About"
                color: Qt.darker(root.bar.foreground, 1.3)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.letterSpacing: 1
            }

            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                text: "Omarseafile v" + root.pluginVersion + "\nSeafile client for Omarchy\n\nReport issues: https://github.com/roddy/Omarseafile/issues"
                color: Qt.darker(root.bar.foreground, 1.4)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
            }
        }

        // Close button
        Button {
            width: parent.width
            text: "Close"
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.body
            onClicked: {
                if (root.onClose) root.onClose()
            }
        }
    }
}