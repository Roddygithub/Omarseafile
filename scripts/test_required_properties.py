#!/usr/bin/env python3
"""Every required property an instantiation receives must actually be supplied.

A missing `required property` assignment is a load-time QML failure: the
component never gets created and the panel renders an empty slot instead of
the view. This walks every `Component { id: ... }` block in the QML sources
and compares the assigned properties with the declared contract of the
component the block instantiates.

`modelData` is excluded: Repeater/DelegateModel inject it into delegates and
the owning component never assigns it.
"""
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCES = {p.stem: p for p in sorted(list((ROOT / "components").glob("*.qml")) + list((ROOT / "views").glob("*.qml")))}
TARGETS = sorted(
    [ROOT / "Panel.qml", ROOT / "BarWidget.qml"]
    + list((ROOT / "components").glob("*.qml"))
    + list((ROOT / "views").glob("*.qml"))
)

INJECTED = {"modelData"}
failed = []


def check(name, ok, detail=""):
    print(("PASS " if ok else "FAIL ") + name + ((" -> " + detail) if (detail and not ok) else ""))
    if not ok:
        failed.append(name)


def match_block(src, start):
    depth = 0
    for i in range(start, len(src)):
        if src[i] == "{":
            depth += 1
        elif src[i] == "}":
            depth -= 1
            if depth == 0:
                return src[start:i + 1]
    return None


def object_body(src, open_brace):
    """Inner text of the object literal opened at open_brace, with nested
    object literals removed so only direct children remain."""
    depth = 0
    end = None
    for i in range(open_brace, len(src)):
        if src[i] == "{":
            depth += 1
        elif src[i] == "}":
            depth -= 1
            if depth == 0:
                end = i
                break
    if end is None:
        return ""
    inner = src[open_brace + 1:end]
    out, depth = [], 0
    for ch in inner:
        if ch == "{":
            depth += 1
        elif ch == "}":
            depth = max(0, depth - 1)
        elif depth == 0:
            out.append(ch)
    return "".join(out)


def instantiated_object(body):
    """Locate `Type {` inside a Component block; returns (type, brace_index)."""
    offset = 0
    for line in body.splitlines(keepends=True):
        stripped = line.strip()
        if not stripped or stripped.startswith("//") or stripped == "Component {" or re.fullmatch(r"id:\s*\w+", stripped):
            offset += len(line)
            continue
        obj = re.match(r"\s*(\w+)\s*\{", line)
        if obj:
            return obj.group(1), offset + line.index("{", obj.end(1))
        offset += len(line)
    return None, None


def component_blocks(src):
    for match in re.finditer(r"Component \{", src):
        body = match_block(src, match.start())
        if not body:
            continue
        block_id = re.search(r"\bid:\s*(\w+)", body)
        type_name, brace = instantiated_object(body)
        if block_id and type_name:
            yield block_id.group(1), type_name, body, brace


checked = 0
for target in TARGETS:
    src = target.read_text()
    for block_id, type_name, body, brace in component_blocks(src):
        source = SOURCES.get(type_name)
        if source is None:
            continue  # QtQuick builtin or a component with no required contract
        required = set(re.findall(r"required property \w+ (\w+)", source.read_text())) - INJECTED
        direct = object_body(body, brace)
        supplied = {name for name in required if re.search(r"^\s*%s\s*:" % re.escape(name), direct, re.M)}
        checked += 1
        missing = sorted(required - supplied)
        label = "%s: %s -> %s" % (target.relative_to(ROOT), block_id, type_name)
        check(label + " supplies " + (", ".join(sorted(required)) or "(no required properties)"),
              not missing, "missing: " + ", ".join(missing))

if checked == 0:
    raise SystemExit("FAILED: no Panel component blocks were matched")
if failed:
    raise SystemExit("FAILED: " + "; ".join(failed))
print("=== required property wiring checks passed (%d blocks) ===" % checked)
