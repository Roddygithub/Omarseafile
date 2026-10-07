# Phase 1 — session/token/cache implementation and audit

## Scope and status

Historical branch/baseline details are omitted here; this document records the session/cache design and test method, not current repository or deployment status.

## Logout contract

Logout revokes in-memory authority synchronously. Work admitted before logout
but still waiting on path validation, HTTP private-file preparation, an upload
slot/stat, a link response, or a retry cannot launch using the old session.
Registered running transfers retain existing best-effort cancellation. A local
file already finalized or a remote mutation already accepted cannot be rolled
back; logout is not server-side token revocation. Old HTTP processes may finish
for resource cleanup, but cannot deliver results to a new session. Old transfer
completions cannot invalidate its cache, notify through its panel, or log it out.
Keyring operations remain serialized; local revocation does not wait for them.

## Reproductions before fixes

The initial eight behavioral checks ran against the untouched baseline before
production edits: six failed, two control cases passed. The final expanded
suite also ran against a temporary `git archive` of the exact baseline: **18
failures / 10 passes**, versus **28 passes** on this branch. No checkout or branch
mutation was used to test the baseline.

- **A — delayed folder response:** launch A `/api2/repos/repo/dir/?p=%2Fdocs`,
  switch through the real panel `changeServerUrl`/logout path, start B for the
  same repo/path, complete B then A. Assertions inspect the generated command
  and private-header contents using synthetic credentials: each request keeps
  its own URL/auth pair. B's immediate UI stays B (existing navigation guard),
  but A overwrites B's folder cache; navigating back consumes A's data. This is
  a cache-write/session bug, not observed credential forwarding to B.
- **B — logout/download admission:** hold `SafePath.secureJoin`, call
  `startDownload`, logout, then release the validation callback. The original
  baseline registered the download with the *new* epoch and sent an old-auth
  link request. Related controls covered late exits and HTTP preparation races.
- **C — keys/invalidation:** the original tests exercised path-boundary,
  root/subtree, and account/server-scope collisions, plus cache reuse across
  re-login.
- **Related in-scope findings:** a pending keyring store delays memory clearing;
  delayed startup lookup can republish logged-out credentials; changing the API
  URL retains the old configured token; late auth/direct API callbacks survive
  session changes. Equal cache timestamps can exceed the entry limit (three
  entries with a configured limit of two). Each has a runnable regression.

No real credentials were read or printed by the new harness.

## Root causes and invariants established

1. `HttpTransport.qml` captures a generation per request. API URL/token changes
   invalidate it. Old callbacks are suppressed, pre-launch continuations stop,
   and any private files already allocated are cleaned up. This covers all API
   transport callers, including direct mutation methods, without rewriting them.
2. `SeafileAPI.qml` clears the token when changing server and invalidates even
   empty-to-empty token clearing (logout during an in-flight login).
3. `Panel.qml` checks session identity *before* library/folder cache writes and
   visible model updates. Cache generation also prevents responses repopulating
   an explicitly cleared cache. Same-session obsolete navigation may still warm
   its own path's cache, without replacing the current view. Old transfer and
   asynchronous logout/cache-clear feedback are ignored.
4. `TransferService.qml` captures the epoch before download destination
   validation, rather than after it. Existing transfer cancellation is preserved.
5. `Auth.qml` updates/revokes memory synchronously and guards startup lookup
   publication. Serialized keyring IO cannot subsequently overwrite newer memory.
6. `Cache.qml` uses JSON tuple keys containing generation, server/account scope,
   resource kind, repo and unchanged path. Scope activation starts a fresh
   generation. Root/subtree invalidation respects component boundaries; eviction
   also works when timestamps tie. Manual clear preserves account scope while
   advancing the generation.

TLS, UrlPolicy, redirect policy and credential-file protections are unchanged.
No dependency was added.

## Changed files

Production: `Panel.qml`, `js/Auth.qml`, `js/Cache.qml`, `js/HttpTransport.qml`,
`js/SeafileAPI.qml`, `js/TransferService.qml`.

Tests: `scripts/test_session_cache.js`, `scripts/test_session_cache.py`,
`scripts/test_portable.py` (new suite wired into the portable gate).

Audit: this document. Commit identity is reported with the final handoff.

## Harness and validation

The new suite reuses `scripts/qmljs.js`: it executes actual QML JavaScript
functions with deterministic delays at OS/process boundaries. It does not
reimplement API, cache, session or panel navigation behavior, and is not a
source-pattern-only test. It deliberately does **not** claim an interactive QML
UI/server race reproduction. Existing real Quickshell runtime suites supplement
it; no live keyring or desktop interaction is needed for the new race suite.

- `python3 scripts/test_session_cache.py`: **28/28 pass**.
- Portable gate: **13 suites pass**, including security, stale-response,
  remediation, panel navigation, and the new suite.
- `python3 scripts/test_ux_performance.py`: **12/12 pass** (existing static checks).
- Quickshell Open Local lifecycle and runtime remediation: **pass**.
- Real HTTP transport integration: **7/7 pass**.
- Deployment-scope tests, QML structural checks and `git diff --check`: **pass**.
- `omarchy plugin validate .`: **exit 0**.
- Ordinary `./scripts/validate.sh`: **exit 1 solely for live deployment parity**;
  `./deploy.sh --check` reports drift. No live deployment was performed.
- Full `validate.sh` with `OMARCHY_PLUGIN_DIR` pointing at a fresh temporary
  deployment: **all checks pass**. Shellcheck is explicitly skipped because it
  is not installed; other listed gates ran.

The original run used temporary local logs, which are not repository artifacts. Its results are historical evidence for that branch, not a claim about the current working tree.

## Adjacent findings and limits

- Live deploy dry-run includes deletion of the target's `.git` file plus existing
  permission/mtime differences. Do not deploy over that checkout without a
  separate deployment-scope decision. The target was left untouched.
- Existing HTTP timing logs include raw resource paths; share-link identifiers
  can occur in such paths. This pre-existing logging behavior was not expanded
  into a logging audit, and the reproduction used only synthetic credentials.
- Logical cancellation does not undo already-started network side effects or
  revoke server-issued tokens. Keyring-clear failures remain user-visible only
  if the logout is still current.
