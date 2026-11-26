# B18: discriminating power proof for the case 24 assertions.
#
# The stage cap gate used to always claim "every declared stage is done" and
# advise closing the chain, even when a stage had never run. The new suite
# case 24 checks the shape on the FAIL line (stages= / all_done=) and the HINT
# that belongs to it. This probe reverts the launcher in a TEMP copy of the
# repo to the old blanket HINT and shows that the new assertions turn red
# while the rest of the suite keeps its verdict. The real tree is never
# touched: everything happens under %TEMP%.
$ErrorActionPreference = 'Stop'
$repo = 'F:\soft\00selfmade\agentask-relay'
$stamp = (Get-Date -Format 'yyyyMMdd-HHmmss')
$root = Join-Path $env:TEMP ('relay-b18-capmut-' + $stamp)
New-Item -ItemType Directory -Path $root -Force | Out-Null
$copy = Join-Path $root 'repo'
& robocopy $repo $copy /E /XD .git examples /NFL /NDL /NJH /NJS /NP | Out-Null
if ($LASTEXITCODE -ge 8) { throw "robocopy failed exit=$LASTEXITCODE" }

$oldBlock = @'
    Say "FAIL reason=chain_at_stage_cap current_stage=$($ledger.current_stage) max_stages=$($ledger.max_stages)"
    Say 'HINT=every declared stage is done but status is still running: close it with relay-ledger.ps1 -Action status, then submit a patch {"set_status":"done"}. Do not raise -MaxStages to keep going.'
'@
# A PowerShell here string does NOT carry the newline in front of its closing
# marker, so the block has to end with one: otherwise the branch's own
# "exit 3" is glued onto the last Say line and becomes part of that string
# (the mutant would then run past the gate instead of refusing the chain).
$oldBlock = $oldBlock + "`n"

function Mutate-Launcher([string]$Path) {
  $text = [IO.File]::ReadAllText($Path)
  $startMark = '    $stageSummary = ''none'''
  $i = $text.IndexOf($startMark)
  if ($i -lt 0) { throw "anchor_start_missing file=$Path" }
  if ($text.IndexOf($startMark, $i + 1) -ge 0) { throw "anchor_start_not_unique file=$Path" }
  $j = $text.IndexOf('    exit 3', $i)
  if ($j -lt 0) { throw "anchor_end_missing file=$Path" }
  $span = $text.Substring($i, $j - $i)
  if ($span -notmatch 'HINT=all_stages_done_but_status_running') { throw "span_is_not_the_cap_branch file=$Path" }
  if ($span -notmatch 'HINT=stage_cap_reached_with_open_stage') { throw "span_is_not_the_cap_branch file=$Path" }
  if ($span -notmatch 'HINT=stage_cap_reached_with_no_stage_records') { throw "span_is_not_the_cap_branch file=$Path" }
  if ($span -notmatch 'all_done=') { throw "span_has_no_all_done_field file=$Path" }
  $mutated = $text.Substring(0, $i) + $oldBlock + $text.Substring($j)
  # The mutant must still refuse the chain (exit 3 on its own line). If the
  # replacement swallowed that line, the mutant would run past the gate and
  # the probe would be measuring a broken script instead of the old wording.
  if ($mutated -notmatch "(?m)^    exit 3\r?$") { throw "mutant_lost_the_exit_line file=$Path" }
  [IO.File]::WriteAllText($Path, $mutated, (New-Object Text.UTF8Encoding($false)))
  return ($mutated.Length - $text.Length)
}

$tpl = Join-Path $copy 'tool\templates\start-relay.ps1'
$dev = Join-Path $copy 'device\start-relay.ps1'
$deltaTpl = Mutate-Launcher $tpl
Copy-Item -LiteralPath $tpl -Destination $dev -Force
$same = (Get-FileHash -Algorithm SHA256 -LiteralPath $tpl).Hash -eq (Get-FileHash -Algorithm SHA256 -LiteralPath $dev).Hash
"ROOT=$root"
"MUTATED tool\templates\start-relay.ps1 delta_bytes=$deltaTpl device_copy_identical=$same"

$log = Join-Path $root 'selftest-mutant.log'
$out = & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $copy 'scripts\selftest.ps1') -EvidencePath $log 2>&1
$exit = $LASTEXITCODE
$suite = ($out | Where-Object { $_ -match 'SUITE_END' } | Select-Object -Last 1)
$capFails = @($out | Where-Object { $_ -match 'CASE_FAIL' -and $_ -match 'cap_hint_' })
$otherFails = @($out | Where-Object { $_ -match 'CASE_FAIL' -and $_ -notmatch 'cap_hint_' })
"MUTANT_EXIT=$exit"
"SUITE $suite"
"CAP_HINT_FAILS=$($capFails.Count)"
foreach ($f in $capFails) { "  $f" }
"OTHER_FAILS=$($otherFails.Count)"
foreach ($f in $otherFails) { "  $f" }

$teeth = ($exit -eq 1) -and ($capFails.Count -ge 4) -and ($otherFails.Count -eq 0) -and ($suite -match 'fail=[1-9]')
if ($teeth) { 'MUTATION_VERDICT=ASSERTION_HAS_TEETH' } else { 'MUTATION_VERDICT=ASSERTION_IS_WEAK' }
$summary = @(
  'B18 cap hint mutation probe',
  ("generated=" + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')),
  ("root=" + $root),
  ("mutant_exit=" + $exit),
  ("suite=" + $suite),
  ("cap_hint_fails=" + $capFails.Count),
  ("other_fails=" + $otherFails.Count),
  ("verdict=" + $(if ($teeth) { 'ASSERTION_HAS_TEETH' } else { 'ASSERTION_IS_WEAK' }))
)
foreach ($f in $capFails) { $summary += ('cap_fail: ' + $f) }
foreach ($f in $otherFails) { $summary += ('other_fail: ' + $f) }
$repoLog = 'F:\soft\00selfmade\agentask-relay\reports\b18-cap-hint-mutation.log'
[IO.File]::WriteAllText($repoLog, (($summary -join "`n") + "`n"), (New-Object Text.UTF8Encoding($false)))
"LOG=$repoLog"
if (-not $teeth) { exit 1 }
exit 0
