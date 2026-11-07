pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "Translation.js" as Translation

QtObject {
    id: root
    readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config"
    readonly property var registry: parse(registryFile.text())
    readonly property string language: Translation.language(languageFile.text(),
        Quickshell.env("LC_ALL") || Quickshell.env("LC_MESSAGES") || Quickshell.env("LANG"), registry)
    readonly property bool rightToLeft: ["ar", "fa", "he", "ur"].indexOf(language) >= 0
    readonly property string formatLocale: (registry[language] || {}).formatLocale || "en-US"
    readonly property var strings: parse(catalogFile.text())

    function parse(text) {
        try {
            var data = JSON.parse(text || "{}")
            return data && typeof data === "object" && !Array.isArray(data) ? data : ({})
        } catch (e) { return ({}) }
    }
    function t(source, args) { return Translation.translate(strings, source, args) }

    // Editors and omarchy-language truncate then write. Read after the burst,
    // so an intermediate empty file cannot leave the UI stuck in English.
    property Timer languageReload: Timer {
        interval: 50
        onTriggered: languageFile.reload()
    }

    // Use Omarchy's persisted choice first; follow the session locale on older hosts.
    property FileView languageFile: FileView {
        path: Quickshell.env("OMARCHY_LANGUAGE_FILE") || root.configHome + "/omarchy/language"
        blockLoading: true
        watchChanges: true
        printErrors: false
        onFileChanged: root.languageReload.restart()
    }
    property FileView registryFile: FileView {
        path: decodeURIComponent(Qt.resolvedUrl("locales/registry.json").toString().replace(/^file:\/\//, ""))
        blockLoading: true
        printErrors: false
    }
    property FileView catalogFile: FileView {
        path: decodeURIComponent(Qt.resolvedUrl("locales/" + root.language + ".json").toString().replace(/^file:\/\//, ""))
        blockLoading: true
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
    }
}
