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

OLD_PIDS="$(pgrep -f '^quickshell -n' || true)"

echo "==> Restarting Omarchy shell"
omarchy-restart-shell

NEW_PID=""
for i in $(seq 1 20); do
  sleep 0.5
  while read -r pid; do
    if [[ -n "$pid" ]] && ! grep -qxF "$pid" <<< "$OLD_PIDS"; then
      NEW_PID="$pid"
      break 2
    fi
  done < <(pgrep -f '^quickshell -n' || true)
done

if [[ -z "${NEW_PID:-}" ]]; then
  echo "ERROR: no Quickshell PID found after restart" >&2
  exit 1
fi

echo "==> Fresh Quickshell PID: $NEW_PID (old: ${OLD_PIDS:-none})"
sleep 3

echo "==> First log lines from PID $NEW_PID (roddy.seafile / errors):"
LOGS="$(journalctl --user "_PID=$NEW_PID" --no-pager 2>/dev/null || true)"
grep -iE "roddy\.seafile|plugins/roddy\.seafile|Omarseafile" <<< "$LOGS" | head -20 || true

if grep -iE "roddy\.seafile|plugins/roddy\.seafile|Omarseafile" <<< "$LOGS" \
  | grep -qiE "TypeError|ReferenceError|SyntaxError|Binding loop|Cannot"; then
  echo "ERROR: fresh Quickshell logs contain Omarseafile runtime errors" >&2
  exit 1
fi

echo "==> Fresh logs are clean. Perform the targeted runtime test against PID $NEW_PID."
