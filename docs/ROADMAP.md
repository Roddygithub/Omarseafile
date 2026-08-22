# Omarseafile Roadmap

## Current State: v0.8.0 "Public Readiness & Configuration" — IN PROGRESS

---

## v0.8.0 — Public Readiness & Configuration

**Theme**: A new Omarchy + Seafile user can install, configure, diagnose, and use Omarseafile without developer assistance.

**Status**: Implementation complete, validation pending.

### Scope

| Item | Description | Status |
|------|-------------|--------|
| Settings UI | Server URL, account email, Test Connection, Auto-login toggle, Clear Cache, Logout, version | ✅ Done |
| Settings Persistence | Auto-login in `shell.json` via manifest schema | ✅ Done |
| Dependency Detection | Startup check for `curl`, `secret-tool`, `wl-copy` with actionable errors | ✅ Done |
| URL Validation | Syntax validation, normalization, HTTPS warning | ✅ Done |
| Connection Test | `/api2/ping/` check with categorized errors | ✅ Done |
| TLS Policy | System trust store only; self-signed = clear error (no bypass) | ✅ Done |
| README.md | Complete public documentation | ✅ Done |
| CHANGELOG.md | Keep-a-Changelog format, v0.1–v0.8 | ✅ Done |
| Validation Script | `scripts/validate.sh` (CI-capable + local-runtime) | ✅ Done |
| GitHub Actions CI | Static validation workflow | ✅ Done |
| Install Docs | `omarchy plugin add` documented | ✅ Done |

### Acceptance Criteria

- [x] Settings UI accessible from toolbar
- [x] Server URL change requires re-authentication
- [x] Test Connection works against real server
- [x] Missing `curl`/`secret-tool` blocks with install hint
- [x] Missing `wl-copy` degrades gracefully (share works, copy shows tooltip)
- [x] Invalid URL rejected before auth attempt
- [x] HTTPS warning shown for HTTP URLs
- [x] Auto-login toggle persists in shell.json
- [x] `scripts/validate.sh` passes locally
- [x] GitHub Actions workflow passes
- [x] `omarchy plugin validate` passes
- [x] `deploy.sh --check` clean
- [x] Repo/runtime byte-identical

---

## v0.9.0 — Core Polish & Usability

**Theme**: Smooth daily-driver experience.

**Estimated**: 3-4 weeks after v0.8.0.

### Planned Scope

| Item | Description | Justification |
|------|-------------|---------------|
| Post-download Open | Right-click completed transfer → Open via `Qt.openUrlExternally()` | High UX value |
| Custom CA Cert Support | User-provided PEM for curl + XHR (if Quickshell supports) | Enterprise/self-hosted |
| Empty State Illustrations | Visual placeholders for history, trash, search | Polish |
| Column Sorting/Resizing | Name, size, date, type; resizable columns | Power user |
| Account/Quota Info | Display user quota, usage in Settings | User visibility |
| Keyboard Hints Overlay | `?` key shows shortcuts | Discoverability |

### Deferred from v0.8
- File Locking (API available, not public readiness)
- Comments (API available, not public readiness)
- Starred Items (API available, not public readiness)
- Upload Links (API available, not public readiness)

---

## v1.0.0 — Public Release Ready

**Theme**: Production-quality public plugin for Omarchy.

**Goal**: A safe, documented, installable, useful public Seafile client plugin for Omarchy.

**NOT**: "Support every Seafile feature."

### MUST_HAVE_FOR_v1

**Functionality**
- [ ] Browse, download, upload, search, share, history, trash, batch ops
- [ ] Keyboard nav (F2, Del, Enter, Arrows, Esc, Ctrl+A)
- [ ] Transfer Manager, BarWidget badge, Offline detection

**Configuration**
- [ ] Settings UI (server URL, Test Connection, account, auto-login, Clear Cache, Logout)
- [ ] Dependency detection, URL validation, TLS policy

**Security**
- [ ] Token never in argv/env/logs
- [ ] Auth header via temp file (0600, cleanup all paths)
- [ ] Credentials in keyring only
- [ ] No hardcoded secrets/URLs/paths

**Portability**
- [ ] HTTPS/HTTP, domains/IPs, custom ports, reverse proxies
- [ ] Wayland-native, Unicode filenames, no hardcoded paths

**UX**
- [ ] First-run guidance, empty states, error overlays, toasts, keyboard hints

**Installation**
- [ ] `omarchy plugin add` documented, `omarchy plugin validate` PASS

**Testing**
- [ ] `scripts/validate.sh` PASS, CI static checks PASS, regression checklist

**Documentation**
- [ ] README.md, LICENSE (MIT), CHANGELOG.md, KEYBINDINGS.md, SEAFILE_API.md

**Release**
- [ ] Git tag v1.0.0, GitHub Release, omarchyplugins.com submission

### SHOULD_HAVE_FOR_v1
- Encrypted library support (create/unlock) — **only if SPIKE proves viable**
- Account/quota information display
- Native file picker (if Quickshell supports)
- Column sorting/visibility

### POST_v1 (Explicitly Deferred)
- File locking/unlocking
- File comments
- Starred items
- Upload links (shared upload)
- Directory download (ZIP)
- Library management (create/rename/delete)
- Activities feed
- Chunked/resumable upload (when CE supports)
- WebDAV integration
- Cross-repo folder copy

---

## Known Seafile CE 12.0.14 Limitations

| Feature | Status | Notes |
|---------|--------|-------|
| Chunked/Resumable Upload | NOT_SUPPORTED | No API on CE 12.0.14 |
| File Restore from Trash | NOT_SUPPORTED | Folders only |
| Revision Revert | NOT_SUPPORTED | 405 on CE 12.0.14 |
| Global Search | NOT_SUPPORTED | Repo-scoped only |
| Batch Delete API | NOT_WORKING | Sequential fallback used |

---

## Decision Log

| Date | Decision | Rationale |
|------|----------|-----------|
| 2026-08-22 | v0.8 = Public Readiness (not Feature Completion) | Chunked upload infeasible on CE; public release blockers are non-feature |
| 2026-08-22 | No insecure TLS bypass in v0.8 | Security policy; system trust store only |
| 2026-08-22 | Encrypted libs = SHOULD_HAVE (not MUST) | Only if safely portable; else documented limitation |
| 2026-08-22 | deploy.sh = DEVELOPMENT only | Official install = `omarchy plugin add` |

---

*Last updated: 2026-08-22*
*Canonical roadmap source of truth*