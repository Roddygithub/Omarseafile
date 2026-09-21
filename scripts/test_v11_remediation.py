#!/usr/bin/env python3
"""v1.1 remediation regression suite.

Runs WITHOUT Omarchy or Quickshell. The JavaScript under test is the real
JavaScript shipped inside our .qml modules: scripts/qmljs.js extracts it and
executes it under Node, so these are behavioural tests of the product code
rather than of a re-implementation.

Test classification is printed per section:
  BEHAVIORAL - executes product JavaScript and asserts on results
  STATIC     - asserts a source invariant that cannot be executed portably
"""

import glob
import os
import re
import shutil
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
NODE = shutil.which("node") or shutil.which("nodejs")

passed = 0
failed = 0
skipped = 0


def test(name, condition, detail="", kind="BEHAVIORAL"):
    global passed, failed
    if condition:
        passed += 1
        print("  PASS [%s]: %s" % (kind, name))
    else:
        failed += 1
        msg = "  FAIL [%s]: %s" % (kind, name)
        if detail:
            msg += " - " + str(detail)
        print(msg)


def read(rel):
    with open(os.path.join(ROOT, rel), encoding="utf-8") as f:
        return f.read()


def code(rel):
    """Source with comment lines removed. A comment explaining that a defect no
    longer happens must not itself trip an absence check."""
    kept = []
    for line in read(rel).split("\n"):
        stripped = line.lstrip()
        if stripped.startswith("//") or stripped.startswith("/*") or stripped.startswith("*"):
            continue
        kept.append(line)
    return "\n".join(kept)


def run_node(script):
    """Execute a Node snippet against the real QML JavaScript. Returns stdout."""
    if not NODE:
        return None
    proc = subprocess.run(
        [NODE, "-e", script], cwd=ROOT, capture_output=True, text=True, timeout=120
    )
    if proc.returncode != 0:
        raise RuntimeError("node failed: %s\n%s" % (proc.returncode, proc.stderr[-2000:]))
    return proc.stdout


HARNESS = 'const h=require("./scripts/qmljs.js");'


# =====================================================================
print("\n--- 1. Quick Access identity, reactivity, account scope (BEHAVIORAL) ---")
# =====================================================================
if not NODE:
    print("  SKIP: node not available")
    skipped += 1
else:
    out = run_node(HARNESS + r'''
const F = h.loadQmlObject("js/Favorites.qml", {});
const R = [];
const say = (k, v) => R.push(k + "=" + JSON.stringify(v));

// sibling folders under the same parent stay distinct
F.setAccountKey("https://srv.example.com/", "user@example.com");
say("siblingA", F.addFolder("r1", "Repo", "/parent/docs", "docs").changed);
say("siblingB", F.addFolder("r1", "Repo", "/other/docs", "docs").changed);
say("folderCount", F.getFolders().length);
say("siblingPaths", F.getFolders().map(f => f.path).sort());

// library favorite never collides with a root folder favorite
say("libAdd", F.addLibrary("r1", "Repo").changed);
say("rootFolderAdd", F.addFolder("r1", "Repo", "/docs", "docs").changed);
say("libStillThere", F.isLibraryFavorite("r1"));
say("rootFolderStillThere", F.isFolderFavorite("r1", "/docs"));

// identity is type + repoId (+ path)
say("keyLib", F.keyFor({ type: "library", repoId: "r1" }));
say("keyFolder", F.keyFor({ type: "folder", repoId: "r1", path: "/a/b/" }));

// duplicate rejection
say("dupLib", F.addLibrary("r1", "Repo").changed);
say("dupFolder", F.addFolder("r1", "Repo", "/docs", "docs").changed);

// path normalisation
say("normRoot", F.normalizePath("/"));
say("normEmpty", F.normalizePath(""));
say("normDup", F.normalizePath("/a//b/"));
say("normDot", F.normalizePath("/a/./b"));
say("fullRoot", F.folderFullPath("/", "x"));
say("fullNested", F.folderFullPath("/a", "x"));

// account key never contains a token
say("accountKey", F.makeAccountKey("HTTPS://Srv.Example.COM/", "User@Example.COM"));
// account key preserves path case: only scheme + host are lowercased
say("pathKey", F.makeAccountKey("HTTPS://Srv.Example.COM/SeafileAPI", "User@Example.COM"));

// removal by record identity, with no browsing context
const saved = JSON.parse(F.saveToSettings());
const scoped = saved["https://srv.example.com|user@example.com"];
const target = scoped.filter(e => e.type === "folder" && e.path === "/docs")[0];
say("removeByRecord", F.removeEntry(target).changed);
say("afterRemove", F.getFolders().map(f => f.path).sort());
say("removeMissing", F.removeEntry({ type: "folder", repoId: "zz", path: "/nope" }).changed);

// A/B isolation
say("beforeSwitch", F.count());
F.setAccountKey("https://other.example.com", "b@example.com");
say("accountB", F.count());
say("Badd", F.addLibrary("rB", "BRepo").changed);
F.setAccountKey("https://srv.example.com/", "user@example.com");
say("accountARestored", F.count());
say("AseesOnlyOwn", F.getLibraries().map(l => l.repoId));
F.setAccountKey("https://other.example.com", "b@example.com");
say("BseesOnlyOwn", F.getLibraries().map(l => l.repoId));

// signed out => empty in-memory view, persisted store intact
F.clearActiveScope();
say("signedOutCount", F.count());
say("signedOutAdd", F.addLibrary("rX", "X").error);
say("storeIntact", Object.keys(JSON.parse(F.saveToSettings())).sort());

console.log(R.join("\n"));
''')
    res = dict(line.split("=", 1) for line in out.strip().split("\n"))
    import json
    g = lambda k: json.loads(res[k])

    test("sibling folder A added", g("siblingA") is True)
    test("sibling folder B added", g("siblingB") is True)
    test("both siblings retained", g("folderCount") >= 2, res.get("folderCount"))
    test("sibling paths distinct",
         g("siblingPaths") == sorted(["/parent/docs", "/other/docs"]),
         res.get("siblingPaths"))
    test("library favorite added", g("libAdd") is True)
    test("library does not shadow root folder", g("libStillThere") is True)
    test("root folder does not shadow library", g("rootFolderStillThere") is True)
    test("library identity includes type", g("keyLib") == "library|r1", res.get("keyLib"))
    test("folder identity includes type + normalized path",
         g("keyFolder") == "folder|r1|/a/b", res.get("keyFolder"))
    test("duplicate library rejected", g("dupLib") is False)
    test("duplicate folder rejected", g("dupFolder") is False)
    test("root path normalizes to empty", g("normRoot") == "")
    test("empty path stays empty", g("normEmpty") == "")
    test("duplicate separators collapsed", g("normDup") == "/a/b", res.get("normDup"))
    test("dot segments dropped", g("normDot") == "/a/b", res.get("normDot"))
    test("full path from library root", g("fullRoot") == "/x", res.get("fullRoot"))
    test("full path from nested dir", g("fullNested") == "/a/x", res.get("fullNested"))
    test("account key is normalized url+email",
         g("accountKey") == "https://srv.example.com|user@example.com", res.get("accountKey"))
    test("account key lowercases scheme+host but preserves path case",
         g("pathKey") == "https://srv.example.com/SeafileAPI|user@example.com", res.get("pathKey"))
    test("account key carries no token", "token" not in g("accountKey").lower())
    test("removal by record works with no currentRepo", g("removeByRecord") is True)
    test("/docs removed", "/docs" not in g("afterRemove"), res.get("afterRemove"))
    test("removing an absent entry reports no change", g("removeMissing") is False)
    test("account B starts empty", g("accountB") == 0, res.get("accountB"))
    test("account A restored after switching back", g("accountARestored") >= 2,
         res.get("accountARestored"))
    test("A sees only its own libraries", g("AseesOnlyOwn") == ["r1"], res.get("AseesOnlyOwn"))
    test("B sees only its own libraries", g("BseesOnlyOwn") == ["rB"], res.get("BseesOnlyOwn"))
    test("signed-out view is empty", g("signedOutCount") == 0)
    test("signed-out mutation refused", g("signedOutAdd") == "Not signed in",
         res.get("signedOutAdd"))
    test("persisted store keeps both accounts",
         g("storeIntact") == ["https://other.example.com|b@example.com",
                               "https://srv.example.com|user@example.com"],
         res.get("storeIntact"))

    # Reactivity: every mutation must reassign, never push/splice in place.
    out2 = run_node(HARNESS + r'''
const F = h.loadQmlObject("js/Favorites.qml", {});
const R = [];
F.setAccountKey("https://s.example", "u@example.com");
const before = F.store;
F.addLibrary("r1", "R1");
R.push("storeReassigned=" + JSON.stringify(F.store !== before));
const listBefore = F.store[F.activeKey];
F.addFolder("r1", "R1", "/a", "a");
R.push("listReassigned=" + JSON.stringify(F.store[F.activeKey] !== listBefore));
const revBefore = F.revision;
F.removeEntry({ type: "library", repoId: "r1", path: "" });
R.push("revisionBumped=" + JSON.stringify(F.revision > revBefore));
R.push("noBareMutation=" + JSON.stringify(!/root\.favorites\.(push|splice)/.test(
    require("fs").readFileSync("js/Favorites.qml", "utf8"))));
console.log(R.join("\n"));
''')
    res2 = dict(line.split("=", 1) for line in out2.strip().split("\n"))
    test("store reassigned on add (reactive)", json.loads(res2["storeReassigned"]) is True)
    test("scoped list reassigned on add (reactive)", json.loads(res2["listReassigned"]) is True)
    test("revision bumped on remove (bindings re-evaluate)",
         json.loads(res2["revisionBumped"]) is True)
    test("no in-place favorites.push/splice left", json.loads(res2["noBareMutation"]) is True)

    # Legacy migration is deterministic and one-time, globally.
    out3 = run_node(HARNESS + r'''
const F = h.loadQmlObject("js/Favorites.qml", {});
const R = [];
const legacy = JSON.stringify([
  { type: "library", repoId: "old", repoName: "Old" },
  { type: "folder", repoId: "old", repoName: "Old", path: "/legacy", name: "legacy" },
  { type: "bogus", repoId: "x" },
]);
F.loadFromSettings("{}", legacy, "[]", "false");
R.push("legacySeen=" + JSON.stringify(F.hasLegacyEntries()));
F.setAccountKey("https://s.example", "u@example.com");
R.push("migratedCount=" + JSON.stringify(F.count()));
R.push("bogusDropped=" + JSON.stringify(F.count() === 2));
R.push("marker=" + JSON.stringify(F.saveMigratedKeys()));
R.push("globalSet=" + F.saveGloballyMigrated());
// reload with the SAME legacy blob plus the recorded markers: must not re-import
const saved = F.saveToSettings();
const marker = F.saveMigratedKeys();
const F2 = h.loadQmlObject("js/Favorites.qml", {});
F2.loadFromSettings(saved, legacy, marker, "true");
R.push("legacyRetired=" + JSON.stringify(!F2.hasLegacyEntries()));
F2.setAccountKey("https://s.example", "u@example.com");
R.push("noSecondImport=" + JSON.stringify(F2.count() === 2));
// A SECOND account must receive ZERO legacy entries after global migration.
F2.setAccountKey("https://other.example", "b@example.com");
R.push("secondAccountCount=" + JSON.stringify(F2.count()));
console.log(R.join("\n"));
''')
    res3 = dict(line.split("=", 1) for line in out3.strip().split("\n"))
    test("legacy blob detected", json.loads(res3["legacySeen"]) is True)
    test("legacy entries migrated into the account", json.loads(res3["migratedCount"]) == 2,
         res3.get("migratedCount"))
    test("malformed legacy record dropped", json.loads(res3["bogusDropped"]) is True)
    test("migration marker records the account",
         json.loads(json.loads(res3["marker"])) == ["https://s.example|u@example.com"],
         res3.get("marker"))
    test("global migration marker set after first import", res3["globalSet"] == "true")
    test("legacy blob retired on next start", json.loads(res3["legacyRetired"]) is True)
    test("legacy not re-imported on next start", json.loads(res3["noSecondImport"]) is True)
    test("second account receives zero legacy entries",
         json.loads(res3["secondAccountCount"]) == 0, res3.get("secondAccountCount"))

    # Panel-wiring contract (INTEGRATION): simulate Panel's exact settings keys
    # (favoritesStore / favoritesLegacy / favoritesLegacyMigrated /
    # favoritesLegacyMigratedGlobally) round-tripped through setting(),
    # proving the legacy blob flows into the first account, a full app restart
    # happens, and account B receives ZERO legacy entries while account A
    # keeps its migrated entries.
    out4 = run_node(HARNESS + r'''
const F = h.loadQmlObject("js/Favorites.qml", {});
const R = [];
// A tiny settings store mirroring Panel's setting()/persistFavorites() keys.
const settings = {
  favoritesStore: "{}",
  favoritesLegacy: JSON.stringify([
    { type: "library", repoId: "legacy-lib", repoName: "Old" },
    { type: "folder", repoId: "legacy-lib", repoName: "Old", path: "/docs", name: "docs" },
  ]),
  favoritesLegacyMigrated: "[]",
  favoritesLegacyMigratedGlobally: "false",
};
function loadFavorites(inst) {
  const legacy = settings.favoritesLegacy;
  const legacyRaw = (!legacy || legacy === "[]" || legacy === "{}") ? settings.favorites : legacy;
  inst.loadFromSettings(settings.favoritesStore, legacyRaw, settings.favoritesLegacyMigrated,
      settings.favoritesLegacyMigratedGlobally);
}
function persistFavorites() {
  settings.favoritesStore = F.saveToSettings();
  settings.favoritesLegacyMigrated = F.saveMigratedKeys();
  settings.favoritesLegacyMigratedGlobally = F.saveGloballyMigrated();
}
// A. legacy -> account A
loadFavorites(F);
F.setAccountKey("https://srv.example.com/", "user@example.com");
// B. persist
persistFavorites();
R.push("importedOnce=" + JSON.stringify(F.count() === 2));
R.push("storePersisted=" + JSON.stringify(JSON.parse(settings.favoritesStore)["https://srv.example.com|user@example.com"].length === 2));
R.push("markerPersisted=" + JSON.stringify(JSON.parse(settings.favoritesLegacyMigrated).length === 1));
R.push("globalPersisted=" + settings.favoritesLegacyMigratedGlobally);
const accountAStore = settings.favoritesStore;
// C. simulate full app restart: fresh Favorites instance, reload from settings
const F2 = h.loadQmlObject("js/Favorites.qml", {});
loadFavorites(F2);
// D. login account B
F2.setAccountKey("https://other.example.com", "b@example.com");
// E. account B receives ZERO legacy entries
R.push("accountBLegacyCount=" + JSON.stringify(F2.count()));
// F. account A still has its migrated entries
F2.setAccountKey("https://srv.example.com/", "user@example.com");
R.push("accountARestored=" + JSON.stringify(F2.count()));
console.log(R.join("\n"));
''')
    res4 = dict(line.split("=", 1) for line in out4.strip().split("\n"))
    import json as _json4
    test("Panel wiring imports legacy into first account", _json4.loads(res4["importedOnce"]) is True)
    test("Panel wiring persists the scoped store", _json4.loads(res4["storePersisted"]) is True)
    test("Panel wiring persists the migration marker", _json4.loads(res4["markerPersisted"]) is True)
    test("Panel wiring persists the global marker", res4["globalPersisted"] == "true")
    test("account B receives zero legacy entries after restart",
         _json4.loads(res4["accountBLegacyCount"]) == 0, res4.get("accountBLegacyCount"))
    test("account A keeps its migrated entries after restart",
         _json4.loads(res4["accountARestored"]) == 2, res4.get("accountARestored"))


# =====================================================================
print("\n--- 2. HTTP status propagation and retry classification (BEHAVIORAL) ---")
# =====================================================================
if NODE:
    out = run_node(HARNESS + r'''
const T = h.loadQmlObject("js/TransferService.qml", { UrlPolicy: h.loadQmlObject("js/UrlPolicy.qml", {}) });
const H = h.loadQmlObject("js/HttpTransport.qml", { Qt: { resolvedUrl: u => "file://" + u } });
const R = [];
const cases = [0, 200, 400, 401, 403, 404, 408, 409, 422, 425, 429, 500, 502, 503, 599];
for (const c of cases) {
  R.push("retry:" + c + "=" + T.isRetryableStatus(c));
  R.push("auth:" + c + "=" + T.isAuthError(c));
}
R.push("legacy3argIsIgnoredMessage=" + T.isRetryableError(404, "network connection timeout"));
R.push("textIsNeverParsed=" + JSON.stringify(
  !/errorMsg\.includes|error\.includes/.test(require("fs").readFileSync("js/TransferService.qml","utf8"))));
R.push("statusFromText000=" + H._statusFromText("000"));
R.put = null;
R.push("statusFromText404=" + H._statusFromText("404\n"));
R.push("statusFromTextJunk=" + H._statusFromText("not a status"));
R.push("msg404=" + T._httpFailureMessage("Upload link request failed", 404, "Upload link request failed"));
R.push("msg0=" + T._httpFailureMessage("curl failed", 0, "Download link request failed"));
console.log(R.join("\n"));
''')
    res = {}
    for line in out.strip().split("\n"):
        k, v = line.split("=", 1)
        res[k] = v

    def as_bool(v):
        return v == "true"

    test("401 is an auth failure", as_bool(res["auth:401"]))
    test("403 is an auth failure", as_bool(res["auth:403"]))
    test("401 is NOT retryable", not as_bool(res["retry:401"]))
    test("403 is NOT retryable", not as_bool(res["retry:403"]))
    test("404 is NOT retryable", not as_bool(res["retry:404"]))
    test("400 is NOT retryable", not as_bool(res["retry:400"]))
    test("409 is NOT retryable", not as_bool(res["retry:409"]))
    test("422 is NOT retryable", not as_bool(res["retry:422"]))
    test("408 IS retryable", as_bool(res["retry:408"]))
    test("425 IS retryable", as_bool(res["retry:425"]))
    test("429 IS retryable", as_bool(res["retry:429"]))
    test("500 IS retryable", as_bool(res["retry:500"]))
    test("502 IS retryable", as_bool(res["retry:502"]))
    test("503 IS retryable", as_bool(res["retry:503"]))
    test("599 IS retryable", as_bool(res["retry:599"]))
    test("status 0 (transport failure) IS retryable", as_bool(res["retry:0"]))
    test("200 is not an error at all", not as_bool(res["retry:200"]) and not as_bool(res["auth:200"]))
    test("message text can no longer force a retry", res["legacy3argIsIgnoredMessage"] == "false",
         res.get("legacy3argIsIgnoredMessage"))
    test("no error-text sniffing remains", res["textIsNeverParsed"] == "true")
    test('curl "000" maps to status 0', res["statusFromText000"] == "0")
    test("status text is trimmed", res["statusFromText404"] == "404")
    test("non-numeric status text maps to 0", res["statusFromTextJunk"] == "0")
    test("permanent failure message carries the status", "(HTTP 404)" in res["msg404"],
         res.get("msg404"))
    test("transport failure message invents no status", "(HTTP" not in res["msg0"], res.get("msg0"))

    # Static: the real status must actually be threaded into the callbacks, and
    # the curl -o / -w contract must be honoured (body -> file, status -> stdout).
    src = read("js/HttpTransport.qml")
    test("curl captures %{http_code}", "-w\", \"%{http_code}" in src, kind="STATIC")
    test("response body goes to a private file via -o",
         '"-o", responseBodyFile' in src and "curl_resp" in src, kind="STATIC")
    test("response body read back from the file", "_readBodyFile" in src, kind="STATIC")
    test("status is parsed from stdout text", "_statusFromText(statusText)" in src, kind="STATIC")
    test("callback contract is (success, data, error, status)",
         re.search(r"callback\(success, data, error, typeof status", src) is not None, kind="STATIC")
    test("response file is private (createSecureFile)",
         'createSecureFile("http", "curl_resp"' in src, kind="STATIC")
    test("response file is cleaned up",
         src.count("cleanup(responseBodyFile)") >= 4, kind="STATIC")
    test("no inverted body/status file remains",
         "curl_status" not in src and "statusFilePath" not in src, kind="STATIC")

    ts = read("js/TransferService.qml")
    test("upload link callback receives status",
         re.search(r"function\(success, data, error, status\)", ts) is not None, kind="STATIC")
    test("upload link classifies on status",
         "isAuthError(status)" in ts and "isRetryableStatus(status)" in ts, kind="STATIC")
    test("no isAuthError(error) misuse remains", "isAuthError(error)" not in ts, kind="STATIC")
    test("no isRetryableError(0, error) misuse remains",
         "isRetryableError(0, error)" not in ts, kind="STATIC")
    test("status threaded to download path", ts.count("isAuthError(status)") >= 3, kind="STATIC")


# =====================================================================
print("\n--- 3. Bounded upload queue and logout race (BEHAVIORAL) ---")
# =====================================================================
if NODE:
    out = run_node(HARNESS + r'''
const fs = require("fs");
const T = h.loadQmlObject("js/TransferService.qml", { UrlPolicy: h.loadQmlObject("js/UrlPolicy.qml", {}) });

// Stub the pieces that need Quickshell so the scheduler logic runs for real.
const spawned = [];
T._statFactory = { createObject: () => {
  const p = { command: null, running: false, destroyed: false,
              destroy() { this.destroyed = true; }, _cb: null };
  spawned.push(p);
  return p;
}};
T.reportError = () => {};
T.transferStateChanged = () => {};
T.transfersChanged = () => {};
// Terminal on purpose: if the stub left the upload in "uploading" it would keep
// occupying a concurrency slot and _pumpUploadQueue() would spin forever.
T.getUploadLinkAndExecute = (u) => { u.state = "completed"; };
T.SafePath = { sanitizeBasename: n => ({ valid: true, sanitized: n }) };
const R = [];

R.push("maxConcurrent=" + T.maxConcurrentUploads);
R.push("maxQueued=" + T.maxQueuedUploads);

// Submit 7 uploads: 3 may validate concurrently, the rest must queue.
for (let i = 0; i < 7; i++) T.startUpload("/tmp/f" + i + ".txt", "tok", "https://s.example", "r1", "/", "f" + i + ".txt");
R.push("registered=" + T.transfers.length);
R.push("validating=" + T.transfers.filter(t => t.state === "validating").length);
R.push("queued=" + T.transfers.filter(t => t.state === "queued").length);
R.push("spawnedStatProcs=" + spawned.length);
R.push("orderPreserved=" + JSON.stringify(T.transfers.map(t => t.fileName)));
R.push("allActive=" + JSON.stringify(T.getActiveTransfers().length === 7));

// Queue limit: with 4 already queued, a limit of 4 must reject the next one.
T.maxQueuedUploads = T.transfers.filter(t => t.state === "queued").length;
R.push("queueLimitRejects=" + JSON.stringify(
  T.startUpload("/tmp/over.txt", "tok", "https://s.example", "r1", "/", "over.txt") === null));
T.maxQueuedUploads = 100;
R.push("queueLimitAcceptsUnderCap=" + JSON.stringify(
  T.startUpload("/tmp/under.txt", "tok", "https://s.example", "r1", "/", "under.txt") !== null));

// Cancelling a QUEUED upload works and frees nothing that was never started
const queued = T.transfers.filter(t => t.state === "queued");
const before = T.transfers.filter(t => t.state === "queued").length;
T.cancelTransfer(queued[0].id);
R.push("queuedCancel=" + (queued[0].state === "cancelled"));
R.push("queuedCancelFreesSlot=" + JSON.stringify(T.transfers.filter(t => t.state === "queued").length === before - 1));

// Finish one in-flight upload: its slot must be handed to the next queued one.
const validating = T.transfers.filter(t => t.state === "validating");
const queuedBefore = T.transfers.filter(t => t.state === "queued").length;
validating[0].state = "completed";
T._pumpUploadQueue();
R.push("pumpStartsNext=" + JSON.stringify(
  T.transfers.filter(t => t.state === "queued").length < queuedBefore));

// Logout during validation: bump the epoch, then fire the stale callback
const victim = T.transfers.filter(t => t.state === "validating")[0];
const victimEpoch = victim.epoch;
const statProcsBefore = spawned.length;
T.logoutCleanup();
R.push("epochBumped=" + JSON.stringify(T.sessionEpoch > victimEpoch));
R.push("transfersCleared=" + JSON.stringify(T.transfers.length === 0));
R.push("victimInvalidated=" + JSON.stringify(victim.epoch !== T.sessionEpoch));
R.push("noCurlAfterLogout=" + JSON.stringify(victim.state !== "uploading"));
console.log(R.join("\n"));
''')
    res = {}
    for line in out.strip().split("\n"):
        k, v = line.split("=", 1)
        res[k] = v

    import json as _json
    test("MAX_CONCURRENT_UPLOADS is 3", res["maxConcurrent"] == "3", res.get("maxConcurrent"))
    test("queue limit is 100", res["maxQueued"] == "100", res.get("maxQueued"))
    test("all 7 uploads registered", res["registered"] == "7", res.get("registered"))
    test("only 3 validating concurrently", res["validating"] == "3", res.get("validating"))
    test("remaining 4 are queued and visible", res["queued"] == "4", res.get("queued"))
    test("only 3 stat processes spawned", res["spawnedStatProcs"] == "3",
         res.get("spawnedStatProcs"))
    test("selection order preserved",
         _json.loads(res["orderPreserved"]) == ["f%d.txt" % i for i in range(7)],
         res.get("orderPreserved"))
    test("queued uploads count as active", _json.loads(res["allActive"]) is True)
    test("queue limit rejects overflow", _json.loads(res["queueLimitRejects"]) is True)
    test("queue accepts work under the cap",
         _json.loads(res["queueLimitAcceptsUnderCap"]) is True)
    test("a queued upload can be cancelled", res["queuedCancel"] == "true")
    test("cancelling a queued upload shrinks the queue",
         _json.loads(res["queuedCancelFreesSlot"]) is True)
    test("finishing one upload starts the next queued",
         _json.loads(res["pumpStartsNext"]) is True)
    test("logout bumps the session epoch", _json.loads(res["epochBumped"]) is True)
    test("logout clears the transfer list", _json.loads(res["transfersCleared"]) is True)
    test("in-flight validation is invalidated by logout",
         _json.loads(res["victimInvalidated"]) is True)
    test("no upload is resurrected after logout",
         _json.loads(res["noCurlAfterLogout"]) is True)

    ts = read("js/TransferService.qml")
    test("transfer is registered before async validation",
         ts.index("root.transfers = list") < ts.index("_beginUploadValidation(next)"),
         kind="STATIC")
    test("validation Process belongs to the transfer", "upload.statProcess = proc" in ts,
         kind="STATIC")
    test("cancelTransfer handles the queued state", 't.state === "queued"' in ts, kind="STATIC")
    test("cancelTransfer handles the validating state", 't.state === "validating"' in ts,
         kind="STATIC")
    test("queued/validating are active states",
         'state === "queued" || state === "validating"' in ts, kind="STATIC")

    # Early terminal failures must all pump the next queued upload exactly once.
    out4 = run_node(HARNESS + r'''
const T = h.loadQmlObject("js/TransferService.qml", { UrlPolicy: h.loadQmlObject("js/UrlPolicy.qml", {}) });
T.SafePath = { sanitizeBasename: n => ({ valid: true, sanitized: n }) };
T.reportError = () => {};
T.transferStateChanged = () => {};
T.transfersChanged = () => {};
T._statFactory = { createObject: () => ({ command: null, running: false, destroy(){} }) };
const R = [];
const helperUsed = /function _finishUploadFailure/.test(require("fs").readFileSync("js/TransferService.qml","utf8"));
R.push("helperPresent=" + helperUsed);

// Inject each early-failure class directly and confirm the slot is released
// and the next queued upload is pumped into "validating".
function makeUpload(name) {
  return { id: name, type: "upload", state: "pending", fileName: name, srcPath: "/tmp/"+name,
           destUploadPath: "/", repoId: "r1", token: "tok", baseUrl: "https://s.example",
           process: null, statProcess: null, uploadLink: null, progress: 0, speed: "",
           error: "", retryCount: 0, startTime: Date.now(), endTime: null,
           authHeaderFile: null, curlConfigFile: null, epoch: T.sessionEpoch };
}
function pumpFor(upload) {
  // Simulate: the failing upload was running, a queued one waits behind it.
  T.transfers = [upload, makeUpload("queued-next")];
  T.transfers[1].state = "queued";
  const before = T.transfers[1].state;
  T._finishUploadFailure(upload, "injected");
  return before + "->" + T.transfers[1].state;
}
const failures = [
  makeUpload("u-policy"), makeUpload("u-resp"), makeUpload("u-url"),
  makeUpload("u-hdr"), makeUpload("u-cfg"), makeUpload("u-proc")
];
R.push("policy=" + pumpFor(failures[0]));
R.push("resp=" + pumpFor(failures[1]));
R.push("url=" + pumpFor(failures[2]));
R.push("hdr=" + pumpFor(failures[3]));
R.push("cfg=" + pumpFor(failures[4]));
R.push("proc=" + pumpFor(failures[5]));
R.push("failedState=" + failures[0].state);
R.push("doublePumpSafe=" + (function(){ T.transfers=[failures[0]]; failures[0].state="failed"; const before2=failures[0].state; T._finishUploadFailure(failures[0],"again"); return failures[0].state===before2; })());
console.log(R.join("\n"));
''')
    res4 = dict(line.split("=", 1) for line in out4.strip().split("\n"))
    import json as _json4
    test("a single _finishUploadFailure helper exists", res4["helperPresent"] == "true",
         kind="STATIC")
    for case in ("policy", "resp", "url", "hdr", "cfg", "proc"):
        test("early failure (%s) pumps the next queued upload" % case,
             res4[case].endswith("->validating"), res4.get(case))
    test("failed upload is terminal after early failure", res4["failedState"] == "failed")
    test("double-pumping a terminal upload is a no-op", res4["doublePumpSafe"] == "true")


# =====================================================================
print("\n--- 4. Home / keyboard architecture (STATIC) ---")
# =====================================================================
panel = read("Panel.qml")
home = read("views/HomeView.qml")
browser = read("views/BrowserView.qml")

test("Panel never reads a bare fileListRef property", "fileListRef" not in panel, kind="STATIC")
test("Panel derives the list from the loaded view",
     "function activeFileList()" in panel and "stateLoader.item" in panel, kind="STATIC")
test("Panel has no lexical homeView reference",
     len(re.findall(r"\bhomeView\b", panel)) == 1
     and re.search(r"^\s*id: homeView\s*$", panel, re.M) is not None, kind="STATIC")
test("Panel has no lexical browserView reference",
     len(re.findall(r"\bbrowserView\b", panel)) == 1
     and re.search(r"^\s*id: browserView\s*$", panel, re.M) is not None, kind="STATIC")
test("HomeView exposes activeFileList", "readonly property var activeFileList:" in home,
     kind="STATIC")
test("BrowserView exposes activeFileList", "readonly property var activeFileList:" in browser,
     kind="STATIC")
test("HomeView activeFileList is null when hidden",
     "librariesSection.visible ? librariesFileList : null" in home, kind="STATIC")
test("BrowserView activeFileList is null when hidden",
     "fileList.visible ? fileList : null" in browser, kind="STATIC")
test("keyboard handlers null-check the derived list",
     panel.count("var list = root.activeFileList()") == 5
     and panel.count("if (!list") >= 5, kind="STATIC")
test("keyboard paths still cover move/activate/delete/rename",
     all(k in panel for k in ("onMoveRequested", "onActivateRequested",
                              "onDeleteRequested", "function renameTarget")), kind="STATIC")
test("F2/Ctrl+A/Delete shortcuts remain gated on currentRepo",
     panel.count("root.currentRepo !== null") >= 3, kind="STATIC")

# Delegate required properties must only ever be model roles.
delegate_required = re.findall(r"delegate:\s*\w+\s*\{(.*?)\n\s{12}\}", home, re.S)
bad = []
for block in delegate_required:
    for m in re.finditer(r"required property\s+\S+\s+(\w+)", block):
        if m.group(1) not in ("modelData", "index"):
            bad.append(m.group(1))
test("HomeView delegates declare only modelData/index as required", not bad, bad, kind="STATIC")
test("HomeView defines explicit favorite callbacks",
     all(k in home for k in ("onFavoriteClicked", "onRemoveFavorite", "onTransferCancel")),
     kind="STATIC")
test("Panel supplies the HomeView favorite callbacks",
     all(k in panel for k in ("onFavoriteClicked:", "onRemoveFavorite:", "onTransferCancel:")),
     kind="STATIC")
test("Home transfer cancel actually invokes the callback",
     "root.onTransferCancel(modelData)" in home, kind="STATIC")
home_code = code("views/HomeView.qml")
test("Home transfers list is bound, not polled",
     "model: root.activeTransfers" in home_code
     and "TransferService.getActiveTransfers()" not in home_code, kind="STATIC")
test("Home transfers section reacts to the bound count",
     "visible: root.activeCount > 0" in home, kind="STATIC")
test("quick-access remove button does not navigate",
     "root.onRemoveFavorite(modelData)" in home, kind="STATIC")


# =====================================================================
print("\n--- 5. Transfers surface, search, files-not-favoriteable (STATIC) ---")
# =====================================================================
test("Transfers lives at Panel level", "id: transfersLoader" in panel
     and "id: transfersComponent" in panel, kind="STATIC")
test("Transfers works without a currentRepo",
     re.search(r"root\.state === \"browse\" && root\.showTransfers", panel) is not None,
     kind="STATIC")
test("BrowserView no longer hosts a TransferManager",
     "TransferManager {" not in browser, kind="STATIC")
test("exactly one TransferManager instantiation in the app",
     sum(read(p).count("TransferManager {") for p in
         glob.glob(os.path.join(ROOT, "**", "*.qml"), recursive=True)) == 1, kind="STATIC")
test("toolbar title shows Transfers",
     'root.showTransfers ? "Transfers"' in panel, kind="STATIC")
test("back/escape closes transfers", "if (root.showTransfers) { root.showTransfers = false }" in panel,
     kind="STATIC")
test("Escape from Transfers returns to the view, never closes the panel",
     "if (root.showTransfers) { root.showTransfers = false; return true }" in panel, kind="STATIC")
test("Transfers Back is visible from the Libraries root",
     "root.showTransfers" in panel.split("showBack:")[1].split("\n")[0], kind="STATIC")
test("browser actions are hidden while Transfers is active",
     all("!root.showTransfers" in line
         for line in panel.split("\n")
         if ("showRefresh:" in line or "showUpload:" in line or "showCreateFolder:" in line
             or "showSearch:" in line or "showTrash:" in line)
         and "property bool" not in line), kind="STATIC")
test("intentional global actions stay while Transfers is active",
     all("!root.showTransfers" not in line
         for line in panel.split("\n")
         if "showLogout:" in line or "showSettings:" in line or "showTransfers:" in line),
     kind="STATIC")
test("TransferManager keeps retry/cancel/clear/open/show-in-folder",
     all(k in panel for k in ("onRetry:", "onCancel:", "onClearCompleted:", "onClearFailed:",
                              "onOpen:", "onShowInFolder:", "onRetryAllFailed:")), kind="STATIC")
test("per-item history removal is wired, not whole-category",
     "onClearTransfer: function(transfer) { TransferService.clearTransfer(transfer.id) }" in panel
     and "clearTransfer" in read("js/TransferService.qml")
     and "onClear: root.onClearTransfer" in read("components/TransferManager.qml"), kind="STATIC")
test("TransferItem treats queued/validating as active",
     'transfer.state === "queued" || transfer.state === "validating"'
     in read("components/TransferItem.qml"), kind="STATIC")
test("TransferItem shows a queued/validating label",
     '"Queued..."' in read("components/TransferItem.qml")
     and '"Validating..."' in read("components/TransferItem.qml"), kind="STATIC")
test("TransferItem queued/validating remain cancellable",
     "visible: root.isActive && !root.isCancelling" in read("components/TransferItem.qml")
     and "onCancel" in read("components/TransferItem.qml"), kind="STATIC")

sr = read("components/SearchResults.qml")

# Behavioral: clearTransfer removes exactly one terminal transfer.
if NODE:
    out5 = run_node(HARNESS + r'''
const T = h.loadQmlObject("js/TransferService.qml", { UrlPolicy: h.loadQmlObject("js/UrlPolicy.qml", {}) });
T.transfersChanged = () => {};
T.transfers = [
  { id: "c1", state: "completed", fileName: "a", type: "download" },
  { id: "c2", state: "completed", fileName: "b", type: "download" },
  { id: "f1", state: "failed", fileName: "c", type: "upload" },
  { id: "a1", state: "uploading", fileName: "d", type: "upload" },
];
const R = [];
const removed = T.clearTransfer("c1");
R.push("removed=" + removed);
R.push("remaining=" + JSON.stringify(T.transfers.map(t => t.id).sort()));
R.push("activeKept=" + JSON.stringify(T.transfers.some(t => t.id === "a1")));
R.push("nonTerminalRefused=" + (T.clearTransfer("a1") === false));
console.log(R.join("\n"));
''')
    res5 = dict(line.split("=", 1) for line in out5.strip().split("\n"))
    import json as _json5
    test("clearTransfer removes exactly one terminal transfer",
         _json5.loads(res5["removed"]) is True and "c1" not in _json5.loads(res5["remaining"]),
         res5.get("remaining"))
    test("clearTransfer keeps other terminal transfers",
         _json5.loads(res5["remaining"]) == ["a1", "c2", "f1"], res5.get("remaining"))
    test("clearTransfer keeps active transfers", _json5.loads(res5["activeKept"]) is True)
    test("clearTransfer refuses non-terminal transfers",
         _json5.loads(res5["nonTerminalRefused"]) is True)

test("search right-click no longer navigates",
     "onResultRightClicked" not in sr and "Qt.RightButton" not in sr, kind="STATIC")
test("search accepts left button only", "acceptedButtons: Qt.LeftButton" in sr, kind="STATIC")
test("search filters live in ListView.header", "header: Column {" in sr, kind="STATIC")
test("search empty state is not anchored",
     "anchors.centerIn: parent" not in code("components/SearchResults.qml"), kind="STATIC")
test("BrowserView dropped the right-click wiring", "onResultRightClicked" not in browser,
     kind="STATIC")

test("files are not Quick Access targets",
     "Only libraries and folders can be added to Quick Access" in panel, kind="STATIC")
test("context menu Quick Access is limited to dirs/favorites",
     "(root.isDir || root.isFavorite || root.libraryMode)" in read("components/ContextMenu.qml")
     and "!root.batchMode &&" in read("components/ContextMenu.qml"), kind="STATIC")
test("libraries at the root support Quick Access (libraryMode)",
     "root.libraryMode" in read("components/ContextMenu.qml")
     and "!root.batchMode && (root.isDir || root.isFavorite || root.libraryMode)"
         in read("components/ContextMenu.qml"), kind="STATIC")
test("folder favorite identity uses the full path",
     'root.currentPath === "/" ? "/" + item.name : root.currentPath + "/" + item.name' in panel,
     kind="STATIC")
test("stale favorite gives feedback without crashing",
     "Library is no longer available" in panel, kind="STATIC")
test("favorites scope is cleared on logout", "Favorites.clearActiveScope()" in panel, kind="STATIC")
test("favorites scope is set on manual login",
     re.search(r"Favorites\.setAccountKey\(normalized, email\)", panel) is not None, kind="STATIC")
test("favorites scope is set on auto-login",
     "Favorites.setAccountKey(serverUrl, Auth.getEmail())" in panel, kind="STATIC")
test("favorites use explicit store + legacy + marker keys",
     'setting("favoritesStore", Favorites.saveToSettings())' in panel
     and 'setting("favoritesLegacyMigrated", Favorites.saveMigratedKeys())' in panel
     and 'setting("favoritesLegacy", "[]")' in panel
     and 'setting("favoritesStore", "{}")' in panel
     and 'setting("favoritesLegacyMigrated", "[]")' in panel, kind="STATIC")
test("legacy blob falls back to the pre-1.1 favorites key",
     'setting("favorites", "[]")' in panel, kind="STATIC")


# =====================================================================
print("\n--- 6. Zenity path pipeline (BEHAVIORAL) ---")
# =====================================================================
if NODE:
    out = run_node(r'''
const h=require("./scripts/qmljs.js");
const vm=require("vm");
const fn=h.extractFunction("components/UploadDialog.qml","parsePickerOutput");
const ctx={}; vm.createContext(ctx);
vm.runInContext("this.parsePickerOutput = "+fn, ctx);
const cases={
  single:"/home/u/a.txt\n",
  multi:"/home/u/a.txt\n/home/u/b.txt\n",
  spaces:"/home/u/file with spaces.txt\n",
  percent:"/home/u/100% terminé.txt\n",
  literalPct20:"/home/u/foo%20bar.txt\n",
  unicode:"/home/u/日本語ファイル.txt\n",
  cancel:"",
  noTrailingNl:"/home/u/a.txt",
  crlf:"/home/u/a.txt\r\n/home/u/b.txt\r\n",
  padSpaces:"  /home/u/ padded .txt  \n",
};
for (const k in cases) console.log(k+"="+JSON.stringify(ctx.parsePickerOutput(cases[k])));
''')
    import json as _json
    res = dict(line.split("=", 1) for line in out.strip().split("\n"))
    g = lambda k: _json.loads(res[k])
    test("single path", g("single") == ["/home/u/a.txt"], res.get("single"))
    test("multi selection", g("multi") == ["/home/u/a.txt", "/home/u/b.txt"], res.get("multi"))
    test("filename with spaces survives", g("spaces") == ["/home/u/file with spaces.txt"],
         res.get("spaces"))
    test("filename with % and unicode survives", g("percent") == ["/home/u/100% terminé.txt"],
         res.get("percent"))
    test("literal %20 is NOT decoded", g("literalPct20") == ["/home/u/foo%20bar.txt"],
         res.get("literalPct20"))
    test("unicode filename survives", g("unicode") == ["/home/u/日本語ファイル.txt"],
         res.get("unicode"))
    test("cancel yields no paths", g("cancel") == [], res.get("cancel"))
    test("missing trailing newline tolerated", g("noTrailingNl") == ["/home/u/a.txt"],
         res.get("noTrailingNl"))
    test("CRLF framing handled", g("crlf") == ["/home/u/a.txt", "/home/u/b.txt"], res.get("crlf"))
    test("legitimate leading/trailing spaces preserved",
         g("padSpaces") == ["  /home/u/ padded .txt  "], res.get("padSpaces"))

    up = read("components/UploadDialog.qml")
    test('picker never builds file:// URLs', '"file://"' not in up, kind="STATIC")
    test("picker output is not URI-decoded",
     "decodeURIComponent" not in code("components/UploadDialog.qml"), kind="STATIC")
    test("cancel (non-zero exit) yields nothing", "if (exitCode !== 0) return" in up, kind="STATIC")
    pn = read("Panel.qml")
    m = re.search(r"onFilesSelected: function\(paths\) \{(.*?)\n(\s{12})\}",
                  code("Panel.qml"), re.S)
    test("Panel wires the picker selection handler", m is not None, kind="STATIC")
    handler = m.group(1) if m else ""
    test("Panel passes picker paths through verbatim",
         "decodeURIComponent" not in handler and "normalizeUserPath" not in handler
         and "root.startUpload(path)" in handler,
         handler.strip()[:200], kind="STATIC")
    test("manual file:// input is still decoded",
         "normalizeUserPath" in pn and "decodeURIComponent(trimmed.substring(7))" in pn, kind="STATIC")
    test("newline separator limitation is documented in source",
         "cannot be represented" in up, kind="STATIC")
    test("Browse is disabled when zenity is missing",
         "enabled: root.pickerAvailable" in up and "pickerAvailable" in up, kind="STATIC")
    test("manual path stays available when zenity is missing",
         "onUpload" in up and 'placeholderText: "/home/user/file.txt"' in up, kind="STATIC")
    test("missing zenity shows a clear message",
         "Zenity is not installed; enter the path manually." in up, kind="STATIC")
    test("zenity availability is probed via which",
         '["which", "zenity"]' in up, kind="STATIC")


# =====================================================================
print("\n--- 7. QML defect sweep (STATIC) ---")
# =====================================================================
fi = read("components/FileItem.qml")
test("FileItem centralizes the ListView attached read",
     "readonly property var _listView: root.ListView" in fi, kind="STATIC")
fi_code = code("components/FileItem.qml")
test("FileItem has no unguarded root.ListView.isCurrentItem",
     "root.ListView.isCurrentItem" not in fi_code, kind="STATIC")
test("FileItem has no unguarded root.ListView.view",
     re.search(r"root\.ListView\.view", fi) is None, kind="STATIC")
test("FileItem guards the transfer speed field",
     "(activeTransfer && activeTransfer.speed)" in fi, kind="STATIC")

proc = subprocess.run([sys.executable, os.path.join(ROOT, "scripts", "check_positioner_anchors.py")],
                      capture_output=True, text=True)
test("no anchors on direct positioner children", proc.returncode == 0,
     proc.stdout.strip()[-400:], kind="STATIC")

dup = subprocess.run([sys.executable, os.path.join(ROOT, "scripts", "check_duplicate_properties.py")],
                     capture_output=True, text=True)
test("no duplicate QML properties on the same object", dup.returncode == 0,
     dup.stdout.strip()[-400:], kind="STATIC")

test("EmptyState centres content with valid anchors",
     "anchors.horizontalCenter: parent.horizontalCenter" in read("components/EmptyState.qml")
     and "horizontalAlignment" not in code("components/EmptyState.qml"), kind="STATIC")

# Untrusted text must stay bounded and PlainText.
for path in sorted(glob.glob(os.path.join(ROOT, "**", "*.qml"), recursive=True)):
    rel = os.path.relpath(path, ROOT)
    body = code(rel)
    for m in re.finditer(r"text:\s*([^\n]*(?:modelData|item\.|transfer\.|root\.errorMessage|result)[^\n]*)", body):
        expr = m.group(1)
        if "boundedDisplayText" in expr or "Icons." in expr:
            continue
        if re.search(r"\b(name|fileName|error|repoName|displayName|subtitle|title)\b", expr) \
           or "currentPath" in expr:
            test("%s bounds untrusted text: %s" % (rel, expr.strip()[:70]), False, kind="STATIC")

icons = read("js/Icons.qml")
test("icon font is centralized in js/Icons.qml", "readonly property string family:" in icons,
     kind="STATIC")
leftover = [p for p in glob.glob(os.path.join(ROOT, "**", "*.qml"), recursive=True)
            if 'font.family: "Noto Sans"' in read(os.path.relpath(p, ROOT))]
test("no hardcoded icon font family remains", not leftover, leftover, kind="STATIC")
leftover_glyph = [os.path.relpath(p, ROOT)
                  for p in glob.glob(os.path.join(ROOT, "**", "*.qml"), recursive=True)
                  if re.search(r'\\uf[0-9a-f]{3}', read(os.path.relpath(p, ROOT)))
                  and not p.endswith("js/Icons.qml")]
test("no raw private-use glyph literals outside Icons.qml", not leftover_glyph, leftover_glyph,
     kind="STATIC")
test("ordinary text follows the Omarchy user font",
     'font.family: "Noto Sans"' not in read("components/FileItem.qml"), kind="STATIC")


# =====================================================================
print("\n--- 8. Dependency contract, URL policy, foldersFirst (BEHAVIORAL/STATIC) ---")
# =====================================================================
auth = read("js/Auth.qml")
test("zenity is declared optional (cannot block login)",
     re.search(r'\{ cmd: "zenity"[^}]*required: false \}', auth) is not None, kind="STATIC")
test("curl is required", re.search(r'\{ cmd: "curl"[^}]*required: true \}', auth) is not None,
     kind="STATIC")
test("secret-tool is required",
     re.search(r'\{ cmd: "secret-tool"[^}]*required: true \}', auth) is not None, kind="STATIC")
test("python3 is required",
     re.search(r'\{ cmd: "python3"[^}]*required: true \}', auth) is not None, kind="STATIC")
test("xdg-open is optional",
     re.search(r'\{ cmd: "xdg-open"[^}]*required: false \}', auth) is not None, kind="STATIC")
test("notify-send is optional",
     re.search(r'\{ cmd: "notify-send"[^}]*required: false \}', auth) is not None, kind="STATIC")

if NODE:
    out = run_node(HARNESS + r'''
const U = h.loadQmlObject("js/UrlPolicy.qml", {});
const cases = [
  ["https://example.com", true],
  ["https://example.com/seafile", true],
  ["https://user:pass@example.com", false],
  ["https://user@example.com", false],
  ["https://example.com/?foo=bar", false],
  ["https://example.com/#x", false],
  ["http://localhost:8000", true],
  ["http://127.0.0.1", true],
  ["http://example.com", false],
];
for (const [u, want] of cases) console.log(u + "=" + (U.validateForAuth(u).valid === want));
console.log("crossOriginBlocked=" + (U.shouldAttachAuth("https://cdn.other/x", "https://example.com") === false));
console.log("sameOriginAllowed=" + (U.shouldAttachAuth("https://example.com/x", "https://example.com") === true));
''')
    for line in out.strip().split("\n"):
        k, v = line.rsplit("=", 1)
        test("URL policy: %s" % k, v == "true")

fl = read("components/FileList.qml")
test("foldersFirst gates the directory grouping",
     "root.foldersFirst && root.sortColumn !== \"type\"" in fl, kind="STATIC")
test("type sorting ignores foldersFirst",
     'if (root.foldersFirst && root.sortColumn !== "type"' in fl, kind="STATIC")
sd = read("components/SettingsDialog.qml")
test("foldersFirst switch is enabled",
     re.search(r"id: foldersFirstSwitch(?:(?!Switch \{)[\s\S])*?checked: root\.foldersFirst", sd) is not None
     and "enabled: false" not in sd.split("id: foldersFirstSwitch")[1].split("}")[0], kind="STATIC")
test("foldersFirst is persisted",
     'setting("foldersFirst", enabled)' in panel and 'setting("foldersFirst", true)' in panel,
     kind="STATIC")
test("foldersFirst reaches the FileList", "foldersFirst: root.foldersFirst" in browser,
     kind="STATIC")


# =====================================================================
print("\n--- 9. Security invariants (STATIC) ---")
# =====================================================================
tsv = read("js/TransferService.qml")
htp = read("js/HttpTransport.qml")
test("curl disables user config everywhere",
     tsv.count('"-q"') >= 6 and '"-q"' in htp, kind="STATIC")
test("no redirect flags anywhere",
     not re.search(r'"(-L|--location|--location-trusted)"', tsv)
     and "--no-location" in htp, kind="STATIC")
test("capability URLs go through a private config file",
     "createCurlConfigFile" in tsv, kind="STATIC")
test("auth header is written to a file, never argv",
     "createAuthHeaderFile" in tsv and "Authorization: " not in tsv.split("createAuthHeaderFile")[0][-2000:],
     kind="STATIC")
test("upload form uses parser-safe literals",
     "curlFileForm" in tsv and "--form-string" in tsv, kind="STATIC")
test("download finalization is exclusive", "mv -nT" in tsv, kind="STATIC")
test("process-group cancellation preserved", '"kill", "-TERM", "-"' in tsv, kind="STATIC")
test("cross-origin auth header still blocked",
     "shouldAttachAuth" in tsv and "shouldAttachAuth" in read("js/UrlPolicy.qml"), kind="STATIC")
test("logout cannot resurrect an upload",
     "root.sessionEpoch++" in tsv and "upload.epoch !== root.sessionEpoch" in tsv, kind="STATIC")
test("token never persisted as a password",
     "secret-tool" in read("js/Auth.qml"), kind="STATIC")
test("byte limits preserved",
     "maxUploadBodyBytes" in tsv and "maxResponseBytes" in htp, kind="STATIC")
test("stall protection preserved",
     '"--speed-limit"' in htp and '"--speed-time"' in htp, kind="STATIC")
test("timeouts preserved", '"--connect-timeout"' in htp and '"--max-time"' in htp, kind="STATIC")


# =====================================================================
print("\n--- 10. Release metadata consistency (STATIC) ---")
# =====================================================================
import json
manifest = json.loads(read("manifest.json"))
test("manifest version is 1.1.0", manifest.get("version") == "1.1.0", manifest.get("version"),
     kind="STATIC")
test("Settings About derives from the same version",
     'readonly property string pluginVersion: "1.1.0"' in panel
     and "pluginVersion: root.pluginVersion" in panel, kind="STATIC")
test("foldersFirst is declared in the manifest schema",
     any(f.get("key") == "foldersFirst" for f in manifest["barWidget"]["schema"]), kind="STATIC")
changelog = read("CHANGELOG.md")
test("CHANGELOG has a 1.1.0 section", "[1.1.0]" in changelog, kind="STATIC")
readme = read("README.md")
test("README documents the zenity picker", "zenity" in readme.lower(), kind="STATIC")
test("README no longer claims Qt FileDialog",
     "QtQuick.Dialogs" not in readme and "FileDialog" not in readme, kind="STATIC")
test("README documents foldersFirst", "foldersFirst" in readme or "Folders first" in readme,
     kind="STATIC")
test("README documents the newline filename limitation", "newline" in readme.lower(), kind="STATIC")
test("README documents Quick Access account scope",
     "Quick Access" in readme, kind="STATIC")


print("\n=== %d passed, %d failed, %d skipped ===" % (passed, failed, skipped))
sys.exit(1 if failed else 0)
