#!/usr/bin/env python3
"""Switch all display languages in one isolated Quickshell process, without changing the desktop."""
import json
import os
from pathlib import Path
import queue
import shutil
import subprocess
import tempfile
import threading
import time

ROOT = Path(__file__).resolve().parent.parent
if not shutil.which("qs"):
    print("SKIP live language changes: Quickshell is not installed")
    raise SystemExit(0)
registry = json.loads((ROOT / "js/locales/registry.json").read_text())
with tempfile.TemporaryDirectory(prefix="plugin language test ") as temporary:
    package = Path(temporary)
    shutil.copytree(ROOT / "js", package / "js", ignore=shutil.ignore_patterns("__pycache__"))
    manifest = json.loads((ROOT / "manifest.json").read_text())
    (package / "manifest.json").write_text(json.dumps(manifest))
    # Exercise the real UpdateService QML/process wiring without a network request
    # or a desktop notification. Only its external release probe is replaced.
    (package / "js/check_update.py").write_text(
        "import sys\nassert sys.argv[1:3] == " + repr([manifest["id"], manifest["version"]])
        + "\nassert len(sys.argv) == 5\nprint('9.9.9')\n")
    choice = package / "language"
    choice.write_text("en\n")
    qml = package / "shell.qml"
    qml.write_text('''import QtQuick
import Quickshell
import "./js"
ShellRoot {
    id: root
    Component.onCompleted: UpdateService.enabled = true
    property string lastLanguage: ""
    readonly property string observedLanguage: L10n.language
    Timer {
        interval: 50
        repeat: true
        running: true
        onTriggered: {
            if (!UpdateService.available || root.lastLanguage === root.observedLanguage) return
            root.lastLanguage = L10n.language
            console.log("LOCALE_RUNTIME " + JSON.stringify({language: L10n.language,
                text: L10n.t("Close"), update: UpdateService.notice, rtl: L10n.rightToLeft, format: L10n.formatLocale}))
            if (L10n.language === "pt-BR") {
                UpdateService.enabled = false
                UpdateService.check()
                console.log("UPDATES_DISABLED " + JSON.stringify({available: UpdateService.available, running: UpdateService.checker.running}))
            }
        }
    }
}
''')
    process = subprocess.Popen(["qs", "--path", str(qml)], stdout=subprocess.PIPE,
                               stderr=subprocess.STDOUT, text=True,
                               env={**os.environ, "QT_QPA_PLATFORM": "offscreen", "OMARCHY_LANGUAGE_FILE": str(choice)})
    output = queue.Queue()
    def read_output():
        for line in process.stdout:
            output.put(line)
    threading.Thread(target=read_output, daemon=True).start()
    log = []
    try:
        for language, entry in registry.items():
            choice.write_text(language + "\n")
            end = time.monotonic() + 5
            while True:
                try:
                    line = output.get(timeout=max(0.01, end - time.monotonic()))
                except queue.Empty:
                    raise AssertionError("No live update for " + language + "\n" + "".join(log[-15:]))
                log.append(line)
                assert not any(error in line for error in ("ReferenceError:", "TypeError:", "Failed to load configuration")), line
                if "LOCALE_RUNTIME " not in line:
                    continue
                data = json.loads(line.split("LOCALE_RUNTIME ", 1)[1])
                if data["language"] != language:
                    continue
                expected = json.loads((ROOT / "js/locales" / f"{language}.json").read_text())["Close"]
                assert data["text"] == expected, data
                strings = json.loads((ROOT / "js/locales" / f"{language}.json").read_text())
                notice = strings["Update available: v%1 — %2"].replace("%1", "9.9.9").replace("%2", "omarchy plugin update " + manifest["id"])
                assert data["update"] == notice, data
                assert data["rtl"] == (language in ("ar", "fa", "he", "ur")), data
                assert data["format"] == entry["formatLocale"], data
                break
        while True:
            line = output.get(timeout=5)
            if "UPDATES_DISABLED " in line:
                assert json.loads(line.split("UPDATES_DISABLED ", 1)[1]) == {"available": False, "running": False}
                break
    finally:
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()
print("PASS 50 live language changes, RTL, display locales and translated update indicators")
