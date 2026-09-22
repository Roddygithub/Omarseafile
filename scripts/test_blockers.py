#!/usr/bin/env python3
"""Behavioral regression tests for the v1.2 hardening blockers."""
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
script = r'''const h = require("./scripts/qmljs.js");
function check(name, value) {
  if (!value) throw new Error(name);
  console.log("PASS " + name);
}

// Exercise the production one-shot probe finalizer through every callback order.
const C = h.loadQmlObject("js/ConnectionService.qml", {});
for (const order of [["done", "error"], ["done", "timeout"], ["error", "done"], ["timeout", "done"]]) {
  const probe = { finalized: false };
  let calls = 0;
  for (const event of order) C.finalizeProbe(probe, () => calls++);
  check("probe finalizes once: " + order.join(" then "), calls === 1);
}
C.probeGeneration = 2;
C.online = true;
C.handleResponse(1, 500);
check("stale probe remains ignored", C.online === true);

// Exercise the real SeafileAPI search parser, not a duplicate parser.
function searchResult(type) {
  let callback;
  const A = h.loadQmlObject("js/SeafileAPI.qml", {
    HttpTransport: { get: (url, headers, cb) => { callback = cb; } },
    UrlPolicy: { validateForAuth: () => ({valid: true}), validateTransferUrl: () => ({valid: true}) }
  });
  A.baseUrl = "https://server.example";
  A.token = "token";
  let result;
  A.search("needle", "repo", (ok, data, error) => result = {ok, data, error});
  callback(true, {data: [{path: "/docs/item", size: 1, mtime: 1, type: type}]}, null);
  return result;
}
check("search accepts file", searchResult("file").ok === true);
check("search accepts folder", searchResult("folder").ok === true);
check("search rejects unknown type", searchResult("link").ok === false);
check("search rejects missing type", searchResult(undefined).ok === false);

// Start a real Panel search, navigate via a real result, then deliver the old
// callback. The old callback must not repopulate Search state.
let delayed;
const P = h.loadQmlObject("Panel.qml", {
  SeafileAPI: { search: (q, repo, cb) => { delayed = cb; } },
  SelectionHelper: { makeKey: () => "k" },
  TransferService: {},
  Cache: {},
  Favorites: {},
  UrlPolicy: {},
  Auth: {},
  Models: {},
  SafePath: {},
  Qt: { resolvedUrl: () => "" }
});
P.searchDebounceTimer = { stop: () => {}, restart: () => {} };
P.libraries = [{id: "repo", name: "Repo", encrypted: false}];
P.searchQuery = "needle";
P.searchActive = true;
P.buildPathHistory = () => {};
P.loadFolder = () => {};
P.clearSelection = () => {};
P.currentRepo = null;
P.executeSearch();
check("search callback was captured", typeof delayed === "function");
delayed(true, [{type: "file", name: "old", repoId: "repo"}], null);
check("search has initial result", P.searchResults.length === 1);
P.onSearchResultClicked({type: "folder", repoId: "repo", path: "/docs"});
check("result navigation leaves search", P.searchActive === false);
const generationAfterNavigation = P.searchGeneration;
delayed(true, [{type: "file", name: "stale", repoId: "repo"}], null);
check("stale search callback cannot repopulate results", P.searchGeneration === generationAfterNavigation && P.searchResults.length === 0);

// Exercise the real folder refresh path: an item removed by a batch mutation
// must not remain selected after the refreshed model replaces currentItems.
let folderCallback;
const F = h.loadQmlObject("Panel.qml", {
  SeafileAPI: { listFolder: (repo, path, cb) => { folderCallback = cb; } },
  Cache: { sessionGeneration: 0, getFolder: () => null, setFolder: () => {} },
  SelectionHelper: { makeKey: item => item.repoId + "|" + item.fullPath },
  TransferService: {}, Favorites: {}, UrlPolicy: {}, Auth: {}, Models: {}, SafePath: {},
  Qt: { resolvedUrl: () => "" }
});
F.beginNavigationTiming = () => {};
F.navigationPhase = () => {};
F.navigationComplete = () => {};
F.currentItems = [];
F.currentRepo = {id: "repo"};
F.selectedItems = [{repoId: "repo", fullPath: "/removed"}];
F.loadFolder("repo", "/");
folderCallback(true, [{name: "kept", type: "file", size: 1, mtime: 1}], null);
check("refresh prunes removed batch selection", F.selectedItems.length === 0);
console.log("=== blocker behavioral checks passed ===");
'''
subprocess.run(["node", "-e", script], cwd=ROOT, check=True)
