import QtQuick
import qs.Commons
import qs.Ui

Item {
    id: root
    property QtObject bar: null
    property alias nameField: nameField
    property alias createButton: createButton
    property alias cancelButton: cancelButton
    property alias errorText: errorText
    property var onCreate: null
    property var onCancel: null

    width: parent.width
    implicitHeight: column.implicitHeight
    height: implicitHeight

    // True while the folder-name field owns keyboard focus. The panel's key
    // catcher reads this to stop interpreting typing as panel shortcuts.
    readonly property bool editing: nameField.activeFocus

    Component.onCompleted: nameField.forceActiveFocus()

    Column {
        id: column
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Style.space(16)
        width: Math.min(parent.width, Style.space(400))

        Text {
            text: "Create Folder"
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.display
            font.bold: true
        }

        Text {
            text: "Enter the name for the new folder"
            color: Qt.darker(root.bar.foreground, 1.4)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.body
            wrapMode: Text.WordWrap
            width: parent.width
        }

        TextField {
            id: nameField
            width: parent.width
            placeholderText: "Folder name"
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.body
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
                id: createButton
                width: parent.width / 2 - Style.space(6)
                text: "Create"
                onClicked: {
                    if (root.onCreate) root.onCreate()
                }
            }
        }
    }
}
