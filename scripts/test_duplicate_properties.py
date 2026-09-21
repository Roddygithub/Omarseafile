#!/usr/bin/env python3
"""Portable duplicate-QML-property sweep (STATIC)."""
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
proc = subprocess.run(
    [sys.executable, os.path.join(ROOT, "scripts", "check_duplicate_properties.py")],
    capture_output=True, text=True,
)
sys.stdout.write(proc.stdout)
if proc.returncode != 0:
    print("=== duplicate QML property check FAILED ===")
    sys.exit(1)
print("=== duplicate QML property check passed ===")