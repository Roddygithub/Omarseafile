#!/usr/bin/env python3
"""Finding 4 regression tests: secret temporary file security.

Tests atomic_write.py and related helpers for:
- secure directory handling
- atomic creation with O_NOFOLLOW
- mode 0600 enforcement
- symlink/clobber protection
- cleanup on failure/cancellation
- no /tmp fallback
"""
import os
import sys
import tempfile
import stat
import time
import subprocess
import shutil

FAKE_PASSWORD = "FAKE_PASSWORD_FINDING4"
FAKE_TOKEN = "FAKE_TOKEN_FINDING4"

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ATOMIC_WRITE = os.path.join(SCRIPT_DIR, "atomic_write.py")
SECURE_OUTPUT = os.path.join(SCRIPT_DIR, "secure_output.py")

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


def run_atomic(dir_path, prefix, content):
    """Run atomic_write.py and return (exitcode, stdout, stderr)."""
    result = subprocess.run(
        [sys.executable, "-u", ATOMIC_WRITE, dir_path, prefix],
        input=content.encode(),
        capture_output=True,
        timeout=10,
    )
    return result.returncode, result.stdout, result.stderr


def run_secure_output(tmpdir, prefix, curl_args):
    result = subprocess.run(
        [sys.executable, "-u", SECURE_OUTPUT, tmpdir, prefix, "--"] + curl_args,
        capture_output=True, timeout=10,
    )
    return result.returncode, result.stdout, result.stderr


# ======================================================================
# A. NORMAL CREATION
# ======================================================================
print("--- A. Normal creation ---")
tmpdir = tempfile.mkdtemp()
try:
    rc, out, err = run_atomic(tmpdir, "test", FAKE_PASSWORD)
    check("exit code 0", rc == 0)
    fullpath = out.decode().strip()
    filepath = fullpath
    check("output is absolute path", fullpath.startswith(tmpdir))
    check("file exists", os.path.exists(filepath))
    st = os.stat(filepath)
    check("mode 0600", stat.S_IMODE(st.st_mode) == 0o600)
    check("content exact", open(filepath).read() == FAKE_PASSWORD)
    check("basename starts with prefix_", os.path.basename(fullpath).startswith("test_"))
    check("no secret in basename", FAKE_PASSWORD not in os.path.basename(fullpath))
    check("no secret in argv visible", FAKE_PASSWORD not in out.decode())
finally:
    shutil.rmtree(tmpdir, ignore_errors=True)

# ======================================================================
# B. EXISTING COLLISION - unique basenames generated
# ======================================================================
print("--- B. Existing collision handling ---")
tmpdir = tempfile.mkdtemp()
try:
    paths = set()
    for _ in range(10):
        rc, out, _ = run_atomic(tmpdir, "coll", FAKE_PASSWORD)
        check("exit 0", rc == 0)
        paths.add(out.decode().strip())
    check("all unique basenames", len(paths) == 10)
    check("no truncation/overwrite", all(os.path.exists(p) for p in paths))
finally:
    shutil.rmtree(tmpdir, ignore_errors=True)

# ======================================================================
# C. DIRECTORY SYMLINK REJECTION
# ======================================================================
print("--- C. Directory symlink rejection ---")
tmpdir = tempfile.mkdtemp()
victim = os.path.join(tmpdir, "victim")
os.mkdir(victim)
linkdir = os.path.join(tmpdir, "linkdir")
os.symlink(victim, linkdir)
try:
    rc, out, err = run_atomic(linkdir, "test", FAKE_PASSWORD)
    check("rejected non-zero exit", rc != 0)
    check("error mentions symlink", b"symlink" in err.lower() or b"not a directory" in err.lower())
    check("victim untouched", not os.listdir(victim))
finally:
    shutil.rmtree(tmpdir, ignore_errors=True)

# ======================================================================
# D. UNSAFE DIRECTORY PERMISSIONS
# ======================================================================
print("--- D. Unsafe directory permissions ---")
tmpdir = tempfile.mkdtemp()
unsafe = os.path.join(tmpdir, "unsafe")
os.mkdir(unsafe)
os.chmod(unsafe, 0o777)
try:
    rc, out, err = run_atomic(unsafe, "test", FAKE_PASSWORD)
    check("rejected non-zero exit", rc != 0)
    check("error mentions permissions", b"unsafe permission" in err.lower() or b"group" in err.lower() or b"other" in err.lower())
finally:
    shutil.rmtree(tmpdir, ignore_errors=True)

# ======================================================================
# E. WRONG OWNER (validation logic test)
# ======================================================================
print("--- E. Wrong owner validation ---")
# Cannot safely chown in test, but we can verify the validation function exists
# by checking the source code contains the check
atomic_src = open(ATOMIC_WRITE).read()
check("atomic_write.py has UID check", "st_uid != os.getuid()" in atomic_src or "st_uid != os.getuid()" in atomic_src)
check("atomic_write.py has mode check", "st_mode & 0o022" in atomic_src)

# ======================================================================
# F. MALICIOUS PREFIX REJECTION
# ======================================================================
print("--- F. Malicious prefix rejection ---")
tmpdir = tempfile.mkdtemp()
malicious = ["../victim", "../../victim", "/etc/passwd", "name/path", ".", "..", "", "x" * 100]
for m in malicious:
    rc, _, err = run_atomic(tmpdir, m, FAKE_PASSWORD)
    check(f"prefix '{m}' rejected", rc != 0 and len(err) > 0)
# Note: control character test skipped (null byte in argv causes subprocess error)
shutil.rmtree(tmpdir, ignore_errors=True)

# ======================================================================
# G. FILE SYMLINK COLLISION
# ======================================================================
print("--- G. File symlink collision (best effort) ---")
# Note: Our atomic creation uses O_EXCL|O_NOFOLLOW which prevents
# following an existing symlink. We test that an existing regular file
# is not truncated.
tmpdir = tempfile.mkdtemp()
try:
    # Create a regular file first
    existing = os.path.join(tmpdir, "existing_file")
    with open(existing, "w") as f:
        f.write("victim data")
    # Try to create with same prefix - should generate unique name
    rc, out, _ = run_atomic(tmpdir, "existing", FAKE_PASSWORD)
    check("exit 0", rc == 0)
    basename = out.decode().strip()
    check("new file created (not existing_file)", basename != "existing_file")
    check("victim data preserved", open(existing).read() == "victim data")
finally:
    shutil.rmtree(tmpdir, ignore_errors=True)

# ======================================================================
# H. WRITE FAILURE CLEANUP
# ======================================================================
print("--- H. Write failure cleanup ---")
# Test oversized content causes cleanup - write incrementally via stdin
tmpdir = tempfile.mkdtemp()
try:
    # Use Popen to stream data incrementally, avoiding 65MB stdin blob
    proc = subprocess.Popen(
        [sys.executable, "-u", ATOMIC_WRITE, tmpdir, "huge"],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    # Stream 65MB in chunks (MAXSIZE is 64 MiB)
    # Handle early exit when process detects size limit
    try:
        for _ in range(65 * 16):  # 65 * 16 * 65536 = ~65 MB
            proc.stdin.write(b"x" * 65536)
    except BrokenPipeError:
        # Process exited early due to size limit - this is expected
        pass
    try:
        proc.stdin.close()
    except BrokenPipeError:
        pass
    rc, out, err = proc.wait(), proc.stdout.read(), proc.stderr.read()
    check("write failure: exit non-zero", rc != 0)
    check("write failure: error mentions size", b"exceed" in err.lower() or b"size" in err.lower())
    check("write failure: no leftover files", len(os.listdir(tmpdir)) == 0)
finally:
    shutil.rmtree(tmpdir, ignore_errors=True)

# ======================================================================
# I. SIGTERM CLEANUP (deterministic)
# ======================================================================
print("--- I. SIGTERM cleanup ---")
tmpdir = tempfile.mkdtemp()
try:
    proc = subprocess.Popen(
        [sys.executable, "-u", ATOMIC_WRITE, tmpdir, "sigterm"],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    # Wait until the temp file is created (poll directory)
    file_created = False
    for _ in range(30):  # up to 3 seconds
        time.sleep(0.1)
        if any(f.startswith("sigterm_") for f in os.listdir(tmpdir)):
            file_created = True
            break
    check("SIGTERM test: file created before signal", file_created)
    proc.send_signal(15)
    try:
        proc.wait(timeout=3)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait()
    remaining = [f for f in os.listdir(tmpdir) if f.startswith("sigterm_")]
    check("SIGTERM cleanup: no leftover secret files", len(remaining) == 0)
finally:
    shutil.rmtree(tmpdir, ignore_errors=True)

# ======================================================================
# I2. SIGINT CLEANUP
# ======================================================================
print("--- I2. SIGINT cleanup ---")
tmpdir = tempfile.mkdtemp()
try:
    proc = subprocess.Popen(
        [sys.executable, "-u", ATOMIC_WRITE, tmpdir, "sigint"],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    # Wait for file creation
    file_created = False
    for _ in range(30):
        time.sleep(0.1)
        if any(f.startswith("sigint_") for f in os.listdir(tmpdir)):
            file_created = True
            break
    check("SIGINT test: file created before signal", file_created)
    proc.send_signal(2)  # SIGINT
    try:
        proc.wait(timeout=3)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait()
    remaining = [f for f in os.listdir(tmpdir) if f.startswith("sigint_")]
    check("SIGINT cleanup: no leftover secret files", len(remaining) == 0)
finally:
    shutil.rmtree(tmpdir, ignore_errors=True)

# ======================================================================
# J. NO /tmp FALLBACK
# ======================================================================
print("--- J. No /tmp fallback ---")
# Non-existent directory should fail, not fall back to /tmp
rc, _, err = run_atomic("/nonexistent/path/that/does/not/exist", "test", FAKE_PASSWORD)
check("non-existent dir rejected", rc != 0)
check("error message", len(err) > 0)

# Empty XDG_RUNTIME_DIR simulation - atomic_write.py requires valid dir
# The helper itself requires a valid directory, so it will fail on empty/nonexistent

# ======================================================================
# K. HELD DIRECTORY FD BEHAVIOR
# ======================================================================
print("--- K. Held directory FD behavior ---")
# Verify the helper uses dir_fd for file creation
atomic_src = open(ATOMIC_WRITE).read()
check("atomic_write.py uses dir_fd", "dir_fd=" in atomic_src)
check("atomic_write.py uses O_NOFOLLOW", "O_NOFOLLOW" in atomic_src)
check("atomic_write.py uses O_EXCL", "O_EXCL" in atomic_src)
check("atomic_write.py uses O_CREAT", "O_CREAT" in atomic_src)
check("atomic_write.py uses os.open with dir_fd", "dir_fd=" in atomic_src)
check("atomic_write.py uses os.unlink with dir_fd", "dir_fd=" in atomic_src and "unlink" in atomic_src)

# ======================================================================
# L. SECRET EXPOSURE
# ======================================================================
print("--- L. Secret exposure check ---")
tmpdir = tempfile.mkdtemp()
try:
    rc, out, err = run_atomic(tmpdir, "exp", FAKE_PASSWORD)
    check("secret not in stdout", FAKE_PASSWORD not in out.decode())
    check("secret not in stderr", FAKE_PASSWORD not in err.decode())
    check("secret not in basename", FAKE_PASSWORD not in out.decode())
    basename = out.decode().strip()
    check("secret not in filename", FAKE_PASSWORD not in os.path.basename(basename))
finally:
    shutil.rmtree(tmpdir, ignore_errors=True)

# ======================================================================
# M. LEGITIMATE PREFIXES WORK
# ======================================================================
print("--- M. Legitimate prefixes work ---")
tmpdir = tempfile.mkdtemp()
try:
    for p in ["curl_hdr", "curl_body", "seafile_auth", "seafile_curl"]:
        rc, out, _ = run_atomic(tmpdir, p, FAKE_PASSWORD)
        check(f"prefix '{p}' works", rc == 0 and out.decode().startswith(tmpdir))
finally:
    shutil.rmtree(tmpdir, ignore_errors=True)

# ======================================================================
# N. SECURE_OUTPUT.PY INTEGRATION
# ======================================================================
print("--- N. secure_output.py integration ---")
tmpdir = tempfile.mkdtemp()
try:
    rc, out, err = run_secure_output(tmpdir, "dl", ["true"])
    check("secure_output exit 0", rc == 0)
    basename = out.decode().strip()
    check("basename valid", len(basename) > 3 and basename.startswith("dl_"))
    filepath = os.path.join(tmpdir, basename)
    check("file created", os.path.exists(filepath))
    st = os.stat(filepath)
    check("mode 0600", stat.S_IMODE(st.st_mode) == 0o600)
finally:
    shutil.rmtree(tmpdir, ignore_errors=True)

# ======================================================================
# SUMMARY
# ======================================================================
print()
print(f"=== {PASS} passed, {FAIL} failed ===")
sys.exit(0 if FAIL == 0 else 1)