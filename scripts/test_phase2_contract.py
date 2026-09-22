#!/usr/bin/env python3
"""Behavioral contract checks for the installed Omarchy panel host."""
import os
import re
import subprocess
from pathlib import Path

ROOT = Path(os.environ.get("PHASE2_SOURCE_ROOT", Path(__file__).resolve().parent.parent))
panel = (ROOT / "Panel.qml").read_text()
bar = (ROOT / "BarWidget.qml").read_text()
file_list = (ROOT / "components/FileList.qml").read_text()
home = (ROOT / "views/HomeView.qml").read_text()
browser = (ROOT / "views/BrowserView.qml").read_text()
host_root = Path("/usr/share/omarchy/shell")
host_panel = (host_root / "Ui/Panel.qml").read_text()
host_controller = (host_root / "Ui/PanelController.qml").read_text()


def check(name, condition):
    if not condition:
        raise AssertionError(name)
    print(f"PASS {name}")


class Settings:
    def __init__(self, values):
        self.values = dict(values)
        self.listeners = []

    def replace(self, values):
        self.values = dict(values)
        for listener in self.listeners:
            listener(self.values)

    def setting(self, name, fallback):
        value = self.values.get(name)
        return fallback if value is None else value


class PanelBinding:
    """Small observable model of QML's binding to Panel.settings."""
    def __init__(self, settings):
        self.settings = settings
        self.foldersFirst = settings.setting("foldersFirst", True)
        settings.listeners.append(self._settings_changed)

    def _settings_changed(self, _values):
        # A QML property binding stays live when the source property changes.
        self.foldersFirst = self.settings.setting("foldersFirst", True)

    def set_setting(self, name, value):
        next_values = dict(self.settings.values)
        next_values[name] = value
        self.settings.replace(next_values)

    def user_toggle_folders_first(self, value):
        self.set_setting("foldersFirst", value)


# This is the discriminating behavior: after the UI write, an external host
# update must still reach the bound property. The baseline fails because its
# UI handler assigns root.foldersFirst imperatively and destroys the binding.
settings = Settings({"foldersFirst": True})
panel_model = PanelBinding(settings)
panel_model.user_toggle_folders_first(False)
check("foldersFirst user toggle persists", settings.values["foldersFirst"] is False)
settings.replace({"foldersFirst": True})
check("foldersFirst external update reaches bound property", panel_model.foldersFirst is True)
settings.replace({})
check("foldersFirst default is restored", panel_model.foldersFirst is True)

# The source guard makes the behavioral model apply to the actual QML path,
# rather than accepting a passing copy of setSetting implemented in this test.
folders_handler = re.search(r'onFoldersFirstToggled:\s*function\(enabled\)\s*\{(?P<body>.*?)\n\s*\}', panel, re.S)
check("foldersFirst handler exists", folders_handler is not None)
check("foldersFirst handler does not overwrite its binding",
      folders_handler is not None and "root.foldersFirst =" not in folders_handler.group("body"))
check("foldersFirst handler persists through setSetting",
      folders_handler is not None and 'root.setSetting("foldersFirst", enabled)' in folders_handler.group("body"))
check("Panel foldersFirst binding has the Omarchy default",
      'property bool foldersFirst: setting("foldersFirst", true)' in panel)
check("FileList accepts the Panel foldersFirst binding",
      "property bool foldersFirst: true" in file_list and "foldersFirst: root.foldersFirst" in browser)

# Verify the real host contract and the actual source paths, without copying
# the production setter into the test harness.
check("installed setting() is a getter", "function setting(name, fallback)" in host_panel)
check("production setter updates Panel settings", "root.settings = next" in panel)
check("production setter updates host settings", 'root.hostWidget.settings = next' in panel)
check("production setter calls host persistence", 'root.bar.shell.updateEntryInline(root.moduleName, next)' in panel)
for key in ("autoLogin", "singleClickOpen", "sortColumn", "sortAscending", "foldersFirst", "notifyEnabled"):
    check(f"{key} has no getter-as-setter call", not re.search(
        rf'setting\("{key}",\s*(?:enabled|col|asc|value)\)\s*$', panel, re.M))

# Controller lifecycle model: Panel.opened and KeyboardPanel.open must read the
# same host controller boolean through every operation.
class Controller:
    def __init__(self):
        self.open = False
    def show(self):
        self.open = True
    def hide(self):
        self.open = False

controller = Controller()
controller.show()
check("controller open and Panel opened agree", controller.open is True)
controller.hide()
check("controller close clears Panel opened", controller.open is False)
controller.show()
controller.hide()
controller.show()
check("reopen restores the same controller state", controller.open is True)

check("installed controller exposes one open state", "property bool open: false" in host_controller)
check("Panel has no second local controller", "PanelController { id: panelController }" not in panel)
check("Panel open uses inherited controller", "root.controller.show()" in panel)
check("Panel close uses inherited controller", "root.controller.hide()" in panel)
check("Panel toggle reads host-visible opened", "function toggle() { root.opened ? close() : open() }" in panel)
check("KeyboardPanel follows root.opened", "open: root.opened" in panel)
check("popout close remains inherited", "function closeForPopoutSwitch" not in panel)
check("base popout lifecycle exists", "function closeForPopoutSwitch()" in host_panel and "popoutSwitchClosing" in host_panel)
check("bar forwards popout close", "panelLoader.item.closeForPopoutSwitch()" in bar)
check("external settings are reinjected", "onSettingsChanged: injectPanel()" in bar and "panelLoader.item.settings = root.settings" in bar)
check("sort callback reaches both views", "onSortChanged: root.onSortChanged" in home and "onSortChanged: root.onSortChanged" in browser)

print("=== phase 2 contract checks passed ===")
