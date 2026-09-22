#!/usr/bin/env python3
"""Focused mutation response contract checks."""
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
api = (ROOT / "js/SeafileAPI.qml").read_text()

def body(name):
    match = re.search(rf"function {name}\([^)]*\)\s*\{{(?P<body>.*?)(?=\n\s*function |\Z)", api, re.S)
    if not match:
        raise AssertionError(f"missing {name}")
    return match.group("body")

def check(name, condition):
    if not condition:
        raise AssertionError(name)
    print(f"PASS {name}")

move = body("moveFolder")
check("moveFolder confirms parsed transport data", "confirmedMutation(data)" in move)
check("moveFolder does not rebuild an obsolete XHR response", "responseText" not in move)
check("confirmedMutation accepts success object", "return data && data.success === true" in body("confirmedMutation"))
check("copyFolder uses parsed transport data", "confirmedMutation(data)" in body("copyFolder"))
check("batch move uses parsed transport data", "function moveItems" in api and "!confirmedMutation(data)" in api)
print("=== mutation contract checks passed ===")
