import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui
import "../js"

Item {
    id: root
    required property var transfer
    required property var bar
    property var onCancel: null
    property var onRetry: null
    property var onClear: null
    property var onOpen: null
    property var onShowInFolder: null

    implicitHeight: row.implicitHeight + Style.space(8)
    height: implicitHeight
    width: parent.width

    property bool isCancelling: transfer.state === "cancelling"
    // "queued" and "validating" are active: the transfer is accepted and
    // cancellable before its first byte moves (matches TransferService).
    property bool isActive: transfer.state === "queued" || transfer.state === "validating"
        || transfer.state === "pending" || transfer.state === "downloading"
        || transfer.state === "uploading" || transfer.state === "opening" || isCancelling
    property bool isCompleted: transfer.state === "completed"
    property bool isFailed: transfer.state === "failed" || transfer.state === "cancelled" || transfer.state === "auth_failed"

    property bool isDownload: transfer.type === "download"
    property bool showOpenActions: isCompleted && isDownload

    // Human-readable label for queued/validating uploads.
    property string stateLabel: transfer.state === "queued" ? "Queued..."
        : (transfer.state === "validating" ? "Validating..." : "")

    Row {
        id: row
        width: parent.width
        spacing: Style.space(8)
        height: implicitHeight

        Text {
            id: typeIcon
            text: root.transfer.type === "download" ? Icons.download : Icons.upload
            color: root.bar.foreground
            font.family: Icons.family
            font.pixelSize: Style.font.body
            width: Style.space(20)
            horizontalAlignment: Text.AlignHCenter
            height: parent.height
            verticalAlignment: Text.AlignVCenter
        }

        Column {
            width: parent.width - typeIcon.width - statusColumn.width - Style.space(32)
            spacing: Style.space(2)

            Text {
                id: nameLabel
                text: Models.boundedDisplayText(root.transfer.fileName || "Unknown", 1024)
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.body
                elide: Text.ElideRight
                width: parent.width
                textFormat: Text.PlainText
            }

            Text {
                id: detailLabel
                text: Models.boundedDisplayText((function() {
                    if (root.isActive) {
                        if (root.isCancelling) return "Cancelling..."
                        if (root.transfer.state === "opening") return "Opening..."
                        if (root.stateLabel !== "") return root.stateLabel
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
                })(), 4096)
                color: Qt.darker(root.bar.foreground, 1.4)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
                width: parent.width
                visible: text !== ""
                textFormat: Text.PlainText
            }
        }

        Column {
            id: statusColumn
            width: Style.space(60)
            spacing: Style.space(2)

            ProgressBar {
                width: parent.width
                height: Style.space(4)
                from: 0
                to: 1
                value: root.transfer.progress
                visible: root.isActive && root.transfer.progress > 0
            }

            Text {
                id: statusIcon
                text: {
                    if (root.isActive) return ""
                    if (root.isCompleted) return Icons.check
                    if (root.transfer.state === "cancelled") return Icons.times
                    return Icons.warning
                }
                color: {
                    if (root.isCompleted) return Color.accent
                    if (root.isFailed) return Color.urgent
                    return root.bar.foreground
                }
                font.family: Icons.family
                font.pixelSize: Style.font.body
                // Full width + AlignHCenter reproduces the centring that the
                // invalid anchors.horizontalCenter (inside a Column) never did.
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                visible: !root.isActive
            }

            Row {
                spacing: Style.space(4)
                visible: root.isFailed

                Text {
                    text: Icons.refresh
                    color: root.bar.foreground
                    font.family: Icons.family
                    font.pixelSize: Style.font.caption
                    activeFocusOnTab: true
                    Accessible.role: Accessible.Button
                    Accessible.name: "Retry transfer"
                    Accessible.onPressAction: { if (root.onRetry) root.onRetry(root.transfer) }
                    ToolTip.text: "Retry transfer"
                    Keys.onReturnPressed: function(event) { if (root.onRetry) root.onRetry(root.transfer); event.accepted = true }
                    Keys.onSpacePressed: function(event) { if (root.onRetry) root.onRetry(root.transfer); event.accepted = true }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { if (root.onRetry) root.onRetry(root.transfer) }
                    }
                }

                Text {
                    text: Icons.times
                    color: Color.urgent
                    font.family: Icons.family
                    font.pixelSize: Style.font.caption
                    activeFocusOnTab: true
                    Accessible.role: Accessible.Button
                    Accessible.name: "Remove transfer from history"
                    Accessible.onPressAction: { if (root.onClear) root.onClear(root.transfer) }
                    ToolTip.text: "Remove from history"
                    Keys.onReturnPressed: function(event) { if (root.onClear) root.onClear(root.transfer); event.accepted = true }
                    Keys.onSpacePressed: function(event) { if (root.onClear) root.onClear(root.transfer); event.accepted = true }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { if (root.onClear) root.onClear(root.transfer) }
                    }
                }
            }

            Text {
                text: Icons.times
                color: Color.urgent
                font.family: Icons.family
                font.pixelSize: Style.font.caption
                activeFocusOnTab: true
                Accessible.role: Accessible.Button
                Accessible.name: "Cancel transfer"
                Accessible.onPressAction: { if (root.onCancel) root.onCancel(root.transfer) }
                ToolTip.text: "Cancel transfer"
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                visible: root.isActive && !root.isCancelling
                Keys.onReturnPressed: function(event) { if (root.onCancel) root.onCancel(root.transfer); event.accepted = true }
                Keys.onSpacePressed: function(event) { if (root.onCancel) root.onCancel(root.transfer); event.accepted = true }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { if (root.onCancel) root.onCancel(root.transfer) }
                }
            }

            Row {
                spacing: Style.space(4)
                visible: root.showOpenActions

                Text {
                    text: Icons.folderOpen
                    color: root.bar.foreground
                    font.family: Icons.family
                    font.pixelSize: Style.font.caption
                    activeFocusOnTab: true
                    Accessible.role: Accessible.Button
                    Accessible.name: "Open downloaded file"
                    Accessible.onPressAction: { if (root.onOpen) root.onOpen(root.transfer) }
                    ToolTip.text: "Open file"
                    Keys.onReturnPressed: function(event) { if (root.onOpen) root.onOpen(root.transfer); event.accepted = true }
                    Keys.onSpacePressed: function(event) { if (root.onOpen) root.onOpen(root.transfer); event.accepted = true }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { if (root.onOpen) root.onOpen(root.transfer) }
                    }
                }

                Text {
                    text: Icons.folder
                    color: root.bar.foreground
                    font.family: Icons.family
                    font.pixelSize: Style.font.caption
                    activeFocusOnTab: true
                    Accessible.role: Accessible.Button
                    Accessible.name: "Show downloaded file in folder"
                    Accessible.onPressAction: { if (root.onShowInFolder) root.onShowInFolder(root.transfer) }
                    ToolTip.text: "Show in file manager"
                    Keys.onReturnPressed: function(event) { if (root.onShowInFolder) root.onShowInFolder(root.transfer); event.accepted = true }
                    Keys.onSpacePressed: function(event) { if (root.onShowInFolder) root.onShowInFolder(root.transfer); event.accepted = true }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { if (root.onShowInFolder) root.onShowInFolder(root.transfer) }
                    }
                }
            }
        }
    }
}
