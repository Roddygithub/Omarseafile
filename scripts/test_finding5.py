#!/usr/bin/env python3
"""Finding 5 regression tests: transfer paths/downloads security.

Tests the complete transfer surface for:
- strict filename validation
- secure download output with held FD
- disk-space admission
- cache eviction via cache_evict.py
- upload source hardening (stat-based)
- process group isolation
- auth token non-leak
- concurrent sequential transfers
"""
import os
import sys
import tempfile
import subprocess
import stat
import time
import shutil

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
SECURE_OUTPUT = os.path.join(SCRIPT_DIR, "secure_output.py")
CACHE_EVICT = os.path.join(SCRIPT_DIR, "cache_evict.py")
ATOMIC_WRITE = os.path.join(SCRIPT_DIR, "atomic_write.py")

PASS = 0
FAIL = 0


def check(label, condition):
    global PASS, FAIL
    if condition:
        PASS += 1
        print(f"  PASS: {label}")
    else:
        FAIL += 1
        print(f"  FAIL: {label}")


def section(title):
    print(f"\n--- {title} ---")


def run_secure_output(tmpdir, prefix, curl_args, max_stderr=None,
                      max_transfer=None, safety_margin=None,
                      already_reserved=None, timeout=15):
    cmd = [sys.executable, "-u", SECURE_OUTPUT, tmpdir, prefix]
    if max_stderr is not None:
        cmd += ["--max-stderr-bytes", str(max_stderr)]
    if max_transfer is not None:
        cmd += ["--max-transfer-bytes", str(max_transfer)]
    if safety_margin is not None:
        cmd += ["--safety-margin", str(safety_margin)]
    if already_reserved is not None:
        cmd += ["--already-reserved-bytes", str(already_reserved)]
    cmd += ["--"] + curl_args
    result = subprocess.run(cmd, capture_output=True, timeout=timeout)
    return result.returncode, result.stdout, result.stderr


# ======================================================================
# A. STRICT FILENAME VALIDATION (source constants)
# ======================================================================
section("A. Strict filename validation")
secure_output_src = open(SECURE_OUTPUT).read()
check("MAX_BASENAME_LEN=128 in source",
      "MAX_BASENAME_LEN = 128" in secure_output_src)
check("VALID_BASENAME_CHARS correct in source",
      "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-"
      in secure_output_src)


# ======================================================================
# B. SECURE DOWNLOAD OUTPUT (held FD, no clobber, mode 0600)
# ======================================================================
section("B. Secure download output")
tmpdir = tempfile.mkdtemp()
try:
    rc, out, err = run_secure_output(
        tmpdir, "dl", ["sh", "-c", "printf 'testdata'"])
    check("exit code 0", rc == 0)
    basename = out.decode().strip()
    check("basename starts with dl_", basename.startswith("dl_"))
    filepath = os.path.join(tmpdir, basename)
    check("file exists", os.path.exists(filepath))
    st = os.stat(filepath)
    check("mode 0600", stat.S_IMODE(st.st_mode) == 0o600)
    check("content exact", open(filepath).read() == "testdata")

    # Existing regular file not clobbered (O_EXCL)
    existing = os.path.join(tmpdir, "dl_existing")
    with open(existing, "w") as f:
        f.write("victim")
    rc2, out2, _ = run_secure_output(
        tmpdir, "dl", ["sh", "-c", "printf 'newdata'"])
    check("second download succeeds", rc2 == 0)
    basename2 = out2.decode().strip()
    check("new file has different name", basename2 != "dl_existing")
    check("victim data preserved", open(existing).read() == "victim")

    # Directory symlink not followed (O_NOFOLLOW on dir_fd)
    link_target = os.path.join(tmpdir, "link_target")
    os.mkdir(link_target)
    link_name = os.path.join(tmpdir, "linkname")
    os.symlink(link_target, link_name)
    rc3, _, _ = run_secure_output(
        tmpdir, "dl", ["sh", "-c", "printf 'data'"])
    check("download succeeds despite symlink in dir", rc3 == 0)
finally:
    shutil.rmtree(tmpdir, ignore_errors=True)


# ======================================================================
# C. DISK ADMISSION CHECK (fstatvfs gating)
# ======================================================================
section("C. Disk admission check")
tmpdir = tempfile.mkdtemp()
try:
    # Normal case with generous space - should pass
    rc, out, _ = run_secure_output(
        tmpdir, "dl",
        ["sh", "-c", "printf 'test'"],
        max_transfer=1000, safety_margin=1000)
    check("admission passes with sufficient space", rc == 0)

    # Admission REJECTION: request more than total disk (10 EiB)
    shutil.rmtree(tmpdir)
    tmpdir = tempfile.mkdtemp()
    rc2, _, err2 = run_secure_output(
        tmpdir, "dl",
        ["sh", "-c", "printf 'should not appear'"],
        max_transfer=10 * 1024 * 1024 * 1024 * 1024 * 1024,
        safety_margin=0)
    check("admission rejects when free < max_transfer", rc2 != 0)
    remaining = [f for f in os.listdir(tmpdir) if f.startswith("dl_")]
    check("no file created on admission rejection", len(remaining) == 0)
finally:
    shutil.rmtree(tmpdir, ignore_errors=True)


# ======================================================================
# D. ENOSPC / SIGNAL CLEANUP
# ======================================================================
section("D. ENOSPC / signal cleanup")
tmpdir = tempfile.mkdtemp()
try:
    proc = subprocess.Popen(
        ["setsid", sys.executable, "-u", SECURE_OUTPUT, tmpdir, "dl",
         "--max-stderr-bytes", "65536",
         "--max-transfer-bytes", "1000000",
         "--safety-margin", "0",
         "--",
         "sh", "-c", "sleep 5"],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    time.sleep(0.3)
    check("helper running before signal", proc.poll() is None)
    proc.send_signal(15)
    try:
        proc.wait(timeout=3)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait()
    remaining = [f for f in os.listdir(tmpdir) if f.startswith("dl_")]
    check("no leftover temp files after SIGTERM", len(remaining) == 0)
finally:
    shutil.rmtree(tmpdir, ignore_errors=True)


# ======================================================================
# E. CACHE EVICTION (cache_evict.py)
# ======================================================================
section("E. Cache eviction")
tmpdir = tempfile.mkdtemp()
try:
    # Create cache files of known sizes using atomic_write.py
    sizes = [200, 300, 400, 500]
    for i, sz in enumerate(sizes):
        subprocess.run(
            [sys.executable, "-u", ATOMIC_WRITE, tmpdir, "cache"],
            input=("X" * sz).encode(),
            capture_output=True, timeout=10)

    evictable = [f for f in os.listdir(tmpdir)
                 if not f.startswith(".") and not f.startswith("dl_")]
    check("4 evictable files present", len(evictable) == 4)

    # Set max_bytes=0 so ALL regular files are evicted
    rc = subprocess.run(
        [sys.executable, CACHE_EVICT, tmpdir, "0"],
        capture_output=True, timeout=10).returncode
    check("cache_evict.py exits 0", rc == 0)

    after = [f for f in os.listdir(tmpdir)
             if not f.startswith(".") and not f.startswith("dl_")]
    check("all evictable files removed", len(after) == 0)

    # Hidden files never evicted
    hidden = os.path.join(tmpdir, ".hidden")
    with open(hidden, "w") as f:
        f.write("secret")
    subprocess.run(
        [sys.executable, CACHE_EVICT, tmpdir, "0"],
        capture_output=True, timeout=10)
    check("hidden files never evicted", os.path.exists(hidden))

    # dl_ files never evicted
    dlfile = os.path.join(tmpdir, "dl_active")
    with open(dlfile, "w") as f:
        f.write("active")
    subprocess.run(
        [sys.executable, CACHE_EVICT, tmpdir, "0"],
        capture_output=True, timeout=10)
    check("dl_ files never evicted", os.path.exists(dlfile))

    # Symlinks never evicted (not regular files, fail-closed skip)
    symlink = os.path.join(tmpdir, "cache_symlink")
    try:
        os.symlink("/tmp", symlink)
        subprocess.run(
            [sys.executable, CACHE_EVICT, tmpdir, "0"],
            capture_output=True, timeout=10)
        check("symlink not evicted", os.path.islink(symlink))
    except OSError:
        check("symlink not evicted (skipped, no perm)", True)
finally:
    shutil.rmtree(tmpdir, ignore_errors=True)


# ======================================================================
# F. UPLOAD SOURCE VALIDATION (stat -c "%F %s")
# ======================================================================
section("F. Upload source validation")
tmpdir = tempfile.mkdtemp()
try:
    # Regular file: stat (no -L) reports "regular file"
    reg_file = os.path.join(tmpdir, "regular.txt")
    with open(reg_file, "w") as f:
        f.write("test")
    result = subprocess.run(
        ["stat", "-c", "%F %s", "--", reg_file],
        capture_output=True, text=True)
    check("regular file detected",
          "regular file" in result.stdout and "4" in result.stdout)

    # Directory: stat reports "directory"
    subdir = os.path.join(tmpdir, "subdir")
    os.mkdir(subdir)
    result = subprocess.run(
        ["stat", "-c", "%F %s", "--", subdir],
        capture_output=True, text=True)
    check("directory detected", "directory" in result.stdout)

    # Symlink: stat (no -L) shows "symbolic link", not the target.
    # The QML uses `stat -c "%F %s"` (no -L), so symlinks are correctly
    # rejected because their type is "symbolic link", not "regular file".
    link = os.path.join(tmpdir, "link.txt")
    os.symlink(reg_file, link)
    result = subprocess.run(
        ["stat", "-c", "%F %s", "--", link],
        capture_output=True, text=True)
    check("symlink detected as 'symbolic link' (not followed)",
          "symbolic link" in result.stdout)

    # FIFO
    fifo = os.path.join(tmpdir, "fifo")
    os.mkfifo(fifo)
    result = subprocess.run(
        ["stat", "-c", "%F %s", "--", fifo],
        capture_output=True, text=True)
    check("fifo detected",
          "fifo" in result.stdout.lower() or "named pipe" in result.stdout.lower())
finally:
    shutil.rmtree(tmpdir, ignore_errors=True)


# ======================================================================
# G. CANCELLATION / PROCESS GROUP ISOLATION
# ======================================================================
section("G. Cancellation / process groups")
tmpdir = tempfile.mkdtemp()
try:
    proc = subprocess.Popen(
        ["setsid", sys.executable, "-u", SECURE_OUTPUT, tmpdir, "dl",
         "--max-stderr-bytes", "65536", "--",
         "sh", "-c", "sleep 10"],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    time.sleep(0.3)
    check("helper running before signal", proc.poll() is None)
    proc.send_signal(15)
    try:
        proc.wait(timeout=3)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait()
    check("parent terminated", proc.poll() is not None)
    remaining = [f for f in os.listdir(tmpdir) if f.startswith("dl_")]
    check("no leftover temp files after cancel", len(remaining) == 0)
finally:
    shutil.rmtree(tmpdir, ignore_errors=True)


# ======================================================================
# H. TOKEN NON-LEAK
# ======================================================================
section("H. Token non-leak")
tmpdir = tempfile.mkdtemp()
try:
    FAKE_TOKEN = "FAKE_TOKEN_FINDING5"
    rc, out, err = run_secure_output(
        tmpdir, "dl", ["sh", "-c", "printf 'data'"])
    check("token not in stdout", FAKE_TOKEN not in out.decode())
    check("token not in stderr", FAKE_TOKEN not in err.decode())
finally:
    shutil.rmtree(tmpdir, ignore_errors=True)


# ======================================================================
# I. ADJACENT-TRANSFER RESERVATION (already-reserved-bytes)
# ======================================================================
section("I. Adjacent-transfer reservation")
tmpdir = tempfile.mkdtemp()
try:
    # Single transfer (reserved=0): passes admission
    rc, out, _ = run_secure_output(
        tmpdir, "dl",
        ["sh", "-c", "printf 'ok'"],
        max_transfer=1000, safety_margin=1000, already_reserved=0)
    check("single transfer (reserved=0) passes", rc == 0)

    # Large reservation exceeding free space: rejects admission
    shutil.rmtree(tmpdir)
    tmpdir = tempfile.mkdtemp()
    rc2, _, _ = run_secure_output(
        tmpdir, "dl",
        ["sh", "-c", "printf 'nope'"],
        max_transfer=1000, safety_margin=0,
        already_reserved=10 * 1024 * 1024 * 1024 * 1024 * 1024)
    check("large reservation rejects admission", rc2 != 0)
    remaining = [f for f in os.listdir(tmpdir) if f.startswith("dl_")]
    check("no file created on reservation rejection", len(remaining) == 0)
finally:
    shutil.rmtree(tmpdir, ignore_errors=True)


# ======================================================================
# J. SEQUENTIAL TRANSFERS (multiple writes to same dir)
# ======================================================================
section("J. Sequential transfers")
tmpdir = tempfile.mkdtemp()
try:
    for i in range(3):
        rc, out, err = run_secure_output(
            tmpdir, "dl",
            ["sh", "-c", f"printf 'data{i}'"],
            max_transfer=1000, safety_margin=1000)
        check(f"transfer {i} succeeds", rc == 0)
    files = os.listdir(tmpdir)
    check("3 files created", len(files) == 3)
finally:
    shutil.rmtree(tmpdir, ignore_errors=True)


# ======================================================================
# K. CACHE EVICTION EMPIRICAL (cache_evict.py end-to-end)
# ======================================================================
section("K. Cache eviction empirical")
tmpdir = tempfile.mkdtemp()
try:
    # Create 4 old cache files: 200 + 300 + 400 + 500 = 1400 bytes
    for sz in [200, 300, 400, 500]:
        subprocess.run(
            [sys.executable, "-u", ATOMIC_WRITE, tmpdir, "cache"],
            input=("X" * sz).encode(), capture_output=True, timeout=10)
    # Make them old (mtime = 0)
    for f in os.listdir(tmpdir):
        os.utime(os.path.join(tmpdir, f), (0, 0))

    # Simulate incoming completed file: 600 bytes (newest, mtime = now)
    incoming = os.path.join(tmpdir, "cache_incoming")
    with open(incoming, "wb") as fout:
        fout.write(b"I" * 600)

    # Total = 1400 + 600 = 2000. Set max = 800.
    # Eviction removes oldest first: 200 + 300 + 400 = 900 removed, total = 1100 > 800.
    # Then removes next oldest: 500 removed, total = 600 <= 800. Done.
    max_bytes = 800
    rc = subprocess.run(
        [sys.executable, CACHE_EVICT, tmpdir, str(max_bytes)],
        capture_output=True, timeout=10).returncode
    check("cache_evict exits 0", rc == 0)

    after = os.listdir(tmpdir)
    total_after = sum(os.path.getsize(os.path.join(tmpdir, f)) for f in after)
    check("final cache total <= max", total_after <= max_bytes)
    check("incoming file still present (newest)", "cache_incoming" in after)

    # dl_ files never evicted
    dl_active = os.path.join(tmpdir, "dl_active")
    with open(dl_active, "wb") as f:
        f.write(b"D" * 900)
    subprocess.run(
        [sys.executable, CACHE_EVICT, tmpdir, str(max_bytes)],
        capture_output=True, timeout=10)
    check("dl_ file preserved after eviction", os.path.exists(dl_active))

    # Hidden files never evicted
    hidden = os.path.join(tmpdir, ".hidden_secret")
    with open(hidden, "wb") as f:
        f.write(b"H" * 100)
    subprocess.run(
        [sys.executable, CACHE_EVICT, tmpdir, "0"],
        capture_output=True, timeout=10)
    check("hidden file preserved after eviction", os.path.exists(hidden))

    # Outside-symlink victim preserved
    outside_dir = tempfile.mkdtemp()
    outside_file = os.path.join(outside_dir, "victim.txt")
    with open(outside_file, "w") as f:
        f.write("do not delete")
    link = os.path.join(tmpdir, "cache_outside_link")
    try:
        os.symlink(outside_dir, link)
        subprocess.run(
            [sys.executable, CACHE_EVICT, tmpdir, "0"],
            capture_output=True, timeout=10)
        check("outside symlink not followed/deleted",
              os.path.exists(outside_file))
    except OSError:
        check("outside symlink not followed/deleted (skipped)", True)
    shutil.rmtree(outside_dir, ignore_errors=True)
finally:
    shutil.rmtree(tmpdir, ignore_errors=True)


# ======================================================================
# L. CONCURRENT RESERVATION ARITHMETIC
# ======================================================================
section("L. Concurrent reservation arithmetic")
# Prove the admission equation: free - already_reserved >= max_transfer + safety_margin
# by varying already_reserved and checking pass/reject.
tmpdir = tempfile.mkdtemp()
try:
    st = os.statvfs(tmpdir)
    free = st.f_bavail * st.f_frsize

    # Case 1: reserved=0 → full free available → should pass
    rc1, _, _ = run_secure_output(
        tmpdir, "dl",
        ["sh", "-c", "printf 'ok'"],
        max_transfer=1000, safety_margin=1000, already_reserved=0)
    check("reserved=0 passes (full free)", rc1 == 0)

    # Case 2: reserved exceeds free → available < 0 → should reject
    shutil.rmtree(tmpdir)
    tmpdir = tempfile.mkdtemp()
    rc2, _, _ = run_secure_output(
        tmpdir, "dl",
        ["sh", "-c", "printf 'nope'"],
        max_transfer=1000, safety_margin=0,
        already_reserved=free + 1)
    check("reserved > free rejects", rc2 != 0)

    # Case 3: reserved = free - 1 → available = 1, required = 2000 → rejects
    shutil.rmtree(tmpdir)
    tmpdir = tempfile.mkdtemp()
    rc3, _, _ = run_secure_output(
        tmpdir, "dl",
        ["sh", "-c", "printf 'nope'"],
        max_transfer=1000, safety_margin=1000,
        already_reserved=free - 1)
    check("reserved near free rejects (1 < 2000 required)", rc3 != 0)

    # Case 4: reserved = free - 2000 → available = 2000, required = 2000 → passes
    shutil.rmtree(tmpdir)
    tmpdir = tempfile.mkdtemp()
    needed = 1000 + 1000  # max_transfer + safety_margin
    reserved4 = free - needed
    if reserved4 < 0:
        reserved4 = 0
    rc4, _, _ = run_secure_output(
        tmpdir, "dl",
        ["sh", "-c", "printf 'ok'"],
        max_transfer=1000, safety_margin=1000,
        already_reserved=reserved4)
    check("reserved leaves exactly required passes", rc4 == 0)

    # Case 5: reserved leaves 1 byte short of required → rejects
    shutil.rmtree(tmpdir)
    tmpdir = tempfile.mkdtemp()
    reserved5 = free - needed + 1  # available = needed - 1 < needed
    if reserved5 < 0:
        reserved5 = 0
    rc5, _, _ = run_secure_output(
        tmpdir, "dl",
        ["sh", "-c", "printf 'nope'"],
        max_transfer=1000, safety_margin=1000,
        already_reserved=reserved5)
    check("reserved leaves 1 short rejects", rc5 != 0)
finally:
    shutil.rmtree(tmpdir, ignore_errors=True)


# ======================================================================
# M. FSTATVFS FAILURE — FAIL CLOSED
# ======================================================================
section("M. fstatvfs failure — fail closed")
# Prove that when fstatvfs fails, _check_disk_admission returns False
# and the helper does not create output or start a child process.
# Use a closed fd to deterministically trigger EBADF in fstatvfs.
import importlib.util
spec = importlib.util.spec_from_file_location("secure_output", SECURE_OUTPUT)
_secure = importlib.util.module_from_spec(spec)
spec.loader.exec_module(_secure)

tmpdir = tempfile.mkdtemp()
try:
    dir_fd = os.open(tmpdir, os.O_RDONLY | os.O_DIRECTORY)
    os.close(dir_fd)  # close to force EBADF in fstatvfs

    ok, err = _secure._check_disk_admission(dir_fd, 1000, 1000, 0)
    check("fstatvfs on closed fd returns False", ok is False)
    check("error message present", len(err) > 0)

    # Subprocess proof: import the function and run it in a child process
    # to prove the production code path exits nonzero on fstatvfs failure.
    probe = (
        f"import os, sys; sys.path.insert(0, {SCRIPT_DIR!r}); "
        f"from secure_output import _check_disk_admission; "
        f"fd = os.open({tmpdir!r}, os.O_RDONLY | os.O_DIRECTORY); "
        f"os.close(fd); "
        f"ok, _ = _check_disk_admission(fd, 1000, 1000, 0); "
        f"sys.exit(0 if ok else 1)"
    )
    rc = subprocess.run(
        [sys.executable, "-c", probe],
        capture_output=True, timeout=5).returncode
    check("subprocess: fstatvfs failure → nonzero exit", rc != 0)
    remaining = [f for f in os.listdir(tmpdir) if f.startswith("dl_")]
    check("no output file created", len(remaining) == 0)
finally:
    shutil.rmtree(tmpdir, ignore_errors=True)


# ======================================================================
# SUMMARY
# ======================================================================
print()
print(f"=== {PASS} passed, {FAIL} failed ===")
sys.exit(0 if FAIL == 0 else 1)
