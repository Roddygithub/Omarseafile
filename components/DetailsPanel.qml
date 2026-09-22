import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui
import "../js"

Item {
    id: root
    required property QtObject bar
    required property var selectedItems
    required property var currentRepo
    required property string currentPath
    required property var onDownload
    required property var onOpen
    required property var onShare
    required property var onHistory
    required property var onRename
    required property var onMove
    required property var onDelete
    required property var onItemClicked

    width: parent.width
    implicitHeight: detailsContainer.implicitHeight

    property var item: root.selectedItems.length > 0 ? root.selectedItems[0] : null
    property bool isSingleSelection: root.selectedItems.length === 1
    property bool isMultiSelection: root.selectedItems.length > 1

    Rectangle {
        id: detailsContainer
        width: parent.width
        color: Qt.darker(root.bar.background, 1.1)
        border.color: Qt.darker(root.bar.background, 1.3)
        border.width: Style.spacing.hairline
        radius: Style.cornerRadius
        anchors.margins: Style.space(8)

        Column {
            id: detailsColumn
            width: parent.width
            spacing: 0

            // Header
            Item {
                width: parent.width
                height: Style.space(32)

                Text {
                    text: root.isMultiSelection ? (root.selectedItems.length + " items selected") : (root.item ? (root.item.type === "dir" ? "Folder" : "File") : "")
                    color: root.bar.foreground
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                    anchors.left: parent.left
                    anchors.leftMargin: Style.space(12)
                    anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                    text: root.isSingleSelection && root.item ? Models.formatSize(root.item.size || 0) : (root.selectedItems.length + " items")
                    color: Qt.darker(root.bar.foreground, 1.4)
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.caption
                    anchors.right: parent.right
                    anchors.rightMargin: Style.space(12)
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            // Details for single selection
            Column {
                id: singleDetails
                width: parent.width
                spacing: Style.space(4)
                visible: root.isSingleSelection && root.item !== null

                // Name
                Item {
                    width: parent.width
                    height: Math.max(labelText.implicitHeight, valueText.implicitHeight) + Style.space(4)
                    anchors.leftMargin: Style.space(8)
                    anchors.rightMargin: Style.space(8)

                    Text {
                        id: labelText
                        text: "Name:"
                        color: Qt.darker(root.bar.foreground, 1.4)
                        font.family: root.bar.fontFamily
                        font.pixelSize: Style.font.caption
                        anchors.left: parent.left
                        anchors.top: parent.top
                        textFormat: Text.PlainText
                    }

                    Text {
                        id: valueText
                        text: root.item ? Models.boundedDisplayText(root.item.name, 1024) : ""
                        color: root.bar.foreground
                        font.family: root.bar.fontFamily
                        font.pixelSize: Style.font.caption
                        font.bold: true
                        anchors.left: labelText.right
                        anchors.leftMargin: Style.space(8)
                        anchors.top: parent.top
                        elide: Text.ElideRight
                        width: parent.width - labelText.width - Style.space(8)
                        textFormat: Text.PlainText
                    }
                }

                // Type
                Item {
                    width: parent.width
                    height: Math.max(labelText2.implicitHeight, valueText2.implicitHeight) + Style.space(4)
                    anchors.leftMargin: Style.space(8)
                    anchors.rightMargin: Style.space(8)

                    Text {
                        id: labelText2
                        text: "Type:"
                        color: Qt.darker(root.bar.foreground, 1.4)
                        font.family: root.bar.fontFamily
                        font.pixelSize: Style.font.caption
                        anchors.left: parent.left
                        anchors.top: parent.top
                        textFormat: Text.PlainText
                    }

                    Text {
                        id: valueText2
                        text: root.item ? (root.item.type === "dir" ? "Folder" : "File") : ""
                        color: root.bar.foreground
                        font.family: root.bar.fontFamily
                        font.pixelSize: Style.font.caption
                        font.bold: true
                        anchors.left: labelText2.right
                        anchors.leftMargin: Style.space(8)
                        anchors.top: parent.top
                        elide: Text.ElideRight
                        width: parent.width - labelText2.width - Style.space(8)
                        textFormat: Text.PlainText
                    }
                }

                // Size/Items
                Item {
                    width: parent.width
                    height: Math.max(labelText3.implicitHeight, valueText3.implicitHeight) + Style.space(4)
                    anchors.leftMargin: Style.space(8)
                    anchors.rightMargin: Style.space(8)

                    Text {
                        id: labelText3
                        text: root.item ? (root.item.type === "dir" ? "Items:" : "Size:") : ""
                        color: Qt.darker(root.bar.foreground, 1.4)
                        font.family: root.bar.fontFamily
                        font.pixelSize: Style.font.caption
                        anchors.left: parent.left
                        anchors.top: parent.top
                        textFormat: Text.PlainText
                    }

                    Text {
                        id: valueText3
                        text: root.item ? (root.item.type === "dir" ? (root.item.sizeFormatted || "—") : Models.formatSize(root.item.size || 0)) : ""
                        color: root.bar.foreground
                        font.family: root.bar.fontFamily
                        font.pixelSize: Style.font.caption
                        font.bold: true
                        anchors.left: labelText3.right
                        anchors.leftMargin: Style.space(8)
                        anchors.top: parent.top
                        elide: Text.ElideRight
                        width: parent.width - labelText3.width - Style.space(8)
                        textFormat: Text.PlainText
                    }
                }

                // Modified
                Item {
                    width: parent.width
                    height: Math.max(labelText4.implicitHeight, valueText4.implicitHeight) + Style.space(4)
                    anchors.leftMargin: Style.space(8)
                    anchors.rightMargin: Style.space(8)

                    Text {
                        id: labelText4
                        text: "Modified:"
                        color: Qt.darker(root.bar.foreground, 1.4)
                        font.family: root.bar.fontFamily
                        font.pixelSize: Style.font.caption
                        anchors.left: parent.left
                        anchors.top: parent.top
                        textFormat: Text.PlainText
                    }

                    Text {
                        id: valueText4
                        text: root.item && root.item.mtime ? Models.formatDate(root.item.mtime) : "—"
                        color: root.bar.foreground
                        font.family: root.bar.fontFamily
                        font.pixelSize: Style.font.caption
                        font.bold: true
                        anchors.left: labelText4.right
                        anchors.leftMargin: Style.space(8)
                        anchors.top: parent.top
                        elide: Text.ElideRight
                        width: parent.width - labelText4.width - Style.space(8)
                        textFormat: Text.PlainText
                    }
                }

                // Library
                Item {
                    width: parent.width
                    height: Math.max(labelText5.implicitHeight, valueText5.implicitHeight) + Style.space(4)
                    anchors.leftMargin: Style.space(8)
                    anchors.rightMargin: Style.space(8)

                    Text {
                        id: labelText5
                        text: "Library:"
                        color: Qt.darker(root.bar.foreground, 1.4)
                        font.family: root.bar.fontFamily
                        font.pixelSize: Style.font.caption
                        anchors.left: parent.left
                        anchors.top: parent.top
                        textFormat: Text.PlainText
                    }

                    Text {
                        id: valueText5
                        text: root.currentRepo ? root.currentRepo.name : "—"
                        color: root.bar.foreground
                        font.family: root.bar.fontFamily
                        font.pixelSize: Style.font.caption
                        font.bold: true
                        anchors.left: labelText5.right
                        anchors.leftMargin: Style.space(8)
                        anchors.top: parent.top
                        elide: Text.ElideRight
                        width: parent.width - labelText5.width - Style.space(8)
                        textFormat: Text.PlainText
                    }
                }

                // Path
                Item {
                    width: parent.width
                    height: Math.max(labelText6.implicitHeight, valueText6.implicitHeight) + Style.space(4)
                    anchors.leftMargin: Style.space(8)
                    anchors.rightMargin: Style.space(8)

                    Text {
                        id: labelText6
                        text: "Path:"
                        color: Qt.darker(root.bar.foreground, 1.4)
                        font.family: root.bar.fontFamily
                        font.pixelSize: Style.font.caption
                        anchors.left: parent.left
                        anchors.top: parent.top
                        textFormat: Text.PlainText
                    }

                    Text {
                        id: valueText6
                        text: root.item ? Models.boundedDisplayText(root.currentPath === "/" ? "/" + root.item.name : root.currentPath + "/" + root.item.name, 1024) : ""
                        color: root.bar.foreground
                        font.family: root.bar.fontFamily
                        font.pixelSize: Style.font.caption
                        font.bold: true
                        anchors.left: labelText6.right
                        anchors.leftMargin: Style.space(8)
                        anchors.top: parent.top
                        elide: Text.ElideRight
                        width: parent.width - labelText6.width - Style.space(8)
                        textFormat: Text.PlainText
                    }
                }
            }

            // Summary for multi-selection
            Column {
                id: multiDetails
                width: parent.width
                spacing: Style.space(4)
                visible: root.isMultiSelection

                Item {
                    width: parent.width
                    height: Math.max(labelTextM1.implicitHeight, valueTextM1.implicitHeight) + Style.space(4)
                    anchors.leftMargin: Style.space(8)
                    anchors.rightMargin: Style.space(8)

                    Text {
                        id: labelTextM1
                        text: "Items:"
                        color: Qt.darker(root.bar.foreground, 1.4)
                        font.family: root.bar.fontFamily
                        font.pixelSize: Style.font.caption
                        anchors.left: parent.left
                        anchors.top: parent.top
                        textFormat: Text.PlainText
                    }

                    Text {
                        id: valueTextM1
                        text: root.selectedItems.length + " selected"
                        color: root.bar.foreground
                        font.family: root.bar.fontFamily
                        font.pixelSize: Style.font.caption
                        font.bold: true
                        anchors.left: labelTextM1.right
                        anchors.leftMargin: Style.space(8)
                        anchors.top: parent.top
                        elide: Text.ElideRight
                        width: parent.width - labelTextM1.width - Style.space(8)
                        textFormat: Text.PlainText
                    }
                }

                Item {
                    width: parent.width
                    height: Math.max(labelTextM2.implicitHeight, valueTextM2.implicitHeight) + Style.space(4)
                    anchors.leftMargin: Style.space(8)
                    anchors.rightMargin: Style.space(8)

                    Text {
                        id: labelTextM2
                        text: "Total size:"
                        color: Qt.darker(root.bar.foreground, 1.4)
                        font.family: root.bar.fontFamily
                        font.pixelSize: Style.font.caption
                        anchors.left: parent.left
                        anchors.top: parent.top
                        textFormat: Text.PlainText
                    }

                    Text {
                        id: valueTextM2
                        text: Models.formatSize((function() {
                            var total = 0
                            for (var i = 0; i < root.selectedItems.length; i++) {
                                total += root.selectedItems[i].size || 0
                            }
                            return total
                        })())
                        color: root.bar.foreground
                        font.family: root.bar.fontFamily
                        font.pixelSize: Style.font.caption
                        font.bold: true
                        anchors.left: labelTextM2.right
                        anchors.leftMargin: Style.space(8)
                        anchors.top: parent.top
                        elide: Text.ElideRight
                        width: parent.width - labelTextM2.width - Style.space(8)
                        textFormat: Text.PlainText
                    }
                }

                Item {
                    width: parent.width
                    height: Math.max(labelTextM3.implicitHeight, valueTextM3.implicitHeight) + Style.space(4)
                    anchors.leftMargin: Style.space(8)
                    anchors.rightMargin: Style.space(8)

                    Text {
                        id: labelTextM3
                        text: "Folders / Files:"
                        color: Qt.darker(root.bar.foreground, 1.4)
                        font.family: root.bar.fontFamily
                        font.pixelSize: Style.font.caption
                        anchors.left: parent.left
                        anchors.top: parent.top
                        textFormat: Text.PlainText
                    }

                    Text {
                        id: valueTextM3
                        text: (function() {
                            var folders = 0, files = 0
                            for (var i = 0; i < root.selectedItems.length; i++) {
                                if (root.selectedItems[i].type === "dir") folders++
                                else files++
                            }
                            return folders + " folders, " + files + " files"
                        })()
                        color: root.bar.foreground
                        font.family: root.bar.fontFamily
                        font.pixelSize: Style.font.caption
                        font.bold: true
                        anchors.left: labelTextM3.right
                        anchors.leftMargin: Style.space(8)
                        anchors.top: parent.top
                        elide: Text.ElideRight
                        width: parent.width - labelTextM3.width - Style.space(8)
                        textFormat: Text.PlainText
                    }
                }
            }

            // Action buttons
            Column {
                width: parent.width
                spacing: Style.space(4)
                visible: root.isSingleSelection && root.item !== null

                Row {
                    width: parent.width
                    spacing: Style.space(8)

                    Button {
                        text: root.item ? (root.item.type === "dir" ? "Open" : "Download") : ""
                        width: parent.width / 3 - Style.space(5)
                        height: Style.space(28)
                        onClicked: {
                            if (root.item && root.item.type === "dir") {
                                if (root.onItemClicked) root.onItemClicked(root.item)
                            } else {
                                if (root.onDownload) root.onDownload(root.item)
                            }
                        }
                    }

                    Button {
                        text: "Share"
                        width: parent.width / 3 - Style.space(5)
                        height: Style.space(28)
                        onClicked: {
                            if (root.onShare) root.onShare(root.item)
                        }
                    }

                    Button {
                        text: "History"
                        width: parent.width / 3 - Style.space(5)
                        height: Style.space(28)
                        onClicked: {
                            if (root.onHistory) root.onHistory(root.item)
                        }
                    }
                }

                Row {
                    width: parent.width
                    spacing: Style.space(8)

                    Button {
                        text: "Rename"
                        width: parent.width / 3 - Style.space(5)
                        height: Style.space(28)
                        onClicked: {
                            if (root.onRename) root.onRename(root.item)
                        }
                    }

                    Button {
                        text: "Move"
                        width: parent.width / 3 - Style.space(5)
                        height: Style.space(28)
                        onClicked: {
                            if (root.onMove) root.onMove(root.item)
                        }
                    }

                    Button {
                        text: "Delete"
                        width: parent.width / 3 - Style.space(5)
                        height: Style.space(28)
                        color: Color.urgent
                        onClicked: {
                            if (root.onDelete) root.onDelete(root.item)
                        }
                    }
                }
            }

            // Multi-selection actions
            Column {
                width: parent.width
                spacing: Style.space(4)
                visible: root.isMultiSelection

                Row {
                    width: parent.width
                    spacing: Style.space(8)

                    Button {
                        text: "Download"
                        width: parent.width / 3 - Style.space(5)
                        height: Style.space(28)
                        enabled: (function() {
                            for (var i = 0; i < root.selectedItems.length; i++) {
                                if (root.selectedItems[i].type !== "dir") return true
                            }
                            return false
                        })()
                        onClicked: {
                            for (var i = 0; i < root.selectedItems.length; i++) {
                                if (root.selectedItems[i].type !== "dir" && root.onDownload) {
                                    root.onDownload(root.selectedItems[i])
                                }
                            }
                        }
                    }

                    Button {
                        text: "Move"
                        width: parent.width / 3 - Style.space(5)
                        height: Style.space(28)
                        onClicked: {
                            if (root.onMove) root.onMove(root.selectedItems[0])
                        }
                    }

                    Button {
                        text: "Delete"
                        width: parent.width / 3 - Style.space(5)
                        height: Style.space(28)
                        color: Color.urgent
                        onClicked: {
                            if (root.onDelete) root.onDelete(root.selectedItems[0])
                        }
                    }
                }
            }
        }
    }
}