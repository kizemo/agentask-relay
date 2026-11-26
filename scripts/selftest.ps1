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
foreach ($need in @($installer, (Join-Path $tplDir 'start-relay.ps1'), (Join-Path $tplDir 'relay-lock.ps1'), (Join-Path $tplDir 'relay-ledger.ps1'), (Join-Path $tplDir 'relay-spawn.ps1'), (Join-Path $tplDir 'AGENTS-RELAY-BLOCK.md'))) {
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

# --- case 9b: ledger write gate (candidate #8) -----------------------------------
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

# --- case 12: launcher plan chain, gate/lock ordering (B7 candidate #8) --------
# Cases 5-8 cover probe / missing / real activation / second activation. The gaps
# closed here: -PlanDoc as a source, ledger plan_doc beating a decoy on disk,
# ambiguous probe picking the newest, the blocked and unparsable gates firing
# BEFORE plan resolution, lock refusal as the third way a second activation dies,
# and -StageTitles reaching the prompt verbatim. Every negative case uses -DryRun
# or a repo without docs\relay.json so nothing here needs session_create.
function New-LauncherRepo([string]$Name) {
  $d = New-Repo $Name
  New-Item -ItemType Directory -Path (Join-Path $d 'docs\relay') -Force | Out-Null
  Copy-Item -LiteralPath (Join-Path $tplDir 'start-relay.ps1') -Destination (Join-Path $d 'docs\relay\start-relay.ps1') -Force
  return $d
}
function New-LedgerJson([hashtable]$Over) {
  $base = [ordered]@{
    goal = 'gate batch'; plan_doc = ''; workspace_dir = 'X'; status = 'idle'; auto_relay = $true
    current_stage = 0; max_stages = 3; next_session_id = $null
    stages = @(); sessions = @(); notes = @(); blocked_on = @()
  }
  foreach ($k in $Over.Keys) { $base[$k] = $Over[$k] }
  return ($base | ConvertTo-Json -Depth 6)
}
function Write-Ledger([string]$Dir, [string]$Body) {
  $p = Join-Path $Dir 'docs\relay.json'
  [IO.File]::WriteAllText($p, $Body, (New-Object Text.UTF8Encoding($false)))
  return $p
}

# 12a: -PlanDoc that does not exist is refused, echoed with source=argument
$r12a = New-LauncherRepo 'repo-plan-arg-missing'
$k12a = Join-Path $r12a 'docs\relay\start-relay.ps1'
$f12a = Run $k12a @('-Target', 'arg batch', '-PlanDoc', 'docs\nope.md', '-DryRun')
Check 'plan_arg_missing_exit_two' ($f12a.Code -eq 2) ('exit=' + $f12a.Code)
Check 'plan_arg_missing_reason' (($f12a.Text -match 'FAIL reason=plan_doc_not_found') -and ($f12a.Text -match 'source=argument')) ('line=' + (((($f12a.Text -split "`n") | Where-Object { $_ -match 'plan_doc_not_found' } | Select-Object -First 1))))
Check 'plan_arg_missing_no_lock' (-not (Test-Path (Join-Path $r12a 'docs\relay\.relay.lock'))) ''

# 12b: plan_doc in the ledger outranks a second plan file on disk (no ambiguity warning)
$r12b = New-LauncherRepo 'repo-plan-from-ledger'
$k12b = Join-Path $r12b 'docs\relay\start-relay.ps1'
Set-Content -LiteralPath (Join-Path $r12b 'docs\plan-real.md') -Value '# real ledger plan' -Encoding utf8
Set-Content -LiteralPath (Join-Path $r12b 'docs\plan-qq.md') -Value '# decoy plan' -Encoding utf8
$null = Write-Ledger $r12b (New-LedgerJson @{ plan_doc = 'docs\plan-real.md' })
$f12b = Run $k12b @('-Target', 'ledger batch', '-DryRun')
Check 'plan_from_ledger_exit_zero' ($f12b.Code -eq 0) ('exit=' + $f12b.Code + ' tail=' + (($f12b.Text -split "`n" | Select-Object -Last 2) -join ' | '))
Check 'plan_from_ledger_source' ($f12b.Text -match 'OK plan_doc=docs[\\/]plan-real\.md source=ledger') ('line=' + (((($f12b.Text -split "`n") | Where-Object { $_ -match 'plan_doc=' } | Select-Object -First 1))))
Check 'plan_from_ledger_no_ambiguity_warn' (-not ($f12b.Text -match 'plan_doc_ambiguous')) ('warn=' + (((($f12b.Text -split "`n") | Where-Object { $_ -match 'ambiguous' } | Select-Object -First 1))))

# 12c: ambiguous probe picks the newest candidate and says so
$r12c = New-LauncherRepo 'repo-plan-ambiguous'
$k12c = Join-Path $r12c 'docs\relay\start-relay.ps1'
$old12c = Join-Path $r12c 'docs\plan-old.md'
$new12c = Join-Path $r12c 'docs\plan-new.md'
Set-Content -LiteralPath $old12c -Value '# stale plan' -Encoding utf8
Set-Content -LiteralPath $new12c -Value '# fresher plan' -Encoding utf8
(Get-Item -LiteralPath $old12c).LastWriteTime = (Get-Date).AddHours(-3)
(Get-Item -LiteralPath $new12c).LastWriteTime = (Get-Date).AddMinutes(-1)
$f12c = Run $k12c @('-Target', 'amb probe batch', '-MaxStages', '2', '-DryRun')
Check 'plan_ambiguous_warns' ($f12c.Text -match 'WARN plan_doc_ambiguous candidates=2' -and $f12c.Text -match 'by=newest_mtime' -and $f12c.Text -match 'pass_-PlanDoc_to_disambiguate') ('line=' + (((($f12c.Text -split "`n") | Where-Object { $_ -match 'plan_doc_ambiguous' } | Select-Object -First 1))))
Check 'plan_ambiguous_picks_newest' ($f12c.Text -match 'source=probe_newest_of_2' -and $f12c.Text -match 'picked=docs[\\/]plan-new\.md') ('line=' + (((($f12c.Text -split "`n") | Where-Object { $_ -match 'probe_found|picked=' } | Select-Object -First 1))))
Check 'plan_ambiguous_does_not_refuse' ($f12c.Code -eq 0) ('exit=' + $f12c.Code)

# 12d: a blocked ledger is refused before the plan is ever resolved
$r12d = New-LauncherRepo 'repo-plan-blocked'
$k12d = Join-Path $r12d 'docs\relay\start-relay.ps1'
$null = Write-Ledger $r12d (New-LedgerJson @{ status = 'blocked'; blocked_on = @('needs a human decision on scope'); max_stages = 2 })
$f12d = Run $k12d @('-Target', 'blocked batch', '-DryRun')
Check 'blocked_ledger_exit_three' ($f12d.Code -eq 3) ('exit=' + $f12d.Code)
Check 'blocked_ledger_lines' ($f12d.Text -match 'WARN reason=ledger_blocked' -and $f12d.Text -match 'blocked_on=needs a human decision' -and $f12d.Text -match 'HINT=blocked chains need a human decision') ('line=' + (((($f12d.Text -split "`n") | Where-Object { $_ -match 'ledger_blocked' } | Select-Object -First 1))))
Check 'blocked_ledger_precedes_plan_resolution' (-not ($f12d.Text -match 'plan_doc_missing')) ('tail=' + (($f12d.Text -split "`n" | Select-Object -Last 2) -join ' | '))

# 12e: an unparsable ledger is refused, left byte-identical, and takes no lock
$r12e = New-LauncherRepo 'repo-ledger-garbage'
$k12e = Join-Path $r12e 'docs\relay\start-relay.ps1'
$gp12e = Write-Ledger $r12e '{ "goal": "broken'
$sha12e = Hash16 $gp12e
$f12e = Run $k12e @('-Target', 'garbage batch', '-DryRun')
Check 'garbage_ledger_exit_three' ($f12e.Code -eq 3 -and $f12e.Text -match 'FAIL reason=ledger_unparsable') ('exit=' + $f12e.Code)
Check 'garbage_ledger_left_untouched' ((Hash16 $gp12e) -eq $sha12e) ('before=' + $sha12e + ' after=' + (Hash16 $gp12e))
Check 'garbage_ledger_no_lock' (-not (Test-Path (Join-Path $r12e 'docs\relay\.relay.lock'))) ''

# 12f: gate passes, lock refuses (exit 4). The ledger must not be rewritten.
$r12f = New-Repo 'repo-lock-refusal'
Set-Content -LiteralPath (Join-Path $r12f 'docs\plan-lock.md') -Value '# lock plan' -Encoding utf8
$null = Run $installer @('-RepoRoot', $r12f, '-Target', 'lock batch', '-PlanDoc', 'docs\plan-lock.md', '-MaxStages', '3')
$k12f = Join-Path $r12f 'docs\relay\start-relay.ps1'
$p12f1 = Join-Path $r12f 'docs\relay\prompt-one.txt'
$p12f2 = Join-Path $r12f 'docs\relay\prompt-two.txt'
$g12f1 = Run $k12f @('-Target', 'lock batch', '-MaxStages', '3', '-PlanDoc', 'docs\plan-lock.md', '-PromptOut', $p12f1)
Check 'lock_case_first_run_ok' ($g12f1.Code -eq 0 -and (Test-Path $p12f1) -and (Test-Path (Join-Path $r12f 'docs\relay.json'))) ('exit=' + $g12f1.Code + ' tail=' + (($g12f1.Text -split "`n" | Select-Object -Last 2) -join ' | '))
$led12f = Join-Path $r12f 'docs\relay.json'
$sha12f = Hash16 $led12f
$g12f2 = Run $k12f @('-Target', 'lock batch', '-MaxStages', '3', '-PlanDoc', 'docs\plan-lock.md', '-PromptOut', $p12f2)
Check 'lock_case_second_run_refused_by_lock' ($g12f2.Code -eq 4 -and $g12f2.Text -match 'FAIL reason=lock_unavailable exit=') ('exit=' + $g12f2.Code + ' line=' + (((($g12f2.Text -split "`n") | Where-Object { $_ -match 'FAIL reason=' } | Select-Object -First 1))))
Check 'lock_case_second_run_wrote_no_prompt' (-not (Test-Path $p12f2)) ('present=' + (Test-Path $p12f2))
Check 'lock_case_second_run_kept_ledger' ((Hash16 $led12f) -eq $sha12f) ('before=' + $sha12f + ' after=' + (Hash16 $led12f))

# 12g: -StageTitles is spliced into the prompt verbatim; the default line appears without it
$r12g = New-LauncherRepo 'repo-stage-titles'
$k12g = Join-Path $r12g 'docs\relay\start-relay.ps1'
Set-Content -LiteralPath (Join-Path $r12g 'docs\plan-t.md') -Value '# titles plan' -Encoding utf8
$titles12g = 'alpha|beta|gamma'
$h12g1 = Run $k12g @('-Target', 'titles batch', '-PlanDoc', 'docs\plan-t.md', '-StageTitles', $titles12g, '-DryRun')
Check 'stage_titles_preview_framed' ($h12g1.Text -match 'DRYRUN prompt_preview_begin' -and $h12g1.Text -match 'DRYRUN prompt_preview_end' -and $h12g1.Text -match 'STAGE PLAN:') ''
Check 'stage_titles_verbatim' ($h12g1.Text -match [regex]::Escape($titles12g)) ('tail=' + (($h12g1.Text -split "`n" | Select-Object -Last 2) -join ' | '))
$h12g2 = Run $k12g @('-Target', 'titles batch', '-PlanDoc', 'docs\plan-t.md', '-DryRun')
Check 'stage_titles_default_line' ($h12g2.Text -match '1\. stage 1 scope inventory' -and -not ($h12g2.Text -match 'alpha')) ('matched_default=' + ($h12g2.Text -match '1\. stage 1 scope inventory'))

# --- case 13: AGENTS.md adjudication + shipped-file invariants (B7 #8/#9b) -----
# 13a: -Force replaces the managed block, never the project prose around it
$r13a = New-Repo 'repo-force'
$ag13a = Join-Path $r13a 'AGENTS.md'
Set-Content -LiteralPath (Join-Path $r13a 'docs\plan-f.md') -Value '# force plan' -Encoding utf8
$null = Run $installer @('-RepoRoot', $r13a, '-Target', 'force batch', '-PlanDoc', 'docs\plan-f.md', '-MaxStages', '2')
$t13a = [IO.File]::ReadAllText($ag13a).Replace($endMark, ('SENTINEL-inside-managed-block' + "`n" + $endMark))
[IO.File]::WriteAllText($ag13a, $t13a, (New-Object Text.UTF8Encoding($false)))
$a13a = Run $installer @('-RepoRoot', $r13a, '-Target', 'force batch', '-PlanDoc', 'docs\plan-f.md', '-MaxStages', '2', '-Force')
$a13aAfter = [IO.File]::ReadAllText($ag13a)
Check 'force_action_replaced' ($a13a.Text -match 'AGENTS action=replaced') ('line=' + (((($a13a.Text -split "`n") | Where-Object { $_ -match 'AGENTS action=' } | Select-Object -First 1))))
Check 'force_single_marker_pair' ((CountOf $ag13a $beginMark) -eq 1 -and (CountOf $ag13a $endMark) -eq 1) ('begin=' + (CountOf $ag13a $beginMark) + ' end=' + (CountOf $ag13a $endMark))
Check 'force_machine_markers_echoed' ($a13a.Text -match 'AGENTS_MARKERS begin=1 end=1') ('line=' + (((($a13a.Text -split "`n") | Where-Object { $_ -match 'AGENTS_MARKERS' } | Select-Object -First 1))))
Check 'force_dropped_injected_line' (-not $a13aAfter.Contains('SENTINEL-inside-managed-block')) ''
Check 'force_kept_project_prose' ($a13aAfter.Contains('Be nice.') -and $a13aAfter.Contains('# repo-force rules')) ('has_prose=' + $a13aAfter.Contains('Be nice.'))

# 13b: a pre-existing relay section found by the TITLE criterion is adopted in place
$r13b = New-Repo 'repo-adopt-title'
$ag13b = Join-Path $r13b 'AGENTS.md'
Set-Content -LiteralPath (Join-Path $r13b 'docs\plan-a.md') -Value '# adopt plan' -Encoding utf8
$adopt13b = @('# Rules', '', '## Auto Relay (manual)', '', 'Only one writer may advance the chain at a time.', '', '## Other rules', '', 'Keep commit messages in English.') -join "`n"
[IO.File]::WriteAllText($ag13b, $adopt13b + "`n", (New-Object Text.UTF8Encoding($false)))
$a13b = Run $installer @('-RepoRoot', $r13b, '-Target', 'adopt batch', '-PlanDoc', 'docs\plan-a.md')
$a13bAfter = [IO.File]::ReadAllText($ag13b)
Check 'adopt_title_action_and_reason' ($a13b.Text -match 'AGENTS action=adopted reason=title') ('line=' + (((($a13b.Text -split "`n") | Where-Object { $_ -match 'AGENTS action=' } | Select-Object -First 1))))
Check 'adopt_title_single_pair' ((CountOf $ag13b $beginMark) -eq 1 -and (CountOf $ag13b $endMark) -eq 1) ('begin=' + (CountOf $ag13b $beginMark) + ' end=' + (CountOf $ag13b $endMark))
Check 'adopt_title_keeps_both_sections' ($a13bAfter.Contains('Only one writer may advance the chain at a time.') -and $a13bAfter.Contains('Keep commit messages in English.')) ''

# 13c: markers present but no locatable block -> present_unparsed, file untouched
$r13c = New-Repo 'repo-unparsed'
$ag13c = Join-Path $r13c 'AGENTS.md'
Set-Content -LiteralPath (Join-Path $r13c 'docs\plan-u.md') -Value '# unparsed plan' -Encoding utf8
$bad13c = '# Rules' + "`n`n" + $endMark + "`n" + 'orphan managed text with the end marker first' + "`n" + $beginMark + "`n"
[IO.File]::WriteAllText($ag13c, $bad13c, (New-Object Text.UTF8Encoding($false)))
$sha13c = Hash16 $ag13c
$a13c = Run $installer @('-RepoRoot', $r13c, '-Target', 'unparsed batch', '-PlanDoc', 'docs\plan-u.md')
Check 'unparsed_action_no_guess' ($a13c.Text -match 'AGENTS action=present_unparsed reason=n/a') ('line=' + (((($a13c.Text -split "`n") | Where-Object { $_ -match 'AGENTS action=' } | Select-Object -First 1))))
Check 'unparsed_left_file_bytes' ((Hash16 $ag13c) -eq $sha13c) ('before=' + $sha13c + ' after=' + (Hash16 $ag13c))
Check 'unparsed_added_no_second_block' ((CountOf $ag13c $beginMark) -eq 1) ('begin=' + (CountOf $ag13c $beginMark))

# 13d: a stray one-sided marker is warned about, stripped, then normal rules apply
$r13d = New-Repo 'repo-stray-marker'
$ag13d = Join-Path $r13d 'AGENTS.md'
Set-Content -LiteralPath (Join-Path $r13d 'docs\plan-s.md') -Value '# stray plan' -Encoding utf8
$stray13d = '# Rules' + "`n`n" + $beginMark + "`n`n## Relay chain`n`nHand-written chain rules." + "`n"
[IO.File]::WriteAllText($ag13d, $stray13d, (New-Object Text.UTF8Encoding($false)))
$a13d = Run $installer @('-RepoRoot', $r13d, '-Target', 'stray batch', '-PlanDoc', 'docs\plan-s.md')
$a13dAfter = [IO.File]::ReadAllText($ag13d)
Check 'stray_marker_warned' ($a13d.Text -match 'WARN agents_markers_corrupt stray_marker_removed') ('line=' + (((($a13d.Text -split "`n") | Where-Object { $_ -match 'agents_markers_corrupt' } | Select-Object -First 1))))
Check 'stray_marker_then_dual_criteria' ($a13d.Text -match 'AGENTS action=(adopted|appended)') ('line=' + (((($a13d.Text -split "`n") | Where-Object { $_ -match 'AGENTS action=' } | Select-Object -First 1))))
Check 'stray_marker_pair_after_fix' ((CountOf $ag13d $beginMark) -eq 1 -and (CountOf $ag13d $endMark) -eq 1) ('begin=' + (CountOf $ag13d $beginMark) + ' end=' + (CountOf $ag13d $endMark))
Check 'stray_marker_kept_section_text' ($a13dAfter.Contains('Hand-written chain rules.')) ''

# 13e: the protocol mirror under protocol\ must equal the shipped template byte for byte
$mirrorTpl = Hash16 (Join-Path $tplDir 'AGENT-RELAY.md')
$mirrorCopy = Hash16 (Join-Path $repoRoot 'protocol\AGENT-RELAY.md')
Check 'protocol_mirror_matches_template' ($mirrorCopy -eq $mirrorTpl -and $mirrorCopy -ne 'MISSING') ('tpl=' + $mirrorTpl + ' mirror=' + $mirrorCopy)

# 13f: protocol doc and the shipped scripts must not drift apart on failure literals
function Cross([string]$DocPath, [string]$CodePath, [string[]]$Tokens, [string]$Tag) {
  $docT = [IO.File]::ReadAllText($DocPath)
  $codeT = [IO.File]::ReadAllText($CodePath)
  $dm = @(); $cm = @()
  foreach ($tk in $Tokens) {
    if (@([regex]::Matches($docT, [regex]::Escape($tk))).Count -eq 0) { $dm += $tk }
    if (@([regex]::Matches($codeT, [regex]::Escape($tk))).Count -eq 0) { $cm += $tk }
  }
  return ($Tag + ' doc_missing=[' + ($dm -join ',') + '] code_missing=[' + ($cm -join ',') + ']')
}
$docRelay = Join-Path $tplDir 'AGENT-RELAY.md'
$lauLiterals = @('workspace_missing', 'not_a_git_repo', 'ledger_unparsable', 'stage_in_progress', 'one_writer_per_project', 'chain_already_running', 'chain_at_stage_cap', 'chain_exhausted', 'ledger_blocked', 'ledger_absent', 'plan_doc_not_found', 'plan_doc_missing', 'plan_doc_ambiguous', 'probe_newest_of_', 'by=newest_mtime', 'pass_-PlanDoc_to_disambiguate', 'lock_unavailable', 'DRYRUN skip=lock_acquire')
$insLiterals = @('agents_markers_corrupt', 'stray_marker_removed', 'AGENTS_MARKERS', 'CLAUDE_MARKERS', 'content_signature count=', 'agents_relay_section_ambiguous', 'appended_managed_block', 'keep_a_single_relay_section', 'present_kept', 'present_unparsed', 'replaced', 'adopted', 'appended')
$crossLau = Cross $docRelay (Join-Path $tplDir 'start-relay.ps1') $lauLiterals 'LAUNCHER'
$crossIns = Cross $docRelay $installer $insLiterals 'INSTALLER'
Check 'protocol_documents_launcher_literals' ($crossLau -match 'doc_missing=\[\] code_missing=\[\]') $crossLau
Check 'protocol_documents_installer_literals' ($crossIns -match 'doc_missing=\[\] code_missing=\[\]') $crossIns

# --- case 14: static portability audit of the shipped kit (candidate #5) ---------
# Absolute paths and home-dir literals are judged on CODE only (comment/help blocks
# are stripped): usage examples in the installer help legitimately show D:\work\myapp.
# Foreign project names are judged on the FULL text, header comments included.
function Get-KitCode([string]$t) {
  $u = [regex]::Replace($t, '(?s)<#.*?#>', ' ')
  $u = [regex]::Replace($u, '(?m)^\s*#.*$', ' ')
  return $u
}
$kitFiles = @()
$kitFiles += @(Get-ChildItem -LiteralPath $tplDir -File -Filter '*.ps1')
$kitFiles += @(Get-ChildItem -LiteralPath (Join-Path $repoRoot 'tool\scripts') -File -Filter '*.ps1')
$kitFiles += @(Get-ChildItem -LiteralPath (Join-Path $repoRoot 'device') -File -Filter '*.ps1')
$absBad = @(); $homeBad = @(); $projBad = @()
foreach ($f in $kitFiles) {
  $raw = [IO.File]::ReadAllText($f.FullName)
  $code = Get-KitCode $raw
  $rel = $f.FullName.Substring($repoRoot.Length + 1)
  if ($code -match '[A-Za-z]:\\') { $absBad += $rel }
  if ($code -match 'USERPROFILE|\$HOME|\.minimax') { $homeBad += $rel }
  if ($raw -match 'PractiLog') { $projBad += $rel }
}
Check 'kit_scanned_file_count' ($kitFiles.Count -ge 7) ('scanned=' + $kitFiles.Count)
Check 'kit_no_absolute_paths_in_code' ($absBad.Count -eq 0) ('files=' + ($absBad -join ' ') + ' scanned=' + $kitFiles.Count)
Check 'kit_no_home_literals_in_code' ($homeBad.Count -eq 0) ('files=' + ($homeBad -join ' ') + ' scanned=' + $kitFiles.Count)
Check 'kit_no_foreign_project_name' ($projBad.Count -eq 0) ('files=' + ($projBad -join ' ') + ' scanned=' + $kitFiles.Count)
$adaptDoc = [IO.File]::ReadAllText((Join-Path $tplDir 'RELAY-ADAPTATION.md'))
Check 'kit_device_specific_ids_flagged' ($adaptDoc.Contains('provider-') -and $adaptDoc.Contains('device-specific, refill')) ('has_provider_id=' + $adaptDoc.Contains('provider-') + ' has_refill_note=' + $adaptDoc.Contains('device-specific, refill'))

# --- case 15: global skill root resolution in publish-relay.ps1 (finding F4) -----
# F4 was found by the portability audit and fixed on 2026-11-25 under a human ruling.
# The default root used to be probed only under the user profile directory, but the active
# desktop profile can live on another volume, so the gate reported skill_root_not_found /
# exit 3 on a machine where the skill really was installed and pushed every caller to pass
# -SkillRoot by hand. The probe now walks the data-dir variables, $HOME / %USERPROFILE%
# (each with the profile sub-variants) and the same relative profile path on every
# filesystem drive, with no path hardcoded. These cases pin that: explicit parameter and
# environment pin must win, the probe branch must stay generic, and a genuinely absent
# root must still fail loudly instead of silently verifying against nothing.
$pubRelay = Join-Path $repoRoot 'scripts\publish-relay.ps1'
$pubRaw = [IO.File]::ReadAllText($pubRelay)
$pubCode = Get-KitCode $pubRaw
$pubNeed = @('Get-RelaySkillCandidate', 'Get-PSDrive', 'skill_root_candidates', 'skill_root_ambiguous', 'RELAY_PORT_SKILL_ROOT', 'MAVIS_DATA_DIR', 'v2\sessions', '.minimax\.minimax', 'skill_root_not_found')
$pubMissing = @()
foreach ($n in $pubNeed) { if (-not $pubCode.Contains($n)) { $pubMissing += $n } }
Check 'publish_probe_tokens_present' ($pubMissing.Count -eq 0) ('missing=' + ($pubMissing -join ',') + ' wanted=' + $pubNeed.Count)
$pubDriveHits = [regex]::Matches($pubCode, '[A-Za-z]:\\').Count
Check 'publish_probe_has_no_hardcoded_drive' ($pubDriveHits -eq 0) ('drive_literals_in_code=' + $pubDriveHits)
$pubDocNeed = @('drive scan for the same relative profile path', 'skill_root_ambiguous')
$pubDocMissing = @()
foreach ($n in $pubDocNeed) { if (-not $pubRaw.Contains($n)) { $pubDocMissing += $n } }
Check 'publish_skill_root_doc_describes_probe' ($pubDocMissing.Count -eq 0) ('missing=' + ($pubDocMissing -join ';'))
$sentEnv = Join-Path $script:root 'skill-root-env-pinned'
$sentArg = Join-Path $script:root 'skill-root-arg-pinned'
$env:RELAY_PORT_SKILL_ROOT = $sentEnv
$runEnv = Run $pubRelay @('-Direction', 'verify')
Check 'publish_skill_root_env_pin' ($runEnv.Text.Contains('skill_root=' + $sentEnv + ' via=env') -and $runEnv.Code -ne 3) ('code=' + $runEnv.Code + ' pinned=' + $sentEnv)
$runArg = Run $pubRelay @('-Direction', 'verify', '-SkillRoot', $sentArg)
Check 'publish_skill_root_parameter_wins' ($runArg.Text.Contains('skill_root=' + $sentArg + ' via=parameter') -and $runArg.Code -ne 3) ('code=' + $runArg.Code + ' pinned=' + $sentArg + ' env_was=' + $sentEnv)
$env:RELAY_PORT_SKILL_ROOT = ''
$runProbe = Run $pubRelay @('-Direction', 'verify')
$probeLine = ''
foreach ($ln in ($runProbe.Text -split "`n")) { if ($ln -match 'skill_root=') { $probeLine = $ln; break } }
$probeOk = ($probeLine -match 'via=probe(-multi)?$')
$probeRoot = ''
if ($probeOk -and ($probeLine -match 'skill_root=(.*?) via=')) { $probeRoot = $Matches[1] }
$probeExists = ($probeRoot -ne '') -and (Test-Path -LiteralPath $probeRoot -PathType Container)
$loudFail = ($runProbe.Code -eq 3) -and $runProbe.Text.Contains('skill_root_not_found') -and $runProbe.Text.Contains('every_drive')
Check 'publish_skill_root_probe_branch' (($probeOk -and $probeExists) -or $loudFail) ('line=' + $probeLine + ' code=' + $runProbe.Code + ' root_exists=' + $probeExists + ' loud_fail=' + $loudFail)

# --- case 16: runtime adaptation layer (B9) -------------------------------------
# One kit, four runtimes. The runtime decides two things: which instruction files
# carry the managed rule block, and how the next link is started. Claude Code is the
# case that needs the most care: it reads CLAUDE.md first and only falls back to
# AGENTS.md when the repo has NO CLAUDE.md, so a repo that already ships a CLAUDE.md
# would shadow the whole relay block -- the kit would look installed while the chain
# never starts. Hence claude-code writes both files; the other three write AGENTS.md.
$r16a = New-Repo 'repo-runtime-cc'
Set-Content -LiteralPath (Join-Path $r16a 'docs\plan-cc.md') -Value '# cc plan' -Encoding utf8
$c16a = Run $installer @('-RepoRoot', $r16a, '-Target', 'cc batch', '-PlanDoc', 'docs\plan-cc.md', '-MaxStages', '2', '-Runtime', 'claude-code')
Check 'runtime_cc_install_exit_zero' ($c16a.Code -eq 0) ('exit=' + $c16a.Code)
Check 'runtime_cc_install_verdict_pass' ($c16a.Text -match 'INSTALL_VERDICT=PASS') ('tail=' + (($c16a.Text -split "`n" | Select-Object -Last 3) -join ' | '))
Check 'runtime_cc_agents_block' ((CountOf (Join-Path $r16a 'AGENTS.md') $beginMark) -eq 1) ('begin=' + (CountOf (Join-Path $r16a 'AGENTS.md') $beginMark))
Check 'runtime_cc_claude_block' ((CountOf (Join-Path $r16a 'CLAUDE.md') $beginMark) -eq 1) ('begin=' + (CountOf (Join-Path $r16a 'CLAUDE.md') $beginMark))
Check 'runtime_cc_markers_echoed' ($c16a.Text -match 'AGENTS_MARKERS begin=1 end=1' -and $c16a.Text -match 'CLAUDE_MARKERS begin=1 end=1') ''
Check 'runtime_cc_reported' ($c16a.Text -match 'INSTALL_RUNTIME=claude-code') ''
$blk16a = [IO.File]::ReadAllText((Join-Path $r16a 'AGENTS.md'))
Check 'runtime_cc_block_carries_spawn_rule' ($blk16a.Contains('Claude Code has no `session_create` tool')) ''
$act16a = [IO.File]::ReadAllText((Join-Path $r16a 'docs\relay\ACTIVATION-PROMPT.txt'))
Check 'runtime_cc_activation_packet' ($act16a.Contains('-Runtime claude-code') -and $act16a.Contains('RELAY_SPAWN_OK runtime=claude-code')) ''

$r16b = New-Repo 'repo-runtime-cx'
Set-Content -LiteralPath (Join-Path $r16b 'docs\plan-cx.md') -Value '# cx plan' -Encoding utf8
$c16b = Run $installer @('-RepoRoot', $r16b, '-Target', 'cx batch', '-PlanDoc', 'docs\plan-cx.md', '-MaxStages', '2', '-Runtime', 'codex')
Check 'runtime_cx_install_exit_zero' ($c16b.Code -eq 0) ('exit=' + $c16b.Code)
Check 'runtime_cx_agents_block' ((CountOf (Join-Path $r16b 'AGENTS.md') $beginMark) -eq 1) ''
Check 'runtime_cx_no_claude_file' (-not (Test-Path (Join-Path $r16b 'CLAUDE.md'))) ''
$blk16b = [IO.File]::ReadAllText((Join-Path $r16b 'AGENTS.md'))
Check 'runtime_cx_block_carries_spawn_rule' ($blk16b.Contains('Codex CLI has no `session_create` tool')) ''

$r16d = New-Repo 'repo-runtime-oc'
Set-Content -LiteralPath (Join-Path $r16d 'docs\plan-oc.md') -Value '# oc plan' -Encoding utf8
$c16d = Run $installer @('-RepoRoot', $r16d, '-Target', 'oc batch', '-PlanDoc', 'docs\plan-oc.md', '-MaxStages', '2', '-Runtime', 'openclaw')
Check 'runtime_oc_install_exit_zero' ($c16d.Code -eq 0) ('exit=' + $c16d.Code)
Check 'runtime_oc_agents_block' ((CountOf (Join-Path $r16d 'AGENTS.md') $beginMark) -eq 1) ''
$blk16d = [IO.File]::ReadAllText((Join-Path $r16d 'AGENTS.md'))
Check 'runtime_oc_block_carries_spawn_rule' ($blk16d.Contains('OpenClaw has no `session_create` tool')) ''

$r16c = New-Repo 'repo-runtime-bad'
Set-Content -LiteralPath (Join-Path $r16c 'docs\plan-bad.md') -Value '# bad plan' -Encoding utf8
$c16c = Run $installer @('-RepoRoot', $r16c, '-Target', 'bad batch', '-PlanDoc', 'docs\plan-bad.md', '-MaxStages', '2', '-Runtime', 'gemini-cli')
Check 'runtime_unknown_exit_2' ($c16c.Code -eq 2) ('exit=' + $c16c.Code)
Check 'runtime_unknown_loud' ($c16c.Text -match 'reason=runtime_unsupported') ('line=' + ((($c16c.Text -split "`n") | Where-Object { $_ -match 'runtime_unsupported' } | Select-Object -First 1)))

Check 'runtime_default_is_mcode' ($a.Text -match 'INSTALL_RUNTIME=mcode') ''
$act16m = [IO.File]::ReadAllText((Join-Path $r1 'docs\relay\ACTIVATION-PROMPT.txt'))
Check 'runtime_mcode_activation_uses_session_create' ($act16m.Contains('session_create')) ''
$runtimeShards16 = @(Get-ChildItem -LiteralPath $tplDir -File -Filter 'ACTIVATION-SPAWN-*.md')
Check 'runtime_shards_present' ($runtimeShards16.Count -eq 4) ('count=' + $runtimeShards16.Count)

$spawnTpl16 = Join-Path $tplDir 'relay-spawn.ps1'
Check 'spawn_installed_into_relay_dir' (Test-Path (Join-Path $r16a 'docs\relay\relay-spawn.ps1')) ''
Check 'spawn_device_copy_matches_template' ((Hash16 $spawnTpl16) -eq (Hash16 (Join-Path $repoRoot 'device\relay-spawn.ps1'))) ('tpl=' + (Hash16 $spawnTpl16) + ' dev=' + (Hash16 (Join-Path $repoRoot 'device\relay-spawn.ps1')))
$prompt16 = Join-Path $script:root 'relay-prompt-16.txt'
[IO.File]::WriteAllText($prompt16, ("next link prompt body`n"), (New-Object Text.UTF8Encoding($false)))
$s16e = Run $spawnTpl16 @('-Runtime', 'claude-code', '-PromptFile', $prompt16, '-WorkspaceDir', $r16a)
Check 'spawn_dryrun_exit_zero' ($s16e.Code -eq 0) ('exit=' + $s16e.Code)
Check 'spawn_dryrun_prints_command' ($s16e.Text -match 'SPAWN_COMMAND claude ' -and $s16e.Text -match '--output-format json') ''
Check 'spawn_dryrun_does_not_run' ($s16e.Text -match 'SPAWN_EXECUTE=false') ''
Check 'spawn_dryrun_prompt_not_inline' (-not ($s16e.Text -match 'next link prompt body')) ''
$s16f = Run $spawnTpl16 @('-Runtime', 'codex', '-PromptFile', $prompt16, '-WorkspaceDir', $r16b)
Check 'spawn_codex_dryrun' ($s16f.Code -eq 0 -and $s16f.Text -match 'SPAWN_COMMAND codex exec') ('exit=' + $s16f.Code)
$s16g = Run $spawnTpl16 @('-Runtime', 'mcode', '-PromptFile', $prompt16)
Check 'spawn_rejects_non_cli_runtime' ($s16g.Code -eq 2 -and $s16g.Text -match 'reason=runtime_not_cli') ('exit=' + $s16g.Code)
$s16h = Run $spawnTpl16 @('-Runtime', 'claude-code', '-PromptFile', (Join-Path $script:root 'no-such-prompt-16.txt'))
Check 'spawn_missing_prompt_file' ($s16h.Code -eq 2 -and $s16h.Text -match 'reason=prompt_file_missing') ('exit=' + $s16h.Code)

# --- case 17: runtime contract end to end (B10) -------------------------------
# B9 gave the kit a runtime adaptation layer, but the launcher still wrote an
# MCode-only hand-off prompt: a CLI chain was assembled correctly and then died
# at the first hand-off. Case 17 checks the contract that closes that gap: the
# installer stamps how the next link starts, the launcher reads that stamp back,
# and the prompt of a CLI runtime names the spawn driver instead of session_create.
$r17a = New-Repo 'repo-runtime-contract'
Set-Content -LiteralPath (Join-Path $r17a 'docs\plan-17.md') -Value '# plan 17' -Encoding utf8
$c17a = Run $installer @('-RepoRoot', $r17a, '-Target', 'contract batch', '-PlanDoc', 'docs\plan-17.md', '-MaxStages', '2', '-Runtime', 'claude-code')
Check 'contract_cc_install_exit_zero' ($c17a.Code -eq 0) ('exit=' + $c17a.Code)
$descPath17 = Join-Path $r17a 'docs\relay\relay-runtime.json'
Check 'contract_descriptor_present' (Test-Path $descPath17) ('path=' + $descPath17)
$desc17 = $null
if (Test-Path $descPath17) { $desc17 = Get-Content -LiteralPath $descPath17 -Raw -Encoding UTF8 | ConvertFrom-Json }
Check 'contract_descriptor_runtime' ($null -ne $desc17 -and $desc17.runtime -eq 'claude-code') ''
Check 'contract_descriptor_mode' ($null -ne $desc17 -and $desc17.next_link_mode -eq 'cli_driver') ''
Check 'contract_descriptor_command_portable' ($null -ne $desc17 -and ([string]$desc17.spawn_command).Contains('{REPO}') -and -not ([string]$desc17.spawn_command).Contains('{{REPO}}')) ('cmd=' + [string]$desc17.spawn_command)
Check 'contract_descriptor_rule_files' ($null -ne $desc17 -and @($desc17.rule_files).Count -eq 2) ('files=' + (@($desc17.rule_files) -join ','))
$start17 = Join-Path $r17a 'docs\relay\start-relay.ps1'
$s17a = Run $start17 @('-Target', 'contract batch', '-DryRun')
Check 'contract_launcher_reads_descriptor' ($s17a.Text -match 'OK runtime=claude-code source=descriptor') ('line=' + ((($s17a.Text -split "`n") | Where-Object { $_ -match 'OK runtime=' } | Select-Object -First 1)))
Check 'contract_prompt_has_stage_header' ($s17a.Text -match 'RELAY_STAGE=1') ''
Check 'contract_prompt_names_spawn_driver' ($s17a.Text -match 'relay-spawn\.ps1') ''
Check 'contract_prompt_has_spawn_command' ($s17a.Text -match 'relay-spawn\.ps1 -Runtime claude-code') ''
Check 'contract_prompt_no_session_create_call' (-not ($s17a.Text -match 'start the next stage with session_create')) ''
Check 'contract_prompt_forbids_session_create' ($s17a.Text -match 'never call it') ''
$s17d = Run $start17 @('-Target', 'bad runtime', '-Runtime', 'gemini-cli', '-DryRun')
Check 'contract_launcher_rejects_unknown_runtime' ($s17d.Code -eq 2 -and $s17d.Text -match 'reason=runtime_unsupported') ('exit=' + $s17d.Code)

$r17b = New-Repo 'repo-runtime-contract-mcode'
Set-Content -LiteralPath (Join-Path $r17b 'docs\plan-17m.md') -Value '# plan 17m' -Encoding utf8
$c17b = Run $installer @('-RepoRoot', $r17b, '-Target', 'contract mcode', '-PlanDoc', 'docs\plan-17m.md', '-MaxStages', '2')
Check 'contract_mcode_install_exit_zero' ($c17b.Code -eq 0) ('exit=' + $c17b.Code)
$desc17m = Get-Content -LiteralPath (Join-Path $r17b 'docs\relay\relay-runtime.json') -Raw -Encoding UTF8 | ConvertFrom-Json
Check 'contract_mcode_mode' ($desc17m.next_link_mode -eq 'session_tool') ''
Check 'contract_mcode_no_spawn_command' ([string]::IsNullOrWhiteSpace([string]$desc17m.spawn_command)) ('cmd=' + [string]$desc17m.spawn_command)
$s17b = Run (Join-Path $r17b 'docs\relay\start-relay.ps1') @('-Target', 'contract mcode', '-DryRun')
Check 'contract_mcode_launcher_runtime' ($s17b.Text -match 'OK runtime=mcode source=descriptor') ''
Check 'contract_mcode_prompt_uses_session_create' ($s17b.Text -match 'start the next stage with session_create using the same recipe') ''
Check 'contract_mcode_prompt_has_no_stage_header' (-not ($s17b.Text -match 'RELAY_STAGE=')) ''

$r17c = New-Repo 'repo-runtime-contract-oc'
Set-Content -LiteralPath (Join-Path $r17c 'docs\plan-17o.md') -Value '# plan 17o' -Encoding utf8
$c17c = Run $installer @('-RepoRoot', $r17c, '-Target', 'contract oc', '-PlanDoc', 'docs\plan-17o.md', '-MaxStages', '2', '-Runtime', 'openclaw')
Check 'contract_oc_install_exit_zero' ($c17c.Code -eq 0) ('exit=' + $c17c.Code)
$desc17o = Get-Content -LiteralPath (Join-Path $r17c 'docs\relay\relay-runtime.json') -Raw -Encoding UTF8 | ConvertFrom-Json
Check 'contract_oc_mode' ($desc17o.next_link_mode -eq 'sessions_spawn_tool') ''
$s17c = Run (Join-Path $r17c 'docs\relay\start-relay.ps1') @('-Target', 'contract oc', '-DryRun')
Check 'contract_oc_prompt_uses_sessions_spawn' ($s17c.Text -match 'sessions_spawn') ''
Check 'contract_oc_prompt_no_cli_driver' (-not ($s17c.Text -match 'relay-spawn\.ps1 -Runtime')) ''

$spawnInst17 = Join-Path $r17a 'docs\relay\relay-spawn.ps1'
$prompt17 = Join-Path $script:root 'relay-prompt-17.txt'
[IO.File]::WriteAllText($prompt17, ("stage two prompt`n"), (New-Object Text.UTF8Encoding($false)))
$s17e = Run $spawnInst17 @('-Runtime', 'claude-code', '-PromptFile', $prompt17, '-WorkspaceDir', $r17a, '-SessionId', 'not-a-uuid')
Check 'contract_spawn_rejects_bad_session_id' ($s17e.Code -eq 2 -and $s17e.Text -match 'reason=session_id_not_uuid') ('exit=' + $s17e.Code)
$uuid17 = '11111111-2222-3333-4444-555555555555'
$ledger17 = [ordered]@{ goal = 'contract batch'; status = 'running'; current_stage = 1; max_stages = 2; next_session_id = $uuid17; stages = @(); sessions = @() }
[IO.File]::WriteAllText((Join-Path $r17a 'docs\relay.json'), (($ledger17 | ConvertTo-Json -Depth 4) -replace "`r`n", "`n"), (New-Object Text.UTF8Encoding($false)))
$s17f = Run $spawnInst17 @('-Runtime', 'claude-code', '-PromptFile', $prompt17, '-WorkspaceDir', $r17a)
Check 'contract_spawn_reads_ledger_session_id' ($s17f.Text -match ('SPAWN_SESSION_ID id=' + $uuid17 + ' source=ledger')) ('line=' + ((($s17f.Text -split "`n") | Where-Object { $_ -match 'SPAWN_SESSION_ID' } | Select-Object -First 1)))
Check 'contract_spawn_dryrun_no_pre_adopt' (-not ($s17f.Text -match 'SPAWN_LOCK_PRE_ADOPTED')) ''

$spawnTpl17 = Join-Path $tplDir 'relay-spawn.ps1'
Check 'contract_device_start_matches_template' ((Hash16 (Join-Path $tplDir 'start-relay.ps1')) -eq (Hash16 (Join-Path $repoRoot 'device\start-relay.ps1'))) ''
Check 'contract_device_spawn_matches_template' ((Hash16 $spawnTpl17) -eq (Hash16 (Join-Path $repoRoot 'device\relay-spawn.ps1'))) ''
$bad17 = @()
foreach ($f17 in @((Join-Path $repoRoot 'device\start-relay.ps1'), (Join-Path $repoRoot 'device\relay-spawn.ps1'))) {
  $b17 = [IO.File]::ReadAllBytes($f17); $na17 = 0; $bom17 = $false
  foreach ($x17 in $b17) { if ($x17 -gt 127) { $na17++ } }
  if ($b17.Length -ge 3 -and $b17[0] -eq 239 -and $b17[1] -eq 187 -and $b17[2] -eq 191) { $bom17 = $true }
  if ($na17 -gt 0 -or $bom17) { $bad17 += (Split-Path -Leaf $f17) }
}
Check 'contract_device_files_ascii_no_bom' ($bad17.Count -eq 0) ('bad=' + ($bad17 -join ','))

# --- case 17b: unattended link invariants (B10 live chain findings) ---------
# The first real Claude Code link of B10 exposed three defects that no dry run
# could see: the driver started the runtime in the wrong working directory, the
# permission mode asked a question that nobody was there to answer, and the
# prompt of a CLI link carried no session id, so the link could not release the
# lock it owned. Case 17b locks those three down.
Check 'contract_launcher_allocates_chain_session_id' ($s17a.Text -match 'OK link_mode=cli_driver chain_session_id=[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}') ('line=' + ((($s17a.Text -split "`n") | Where-Object { $_ -match 'OK link_mode=' } | Select-Object -First 1)))
Check 'contract_prompt_carries_session_id' ($s17a.Text -match 'RELAY_SESSION_ID=[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}') ''
Check 'contract_prompt_stop_rule_names_session_id' ($s17a.Text -match 'relay-lock\.ps1 -Action release -SessionId') ''
Check 'contract_spawn_permission_mode_never_asks' ($s17f.Text -match '--permission-mode bypassPermissions') ''
Check 'contract_spawn_disables_question_box' ($s17f.Text -match 'autoQuestion') ''
Check 'contract_mcode_prompt_has_no_session_id' (-not ($s17b.Text -match 'RELAY_SESSION_ID=')) ''
$s17g2 = Run $spawnInst17 @('-Runtime', 'claude-code', '-PromptFile', $prompt17, '-WorkspaceDir', (Join-Path $script:root 'no-such-workspace-17'))
Check 'contract_spawn_rejects_missing_workspace' ($s17g2.Code -eq 2 -and $s17g2.Text -match 'reason=workspace_missing') ('exit=' + $s17g2.Code)

# --- case 17c: headless permission rules travel in a settings file -------------
# The second real Claude Code link of B10 showed the truth about permissions: on
# claude 999.0.0-local the CLI flags --permission-mode and --allowedTools are
# ignored, so every non read-only call came back as "This command requires
# approval" and the link could not run a single relay script. The same rules
# inside a --settings FILE are honoured. Case 17c locks that down, and it also
# keeps the mcode prompt free of the cli-only command style rule.
Check 'contract_spawn_settings_json_disables_question_box' ($s17f.Text -match 'SPAWN_SETTINGS_JSON .*autoQuestion') ''
Check 'contract_spawn_settings_json_bypass_mode' ($s17f.Text -match '"defaultMode":"bypassPermissions"') ''
Check 'contract_spawn_settings_json_allows_pwsh' ($s17f.Text -match 'Bash\(pwsh:\*\)') ''
Check 'contract_spawn_uses_settings_file' ($s17f.Text -match '--settings .*relay-settings\.json') ''
Check 'contract_spawn_no_inline_settings_json' (-not ($s17f.Text -match '--settings \{')) ''
Check 'contract_cli_prompt_command_style' ($s17a.Text -match 'Command style for this runtime' -and $s17a.Text -match 'one command per call') ''
Check 'contract_mcode_prompt_has_no_command_style' (-not ($s17b.Text -match 'Command style for this runtime')) ''

$r17d = New-Repo 'repo-runtime-contract-live'
Set-Content -LiteralPath (Join-Path $r17d 'docs\plan-17l.md') -Value '# plan 17l' -Encoding utf8
$c17d = Run $installer @('-RepoRoot', $r17d, '-Target', 'live contract', '-PlanDoc', 'docs\plan-17l.md', '-MaxStages', '2', '-Runtime', 'claude-code')
Check 'contract_live_install_exit_zero' ($c17d.Code -eq 0) ('exit=' + $c17d.Code)
$live17 = Run (Join-Path $r17d 'docs\relay\start-relay.ps1') @('-Target', 'live contract', '-MaxStages', '2')
Check 'contract_live_launcher_exit_zero' ($live17.Code -eq 0) ('exit=' + $live17.Code)
$led17d = $null
$ledPath17 = Join-Path $r17d 'docs\relay.json'
if (Test-Path -LiteralPath $ledPath17) { $led17d = Get-Content -LiteralPath $ledPath17 -Raw -Encoding UTF8 | ConvertFrom-Json }
Check 'contract_live_ledger_carries_session_id' ($null -ne $led17d -and ([string]$led17d.next_session_id) -match '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') ('id=' + [string]$led17d.next_session_id)
$promptLive17 = ''
$promptPath17 = Join-Path $r17d 'docs\relay\next-relay-prompt.txt'
if (Test-Path -LiteralPath $promptPath17) { $promptLive17 = [IO.File]::ReadAllText($promptPath17) }
Check 'contract_live_prompt_session_id_matches_ledger' ($promptLive17 -match ('RELAY_SESSION_ID=' + [regex]::Escape([string]$led17d.next_session_id))) ''

# --- case 17d: the command line the CLI really parses (B10 live chain findings) ---
# The third real Claude Code link of B10 was stopped by the permission layer again,
# and the cause was in the command line, not in the rules: on claude 999.0.0-local
# the argument parser stops at the first positional argument, so every flag that
# followed the prompt was dropped. --settings included, which left the link in
# default mode where every pwsh call waits for an approval that never comes.
# The rules inside the settings file also need the key inside "permissions".
# Case 17d locks both down: no other check in this suite can see the order of
# the arguments, and the order is the whole bug.
$spawnLine17 = ''
foreach ($x17 in ($s17f.Text -split "`n")) { if ($x17 -match 'SPAWN_COMMAND claude ') { $spawnLine17 = $x17.Trim() } }
Check 'contract_spawn_prompt_is_last_argument' ($spawnLine17 -match '-p <prompt from file>$') ('line=' + $spawnLine17)
Check 'contract_spawn_settings_flag_before_prompt' ($spawnLine17 -match '--settings .*relay-settings\.json' -and $spawnLine17.IndexOf('--settings') -lt $spawnLine17.IndexOf('-p <prompt from file>')) ('line=' + $spawnLine17)
Check 'contract_spawn_permission_mode_flag_before_prompt' ($spawnLine17 -match '--permission-mode bypassPermissions' -and $spawnLine17.IndexOf('--permission-mode') -lt $spawnLine17.IndexOf('-p <prompt from file>')) ('line=' + $spawnLine17)
Check 'contract_spawn_settings_json_nested_default_mode' ($s17f.Text -match '"permissions":\{"defaultMode":"bypassPermissions"') ''

# --- case 18: first run asks the project's three rulings (B11) -----------------
# Until B11 the kit shipped docs\RELAY-ADAPTATION.md with TODO in the write set,
# the gate and the model policy, and a human had to fill them in after the
# install. The install now probes usable defaults, renders them with a source
# mark, writes a question packet, and refuses to sound confirmed until an
# answers file lands. Case 18 locks all of that down: the pending state, the
# packet contents, the answers overlay and the failure code for a missing file.
$r18 = New-Repo 'repo-adapt-questions'
Set-Content -LiteralPath (Join-Path $r18 'docs\plan-18.md') -Value '# plan 18' -Encoding utf8
$c18a = Run $installer @('-RepoRoot', $r18, '-Target', 'adapt batch', '-PlanDoc', 'docs\plan-18.md', '-MaxStages', '2')
Check 'adapt_first_run_exit_zero' ($c18a.Code -eq 0) ('exit=' + $c18a.Code)
Check 'adapt_first_run_verdict_pass' ($c18a.Text -match 'INSTALL_VERDICT=PASS') ''
Check 'adapt_status_pending' ($c18a.Text -match 'ADAPTATION_STATUS=pending') ''
Check 'adapt_source_defaults' ($c18a.Text -match 'ADAPTATION_SOURCE=defaults') ''
Check 'adapt_questions_line' ($c18a.Text -match 'ADAPTATION_QUESTIONS=docs\\relay\\adaptation-questions\.md') ''
Check 'adapt_warns_unconfirmed' ($c18a.Text -match 'WARN adaptation_defaults_unconfirmed') ''
Check 'adapt_check_zero_placeholders' ($c18a.Text -match 'ADAPT_CHECK doc=docs\\RELAY-ADAPTATION\.md placeholders=0 source=defaults') ''
$adaptDoc18 = Join-Path $r18 'docs\RELAY-ADAPTATION.md'
$adaptTxt18a = ''
if (Test-Path -LiteralPath $adaptDoc18) { $adaptTxt18a = [IO.File]::ReadAllText($adaptDoc18) }
Check 'adapt_doc_no_todo_left' (-not ($adaptTxt18a -match 'TODO')) ''
Check 'adapt_doc_no_brace_tokens' (-not ($adaptTxt18a -match '\{\{[A-Z_]+\}\}')) ''
Check 'adapt_doc_source_defaults_marks' ((([regex]::Matches($adaptTxt18a, 'source: defaults')).Count) -eq 3) ''
$qMd18 = Join-Path $r18 'docs\relay\adaptation-questions.md'
$qJs18 = Join-Path $r18 'docs\relay\adaptation-questions.json'
$aTpl18 = Join-Path $r18 'docs\relay\adaptation-answers.template.json'
Check 'adapt_packet_md_present' (Test-Path -LiteralPath $qMd18) ''
Check 'adapt_packet_json_present' (Test-Path -LiteralPath $qJs18) ''
Check 'adapt_answers_template_present' (Test-Path -LiteralPath $aTpl18) ''
$qObj18 = $null
if (Test-Path -LiteralPath $qJs18) { $qObj18 = Get-Content -LiteralPath $qJs18 -Raw -Encoding UTF8 | ConvertFrom-Json }
Check 'adapt_packet_json_questions_8' ($null -ne $qObj18 -and @($qObj18.questions).Count -eq 8) ''
Check 'adapt_packet_json_repo_filled' ($null -ne $qObj18 -and -not [string]::IsNullOrWhiteSpace([string]$qObj18.repo)) ''
Check 'adapt_packet_json_all_answer_keys' ($null -ne $qObj18 -and ((@($qObj18.questions | ForEach-Object { [string]$_.answer_key } | Sort-Object) -join ',')) -eq 'concurrency_check,gate_command,gate_verdict_field,model_fallback_day,model_fallback_night,model_primary,write_set_allow,write_set_deny') ''
$qMdTxt18 = ''
if (Test-Path -LiteralPath $qMd18) { $qMdTxt18 = [IO.File]::ReadAllText($qMd18) }
Check 'adapt_packet_md_names_every_key' ($null -ne $qObj18 -and @($qObj18.questions | Where-Object { $qMdTxt18 -notmatch [regex]::Escape([string]$_.answer_key) }).Count -eq 0) ''
Check 'adapt_packet_md_says_batch_of_2_3' ($qMdTxt18 -match '2-3') ''
$ans18Path = Join-Path $r18 'docs\relay\adaptation-answers.json'
$ans18 = [ordered]@{
  schema = 'relay-port/adaptation-answers@1'
  write_set_allow = @('src/', 'tests/')
  write_set_deny = @('secrets/')
  gate_command = 'pwsh -NoProfile -ExecutionPolicy Bypass -File scripts\gate-check.ps1'
  gate_verdict_field = 'GATE_VERDICT=PASS'
  model_primary = 'minimax/MiniMax-M3'
}
[IO.File]::WriteAllText($ans18Path, (($ans18 | ConvertTo-Json -Depth 4) -replace "`r`n", "`n"), (New-Object Text.UTF8Encoding($false)))
$c18b = Run $installer @('-RepoRoot', $r18, '-Target', 'adapt batch', '-PlanDoc', 'docs\plan-18.md', '-MaxStages', '2', '-AnswersFile', 'docs\relay\adaptation-answers.json')
Check 'adapt_answers_run_exit_zero' ($c18b.Code -eq 0) ('exit=' + $c18b.Code)
Check 'adapt_answers_applied' ($c18b.Text -match 'ADAPT answers=docs\\relay\\adaptation-answers\.json applied=5/8') ''
Check 'adapt_answers_patches_three_sections' ($c18b.Text -match 'PATCH RELAY-ADAPTATION\.md sections=3,4,5 missing= answers=') ''
Check 'adapt_status_confirmed' ($c18b.Text -match 'ADAPTATION_STATUS=confirmed') ''
Check 'adapt_answers_source_answers' ($c18b.Text -match 'ADAPTATION_SOURCE=answers') ''
Check 'adapt_questions_line_cleared' (-not ($c18b.Text -match 'ADAPTATION_QUESTIONS=docs')) ''
Check 'adapt_answers_no_unconfirmed_warn' (-not ($c18b.Text -match 'WARN adaptation_defaults_unconfirmed')) ''
$adaptTxt18b = ''
if (Test-Path -LiteralPath $adaptDoc18) { $adaptTxt18b = [IO.File]::ReadAllText($adaptDoc18) }
Check 'adapt_answers_wrote_values' ($adaptTxt18b -match 'GATE_VERDICT=PASS' -and $adaptTxt18b -match 'secrets/' -and $adaptTxt18b -match 'tests/') ''
Check 'adapt_answers_source_marked' ((([regex]::Matches($adaptTxt18b, 'source: answers')).Count) -eq 3) ''
Check 'adapt_answers_kept_later_sections' ($adaptTxt18b -match '## 6\.' -and $adaptTxt18b -match '## 9\.') ''
$c18c = Run $installer @('-RepoRoot', $r18, '-Target', 'adapt batch', '-PlanDoc', 'docs\plan-18.md', '-MaxStages', '2', '-AnswersFile', 'docs\relay\missing-answers.json')
Check 'adapt_missing_answers_exit_two' ($c18c.Code -eq 2 -and $c18c.Text -match 'reason=answers_file_missing') ('exit=' + $c18c.Code)

# --- case 19: what the first unattended Claude Code link proved (B13) ---------
# The B13 live chain ran a whole unattended Claude Code chain end to end in a
# clean repository: stage 1 wrote its artifact, committed the hand-off through
# the ledger gate and started stage 2 by itself, stage 2 closed the chain.
# Two things came out of it that no dry run could see:
#   * the installer was given a stage list and the launcher ignored it, so
#     every link of the chain was told "1. stage 1 scope inventory";
#   * the command style rule of a cli prompt prescribed the Bash tool and
#     showed a Windows path. The Bash tool is a real bash and it eats the
#     backslashes, so the link lost two commands to exit 64
#     ("docsrelayrelay-ledger.ps1" not found) before it converted the paths
#     itself.
# Case 19 locks both down, and keeps the mcode prompt on Windows paths: only a
# stage list the user actually declared travels to the launcher.
$r19 = New-Repo 'repo-b13-stage-list'
Set-Content -LiteralPath (Join-Path $r19 'docs\plan-19.md') -Value '# plan 19' -Encoding utf8
$c19a = Run $installer @('-RepoRoot', $r19, '-Target', 'b13 batch', '-PlanDoc', 'docs\plan-19.md', '-MaxStages', '3', '-Runtime', 'claude-code', '-StageTitles', '1. alpha stage;2. beta stage;3. gamma stage')
Check 'b13_install_with_stage_titles_exit_zero' ($c19a.Code -eq 0) ('exit=' + $c19a.Code)
$desc19 = Get-Content -LiteralPath (Join-Path $r19 'docs\relay\relay-runtime.json') -Raw -Encoding UTF8 | ConvertFrom-Json
Check 'b13_descriptor_carries_stage_titles' ($null -ne $desc19 -and ([string]$desc19.stage_titles) -match 'alpha stage' -and ([string]$desc19.stage_titles) -match 'gamma stage') ('titles=' + [string]$desc19.stage_titles)
$s19a = Run (Join-Path $r19 'docs\relay\start-relay.ps1') @('-Target', 'b13 batch', '-MaxStages', '3', '-DryRun')
Check 'b13_launcher_reports_stage_titles_source' ($s19a.Text -match 'OK stage_titles source=descriptor') ('line=' + ((($s19a.Text -split "`n") | Where-Object { $_ -match 'OK stage_titles' } | Select-Object -First 1)))
$prompt19 = ($s19a.Text -split 'DRYRUN prompt_preview_begin', 2)[1]
$prompt19 = ($prompt19 -split 'DRYRUN prompt_preview_end', 2)[0]
Check 'b13_cli_prompt_has_real_stage_list' ($prompt19 -match '1\. alpha stage' -and $prompt19 -match '3\. gamma stage') ''
Check 'b13_cli_prompt_has_no_generic_stage_list' (-not ($prompt19 -match '1\. stage 1 scope inventory')) ''
Check 'b13_cli_prompt_gate_path_uses_forward_slashes' ($prompt19 -match 'docs/relay/relay-ledger\.ps1') ''
Check 'b13_cli_prompt_has_no_backslash_gate_path' (-not ($prompt19 -match 'docs\\relay\\relay-ledger\.ps1')) ''
Check 'b13_cli_prompt_has_no_backslash_relay_path' (-not ($prompt19 -match 'docs\\relay\\')) ''
Check 'b13_cli_prompt_spawn_command_uses_forward_slashes' ($prompt19 -match 'relay-spawn\.ps1 -Runtime claude-code -PromptFile [A-Za-z]:/') ''
Check 'b13_cli_prompt_spawn_command_has_no_backslash' (-not ($prompt19 -match 'relay-spawn\.ps1 -Runtime claude-code -PromptFile [A-Za-z]:\\')) ''
Check 'b13_cli_prompt_command_style_rule_survives' ($prompt19 -match 'Command style for this runtime' -and $prompt19 -match 'one command per call') ''

$r19m = New-Repo 'repo-b13-mcode-prompt'
Set-Content -LiteralPath (Join-Path $r19m 'docs\plan-19m.md') -Value '# plan 19m' -Encoding utf8
$c19m = Run $installer @('-RepoRoot', $r19m, '-Target', 'b13 mcode', '-PlanDoc', 'docs\plan-19m.md', '-MaxStages', '2')
Check 'b13_mcode_install_exit_zero' ($c19m.Code -eq 0) ('exit=' + $c19m.Code)
$desc19m = Get-Content -LiteralPath (Join-Path $r19m 'docs\relay\relay-runtime.json') -Raw -Encoding UTF8 | ConvertFrom-Json
Check 'b13_mcode_descriptor_has_no_stage_titles' ([string]::IsNullOrWhiteSpace([string]$desc19m.stage_titles)) ('titles=' + [string]$desc19m.stage_titles)
$s19m = Run (Join-Path $r19m 'docs\relay\start-relay.ps1') @('-Target', 'b13 mcode', '-DryRun')
$prompt19m = ($s19m.Text -split 'DRYRUN prompt_preview_begin', 2)[1]
$prompt19m = ($prompt19m -split 'DRYRUN prompt_preview_end', 2)[0]
Check 'b13_mcode_prompt_keeps_windows_gate_path' ($prompt19m -match 'docs\\relay\\relay-ledger\.ps1') ''
Check 'b13_mcode_prompt_has_no_forward_slash_gate_path' (-not ($prompt19m -match 'docs/relay/relay-ledger\.ps1')) ''
Check 'b13_mcode_prompt_keeps_generic_stage_list' ($prompt19m -match '1\. stage 1 scope inventory') ''
Check 'b13_mcode_prompt_has_no_spawn_command_prompt_form' (-not ($prompt19m -match 'relay-spawn\.ps1 -Runtime claude-code -PromptFile')) ''
Check 'b13_mcode_prompt_keeps_windows_relay_paths' ($prompt19m -match 'docs\\relay\\relay-lock\.ps1' -and $prompt19m -match 'docs\\relay\\\.relay\.lock') ''

# --- case 20: the gate keeps the session trail by itself (F6) --------------------
# The B13 live chain ended with sessions=[]: the session trail was only a prose
# request (sessions_append), and the link that finished the last stage did not
# send it, so the ledger had no independent record of which sessions ran.
# The gate now registers the session of a stage_done commit itself. Case 20
# locks that down: the id is registered once, a repeat commit does not
# duplicate it, a link that follows the protocol and also sends sessions_append
# does not duplicate it either, and the trail only ever grows.
function New-GateRepo([string]$Name, [hashtable]$Over) {
  $d = New-Repo $Name
  New-Item -ItemType Directory -Path (Join-Path $d 'docs\relay') -Force | Out-Null
  Copy-Item -LiteralPath (Join-Path $tplDir 'relay-ledger.ps1') -Destination (Join-Path $d 'docs\relay\relay-ledger.ps1') -Force
  $seed = [ordered]@{
    goal = 'F6 session trail'; plan_doc = 'docs\plan.md'; workspace_dir = $d
    status = 'running'; auto_relay = $true; current_stage = 1; max_stages = 3
    next_session_id = $null; stages = @(); sessions = @(); notes = @(); blocked_on = @()
  }
  foreach ($k in $Over.Keys) { $seed[$k] = $Over[$k] }
  [IO.File]::WriteAllText((Join-Path $d 'docs\relay.json'), ($seed | ConvertTo-Json -Depth 6), (New-Object Text.UTF8Encoding($false)))
  return $d
}
$r20 = New-GateRepo 'repo-f6-session-trail' @{}
$g20 = Join-Path $r20 'docs\relay\relay-ledger.ps1'
$l20 = Join-Path $r20 'docs\relay.json'
function G20Sha { [regex]::Match((Run $g20 @('-Action','status')).Text, 'sha256=([0-9A-Fa-f]{64})').Groups[1].Value }
function P20([string]$Name, [string]$Body) {
  $p = Join-Path (Join-Path $r20 'docs\relay') $Name
  [IO.File]::WriteAllText($p, $Body, (New-Object Text.UTF8Encoding($false)))
  return $p
}
$p20a = P20 'p20a.json' '{"append_stage":{"id":1,"title":"F6 stage one","session_id":"sess-f6-alpha"}}'
$c20a = Run $g20 @('-Action','commit','-ExpectSha256',(G20Sha),'-Patch',$p20a)
Check 'f6_append_stage_ok' ($c20a.Code -eq 0 -and $c20a.Text -match 'LEDGER_COMMITED') ('exit=' + $c20a.Code)
$p20b = P20 'p20b.json' '{"stage_done":1,"stage_fields":{"result":"alpha done"}}'
$c20b = Run $g20 @('-Action','commit','-ExpectSha256',(G20Sha),'-Patch',$p20b)
Check 'f6_stage_done_committed' ($c20b.Code -eq 0 -and $c20b.Text -match 'LEDGER_COMMITED') ('exit=' + $c20b.Code)
Check 'f6_session_registered_by_gate' ($c20b.Text -match 'LEDGER_SESSION_REGISTERED session=sess-f6-alpha stage=1') ('line=' + (($c20b.Text -split "`n") | Where-Object { $_ -match 'LEDGER_SESSION_' } | Select-Object -First 1))
$led20 = Get-Content -LiteralPath $l20 -Raw | ConvertFrom-Json
Check 'f6_sessions_trail_has_the_session' (@($led20.sessions).Count -eq 1 -and [string]@($led20.sessions)[0] -eq 'sess-f6-alpha') ('count=' + @($led20.sessions).Count)
# a repeat commit of the same stage must not grow the trail
$p20c = P20 'p20c.json' '{"stage_done":1,"stage_fields":{"result":"alpha done"}}'
$c20c = Run $g20 @('-Action','commit','-ExpectSha256',(G20Sha),'-Patch',$p20c)
$led20c = Get-Content -LiteralPath $l20 -Raw | ConvertFrom-Json
Check 'f6_repeat_commit_does_not_duplicate_session' ($c20c.Code -eq 0 -and @($led20c.sessions).Count -eq 1 -and $c20c.Text -match 'LEDGER_SESSION_ALREADY_REGISTERED') ('exit=' + $c20c.Code + ' count=' + @($led20c.sessions).Count)
# a link that follows the protocol and also sends sessions_append is still one entry
$p20d = P20 'p20d.json' '{"stage_done":1,"sessions_append":["sess-f6-alpha"]}'
$c20d = Run $g20 @('-Action','commit','-ExpectSha256',(G20Sha),'-Patch',$p20d)
$led20d = Get-Content -LiteralPath $l20 -Raw | ConvertFrom-Json
Check 'f6_sessions_append_does_not_duplicate_session' ($c20d.Code -eq 0 -and @($led20d.sessions).Count -eq 1) ('exit=' + $c20d.Code + ' count=' + @($led20d.sessions).Count)
Check 'f6_trail_is_append_only' (@($led20d.sessions).Count -eq 1 -and [string]@($led20d.sessions)[0] -eq 'sess-f6-alpha' -and [string]@($led20d.stages)[0].status -eq 'done') ('sessions=' + (@($led20d.sessions) -join '|'))

# a stage without a session id falls back to the id of the link that is running
$r20e = New-GateRepo 'repo-f6-fallback' @{ next_session_id = 'sess-f6-beta'; stages = @(@{ id = 1; title = 'F6 beta'; status = 'in_progress' }) }
$g20e = Join-Path $r20e 'docs\relay\relay-ledger.ps1'
$l20e = Join-Path $r20e 'docs\relay.json'
$p20e = Join-Path (Join-Path $r20e 'docs\relay') 'p20e.json'
[IO.File]::WriteAllText($p20e, '{"stage_done":1,"stage_fields":{"result":"beta done"}}', (New-Object Text.UTF8Encoding($false)))
$c20e = Run $g20e @('-Action','commit','-ExpectSha256',(Get-FileHash -Algorithm SHA256 -LiteralPath $l20e).Hash, '-Patch', $p20e)
Check 'f6_fallback_uses_running_link_id' ($c20e.Code -eq 0 -and $c20e.Text -match 'LEDGER_SESSION_REGISTERED session=sess-f6-beta stage=1 source=ledger_next_session_id') ('line=' + (($c20e.Text -split "`n") | Where-Object { $_ -match 'LEDGER_SESSION_' } | Select-Object -First 1))

# no session id anywhere: the gate says so instead of inventing one
$r20f = New-GateRepo 'repo-f6-no-session' @{ stages = @(@{ id = 1; title = 'F6 gamma'; status = 'in_progress' }) }
$g20f = Join-Path $r20f 'docs\relay\relay-ledger.ps1'
$l20f = Join-Path $r20f 'docs\relay.json'
$p20f = Join-Path (Join-Path $r20f 'docs\relay') 'p20f.json'
[IO.File]::WriteAllText($p20f, '{"stage_done":1,"stage_fields":{"result":"gamma done"}}', (New-Object Text.UTF8Encoding($false)))
$c20f = Run $g20f @('-Action','commit','-ExpectSha256',(Get-FileHash -Algorithm SHA256 -LiteralPath $l20f).Hash, '-Patch', $p20f)
$led20f = Get-Content -LiteralPath $l20f -Raw | ConvertFrom-Json
Check 'f6_no_session_id_is_skipped_not_faked' ($c20f.Code -eq 0 -and $c20f.Text -match 'LEDGER_SESSION_SKIPPED stage=1 reason=no_session_id' -and @($led20f.sessions).Count -eq 0) ('exit=' + $c20f.Code + ' count=' + @($led20f.sessions).Count)

# --- case 21: finishing the chain is done, not blocked (F5) ---------------------
# B13's live chain ended with status=blocked because the shipped rule said
# "current_stage >= max_stages -> status=blocked": the last stage finishing
# looked like a failure. The terminal state is now done, and blocked stays
# reserved for a real stop. The launcher's own gate already keys
# chain_exhausted on (status=done and current_stage >= max_stages), so the
# wording is checked together with the code that consumes it.
$blockTpl = Get-Content -LiteralPath (Join-Path $tplDir 'AGENTS-RELAY-BLOCK.md') -Raw
$rule11 = @($blockTpl -split "`n" | Where-Object { $_ -match 'current_stage > max_stages' })
Check 'f5_house_rule_names_done' ($rule11.Count -eq 1 -and $rule11[0] -match 'status="done"') ('lines=' + $rule11.Count)
$seedTpl = Get-Content -LiteralPath (Join-Path $tplDir 'start-relay.ps1') -Raw
Check 'f5_ledger_seed_names_done' ($seedTpl -match 'current_stage > max_stages with every stage done -> status=done') ''
Check 'f5_ledger_seed_has_no_old_rule' (-not ($seedTpl -match 'current_stage >= max_stages -> status=blocked')) ''
$protoTpl = Get-Content -LiteralPath (Join-Path $tplDir 'AGENT-RELAY.md') -Raw
Check 'f5_protocol_stop_conditions_name_done' ($protoTpl -match 'current_stage > max_stages with every stage done -> status=done') ''
Check 'f5_protocol_has_no_old_stop_rule' (-not ($protoTpl -match 'current_stage >= max_stages"')) ''
Check 'f5_protocol_copies_are_byte_identical' ((Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $tplDir 'AGENT-RELAY.md')).Hash -eq (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $repoRoot 'protocol\AGENT-RELAY.md')).Hash) ''

$r21 = New-Repo 'repo-f5-done'
New-Item -ItemType Directory -Path (Join-Path $r21 'docs\relay') -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $r21 'docs\plans') -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $tplDir 'start-relay.ps1') -Destination (Join-Path $r21 'docs\relay\start-relay.ps1') -Force
Copy-Item -LiteralPath (Join-Path $tplDir 'relay-lock.ps1') -Destination (Join-Path $r21 'docs\relay\relay-lock.ps1') -Force
Copy-Item -LiteralPath (Join-Path $tplDir 'relay-ledger.ps1') -Destination (Join-Path $r21 'docs\relay\relay-ledger.ps1') -Force
[IO.File]::WriteAllText((Join-Path $r21 'docs\plans\f5.md'), '# plan' + "`n`n" + '1. one stage' + "`n", (New-Object Text.UTF8Encoding($false)))
$done21 = [ordered]@{
  goal = 'F5 done'; plan_doc = 'docs\plans\f5.md'; workspace_dir = $r21
  status = 'done'; auto_relay = $true; current_stage = 2; max_stages = 1
  next_session_id = $null; stages = @(@{ id = 1; title = 'only stage'; status = 'done' })
  sessions = @(); notes = @(); blocked_on = @()
}
[IO.File]::WriteAllText((Join-Path $r21 'docs\relay.json'), ($done21 | ConvertTo-Json -Depth 6), (New-Object Text.UTF8Encoding($false)))
$k21 = Run (Join-Path $r21 'docs\relay\start-relay.ps1') @('-Target', 'f5', '-DryRun')
Check 'f5_done_chain_is_exhausted_not_runnable' ($k21.Code -eq 3 -and $k21.Text -match 'chain_exhausted') ('exit=' + $k21.Code + ' line=' + ((($k21.Text -split "`n") | Where-Object { $_ -match 'chain_exhausted|FAIL reason' } | Select-Object -First 1)))

# --- case 22: a running chain already at the stage cap is refused (B16) --------
# B15 left one hole: when the last stage finished but nobody flipped status to
# done, both older gates pass (no in_progress stage, empty next_session_id) and
# the launcher would boot stage N+1, i.e. work outside the declared plan. The
# backstop keys on (status=running and current_stage >= max_stages). Both
# directions are checked here: the cap case must be refused, the mid-chain case
# must still start, otherwise the new branch has no discriminating power.
$r22 = New-Repo 'repo-stage-cap'
New-Item -ItemType Directory -Path (Join-Path $r22 'docs\relay') -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $r22 'docs\plans') -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $tplDir 'start-relay.ps1') -Destination (Join-Path $r22 'docs\relay\start-relay.ps1') -Force
Copy-Item -LiteralPath (Join-Path $tplDir 'relay-lock.ps1') -Destination (Join-Path $r22 'docs\relay\relay-lock.ps1') -Force
Copy-Item -LiteralPath (Join-Path $tplDir 'relay-ledger.ps1') -Destination (Join-Path $r22 'docs\relay\relay-ledger.ps1') -Force
[IO.File]::WriteAllText((Join-Path $r22 'docs\plans\f7.md'), ('# plan' + "`n`n" + '1. first stage' + "`n" + '2. second stage' + "`n"), (New-Object Text.UTF8Encoding($false)))
$cap22 = [ordered]@{
  goal = 'stage cap'; plan_doc = 'docs\plans\f7.md'; workspace_dir = $r22
  status = 'running'; auto_relay = $true; current_stage = 2; max_stages = 2
  next_session_id = $null; stages = @(@{ id = 1; title = 'first stage'; status = 'done' }, @{ id = 2; title = 'second stage'; status = 'done' })
  sessions = @(); notes = @(); blocked_on = @()
}
[IO.File]::WriteAllText((Join-Path $r22 'docs\relay.json'), ($cap22 | ConvertTo-Json -Depth 6), (New-Object Text.UTF8Encoding($false)))
$k22 = Run (Join-Path $r22 'docs\relay\start-relay.ps1') @('-Target', 'f7', '-DryRun')
Check 'gate_refuses_running_chain_at_stage_cap' ($k22.Code -eq 3 -and $k22.Text -match 'chain_at_stage_cap') ('exit=' + $k22.Code + ' line=' + ((($k22.Text -split "`n") | Where-Object { $_ -match 'chain_at_stage_cap|FAIL reason' } | Select-Object -First 1)))

$mid22 = [ordered]@{
  goal = 'stage cap'; plan_doc = 'docs\plans\f7.md'; workspace_dir = $r22
  status = 'running'; auto_relay = $true; current_stage = 1; max_stages = 2
  next_session_id = $null; stages = @(@{ id = 1; title = 'first stage'; status = 'done' }, @{ id = 2; title = 'second stage'; status = 'pending' })
  sessions = @(); notes = @(); blocked_on = @()
}
[IO.File]::WriteAllText((Join-Path $r22 'docs\relay.json'), ($mid22 | ConvertTo-Json -Depth 6), (New-Object Text.UTF8Encoding($false)))
$m22 = Run (Join-Path $r22 'docs\relay\start-relay.ps1') @('-Target', 'f7', '-DryRun')
Check 'gate_still_starts_below_stage_cap' ($m22.Code -eq 0 -and -not ($m22.Text -match 'chain_at_stage_cap') -and $m22.Text -match 'DRYRUN skip=lock_acquire') ('exit=' + $m22.Code + ' cap_hit=' + [bool]($m22.Text -match 'chain_at_stage_cap'))

# --- case 23: the link naming rule is asserted on the generated artifacts ---
# B17 shipped the zero padded naming (relay-01of02) but left it unasserted: the
# rule lived only in the prompt text, so a silent revert to the old form
# (relay-1-<stage>) would not turn anything red. These checks read the GENERATED
# prompt of a real launcher run: the new form must hit, the old form must hit
# zero times, and a legacy sample must not satisfy the new pattern (that last
# one is the discriminating power inside the suite). The out of suite proof that
# a template revert really turns these checks red is reports\b18-naming-mutation.ps1.
$linkRuns = @(@{ rt = 'claude-code'; dir = 'repo-link-naming-cli' }, @{ rt = 'mcode'; dir = 'repo-link-naming-mcode' })
foreach ($lr in $linkRuns) {
  $rr = New-Repo $lr.dir
  New-Item -ItemType Directory -Path (Join-Path $rr 'docs\relay') -Force | Out-Null
  New-Item -ItemType Directory -Path (Join-Path $rr 'docs\plans') -Force | Out-Null
  Copy-Item -LiteralPath (Join-Path $tplDir 'start-relay.ps1') -Destination (Join-Path $rr 'docs\relay\start-relay.ps1') -Force
  Copy-Item -LiteralPath (Join-Path $tplDir 'relay-lock.ps1') -Destination (Join-Path $rr 'docs\relay\relay-lock.ps1') -Force
  Copy-Item -LiteralPath (Join-Path $tplDir 'relay-ledger.ps1') -Destination (Join-Path $rr 'docs\relay\relay-ledger.ps1') -Force
  [IO.File]::WriteAllText((Join-Path $rr 'docs\plans\link.md'), ('# plan' + "`n`n" + '1. first stage' + "`n" + '2. second stage' + "`n"), (New-Object Text.UTF8Encoding($false)))
  $run23 = Run (Join-Path $rr 'docs\relay\start-relay.ps1') @('-Target', 'link batch', '-MaxStages', '2', '-Runtime', $lr.rt, '-PlanDoc', 'docs\plans\link.md')
  Check ('link_naming_' + $lr.rt + '_launcher_exit_zero') ($run23.Code -eq 0) ('exit=' + $run23.Code)
  $prompt23 = [IO.File]::ReadAllText((Join-Path $rr 'docs\relay\next-relay-prompt.txt'))
  $newHits23 = [regex]::Matches($prompt23, 'relay-\d{2}of\d{2}').Count
  $legacyHits23 = [regex]::Matches($prompt23, 'relay-\d+-').Count
  Check ('link_naming_' + $lr.rt + '_uses_zero_padded_form') ($newHits23 -gt 0) ('new_form_hits=' + $newHits23)
  Check ('link_naming_' + $lr.rt + '_has_no_legacy_form') ($legacyHits23 -eq 0) ('legacy_hits=' + $legacyHits23)
}
$promptCli23 = [IO.File]::ReadAllText((Join-Path $script:root 'repo-link-naming-cli\docs\relay\next-relay-prompt.txt'))
Check 'link_naming_cli_header_names_the_link' ($promptCli23 -match 'RELAY_LINK=relay-\d{2}of\d{2}') ''
Check 'link_naming_cli_handoff_names_next_link' ($promptCli23 -match 'change RELAY_LINK=relay-01of02 to RELAY_LINK=relay-02of02') ''
Check 'link_naming_rule_rejects_legacy_sample' (-not ('relay-1-inventory' -match 'relay-\d{2}of\d{2}')) ('legacy_sample_matched=' + [bool]('relay-1-inventory' -match 'relay-\d{2}of\d{2}'))

# --- case 24: the stage cap gate tells the truth about the shape it hit ------
# B18 proved on the real device that the cap branch always claimed "every
# declared stage is done" and advised closing the chain - advice that silently
# drops a stage when the last stage never ran. The gate now reports the shape
# on the FAIL line (stages= and all_done=) and picks the HINT from it. All
# three shapes are checked, and the open-stage case asserts that the closing
# advice is NOT given, so a revert to one blanket HINT turns this red.
$r24 = New-Repo 'repo-cap-hint'
New-Item -ItemType Directory -Path (Join-Path $r24 'docs\relay') -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $r24 'docs\plans') -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $tplDir 'start-relay.ps1') -Destination (Join-Path $r24 'docs\relay\start-relay.ps1') -Force
Copy-Item -LiteralPath (Join-Path $tplDir 'relay-lock.ps1') -Destination (Join-Path $r24 'docs\relay\relay-lock.ps1') -Force
Copy-Item -LiteralPath (Join-Path $tplDir 'relay-ledger.ps1') -Destination (Join-Path $r24 'docs\relay\relay-ledger.ps1') -Force
[IO.File]::WriteAllText((Join-Path $r24 'docs\plans\f8.md'), ('# plan' + "`n`n" + '1. first stage' + "`n" + '2. second stage' + "`n"), (New-Object Text.UTF8Encoding($false)))
$cap24 = @(
  @{ tag = 'all_done'; stages = @(@{ id = 1; title = 'first stage'; status = 'done' }, @{ id = 2; title = 'second stage'; status = 'done' }); expect_state = 'true'; expect_summary = 'stages=1:done,2:done'; expect_token = 'all_stages_done_but_status_running' },
  @{ tag = 'open_stage'; stages = @(@{ id = 1; title = 'first stage'; status = 'done' }, @{ id = 2; title = 'second stage'; status = 'pending' }); expect_state = 'false'; expect_summary = 'stages=1:done,2:pending'; expect_token = 'stage_cap_reached_with_open_stage' },
  @{ tag = 'no_records'; stages = @(); expect_state = 'unknown'; expect_summary = 'stages=none'; expect_token = 'stage_cap_reached_with_no_stage_records' }
)
$capTokens = @('all_stages_done_but_status_running', 'stage_cap_reached_with_open_stage', 'stage_cap_reached_with_no_stage_records')
$run24ByTag = @{}
foreach ($c24 in $cap24) {
  $led24 = [ordered]@{
    goal = 'cap hint'; plan_doc = 'docs\plans\f8.md'; workspace_dir = $r24
    status = 'running'; auto_relay = $true; current_stage = 2; max_stages = 2
    next_session_id = $null; stages = $c24.stages
    sessions = @(); notes = @(); blocked_on = @()
  }
  [IO.File]::WriteAllText((Join-Path $r24 'docs\relay.json'), ($led24 | ConvertTo-Json -Depth 6), (New-Object Text.UTF8Encoding($false)))
  $run24 = Run (Join-Path $r24 'docs\relay\start-relay.ps1') @('-Target', 'f8', '-DryRun')
  $run24ByTag[$c24.tag] = $run24
  $fail24 = (($run24.Text -split "`n") | Where-Object { $_ -match 'FAIL reason=chain_at_stage_cap' } | Select-Object -First 1)
  Check ('cap_hint_' + $c24.tag + '_is_refused') ($run24.Code -eq 3 -and [bool]$fail24) ('exit=' + $run24.Code + ' line=' + $fail24)
  Check ('cap_hint_' + $c24.tag + '_reports_stage_summary') ([bool]($fail24 -match [regex]::Escape($c24.expect_summary))) ('line=' + $fail24)
  Check ('cap_hint_' + $c24.tag + '_reports_all_done_state') ([bool]($fail24 -match ('all_done=' + $c24.expect_state))) ('line=' + $fail24)
  Check ('cap_hint_' + $c24.tag + '_picks_its_own_hint') ($run24.Text -match ('HINT=' + $c24.expect_token)) ('expect=' + $c24.expect_token)
  $leaked24 = @($capTokens | Where-Object { $_ -ne $c24.expect_token -and ($run24.Text -match ('HINT=' + $_)) })
  Check ('cap_hint_' + $c24.tag + '_hints_are_exclusive') ($leaked24.Count -eq 0) ('leaked=' + ($leaked24 -join '|'))
}
Check 'cap_hint_open_stage_refuses_to_close_chain' (-not ($run24ByTag['open_stage'].Text -match '"set_status":"done"')) ('text_has_set_status=' + [bool]($run24ByTag['open_stage'].Text -match '"set_status":"done"'))
Check 'cap_hint_all_done_says_how_to_close' ($run24ByTag['all_done'].Text -match '"set_status":"done"') ''
Check 'cap_hint_reason_is_unchanged' ($run24ByTag['all_done'].Text -match 'FAIL reason=chain_at_stage_cap') ''

# --- case 25: the ledger describes the chain in the launcher's words -----------
# B19-a. -Action status prints a second line, LEDGER_CHAIN, carrying the same
# vocabulary the launcher prints on its cap gate (cap_reached= / stages= /
# all_done= / open_stages=). The two renderings are separate code on purpose, so
# the cross check below feeds both the same ledger and compares them field by
# field: a drift in either one goes red instead of being copied over from the
# other. Five shapes are covered, including the two the launcher never prints a
# cap line for (below the cap, and a ledger whose stage numbers are missing).
$r25 = New-Repo 'repo-chain-status'
New-Item -ItemType Directory -Path (Join-Path $r25 'docs\relay') -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $r25 'docs\plans') -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $tplDir 'start-relay.ps1') -Destination (Join-Path $r25 'docs\relay\start-relay.ps1') -Force
Copy-Item -LiteralPath (Join-Path $tplDir 'relay-lock.ps1') -Destination (Join-Path $r25 'docs\relay\relay-lock.ps1') -Force
Copy-Item -LiteralPath (Join-Path $tplDir 'relay-ledger.ps1') -Destination (Join-Path $r25 'docs\relay\relay-ledger.ps1') -Force
[IO.File]::WriteAllText((Join-Path $r25 'docs\plans\f9.md'), ('# plan' + "`n`n" + '1. first stage' + "`n" + '2. second stage' + "`n"), (New-Object Text.UTF8Encoding($false)))
$chain25 = @(
  @{ tag = 'all_done'; cur = 2; max = 2; stages = @(@{ id = 1; status = 'done' }, @{ id = 2; status = 'done' }); expect = 'cap_reached=true stages=1:done,2:done all_done=true open_stages=0'; cross = $true },
  @{ tag = 'open_stage'; cur = 2; max = 2; stages = @(@{ id = 1; status = 'done' }, @{ id = 2; status = 'pending' }); expect = 'cap_reached=true stages=1:done,2:pending all_done=false open_stages=1'; cross = $true },
  @{ tag = 'no_records'; cur = 2; max = 2; stages = @(); expect = 'cap_reached=true stages=none all_done=unknown open_stages=none'; cross = $true },
  @{ tag = 'below_cap'; cur = 1; max = 2; stages = @(@{ id = 1; status = 'running' }, @{ id = 2; status = 'pending' }); expect = 'cap_reached=false stages=1:running,2:pending all_done=false open_stages=2'; cross = $false },
  @{ tag = 'no_numbers'; cur = $null; max = $null; stages = @(@{ id = 1; status = 'done' }); expect = 'cap_reached=unknown stages=1:done all_done=true open_stages=0'; cross = $false }
)
$ledgerPath25 = Join-Path $r25 'docs\relay.json'
foreach ($c25 in $chain25) {
  $led25 = [ordered]@{
    goal = 'chain status'; plan_doc = 'docs\plans\f9.md'; workspace_dir = $r25
    status = 'running'; auto_relay = $true; current_stage = $c25.cur; max_stages = $c25.max
    next_session_id = $null; stages = $c25.stages
    sessions = @(); notes = @(); blocked_on = @()
  }
  [IO.File]::WriteAllText($ledgerPath25, ($led25 | ConvertTo-Json -Depth 6), (New-Object Text.UTF8Encoding($false)))
  $st25 = Run (Join-Path $r25 'docs\relay\relay-ledger.ps1') @('-Action', 'status', '-LedgerPath', $ledgerPath25)
  $chainLine25 = (($st25.Text -split "`n") | Where-Object { $_ -match '^LEDGER_CHAIN ' } | Select-Object -First 1)
  Check ('chain_status_' + $c25.tag + '_reads') ($st25.Code -eq 0 -and [bool]$chainLine25) ('exit=' + $st25.Code + ' line=' + $chainLine25)
  Check ('chain_status_' + $c25.tag + '_reports_its_shape') ([bool]($chainLine25 -match [regex]::Escape($c25.expect))) ('expect=' + $c25.expect + ' line=' + $chainLine25)
  Check ('chain_status_' + $c25.tag + '_keeps_the_state_line') ([bool]($st25.Text -match '(?m)^LEDGER_STATE ')) ''
  if ($c25.cross) {
    $run25 = Run (Join-Path $r25 'docs\relay\start-relay.ps1') @('-Target', 'f9', '-DryRun')
    $fail25 = (($run25.Text -split "`n") | Where-Object { $_ -match 'FAIL reason=chain_at_stage_cap' } | Select-Object -First 1)
    $lStages25 = ''; if ($chainLine25 -match ' stages=([^ ]+) ') { $lStages25 = $Matches[1] }
    $lDone25 = ''; if ($chainLine25 -match ' all_done=([a-z]+) ') { $lDone25 = $Matches[1] }
    $fStages25 = ''; if ($fail25 -match ' stages=([^ ]+) ') { $fStages25 = $Matches[1] }
    $fDone25 = ''; if ($fail25 -match ' all_done=([a-z]+)') { $fDone25 = $Matches[1] }
    Check ('chain_status_' + $c25.tag + '_agrees_with_launcher_stages') ($lStages25 -ne '' -and $lStages25 -eq $fStages25) ('ledger=' + $lStages25 + ' launcher=' + $fStages25)
    Check ('chain_status_' + $c25.tag + '_agrees_with_launcher_all_done') ($lDone25 -ne '' -and $lDone25 -eq $fDone25) ('ledger=' + $lDone25 + ' launcher=' + $fDone25)
  }
}
Check 'chain_status_keeps_the_stage_count_distinct' ([bool]($st25.Text -match '(?m)^LEDGER_STATE .* stages=\d+ ') -and [bool]($chainLine25 -match ' stages=[0-9]+:')) 'the count and the list share a key name; the line prefix must tell them apart'

# --- case 26: the managed close goes through the ledger gate -------------------
# B19-b. -AutoFinalize is opt in and only fires in the one shape where every
# declared stage is done. Six scenes: an open stage is never closed, a dry run
# announces the skip and writes nothing, the switch is off by default, a held
# writer lock makes the close fail as a gate, the happy path reaches status=done,
# and the re-run reports an exhausted chain instead of finalizing twice. The
# locked scene is what proves the write really goes through relay-ledger.ps1: a
# bare Set-Content would not care about that lock at all.
$r26 = New-Repo 'repo-auto-finalize'
New-Item -ItemType Directory -Path (Join-Path $r26 'docs\relay') -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $r26 'docs\plans') -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $tplDir 'start-relay.ps1') -Destination (Join-Path $r26 'docs\relay\start-relay.ps1') -Force
Copy-Item -LiteralPath (Join-Path $tplDir 'relay-lock.ps1') -Destination (Join-Path $r26 'docs\relay\relay-lock.ps1') -Force
Copy-Item -LiteralPath (Join-Path $tplDir 'relay-ledger.ps1') -Destination (Join-Path $r26 'docs\relay\relay-ledger.ps1') -Force
[IO.File]::WriteAllText((Join-Path $r26 'docs\plans\f10.md'), ('# plan' + "`n`n" + '1. first stage' + "`n" + '2. second stage' + "`n"), (New-Object Text.UTF8Encoding($false)))
$ledgerPath26 = Join-Path $r26 'docs\relay.json'
$lockPath26 = Join-Path $r26 'docs\relay\.ledger.lock'
$launcher26 = Join-Path $r26 'docs\relay\start-relay.ps1'
$writeLedger26 = {
  param([string]$LastStageStatus)
  $st26 = @(@{ id = 1; title = 'first stage'; status = 'done' }, @{ id = 2; title = 'second stage'; status = $LastStageStatus })
  $led26 = [ordered]@{
    goal = 'auto finalize'; plan_doc = 'docs\plans\f10.md'; workspace_dir = $r26
    status = 'running'; auto_relay = $true; current_stage = 2; max_stages = 2
    next_session_id = $null; stages = $st26
    sessions = @(); notes = @(); blocked_on = @()
  }
  [IO.File]::WriteAllText($ledgerPath26, ($led26 | ConvertTo-Json -Depth 6), (New-Object Text.UTF8Encoding($false)))
}
$readStatus26 = { ([IO.File]::ReadAllText($ledgerPath26) | ConvertFrom-Json).status }
& $writeLedger26 'pending'
$s1 = Run $launcher26 @('-Target', 'f10', '-AutoFinalize')
Check 'auto_finalize_open_stage_is_not_closed' (-not ($s1.Text -match 'AUTO_FINALIZED')) ''
Check 'auto_finalize_open_stage_raises_no_warn' (-not ($s1.Text -match 'WARN auto_finalize')) ''
Check 'auto_finalize_open_stage_leaves_ledger_running' ((& $readStatus26) -eq 'running') ('status=' + (& $readStatus26))
Check 'auto_finalize_open_stage_still_exits_three' ($s1.Code -eq 3) ('exit=' + $s1.Code)
& $writeLedger26 'done'
$s2 = Run $launcher26 @('-Target', 'f10', '-AutoFinalize', '-DryRun')
Check 'auto_finalize_dry_run_announces_the_skip' ([bool]($s2.Text -match 'DRYRUN skip=auto_finalize')) ''
Check 'auto_finalize_dry_run_writes_nothing' (-not ($s2.Text -match 'AUTO_FINALIZED') -and (& $readStatus26) -eq 'running') ('status=' + (& $readStatus26))
Check 'auto_finalize_dry_run_still_exits_three' ($s2.Code -eq 3) ('exit=' + $s2.Code)
& $writeLedger26 'done'
$s3 = Run $launcher26 @('-Target', 'f10')
Check 'auto_finalize_is_off_by_default' (-not ($s3.Text -match 'AUTO_FINALIZED') -and (& $readStatus26) -eq 'running') ('status=' + (& $readStatus26))
Check 'auto_finalize_off_keeps_the_cap_fail' ([bool]($s3.Text -match 'FAIL reason=chain_at_stage_cap')) ''
& $writeLedger26 'done'
[IO.File]::WriteAllText($lockPath26, ('pid=' + $PID + ' host=selftest taken_at=' + [DateTimeOffset]::Now.ToString('o')), (New-Object Text.UTF8Encoding($false)))
$s4 = Run $launcher26 @('-Target', 'f10', '-AutoFinalize')
Check 'auto_finalize_held_lock_is_refused' ([bool]($s4.Text -match 'WARN auto_finalize=failed')) ('warn=' + [bool]($s4.Text -match 'WARN auto_finalize=failed'))
Check 'auto_finalize_held_lock_reason_names_the_gate' ([bool]($s4.Text -match 'writer_lock_timeout')) ''
Check 'auto_finalize_held_lock_leaves_ledger_running' ((& $readStatus26) -eq 'running') ('status=' + (& $readStatus26))
Check 'auto_finalize_held_lock_still_exits_three' ($s4.Code -eq 3) ('exit=' + $s4.Code)
Check 'auto_finalize_held_lock_is_not_stolen' (Test-Path -LiteralPath $lockPath26) ''
Remove-Item -LiteralPath $lockPath26 -Force -ErrorAction SilentlyContinue
& $writeLedger26 'done'
$s5 = Run $launcher26 @('-Target', 'f10', '-AutoFinalize')
Check 'auto_finalize_closes_the_chain' ([bool]($s5.Text -match 'AUTO_FINALIZED status=done')) ''
Check 'auto_finalize_ledger_reaches_done' ((& $readStatus26) -eq 'done') ('status=' + (& $readStatus26))
Check 'auto_finalize_reports_both_hashes' ([bool]($s5.Text -match 'AUTO_FINALIZED status=done before=[0-9a-f]{64} after=[0-9a-f]{64}')) ''
Check 'auto_finalize_swaps_in_its_own_hint' ([bool]($s5.Text -match 'HINT=chain_closed_by_auto_finalize')) ''
Check 'auto_finalize_invents_no_second_reason' (-not ($s5.Text -match 'FAIL reason=chain_exhausted')) ''
Check 'auto_finalize_close_still_exits_three' ($s5.Code -eq 3) ('exit=' + $s5.Code)
$s6 = Run $launcher26 @('-Target', 'f10', '-AutoFinalize')
Check 'auto_finalize_rerun_reports_exhausted' ([bool]($s6.Text -match 'FAIL reason=chain_exhausted')) ('fail=' + (($s6.Text -split "`n") | Where-Object { $_ -match '^FAIL ' } | Select-Object -First 1))
Check 'auto_finalize_rerun_never_finalizes_twice' (-not ($s6.Text -match 'AUTO_FINALIZED')) ''
Check 'auto_finalize_rerun_exits_three' ($s6.Code -eq 3) ('exit=' + $s6.Code)

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
