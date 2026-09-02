import QtQuick
import qs.Commons
import qs.Ui

Item {
    id: root
    property string message: "An error occurred"
    property bool showError: false
    property var onRetry: null
    property QtObject bar: null

    width: parent.width
    height: showError ? column.implicitHeight + Style.space(40) : 0

    Rectangle {
        anchors.fill: parent
        color: Util.alpha(Color.background, 0.85)
    }

    Column {
        id: column
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
            textFormat: Text.PlainText
        }

        Button {
            text: "Retry"
            onClicked: {
                root.visible = false
                if (root.onRetry) root.onRetry()
            }
        }
    }
}