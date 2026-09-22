#!/usr/bin/env python3
"""Focused login submission, error, and busy-state checks."""
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
login = (ROOT / "components/LoginDialog.qml").read_text()
panel = (ROOT / "Panel.qml").read_text()

def check(name, condition):
    if not condition:
        raise AssertionError(name)
    print(f"PASS {name}")

check("Enter submission has one shared path", "function submit()" in login and login.count("onAccepted: root.submit()") == 3)
check("empty form is not submitted", "if (!serverField.text.trim() || !emailField.text.trim() || !passwordField.text) return" in login)
check("login errors are displayed", "property string _raw: root.errorMessage" in login and "errorMessage: root.errorMessage" in panel)
check("busy login disables submit", "enabled: !root.loading" in login and "if (root.loading) return" in login)
check("busy state is visible", 'text: root.loading ? "Connecting…" : "Connect"' in login)
check("Escape still dismisses login", login.count("root.onDismiss()") == 3)
print("=== login contract checks passed ===")
