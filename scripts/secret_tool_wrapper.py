#!/usr/bin/env python3
"""Wrapper for secret-tool with process-group isolation and producer-side byte caps.

Usage:
  secret_tool_wrapper.py <max_stdout_bytes> <max_stderr_bytes> -- <secret-tool args...>

Runs secret-tool in an isolated process group (setsid). Enforces hard
producer-side byte ceilings on both stdout and stderr before data enters
the QML StdioCollector. Overflow fails closed (truncated output + exit 1).
No secret values appear in argv, environment, or logs.
"""
import os
import sys
import subprocess
import signal
import threading


_child_pid = [None]
_terminated = [False]


def _signal_handler(signum, frame):
    """On SIGTERM/SIGINT: terminate child process group, then exit."""
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
    """Read from stream up to max_bytes, write to output_fd. Thread-safe."""
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
    if len(sys.argv) < 5 or sys.argv[3] != "--":
        sys.stderr.write("usage: secret_tool_wrapper.py <max_stdout> <max_stderr> -- <args...>\n")
        return 2

    try:
        max_stdout = int(sys.argv[1])
        max_stderr = int(sys.argv[2])
    except ValueError:
        sys.stderr.write("invalid byte limits\n")
        return 2

    cmd = sys.argv[4:]

    signal.signal(signal.SIGTERM, _signal_handler)
    signal.signal(signal.SIGINT, _signal_handler)

    proc = subprocess.Popen(
        cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        start_new_session=True,
    )
    _child_pid[0] = proc.pid

    lock = threading.Lock()
    stdout_result = {}
    stderr_result = {}

    stdout_thread = threading.Thread(
        target=_drain,
        args=(proc.stdout, max_stdout, 1, lock, stdout_result),
        daemon=True,
    )
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

    if stdout_result.get('truncated') or stderr_result.get('truncated'):
        return 1
    return rc


if __name__ == "__main__":
    sys.exit(main() or 0)
