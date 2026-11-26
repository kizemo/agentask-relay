# B17 real-chain read-back + second-activation rejection check.
# Pure ASCII, no BOM. Read-only except the deliberate second launch attempt.
$ErrorActionPreference = 'Continue'

$repo = 'C:\Users\Duanyi\AppData\Local\Temp\relay-b17-e2e-20261126-172536\repo'
$ledgerPath = Join-Path $repo 'docs\relay.json'
$outDir = 'F:\soft\00selfmade\agentask-relay\reports'

function Say([string]$s) { Write-Host $s }

Say '=== LEDGER (read back from disk) ==='
if (-not (Test-Path -LiteralPath $ledgerPath)) {
  Say 'LEDGER_PRESENT=False'
} else {
  Say ('LEDGER_PRESENT=True bytes=' + (Get-Item -LiteralPath $ledgerPath).Length)
  try {
    $L = Get-Content -LiteralPath $ledgerPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Say ('LEDGER status=' + $L.status)
    Say ('LEDGER current_stage=' + $L.current_stage + ' max_stages=' + $L.max_stages)
    Say ('LEDGER next_session_id=[' + $L.next_session_id + ']')
    Say ('LEDGER sessions_count=' + @($L.sessions).Count)
    Say ('LEDGER blocked_on_count=' + @($L.blocked_on).Count)
    if (@($L.blocked_on).Count -gt 0) { Say ('LEDGER blocked_on=' + (@($L.blocked_on) -join ' | ')) }
    $i = 0
    foreach ($st in @($L.stages)) {
      $i++
      Say ('STAGE[' + $i + '] status=' + $st.status + ' stage=' + $st.stage + ' title=' + $st.title)
      if ($st.PSObject.Properties.Name -contains 'note' -and $st.note) { Say ('STAGE[' + $i + '] note=' + $st.note) }
      if ($st.PSObject.Properties.Name -contains 'evidence' -and $st.evidence) { Say ('STAGE[' + $i + '] evidence=' + $st.evidence) }
    }
    Say ('STAGE_COUNT=' + @($L.stages).Count)
    # B15 expectation: done + current_stage > max_stages + every stage done
    $allDone = (@($L.stages).Count -gt 0)
    foreach ($st in @($L.stages)) { if ($st.status -ne 'done') { $allDone = $false } }
    Say ('EXPECT_DONE_VERDICT status_done=' + ($L.status -eq 'done') + ' every_stage_done=' + $allDone + ' cap_reached=' + ([int]$L.current_stage -gt [int]$L.max_stages))
  } catch {
    Say ('LEDGER_PARSE_ERROR ' + $_.Exception.Message)
  }
}

Say ''
Say '=== LOCK ==='
$lockScript = Join-Path $repo 'docs\relay\relay-lock.ps1'
& pwsh -NoProfile -ExecutionPolicy Bypass -File $lockScript -Action status 2>&1 | ForEach-Object { Say ('LOCK> ' + $_) }
Say ('LOCK_EXIT=' + $LASTEXITCODE)

Say ''
Say '=== ARTIFACTS ==='
foreach ($rel in @('docs\relay\stage-1-inventory.md', 'docs\relay\stage-2-inventory.md')) {
  $p = Join-Path $repo $rel
  if (Test-Path -LiteralPath $p) {
    Say ('ARTIFACT present=' + $rel + ' bytes=' + (Get-Item -LiteralPath $p).Length)
  } else {
    Say ('ARTIFACT missing=' + $rel)
  }
}
Say 'GIT_STATUS_BEGIN'
& git -C $repo status --porcelain -uall 2>&1 | ForEach-Object { Say ('GIT> ' + $_) }
Say 'GIT_STATUS_END'

Say ''
Say '=== SECOND ACTIVATION ATTEMPT (expect refusal, nonzero exit) ==='
$launchScript = Join-Path $repo 'docs\relay\start-relay.ps1'
$secondLog = Join-Path $outDir 'b17-second-launch.log'
& pwsh -NoProfile -ExecutionPolicy Bypass -File $launchScript -Target 'B17 real chain retest' -MaxStages 2 *>&1 | Tee-Object -FilePath $secondLog | ForEach-Object { Say ('2ND> ' + $_) }
$secondExit = $LASTEXITCODE
Say ('SECOND_LAUNCH_EXIT=' + $secondExit)
Say ('SECOND_LAUNCH_LOG=' + $secondLog)

$text = ''
if (Test-Path -LiteralPath $secondLog) { $text = Get-Content -LiteralPath $secondLog -Raw }
$reasons = @('stage_in_progress', 'chain_already_running', 'chain_at_stage_cap', 'chain_exhausted', 'ledger_blocked', 'ledger_unparsable', 'lock_unavailable')
$hit = @()
foreach ($r in $reasons) { if ($text -match [regex]::Escape($r)) { $hit += $r } }
Say ('REFUSAL_REASON_HITS=' + ($(if ($hit.Count -gt 0) { $hit -join ',' } else { 'NONE' })))
Say ('REFUSAL_VERDICT=' + $(if ($secondExit -ne 0 -and $hit.Count -gt 0) { 'REFUSED_WITH_REASON' } elseif ($secondExit -ne 0) { 'REFUSED_NO_KNOWN_REASON' } else { 'NOT_REFUSED' }))