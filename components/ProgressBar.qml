import QtQuick
import qs.Commons
import qs.Ui

Item {
    id: root
    property int from: 0
    property int to: 1
    property real value: 0
    property color foreground: root.bar ? root.bar.foreground : Color.foreground
    property color background: Util.alpha(root.foreground, 0.15)
    property int radius: Style.space(3)

    implicitWidth: Style.space(120)
    implicitHeight: Style.space(6)

    Rectangle {
        anchors.fill: parent
        color: root.background
        radius: root.radius
    }

    Rectangle {
        id: progressRect
        width: parent.width * root.value
        height: parent.height
        color: root.foreground
        radius: root.radius
        Behavior on width {
            NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
        }
    }
}