import QtQuick
import qs.Commons
import qs.Ui

Item {
    id: root
    required property var transfer
    required property var bar
    property var onCancel: null
    property var onRetry: null
    property var onClear: null

    implicitHeight: row.implicitHeight + Style.space(8)
    width: parent.width

    property bool isActive: transfer.state === "pending" || transfer.state === "downloading" || transfer.state === "uploading"
    property bool isCompleted: transfer.state === "completed"
    property bool isFailed: transfer.state === "failed" || transfer.state === "cancelled" || transfer.state === "auth_failed"

    Row {
        id: row
        anchors.fill: parent
        anchors.leftMargin: Style.space(8)
        anchors.rightMargin: Style.space(8)
        spacing: Style.space(8)

        Text {
            id: typeIcon
            text: root.transfer.type === "download" ? "\uf019" : "\uf093"
            color: root.bar.foreground
            font.family: "Noto Sans"
            font.pixelSize: Style.font.body
            width: Style.space(20)
            horizontalAlignment: Text.AlignHCenter
            anchors.verticalCenter: parent.verticalCenter
        }

        Column {
            width: parent.width - typeIcon.width - statusColumn.width - Style.space(32)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
                id: nameLabel
                text: root.transfer.fileName || "Unknown"
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.body
                elide: Text.ElideRight
                width: parent.width
            }

            Text {
                id: detailLabel
                text: {
                    if (root.isActive) {
                        var parts = []
                        if (root.transfer.progress > 0) parts.push(Math.round(root.transfer.progress * 100) + "%")
                        if (root.transfer.speed) parts.push(root.transfer.speed)
                        return parts.join(" - ") || "Starting..."
                    } else if (root.isCompleted) {
                        return "Completed"
                    } else if (root.isFailed) {
                        return root.transfer.error || "Failed"
                    }
                    return ""
                }
                color: Qt.darker(root.bar.foreground, 1.4)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
                width: parent.width
                visible: text !== ""
            }
        }

        Column {
            id: statusColumn
            width: Style.space(60)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            ProgressBar {
                width: parent.width
                height: Style.space(4)
                from: 0
                to: 1
                value: root.transfer.progress
                visible: root.isActive && root.transfer.progress > 0
                bar: root.bar
            }

            Text {
                id: statusIcon
                text: {
                    if (root.isActive) return ""
                    if (root.isCompleted) return "\uf00c"
                    if (root.transfer.state === "cancelled") return "\uf00d"
                    return "\uf06a"
                }
                color: {
                    if (root.isCompleted) return Color.accent
                    if (root.isFailed) return Color.urgent
                    return root.bar.foreground
                }
                font.family: "Noto Sans"
                font.pixelSize: Style.font.body
                horizontalAlignment: Text.AlignHCenter
                anchors.horizontalCenter: parent.horizontalCenter
                visible: !root.isActive
            }

            Row {
                spacing: Style.space(4)
                anchors.horizontalCenter: parent.horizontalCenter
                visible: root.isFailed

                Text {
                    text: "\uf021"
                    color: root.bar.foreground
                    font.family: "Noto Sans"
                    font.pixelSize: Style.font.caption
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { if (root.onRetry) root.onRetry(root.transfer) }
                    }
                }

                Text {
                    text: "\uf00d"
                    color: Color.urgent
                    font.family: "Noto Sans"
                    font.pixelSize: Style.font.caption
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { if (root.onClear) root.onClear(root.transfer) }
                    }
                }
            }

            Text {
                text: "\uf00d"
                color: Color.urgent
                font.family: "Noto Sans"
                font.pixelSize: Style.font.caption
                horizontalAlignment: Text.AlignHCenter
                anchors.horizontalCenter: parent.horizontalCenter
                visible: root.isActive
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { if (root.onCancel) root.onCancel(root.transfer) }
                }
            }
        }
    }
}
