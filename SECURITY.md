# Security Policy

## Supported Versions

Until v1.0 is released, security fixes are made against the current development branch. Older published versions may not receive fixes.

## Reporting a Vulnerability

Please report suspected vulnerabilities privately through the repository's GitHub security reporting mechanism when available. Do not post credentials, access tokens, private server addresses, or exploit details in a public issue. Include the affected version, reproduction steps, and impact while redacting sensitive data.

## Security Boundaries

- Omarseafile stores the session token, server URL, and account email through Secret Service (`secret-tool`); it does not persist the login password.
- Transfer authentication and server-provided transfer URLs are kept out of process arguments and environment variables.
- Temporary authorization header and curl configuration files are created with mode 0600 and removed after use, including failure and cancellation paths.
- Transfer processes disable user curl configuration and do not follow redirects, so a custom authorization header is not forwarded to another origin.
- TLS certificate verification is not disabled. HTTPS is required for non-loopback servers; HTTP is accepted only for loopback (localhost, 127.0.0.1, ::1).
- The plugin has no telemetry service. Network requests are made to the Seafile server configured by the user and to local desktop utilities such as `wl-copy`.

**Transfer Path Hardening (Finding 5):**
- **Secure output creation**: Download targets created via `secure_output.py` using held directory FD (O_DIRECTORY|O_NOFOLLOW), verified ownership/permissions, unpredictable basename, O_CREAT|O_EXCL|O_NOFOLLOW, mode 0600. curl writes to held FD (stdout), never a pathname. Relative unlink on failure/cancellation.
- **Byte ceiling & disk admission**: Producer-side 1 GiB default via curl --max-filesize. Disk-space admission check using fstatvfs on held dir_fd with 256 MiB safety margin. Insufficient space fails before any content write. ENOSPC during transfer triggers cleanup.
- **Deadlines**: curl --max-time 30 min, --connect-timeout 10s, stall protection (--speed-limit 1 --speed-time 30s). Process group isolation via setsid; cancellation kills entire tree (kill -TERM -pgid).
- **Open Local cache**: Private XDG_RUNTIME_DIR/omarseafile/cache. Bounded 2 GiB default, LRU eviction on successful completion. Active/temp files protected from eviction. No symlink traversal during eviction.
- **Upload source hardening**: Absolute path required. Must be regular file (stat %F check). Rejects symlinks, directories, devices, FIFOs, sockets. Size precheck (1 GiB default).
- **Auth isolation**: Cross-origin transfer URLs never receive Authorization header (same-origin check via UrlPolicy.shouldAttachAuth). Redirects disabled (--no-location).
- **Output bounds**: Helper stderr capped at 64 KiB (--max-stderr-bytes). stdout bounded by curl --max-filesize.

These are implementation goals and documented behavior, not a guarantee against abrupt host/process termination or a compromised host or Seafile server. Keep Omarchy, Quickshell, Seafile, and the host system updated.
