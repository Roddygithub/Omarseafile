#!/usr/bin/env python3
"""Runtime race checks for ConnectionService's stale-probe guard."""
import http.server
import os
import shutil
import subprocess
import tempfile
import threading
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
QS = shutil.which("qs")
if not QS:
    print("SKIP: qs is required for ConnectionService runtime tests")
    raise SystemExit(0)

class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        route = self.path.split("?", 1)[0]
        if route == "/A/api2/ping/":
            time.sleep(0.25)
            status = 200 if self.server.scenario == "online-after-offline" else 500
        elif route == "/B/api2/ping/":
            status = 500 if self.server.scenario in ("online-after-offline", "timeout-stale", "error-stale") else 200
            if self.server.scenario == "timeout-stale":
                time.sleep(0.05)
        else:
            status = 404
        self.send_response(status)
        self.end_headers()
        self.wfile.write(b"ok")

    def log_message(self, *_args):
        pass

for scenario in ("offline-after-online", "online-after-offline", "timeout-stale", "error-stale"):
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    server.scenario = scenario
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        with tempfile.TemporaryDirectory() as temp:
            package = Path(temp) / "package"
            package.mkdir()
            (package / "js").symlink_to(ROOT / "js", target_is_directory=True)
            qml = (package / "test_connection_service.qml")
            source = (ROOT / "test_connection_service.qml").read_text()
            qml.write_text(source.replace('property string baseUrl: ""', f'property string baseUrl: "http://127.0.0.1:{server.server_port}"').replace('property string scenario: ""', f'property string scenario: "{scenario}"'))
            result = subprocess.run(
                ["timeout", "9", QS, "--path", str(qml)],
                capture_output=True, text=True, timeout=12,
            )
            output = result.stdout + result.stderr
            if result.returncode != 0 or f"{scenario} online=" not in output:
                raise SystemExit(f"FAIL {scenario}: qs={result.returncode}\n{output}")
            expected = "online=true" if scenario == "offline-after-online" else "online=false"
            if expected not in output:
                raise SystemExit(f"FAIL {scenario}: expected {expected}\n{output}")
            print(f"PASS {scenario}")
    finally:
        server.shutdown()
        server.server_close()

print("=== ConnectionService race checks passed ===")
