#!/usr/bin/env python3
"""Release checks never install anything, leak credentials, or repeat successful notices."""
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import tempfile
from unittest.mock import patch

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("check_update", ROOT / "js/check_update.py")
u = importlib.util.module_from_spec(spec)
spec.loader.exec_module(u)

assert u.version("v1.2.10") > u.version("1.2.9")
for invalid in (None, "", "1.2", "1.2.3-beta", "1.2.3;id", "v9999.1.1", [], {}):
    assert u.version(invalid) is None

with patch.object(u.urllib.request, "urlopen", return_value=io.BytesIO(json.dumps({"tag_name": "v1.2.10"}).encode())) as http:
    assert u.latest("Roddygithub/OmaPiP") == "1.2.10"
    request = http.call_args.args[0]
    assert request.full_url == "https://api.github.com/repos/Roddygithub/OmaPiP/releases/latest"
    assert not request.has_header("Authorization")
with patch.object(u.urllib.request, "urlopen", return_value=io.BytesIO(b"x" * 65537)):
    try:
        u.latest("Roddygithub/OmaPiP")
        raise AssertionError("unbounded response accepted")
    except ValueError:
        pass
for release in ({"tag_name": "v1.3.0", "draft": True}, {"tag_name": "v1.3.0", "prerelease": True}, {"tag_name": "v1.3.0-rc1"}):
    with patch.object(u.urllib.request, "urlopen", return_value=io.BytesIO(json.dumps(release).encode())):
        assert u.latest("Roddygithub/OmaPiP") == ""

for plugin in u.PLUGINS:
    with tempfile.TemporaryDirectory() as state, patch.object(u, "latest", return_value="1.2.10") as fetch, patch.object(u.subprocess, "run", return_value=subprocess.CompletedProcess([], 0)) as notify:
        def check(installed="1.2.9", now=100000):
            return u.check(plugin, installed, "Update available", "Version %1. Run: %2", state_home=state, now=now)
        assert check() == "1.2.10"
        assert fetch.call_count == 1 and notify.call_count == 1
        argv = notify.call_args.args[0]
        assert argv[-1] == "Version 1.2.10. Run: omarchy plugin update " + plugin
        assert "shell" not in notify.call_args.kwargs
        assert check(now=100001) == "1.2.10"
        assert fetch.call_count == 1 and notify.call_count == 1
        assert check(installed="1.2.10", now=100002) == ""
        fetch.side_effect = OSError("offline or rate-limited")
        assert check(now=200000) == "1.2.10"
        assert notify.call_count == 1
        assert check(now=200001) == "1.2.10" and fetch.call_count == 2
    with tempfile.TemporaryDirectory() as state, patch.object(u, "latest", return_value="1.2.10") as fetch, patch.object(u.subprocess, "run", side_effect=FileNotFoundError()):
        assert u.check(plugin, "1.2.9", "Update", "%1 %2", state_home=state, now=100000) == "1.2.10"
        stored = json.loads((Path(state) / plugin / "update.json").read_text())
        assert "notified" not in stored  # Retried later; visible in the bar meanwhile.
print("PASS update versions, bounded responses, daily cache, offline handling and notification deduplication")
