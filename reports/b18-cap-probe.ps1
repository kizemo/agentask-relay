$ErrorActionPreference = 'Stop'

# B18-c: the chain_at_stage_cap branch, exercised on the REAL device with a REAL
# ledger, and the wording of its refusal line.
#
# Part 1 (fault injection): the state is produced through the SANCTIONED write
# gate (relay-ledger.ps1 -Action commit with CAS), never by hand. This is fault
# injection, not an unattended chain: the point is to prove the refusal on a
# ledger that the real launcher and the real gate produced.
#
# Part 2 (wording probe): a chain that declares ONE stage. After the launcher
# bootstraps it, current_stage (1) already equals max_stages (1), so the cap
# predicate fires while that only stage is still pending. The refusal is still
# correct (do not start a second chain), but the hint must not claim that every
# stage is done.
#
# Pure ASCII, no BOM. Writes only to %TEMP% and to reports\.

$repoRoot = 'F:\soft\00selfmade\agentask-relay'
$installer = Join-Path $repoRoot 'tool\scripts\install-relay.ps1'
$outDir = Join-Path $repoRoot 'reports'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$script:root = Join-Path $env:TEMP ('relay-b18-cap-' + $stamp)
New-Item -ItemType Directory -Path $script:root -Force | Out-Null
$script:lines = New-Object System.Collections.Generic.List[string]

function Say([string]$s) { Write-Output $s }

function New-Kit([string]$Name, [int]$MaxStages) {
  $dir = Join-Path $script:root $Name
  New-Item -ItemType Directory -Path (Join-Path $dir 'docs\relay') -Force | Out-Null
  New-Item -ItemType Directory -Path (Join-Path $dir 'docs\plans') -Force | Out-Null
  $plan = '# plan' + "`n`n" + '1. first stage' + "`n" + '2. second stage' + "`n"
  [IO.File]::WriteAllText((Join-Path $dir 'docs\plans\cap.md'), $plan, (New-Object Text.UTF8Encoding($false)))
  & git -C $dir init -q 2>&1 | Out-Null
  & git -C $dir add -A 2>&1 | Out-Null
  & git -C $dir -c user.email=t@t -c user.name=t commit -qm init 2>&1 | Out-Null
  $answers = '{
  "schema": "relay-port/adaptation-answers@1",
  "write_set_allow": ["docs/", "src/"],
  "write_set_deny": [],
  "concurrency_check": "pwsh -NoProfile -ExecutionPolicy Bypass -File docs\\relay\\relay-lock.ps1 -Action status",
  "gate_command": "pwsh -NoProfile -ExecutionPolicy Bypass -File docs\\relay\\relay-ledger.ps1 -Action status",
  "gate_verdict_field": "LEDGER_STATE status=running",
  "model_primary": "minimax/MiniMax-M3",
  "model_fallback_day": "custom_provider:provider-aa5659/auto",
  "model_fallback_night": "custom_provider:provider-aa5659/deepseek-v4.1-flash-1017",
  "confirmed_by": "defaults-accepted-for-throwaway-fixture",
  "confirmed_at": "2026-11-26"
}'
  [IO.File]::WriteAllText((Join-Path $dir 'docs\adaptation-answers.json'), $answers, (New-Object Text.UTF8Encoding($false)))
  & pwsh -NoProfile -ExecutionPolicy Bypass -File $installer -RepoRoot $dir -Target 'B18 cap probe' -PlanDoc 'docs\plans\cap.md' -MaxStages $MaxStages -Runtime mcode -AnswersFile 'docs\adaptation-answers.json' *>&1 | Out-Null
  $script:lines.Add(('KIT ' + $Name + ' install_exit=' + $LASTEXITCODE))
  return $dir
}

function Get-Ledger([string]$Dir) {
  $p = Join-Path $Dir 'docs\relay.json'
  if (-not (Test-Path -LiteralPath $p)) { return $null }
  return (Get-Content -LiteralPath $p -Raw -Encoding UTF8 | ConvertFrom-Json)
}

function Stage-Statuses([string]$Dir) {
  $L = Get-Ledger $Dir
  if ($null -eq $L) { return 'NO_LEDGER' }
  $parts = @()
  foreach ($s in @($L.stages)) { $parts += ([string]$s.id) + ':' + ([string]$s.status) }
  return ($parts -join ',')
}

function Launch([string]$Dir, [int]$MaxStages, [string]$Tag) {
  $log = Join-Path $outDir ('b18-cap-' + $Tag + '.log')
  & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Dir 'docs\relay\start-relay.ps1') -Target 'B18 cap probe' -MaxStages $MaxStages -Runtime mcode -PlanDoc 'docs\plans\cap.md' *>&1 | Tee-Object -FilePath $log | Out-Null
  $code = $LASTEXITCODE
  $text = ''
  if (Test-Path -LiteralPath $log) { $text = Get-Content -LiteralPath $log -Raw }
  $reason = 'NONE'
  foreach ($r in @('stage_in_progress', 'chain_already_running', 'chain_at_stage_cap', 'chain_exhausted', 'ledger_blocked', 'lock_unavailable')) {
    if ($text -match [regex]::Escape($r)) { $reason = $r; break }
  }
  $script:lines.Add(('LAUNCH ' + $Tag + ' exit=' + $code + ' reason=' + $reason))
  foreach ($line in @($text -split "`n")) {
    if ($line -match 'FAIL reason=|HINT=') { $script:lines.Add(('  2ND> ' + $line.Trim())) }
  }
  return @{ Exit = $code; Reason = $reason; Text = $text }
}

# =====================================================================================
# Part 1: fault injection through the sanctioned gate.
# =====================================================================================
Say '=== PART 1: injected "at cap, not closed" state (2 stages) ==='
$dir1 = New-Kit 'cap-two-stages' 2
$first1 = Launch $dir1 2 'part1-first'
Say ('PART1_FIRST_LAUNCH exit=' + $first1.Exit + ' (expect 0: the chain can start)')
$L1 = Get-Ledger $dir1
Say ('PART1_LEDGER_BEFORE status=' + $L1.status + ' current_stage=' + $L1.current_stage + ' max_stages=' + $L1.max_stages + ' stages=' + (Stage-Statuses $dir1))

# release the lock so that only the ledger gate can refuse the next launch
& pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $dir1 'docs\relay\relay-lock.ps1') -Action release *>&1 | Out-Null
Say ('PART1_LOCK_RELEASE exit=' + $LASTEXITCODE)

# read the on-disk sha through the sanctioned gate, then commit the injection
$statusLine = & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $dir1 'docs\relay\relay-ledger.ps1') -Action status 2>&1 | ForEach-Object { $_.ToString() }
$sha = ''
foreach ($line in @($statusLine)) { if ($line -match 'sha256=([0-9a-f]{64})') { $sha = $Matches[1] } }
Say ('PART1_GATE_SHA len=' + $sha.Length)
if ($sha.Length -ne 64) { Say 'FAIL part1_sha_missing'; exit 2 }
$patch = Join-Path $dir1 'docs\relay\cap-patch.json'
[IO.File]::WriteAllText($patch, '{ "bump_current_stage": true }', (New-Object Text.UTF8Encoding($false)))
& pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $dir1 'docs\relay\relay-ledger.ps1') -Action commit -ExpectSha256 $sha -Patch $patch *>&1 | ForEach-Object { $script:lines.Add(('  GATE> ' + $_.ToString())) }
Say ('PART1_COMMIT_EXIT=' + $LASTEXITCODE)
$L1b = Get-Ledger $dir1
Say ('PART1_LEDGER_AFTER status=' + $L1b.status + ' current_stage=' + $L1b.current_stage + ' max_stages=' + $L1b.max_stages + ' stages=' + (Stage-Statuses $dir1))

$second1 = Launch $dir1 2 'part1-second'
$part1Ok = ($second1.Exit -eq 3 -and $second1.Reason -eq 'chain_at_stage_cap')
Say ('PART1_VERDICT refused_with_cap_reason=' + $part1Ok)

# =====================================================================================
# Part 2: a one stage chain, where the cap predicate is already true at bootstrap.
# =====================================================================================
Say ''
Say '=== PART 2: one stage chain, cap predicate already true while the stage is pending ==='
$dir2 = New-Kit 'cap-one-stage' 1
$first2 = Launch $dir2 1 'part2-first'
Say ('PART2_FIRST_LAUNCH exit=' + $first2.Exit + ' (expect 0: a one stage chain must still start)')
$L2 = Get-Ledger $dir2
Say ('PART2_LEDGER_BEFORE status=' + $L2.status + ' current_stage=' + $L2.current_stage + ' max_stages=' + $L2.max_stages + ' stages=' + (Stage-Statuses $dir2))
& pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $dir2 'docs\relay\relay-lock.ps1') -Action release *>&1 | Out-Null
$second2 = Launch $dir2 1 'part2-second'
Say ('PART2_SECOND_LAUNCH exit=' + $second2.Exit + ' reason=' + $second2.Reason)
$hintSaysDone = ($second2.Text -match 'every declared stage is done')
Say ('PART2_HINT_CLAIMS_ALL_DONE=' + $hintSaysDone + ' (a pending stage means this claim is false)')

foreach ($l in $script:lines) { Say $l }
Say ''
Say ('ROOT=' + $script:root)
if ($part1Ok) { exit 0 } else { exit 3 }
