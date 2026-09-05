#!/usr/bin/env python3
"""Secure, deterministic eviction of Open Local cache files.

Usage:
  cache_evict.py <cache_dir> <max_bytes>

Evicts the oldest regular files directly under <cache_dir> (by mtime, oldest
first) until the total size of retained files is <= <max_bytes>.

All filesystem operations run relative to a held directory FD opened with
O_DIRECTORY|O_NOFOLLOW, and each entry is inspected with lstat semantics
(no symlink following). Hidden entries and active download temp files
(prefix "dl_") are never evicted.

Exits 0 on success, 1 on error, 2 on usage error.
"""
import os
import sys
import errno
import stat


def _valid_dir_fd(cache_dir):
    """Open cache_dir O_DIRECTORY|O_NOFOLLOW and verify ownership/perms.

    Returns an open fd, or None after writing an error to stderr.
    """
    try:
        fd = os.open(cache_dir, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    except OSError as e:
        sys.stderr.write(f"cache_evict: cannot open cache dir: {e}\n")
        return None
    try:
        st = os.fstat(fd)
    except OSError as e:
        os.close(fd)
        sys.stderr.write(f"cache_evict: cannot stat cache dir: {e}\n")
        return None
    if st.st_uid != os.getuid():
        os.close(fd)
        sys.stderr.write("cache_evict: cache dir not owned by current user\n")
        return None
    if st.st_mode & 0o022:
        os.close(fd)
        sys.stderr.write("cache_evict: cache dir has unsafe permissions\n")
        return None
    return fd


def main():
    if len(sys.argv) != 3:
        sys.stderr.write("usage: cache_evict.py <cache_dir> <max_bytes>\n")
        return 2
    cache_dir = sys.argv[1]
    try:
        max_bytes = int(sys.argv[2])
    except ValueError:
        sys.stderr.write("cache_evict: invalid max_bytes\n")
        return 2

    dir_fd = _valid_dir_fd(cache_dir)
    if dir_fd is None:
        return 1

    entries = []
    try:
        with os.scandir(dir_fd) as it:
            for entry in it:
                name = entry.name
                # Never evict hidden files or active download temp files.
                if name.startswith(".") or name.startswith("dl_"):
                    continue
                try:
                    st = entry.stat(follow_symlinks=False)
                except OSError:
                    # Fail closed: skip entries that cannot be safely inspected.
                    continue
                # Only regular files, and only files directly in this directory.
                if not stat.S_ISREG(st.st_mode):
                    continue
                if name in (".", ".."):
                    continue
                entries.append((st.st_mtime, name, st.st_size))
    except OSError as e:
        os.close(dir_fd)
        sys.stderr.write(f"cache_evict: cannot scan cache dir: {e}\n")
        return 1

    entries.sort(key=lambda x: x[0])  # oldest mtime first

    total = sum(e[2] for e in entries)
    for _, name, size in entries:
        if total <= max_bytes:
            break
        try:
            os.unlink(name, dir_fd=dir_fd)
        except OSError as e:
            # Fail closed on per-entry removal error: leave the file in place
            # and stop trying to reduce usage rather than risk an error loop.
            if e.errno == errno.EISDIR:
                continue
            break
        total -= size

    os.close(dir_fd)
    return 0


if __name__ == "__main__":
    sys.exit(main() or 0)