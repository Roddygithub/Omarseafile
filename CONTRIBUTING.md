# Contributing

## Prerequisites

- Omarchy, Quickshell, and a Wayland session for runtime testing.
- `curl`, `libsecret`/`secret-tool`, `rsync`, and optionally `wl-clipboard`.
- A disposable Seafile test account/library for mutation tests.

## Development Setup

```bash
git clone https://github.com/Roddygithub/Omarseafile.git
cd Omarseafile
./deploy.sh
```

The repository is the canonical source. The installed plugin is a deployment target, not a second source tree.

## Validation

Run static checks before submitting changes:

```bash
./scripts/validate.sh
./deploy.sh --check
```

For runtime changes, Omarchy uses a long-lived Quickshell process with file watching disabled. The authoritative workflow is:

```text
source change
  -> ./deploy.sh
  -> omarchy-restart-shell
  -> identify the new Quickshell PID
  -> inspect only that PID's logs
  -> perform the runtime test
```

`./scripts/dev-deploy.sh` chains deployment, shell restart, and fresh-PID log inspection; perform the targeted runtime interaction afterward. Do not treat hot reload or logs from an old PID as runtime evidence.

## Testing Expectations

Use disposable server data for Move, Copy, Delete, and upload tests. Do not modify a user's existing files. Verify both the UI result and the server-side path for file mutations. Never put tokens, passwords, private server addresses, or test artifacts into commits or logs.

## Pull Requests

- Keep changes focused and explain user-visible behavior.
- Update documentation when behavior changes.
- Do not bump the manifest version, tag, push, or publish a release as part of ordinary development unless the release task explicitly requires it.
- Report unresolved runtime or server compatibility findings clearly.
