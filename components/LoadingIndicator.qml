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

    Column {
        id: column
        anchors.centerIn: parent
        spacing: Style.space(12)

        BusyIndicator {
            running: root.indeterminate
        }

        Text {
            text: root.message
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.body
        }
    }
}