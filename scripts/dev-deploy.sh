#!/bin/bash
# dev-deploy.sh — Developer helper: deploy + restart shell + fresh PID logs
#
# Omarchy runs Quickshell with QS_DISABLE_FILE_WATCHER=1, so deployed source
# is NOT reliably picked up by the running shell. This script chains the
# mandatory runtime-reload procedure:
#
#   ./deploy.sh → omarchy-restart-shell → wait for fresh PID → tail its logs
#
# deploy.sh remains deployment-only (CI/validation); this helper is for
# interactive development only.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"

echo "==> Deploying canonical source"
"$REPO_DIR/deploy.sh"

OLD_PID="$(pgrep -f '^quickshell -n' | head -1 || true)"

echo "==> Restarting Omarchy shell"
omarchy-restart-shell

for i in $(seq 1 20); do
  sleep 0.5
  NEW_PID="$(pgrep -f '^quickshell -n' | head -1 || true)"
  if [[ -n "$NEW_PID" && "$NEW_PID" != "$OLD_PID" ]]; then
    break
  fi
done

if [[ -z "${NEW_PID:-}" ]]; then
  echo "ERROR: no Quickshell PID found after restart" >&2
  exit 1
fi

echo "==> Fresh Quickshell PID: $NEW_PID (old: ${OLD_PID:-none})"
sleep 3

echo "==> First log lines from PID $NEW_PID (roddy.seafile / errors):"
journalctl --user "_PID=$NEW_PID" --no-pager 2>/dev/null \
  | grep -iE "seafile|TypeError|ReferenceError|SyntaxError|Cannot|Binding loop" \
  | head -20 || true

echo "==> Done. Validate runtime behavior against PID $NEW_PID only."
