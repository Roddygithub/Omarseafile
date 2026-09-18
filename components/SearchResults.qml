import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui
import "../js"

ListView {
    id: root
    required property var results
    required property var onResultClicked
    required property var onResultRightClicked
    required property QtObject bar
    property string filterType: "all"  // "all", "file", "folder"
    property string filterLibrary: ""  // empty = all libraries

    width: parent.width
    height: parent.height
    clip: true
    spacing: Style.space(2)

    property var filteredResults: {
        var out = []
        for (var i = 0; i < root.results.length; i++) {
            var r = root.results[i]
            if (root.filterType !== "all" && r.type !== root.filterType) continue
            if (root.filterLibrary !== "" && r.repoName !== root.filterLibrary) continue
            out.push(r)
        }
        return out
    }

    model: root.filteredResults

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
                color: root.bar.foreground
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
                    text: Models.boundedDisplayText(delegate.modelData.name, 1024)
                    color: root.bar.foreground
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.body
                    elide: Text.ElideRight
                    width: parent.width
                    textFormat: Text.PlainText
                }

                Text {
                    id: pathLabel
                    text: Models.boundedDisplayText(delegate.repoName + " \u2022 " + delegate.modelData.parentPath, 4096)
                    color: Qt.darker(root.bar.foreground, 1.4)
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                    width: parent.width
                    visible: text !== " \u2022 "
                    textFormat: Text.PlainText
                }
            }

            Text {
                id: sizeLabel
                text: delegate.isDir ? "" : Models.formatSize(delegate.modelData.size)
                color: Qt.darker(root.bar.foreground, 1.4)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                width: Style.space(80)
                horizontalAlignment: Text.AlignRight
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
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

    // Filter bar
    Column {
        id: filterBar
        width: parent.width
        visible: root.results.length > 0
        spacing: Style.space(4)

        Row {
            width: parent.width
            spacing: Style.space(8)

            Text {
                text: "Filter:"
                color: Qt.darker(root.bar.foreground, 1.4)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                anchors.verticalCenter: parent.verticalCenter
            }

            ComboBox {
                id: typeFilter
                width: Style.space(100)
                model: ["All", "Files", "Folders"]
                currentIndex: root.filterType === "all" ? 0 : (root.filterType === "file" ? 1 : 2)
                onActivated: {
                    root.filterType = ["all", "file", "folder"][index]
                }
            }

            ComboBox {
                id: libraryFilter
                width: Style.space(140)
                model: ["All libraries"] + (function() {
                    var libs = []
                    for (var i = 0; i < root.results.length; i++) {
                        if (libs.indexOf(root.results[i].repoName) === -1) {
                            libs.push(root.results[i].repoName)
                        }
                    }
                    return libs
                })()
                currentIndex: root.filterLibrary === "" ? 0 : (function() {
                    var libs = []
                    for (var i = 0; i < root.results.length; i++) {
                        if (libs.indexOf(root.results[i].repoName) === -1) {
                            libs.push(root.results[i].repoName)
                        }
                    }
                    return libs.indexOf(root.filterLibrary) + 1
                })()
                onActivated: {
                    var libs = [""]
                    for (var i = 0; i < root.results.length; i++) {
                        if (libs.indexOf(root.results[i].repoName) === -1) {
                            libs.push(root.results[i].repoName)
                        }
                    }
                    root.filterLibrary = libs[index]
                }
            }

            Button {
                text: "Clear"
                width: Style.space(50)
                onClicked: {
                    root.filterType = "all"
                    root.filterLibrary = ""
                }
            }
        }
    }

    EmptyState {
        id: emptyState
        bar: root.bar
        icon: "\uf002"
        title: root.results.length === 0 ? "No results" : "No matching results"
        subtitle: root.results.length === 0 ? "Try different search terms" : "Adjust filters or search terms"
        width: parent.width
        height: parent.height
        anchors.centerIn: parent
        visible: root.filteredResults.length === 0
    }

    ScrollBar.vertical: ScrollBar {
        policy: ScrollBar.AsNeeded
    }
}