# Omarseafile Panel.qml Architecture Audit

**File**: `/home/roddy/Projects/Omarseafile/Panel.qml` (1724 lines)
**Companion**: `/home/roddy/Projects/Omarseafile/views/BrowserView.qml` (7548 lines)
**Other views**: No separate HomeView, SearchView, TransferView QML files exist; view decomposition lives inside BrowserView.qml.

---

## 1. Current State Machine

The Panel's root object holds a dense flat state machine with 30+ `property` declarations. Key groups:

| State Group | Properties |
|---|---|
| **View navigation** | `state` ("login" \| "browse"), `navigationGeneration`, `sessionGeneration`, `connectionTestGeneration`, `loginGeneration` |
| **Visibility toggles** | `showTransfers`, `showHistory`, `showTrash`, `searchActive`, `destinationMode` (string: "" \| "move" \| "copy") |
| **Search** | `searchQuery`, `searchState` ("idle" \| "debounce" \| "loading" \| "results" \| "error" \| "empty"), `searchResults`, `searchErrorMessage`, `searchGeneration`, `searchPendingCount`, `searchTruncated`, `maxSearchResults` (100) |
| **Transfers** | `activeTransferCount`, `hasTransferFailures`, `fileTransfers` (map), `transferRevision` |
| **Destination mode** | `destinationOperation` ("move" \| "copy"), `destinationSources` (array), `destinationSourceRepoId`, `destinationSourcePath`, `destinationSourceHistory`, `destinationSubmitting` |
| **Selection** | `selectedItems` (array), `selectionAnchor` (item null) |
| **Browse context** | `currentRepo`, `currentPath`, `pathHistory` (array), `libraries` (array), `currentItems` (array), `loading`, `errorMessage` |
| **IPC / lifecycle** | `hostWidget`, `anchorItem`, `bar`, `fileListRef`, `settingsOpen`, `dialogOpen`, `_loaderEditing()`, `textInputActive` |

**Transition functions** (defined on Panel root):
- `handleBackClick()` — cycles through: transfers � history � trash � settings ⇒ goBack()
- `closeTopDialog()` — dismisses topmost modal, returns true if handled
- `toggleTransfersView()` — `showTransfers = !showTransfers`
- `doLogin()`, `doLogout()` — reset entire state machine
- `openSettings()`, `closeSettings()` — toggle settings loader
- `beginDestinationMode(operation, snapshot)` — enters destination mode
- `cancelDestinationMode()` — exits destination mode, restores path history
- `confirmDestination()` — submits move/copy operation
- `moveItems()`, `copyItems()` — begin destination mode from selection
- `pickDelete(item)`, `deleteItems()` — delete flow
- `openHistory(item)`, `openTrash()` — show respective panels
- `pickFileForUpload()`, `confirmUpload()`, `openFile()`, `downloadFile()` — file actions
- `executeSearch()` — debounced global search across libraries
- `onSearchQueryChanged()`, `onSearchActiveToggle()` — search control
- `refresh()` — reload current folder
- `goBack()`, `navigateToPath(index)` — path navigation
- `loadLibraries()`, `loadFolder()` — data loading

**State-aware UI** (ToolBar visibility bindings):
- `showBack`, `showRefresh`, `showUpload`, `showCreateFolder`, `showSearch`, `showLogout`
- `showTransfers`, `showTrash`
- `destinationMode`, `destinationOperation`, `destinationCount`, `destinationPath`
- `searchActive`, `searchQuery`, `selectionCount`, `hasTrashItems`

---

## 2. View Boundaries

### BrowserView (the only view component, `views/BrowserView.qml`)

Declarative layout: a `Column` stacking overlay elements, each with `visible` guards.

| Sublayout | When visible | Key properties/signals |
|---|---|---|
| `Breadcrumbs` | `!root.searchActive` | `path: root.pathHistory`, `onSegmentClicked` → `onNavigateToPath` |
| `LoadingIndicator` | `root.loading` | message: "Searching..." / "Loading..." |
| `ErrorOverlay` | `root.errorMessage !== "" && !root.searchActive` | `onRetry` → `root.onRefresh` |
| `OfflineBanner` | `!root.connectionService.online` | fixed message |
| `searchStatusText` | `root.searchActive && (loading\|results\|empty)` | shows pending-count / results count / "No results found" |
| `searchErrorOverlay` | `root.searchActive && searchState === "error"` | `onRetry` → `root.onSearchRetry` |
| `FileList` | `!root.loading && root.errorMessage === "" && !root.searchActive && !root.showTransfers` | displays `root.currentItems`, handles selection via `onToggleSelection`, `onSelectionRange`, `onSelectOnly`, `onPositionClicked`, `onContextMenuRequested` |
| `SearchResults` | `root.searchActive && searchState !== "loading"` | displays `root.searchResults`, `onResultClicked` → `onSearchResultClicked` |
| `TransferManager` | `root.showTransfers && !root.searchActive` | shows transfer list, cancel/retry/clear actions |

**Required properties** (Panel → BrowserView): `bar`, `currentItems`, `pathHistory`, `libraries`, `loading`, `errorMessage`, `searchActive`, `searchState`, `searchResults`, `searchErrorMessage`, `searchTruncated`, `maxSearchResults`, `showTransfers`, `transferRevision`, `selectedItems`, `selectionAnchor`, `currentRepo`, `currentPath`, `destinationMode`, `connectionService`, `searchPendingCount`, and 20+ callback props (`onItemClicked`, `onDownloadClicked`, `onOpenClicked`, `onRenameClicked`, `onMoveClicked`, `onDeleteClicked`, `onShareClicked`, `onHistoryClicked`, `onSearchResultClicked`, `onNavigateToPath`, `onRefresh`, `onToggleSelection`, `onSelectRange`, `onSelectOnly`, `onPositionClicked`, `onContextMenuRequested`, `onSearchRetry`).

**No separate views exist**: There is no `HomeView.qml`, `SearchView.qml`, or `TransferView.qml`. The "views" are runtime-enabled/disabled via `visible` boolean guards inside BrowserView. The Panel uses Loader components (`loginComponent`, `browseComponent`, plus 8 modal loaders: `createFolderLoader`, `renameLoader`, `confirmLoader`, `shareLoader`, `uploadLoader`, `historyLoader`, `trashLoader`, `settingsLoader`) to swap top-level components.

---

## 3. Shared State: Panel vs Views

### Stay in Panel (state machine root)

These are the "global" controls that coordinate all views. Moving them would require re-architecting the Loader-based modal system.

- `state`, `serverUrl`, `currentRepo`, `currentPath`, `pathHistory`, `libraries`, `currentItems`
- `loading`, `errorMessage`, `depErrorMessage`, `depsChecked`
- `showTransfers`, `showHistory`, `showTrash`, `searchActive`, `destinationMode`
- `destinationOperation`, `destinationSources`, `destinationSourceRepoId`, `destinationSourcePath`, `destinationSourceHistory`, `destinationSubmitting`
- `activeTransferCount`, `hasTransferFailures`, `fileTransfers`, `transferRevision`
- `searchQuery`, `searchState`, `searchResults`, `searchErrorMessage`, `searchGeneration`, `searchPendingCount`, `searchTruncated`
- `selectedItems`, `selectionAnchor`
- `navigationGeneration`, `sessionGeneration`, `connectionTestGeneration`, `loginGeneration`
- `textInputActive` (derived), `settingsOpen`, `dialogOpen`
- All `handle*()`, `do*()`, `open*()`, `close*()` functions

### Could be moved to views (but currently embedded)

These are view-local states that are *read* from Panel but could conceptually live in the view:

- `searchState`, `searchErrorMessage`, `searchPendingCount`, `searchTruncated` — only used by BrowserView's search overlays
- `transferRevision`, `fileTransfers` — only used by TransferManager inside BrowserView
- `destinationMode` — but this is a cross-view mode (affects Panel ToolBar + BrowserView + selection), so keeping it in Panel is correct
- `selectedItems` / `selectionAnchor` — selection logic lives in Panel (SelectionHelper) but is read by BrowserView FileList

**Verdict**: The current decomposition is reasonable. Panel owns the "model" (state + data); BrowserView owns the "view logic" (visible guards, local rendering). The main risk is the flat state machine growing unchecked as new toggles are added.

---

## 4. Integration Points & Event Handlers

### Panel → BrowserView (20+ callbacks, all required properties)

| Callback | Panel function delegates to | Purpose |
|---|---|---|
| `onItemClicked` | `root.onItemClicked(item)` | Open folder or navigate |
| `onDownloadClicked` | `root.downloadFile(item)` | Start download |
| `onOpenClicked` | `root.openFile(item)` | Start open/preview |
| `onRenameClicked` | `root.pickRename(item)` | Start rename flow |
| `onMoveClicked` | `root.beginDestinationMode("move", [item])` | Start move with single item |
| `onDeleteClicked` | `root.pickDelete(item)` | Start delete flow |
| `onShareClicked` | `root.pickShare(item)` | Start share flow |
| `onHistoryClicked` | `root.openHistory(item)` | Show historical revisions |
| `onSearchResultClicked` | `root.onSearchResultClicked(result)` | Navigate to search result |
| `onNavigateToPath` | `root.navigateToPath(index)` | Jump to history entry |
| `onRefresh` | `root.refresh()` | Reload current folder |
| `onToggleSelection` | `root.toggleSelection` | Toggle single selection |
| `onSelectRange` | `root.selectRange(item, visibleItems)` | Shift+click range select |
| `onSelectOnly` | `root.selectOnly(item)` | Replace selection with single item |
| `onPositionClicked` | `root.positionOn(item)` | Click without selecting (anchor only) |
| `onContextMenuRequested` | `root.showItemContextMenu(item, x, y)` | Show context menu |
| `onSearchRetry` | `root.executeSearch()` | Retry search |

### BrowserView → Panel (signals / ToolBar handlers)

| Handler | Target | Purpose |
|---|---|---|
| `onBackClicked` | `root.handleBackClick` | Navigate back or close modals |
| `onRefreshClicked` | `root.refresh` | Reload |
| `onUploadClicked` | `root.pickFileForUpload` | Open upload dialog |
| `onCreateFolderClicked` | `root.pickCreateFolder` | Open create folder dialog |
| `onSearchChanged` | `root.onSearchQueryChanged` | Update search query as user types |
| `onSearchActiveToggled` | `root.onSearchActiveToggle` | Show/hide search bar |
| `onLogoutClicked` | `root.doLogout` | Log out |
| `onTransfersClicked` | `root.toggleTransfersView` | Show/hide transfers |
| `onTrashClicked` | `root.showTrashPanel` | Show trash |
| `onSettingsClicked` | `root.openSettings` | Open settings |
| `onMoveBatch` | `root.moveItems` | Move multiple selected |
| `onCopyBatch` | `root.copyItems` | Copy multiple selected |
| `onDeleteBatch` | `root.deleteItems` | Delete multiple selected |
| `onClearSelection` | `root.clearSelection` | Clear selection |
| `onDestinationCancel` | `root.cancelDestinationMode` | Cancel move/copy |
| `onDestinationConfirm` | `root.confirmDestination` | Finalize move/copy |
| `showOffline` | `!connectionService.online` | Offline banner |

### KeyboardPanel (embedded in Panel content)

| Handler | Purpose |
|---|---|
| `onCloseRequested` | `closeTopDialog()` ⇒ `root.close()` |
| `onMoveRequested` | h/j/k/l navigation or goBack |
| `onActivateRequested` | Open selected file/folder |
| `onDeleteRequested` | Delete selected items or pick delete |
| Shortcuts: F2 (rename), Ctrl+A (select all), Delete (delete) |

### IpcHandler

| Function | Target |
|---|---|
| `open()` | `root.open()` |
| `close()` | `root.close()` |
| `show()` | `root.open()` |
| `hide()` | `root.close()` |
| `toggle()` | `root.toggle()` |
| `status()` | `root.state` |

### Modal Loader Integration

8 `Loader` items in Panel content, each with a `Component` definition:

| Loader | Component | When active |
|---|---|---|
| `stateLoader` | `loginComponent` (LoginDialog) | `root.state === "login"` |
| `destinationBarLoader` | `destinationBarComponent` | `root.destinationMode !== ""` |
| `createFolderLoader` | `createFolderComponent` | User-activated |
| `renameLoader` | `renameComponent` | User-activated |
| `confirmLoader` | `confirmComponent` (ConfirmDialog) | User-activated |
| `shareLoader` | `shareComponent` (ShareDialog) | User-activated |
| `uploadLoader` | `uploadComponent` (UploadDialog) | User-activated |
| `historyLoader` | `historyComponent` (HistoryPanel) | `root.showHistory` |
| `trashLoader` | `trashComponent` (TrashPanel) | `root.showTrash` |
| `settingsLoader` | `settingsComponent` (SettingsDialog) | User-activated |

**Key integration pattern**: Each modal Loader's `sourceComponent` is set to the Component `id`, and cleared to `undefined` to hide. The `dialogOpen` readonly property is `true` if *any* loader's `item !== null`. This gates KeyboardPanel navigation/actions.

---

## Summary & Recommendations

1. **No separate view files exist** — HomeView, SearchView, TransferView are not decomposed. All view logic resides in `BrowserView.qml` via visible guards. If decomposition is desired, each view could be a separate QML file with its own Loader, but the current design is functional.

2. **State machine is flat and Panel-owned** — All 30+ properties live on the Panel root. Consider grouping related properties into a sub-object (e.g., `root.stateMachine = { showTransfers: false, search: { active: false, query: "" } }`) to reduce noise, but this is a refactor, not a fix.

3. **Event handler coverage is comprehensive** — Every UI action in ToolBar, FileList, SearchResults, TransferManager, and KeyboardPanel has a dedicated callback. The integration pattern (Panel function → BrowserView callback → Panel function) is consistent.

4. **Modal loaders are the view-switching mechanism** — Eight Loader items handle modal dialogs. The `dialogOpen` gating is the single source of truth for "is anything open?".

5. **Shared state boundaries are clear** — Panel holds the model; BrowserView holds the view-local rendering state (search overlays, transfer list visibility). The `required property` declarations on BrowserView make the dependency graph explicit.

6. **Potential simplification**: The `destinationMode` + `destinationSources` + `destinationOperation` could be consolidated into a single `DestinationMode { operation: "move", sources: [...] }` object, but the current flat properties work and are directly bound in ToolBar.

---
*End of audit. No files were modified.*