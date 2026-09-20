import QtQuick
import qs.Commons
import qs.Ui
import "../js"

Column {
    id: root
    required property var bar
    property var onCancel: null
    property var onRetry: null
    property var onClearCompleted: null
    property var onClearFailed: null
    property var onRetryAllFailed: null
    property var onClearAllCompleted: null
    property var onClearAllFailed: null
    property var onOpen: null
    property var onShowInFolder: null
    property int activeCount: 0
    property int completedCount: 0
    property int failedCount: 0
    property var activeTransfers: []
    property var completedTransfers: []
    property var failedTransfers: []
    property int transferRevision: 0

    width: parent.width
    spacing: 0

    onTransferRevisionChanged: refresh()

    Component.onCompleted: refresh()

    function refresh() {
        var service = null
        try { service = TransferService } catch(e) { return }
        if (!service) return

        root.activeTransfers = service.getActiveTransfers()
        root.completedTransfers = service.getCompletedTransfers()
        root.failedTransfers = service.getFailedTransfers()
        root.activeCount = root.activeTransfers.length
        root.completedCount = root.completedTransfers.length
        root.failedCount = root.failedTransfers.length
    }

    Connections {
        target: TransferService
        function onTransfersChanged() { root.refresh() }
    }

    // Header with summary
    Item {
        width: parent.width
        height: Style.space(32)
        visible: root.activeCount > 0 || root.completedCount > 0 || root.failedCount > 0

        Row {
            spacing: Style.space(8)

            Text {
                text: "Transfers"
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                height: parent.height
                verticalAlignment: Text.AlignVCenter
            }

            Text {
                text: "(" + (root.activeCount + root.completedCount + root.failedCount) + ")"
                color: Qt.darker(root.bar.foreground, 1.4)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                height: parent.height
                verticalAlignment: Text.AlignVCenter
            }
        }
    }

    // Active section
    Column {
        width: parent.width
        visible: root.activeCount > 0
        spacing: Style.space(4)

        Row {
            width: parent.width
            height: Style.space(28)
            leftPadding: Style.space(8)

            Text {
                text: "Active (" + root.activeCount + ")"
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                height: parent.height
                verticalAlignment: Text.AlignVCenter
                textFormat: Text.PlainText
            }
        }

        Repeater {
            model: root.activeTransfers
            delegate: TransferItem {
                required property var modelData
                width: root.width
                bar: root.bar
                transfer: modelData
                onCancel: root.onCancel
            }
        }
    }

    // Completed section
    Column {
        width: parent.width
        visible: root.completedCount > 0
        spacing: Style.space(4)

        Row {
            width: parent.width
            height: Style.space(28)

            Text {
                id: completedLabel
                text: "Completed (" + root.completedCount + ")"
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                height: parent.height
                verticalAlignment: Text.AlignVCenter
                textFormat: Text.PlainText
            }

            Item { width: parent.width - completedLabel.width - clearCompletedBtn.width - Style.space(8); height: 1 }

            Text {
                id: clearCompletedBtn
                text: "Clear Done"
                color: Color.accent
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                height: parent.height
                verticalAlignment: Text.AlignVCenter
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { if (root.onClearCompleted) root.onClearCompleted() }
                }
            }
        }

        Repeater {
            model: root.completedTransfers
            delegate: TransferItem {
                required property var modelData
                width: root.width
                bar: root.bar
                transfer: modelData
                onClear: root.onClearCompleted
                onOpen: root.onOpen
                onShowInFolder: root.onShowInFolder
            }
        }
    }

    // Failed section
    Column {
        width: parent.width
        visible: root.failedCount > 0
        spacing: Style.space(4)

        Row {
            width: parent.width
            height: Style.space(28)

            Text {
                id: failedLabel
                text: "Failed (" + root.failedCount + ")"
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                height: parent.height
                verticalAlignment: Text.AlignVCenter
                textFormat: Text.PlainText
            }

            Item { width: parent.width - failedLabel.width - clearFailedBtn.width - Style.space(8); height: 1 }

            Text {
                id: clearFailedBtn
                text: "Clear"
                color: Color.urgent
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                height: parent.height
                verticalAlignment: Text.AlignVCenter
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { if (root.onClearFailed) root.onClearFailed() }
                }
            }
        }

        Repeater {
            model: root.failedTransfers
            delegate: TransferItem {
                required property var modelData
                width: root.width
                bar: root.bar
                transfer: modelData
                onRetry: root.onRetry
                onClear: root.onClearFailed
            }
        }
    }

    // Batch actions bar (visible when there are failed or completed transfers)
    Column {
        width: parent.width
        visible: root.completedCount > 0 || root.failedCount > 0
        spacing: Style.space(4)

        Row {
            width: parent.width
            spacing: Style.space(8)

            Button {
                text: "Retry All Failed"
                width: parent.width / 3 - Style.space(5)
                height: Style.space(28)
                visible: root.failedCount > 0
                onClicked: {
                    if (root.onRetryAllFailed) root.onRetryAllFailed()
                }
            }

            Button {
                text: "Clear All Done"
                width: parent.width / 3 - Style.space(5)
                height: Style.space(28)
                visible: root.completedCount > 0
                onClicked: {
                    if (root.onClearAllCompleted) root.onClearAllCompleted()
                }
            }

            Button {
                text: "Clear All Failed"
                width: parent.width / 3 - Style.space(5)
                height: Style.space(28)
                color: Color.urgent
                visible: root.failedCount > 0
                onClicked: {
                    if (root.onClearAllFailed) root.onClearAllFailed()
                }
            }
        }
    }

    // Empty state
    EmptyState {
        id: emptyState
        bar: root.bar
        icon: Icons.exchange
        title: "No transfers"
        subtitle: "Downloads and uploads appear here"
        width: parent.width
        visible: root.activeCount === 0 && root.completedCount === 0 && root.failedCount === 0
    }
}