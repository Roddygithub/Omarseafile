import QtQuick
import qs.Commons
import qs.Ui
import "../js"

Item {
    id: root
    property var path: []
    property var onSegmentClicked: null
    property QtObject bar: null

    implicitHeight: row.implicitHeight
    width: parent.width

    Row {
        id: row
        spacing: Style.space(6)
        height: Style.font.body + Style.space(8)

        Repeater {
            model: root.path
            delegate: Item {
                width: segmentLabel.implicitWidth + (index < root.path.length - 1 ? separator.implicitWidth : 0)
                height: row.height

                Text {
                    id: segmentLabel
                    text: Models.boundedDisplayText(modelData.name, 1024)
                    color: index === root.path.length - 1 ? root.bar.foreground : Qt.darker(root.bar.foreground, 1.4)
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.body
                    font.bold: index === root.path.length - 1
                    elide: Text.ElideRight
                    width: parent.width - (index < root.path.length - 1 ? separator.implicitWidth : 0)
                    anchors.verticalCenter: parent.verticalCenter
                    textFormat: Text.PlainText

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (root.onSegmentClicked) root.onSegmentClicked(index)
                        }
                    }
                }

                Text {
                    id: separator
                    text: " / "
                    color: Qt.darker(root.bar.foreground, 1.6)
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.body
                    visible: index < root.path.length - 1
                    anchors.left: segmentLabel.right
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }
    }
}