#!/usr/bin/env python3
"""Deterministic session/cache regressions using the existing QML JS harness."""
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parent.parent
subprocess.run(["node", "scripts/test_session_cache.js"], cwd=root, check=True)
