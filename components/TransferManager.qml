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
                anchors.verticalCenter: parent.verticalCenter
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
                text: "Completed (" + root.completedCount + ")"
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                anchors.verticalCenter: parent.verticalCenter
            }

            Item { width: parent.width - clearCompletedBtn.width - Style.space(20); height: 1 }

            Text {
                id: clearCompletedBtn
                text: "Clear Done"
                color: Color.accent
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                anchors.verticalCenter: parent.verticalCenter
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
                text: "Failed (" + root.failedCount + ")"
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                anchors.verticalCenter: parent.verticalCenter
            }

            Item { width: parent.width - clearFailedBtn.width - Style.space(20); height: 1 }

            Text {
                id: clearFailedBtn
                text: "Clear"
                color: Color.urgent
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                anchors.verticalCenter: parent.verticalCenter
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

    // Empty state
    EmptyState {
        id: emptyState
        bar: root.bar
        icon: "\uf0ec"
        title: "No transfers"
        subtitle: "Downloads and uploads appear here"
        width: parent.width
        visible: root.activeCount === 0 && root.completedCount === 0 && root.failedCount === 0
    }
}
