import QtQuick
import qs.Commons
import qs.Ui
import "Models.js" as Models

ListView {
    id: root
    required property var results
    required property var onResultClicked
    required property var onResultRightClicked
    required property QtObject bar

    width: parent.width
    height: parent.height
    clip: true
    spacing: Style.space(2)

    model: root.results

    delegate: Item {
        id: delegate
        required property var modelData
        property bool isDir: modelData.type === "folder"
        property string repoName: modelData.repoName || ""

        implicitHeight: row.implicitHeight
        width: parent.width

        Row {
            id: row
            anchors.fill: parent
            anchors.leftMargin: Style.space(12)
            anchors.rightMargin: Style.space(12)
            spacing: Style.space(12)

            Text {
                id: icon
                text: delegate.isDir ? "\uf07b" : "\uf15b"
                color: delegate.bar.foreground
                font.family: "Noto Sans"
                font.pixelSize: Style.font.title
                width: Style.space(24)
                horizontalAlignment: Text.AlignHCenter
                anchors.verticalCenter: parent.verticalCenter
            }

            Column {
                width: parent.width - icon.width - sizeLabel.width - Style.space(36)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(2)

                Text {
                    id: nameLabel
                    text: delegate.modelData.name
                    color: delegate.bar.foreground
                    font.family: delegate.bar.fontFamily
                    font.pixelSize: Style.font.body
                    elide: Text.ElideRight
                    width: parent.width
                }

                Text {
                    id: pathLabel
                    text: delegate.repoName + " \u2022 " + delegate.modelData.parentPath
                    color: Qt.darker(delegate.bar.foreground, 1.4)
                    font.family: delegate.bar.fontFamily
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                    width: parent.width
                    visible: text !== " \u2022 "
                }
            }

            Text {
                id: sizeLabel
                text: delegate.isDir ? "" : Models.formatSize(delegate.modelData.size)
                color: Qt.darker(delegate.bar.foreground, 1.4)
                font.family: delegate.bar.fontFamily
                font.pixelSize: Style.font.caption
                width: Style.space(80)
                horizontalAlignment: Text.AlignRight
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: {
                if (mouse.button === Qt.LeftButton) {
                    if (root.onResultClicked) root.onResultClicked(delegate.modelData)
                } else if (mouse.button === Qt.RightButton) {
                    if (root.onResultRightClicked) root.onResultRightClicked(delegate.modelData, mouse)
                }
            }
        }
    }

    ScrollBar.vertical: ScrollBar {
        policy: ScrollBar.AsNeeded
    }
}
