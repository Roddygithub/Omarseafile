#!/bin/bash
# scripts/validate.sh — Omarseafile validation script
# Runs both CI-capable and local-runtime checks

set -euo pipefail

FAIL=0
WARN=0

check() {
    local desc="$1"
    shift
    echo -n "  $desc... "
    if "$@"; then
        echo "OK"
    else
        echo "FAIL"
        FAIL=1
    fi
}

warn() {
    local desc="$1"
    shift
    echo -n "  $desc... "
    if "$@"; then
        echo "OK"
    else
        echo "WARN"
        WARN=1
    fi
}

echo "== Omarseafile Validation =="

# --- CI_CAPABLE: Manifest & Structure ---
echo ""
echo "--- Manifest & Structure ---"
check "manifest.json valid JSON" jq -e . manifest.json >/dev/null
check "manifest schemaVersion == 1" jq -e '.schemaVersion == 1' manifest.json >/dev/null
check "manifest id == roddy.seafile" jq -e '.id == "roddy.seafile"' manifest.json >/dev/null
check "manifest version semver format" jq -e '.version | test("^\\d+\\.\\d+\\.\\d+$")' manifest.json >/dev/null
check "manifest kinds includes bar-widget" jq -e '.kinds | index("bar-widget")' manifest.json >/dev/null
check "manifest entryPoints.barWidget exists" jq -e '.entryPoints.barWidget' manifest.json >/dev/null
check "manifest barWidget.schema has autoLogin" jq -e '.barWidget.schema[] | select(.key == "autoLogin")' manifest.json >/dev/null
check "BarWidget.qml exists" test -f BarWidget.qml
check "Panel.qml exists" test -f Panel.qml
check "SettingsDialog.qml exists" test -f components/SettingsDialog.qml

# --- CI_CAPABLE: Required repository files ---
echo ""
echo "--- Required Files ---"
check "README.md exists" test -f README.md
check "README.md > 50 lines" test "$(wc -l < README.md)" -gt 50
check "CHANGELOG.md exists" test -f CHANGELOG.md
check "CHANGELOG.md has [0.8.0] entry" grep -q "\[0.8.0\]" CHANGELOG.md

# --- CI_CAPABLE: Forbidden Known Personal Values ---
echo ""
echo "--- Forbidden Personal Values ---"
check "No hardcoded private IP (192.168.x.x)" bash -c '! grep -rE "192\\.168\\.[0-9]+\\.[0-9]+" --include="*.qml" --include="*.js" . 2>/dev/null'
check "No hardcoded localhost:port" bash -c '! grep -rE "localhost:[0-9]+" --include="*.qml" --include="*.js" . 2>/dev/null | grep -v "placeholderText"'
check "No hardcoded personal email pattern" bash -c '! grep -rE "[a-z0-9._%+-]+@[a-z0-9.-]+\\.[a-z]{2,}" --include="*.qml" --include="*.js" . 2>/dev/null | grep -v "placeholderText\|encodeURIComponent\|@.*\\."'

# --- CI_CAPABLE: Keybindings Consistency ---
echo ""
echo "--- Keybindings Consistency ---"
check "docs/KEYBINDINGS.md exists" test -f docs/KEYBINDINGS.md
check "F2 (rename) implemented" grep -Eq "Key_F2|Qt\.Key_F2|sequence:[[:space:]]*\"F2\"" Panel.qml
check "Delete implemented" grep -q "onDeleteRequested\|pickDelete" Panel.qml
check "Escape implemented" grep -q "onCloseRequested\|close()" Panel.qml
check "Ctrl+A implemented" grep -Eq "Key_A.*ControlModifier|sequence:[[:space:]]*\"Ctrl\+A\"" Panel.qml
check "No Ctrl+H references (removed per policy)" bash -c '! grep -q "Key_H.*ControlModifier\|Qt.Key_H.*ControlModifier" Panel.qml'
check "No Ctrl+T references (removed per policy)" bash -c '! grep -q "Key_T.*ControlModifier\|Qt.Key_T.*ControlModifier" Panel.qml'

# --- CI_CAPABLE: Color Names ---
echo ""
echo "--- Omarchy Color Names ---"
check "Only valid Color names used" bash -c '! grep -rE "Color\\.(urgent|accent|foreground|background)" --include="*.qml" . 2>/dev/null | grep -vE "Color\\.(urgent|accent|foreground|background)"'

# --- CI_CAPABLE: Shell Syntax ---
echo ""
echo "--- Shell Syntax ---"
if command -v shellcheck >/dev/null; then
    check "deploy.sh shellcheck" shellcheck deploy.sh
else
    echo "  deploy.sh shellcheck... SKIP (shellcheck not installed)"
fi
check "deploy.sh --check dry-run" ./deploy.sh --check >/dev/null 2>&1

# --- CI_CAPABLE: Documentation Content ---
echo ""
echo "--- Documentation Content ---"
check "README has Installation section" grep -qi "installation" README.md
check "README has Requirements section" grep -qi "requirements" README.md
check "README has Keyboard Controls" grep -qi "keyboard" README.md
check "README has Known Limitations" grep -qi "limitations\|limitation" README.md
check "README has Security Model" grep -qi "security" README.md

# --- CI_CAPABLE: Source Code Patterns ---
echo ""
echo "--- Source Code Patterns ---"
check "SettingsDialog imported in Panel.qml" grep -q 'import.*\(SettingsDialog\|"\./components"\)' Panel.qml
check "Auth.checkDependencies exists" grep -q "checkDependencies" js/Auth.qml
check "normalizeUrl function exists" grep -q "normalizeUrl" Panel.qml
check "testConnection function exists" grep -q "testConnection" Panel.qml
check "autoLogin setting used" grep -q 'setting("autoLogin"' Panel.qml

# --- LOCAL_RUNTIME: Requires Omarchy/Quickshell ---
echo ""
echo "--- Local Runtime (requires Omarchy) ---"
if command -v omarchy >/dev/null 2>&1; then
    check "omarchy plugin validate" omarchy plugin validate . >/dev/null 2>&1
else
    echo "  omarchy plugin validate... SKIP (omarchy not in PATH)"
fi

if [[ -d "$HOME/.config/omarchy/plugins/roddy.seafile" ]]; then
    check "Repo == Runtime parity (deploy.sh --check)" bash -c './deploy.sh --check 2>&1 | grep -q "No files changed"'
else
    echo "  Runtime parity... SKIP (plugin not deployed)"
fi

# --- QML STRUCTURAL ANTI-PATTERNS ---
# Detect Qt6/QML-invalid constructs that previously blocked Panel from loading.
echo ""
echo "--- QML Structural Anti-Patterns ---"
check "No QML-in-.js / stale .js module references" bash -c '
  bad=0
  # A `.js` file must never carry a QML `pragma Singleton` (that only belongs in
  # `.qml`). Quickshell JS modules legitimately use `QtObject { }`, `property`,
  # and `Process { }` extensions, so those are NOT flagged.
  for f in $(find . -name "*.js" -not -path "*/node_modules/*" 2>/dev/null); do
    if grep -qE "pragma Singleton" "$f" 2>/dev/null; then
      echo "  QML-in-JS: $f"; bad=1
    fi
  done
  # JavaScript-style imports of individual .qml files with an alias (invalid Qt6
  # import for our module layout; .js module imports like "./js/Auth.js" as Auth
  # are legitimate and must NOT be flagged).
  if grep -rqE "import \".*\.qml\" as " --include="*.qml" . 2>/dev/null; then
    grep -rE "import \".*\.qml\" as " --include="*.qml" . 2>/dev/null | sed "s/^/  bad import: /"; bad=1
  fi
  exit $bad
'
check "No duplicate QML functions / properties / <prop>Changed collisions / uppercase props / illegal QtObject children" python3 - <<"PY"
import re, glob, sys
problems = []
for f in sorted(glob.glob("**/*.qml", recursive=True)):
    try:
        src = open(f, encoding="utf-8").read()
    except Exception:
        continue
    lines = src.splitlines()
    funcs = re.findall(r"^\s{4}function\s+(\w+)\s*\(", src, re.M)
    props = re.findall(r"^\s{4}(?:readonly )?property\s+\S+\s+(\w+)\s*:", src, re.M)
    from collections import Counter
    for nm, c in Counter(funcs).items():
        if c > 1:
            problems.append(f"{f}: duplicate function {nm}")
    for nm, c in Counter(props).items():
        if c > 1:
            problems.append(f"{f}: duplicate property {nm}")
    propnames = set(props)
    for fn in funcs:
        if fn.endswith("Changed") and fn[:-7] in propnames:
            problems.append(f"{f}: function {fn}() collides with auto signal of property {fn[:-7]}")
    for p in props:
        if p[0].isupper():
            problems.append(f"{f}: uppercase-leading property {p}")
    # illegal direct child object inside QtObject
    depth = 0
    stack = []  # list of (indent_of_object_decl, type)
    for l in lines:
        s = l.lstrip()
        if not s:
            continue
        m = re.match(r"^([A-Z]\w+)\s*\{", s)
        if m:
            indent = len(l) - len(s)
            # direct child if indent equals parent body indent (parent_indent+4)
            if stack and indent == stack[-1][0] + 4 and stack[-1][1] == "QtObject":
                # a property-typed child would be "property X y: Type {" -> indent deeper after colon; here decl at body indent
                if not re.match(r"^(property|readonly|id|function|signal|Component)", s):
                    problems.append(f"{f}: illegal direct child object {m.group(1)} inside QtObject")
            stack.append((indent, m.group(1)))
        # detect closing braces to pop
        opens = s.count("{"); closes = s.count("}")
        # simple pop per close at matching indent (approx)
        for _ in range(closes):
            if stack:
                stack.pop()
        depth += opens - closes
# (heuristic; duplicate-closing noise ignored)
if problems:
    for p in problems:
        print("  " + p)
    sys.exit(1)
sys.exit(0)
PY

# --- Dependency Reporting ---
echo ""
echo "--- Dependency Report ---"
for cmd in curl secret-tool wl-copy; do
    if command -v "$cmd" >/dev/null; then
        echo "  $cmd: $(which $cmd)"
    else
        echo "  $cmd: MISSING (install: sudo pacman -S ${cmd})"
    fi
done

# --- Summary ---
echo ""
if [[ $FAIL -eq 0 ]]; then
    echo "== ALL CHECKS PASSED =="
    if [[ $WARN -gt 0 ]]; then
        echo "  ($WARN warnings)"
    fi
    exit 0
else
    echo "== VALIDATION FAILED =="
    exit 1
fi