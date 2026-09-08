#!/usr/bin/env python3
"""Behavioral regressions for the final marketplace remediation."""
import os
import signal
import stat
import subprocess
import sys
import tempfile
import textwrap
import time


ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCRIPTS = os.path.join(ROOT, "scripts")
CACHE_EVICT = os.path.join(SCRIPTS, "cache_evict.py")
SECURE_OUTPUT = os.path.join(SCRIPTS, "secure_output.py")
TRANSFER_OUTPUT = os.path.join(SCRIPTS, "transfer_output.py")
SECURE_FINALIZE = os.path.join(SCRIPTS, "secure_finalize.py")
passed = failed = 0


def check(label, condition):
    global passed, failed
    if condition:
        passed += 1
    else:
        failed += 1
        print(f"FAIL: {label}")


def run(*args, **kwargs):
    return subprocess.run(args, capture_output=True, timeout=10, **kwargs)


def evict(directory, limit):
    return run(sys.executable, CACHE_EVICT, directory, str(limit))


def process_start_time(pid):
    return open(f"/proc/{pid}/stat", encoding="ascii").read().rsplit(") ", 1)[1].split()[19]


with tempfile.TemporaryDirectory() as cache:
    negative = run(sys.executable, SECURE_OUTPUT, cache, "dl", "--already-reserved-bytes", "-1", "--", "true")
    check("negative reservation rejected", negative.returncode != 0 and not os.listdir(cache))

with tempfile.TemporaryDirectory() as cache:
    active = os.path.join(cache, "dl_active")
    with open(active, "wb") as f:
        f.write(b"x" * 16)
    owner = subprocess.Popen(["sleep", "5"])
    try:
        with open(os.path.join(cache, ".active_dl_active"), "w") as f:
            f.write(f"{owner.pid}:{process_start_time(owner.pid)}")
        result = evict(cache, 0)
        check("active transfer protected", result.returncode != 0 and os.path.exists(active))
    finally:
        owner.send_signal(signal.SIGTERM)
        owner.wait(timeout=3)
    marker = os.path.join(cache, ".active_dl_active")
    os.utime(marker, (time.time() - 31, time.time() - 31))
    result = evict(cache, 0)
    check("abandoned dl file evictable", result.returncode == 0 and not os.path.exists(active))

with tempfile.TemporaryDirectory() as cache:
    active = os.path.join(cache, "dl_reused_pid")
    with open(active, "wb") as f:
        f.write(b"x")
    with open(os.path.join(cache, ".active_dl_reused_pid"), "w") as f:
        f.write(f"{os.getpid()}:0")
    stale = os.path.join(cache, ".active_dl_reused_pid")
    os.utime(stale, (time.time() - 31, time.time() - 31))
    result = evict(cache, 0)
    check("PID reuse does not protect stale marker", result.returncode == 0 and not os.path.exists(active))

with tempfile.TemporaryDirectory() as cache:
    handoff_result = run(sys.executable, SECURE_OUTPUT, cache, "dl", "--active-marker", "--", "sh", "-c", "printf x")
    handoff = os.path.join(cache, handoff_result.stdout.decode())
    marker = os.path.join(cache, ".active_" + handoff_result.stdout.decode())
    result = evict(cache, 0)
    check("fresh helper marker protects finalization handoff", handoff_result.returncode == 0 and result.returncode != 0 and os.path.exists(handoff))
    os.utime(marker, (time.time() - 31, time.time() - 31))
    os.unlink(handoff)
    result = evict(cache, 0)
    check("orphaned marker is removed", result.returncode == 0 and not os.path.exists(marker))

with tempfile.TemporaryDirectory() as cache:
    stuck = os.path.join(cache, "completed")
    with open(stuck, "wb") as f:
        f.write(b"x")
    os.chmod(cache, 0o500)
    try:
        result = evict(cache, 0)
        check("eviction cannot falsely succeed", result.returncode != 0 and os.path.exists(stuck))
    finally:
        os.chmod(cache, 0o700)

with tempfile.TemporaryDirectory() as cache:
    source = os.path.join(cache, "dl_source")
    victim = os.path.join(cache, "victim")
    target = os.path.join(cache, "open_target.pdf")
    with open(source, "wb") as f:
        f.write(b"payload")
    os.chmod(source, 0o600)
    with open(victim, "wb") as f:
        f.write(b"victim")
    os.symlink(victim, target)
    blocked = run(sys.executable, SECURE_FINALIZE, cache, "dl_source", "open_target.pdf")
    check("cache finalization rejects target symlink", blocked.returncode != 0 and open(victim, "rb").read() == b"victim")
    os.unlink(target)
    promoted = run(sys.executable, SECURE_FINALIZE, cache, "dl_source", "open_target.pdf")
    check("cache finalization is exclusive and private", promoted.returncode == 0 and not os.path.exists(source) and stat.S_IMODE(os.stat(target).st_mode) == 0o600)

with tempfile.TemporaryDirectory() as cache:
    source = os.path.join(cache, "dl_source")
    target = os.path.join(cache, "open_target")
    with open(source, "wb") as f:
        f.write(b"payload")
    os.chmod(source, 0o600)
    probe = '''
import importlib.util, os, signal, sys
spec = importlib.util.spec_from_file_location("secure_finalize", sys.argv[1])
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
source = sys.argv[3]
original_unlink = module.os.unlink
fired = [False]
def unlink(path, *args, **kwargs):
    result = original_unlink(path, *args, **kwargs)
    if path == source and not fired[0]:
        fired[0] = True
        os.kill(os.getpid(), signal.SIGTERM)
    return result
module.os.unlink = unlink
sys.argv = ["secure_finalize.py", sys.argv[2], source, sys.argv[4]]
module.main()
'''
    result = run(sys.executable, "-c", probe, SECURE_FINALIZE, cache, "dl_source", "open_target")
    check("finalizer signal handoff retains target", result.returncode == 0 and not os.path.exists(source) and open(target, "rb").read() == b"payload")

with tempfile.TemporaryDirectory() as cache:
    probe = textwrap.dedent("""
        import importlib.util, os, subprocess, sys
        helper, evict, cache = sys.argv[1:]
        spec = importlib.util.spec_from_file_location("secure_output", helper)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        original_open = module.os.open
        original_close = module.os.close
        marker_fd = [None]
        fired = [False]
        def close_hook(fd):
            result = original_close(fd)
            if fd == marker_fd[0] and not fired[0]:
                fired[0] = True
                subprocess.run([sys.executable, evict, cache, "0"], check=False)
                if not os.path.exists(os.path.join(cache, ".active_" + marker_name[0])):
                    raise RuntimeError("eviction removed live pre-publication marker")
            return result
        marker_name = [None]
        def open_hook(path, flags, *args, **kwargs):
            fd = original_open(path, flags, *args, **kwargs)
            if isinstance(path, str) and path.startswith(".active_dl_"):
                marker_fd[0] = fd
                marker_name[0] = path[len(".active_"):]
            return fd
        module.os.open = open_hook
        module.os.close = close_hook
        sys.argv = ["secure_output.py", cache, "dl", "--active-marker", "--max-transfer-bytes", "0", "--safety-margin", "0", "--", "sh", "-c", "printf payload"]
        raise SystemExit(module.main())
    """)
    result = run(sys.executable, "-c", probe, SECURE_OUTPUT, CACHE_EVICT, cache)
    names = [name for name in os.listdir(cache) if name.startswith("dl_")]
    check("live marker survives eviction before output publication", result.returncode == 0 and len(names) == 1 and open(os.path.join(cache, names[0]), "rb").read() == b"payload")

with tempfile.TemporaryDirectory() as cache:
    source = os.path.join(cache, "dl_source")
    target = os.path.join(cache, "open_target")
    with open(source, "wb") as f:
        f.write(b"payload")
    os.chmod(source, 0o600)
    probe = textwrap.dedent("""
        import importlib.util, os, subprocess, sys
        helper, evict, cache, source, target = sys.argv[1:]
        spec = importlib.util.spec_from_file_location("secure_finalize", helper)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        original_write_marker = module._write_marker
        fired = [False]
        def write_marker(name):
            result = original_write_marker(name)
            if name == target and not fired[0]:
                fired[0] = True
                subprocess.run([sys.executable, evict, cache, "0"], check=False)
                if not os.path.exists(os.path.join(cache, ".active_" + target)):
                    raise RuntimeError("eviction removed live pre-link marker")
            return result
        module._write_marker = write_marker
        sys.argv = ["secure_finalize.py", cache, source, target]
        raise SystemExit(module.main())
    """)
    result = run(sys.executable, "-c", probe, SECURE_FINALIZE, CACHE_EVICT, cache, "dl_source", "open_target")
    check("live marker survives eviction before finalization link", result.returncode == 0 and not os.path.exists(source) and open(target, "rb").read() == b"payload")

stderr_flood = run(sys.executable, TRANSFER_OUTPUT, "100", "--", "sh", "-c", "for i in $(seq 1 1000); do printf x >&2; done")
check("HTTP stderr wrapper bounds producer output", stderr_flood.returncode != 0 and len(stderr_flood.stderr) <= 100)

print(f"=== {passed} passed, {failed} failed ===")
sys.exit(1 if failed else 0)
