# Omarseafile

A Seafile cloud file client plugin for [Omarchy](https://omarchy.org).

Omarseafile integrates into the Omarchy bar as a widget. Click to open a panel for browsing, downloading, uploading, and managing files on your Seafile server.

## Screenshots

*Screenshots coming soon*

## Features

- **Browse libraries and folders** — Navigate your Seafile repositories with breadcrumb navigation
- **Download files** — Click any file to download to `~/Downloads` with progress tracking
- **Upload files** — Enter local file path to upload to current folder
- **File operations** — Create folders, rename, move, copy, delete (single and batch)
- **Multi-selection** — Ctrl+Click, Shift+Click, Ctrl+A for batch operations
- **Search** — Repo-scoped search with debounced input
- **Share links** — Create password-protected, expiring share links with permissions
- **Transfer Manager** — Active, completed, and failed transfers with retry/cancel
- **File history** — Browse file revision history and download historical versions
- **Trash browser** — View deleted items and restore folders
- **Keyboard navigation** — F2=rename, Delete=delete, Enter=activate, Arrows=navigate, Esc=close, Ctrl+A=Select All
- **Offline detection** — Automatic connectivity monitoring with offline banner

## Requirements

- **Omarchy** (Hyprland/Wayland)
- **Seafile CE 12.0+** (tested with 12.0.14)
- **Runtime dependencies** (must be installed on the system):
  - `curl` — file transfers
  - `libsecret` (provides `secret-tool`) — secure credential storage in GNOME keyring
  - `wl-clipboard` (provides `wl-copy`) — clipboard copy for share links (optional)

Install dependencies on Arch/Omarchy:
```bash
sudo pacman -S curl libsecret wl-clipboard
```

## Installation

### End-user installation (recommended)

```bash
omarchy plugin add https://github.com/roddy/Omarseafile.git --enable
```

This clones the plugin to `~/.config/omarchy/plugins/roddy.seafile/` and enables it.

### Development installation

```bash
git clone https://github.com/roddy/Omarseafile.git
cd Omarseafile
./deploy.sh
```

This syncs the repository to the Omarchy plugin directory for local testing.

## Enabling the Plugin

If installed via `omarchy plugin add`, the plugin is ready to use. Click the Seafile icon () in the Omarchy bar to open the panel.

If manually deployed, run:
```bash
omarchy plugin enable roddy.seafile
```

## First Login

1. Click the Seafile icon in the bar
2. Enter your Seafile server URL (e.g. `https://cloud.example.com` or `http://192.0.2.10:8000`)
3. Enter your email and password
4. Click **Connect**

The server URL is validated for syntax before connecting. Plain HTTP is allowed but shows a security warning.

## Server URL Examples

| Format | Example |
|--------|---------|
| HTTPS domain | `https://seafile.example.com` |
| HTTPS with path | `https://cloud.example.com/seafile` |
| HTTP with IP and port | `http://192.0.2.10:8000` |
| HTTP localhost | `http://localhost:8000` |

Trailing slashes are normalized automatically.

## HTTPS & Security Guidance

- **HTTPS is strongly recommended** — credentials are encrypted in transit
- **Self-signed certificates** are not supported in v0.8. Use a valid TLS certificate or add your CA to the system trust store
- **Credentials are stored in the system keyring** (via `secret-tool`) — never in plain text files
- **Authentication tokens** are passed via temporary 0600 files to curl, never in command line or environment
- **Auto-login** restores session from keyring on panel open (toggleable in Settings)

## Usage

### Browsing
- Click a library to enter it
- Click a folder to navigate
- Click a file to download
- Use breadcrumbs (top) to navigate back

### Download/Upload
- **Download**: Click any file — saves to `~/Downloads` with progress
- **Upload**: Click ↑ Upload button → enter local file path → uploads to current folder

### File Operations
- **Right-click** any item for context menu
- **Rename**: F2 or context menu
- **Move/Copy/Delete**: Context menu or BatchActionBar (appears when items selected)
- **Create Folder**: Right-click → New Folder

### Multi-selection & Batch Operations
- **Ctrl+Click**: Toggle selection
- **Shift+Click**: Range selection
- **Ctrl+A**: Select all visible items
- BatchActionBar shows: Move, Copy, Delete, Clear

### Search
- Click 🔍 Search icon in toolbar
- Type query (min 2 chars) — searches current repo or all accessible repos
- Click result to navigate (folder) or download (file)

### Sharing
- Right-click item → Share
- Set password (min 6 chars), expiration (days), permissions
- Copy link to clipboard (requires `wl-copy`)

### Transfer Manager
- Click 📥 Transfer icon in toolbar (shows active count)
- Tabs: Active / Completed / Failed
- Retry failed transfers, clear history

### File History
- Right-click file → History
- View revision metadata (author, date, size)
- Click revision to download historical version

### Trash / Recovery
- Click 🗑️ Trash icon in toolbar
- View deleted files and folders
- Restore folders (files: restore not supported on CE 12.0.14)

## Keyboard Controls

| Shortcut | Action |
|----------|--------|
| F2 | Rename selected item |
| Delete | Delete selected item(s) |
| Enter / Space | Activate (open folder / download file) |
| Arrow keys | Navigate list |
| Esc | Close panel / dismiss dialog / clear search |
| Ctrl+A | Select all visible items |

*All shortcuts are contextual — only active when file list is focused, not in text fields.*

## Known Seafile CE Limitations

These are upstream Seafile CE 12.0.14 limitations, not Omarseafile bugs:

- **No chunked/resumable upload** — large files upload in single request (tested to 500 MB+)
- **No file restore from trash** — only folders can be restored
- **No revision revert** — historical versions can be downloaded but not restored
- **No global search** — search is repo-scoped only (CE limitation)
- **Batch delete API not working** — Omarseafile uses sequential fallback

## Troubleshooting

| Issue | Solution |
|-------|----------|
| "Missing dependencies" on startup | Install `curl`, `libsecret`, `wl-clipboard` via `pacman` |
| "Invalid URL format" | Check URL syntax — must include scheme (http/https) |
| Connection fails / TLS error | Verify server URL, check certificate validity, ensure HTTPS cert is trusted |
| "Authentication failed" | Check email/password; try logging in via web UI first |
| Auto-login not working | Ensure `secret-tool` works; check Settings → Auto-login is enabled |
| Share link copy doesn't work | Install `wl-clipboard` (`sudo pacman -S wl-clipboard`) |
| Plugin not appearing in bar | Run `omarchy plugin list` to verify enabled; check `omarchy-shell` logs |

## Updating

### End-user (via omarchy)
```bash
omarchy plugin update roddy.seafile
```

### Development (from source)
```bash
git pull
./deploy.sh
```

## Uninstalling

```bash
omarchy plugin remove roddy.seafile
```

This disables the plugin and removes the local clone.

## Development

See [CONTRIBUTING.md](CONTRIBUTING.md) for development setup, coding conventions, and contribution guidelines.

## Security Model

- Credentials stored in GNOME keyring via `secret-tool`
- Auth tokens never in argv, environment, or logs
- Temporary auth header files: 0600 permissions, cleaned on all paths (success, failure, cancel, retry, logout)
- HTTPS enforced by default with warning for HTTP
- No telemetry, no external connections except your Seafile server

## License

MIT License — see [LICENSE](LICENSE) for details.