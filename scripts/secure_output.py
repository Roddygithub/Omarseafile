#!/usr/bin/env python3
"""Securely stream curl output to an exclusively-created temporary file.

Usage:
  secure_output.py <outdir> <prefix> -- <curl args...>

Creates a fresh temp file in <outdir> with exclusive creation (O_CREAT|O_EXCL|O_NOFOLLOW)
relative to a held directory FD, mode 0600. Streams curl body into the held fd
(via stdout redirection, never a pathname re-open). On success, prints ONLY the
basename of the created file to stdout. curl's stderr (progress) is passed through.

This removes the TOCTOU/symlink race of pathname-based `--output <path>`.
"""
import os
import sys
import secrets
import subprocess
import signal
import errno

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
    """Signal handler: mark cancellation, terminate child if running."""
    _cancelled[0] = True
    pid = _child_pid[0]
    if pid is not None:
        try:
            os.kill(pid, signal.SIGTERM)
        except OSError:
            pass

def main():
    if len(sys.argv) < 5 or sys.argv[3] != "--":
        sys.stderr.write("usage: secure_output.py <outdir> <prefix> -- <curl args...>\n")
        return 2

    outdir, prefix = sys.argv[1], sys.argv[2]
    curl_args = sys.argv[4:]

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

    try:
        # Spawn curl child, streaming body into the held fd
        proc = subprocess.Popen(
            curl_args + ["--output", "-"],
            stdout=fd,
            stderr=subprocess.PIPE,
            pass_fds=(fd,),
        )
        _child_pid[0] = proc.pid

        # Wait for curl to complete, forwarding progress from stderr
        while True:
            try:
                line = proc.stderr.readline()
            except (OSError, IOError) as e:
                if e.errno == errno.EINTR:
                    if _cancelled[0]:
                        break
                    continue
                raise

            if not line and proc.poll() is not None:
                break
            if line:
                sys.stderr.buffer.write(line)
                sys.stderr.buffer.flush()

            if _cancelled[0]:
                try:
                    os.kill(proc.pid, signal.SIGTERM)
                except OSError:
                    pass

        rc = proc.wait()
        _child_pid[0] = None

    except Exception as e:
        sys.stderr.write(f"child execution failed: {e}\n")
        if _child_pid[0] is not None:
            try:
                os.kill(_child_pid[0], signal.SIGTERM)
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

    if _cancelled[0] or rc != 0:
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
        return rc

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