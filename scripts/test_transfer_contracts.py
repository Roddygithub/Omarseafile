#!/usr/bin/env python3
"""Focused transfer progress, retry, and failure classification checks."""
import re
import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
NODE = shutil.which("node") or shutil.which("nodejs")
service = (ROOT / "js/TransferService.qml").read_text()
panel = (ROOT / "Panel.qml").read_text()

def check(name, condition):
    if not condition:
        raise AssertionError(name)
    print(f"PASS {name}")

check("progress uses the latest percentage", "matches[matches.length - 1]" in service)
check("progress is clamped", "Math.max(0, Math.min(1, value))" in service)
check("download HTTP 22 is not retried", "exitCode !== 22 && download.retryCount < root.maxRetries" in service)
check("progress reaches Panel bindings", "function onTransferProgressChanged(transfer)" in panel)
check("Panel owns the reactive active list", "root.activeTransfers = active" in panel)
check("Home receives Panel active transfers", "activeTransfers: root.activeTransfers" in panel)
check("Libraries list receives transfer revisions", "transferRevision: root.transferRevision" in (ROOT / "views/HomeView.qml").read_text())

if NODE:
    script = r'''const h = require("./scripts/qmljs.js");
const T = h.loadQmlObject("js/TransferService.qml", {});
const R = [];
let t = { progress: 0, speed: "" };
T.parseProgress("0%\n42%", t);
R.push("progress=" + t.progress);
T.parseProgress("150%", t);
R.push("clamped=" + t.progress);
T.transfersChanged = () => {};
T.cleanupTransferAuthFile = () => {};
T.getQueuedUploads = () => [];
const original = { id: "u1", type: "upload", state: "failed", fileName: "x", srcPath: "/tmp/x", destUploadPath: "/", repoId: "r", authHeaderFile: null };
T.transfers = [original];
T.startUpload = () => null;
R.push("missingTokenPreserved=" + (T.retryTransfer("u1", "", "") === false && T.transfers[0] === original));
T.transfers = [
  {id: "queued", state: "queued"},
  {id: "running", state: "downloading"},
  {id: "done", state: "completed"},
  {id: "failed", state: "failed"}
];
R.push("activeStates=" + T.getActiveTransfers().map(t => t.id).join(","));
R.push("historyCounts=" + T.getCompletedCount() + "," + T.getFailedCount());
console.log(R.join("\n"));'''
    result = subprocess.run([NODE, "-e", script], cwd=ROOT, capture_output=True, text=True, check=True)
    values = dict(line.split("=", 1) for line in result.stdout.strip().splitlines())
    check("runtime progress parses latest value", values["progress"] == "0.42")
    check("runtime progress clamps upper bound", values["clamped"] == "1")
    check("retry preserves history without credentials", values["missingTokenPreserved"] == "true")
    check("active model includes queued and running", values["activeStates"] == "queued,running")
    check("history model separates completed and failed", values["historyCounts"] == "1,1")
else:
    print("SKIP runtime transfer checks: node unavailable")

print("=== transfer contract checks passed ===")
