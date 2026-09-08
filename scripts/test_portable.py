#!/usr/bin/env python3
"""Portable CI suite: no Omarchy or Quickshell executable is required."""
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
tests = [
    "test_secure_output.py",
    "test_finding2.py",
    "test_finding4.py",
    "test_finding5.py",
    "test_finding6.py",
    "test_finding7.py",
    "test_security_fixes.py",
    "test_remediation.py",
]
for test in tests:
    result = subprocess.run([sys.executable, os.path.join(ROOT, "scripts", test)])
    if result.returncode:
        sys.exit(result.returncode)
print("=== portable CI suite passed ===")
