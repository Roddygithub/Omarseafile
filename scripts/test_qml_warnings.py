#!/usr/bin/env python3
"""
Regression tests for QML runtime warning fixes.

Verifies that the three QML runtime warning fixes are present:
1. DetailsPanel - null guards on root.item property access
2. FileItem - safe access to ListView, ListView.view, root.bar.foreground
3. FileList - no anchors.fill:parent in Column (replaced with explicit width/height)
"""

import os
import sys
import re

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
passed = 0
failed = 0


def test(name, condition, detail=""):
    global passed, failed
    if condition:
        passed += 1
        print(f"  PASS: {name}")
    else:
        failed += 1
        msg = f"  FAIL: {name}"
        if detail:
            msg += f" — {detail}"
        print(msg)


def read_file(relpath):
    with open(os.path.join(REPO_ROOT, relpath)) as f:
        return f.read()


if __name__ == "__main__":
    passed = 0
    failed = 0

    def test(name, condition, detail=""):
        global passed, failed
        if condition:
            passed += 1
            print(f"  PASS: {name}")
        else:
            failed += 1
            msg = f"  FAIL: {name}"
            if detail:
                msg += f" — {detail}"
            print(msg)

    # --- DetailsPanel tests ---
    details_src = read_file("components/DetailsPanel.qml")
    
    test("DetailsPanel: root.item.name null guard",
         "root.item ? Models.boundedDisplayText(root.item.name, 1024) : \"\"" in read_file("components/DetailsPanel.qml"))
    
    test("DetailsPanel: root.item.type null guard (Folder/File)",
         "root.item ? (root.item.type === \"dir\" ? \"Folder\" : \"File\") : \"\"" in read_file("components/DetailsPanel.qml"))
    
    test("DetailsPanel: root.item.type null guard (Items/Size)",
         "root.item ? (root.item.type === \"dir\" ? \"Items:\" : \"Size:\") : \"\"" in read_file("components/DetailsPanel.qml"))
    
    test("DetailsPanel: root.item.type null guard (size)",
         "root.item ? (root.item.type === \"dir\" ? (root.item.sizeFormatted || \"—\") : Models.formatSize(root.item.size || 0)) : \"\"" in read_file("components/DetailsPanel.qml"))
    
    test("DetailsPanel: root.item.mtime null guard",
         "root.item && root.item.mtime ? Models.formatDate(root.item.mtime) : \"—\"" in read_file("components/DetailsPanel.qml"))
    
    test("DetailsPanel: root.item.name null guard (path)",
         "root.item ? (root.currentPath === \"/\" ? \"/\" + root.item.name : root.currentPath + \"/\" + root.item.name) : \"\"" in read_file("components/DetailsPanel.qml"))

    # --- FileItem tests ---
    fileitem_src = read_file("components/FileItem.qml")
    
    test("FileItem: ListView.isCurrentItem null guard (visible)",
         "(root.ListView && root.ListView.isCurrentItem) || false" in fileitem_src)
    
    test("FileItem: ListView.view null guard",
         "(root.ListView && root.ListView.view)" in fileitem_src)
    
    test("FileItem: root.bar.foreground null guard (|| Color.foreground)",
         "(root.bar.foreground || Color.foreground)" in fileitem_src)
    
    test("FileItem: ListView.view access guard",
         "(root.ListView && root.ListView.view)" in fileitem_src)
    
    test("FileItem: color property bar.foreground null guard",
         "root.bar ? (root.bar.foreground || Color.foreground) : Color.foreground" in fileitem_src)
    
    test("FileItem: Qt.darker bar.foreground null guard",
         "Qt.darker(root.bar ? (root.bar.foreground || Color.foreground) : Color.foreground" in fileitem_src)
    
    # --- FileList tests ---
    filelist_src = read_file("components/FileList.qml")
    
    test("FileList: Row in Column uses explicit width/height (not anchors.fill)",
         "width: parent.width" in filelist_src and "height: implicitHeight" in filelist_src)
    
    test("FileList: no anchors.fill:parent in Column child",
         "anchors.fill: parent" not in filelist_src or "anchors.fill: parent" not in filelist_src)
    
    # Verify no anchors.fill:parent in Column children
    header_section = filelist_src.split("header: Item {")[1].split("}  // closes header Item")[0] if "header: Item {" in filelist_src else ""
    test("FileList: header Row has explicit width/height",
         "width: parent.width" in header_section and "height: implicitHeight" in header_section)

    print(f"\n=== {passed} passed, {failed} failed ===")
    sys.exit(1 if failed else 0)