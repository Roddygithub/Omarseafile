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

    // Zenity separates selected paths with the requested separator. A newline
    // is the only practical choice here, which means a filename that itself
    // contains a newline cannot be represented - see README "Known
    // limitations". Everything else, including spaces, percent signs and
    // non-ASCII characters, survives intact.
    readonly property string pickerSeparator: "\n"

    function openPicker() {
        if (pickerProcess.running) return
        pickerProcess.command = ["zenity", "--file-selection", "--multiple",
            "--separator=" + root.pickerSeparator, "--file-filter=All files | *"]
        pickerProcess.running = true
    }

    // Split zenity's stdout into filesystem paths.
    //
    // Zenity already prints absolute filesystem paths. They must NOT be turned
    // into file:// URLs and must NOT be decodeURIComponent()-ed: doing so
    // corrupts real filenames such as "100% termine.txt" or a literal
    // "foo%20bar.txt". Only the transport framing is removed - a trailing
    // newline and, on some locales, a carriage return - and legitimately
    // leading/trailing spaces inside a filename are preserved.
    function parsePickerOutput(text) {
        if (typeof text !== "string") return []
        var normalized = text.replace(/\r/g, "")
        if (normalized.length > 0 && normalized.charAt(normalized.length - 1) === "\n") {
            normalized = normalized.substring(0, normalized.length - 1)
        }
        if (normalized === "") return []
        var parts = normalized.split("\n")
        var paths = []
        for (var i = 0; i < parts.length; i++) {
            // An empty record can only come from framing, never from a real
            // path: zenity never emits an empty selection entry.
            if (parts[i] !== "") paths.push(parts[i])
        }
        return paths
    }

    Process {
        id: pickerProcess
        stdout: StdioCollector {}

        onExited: function(exitCode) {
            // Non-zero means the user cancelled (1) or zenity errored (5);
            // neither produces a selection.
            if (exitCode !== 0) return
            var paths = root.parsePickerOutput(pickerProcess.stdout.text)
            if (paths.length > 0 && root.onFilesSelected) root.onFilesSelected(paths)
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
