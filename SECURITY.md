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
- TLS certificate verification is not disabled. HTTPS is recommended; HTTP is accepted only with a warning.
- The plugin has no telemetry service. Network requests are made to the Seafile server configured by the user and to local desktop utilities such as `wl-copy`.

These are implementation goals and documented behavior, not a guarantee against abrupt host/process termination or a compromised host or Seafile server. Keep Omarchy, Quickshell, Seafile, and the host system updated.
