import QtQuick
import qs.Commons
import qs.Ui

Item {
    id: root
    property string message: "Loading..."
    property bool indeterminate: true
    property real progress: 0
    property QtObject bar: null

    implicitWidth: parent.width
    implicitHeight: column.implicitHeight
    height: visible ? implicitHeight : 0

    Column {
        id: column
        anchors.centerIn: parent
        spacing: Style.space(12)

        Text {
            id: spinner
            text: "\uf110"
            color: root.bar.foreground
            font.family: "Noto Sans"
            font.pixelSize: Style.font.title
            visible: root.indeterminate
            RotationAnimator on rotation {
                from: 0; to: 360
                duration: 1000
                loops: Animation.Infinite
                running: root.indeterminate
            }
        }

        Rectangle {
            width: parent.width
            height: Style.space(4)
            radius: Style.space(2)
            color: Qt.darker(root.bar.foreground, 1.3)
            visible: !root.indeterminate

            Rectangle {
                width: parent.width * root.progress
                height: parent.height
                radius: parent.radius
                color: root.bar.foreground
            }
        }

        Text {
            text: root.message
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.body
            textFormat: Text.PlainText
        }
    }
}
