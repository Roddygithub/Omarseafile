#!/usr/bin/env python3
"""Securely stream curl output to an exclusively-created temporary file.

Usage:
  secure_output.py <outdir> <prefix> [--max-stderr-bytes N] -- <curl args...>

Creates a fresh temp file in <outdir> with exclusive creation (O_CREAT|O_EXCL|O_NOFOLLOW)
relative to a held directory FD, mode 0600. Streams curl body into the held fd
(via stdout redirection, never a pathname re-open). On success, prints ONLY the
basename of the created file to stdout. curl's stderr (progress) is passed through.

Optional --max-stderr-bytes N: hard producer-side byte ceiling on forwarded
stderr. Overflow truncates and returns exit 1.

This removes the TOCTOU/symlink race of pathname-based `--output <path>`.
"""
import os
import sys
import secrets
import subprocess
import signal
import errno
import threading

_cancelled = [False]
_child_pid = [None]

MAX_BASENAME_LEN = 128
VALID_BASENAME_CHARS = set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-")

def _validate_basename(basename: str) -> bool:
    """Validate basename: ASCII-safe, no slash/backslash, no special names, length <= MAX."""
    if not basename or len(basename) > 128:
        return False
    if any(c not in VALID_BASENAME_CHARS for c in basename):
        return False
    if basename in (".", ".."):
        return False
    if "/" in basename or "\\" in basename:
        return False
    return True

def _signal_handler(signum, frame):
    """Signal handler: mark cancellation, terminate child process group."""
    _cancelled[0] = True
    pid = _child_pid[0]
    if pid is not None:
        try:
            os.killpg(os.getpgid(pid), signal.SIGTERM)
        except OSError:
            pass

def main():
    # Parse optional --max-stderr-bytes before the -- separator
    max_stderr_bytes = None
    args = sys.argv[1:]
    dash_idx = args.index("--") if "--" in args else -1
    if dash_idx > 0:
        before = args[:dash_idx]
        after = args[dash_idx:]
        kept = []
        i = 0
        while i < len(before):
            if before[i] == "--max-stderr-bytes" and i + 1 < len(before):
                try:
                    max_stderr_bytes = int(before[i + 1])
                except ValueError:
                    pass
                i += 2
            else:
                kept.append(before[i])
                i += 1
        args = kept + after

    if len(args) < 4 or args[2] != "--":
        sys.stderr.write("usage: secure_output.py <outdir> <prefix> [--max-stderr-bytes N] -- <curl args...>\n")
        return 2

    outdir, prefix = args[0], args[1]
    curl_args = args[3:]

    # Open output directory with O_DIRECTORY|O_NOFOLLOW to avoid symlink races
    try:
        dir_fd = os.open(outdir, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    except OSError as e:
        sys.stderr.write(f"failed to open output directory: {e}\n")
        return 1

    # Verify ownership and permissions on the held directory FD
    try:
        st = os.fstat(dir_fd)
    except OSError:
        os.close(dir_fd)
        sys.stderr.write("failed to stat output directory\n")
        return 1

    if st.st_uid != os.getuid():
        os.close(dir_fd)
        sys.stderr.write("output directory not owned by current user\n")
        return 1
    if st.st_mode & 0o022:
        os.close(dir_fd)
        sys.stderr.write("output directory has unsafe permissions (group/other writable)\n")
        return 1

    # Set up signal handlers
    signal.signal(signal.SIGTERM, _signal_handler)
    signal.signal(signal.SIGINT, _signal_handler)

    # Create temp file exclusively relative to held directory FD with retry loop
    basename = None
    fd = None
    for attempt in range(10):  # Retry up to 10 times with new random names
        basename = f"{prefix}_{secrets.token_urlsafe(16)}"
        if not _validate_basename(basename):
            continue
        try:
            flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW
            fd = os.open(basename, flags, 0o600, dir_fd=dir_fd)
            break
        except OSError as e:
            if e.errno == errno.EEXIST:
                continue  # Retry with new random name
            os.close(dir_fd)
            sys.stderr.write(f"failed to create exclusive temp file: {e}\n")
            return 1
    else:
        os.close(dir_fd)
        sys.stderr.write("failed to create unique temp file after retries\n")
        return 1

    # Set up signal handlers
    signal.signal(signal.SIGTERM, _signal_handler)
    signal.signal(signal.SIGINT, _signal_handler)

    stderr_truncated = False
    try:
        # Spawn curl child, streaming body into the held fd
        proc = subprocess.Popen(
            curl_args + ["--output", "-"],
            stdout=fd,
            stderr=subprocess.PIPE,
            pass_fds=(fd,),
        )
        _child_pid[0] = proc.pid

        # Forward stderr in a thread so signal handlers can fire during reads
        stderr_fwd = [0]
        stderr_truncated = [False]
        stderr_lock = threading.Lock()

        def _forward_stderr():
            try:
                while True:
                    line = proc.stderr.readline()
                    if not line:
                        break
                    with stderr_lock:
                        if not stderr_truncated[0] and (
                            max_stderr_bytes is None or
                            stderr_fwd[0] + len(line) <= max_stderr_bytes
                        ):
                            sys.stderr.buffer.write(line)
                            sys.stderr.buffer.flush()
                            stderr_fwd[0] += len(line)
                        else:
                            stderr_truncated[0] = True
            except Exception:
                pass

        stderr_thread = threading.Thread(target=_forward_stderr, daemon=True)
        stderr_thread.start()

        rc = proc.wait()
        _child_pid[0] = None
        stderr_thread.join(timeout=5)
        stderr_truncated = stderr_truncated[0]

    except Exception as e:
        sys.stderr.write(f"child execution failed: {e}\n")
        if _child_pid[0] is not None:
            try:
                os.killpg(os.getpgid(_child_pid[0]), signal.SIGTERM)
            except OSError:
                pass
            try:
                os.waitpid(_child_pid[0], 0)
            except OSError:
                pass
            _child_pid[0] = None
        rc = 1
    finally:
        try:
            if fd is not None:
                os.close(fd)
        except OSError:
            pass

    if _cancelled[0] or rc != 0 or stderr_truncated:
        # On cancellation or curl failure: unlink temp file
        if basename is not None:
            try:
                os.unlink(basename, dir_fd=dir_fd)
            except OSError:
                pass
        if _cancelled[0]:
            os.close(dir_fd)
            return 128 + signal.SIGTERM
        os.close(dir_fd)
        return 1 if stderr_truncated else rc

    # Success: print ONLY the basename (validated, no path components)
    if _validate_basename(basename):
        sys.stdout.write(basename)
        sys.stdout.flush()
        os.close(dir_fd)
        return 0
    else:
        # Validation failed - should not happen
        try:
            os.unlink(basename, dir_fd=dir_fd)
        except OSError:
            pass
        os.close(dir_fd)
        return 1

if __name__ == "__main__":
    sys.exit(main() or 0)