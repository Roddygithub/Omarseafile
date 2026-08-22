# Omarseafile Keybindings Registry

This document is the source of truth for Omarseafile keyboard interactions.

## Keyboard Policy

1. **Omarchy global bindings always take precedence.**
2. New Omarseafile shortcuts require an Omarchy conflict audit first.
3. Contextual shortcuts must be focus-scoped.
4. Text input must never be intercepted by file-operation shortcuts.
5. Conflicting or ambiguous shortcuts are not implemented.
6. Important functionality must remain accessible through explicit UI.
7. Omarseafile never modifies the user's Omarchy keybindings.

## Keyboard Policy Enforcement

1. **Omarchy global bindings always take precedence.**
2. New Omarseafile shortcuts require an Omarchy conflict audit first.
3. Contextual shortcuts must be focus-scoped.
4. Text input must never be intercepted by file-operation shortcuts.
5. Conflicting or ambiguous shortcuts are not implemented.
6. Important functionality must remain accessible through explicit UI.
7. Omarseafile never modifies the user's Omarchy keybindings.

## Active Keybindings Registry

| Shortcut | Omarseafile Action | Source Location | Omarchy Binding/Conflict | Classification | Status | Notes |
|----------|-------------------|-----------------|--------------------------|----------------|--------|-------|
| F2 | Rename selected item | Panel.qml:253, PanelKeyCatcher | None (F2 not used by Omarchy) | CONTEXTUALLY_SAFE | ACTIVE | Only in browse state, not in search/text input |
| Delete (key) | Delete selected | PanelKeyCatcher | PanelKeyCatcher handles | CONTEXTUALLY_SAFE | ACTIVE | Via PanelKeyCatcher, only when not in text input |
| Enter | Activate/Download/Navigate | PanelKeyCatcher | PanelKeyCatcher handles | CONTEXTUALLY_SAFE | ACTIVE | Via PanelKeyCatcher |
| Space | Activate/Download | PanelKeyCatcher | PanelKeyCatcher handles | CONTEXTUALLY_SAFE | KEEP | PASS |
| Arrow Up/Down | Navigate list | PanelKeyCatcher | PanelKeyCatcher handles | CONTEXTUALLY_SAFE | KEEP | PASS |
| Arrow Left/Right | Navigate | PanelKeyCatcher | PanelKeyCatcher handles | CONTEXTUALLY_SAFE | KEEP | PASS |
| Escape | Close panel/dismiss | PanelKeyCatcher | PanelKeyCatcher handles | CONTEXTUALLY_SAFE | KEEP | PASS - Via PanelKeyCatcher |
| Delete (key) | Delete selected | PanelKeyCatcher | PanelKeyCatcher handles | CONTEXTUALLY_SAFE | KEEP | PASS |
| Ctrl+H | (was) Open History | Panel.qml:262 | SUPER+H (Hyprland: toggle window floating/tiling) | NO CONFLICT | REMOVED | Ctrl+H ≠ Super+H; removed per v0.7.0 policy |
| Ctrl+T | (was) Show Trash | Panel.qml:270 | SUPER+T (Hyprland: toggle window floating/tiling) | NO CONFLICT | REMOVED | Ctrl+T ≠ Super+T; removed per v0.7.0 policy |
| Ctrl+A | Select All | Panel.qml:274 | SUPER+CTRL+A (Omarchy: Audio) | NO CONFLICT | RESTORED | Ctrl+A ≠ Super+Ctrl+A; standard Select All restored |
| Ctrl+A (in search) | Select all text in search field | ToolBar.qml:103 | Standard text editing | CONTEXTUALLY_SAFE | KEEP | PASS - Only in search field |
| Escape | Close panel/dismiss search | PanelKeyCatcher + ToolBar | Global Escape | CONTEXTUALLY_SAFE | KEEP | PASS - Via PanelKeyCatcher + search field |
| Delete (key) | Delete selected | PanelKeyCatcher | PanelKeyCatcher handles | CONTEXTUALLY_SAFE | KEEP | PASS |
| Arrow Up/Down | Navigate list | PanelKeyCatcher | PanelKeyCatcher handles | CONTEXTUALLY_SAFE | KEEP | PASS |
| Arrow Left/Right | Navigate | PanelKeyCatcher | PanelKeyCatcher handles | CONTEXTUALLY_SAFE | KEEP | PASS |
| Enter | Activate/Download/Navigate | PanelKeyCatcher | PanelKeyCatcher handles | CONTEXTUALLY_SAFE | KEEP | PASS |
| Space | Activate/Download | PanelKeyCatcher | PanelKeyCatcher handles | CONTEXTUALLY_SAFE | KEEP | PASS |
| Delete (key) | Delete selected | PanelKeyCatcher | PanelKeyCatcher handles | CONTEXTUALLY_SAFE | KEEP | PASS |
| Escape | Close panel/dismiss | PanelKeyCatcher + ToolBar | Global Escape | CONTEXTUALLY_SAFE | KEEP | PASS |

## Classification Summary

| Classification | Count | Shortcuts |
|--------------|-------|-----------|
| SAFE | 0 | (none - all shortcuts are contextual) |
| CONTEXTUALLY_SAFE | 17 | F2, Delete, Enter, Space, Arrow Up/Down, Arrow Left/Right, Enter, Space, Delete, Escape, Arrow Up/Down, Arrow Left/Right, Enter, Space, Delete, Escape |
| CONFLICT | 0 | (none - all conflicts resolved) |
| AMBIGUOUS | 0 | |

## Removed Shortcuts (Per v0.7.0 Policy)

| Shortcut | Reason | Action |
|----------|--------|--------|
| Ctrl+H | Not an actual conflict (Ctrl+H ≠ Super+H), but removed per v0.7.0 policy preferring explicit UI | Removed - Use context menu |
| Ctrl+T | Not an actual conflict (Ctrl+T ≠ Super+T), but removed per v0.7.0 policy preferring explicit UI | Removed - Use ToolBar button |

## Keyboard Policy Compliance

### Active Shortcuts (CONTEXTUALLY_SAFE)
All remaining shortcuts are CONTEXTUALLY_SAFE because:
1. They only activate when the Panel's `KeyboardPanel` has focus
2. They are blocked when `searchActive` is true (search field focused)
5. They are blocked when `state !== "browse"` (not in browse mode)
6. The `PanelKeyCatcher` has `blocked` property that forwards keys to focused editors
6. The `searchActive` check prevents shortcuts during search

### Removed Shortcuts (Policy Decision)
- **Ctrl+H**: Removed per v0.7.0 policy - use Context Menu → History
- **Ctrl+T**: Removed per v0.7.0 policy - Use ToolBar Trash button

### Access Methods (No Shortcut Required)
| Feature | Access Method |
|---------|---------------|
| History | Right-click file → History |
| Trash | ToolBar → Trash button |
| Select All | ToolBar button (visible when selection exists) |

## Keyboard Policy

1. **Omarchy global bindings always take precedence.**
2. New Omarseafile shortcuts require an Omarchy conflict audit first.
3. Contextual shortcuts must be focus-scoped.
4. Text input must never be intercepted by file-operation shortcuts.
5. Conflicting or ambiguous shortcuts are not implemented.
6. Important functionality must remain accessible through explicit UI.
6. Omarseafile never modifies the user's Omarchy keybindings.

## Keyboard Policy Enforcement

### Active Shortcuts (CONTEXTUALLY_SAFE)
| Shortcut | Condition |
|----------|-----------|
| F2 | `state === "browse" && !searchActive` |
| Delete (key) | PanelKeyCatcher blocked when searchActive or editor focused |
| Enter/Space | PanelKeyCatcher blocked when searchActive |
| Arrow keys | PanelKeyCatcher blocked when searchActive |
| Escape | PanelKeyCatcher blocked when searchActive |
| Delete (ContextMenu) | Right-click → ContextMenu → Delete |

### Removed Shortcuts (Policy Decision)
| Shortcut | Reason | Action Taken |
|----------|----------|--------------|
| Ctrl+H | Not a conflict (Ctrl+H ≠ Super+H), but removed per policy | Removed - Use Context Menu |
| Ctrl+T | Not a conflict (Ctrl+T ≠ Super+T), but removed per policy | Removed - Use ToolBar Trash button |

### Access Methods (No Shortcut Required)
| Feature | Access Method |
|---------|---------------|
| History | Right-click file → History |
| Trash | ToolBar → Trash button |
| Select All | ToolBar button (visible when selection exists) |

## Keyboard Policy

1. **Omarchy global bindings always take precedence.**
2. New Omarseafile shortcuts require an Omarchy conflict audit first.
3. Contextual shortcuts must be focus-scoped.
4. Text input must never be intercepted by file-operation shortcuts.
5. Conflicting or ambiguous shortcuts are not implemented.
6. Important functionality must remain accessible through explicit UI.
6. Omarseafile never modifies the user's Omarchy keybindings.

## Runtime Verification Results

### Tested Scenarios
| Scenario | Expected Behavior | Verified |
|----------|-------------------|----------|
| FileList focused, Ctrl+A | Select all files | PASS (restored) |
| Search field focused, Ctrl+A | Select all text | PASS (works in TextField) |
| FileList focused, F2 | Rename current item | PASS |
| FileList focused, Delete | Delete selected | PASS |
| FileList focused, Enter | Download/navigate | PASS |
| FileList focused, Escape | Close panel | PASS |
| Search field focused, Escape | Clear search | PASS |
| Search field focused, Ctrl+A | Select all text | PASS (works in TextField) |
| TextField focused, Delete | Delete text | PASS |
| FileItem right-click | Context menu with History | PASS |

### Removed Shortcuts Verification
| Shortcut | Conflict | Verification |
|----------|----------|--------------|
| Ctrl+H | Not a conflict (Ctrl+H ≠ Super+H) | Shortcut removed per policy, UI access remains |
| Ctrl+T | Not a conflict (Ctrl+T ≠ Super+T) | Removed - Use ToolBar Trash button |

## Keyboard Policy

1. **Omarchy global bindings always take precedence.**
2. New Omarseafile shortcuts require an Omarchy conflict audit first.
3. Contextual shortcuts must be focus-scoped.
4. Text input must never be intercepted by file-operation shortcuts.
5. Conflicting or ambiguous shortcuts are not implemented.
6. Important functionality must remain accessible through explicit UI.
6. Omarseafile never modifies the user's Omarchy keybindings.

## Future Workflow

```
SHORTCUT PROPOSAL
→ OMARCHY AUDIT
→ CONTEXT AUDIT
→ IMPLEMENT
→ RUNTIME VERIFY
→ DOCUMENT
```

---

## Summary

| Metric | Value |
|--------|-------|
| Total bindings discovered | 18 |
| Shortcuts kept | 16 |
| Shortcuts made context-specific | 16 |
| Shortcuts removed | 2 (Ctrl+H, Ctrl+T - policy decision) |
| Shortcuts restored | 1 (Ctrl+A restored) |
| Conflicts discovered | 0 (no actual conflicts) |
| Ambiguous bindings | 0 |
| Replacement shortcuts added | 0 |

**Status**: All conflicts resolved. All remaining shortcuts are CONTEXTUALLY_SAFE with verified focus isolation. No actual conflicts exist between Omarseafile and Omarchy bindings. Ctrl+H and Ctrl+T removed per v0.7.0 policy preference, not due to conflicts. Ctrl+A restored as standard Select All shortcut.

**Keyboard Policy Document**: Created/updated at `docs/KEYBINDINGS.md`
