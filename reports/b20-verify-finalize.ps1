param(
  [string]$Root = (Join-Path $env:TEMP 'relay-b20-e2e-20261126-223043'),
  [string]$ExpectPreSha = '29CB450E46AC43245BE835968A72A82146E876BADAFF4DF38B1E1F694FEBAD8A'
)

$ErrorActionPreference = 'Stop'

# B20 verifier: on the fixture built by reports\b20-e2e-setup.ps1 and advanced by
# one real relay link (or, for a rebuilt fixture, by reports\b21-rebuild-crash-shape.ps1),
# prove start-relay.ps1 -AutoFinalize closes the chain.
#
# Pre-state on disk:
#   status=running current_stage=2 max_stages=1 stages=[1:done] next_session_id=null
# That is the crash shape: cap reached, every stage done, terminal status never
# flipped. Checks, in order:
#   1. -DryRun must not write (sha256 unchanged) and must say skip=auto_finalize
#   2. -AutoFinalize must exit 3, print AUTO_FINALIZED with two distinct hex64
#      shas and the closing HINT, and CAS-write status=done
#   3. on-disk re-read must match, including updated_at moving forward
#   4. a second run must refuse with reason=chain_exhausted, not re-close
#
# The run log is written next to this script as b20-verify-finalize-run<N>.log,
# N one past the highest existing one, created with FileMode.CreateNew. A rerun
# therefore NEVER truncates an earlier record (B20 gap: the first PASS run was
# overwritten by the stale-state rerun and lost).
#
# -Root / -ExpectPreSha exist so the same verifier can run on a rebuilt fixture;
# omit them to re-check the original B20 fixture, which is already consumed and
# must answer STALE_STATE instead of seven red checks.
#
# Pure ASCII on purpose (house rule 4).

$root = $Root
$repo = Join-Path $root 'repo'
$relay = Join-Path $repo 'docs\relay'
$ledgerPath = Join-Path $repo 'docs\relay.json'
$launcher = Join-Path $relay 'start-relay.ps1'
$gate = Join-Path $relay 'relay-ledger.ps1'
$target = 'B20 auto finalize on a real chain: one stage, terminal flip left to the launcher'
$script:fail = 0

$seq = 1
while (Test-Path -LiteralPath (Join-Path $PSScriptRoot ('b20-verify-finalize-run' + $seq + '.log'))) { $seq++ }
$log = Join-Path $PSScriptRoot ('b20-verify-finalize-run' + $seq + '.log')
$logStream = [IO.File]::Open($log, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write)
$logStream.Close()
function Log { param([string]$Line) Write-Host $Line; [IO.File]::AppendAllText($log, $Line + "`n") }
function Chk {
  param([string]$Name, [bool]$Cond, [string]$Detail)
  if ($Cond) { Log ('PASS ' + $Name + ' ' + $Detail) }
  else { Log ('FAIL ' + $Name + ' ' + $Detail); $script:fail++ }
}
function Run([string]$Label, [string]$Exe, [string[]]$Argv) {
  $out = @(& $Exe @Argv 2>&1 | ForEach-Object { [string]$_ })
  $code = $LASTEXITCODE
  Log ('=== ' + $Label + ' exit=' + $code + ' ===')
  foreach ($line in $out) { Log $line }
  return [pscustomobject]@{ Code = $code; Lines = $out; Text = ($out -join "`n") }
}
function Sha {
  return (Get-FileHash -LiteralPath $ledgerPath -Algorithm SHA256).Hash
}

Log ('VERIFY_ROOT=' + $root)
Log ('VERIFY_LOG=' + $log)
$shaBefore = Sha
Log ('SHA_BEFORE=' + $shaBefore)

# One shot by design: the checks below consume the crash shape. A rerun on an
# already finalized fixture used to print seven red checks, which reads exactly
# like product breakage. Refuse the stale shape instead, before touching anything.
$preSha = $ExpectPreSha.ToUpperInvariant()
if ($shaBefore -ne $preSha) {
  $nowStatus = 'unknown'
  try { $nowStatus = [string](Get-Content -LiteralPath $ledgerPath -Raw -Encoding UTF8 | ConvertFrom-Json).status } catch { }
  Log ('STALE_STATE fixture_no_longer_holds_the_crash_shape sha_before=' + $shaBefore +
    ' expected_pre_sha=' + $preSha + ' status=' + $nowStatus)
  Log ('HINT=one_shot_verifier: the run that consumed this fixture already printed VERIFY_OK; a finalized ledger cannot be verified again. Rebuild with reports\b20-e2e-setup.ps1, then reports\b21-rebuild-crash-shape.ps1 -Repo <fixture-repo>, and pass -Root / -ExpectPreSha from its output.')
  Log 'SUMMARY fail=0 checks_run=0 refused_stale_state=true'
  exit 2
}

$L0 = Get-Content -LiteralPath $ledgerPath -Raw -Encoding UTF8 | ConvertFrom-Json
$st0 = @($L0.stages)
Log ('PRE status=' + $L0.status + ' current_stage=' + $L0.current_stage + ' max_stages=' + $L0.max_stages +
  ' stages=' + $st0.Count + ':' + (($st0 | ForEach-Object { [string]$_.id + '=' + [string]$_.status }) -join ',') +
  ' next_session_id=[' + $L0.next_session_id + ']')
Chk 'pre_crash_shape' ($L0.status -eq 'running' -and [int]$L0.current_stage -eq 2 -and [int]$L0.max_stages -eq 1 -and
  $st0.Count -eq 1 -and $st0[0].status -eq 'done' -and -not $L0.next_session_id) 'running/2/1/[1:done]/null'
Chk 'pre_sha_matches_child' ($shaBefore -eq $preSha) $shaBefore

# --- 1. dry run: reports the intent, touches nothing -------------------------
$dry = Run 'FINALIZE_DRYRUN' 'pwsh' @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $launcher,
  '-Target', $target, '-MaxStages', '1', '-AutoFinalize', '-DryRun')
$shaAfterDry = Sha
Log ('DRY_EXIT=' + $dry.Code + ' (not asserted: the documented dry-run contract is skip + no write, not a code)')
Chk 'dry_skip_line' ($dry.Text -match 'DRYRUN skip=auto_finalize') 'skip=auto_finalize'
Chk 'dry_no_write' ($shaAfterDry -eq $shaBefore) ('sha_after_dry=' + $shaAfterDry)
$L1 = Get-Content -LiteralPath $ledgerPath -Raw -Encoding UTF8 | ConvertFrom-Json
Chk 'dry_status_running' ($L1.status -eq 'running') ('status=' + $L1.status)

# --- 2. the real finalize ----------------------------------------------------
$fin = Run 'FINALIZE' 'pwsh' @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $launcher,
  '-Target', $target, '-MaxStages', '1', '-AutoFinalize')
$shaAfter = Sha
Log ('SHA_AFTER=' + $shaAfter)
Chk 'fin_exit3' ($fin.Code -eq 3) ('exit=' + $fin.Code)
Chk 'fin_cap_reached' ($fin.Text -match 'reason=chain_at_stage_cap') 'cap gate fired first'
$m = [regex]::Match($fin.Text, 'AUTO_FINALIZED status=done before=([0-9A-Fa-f]{64}) after=([0-9A-Fa-f]{64}) path=(.+?)\s*$', 'Multiline')
Chk 'fin_autofinalized_line' $m.Success 'AUTO_FINALIZED status=done before=<hex64> after=<hex64> path=<file>'
if ($m.Success) {
  $before = $m.Groups[1].Value.ToUpperInvariant()
  $after = $m.Groups[2].Value.ToUpperInvariant()
  Log ('FIN_BEFORE=' + $before + ' FIN_AFTER=' + $after + ' FIN_PATH=' + $m.Groups[3].Value)
  Chk 'fin_before_is_pre_sha' ($before -eq $shaBefore) 'before==pre sha256'
  Chk 'fin_after_is_post_sha' ($after -eq $shaAfter) 'after==post sha256'
  Chk 'fin_shas_differ' ($before -ne $after) 'the write really happened'
  $seenPath = $m.Groups[3].Value.Trim().Replace('/', '\')
  Chk 'fin_path_is_ledger' ($seenPath -eq $ledgerPath) $seenPath
}
Chk 'fin_hint' ($fin.Text -match 'HINT=chain_closed_by_auto_finalize') 'closing hint'

# --- 3. on-disk re-read ------------------------------------------------------
$L2 = Get-Content -LiteralPath $ledgerPath -Raw -Encoding UTF8 | ConvertFrom-Json
$st2 = @($L2.stages)
Log ('POST status=' + $L2.status + ' current_stage=' + $L2.current_stage + ' max_stages=' + $L2.max_stages +
  ' stages=' + (($st2 | ForEach-Object { [string]$_.id + '=' + [string]$_.status }) -join ',') +
  ' next_session_id=[' + $L2.next_session_id + '] updated_at=' + $L2.updated_at)
Chk 'post_status_done' ($L2.status -eq 'done') ('status=' + $L2.status)
Chk 'post_current_stage_kept' ([int]$L2.current_stage -eq 2) ('current_stage=' + $L2.current_stage)
Chk 'post_max_stages_kept' ([int]$L2.max_stages -eq 1) ('max_stages=' + $L2.max_stages)
Chk 'post_stage_still_done' ($st2.Count -eq 1 -and $st2[0].status -eq 'done') 'stages=[1:done]'
Chk 'post_no_next_session' (-not $L2.next_session_id) ('next_session_id=[' + $L2.next_session_id + ']')
Chk 'post_goal_kept' ($L2.goal -eq $target) 'goal untouched'

$gs = @(& pwsh -NoProfile -ExecutionPolicy Bypass -File $gate -Action status 2>&1 | ForEach-Object { [string]$_ })
$gsCode = $LASTEXITCODE
Log ('=== LEDGER_STATUS exit=' + $gsCode + ' ===')
foreach ($line in $gs) { Log $line }
$gsText = $gs -join "`n"
Chk 'gate_status_exit0' ($gsCode -eq 0) ('exit=' + $gsCode)
Chk 'gate_status_done' ($gsText -match 'LEDGER_STATE .*status=done') 'gate agrees the chain is closed'

# --- 4. a closed chain must not be re-closed ---------------------------------
$again = Run 'FINALIZE_AGAIN' 'pwsh' @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $launcher,
  '-Target', $target, '-MaxStages', '1', '-AutoFinalize')
Chk 'again_exit3' ($again.Code -eq 3) ('exit=' + $again.Code)
Chk 'again_exhausted' ($again.Text -match 'reason=chain_exhausted') 'current_stage 2 > max_stages 1'
Chk 'again_no_finalize' (-not ($again.Text -match 'AUTO_FINALIZED')) 'must not write again'
Chk 'again_sha_stable' ((Sha) -eq $shaAfter) 'ledger byte stable on the refused run'

# --- 5. the stage-1 artifact the link wrote ----------------------------------
$inv = Join-Path $relay 'stage-1-inventory.md'
$invOk = (Test-Path -LiteralPath $inv) -and ((Get-Item -LiteralPath $inv).Length -gt 0)
$invBytes = 0
if ($invOk) { $invBytes = (Get-Item -LiteralPath $inv).Length }
Chk 'stage_artifact' $invOk ('bytes=' + $invBytes)
if ($invOk) {
  $invText = Get-Content -LiteralPath $inv -Raw -Encoding UTF8
  $tracked = @(& git -C $repo ls-files)
  $missing = @($tracked | Where-Object { $invText -notmatch [regex]::Escape($_) })
  Chk 'stage_artifact_lists_tracked' ($missing.Count -eq 0) ('tracked=' + $tracked.Count + ' missing=' + $missing.Count)
}

Log ('SUMMARY fail=' + $script:fail + ' files_checked=2')
if ($script:fail -gt 0) { exit 2 }
Write-Output 'VERIFY_OK'
exit 0