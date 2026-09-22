#!/usr/bin/env python3
"""Small behavioral checks for the UI/UX batch; uses shipped QML helpers."""
import subprocess
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
'''
subprocess.run(["node", "-e", script], cwd=ROOT, check=True)
file_item = (ROOT / "components/FileItem.qml").read_text()
assert "ToolTip.visible: mouseArea.containsMouse && truncated" in file_item
assert "border.width: root.isCurrent ? Style.spacing.hairline : 0" in file_item
print("PASS long-name tooltip and focus styling")
bar = (ROOT / "components/BatchActionBar.qml").read_text()
assert 'text: "More"' in bar and 'text: "Copy"' in bar
assert 'text: "Delete"' in bar and 'text: "Clear"' in bar
print("PASS compact selection action hierarchy")
print("=== UI/UX list checks passed ===")
