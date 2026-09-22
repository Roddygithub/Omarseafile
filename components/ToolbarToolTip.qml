import QtQuick
import qs.Commons
import qs.Ui

PanelToolTip {
    id: root

    required property Item target
    property var overlay: null
    readonly property real edgeMargin: Style.space(4)

    parent: root.overlay

    function reposition() {
        if (!root.overlay || !root.target) return
        var point = root.target.mapToItem(root.overlay, 0, 0)
        var maxX = Math.max(root.edgeMargin, root.overlay.width - root.implicitWidth - root.edgeMargin)
        var centeredX = point.x + (root.target.width - root.implicitWidth) / 2
        root.x = Math.max(root.edgeMargin, Math.min(centeredX, maxX))

        var below = point.y + root.target.height + root.edgeMargin
        var above = point.y - root.implicitHeight - root.edgeMargin
        root.y = below + root.implicitHeight <= root.overlay.height - root.edgeMargin
            ? below
            : Math.max(root.edgeMargin, above)
    }

    onOpened: root.reposition()
    onImplicitWidthChanged: if (root.opened) root.reposition()
    onImplicitHeightChanged: if (root.opened) root.reposition()
}
