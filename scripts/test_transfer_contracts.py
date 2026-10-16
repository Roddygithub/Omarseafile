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
home = (ROOT / "views/HomeView.qml").read_text()

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
check("notifications use an injected preference", "property bool notifyEnabled: true" in service and "root.notifyEnabled" in service)
check("transfer notification ownership is tracked", "transfer.notificationSent = true" in service and "!transfer.notificationSent" in panel)
check("Panel forwards notification preference", "TransferService.notifyEnabled = root.notifyEnabled" in panel)
check("file progress background waits for progress", "visible: root.transferProgress > 0" in (ROOT / "components/FileItem.qml").read_text())
check("home progress background waits for progress", "visible: isActive && modelData.progress > 0" in home)
item = (ROOT / "components/TransferItem.qml").read_text()
check("Libraries list receives transfer revisions", "transferRevision: root.transferRevision" in home)
check("Home active transfer rows keep their width", "id: row\n                        width: parent.width\n                        spacing: Style.space(12)" in home)
check("Transfer rows keep their width", "id: row\n        width: parent.width\n        spacing: Style.space(8)" in item)
check("Transfer rows render the file name", "root.transfer.fileName || \"Unknown\"" in item)

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
T._notifyFactory = { createObject: () => ({ command: null, running: false }) };
T.cleanupTransferAuthFile = () => {};
T.cleanupTransferConfigFile = () => {};
T._pumpUploadQueue = () => {};
T.transfersChanged = () => {};
T.transferStateChanged = () => {};
const completed = { id: "upload-done", type: "upload", state: "uploading", fileName: "x", progress: 0, speed: "", authHeaderFile: null, curlConfigFile: null, process: { stdout: { text: '[{"name":"x"}]' }, destroy() {} } };
T.transfers = [completed];
T.handleUploadExited(0, completed);
R.push("completionState=" + completed.state);
R.push("completionActive=" + T.getActiveTransfers().length);
R.push("completionNotified=" + completed.notificationSent);
R.push("legacyRetryable404=" + T.isRetryableError(404, "timeout"));
R.push("legacyRetryable500=" + T.isRetryableError(500, "permanent"));
console.log(R.join("\n"));'''
    result = subprocess.run([NODE, "-e", script], cwd=ROOT, capture_output=True, text=True, check=True)
    values = dict(line.split("=", 1) for line in result.stdout.strip().splitlines())
    check("runtime progress parses latest value", values["progress"] == "0.42")
    check("runtime progress clamps upper bound", values["clamped"] == "1")
    check("retry preserves history without credentials", values["missingTokenPreserved"] == "true")
    check("active model includes queued and running", values["activeStates"] == "queued,running")
    check("history model separates completed and failed", values["historyCounts"] == "1,1")
    check("completed upload leaves active model", values["completionState"] == "completed" and values["completionActive"] == "0")
    check("completed upload owns one notification", values["completionNotified"] == "true")
    check("legacy retry helper ignores misleading message on 404", values["legacyRetryable404"] == "false")
    check("legacy retry helper classifies 500 by status", values["legacyRetryable500"] == "true")
else:
    print("SKIP runtime transfer checks: node unavailable")

print("=== transfer contract checks passed ===")
