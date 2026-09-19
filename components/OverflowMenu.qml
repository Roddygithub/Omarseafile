import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui
import "../js"

// Custom Omarseafile-styled overflow menu. Uses a Popup (not native
// QtQuick.Controls.Menu) to avoid native grey styling and fragile Menu
// internal overrides. Geometry is explicit and deterministic.
Popup {
    id: popup

    // Reused from ToolBar: action availability + click handlers.
    property QtObject bar: null
    property bool showCreateFolder: false
    property bool showRefresh: false
    property bool showTransfers: false
    property bool showTrash: false
    property bool showSettings: false
    property bool showLogout: false
    property int selectionCount: 0
    property bool searchActive: false

    property var onCreateFolderClicked: null
    property var onRefreshClicked: null
    property var onTransfersClicked: null
    property var onTrashClicked: null
    property var onSettingsClicked: null
    property var onLogoutClicked: null

    // Keyboard focus index into actions.
    property int currentIndex: 0
    readonly property int itemHeight: Style.space(28)
    readonly property int itemCount: popup.actions.length

    // Build the visible action list preserving the original enabled/visible logic.
    property var actions: {
        var out = []
        if (popup.showCreateFolder && !popup.searchActive && popup.selectionCount === 0)
            out.push({ label: "New folder", urgent: false, action: popup.onCreateFolderClicked })
        if (popup.showRefresh && !popup.searchActive && popup.selectionCount === 0)
            out.push({ label: "Refresh", urgent: false, action: popup.onRefreshClicked })
        if (popup.showTransfers && popup.selectionCount === 0)
            out.push({ label: "Transfers", urgent: false, action: popup.onTransfersClicked })
        if (popup.showTrash && popup.selectionCount === 0)
            out.push({ label: "Trash", urgent: false, action: popup.onTrashClicked })
        if (popup.showSettings && popup.selectionCount === 0)
            out.push({ label: "Settings", urgent: false, action: popup.onSettingsClicked })
        if (popup.showLogout && popup.selectionCount === 0)
            out.push({ label: "Logout", urgent: true, action: popup.onLogoutClicked })
        return out
    }

    function triggerItem(idx) {
        var action = idx >= 0 && idx < popup.actions.length ? popup.actions[idx].action : null
        popup.close()
        if (action) action()
    }

    // Deterministic geometry — never depends on native Menu sizing.
    readonly property int longestLabelWidth: {
        var w = 0
        for (var i = 0; i < popup.actions.length; i++) {
            var l = popup.actions[i].label
            w = Math.max(w, l.length * Style.font.body)
        }
        return w
    }
    readonly property int menuWidth: Math.max(Style.space(150), longestLabelWidth + Style.space(28))
    readonly property int menuHeight: popup.itemCount * popup.itemHeight + Style.space(8)

    implicitWidth: popup.menuWidth
    implicitHeight: popup.menuHeight
    width: popup.menuWidth
    height: popup.menuHeight

    padding: Style.space(4)
    modal: true
    focus: true
    dim: false
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    background: Rectangle {
        color: Qt.darker(popup.bar ? popup.bar.background : Color.background, 1.1)
        border.color: Color.accent
        border.width: Style.spacing.hairline
        radius: Style.cornerRadius
    }

    contentItem: Item {
        width: popup.width
        height: popup.height

        Column {
            id: actionColumn
            width: parent.width
            spacing: 0

            Repeater {
                model: popup.actions
                delegate: Rectangle {
                    required property var modelData
                    required property int index
                    width: actionColumn.width
                    height: popup.itemHeight
                    color: index === popup.currentIndex
                        ? Qt.darker(popup.bar ? popup.bar.background : Color.background, 1.3)
                        : "transparent"

                    Text {
                        text: Models.boundedDisplayText(modelData.label, 1024)
                        anchors.left: parent.left
                        anchors.leftMargin: Style.space(10)
                        anchors.verticalCenter: parent.verticalCenter
                        color: modelData.urgent ? Color.urgent : (popup.bar ? popup.bar.foreground : Color.foreground)
                        font.family: popup.bar ? popup.bar.fontFamily : Style.font.family
                        font.pixelSize: Style.font.body
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        onEntered: popup.currentIndex = index
                        onClicked: popup.triggerItem(index)
                    }
                }
            }
        }

        focus: true
        Keys.onPressed: (event) => {
            if (event.key === Qt.Key_Down) {
                popup.currentIndex = (popup.currentIndex + 1) % Math.max(1, popup.itemCount)
                event.accepted = true
            } else if (event.key === Qt.Key_Up) {
                popup.currentIndex = (popup.currentIndex - 1 + Math.max(1, popup.itemCount)) % Math.max(1, popup.itemCount)
                event.accepted = true
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                popup.triggerItem(popup.currentIndex)
                event.accepted = true
            }
        }
    }

    onOpened: popup.currentIndex = 0
}