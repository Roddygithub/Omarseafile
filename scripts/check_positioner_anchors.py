#!/usr/bin/env python3
"""Locate anchors set on direct children of QML positioners.

Column, Row, Grid and Flow position their children themselves. Setting
`anchors.*` on a direct child is invalid: Qt logs
"Cannot specify <anchor> for items inside <Positioner>" and ignores the anchor,
so the intended layout silently does not happen.

Anchors that target something other than the positioner parent
(e.g. `anchors.centerIn: someOtherItem`, `anchors.left: sibling.right`) are
legitimate and are not reported.

Used both as a developer tool and by scripts/test_v11_remediation.py.
"""
import glob
import os
import re
import sys

POSITIONERS = {"Column", "Row", "Grid", "Flow"}
DECL = re.compile(r"^([A-Z]\w*)\s*\{")

# Anchors that are meaningless/invalid when the parent is a positioner.
INVALID_ON_POSITIONER_CHILD = re.compile(
    r"^anchors\.(fill|centerIn|horizontalCenter|verticalCenter|"
    r"left|right|top|bottom|leftMargin|rightMargin|topMargin|bottomMargin|"
    r"verticalCenterOffset|horizontalCenterOffset)\b"
)


def strip_comments(src):
    """Blank out comments, preserving offsets. Regex-literal aware."""
    out = []
    i = 0
    n = len(src)
    string = None
    in_regex = False
    in_class = False
    last = ''
    regex_allowed_after = re.compile(r"[\w$\]]$")
    while i < n:
        c = src[i]
        if in_regex:
            out.append(c)
            if c == '\\':
                out.append(src[i + 1] if i + 1 < n else '')
                i += 2
                continue
            if c == '[':
                in_class = True
            elif c == ']':
                in_class = False
            elif c == '/' and not in_class:
                in_regex = False
                last = '/'
            elif c == '\n':
                in_regex = False
                in_class = False
            i += 1
            continue
        if string:
            out.append(c)
            if c == '\\':
                out.append(src[i + 1] if i + 1 < n else '')
                i += 2
                continue
            if c == string:
                string = None
                last = c
            i += 1
            continue
        if c in '"\'`':
            string = c
            out.append(c)
            i += 1
            continue
        if c == '/' and i + 1 < n and src[i + 1] == '/':
            while i < n and src[i] != '\n':
                out.append(' ')
                i += 1
            continue
        if c == '/' and i + 1 < n and src[i + 1] == '*':
            while i < n and not (src[i] == '*' and i + 1 < n and src[i + 1] == '/'):
                out.append('\n' if src[i] == '\n' else ' ')
                i += 1
            out.append('  ')
            i += 2
            continue
        if c == '/' and not regex_allowed_after.search(last):
            in_regex = True
            out.append(c)
            i += 1
            continue
        if not c.isspace():
            last = c
        out.append(c)
        i += 1
    return ''.join(out)


def scan(path):
    """Return [(line_no, child_type, positioner_type, anchor_line), ...].

    An `anchors.*` line belongs to the innermost enclosing object declaration,
    which is either the declaration on a previous line at shallower indent or
    the declaration on the same line (`Item { anchors.fill: parent }`). Its
    PARENT is the next declaration outwards from there. Getting this backwards
    is what makes `Column { anchors.horizontalCenter: ... }` - a perfectly
    valid anchor on the Column itself - look like a child anchor.
    """
    raw = open(path, encoding='utf-8').read()
    src = strip_comments(raw)
    lines = src.split('\n')

    # Build the declaration tree: (line_no, indent, type, parent_index).
    decls = []          # index -> dict(line, indent, type, parent)
    stack = []          # open declarations: [decl_index, depth_after_open]
    depth = 0
    decl_at_line = {}
    owner_by_line = {}

    for idx, line in enumerate(lines, 1):
        stripped = line.strip()
        if not stripped:
            continue
        indent = len(line) - len(line.lstrip())
        decl = DECL.match(stripped)
        # The owner of any property on this line is the declaration currently
        # open, or the one this very line declares.
        owner_by_line[idx] = stack[-1][0] if stack else None

        # Walk the characters of this line, maintaining the brace stack.
        i = 0
        s = None
        opened_decl = False
        decl_index = None
        while i < len(stripped):
            ch = stripped[i]
            if s:
                if ch == '\\':
                    i += 2
                    continue
                if ch == s:
                    s = None
                i += 1
                continue
            if ch in '"\'`':
                s = ch
                i += 1
                continue
            if ch == '{':
                depth += 1
                if decl and not opened_decl:
                    parent_index = stack[-1][0] if stack else None
                    decls.append({
                        'line': idx,
                        'indent': indent,
                        'type': decl.group(1),
                        'parent': parent_index,
                    })
                    decl_index = len(decls) - 1
                    decl_at_line[idx] = decl_index
                    stack.append([decl_index, depth])
                    opened_decl = True
                    owner_by_line[idx] = decl_index
                else:
                    stack.append([None, depth])
            elif ch == '}':
                while stack and stack[-1][1] >= depth:
                    stack.pop()
                depth -= 1
            i += 1

    def owner_of(line_no):
        """Index of the declaration that owns a property on `line_no`.

        Resolved from the live brace stack, not from indentation: a closed
        sibling block must not capture the next sibling's properties.
        """
        return owner_by_line.get(line_no)

    findings = []
    for idx, line in enumerate(lines, 1):
        stripped = line.strip()
        if not stripped.startswith('anchors.'):
            continue
        owner = owner_of(idx)
        if owner is None:
            continue
        parent_index = decls[owner]['parent']
        if parent_index is None:
            continue
        parent_type = decls[parent_index]['type']
        if parent_type not in POSITIONERS:
            continue
        if not INVALID_ON_POSITIONER_CHILD.match(stripped):
            continue
        # Anchors that resolve against something other than the positioner
        # parent (a sibling, a named item) are legitimate.
        target = stripped.split(':', 1)[1].strip() if ':' in stripped else ''
        if not (target.startswith('parent') or target == ''):
            continue
        findings.append((idx, decls[owner]['type'], parent_type, stripped))

    return findings


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    total = 0
    for path in sorted(glob.glob(os.path.join(root, '**', '*.qml'), recursive=True)):
        rel = os.path.relpath(path, root)
        found = scan(path)
        if not found:
            continue
        print('--- ' + rel)
        for line_no, child, parent, text in found:
            print('   line %4d  %-12s inside %-6s -> %s' % (line_no, child, parent, text))
        total += len(found)
    if total == 0:
        print('OK: no anchors on direct positioner children')
    else:
        print('\n%d invalid positioner anchor(s) found' % total)
    return 1 if total else 0


if __name__ == '__main__':
    sys.exit(main())
