import QtQuick
import qs.Commons
import qs.Ui

Item {
    id: root
    property string message: "An error occurred"
    property bool visible: false

    width: parent.width
    height: parent.height

    visible: root.visible

    Rectangle {
        anchors.fill: parent
        color: Util.alpha(Color.background, 0.85)
    }

    Column {
        anchors.centerIn: parent
        spacing: Style.space(16)

        Text {
            text: root.message
            color: Color.urgent
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.body
            wrapMode: Text.WordWrap
            width: Math.min(parent.width, Style.space(340))
            horizontalAlignment: Text.AlignHCenter
        }

        Button {
            text: "Retry"
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            onClicked: {
                root.visible = false
                if (root.onRetry) root.onRetry()
            }
        }
    }
}