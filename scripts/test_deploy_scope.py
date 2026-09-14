#!/usr/bin/env python3
"""Regression test for deployment-only scope exclusions."""
import os
import pathlib
import shutil
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent

with tempfile.TemporaryDirectory() as temp:
    target = pathlib.Path(temp) / "plugin"
    env = os.environ.copy()
    env["OMARCHY_PLUGIN_DIR"] = str(target)
    deployed = subprocess.run([str(ROOT / "deploy.sh")], capture_output=True, text=True, env=env)
    if deployed.returncode != 0:
        raise SystemExit("FAIL: deploy did not complete\n" + deployed.stdout + deployed.stderr)
    if (target / ".agents").exists() or (target / ".codex").exists():
        raise SystemExit("FAIL: development metadata was deployed")
    if not (target / "Panel.qml").is_file():
        raise SystemExit("FAIL: runtime plugin file was not deployed")
    checked = subprocess.run([str(ROOT / "deploy.sh"), "--check"], capture_output=True, text=True, env=env)
    if checked.returncode != 0:
        raise SystemExit("FAIL: clean scoped deployment failed parity\n" + checked.stdout + checked.stderr)
    shutil.rmtree(target)

print("=== deployment scope checks passed ===")
