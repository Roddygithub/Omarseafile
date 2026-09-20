import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui
import "../js"

Item {
    id: root
    required property var bar
    property var onClose: null
    property var onLogout: null
    property var onClearCache: null
    property var onChangeServer: null
    property var onTestConnection: null
    property var onAutoLoginToggled: null
    property var onSingleClickOpenToggled: null
    property var onSortColumnChange: null
    property var onSortAscendingChange: null
    property var onFoldersFirstToggled: null
    property var onNotifyToggled: null

    Component.onCompleted: {
        var email = Auth.getEmail()
        if (email) root.accountEmail = email
        serverUrlField.forceActiveFocus()
    }

    width: parent.width
    implicitHeight: column.implicitHeight
    height: implicitHeight

    // True while the server-URL field owns keyboard focus. The panel's key
    // catcher reads this to stop interpreting typing as panel shortcuts.
    readonly property bool editing: serverUrlField.activeFocus

    property string serverUrl: ""
    property string accountEmail: ""
    property string pluginVersion: "1.0.0"
    property bool autoLogin: true
    property bool singleClickOpen: false
    property string sortColumn: "name"
    property bool sortAscending: true
    property bool foldersFirst: true
    property bool notifyEnabled: true
    property bool connectionTestRunning: false
    property bool connectionTestSuccess: false
    property string connectionTestMessage: ""

    Column {
        id: column
        spacing: Style.space(10)
        width: Math.min(parent.width, Style.space(420))

        Text {
            text: "Settings"
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.heading
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
            spacing: Style.space(6)
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
                // Escape closes settings only — never the whole panel.
                Keys.onEscapePressed: function(event) {
                    event.accepted = true
                    if (root.onClose) root.onClose()
                }
            }

            Row {
                spacing: Style.space(8)
                width: parent.width
                Button {
                    id: testConnectionButton
                    width: parent.width / 2 - Style.space(4)
                    text: "Test Connection"
                    onClicked: {
                        if (root.onTestConnection) root.onTestConnection(serverUrlField.text)
                    }
                }
                Button {
                    id: applyServerButton
                    width: parent.width / 2 - Style.space(4)
                    text: "Apply Server"
                    onClicked: {
                        if (root.onChangeServer) root.onChangeServer(serverUrlField.text, true)
                    }
                }
            }

            Text {
                id: connectionTestResult
                width: parent.width
                text: Models.boundedDisplayText(root.connectionTestMessage, 4096)
                color: root.connectionTestSuccess ? Style.green : (root.connectionTestRunning ? Qt.darker(root.bar.foreground, 1.3) : Color.urgent)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
                visible: text !== ""
                textFormat: Text.PlainText
            }

        }

        Rectangle {
            width: parent.width
            height: Style.spacing.hairline
            color: root.bar.foreground
            opacity: 0.12
        }

        // Account Section
        Column {
            spacing: Style.space(6)
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
                height: Style.space(26)
                Row {
                    spacing: Style.space(6)
                    Text {
                        text: Icons.user
                        font.family: Icons.family
                        font.pixelSize: Style.font.title
                        color: Qt.darker(root.bar.foreground, 1.4)
                        height: parent.height
                        verticalAlignment: Text.AlignVCenter
                        width: Style.space(24)
                    }
                    Text {
                        text: Models.boundedDisplayText(root.accountEmail || Auth.cachedEmail || "Not signed in", 320)
                        color: root.bar.foreground
                        font.family: root.bar.fontFamily
                        font.pixelSize: Style.font.body
                        elide: Text.ElideRight
                        height: parent.height
                        verticalAlignment: Text.AlignVCenter
                        textFormat: Text.PlainText
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
            spacing: Style.space(6)
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
                    width: parent.width - autoLoginSwitch.width - Style.space(8)
                    height: parent.height
                    verticalAlignment: Text.AlignVCenter
                }
                Switch {
                    id: autoLoginSwitch
                    checked: root.autoLogin
                    onToggled: {
                        if (root.onAutoLoginToggled) root.onAutoLoginToggled(checked)
                    }
                    height: parent.height
                }
            }

            Row {
                width: parent.width
                spacing: Style.space(8)
                Text {
                    text: "Single-click to open"
                    color: root.bar.foreground
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.body
                    width: parent.width - singleClickOpenSwitch.width - Style.space(8)
                    height: parent.height
                    verticalAlignment: Text.AlignVCenter
                }
                Switch {
                    id: singleClickOpenSwitch
                    checked: root.singleClickOpen
                    onToggled: {
                        if (root.onSingleClickOpenToggled) root.onSingleClickOpenToggled(checked)
                    }
                    height: parent.height
                }
            }

            Row {
                width: parent.width
                spacing: Style.space(8)
                Text {
                    text: "Default sort"
                    color: root.bar.foreground
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.body
                    width: parent.width - sortColumnCombo.width - Style.space(8)
                    height: parent.height
                    verticalAlignment: Text.AlignVCenter
                }
                ComboBox {
                    id: sortColumnCombo
                    width: Style.space(120)
                    model: ["Name", "Size", "Modified", "Type"]
                    currentIndex: ["name", "size", "date", "type"].indexOf(root.sortColumn)
                    onActivated: {
                        if (root.onSortColumnChange) root.onSortColumnChange(["name", "size", "date", "type"][index])
                    }
                    height: parent.height
                }
            }

            Row {
                width: parent.width
                spacing: Style.space(8)
                Text {
                    text: "Folders first"
                    color: root.bar.foreground
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.body
                    width: parent.width - foldersFirstSwitch.width - Style.space(8)
                    height: parent.height
                    verticalAlignment: Text.AlignVCenter
                }
                Switch {
                    id: foldersFirstSwitch
                    // Was a hard-coded, disabled always-true switch: the setting
                    // existed in the UI but did nothing.
                    checked: root.foldersFirst
                    onToggled: {
                        if (root.onFoldersFirstToggled) root.onFoldersFirstToggled(checked)
                    }
                    height: parent.height
                }
            }

            Row {
                width: parent.width
                spacing: Style.space(8)
                Text {
                    text: "Ascending"
                    color: root.bar.foreground
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.body
                    width: parent.width - sortAscendingSwitch.width - Style.space(8)
                    height: parent.height
                    verticalAlignment: Text.AlignVCenter
                }
                Switch {
                    id: sortAscendingSwitch
                    checked: root.sortAscending
                    onToggled: {
                        if (root.onSortAscendingChange) root.onSortAscendingChange(checked)
                    }
                    height: parent.height
                }
            }

            Row {
                width: parent.width
                spacing: Style.space(8)
                Text {
                    text: "Transfer notifications"
                    color: root.bar.foreground
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.body
                    width: parent.width - notifySwitch.width - Style.space(8)
                    height: parent.height
                    verticalAlignment: Text.AlignVCenter
                }
                Switch {
                    id: notifySwitch
                    checked: root.notifyEnabled
                    onToggled: {
                        if (root.onNotifyToggled) root.onNotifyToggled(checked)
                    }
                    height: parent.height
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
            spacing: Style.space(6)
            width: parent.width

            Text {
                text: "Data"
                color: Qt.darker(root.bar.foreground, 1.3)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.letterSpacing: 1
            }

            Row {
                width: parent.width
                spacing: Style.space(8)
                Button {
                    id: clearCacheButton
                    width: (parent.width - Style.space(8)) / 2
                    text: "Clear Cache"
                    onClicked: {
                        if (root.onClearCache) root.onClearCache()
                    }
                }
                Button {
                    id: logoutButton
                    width: (parent.width - Style.space(8)) / 2
                    text: "Logout"
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
                text: Models.boundedDisplayText("Omarseafile v" + root.pluginVersion + "\nSeafile client for Omarchy\n\nReport issues: https://github.com/Roddygithub/Omarseafile/issues", 1024)
                color: Qt.darker(root.bar.foreground, 1.4)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                textFormat: Text.PlainText
            }
        }

        // Close button
        Item { width: 1; height: Style.space(4) }

        Button {
            width: parent.width
            text: "Close"
            onClicked: {
                if (root.onClose) root.onClose()
            }
        }
    }
}
