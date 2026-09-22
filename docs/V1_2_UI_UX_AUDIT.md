# Omarseafile v1.2 UI/UX audit

Baseline: `151c7ec71b95af6b0de601fda14c1b986b0dea02`

## Runtime reference

Captured from the synchronized Omarchy runtime before UI changes:

- `/tmp/omarseafile-before.png` — panel at the Libraries root.
- `/tmp/omarseafile-before-crop.png` — readable crop of the panel.

The panel is a compact top-right card. The current root view is legible and
appropriately dense, but file rows use one generic file glyph, selected rows
are distinguished mainly by a subtle tint, and the selection action bar gives
Move, Copy, Delete, and Clear equal weight. Context actions are a flat list.

## KEEP

- Omarchy `Style`, `Color`, `Icons`, and bar font bindings.
- The single Browser/FileList navigation model and existing keyboard cursor.
- Search, transfer, error, and selection contracts from core hardening.
- Current compact panel dimensions and existing popup positioning.

## CHANGE

- Add a small, bounded file-type icon mapping with a generic fallback.
- Make long names discoverable without changing row width.
- Strengthen selected/current/focus row affordances without relying only on hue.
- Reduce the selection toolbar to the highest-frequency actions; retain the
  remaining action through the existing context-menu path.
- Add lightweight grouping and destructive emphasis to context actions.
- Clarify state and transfer surfaces only where the current hierarchy is
  ambiguous.

## REMOVE_OR_SIMPLIFY

- Do not add previews, recents, sync, tagging, comments, or a second design
  system.
- Do not duplicate core action targeting or navigation state.
- Do not expand the format mapping into a catalogue of every extension.

## Phase plan

B: file list readability and selection affordances.
C: compact selection toolbar.
D: context-menu grouping and DetailsPanel action hierarchy.
E: keyboard/focus affordances using existing ListView/Popup focus paths.
F: loading/empty/error/transfer presentation.
G: final spacing and Omarchy polish after functional changes.
