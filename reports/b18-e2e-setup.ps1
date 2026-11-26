$ErrorActionPreference = 'Stop'

# B18 fixture builder: real unattended chain on the MCODE runtime.
# Pure ASCII on purpose (house rule 4). Writes only to $env:TEMP.
# The chain itself is started by the controller, not by this script.

$modelKey = 'minimax/MiniMax-M3'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$root  = Join-Path $env:TEMP ("relay-b18-e2e-" + $stamp)
$repo  = Join-Path $root 'repo'
$relay = Join-Path $repo 'docs\relay'

New-Item -ItemType Directory -Path (Join-Path $repo 'docs') -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $repo 'src')  -Force | Out-Null

$plan = @'
# Plan b18 - real chain on the MCode runtime (two stages)

Goal: exercise the CURRENT relay-port templates end to end with the built-in
session_create tool as the link driver. The chain must produce two artifacts and
stop by itself, with no human in the loop.

## Stage 1
List the tracked files of this repository into docs/relay/stage-1-inventory.md,
with the byte size of every file and the total.

## Stage 2
Read stage 1 and write docs/relay/stage-2-inventory.md summarizing the inventory
(file count, largest file, total bytes) and state whether it matches stage 1.

## Acceptance
- docs/relay/stage-1-inventory.md exists and lists every tracked file.
- docs/relay/stage-2-inventory.md exists and is consistent with stage 1.
- No third stage: max_stages is 2.
'@
[IO.File]::WriteAllText((Join-Path $repo 'docs\plan-b18.md'), $plan, [Text.UTF8Encoding]::new($false))

$readme = @'
# b18 fixture

Throwaway repository for the relay-port MCode runtime real chain.
'@
[IO.File]::WriteAllText((Join-Path $repo 'README.md'), $readme, [Text.UTF8Encoding]::new($false))

$src = @'
param([string]$Path = '.')
Get-ChildItem -LiteralPath $Path -File -Recurse |
  Select-Object FullName, Length |
  Sort-Object Length -Descending
'@
[IO.File]::WriteAllText((Join-Path $repo 'src\inventory.ps1'), $src, [Text.UTF8Encoding]::new($false))

& git -C $repo init -q
& git -C $repo add -A
& git -C $repo -c user.name='relay-fixture' -c user.email='relay@example.invalid' commit -q -m 'fixture: b18 plan and sources'
if ($LASTEXITCODE -ne 0) { Write-Output "FAIL git_commit exit=$LASTEXITCODE"; exit 2 }
Write-Output ("OK fixture repo=" + $repo)

# The answers file lives outside docs\relay on purpose: docs\relay does not exist
# yet at this point, the installer creates it in pass 1.
$answersPath = Join-Path $repo 'docs\adaptation-answers.json'
$answers = @'
{
  "schema": "relay-port/adaptation-answers@1",
  "write_set_allow": ["docs/", "src/"],
  "write_set_deny": [
    ".github/workflows/",
    "**/.env*",
    "**/*.key",
    "**/*.pem",
    "**/*.pfx",
    "scripts/publish-*",
    "scripts/release-*",
    "scripts/deploy-*",
    "scripts/sign-*",
    "**/gate*.ps1",
    "docs/relay/*.ps1"
  ],
  "concurrency_check": "pwsh -NoProfile -ExecutionPolicy Bypass -File docs\\relay\\relay-lock.ps1 -Action status",
  "gate_command": "pwsh -NoProfile -ExecutionPolicy Bypass -File docs\\relay\\relay-ledger.ps1 -Action status",
  "gate_verdict_field": "LEDGER_STATE status=running",
  "model_primary": "MODEL_KEY_PLACEHOLDER",
  "model_fallback_day": "custom_provider:provider-aa5659/auto",
  "model_fallback_night": "custom_provider:provider-aa5659/deepseek-v4.1-flash-1017",
  "confirmed_by": "defaults-accepted-for-throwaway-fixture",
  "confirmed_at": "2026-11-26"
}
'@
$answers = $answers.Replace('MODEL_KEY_PLACEHOLDER', $modelKey)
[IO.File]::WriteAllText($answersPath, $answers, [Text.UTF8Encoding]::new($false))

$installer = 'F:\soft\00selfmade\agentask-relay\tool\scripts\install-relay.ps1'
$target    = 'B18 real chain on the MCode runtime: stage 1 inventory, stage 2 summary'
$stages    = '1. inventory tracked files into docs\relay\stage-1-inventory.md;2. summarize into docs\relay\stage-2-inventory.md'

Write-Output '=== INSTALL PASS 1 (expect ADAPTATION_STATUS=pending) ==='
& pwsh -NoProfile -ExecutionPolicy Bypass -File $installer -RepoRoot $repo -Target $target -PlanDoc 'docs\plan-b18.md' -StageTitles $stages -MaxStages 2 -Runtime mcode
Write-Output ("INSTALL1_EXIT=" + $LASTEXITCODE)

Write-Output '=== INSTALL PASS 2 (expect ADAPTATION_STATUS=confirmed) ==='
& pwsh -NoProfile -ExecutionPolicy Bypass -File $installer -RepoRoot $repo -Target $target -PlanDoc 'docs\plan-b18.md' -StageTitles $stages -MaxStages 2 -Runtime mcode -AnswersFile 'docs\adaptation-answers.json'
Write-Output ("INSTALL2_EXIT=" + $LASTEXITCODE)

Write-Output '=== LAUNCHER (real, expect exit 0) ==='
& pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $relay 'start-relay.ps1') -Target $target -MaxStages 2
Write-Output ("LAUNCH_EXIT=" + $LASTEXITCODE)

Write-Output '=== LEDGER (read back) ==='
$ledgerPath = Join-Path $repo 'docs\relay.json'
if (Test-Path -LiteralPath $ledgerPath) {
  $L = Get-Content -LiteralPath $ledgerPath -Raw -Encoding UTF8 | ConvertFrom-Json
  Write-Output ('LEDGER status=' + $L.status + ' current_stage=' + $L.current_stage + ' max_stages=' + $L.max_stages)
  Write-Output ('LEDGER next_session_id=[' + $L.next_session_id + ']')
  Write-Output ('LEDGER workspace_dir=' + $L.workspace_dir)
  Write-Output ('LEDGER model_policy=' + $L.model_policy.preferred)
} else {
  Write-Output 'LEDGER_MISSING'
}

Write-Output '=== LOCK (read back) ==='
& pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $relay 'relay-lock.ps1') -Action status

$promptPath = Join-Path $relay 'next-relay-prompt.txt'
Write-Output ('PROMPT_PATH=' + $promptPath)
if (Test-Path -LiteralPath $promptPath) {
  Write-Output ('PROMPT_BYTES=' + (Get-Item -LiteralPath $promptPath).Length)
}
Write-Output ("E2E_ROOT=" + $root)
