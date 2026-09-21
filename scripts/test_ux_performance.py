#!/usr/bin/env python3
from pathlib import Path

panel = Path('Panel.qml').read_text()
browser = Path('views/BrowserView.qml').read_text()
toolbar = Path('components/ToolBar.qml').read_text()
cache = Path('js/Cache.qml').read_text()
http = Path('js/HttpTransport.qml').read_text()
checks = {
    'login toolbar hidden and collapses': 'visible: root.state !== "login"' in panel and 'implicitHeight: visible ? row.implicitHeight : 0' in toolbar,
    'library title omitted from nested breadcrumb': 'path: root.pathHistory.length > 1 ? root.pathHistory.slice(1) : []' in browser,
    'breadcrumb callback preserves path index': 'onSegmentClicked: function(index) { root.onNavigateToPath(index + 1) }' in browser,
    'panel and list are clipped/bounded': 'clip: true' in panel and 'Style.space(360)' in browser,
    'loading blocks repeated navigation clicks': 'root.destinationSubmitting || root.loading' in panel,
    'stale responses rejected': 'generation !== root.navigationGeneration' in panel,
    'cache scoped to server and account': 'function setScope(serverUrl, account)' in cache and 'scopedKey' in cache,
    'cache cleared on logout': 'Cache.clear()' in panel,
    'timings include HTTP and parse phases': 'SEAFILE_TIMING http_start' in http and 'parse_ms=' in http,
}
for name, ok in checks.items(): print(('PASS' if ok else 'FAIL') + ': ' + name)
if not all(checks.values()): raise SystemExit(1)
print(f'=== {len(checks)} UX/performance checks passed ===')
