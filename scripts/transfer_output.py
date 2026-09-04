#!/usr/bin/env python3
"""Transfer output wrapper: producer-side stderr byte ceiling for curl uploads.

Usage:
  transfer_output.py <max_stderr_bytes> -- <curl args...>

Runs curl in an isolated process group (setsid). Enforces a hard
producer-side byte ceiling on stderr (progress output) before data
enters the QML StdioCollector. stdout (response body) passes through
unmodified. Overflow fails closed (exit 1).
"""
import os
import sys
import subprocess
import signal
import threading

_child_pid = [None]
_terminated = [False]


def _signal_handler(signum, frame):
    if _terminated[0]:
        return
    _terminated[0] = True
    pid = _child_pid[0]
    if pid is not None:
        try:
            os.killpg(os.getpgid(pid), signal.SIGTERM)
        except OSError:
            pass
    os._exit(128 + signum)


def _drain(stream, max_bytes, output_fd, lock, result):
    total = 0
    truncated = False
    try:
        while True:
            remaining = (max_bytes - total) if max_bytes else None
            if remaining is not None and remaining <= 0:
                chunk = stream.read1(4096)
                if not chunk:
                    break
                truncated = True
                continue
            chunk = stream.read1(min(4096, remaining) if remaining else 4096)
            if not chunk:
                break
            total += len(chunk)
            if max_bytes is None or total <= max_bytes:
                with lock:
                    os.write(output_fd, chunk)
            else:
                truncated = True
    except Exception:
        pass
    result['bytes'] = total
    result['truncated'] = truncated


def main():
    if len(sys.argv) < 4 or sys.argv[2] != "--":
        sys.stderr.write("usage: transfer_output.py <max_stderr_bytes> -- <curl args...>\n")
        return 2

    try:
        max_stderr = int(sys.argv[1])
    except ValueError:
        sys.stderr.write("invalid byte limit\n")
        return 2

    cmd = sys.argv[3:]

    signal.signal(signal.SIGTERM, _signal_handler)
    signal.signal(signal.SIGINT, _signal_handler)

    proc = subprocess.Popen(
        cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    _child_pid[0] = proc.pid

    lock = threading.Lock()
    stderr_result = {}

    # stdout passes through unmodified
    stdout_thread = threading.Thread(
        target=_drain,
        args=(proc.stdout, None, 1, lock, {}),
        daemon=True,
    )
    # stderr is capped
    stderr_thread = threading.Thread(
        target=_drain,
        args=(proc.stderr, max_stderr, 2, lock, stderr_result),
        daemon=True,
    )

    stdout_thread.start()
    stderr_thread.start()

    rc = 1
    try:
        proc.wait()
        rc = proc.returncode
    except Exception:
        rc = 1
    finally:
        _child_pid[0] = None

    stdout_thread.join(timeout=5)
    stderr_thread.join(timeout=5)

    if stderr_result.get('truncated'):
        return 1
    return rc


if __name__ == "__main__":
    sys.exit(main() or 0)
