# Omarseafile v1.0 Definition of Done

This document defines the complete criteria for considering Omarseafile v1.0 "done" and ready for public release as an Omarchy plugin.

---

## 1. FUNCTIONALITY

### Core File Operations (MUST HAVE)
- [ ] Browse libraries and navigate directories
- [ ] Download files (with progress)
- [ ] Upload files (with progress, collision handling)
- [ ] Create folders
- [ ] Rename files/folders
- [ ] Move files/folders (single + batch)
- [ ] Copy files/folders (single + batch)
- [ ] Delete files/folders (single + batch sequential)
- [ ] Rename files/folders
- [ ] Create folders
- [ ] Search files (repo-scoped)
- [ ] Share links (create, list, delete)
- [ ] File history browser
- [ ] Revision download
- [ ] Trash browser (files + folders)
- [ ] Restore deleted folders from trash
- [ ] Deleted files visible in trash (restore disabled with explanation)
- [ ] Folder restore from trash

### Advanced File Operations (v0.8+)
- [ ] File lock/unlock
- [ ] File comments (view + create)
- [ ] Star/unstar files
- [ ] Upload links (create, list, delete)
- [ ] Star/unstar items
- [ ] Batch operations (move, copy, delete, copy)

### UX & Polish (v0.8+)
- [ ] Keyboard shortcuts: F2=rename, Del=delete, Enter=activate, Arrows=navigate, Esc=close, Ctrl+A=select all, Ctrl+H (removed), Ctrl+T (removed)
- [ ] Visible Select All / Clear buttons in BatchActionBar
- [ ] Subtle selection highlight on selected rows
- [ ] Selection count in BatchActionBar
- [ ] Keyboard: F2=rename, Del=delete, Enter=activate, Arrows=navigate, Esc=clear selection/close, Ctrl+A=select all
- [ ] Context menu: History for files
- [ ] Trash button in ToolBar with badge
- [ ] BatchActionBar with Move/Copy/Delete/Clear
- [ ] Transfer Manager with active/completed/failed groups
- [ ] Transfer badge in BarWidget (count + failure indicator)
- [ ] Keyboard navigation: F2=rename, Arrows=navigate, Enter=activate, Del=delete, Esc=close, Ctrl+A=select all, F2=rename
- [ ] Keyboard: Ctrl+H removed, Ctrl+T removed, Ctrl+A=Select All (restored)
- [ ] Search: debounced, repo-scoped, results navigation
- [ ] Empty states for history, trash, search
- [ ] Error overlays with retry
- [ ] Toast notifications (success/error)
- [ ] Offline banner
- [ ] Loading indicators
- [ ] Progress bars for transfers
- [ ] Transfer speed display
- [ ] File size formatting
- [ ] File type icons (folder/file)
- [ ] Keyboard navigation in FileList (arrows, Enter, F2, Delete, Ctrl+A)
- [ ] Context menus (right-click)
- [ ] Context menu: History action for files
- [ ] Transfer Manager with active/completed/failed groups
- [ ] Transfer badge in BarWidget
- [ ] ToolBar with Trash button + badge
- [ ] BatchActionBar with Move/Copy/Delete/Clear
- [ ] Transfer Manager (active/completed/failed groups)
- [ ] BarWidget transfer badge (count + failure indicator)
- [ ] ToolBar Trash button with badge
- [ ] Keyboard shortcuts: F2, Del, Enter, Space, Arrows, Esc, Ctrl+A
- [ ] Search with debounce, repo-scoped
- [ ] Offline banner
- [ ] Keyboard shortcuts documented in KEYBINDINGS.md

### Network & Offline
- [ ] Offline detection (ConnectionService)
- [ ] Automatic reconnection
- [ ] Offline banner display
- [ ] Offline state persists across panel open/close

### Transfers
- [ ] Download with progress + speed
- [ ] Upload with progress + speed
- [ ] Cancel transfer (kills curl, deletes partial file)
- [ ] Retry logic (exponential backoff, max 3)
- [ ] Automatic retry on transient errors
- [ ] Manual retry for failed transfers
- [ ] Cancel all transfers on logout
- [ ] Partial download cleanup on cancel
- [ ] Transfer history (completed/failed retained, max 50)
- [ ] Clear completed/failed transfers
- [ ] Transfer Manager UI (active/completed/failed tabs)
- [ ] BarWidget transfer badge (count + failure indicator)
- [ ] Transfer Manager UI (active/completed/failed groups)
- [ ] Transfer badge in BarWidget (count + failure indicator)
- [ ] Transfer Manager with active/completed/failed groups
- [ ] BarWidget badge (count + failure color)
- [ ] Toast notifications (success/error)
- [ ] Toast click to dismiss

### Authentication & Session
- [ ] Login with server URL, email, password
- [ ] Token stored in system keyring (secret-tool)
- [ ] Server URL stored in keyring
- [ ] Email stored in keyring
- [ ] Session validation on startup
- [ ] Auto-login on panel open
- [ ] Logout clears session + transfers + cache
- [ ] Logout cancels active transfers
- [ ] Invalid token → auto-logout
- [ ] Server URL stored in keyring
- [ ] Email stored in keyring
- [Server URL validation (HTTPS preferred)]
- [ ] Self-signed certificate handling (if applicable)

### Caching
- [ ] Library listing cache (30s TTL)
- [ ] Folder listing cache (30s TTL, 100 entries max)
- [ ] Cache invalidation on mutations
- [ ] Force refresh option
- [ ] Cache TTL: 30 seconds default
- [ ] Max 100 cache entries (LRU eviction)

### Search
- [ ] Repo-scoped search (v2.1 API)
- [ ] Debounced input (300ms)
- [ ] Min query length: 2 chars
- [ ] Results show: name, path, size, type, repo name
- [ ] Click file → navigate to parent folder
- [ ] Click folder → navigate
- [ ] Clear search on escape
- [ ] Search field in ToolBar
- [ ] Search debounce (300ms)
- [ ] Min query length: 2 chars
- [ ] Results show: name, type, path, size, repo name
- [ ] Click file → navigate to parent, select file
- [ ] Click folder → navigate to folder
- [ ] Clear search on Escape
- [ ] Loading state during search
- [ ] Error state with retry

### Share Links
- [ ] Create share link (file/folder)
- [ ] Password protection (min 6 chars)
- [ ] Expiration date (days)
- [ ] Permissions (edit/download/upload)
- [ ] List existing share links
- [ ] Revoke share link (with confirmation)
- [ ] Copy link to clipboard (wl-copy)
- [ ] Password min 6 chars validation
- [ ] Expiration days input (string format)
- [ ] Permissions: can_edit, can_download, can_upload
- [ ] Duplicate link prevention

### Upload
- [ ] File upload via file path input
- [ ] Upload progress + speed
- [ ] Collision handling (auto-rename with (1), (2))
- [ ] Replace option (replace=1)
- [ ] Upload link reuse (reuse=1)
- [ ] Cancel upload
- [ ] Multi-file upload (single file per dialog)
- [ ] Upload to current folder
- [ ] File picker: manual path entry (no native picker)
- [ ] Upload progress + speed display
- [ ] Upload cancellation
- [ ] Replace behavior (auto-rename on collision)
- [ ] Upload link reuse

### Download
- [ ] Download to ~/Downloads
- [ ] Progress + speed
- [ ] Cancel download
- [ ] Partial file cleanup on cancel/failure
- [ ] Retry with exponential backoff (max 3)
- [ ] Auth header via temp file (secure)
- [ ] File name collision handling (auto-rename)
- [ ] Download to ~/Downloads
- [ ] Progress + speed display
- [ ] Cancel support
- [ ] Partial file cleanup on cancel/failure
- [ ] Retry with exponential backoff (max 3)
- [ ] Auth header via temp file (0600 perms)

### Transfers
- [ ] Transfer Manager UI (active/completed/failed tabs)
- [ ] Cancel individual transfer
- [ ] Retry failed transfer
- [ ] Clear completed
- [ ] Clear failed
- [ ] BarWidget badge (active count + failure indicator)
- [ ] Transfer Manager UI (active/completed/failed groups)
- [ ] BarWidget badge (count + failure indicator)
- [ ] Cancel transfer (kill curl, cleanup)
- [ ] Retry failed transfer
- [ ] Clear completed/failed
- [ ] Aggregate progress in BarWidget badge
- [ ] Toast on completion/failure
- [ ] Automatic retry with exponential backoff (2s, 4s, 8s... max 30s)
- [ ] Retry count tracking (max 3)
- [ ] Partial file cleanup on cancel/failure
- [ ] Transfer history retained (max 50)
- [ ] Auth header via temp file (0600 perms)

### File Operations
- [ ] Rename file/folder
- [ ] Move file/folder (single + batch)
- [ ] Copy file/folder (single + batch)
- [ ] Delete file/folder (single + batch sequential)
- [ ] Create folder
- [ ] Rename file/folder
- [ ] Move file/folder
- [ ] Copy file/folder
- [ ] Delete file/folder
- [ ] Create folder
- [ ] Share links (create, list, revoke)
- [ ] Copy file/folder
- [ ] Download revision (historical)
- [ ] File history browser
- [ ] Download specific revision
- [ ] Trash browser
- [ ] Restore folder from trash
- [ ] Deleted file visible in trash (restore disabled)
- [ ] Folder restore from trash
- [ ] Clear completed transfers
- [ ] Clear failed transfers
- [ ] Clear all terminal
- [ ] Logout cancels all transfers + clears history
- [ ] Transfer retry (manual)
- [ ] Transfer cancellation
- [ ] Partial download cleanup
- [ ] Transfer history retention (max 50)

### Search
- [ ] Repo-scoped search (current repo)
- [ ] Global search (all accessible repos)
- [ ] Debounced input (300ms)
- [ ] Min query length: 2 chars
- [ ] Results: name, path, size, type, repo name
- [ ] Click file → navigate to folder
- [ ] Click folder → navigate
- [ ] Empty query handling
- [ ] Error state with retry
- [ ] Loading state
- [ ] Search field in ToolBar
- [ ] Debounce 300ms
- [ ] Min query length 2
- [ ] Results: name, type, path, size, repo
- [ ] Click file → navigate to folder
- [ ] Click folder → navigate
- [ ] Escape clears search
- [ ] Loading state
- [ ] Error state with retry

### Share Links
- [ ] Create share link (file/folder)
- [ ] Password protection (min 6 chars)
- [ ] Expiration date
- [ ] Permissions (edit/download/upload)
- [ ] List existing share links
- [ ] Revoke share link (confirm)
- [ ] Copy to clipboard (wl-copy)
- [ ] Password min 6 chars
- [ ] Expiration days (string)
- [ ] Permissions: can_edit, can_download, can_upload

### Trash
- [ ] List deleted items
- [ ] Restore folder (works)
- [ ] File restore: disabled with explanation
- [ ] Empty state handling
- [ ] Folder restore with confirmation
- [ ] File restore: disabled with explanation
- [ ] Clear completed/failed transfers

### Transfers
- [ ] Transfer Manager UI
- [ ] Cancel individual transfer
- [ ] Retry failed transfer
- [ ] Clear completed
- [ ] Clear failed
- [ ] BarWidget badge
- [ ] Transfer Manager UI
- [ ] Cancel transfer
- [ ] Retry failed
- [ ] Clear completed/failed
- [ ] BarWidget badge

### Cache
- [ ] Library listing cache (30s TTL)
- [ ] Folder listing cache (30s TTL)
- [ ] Max 100 entries
- [ ] LRU eviction
- [ ] Cache invalidation on mutations
- [ ] Force refresh
- [ ] Cache TTL: 30s
- [ ] Max entries: 100

### Offline/Connectivity
- [ ] ConnectionService polling (30s)
- [ ] Online/offline detection
- [ ] Offline banner
- [ ] Force check button
- [ ] Graceful degradation
- [ ] 3 failures → offline
- [ ] 5s timeout per check

### Auth & Session
- [ ] Token stored in secret-tool (gnome-keyring)
- [ ] Server URL stored in keyring
- [ ] Email stored in keyring
- [ ] Token never in argv/env/logs
- [ ] Auth header via temp file (0600)
- [ ] Temp file cleanup on all paths
- [ ] Logout clears all
- [ ] Auto-login on panel open
- [ ] Session validation on startup
- [ ] Token cleared on logout
- [ ] Server URL in keyring
- [ ] Email in keyring
- [ ] No token in argv/env/logs
- [ ] Credential files 0600
- [ ] Temp file cleanup on all paths

### UI/UX
- [ ] BarWidget with icon + badge
- [ ] Panel with KeyboardPanel
- [ ] ToolBar with title, actions, search
- [ ] FileList with FileItem delegates
- [ ] Context menus (right-click)
- [ ] Dialogs: Login, Upload, CreateFolder, Rename, Move, Confirm, Share, Copy
- [ ] Breadcrumbs navigation
- [ ] Loading indicators
- [ ] Error overlays with retry
- [ ] Offline banner
- [ ] Toast notifications (success/error)
- [ ] Toast click to dismiss
- [ ] FileItem with icon, name, size, transfer progress
- [ ] Transfer progress inline in FileItem
- [ ] Transfer speed display
- [ ] File size formatting
- [ ] Context menus (right-click)
- [ ] Dialogs: Login, Upload, CreateFolder, Rename, Move, Confirm, Share, Copy
- [ ] Breadcrumbs navigation
- [ ] Loading indicators
- [ ] Error overlays with retry
- [ ] Offline banner
- [ ] Toast notifications
- [ ] FileItem: icon, name, size, transfer progress/speed
- [ ] Context menus (right-click)
- [ ] Dialogs: Login, Upload, CreateFolder, Rename, Move, Confirm, Share, Copy
- [ ] Breadcrumbs
- [ ] Loading indicators
- [ ] Error overlays with retry
- [ ] Offline banner
- [ ] Toast notifications
- [ ] Keyboard navigation (arrows, Enter, F2, Delete, Escape, Ctrl+A)
- [ ] Keyboard: F2=rename, Del=delete, Enter=activate, Arrows=navigate, Esc=close, Ctrl+A=select all
- [ ] Keyboard: Ctrl+H removed, Ctrl+T removed, Ctrl+A=Select All
- [ ] Context menus with History action
- [ ] Transfer Manager with active/completed/failed groups
- [ ] BarWidget badge (count + failure indicator)
- [ ] ToolBar: search, upload, refresh, back, logout, transfers
- [ ] ToolBar: Trash button with badge
- [ ] BatchActionBar with count + actions
- [ ] FileItem selection highlight
- [ ] Transfer progress inline in FileItem
- [ ] BatchActionBar with Move/Copy/Delete/Clear
- [ ] Transfer Manager with active/completed/failed
- [ ] BarWidget transfer badge (count + failure color)
- [ ] ToolBar Trash button with badge
- [ ] BatchActionBar

### Search
- [ ] Repo-scoped search
- [ ] Global search (parallel across repos)
- [ ] Debounce 300ms
- [ ] Min query length: 2
- [ ] Results: name, path, size, type, repo
- [ ] Click file → navigate to folder
- [ ] Click folder → navigate
- [ ] Clear on escape
- [ ] Loading/error/empty states
- [ ] Debounce 300ms
- [ ] Min query length 2
- [ ] Results: name, type, path, size, repo
- [ ] Click file → navigate to folder
- [ ] Click folder → navigate
- [ ] Escape clears search

### Configuration/Deployment
- [ ] manifest.json valid (schema v1)
- [ ] deploy.sh works (rsync)
- [ ] deploy.sh --check works
- [ ] omarchy plugin validate PASS
- [ ] No symlinks in deployment
- [ ] No secrets in repo
- [ ] No test files in repo
- [ ] manifest.json schema v1
- [ ] Version 0.7.0 in manifest
- [ ] deploy.sh works
- [ ] deploy.sh --check clean
- [ ] omarchy plugin validate PASS
- [ ] No secrets in repo
- [ ] No test artifacts in repo
- [ ] Repo/runtime byte-identical

### Shell Integration
- [ ] `omarchy plugin validate` PASS
- [ ] `deploy.sh` works
- [ ] `deploy.sh --check` clean
- [ ] Plugin loads in Omarchy shell
- [ ] BarWidget appears in bar
- [ ] Panel opens on click
- [ ] Panel closes on escape/outside click
- [ ] Panel positioned correctly
- [ ] Plugin loads without errors

---

## 2. SECURITY (MUST HAVE)

- [ ] TOKEN_IN_ARGV = NO (verified via /proc/<pid>/cmdline)
- [ ] TOKEN_IN_ENVIRON = NO
- [ ] TOKEN_IN_LOGS = NO
- [ ] CREDENTIAL_FILES_LEFT = 0
- [ ] No tokens in curl argv (using -H @file)
- [ ] Temp auth files 0600 permissions
- [ ] Temp auth files cleaned on all paths
- [ ] No token in logs/transfer history/UI
- [ ] secret-tool for credential storage
- [ ] No hardcoded credentials
- [ ] No hardcoded IPs/URLs
- [ ] HTTPS enforcement/warning
- [ ] Logout cleans all transfer state

---

## 3. PUBLIC PLUGIN REQUIREMENTS

- [ ] No hardcoded usernames
- [ ] No hardcoded paths (uses Qt.getenv("HOME"))
- [ ] No hardcoded IPs
- [ ] No hardcoded repo names
- [ ] No hardcoded emails
- [ ] No test data in source
- [ ] Server URL from user input
- [ ] Credentials from keyring only
- [ ] Generic Seafile CE compatible
- [ ] No machine-specific config

---

## 3. DOCUMENTATION

- [ ] README.md (install, usage, features, shortcuts)
- [ ] docs/SEAFILE_API.md (current, accurate)
- [ ] docs/KEYBINDINGS.md (complete, accurate)
- [ ] docs/SEAFILE_API.md (accurate, up-to-date)
- [ ] docs/KEYBINDINGS.md (accurate)
- [ ] docs/ROADMAP_v0.8_to_v1.0.md
- [ ] docs/V1_DEFINITION_OF_DONE.md
- [ ] README.md (install, usage, shortcuts)
- [ ] CHANGELOG (from git log)

---

## 4. TESTING & VALIDATION

- [ ] omarchy plugin validate PASS
- [ ] ./deploy.sh --check clean
- [ ] Repo == Runtime (byte identical)
- [ ] Shell logs clean
- [ ] No secrets in diff
- [ ] git status clean (after commit)
- [ ] Regression tests pass:
  - Login/logout
  - Browse libraries/folders
  - Search
  - Upload/download
  - Share links
  - Rename/move/delete/create
  - Transfers (active/completed/failed)
  - Transfer cancellation
  - Retry logic
  - Logout during transfer
  - Panel close/reopen during transfer
  - Offline/reconnect
  - Keyboard shortcuts
  - Context menus
  - Share links
  - Transfer Manager UI
  - BarWidget badge
  - Keyboard shortcuts
  - Offline/online transitions
  - Share links
  - Cancel/Retry/Delete transfers
  - Panel close/reopen during transfer
  - Logout during transfer

---

## 5. SECURITY

- [ ] TOKEN_IN_ARGV = NO
- [ ] TOKEN_IN_ENVIRON = NO
- [ ] TOKEN_IN_LOGS = NO
- [ ] CREDENTIAL_FILES_LEFT = 0
- [ ] No hardcoded credentials
- [ ] No hardcoded IPs/URLs
- [ ] Token never in curl argv
- [ ] Token not in logs/transfer history
- [ ] Temp auth files 0600 + cleanup
- [ ] HTTPS enforcement/warning
- [ ] Logout cleans all transfer state
- [ ] No credentials in repo

---

## 6. PUBLIC PLUGIN REQUIREMENTS

- [ ] No hardcoded usernames
- [ ] No hardcoded paths (uses Qt.getenv("HOME"))
- [ ] No hardcoded IPs
- [ ] No hardcoded repo names
- [ ] No hardcoded emails
- [ ] Server URL from user input
- [ ] Credentials from keyring only
- [ ] Generic Seafile CE compatible
- [ ] No machine-specific config

---

## 6. DEPLOYMENT

- [ ] `./deploy.sh` works
- [ ] `./deploy.sh --check` clean
- [ ] `omarchy plugin validate` PASS
- [ ] Repo == Runtime (byte identical)
- [ ] `git status` clean (after commit)
- [ ] No secrets in staged changes
- [ ] No test artifacts in repo

---

## 7. RELEASE ENGINEERING

- [ ] Manifest version = 1.0.0
- [ ] CHANGELOG (from git log)
- [ ] Git tag v1.0.0
- [ ] GitHub Release (if applicable)
- [ ] omarchy plugin validate PASS
- [ ] deploy.sh works
- [ ] deploy.sh --check clean
- [ ] No secrets in release artifacts

---

## SIGN-OFF

**v1.0 READY** when ALL checkboxes above are checked.

**Current Status**: NOT READY (v0.7.0)

---

*Generated as part of v0.7.0 post-implementation audit.*
