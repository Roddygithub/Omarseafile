import QtQuick
import QtQuick.Controls
import Quickshell.Io
import qs.Commons
import qs.Ui
import "../js"

Item {
    id: root
    property QtObject bar: null
    property alias pathField: pathField
    property alias uploadButton: uploadButton
    property alias cancelButton: cancelButton
    property alias errorText: errorText
    property var onUpload: null
    property var onCancel: null
    property var onFilesSelected: null

    width: parent.width
    implicitHeight: column.implicitHeight
    height: implicitHeight

    // True while the path field owns keyboard focus. The panel's key catcher
    // reads this to stop interpreting typing as panel shortcuts.
    readonly property bool editing: pathField.activeFocus

    Component.onCompleted: pathField.forceActiveFocus()

    function openPicker() {
        if (pickerProcess.running) return
        pickerProcess.command = ["zenity", "--file-selection", "--multiple",
            "--separator=\n", "--file-filter=All files (*)"]
        pickerProcess.running = true
    }

    Process {
        id: pickerProcess
        stdout: StdioCollector {}

        onExited: function(exitCode) {
            if (exitCode === 0) {
                var text = pickerProcess.stdout.text.trim()
                if (text === "") return
                var lines = text.split("\n")
                var urls = []
                for (var i = 0; i < lines.length; i++) {
                    var line = lines[i].trim()
                    if (line !== "") {
                        urls.push("file://" + line)
                    }
                }
                if (urls.length > 0 && root.onFilesSelected) root.onFilesSelected(urls)
            }
        }
    }

    Column {
        id: column
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Style.space(16)
        width: Math.min(parent.width, Style.space(400))

        Text {
            text: "Upload File"
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.display
            font.bold: true
        }

        Text {
            text: "Choose files to upload"
            color: Qt.darker(root.bar.foreground, 1.4)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.body
            wrapMode: Text.WordWrap
            width: parent.width
        }

        Row {
            width: parent.width
            spacing: Style.space(8)

            TextField {
                id: pathField
                width: parent.width - Style.space(8) - browseButton.width
                placeholderText: "/home/user/file.txt"
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.body
                // Escape closes this dialog only — never the whole panel.
                Keys.onEscapePressed: function(event) {
                    event.accepted = true
                    if (root.onCancel) root.onCancel()
                }
            }

            Button {
                id: browseButton
                width: Style.space(80)
                height: Style.space(32)
                text: "Browse..."
                tooltipText: "Open graphical file picker"
                onClicked: root.openPicker()
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
            text: Models.boundedDisplayText(errorText._raw, 4096)
            property string _raw: ""
        }

        Row {
            spacing: Style.space(12)
            width: parent.width

            Button {
                id: cancelButton
                width: parent.width / 2 - Style.space(6)
                text: "Cancel"
                onClicked: {
                    if (root.onCancel) root.onCancel()
                }
            }

            Button {
                id: uploadButton
                width: parent.width / 2 - Style.space(6)
                text: "Upload"
                onClicked: {
                    if (root.onUpload) root.onUpload()
                }
            }
        }
    }
}
