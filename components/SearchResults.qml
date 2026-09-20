import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui
import "../js"

ListView {
    id: root
    required property var results
    required property var onResultClicked
    required property QtObject bar
    property string filterType: "all"  // "all", "file", "folder"
    property string filterLibrary: ""  // empty = all libraries

    width: parent.width
    height: parent.height
    clip: true
    spacing: Style.space(2)

    // Distinct library names present in the current result set, in first-seen
    // order. Computed once so the filter model and its index lookup agree.
    readonly property var libraryNames: {
        var libs = []
        for (var i = 0; i < root.results.length; i++) {
            var name = root.results[i].repoName
            if (name && libs.indexOf(name) === -1) libs.push(name)
        }
        return libs
    }

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

    // The filter controls live in the header so they occupy real layout space
    // and scroll out of the way. As a plain child of the ListView they floated
    // at (0,0) directly on top of the first result and never scrolled.
    header: Column {
        id: filterBar
        width: root.width
        visible: root.results.length > 0
        height: visible ? implicitHeight : 0
        spacing: Style.space(4)

        Row {
            width: parent.width
            height: implicitHeight
            spacing: Style.space(8)

            Text {
                text: "Filter:"
                color: Qt.darker(root.bar.foreground, 1.4)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                height: parent.height
                verticalAlignment: Text.AlignVCenter
            }

            ComboBox {
                id: typeFilter
                width: Style.space(100)
                model: ["All", "Files", "Folders"]
                currentIndex: root.filterType === "all" ? 0 : (root.filterType === "file" ? 1 : 2)
                onActivated: function(index) {
                    root.filterType = ["all", "file", "folder"][index]
                }
            }

            ComboBox {
                id: libraryFilter
                width: Style.space(140)
                model: ["All libraries"].concat(root.libraryNames)
                currentIndex: root.filterLibrary === "" ? 0 : Math.max(0, root.libraryNames.indexOf(root.filterLibrary) + 1)
                onActivated: function(index) {
                    root.filterLibrary = index === 0 ? "" : (root.libraryNames[index - 1] || "")
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

        Rectangle {
            width: parent.width
            height: Style.spacing.hairline
            color: root.bar.foreground
            opacity: 0.12
        }
    }

    delegate: Item {
        id: delegate
        required property var modelData
        property bool isDir: modelData.type === "folder"
        property string repoName: modelData.repoName || ""

        implicitHeight: row.implicitHeight
        width: ListView.view ? ListView.view.width : parent.width

        Row {
            id: row
            spacing: Style.space(12)
            height: Math.max(icon.implicitHeight, textColumn.implicitHeight) + Style.space(6)

            Text {
                id: icon
                text: delegate.isDir ? Icons.folder : Icons.file
                color: root.bar.foreground
                font.family: Icons.family
                font.pixelSize: Style.font.title
                width: Style.space(24)
                horizontalAlignment: Text.AlignHCenter
                height: parent.height
                verticalAlignment: Text.AlignVCenter
            }

            Column {
                id: textColumn
                width: parent.width - icon.width - sizeLabel.width - Style.space(36)
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
                height: parent.height
                verticalAlignment: Text.AlignVCenter
                textFormat: Text.PlainText
            }
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            // Left-click activation only. Right-click previously performed the
            // same navigation as a left-click, which is surprising and offered
            // no menu of its own.
            acceptedButtons: Qt.LeftButton
            onClicked: {
                if (root.onResultClicked) root.onResultClicked(delegate.modelData)
            }
        }
    }

    EmptyState {
        id: emptyState
        bar: root.bar
        icon: Icons.search
        title: root.results.length === 0 ? "No results" : "No matching results"
        subtitle: root.results.length === 0 ? "Try different search terms" : "Adjust filters or search terms"
        // Positioned explicitly rather than anchors.centerIn: parent. Anchors are
        // unsupported on ListView children, and centering against the ListView
        // would place this in the middle of the (header-sized) content item
        // rather than in the middle of what the user can actually see. Tracking
        // contentY keeps it fixed in the viewport while the filter header above
        // it scrolls out of the way.
        width: root.width
        height: root.height
        y: root.contentY + (root.height - height) / 2
        visible: root.filteredResults.length === 0
    }

    ScrollBar.vertical: ScrollBar {
        policy: ScrollBar.AsNeeded
    }
}
