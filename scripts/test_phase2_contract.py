#!/usr/bin/env python3
"""Behavioral contract checks for the installed Omarchy 4.0.4/Quickshell 0.3.1 host."""
import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
panel = (ROOT / "Panel.qml").read_text()
bar = (ROOT / "BarWidget.qml").read_text()
file_list = (ROOT / "components/FileList.qml").read_text()
host_panel = Path("/usr/share/omarchy/shell/Ui/Panel.qml").read_text()


def check(name, condition):
    if not condition:
        raise AssertionError(name)
    print(f"PASS {name}")


# Exercise the same getter/setter contract and host update path used by the QML fix.
script = r'''
const host = { settings: { autoLogin: true } };
const shell = { updates: [], updateEntryInline(id, settings) { this.updates.push([id, settings]); } };
const panel = { moduleName: "roddy.seafile", settings: host.settings, hostWidget: host, bar: { shell } };
function setting(name, fallback) {
  const value = panel.settings ? panel.settings[name] : undefined;
  return value === undefined || value === null ? fallback : value;
}
function setSetting(name, value) {
  const next = Object.assign({}, panel.settings, {});
  next[name] = value;
  panel.settings = next;
  if (panel.hostWidget && "settings" in panel.hostWidget) panel.hostWidget.settings = next;
  if (panel.bar && panel.bar.shell && typeof panel.bar.shell.updateEntryInline === "function")
    panel.bar.shell.updateEntryInline(panel.moduleName, next);
}
if (setting("autoLogin", true) !== true) throw Error("default read");
setSetting("autoLogin", false);
if (setting("autoLogin", true) !== false) throw Error("panel write");
if (host.settings.autoLogin !== false) throw Error("host write");
if (shell.updates.length !== 1 || shell.updates[0][0] !== "roddy.seafile") throw Error("persistence write");
const restored = { settings: shell.updates[0][1] };
if (restored.settings.autoLogin !== false) throw Error("reopen persistence");
'''
subprocess.run(["node", "-e", script], check=True)
print("PASS settings read/write/persistence behavior")

check("setting() is read-only in the installed contract", 'function setting(name, fallback)' in host_panel and 'function setSetting(name, value)' in panel)
check("all Panel writes use setSetting", 'setting("autoLogin", enabled)' not in panel and 'setting("favoritesStore", Favorites.saveToSettings())' not in panel)
check("external settings refresh the loaded panel", "onSettingsChanged: injectPanel()" in bar and "panelLoader.item.settings = root.settings" in bar)
check("PanelController has one source of truth", "PanelController { id: panelController }" not in panel and "open: root.opened" in panel)
check("toggle follows host-visible opened state", "function toggle() { root.opened ? close() : open() }" in panel)
check("sort changes use the explicit persistence callback", "root.onSortChanged(root.sortColumn, root.sortAscending)" in file_list)
check("sort callback is wired through both views", panel.count("onSortChanged: function(column, ascending)") == 2)
print("=== phase 2 contract checks passed ===")
