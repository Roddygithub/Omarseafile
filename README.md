# Omarseafile

Omarseafile is an [Omarchy](https://omarchy.org) bar-widget plugin for browsing and managing a self-hosted [Seafile](https://www.seafile.com/) account from a Quickshell panel.

## Features

- Browse accessible Seafile libraries and folders with breadcrumbs.
- Search across accessible non-encrypted libraries.
- Download files to `~/Downloads` with progress, cancellation, retry, and no-overwrite collision protection.
- **Secure download target creation**: temporary files created with exclusive O_CREAT|O_EXCL|O_NOFOLLOW on a held directory FD, mode 0600, curl writes to held FD (no pathname reopen), producer-side byte ceiling (1 GiB default) and disk-space admission check (256 MiB safety margin), automatic cleanup on failure/cancellation, symlink and clobber protection.
- **Open Local**: download to private XDG_RUNTIME_DIR cache, same secure creation, bounded cache (2 GiB default, LRU eviction on completion), cached file opened with xdg-open.
- Upload a local file by entering its path, with progress, cancellation, manual retry, and server-side conflict protection.
- **Upload source hardening**: absolute path required, must be regular file (rejects symlinks, directories, devices, FIFOs, sockets), size precheck (1 GiB default).
- Create folders, rename items, and delete files or folders.
- Select multiple items with Ctrl+Click, Shift+Click, or Ctrl+A for batch actions.
- Copy and move files and folders, including batch operations.
- Choose Copy/Move destinations in the existing Seafile browser and see the effective destination path.
- Create, list, copy, and revoke password-protected or expiring share links.
- Browse file history and download historical revisions.
- Browse library trash; restore is explicitly unavailable because the tested CE API does not provide a confirmable restore operation.
- Monitor active, completed, and failed transfers.
- Show offline status, loading states, errors, empty states, and toasts.
- Open completed downloads or reveal them in the file manager.

## Requirements

- Omarchy with Hyprland/Wayland and Quickshell.
- A reachable Seafile server. Development validation used Seafile CE 12.0.x.
- `curl` for transfers.
- `libsecret` for `secret-tool` and credential storage.
- `wl-clipboard` for copying share links. Sharing still works without it, but copying the link does not.

On Arch/Omarchy:

```bash
sudo pacman -S curl libsecret wl-clipboard
```

## Installation

```bash
omarchy plugin add https://github.com/Roddygithub/Omarseafile.git --enable
```

The plugin can then be opened from the Seafile icon in the Omarchy bar. For a source checkout, see [CONTRIBUTING.md](CONTRIBUTING.md).

To update an installed plugin:

```bash
omarchy plugin update roddy.seafile
```

## First Login

1. Open the Seafile bar widget.
2. Enter the server URL, email, and password.
3. Select **Connect**.

HTTPS is required for non-loopback servers. HTTP is accepted only for loopback addresses (localhost, 127.0.0.1). The URL is normalized and validated before authentication. Auto-login can be enabled or disabled in Settings.

The session token, server URL, and account email are stored through the desktop Secret Service using `secret-tool`. The login password is not persisted.

## Usage

### Browsing and transfers

- Select a library, then select folders to navigate.
- Double-click a file, press Enter with it focused, or use its context menu to download it.
- Choose **Upload**, then enter the local path of the file to upload.
- Right-click an item for available actions.
- Use the Transfer Manager to cancel active transfers, retry failed transfers, or clear terminal history.

### File operations

- **New Folder** creates a folder in the current location.
- **Rename** is available from the context menu or F2.
- **Delete** is available from the context menu or Delete.
- Use Ctrl+Click, Shift+Click, or Ctrl+A to select items for batch Move, Copy, or Delete.

### Copy and Move destinations

Copy and Move use the existing Seafile browser. Start the operation, browse folders inside the source library, and confirm with **Copy here** or **Move here**. The panel displays the current destination as a library and path, for example `Library / Projects / 2026`.

Copy and Move are same-library operations in v1. A source folder cannot be moved or copied into itself or one of its descendants, and a destination equal to every selected item's source folder is rejected.

### Search

Search is available from the toolbar. It is debounced and searches each accessible non-encrypted library through Seafile's repo-scoped search API. Results include the library, path, type, and size where available. Seafile CE's global search endpoint is not used.

### Sharing, history, and trash

- Right-click a file or folder and choose **Share** to manage share links. Optional password protection requires at least six characters; expiration and permissions are supported.
- Choose **History** on a file to inspect revisions and download an older revision.
- Use the toolbar's Trash view to inspect deleted items. Restore is not offered in v1 because the tested CE 12.0.x endpoint did not perform or confirm restoration.

## Upload Limitation

The current Omarchy/Quickshell environment does not provide a reliable native graphical local-file picker for this plugin. Uploads therefore use the supported manual-path workflow: choose **Upload** and enter the local file path. A reliable graphical picker is post-v1 work.

## Keyboard Controls

| Shortcut | Action |
| --- | --- |
| F2 | Rename the current or selected item |
| Delete | Delete the current or selected item |
| Enter / Space | Navigate into a folder or activate a file |
| Arrow Up/Down / j k | Move the file-list cursor |
| h / l | Back / open the focused folder |
| Escape | Close the active dialog/view, clear search, or close the panel |
| Ctrl+A | Select all visible items |

Shortcuts are contextual and are not intercepted while a text field has focus. See [docs/KEYBINDINGS.md](docs/KEYBINDINGS.md).

## Known Limitations

- Native graphical local-file selection is unavailable in the current Quickshell environment; uploads require a manually entered path.
- Copy and Move are limited to the current source library.
- Seafile CE support depends on the server's enabled APIs. In the tested CE 12.0.x environment, trash restore and revision revert are unavailable; repo-scoped search returns all matching results without pagination.
- Large uploads use a single request rather than chunked or resumable upload.
- HTTPS is required for non-loopback servers. Certificate verification uses the system trust store; TLS verification is not bypassed.
- The plugin assumes Omarchy's Quickshell runtime and Wayland desktop integration.

## Troubleshooting

| Problem | Action |
| --- | --- |
| Missing dependency | Install `curl`, `libsecret`, and optionally `wl-clipboard`. |
| Invalid URL | Include an `https://` scheme and check the server address. HTTP is only allowed for loopback. |
| Authentication failure | Check the credentials and try the Seafile web interface. |
| TLS failure | Use a certificate trusted by the system; do not disable verification. |
| Auto-login failure | Check that Secret Service is available and Auto-login is enabled in Settings. |
| Share link will not copy | Install `wl-clipboard`; the link can still be viewed. |
| Plugin missing from the bar | Check `omarchy plugin list`, then inspect Omarchy shell logs. |

## Development

The repository is the source of truth. Run `./scripts/validate.sh` before submitting changes.

Omarchy uses a long-lived Quickshell process with file watching disabled in this environment. The authoritative runtime workflow is:

```text
source change
  -> ./deploy.sh
  -> omarchy-restart-shell
  -> identify the new Quickshell PID
  -> inspect only that PID's logs
  -> perform the runtime test
```

`./scripts/dev-deploy.sh` automates deployment, restart, fresh-PID detection, and log checks. The targeted runtime interaction remains manual. See [CONTRIBUTING.md](CONTRIBUTING.md) and [docs/SEAFILE_API.md](docs/SEAFILE_API.md).

## Uninstalling

```bash
omarchy plugin remove roddy.seafile
```

This disables the plugin and removes its local plugin checkout. Credentials remain in Secret Service. Clear them before uninstalling with Logout, or afterward with:

```bash
secret-tool clear service seafile key auth-token
secret-tool clear service seafile key server-url
secret-tool clear service seafile key user-email
```

## Security

See [SECURITY.md](SECURITY.md) for reporting and security boundaries. In brief, credentials use Secret Service, transfer authentication avoids argv/environment exposure, temporary authorization/configuration files are restricted and cleaned up, and the plugin makes no telemetry connection.

**Transfer security (Finding 5 remediation):**
- Download targets created exclusively via held directory FD (O_DIRECTORY|O_NOFOLLOW), verified ownership and permissions, unpredictable basename, O_CREAT|O_EXCL|O_NOFOLLOW, mode 0600
- curl writes to held file descriptor (stdout), never a pathname target
- Producer-side byte ceiling (default 1 GiB via curl --max-filesize) and disk-space admission check (fstatvfs on held dir_fd, default 256 MiB safety margin)
- Download deadlines: --max-time 30 min, --connect-timeout 10s, stall protection (--speed-limit 1 --speed-time 30s)
- Process group isolation via setsid; cancellation kills entire process tree (kill -TERM -pgid)
- Open Local cache bounded (default 2 GiB), LRU eviction on successful completion, active/temp files protected
- Upload source validation: absolute path, regular file only (rejects symlinks, directories, devices, FIFOs, sockets), size precheck (default 1 GiB)
- Cross-origin transfer URLs never receive Authorization header (same-origin check)
- Redirects disabled (--no-location)
- Helper stdout/stderr bounded (64 KiB stderr cap)

## Project Documents

- [Security policy](SECURITY.md)
- [Contributing and development](CONTRIBUTING.md)
- [Keybindings](docs/KEYBINDINGS.md)
- [Seafile API notes](docs/SEAFILE_API.md)
- [Roadmap](docs/ROADMAP.md)
- [v1.0 checklist](docs/V1_DEFINITION_OF_DONE.md)
- [Changelog](CHANGELOG.md)

## License

MIT License. See [LICENSE](LICENSE).
