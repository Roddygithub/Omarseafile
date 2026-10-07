# Phase 2 — installed Omarchy contract

## Evidence

Historical machine-runtime inspection (not a statement about the current host): Omarchy `4.0.4-1`, Quickshell `0.3.1`, host sources under `/usr/share/omarchy/shell`. Recheck the installed runtime before relying on version-specific details.

## Contract comparison

### Settings

**DOCUMENTED_CONTRACT / INSTALLED_RUNTIME_CONTRACT:** `Panel` and `BarWidget`
receive a `settings` object from the shell. `setting(name, fallback)` only
reads that object and returns the fallback for a missing/null key. It is not a
setter. Persistence uses the host shell API:

```qml
root.settings = Object.assign({}, root.settings, { key: value })
root.hostWidget.settings = root.settings
root.bar.shell.updateEntryInline(root.moduleName, root.settings)
```

The installed examples are the installed shell's `Ui/Panel.qml` and example panels.

**OMARSEAFILE_ASSUMPTION (baseline):** calls such as
`setting("autoLogin", enabled)` and `setting("favoritesStore", value)` wrote
nothing. Baseline reproduction: the getter returned the old value after the
write call and a recreated component did not see the change.

The fix adds one small `setSetting()` path, updates the host widget, and calls
`updateEntryInline`. Sort changes now use the same path.

### Panel lifecycle

**DOCUMENTED_CONTRACT / INSTALLED_RUNTIME_CONTRACT:** the installed `Panel`
base owns one `PanelController`, exposes `opened`, `open`, `close`,
`closeForPopoutSwitch`, and `toggle`, and the `KeyboardPanel` open binding
should follow `opened`. The bar widget forwards `open`, `close`, `toggle`,
`opened`, and `popoutSwitchClosing`; popout handoff uses
`closeForPopoutSwitch`.

**OMARSEAFILE_ASSUMPTION (baseline):** `Panel.qml` declared a second local
`PanelController` with the same id and bound `KeyboardPanel.open` to that
controller. The base `opened` property and the visual panel could therefore
have different state sources. Baseline also duplicated the host controller
rather than using the base `controller` alias.

The fix removes the second controller and uses `root.controller`/`root.opened`.
The inherited `closeForPopoutSwitch()` remains the single popout handoff path.
`BarWidget` now reinjects settings when the host changes them externally.

## Lifecycle decisions

Panel-local navigation, dialogs, selections, and view state may be recreated
when the Loader is recreated. Settings and active transfers remain in their
singletons/host settings. Opening still loads libraries only when empty;
closing does not cancel transfers or clear persisted configuration. Reopening
uses the same host-visible controller state and refreshes connectivity.

## Runtime observations before correction

Runtime log observations from that investigation are historical and may no longer apply; reproduce against the current process before acting on them.
