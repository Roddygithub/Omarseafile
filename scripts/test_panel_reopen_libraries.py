#!/usr/bin/env python3
"""
Regression test for panel reopen library loading.

Verifies that Panel.open() calls loadLibraries() when libraries array is empty,
and does NOT reload when libraries are already populated.
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


def func_body(src, name):
    """Extract the body of a function by name from source."""
    start = src.index("function " + name + "(")
    open_brace = src.index("{", start)
    depth = 0
    i = open_brace
    while i < len(src):
        if src[i] == "{":
            depth += 1
        elif src[i] == "}":
            depth -= 1
            if depth == 0:
                return src[start:i + 1]
        i += 1
    return src[start:]


def test_panel_open_reloads_when_libraries_empty():
    """Panel.open() should call loadLibraries() when libraries is empty."""
    src = read_file("Panel.qml")
    open_func = func_body(src, "open")
    # Check for the conditional loadLibraries call
    has_check = "if (!root.libraries || root.libraries.length === 0)" in open_func
    has_call = "root.loadLibraries()" in open_func
    test("Panel.open() checks if libraries is empty", has_check)
    test("Panel.open() calls loadLibraries() when empty", has_check and has_call)


def test_panel_open_does_not_reload_when_libraries_populated():
    """Panel.open() should NOT reload libraries when already populated."""
    src = read_file("Panel.qml")
    open_func = func_body(src, "open")
    # The loadLibraries call should be inside the conditional, not unconditional
    # The open function should NOT have an unconditional loadLibraries() call
    unconditional_load = open_func.count("root.loadLibraries()") == 1
    test("Panel.open() calls loadLibraries() exactly once (conditionally)", unconditional_load)


def test_load_libraries_function_exists():
    """Ensure loadLibraries function exists and is callable."""
    src = read_file("Panel.qml")
    test("loadLibraries function exists", "function loadLibraries()" in src)


if __name__ == "__main__":
    import sys
    sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    
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
    
    # Change to repo root for file reading
    import os
    os.chdir(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    
    test_load_libraries_function_exists()
    test_panel_open_reloads_when_libraries_empty()
    test_panel_open_does_not_reload_when_libraries_populated()
    
    print(f"\n=== {passed} passed, {failed} failed ===")
    sys.exit(1 if failed else 0)