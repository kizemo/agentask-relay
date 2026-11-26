$ErrorActionPreference = 'Stop'

# One-off fixture builder for the B17 real-chain retest.
# Pure ASCII on purpose (house rule 4). Writes only to $env:TEMP.

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$root  = Join-Path $env:TEMP ("relay-b17-e2e-" + $stamp)
$repo  = Join-Path $root 'repo'
$relay = Join-Path $repo 'docs\relay'

New-Item -ItemType Directory -Path (Join-Path $repo 'docs') -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $repo 'src')  -Force | Out-Null

$plan = @'
# Plan b17 - real chain retest (two stages)

Goal: exercise the CURRENT relay-port templates end to end on a throwaway repo.
The chain must produce two artifacts and stop by itself.

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
[IO.File]::WriteAllText((Join-Path $repo 'docs\plan-b17.md'), $plan, [Text.UTF8Encoding]::new($false))

$readme = @'
# b17 fixture

Throwaway repository for the relay-port real-chain retest.
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
& git -C $repo -c user.name='relay-fixture' -c user.email='relay@example.invalid' commit -q -m 'fixture: b17 plan and sources'
if ($LASTEXITCODE -ne 0) { Write-Output "FAIL git_commit exit=$LASTEXITCODE"; exit 2 }
Write-Output ("OK fixture repo=" + $repo)
Write-Output ("OK fixture head=" + (& git -C $repo rev-parse --short HEAD))

$installer = 'F:\soft\00selfmade\agentask-relay\tool\scripts\install-relay.ps1'
$target    = 'B17 real chain retest: stage 1 inventory, stage 2 summary'
$stages    = '1. inventory tracked files into docs\relay\stage-1-inventory.md;2. summarize into docs\relay\stage-2-inventory.md'

Write-Output '=== INSTALL PASS 1 (expect ADAPTATION_STATUS=pending) ==='
& pwsh -NoProfile -ExecutionPolicy Bypass -File $installer -RepoRoot $repo -Target $target -PlanDoc 'docs\plan-b17.md' -StageTitles $stages -MaxStages 2 -Runtime claude-code
Write-Output ("INSTALL1_EXIT=" + $LASTEXITCODE)

$answersSrc = Join-Path $env:TEMP 'relay-b13-e2e2-20261126-153941\repo\docs\relay\adaptation-answers.json'
if (-not (Test-Path -LiteralPath $answersSrc)) { Write-Output 'FAIL answers_source_missing'; exit 2 }
Copy-Item -LiteralPath $answersSrc -Destination (Join-Path $relay 'adaptation-answers.json') -Force

Write-Output '=== INSTALL PASS 2 (expect ADAPTATION_STATUS=confirmed) ==='
& pwsh -NoProfile -ExecutionPolicy Bypass -File $installer -RepoRoot $repo -Target $target -PlanDoc 'docs\plan-b17.md' -StageTitles $stages -MaxStages 2 -Runtime claude-code -AnswersFile 'docs\relay\adaptation-answers.json'
Write-Output ("INSTALL2_EXIT=" + $LASTEXITCODE)

Write-Output '=== LAUNCHER (real, expect exit 0) ==='
& pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $relay 'start-relay.ps1') -Target $target -MaxStages 2
Write-Output ("LAUNCH_EXIT=" + $LASTEXITCODE)

Write-Output ("E2E_ROOT=" + $root)