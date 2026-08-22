import QtQuick
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
    width: parent.width
    implicitHeight: row.implicitHeight

    Row {
        id: row
        anchors.fill: parent
        anchors.leftMargin: Style.space(8)
        anchors.rightMargin: Style.space(8)
        spacing: Style.space(8)

        Text {
            id: countLabel
            text: root.count + " selected"
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            anchors.verticalCenter: parent.verticalCenter
        }

        Item {
            width: Style.space(8)
            height: 1
        }

        Button {
            id: moveBtn
            text: "Move"
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
            visible: root.count > 0
            onClicked: {
                if (root.onMove) root.onMove()
            }
        }

        Button {
            id: copyBtn
            text: "Copy"
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
            visible: root.count > 0
            onClicked: {
                if (root.onCopy) root.onCopy()
            }
        }

        Button {
            id: deleteBtn
            text: "Delete"
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
            color: Color.urgent
            visible: root.count > 0
            onClicked: {
                if (root.onDelete) root.onDelete()
            }
        }

        Button {
            id: clearBtn
            text: "Clear"
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
            visible: root.count > 0
            onClicked: {
                if (root.onClear) root.onClear()
            }
        }
    }
}