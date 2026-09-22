# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [1.2.0] - 2026-09-22

### Added
- File-type recognition for common documents, images, archives, and code, with a generic fallback.
- Hover discovery for truncated file names and paths.

### Changed
- Hardened session, connectivity, mutation, transfer, login, and stale-response handling.
- Search now validates file/folder result types and ignores stale callbacks after navigation.
- Selection actions use a compact toolbar with secondary actions grouped under More.
- Context actions are grouped by intent and Delete is clearly destructive.
- Keyboard focus, selected-row contrast, loading states, and transfer presentation are improved for compact Omarchy panels.
- Transfer history is bounded and the transfer surface remains scrollable for longer lists.

### Fixed
- Batch selection is pruned after refreshed mutation results.
- Enter/Return login submission and busy/error feedback are consistent.
- Stale connectivity probes, mutation confirmations, and transfer retries cannot act on obsolete session state.

## [1.1.0] - 2026-09-20

### Added
- First-class Transfers view reachable from the Libraries root as well as inside a library, with a single shared transfer state and a "Transfers" toolbar title.
- Account-scoped Quick Access: favorites are stored per server URL plus signed-in email, so switching accounts or servers no longer mixes entries.
- Bounded upload queue: at most three concurrent uploads, with the remainder queued in selection order (cap of 100) and cancellable while queued.
- Real `foldersFirst` preference, persisted and wired through Settings, Panel and the file list. Type sorting keeps its own semantics.
- Quick Access entries for libraries (from the Libraries root) and folders (inside a library), keyed by full folder path so same-named siblings stay distinct.

### Changed
- Upload file picker paths are passed through verbatim. Zenity already returns filesystem paths, so the previous `file://` wrapping plus `decodeURIComponent()` round-trip - which corrupted names such as `100% termine.txt` or a literal `foo%20bar.txt` - is gone.
- Transfer failures are classified from the real HTTP status instead of curl's exit code and message text.
- Icon glyphs and the dedicated icon font are centralised in `js/Icons.qml`; all other text follows the Omarchy user font.
- Search results activate on left-click only, and the filter controls moved into the list header.
- `zenity`, `xdg-open` and `notify-send` are now declared optional dependencies; `python3` is declared required.

### Fixed
- Keyboard navigation was inert: `Panel.fileListRef` was declared but never assigned, so every key handler bailed out on a null list. The navigable list is now derived from the loaded view and nulls itself when no list is on screen.
- Home failed to load because three delegates declared `required property` entries (`bar`, `onClicked`, `onRemoveFromFavorites`, `onCancel`, `onOpen`) that the Repeater never supplied.
- The Home active-transfer cancel button evaluated its callback without calling it, so cancel did nothing.
- `isAuthError()` and `isRetryableError()` were handed error strings rather than statuses, so 401/403 never triggered re-authentication and every HTTP failure looked retryable.
- Adding a file to Quick Access silently pinned the whole library; files are no longer Quick Access targets.
- Removing a Quick Access entry derived its identity from the current browsing context, so it could not work from Home.
- A logout during upload validation could be missed by the pending `stat` preflight, which then resurrected the transfer with the old token. Transfers are now registered before validation and every continuation checks a session epoch.
- `anchors` set on direct children of `Column`/`Row` positioners - ignored by Qt with a runtime warning - replaced with the supported alignment properties.
- Unguarded `ListView` attached-property reads in `FileItem` and an `EmptyState` anchored inside a `Column`.
- The server URL now rejects credentials, query strings and fragments, while still allowing subpath deployments.

### Known Limitations
- The zenity picker separates selections with a newline, so a filename containing a newline cannot be selected. Enter such a path manually in the upload dialog.
- Graphical upload selection needs `zenity`; without it the manual path field is the only upload route.

## [1.0.0] - 2026-09-01

### Added
- Omarchy bar-widget integration for authenticated Seafile library and folder browsing.
- Repo-scoped search, manual-path uploads, protected downloads, transfer management, sharing, file history, and trash browsing.
- Single and batch Delete, Move, and Copy with in-browser destination selection and same-library safety guards.

### Changed
- Prepared public documentation for the v1.0 audit.
- Documented the current main-browser Copy/Move destination workflow.
- Documented the manual-path upload workflow and current platform/server limitations.
- Disabled unconfirmable trash restore instead of treating arbitrary HTTP 200 responses as success.
- Use synchronous folder moves and a root-create/move workaround for nested folder creation on CE 12.0.x.

### Fixed
- Serialized keyring mutations and restored working login/logout credential handling.
- Isolated destination mode from context actions, restored navigation state on cancel, and rejected exact self-targets.
- Captured async operation context so stale callbacks cannot act on a different file, library, or session.
- Disabled user curl configuration, escaped multipart paths, and hardened no-overwrite download finalization.
- Corrected share-link revocation failure reporting.

### Known Limitations
- Upload uses a manually entered local path; a native graphical file picker is not part of v1.
- Move and Copy are limited to the source library.
- Trash restore is disabled because the tested Seafile CE 12.0.x API does not perform or confirm restoration.
- Cleanup after abrupt process or host termination is not guaranteed.
- Nested folder creation uses a temporary root folder; an intermediate server failure can leave that identifiable temporary folder in the library.

## [0.9.0] - 2026-08-23

### Added
- **Post-download Open / Show in Folder** — Right-click completed downloads to open in default application or show in file manager
- **File list sorting** — Click column headers to sort by Name, Size, Modified date, or Type (ascending/descending)
- **Search global result cap** — Limited to 100 results globally with truncation notice
- **Search feedback** — "Searching X of Y libraries..." progress, result counts, truncation notices
- **Empty state illustrations** — Icon + title + subtitle for History, Trash, Search, and Transfers
- **Transfer action tooltips** — Hover tooltips for Cancel, Retry, Clear, Open, Show in Folder

### Changed
- **Empty states** — Visual icons + titles + subtitles for History, Trash, Search, Transfers
- **TransferItem actions** — Added Open and Show in Folder for completed downloads
- **File list sorting** — Clickable column headers for Name, Size, Modified date

### Security
- **Desktop integration** — User-initiated `Qt.openUrlExternally()` only, no auto-execution

## [0.8.0] - 2026-08-22

### Added
- **Settings UI** — Server URL display/change, account email display, Test Connection button, Auto-login toggle, Clear Cache, Logout, plugin version display
- **Settings persistence** — Auto-login preference stored in `shell.json` via Omarchy manifest schema
- **Dependency detection** — Startup check for `curl`, `secret-tool`, `wl-copy` with actionable install hints
- **URL validation** — Syntax validation with normalization, HTTPS warning, malformed URL rejection before auth
- **Connection Test** — User-initiated connectivity check against `/api2/ping/` with categorized errors (INVALID_URL, DNS_FAILURE, CONNECTION_REFUSED, TIMEOUT, TLS_ERROR, SERVER_NOT_SEAFILE)
- **TLS policy** — System trust store only; self-signed certs produce clear error (no silent bypass)
- **Public documentation** — Comprehensive README.md with install, usage, troubleshooting, and known limitations
- **CHANGELOG.md** — Keep-a-Changelog format
- **Validation script** — `scripts/validate.sh` with CI-capable and local-runtime checks
- **GitHub Actions CI** — Static validation workflow (manifest, docs, syntax, forbidden values)
- **Official installation docs** — Documents `omarchy plugin add` as primary install method

### Changed
- **Server URL handling** — Normalized trailing slashes, syntax validation before authentication
- **Login flow** — URL validation and HTTPS warning before auth attempt
- **Toolbar** — Added Settings button (⚙) in browse mode
- **Back button behavior** — Closes Settings dialog before navigating back

### Security
- **TLS verification never weakened** — No `curl -k` or certificate bypass
- **Credential storage unchanged** — Tokens remain in system keyring via `secret-tool`

## [0.7.0] - 2026-08-22

### Added
- **File history browser** — Browse file revision metadata (author, date, size, commit message)
- **Historical revision download** — Download any file revision via TransferManager
- **Trash browser** — View deleted files and folders with metadata
- **Folder restore from trash** — Restore deleted folders with confirmation dialog
- **Multi-selection** — Ctrl+Click, Shift+Click, Ctrl+A for batch operations
- **Batch operations** — Move, Copy, Delete (sequential) via BatchActionBar
- **Keyboard navigation** — F2=rename, Del=delete, Enter=activate, Arrows=navigate, Esc=close, Ctrl+A=Select All
- **BatchActionBar** — Contextual toolbar with Move/Copy/Delete/Clear actions
- **TransferManager UI** — Active/Completed/Failed transfer groups with retry/cancel
- **BarWidget transfer badge** — Active count + failure indicator
- **Toolbar Trash button** — With badge for deleted items count

### Security
- **Token removed from argv/env/logs** — Verified via `/proc/<pid>/cmdline`, `/proc/<pid>/environ`, `journalctl`
- **Secure curl auth via temp files** — Auth header passed via 0600 temp file (`-H @file`), cleaned on all paths

### Fixed
- **Ctrl+A restored** as standard Select All (previously removed)
- **Ctrl+H / Ctrl+T removed** per keyboard policy (not conflicts, policy decision)

## [0.6.0] - 2026-08-XX

### Added
- **Share links** — Create, list, revoke share links with password, expiration, permissions
- **Copy to clipboard** — Share links copied via `wl-copy`
- **Search** — Repo-scoped search with debounced input (300ms)
- **Offline detection** — ConnectionService with 30s polling, 3-failure offline threshold

## [0.5.0] - 2026-08-XX

### Added
- **Transfer retry logic** — Exponential backoff (2s, 4s, 8s, max 3 retries)
- **Manual retry** — Retry failed transfers with fresh credentials
- **Transfer cancellation** — Kill curl, clean partial download file
- **Progress parsing** — Percentage and speed from curl stderr

## [0.4.0] - 2026-08-XX

### Added
- **Concurrent transfers** — Multiple simultaneous downloads/uploads
- **Upload collision handling** — Auto-rename (1), (2) on conflict
- **Replace option** — `replace=1` to overwrite existing files

## [0.3.0] - 2026-08-XX

### Added
- **Single file download/upload** — Basic transfer functionality
- **Folder navigation** — Browse libraries, folders, breadcrumbs
- **Basic UI** — Panel, ToolBar, FileList, FileItem

## [0.2.0] - 2026-08-XX

### Added
- **Authentication** — Login with email/password, token stored in keyring
- **Auto-login** — Session restored from keyring on panel open
- **Logout** — Clears session, transfers, cache

## [0.1.0] - 2026-08-XX

### Added
- **Initial scaffold** — Omarchy bar widget + panel architecture
- **Manifest** — Schema v1, bar-widget kind
- **Deploy script** — `deploy.sh` for runtime sync
