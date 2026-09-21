#!/usr/bin/env python3
"""Real HTTP transport integration test.

Starts a local Python HTTP server and runs the REAL HttpTransport QML under
Quickshell against it, proving the curl body/status contract end to end:

  -o FILE   writes the HTTP BODY into FILE
  -w %{http_code} writes the HTTP STATUS to stdout

and that HttpTransport threads both into callback(success, data, error, status).

Test classification: INTEGRATION (requires qs + a network loopback server).
"""
import http.server
import os
import shutil
import socketserver
import subprocess
import sys
import tempfile
import threading

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
qs = shutil.which("qs")
if not qs:
    print("SKIP: qs is required for the HTTP integration test")
    sys.exit(0)


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def _send(self, status, body):
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/ok":
            self._send(200, b'{"token":"abc"}')
        elif self.path == "/echo":
            self._send(200, b'{"hello":"world"}')
        elif self.path == "/large":
            self._send(200, b'{"x":"' + b"y" * (2 * 1024 * 1024) + b'"}')
        elif self.path == "/unauth":
            self._send(401, b'{"detail":"bad token"}')
        elif self.path == "/busy":
            self._send(503, b'{"detail":"overloaded"}')
        else:
            self._send(404, b'{"detail":"missing"}')

    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(length)
        import json
        self._send(200, json.dumps({"saw": body.decode(errors="replace")}).encode())


def main():
    server = socketserver.TCPServer(("127.0.0.1", 0), Handler)
    port = server.server_address[1]
    t = threading.Thread(target=server.serve_forever, daemon=True)
    t.start()

    with tempfile.TemporaryDirectory() as temp:
        package_dir = os.path.join(temp, "package")
        os.mkdir(package_dir)
        for name in ("test_http_integration.qml", "js", "scripts"):
            os.symlink(os.path.join(ROOT, name), os.path.join(package_dir, name))
        os.symlink("/usr/share/omarchy/shell/Ui", os.path.join(package_dir, "Ui"))
        os.symlink("/usr/share/omarchy/shell/Commons", os.path.join(package_dir, "Commons"))

        env = os.environ.copy()
        # Provide a real XDG_RUNTIME_DIR so SafePath can create private files.
        rt = os.path.join(temp, "run")
        os.makedirs(rt, mode=0o700)
        env["XDG_RUNTIME_DIR"] = rt
        env["HTTP_TEST_BASE"] = "http://127.0.0.1:%d" % port
        env["XDG_CACHE_HOME"] = os.path.join(temp, "cache")
        os.makedirs(env["XDG_CACHE_HOME"], mode=0o700)

        result = subprocess.run(
            ["timeout", "25", qs, "--path", os.path.join(package_dir, "test_http_integration.qml")],
            capture_output=True, timeout=30, env=env,
        )
    server.shutdown()

    output = (result.stdout + result.stderr).decode(errors="replace")
    # The QML prints one "HTTPINT name=verdict:detail" line per check.
    lines = [l for l in output.splitlines() if " HTTPINT " in l]
    if not lines:
        print("FAIL: no HTTPINT result line; qs exit=%d" % result.returncode)
        print(output[-4000:])
        sys.exit(1)

    wanted = {
        "status200", "status404", "status401", "status503",
        "bodyParsed", "postBody", "oversized",
    }
    failed = []
    seen = set()
    for ln in lines:
        idx = ln.index(" HTTPINT ") + len(" HTTPINT ")
        rec = ln[idx:].strip()
        name, _, verdict = rec.partition("=")
        seen.add(name)
        if not verdict.startswith("PASS"):
            failed.append(rec)
    for missing in sorted(wanted - seen):
        failed.append(missing + "=MISSING")
    if failed or result.returncode != 0:
        print("FAIL: " + "; ".join(failed) + (" (qs exit=%d)" % result.returncode))
        print(output[-4000:])
        sys.exit(1)
    print("=== HTTP transport integration: %d/%d checks passed ===" % (len(seen), len(seen)))


if __name__ == "__main__":
    main()