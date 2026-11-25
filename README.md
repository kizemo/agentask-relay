# agentask-relay - engineering home of the unattended relay kit (`relay-port`)

[![selftest](https://github.com/kizemo/agentask-relay/actions/workflows/selftest.yml/badge.svg)](https://github.com/kizemo/agentask-relay/actions/workflows/selftest.yml)

<p align="left">
  <a href="./README.md"><img alt="English" src="https://img.shields.io/badge/lang-English-2ea44f?style=for-the-badge"/></a>
  <a href="./README.zh-CN.md"><img alt="Chinese (Simplified)" src="https://img.shields.io/badge/lang-Chinese_Simplified-0969da?style=for-the-badge"/></a>
</p>

[![selftest](https://github.com/kizemo/agentask-relay/actions/workflows/selftest.yml/badge.svg)](https://github.com/kizemo/agentask-relay/actions/workflows/selftest.yml)

**English** | [Chinese (Simplified)](./README.zh-CN.md)

[![selftest](https://github.com/kizemo/agentask-relay/actions/workflows/selftest.yml/badge.svg)](https://github.com/kizemo/agentask-relay/actions/workflows/selftest.yml)

This directory is the **evolvable engineering surface** for one tool: installing an
"unattended relay chain" into any git project, so that a single prompt starts a
self-advancing chain of sessions with one writer per stage.

[![selftest](https://github.com/kizemo/agentask-relay/actions/workflows/selftest.yml/badge.svg)](https://github.com/kizemo/agentask-relay/actions/workflows/selftest.yml)

The tool itself is also published as a global skill at
`<MCode data dir>\skills\relay-port\` (on Windows that is
`%USERPROFILE%\.minimax\.minimax\skills\relay-port\`). This repository is its
**source of truth / working copy**: edit here -> run the one-shot selftest ->
sync back to the global skill directory. Only after the sync does a new session
pick up the change.

[![selftest](https://github.com/kizemo/agentask-relay/actions/workflows/selftest.yml/badge.svg)](https://github.com/kizemo/agentask-relay/actions/workflows/selftest.yml)

## Tool in one line

[![selftest](https://github.com/kizemo/agentask-relay/actions/workflows/selftest.yml/badge.svg)](https://github.com/kizemo/agentask-relay/actions/workflows/selftest.yml)

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File tool\scripts\install-relay.ps1 `
  -RepoRoot "<absolute repo path>" -Target "<this round's goal batch>" `
  [-PlanDoc "<plan document path>"] [-StageTitles "1. xxx;2. yyy"] [-MaxStages 6] `
  [-WorkspaceDir "<workspace dir>"] [-TtlSeconds 1800] [-Force] [-SkipVerify]
```

[![selftest](https://github.com/kizemo/agentask-relay/actions/workflows/selftest.yml/badge.svg)](https://github.com/kizemo/agentask-relay/actions/workflows/selftest.yml)

`-PlanDoc` **may be omitted**. When it is not given, the plan document is resolved
in this order: explicit `-PlanDoc` -> ledger `plan_doc` -> probing
`docs\plan-*.md`, `docs\plans\*.md`, `docs\superpowers\plans\*.md`. Exactly one hit is
used; multiple hits emit a `WARN` and the newest by mtime wins; zero hits means
`exit 2` and the chain refuses to start. Installation and chain start share the same
list, so there is no "install first, then hand-type the plan path".
**A plan document is never created just to satisfy chain start.**

[![selftest](https://github.com/kizemo/agentask-relay/actions/workflows/selftest.yml/badge.svg)](https://github.com/kizemo/agentask-relay/actions/workflows/selftest.yml)

After installation, say one sentence **inside the target project** to start the chain:

[![selftest](https://github.com/kizemo/agentask-relay/actions/workflows/selftest.yml/badge.svg)](https://github.com/kizemo/agentask-relay/actions/workflows/selftest.yml)

```
start the relay chain per docs\relay\ACTIVATION-PROMPT.txt
```

[![selftest](https://github.com/kizemo/agentask-relay/actions/workflows/selftest.yml/badge.svg)](https://github.com/kizemo/agentask-relay/actions/workflows/selftest.yml)

The launcher's exit code decides whether you may start a link at all:

[![selftest](https://github.com/kizemo/agentask-relay/actions/workflows/selftest.yml/badge.svg)](https://github.com/kizemo/agentask-relay/actions/workflows/selftest.yml)

| Exit | Meaning | Start a session? |
|---|---|---|
| `0` | all gates passed, next prompt generated | yes |
| `2` | invalid workspace (or plan document unresolved, ledger gate missing) | **no** |
| `3` | a chain is already running / a stage is `in_progress` / `blocked` / stages exhausted | **no** |
| `4` | the lock is held by another session | **no** |

[![selftest](https://github.com/kizemo/agentask-relay/actions/workflows/selftest.yml/badge.svg)](https://github.com/kizemo/agentask-relay/actions/workflows/selftest.yml)

Activation is four fixed steps (written into `docs\relay\ACTIVATION-PROMPT.txt`):
run the launcher -> `session_create` with only `agent_name` / `title` /
`workspace_dir` (backslash absolute path) / `model` / `content` (never `effort`,
`defer_first_turn`, or `parent_session_id`) -> `relay-lock.ps1 -Action adopt` with the new
session id -> read the session back to verify `workspace_dir` / model / status. On any
failure: `-Action release` and report honestly instead of retrying.

[![selftest](https://github.com/kizemo/agentask-relay/actions/workflows/selftest.yml/badge.svg)](https://github.com/kizemo/agentask-relay/actions/workflows/selftest.yml)

## What installation leaves in the target repository

[![selftest](https://github.com/kizemo/agentask-relay/actions/workflows/selftest.yml/badge.svg)](https://github.com/kizemo/agentask-relay/actions/workflows/selftest.yml)

- `docs\relay\start-relay.ps1` + `docs\relay\relay-lock.ps1` + `docs\relay\relay-ledger.ps1`
  - the device, byte-identical to `device\`. Ledger write-back must **only** go through
  `relay-ledger.ps1` (lock + CAS + append-only + read-back), never a bare `Set-Content`.
- `docs\AGENT-RELAY.md` + `docs\RELAY-SOP.md` + `docs\RELAY-ADAPTATION.md`
  - protocol / operating procedure / per-project decision skeleton.
- A house-rules block in `AGENTS.md` delimited by `<!-- BEGIN RELAY-PORT -->`, injected
  idempotently. An existing block is **absorbed** (with markers added) rather than
  duplicated; an equivalent paragraph whose title lacks the word "relay" is now also
  recognized by the content-fingerprint criterion.
- `docs\plan-relay.md` - a plan document, generated only when no existing plan is found.
- `docs\relay\ACTIVATION-PROMPT.txt` and `docs\relay\install-report.md`.

[![selftest](https://github.com/kizemo/agentask-relay/actions/workflows/selftest.yml/badge.svg)](https://github.com/kizemo/agentask-relay/actions/workflows/selftest.yml)

**`docs\relay.json` (the ledger) is created by the launcher at the moment the chain starts.
The installer never writes it.**

[![selftest](https://github.com/kizemo/agentask-relay/actions/workflows/selftest.yml/badge.svg)](https://github.com/kizemo/agentask-relay/actions/workflows/selftest.yml)

Four concurrency gates protect the chain: an atomic lock (`FileMode.CreateNew`), the
ledger gate (refuses to start when a stage is `in_progress`, when `running` already has a
`next_session_id`, when blocked, or when stages are exhausted), a write-set fingerprint
(`git status --porcelain -uall` + `HEAD` + target file fingerprints), and CAS on write-back
(re-read from disk, compare `sha256`, append only).

[![selftest](https://github.com/kizemo/agentask-relay/actions/workflows/selftest.yml/badge.svg)](https://github.com/kizemo/agentask-relay/actions/workflows/selftest.yml)

## Directory map

[![selftest](https://github.com/kizemo/agentask-relay/actions/workflows/selftest.yml/badge.svg)](https://github.com/kizemo/agentask-relay/actions/workflows/selftest.yml)

| Path | Contents | Origin |
|---|---|---|
| `tool/` | **the tool body** (relay-port skill source): installer + 6 templates + manual + selftest evidence | `skills\relay-port\` |
| `device/` | device bodies `start-relay.ps1` / `relay-lock.ps1` / `relay-ledger.ps1` + a design-sample ledger `relay.json` | PractiLog field version + `maintenance\relay\` |
| `protocol/` | shared protocol layer: general protocol / SOP / relay prompt / pointer / evidence-driven notes (5 files) | `maintenance\relay\` |
| `protocol/probe-ws/` | **real-chain probe on a generic repository** - complete artifacts of a 3-link run that was not executed in the PractiLog repo (5 files) | `maintenance\relay\probe-ws\` |
| `examples/practilog/` | production landing site: full 22-key ledger + a project decision record + 6-link chain artifacts + gate and supervision evidence + the extracted relay section of its `AGENTS.md` | the PractiLog repository |
| `scripts/` | **this repository's own maintenance scripts** (not the tool body): `selftest.ps1`, `publish-relay.ps1`, `refresh-manifest.ps1` | written here |
| `MANIFEST.txt` | every file as `<sha16> \| <bytes> \| <relative path>`; entry count = file count - 1 (excludes itself). Refresh with `pwsh -File scripts\refresh-manifest.ps1`, always as the **last step** of a round | generated here |
| `HANDOFF.md` | handoff: background / progress / verified / inferred / unverified / evidence paths / candidate backlog / tool pitfalls | written here |
| `AGENTS.md` | this project's house rules | written here |

[![selftest](https://github.com/kizemo/agentask-relay/actions/workflows/selftest.yml/badge.svg)](https://github.com/kizemo/agentask-relay/actions/workflows/selftest.yml)

All file and directory names are ASCII, so the repository listing contains no non-ASCII
entries in either README.

[![selftest](https://github.com/kizemo/agentask-relay/actions/workflows/selftest.yml/badge.svg)](https://github.com/kizemo/agentask-relay/actions/workflows/selftest.yml)

## The two one-shot scripts in this repository

[![selftest](https://github.com/kizemo/agentask-relay/actions/workflows/selftest.yml/badge.svg)](https://github.com/kizemo/agentask-relay/actions/workflows/selftest.yml)

```powershell
# House rule 1: mandatory selftest. Creates a throwaway git repo under %TEMP%, really runs
# installer / launcher / lock (install, idempotent re-run, absorption, -PlanDoc resolution,
# real activation, second start refused, lock mutual exclusion). Green = EXIT=0 and fail=0.
pwsh -NoProfile -File scripts\selftest.ps1 -EvidencePath "$env:TEMP\relay-selftest.log"

[![selftest](https://github.com/kizemo/agentask-relay/actions/workflows/selftest.yml/badge.svg)](https://github.com/kizemo/agentask-relay/actions/workflows/selftest.yml)

# Publishing: device<->templates hard invariant + per-file sha16 reconciliation between
# tool\ and the global skill. Sync and verification in one shot.
pwsh -NoProfile -File scripts\publish-relay.ps1 -Direction verify    # report only
pwsh -NoProfile -File scripts\publish-relay.ps1 -Direction publish   # this dir -> global skill
```

[![selftest](https://github.com/kizemo/agentask-relay/actions/workflows/selftest.yml/badge.svg)](https://github.com/kizemo/agentask-relay/actions/workflows/selftest.yml)

`examples\practilog\docs\relay\` is a historical evidence snapshot: it only reports
`SNAPSHOT_DRIFT`, takes no part in the verdict, and **must not** be synced for its sake.

[![selftest](https://github.com/kizemo/agentask-relay/actions/workflows/selftest.yml/badge.svg)](https://github.com/kizemo/agentask-relay/actions/workflows/selftest.yml)

## Current status

[![selftest](https://github.com/kizemo/agentask-relay/actions/workflows/selftest.yml/badge.svg)](https://github.com/kizemo/agentask-relay/actions/workflows/selftest.yml)

- Every file was copied into this directory with per-file sha16 matching its source
  (`SHA_MATCH=42 / SHA_MISMATCH=0`). Across the whole repository:
  `BOM=0`, non-ASCII `.ps1=0`, `CR=0` in `.md` and `.txt`. Reconciliation lives in
  `MANIFEST.txt`.
- The tool is implemented and verified end to end. The first batch of 14 cases passed
  (`tool\references\selftest-2026-11-25.md`); batches B2/B3 add assertion suites recorded as
  `selftest-2026-11-25-b2.md` and `-b3.md` with raw logs alongside them.
- Fixed defects: **D1** an uninitialized output variable in the idempotent branch truncated
  the target project's `AGENTS.md` to 0 bytes; **D2** dry-run evidence was 0 B; **D3** CJK
  literals inside installer `.ps1` files would garble under Windows PowerShell 5.1 without a
  BOM (now built from code points, retested `NON_ASCII=0 / PARSE_ERRORS=0`);
  **D4** the launcher's `-PlanDoc` default was a PractiLog-specific path (replaced by the
  resolution chain above, with an explicit error instead of a silent fallback).
- Batch B3 added the **ledger write gate** `relay-ledger.ps1` (`-Action status` / `-Action commit`):
  lock + CAS + append-only invariant + read-back. Every ledger write-back recipe points at it.
- The repository is under git now and published to
  [github.com/kizemo/agentask-relay](https://github.com/kizemo/agentask-relay).
- Still not done: **dogfood** - installing `relay-port` into this repository itself so the
  tool's own backlog advances by chain; cross-platform audit (macOS/Linux paths are inferred,
  not executed); a model pre-flight check before starting a link. See the candidate backlog in
  `HANDOFF.md`.
- Not verified by any automated run: real chain activation depends on `session_create`, which
  the selftest never calls - it asserts the generated activation package instead.

[![selftest](https://github.com/kizemo/agentask-relay/actions/workflows/selftest.yml/badge.svg)](https://github.com/kizemo/agentask-relay/actions/workflows/selftest.yml)

## Relationship with the global skill

[![selftest](https://github.com/kizemo/agentask-relay/actions/workflows/selftest.yml/badge.svg)](https://github.com/kizemo/agentask-relay/actions/workflows/selftest.yml)

| | Role | When to change |
|---|---|---|
| `tool\` (this repository) | working surface / source of truth / evolution spot | when changing the tool |
| `<MCode data dir>\skills\relay-port\` | the copy sessions actually load | after a change here passes the selftest, **sync it over** |

[![selftest](https://github.com/kizemo/agentask-relay/actions/workflows/selftest.yml/badge.svg)](https://github.com/kizemo/agentask-relay/actions/workflows/selftest.yml)

Sync with `scripts\publish-relay.ps1 -Direction publish`, which covers `SKILL.md`,
`scripts\`, `templates\`, `references\` and re-verifies every file. After editing a device
template, `device\` must be kept byte-identical
(`Copy-Item tool\templates\<f> device\<f> -Force`); otherwise `publish-relay.ps1` fails the
hard invariant outright.

[![selftest](https://github.com/kizemo/agentask-relay/actions/workflows/selftest.yml/badge.svg)](https://github.com/kizemo/agentask-relay/actions/workflows/selftest.yml)

## License

[![selftest](https://github.com/kizemo/agentask-relay/actions/workflows/selftest.yml/badge.svg)](https://github.com/kizemo/agentask-relay/actions/workflows/selftest.yml)

No license file has been added to this repository, so all rights are reserved by default.
Choosing a license is an open item on the backlog (see `HANDOFF.md`).
