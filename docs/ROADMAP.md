# Omarseafile Roadmap

## Current State

Version `1.0.0` completes the validated v1 scope. Further items below are post-v1 work.

## v1 Scope

- Stable Omarchy installation, configuration, login, auto-login, logout, and settings.
- Library/folder browsing, search, upload, download, sharing, history, trash, and file operations.
- Single and batch Copy/Move/Delete with visible destination paths.
- Transfer progress, cancellation, explicit retry, history, offline indication, and clear error states.
- Secure credential and transfer handling, validation, and public documentation.

## Post-v1

These are not v1 commitments:

- Reliable native graphical local-file picker.
- Cross-library Copy/Move.
- Chunked or resumable uploads when supported by the target server.
- File locking, comments, starred items, shared upload links, directory ZIP downloads, library management, and activities.

## Server Constraints

The tested Seafile CE 12.0.x environment does not provide confirmable trash restore, revision revert, or the global search endpoint used by the client. Repo-scoped search is used instead. The client also uses single-request uploads and does not automatically retry an upload after an ambiguous transfer failure.

## Release Gate

The final version bump, release tag, public release, and independent GPT-5.6 Sol audit are future work. See [V1_DEFINITION_OF_DONE.md](V1_DEFINITION_OF_DONE.md).
