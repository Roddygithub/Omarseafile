#!/usr/bin/env python3
"""Small behavioral checks for the UI/UX batch; uses shipped QML helpers."""
import subprocess
import os
import shutil
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
script = r'''const h = require("./scripts/qmljs.js");
const I = h.loadQmlObject("js/Icons.qml", {});
const F = h.loadQmlObject("components/FileItem.qml", {Icons: I});
function check(name, value) { if (!value) throw new Error(name); console.log("PASS " + name); }
check("folder icon", F.iconForItem({type: "dir", name: "docs"}) === I.folder);
check("pdf icon", F.iconForItem({type: "file", name: "report.pdf"}) === I.filePdf);
check("spreadsheet icon", F.iconForItem({type: "file", name: "budget.xlsx"}) === I.fileExcel);
check("image icon", F.iconForItem({type: "file", name: "photo.webp"}) === I.fileImage);
check("archive icon", F.iconForItem({type: "file", name: "backup.tar.gz"}) === I.fileArchive);
check("unknown extension fallback", F.iconForItem({type: "file", name: "notes.unknown"}) === I.file);

const P = h.loadQmlObject("Panel.qml", {
  UrlPolicy: {validateForAuth: () => ({valid: false, error: "invalid"})},
  SeafileAPI: {}, SelectionHelper: {}, TransferService: {}, Cache: {},
  Favorites: {}, Auth: {}, Models: {}, SafePath: {}, Qt: {resolvedUrl: () => ""}
});
P.settingsLoader = {item: {connectionTestRunning: true, connectionTestSuccess: true, connectionTestMessage: "stale"}};
P.connectionTestGeneration = 2;
P.showToast = () => { throw new Error("URL typing must not toast") };
P.changeServerUrl("https://unfinished.example", false);
check("editing server URL invalidates stale test quietly",
  P.connectionTestGeneration === 3 && !P.settingsLoader.item.connectionTestRunning
  && !P.settingsLoader.item.connectionTestSuccess && P.settingsLoader.item.connectionTestMessage === "");
let keyboardContext = null;
const contextRow = {
  item: {name: "focused", type: "file"}, width: 100, height: 24,
  mapToItem: () => ({x: 50, y: 12})
};
P.state = "browse";
P.searchActive = false;
P.destinationMode = "";
P.destinationSubmitting = false;
P.showTransfers = false;
P.activeFileList = () => ({count: 1, currentIndex: 0, currentItem: contextRow});
P.keyCatcher = {Overlay: {overlay: {}}};
P.showItemContextMenu = (item, x, y) => { keyboardContext = {item, x, y} };
P.showKeyboardContextMenu();
check("Shift+F10 targets the focused row", keyboardContext
  && keyboardContext.item.name === "focused" && keyboardContext.x === 50 && keyboardContext.y === 12);
let contextShareItem = null;
let temporarySelectionCleared = 0;
P.contextMenuAddedSelection = true;
P.selectedItems = [contextRow.item];
P.clearSelection = () => { temporarySelectionCleared++; P.selectedItems = [] };
P.pickShare = (item) => { contextShareItem = item };
P.shareFromContextMenu(contextRow.item);
check("context-menu Share clears temporary selection, preserves its target, and resets its marker",
  contextShareItem === contextRow.item && temporarySelectionCleared === 1
  && P.selectedItems.length === 0 && !P.contextMenuAddedSelection);
let contextClosed = false;
P.destinationMode = "";
P.shareLoader = {item: null};
P.contextMenu = {opened: true, close: () => { contextClosed = true }};
check("Escape dismisses context menu before closing the panel",
  P.closeTopDialog() === true && contextClosed);
P.contextMenu.opened = false;
let revokeCancelled = 0;
P.shareLoader = {item: {revokeConfirmationOpen: true, cancelRevoke: () => { revokeCancelled++ }}};
check("Escape closes share revoke confirmation before the share view",
  P.closeTopDialog() === true && revokeCancelled === 1);

let shareRequests = 0;
const S = h.loadQmlObject("components/ShareDialog.qml", {
  SeafileAPI: {createShareLink: () => { shareRequests++ }}
});
S.enableExpiration = true;
S.expireDays = "";
S.createLink();
check("enabled share expiration cannot silently become non-expiring",
  shareRequests === 0 && S.errorMessage.indexOf("Expiration") === 0);
S.expireDays = "366";
S.errorMessage = "";
S.createLink();
check("share expiration is bounded to one year", shareRequests === 0 && S.errorMessage.indexOf("Expiration") === 0);
S.shareUrl = "https://old.example/link";
S.shareToken = "old-token";
S.errorMessage = "stale error";
S.enablePassword = true;
S.passwordValue = "old-password";
S.enableExpiration = true;
S.expireDays = "30";
S.enablePermissions = true;
S.beginCreateForm();
check("creating another share link clears the previous result", S.showCreateForm
  && S.shareUrl === "" && S.shareToken === "" && S.errorMessage === ""
  && !S.enablePassword && S.passwordValue === "" && !S.enableExpiration
  && S.expireDays === "7" && !S.enablePermissions);
'''
subprocess.run(["node", "-e", script], cwd=ROOT, check=True)
file_item = (ROOT / "components/FileItem.qml").read_text()
panel_source = (ROOT / "Panel.qml").read_text()
assert "ToolTip.visible: mouseArea.containsMouse && truncated" in file_item
assert "mouse.button !== Qt.LeftButton || root.singleClickOpen" in file_item
assert 'if (root.state === "browse" && (!root.libraries || root.libraries.length === 0))' in panel_source
assert "border.width: root.isCurrent ? Style.spacing.hairline : 0" in file_item
assert "readonly property int highlightInset: Style.space(16)" in file_item
assert "width: parent.width - 2 * x" in file_item
assert "width: parent.width - Style.space(24)" in file_item
file_list = (ROOT / "components/FileList.qml").read_text()
assert "width: parent.width - Style.space(24)" in file_list
# Header and row cells share the same fixed column widths, so the sort header
# stays aligned with the cells under it after the highlight gutter.
assert "width: visible ? (Style.space(150) - Style.space(24)) : 0" in file_item
assert "width: Style.space(150) - Style.space(24)" in file_list
print("PASS long-name tooltip and focus styling")
bar = (ROOT / "components/BatchActionBar.qml").read_text()
toolbar = (ROOT / "components/ToolBar.qml").read_text()
panel = (ROOT / "Panel.qml").read_text()
assert 'text: "More"' in bar and 'text: "Copy"' in bar
assert 'text: "Delete"' in bar and 'text: "Clear"' in bar
assert "hoverEnabled: true" in toolbar
assert "readonly property bool overflowAvailable: overflowMenu.itemCount > 0" in toolbar
assert "visible: root.overflowAvailable" in toolbar
assert "if (root.overflowAvailable) root.overflowOpen = !root.overflowOpen" in toolbar
assert 'ToolbarToolTip' not in toolbar
assert toolbar.count('PanelToolTip {') == 5
assert 'text: "More"' not in toolbar
assert 'ToolTip.visible:' not in toolbar
assert 'showUpload: root.state === "browse" && root.currentRepo !== null' in panel
assert 'showTransfers: root.state === "browse" && !root.dialogOpen && !root.destinationMode && !root.showTransfers' in panel
for surface in ("components/HistoryPanel.qml", "components/TrashPanel.qml"):
    source = (ROOT / surface).read_text()
    assert "property bool loading: false" in source
    assert "property string errorMessage: \"\"" in source
    assert "visible: !root.loading && root.errorMessage !== \"\"" in source
print("PASS compact selection action hierarchy")
selection_bar = (ROOT / "components/BatchActionBar.qml").read_text()
assert "mapToItem(root.overlay" in selection_bar
print("PASS selection popup uses overlay coordinates")
menu = (ROOT / "components/ContextMenu.qml").read_text()
assert menu.count("height: visible ? Style.spacing.hairline : 0") == 3
assert "color: Color.urgent" in menu
assert "closePolicy: Popup.CloseOnPressOutside" in menu
assert 'sequence: "Escape"' in menu and "enabled: root.opened" in menu and "onActivated: root.close()" in menu
assert "CloseOnPressOutsideParent" not in menu
print("PASS grouped context actions and destructive emphasis")
details = (ROOT / "components/DetailsPanel.qml").read_text()
assert "ToolTip.visible: nameHover.containsMouse && truncated" in details
assert "ToolTip.visible: pathHover.containsMouse && truncated" in details
assert 'visible: root.item && root.item.type === "file"' in details
print("PASS details long-name and action visibility")
home = (ROOT / "views/HomeView.qml").read_text()
assert 'visible: root.loading && !root.searchActive' in home
assert 'visible: !root.loading && root.errorMessage === ""' in home
assert 'height: implicitHeight' in home
print("PASS home loading and empty states do not collide")
assert 'ipcTarget: "roddy.seafile"' not in panel
assert "target: root.moduleName" in panel
assert 'sequence: "Shift+F10"' in panel and "root.showKeyboardContextMenu()" in panel
assert "context: Qt.ApplicationShortcut" in panel
print("PASS plugin uses one active shell IPC target")
for path in ("components/FileItem.qml", "components/SearchResults.qml", "components/HistoryPanel.qml", "components/TrashPanel.qml"):
    source = (ROOT / path).read_text()
    assert "width: parent.width" in source
details = (ROOT / "components/DetailsPanel.qml").read_text()
assert "height: implicitHeight" in details and "detailsColumn.implicitHeight" in details
browser = (ROOT / "views/BrowserView.qml").read_text()
toolbar = (ROOT / "components/ToolBar.qml").read_text()
assert "uploadButton.visible ? uploadButton.implicitWidth : 0" in toolbar
assert "transferIndicator.visible ? transferIndicator.width : 0" in toolbar
assert "root.selectedItems.length > 1" in panel and "root.selectedItems.length : 0" in panel
assert "!root.dialogOpen && !contextMenu.opened" in panel
assert "&& !root.contextMenuOpen" in browser
print("PASS list geometry, details sizing, and toolbar width accounting")
print("PASS context menu suppresses duplicate selection actions")
print("=== UI/UX list checks passed ===")

# The context menu owns a real Popup overlay, so exercise its close lifecycle
# with Qt when the local Omarchy/Quickshell runtime is available. This catches
# input-routing regressions that a source-only check cannot observe.
qs = shutil.which("qs")
shell = Path("/usr/share/omarchy/shell")
if not qs or not (shell / "Ui").is_dir():
    print("SKIP context-menu Qt interaction checks: Quickshell/Omarchy required")
else:
    qml = '''import QtQuick
import QtQuick.Controls
import QtTest
import "components"
TestCase {
    id: tests
    name: "ContextMenuJourney"
    when: ready
    width: 600
    height: 900
    property bool ready: false
    property int openedItems: 0
    property int favoriteItems: 0
    TestResult { id: result }
    Timer { interval: 100; running: true; onTriggered: ready = true }
    onCompletedChanged: if (completed) {
        console.log(result.failCount === 0 ? "CONTEXT_MENU_QT_OK" : "CONTEXT_MENU_QT_FAILED")
        Qt.quit()
    }
    QtObject {
        id: fakeBar
        property color foreground: "white"
        property color background: "#222222"
        property string fontFamily: "sans-serif"
    }
    Button { id: outsideButton; x: 300; y: 300; width: 120; height: 40; text: "Outside" }
    ContextMenu {
        id: menu
        bar: fakeBar
        item: ({name: "Library", type: "dir"})
        isDir: true
        libraryMode: true
        selectionCount: 1
        onOpenClicked: function(item) { tests.openedItems++ }
        onAddToFavoritesClicked: function(item) { tests.favoriteItems++ }
    }
    function positionMenu() {
        menu.parent = tests.Overlay.overlay
        menu.x = 10
        menu.y = 10
    }
    function test_action_closes() {
        positionMenu()
        menu.open()
        tryCompare(menu, "opened", true, 1000)
        mouseClick(menu.contentItem, 50, 16, Qt.LeftButton, Qt.NoModifier)
        tryCompare(menu, "opened", false, 1000)
        compare(openedItems, 1)
    }
    function test_keyboard_navigation_activates_action() {
        positionMenu()
        menu.open()
        tryCompare(menu, "opened", true, 1000)
        tryCompare(menu, "focusedActionIndex", 1, 1000)
        keyClick(Qt.Key_Down)
        tryCompare(menu, "focusedActionIndex", 8, 1000)
        keyClick(Qt.Key_Return)
        tryCompare(tests, "favoriteItems", 1, 1000)
        tryCompare(menu, "opened", false, 1000)
    }
    function test_outside_click_closes() {
        positionMenu()
        menu.open()
        tryCompare(menu, "opened", true, 1000)
        mouseClick(outsideButton, 60, 20, Qt.LeftButton, Qt.NoModifier)
        tryCompare(menu, "opened", false, 1000)
    }
    function test_escape_closes() {
        positionMenu()
        menu.open()
        tryCompare(menu, "opened", true, 1000)
        keyClick(Qt.Key_Escape)
        tryCompare(menu, "opened", false, 1000)
    }
}
'''
    with tempfile.TemporaryDirectory(prefix="omarseafile-context-menu-") as temp:
        package = Path(temp)
        for name in ("components", "js"):
            (package / name).symlink_to(ROOT / name)
        for name in ("Ui", "Commons"):
            (package / name).symlink_to(shell / name)
        test_file = package / "test.qml"
        test_file.write_text(qml)
        runtime = package / "runtime"
        runtime.mkdir(mode=0o700)
        env = dict(os.environ, QT_QPA_PLATFORM="offscreen",
                   QT_QPA_PLATFORMTHEME="generic", QT_QUICK_CONTROLS_STYLE="Basic",
                   XDG_RUNTIME_DIR=str(runtime), XDG_CACHE_HOME=str(package / "cache"))
        env.pop("WAYLAND_DISPLAY", None)
        result = subprocess.run([qs, "--path", str(test_file)], env=env,
                                capture_output=True, text=True, timeout=30)
    output = result.stdout + result.stderr
    if result.returncode or "CONTEXT_MENU_QT_OK" not in output or "CONTEXT_MENU_QT_FAILED" in output:
        raise AssertionError(output)
    print("PASS context menu closes after action, outside click, and Escape")
