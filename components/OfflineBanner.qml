import QtQuick
import qs.Commons
import qs.Ui
import "../js"

Item {
    id: root
    property string message: "Offline"
    property QtObject bar: null

    implicitHeight: banner.implicitHeight
    width: parent.width
    height: visible ? implicitHeight : 0

    Rectangle {
        id: banner
        width: parent.width
        color: Color.urgent
        implicitHeight: text.implicitHeight + Style.space(16)

        Text {
            id: text
            text: Models.boundedDisplayText(root.message, 4096)
            color: Color.background
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.body
            font.bold: true
            anchors.centerIn: parent
            wrapMode: Text.WordWrap
            width: parent.width - Style.space(24)
            textFormat: Text.PlainText
        }
    }
}