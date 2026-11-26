# B19: discriminating power proof for the two new assertion groups.
#
# Two features were added in B19 and each one has a set of assertions that keeps
# it honest. This probe breaks each feature in a TEMP copy of the repo and shows
# that only the assertions built for that feature go red, while the rest of the
# suite keeps its verdict. The real tree is never touched.
#
#   mutant 1  the launcher loses its "every declared stage is done" condition,
#             so -AutoFinalize closes a chain that still has an open stage.
#   mutant 2  the ledger reports all_done=true no matter what the stage list
#             says, so its new LEDGER_CHAIN line stops describing the chain.
#
# A green suite alone would not prove the assertions can fail; a red suite alone
# would not prove they fail for the right reason. Both mutants therefore count
# their own bucket of CASE_FAIL lines, require every other bucket to be empty,
# and also name the assertions that must stay green under that mutation, so a
# blind spot is stated with evidence instead of being quietly dropped.
#
# Why some assertions are expected to stay green (measured, not assumed):
#   mutant 1  auto_finalize_open_stage_raises_no_warn guards the path where the
#             ledger write FAILS (WARN auto_finalize=failed). With the guard
#             removed the write succeeds, so no WARN appears and the assertion
#             is blind to this mutation by design. The open chain is caught by
#             is_not_closed and leaves_ledger_running instead.
#             auto_finalize_open_stage_still_exits_three only checks the exit
#             code, which the mutant keeps at 3.
#   mutant 2  the all_done, no_records and no_numbers shapes all expect
#             all_done=true or all_done=unknown, which the pinned value still
#             satisfies; only the two shapes that expect all_done=false and the
#             cross check against the launcher can see the mutation.
$ErrorActionPreference = 'Stop'
$repo = 'F:\soft\00selfmade\agentask-relay'
$stamp = (Get-Date -Format 'yyyyMMdd-HHmmss')
$root = Join-Path $env:TEMP ('relay-b19-guardmut-' + $stamp)
New-Item -ItemType Directory -Path $root -Force | Out-Null

function New-Copy([string]$Name) {
  $copy = Join-Path $root $Name
  & robocopy $repo $copy /E /XD .git examples /NFL /NDL /NJH /NJS /NP | Out-Null
  if ($LASTEXITCODE -ge 8) { throw "robocopy failed exit=$LASTEXITCODE" }
  return $copy
}

# Exact, count checked, single occurrence replacement. A mutation that silently
# matches nothing would leave the suite green and prove nothing, so every miss
# is a hard error rather than a quiet no-op. -MustKeep is the structural line the
# mutated file must still contain: without it the mutant could be a broken script
# and the probe would be measuring a crash instead of the guard under test.
function Set-Exact([string]$Path, [string]$Old, [string]$New, [string]$MustKeep) {
  $text = [IO.File]::ReadAllText($Path)
  $i = $text.IndexOf($Old)
  if ($i -lt 0) { throw "anchor_missing file=$Path" }
  if ($text.IndexOf($Old, $i + 1) -ge 0) { throw "anchor_not_unique file=$Path" }
  $mutated = $text.Substring(0, $i) + $New + $text.Substring($i + $Old.Length)
  if ($mutated -eq $text) { throw "mutation_changed_nothing file=$Path" }
  if ($mutated -notmatch $MustKeep) { throw "mutant_lost_kept_anchor file=$Path keep=$MustKeep" }
  [IO.File]::WriteAllText($Path, $mutated, (New-Object Text.UTF8Encoding($false)))
  return ($mutated.Length - $text.Length)
}

function Invoke-Suite([string]$Copy, [string]$LogPath) {
  $out = & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Copy 'scripts\selftest.ps1') -EvidencePath $LogPath 2>&1
  $code = $LASTEXITCODE
  return [pscustomobject]@{ Code = $code; Lines = @($out | ForEach-Object { [string]$_ }) }
}

function Get-Reds($Run) { return @($Run.Lines | Where-Object { $_ -match 'CASE_FAIL' }) }
function Get-Suite($Run) {
  $hit = @($Run.Lines | Where-Object { $_ -match 'SUITE_END' } | Select-Object -Last 1)
  if ($hit.Count -lt 1) { return 'suite_line_missing' }
  return $hit[0]
}
function Count-Hits($Reds, [string[]]$Names) {
  $n = 0
  foreach ($name in $Names) {
    if (@($Reds | Where-Object { $_ -match ('CASE_FAIL ' + [regex]::Escape($name)) }).Count -gt 0) { $n++ }
  }
  return $n
}

$results = @()

# --- mutant 1: the launcher closes a chain with an open stage -------------------
$copy1 = New-Copy 'repo-guard'
$tpl1 = Join-Path $copy1 'tool\templates\start-relay.ps1'
$old1 = 'if ($AutoFinalize -and $allDoneState -eq ''true'') {'
$delta1 = Set-Exact $tpl1 $old1 'if ($AutoFinalize) {' '(?m)^    exit 3\r?$'
$guardGone = -not ([IO.File]::ReadAllText($tpl1) -match [regex]::Escape($old1))
# The hard invariant (device\ is byte identical to tool\templates\) is itself a
# suite case, so the mutant has to be carried over or it would report a stray.
Copy-Item -LiteralPath $tpl1 -Destination (Join-Path $copy1 'device\start-relay.ps1') -Force
$need1 = @(
  'auto_finalize_open_stage_is_not_closed',
  'auto_finalize_open_stage_leaves_ledger_running'
)
$keep1 = @(
  'auto_finalize_open_stage_raises_no_warn',
  'auto_finalize_open_stage_still_exits_three'
)
$run1 = Invoke-Suite $copy1 (Join-Path $root 'selftest-guard.log')
$red1 = Get-Reds $run1
$hit1 = Count-Hits $red1 $need1
$keepRed1 = Count-Hits $red1 $keep1
$stray1 = @($red1 | Where-Object { $_ -notmatch 'CASE_FAIL auto_finalize_open_stage_' })
$ok1 = ($run1.Code -eq 1) -and $guardGone -and ($hit1 -eq $need1.Count) -and ($keepRed1 -eq 0) -and ($stray1.Count -eq 0)
$results += [pscustomobject]@{
  tag = 'launcher_guard_removed'; copy = $copy1; delta = $delta1; code = $run1.Code
  suite = (Get-Suite $run1); hits = $hit1; want = $need1.Count; keepRed = $keepRed1; keepWant = $keep1.Count
  reds = @($red1 | Where-Object { $_ -match 'CASE_FAIL auto_finalize_open_stage_' })
  stray = $stray1; ok = $ok1
}

# --- mutant 2: the ledger always claims every stage is done -------------------
$copy2 = New-Copy 'repo-alldone'
$tpl2 = Join-Path $copy2 'tool\templates\relay-ledger.ps1'
$old2 = 'if ($doneStages -eq $declaredStages.Count) { $chainAllDone = ''true'' } else { $chainAllDone = ''false'' }'
$delta2 = Set-Exact $tpl2 $old2 '$chainAllDone = ''true''' 'LEDGER_CHAIN'
$alwaysDone = [bool]([IO.File]::ReadAllText($tpl2) -match '(?m)^\s+\$chainAllDone = ''true''\r?$')
Copy-Item -LiteralPath $tpl2 -Destination (Join-Path $copy2 'device\relay-ledger.ps1') -Force
$need2 = @(
  'chain_status_open_stage_reports_its_shape',
  'chain_status_open_stage_agrees_with_launcher_all_done',
  'chain_status_below_cap_reports_its_shape'
)
$keep2 = @(
  'chain_status_all_done_reports_its_shape',
  'chain_status_no_records_reports_its_shape',
  'chain_status_no_numbers_reports_its_shape'
)
$run2 = Invoke-Suite $copy2 (Join-Path $root 'selftest-alldone.log')
$red2 = Get-Reds $run2
$hit2 = Count-Hits $red2 $need2
$keepRed2 = Count-Hits $red2 $keep2
$stray2 = @($red2 | Where-Object { $_ -notmatch 'CASE_FAIL chain_status_' })
$ok2 = ($run2.Code -eq 1) -and $alwaysDone -and ($hit2 -eq $need2.Count) -and ($keepRed2 -eq 0) -and ($stray2.Count -eq 0)
$results += [pscustomobject]@{
  tag = 'ledger_all_done_pinned'; copy = $copy2; delta = $delta2; code = $run2.Code
  suite = (Get-Suite $run2); hits = $hit2; want = $need2.Count; keepRed = $keepRed2; keepWant = $keep2.Count
  reds = @($red2 | Where-Object { $_ -match 'CASE_FAIL chain_status_' })
  stray = $stray2; ok = $ok2
}

# --- report -------------------------------------------------------------------
$lines = @('B19 guard mutation probe', ('generated=' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')), ('root=' + $root))
foreach ($r in $results) {
  $lines += ''
  $lines += ('MUTANT ' + $r.tag)
  $lines += ('  copy=' + $r.copy)
  $lines += ('  delta_bytes=' + $r.delta)
  $lines += ('  mutant_exit=' + $r.code)
  $lines += ('  suite=' + $r.suite)
  $lines += ('  expected_reds=' + $r.want + ' matched=' + $r.hits)
  foreach ($f in $r.reds) { $lines += ('  red: ' + $f) }
  $lines += ('  must_stay_green=' + $r.keepWant + ' went_red=' + $r.keepRed)
  $lines += ('  other_fails=' + $r.stray.Count)
  foreach ($f in $r.stray) { $lines += ('  other: ' + $f) }
}
$lines += ([string]::Empty)
foreach ($r in $results) {
  $verdict = 'ASSERTION_HAS_TEETH'
  if (-not $r.ok) { $verdict = 'ASSERTION_IS_WEAK' }
  $lines += ('MUTATION_VERDICT ' + $r.tag + '=' + $verdict)
}
$text = ($lines -join "`n") + "`n"
foreach ($r in $results) { $text | Write-Output }
$text | Write-Output

$logPath = Join-Path $repo 'reports\b19-guard-mutation.log'
[IO.File]::WriteAllText($logPath, $text, (New-Object Text.UTF8Encoding($false)))
'LOG=' + $logPath
foreach ($r in $results) { if (-not $r.ok) { exit 1 } }
exit 0