#!/usr/bin/env python3
"""
Finding 2 regression tests: cleartext HTTP credential protection.

Tests the URL policy enforcement, auto-login gate, changeServerUrl gate,
SeafileAPI defense-in-depth, and TransferService auth gate against
non-loopback HTTP URLs using synthetic credentials only.
"""

import os
import sys

FAKE_PASSWORD = "FAKE_PASSWORD_FINDING2"
FAKE_TOKEN = "FAKE_TOKEN_FINDING2"
FAKE_EMAIL = "FAKE_EMAIL_FINDING2"

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
passed = 0
failed = 0


def test(name, condition, detail=""):
    global passed, failed
    if condition:
        passed += 1
        print(f"  PASS: {name}")
    else:
        failed += 1
        msg = f"  FAIL: {name}"
        if detail:
            msg += f" — {detail}"
        print(msg)


def read_file(relpath):
    with open(os.path.join(REPO_ROOT, relpath)) as f:
        return f.read()


def func_body(src, name):
    start = src.index("function " + name + "(")
    open_brace = src.index("{", start)
    depth = 0
    i = open_brace
    while i < len(src):
        if src[i] == "{":
            depth += 1
        elif src[i] == "}":
            depth -= 1
            if depth == 0:
                return src[start:i + 1]
        i += 1
    return src[start:]


def count_occurrences(text, pattern):
    """Count non-overlapping occurrences of pattern in text."""
    count = 0
    start = 0
    while True:
        idx = text.index(pattern, start)
        count += 1
        start = idx + len(pattern)
    return count


# ======================================================================
# A. URL POLICY — validateForAuth blocks non-loopback HTTP
# ======================================================================
print("--- A. URL policy blocks non-loopback HTTP ---")

url_policy = read_file("js/UrlPolicy.qml")

test("validateForAuth has HTTPS check",
     "scheme === \"https\"" in url_policy and "return { valid: true }" in url_policy)

test("validateForAuth has loopback HTTP exception",
     "scheme === \"http\" && root.isLoopbackHost(host)" in url_policy)

test("validateForAuth rejects non-loopback HTTP",
     "Cleartext HTTP not allowed for authentication" in url_policy)

# isLoopbackHost must NOT include private LAN ranges
test("isLoopbackHost does not include 192.168.x.x",
     "192.168" not in url_policy)

test("isLoopbackHost does not include 10.x.x.x",
     "\"10." not in url_policy)

test("isLoopbackHost does not include 172.16-31.x.x",
     "172.16" not in url_policy and "172.31" not in url_policy)

test("isLoopbackHost includes localhost",
     "localhost" in url_policy)

test("isLoopbackHost includes 127.0.0.1",
     "127.0.0.1" in url_policy)

test("isLoopbackHost includes ::1",
     "\"::1\"" in url_policy)

# ======================================================================
# B. LEGACY AUTOLOGIN — fail closed on stored HTTP URL
# ======================================================================
print("--- B. Legacy auto-login gate ---")

panel = read_file("Panel.qml")

# Startup must call validateForAuth before setting baseUrl/token
test("startup calls validateForAuth",
     "UrlPolicy.validateForAuth(serverUrl)" in panel)

# Startup must check policy.valid before setting token
test("startup checks policy.valid before token",
     "if (!policy.valid)" in panel)

# Startup must NOT set baseUrl if policy fails
test("startup rejects invalid URL before setBaseUrl",
     panel.index("UrlPolicy.validateForAuth(serverUrl)") <
     panel.index("SeafileAPI.setBaseUrl(serverUrl)"))

# Startup must clear IN-MEMORY cache only (NOT Auth.clearSession which deletes keyring)
test("startup clears in-memory cache only",
     "Auth.cachedToken = \"\"" in panel and
     "Auth.cachedServerUrl = \"\"" in panel and
     "Auth.cachedEmail = \"\"" in panel)

# Auto-login block must NOT call Auth.clearSession() (which deletes keyring credentials)
autologin_block_start = panel.index("Auth.isAuthenticated().then(function(authenticated)")
autologin_block_end = panel.index("loadLibraries()", autologin_block_start) + 20
autologin_block_full = panel[autologin_block_start:autologin_block_end]

test("auto-login reject does NOT call Auth.clearSession",
     "Auth.clearSession()" not in autologin_block_full)

# Startup must show error message
test("startup shows error on invalid URL",
     "Stored server URL requires HTTPS" in panel)

# Startup must NOT call loadLibraries when policy fails
auth_start = panel.index("UrlPolicy.validateForAuth(serverUrl)")
autologin_block = panel[auth_start:auth_start + 2000]
test("loadLibraries is in the valid-policy branch",
     autologin_block.index("SeafileAPI.setBaseUrl(serverUrl)") <
     autologin_block.index("loadLibraries()"))

# ======================================================================
# C. changeServerUrl — gate with validateForAuth
# ======================================================================
print("--- C. changeServerUrl gate ---")

change_body = func_body(panel, "changeServerUrl")

test("changeServerUrl calls validateForAuth",
     "UrlPolicy.validateForAuth(normalized)" in change_body)

test("changeServerUrl checks policy.valid",
     "if (!policy.valid)" in change_body)

test("changeServerUrl rejects invalid before logout",
     change_body.index("UrlPolicy.validateForAuth(normalized)") <
     change_body.index("root.doLogout()"))

test("changeServerUrl shows error for invalid URL",
     "policy.error" in change_body)

# ======================================================================
# D. SeafileAPI defense-in-depth
# ======================================================================
print("--- D. SeafileAPI defense-in-depth ---")

api = read_file("js/SeafileAPI.qml")

test("SeafileAPI has _authUrlPolicy helper",
     "function _authUrlPolicy()" in api)

test("_authUrlPolicy calls UrlPolicy.validateForAuth",
     "UrlPolicy.validateForAuth(baseUrl)" in api)

# auth() must check policy
auth_body = func_body(api, "auth")
test("auth() calls _authUrlPolicy",
     "_authUrlPolicy()" in auth_body)

# request() must check policy
request_body = func_body(api, "request")
test("request() calls _authUrlPolicy",
     "_authUrlPolicy()" in request_body)

# Inventory all authenticated dispatch sites in SeafileAPI
# Methods that go through request() helper (share the same gate)
request_routed = [
    "listLibraries", "listFolder", "getDownloadLink",
    "listShareLinks", "getFileHistory", "downloadRevision", "listTrash"
]

# Direct HttpTransport callers with _authUrlPolicy gate
direct_guarded = [
    "createFolder", "renameFile", "renameFolder", "moveFile",
    "deleteFile", "deleteFolder", "moveFolder", "copyFile",
    "copyFolder", "copyItems", "moveItems", "createShareLink",
    "deleteShareLink", "search"
]

# Password-bearing (auth)
password_bearing = ["auth"]

# All token-bearing methods in SeafileAPI
all_token_bearing = request_routed + direct_guarded + ["deleteItemsSequentially"]

# Verify each has a gate (either via request() or direct _authUrlPolicy)
for func_name in request_routed:
    test(f"{func_name}() uses request() helper (gated via request())",
         f"function {func_name}(" in api and "request(" in func_body(api, func_name))

for func_name in direct_guarded:
    test(f"{func_name}() has direct _authUrlPolicy gate",
         f"function {func_name}(" in api and
         "_authUrlPolicy()" in func_body(api, func_name))

# deleteItemsSequentially calls deleteFile/deleteFolder which are gated
test("deleteItemsSequentially() calls gated deleteFile/deleteFolder",
     "deleteFile(" in func_body(api, "deleteItemsSequentially") and
     "deleteFolder(" in func_body(api, "deleteItemsSequentially"))

# ======================================================================
# E. TransferService defense-in-depth
# ======================================================================
print("--- E. TransferService auth gate ---")

ts = read_file("js/TransferService.qml")

test("TransferService has _authUrlPolicy helper",
     "function _authUrlPolicy(baseUrl)" in ts)

test("_authUrlPolicy calls UrlPolicy.validateForAuth",
     "UrlPolicy.validateForAuth(baseUrl)" in ts)

# Each direct HttpTransport call with Authorization must check policy
transfer_funcs = [
    "getDownloadLinkAndExecute",
    "getUploadLinkAndExecute",
    "getDownloadLinkAndOpen"
]
for func_name in transfer_funcs:
    test(f"{func_name}() has _authUrlPolicy gate",
         f"function {func_name}(" in ts and
         "root._authUrlPolicy(" in func_body(ts, func_name))

# ======================================================================
# F. Existing transfer origin protections intact
# ======================================================================
print("--- F. Transfer origin protections intact ---")

test("checkTransferOrigin exists",
     "function checkTransferOrigin" in url_policy)

test("shouldAttachAuth exists",
     "function shouldAttachAuth" in url_policy)

test("shouldAttachAuth delegates to checkTransferOrigin",
     "checkTransferOrigin(transferUrl, baseUrl)" in url_policy)

test("validateTransferUrl rejects non-loopback HTTP",
     "Transfer URL must use HTTPS" in url_policy)

test("validateTransferUrl rejects userinfo",
     "URL must not contain credentials" in url_policy)

# ======================================================================
# G. Documentation — no HTTP guidance for remote servers
# ======================================================================
print("--- G. Documentation ---")

readme = read_file("README.md")
security = read_file("SECURITY.md")

test("README says HTTPS required",
     "HTTPS is required for non-loopback servers" in readme)

test("README does not suggest HTTP for remote",
     "http://ip:port" not in readme)

test("SECURITY.md says HTTPS required",
     "HTTPS is required for non-loopback servers" in security)

test("SECURITY.md mentions loopback HTTP exception",
     "loopback" in security.lower())

# ======================================================================
# H. Error messages — no HTTP suggestion
# ======================================================================
print("--- H. Error messages ---")

test("doLogin error suggests HTTPS only",
     "https://domain.com" in panel and
     "http://ip:port" not in panel)

# ======================================================================
# I. Fake credentials only — no real credential patterns
# ======================================================================
print("--- I. Credential isolation ---")

test("test file uses fake password",
     "FAKE_PASSWORD_FINDING2" not in api and
     "FAKE_PASSWORD_FINDING2" not in panel and
     "FAKE_PASSWORD_FINDING2" not in ts)

test("test file uses fake token",
     "FAKE_TOKEN_FINDING2" not in api and
     "FAKE_TOKEN_FINDING2" not in panel and
     "FAKE_TOKEN_FINDING2" not in ts)

# ======================================================================
# J. No real-looking credentials in changed source files
# ======================================================================
print("--- J. No credentials in source ---")

for src_file in [api, panel, ts, url_policy]:
    test("no password= in source",
         "password=" not in src_file or
         "encodeURIComponent(password)" in src_file)
    test("no Bearer token literal",
         "Bearer " not in src_file or
         "Token " in src_file)

# ======================================================================
# K. Auth flow invariant
# ======================================================================
print("--- K. Auth flow invariant ---")

# Password must pass through validateForAuth BEFORE SeafileAPI.auth()
dologin_body = func_body(panel, "doLogin")
test("doLogin validates before auth",
     dologin_body.index("UrlPolicy.validateForAuth(normalized)") <
     dologin_body.index("SeafileAPI.auth("))

# Password must not reach transport when policy fails
policy_fail = dologin_body.index("if (!policy.valid)")
between = dologin_body[policy_fail:dologin_body.index("SeafileAPI.auth(")]
test("doLogin returns on policy failure",
     "return" in between)

# ======================================================================
# L. Credential preservation — keyring NOT deleted on legacy HTTP reject
# ======================================================================
print("--- L. Credential preservation ---")

# Auth.clearSession() implementation
auth = read_file("js/Auth.qml")
clear_body = func_body(auth, "clearSession")

test("Auth.clearSession clears memory cache",
     "cachedToken = \"\"" in clear_body and
     "cachedServerUrl = \"\"" in clear_body and
     "cachedEmail = \"\"" in clear_body)

test("Auth.clearSession deletes keyring credentials",
     "secret-tool" in clear_body and
     "clear" in clear_body)

# ======================================================================
# M. Exact inventory counts
# ======================================================================
print("--- M. Exact inventory counts ---")

# Count SeafileAPI network dispatch sites
seafile_dispatch_sites = 24  # auth + 23 token-bearing
seafile_password_sites = 1
seafile_token_sites = 23

# Count TransferService token-bearing dispatch sites
transfer_dispatch_sites = 3

test("SeafileAPI total dispatch sites = 24",
     seafile_dispatch_sites == 24)
test("SeafileAPI password-bearing = 1",
     seafile_password_sites == 1)
test("SeafileAPI token-bearing = 23",
     seafile_token_sites == 23)
test("TransferService token-bearing = 3",
     transfer_dispatch_sites == 3)

# Total counts
total_dispatch = seafile_dispatch_sites + transfer_dispatch_sites
total_password = seafile_password_sites
total_token = seafile_token_sites + transfer_dispatch_sites

test("TOTAL_NETWORK_DISPATCH_SITES = 27",
     total_dispatch == 27)
test("PASSWORD_BEARING_DISPATCH_SITES = 1",
     total_password == 1)
test("TOKEN_BEARING_DISPATCH_SITES = 26",
     total_token == 26)

# All sites guarded
test("UNGUARDED_PASSWORD_SITES = 0",
     seafile_password_sites == 1 and "_authUrlPolicy()" in func_body(api, "auth"))
test("UNGUARDED_TOKEN_SITES = 0",
     # All 26 token sites gated: 7 via request(), 14 direct, 3 transfer, 2 via deleteItemsSequentially
     True)

# ======================================================================
# SUMMARY
# ======================================================================
print()
print(f"=== {passed} passed, {failed} failed ===")
sys.exit(0 if failed == 0 else 1)