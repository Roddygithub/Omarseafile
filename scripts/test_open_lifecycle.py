#!/usr/bin/env python3
"""Headless behavioral regression test for the Open Local handoff lifecycle."""
import os
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
qs = shutil.which("qs")
if not qs:
    print("SKIP: qs is required for Open Local lifecycle tests")
    sys.exit(0)

with tempfile.TemporaryDirectory() as temp:
    package_dir = os.path.join(temp, "package")
    os.mkdir(package_dir)
    for name in ("test_open_lifecycle.qml", "js", "scripts"):
        os.symlink(os.path.join(ROOT, name), os.path.join(package_dir, name))

    bin_dir = os.path.join(temp, "bin")
    os.mkdir(bin_dir)
    pid_dir = os.path.join(temp, "pids")
    os.mkdir(pid_dir)
    xdg_mime = os.path.join(bin_dir, "xdg-mime")
    with open(xdg_mime, "w", encoding="utf-8") as f:
        f.write("#!/bin/sh\ncase \"$1 $2\" in\n  'query filetype') printf 'text/plain\\n' ;;\n  'query default') printf 'probe-handler.desktop\\n' ;;\n  *) exit 1 ;;\nesac\n")
    os.chmod(xdg_mime, 0o700)
    uwsm_app = os.path.join(bin_dir, "uwsm-app")
    with open(uwsm_app, "w", encoding="utf-8") as f:
        f.write("#!/bin/sh\nprintf '%s\\n' \"$2\" > \"$OPEN_PROBE_PID_DIR/handler.txt\"\ncase \"$3\" in\n  /probe-failure) exit 1 ;;\n  *) printf '%s\\n' \"$$\" > \"$OPEN_PROBE_PID_DIR/${3##*/}.pid\"; exec python3 -c 'import signal; signal.pause()' ;;\nesac\n")
    os.chmod(uwsm_app, 0o700)

    runtime_dir = os.path.join(temp, "runtime")
    cache_root = os.path.join(temp, "cache")
    cache_dir = os.path.join(cache_root, "omarseafile")
    os.mkdir(runtime_dir, mode=0o700)
    os.makedirs(cache_dir, mode=0o700)
    cache_path = os.path.join(cache_dir, "open_lifecycle_probe")
    with open(cache_path, "wb") as f:
        f.write(b"payload")
    os.chmod(cache_path, 0o600)

    env = os.environ.copy()
    env.update({
        "DBUS_SESSION_BUS_ADDRESS": "",
        "DISPLAY": "",
        "OPEN_PROBE_PID_DIR": pid_dir,
        "PATH": bin_dir + os.pathsep + env["PATH"],
        "QT_QPA_PLATFORM": "offscreen",
        "QT_QPA_PLATFORMTHEME": "",
        "QT_STYLE_OVERRIDE": "Fusion",
        "WAYLAND_DISPLAY": "",
        "XDG_CACHE_HOME": cache_root,
        "XDG_RUNTIME_DIR": runtime_dir,
    })
    result = subprocess.run(
        ["timeout", "8", qs, "--path", os.path.join(package_dir, "test_open_lifecycle.qml")],
        capture_output=True,
        timeout=10,
        env=env,
    )

    live_pids = []
    for name in os.listdir(pid_dir):
        if not name.endswith(".pid"):
            continue
        pid = int(open(os.path.join(pid_dir, name), encoding="ascii").read())
        try:
            os.kill(pid, 0)
        except ProcessLookupError:
            continue
        live_pids.append(pid)
    handler_marker = os.path.join(pid_dir, "handler.txt")
    handler_resolved = os.path.exists(handler_marker) and open(handler_marker, encoding="ascii").read().strip() == "probe-handler.desktop"

output = (result.stdout + result.stderr).decode(errors="replace")
checks = (
    "failureHandled=true",
    "cancelHandled=true",
    "handoffCompleted=true",
    "openingCacheProtected=true",
    "lateExitSafe=true",
    "cacheReleased=true",
)
failed = [check for check in checks if check not in output]
if result.returncode != 0:
    failed.append("qs exit=" + str(result.returncode))
if live_pids:
    failed.append("live helper processes=" + repr(live_pids))
if not handler_resolved:
    failed.append("desktop handler was not resolved and passed as an argv")
if failed:
    print("FAIL: " + ", ".join(failed))
    print(output)
    sys.exit(1)
print("=== Open Local lifecycle checks passed ===")
