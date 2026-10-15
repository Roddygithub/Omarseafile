#!/usr/bin/env python3
"""Transfer output wrapper: producer-side stderr byte ceiling for curl uploads.

Usage:
  transfer_output.py <max_stderr_bytes> [secure upload options] -- <command...>

Runs curl in an isolated process group (setsid). Enforces a hard
producer-side byte ceiling on stderr (progress output) before data
enters the QML StdioCollector. stdout (response body) passes through
unmodified. Overflow fails closed (exit 1).

For uploads, --secure-upload-source opens one absolute regular-file pathname
with O_NOFOLLOW, checks --max-input-bytes, and replaces the marker form value
file=@__OMARSEAFILE_SECURE_UPLOAD_SOURCE__ with a /proc/self/fd path inherited
by the child. Curl therefore cannot reopen a raced or replaced pathname.
"""
import os
import sys
import subprocess
import signal
import threading
import stat

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


def _spawn(cmd, pass_fds=()):
    # Block cancellation until proc.pid is published, then explicitly unblock
    # it for both wrapper and child so inherited masks cannot defeat cleanup.
    cancel_signals = {signal.SIGTERM, signal.SIGINT}
    signal.pthread_sigmask(signal.SIG_BLOCK, cancel_signals)
    try:
        proc = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            pass_fds=tuple(pass_fds),
            start_new_session=True,
            preexec_fn=lambda: signal.pthread_sigmask(signal.SIG_UNBLOCK, cancel_signals),
        )
        _child_pid[0] = proc.pid
        return proc
    finally:
        signal.pthread_sigmask(signal.SIG_UNBLOCK, cancel_signals)


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
    if len(sys.argv) < 4 or "--" not in sys.argv[2:]:
        sys.stderr.write(
            "usage: transfer_output.py <max_stderr_bytes> "
            "[--secure-upload-source PATH --max-input-bytes N] -- <command...>\n"
        )
        return 2

    try:
        max_stderr = int(sys.argv[1])
    except ValueError:
        sys.stderr.write("invalid byte limit\n")
        return 2

    secure_source = None
    max_input_bytes = None
    option_end = sys.argv.index("--")
    options = sys.argv[2:option_end]
    i = 0
    while i < len(options):
        if options[i] == "--secure-upload-source" and i + 1 < len(options):
            secure_source = options[i + 1]
            i += 2
        elif options[i] == "--max-input-bytes" and i + 1 < len(options):
            try:
                max_input_bytes = int(options[i + 1])
            except ValueError:
                sys.stderr.write("invalid input byte limit\n")
                return 2
            i += 2
        else:
            sys.stderr.write("invalid transfer option\n")
            return 2

    cmd = sys.argv[option_end + 1:]
    source_fd = None
    if secure_source is not None:
        if not secure_source.startswith("/") or max_input_bytes is None or max_input_bytes < 0:
            sys.stderr.write("invalid secure upload source\n")
            return 2
        try:
            source_fd = os.open(
                secure_source,
                os.O_RDONLY | os.O_NOFOLLOW | os.O_CLOEXEC,
            )
            source_stat = os.fstat(source_fd)
            if not stat.S_ISREG(source_stat.st_mode):
                raise OSError("upload source is not a regular file")
            if source_stat.st_size > max_input_bytes:
                raise OSError("upload source exceeds maximum size")
        except OSError as e:
            if source_fd is not None:
                os.close(source_fd)
            sys.stderr.write(f"secure upload source rejected: {e}\n")
            return 1

        marker = "file=@__OMARSEAFILE_SECURE_UPLOAD_SOURCE__"
        replacement = f"file=@/proc/self/fd/{source_fd}"
        marker_found = marker in cmd
        cmd = [replacement if arg == marker else arg for arg in cmd]
        if not marker_found:
            os.close(source_fd)
            source_fd = None
            sys.stderr.write("secure upload source marker missing\n")
            return 2

    signal.signal(signal.SIGTERM, _signal_handler)
    signal.signal(signal.SIGINT, _signal_handler)

    try:
        proc = _spawn(cmd, (source_fd,) if source_fd is not None else ())
    except Exception:
        if source_fd is not None:
            os.close(source_fd)
        raise

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
        if source_fd is not None:
            os.close(source_fd)

    stdout_thread.join(timeout=5)
    stderr_thread.join(timeout=5)

    if stderr_result.get('truncated'):
        return 1
    return rc


if __name__ == "__main__":
    sys.exit(main() or 0)
