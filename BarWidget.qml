import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

BarWidget {
    id: root
    moduleName: "roddy.seafile"

    readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
    readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false
    readonly property int activeTransferCount: panelLoader.item ? panelLoader.item.activeTransferCount : 0
    readonly property bool hasTransferFailures: panelLoader.item ? panelLoader.item.hasTransferFailures : false

    function open() {
        if (panelLoader.item) panelLoader.item.open()
    }

    function close() {
        if (panelLoader.item) panelLoader.item.close()
    }

    function toggle() {
        if (panelLoader.item) panelLoader.item.toggle()
    }

    function closeForPopoutSwitch() {
        if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
    }

    function injectPanel() {
        if (!panelLoader.item) return
        panelLoader.item.bar = root.bar
        panelLoader.item.anchorItem = button
        panelLoader.item.hostWidget = root
    }

    implicitWidth: button.implicitWidth
    implicitHeight: button.implicitHeight

    onBarChanged: injectPanel()

    Loader {
        id: panelLoader
        active: true
        source: Qt.resolvedUrl("Panel.qml")
        visible: false
        onLoaded: {
            root.injectPanel()
            Qt.callLater(root.injectPanel)
        }
    }

    BarIconButton {
        id: button
        anchors.fill: parent
        bar: root.bar
        text: "\uf07b"
        tooltipText: "Seafile"
        onPressed: function(b) {
            if (b === Qt.LeftButton) root.toggle()
        }
    }

    Rectangle {
        id: transferBadge
        width: badgeText.implicitWidth + Style.space(6)
        height: badgeText.implicitHeight + Style.space(4)
        radius: width / 2
        color: root.hasTransferFailures ? Color.urgent : Color.accent
        visible: root.activeTransferCount > 0
        anchors.top: button.top
        anchors.right: button.right
        anchors.topMargin: -Style.space(2)
        anchors.rightMargin: -Style.space(2)
        z: 10

        Text {
            id: badgeText
            text: root.activeTransferCount
            color: Color.background
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.tiny
            font.bold: true
            anchors.centerIn: parent
        }
    }
}