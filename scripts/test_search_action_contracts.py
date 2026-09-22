#!/usr/bin/env python3
"""Focused search and selection-targeting checks."""
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
panel = (ROOT / "Panel.qml").read_text()
toolbar = (ROOT / "components/ToolBar.qml").read_text()
details = (ROOT / "components/DetailsPanel.qml").read_text()
browser = (ROOT / "views/BrowserView.qml").read_text()
search = (ROOT / "components/SearchResults.qml").read_text()

def check(name, condition):
    if not condition:
        raise AssertionError(name)
    print(f"PASS {name}")

check("search Enter executes immediately", "onAccepted" in toolbar and "onSearchSubmitted" in toolbar and "onSearchSubmitted: root.executeSearch" in panel)
check("search close button is visible while active", "visible: root.showSearch" in toolbar and "root.searchActive = !root.searchActive" in toolbar)
check("search opens folders and files", "if (result.type === \"folder\")" in panel and "else if (result.type === \"file\")" in panel)
check("search counts searchable libraries", "searchableLibraryCount" in browser and "encrypted !== true" in browser)
check("details batch move targets full selection", "onMoveBatch" in details and "root.onMoveBatch()" in details)
check("details batch delete targets full selection", "onDeleteBatch" in details and "root.onDeleteBatch()" in details)
check("browser wires detail batch actions", "onMoveBatch: root.onMoveBatch" in browser and "onDeleteBatch: root.onDeleteBatch" in browser)
check("panel wires batch actions", panel.count("onMoveBatch: root.moveItems") >= 1 and panel.count("onDeleteBatch: root.deleteItems") >= 1)
check("search right click is not an accidental navigation", "acceptedButtons: Qt.LeftButton" in search)
print("=== search/action targeting checks passed ===")
