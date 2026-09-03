# AGENTS.md — Omarseafile operating contract

Concise rules for coding agents working on this repository. Read this file
every session. It is the compiled project operating model; do not reconstruct
workflow from past conversations.

## 1. Project classification

- **BROWNFIELD**, structurally **LIGHT**, published plugin (v1.0.0).
- High-risk domains that keep full review rigor despite LIGHT structural
  complexity:
  - security / trust boundaries (credentials, transfer URLs, cross-origin
    token isolation, secret-file creation, process lifecycle);
  - Omarchy / Quickshell host integration;
  - Seafile external API integration.

## 2. Source of truth

Priority (highest first):

1. executable behavior + validation / tests;
2. current source code;
3. authoritative deployed plugin state;
4. exact Git / GitHub state (pushed SHA);
5. maintained project docs (README, CONTRIBUTING, SECURITY, docs/);
6. historical docs / past AI conversations (lowest).

- The repository is canonical.
- The installed plugin (`~/.config/omarchy/plugins/roddy.seafile`) is a
  **deployment target**, never a second source tree.

## 3. Development host

- The current Omarchy laptop is both the authoritative development machine
  and the authoritative runtime-validation machine.
- Do not introduce a split-machine workflow.

## 4. Runtime validation contract

After **any** source/QML change that affects runtime behavior:

```text
SOURCE CHANGE
→ ./deploy.sh
→ omarchy-restart-shell
→ verify NEW Quickshell PID != OLD PID
→ inspect logs from NEW PID only
→ exercise the real Omarseafile UI/runtime path
```

- Omarchy runs a long-lived Quickshell with `QS_DISABLE_FILE_WATCHER=1`, so
  hot reload is **not** authoritative.
- Manual curl / backend / helper execution alone does **not** prove UI
  behavior.
- Hyprland `hyprctl` cursor/key dispatch is an accepted automation mechanism
  when actual GUI interaction must be proven.
- Docs-only changes require **no** runtime restart.

## 5. Validation

Use the actual existing commands:

```text
./scripts/validate.sh
omarchy plugin validate .
git diff --check
./deploy.sh --check        # where source/deployment parity matters
```

Do not invent commands that do not exist in this repository.

## 6. Security workflow

- Current security work lives on branch: `security/marketplace-review`.
- Marketplace issue: **#4145**.
- Do **not** without explicit approval: merge, force-push, move the v1.0.0
  tag, create a release, or modify marketplace issue #4145.
- An implementation agent's "DONE" report is **not** proof that a maintainer
  finding is closed.

## 7. Review gate

For security / high-risk changes:

```text
implementation
→ focused tests / static validation
→ authoritative runtime validation where applicable
→ commit + push on the dedicated branch
→ independent review of the EXACT pushed GitHub SHA
→ remediate findings
→ only then eligible for merge
```

- The independent reviewer must inspect code and evidence, not trust the
  implementer's conclusions.

## 8. Autonomy

Agents may autonomously:

- inspect / read;
- run non-destructive tests and validation;
- implement an explicitly approved, scoped change;
- fix straightforward failures inside that scope.

Agents must stop / escalate for:

- destructive operations;
- architecture changes;
- new dependencies / tools;
- security-policy decisions outside the approved scope;
- branch / merge / release decisions;
- real ambiguity affecting product behavior;
- unexpected secret exposure.

- Never print real credentials or tokens.

## 9. Model / role policy

- Roles are **not** permanently tied to model names.
- Use economical / free coding models for mechanical implementation, tests,
  validation, and straightforward fixes.
- Reserve stronger reasoning, when available, for architecture, difficult
  security design, ambiguous high-risk decisions, and major independent
  review.
- Single-model operation must remain possible.
- A fresh-context reviewer is acceptable when only one model is available.

## 10. Tooling policy

Keep what is already working:

- OpenCode;
- RTK;
- Ponytail;
- existing native scripts and workflow.

Default for **new** tooling: **NONE**.

Do not introduce BMAD, Spec Kit, OpenSpec, GSD, Task Master, Beads, Serena,
SkillSpector, MCP infrastructure, memory infrastructure, or orchestration
without a demonstrated project-specific gap and explicit approval.

Prefer native / project-existing mechanisms first.

## 11. Anti-churn

This is mature brownfield. Prefer the smallest change that satisfies the
requirement.

Do not:

- redesign working architecture during a scoped fix;
- duplicate state authorities;
- create speculative infrastructure;
- refactor unrelated code;
- add ceremony merely to match a methodology.

## 12. External integration

Do not assume local / static success proves:

- Omarchy / Quickshell behavior;
- Seafile API behavior.

External-integration claims require evidence against the relevant real
contract / runtime.

## 13. Current security mission

- The marketplace remediation remains the active critical mission.
- Bootstrap adoption must **not** alter application or security
  implementation.
- After this contract is established, resume the security remediation from
  the existing branch state.