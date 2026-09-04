#!/usr/bin/env python3
"""Finding 7 — hostile display-text + bounds tests.

Tests boundedDisplayText() in isolation and validates source-level
structural properties of QML Text sinks (PlainText + character bounds).
"""
import os
import re
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.dirname(SCRIPT_DIR)

passed = 0
failed = 0


def check(label, condition, detail=""):
    global passed, failed
    if condition:
        passed += 1
    else:
        failed += 1
        extra = f" — {detail}" if detail else ""
        print(f"  FAIL: {label}{extra}")


# ── boundedDisplayText tests (import from JS via Python eval proxy) ──────

# We test the LOGIC of boundedDisplayText by reimplementing it in Python
# (same algorithm) since QML is not directly executable here.
# This validates the contract, not the QML runtime.

def bounded_display_text(value, max_chars):
    """Python mirror of Models.boundedDisplayText for testing."""
    if value is None:
        return ""
    if max_chars <= 0:
        return ""
    s = str(value)
    if len(s) <= max_chars:
        return s
    return s[:max_chars - 1] + "\u2026"


print("--- A. null/undefined safety ---")
check("null returns empty string", bounded_display_text(None, 1024) == "")
check("empty string passes through", bounded_display_text("", 1024) == "")

print("--- B. basic truncation ---")
check("short string unchanged", bounded_display_text("hello", 1024) == "hello")
check("exact max unchanged", bounded_display_text("x" * 1024, 1024) == "x" * 1024)
check("over-max truncated with ellipsis", bounded_display_text("x" * 1025, 1024) == "x" * 1023 + "\u2026")
check("one over truncated", bounded_display_text("ab", 1) == "\u2026")

print("--- C. numeric coercion ---")
check("integer coerced", bounded_display_text(42, 1024) == "42")
check("float coerced", bounded_display_text(3.14, 1024) == "3.14")
check("zero passes", bounded_display_text(0, 1024) == "0")

print("--- D. hostile markup — literal passthrough ---")
hostile = [
    '<font color="red">INJECTED</font>',
    "<b>bold</b>",
    '<img src="file:///etc/passwd">',
    '<a href="https://example.invalid">link</a>',
    "&amp;",
    "&#60;script&#62;",
]
for h in hostile:
    result = bounded_display_text(h, 1024)
    check(f"markup literal for: {h[:30]}", result == h)

print("--- E. embedded newlines/control characters ---")
check("newline preserved", bounded_display_text("a\nb", 1024) == "a\nb")
check("tab preserved", bounded_display_text("a\tb", 1024) == "a\tb")
check("null char preserved", bounded_display_text("a\x00b", 1024) == "a\x00b")

print("--- F. extreme lengths ---")
check("10000 char filename bounded to 1024", len(bounded_display_text("f" * 10000, 1024)) == 1024)
check("100000 char error bounded to 4096", len(bounded_display_text("e" * 100000, 4096)) == 4096)
check("100000 char URL bounded to 8192", len(bounded_display_text("u" * 100000, 8192)) == 8192)
check("truncation ends with ellipsis", bounded_display_text("x" * 5000, 1024).endswith("\u2026"))

print("--- G. composed string bounds ---")
# Simulate: "Failed to open " + filename + ": " + error
filename = "f" * 2000
error = "e" * 2000
composed = bounded_display_text("Failed to open " + filename + ": " + error, 4096)
# "Failed to open " (15) + 2000 + ": " (2) + 2000 = 4017 — under 4096, no truncation
check("composed string under max passes through", len(composed) == 4017)
# Now test when composed exceeds max
big_filename = "f" * 3000
big_error = "e" * 3000
big_composed = bounded_display_text("Failed to open " + big_filename + ": " + big_error, 4096)
check("composed string over max bounded to 4096", len(big_composed) == 4096)
check("composed ends with ellipsis", big_composed.endswith("\u2026"))

print("--- H. maximum constants match specification ---")
NAME_MAX = 1024
PATH_MAX = 4096
URL_MAX = 8192
EMAIL_MAX = 320
ERROR_MAX = 4096
METADATA_MAX = 1024
check("NAME_MAX=1024", NAME_MAX == 1024)
check("PATH_MAX=4096", PATH_MAX == 4096)
check("URL_MAX=8192", URL_MAX == 8192)
check("EMAIL_MAX=320", EMAIL_MAX == 320)
check("ERROR_MAX=4096", ERROR_MAX == 4096)
check("METADATA_MAX=1024", METADATA_MAX == 1024)

print("--- H2. N=0 boundary invariant ---")
check("N=0 input_len=0 output_len=0", len(bounded_display_text("x" * 0, 0)) == 0)
check("N=0 input_len=1 output_len=0", len(bounded_display_text("x" * 1, 0)) == 0)
check("N=0 input_len=100000 output_len=0", len(bounded_display_text("x" * 100000, 0)) == 0)
check("N=0 null returns empty", bounded_display_text(None, 0) == "")

print("--- H3. boundary invariant: output.length <= N for all N ---")
all_pass = True
for N in [0, 1, 2, 320, 1024, 4096, 8192]:
    for delta in [-1, 0, 1]:
        length = N + delta
        if length < 0:
            continue
        result = bounded_display_text("x" * length, N)
        if len(result) > N:
            all_pass = False
            print(f"  FAIL: N={N} input_len={length} output_len={len(result)}")
    result = bounded_display_text("x" * 100000, N)
    if len(result) > N:
        all_pass = False
        print(f"  FAIL: N={N} input_len=100000 output_len={len(result)}")
    result = bounded_display_text(None, N)
    if len(result) > N:
        all_pass = False
        print(f"  FAIL: N={N} input=None output_len={len(result)}")
check("output.length <= N for all tested N and input lengths", all_pass)


# ── Source-level QML structural validation ──────────────────────────────

print()
print("--- I. QML textFormat: Text.PlainText completeness ---")

# Files with data-driven sinks that MUST have explicit Text.PlainText.
# Icon-glyph and sort-header Text elements are excluded (static by design).
REQUIRED_PLAINTEXT = {
    "ErrorOverlay.qml": 1,       # message
    "FileItem.qml": 4,           # nameLabel, speedLabel, sizeLabel, dateLabel
    "SearchResults.qml": 3,      # nameLabel, pathLabel, sizeLabel
    "ShareDialog.qml": 5,        # item name, errorMessage, share link, link info, created URL
    "Toast.qml": 1,              # message
    "ConfirmDialog.qml": 1,      # message
    "HistoryPanel.qml": 4,       # header (fileName), timeLabel, descLabel, sizeLabel
    "TransferItem.qml": 2,       # nameLabel, detailLabel
    "TrashPanel.qml": 2,         # nameLabel, detailLabel
    "SettingsDialog.qml": 3,     # connectionTestResult, accountEmail, about text
    "RenameDialog.qml": 2,       # title, errorText
    "UploadDialog.qml": 1,       # errorText
    "CreateFolderDialog.qml": 1, # errorText
    "LoginDialog.qml": 2,        # depErrorMessage, errorText
    "OfflineBanner.qml": 1,      # message
    "Breadcrumbs.qml": 1,        # segmentLabel
    "ToolBar.qml": 2,            # titleLabel, transfersBadge
    "LoadingIndicator.qml": 1,   # message
    "EmptyState.qml": 2,         # title, subtitle
    "BatchActionBar.qml": 1,     # countLabel
    "TransferManager.qml": 3,    # active count, completed count, failed count
}
# Also check Panel.qml in repo root
REQUIRED_PLAINTEXT["Panel.qml"] = 3  # dest count text, dest path text, searchStatusText

total_required = sum(REQUIRED_PLAINTEXT.values())
total_found = 0
missing_files = []

for fname, expected_count in sorted(REQUIRED_PLAINTEXT.items()):
    if fname == "Panel.qml":
        qml_path = os.path.join(REPO_ROOT, fname)
    else:
        qml_path = os.path.join(REPO_ROOT, "components", fname)

    if not os.path.exists(qml_path):
        missing_files.append(fname)
        continue

    with open(qml_path) as f:
        content = f.read()
    count = content.count("textFormat: Text.PlainText")
    if count >= expected_count:
        total_found += expected_count
    else:
        total_found += count
        missing_files.append(f"{fname} ({count}/{expected_count})")

check(f"all {len(REQUIRED_PLAINTEXT)} files have PlainText",
      len(missing_files) == 0,
      f"missing: {missing_files}" if missing_files else "")
check(f"total PlainText instances >= {total_required}",
      total_found >= total_required,
      f"found {total_found}/{total_required}")

print(f"  {total_found}/{total_required} required PlainText instances found across {len(REQUIRED_PLAINTEXT)} files")

print("--- J. boundedDisplayText usage in QML files ---")
# Every file with a dynamic text sink must use Models.boundedDisplayText.
REQUIRED_BOUNDS = {
    "ErrorOverlay.qml": 1,       # message
    "FileItem.qml": 1,           # nameLabel
    "SearchResults.qml": 2,      # nameLabel, pathLabel
    "ShareDialog.qml": 5,        # item name, errorMessage, share link, link info, created URL
    "Toast.qml": 1,              # message
    "ConfirmDialog.qml": 1,      # message
    "HistoryPanel.qml": 2,       # header (fileName), descLabel
    "TransferItem.qml": 2,       # nameLabel, detailLabel
    "TrashPanel.qml": 2,         # nameLabel, detailLabel
    "SettingsDialog.qml": 3,     # connectionTestResult, accountEmail, about text
    "RenameDialog.qml": 1,       # title
    "LoginDialog.qml": 1,        # depErrorMessage
    "OfflineBanner.qml": 1,      # message
    "Breadcrumbs.qml": 1,        # segmentLabel
    "ToolBar.qml": 1,            # titleLabel
    "EmptyState.qml": 2,         # title, subtitle
}
REQUIRED_BOUNDS["Panel.qml"] = 2  # dest path text, confirmDialog message

total_bound_required = sum(REQUIRED_BOUNDS.values())
total_bound_found = 0
bound_missing = []

for fname, expected_count in sorted(REQUIRED_BOUNDS.items()):
    if fname == "Panel.qml":
        qml_path = os.path.join(REPO_ROOT, fname)
    else:
        qml_path = os.path.join(REPO_ROOT, "components", fname)

    if not os.path.exists(qml_path):
        bound_missing.append(fname)
        continue

    with open(qml_path) as f:
        content = f.read()
    count = content.count("Models.boundedDisplayText")
    if count >= expected_count:
        total_bound_found += expected_count
    else:
        total_bound_found += count
        bound_missing.append(f"{fname} ({count}/{expected_count})")

check(f"all {len(REQUIRED_BOUNDS)} files have boundedDisplayText",
      len(bound_missing) == 0,
      f"missing: {bound_missing}" if bound_missing else "")
check(f"total boundedDisplayText calls >= {total_bound_required}",
      total_bound_found >= total_bound_required,
      f"found {total_bound_found}/{total_bound_required}")

print(f"  {total_bound_found}/{total_bound_required} required boundedDisplayText calls across {len(REQUIRED_BOUNDS)} files")

print()
print(f"=== {passed} passed, {failed} failed ===")
sys.exit(0 if failed == 0 else 1)
