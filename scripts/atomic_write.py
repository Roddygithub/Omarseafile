#!/usr/bin/env python3
"""Atomic secure file writer: held dir_fd with O_CREAT|O_EXCL|O_NOFOLLOW.

Usage: atomic_write.py <dir> <prefix>

Creates an unpredictable filename with exclusive creation (O_CREAT|O_EXCL|O_NOFOLLOW
in a single atomic syscall relative to a held directory fd), mode forced to 0600
on the held file descriptor before any content is written, and all content is
written through that descriptor. The path is printed to stdout only on success.
"""
import os
import sys
import secrets
import signal

MAXSIZE = 64 * 1024 * 1024  # 64 MiB hard cap on write

VALID_PREFIX_CHARS = set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-")

def _validate_prefix(prefix: str) -> bool:
    """Validate prefix: no traversal, no control chars, no path separators."""
    if not prefix or len(prefix) > 64:
        return False
    if any(c not in VALID_PREFIX_CHARS for c in prefix):
        return False
    if "/" in prefix or "\\" in prefix:
        return False
    if prefix in (".", ".."):
        return False
    return True

def _validate_basename(basename: str) -> bool:
    """Validate basename: no traversal, no control chars, no path separators."""
    if not basename or len(basename) > 128:
        return False
    if any(c not in VALID_PREFIX_CHARS for c in basename):
        return False
    if "/" in basename or "\\" in basename:
        return False
    if basename in (".", ".."):
        return False
    return True

_cancelled = [False]
_dir_fd = [None]
_basename = [None]

def _signal_handler(signum, frame):
    _cancelled[0] = True
    if _dir_fd[0] is not None and _basename[0] is not None:
        try:
            os.unlink(_basename[0], dir_fd=_dir_fd[0])
        except OSError:
            pass
    sys.exit(128 + signum)

def main():
    if len(sys.argv) != 3:
        sys.stderr.write("Usage: atomic_write.py <dir> <prefix>\n")
        sys.exit(1)

    dir_path = sys.argv[1]
    prefix = sys.argv[2]

    if not _validate_prefix(prefix):
        sys.stderr.write("Invalid prefix\n")
        sys.exit(1)

    # Open the target directory with held fd to avoid TOCTOU/symlink races
    try:
        dir_fd = os.open(dir_path, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    except OSError as e:
        sys.stderr.write(f"failed to open directory: {e}\n")
        sys.exit(1)

    # Validate the opened directory using fstat on held fd
    try:
        st = os.fstat(dir_fd)
    except OSError:
        os.close(dir_fd)
        sys.stderr.write("failed to stat directory\n")
        sys.exit(1)

    if st.st_uid != os.getuid():
        os.close(dir_fd)
        sys.stderr.write("directory not owned by current user\n")
        sys.exit(1)
    if st.st_mode & 0o022:
        os.close(dir_fd)
        sys.stderr.write("directory has unsafe permissions (group/other writable)\n")
        sys.exit(1)

    # Setup signal handlers for cleanup
    _dir_fd[0] = dir_fd
    signal.signal(signal.SIGTERM, _signal_handler)
    signal.signal(signal.SIGINT, _signal_handler)

    # Create temp file exclusively relative to held directory fd
    fd = None
    basename = None
    for attempt in range(10):
        # Generate unpredictable basename with safe prefix
        rand = secrets.token_urlsafe(16)
        basename = f"{prefix}_{rand}"
        if not _validate_basename(basename):
            continue
        try:
            flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW
            fd = os.open(basename, flags, 0o600, dir_fd=dir_fd)
            _basename[0] = basename
            break
        except OSError as e:
            if e.errno == 17:  # EEXIST
                continue  # Retry with new random name
            os.close(dir_fd)
            sys.stderr.write(f"failed to create exclusive temp file: {e}\n")
            sys.exit(1)
    else:
        os.close(dir_fd)
        sys.stderr.write("failed to create unique temp file after retries\n")
        sys.exit(1)

    # Ensure mode 0600 on the held fd (belt-and-suspenders)
    try:
        os.fchmod(fd, 0o600)
    except OSError:
        os.close(fd)
        os.unlink(basename, dir_fd=dir_fd)
        os.close(dir_fd)
        sys.stderr.write("failed to set file mode\n")
        sys.exit(1)

    # Read stdin with hard cap, write through held fd
    try:
        total = 0
        while True:
            chunk = sys.stdin.buffer.read(65536)
            if not chunk:
                break
            total += len(chunk)
            if total > MAXSIZE:
                os.close(fd)
                os.unlink(basename, dir_fd=dir_fd)
                os.close(dir_fd)
                sys.stderr.write(f"Content exceeds {MAXSIZE} bytes\n")
                sys.exit(1)
            os.write(fd, chunk)
    except OSError as e:
        os.close(fd)
        os.unlink(basename, dir_fd=dir_fd)
        os.close(dir_fd)
        sys.stderr.write(f"Write error: {e}\n")
        sys.exit(1)

    os.close(fd)
    os.close(dir_fd)
    _dir_fd[0] = None

    # Success — print only the usable path (directory + basename)
    result_path = os.path.join(dir_path, basename)
    sys.stdout.write(result_path + "\n")
    sys.exit(0)

if __name__ == "__main__":
    main()