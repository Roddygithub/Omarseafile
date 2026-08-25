import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui

// Destination folder picker for Copy/Move — CURRENT LIBRARY ONLY.
//
// v1 SAFE FORM: parent navigation (Up) + an editable destination path.
// A dynamic subfolder listing (async listing rendered inside this dialog)
// crashed the Quickshell compositor thread natively during P1 testing —
// that variant is deferred (needs a native-level spike) and the editable
// path field is the documented fallback.
//
// Confirm hands the chosen path to the existing confirmMove/confirmCopy
// execution path — this dialog never performs the operation itself.
Item {
    id: root

    property QtObject bar: null
    property string operation: "Move"        // "Move" | "Copy" — title + confirm text
    property int itemCount: 1                // >1 renders the batch count in the title
    property string initialDestination: "/"  // starting destination (current folder)
    property var onConfirm: null             // function(destPath)
    property var onCancel: null
    property alias destField: destField
    property alias errorText: errorText

    width: parent.width
    implicitHeight: column.implicitHeight
    height: implicitHeight

    // Navigation state — fresh per dialog instance (loaders recreate on open).
    property string navPath: initialDestination === "" ? "/" : initialDestination

    // True while the destination field owns keyboard focus. The panel's key
    // catcher reads this to stop interpreting typing as panel shortcuts.
    readonly property bool editing: destField.activeFocus

    // Path joins follow the canonical pattern used across Panel.qml:
    // "/"-rooted absolute paths, no duplicate separators, no relative paths.
    function joinPath(base, name) {
        return base === "/" ? "/" + name : base + "/" + name
    }

    function parentOf(path) {
        if (path === "/") return ""
        var idx = path.lastIndexOf("/")
        return idx <= 0 ? "/" : path.substring(0, idx)
    }

    function goUp() {
        var parent = parentOf(navPath)
        if (parent === "") return
        navPath = parent
        destField.text = parent
    }

    Component.onCompleted: destField.text = navPath

    Column {
        id: column
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Style.space(10)
        width: Math.min(parent.width, Style.space(400))

        Text {
            text: root.operation + (root.itemCount > 1 ? " " + root.itemCount + " items" : "")
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.display
            font.bold: true
        }

        // Current destination — always visible so the user knows what Confirm does.
        Text {
            text: root.navPath
            color: Qt.darker(root.bar.foreground, 1.4)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideMiddle
            width: parent.width
        }

        Row {
            spacing: Style.space(8)
            width: parent.width

            Button {
                id: upButton
                text: "\uf062"
                enabled: root.navPath !== "/"
                onClicked: root.goUp()
            }

            Text {
                text: "Up = parent folder · subfolder names go in the path below"
                color: Qt.darker(root.bar.foreground, 1.4)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                anchors.verticalCenter: parent.verticalCenter
                elide: Text.ElideRight
                width: parent.width - upButton.width - Style.space(8)
            }
        }

        Text {
            text: "Destination path (editable):"
            color: Qt.darker(root.bar.foreground, 1.4)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
        }

        TextField {
            id: destField
            width: parent.width
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.body
            color: root.bar.foreground
            background: Rectangle {
                color: Qt.darker(root.bar.background, 1.2)
                radius: Style.space(4)
                border.color: Qt.darker(root.bar.background, 1.4)
                border.width: 1
            }
            // Escape closes this dialog only — never the whole panel.
            Keys.onEscapePressed: function(event) {
                event.accepted = true
                if (root.onCancel) root.onCancel()
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

        // Explicit Row width AND button heights — implicit-height races left
        // the hit area offset from the visuals in earlier iterations.
        Row {
            spacing: Style.space(12)
            width: parent.width
            height: Style.space(40)

            Button {
                width: parent.width / 2 - Style.space(6)
                height: parent.height
                text: "Cancel"
                onClicked: {
                    if (root.onCancel) root.onCancel()
                }
            }

            Button {
                width: parent.width / 2 - Style.space(6)
                height: parent.height
                text: root.operation
                onClicked: {
                    if (root.onConfirm) root.onConfirm(destField.text)
                }
            }
        }
    }
}
