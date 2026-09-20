pragma Singleton
import QtQuick

// Central icon-font handling.
//
// The panel's icons are Font Awesome codepoints in Unicode's private-use area.
// They are NOT ordinary text, so they must never inherit the user's UI font:
// doing so would render tofu boxes. Omarchy exposes no public icon-font
// abstraction that this plugin can bind to, so the dedicated icon family is
// centralised here and documented.
//
// Rules:
//   * Icon glyphs use `Icons.family`.
//   * Every other Text element follows the Omarchy user font through
//     `bar.fontFamily` (Style.font.family as a fallback where no bar exists).
//   * If Omarchy ever ships a canonical icon mechanism, this singleton is the
//     single place to switch over.
QtObject {
    id: root

    // Dedicated icon family. Deliberately distinct from the text font.
    readonly property string family: "Noto Sans"

    // Font Awesome codepoints in use, by role rather than by hex value, so a
    // glyph swap is a one-line change here instead of an edit in twelve files.
    readonly property string book: "\uf02d"          // library / Quick Access
    readonly property string clock: "\uf017"         // recent
    readonly property string times: "\uf00d"         // close / remove / cancel
    readonly property string folder: "\uf07b"        // directory
    readonly property string folderOpen: "\uf07c"    // open directory
    readonly property string file: "\uf15b"          // file
    readonly property string download: "\uf019"      // download
    readonly property string upload: "\uf093"        // upload
    readonly property string search: "\uf002"        // search
    readonly property string chevronLeft: "\uf053"   // back
    readonly property string user: "\uf007"          // account
    readonly property string trash: "\uf1f8"         // trash
    readonly property string ellipsisV: "\uf142"     // overflow menu
    readonly property string spinner: "\uf110"       // busy
    readonly property string warning: "\uf06a"       // error / warning
    readonly property string ban: "\uf05e"           // unavailable
    readonly property string refresh: "\uf021"       // refresh / retry
    readonly property string check: "\uf00c"         // success
    readonly property string exchange: "\uf0ec"      // move / copy
}
