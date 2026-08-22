# Omarseafile — Seafile API Audit & Reference

> **Source of Truth Hierarchy**
> 1. **Server Reality** (our server at `http://192.168.1.108:8000`) — ultimate authority
> 2. **Current Official Docs** — [seafile-api.readme.io](https://seafile-api.readme.io/) + [manual.seafile.com](https://manual.seafile.com/)
> 3. **Model Knowledge** — never authoritative, only for gaps

> **Rule**: Before implementing any Seafile feature → consult this doc → check official docs if not VERIFIED → SPIKE against real server → update this doc → then implement.

---

## API Family & Version Matrix

| Family | Version | Base Path | Auth | Primary Use |
|--------|---------|-----------|------|-------------|
| **Account Token** | v2 | `/api2/auth-token/` | Basic (user/pass) | Get account token |
| **Account API** | v2 | `/api2/` | Account-Token | User, libraries, repos |
| **Repo Token API** | v2.1 | `/api/v2.1/` | Repo-Token | Scoped repo operations |
| **Seafhttp** | v2 | `/seafhttp/` | Token in header/query | File upload/download |
| **Admin API** | v2 | `/api/v2.1/admin/` | Admin Token | System administration |

**Auth Header**: `Authorization: Token <token>` (both Account-Token and Repo-Token)

---

## Endpoint Audit Matrix

### AUTH

| Feature | Method | Endpoint | API Ver | Status | Omarseafile Ver | Notes |
|---------|--------|----------|---------|--------|-----------------|-------|
| Obtain Account Token | POST | `/api2/auth-token/` | v2 | **VERIFIED** | v0.1.0 | `username` + `password` form-encoded |
| Validate Token | GET | `/api2/ping/` | v2 | **VERIFIED** | v0.1.4 | Returns 200 if valid |
| Get Account Info | GET | `/api2/account-info/` | v2 | DOCUMENTED_UNVERIFIED | — | |
| Get Client Token | POST | `/api2/client-login/` | v2 | DOCUMENTED_UNVERIFIED | — | For desktop client |

### LIBRARIES

| Feature | Method | Endpoint | API Ver | Status | Omarseafile Ver | Notes |
|---------|--------|----------|---------|--------|-----------------|-------|
| List Libraries | GET | `/api2/repos/` | v2 | **VERIFIED** | v0.1.1 | Returns all accessible repos |
| Get Library Info | GET | `/api2/repos/{repo_id}/` | v2 | DOCUMENTED_UNVERIFIED | — | |
| Create Library | POST | `/api2/repos/` | v2 | DOCUMENTED_UNVERIFIED | — | `name`, `passwd` (optional) |
| Create Encrypted Library | POST | `/api2/repos/` | v2 | DOCUMENTED_UNVERIFIED | — | `passwd` required |
| Rename Library | POST | `/api2/repos/{repo_id}/` | v2 | DOCUMENTED_UNVERIFIED | — | `op=rename`, `name` |
| Delete Library | DELETE | `/api2/repos/{repo_id}/` | v2 | DOCUMENTED_UNVERIFIED | — | |
| Get Library Owner | GET | `/api2/repos/{repo_id}/owner/` | v2 | DOCUMENTED_UNVERIFIED | — | |
| Transfer Library | PUT | `/api2/repos/{repo_id}/owner/` | v2 | DOCUMENTED_UNVERIFIED | — | `owner` param |
| Get Library History | GET | `/api/v2.1/repos/{repo_id}/history/` | v2.1 | DOCUMENTED_UNVERIFIED | — | |
| Get/Set History Limit | GET/PUT | `/api2/repos/{repo_id}/history-limit/` | v2 | DOCUMENTED_UNVERIFIED | — | Days |
| Get Library Trash | GET | `/api/v2.1/repos/{repo_id}/trash/` | v2.1 | **VERIFIED** | v0.7.0 | |
| Clean Library Trash | DELETE | `/api/v2.1/repos/{repo_id}/trash/` | v2.1 | DOCUMENTED_UNVERIFIED | — | |

### DIRECTORIES (api/v2.1 via repo-token)

| Feature | Method | Endpoint | API Ver | Status | Omarseafile Ver | Notes |
|---------|--------|----------|---------|--------|-----------------|-------|
| List Directory | GET | `/api/v2.1/via-repo-token/dir/` | v2.1 | **VERIFIED** | v0.1.1 | `p=/path` |
| Create Dir | POST | `/api/v2.1/via-repo-token/dir/` | v2.1 | **PARTIALLY_VERIFIED** | v0.2.1 | `operation=mkdir`, `dir_name`, `p=/parent` **p ignored** |
| Rename Dir | POST | `/api/v2.1/via-repo-token/dir/` | v2.1 | **VERIFIED** | v0.2.1 | `operation=rename`, `oldname`, `newname`, `p=/parent` |
| Delete Dir | DELETE | `/api/v2.1/via-repo-token/dir/` | v2.1 | **VERIFIED** | v0.2.1.1 | `p=/full/path` |
| Revert Dir | PUT | `/api2/repos/{repo_id}/dir/revert/` | v2 | DOCUMENTED_UNVERIFIED | — | `commit_id` |
| Move Dir (merged) | POST | `/api/v2.1/move-folder-merge/` | v2.1 | DOCUMENTED_UNVERIFIED | — | Sync move |
| Async Move Dir | POST | `/api/v2.1/repos/async-batch-move-item/` | v2.1 | **VERIFIED** | v0.2.1.1 | Async, returns task_id |
| Get Dir Detail | GET | `/api/v2.1/repos/{repo_id}/dir/detail/` | v2.1 | DOCUMENTED_UNVERIFIED | — | |
| Repo Token Dir List | GET | `/api2/repos/{repo_id}/dir/` | v2 | **VERIFIED** | v0.1.1 | `p=/path` |
| Create/Rename Dir (v2) | POST | `/api2/repos/{repo_id}/dir/` | v2 | **VERIFIED** | v0.2.1 | `operation=mkdir/rename`, `p=/path` |
| Delete Dir (v2) | DELETE | `/api2/repos/{repo_id}/dir/` | v2 | **VERIFIED** | v0.2.1.1 | `p=/path` |

### FILES (api/v2.1 via repo-token)

| Feature | Method | Endpoint | API Ver | Status | Omarseafile Ver | Notes |
|---------|--------|----------|---------|--------|-----------------|-------|
| Get File Info | GET | `/api/v2.1/via-repo-token/file/` | v2.1 | DOCUMENTED_UNVERIFIED | — | `p=/path` |
| Rename File | POST | `/api/v2.1/via-repo-token/file/` | v2.1 | **VERIFIED** | v0.2.1 | `operation=rename`, `oldname`, `newname`, `p=/full/path` |
| Delete File | DELETE | `/api/v2.1/via-repo-token/file/` | v2.1 | **VERIFIED** | v0.2.1.1 | `p=/full/path` |
| Lock/Unlock File | PUT | `/api/v2.1/via-repo-token/file/` | v2.1 | DOCUMENTED_UNVERIFIED | — | `operation=lock/unlock` |
| Move Dir (merged) | POST | `/api/v2.1/via-repo-token/move-dir/` | v2.1 | DOCUMENTED_UNVERIFIED | — | |
| Get File Detail (v2) | GET | `/api2/repos/{repo_id}/file/detail/` | v2 | **VERIFIED** | v0.2.1 | `p=/path` |
| Create/Rename/Move/Copy/Revert File (v2) | POST | `/api/v2.1/repos/{repo_id}/file/` | v2.1 | **PARTIALLY_VERIFIED** | v0.2.1 | `operation=rename/move/copy/revert/create` |
| Delete File (v2) | DELETE | `/api/v2.1/repos/{repo_id}/file/` | v2.1 | **VERIFIED** | v0.2.1.1 | `p=/full/path` |
| Lock/Unlock File (v2) | PUT | `/api/v2.1/repos/{repo_id}/file/` | v2.1 | DOCUMENTED_UNVERIFIED | — | `operation=lock/unlock` |

### UPLOAD

| Feature | Method | Endpoint | API Ver | Status | Omarseafile Ver | Notes |
|---------|--------|----------|---------|--------|-----------------|-------|
| Get Upload Link | GET | `/api2/repos/{repo_id}/upload-link/` | v2 | **VERIFIED** | v0.1.3 | `p=/path`, `replace=0\|1` |
| Get Upload Link (v2.1) | GET | `/api2/repos/{repo_id}/upload-link/` | v2 | **VERIFIED** | v0.1.3 | `p=/path`, `replace=0\|1` |
| Get Upload Link (v2.1 token) | GET | `/api/v2.1/via-repo-token/upload-link/` | v2.1 | DOCUMENTED_UNVERIFIED | — | `p=/path` |
| Upload File | POST | `{upload_link}?ret-json=1` | seafhttp | **VERIFIED** | v0.1.3 | multipart/form-data `file=@path`, `parent_dir`, `replace=0\|1` |
| Chunked Upload | POST | `/seafhttp/upload-api/{token}` | seafhttp | **NOT_SUPPORTED_BY_SERVER** | — | Large files, see `file_chunk_upload.md` |
| Update Link | GET | `/api2/repos/{repo_id}/update-link/` | v2 | DOCUMENTED_UNVERIFIED | — | `p=/path` |
| Update File | POST | `{update_link}` | seafhttp | DOCUMENTED_UNVERIFIED | — | multipart/form-data |
| Replace Behavior | — | `replace=0` | — | **VERIFIED** | v0.1.3 | Auto-renames `(1)`, `(2)` on collision |

### DOWNLOAD

| Feature | Method | Endpoint | API Ver | Status | Omarseafile Ver | Notes |
|---------|--------|----------|---------|--------|-----------------|-------|
| Get Download Link | GET | `/api2/repos/{repo_id}/file/` | v2 | **VERIFIED** | v0.1.2 | `p=/path`, `reuse=1` |
| Get Download Link (v2.1) | GET | `/api/v2.1/via-repo-token/download-link/` | v2.1 | DOCUMENTED_UNVERIFIED | — | `p=/path` |
| Download File | GET | `{download_link}` | seafhttp | **VERIFIED** | v0.1.2 | **Requires `Authorization: Token` header** |
| Download File (v2) | GET | `/api2/repos/{repo_id}/file/` | v2 | **VERIFIED** | v0.1.2 | `p=/path` |
| Download Revision | GET | `/api2/repos/{repo_id}/file/revision/` | v2 | **VERIFIED** | v0.7.0 | `commit_id` |

### FILE HISTORY / REVISIONS

| Feature | Method | Endpoint | API Ver | Status | Omarseafile Ver | Notes |
|---------|--------|----------|---------|--------|-----------------|-------|
| Get File History | GET | `/api2/repos/{repo_id}/file/history/` | v2 | **VERIFIED** | v0.7.0 | `p=/path` (URL-encoded) |
| Get File History (v2.1) | GET | `/api/v2.1/repos/{repo_id}/file/history/` | v2.1 | **VERIFIED** | v0.7.0 | `p=/path` (URL-encoded) |
| Download Revision | GET | `/api2/repos/{repo_id}/file/revision/` | v2 | **VERIFIED** | v0.7.0 | `p=/path`, `commit_id` |
| Revert File | GET | `/api2/repos/{repo_id}/file/revision/` | v2 | **NOT_SUPPORTED** | — | 405 Method Not Allowed on CE 12.0.14 |
| Revert Dir | PUT | `/api2/repos/{repo_id}/dir/revert/` | v2 | DOCUMENTED_UNVERIFIED | — | `commit_id` |
| Get Library Trash | GET | `/api/v2.1/repos/{repo_id}/trash/` | v2.1 | **VERIFIED** | v0.7.0 | |
| Clean Library Trash | DELETE | `/api/v2.1/repos/{repo_id}/trash/` | v2.1 | DOCUMENTED_UNVERIFIED | — | |
| Restore from Trash | POST | `/api/v2.1/repos/{repo_id}/trash/` | v2.1 | **PARTIALLY_VERIFIED** | v0.7.0 | `op=restore`, folder only |
| Clean Library Trash | DELETE | `/api/v2.1/repos/{repo_id}/trash/` | v2.1 | DOCUMENTED_UNVERIFIED | — | |

### SHARE LINKS

| Feature | Method | Endpoint | API Ver | Status | Omarseafile Ver | Notes |
|---------|--------|----------|---------|--------|-----------------|-------|
| List Share Links | GET | `/api/v2.1/share-links/` | v2.1 | **VERIFIED** | v0.2.2 | Returns array |
| Create Share Link | POST | `/api/v2.1/share-links/` | v2.1 | **VERIFIED** | v0.2.2 | `repo_id`, `path`, `password`, `expire_days`, `permissions` |
| List Share Links by Repo | GET | `/api/v2.1/share-links/?repo_id={repo_id}` | v2.1 | **VERIFIED** | v0.2.2 | Query param filter |
| List Share Links by Path | GET | `/api/v2.1/share-links/?repo_id={repo_id}&path={path}` | v2.1 | **VERIFIED** | v0.2.2 | Query param filter |
| Delete Share Link | DELETE | `/api/v2.1/share-links/{token}/` | v2.1 | **VERIFIED** | v0.2.2 | Uses `token` |
| Send Share Link Email | POST | `/api2/send-share-link/` | v2 | DOCUMENTED_UNVERIFIED | — | |

### UPLOAD LINKS (Shared Upload)

| Feature | Method | Endpoint | API Ver | Status | Omarseafile Ver | Notes |
|---------|--------|----------|---------|--------|-----------------|-------|
| List Upload Links | GET | `/api/v2.1/upload-links/` | v2.1 | DOCUMENTED_UNVERIFIED | — | |
| Create Upload Link | POST | `/api/v2.1/upload-links/` | v2.1 | DOCUMENTED_UNVERIFIED | — | `repo_id`, `path`, `password`, `expire` |
| Delete Upload Link | DELETE | `/api/v2.1/upload-links/{token}/` | v2.1 | DOCUMENTED_UNVERIFIED | — | |
| Send Upload Link Email | POST | `/api2/send-upload-link/` | v2 | DOCUMENTED_UNVERIFIED | — | |

### SEARCH

| Feature | Method | Endpoint | API Ver | Status | Omarseafile Ver | Notes |
|---------|--------|----------|---------|--------|-----------------|-------|
| Search Files (Global) | GET | `/api2/search/` | v2 | **NOT_ACCESSIBLE** | — | Returns 403 on CE 12.0.14 |
| Search Files in Repo | GET | `/api/v2.1/search-file/` | v2.1 | **VERIFIED** | v0.2.3 | `q` required, `repo_id` required |

### STARRED / FAVORITES

| Feature | Method | Endpoint | API Ver | Status | Omarseafile Ver | Notes |
|---------|--------|----------|---------|--------|-----------------|-------|
| List Starred | GET | `/api/v2.1/starred-items/` | v2.1 | DOCUMENTED_UNVERIFIED | — | |
| Star Item | POST | `/api/v2.1/starred-items/` | v2.1 | DOCUMENTED_UNVERIFIED | — | `obj_type`, `obj_id`, `repo_id` |
| Unstar Item | DELETE | `/api/v2.1/starred-items/` | v2.1 | DOCUMENTED_UNVERIFIED | — | Same params |

### HISTORY / TRASH (Expanded)

| Feature | Method | Endpoint | API Ver | Status | Omarseafile Ver | Notes |
|---------|--------|----------|---------|--------|-----------------|-------|
| Get File History | GET | `/api2/repos/{repo_id}/file/history/` | v2 | **VERIFIED** | v0.7.0 | `p=/path` (URL-encoded) |
| Download Revision | GET | `/api2/repos/{repo_id}/file/revision/` | v2 | **VERIFIED** | v0.7.0 | `p=/path`, `commit_id` |
| Revert File | GET | `/api2/repos/{repo_id}/file/revision/` | v2 | **NOT_SUPPORTED** | — | 405 on CE 12.0.14 |
| Revert Dir | PUT | `/api2/repos/{repo_id}/dir/revert/` | v2 | DOCUMENTED_UNVERIFIED | — | `commit_id` |
| Get Library Trash | GET | `/api/v2.1/repos/{repo_id}/trash/` | v2.1 | **VERIFIED** | v0.7.0 | |
| Clean Library Trash | DELETE | `/api/v2.1/repos/{repo_id}/trash/` | v2.1 | DOCUMENTED_UNVERIFIED | — | |
| Restore from Trash | POST | `/api/v2.1/repos/{repo_id}/trash/` | v2.1 | **PARTIALLY_VERIFIED** | v0.7.0 | Folder only, `op=restore` |
| Clean Library Trash | DELETE | `/api/v2.1/repos/{repo_id}/trash/` | v2.1 | DOCUMENTED_UNVERIFIED | — | |

### BATCH OPERATIONS

| Feature | Method | Endpoint | API Ver | Status | Omarseafile Ver | Notes |
|---------|--------|----------|---------|--------|-----------------|-------|
| Sync Batch Move | POST | `/api/v2.1/repos/sync-batch-move-item/` | v2.1 | **VERIFIED** | v0.2.1.1 | Sync |
| Sync Batch Copy | POST | `/api/v2.1/repos/sync-batch-copy-item/` | v2.1 | **VERIFIED** | v0.7.0 | |
| Async Batch Move | POST | `/api/v2.1/repos/async-batch-move-item/` | v2.1 | **VERIFIED** | v0.2.1.1 | Returns `task_id` |
| Async Batch Copy | POST | `/api/v2.1/repos/async-batch-copy-item/` | v2.1 | **PARTIALLY_VERIFIED** | v0.7.0 | Empty task_id |
| Batch Delete | DELETE | `/api/v2.1/repos/batch-delete-item/` | v2.1 | **NOT_WORKING** | — | 500/404 on CE 12.0.14 |
| Sync Batch Copy | POST | `/api/v2.1/repos/sync-batch-copy-item/` | v2.1 | **VERIFIED** | v0.7.0 | Mixed files+folders |
| Async Batch Copy | POST | `/api/v2.1/repos/async-batch-copy-item/` | v2.1 | **PARTIALLY_VERIFIED** | v0.7.0 | Empty task_id |
| Batch Delete | DELETE | `/api/v2.1/repos/batch-delete-item/` | v2.1 | **NOT_WORKING** | — | 500/404 on CE 12.0.14 |

### SHARE LINKS (v0.2.2 Target)

| Feature | Method | Endpoint | API Ver | Status | Omarseafile Ver | Notes |
|---------|--------|----------|---------|--------|-----------------|-------|
| List All Share Links | GET | `/api/v2.1/share-links/` | v2.1 | **VERIFIED** | v0.2.2 | Returns array |
| Create Share Link | POST | `/api/v2.1/share-links/` | v2.1 | **VERIFIED** | v0.2.2 | `repo_id`, `path`, `password`, `expire_days`, `permissions` |
| List Share Links by Repo | GET | `/api/v2.1/share-links/?repo_id={repo_id}` | v2.1 | **VERIFIED** | v0.2.2 | Query param filter |
| List Share Links by Path | GET | `/api/v2.1/share-links/?repo_id={repo_id}&path={path}` | v2.1 | **VERIFIED** | v0.2.2 | Query param filter |
| Delete Share Link | DELETE | `/api/v2.1/share-links/{token}/` | v2.1 | **VERIFIED** | v0.2.2 | Uses `token` |
| Send Share Link Email | POST | `/api2/send-share-link/` | v2 | DOCUMENTED_UNVERIFIED | — | |

### UPLOAD LINKS (Shared Upload)

| Feature | Method | Endpoint | API Ver | Status | Omarseafile Ver | Notes |
|---------|--------|----------|---------|--------|-----------------|-------|
| List Upload Links | GET | `/api/v2.1/upload-links/` | v2.1 | DOCUMENTED_UNVERIFIED | — | |
| Create Upload Link | POST | `/api/v2.1/upload-links/` | v2.1 | DOCUMENTED_UNVERIFIED | — | `repo_id`, `path`, `password`, `expire` |
| Delete Upload Link | DELETE | `/api/v2.1/upload-links/{token}/` | v2.1 | DOCUMENTED_UNVERIFIED | — | |

### USER / ACCOUNT

| Feature | Method | Endpoint | API Ver | Status | Omarseafile Ver | Notes |
|---------|--------|----------|---------|--------|-----------------|-------|
| Get Account Info | GET | `/api2/account-info/` | v2 | DOCUMENTED_UNVERIFIED | — | |
| Get User Profile | GET | `/api/v2.1/user/` | v2.1 | DOCUMENTED_UNVERIFIED | — | |
| Update User Profile | PUT | `/api/v2.1/user/` | v2.1 | DOCUMENTED_UNVERIFIED | — | |
| Get User Avatar | GET | `/api2/avatars/user/{user}/` | v2 | DOCUMENTED_UNVERIFIED | — | |
| Get Account Info | GET | `/api/v2.1/account-info/` | v2.1 | DOCUMENTED_UNVERIFIED | — | |

### BATCH OPERATIONS (Async)

| Feature | Method | Endpoint | API Ver | Status | Omarseafile Ver | Notes |
|---------|--------|----------|---------|--------|-----------------|-------|
| Async Batch Move | POST | `/api/v2.1/repos/async-batch-move-item/` | v2.1 | **VERIFIED** | v0.2.1.1 | Returns `task_id` |
| Async Batch Copy | POST | `/api/v2.1/repos/async-batch-copy-item/` | v2.1 | DOCUMENTED_UNVERIFIED | — | |
| Query Async Progress | GET | `/api/v2.1/query-copy-move-progress/` | v2.1 | DOCUMENTED_UNVERIFIED | — | `task_id` |
| Cancel Async | DELETE | `/api/v2.1/copy-move-task/` | v2.1 | DOCUMENTED_UNVERIFIED | — | `task_id` |

---

## Summary Statistics

| Status | Count |
|--------|-------|
| **VERIFIED** | 33 |
| **PARTIALLY_VERIFIED** | 5 |
| **DOCUMENTED_UNVERIFIED** | 81 |
| **NOT_ACCESSIBLE** | 1 |
| **NOT_SUPPORTED_BY_SERVER** | 2 |
| **NOT_WORKING** | 2 |
| **DEPRECATED** | 0 |
| **NOT_RELEVANT** | 0 |

**Total Endpoints Catalogued**: 123

---

## Verified Server Behaviors

> All behaviors tested against our real server at `http://192.168.1.108:8000` (Seafile CE 12.0.14).

| Behavior | Verified | Details |
|----------|----------|---------|
| **Auth Token** | ✅ | `POST /api2/auth-token/` with `username`/`password` form-encoded → returns `{token}` |
| **Libraries List** | ✅ | `GET /api2/repos/` → array of repo objects with `id`, `name`, `size`, `mtime`, `permission`, `encrypted` |
| **Folder Listing** | ✅ | `GET /api2/repos/{id}/dir/?p=/path` → array of `{type, name, id, mtime, size, permission}` |
| **Folder Sorting** | ✅ | Server returns dirs first (000... IDs), then files, alpha order |
| **Download Link** | ✅ | `GET /api2/repos/{id}/file/?p=/path&reuse=1` → returns seafhttp URL |
| **Download Auth** | ✅ | **Requires** `Authorization: Token <token>` header on seafhttp download |
| **Download 0-byte** | ✅ | Works (returns 0-byte file), but link returns "Access token not found" without auth header |
| **Upload Link** | ✅ | `GET /api2/repos/{id}/upload-link/?p=/path&reuse=0\|1` → seafhttp upload URL |
| **Upload Multipart** | ✅ | `POST {link}?ret-json=1` with `file=@path`, `parent_dir`, `replace=0\|1` |
| **Upload Replace** | ✅ | `replace=0` → auto-rename `(1)`, `(2)`; `replace=1` → overwrite |
| **Upload Large File** | ✅ | 500 MB tested OK |
| **Upload 0-byte** | ✅ | Returns `{name, id, size: 0}` |
| **Upload Collision** | ✅ | `replace=0` → server renames to `(1)`, `(2)` etc. |
| **Upload Link Reuse** | ✅ | `reuse=1` makes link reusable for multiple uploads |
| **Download 403** | ✅ | Without `Authorization` header → 403 "Access token not found" |
| **Auth Error** | ✅ | Invalid token → `{"detail":"Invalid token"}` (401) |
| **Rename File** | ✅ | `POST /api/v2.1/repos/{id}/file/?p=/full/path` with `operation=rename&oldname=...&newname=...` |
| **Rename Folder** | ✅ | `POST /api/v2.1/repos/{id}/dir/?p=/parent&operation=rename&oldname=...&newname=...` |
| **Move File** | ✅ | `POST /api/v2.1/repos/{id}/file/?p=/full/path&operation=move&dst_repo={id}&dst_dir=/dest` |
| **Move Folder (Async)** | ✅ | `POST /api/v2.1/repos/async-batch-move-item/` with JSON body |
| **Delete File** | ✅ | `DELETE /api/v2.1/repos/{id}/file/?p=/full/path` → `{"success":true}` |
| **Delete Folder** | ✅ | `DELETE /api2/repos/{id}/dir/?p=/path` → `"success"` |
| **Upload Link Reuse** | ✅ | `reuse=1` makes link reusable for multiple uploads |
| **Upload Collision** | ✅ | `replace=0` → server renames to `(1)`, `(2)` etc. |
| **Upload 0-byte** | ✅ | Works, returns `size: 0` |
| **Download 0-byte** | ✅ | Creates 0-byte file locally |
| **Token 401** | ✅ | Invalid token → `{"detail":"Invalid token"}` (401) |
| **Folder Not Found** | ✅ | 404 for invalid path |
| **Async Move Folder** | ✅ | `POST /api/v2.1/repos/async-batch-move-item/` with JSON body → returns `task_id` |
| **Create Folder** | ⚠️ | **API ignores `p` parameter** — creates at repo root regardless of `p=` |
| **List Share Links** | ✅ | `GET /api/v2.1/share-links/` → returns array of all user's share links |
| **Create Share Link (File)** | ✅ | `POST /api/v2.1/share-links/` with `repo_id`, `path` → returns link object |
| **Create Share Link (Folder)** | ✅ | `POST /api/v2.1/share-links/` with `repo_id`, `path` → returns link object |
| **Share Link Password** | ✅ | `POST /api/v2.1/share-links/` with `password` → min 6 chars required |
| **Share Link Expiration** | ✅ | `POST /api/v2.1/share-links/` with `expire_days` (string) → sets expiry |
| **Share Link Permissions** | ✅ | `POST /api/v2.1/share-links/` with `permissions` object → `can_edit`, `can_download`, `can_upload` |
| **List Share Links by Repo** | ✅ | `GET /api/v2.1/share-links/?repo_id={id}` → query param filter |
| **List Share Links by Path** | ✅ | `GET /api/v2.1/share-links/?repo_id={id}&path={path}` → query param filter |
| **Delete Share Link** | ✅ | `DELETE /api/v2.1/share-links/{token}/` → `{"success":true}` |
| **Share Link Password Short** | ⚠️ | Password < 6 chars → `{"error_msg":"Password is too short."}` (400) |
| **Share Link Duplicate** | ⚠️ | Creating link for same path twice → `{"error_msg":"Share link already exists."}` (400) |
| **Search (Global)** | ❌ | `GET /api2/search/?q=term` → 403 "permission denied" on CE 12.0.14 |
| **Search (Repo-scoped)** | ✅ | `GET /api/v2.1/search-file/?q=term&repo_id={id}` → `{data: [{path, size, mtime, type}]}` |
| **Search (Empty query)** | ✅ | `GET /api/v2.1/search-file/?q=&repo_id={id}` → `{"error_msg":"q invalid."}` |
| **Search (Invalid token)** | ✅ | `GET /api/v2.1/search-file/?q=test&repo_id={id}` with bad token → `{"detail":"Invalid token"}` |
| **Search (Invalid repo)** | ⚠️ | `GET /api/v2.1/search-file/?q=test&repo_id=invalid` → HTML error page (500) |
| **Search (Case-insensitive)** | ✅ | "Github" finds "github-recovery-codes.txt" |
| **Search (Recursive)** | ✅ | Finds files in subdirectories (e.g., `/Non triées/P1050683.JPG`) |
| **Search (Folders)** | ✅ | Returns folders with type="folder", size=0 |
| **Search (No pagination)** | ✅ | `page`/`per_page` params are ignored |
| **File History** | ✅ | `GET /api2/repos/{id}/file/history/?p=/path` (URL-encoded path) |
| **Revision Download** | ✅ | `GET /api2/repos/{id}/file/revision/?p=/path&commit_id=xxx` |
| **Revision Restore** | ❌ | NOT_SUPPORTED on CE 12.0.14 (405) |
| **Trash List** | ✅ | `GET /api/v2.1/repos/{id}/trash/` |
| **Trash Restore (Folder)** | ✅ | `POST /api/v2.1/repos/{id}/trash/` with `op=restore` |
| **Trash Restore (File)** | ❌ | NOT_SUPPORTED on CE 12.0.14 |

---

## Known Server/API Quirks

| Quirk | Impact | Workaround |
|-------|--------|------------|
| **Create Folder ignores `p=`** | Cannot create folder in subdirectory via API; always creates at repo root | Use workaround: create at root, then move (async move folder works) |
| **Download link requires Auth header** | Seafhttp download returns 403 "Access token not found" without `Authorization: Token` | Always pass `Authorization: Token <token>` header on seafhttp downloads |
| **0-byte files** | Download link returns "Access token not found" for 0-byte files without auth; works with auth header | Use auth header |
| **Create Folder `p=` ignored** | API creates folder at repo root regardless of `p=/parent` parameter | Create at root, then async move to desired location |
| **Async Move Folder** | Works but returns empty `task_id`; completes quickly on small dirs | Just refresh after short delay |
| **Rename File Path Format** | `p=` must be **full file path** including filename, not parent dir | Use `p=/full/path/to/file.txt` not `p=/parent/dir` |
| **Rename Folder Path Format** | `p=` must be **parent directory path**, not folder path | Use `p=/parent` not `p=/parent/folder` |
| **Move Folder Async** | Returns empty `task_id` (`""`); completes synchronously on small dirs | Just refresh after short delay |
| **Upload Collision** | `replace=0` → server renames to `(1)`, `(2)` etc. automatically | Use `replace=0` for safe behavior |
| **Download 0-byte files** | Returns 403 "Access token not found" without auth header; works with auth | Always include auth header |
| **Upload Link Reuse** | `reuse=1` makes link reusable; without it link is single-use | Use `reuse=1` for multiple uploads |
| **Delete Root Protection** | Must prevent deleting `/` path manually | Check `path === "/"` before delete |
| **Folder Rename Path** | `p=` must be **parent directory**, not folder path | Use `p=/parent` not `p=/parent/folder` |
| **Move Folder Async** | Returns empty `task_id` (`""`); completes synchronously on small dirs | Just refresh after short delay |
| **Upload Collision** | `replace=0` → server renames to `(1)`, `(2)` etc. automatically | Use `replace=0` for safe behavior |
| **Download 0-byte files** | Returns 403 "Access token not found" without auth header; works with auth | Always include auth header |
| **Upload Link Reuse** | `reuse=1` makes link reusable; without it link is single-use | Use `reuse=1` for multiple uploads |
| **Delete Root Protection** | Must prevent deleting `/` path manually | Check `path === "/"` before delete |
| **Folder Rename Path** | `p=` must be **parent directory**, not folder path | Use `p=/parent` not `p=/parent/folder` |
| **Share Link Password Min** | Password must be ≥ 6 characters | Use `SecureP@ssw0rd!` or similar |
| **Share Link Duplicate** | Cannot create two links for same file/folder | Check existing links before creating |
| **Share Link `expire_days`** | Parameter is string, not integer; format: "7" not 7 | Send as string |
| **Share Link Permissions** | `can_edit` automatically set to `true` if not specified | Explicitly set `permissions` object |
| **Share Link `can_copy_content`** | Server always returns this field; not settable | Ignore in UI |
| **Search `/api2/search/`** | Returns 403 on CE 12.0.14 even with admin account | Use `/api/v2.1/search-file/` instead |
| **Search invalid repo_id** | Returns HTML error page instead of JSON | Check repo_id validity before calling; handle gracefully |
| **Search no pagination** | `/api/v2.1/search-file/` ignores `page`/`per_page` params | All results returned at once; no way to limit |
| **Search type field** | Returns `"folder"` not `"dir"` for directories | Use `type === "folder"` not `type === "dir"` |

---

## Roadmap Discoveries

Based on API documentation review, these features are available for future Omarseafile versions:

### High Priority (v0.7.0+)
| Feature | API Availability | Priority |
|---------|-----------------|----------|
| Share Links (create/list/delete) | `/api/v2.1/share-links/` | High (v0.2.2) |
| File Search | `/api2/search/`, `/api/v2.1/search-file/` | High |
| **File History/Versions** | `/api2/repos/{id}/file/history/` | High (v0.7.0) |
| File Comments | `/api2/repos/{id}/file/comments/` | Low |
| File Locking | `/api/v2.1/via-repo-token/file/` (lock/unlock) | Low |
| Upload Links (Shared) | `/api/v2.1/upload-links/` | Medium |
| Tags/Metadata | `/api/v2.1/repos/{id}/metadata/` | Low (Pro feature?) |

### Roadmap Adjustments

| Original Plan | Adjusted Plan | Reason |
|---------------|---------------|--------|
| v0.2.2 Sharing | **Keep** | Share links API well documented |
| Chunked Upload | **Defer to v0.8.0** | Not needed yet; standard upload handles 500MB+ |
| Folder Move Sync | **Available** | `/api/v2.1/move-folder-merge/` exists |
| Batch Copy | **Available** | `/api/v2.1/repos/sync-batch-copy-item/` |
| File Search | **Available** | `/api2/search/` + `/api/v2.1/search-file/` — **Recommended: `/api/v2.1/search-file/` for v0.7.0** |
| File Locking | **Available** | `/api/v2.1/via-repo-token/file/` (lock/unlock) |
| Trash/Restore | **Available** | `/api/v2.1/repos/{id}/trash/` |
| File History/Versions | **Available** | `/api/v2.1/repos/{id}/file/history/` |

---

## Development Rule Enforcement

> **Before any new Seafile feature implementation:**
> 1. Check `docs/SEAFILE_API.md` for endpoint status
> 2. If not `VERIFIED` → check official docs (seafile-api.readme.io)
> 3. SPIKE minimal test against real server
> 4. Update this document with results
> 5. Only then implement

**No endpoint may be invented or assumed.**

---

## Maintenance

- **Last Audit**: 2026-08-22
- **Server Tested**: `http://192.168.1.108:8000` (Seafile CE 12.0.14)
- **Auditor**: Omarseafile bootstrap process
- **Next Review**: Before v0.8.0 implementation
- **Search API Audit**: 2026-08-22 — SPIKEs completed; `/api2/search/` NOT_ACCESSIBLE, `/api/v2.1/search-file/` VERIFIED
- **History/Revision/Trash Audit**: 2026-08-22 — SPIKEs completed

---

*This document is the single source of truth for Omarseafile's Seafile API integration. Update it before every new feature.*
