#!/usr/bin/env python3
"""Atomic secure file writer: mkstemp creates an unpredictable filename with
exclusive creation (O_CREAT|O_EXCL in one atomic syscall), mode is forced to 0600
on the held file descriptor before any content is written, and all content is
written through that descriptor. The path is printed to stdout only on success."""
import os
import sys
import tempfile
import signal

MAXSIZE = 64 * 1024 * 1024  # 64 MiB hard cap on write

def main():
    if len(sys.argv) != 3:
        sys.stderr.write("Usage: atomic_write.py <dir> <prefix>\n")
        sys.exit(1)

    dir_path = sys.argv[1]
    prefix = sys.argv[2]

    # Reject any symlink in the directory path itself
    if os.path.islink(dir_path):
        sys.stderr.write("Directory is a symlink\n")
        sys.exit(1)

    # Parent must be owned by us
    st = os.stat(dir_path)
    if st.st_uid != os.getuid():
        sys.stderr.write("Directory not owned by current user\n")
        sys.exit(1)

    # mkstemp atomically creates and opens the file: open(name, O_CREAT|O_EXCL)
    # in a single syscall, returning both fd and path. No second open() call.
    fd = None
    try:
        fd, path = tempfile.mkstemp(dir=dir_path, prefix=prefix + "_")
    except FileExistsError:
        sys.stderr.write("File already exists (symlink attack detected)\n")
        sys.exit(1)

    # Set mode 0600 on the still-open descriptor before writing content
    os.fchmod(fd, 0o600)

    # Read stdin with hard cap
    try:
        total = 0
        while True:
            chunk = sys.stdin.buffer.read(65536)
            if not chunk:
                break
            total += len(chunk)
            if total > MAXSIZE:
                os.close(fd)
                os.unlink(path)
                sys.stderr.write(f"Content exceeds {MAXSIZE} bytes\n")
                sys.exit(1)
            os.write(fd, chunk)
    except OSError as e:
        os.close(fd)
        os.unlink(path)
        sys.stderr.write(f"Write error: {e}\n")
        sys.exit(1)

    os.close(fd)
    # Success — path printed to stdout, secret never in argv or env
    sys.stdout.write(path + "\n")
    sys.exit(0)

if __name__ == "__main__":
    main()
