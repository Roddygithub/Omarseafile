import QtQuick
import qs.Commons
import qs.Ui
import "./ConfirmDialog.qml" as ConfirmDialog

Item {
    id: root
    property QtObject bar: null
    property var item: null
    property string repoId: ""
    property string repoName: ""
    property string itemPath: ""
    property bool isDir: false
    property var onDone: null
    property var onCancel: null

    property var existingLinks: []
    property bool loading: true
    property string errorMessage: ""
    property string shareUrl: ""
    property string shareToken: ""

    // Create form state
    property bool showCreateForm: false
    property bool enablePassword: false
    property string passwordValue: ""
    property bool enableExpiration: false
    property string expireDays: "7"
    property bool enablePermissions: false
    property bool permCanEdit: false
    property bool permCanDownload: true
    property bool permCanUpload: false

    // Revoke confirmation state
    property var revokeLinkData: null

    width: parent.width
    implicitHeight: column.implicitHeight

    Component.onCompleted: {
        loadExistingLinks()
    }

    function loadExistingLinks() {
        root.loading = true
        root.errorMessage = ""
        SeafileAPI.listShareLinks(root.repoId, root.itemPath, function(success, data, error) {
            root.loading = false
            if (success) {
                root.existingLinks = data
                if (data.length === 0) {
                    root.showCreateForm = true
                }
            } else {
                root.errorMessage = error || "Failed to load share links"
            }
        })
    }

    function createLink() {
        if (root.enablePassword && root.passwordValue.length < 6) {
            root.errorMessage = "Password must be at least 6 characters"
            return
        }
        root.loading = true
        root.errorMessage = ""
        var options = {}
        if (root.enablePassword && root.passwordValue) {
            options.password = root.passwordValue
        }
        if (root.enableExpiration && root.expireDays) {
            options.expire_days = root.expireDays
        }
        if (root.enablePermissions) {
            options.permissions = {
                can_edit: root.permCanEdit,
                can_download: root.permCanDownload,
                can_upload: root.permCanUpload
            }
        }
        SeafileAPI.createShareLink(root.repoId, root.itemPath, options, function(success, data, error) {
            root.loading = false
            if (success) {
                root.shareUrl = data.link
                root.shareToken = data.token
                root.showCreateForm = false
                root.existingLinks.push(data)
                root.existingLinks = root.existingLinks.slice()
            } else {
                root.errorMessage = error || "Failed to create share link"
            }
        })
    }

    function deleteLink(token) {
        root.loading = true
        root.errorMessage = ""
        SeafileAPI.deleteShareLink(token, function(success, error) {
            root.loading = false
            if (success) {
                root.existingLinks = root.existingLinks.filter(function(l) {
                    return l.token !== token
                })
                if (root.shareToken === token) {
                    root.shareUrl = ""
                    root.shareToken = ""
                }
                if (root.existingLinks.length === 0) {
                    root.showCreateForm = true
                }
            } else {
                root.errorMessage = error || "Failed to delete share link"
            }
        })
    }

    function copyToClipboard(text) {
        clipboardProcess.command = ["wl-copy", text]
        clipboardProcess.running = true
    }

    function confirmRevoke(linkData) {
        root.revokeLinkData = linkData
        confirmLoader.sourceComponent = confirmComponent
    }

    function cancelRevoke() {
        confirmLoader.sourceComponent = undefined
        root.revokeLinkData = null
    }

    function executeRevoke() {
        var linkData = root.revokeLinkData
        confirmLoader.sourceComponent = undefined
        root.revokeLinkData = null
        if (linkData) {
            root.deleteLink(linkData.token)
        }
    }

    Loader {
        id: confirmLoader
        sourceComponent: undefined
    }

    Component {
        id: confirmComponent
        ConfirmDialog {
            bar: root.bar
            message: "Revoke share link for \"" + root.revokeLinkData.obj_name + "\"?"
            onConfirm: root.executeRevoke()
            onCancel: root.cancelRevoke()
        }
    }

    Process {
        id: clipboardProcess
        onExited: function(exitCode) {
            // Clipboard copied
        }
    }

    Column {
        id: column
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Style.space(16)
        width: Math.min(parent.width, Style.space(400))

        Text {
            text: "Share"
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.display
            font.bold: true
        }

        Text {
            text: root.isDir ? "Folder: " + root.item.name : "File: " + root.item.name
            color: Qt.darker(root.bar.foreground, 1.4)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.body
            elide: Text.ElideRight
            width: parent.width
        }

        // Loading indicator
        Text {
            text: "Loading..."
            color: Qt.darker(root.bar.foreground, 1.4)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.body
            visible: root.loading
        }

        // Error message
        Text {
            text: root.errorMessage
            color: Color.urgent
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.body
            visible: root.errorMessage !== ""
            wrapMode: Text.WordWrap
            width: parent.width
        }

        // Existing links list
        Column {
            width: parent.width
            spacing: Style.space(8)
            visible: !root.loading && root.existingLinks.length > 0 && !root.showCreateForm

            Text {
                text: "Existing Links"
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.body
                font.bold: true
            }

            Repeater {
                model: root.existingLinks

                delegate: Column {
                    width: parent.width
                    spacing: Style.space(4)

                    Row {
                        width: parent.width
                        spacing: Style.space(8)

                        Text {
                            text: modelData.link
                            color: root.bar.foreground
                            font.family: root.bar.fontFamily
                            font.pixelSize: Style.font.caption
                            elide: Text.ElideRight
                            width: parent.width - copyBtn.width - deleteBtn.width - Style.space(16)
                            anchors.verticalCenter: parent.verticalCenter

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.copyToClipboard(modelData.link)
                                }
                            }
                        }

                        Button {
                            id: copyBtn
                            text: "Copy"
                            font.family: root.bar.fontFamily
                            font.pixelSize: Style.font.caption
                            onClicked: {
                                root.copyToClipboard(modelData.link)
                            }
                        }

                        Button {
                            id: deleteBtn
                            text: "Revoke"
                            color: Color.urgent
                            font.family: root.bar.fontFamily
                            font.pixelSize: Style.font.caption
                            onClicked: {
                                root.confirmRevoke(modelData)
                            }
                        }
                    }

                    Text {
                        text: {
                            var info = []
                            if (modelData.expire_date) {
                                info.push("Expires: " + modelData.expire_date.split("T")[0])
                            }
                            if (modelData.password) {
                                info.push("Password protected")
                            }
                            if (modelData.permissions) {
                                var perms = []
                                if (modelData.permissions.can_edit) perms.push("Edit")
                                if (modelData.permissions.can_download) perms.push("Download")
                                if (modelData.permissions.can_upload) perms.push("Upload")
                                if (perms.length > 0) info.push(perms.join(", "))
                            }
                            return info.join(" | ")
                        }
                        color: Qt.darker(root.bar.foreground, 1.4)
                        font.family: root.bar.fontFamily
                        font.pixelSize: Style.font.caption
                        visible: text !== ""
                    }
                }
            }

            Button {
                width: parent.width
                text: "Create New Link"
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.body
                onClicked: {
                    root.showCreateForm = true
                }
            }
        }

        // Create form
        Column {
            width: parent.width
            spacing: Style.space(8)
            visible: !root.loading && root.showCreateForm

            Text {
                text: "Create Share Link"
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.body
                font.bold: true
            }

            // Password option
            Row {
                spacing: Style.space(8)
                width: parent.width

                Switch {
                    id: passwordSwitch
                    checked: root.enablePassword
                    onCheckedChanged: root.enablePassword = checked
                }

                Text {
                    text: "Password protect"
                    color: root.bar.foreground
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.body
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            TextField {
                id: passwordField
                width: parent.width
                placeholderText: "Password (min 6 chars)"
                text: root.passwordValue
                onTextChanged: root.passwordValue = text
                visible: root.enablePassword
                echoMode: TextInput.Password
            }

            // Expiration option
            Row {
                spacing: Style.space(8)
                width: parent.width

                Switch {
                    id: expirationSwitch
                    checked: root.enableExpiration
                    onCheckedChanged: root.enableExpiration = checked
                }

                Text {
                    text: "Set expiration"
                    color: root.bar.foreground
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.body
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            Row {
                spacing: Style.space(8)
                width: parent.width
                visible: root.enableExpiration

                TextField {
                    id: expireDaysField
                    width: parent.width - daysLabel.width - Style.space(8)
                    placeholderText: "Days"
                    text: root.expireDays
                    onTextChanged: root.expireDays = text
                    validator: IntValidator { bottom: 1; top: 365 }
                }

                Text {
                    id: daysLabel
                    text: "days"
                    color: root.bar.foreground
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.body
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            // Permissions option
            Row {
                spacing: Style.space(8)
                width: parent.width

                Switch {
                    id: permissionsSwitch
                    checked: root.enablePermissions
                    onCheckedChanged: root.enablePermissions = checked
                }

                Text {
                    text: "Set permissions"
                    color: root.bar.foreground
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.body
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            Column {
                width: parent.width
                spacing: Style.space(4)
                visible: root.enablePermissions

                Row {
                    spacing: Style.space(8)
                    width: parent.width

                    Switch {
                        id: canEditSwitch
                        checked: root.permCanEdit
                        onCheckedChanged: root.permCanEdit = checked
                    }

                    Text {
                        text: "Can edit"
                        color: root.bar.foreground
                        font.family: root.bar.fontFamily
                        font.pixelSize: Style.font.body
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                Row {
                    spacing: Style.space(8)
                    width: parent.width

                    Switch {
                        id: canDownloadSwitch
                        checked: root.permCanDownload
                        onCheckedChanged: root.permCanDownload = checked
                    }

                    Text {
                        text: "Can download"
                        color: root.bar.foreground
                        font.family: root.bar.fontFamily
                        font.pixelSize: Style.font.body
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                Row {
                    spacing: Style.space(8)
                    width: parent.width
                    visible: root.isDir

                    Switch {
                        id: canUploadSwitch
                        checked: root.permCanUpload
                        onCheckedChanged: root.permCanUpload = checked
                    }

                    Text {
                        text: "Can upload"
                        color: root.bar.foreground
                        font.family: root.bar.fontFamily
                        font.pixelSize: Style.font.body
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }

            // Created link display
            Column {
                width: parent.width
                spacing: Style.space(8)
                visible: root.shareUrl !== ""

                Text {
                    text: "Link created!"
                    color: Color.success
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.body
                    font.bold: true
                }

                Row {
                    width: parent.width
                    spacing: Style.space(8)

                    Text {
                        text: root.shareUrl
                        color: root.bar.foreground
                        font.family: root.bar.fontFamily
                        font.pixelSize: Style.font.caption
                        elide: Text.ElideRight
                        width: parent.width - copyCreatedBtn.width - Style.space(8)
                        anchors.verticalCenter: parent.verticalCenter

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.copyToClipboard(root.shareUrl)
                            }
                        }
                    }

                    Button {
                        id: copyCreatedBtn
                        text: "Copy"
                        font.family: root.bar.fontFamily
                        font.pixelSize: Style.font.caption
                        onClicked: {
                            root.copyToClipboard(root.shareUrl)
                        }
                    }
                }
            }
        }

        // Buttons
        Row {
            spacing: Style.space(12)
            width: parent.width

            Button {
                width: parent.width / 2 - Style.space(6)
                text: "Close"
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.body
                onClicked: {
                    if (root.onDone) root.onDone()
                }
            }

            Button {
                width: parent.width / 2 - Style.space(6)
                text: "Create"
                visible: root.showCreateForm && root.shareUrl === ""
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.body
                onClicked: {
                    root.createLink()
                }
            }
        }
    }
}
