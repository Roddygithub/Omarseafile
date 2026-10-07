#!/usr/bin/env python3
"""Headless behavioral regression test for the Open Local handoff lifecycle."""
import os
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OPEN_HELPER = os.path.join(ROOT, "scripts", "open_cached_file.sh")
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

    # Exercise the exact production launcher instead of a copied shell snippet:
    # the transfer service must build the helper path with the shared decoder
    # that these probes rely on for paths containing spaces, "%" and "#".
    transfer_service = open(os.path.join(ROOT, "js", "TransferService.qml"), encoding="utf-8").read()
    safe_path = open(os.path.join(ROOT, "js", "SafePath.qml"), encoding="utf-8").read()
    if ('_scriptsDir + "/open_cached_file.sh"' not in transfer_service
            or 'SafePath.toLocalFile(Qt.resolvedUrl("../scripts"))' not in transfer_service
            or "function toLocalFile" not in safe_path
            or "decodeURIComponent(" not in safe_path):
        raise AssertionError("TransferService does not resolve the tested Open Local helper through the shared decoder")

    fallback_dir = os.path.join(temp, "fallback-bin")
    os.mkdir(fallback_dir)
    with open(os.path.join(fallback_dir, "setsid"), "w", encoding="utf-8") as f:
        f.write("#!/bin/sh\nexec /usr/bin/setsid \"$@\"\n")
    with open(os.path.join(fallback_dir, "xdg-mime"), "w", encoding="utf-8") as f:
        f.write("#!/bin/sh\n[ \"$2\" = default ] && printf 'probe-handler.desktop\\n' && exit 0\nprintf 'application/pdf\\n'\n")
    with open(os.path.join(fallback_dir, "uwsm-app"), "w", encoding="utf-8") as f:
        f.write("#!/bin/sh\nprintf 'unexpected-uwsm\\n' > \"$OPEN_PROBE_PID_DIR/fallback.txt\"\nexit 1\n")
    with open(os.path.join(fallback_dir, "xdg-open"), "w", encoding="utf-8") as f:
        f.write("#!/bin/sh\nprintf '%s\\n' \"$1\" > \"$OPEN_PROBE_PID_DIR/fallback.txt\"\n")
    for name in ("setsid", "xdg-mime", "uwsm-app", "xdg-open"):
        os.chmod(os.path.join(fallback_dir, name), 0o700)
    fallback_env = env.copy()
    fallback_env.update({"PATH": fallback_dir, "OPEN_PROBE_PID_DIR": pid_dir})
    fallback_path = "/probe folder/100% # file.txt"
    fallback_result = subprocess.run(
        ["/usr/bin/bash", OPEN_HELPER, fallback_path],
        env=fallback_env, capture_output=True, check=False
    )
    fallback_marker = os.path.join(pid_dir, "fallback.txt")
    fallback_used = fallback_result.returncode == 0 and os.path.exists(fallback_marker) \
        and open(fallback_marker, encoding="utf-8").read().rstrip("\n") == fallback_path

    missing_mime_dir = os.path.join(temp, "missing-mime-bin")
    os.mkdir(missing_mime_dir)
    with open(os.path.join(missing_mime_dir, "xdg-open"), "w", encoding="utf-8") as f:
        f.write("#!/bin/sh\nprintf '%s\\n' \"$1\" > \"$OPEN_PROBE_PID_DIR/missing-mime.txt\"\n")
    os.chmod(os.path.join(missing_mime_dir, "xdg-open"), 0o700)
    missing_mime_env = env.copy()
    missing_mime_env.update({"PATH": missing_mime_dir, "OPEN_PROBE_PID_DIR": pid_dir})
    missing_mime_result = subprocess.run(
        ["/usr/bin/bash", OPEN_HELPER, "/probe-missing-mime"],
        env=missing_mime_env, capture_output=True, check=False
    )
    missing_mime_marker = os.path.join(pid_dir, "missing-mime.txt")
    missing_mime_used = missing_mime_result.returncode == 0 and os.path.exists(missing_mime_marker) \
        and open(missing_mime_marker, encoding="ascii").read().strip() == "/probe-missing-mime"

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
if not fallback_used:
    failed.append("xdg-open fallback was not used when the UWSM launcher failed")
if not missing_mime_used:
    failed.append("xdg-open fallback was not used when xdg-mime was missing")
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
