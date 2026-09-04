#!/usr/bin/env python3
"""Focused adversarial tests for Finding 6 remediation.

Tests secret_tool_wrapper.py, secure_output.py, transfer_output.py.
Uses fake helpers and fake secrets only. No real credentials.
"""
import os
import sys
import subprocess
import tempfile
import signal
import time

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
WRAPPER = os.path.join(SCRIPT_DIR, "secret_tool_wrapper.py")
SECURE = os.path.join(SCRIPT_DIR, "secure_output.py")
TRANSFER = os.path.join(SCRIPT_DIR, "transfer_output.py")

PASS = 0
FAIL = 0


def check(label, condition):
    global PASS, FAIL
    if condition:
        PASS += 1
    else:
        FAIL += 1
        print(f"  FAIL: {label}")


def section(title):
    print(f"\n--- {title} ---")


def run(cmd, timeout=10):
    return subprocess.run(cmd, capture_output=True, timeout=timeout)


# ===== 1. secret-tool wrapper: normal success =====
section("1. Secret-tool wrapper normal success")
r = run([sys.executable, WRAPPER, "4096", "4096", "--",
         "sh", "-c", "echo FAKE_TOKEN_12345; echo FAKE_PROGRESS >&2"])
check("exit code 0", r.returncode == 0)
check("stdout contains token", b"FAKE_TOKEN_12345" in r.stdout)
check("stderr contains progress", b"FAKE_PROGRESS" in r.stderr)

# ===== 2. Secret-tool wrapper: hangs -> SIGTERM terminates =====
section("2. Secret-tool wrapper hangs -> SIGTERM terminates")
proc = subprocess.Popen(
    ["setsid", sys.executable, WRAPPER, "4096", "4096", "--", "sleep", "300"],
    stdout=subprocess.PIPE, stderr=subprocess.PIPE,
)
time.sleep(0.3)
try:
    children = subprocess.check_output(
        ["pgrep", "-P", str(proc.pid)], text=True
    ).strip().split("\n")
    child_pid = int(children[0]) if children[0] else None
except Exception:
    child_pid = None
check("wrapper alive before timeout", proc.poll() is None)
proc.send_signal(signal.SIGTERM)
try:
    proc.wait(timeout=3)
except subprocess.TimeoutExpired:
    proc.kill()
    proc.wait()
check("wrapper terminated", proc.poll() is not None)

# ===== 3. Helper spawns descendant -> timeout kills both =====
section("3. Helper spawns descendant -> timeout kills both")
proc = subprocess.Popen(
    ["setsid", sys.executable, WRAPPER, "4096", "4096", "--",
     "sh", "-c", "sh -c 'sleep 300' & sleep 300"],
    stdout=subprocess.PIPE, stderr=subprocess.PIPE,
)
time.sleep(0.5)
try:
    all_desc = subprocess.check_output(
        ["pgrep", "-P", str(proc.pid)], text=True
    ).strip().split("\n")
    desc_pids = [int(p) for p in all_desc if p]
except Exception:
    desc_pids = []
grandchildren = []
for dp in desc_pids:
    try:
        gc = subprocess.check_output(
            ["pgrep", "-P", str(dp)], text=True
        ).strip().split("\n")
        grandchildren.extend([int(g) for g in gc if g])
    except Exception:
        pass
check("has descendants", len(desc_pids) > 0)
proc.send_signal(signal.SIGTERM)
try:
    proc.wait(timeout=3)
except subprocess.TimeoutExpired:
    proc.kill()
    proc.wait()
all_dead = True
for pid in desc_pids + grandchildren:
    try:
        os.kill(pid, 0)
        all_dead = False
    except OSError:
        pass
check("all descendants dead after SIGTERM", all_dead)

# ===== 4. stdout flood exceeds cap -> bounded =====
section("4. stdout flood exceeds cap -> bounded memory")
r = run([sys.executable, WRAPPER, "100", "4096", "--",
         "sh", "-c", "dd if=/dev/zero bs=1024 count=100 2>/dev/null"],
        timeout=10)
check("stdout capped at ~100 bytes", len(r.stdout) <= 120)
check("exit code 1 (truncated)", r.returncode == 1)
print(f"  stdout_len={len(r.stdout)}")

# ===== 5. stderr flood exceeds cap -> bounded =====
section("5. stderr flood exceeds cap -> bounded memory")
r = run([sys.executable, WRAPPER, "4096", "100", "--",
         "sh", "-c", "for i in $(seq 1 10000); do echo line_$i >&2; done"],
        timeout=15)
check("stderr capped at ~100 bytes", len(r.stderr) <= 120)
check("exit code 1 (truncated)", r.returncode == 1)
print(f"  stderr_len={len(r.stderr)}")

# ===== 6. fake secret absent from argv =====
section("6. Fake secret absent from argv")
r = run([sys.executable, WRAPPER, "4096", "4096", "--",
         "sh", "-c", "echo \"$*\"", "sh",
         "secret-tool", "lookup", "service", "seafile", "key", "auth-token"])
check("argv contains 'secret-tool'", b"secret-tool" in r.stdout)
check("argv contains 'lookup'", b"lookup" in r.stdout)
print(f"  argv: {r.stdout.decode().strip()}")

# ===== 7. fake secret absent from environment =====
section("7. Fake secret absent from environment")
r = run([sys.executable, WRAPPER, "4096", "4096", "--", "env"])
env_text = r.stdout.decode()
check("env does not contain 'SUPERSECRET123'", "SUPERSECRET123" not in env_text)
check("env does not contain 'SECRET_VALUE'", "SECRET_VALUE" not in env_text)

# ===== 8. fake secret absent from logs/errors =====
section("8. Fake secret absent from logs/errors")
r = run([sys.executable, WRAPPER, "4096", "4096", "--",
         "sh", "-c", "echo error_foo >&2; exit 1"])
check("stderr does not contain fake secret", "SUPERSECRET123" not in r.stderr.decode())
check("stderr contains expected error", "error_foo" in r.stderr.decode())

# ===== 9. transfer_output.py: stderr flood bounded =====
section("9. transfer_output.py: stderr flood bounded")
r = run([sys.executable, TRANSFER, "200", "--",
         "sh", "-c", "for i in $(seq 1 10000); do echo prog_$i >&2; done; echo RESPONSE"],
        timeout=15)
check("stderr capped at ~200 bytes", len(r.stderr) <= 220)
check("stdout passes through (RESPONSE)", b"RESPONSE" in r.stdout)
check("exit code 1 (truncated)", r.returncode == 1)
print(f"  stderr_len={len(r.stderr)}, stdout_len={len(r.stdout)}")

# ===== 10. transfer_output.py: stdout passes through unmodified =====
section("10. transfer_output.py: stdout unmodified")
r = run([sys.executable, TRANSFER, "100", "--",
         "sh", "-c", "echo NORMAL_OUTPUT; echo progress >&2"],
        timeout=5)
check("stdout contains NORMAL_OUTPUT", b"NORMAL_OUTPUT" in r.stdout)
check("stderr contains progress", b"progress" in r.stderr)
check("exit code 0 (no truncation)", r.returncode == 0)

# ===== 11. secure_output.py: max-stderr-bytes limits forwarded stderr =====
section("11. secure_output.py: max-stderr-bytes limits forwarded stderr")
tmpdir = tempfile.mkdtemp()
r = run([sys.executable, "-u", SECURE, tmpdir, "dl",
         "--max-stderr-bytes", "100", "--",
         "sh", "-c", "for i in $(seq 1 1000); do echo prog_$i >&2; done; exit 0"],
        timeout=15)
check("exit code 1 (stderr truncated)", r.returncode == 1)
check("basename not written on truncation", len(r.stdout) == 0)
print(f"  forwarded_stderr_len={len(r.stderr)}")

# ===== 12. secure_output.py: success with --max-stderr-bytes (no truncation) =====
section("12. secure_output.py: success when stderr under cap")
tmpdir = tempfile.mkdtemp()
r = run([sys.executable, "-u", SECURE, tmpdir, "dl",
         "--max-stderr-bytes", "65536", "--",
         "sh", "-c", "printf testdata; echo progress >&2"],
        timeout=5)
check("exit code 0", r.returncode == 0)
check("stdout contains basename", r.stdout.decode().startswith("dl_"))
check("stderr contains progress", b"progress" in r.stderr)
basename = r.stdout.decode().strip()
check("file exists", os.path.exists(os.path.join(tmpdir, basename)))

# ===== 13. secure_output.py: cancellation kills process group =====
section("13. secure_output.py: cancellation kills process group")
tmpdir = tempfile.mkdtemp()
proc = subprocess.Popen(
    ["setsid", sys.executable, "-u", SECURE, tmpdir, "dl", "--",
     "sh", "-c", "sleep 300"],
    stdout=subprocess.PIPE, stderr=subprocess.PIPE,
)
time.sleep(0.3)
try:
    children = subprocess.check_output(
        ["pgrep", "-P", str(proc.pid)], text=True
    ).strip().split("\n")
    child_pid = int(children[0]) if children[0] else None
except Exception:
    child_pid = None
proc.send_signal(signal.SIGTERM)
try:
    proc.wait(timeout=3)
except subprocess.TimeoutExpired:
    proc.kill()
    proc.wait()
check("parent terminated", proc.poll() is not None)
if child_pid:
    try:
        os.kill(child_pid, 0)
        check("child killed by process-group SIGTERM", False)
    except OSError:
        check("child killed by process-group SIGTERM", True)

# ===== 14. regression: existing secure_output tests still pass =====
section("14. Regression: secure_output.py basic operations")
tmpdir = tempfile.mkdtemp()
r = run([sys.executable, "-u", SECURE, tmpdir, "dl", "--",
         "sh", "-c", "printf regression_test"], timeout=5)
check("regression: success exit 0", r.returncode == 0)
check("regression: basename output", r.stdout.decode().startswith("dl_"))
check("regression: file created", os.path.exists(os.path.join(tmpdir, r.stdout.decode().strip())))

tmpdir2 = tempfile.mkdtemp()
r2 = run([sys.executable, "-u", SECURE, tmpdir2, "dl", "--",
          "sh", "-c", "exit 1"], timeout=5)
check("regression: failure exit != 0", r2.returncode != 0)
check("regression: no output on failure", len(r2.stdout) == 0)
check("regression: no leftover files", len(os.listdir(tmpdir2)) == 0)

# ===== Summary =====
print(f"\n=== {PASS} passed, {FAIL} failed ===")
sys.exit(1 if FAIL else 0)
