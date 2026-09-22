import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui

Item {
    id: root
    required property var bar
    required property int count
    property var onMove: null
    property var onCopy: null
    property var onDelete: null
    property var onClear: null

    visible: root.count > 0
    // Size to content: this bar lives inside the ToolBar Row, so binding
    // width to parent.width would swallow the whole card width and push
    // every sibling button off-card.
    implicitWidth: row.implicitWidth + Style.space(16)
    implicitHeight: row.implicitHeight
    width: implicitWidth

    Row {
        id: row
        spacing: Style.space(8)

        Text {
            id: countLabel
            text: root.count + " selected"
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            height: parent.height
            verticalAlignment: Text.AlignVCenter
            textFormat: Text.PlainText
        }

        Item {
            width: Style.space(8)
            height: 1
        }

        Button {
            id: moveBtn
            text: "Move"
            visible: root.count > 0
            onClicked: {
                if (root.onMove) root.onMove()
            }
        }

        Button {
            id: deleteBtn
            text: "Delete"
            color: Color.urgent
            visible: root.count > 0
            onClicked: {
                if (root.onDelete) root.onDelete()
            }
        }

        Button {
            id: moreBtn
            text: "More"
            visible: root.count > 0
            onClicked: moreMenu.open()
        }

        Button {
            id: clearBtn
            text: "Clear"
            visible: root.count > 0
            onClicked: {
                if (root.onClear) root.onClear()
            }
        }
    }

    Popup {
        id: moreMenu
        width: Style.space(140)
        padding: Style.space(4)
        x: moreBtn.x + moreBtn.width - width
        y: moreBtn.y + moreBtn.height + Style.space(2)
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        background: Rectangle {
            color: Qt.darker(root.bar.background, 1.1)
            border.color: Color.accent
            border.width: Style.spacing.hairline
            radius: Style.cornerRadius
        }

        Column {
            width: parent.width
            spacing: Style.space(2)

            Button {
                width: parent.width
                text: "Copy"
                onClicked: {
                    moreMenu.close()
                    if (root.onCopy) root.onCopy()
                }
            }
        }
    }
}