#!/usr/bin/env python3
"""Focused login submission, error, and busy-state checks."""
from pathlib import Path
import os
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent
login = (ROOT / "components/LoginDialog.qml").read_text()
panel = (ROOT / "Panel.qml").read_text()

def check(name, condition):
    if not condition:
        raise AssertionError(name)
    print(f"PASS {name}")

check("Enter submission has one shared path", "function submit()" in login and login.count("onAccepted: root.submit()") == 3)
check("empty fields show inline validation and are not submitted",
      'root.validationMessage = "Enter your Seafile server URL."' in login
      and 'root.validationMessage = "Enter your email address."' in login
      and 'root.validationMessage = "Enter your password."' in login
      and "root.onLogin(serverField.text, emailField.text.trim(), passwordField.text)" in login)
check("login errors are displayed", "root.validationMessage || errorText._raw" in login and "errorMessage: root.errorMessage" in panel)
check("busy login disables submit", "enabled: !root.loading" in login and "if (root.loading) return" in login)
check("busy state is visible", 'text: root.loading ? "Connecting…" : "Connect"' in login)
check("Escape still dismisses login", login.count("root.onDismiss()") == 3)
print("=== login contract checks passed ===")

# Exercise the real dialog and shell controls, without a server or credentials.
qs = shutil.which("qs")
shell = Path("/usr/share/omarchy/shell")
if not qs or not (shell / "Ui").is_dir():
    print("SKIP login keyboard runtime checks: Quickshell and Omarchy required")
else:
    with tempfile.TemporaryDirectory(prefix="omarseafile-login-") as temp:
        package = Path(temp)
        for name in ("components", "js"):
            (package / name).symlink_to(ROOT / name)
        for name in ("Ui", "Commons"):
            (package / name).symlink_to(shell / name)
        shutil.copyfile(ROOT / "scripts/tst_login.qml", package / "test.qml")
        runtime = package / "runtime"
        runtime.mkdir(mode=0o700)
        env = dict(os.environ, QT_QPA_PLATFORM="offscreen",
                   QT_QPA_PLATFORMTHEME="generic", QT_QUICK_CONTROLS_STYLE="Basic",
                   XDG_RUNTIME_DIR=str(runtime), XDG_CACHE_HOME=str(package / "cache"))
        env.pop("WAYLAND_DISPLAY", None)
        result = subprocess.run([qs, "--path", str(package / "test.qml")],
                                env=env, capture_output=True, text=True, timeout=20)
    output = result.stdout + result.stderr
    if result.returncode or "LOGIN_KEYBOARD_OK" not in output or "LOGIN_KEYBOARD_FAILED" in output:
        raise AssertionError(output)
    print("PASS real Qt Enter/Return, single submission, validation, busy/retry and Escape")
