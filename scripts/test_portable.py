#!/usr/bin/env python3
"""Portable CI suite: no Omarchy or Quickshell executable is required.

This is the complete portable gate. `.github/workflows/validate.yml` invokes
`./scripts/validate.sh`, which runs this file, so every suite listed here is
enforced on CI rather than only when someone remembers to run it by hand.

Suites that genuinely need a Quickshell runtime live in validate.sh behind a
`command -v qs` guard and are reported as SKIP when it is absent.
"""
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

tests = [
    # Security regressions.
    "test_secure_output.py",
    "test_finding2.py",
    "test_finding4.py",
    "test_finding5.py",
    "test_finding6.py",
    "test_finding7.py",
    "test_security_fixes.py",
    "test_remediation.py",
    # QML structural / runtime-warning regressions. These were previously only
    # runnable manually, which is how a green gate coexisted with a panel that
    # failed to load.
    "test_qml_warnings.py",
    "test_panel_reopen_libraries.py",
    # v1.1 remediation: favourites identity/account scope, HTTP status
    # classification, bounded upload queue, logout race, zenity path pipeline,
    # keyboard architecture, foldersFirst, URL policy, metadata.
    "test_v11_remediation.py",
    # Duplicate QML property assignment sweep (wired via validate.sh and the
    # v1.1 suite; listed explicitly so CI runs it directly too).
    "test_duplicate_properties.py",
]

failed = []
for test in tests:
    print("\n### %s" % test)
    result = subprocess.run([sys.executable, os.path.join(ROOT, "scripts", test)])
    if result.returncode:
        failed.append(test)

if failed:
    print("\n=== portable CI suite FAILED: %s ===" % ", ".join(failed))
    sys.exit(1)
print("\n=== portable CI suite passed (%d suites) ===" % len(tests))
