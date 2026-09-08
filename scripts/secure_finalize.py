#!/usr/bin/env python3
"""Atomically promote a secure download file inside one held cache directory."""
import errno
import os
import signal
import stat
import sys


_dir_fd = None
_target = None
_target_created = False
_source_removed = False


def _write_marker(name):
    marker = ".active_" + name
    start_time = open(f"/proc/{os.getpid()}/stat", encoding="ascii").read().rsplit(") ", 1)[1].split()[19]
    payload = f"{os.getpid()}:{start_time}".encode("ascii")
    try:
        fd = os.open(marker, os.O_WRONLY | os.O_NOFOLLOW, dir_fd=_dir_fd)
    except FileNotFoundError:
        fd = os.open(marker, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600, dir_fd=_dir_fd)
    try:
        st = os.fstat(fd)
        if not stat.S_ISREG(st.st_mode) or st.st_uid != os.getuid() or st.st_mode & 0o022:
            raise OSError("unsafe active marker")
        os.ftruncate(fd, 0)
        os.write(fd, payload)
        os.fsync(fd)
    finally:
        os.close(fd)


def _rollback_target():
    # Before source removal, cancellation can safely undo the new hard link.
    # Afterwards the target is the only valid copy and must be retained.
    if _target_created and not _source_removed and _dir_fd is not None:
        try:
            os.unlink(_target, dir_fd=_dir_fd)
        except OSError:
            pass


def _cancel(signum, frame):
    _rollback_target()
    os._exit(128 + signum)


def valid(name):
    return bool(name) and len(name) <= 128 and all(c.isascii() and (c.isalnum() or c in "._-") for c in name) and name not in (".", "..")


def main():
    global _dir_fd, _target, _target_created, _source_removed
    if len(sys.argv) != 4 or not valid(sys.argv[2]) or not valid(sys.argv[3]):
        return 2
    try:
        _dir_fd = os.open(sys.argv[1], os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
        _target = sys.argv[3]
        signal.signal(signal.SIGTERM, _cancel)
        signal.signal(signal.SIGINT, _cancel)
        directory = os.fstat(_dir_fd)
        source = os.stat(sys.argv[2], dir_fd=_dir_fd, follow_symlinks=False)
        if directory.st_uid != os.getuid() or directory.st_mode & 0o022 or not stat.S_ISREG(source.st_mode) or source.st_mode & 0o077:
            return 1
        # Mark both names before either can be evicted. A crash leaves
        # PID-backed stale markers for recovery.
        _write_marker(sys.argv[2])
        _write_marker(sys.argv[3])
        # Keep cancellation blocked through the ownership handoff. There is
        # always at least one valid name: source before unlink, target after.
        signal.pthread_sigmask(signal.SIG_BLOCK, {signal.SIGTERM, signal.SIGINT})
        os.link(sys.argv[2], sys.argv[3], src_dir_fd=_dir_fd, dst_dir_fd=_dir_fd, follow_symlinks=False)
        _target_created = True
        os.unlink(sys.argv[2], dir_fd=_dir_fd)
        _source_removed = True
        try:
            os.unlink(".active_" + sys.argv[2], dir_fd=_dir_fd)
        except FileNotFoundError:
            pass
        try:
            os.unlink(".active_" + sys.argv[3], dir_fd=_dir_fd)
        except FileNotFoundError:
            pass
        # TERM/INT remain blocked through process exit, so no signal can split
        # the link/unlink ownership transition.
        os._exit(0)
    except OSError as e:
        _rollback_target()
        if e.errno != errno.EEXIST:
            return 1
        return 1
    finally:
        try:
            if _dir_fd is not None:
                os.close(_dir_fd)
        except OSError:
            pass


if __name__ == "__main__":
    sys.exit(main())
