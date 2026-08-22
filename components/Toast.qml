import QtQuick
import qs.Commons
import qs.Ui

Item {
    id: root
    property string message: ""
    property string type: "success"
    property int duration: 3000
    property QtObject bar: null

    implicitHeight: banner.implicitHeight
    width: parent.width
    visible: false

    function show(msg, msgType) {
        root.message = msg
        root.type = msgType || "success"
        root.visible = true
        dismissTimer.restart()
    }

    Timer {
        id: dismissTimer
        interval: root.duration
        onTriggered: root.visible = false
    }

    Rectangle {
        id: banner
        width: parent.width
        color: {
            switch (root.type) {
            case "error": return Color.urgent
            case "warning": return Color.accent
            case "info": return Color.accent
            default: return Color.accent
            }
        }
        implicitHeight: text.implicitHeight + Style.space(16)

        Text {
            id: text
            text: root.message
            color: Color.background
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.body
            font.bold: true
            anchors.centerIn: parent
            wrapMode: Text.WordWrap
            width: parent.width - Style.space(24)
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: {
            dismissTimer.stop()
            root.visible = false
        }
    }
}
