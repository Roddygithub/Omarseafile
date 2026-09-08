#!/usr/bin/env python3
"""Quickshell-only remediation checks; not part of portable CI."""
import os
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FINALIZE = os.path.join(ROOT, "scripts", "secure_finalize.py")
qs = shutil.which("qs")
if not qs:
    print("SKIP: qs is required for runtime remediation tests")
    sys.exit(0)

with tempfile.TemporaryDirectory() as temp:
    package_dir = os.path.join(temp, "package")
    os.mkdir(package_dir)
    for name in ("test_remediation.qml", "Panel.qml", "components", "js", "scripts"):
        os.symlink(os.path.join(ROOT, name), os.path.join(package_dir, name))
    os.symlink("/usr/share/omarchy/shell/Ui", os.path.join(package_dir, "Ui"))
    os.symlink("/usr/share/omarchy/shell/Commons", os.path.join(package_dir, "Commons"))
    bin_dir = os.path.join(temp, "bin")
    os.mkdir(bin_dir)
    xdg_open = os.path.join(bin_dir, "xdg-open")
    with open(xdg_open, "w", encoding="utf-8") as f:
        f.write("#!/bin/sh\ncase \"$1\" in\n  /probe-failure) exit 1 ;;\n  /probe-cancel|/probe-logout|*/open_runtime_protected) exec python3 -c 'import signal; signal.pause()' ;;\n  *) exit 0 ;;\nesac\n")
    os.chmod(xdg_open, 0o700)
    xdg_user_dir = os.path.join(bin_dir, "xdg-user-dir")
    with open(xdg_user_dir, "w", encoding="utf-8") as f:
        f.write("#!/bin/sh\nsleep 1\nprintf '%s\\n' \"$HOME/Downloads\"\n")
    os.chmod(xdg_user_dir, 0o700)
    env = os.environ.copy()
    env["XDG_CACHE_HOME"] = os.path.join(temp, "fresh-cache-root")
    env["PATH"] = bin_dir + os.pathsep + env["PATH"]
    cache_dir = os.path.join(env["XDG_CACHE_HOME"], "omarseafile")
    os.makedirs(cache_dir, mode=0o700)
    source = os.path.join(cache_dir, "dl_runtime_source")
    with open(source, "wb") as f:
        f.write(b"payload")
    os.chmod(source, 0o600)
    finalized = subprocess.run([sys.executable, FINALIZE, cache_dir, "dl_runtime_source", "open_runtime_protected"], capture_output=True)
    if finalized.returncode != 0:
        print("FAIL: runtime cache probe finalization failed")
        sys.exit(1)
    result = subprocess.run(["timeout", "7", qs, "--path", os.path.join(package_dir, "test_remediation.qml")], capture_output=True, timeout=10, env=env)
output = (result.stdout + result.stderr).decode(errors="replace")
checks = [
    "reserved=2684354560",
    "released=0",
    "deep=false",
    "libraryKeys=true",
    "visualRange=3",
    "freshCache=true",
    "pendingOpenCancelled=true",
    "xdgOpenFailed=true",
    "xdgOpenCancel=true",
    "xdgOpenLogout=true",
    "xdgOpenReleased=true",
        "xdgOpenSuccess=true",
        "accountSwitchSafe=true",
        "openingCacheProtected=true",
        "protectionReleased=true",
]
failed = [check for check in checks if check not in output]
if result.returncode != 0:
    failed.append("qs exit=" + str(result.returncode))
if "SENTINEL_SESSION_" in output:
    failed.append("session sentinel leaked to runtime output")
if failed:
    print("FAIL: " + ", ".join(failed))
    print(output)
    sys.exit(1)
print("=== runtime remediation checks passed ===")
