<#
.SYNOPSIS
  One-click regression suite for the relay-port kit (turns project rule 1 into a runnable script).
.DESCRIPTION
  What it does
    Builds throwaway git repos under $env:TEMP, runs the real installer and the real launcher from tool/
    against them, and asserts the behaviours that project rule 1 requires to be re-checked after every
    change to tool/: fresh install, idempotent re-install, dry run, real activation, second activation
    refused, lock mutual exclusion, adoption of a pre-existing house-rules section. Plus the B2 additions:
    launcher plan-document resolution (probe / missing / ambiguous) and content-signature adoption.

  Safety
    Never touches this repository's working tree, never touches any real project, never calls
    session_create. The only thing it writes outside TEMP is the optional evidence log.
    Artifacts are kept by default so failures stay inspectable; pass -Cleanup to remove them.

  Exit codes
    0  every case passed
    1  at least one case failed (see CASE_FAIL lines and the evidence log)
    2  the suite could not run (git missing, tool/ missing, temp dir unwritable)
.PARAMETER Keep
  Keep the temp workspace after the run. This is the default; the parameter exists for explicitness.
.PARAMETER Cleanup
  Remove the temp workspace at the end. Use only after a green run.
.PARAMETER EvidencePath
  Also write the full machine log to this absolute path. Relative paths are rejected so the log cannot
  land somewhere surprising.
.EXAMPLE
  pwsh -NoProfile -File scripts\selftest.ps1
.EXAMPLE
  pwsh -NoProfile -File scripts\selftest.ps1 -EvidencePath "$env:TEMP\relay-selftest-b2.log" -Cleanup
.NOTES
  Pure ASCII, no BOM, LF. A green run here is a precondition for scripts\publish-relay.ps1 -Direction publish.
#>
[CmdletBinding()]
param(
  [switch]$Keep,
  [switch]$Cleanup,
  [string]$EvidencePath = ''
)

$ErrorActionPreference = 'Stop'

$repoRoot = (Get-Item -LiteralPath (Split-Path -Parent $PSCommandPath)).Parent.FullName
$installer = Join-Path $repoRoot 'tool\scripts\install-relay.ps1'
$tplDir = Join-Path $repoRoot 'tool\templates'
$pwsh = (Get-Process -Id $PID).Path
$log = New-Object System.Collections.Generic.List[string]
$script:pass = 0
$script:fail = 0

function Say([string]$Text) {
  $line = (Get-Date).ToString('HH:mm:ss') + ' ' + $Text
  $log.Add($line)
  Write-Output $line
}
function Check([string]$Case, [bool]$Condition, [string]$Detail) {
  if ($Condition) { $script:pass++; Say ('CASE_PASS ' + $Case + ' ' + $Detail) }
  else { $script:fail++; Say ('CASE_FAIL ' + $Case + ' ' + $Detail) }
}
function Run([string]$File, [string[]]$Args_) {
  $out = & $pwsh -NoProfile -ExecutionPolicy Bypass -File $File @Args_ *>&1 | ForEach-Object { $_.ToString() }
  return [pscustomobject]@{ Code = $LASTEXITCODE; Text = ($out -join "`n") }
}
function New-Repo([string]$Name) {
  $dir = Join-Path $script:root $Name
  New-Item -ItemType Directory -Path (Join-Path $dir 'docs') -Force | Out-Null
  Set-Content -LiteralPath (Join-Path $dir 'README.md') -Value ('# ' + $Name) -Encoding utf8
  Set-Content -LiteralPath (Join-Path $dir 'AGENTS.md') -Value ('# ' + $Name + ' rules' + "`n`n" + 'Be nice.') -Encoding utf8
  & git -C $dir init -q 2>&1 | Out-Null
  & git -C $dir add -A 2>&1 | Out-Null
  & git -C $dir -c user.email=t@t -c user.name=t commit -qm init 2>&1 | Out-Null
  return $dir
}
function CountOf([string]$Path, [string]$Needle) {
  if (-not (Test-Path -LiteralPath $Path)) { return -1 }
  $t = [IO.File]::ReadAllText($Path)
  return ([regex]::Matches($t, [regex]::Escape($Needle))).Count
}
function Hash16([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path)) { return 'MISSING' }
  return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.Substring(0, 16)
}

# --- preconditions --------------------------------------------------------------
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { Say 'ABORT reason=git_missing'; exit 2 }
foreach ($need in @($installer, (Join-Path $tplDir 'start-relay.ps1'), (Join-Path $tplDir 'relay-lock.ps1'), (Join-Path $tplDir 'relay-ledger.ps1'), (Join-Path $tplDir 'AGENTS-RELAY-BLOCK.md'))) {
  if (-not (Test-Path -LiteralPath $need)) { Say ('ABORT reason=kit_file_missing path=' + $need); exit 2 }
}
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$script:root = Join-Path $env:TEMP ('relay-port-selftest\' + $stamp)
New-Item -ItemType Directory -Path $script:root -Force | Out-Null
# Canonicalise the temp root. A Windows logon name longer than 8 characters can make
# %TEMP% itself an 8.3 short path (a GitHub runner reports C:\Users\RUNNER~1\...), and
# then every path the launcher echoes back is the LONG form. Assertions that compare
# path text would go red on a real kit that is fine, so resolve the short names once,
# here. Long == short on a normal developer profile, so this changes nothing locally.
$shortRoot = $script:root
$script:root = (Get-Item -LiteralPath $script:root).FullName
if ($script:root -ne $shortRoot) { Say ('NOTE root_canonicalised short=' + $shortRoot + ' -> long=' + $script:root) }
Say ('SUITE_START root=' + $script:root + ' kit=' + $repoRoot)

$beginMark = '<!-- BEGIN RELAY-PORT -->'
$endMark = '<!-- END RELAY-PORT -->'

# --- case 1: fresh install ------------------------------------------------------
$r1 = New-Repo 'repo-fresh'
Set-Content -LiteralPath (Join-Path $r1 'docs\plan-b1.md') -Value '# plan b1' -Encoding utf8
$a = Run $installer @('-RepoRoot', $r1, '-Target', 'smoke batch', '-PlanDoc', 'docs\plan-b1.md', '-MaxStages', '3')
Check 'install_exit_zero' ($a.Code -eq 0) ('exit=' + $a.Code)
Check 'install_verdict_pass' ($a.Text -match 'INSTALL_VERDICT=PASS') ('tail=' + (($a.Text -split "`n" | Select-Object -Last 3) -join ' | '))
Check 'install_launcher_present' (Test-Path (Join-Path $r1 'docs\relay\start-relay.ps1')) ('dir=' + $r1)
Check 'install_lock_present' (Test-Path (Join-Path $r1 'docs\relay\relay-lock.ps1')) ''
Check 'install_ledger_gate_present' (Test-Path (Join-Path $r1 'docs\relay\relay-ledger.ps1')) ''
Check 'install_agents_single_block' ((CountOf (Join-Path $r1 'AGENTS.md') $beginMark) -eq 1 -and (CountOf (Join-Path $r1 'AGENTS.md') $endMark) -eq 1) ''
$dryArtifact = Join-Path $r1 'docs\relay\install-dryrun.txt'
Check 'install_dryrun_ok_line' ($a.Text -match 'DRYRUN exit=0 verdict=OK') ('line=' + ((($a.Text -split "`n") | Where-Object { $_ -match 'DRYRUN' } | Select-Object -First 1)))
Check 'install_dryrun_passed_plandoc_through' ((Test-Path $dryArtifact) -and (([IO.File]::ReadAllText($dryArtifact)) -match 'OK plan_doc=docs[\\/]plan-b1\.md')) ('artifact=' + $dryArtifact + ' line=' + (((([IO.File]::ReadAllText($dryArtifact)) -split "`n") | Where-Object { $_ -match 'plan_doc=' } | Select-Object -First 1)))

# --- case 2: idempotent re-install ---------------------------------------------
$h1 = Hash16 (Join-Path $r1 'AGENTS.md')
$b = Run $installer @('-RepoRoot', $r1, '-Target', 'smoke batch', '-PlanDoc', 'docs\plan-b1.md', '-MaxStages', '3')
Check 'reinstall_exit_zero' ($b.Code -eq 0) ('exit=' + $b.Code)
Check 'reinstall_agents_bytes_stable' ((Hash16 (Join-Path $r1 'AGENTS.md')) -eq $h1) ('before=' + $h1 + ' after=' + (Hash16 (Join-Path $r1 'AGENTS.md')))
Check 'reinstall_single_block_still' ((CountOf (Join-Path $r1 'AGENTS.md') $beginMark) -eq 1) ''
Check 'reinstall_keeps_existing' ($b.Text -match 'present_kept|already|kept|SKIP') ('agents_line=' + ((($b.Text -split "`n") | Where-Object { $_ -match 'AGENTS action=' } | Select-Object -First 1)))

# --- case 3: adoption by content signature (candidate 4) ------------------------
$r3 = New-Repo 'repo-signature'
Set-Content -LiteralPath (Join-Path $r3 'docs\plan-x.md') -Value '# plan x' -Encoding utf8
# A pre-existing relay section whose heading mentions neither "Relay" nor the CJK word for it,
# but whose body carries at least four relay signals.
$foreign = @(
  '# Rules',
  '',
  '## Unattended progress rules',
  '',
  'One writer per project: while a stage is in_progress no second session may start.',
  'State lives in docs\relay.json and is updated by appending only, guarded by relay-lock.ps1.',
  'Each stage starts a new session through session_create and records next_session_id.',
  'Stop and ask the human at an awaiting_user checkpoint or when max_stages is reached.',
  'start-relay.ps1 is the only entry point.'
) -join "`n"
[IO.File]::WriteAllText((Join-Path $r3 'AGENTS.md'), $foreign + "`n", (New-Object Text.UTF8Encoding($false)))
$c = Run $installer @('-RepoRoot', $r3, '-Target', 'sig batch', '-PlanDoc', 'docs\plan-x.md')
$agentsR3 = [IO.File]::ReadAllText((Join-Path $r3 'AGENTS.md'))
Check 'adopt_by_content_exit_zero' ($c.Code -eq 0) ('exit=' + $c.Code)
Check 'adopt_by_content_marked' ($agentsR3.Contains($beginMark) -and $agentsR3.Contains('Unattended progress rules')) ('has_marker=' + $agentsR3.Contains($beginMark) + ' kept_original=' + $agentsR3.Contains('Unattended progress rules'))
Check 'adopt_by_content_reason_logged' ($c.Text -match 'reason=content_signature') ('agents_line=' + ((($c.Text -split "`n") | Where-Object { $_ -match 'AGENTS action=' } | Select-Object -First 1)))

# --- case 4: ambiguous relay sections are not guessed ---------------------------
$r4 = New-Repo 'repo-ambiguous'
Set-Content -LiteralPath (Join-Path $r4 'docs\plan-y.md') -Value '# plan y' -Encoding utf8
$two = @(
  '# Rules',
  '',
  '## Section one',
  'The ledger docs\relay.json tracks in_progress stages and start-relay.ps1 gates them.',
  'relay-lock.ps1 is held by one writer and session_create records next_session_id.',
  '',
  '## Section two',
  'Also mentions docs\relay.json, max_stages, awaiting_user and AGENT-RELAY.md.',
  'And relay-lock.ps1 plus in_progress plus session_create plus start-relay.ps1.',
  '',
  '## Unrelated',
  'Commit messages stay in English.'
) -join "`n"
[IO.File]::WriteAllText((Join-Path $r4 'AGENTS.md'), $two + "`n", (New-Object Text.UTF8Encoding($false)))
$d = Run $installer @('-RepoRoot', $r4, '-Target', 'amb batch', '-PlanDoc', 'docs\plan-y.md')
Check 'ambiguous_warns' ($d.Text -match 'WARN.*agents_relay_section_ambiguous') ('warn=' + ((($d.Text -split "`n") | Where-Object { $_ -match 'WARN.*agents_relay_section_ambiguous' } | Select-Object -First 1)))
Check 'ambiguous_appends_managed_block' ((CountOf (Join-Path $r4 'AGENTS.md') $beginMark) -eq 1) ''
Check 'ambiguous_keeps_both_sections' ((([IO.File]::ReadAllText((Join-Path $r4 'AGENTS.md'))) -match 'Section one') -and (([IO.File]::ReadAllText((Join-Path $r4 'AGENTS.md'))) -match 'Section two')) ''

# --- case 5: launcher resolves a plan it was never told about (candidate 3) ------
$r5 = New-Repo 'repo-planprobe'
New-Item -ItemType Directory -Path (Join-Path $r5 'docs\superpowers\plans') -Force | Out-Null
Set-Content -LiteralPath (Join-Path $r5 'docs\superpowers\plans\2026-11-07-b1.md') -Value '# real plan' -Encoding utf8
$null = Run $installer @('-RepoRoot', $r5, '-Target', 'probe batch', '-MaxStages', '2')
$launcher5 = Join-Path $r5 'docs\relay\start-relay.ps1'
$e = Run $launcher5 @('-Target', 'probe batch', '-MaxStages', '2', '-DryRun')
Check 'probe_dryrun_exit_zero' ($e.Code -eq 0) ('exit=' + $e.Code)
Check 'probe_found_plan' ($e.Text -match 'OK plan_doc=docs[\\/]superpowers[\\/]plans[\\/]2026-11-07-b1\.md source=probe') ('line=' + ((($e.Text -split "`n") | Where-Object { $_ -match 'plan_doc=' } | Select-Object -First 1)))
Check 'probe_no_lock_left_behind' (-not (Test-Path (Join-Path $r5 'docs\relay\.relay.lock'))) ''
Check 'probe_no_ledger_written' (-not (Test-Path (Join-Path $r5 'docs\relay.json'))) ''
# D4: nothing that SHIPS INTO a target repo may carry the foreign default plan path.
# tool\references\* are historical evidence snapshots and legitimately quote removed
# defaults (the baseline table records what the old default was), so they are out of scope.
$kitFiles = @(Get-ChildItem -LiteralPath (Join-Path $repoRoot 'tool') -Recurse -File |
  Where-Object { $_.Extension -in @('.ps1', '.md', '.txt') } |
  Where-Object { $_.FullName -notmatch '\\tool\\references\\' })
# positive control: the scan must actually see the shipped kit, otherwise the check below is vacuous
Check 'kit_scan_scope_nonempty' ($kitFiles.Count -ge 5) ('scanned=' + $kitFiles.Count)
$kitScan = @($kitFiles |
  Where-Object { ([IO.File]::ReadAllText($_.FullName)) -match 'b1-flutter-implementation' })
Check 'kit_has_no_foreign_default_plan' (@($kitScan).Count -eq 0) ('hits=' + (@($kitScan | ForEach-Object { $_.FullName.Substring($repoRoot.Length + 1) }) -join ','))

# --- case 6: unresolvable plan fails before the lock (candidate 3) ----------------
$r6 = New-Repo 'repo-noplan'
New-Item -ItemType Directory -Path (Join-Path $r6 'docs\relay') -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $tplDir 'start-relay.ps1') -Destination (Join-Path $r6 'docs\relay\start-relay.ps1') -Force
$f = Run (Join-Path $r6 'docs\relay\start-relay.ps1') @('-Target', 'orphan', '-DryRun')
Check 'noplan_exit_two' ($f.Code -eq 2) ('exit=' + $f.Code)
Check 'noplan_reason_reported' ($f.Text -match 'plan_doc_missing') ('line=' + ((($f.Text -split "`n") | Where-Object { $_ -match 'plan_doc' } | Select-Object -First 1)))
Check 'noplan_no_lock' (-not (Test-Path (Join-Path $r6 'docs\relay\.relay.lock'))) ''

# --- case 7: real activation writes ledger + prompt with an absolute plan path ----
$g = Run $launcher5 @('-Target', 'probe batch', '-MaxStages', '2', '-PromptOut', (Join-Path $r5 'docs\relay\next-prompt.md'))
Check 'activate_exit_zero' ($g.Code -eq 0) ('exit=' + $g.Code + ' tail=' + (($g.Text -split "`n" | Select-Object -Last 2) -join ' | '))
Check 'activate_ledger_created' (Test-Path (Join-Path $r5 'docs\relay.json')) ''
$led5 = $null
if (Test-Path (Join-Path $r5 'docs\relay.json')) { $led5 = Get-Content -LiteralPath (Join-Path $r5 'docs\relay.json') -Raw -Encoding UTF8 | ConvertFrom-Json }
Check 'activate_ledger_plan_doc_relative' ($led5.plan_doc -eq 'docs\superpowers\plans\2026-11-07-b1.md') ('plan_doc=' + [string]$led5.plan_doc)
Check 'activate_lock_held' (Test-Path (Join-Path $r5 'docs\relay\.relay.lock')) ''
Check 'activate_prompt_absolute_plan' ((Test-Path (Join-Path $r5 'docs\relay\next-prompt.md')) -and (([IO.File]::ReadAllText((Join-Path $r5 'docs\relay\next-prompt.md'))) -match [regex]::Escape($r5 + '\docs\superpowers\plans\2026-11-07-b1.md'))) ''

# --- case 8: second activation while the chain is live ---------------------------
$h = Run $launcher5 @('-Target', 'probe batch', '-MaxStages', '2')
Check 'second_activation_refused' ($h.Code -ne 0) ('exit=' + $h.Code)
Check 'second_activation_reason_logged' ($h.Text -match 'reason=(stage_in_progress|chain_already_running|lock_unavailable)') ('line=' + ((($h.Text -split "`n") | Where-Object { $_ -match 'FAIL reason=' } | Select-Object -First 1)))

# --- case 9: lock mutual exclusion ---------------------------------------------
$r9 = New-Repo 'repo-lock'
$lock9 = Join-Path $tplDir 'relay-lock.ps1'
New-Item -ItemType Directory -Path (Join-Path $r9 'docs\relay') -Force | Out-Null
$lp = Join-Path $r9 'docs\relay\.relay.lock'
$l1 = Run $lock9 @('-Action', 'acquire', '-SessionId', 'session-alpha', '-Stage', '1', '-TtlSeconds', '600', '-LockPath', $lp)
Check 'lock_alpha_acquired' ($l1.Code -eq 0 -and $l1.Text -match 'LOCK_ACQUIRED holder=session-alpha') ('exit=' + $l1.Code + ' out=' + (($l1.Text -split "`n" | Select-Object -Last 1)))
$l2 = Run $lock9 @('-Action', 'acquire', '-SessionId', 'session-beta', '-TtlSeconds', '600', '-LockPath', $lp)
Check 'lock_beta_refused' ($l2.Code -ne 0 -and $l2.Text -match 'LOCK_HELD holder=session-alpha') ('exit=' + $l2.Code + ' out=' + (($l2.Text -split "`n" | Select-Object -Last 1)))
$l3 = Run $lock9 @('-Action', 'status', '-LockPath', $lp)
Check 'lock_owner_still_alpha' ($l3.Text -match 'session-alpha') ('out=' + (($l3.Text -split "`n" | Select-Object -Last 1)))
$l4 = Run $lock9 @('-Action', 'release', '-SessionId', 'session-beta', '-LockPath', $lp)
Check 'lock_release_by_wrong_owner_refused' ($l4.Code -ne 0 -and $l4.Text -match 'LOCK_NOT_MINE') ('exit=' + $l4.Code + ' out=' + (($l4.Text -split "`n" | Select-Object -Last 1)))
$l5 = Run $lock9 @('-Action', 'release', '-SessionId', 'session-alpha', '-LockPath', $lp)
Check 'lock_released_by_owner' ($l5.Code -eq 0 -and -not (Test-Path $lp)) ('exit=' + $l5.Code + ' still_there=' + (Test-Path $lp))

# --- case 10: house rule 4, pure ASCII / no BOM / parses -----------------------
$bad = @()
$kitPs1 = @(Get-ChildItem -LiteralPath (Join-Path $repoRoot 'tool') -Recurse -File -Filter '*.ps1')
foreach ($f2 in ($kitPs1 + @(Get-Item -LiteralPath (Join-Path $repoRoot 'scripts\selftest.ps1'), (Join-Path $repoRoot 'scripts\publish-relay.ps1'), (Join-Path $repoRoot 'scripts\refresh-manifest.ps1'), (Join-Path $repoRoot 'device\start-relay.ps1'), (Join-Path $repoRoot 'device\relay-lock.ps1'), (Join-Path $repoRoot 'device\relay-ledger.ps1'), (Join-Path $tplDir 'relay-ledger.ps1')))) {
  $bytes = [IO.File]::ReadAllBytes($f2.FullName)
  $nonAscii = 0
  for ($i = 0; $i -lt $bytes.Length; $i++) { if ($bytes[$i] -gt 127) { $nonAscii++ } }
  $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
  $errs = $null
  [void][System.Management.Automation.Language.Parser]::ParseFile($f2.FullName, [ref]$null, [ref]$errs)
  if ($nonAscii -gt 0 -or $hasBom -or @($errs).Count -gt 0) {
    $bad += ($f2.FullName.Substring($repoRoot.Length + 1) + '(nonAscii=' + $nonAscii + ',bom=' + $hasBom + ',parse=' + @($errs).Count + ')')
  }
}
Check 'ps1_ascii_bom_parse' ($bad.Count -eq 0) ('bad=' + ($bad -join ' '))

# --- case 9: ledger write gate (candidate #8) ------------------------------------
$gate = Join-Path $r5 'docs\relay\relay-ledger.ps1'
Check 'ledger_gate_installed' (Test-Path -LiteralPath $gate) ('path=' + $gate)
function Get-GateSha {
  [regex]::Match((Run $gate @('-Action','status')).Text, 'sha256=([0-9A-Fa-f]{64})').Groups[1].Value
}
function Write-GatePatch([string]$Name, [string]$Body) {
  $p = Join-Path (Split-Path -Parent $gate) $Name
  [IO.File]::WriteAllText($p, $Body, (New-Object Text.UTF8Encoding($false)))
  return $p
}
$st = Run $gate @('-Action', 'status')
$sha0 = [regex]::Match($st.Text, 'sha256=([0-9A-Fa-f]{64})').Groups[1].Value
Check 'ledger_status_reports_sha256' ($st.Code -eq 0 -and $st.Text -match 'LEDGER_STATE' -and $sha0.Length -eq 64) ('exit=' + $st.Code + ' sha16=' + $sha0.Substring(0, 16))
$gp = Write-GatePatch 'gate-note.json' '{"notes_append":["gate note from selftest"]}'
$c1 = Run $gate @('-Action', 'commit', '-ExpectSha256', $sha0, '-Patch', $gp)
$sha1 = [regex]::Match($c1.Text, 'after=([0-9A-Fa-f]{64})').Groups[1].Value
Check 'ledger_commit_ok' ($c1.Code -eq 0 -and $c1.Text -match 'LEDGER_COMMITED' -and $sha1.Length -eq 64) ('exit=' + $c1.Code + ' tail=' + (($c1.Text -split "`n" | Select-Object -Last 1)))
Check 'ledger_sha_advanced_after_commit' ($sha1.Length -eq 64 -and $sha1 -ne $sha0) ('before=' + $sha0.Substring(0, 16) + ' after=' + $sha1.Substring(0, 16))
$led5b = Get-Content -LiteralPath (Join-Path $r5 'docs\relay.json') -Raw | ConvertFrom-Json
$noteHits = @($led5b.notes | Where-Object { $_ -eq 'gate note from selftest' }).Count
Check 'ledger_note_appended_once' ($noteHits -eq 1) ('count=' + $noteHits)
$c2 = Run $gate @('-Action', 'commit', '-ExpectSha256', $sha0, '-Patch', $gp)
Check 'ledger_stale_sha_refused_as_cas_conflict' ($c2.Code -eq 3 -and $c2.Text -match 'cas_conflict') ('exit=' + $c2.Code)
$gBad = Write-GatePatch 'gate-bad-key.json' '{"bogus_key":1}'
$c3 = Run $gate @('-Action', 'commit', '-ExpectSha256', (Get-GateSha), '-Patch', $gBad)
Check 'ledger_unknown_patch_key_refused' ($c3.Code -eq 2 -and $c3.Text -match 'patch_unknown_key') ('exit=' + $c3.Code)
$gRun = Write-GatePatch 'gate-running.json' '{"set_status":"running"}'
$c4 = Run $gate @('-Action', 'commit', '-ExpectSha256', (Get-GateSha), '-Patch', $gRun)
Check 'ledger_status_running_is_human_only' ($c4.Code -eq 3 -and $c4.Text -match 'status_running_is_human_only') ('exit=' + $c4.Code)
$gApp = Write-GatePatch 'gate-append-stage.json' '{"append_stage":{"id":99,"title":"Selftest stage"}}'
$ca = Run $gate @('-Action', 'commit', '-ExpectSha256', (Get-GateSha), '-Patch', $gApp)
Check 'ledger_append_stage_ok' ($ca.Code -eq 0 -and $ca.Text -match 'LEDGER_COMMITED') ('exit=' + $ca.Code)
$gOwn = Write-GatePatch 'gate-owner-fields.json' '{"stage_done":99,"stage_fields":{"deliverable":"owner-authored"}}'
$co = Run $gate @('-Action', 'commit', '-ExpectSha256', (Get-GateSha), '-Patch', $gOwn)
Check 'ledger_owner_stage_fields_accepted' ($co.Code -eq 0 -and $co.Text -match 'LEDGER_COMMITED') ('exit=' + $co.Code)
$gHij = Write-GatePatch 'gate-hijack.json' '{"stage_fields":{"title":"HIJACKED"}}'
$shaA = Get-GateSha
$c5 = Run $gate @('-Action', 'commit', '-ExpectSha256', $shaA, '-Patch', $gHij)
Check 'ledger_foreign_stage_field_refused' ($c5.Code -eq 2 -and $c5.Text -match 'stage_fields_without_stage_done') ('exit=' + $c5.Code)
$shaB = Get-GateSha
$d1 = Run $gate @('-Action', 'commit', '-ExpectSha256', $shaB, '-Patch', $gp, '-DryRun')
$shaC = Get-GateSha
$lockLeft = @(Get-ChildItem -LiteralPath (Split-Path -Parent $gate) -Force -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -like '*ledger.lock*' }).Count
Check 'ledger_dryrun_is_non_destructive' ($d1.Code -eq 0 -and $d1.Text -match 'LEDGER_DRYRUN' -and $shaC -eq $shaB -and $lockLeft -eq 0) ('exit=' + $d1.Code + ' sha_same=' + ($shaC -eq $shaB) + ' locks=' + $lockLeft)
$gConc = Write-GatePatch 'gate-conc.json' '{"notes_append":["concurrent writer"]}'
$shaD = Get-GateSha
$jobBody = { param($g,$s,$p) $exe = (Get-Process -Id $PID).Path; $o = & $exe -NoProfile -ExecutionPolicy Bypass -File $g -Action commit -ExpectSha256 $s -Patch $p 2>&1 | Out-String; return ('CODE=' + $LASTEXITCODE + ' ' + $o) }
$jA = Start-Job -ScriptBlock $jobBody -ArgumentList $gate,$shaD,$gConc
$jB = Start-Job -ScriptBlock $jobBody -ArgumentList $gate,$shaD,$gConc
$null = $jA,$jB | Wait-Job -Timeout 120
$tA = ($jA | Receive-Job) -join ' '
$tB = ($jB | Receive-Job) -join ' '
$wins = @($tA,$tB | Where-Object { $_ -match 'CODE=0' -and $_ -match 'LEDGER_COMMITED' }).Count
$refused = @($tA,$tB | Where-Object { $_ -match 'cas_conflict' -or $_ -match 'lock_timeout' -or $_ -match 'CODE=[1-9]' }).Count
Check 'ledger_single_writer_under_concurrency' ($wins -eq 1 -and $refused -eq 1 -and ($wins + $refused) -eq 2) ('wins=' + $wins + ' refused=' + $refused)
$e1 = Run $gate @('-Action', 'commit', '-ExpectSha256', (Get-GateSha), '-Patch', $gConc)
$lockLeft2 = @(Get-ChildItem -LiteralPath (Split-Path -Parent $gate) -Force -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -like '*ledger.lock*' }).Count
Check 'ledger_locks_cleared_after_race' ($e1.Code -eq 0 -and $lockLeft2 -eq 0) ('exit=' + $e1.Code + ' locks=' + $lockLeft2)

# --- case 11: device == templates right now ------------------------------------
$drift = @()
foreach ($name in @('start-relay.ps1', 'relay-lock.ps1', 'relay-ledger.ps1')) {
  if ((Hash16 (Join-Path $tplDir $name)) -ne (Hash16 (Join-Path $repoRoot ('device\' + $name)))) { $drift += $name }
}
Check 'device_matches_templates' ($drift.Count -eq 0) ('drift=' + ($drift -join ','))

# --- verdict -------------------------------------------------------------------
Say ('SUITE_END pass=' + $script:pass + ' fail=' + $script:fail + ' root=' + $script:root)
Say ('MANUAL_STEP real_session_activation: this suite never calls session_create. One live chain per changed ' +
  'kit is still an agent-side step; see tool\references\selftest-*.md for how it was last verified.')
if (-not [string]::IsNullOrWhiteSpace($EvidencePath)) {
  if (-not [IO.Path]::IsPathRooted($EvidencePath)) { Say 'WARN evidence_path_not_absolute_ignored' }
  else {
    New-Item -ItemType Directory -Path (Split-Path -Parent $EvidencePath) -Force | Out-Null
    [IO.File]::WriteAllText($EvidencePath, (($log -join "`n") + "`n"), (New-Object Text.UTF8Encoding($false)))
    Say ('EVIDENCE written=' + $EvidencePath + ' bytes=' + (Get-Item -LiteralPath $EvidencePath).Length)
  }
}
if ($Cleanup) {
  Remove-Item -LiteralPath $script:root -Recurse -Force -ErrorAction SilentlyContinue
  Say ('CLEANUP removed=' + $script:root)
}
if ($script:fail -gt 0) { exit 1 }
exit 0
