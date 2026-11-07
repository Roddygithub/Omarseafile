#!/usr/bin/env python3
"""Bounded, credential-free release checks; one notice per release across monitors/restarts."""
import fcntl
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import time
import urllib.request

PLUGINS = {
    "roddy.seafile": "Roddygithub/Omarseafile",
    "io.github.roddygithub.omapip": "Roddygithub/OmaPiP",
}
INTERVAL = 86400


def version(tag):
    if not isinstance(tag, str) or not re.fullmatch(r"v?[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}", tag):
        return None
    return tuple(map(int, tag.removeprefix("v").split(".")))


def latest(repo):
    request = urllib.request.Request(
        "https://api.github.com/repos/" + repo + "/releases/latest",
        headers={"Accept": "application/vnd.github+json", "User-Agent": "Omarchy-plugin-update-check"},
    )
    with urllib.request.urlopen(request, timeout=15) as response:
        raw = response.read(65537)
    if len(raw) > 65536:
        raise ValueError("Release response too large")
    release = json.loads(raw)
    if not isinstance(release, dict):
        raise ValueError("Invalid release response")
    if release.get("draft") or release.get("prerelease"):
        return ""
    tag = release.get("tag_name")
    return tag.removeprefix("v") if version(tag) else ""


def save(path, state):
    fd, temporary = tempfile.mkstemp(dir=path.parent)
    try:
        with os.fdopen(fd, "w") as stream:
            json.dump(state, stream)
        os.replace(temporary, path)
    finally:
        Path(temporary).unlink(missing_ok=True)


def check(plugin, installed, title, message, state_home=None, now=None):
    repo = PLUGINS[plugin]
    if not version(installed):
        return ""
    directory = Path(state_home or os.environ.get("XDG_STATE_HOME") or Path.home() / ".local/state") / plugin
    directory.mkdir(parents=True, exist_ok=True)
    path = directory / "update.json"
    with (directory / "update.lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        try:
            state = json.loads(path.read_text())
            if not isinstance(state, dict):
                state = {}
        except (OSError, ValueError):
            state = {}
        now = time.time() if now is None else now
        checked = state.get("checked", 0)
        if not isinstance(checked, (int, float)):
            checked = 0
        if not checked or now < checked or now - checked >= INTERVAL:
            try:
                state["latest"] = latest(repo)
            except (OSError, ValueError, TypeError):
                pass  # Offline/rate-limited: keep a previously discovered release.
            state["checked"] = now
        candidate = state.get("latest", "")
        available = candidate if version(candidate) and version(candidate) > version(installed) else ""
        if available and state.get("notified") != available:
            command = "omarchy plugin update " + plugin
            body = re.sub(r"%([12])", lambda m: available if m[1] == "1" else command, message)
            try:
                result = subprocess.run(["notify-send", "--app-name=" + repo.split("/")[1],
                                         "--urgency=low", "--", title, body],
                                        timeout=5, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                if result.returncode == 0:
                    state["notified"] = available
            except (OSError, subprocess.TimeoutExpired):
                pass  # The bar indicator remains available without desktop notifications.
        save(path, state)
        return available


if __name__ == "__main__":
    try:
        print(check(*sys.argv[1:]))
    except (OSError, ValueError, KeyError, TypeError):
        print("")
