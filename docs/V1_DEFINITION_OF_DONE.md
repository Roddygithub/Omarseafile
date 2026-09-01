# Omarseafile v1.0 Definition of Done

This is a release checklist for the later independent audit. It is not a certification and is intentionally not marked complete.

## Functionality

- [ ] Browse libraries and folders with breadcrumbs.
- [ ] Search accessible libraries and handle loading, empty, capped, and error states.
- [ ] Upload by manual local path; download with progress and no-overwrite collision protection.
- [ ] Create folders, rename, delete, share, history, and trash browsing work; unsupported restore is clearly surfaced without a mutation request.
- [ ] Single and batch Copy/Move/Delete work through the current UI.
- [ ] Move/Copy destination path matches the effective repo/path sent to Seafile.

## Runtime and Installation

- [ ] `omarchy plugin add ... --enable` installation works.
- [ ] Login, auto-login, logout, settings, dependency checks, and URL validation work.
- [ ] `./deploy.sh` followed by a fresh `omarchy-restart-shell` loads source changes.
- [ ] Bar widget and panel load without runtime errors.
- [ ] Uninstall behavior is documented and verified.

## Transfers

- [ ] Download and upload progress, cancellation, conflict handling, and explicit retry work; ambiguous failed uploads are not retried automatically.
- [ ] Transfer Manager groups active, completed, and failed transfers.
- [ ] Partial files and temporary authorization material are cleaned up.

## Safety and Security

- [ ] Root/library destructive actions are blocked where unsupported.
- [ ] Same-source Move is rejected before the API call.
- [ ] Credentials remain in Secret Service/keyring.
- [ ] Token is absent from argv, environment, logs, and repository files.
- [ ] Temporary auth files are restricted and cleaned on success, failure, cancellation, retry, and logout.
- [ ] TLS verification is never bypassed.

## Static and Documentation Validation

- [ ] `./scripts/validate.sh` passes.
- [ ] `./deploy.sh --check` passes.
- [ ] `git diff --check` passes.
- [ ] README, SECURITY, CONTRIBUTING, CHANGELOG, ROADMAP, and keybindings match current code.
- [ ] Links and public examples contain no private machine data or test artifacts.

## Repository Hygiene

- [ ] No generated junk, debug traces, secrets, or disposable test artifacts are tracked.
- [ ] Manifest version is intentionally changed to `1.0.0` only at release time.
- [ ] Final independent release audit is completed by a fresh reviewer.
- [ ] Release tag and public release are created only after the audit passes.
