$ErrorActionPreference = 'Stop'

# B20 hint witness: the cap-gate HINT in the "every stage done, status still
# running" shape must not tell the reader to hand close a chain that the same
# run closes. The two wordings differ ONLY by the -AutoFinalize flag, so this
# script drives one fixture into that shape and runs the launcher twice.
#
#   without -AutoFinalize : HINT says "submit a patch {\"set_status\":\"done\"}"
#   with    -AutoFinalize : same token, no hand-close advice, AUTO_FINALIZED
#
# Both runs must keep the token all_stages_done_but_status_running, because the
# token names the ledger shape and the one-click selftest asserts on it.
#
# Pure ASCII on purpose (house rule 4). Writes only to $env:TEMP.

$repoRoot = 'F:\soft\00selfmade\agentask-relay'
$setupScript = Join-Path $repoRoot 'reports\b20-e2e-setup.ps1'
$script:fail = 0

function Log { param([string]$Line) Write-Host $Line }
function Chk {
  param([string]$Name, [bool]$Cond, [string]$Detail)
  if ($Cond) { Log ('PASS ' + $Name + ' ' + $Detail) }
  else { Log ('FAIL ' + $Name + ' ' + $Detail); $script:fail++ }
}
function Run([string]$Label, [string[]]$Argv) {
  $out = @(& pwsh -NoProfile -ExecutionPolicy Bypass @Argv 2>&1 | ForEach-Object { [string]$_ })
  $code = $LASTEXITCODE
  Log ('=== ' + $Label + ' exit=' + $code + ' ===')
  foreach ($line in $out) { Log $line }
  return [pscustomobject]@{ Code = $code; Lines = $out; Text = ($out -join "`n") }
}

# --- 1. a fresh fixture, still at its bootstrapped state ---------------------
$setup = Run 'SETUP' @('-File', $setupScript)
if ($setup.Text -notmatch 'SETUP_OK') { Log 'FAIL setup_did_not_finish'; exit 2 }
$repo = $null
$ledgerPath = $null
foreach ($line in $setup.Lines) {
  if ($line -match '^B20_REPO=(.+)$') { $repo = $Matches[1].Trim() }
  if ($line -match '^B20_LEDGER=(.+)$') { $ledgerPath = $Matches[1].Trim() }
}
Chk 'setup_paths' ($null -ne $repo -and $null -ne $ledgerPath) ('repo=' + $repo)
if ($null -eq $repo -or $null -eq $ledgerPath) { exit 2 }
$relay = Join-Path $repo 'docs\relay'
$launcher = Join-Path $relay 'start-relay.ps1'
$gate = Join-Path $relay 'relay-ledger.ps1'
$target = 'B20 auto finalize on a real chain: one stage, terminal flip left to the launcher'
$scratch = Join-Path $repo 'docs\relay'

# --- 2. drive the ledger into the shape under test, gate only ----------------
# No real link here: this witness tests the wording of a gate message, not the
# chain. Every write still goes through relay-ledger.ps1, never by hand.
function GateCommit([string]$Name, [string]$Json) {
  $st = @(& pwsh -NoProfile -ExecutionPolicy Bypass -File $gate -Action status 2>&1 | ForEach-Object { [string]$_ })
  $stateLine = @($st | Where-Object { $_ -match '^LEDGER_STATE ' })
  Chk ($Name + '_status_line') ($stateLine.Count -ge 1) ('lines=' + $stateLine.Count)
  $sha = ''
  if ($stateLine.Count -ge 1 -and $stateLine[0] -match ' sha256=([0-9A-Fa-f]{64})') { $sha = $Matches[1] }
  Chk ($Name + '_sha') ($sha.Length -eq 64) $sha
  $patch = Join-Path $scratch ($Name + '-patch.json')
  [IO.File]::WriteAllText($patch, $Json, [Text.UTF8Encoding]::new($false))
  $dry = Run ($Name + '_dryrun') @('-File', $gate, '-Action', 'commit', '-ExpectSha256', $sha, '-Patch', $patch, '-DryRun')
  Chk ($Name + '_dryrun_ok') ($dry.Code -eq 0 -and $dry.Text -match 'DRYRUN') ('exit=' + $dry.Code)
  $com = Run ($Name + '_commit') @('-File', $gate, '-Action', 'commit', '-ExpectSha256', $sha, '-Patch', $patch)
  Chk ($Name + '_commit_ok') ($com.Code -eq 0) ('exit=' + $com.Code)
}

GateCommit 'append' '{"append_stage":{"id":1,"title":"inventory tracked files","status":"pending"}}'
GateCommit 'finish' '{"stage_done":1,"bump_current_stage":true}'

$L = Get-Content -LiteralPath $ledgerPath -Raw -Encoding UTF8 | ConvertFrom-Json
Log ('SHAPE status=' + $L.status + ' current_stage=' + $L.current_stage + ' max_stages=' + $L.max_stages +
  ' stages=' + (($L.stages | ForEach-Object { [string]$_.id + '=' + $_.status }) -join ','))
Chk 'shape_is_the_target_one' ($L.status -eq 'running' -and [int]$L.current_stage -eq 2 -and [int]$L.max_stages -eq 1) 'running/2/1'

# --- 3. run A: no flag, the reader is told to close it by hand --------------
$a = Run 'LAUNCHER_PLAIN' @('-File', $launcher, '-Target', $target, '-MaxStages', '1')
Chk 'plain_exit3' ($a.Code -eq 3) ('exit=' + $a.Code)
Chk 'plain_token_kept' ($a.Text -match 'HINT=all_stages_done_but_status_running') 'shape token'
Chk 'plain_hand_close_advice' ($a.Text -match 'submit a patch') 'names the manual remedy'
Chk 'plain_no_finalize' (-not ($a.Text -match 'AUTO_FINALIZED')) 'off by default'
$L = Get-Content -LiteralPath $ledgerPath -Raw -Encoding UTF8 | ConvertFrom-Json
Chk 'plain_ledger_running' ($L.status -eq 'running') ('status=' + $L.status)

# --- 4. run B: same state, same flag the feature ships ----------------------
$b = Run 'LAUNCHER_AUTOFINALIZE' @('-File', $launcher, '-Target', $target, '-MaxStages', '1', '-AutoFinalize')
Chk 'auto_exit3' ($b.Code -eq 3) ('exit=' + $b.Code)
Chk 'auto_token_kept' ($b.Text -match 'HINT=all_stages_done_but_status_running') 'shape token unchanged'
Chk 'auto_no_hand_close_advice' (-not ($b.Text -match 'submit a patch')) 'the fix: no contradictory remedy'
Chk 'auto_names_itself' ($b.Text -match 'AutoFinalize closes it through relay-ledger') 'hint names the actor'
Chk 'auto_finalized' ($b.Text -match 'AUTO_FINALIZED status=done before=[0-9a-f]{64} after=[0-9a-f]{64}') 'still closes the chain'
Chk 'auto_hint_swapped' ($b.Text -match 'HINT=chain_closed_by_auto_finalize') 'closing hint present'
$L = Get-Content -LiteralPath $ledgerPath -Raw -Encoding UTF8 | ConvertFrom-Json
Chk 'auto_ledger_done' ($L.status -eq 'done') ('status=' + $L.status)

# --- 5. the pair is the evidence: one flag, one wording ---------------------
Chk 'witness_hints_differ' (($a.Text -match 'submit a patch') -and -not ($b.Text -match 'submit a patch')) 'same state, flag decides the remedy'

Log ('SUMMARY fail=' + $script:fail + ' repo=' + $repo)
if ($script:fail -gt 0) { exit 2 }
Write-Output 'WITNESS_OK'
exit 0