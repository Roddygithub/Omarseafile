# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

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