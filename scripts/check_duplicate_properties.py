#!/usr/bin/env python3
"""Locate duplicate QML property assignments on the SAME object.

QML forbids assigning the same property twice on one object:
  Column { width: 10; width: 20 }   # duplicate 'width'
The later binding is a runtime warning and only one wins. This scans the real
sources and reports only assignments that share BOTH a property name AND the
owning object declaration.

It distinguishes:
  * same object          -> duplicate (reported)
  * nested/sibling object -> different owner -> NOT reported
  * signal handlers      -> `onXxx:` grouped separately (duplicates reported)
  * property declarations -> `property T name:` grouped with name assignments

Used by scripts/validate.sh and test_v11_remediation.py. Target: 0 findings.
"""
import glob
import os
import re
import sys

DECL = re.compile(r"^([A-Z]\w*)\s*\{")


def strip_comments(src):
    out = []
    i = 0
    n = len(src)
    string = None
    in_regex = False
    in_class = False
    last = ""
    regex_allowed_after = re.compile(r"[\w$\]]$")
    while i < n:
        c = src[i]
        if in_regex:
            out.append(c)
            if c == "\\":
                out.append(src[i + 1] if i + 1 < n else "")
                i += 2
                continue
            if c == "[":
                in_class = True
            elif c == "]":
                in_class = False
            elif c == "/" and not in_class:
                in_regex = False
                last = "/"
            elif c == "\n":
                in_regex = False
                in_class = False
            i += 1
            continue
        if string:
            out.append(c)
            if c == "\\":
                out.append(src[i + 1] if i + 1 < n else "")
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
        if c == "/" and i + 1 < n and src[i + 1] == "/":
            while i < n and src[i] != "\n":
                out.append(" ")
                i += 1
            continue
        if c == "/" and i + 1 < n and src[i + 1] == "*":
            while i < n and not (src[i] == "*" and i + 1 < n and src[i + 1] == "/"):
                out.append("\n" if src[i] == "\n" else " ")
                i += 1
            out.append("  ")
            i += 2
            continue
        if c == "/" and not regex_allowed_after.search(last):
            in_regex = True
            out.append(c)
            i += 1
            continue
        if not c.isspace():
            last = c
        out.append(c)
        i += 1
    return "".join(out)


# A property assignment starts a line (no leading nesting) and is one of:
#   key: value
#   property <type> key: value
#   readonly property <type> key: value
ASSIGN = re.compile(
    r"^(?:(?:readonly\s+)?property\s+(?:[\w.<>\[\]]+)\s+)?"
    r"(on[A-Z]\w*|id|[\w-]+)\s*:"
)


def scan(path):
    """Return [path, [(line_no, object_type, property)]] duplicate assignments."""
    raw = open(path, encoding="utf-8").read()
    src = strip_comments(raw)
    lines = src.split("\n")

    decls = []          # index -> dict(line, indent, type, parent)
    stack = []          # open declarations [decl_index, depth]
    depth = 0
    owner_by_line = {}

    for idx, line in enumerate(lines, 1):
        stripped = line.strip()
        if not stripped:
            continue
        indent = len(line) - len(line.lstrip())
        decl = DECL.match(stripped)
        owner_by_line[idx] = stack[-1][0] if stack else None
        i = 0
        s = None
        opened_decl = False
        while i < len(stripped):
            ch = stripped[i]
            if s:
                if ch == "\\":
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
            if ch == "{":
                depth += 1
                if decl and not opened_decl:
                    parent_index = stack[-1][0] if stack else None
                    decls.append({
                        "line": idx, "indent": indent, "type": decl.group(1),
                        "parent": parent_index,
                    })
                    stack.append([len(decls) - 1, depth])
                    opened_decl = True
                    owner_by_line[idx] = len(decls) - 1
                else:
                    stack.append([None, depth])
            elif ch == "}":
                while stack and stack[-1][1] >= depth:
                    stack.pop()
                depth -= 1
            i += 1

    # Collect property -> (line, kind) per owner object.
    owners = {}
    for idx, line in enumerate(lines, 1):
        stripped = line.strip()
        m = ASSIGN.match(stripped)
        if not m:
            continue
        owner = owner_by_line.get(idx)
        if owner is None:
            continue
        key = m.group(1)
        if key == "id":
            continue
        kind = "handler" if key.startswith("on") and key[2].isupper() else "property"
        owners.setdefault(owner, {}).setdefault(key, []).append((idx, kind))

    findings = []
    for oi, props in owners.items():
        for key, hits in props.items():
            kinds = {k for _, k in hits}
            if len(hits) > 1:
                # Report one line per duplicate occurrence beyond the first.
                for line_no, kind in hits[1:]:
                    findings.append((line_no, decls[oi]["type"], key, kind))
    return findings


def main():
    root_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    total = 0
    for path in sorted(glob.glob(os.path.join(root_dir, "**", "*.qml"), recursive=True)):
        rel = os.path.relpath(path, root_dir)
        found = scan(path)
        if not found:
            continue
        print("--- " + rel)
        for line_no, obj_type, prop, kind in found:
            print("   line %4d  %s  %s -> %s" % (line_no, obj_type, kind, prop))
        total += len(found)
    if total == 0:
        print("OK: no duplicate QML property assignments on the same object")
    else:
        print("\n%d duplicate property assignment(s) found" % total)
    return 1 if total else 0


if __name__ == "__main__":
    sys.exit(main())