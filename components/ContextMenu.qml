import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui

Popup {
    id: root

    property var item: null
    property bool isDir: false
    property int selectionCount: 1
    property bool libraryMode: false
    property bool isFavorite: false
    property QtObject bar: null
    property int focusedActionIndex: -1

    signal openClicked(var item)
    signal downloadClicked(var item)
    signal renameClicked(var item)
    signal moveClicked(var item)
    signal copyClicked(var item)
    signal deleteClicked(var item)
    signal shareClicked(var item)
    signal historyClicked(var item)
    signal addToFavoritesClicked(var item)
    signal removeFromFavoritesClicked(var item)

    readonly property bool batchMode: selectionCount > 1

    function actionButtons() {
        return [openFileButton, openFolderButton, downloadButton, shareButton,
            renameButton, moveButton, copyButton, historyButton, favoritesButton, deleteButton]
    }

    function focusFirstAction() {
        var buttons = root.actionButtons()
        for (var i = 0; i < buttons.length; i++) {
            if (buttons[i].visible && buttons[i].enabled) {
                root.focusedActionIndex = i
                buttons[i].forceActiveFocus()
                return
            }
        }
    }

    function moveActionFocus(direction) {
        var buttons = root.actionButtons()
        for (var step = 1; step <= buttons.length; step++) {
            var index = (root.focusedActionIndex + direction * step + buttons.length * 2) % buttons.length
            if (buttons[index].visible && buttons[index].enabled) {
                root.focusedActionIndex = index
                buttons[index].forceActiveFocus()
                return
            }
        }
    }

    function activateFocusedAction() {
        var buttons = root.actionButtons()
        var button = buttons[root.focusedActionIndex]
        if (button && button.visible && button.enabled) button.clicked()
    }

    width: Style.space(180)
    implicitHeight: column.implicitHeight + topPadding + bottomPadding
    padding: Style.space(4)
    focus: true
    modal: true
    dim: false
    closePolicy: Popup.CloseOnPressOutside
    onOpened: Qt.callLater(root.focusFirstAction)

    Column {
        id: column
        width: parent.width
        spacing: Style.space(2)

        Item {
            width: 0
            height: 0
            Shortcut {
                sequence: "Escape"
                context: Qt.ApplicationShortcut
                enabled: root.opened
                onActivated: root.close()
            }
            Shortcut {
                sequence: "Up"
                context: Qt.ApplicationShortcut
                enabled: root.opened
                onActivated: root.moveActionFocus(-1)
            }
            Shortcut {
                sequence: "Down"
                context: Qt.ApplicationShortcut
                enabled: root.opened
                onActivated: root.moveActionFocus(1)
            }
            Shortcut {
                sequence: "Shift+Tab"
                context: Qt.ApplicationShortcut
                enabled: root.opened
                onActivated: root.moveActionFocus(-1)
            }
            Shortcut {
                sequence: "Tab"
                context: Qt.ApplicationShortcut
                enabled: root.opened
                onActivated: root.moveActionFocus(1)
            }
            Shortcut {
                sequence: "Return"
                context: Qt.ApplicationShortcut
                enabled: root.opened
                onActivated: root.activateFocusedAction()
            }
            Shortcut {
                sequence: "Space"
                context: Qt.ApplicationShortcut
                enabled: root.opened
                onActivated: root.activateFocusedAction()
            }
        }

        Button {
            id: openFileButton
            width: parent.width
            text: "Open"
            visible: !root.libraryMode && !root.batchMode && !root.isDir
            onClicked: {
                root.openClicked(root.item)
                root.close()
            }
        }

        Button {
            id: openFolderButton
            width: parent.width
            text: "Open"
            visible: !root.batchMode && (root.libraryMode || root.isDir)
            onClicked: {
                root.openClicked(root.item)
                root.close()
            }
        }

        Button {
            id: downloadButton
            width: parent.width
            text: "Download"
            visible: !root.libraryMode && !root.batchMode && !root.isDir
            onClicked: {
                root.downloadClicked(root.item)
                root.close()
            }
        }

        Button {
            id: shareButton
            width: parent.width
            text: "Share"
            visible: !root.libraryMode && !root.batchMode
            onClicked: {
                root.shareClicked(root.item)
                root.close()
            }
        }

        Rectangle {
            width: parent.width
            height: visible ? Style.spacing.hairline : 0
            color: root.bar ? root.bar.foreground : Color.foreground
            opacity: 0.14
            visible: !root.libraryMode && !root.batchMode
        }

        Button {
            id: renameButton
            width: parent.width
            text: "Rename"
            visible: !root.libraryMode && !root.batchMode
            onClicked: {
                root.renameClicked(root.item)
                root.close()
            }
        }

        Button {
            id: moveButton
            width: parent.width
            text: root.batchMode ? "Move " + root.selectionCount + " items" : "Move"
            visible: !root.libraryMode
            onClicked: {
                root.moveClicked(root.item)
                root.close()
            }
        }

        Button {
            id: copyButton
            width: parent.width
            text: root.batchMode ? "Copy " + root.selectionCount + " items" : "Copy"
            visible: !root.libraryMode
            onClicked: {
                root.copyClicked(root.item)
                root.close()
            }
        }

        Rectangle {
            width: parent.width
            height: visible ? Style.spacing.hairline : 0
            color: root.bar ? root.bar.foreground : Color.foreground
            opacity: 0.14
            visible: !root.libraryMode && !root.batchMode
        }

        Button {
            id: historyButton
            width: parent.width
            text: "History"
            visible: !root.libraryMode && !root.batchMode && !root.isDir
            onClicked: {
                root.historyClicked(root.item)
                root.close()
            }
        }

        Button {
            id: favoritesButton
            width: parent.width
            text: root.isFavorite ? "Remove from Quick Access" : "Add to Quick Access"
            // Quick Access targets are libraries and folders only in v1.1.
            // At the Libraries root (libraryMode) the item is a library, so the
            // action is available there too; for files it is hidden rather than
            // offering a no-op. Batch selections do not support Quick Access.
            visible: !root.batchMode && (root.isDir || root.isFavorite || root.libraryMode)
            onClicked: {
                if (root.isFavorite) {
                    root.removeFromFavoritesClicked(root.item)
                } else {
                    root.addToFavoritesClicked(root.item)
                }
                root.close()
            }
        }

        Rectangle {
            width: parent.width
            height: visible ? Style.spacing.hairline : 0
            color: root.bar ? root.bar.foreground : Color.foreground
            opacity: 0.14
            visible: !root.libraryMode
        }

        Button {
            id: deleteButton
            width: parent.width
            text: "Delete"
            color: Color.urgent
            visible: !root.libraryMode
            onClicked: {
                root.deleteClicked(root.item)
                root.close()
            }
        }
    }

    Rectangle {
        z: 1
        x: column.x
        y: root.focusedActionIndex >= 0 ? root.actionButtons()[root.focusedActionIndex].y : 0
        width: column.width
        height: root.focusedActionIndex >= 0 ? root.actionButtons()[root.focusedActionIndex].height : 0
        color: "transparent"
        border.color: Color.accent
        border.width: Style.spacing.hairline
        radius: Style.cornerRadius
        visible: root.opened && root.focusedActionIndex >= 0
            && root.actionButtons()[root.focusedActionIndex].visible
        enabled: false
    }
}
