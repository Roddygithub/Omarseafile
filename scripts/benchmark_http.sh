#!/bin/bash
# Benchmark HTTP transport optimization.
# Run on the real machine after deploying the perf branch.
# Measures: curl baseline, plugin cold folder, panel→libraries, back-nav cache hit.
set -euo pipefail

echo "=== HTTP Transport Benchmark ==="
echo "Machine: $(hostname)"
echo "Date: $(date -Iseconds)"
echo ""

# 1. Curl baseline
echo "--- curl baseline ---"
for i in 1 2 3; do
  t=$( { time curl -sk -o /dev/null -w '%{http_code}' \
    -H "Authorization: Token $(secret-tool lookup service seafile key auth-token/server-url/user-email 2>/dev/null | head -1)" \
    "$(secret-tool lookup service seafile key auth-token/server-url/user-email 2>/dev/null | tail -1)/api2/repos/" ; } 2>&1 | grep real | awk '{print $2}')
  echo "  attempt $i: $t"
done
echo ""

# 2. Plugin metrics (from SEAFILE_TIMING logs)
echo "--- Plugin metrics ---"
echo "Open the Seafile panel, navigate to a library, then check journal:"
echo "  journalctl --user -u omarchy-shell -g SEAFILE_TIMING --since '5 min ago' | tail -20"
echo ""
echo "Key fields:"
echo "  http_start:   curl launch timestamp"
echo "  http_done:    curl exit + body parse complete"
echo "  duration_ms:  total HTTP round-trip"
echo "  parse_ms:     JSON parse time only"
echo ""
echo "Expected improvement:"
echo "  Before: ~1200-2500ms cold (19 process spawns)"
echo "  After:  ~400-800ms cold (5 process spawns, 74% fewer)"
echo "  Cache hit: ~2ms (unchanged)"
