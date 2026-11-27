# agentask-relay — the unattended relay kit (`agentask-relay`)

[![selftest](https://github.com/kizemo/agentask-relay/actions/workflows/selftest.yml/badge.svg)](https://github.com/kizemo/agentask-relay/actions/workflows/selftest.yml)

**English** | [简体中文](./README.zh-CN.md)

Put an **unattended relay chain** into any git project. One sentence starts a
self-advancing chain of sessions where exactly one writer runs at a time, every
stage has acceptance criteria, and the chain stops on its own the moment a human
checkpoint is reached.

Works on **MCode**, **Claude Code**, **Codex CLI** and **OpenClaw**.

---

## 1. What it does

Without a relay kit, "keep going until it's done" means a human keeps pasting
"continue" into a chat window, and every paste re-reads the whole repo, loses
the thread, and sometimes writes into a file another session is writing right
now. The kit turns that into a **machine-driven chain**:

| | Without the kit | With the kit |
|---|---|---|
| Who starts the next stage | a human pastes "continue" | the previous stage starts it itself |
| Concurrency | two sessions edit the same file | one writer per project, enforced by an atomic lock |
| Where is the state | in someone's head | `docs\relay.json` — append-only, CAS-guarded |
| What stops it | nothing stops it | acceptance criteria, `max_stages`, write-set rules, human checkpoints |
| Can it resume | only by re-reading everything | resume from the ledger |

Concretely, installing the kit gives the target repository:

- **a launcher** — validates the workspace, runs the concurrency gates, takes the lock, creates the ledger (never overwrites it), and writes the next-stage prompt;
- **an atomic lock** — `FileMode.CreateNew`, so two sessions can never hold the same project;
- **a ledger write gate** — lock + compare-and-swap (`sha256`) + append-only invariant + read-back after write + a session trail the gate fills in by itself;
- **a protocol** (`docs\AGENT-RELAY.md`), an **operating procedure** (`docs\RELAY-SOP.md`) and a **per-project decision skeleton** (`docs\RELAY-ADAPTATION.md`);
- **a house-rules block** injected into the project's instruction file, idempotently, without duplicating or overwriting what the project already wrote;
- **an activation packet** — the exact four steps plus the one sentence a human says to start the chain.

---

## 2. Why it is worth it

- **Unattended by design, not by luck.** The chain advances only when the previous stage reached its acceptance criteria, wrote its evidence, and appended its result to the ledger. "It stopped" always has a reason in `docs\relay.json`, not a feeling.
- **Safe to run while you sleep.** Four gates stand between "the model wants to continue" and "the model writes": the atomic lock, the ledger gate, the write-set fingerprint, and CAS on write-back. A stale view cannot silently overwrite a fresher one.
- **Auditable.** Every stage leaves a ledger entry, a stage document and a lock heartbeat. The evidence is on disk, not in a transcript.
- **Portable across agent runtimes.** The same kit runs on MCode, Claude Code, Codex CLI and OpenClaw. One command picks the runtime; the house rules and the way the next link starts are adapted for you.
- **Zero resident processes.** Nothing runs in the background between turns. The chain lives entirely in files plus the agent session that is currently holding the lock.

---

## 3. Install and deploy

### 3.1 Requirements

- PowerShell 7 (`pwsh`) — Windows, Linux or macOS.
- A **git repository** — the launcher refuses to start a chain anywhere else.
- A plan document describing the stages, or let the installer create one.

### 3.2 Install into a target project

The tool is published as a global skill at `<MCode data dir>\skills\agentask-relay\`
(on Windows: `%USERPROFILE%\.minimax\.minimax\skills\agentask-relay\`). This
repository is its source of truth and working copy.

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File "<skill>\scripts\install-relay.ps1" `
  -RepoRoot "<absolute path of the target repo>" `
  -Target "<this round's goal batch>" `
  -Runtime mcode `
  [-PlanDoc "<plan document path, repo-relative>"] `
  [-StageTitles "1. scope;2. build;3. verify;4. closeout"] `
  [-MaxStages 6] [-WorkspaceDir "<repo root>"] [-TtlSeconds 1800] [-Force]
```

Exit codes: `0` installed, `2` invalid parameters or workspace, `5` self-check failed.
A dry run of the launcher is run at the end; its result is recorded but does not
change the install exit code.

### 3.3 Pick the runtime

`-Runtime` decides **where the house rules land** and **how the next link starts**.

| `-Runtime` | House rules go to | Next link starts with | Needs the spawn driver |
|---|---|---|---|
| `mcode` (default) | `AGENTS.md` | the built-in `session_create` tool | no |
| `claude-code` | `AGENTS.md` **and** `CLAUDE.md` | a headless `claude -p` child process | yes |
| `codex` | `AGENTS.md` | a headless `codex exec` child process | yes |
| `openclaw` | `AGENTS.md` | the runtime's own `sessions_spawn` tool | no (lock hand-over stays manual) |

An unknown runtime fails loudly (`FAIL reason=runtime_unsupported`, exit `2`) —
it never silently falls back to the default.

> **Why Claude Code needs two files.** Claude Code reads `CLAUDE.md`, and only
> falls back to `AGENTS.md` when the repository has no `CLAUDE.md`. A repository
> that already ships a `CLAUDE.md` would therefore shadow the whole relay block:
> the kit would look installed while the chain never starts. The installer
> writes both files for `claude-code` and prints `AGENTS_MARKERS begin=1 end=1`
> and `CLAUDE_MARKERS begin=1 end=1` so you can verify it.
>
> **OpenClaw hard constraint.** OpenClaw injects only the `AGENTS.md` at the root
> of *its own workspace*. The target repository must be that workspace, or the
> house-rules block has to be copied there.

Per-runtime deployment guides (prerequisites, activation, how to tell it worked,
the traps):

- `tool\references\deployment-claude-code.md`
- `tool\references\deployment-codex.md`
- `tool\references\deployment-openclaw.md`
- `tool\references\runtime-portability-2026-11-25.md` — the full four-runtime analysis

### 3.4 Two things you must do after installing

1. **Fill in the TODO sections of `docs\RELAY-ADAPTATION.md`** — the write set
   (which directories may change, which must not), the acceptance gate commands
   and what "green" means, and the model policy. Without this the chain stops in
   its first stage with "write set unknown".
2. **Activate inside the target project.** The right to start a chain belongs to
   the target project, never to an outside supervisor session.

```
follow docs\relay\ACTIVATION-PROMPT.txt to start the relay chain
```

The activation packet contains four fixed steps: run the launcher, start the
first link, hand the lock over (`relay-lock.ps1 -Action adopt`), and read the
new session back to verify it. On any failure: release the lock and report
honestly — never retry starting a link.

### 3.5 The launcher's exit code decides everything

| Exit | Meaning | Start a link? |
|---|---|---|
| `0` | all gates passed, next prompt generated | yes |
| `2` | invalid workspace, or the plan document could not be resolved | **no** |
| `3` | a chain is already running, a stage is `in_progress`, or the ledger is blocked / exhausted | **no** |
| `4` | the lock is held by another session | **no** |

The plan document is resolved before the lock is taken: explicit `-PlanDoc` →
ledger `plan_doc` → probing `docs\plan-*.md`, `docs\plans\*.md`,
`docs\superpowers\plans\*.md`. One hit is used; several hits warn and the
newest by mtime wins; zero hits means exit `2`. **A plan document is never
created just to satisfy chain start.**

---

## 4. What installation leaves in the target repository

- `docs\relay\start-relay.ps1` — launcher
- `docs\relay\relay-lock.ps1` — atomic lock
- `docs\relay\relay-ledger.ps1` — ledger write gate (lock + CAS + append-only + read-back + session trail)
- `docs\relay\relay-spawn.ps1` — spawn driver (CLI runtimes only; dry run by default, `-Execute` to run)
- `docs\AGENT-RELAY.md`, `docs\RELAY-SOP.md`, `docs\RELAY-ADAPTATION.md` — protocol / procedure / project decisions
- `docs\relay\ACTIVATION-PROMPT.txt`, `docs\relay\install-report.md` — activation packet / install report
- `docs\plan-relay.md` — a plan document, generated only when no existing plan is found
- a house-rules block in `AGENTS.md` (and `CLAUDE.md` for `claude-code`), delimited by `<!-- BEGIN RELAY-PORT -->` / `<!-- END RELAY-PORT -->`

**`docs\relay.json` (the ledger) is created by the launcher when the chain
starts. The installer never writes it.**

An existing relay section is **absorbed** (wrapped in the markers, text kept
verbatim) rather than duplicated — by title criterion first, then by a
content-fingerprint criterion. If two sections would qualify, the installer
refuses to guess, appends a managed block and warns
`WARN agents_relay_section_ambiguous matches=N`.

---

## 5. Repository map

| Path | Contents |
|---|---|
| `tool/` | **the tool body** — installer, templates (device scripts, protocol, activation packets), evidence |
| `device/` | device bodies `start-relay.ps1` / `relay-lock.ps1` / `relay-ledger.ps1` / `relay-spawn.ps1` + a design-sample ledger |
| `protocol/` | the shared protocol layer, mirrored byte-for-byte from `tool\templates\AGENT-RELAY.md` |
| `examples/practilog/` | a production landing site: real ledger, project decision record, chain artifacts, gate evidence |
| `scripts/` | **this repository's own maintenance scripts** (not shipped): `selftest.ps1`, `publish-relay.ps1`, `refresh-manifest.ps1` |
| `MANIFEST.txt` | every file as `<sha16>` / `<bytes>` / `<relative path>`; refresh with `scripts\refresh-manifest.ps1`, always as the **last** step |
| `HANDOFF.md` | handoff: background / progress / verified / inferred / unverified / evidence paths / backlog / tool pitfalls |
| `AGENTS.md` | this project's house rules |

---

## 6. Maintaining the tool

```powershell
# House rule 1: mandatory selftest after touching tool\ or device\.
# Builds throwaway git repos under %TEMP% and really runs installer / launcher / lock /
# ledger / encoding / byte-identity checks. Green = EXIT=0 and fail=0.
pwsh -NoProfile -File scripts\selftest.ps1 -EvidencePath "$env:TEMP\relay-selftest.log"

# Publishing: device<->templates hard invariant + per-file reconciliation between tool\
# and the global skill, in one shot.
pwsh -NoProfile -File scripts\publish-relay.ps1 -Direction verify    # report only
pwsh -NoProfile -File scripts\publish-relay.ps1 -Direction publish   # this repo -> global skill
```

The order is fixed: **selftest → publish → refresh-manifest** (the manifest
includes itself, so it goes last).

`examples\practilog\docs\relay\` is a historical evidence snapshot: it only
reports `SNAPSHOT_DRIFT`, takes no part in the verdict, and **must not** be
synced for its sake.

---

## 7. Status

- The kit is implemented and verified by `scripts\selftest.ps1` — cases 1–16,
  **135 assertions / 0 failures / `EXIT=0`**. The raw log and its note for each
  round live in `tool\references\selftest-*.txt` / `.md`.
- Fixed defects worth knowing about: **D1** an uninitialized output variable
  truncated the target `AGENTS.md` to 0 bytes; **D2** dry-run evidence was 0 B;
  **D3** CJK literals inside `.ps1` garbled under Windows PowerShell 5.1 without
  a BOM; **D4** the launcher's `-PlanDoc` default was a project-specific path.
- The runtime adaptation layer (B9) added `-Runtime`, the spawn driver
  `relay-spawn.ps1`, per-runtime activation packets and protocol §10.
- Not done: dogfooding the kit in this repository itself; a macOS/Linux
  execution audit (those paths are inferred, not executed); a model pre-flight
  check before starting a link. See the backlog in `HANDOFF.md`.
- Not covered by any automated run: a real chain activation — it depends on
  starting a new agent session, which the selftest never does.

---

## 8. Relationship with the global skill

| | Role | When to change |
|---|---|---|
| `tool\` (this repository) | working surface / source of truth / evolution spot | when changing the tool |
| `<MCode data dir>\skills\agentask-relay\` | the copy sessions actually load | after a change here passes the selftest, **sync it over** |

Sync with `scripts\publish-relay.ps1 -Direction publish`, which covers
`SKILL.md`, `scripts\`, `templates\`, `references\` and re-verifies every file.
After editing a device template, `device\` must be kept byte-identical
(`Copy-Item tool\templates\<f> device\<f> -Force`); otherwise
`publish-relay.ps1` fails the hard invariant outright.

---

## License

No license file has been added to this repository, so all rights are reserved by
default. Choosing a license is an open item on the backlog (see `HANDOFF.md`).
