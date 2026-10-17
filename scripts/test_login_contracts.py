#!/usr/bin/env python3
"""Focused login submission, error, and busy-state checks."""
from pathlib import Path
import os
import shutil
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parent.parent
login = (ROOT / "components/LoginDialog.qml").read_text()
panel = (ROOT / "Panel.qml").read_text()

def check(name, condition):
    if not condition:
        raise AssertionError(name)
    print(f"PASS {name}")

check("Enter submission has one shared path",
      "function submit()" in login
      and login.count("event.key === Qt.Key_Return || event.key === Qt.Key_Enter") == 1
      and login.count("root.handleKeys(") == 3)
check("empty fields show inline validation and are not submitted",
      'root.validationMessage = "Enter your Seafile server URL."' in login
      and 'root.validationMessage = "Enter your email address."' in login
      and 'root.validationMessage = "Enter your password."' in login
      and "root.onLogin(serverField.text, emailField.text.trim(), passwordField.text)" in login)
check("login errors are displayed", "root.validationMessage || errorText._raw" in login and "errorMessage: root.errorMessage" in panel)
check("busy login disables submit", "enabled: !root.loading" in login and "if (root.loading) return" in login)
check("busy state is visible", 'text: root.loading ? "Connecting…" : "Connect"' in login)
check("Escape still dismisses login", login.count("root.onDismiss()") == 3)
check("Qt text inputs stay read-only and intercept explicit paste",
      login.count("readOnly: true") == 3
      and login.count("root.isPasteShortcut(event)") == 1
      and "event.key === Qt.Key_V" in login
      and "Qt.ShiftModifier) && event.key === Qt.Key_Insert" in login
      and login.count("acceptedButtons: Qt.MiddleButton") == 3
      and login.count("root.requestPaste(field, false)") == 1
      and login.count("root.requestPaste(field, true)") == 1
      and all(login.count("root.handleKeys(%s, event)" % f) == 1 for f in ("serverField", "emailField", "passwordField")))
check("native Qt paste is unreachable", ".paste(" not in login and login.count("readOnly: true") == 3)
check("clipboard reads are capped and deadlined before entering Qt",
      "set -o pipefail" in login
      and "timeout -s KILL" in login
      and "wl-paste" in login
      and "head -c" in login
      and "root.pasteMaxBytes + 1" in login
      and "readonly property int pasteMaxBytes: 16384" in login
      and 'readonly property string pasteDeadlineSeconds: "2"' in login
      and "pasteByteLength(text) > root.pasteMaxBytes" in login)
check("oversized, stalled and missing-tool pastes are reported and rejected",
      "exceeds the 16 KiB limit." in login
      and "Clipboard read timed out." in login
      and "wl-clipboard (wl-paste)" in login
      and "Paste unavailable (exit" in login)
check("guarded reads run out-of-process with collected stdout",
      "stdout: StdioCollector {}" in login and "Process {" in login)
# Exercise the exact producer-side pipeline with a flooding producer and a
# producer that never exits. StdioCollector only sees at most cap + 1 bytes.
with tempfile.TemporaryDirectory(prefix="omarseafile-paste-") as temp:
    bindir = Path(temp)
    fake_wl_paste = bindir / "wl-paste"
    pipeline = ["bash", "-c",
                "set -o pipefail; timeout -s KILL 2 wl-paste --no-newline "
                "--type text/plain | head -c 16385"]
    check("production uses wl-paste's documented MIME option", "--type text/plain" in login)
    fake_wl_paste.write_text(
        "#!/usr/bin/env python3\nimport os\n"
        "while True: os.write(1, b'x' * 8192)\n", encoding="utf-8")
    fake_wl_paste.chmod(0o700)
    env = dict(os.environ, PATH=temp + os.pathsep + os.environ["PATH"])
    result = subprocess.run(pipeline, env=env, capture_output=True, timeout=5)
    check("flooding clipboard producer cannot exceed cap + 1 byte", len(result.stdout) == 16385)

    fake_wl_paste.write_text("#!/bin/sh\nexec sleep 10\n", encoding="utf-8")
    fake_wl_paste.chmod(0o700)
    started = time.monotonic()
    result = subprocess.run(pipeline, env=env, capture_output=True, timeout=5)
    elapsed = time.monotonic() - started
    check("stalled clipboard producer is killed by the deadline",
          result.returncode != 0 and elapsed < 4)
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
    print("PASS real Qt Enter/Return, single submission, validation, busy/retry, Escape and bounded paste")
