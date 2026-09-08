#!/usr/bin/env python3
"""Secure, deterministic eviction of Open Local cache files.

Usage:
  cache_evict.py <cache_dir> <max_bytes> [protected_basename ...]

Active downloads and finalizations have private .active_<basename> markers
containing their owner PID and start time. Live markers protect any cache
artifact; dead markers are removed and abandoned files become evictable.
"""
import errno
import os
import stat
import sys
import time


ACTIVE_PREFIX = ".active_"
MARKER_HANDOFF_SECONDS = 30


def _valid_dir_fd(cache_dir):
    try:
        fd = os.open(cache_dir, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
        st = os.fstat(fd)
    except OSError as e:
        sys.stderr.write(f"cache_evict: cannot open cache dir: {e}\n")
        return None
    if st.st_uid != os.getuid() or st.st_mode & 0o022:
        os.close(fd)
        sys.stderr.write("cache_evict: cache dir has unsafe ownership or permissions\n")
        return None
    return fd


def _safe_name(name):
    return bool(name) and len(name) <= 128 and all(c.isascii() and (c.isalnum() or c in "._-") for c in name)


def _process_start_time(pid):
    try:
        return open(f"/proc/{pid}/stat", encoding="ascii").read().rsplit(") ", 1)[1].split()[19]
    except (OSError, IndexError):
        return None


def _marker_is_live(dir_fd, name):
    marker = ACTIVE_PREFIX + name
    try:
        marker_fd = os.open(marker, os.O_RDONLY | os.O_NOFOLLOW, dir_fd=dir_fd)
    except FileNotFoundError:
        return False
    except OSError:
        return True  # Fail closed when marker inspection is unsafe.
    try:
        st = os.fstat(marker_fd)
        raw = os.read(marker_fd, 32).decode("ascii")
    except (OSError, UnicodeDecodeError):
        return True
    finally:
        os.close(marker_fd)
    if not stat.S_ISREG(st.st_mode) or st.st_uid != os.getuid() or st.st_mode & 0o022:
        return True
    # The downloader exits before its QML finalizer starts. Retain a fresh
    # marker across that short handoff; stale markers are still cleaned up.
    if time.time() - st.st_mtime <= MARKER_HANDOFF_SECONDS:
        return True
    try:
        pid_text, start_time = raw.split(":", 1)
        pid = int(pid_text)
        if pid <= 0 or not start_time.isdigit():
            raise ValueError
        os.kill(pid, 0)
        if _process_start_time(pid) == start_time:
            return True
        raise ProcessLookupError
    except (ValueError, ProcessLookupError):
        try:
            os.unlink(marker, dir_fd=dir_fd)
        except OSError:
            return True
        return False
    except PermissionError:
        return True


def _scan(dir_fd, protected):
    entries = []
    total = 0
    with os.scandir(dir_fd) as it:
        for entry in it:
            name = entry.name
            if name.startswith(ACTIVE_PREFIX):
                target = name[len(ACTIVE_PREFIX):]
                if not _safe_name(target):
                    try:
                        os.unlink(name, dir_fd=dir_fd)
                    except OSError:
                        pass
                else:
                    try:
                        os.stat(target, dir_fd=dir_fd, follow_symlinks=False)
                    except FileNotFoundError:
                        # A live owner may have reserved its name before the
                        # exclusive create/link. Only stale owners are reclaimable.
                        _marker_is_live(dir_fd, target)
                continue
            try:
                st = entry.stat(follow_symlinks=False)
            except OSError:
                continue
            if not stat.S_ISREG(st.st_mode):
                continue
            total += st.st_size
            active = _marker_is_live(dir_fd, name)
            if not name.startswith(".") and not active and name not in protected:
                entries.append((st.st_mtime, name, st.st_size))
    return entries, total


def main():
    if len(sys.argv) < 3:
        sys.stderr.write("usage: cache_evict.py <cache_dir> <max_bytes> [protected_basename ...]\n")
        return 2
    try:
        max_bytes = int(sys.argv[2])
    except ValueError:
        sys.stderr.write("cache_evict: invalid max_bytes\n")
        return 2
    protected = set(sys.argv[3:])
    if max_bytes < 0 or any(not _safe_name(name) for name in protected):
        sys.stderr.write("cache_evict: invalid limit or protected basename\n")
        return 2

    dir_fd = _valid_dir_fd(sys.argv[1])
    if dir_fd is None:
        return 1
    try:
        entries, total = _scan(dir_fd, protected)
        for _, name, _ in sorted(entries):
            if total <= max_bytes:
                break
            try:
                os.unlink(name, dir_fd=dir_fd)
            except FileNotFoundError:
                pass
            except OSError:
                pass
            entries, total = _scan(dir_fd, protected)
        # Re-measure after every attempted removal; projected totals are untrusted.
        _, total = _scan(dir_fd, protected)
        return 0 if total <= max_bytes else 1
    except OSError as e:
        sys.stderr.write(f"cache_evict: cannot scan cache dir: {e}\n")
        return 1
    finally:
        os.close(dir_fd)


if __name__ == "__main__":
    sys.exit(main() or 0)
