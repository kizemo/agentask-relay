<#
.SYNOPSIS
  One-click regression suite for the agentask-relay kit (turns project rule 1 into a runnable script).
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
$script:root = Join-Path $env:TEMP ('agentask-relay-selftest\' + $stamp)
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
if (Test-Path $dryArtifact) { $dry1 = [IO.File]::ReadAllText($dryArtifact) } else { $dry1 = '<missing>' }
$dry1Line = (($dry1 -split "`n") | Where-Object { $_ -match 'plan_doc=' } | Select-Object -First 1)
Check 'install_dryrun_passed_plandoc_through' ($dry1 -match 'OK plan_doc=docs[\\/]plan-b1\.md') ('artifact=' + $dryArtifact + ' line=' + $dry1Line)

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
    goal = 'gate batch'; plan_doc = ''; workspace_dir = 'X'; status = 'running'; auto_relay = $true
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
Check 'blocked_ledger_lines' ($f12d.Text -match 'FAIL reason=chain_blocked' -and $f12d.Text -match 'blocked_on=needs a human decision' -and $f12d.Text -match 'HINT=blocked chains need a human decision') ('line=' + (((($f12d.Text -split "`n") | Where-Object { $_ -match 'chain_blocked' } | Select-Object -First 1))))
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
$lauLiterals = @('workspace_missing', 'not_a_git_repo', 'ledger_unparsable', 'stage_in_progress', 'one_writer_per_project', 'chain_already_running', 'chain_at_stage_cap', 'chain_exhausted', 'chain_blocked', 'ledger_absent', 'plan_doc_not_found', 'plan_doc_missing', 'plan_doc_ambiguous', 'probe_newest_of_', 'by=newest_mtime', 'pass_-PlanDoc_to_disambiguate', 'lock_unavailable', 'DRYRUN skip=lock_acquire')
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
Check 'adapt_status_partial' ($c18b.Text -match 'ADAPTATION_STATUS=partial') ''
Check 'adapt_answers_source_answers' ($c18b.Text -match 'ADAPTATION_SOURCE=answers') ''
Check 'adapt_questions_line_cleared' (-not ($c18b.Text -match 'ADAPTATION_QUESTIONS=docs')) ''
Check 'adapt_answers_no_unconfirmed_warn' (-not ($c18b.Text -match 'WARN adaptation_defaults_unconfirmed')) ''
$adaptTxt18b = ''
if (Test-Path -LiteralPath $adaptDoc18) { $adaptTxt18b = [IO.File]::ReadAllText($adaptDoc18) }
Check 'adapt_answers_wrote_values' ($adaptTxt18b -match 'GATE_VERDICT=PASS' -and $adaptTxt18b -match 'secrets/' -and $adaptTxt18b -match 'tests/') ''
Check 'adapt_answers_source_marked' ((([regex]::Matches($adaptTxt18b, 'source: answers')).Count) -eq 3) ''
Check 'adapt_answers_kept_later_sections' ($adaptTxt18b -match '## 6\.' -and $adaptTxt18b -match '## 9\.') ''

# B31: "confirmed" has to mean that every key really landed. A 5 of 8 answers
# file is partial, so the confirmed state needs a second run with all eight
# keys answered. The answers file is written before the install, so the
# directory has to exist first.
$r18d = New-Repo 'repo-adapt-confirmed'
New-Item -ItemType Directory -Path (Join-Path $r18d 'docs\relay') -Force | Out-Null
Set-Content -LiteralPath (Join-Path $r18d 'docs\plan-18d.md') -Value '# plan 18d' -Encoding utf8
$ans18d = [ordered]@{
  schema = 'relay-port/adaptation-answers@1'
  write_set_allow = @('src/', 'tests/')
  write_set_deny = @('secrets/')
  concurrency_check = 'pwsh -NoProfile -ExecutionPolicy Bypass -File docs\relay\relay-lock.ps1 -Action status'
  gate_command = 'pwsh -NoProfile -ExecutionPolicy Bypass -File scripts\gate-check.ps1'
  gate_verdict_field = 'GATE_VERDICT=PASS'
  model_primary = 'minimax/MiniMax-M3'
  model_fallback_day = 'custom_provider:provider-aa5659/auto'
  model_fallback_night = 'custom_provider:provider-aa5659/deepseek-v4.1-flash-1017'
}
$ans18dPath = Join-Path $r18d 'docs\relay\adaptation-answers.json'
[IO.File]::WriteAllText($ans18dPath, (($ans18d | ConvertTo-Json -Depth 4) -replace "`r`n", "`n"), (New-Object Text.UTF8Encoding($false)))
$c18d = Run $installer @('-RepoRoot', $r18d, '-Target', 'adapt batch', '-PlanDoc', 'docs\plan-18d.md', '-MaxStages', '2', '-AnswersFile', 'docs\relay\adaptation-answers.json')
Check 'adapt_status_confirmed' ($c18d.Code -eq 0 -and $c18d.Text -match 'ADAPTATION_STATUS=confirmed') ('exit=' + $c18d.Code + ' text=' + $c18d.Text)
Check 'adapt_answers_all_keys_applied' ($c18d.Text -match 'ADAPT answers=docs\\relay\\adaptation-answers\.json applied=8/8') ('text=' + $c18d.Text)
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
  @{ tag = 'no_numbers'; cur = $null; max = $null; stages = @(@{ id = 1; status = 'done' }); expect = 'cap_reached=unknown stages=1:done all_done=true open_stages=0'; cross = $false },
  # B30: a ledger written before stage ids existed keys its stages by stage.
  # Rendering only id printed ":done" - an empty key that reads exactly like a
  # stage whose id is the empty string - and the launcher printed the same empty
  # key, so the field-by-field cross check below agreed with a line that told
  # the reader nothing. Identity now falls back id -> stage -> #index in both
  # renderers, and the expected line is asserted verbatim so a silent fallback
  # to ":done" cannot pass by being equal on both sides.
  @{ tag = 'legacy_stage_key'; cur = 2; max = 2; stages = @(@{ stage = 1; status = 'done' }, @{ stage = 2; status = 'done' }); expect = 'cap_reached=true stages=1:done,2:done all_done=true open_stages=0'; cross = $true },
  @{ tag = 'no_identity_key'; cur = 1; max = 2; stages = @(@{ status = 'done' }); expect = 'cap_reached=false stages=#0:done all_done=true open_stages=0'; cross = $false }
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
# B30: a stage with no identity key is rendered as #<index>, so the list half of
# this shape accepts an optional # before the entry number. A bare count
# (stages=2) still has no colon and still fails, so the discrimination stays.
Check 'chain_status_keeps_the_stage_count_distinct' ([bool]($st25.Text -match '(?m)^LEDGER_STATE .* stages=\d+ ') -and [bool]($chainLine25 -match ' stages=(?:#)?[0-9]+:')) 'the count and the list share a key name; the line prefix must tell them apart'

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

# --- case 27: an ephemeral link leaves no project behind -------------------------
# Claude Code keys every session by its working directory and writes the entry
# into <user profile>\.claude\projects\<mangled cwd>, and the desktop client
# renders that directory as its project list. A link that runs in a throwaway
# fixture therefore leaves a project behind that the user never asked for.
# The spawn driver can move that entry away again. This case runs the real
# driver against a fake claude that creates the entry, and it runs it twice:
# without the switch the entry must stay (otherwise the case would pass for
# the wrong reason), with the switch the entry must be gone and its transcript
# must still be on disk.
$shimDir27 = Join-Path $script:root 'shim27'
New-Item -ItemType Directory -Path $shimDir27 -Force | Out-Null
$shim27 = Join-Path $shimDir27 'claude.cmd'
$shimBody27 = @'
@echo off
setlocal
if not exist "%RELAY_TEST_REGISTRY%\%RELAY_TEST_PROJECT_KEY%" mkdir "%RELAY_TEST_REGISTRY%\%RELAY_TEST_PROJECT_KEY%"
echo {"type":"result","session_id":"22222222-3333-4444-5555-666666666666","result":"ok"}
exit /b 0
'@
[IO.File]::WriteAllText($shim27, ($shimBody27 -replace "`r`n", "`n"), (New-Object Text.UTF8Encoding($false)))
$repo27 = New-Repo 'repo-ephemeral'
$prompt27 = Join-Path $script:root 'relay-prompt-27.txt'
[IO.File]::WriteAllText($prompt27, ("ephemeral prompt`n"), (New-Object Text.UTF8Encoding($false)))
$key27 = ($repo27 -replace '[^A-Za-z0-9]', '-')
function Invoke-FakeSpawn27([string]$CfgDir, [bool]$Ephemeral) {
  New-Item -ItemType Directory -Path (Join-Path $CfgDir 'projects') -Force | Out-Null
  $oldPath = $env:PATH
  $oldCfg = $env:CLAUDE_CONFIG_DIR
  $oldReg = $env:RELAY_TEST_REGISTRY
  $oldKey = $env:RELAY_TEST_PROJECT_KEY
  try {
    $env:PATH = $shimDir27 + [IO.Path]::PathSeparator + $oldPath
    $env:CLAUDE_CONFIG_DIR = $CfgDir
    $env:RELAY_TEST_REGISTRY = (Join-Path $CfgDir 'projects')
    $env:RELAY_TEST_PROJECT_KEY = $key27
    $argv = @('-Runtime', 'claude-code', '-PromptFile', $prompt27, '-WorkspaceDir', $repo27, '-Execute')
    if ($Ephemeral) { $argv += '-EphemeralWorkspace' }
    return (Run (Join-Path $tplDir 'relay-spawn.ps1') $argv)
  } finally {
    $env:PATH = $oldPath
    $env:CLAUDE_CONFIG_DIR = $oldCfg
    $env:RELAY_TEST_REGISTRY = $oldReg
    $env:RELAY_TEST_PROJECT_KEY = $oldKey
  }
}
$cfg27a = Join-Path $script:root 'cfg27a'
$cfg27b = Join-Path $script:root 'cfg27b'
$s27a = Invoke-FakeSpawn27 $cfg27a $false
Check 'ephemeral_fake_claude_ran' ($s27a.Code -eq 0) ('exit=' + $s27a.Code)
Check 'ephemeral_entry_appears_without_the_switch' (Test-Path -LiteralPath (Join-Path (Join-Path $cfg27a 'projects') $key27)) ('key=' + $key27)
$s27b = Invoke-FakeSpawn27 $cfg27b $true
Check 'ephemeral_spawn_with_switch_exits_zero' ($s27b.Code -eq 0) ('exit=' + $s27b.Code)
Check 'ephemeral_spawn_reports_the_cleanup' ($s27b.Text -match 'SPAWN_EPHEMERAL_PROJECT_CLEANED') ''
Check 'ephemeral_entry_is_gone_after_the_switch' (-not (Test-Path -LiteralPath (Join-Path (Join-Path $cfg27b 'projects') $key27))) ('key=' + $key27)
Check 'ephemeral_transcript_is_kept_as_evidence' (Test-Path -LiteralPath (Join-Path $cfg27b '_relay-ephemeral')) ''
Check 'ephemeral_cleanup_touches_no_other_registry' (Test-Path -LiteralPath (Join-Path (Join-Path $cfg27a 'projects') $key27)) ''

# The flag has to travel all the way into the spawn command of the prompt: in a
# fixture chain nobody types it by hand, the link that starts the next link is
# the one that runs the command the launcher wrote.
$repo27b = New-Repo 'repo-ephemeral-launcher'
Set-Content -LiteralPath (Join-Path $repo27b 'docs\plan-27.md') -Value '# plan 27' -Encoding utf8
$i27 = Run $installer @('-RepoRoot', $repo27b, '-Target', 'e27', '-PlanDoc', 'docs\plan-27.md', '-MaxStages', '2', '-Runtime', 'claude-code')
Check 'ephemeral_launcher_install_exit_zero' ($i27.Code -eq 0) ('exit=' + $i27.Code)
$l27 = Run (Join-Path $repo27b 'docs\relay\start-relay.ps1') @('-Target', 'e27', '-MaxStages', '2', '-EphemeralWorkspace', '-DryRun')
Check 'ephemeral_launcher_carries_the_flag' ($l27.Text -match 'relay-spawn\.ps1[^\r\n]*-EphemeralWorkspace') ''
$l27b = Run (Join-Path $repo27b 'docs\relay\start-relay.ps1') @('-Target', 'e27', '-MaxStages', '2', '-DryRun')
Check 'ephemeral_launcher_is_off_by_default' (-not ($l27b.Text -match '-EphemeralWorkspace')) ''

# --- case 28: the launcher names the project the chain lands in -----------------
# B23: the host files a session under the project whose workspace path is exactly
# the directory the session runs in, so a repository that lives inside another
# directory the operator calls "the project" lands in a project of its own, and
# until now the launcher said nothing about it. Two scenes with opposite
# expectations, so the assertion can tell the two apart: the recorded project is
# the parent container (mismatch, reported) and the recorded project is the
# repository root (no mismatch, and the key line is still there).
$container28 = Join-Path $script:root 'container28'
New-Item -ItemType Directory -Path $container28 -Force | Out-Null
$repo28 = New-Repo 'container28\repo-nested'
Set-Content -LiteralPath (Join-Path $repo28 'docs\plan-28.md') -Value '# plan 28' -Encoding utf8
$i28 = Run $installer @('-RepoRoot', $repo28, '-Target', 'e28', '-PlanDoc', 'docs\plan-28.md', '-MaxStages', '2')
Check 'host_project_install_exit_zero' ($i28.Code -eq 0) ('exit=' + $i28.Code)
$expectFile28 = Join-Path $repo28 'docs\relay\host-project.txt'
# bad scene: the operator expects the chain under the parent container
Set-Content -LiteralPath $expectFile28 -Value $container28 -Encoding utf8
$g28 = Run (Join-Path $repo28 'docs\relay\start-relay.ps1') @('-Target', 'e28', '-MaxStages', '2', '-DryRun')
$mismatchLine28 = (($g28.Text -split "`n") | Where-Object { $_ -match 'host_project_mismatch' } | Select-Object -First 1)
Check 'host_project_mismatch_reported' ($g28.Text -match 'WARN host_project_mismatch') ('line=' + $mismatchLine28)
Check 'host_project_mismatch_names_the_key' ($g28.Text -match 'actual_key=' + [regex]::Escape($repo28)) ('repo=' + $repo28)
Check 'host_project_mismatch_explains_the_rule' ($g28.Text -match 'reason=host_projects_are_keyed_by_exact_workspace_path') ('line=' + $mismatchLine28)
# good scene: the recorded project is the repository root itself
Set-Content -LiteralPath $expectFile28 -Value $repo28 -Encoding utf8
$b28 = Run (Join-Path $repo28 'docs\relay\start-relay.ps1') @('-Target', 'e28', '-MaxStages', '2', '-DryRun')
Check 'host_project_match_is_quiet' (-not ($b28.Text -match 'WARN host_project_mismatch')) ('line=' + ((($b28.Text -split "`n") | Where-Object { $_ -match 'host_project' } | Select-Object -First 1)))
Check 'host_project_key_always_reported' ($b28.Text -match 'INFO host_project_key exact_workspace_dir=' + [regex]::Escape($repo28)) ('repo=' + $repo28)

# B24: the launcher must stop handing out workspace_dir -- that argument is what makes
# the host insert a project row of its own -- and it must hard-stop when the recorded
# host project is not the directory the chain runs in. Three scenes, because "warn and
# continue" and "stop" are indistinguishable from a single dry run: mismatch without the
# switch (must exit 2), mismatch with the switch (parent hosting), and an exact launch
# whose ledger seed and prompt carry the chain identity.
Set-Content -LiteralPath $expectFile28 -Value $container28 -Encoding utf8
$f28 = Run (Join-Path $repo28 'docs\relay\start-relay.ps1') @('-Target', 'e28', '-MaxStages', '2')
Check 'host_project_mismatch_hard_fails' ($f28.Code -eq 2) ('exit=' + $f28.Code)
Check 'host_project_mismatch_explains_the_hard_stop' ($f28.Text -match 'FAIL reason=host_project_mismatch' -and $f28.Text -match 'rule=sessions_are_filed_under_the_exact_session_directory') ('exit=' + $f28.Code)
$p28 = Run (Join-Path $repo28 'docs\relay\start-relay.ps1') @('-Target', 'e28', '-MaxStages', '2', '-DryRun', '-AllowHostMismatch', '-InitiatorSession', 'mvs_case28')
Check 'host_project_parent_hosting_is_explicit' ($p28.Text -match 'mode=parent') ''
Check 'parent_hosting_is_not_silent' ($p28.Text -match 'reason=explicit_allow_host_mismatch') ''
Check 'initiator_session_is_recorded' ($p28.Text -match 'initiator_session=mvs_case28') ''
Check 'chain_identity_is_reported' ($p28.Text -match 'chain_id=relay-chain-\d{8}-\d{6}' -and $p28.Text -match 'chain_tag=\d{4}-\d{4}') ''
# exact launch: the project key equals the directory the session runs in, so the chain
# lands in the project that already exists instead of inserting a new row.
$ledger28 = Join-Path $repo28 'docs\relay.json'
if (Test-Path -LiteralPath $ledger28) { Remove-Item -LiteralPath $ledger28 -Force }
Set-Content -LiteralPath $expectFile28 -Value $repo28 -Encoding utf8
$r28 = Run (Join-Path $repo28 'docs\relay\start-relay.ps1') @('-Target', 'e28', '-MaxStages', '2', '-InitiatorSession', 'mvs_case28', '-ExpectedHostProject', $repo28)
Check 'host_project_exact_launch_exit_zero' ($r28.Code -eq 0) ('exit=' + $r28.Code)
$seed28 = $null
if (Test-Path -LiteralPath $ledger28) { $seed28 = Get-Content -LiteralPath $ledger28 -Raw -Encoding UTF8 | ConvertFrom-Json }
Check 'seed_records_chain_identity' ($null -ne $seed28 -and [string]$seed28.chain_id -like 'relay-*' -and [string]$seed28.chain_tag -match '^\d{4}-\d{4}$' -and [string]$seed28.initiator_session -eq 'mvs_case28') ''
Check 'seed_records_host_project' ($null -ne $seed28 -and [string]$seed28.host_project -eq $repo28 -and [string]$seed28.host_project_mode -eq 'exact') ''
$prompt28 = ''
$prompt28Path = Join-Path $repo28 'docs\relay\next-relay-prompt.txt'
if (Test-Path -LiteralPath $prompt28Path) { $prompt28 = [IO.File]::ReadAllText($prompt28Path) }
Check 'prompt_carries_chain_banner' ($prompt28 -match 'CHAIN relay-chain-\d{8}-\d{6} \| link relay-01of02 \| started ' -and $prompt28 -match '\| initiator mvs_case28 \| host project ') ''
Check 'prompt_names_the_host_project_key' ($prompt28 -match ('host project ' + [regex]::Escape($repo28) + ' \(exact\)')) ''
Check 'prompt_asks_for_the_project_argument' ($prompt28 -match 'project=') ''
Check 'prompt_never_hands_out_workspace_dir' ((-not ($prompt28 -match 'workspace_dir\s*=')) -and (-not ($prompt28 -match '"workspace_dir"'))) ''

# --- case b25: hand-over gate (prespawn / verify / stop sentinel / job registry) ---
# A foreground that is displayed as stopped must not be able to open a second
# writer: the permit is issued once, consumed once, and refused while a stop
# sentinel exists or while a registered background job is still alive.
$b25Lock = Join-Path $script:root 'b25\.relay.lock'
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $b25Lock) | Out-Null
$b25Tpl = Join-Path (Split-Path -Parent $PSScriptRoot) 'tool\templates\relay-lock.ps1'
function B25Run([string[]]$b25Args) {
  $b25Out = & pwsh -NoProfile -ExecutionPolicy Bypass -File $b25Tpl @b25Args 2>&1 | Out-String
  [pscustomobject]@{ Code = $LASTEXITCODE; Text = $b25Out }
}
$b25a = B25Run @('-Action','acquire','-SessionId','sess-a','-TtlSeconds','600','-LockPath',$b25Lock)
Check 'b25_lock_acquired' ($b25a.Code -eq 0 -and $b25a.Text -match 'LOCK_') ('exit=' + $b25a.Code + ' text=' + $b25a.Text)
$b25p1 = B25Run @('-Action','prespawn','-Stage','1','-LockPath',$b25Lock)
Check 'b25_prespawn_permit' ($b25p1.Code -eq 0 -and $b25p1.Text -match 'SPAWN_PERMIT ok nonce=') ('exit=' + $b25p1.Code + ' text=' + $b25p1.Text)
$b25nonce = ''
if ($b25p1.Text -match 'SPAWN_PERMIT ok nonce=(\w+)') { $b25nonce = $matches[1] }
Check 'b25_prespawn_nonce_shape' ($b25nonce.Length -eq 16) ('nonce=' + $b25nonce)
$b25p2 = B25Run @('-Action','prespawn','-Stage','1','-LockPath',$b25Lock)
Check 'b25_second_prespawn_refused' ($b25p2.Code -eq 3 -and $b25p2.Text -match 'permit_outstanding') ('exit=' + $b25p2.Code + ' text=' + $b25p2.Text)
$b25v0 = B25Run @('-Action','verify','-SessionId','sess-b','-Nonce','0000000000000000','-LockPath',$b25Lock)
Check 'b25_verify_wrong_nonce' ($b25v0.Code -eq 3 -and $b25v0.Text -match 'PERMIT_INVALID reason=nonce_mismatch') ('exit=' + $b25v0.Code + ' text=' + $b25v0.Text)
$b25v1 = B25Run @('-Action','verify','-SessionId','sess-b','-Nonce',$b25nonce,'-LockPath',$b25Lock)
Check 'b25_verify_consumes_permit' ($b25v1.Code -eq 0 -and $b25v1.Text -match 'SPAWN_VERIFIED ok nonce=') ('exit=' + $b25v1.Code + ' text=' + $b25v1.Text)
$b25v2 = B25Run @('-Action','verify','-SessionId','sess-c','-Nonce',$b25nonce,'-LockPath',$b25Lock)
Check 'b25_permit_single_use' ($b25v2.Code -eq 3 -and $b25v2.Text -match 'PERMIT_INVALID reason=permit_consumed') ('exit=' + $b25v2.Code + ' text=' + $b25v2.Text)
$b25j1 = B25Run @('-Action','job-register','-SessionId','sess-b','-ProcId',"$PID",'-LockPath',$b25Lock)
Check 'b25_job_registered' ($b25j1.Code -eq 0 -and $b25j1.Text -match 'JOB_REGISTERED') ('exit=' + $b25j1.Code + ' text=' + $b25j1.Text)
$b25b1 = B25Run @('-Action','prespawn','-Stage','2','-LockPath',$b25Lock)
Check 'b25_live_job_blocks_spawn' ($b25b1.Code -eq 5 -and $b25b1.Text -match 'reason=background_jobs_live') ('exit=' + $b25b1.Code + ' text=' + $b25b1.Text)
$null = B25Run @('-Action','job-clear','-SessionId','sess-b','-ProcId',"$PID",'-LockPath',$b25Lock)
$b25p3 = B25Run @('-Action','prespawn','-Stage','2','-LockPath',$b25Lock)
Check 'b25_prespawn_after_job_clear' ($b25p3.Code -eq 0 -and $b25p3.Text -match 'SPAWN_PERMIT ok nonce=') ('exit=' + $b25p3.Code + ' text=' + $b25p3.Text)
$b25nonce2 = ''
if ($b25p3.Text -match 'SPAWN_PERMIT ok nonce=(\w+)') { $b25nonce2 = $matches[1] }
$null = B25Run @('-Action','stop-mark','-SessionId','sess-b','-Note','selftest','-LockPath',$b25Lock)
$b25s1 = B25Run @('-Action','prespawn','-Stage','3','-LockPath',$b25Lock)
Check 'b25_stop_blocks_spawn' ($b25s1.Code -eq 3 -and $b25s1.Text -match 'reason=chain_stopped') ('exit=' + $b25s1.Code + ' text=' + $b25s1.Text)
$b25s2 = B25Run @('-Action','verify','-SessionId','sess-d','-Nonce',$b25nonce2,'-LockPath',$b25Lock)
Check 'b25_stop_blocks_verify' ($b25s2.Code -eq 3 -and $b25s2.Text -match 'PERMIT_INVALID reason=chain_stopped') ('exit=' + $b25s2.Code + ' text=' + $b25s2.Text)
$null = B25Run @('-Action','stop-clear','-SessionId','sess-b','-LockPath',$b25Lock)
$b25s3 = B25Run @('-Action','prespawn','-Stage','3','-LockPath',$b25Lock)
Check 'b25_permit_still_outstanding' ($b25s3.Code -eq 3 -and $b25s3.Text -match 'permit_outstanding') ('exit=' + $b25s3.Code + ' text=' + $b25s3.Text)
$b25g = B25Run @('-Action','gate-status','-LockPath',$b25Lock)
Check 'b25_gate_status_line' ($b25g.Code -eq 0 -and $b25g.Text -match 'GATE holder=sess-b stop=no permit=outstanding jobs_live=0') ('exit=' + $b25g.Code + ' text=' + $b25g.Text)
$b25n = B25Run @('-Action','prespawn','-SessionId','sess-zzz','-LockPath',$b25Lock)
Check 'b25_lock_not_mine' ($b25n.Code -eq 5 -and $b25n.Text -match 'reason=lock_not_mine') ('exit=' + $b25n.Code + ' text=' + $b25n.Text)
# --- case b26: a repository that has no commit yet (B25-3 tail) -----------------
# `git rev-parse --short HEAD` prints nothing before the first commit. Both the
# installer and the launcher must fall back to head=none instead of dereferencing
# the empty result, otherwise no fresh project can ever get a dry run, let alone
# a chain. This case fails on the pre-fix launcher with a null method call.
$r26 = Join-Path $script:root 'repo-nohead'
New-Item -ItemType Directory -Path (Join-Path $r26 'docs') -Force | Out-Null
Set-Content -LiteralPath (Join-Path $r26 'docs\plan-b1.md') -Value '# plan b1' -Encoding utf8
& git -C $r26 init -q 2>&1 | Out-Null
$head26 = (& git -C $r26 rev-parse --short HEAD 2>$null)
Check 'nohead_fixture_really_has_no_head' ([string]::IsNullOrWhiteSpace([string]$head26)) ('probe=' + [string]$head26)
$a26 = Run $installer @('-RepoRoot', $r26, '-Target', 'zero batch', '-PlanDoc', 'docs\plan-b1.md', '-MaxStages', '2')
Check 'nohead_install_exit_zero' ($a26.Code -eq 0) ('exit=' + $a26.Code + ' tail=' + (($a26.Text -split "`n" | Select-Object -Last 3) -join ' | '))
Check 'nohead_install_reports_none' ($a26.Text -match 'REPO head=none') ('hits=' + ([regex]::Matches($a26.Text, 'REPO head=none')).Count)
$r26Launcher = Join-Path $r26 'docs\relay\start-relay.ps1'
$d26 = Run $r26Launcher @('-Target', 'zero batch', '-MaxStages', '2', '-DryRun')
Check 'nohead_dryrun_exit_zero' ($d26.Code -eq 0) ('exit=' + $d26.Code + ' tail=' + (($d26.Text -split "`n" | Select-Object -Last 3) -join ' | '))
Check 'nohead_dryrun_reports_none' ($d26.Text -match 'OK head=none dirty_files=\d+') ('line=' + ((($d26.Text -split "`n") | Where-Object { $_ -match 'OK head=' } | Select-Object -First 1)))
Check 'nohead_dryrun_no_null_deref' (-not ($d26.Text -match 'Null')) ('exit=' + $d26.Code)
# --- case b27: ledger state machine (R1/R3) and the spawn pre-gate (R5) ---------
# A relay port reported defects that share one shape: the ledger knew the truth
# and a reader acted on a stale or empty field. R1: an empty next_session_id was
# dropped without a word, so the stop recipe the prompt hands to every link
# ("blocked_on_append plus set_status=blocked and an empty next_session_id")
# could not clear it, and stage_done fell back to a dead id on a stopped chain.
# R3: set_status accepted any value and checked nothing. R2: the launcher called
# a hard stop a WARN. R5: the driver spawned for a blocked chain without ever
# reading status.
$r27 = New-GateRepo 'repo-b27-state' @{ next_session_id = 'sess-b27-old'; stages = @(@{ id = 1; title = 'b27 stage'; status = 'in_progress' }) }
$g27 = Join-Path $r27 'docs\relay\relay-ledger.ps1'
$l27led = Join-Path $r27 'docs\relay.json'
function P27([string]$Name, [string]$Body) {
  $p = Join-Path (Join-Path $r27 'docs\relay') $Name
  [IO.File]::WriteAllText($p, $Body, (New-Object Text.UTF8Encoding($false)))
  return $p
}
function L27Sha { (Get-FileHash -Algorithm SHA256 -LiteralPath $l27led).Hash }
$c27a = Run $g27 @('-Action','commit','-ExpectSha256',(L27Sha),'-Patch',(P27 'p27a.json' '{"next_session_id":""}'))
$led27a = Get-Content -LiteralPath $l27led -Raw | ConvertFrom-Json
Check 'b27_empty_next_session_id_clears' ($c27a.Code -eq 0 -and $c27a.Text -match 'LEDGER_NEXT_SESSION_CLEARED' -and [string]$led27a.next_session_id -eq '') ('exit=' + $c27a.Code + ' value=[' + [string]$led27a.next_session_id + ']')
$c27b = Run $g27 @('-Action','commit','-ExpectSha256',(L27Sha),'-Patch',(P27 'p27b.json' '{"next_session_id":"sess-b27-new"}'))
$led27b = Get-Content -LiteralPath $l27led -Raw | ConvertFrom-Json
Check 'b27_non_empty_next_session_id_still_sets' ($c27b.Code -eq 0 -and [string]$led27b.next_session_id -eq 'sess-b27-new') ('exit=' + $c27b.Code + ' value=' + [string]$led27b.next_session_id)

# R1 fallback: on a blocked chain the leftover id is not registered
$r27b = New-GateRepo 'repo-b27-blocked-trail' @{ status = 'blocked'; blocked_on = @('scope'); next_session_id = 'sess-b27-stale'; stages = @(@{ id = 1; title = 'b27 blocked stage'; status = 'in_progress' }) }
$g27b = Join-Path $r27b 'docs\relay\relay-ledger.ps1'
$l27b = Join-Path $r27b 'docs\relay.json'
$p27c = Join-Path (Join-Path $r27b 'docs\relay') 'p27c.json'
[IO.File]::WriteAllText($p27c, '{"stage_done":1}', (New-Object Text.UTF8Encoding($false)))
$c27c = Run $g27b @('-Action','commit','-ExpectSha256',(Get-FileHash -Algorithm SHA256 -LiteralPath $l27b).Hash,'-Patch',$p27c)
$led27c = Get-Content -LiteralPath $l27b -Raw | ConvertFrom-Json
Check 'b27_blocked_chain_does_not_register_stale_id' ($c27c.Code -eq 0 -and $c27c.Text -match 'LEDGER_SESSION_SKIPPED stage=1 reason=chain_not_running status=blocked' -and @($led27c.sessions).Count -eq 0) ('exit=' + $c27c.Code + ' sessions=' + @($led27c.sessions).Count + ' line=' + (($c27c.Text -split "`n") | Where-Object { $_ -match 'LEDGER_SESSION_' } | Select-Object -First 1))

# R3: a terminal status must agree with the stage list and with blocked_on
$r27s = New-GateRepo 'repo-b27-status' @{ stages = @(@{ id = 1; title = 'b27 s1'; status = 'done' }, @{ id = 2; title = 'b27 s2'; status = 'pending' }) }
$g27s = Join-Path $r27s 'docs\relay\relay-ledger.ps1'
$l27s = Join-Path $r27s 'docs\relay.json'
function P27S([string]$Name, [string]$Body) {
  $p = Join-Path (Join-Path $r27s 'docs\relay') $Name
  [IO.File]::WriteAllText($p, $Body, (New-Object Text.UTF8Encoding($false)))
  return $p
}
$sha27s = (Get-FileHash -Algorithm SHA256 -LiteralPath $l27s).Hash
$c27d = Run $g27s @('-Action','commit','-ExpectSha256',$sha27s,'-Patch',(P27S 'p27d.json' '{"set_status":"done"}'))
Check 'b27_done_with_open_stage_is_refused' ($c27d.Code -eq 3 -and $c27d.Text -match 'status_done_but_stages_open open_stages=2' -and (Get-FileHash -Algorithm SHA256 -LiteralPath $l27s).Hash -eq $sha27s) ('exit=' + $c27d.Code + ' line=' + (($c27d.Text -split "`n") | Where-Object { $_ -match 'STATUS|status_' } | Select-Object -First 1))
$c27e = Run $g27s @('-Action','commit','-ExpectSha256',$sha27s,'-Patch',(P27S 'p27e.json' '{"set_status":"blocked"}'))
Check 'b27_blocked_without_reason_is_refused' ($c27e.Code -eq 3 -and $c27e.Text -match 'status_blocked_without_blocked_on') ('exit=' + $c27e.Code)
$c27f = Run $g27s @('-Action','commit','-ExpectSha256',$sha27s,'-Patch',(P27S 'p27f.json' '{"set_status":"paused"}'))
Check 'b27_unknown_status_is_refused' ($c27f.Code -eq 2 -and $c27f.Text -match 'status_not_allowed value=paused') ('exit=' + $c27f.Code)
# the documented stop recipe works as ONE patch: reason, status, and a cleared claim
$c27g = Run $g27s @('-Action','commit','-ExpectSha256',$sha27s,'-Patch',(P27S 'p27g.json' '{"blocked_on_append":["needs a human decision on scope"],"set_status":"blocked","next_session_id":""}'))
$led27g = Get-Content -LiteralPath $l27s -Raw | ConvertFrom-Json
Check 'b27_stop_recipe_commits_in_one_patch' ($c27g.Code -eq 0 -and [string]$led27g.status -eq 'blocked' -and @($led27g.blocked_on).Count -eq 1 -and [string]$led27g.next_session_id -eq '') ('exit=' + $c27g.Code + ' status=' + [string]$led27g.status + ' blocked_on=' + (@($led27g.blocked_on) -join '|') + ' next=[' + [string]$led27g.next_session_id + ']')

# R5: the driver refuses to spawn for a chain a human stopped
$prompt27x = Join-Path $script:root 'relay-prompt-b27.txt'
[IO.File]::WriteAllText($prompt27x, ("b27 prompt`n"), (New-Object Text.UTF8Encoding($false)))
$spawn27 = Join-Path $tplDir 'relay-spawn.ps1'
$s27x = Run $spawn27 @('-Runtime','claude-code','-PromptFile',$prompt27x,'-WorkspaceDir',$r27s,'-Execute')
Check 'b27_spawn_refuses_blocked_chain' ($s27x.Code -eq 3 -and $s27x.Text -match 'SPAWN_LEDGER status=blocked' -and $s27x.Text -match 'FAIL reason=chain_not_running status=blocked') ('exit=' + $s27x.Code + ' line=' + (($s27x.Text -split "`n") | Where-Object { $_ -match 'SPAWN_LEDGER|chain_not_running' } | Select-Object -First 1))
$s27y = Run $spawn27 @('-Runtime','claude-code','-PromptFile',$prompt27x,'-WorkspaceDir',$r27s)
Check 'b27_spawn_dryrun_only_warns' ($s27y.Code -eq 0 -and $s27y.Text -match 'WARN reason=chain_not_running status=blocked' -and $s27y.Text -match 'SPAWN_EXECUTE=false') ('exit=' + $s27y.Code)
# --- case b28: read-only ledger doctor (R4) -------------------------------------
# A relay port reported a ledger whose current_stage named a stage the ledger did
# not contain, and whose next_session_id still named the session of a chain that
# had already stopped. Every reader downstream believes those fields, so R4 asks
# the gate to say it out loud. doctor only reports: it never takes the writer lock
# and never writes, which the checks below prove by comparing the ledger bytes and
# the gate directory around a run.
$r28 = New-GateRepo 'repo-b28-doctor-clean' @{ stages = @(@{ id = 1; title = 'b28 stage one'; status = 'done' }) }
$g28 = Join-Path $r28 'docs\relay\relay-ledger.ps1'
$l28 = Join-Path $r28 'docs\relay.json'
$dir28 = Join-Path $r28 'docs\relay'
$sha28a = (Get-FileHash -Algorithm SHA256 -LiteralPath $l28).Hash
$files28a = @(Get-ChildItem -LiteralPath $dir28 -File -Force).Count
$d28a = Run $g28 @('-Action','doctor')
$sha28b = (Get-FileHash -Algorithm SHA256 -LiteralPath $l28).Hash
$files28b = @(Get-ChildItem -LiteralPath $dir28 -File -Force).Count
Check 'b28_clean_ledger_exits_zero' ($d28a.Code -eq 0 -and $d28a.Text -match 'DOCTOR_VERDICT ok findings=0') ('exit=' + $d28a.Code + ' line=' + (($d28a.Text -split "`n") | Where-Object { $_ -match 'DOCTOR_VERDICT' }))
Check 'b28_doctor_reports_the_sha_it_read' ($d28a.Text -match ('DOCTOR_STATE .*sha256=' + $sha28a)) ('line=' + (($d28a.Text -split "`n") | Where-Object { $_ -match 'DOCTOR_STATE' } | Select-Object -First 1))
Check 'b28_doctor_writes_no_byte' ($sha28a -eq $sha28b) ('before=' + $sha28a + ' after=' + $sha28b)
Check 'b28_doctor_takes_no_lock_and_leaves_no_temp' ($files28a -eq $files28b -and -not (Test-Path -LiteralPath (Join-Path $dir28 '.ledger.lock'))) ('files=' + $files28a + '->' + $files28b)

# one fixture per dangling shape, so a finding that starts firing for the wrong
# reason cannot hide behind another one
$r28b = New-GateRepo 'repo-b28-doctor-dangling' @{ status = 'blocked'; blocked_on = @(); next_session_id = 'sess-b28-stale'; current_stage = 2; stages = @(@{ id = 1; title = 'b28 one'; status = 'done' }) }
$g28b = Join-Path $r28b 'docs\relay\relay-ledger.ps1'
$l28b = Join-Path $r28b 'docs\relay.json'
$sha28c = (Get-FileHash -Algorithm SHA256 -LiteralPath $l28b).Hash
$d28b = Run $g28b @('-Action','doctor')
$sha28d = (Get-FileHash -Algorithm SHA256 -LiteralPath $l28b).Hash
Check 'b28_dangling_exit_is_three' ($d28b.Code -eq 3) ('exit=' + $d28b.Code)
Check 'b28_missing_stage_is_reported' ($d28b.Text -match 'DANGLING current_stage=2 stage_missing=2') ('line=' + (($d28b.Text -split "`n") | Where-Object { $_ -match 'stage_missing' } | Select-Object -First 1))
Check 'b28_dead_next_session_is_reported' ($d28b.Text -match 'DANGLING next_session_id=sess-b28-stale reason=dead_pointer status=blocked') ('line=' + (($d28b.Text -split "`n") | Where-Object { $_ -match 'dead_pointer' } | Select-Object -First 1))
Check 'b28_blocked_without_reason_is_reported' ($d28b.Text -match 'DANGLING status=blocked blocked_on_present=false') ('line=' + (($d28b.Text -split "`n") | Where-Object { $_ -match 'blocked_on_present' } | Select-Object -First 1))
Check 'b28_verdict_counts_every_finding' ($d28b.Text -match 'DOCTOR_VERDICT dangling findings=3') ('line=' + (($d28b.Text -split "`n") | Where-Object { $_ -match 'DOCTOR_VERDICT' }))
Check 'b28_reporting_writes_nothing' ($sha28c -eq $sha28d) ('before=' + $sha28c + ' after=' + $sha28d)

# a launcher-seeded ledger (current_stage=1, stages=[]) is the normal start state,
# not a finding: a doctor that reddens every fresh chain is useless
$r28c = New-GateRepo 'repo-b28-doctor-fresh' @{}
$d28c = Run (Join-Path $r28c 'docs\relay\relay-ledger.ps1') @('-Action','doctor')
Check 'b28_fresh_seed_is_not_dangling' ($d28c.Code -eq 0 -and $d28c.Text -match 'DOCTOR_VERDICT ok findings=0') ('exit=' + $d28c.Code)

# the report's own shapes: a stage cap overrun and a duplicated stage id
$r28d = New-GateRepo 'repo-b28-doctor-cap' @{ current_stage = 9; max_stages = 3; stages = @(@{ id = 9; title = 'b28 nine'; status = 'done' }, @{ id = 9; title = 'b28 nine again'; status = 'done' }) }
$d28d = Run (Join-Path $r28d 'docs\relay\relay-ledger.ps1') @('-Action','doctor')
Check 'b28_stage_beyond_cap_is_reported' ($d28d.Code -eq 3 -and $d28d.Text -match 'DANGLING current_stage=9 max_stages=3 reason=beyond_stage_cap') ('exit=' + $d28d.Code + ' line=' + (($d28d.Text -split "`n") | Where-Object { $_ -match 'beyond_stage_cap' } | Select-Object -First 1))
Check 'b28_duplicate_stage_id_is_reported' ($d28d.Text -match 'DANGLING stage_id=9 reason=duplicate_stage_id') ('line=' + (($d28d.Text -split "`n") | Where-Object { $_ -match 'duplicate_stage_id' } | Select-Object -First 1))
Check 'b28_duplicate_is_reported_once_with_count' (([regex]::Matches($d28d.Text, 'duplicate_stage_id')).Count -eq 1 -and $d28d.Text -match 'reason=duplicate_stage_id count=2') ('hits=' + ([regex]::Matches($d28d.Text, 'duplicate_stage_id')).Count)

# a terminal status that disagrees with the stage list is exactly what the write
# gate refuses to create, so an old ledger still carrying it must be visible
$r28e = New-GateRepo 'repo-b28-doctor-done' @{ status = 'done'; current_stage = 2; max_stages = 2; stages = @(@{ id = 1; title = 'b28 one'; status = 'done' }, @{ id = 2; title = 'b28 two'; status = 'pending' }) }
$d28e = Run (Join-Path $r28e 'docs\relay\relay-ledger.ps1') @('-Action','doctor')
Check 'b28_done_with_open_stage_is_reported' ($d28e.Code -eq 3 -and $d28e.Text -match 'DANGLING status=done reason=open_stages open_stages=2') ('exit=' + $d28e.Code + ' line=' + (($d28e.Text -split "`n") | Where-Object { $_ -match 'open_stages' } | Select-Object -First 1))

# ledgers written before stages carried an id key list them by stage instead.
# Reading only id made the gate call a healthy such ledger dangling: one
# stage_missing plus one unnamed duplicate per stage. Both shapes are pinned here.
$r28f = New-GateRepo 'repo-b28-doctor-stagekey' @{ status = 'running'; current_stage = 2; max_stages = 2; stages = @(@{ stage = 1; title = 'b28 s1'; status = 'done' }, @{ stage = 2; title = 'b28 s2'; status = 'pending' }) }
$d28f = Run (Join-Path $r28f 'docs\relay\relay-ledger.ps1') @('-Action','doctor')
Check 'b28_stage_keyed_ledger_is_not_dangling' ($d28f.Code -eq 0 -and $d28f.Text -match 'DOCTOR_VERDICT ok findings=0') ('exit=' + $d28f.Code + ' out=' + ($d28f.Text -split "`n" | Where-Object { $_ -match 'DANGLING|DOCTOR_VERDICT' }) -join ' | ')
Check 'b28_stage_key_counts_as_the_current_stage' (-not ($d28f.Text -match 'stage_missing')) ('line=' + (($d28f.Text -split "`n") | Where-Object { $_ -match 'stage_missing' } | Select-Object -First 1))

$r28g = New-GateRepo 'repo-b28-doctor-unnamed' @{ status = 'running'; current_stage = 1; max_stages = 2; stages = @(@{ title = 'b28 no key one'; status = 'done' }, @{ title = 'b28 no key two'; status = 'done' }) }
$d28g = Run (Join-Path $r28g 'docs\relay\relay-ledger.ps1') @('-Action','doctor')
Check 'b28_stage_without_any_key_is_reported_once' (([regex]::Matches($d28g.Text, 'reason=stage_id_missing')).Count -eq 2 -and $d28g.Text -match 'DANGLING stage_index=1 reason=stage_id_missing') ('hits=' + ([regex]::Matches($d28g.Text, 'reason=stage_id_missing')).Count)
Check 'b28_unnamed_stages_are_not_duplicates' (-not ($d28g.Text -match 'duplicate_stage_id')) ('out=' + ($d28g.Text -split "`n" | Where-Object { $_ -match 'DANGLING|DOCTOR_VERDICT' }) -join ' | ')

# --- case b29: migration hints (read only) and the own-stage guard --------------
# R6 asks for migration advice without touching a live ledger: a ledger written by
# an older kit can be entirely self-consistent (doctor is green) and still carry a
# shape this gate cannot act on - a stage keyed by stage, when commit resolves
# stage_done by id only. migrate-hint names such shapes and writes nothing.
$r29a = New-GateRepo 'repo-b29-hint-clean' @{ stages = @(@{ id = 1; title = 'b29 one'; status = 'done' }) }
$g29a = Join-Path $r29a 'docs\relay\relay-ledger.ps1'
$l29a = Join-Path $r29a 'docs\relay.json'
$dir29a = Join-Path $r29a 'docs\relay'
$sha29a = (Get-FileHash -Algorithm SHA256 -LiteralPath $l29a).Hash
$files29a = @(Get-ChildItem -LiteralPath $dir29a -File -Force).Count
$m29a = Run $g29a @('-Action','migrate-hint')
$sha29b = (Get-FileHash -Algorithm SHA256 -LiteralPath $l29a).Hash
$files29b = @(Get-ChildItem -LiteralPath $dir29a -File -Force).Count
Check 'b29_current_schema_needs_no_migration' ($m29a.Code -eq 0 -and $m29a.Text -match 'MIGRATE_VERDICT none hints=0') ('exit=' + $m29a.Code + ' line=' + (($m29a.Text -split "`n") | Where-Object { $_ -match 'MIGRATE_VERDICT' }))
Check 'b29_migrate_hint_writes_no_byte' ($sha29a -eq $sha29b) ('before=' + $sha29a + ' after=' + $sha29b)
Check 'b29_migrate_hint_takes_no_lock' ($files29a -eq $files29b -and -not (Test-Path -LiteralPath (Join-Path $dir29a '.ledger.lock'))) ('files=' + $files29a + '->' + $files29b)
Check 'b29_migrate_hint_is_not_doctor' (-not ($m29a.Text -match 'DOCTOR_')) ('out=' + (($m29a.Text -split "`n") -join ' | '))

# the shape that actually blocks a live chain: stage keyed by stage, not id
$r29b = New-GateRepo 'repo-b29-hint-stagekey' @{ status = 'running'; current_stage = 2; max_stages = 2; stages = @(@{ stage = 1; title = 'b29 s1'; status = 'done' }, @{ stage = 2; title = 'b29 s2'; status = 'pending' }) }
$g29b = Join-Path $r29b 'docs\relay\relay-ledger.ps1'
$m29b = Run $g29b @('-Action','migrate-hint')
$d29b = Run $g29b @('-Action','doctor')
Check 'b29_stage_key_is_reported_with_rename' ($m29b.Code -eq 3 -and $m29b.Text -match 'MIGRATE_HINT scope=stage index=0 item=stage_key_not_id key=stage rename_to=id effect=commit_resolves_stage_done_by_id') ('exit=' + $m29b.Code + ' line=' + (($m29b.Text -split "`n") | Where-Object { $_ -match 'stage_key_not_id' } | Select-Object -First 1))
Check 'b29_every_stage_key_is_reported' (([regex]::Matches($m29b.Text, 'item=stage_key_not_id')).Count -eq 2 -and $m29b.Text -match 'MIGRATE_VERDICT suggested hints=2') ('hits=' + ([regex]::Matches($m29b.Text, 'item=stage_key_not_id')).Count + ' line=' + (($m29b.Text -split "`n") | Where-Object { $_ -match 'MIGRATE_VERDICT' }))
Check 'b29_doctor_and_migrate_hint_answer_different_questions' ($d29b.Code -eq 0 -and $m29b.Code -eq 3) ('doctor_exit=' + $d29b.Code + ' hint_exit=' + $m29b.Code)

# the other shapes: no identity key at all, a status this gate never writes, a
# max_stages no cap can be compared against
$r29c = New-GateRepo 'repo-b29-hint-idless' @{ max_stages = $null; stages = @(@{ title = 'b29 nameless'; status = 'complete' }) }
$m29c = Run (Join-Path $r29c 'docs\relay\relay-ledger.ps1') @('-Action','migrate-hint')
Check 'b29_missing_stage_id_is_reported' ($m29c.Text -match 'MIGRATE_HINT scope=stage index=0 item=stage_id_missing keys=') ('line=' + (($m29c.Text -split "`n") | Where-Object { $_ -match 'stage_id_missing' } | Select-Object -First 1))
Check 'b29_unknown_stage_status_is_reported' ($m29c.Text -match 'MIGRATE_HINT scope=stage index=0 item=stage_status_unknown status=complete') ('line=' + (($m29c.Text -split "`n") | Where-Object { $_ -match 'stage_status_unknown' } | Select-Object -First 1))
Check 'b29_unparsable_max_stages_is_reported' ($m29c.Text -match 'MIGRATE_HINT scope=ledger item=stage_max_unknown value=\(none\) effect=stage_cap_cannot_be_compared') ('line=' + (($m29c.Text -split "`n") | Where-Object { $_ -match 'stage_max_unknown' } | Select-Object -First 1))
Check 'b29_hint_count_matches_lines' (([regex]::Matches($m29c.Text, 'MIGRATE_HINT ')).Count -eq 3 -and $m29c.Text -match 'MIGRATE_VERDICT suggested hints=3') ('hits=' + ([regex]::Matches($m29c.Text, 'MIGRATE_HINT ')).Count + ' line=' + (($m29c.Text -split "`n") | Where-Object { $_ -match 'MIGRATE_VERDICT' }))

# the append-only guard for a stage's own keys read @($oldEntry) - the object, not
# its properties - so it compared '<null>' with '<null>' and could never fire. A
# guard that cannot fail proves nothing, so the check below mutates a copy of the
# gate into editing a key the patch never declared and requires it to be refused.
$r29d = New-GateRepo 'repo-b29-mutant' @{ stages = @(@{ id = 1; title = 'b29 mutant one'; status = 'in_progress' }, @{ id = 2; title = 'b29 mutant two'; status = 'pending' }) }
$g29d = Join-Path $r29d 'docs\relay\mutant-ledger.ps1'
$l29d = Join-Path $r29d 'docs\relay.json'
$src29 = [IO.File]::ReadAllText((Join-Path $tplDir 'relay-ledger.ps1'))
$anchor29 = 'Set-NoteProp -Target $entry -Name ''status'' -Value ''done'''
$inject29 = "`n      " + 'Set-NoteProp -Target $entry -Name ''title'' -Value ''mutant title'''
$mutant29 = $src29.Replace($anchor29, ($anchor29 + $inject29))
Check 'b29_mutation_anchor_is_unique' (([regex]::Matches($src29, [regex]::Escape($anchor29))).Count -eq 1 -and $mutant29 -ne $src29) ('anchor_hits=' + ([regex]::Matches($src29, [regex]::Escape($anchor29))).Count)
[IO.File]::WriteAllText($g29d, $mutant29, (New-Object Text.UTF8Encoding($false)))
$sha29d = (Get-FileHash -Algorithm SHA256 -LiteralPath $l29d).Hash
$p29d = Join-Path (Join-Path $r29d 'docs\relay') 'p29d.json'
[IO.File]::WriteAllText($p29d, '{"stage_done":1}', (New-Object Text.UTF8Encoding($false)))
$c29d = Run $g29d @('-Action','commit','-ExpectSha256',$sha29d,'-Patch',$p29d)
Check 'b29_own_stage_key_guard_has_teeth' ($c29d.Code -eq 3 -and $c29d.Text -match 'rule_edited_own_stage_key stage_id=1 key=title') ('exit=' + $c29d.Code + ' line=' + (($c29d.Text -split "`n") | Where-Object { $_ -match 'rule_edited' } | Select-Object -First 1))
Check 'b29_refused_commit_wrote_nothing' ((Get-FileHash -Algorithm SHA256 -LiteralPath $l29d).Hash -eq $sha29d) ('sha=' + (Get-FileHash -Algorithm SHA256 -LiteralPath $l29d).Hash)
# the control: the same commit against the real gate must still pass, otherwise the
# check above would only prove that every stage_done is refused
$r29e = New-GateRepo 'repo-b29-guard-control' @{ stages = @(@{ id = 1; title = 'b29 control one'; status = 'in_progress' }) }
$l29e = Join-Path $r29e 'docs\relay.json'
$p29e = Join-Path (Join-Path $r29e 'docs\relay') 'p29e.json'
[IO.File]::WriteAllText($p29e, '{"stage_done":1,"stage_fields":{"result":"control done"}}', (New-Object Text.UTF8Encoding($false)))
$c29e = Run (Join-Path $r29e 'docs\relay\relay-ledger.ps1') @('-Action','commit','-ExpectSha256',(Get-FileHash -Algorithm SHA256 -LiteralPath $l29e).Hash,'-Patch',$p29e)
Check 'b29_own_stage_key_guard_allows_declared_keys' ($c29e.Code -eq 0 -and $c29e.Text -match 'LEDGER_COMMITED') ('exit=' + $c29e.Code + ' line=' + (($c29e.Text -split "`n") | Where-Object { $_ -match 'LEDGER_FAIL|LEDGER_COMMITED' } | Select-Object -First 1))

# stage identity used to be cast, not parsed: [int]$null is 0, so stage_done=0
# closed an id-less first stage that no patch had named, and a non-numeric value
# killed the gate with an unhandled cast (exit 1) instead of exit 2.
$r29f = New-GateRepo 'repo-b29-stage-done-zero' @{ status = 'running'; current_stage = 1; max_stages = 2; stages = @(@{ stage = 1; title = 'b29 no id'; status = 'in_progress' }) }
$l29f = Join-Path $r29f 'docs\relay.json'
$g29f = Join-Path $r29f 'docs\relay\relay-ledger.ps1'
$sha29f = (Get-FileHash -Algorithm SHA256 -LiteralPath $l29f).Hash
$p29f = Join-Path (Join-Path $r29f 'docs\relay') 'p29f.json'
[IO.File]::WriteAllText($p29f, '{"stage_done":0}', (New-Object Text.UTF8Encoding($false)))
$c29f = Run $g29f @('-Action','commit','-ExpectSha256',$sha29f,'-Patch',$p29f)
Check 'b29_stage_done_zero_does_not_match_id_less_stage' ($c29f.Code -eq 3 -and $c29f.Text -match 'stage_not_found stage_done=0' -and (Get-FileHash -Algorithm SHA256 -LiteralPath $l29f).Hash -eq $sha29f) ('exit=' + $c29f.Code + ' line=' + (($c29f.Text -split "`n") | Where-Object { $_ -match 'stage_not_found' } | Select-Object -First 1))
$p29g = Join-Path (Join-Path $r29f 'docs\relay') 'p29g.json'
[IO.File]::WriteAllText($p29g, '{"stage_done":"one"}', (New-Object Text.UTF8Encoding($false)))
$c29g = Run $g29f @('-Action','commit','-ExpectSha256',$sha29f,'-Patch',$p29g)
Check 'b29_non_numeric_stage_done_is_refused' ($c29g.Code -eq 2 -and $c29g.Text -match 'stage_done_not_an_integer value=one') ('exit=' + $c29g.Code + ' tail=' + (($c29g.Text -split "`n" | Select-Object -Last 2) -join ' | '))

# --- B30: array counting, session identity and the batch scan -------------------
# Three defects that only show up on a ledger this kit did not write:
# @($null).Count is 1, so a seed without a sessions/notes array claimed one
# entry; a session id that was a prefix of a stored one was called "already
# registered" and the trail lost the id that actually ran the stage; and
# stage_fields could rewrite id, the key stage_done resolves against.
$r30 = New-GateRepo 'repo-b30-array-count' @{ status = 'running'; current_stage = 1; max_stages = 2; stages = @(@{ id = 1; title = 'b30 count'; status = 'in_progress' }) }
$l30 = Join-Path $r30 'docs\relay.json'
$g30 = Join-Path $r30 'docs\relay\relay-ledger.ps1'
$led30 = Get-Content -LiteralPath $l30 -Raw | ConvertFrom-Json
$null = $led30.PSObject.Properties.Remove('sessions')
$null = $led30.PSObject.Properties.Remove('notes')
[IO.File]::WriteAllText($l30, ($led30 | ConvertTo-Json -Depth 6), (New-Object Text.UTF8Encoding($false)))
$st30 = Run $g30 @('-Action','status','-LedgerPath',$l30)
$state30 = (($st30.Text -split "`n") | Where-Object { $_ -match '^LEDGER_STATE ' } | Select-Object -First 1)
Check 'b30_absent_trail_arrays_count_zero' ($st30.Code -eq 0 -and $state30 -match 'sessions=0([ ,]|$)' -and $state30 -match 'notes=0([ ,]|$)') ('exit=' + $st30.Code + ' line=' + $state30)

# a stored id that merely starts with the live one is not the same session
$r30s = New-GateRepo 'repo-b30-session-prefix' @{ status = 'running'; current_stage = 1; max_stages = 2; sessions = @('sess-b30-alpha-long'); stages = @(@{ id = 1; title = 'b30 alpha'; status = 'in_progress'; session_id = 'sess-b30-alpha' }) }
$g30s = Join-Path $r30s 'docs\relay\relay-ledger.ps1'
$l30s = Join-Path $r30s 'docs\relay.json'
$p30s = Join-Path (Join-Path $r30s 'docs\relay') 'p30s.json'
[IO.File]::WriteAllText($p30s, '{"stage_done":1}', (New-Object Text.UTF8Encoding($false)))
$c30s = Run $g30s @('-Action','commit','-ExpectSha256',(Get-FileHash -Algorithm SHA256 -LiteralPath $l30s).Hash,'-Patch',$p30s)
$led30s = Get-Content -LiteralPath $l30s -Raw | ConvertFrom-Json
Check 'b30_session_prefix_is_not_the_same_session' ($c30s.Code -eq 0 -and $c30s.Text -match 'LEDGER_SESSION_REGISTERED session=sess-b30-alpha stage=1' -and @($led30s.sessions).Count -eq 2) ('exit=' + $c30s.Code + ' count=' + @($led30s.sessions).Count + ' line=' + (($c30s.Text -split "`n") | Where-Object { $_ -match 'LEDGER_SESSION_' } | Select-Object -First 1))

# stage_fields is the one patch channel that skips the rule loop, so the identity
# key has to be refused on its own
$sha30 = (Get-FileHash -Algorithm SHA256 -LiteralPath $l30s).Hash
$p30i = Join-Path (Join-Path $r30s 'docs\relay') 'p30i.json'
[IO.File]::WriteAllText($p30i, '{"stage_done":1,"stage_fields":{"id":7}}', (New-Object Text.UTF8Encoding($false)))
$c30i = Run $g30s @('-Action','commit','-ExpectSha256',$sha30,'-Patch',$p30i)
Check 'b30_stage_fields_cannot_rewrite_identity' ($c30i.Code -eq 2 -and $c30i.Text -match 'stage_fields_rewrites_identity stage_id=1 key=id' -and (Get-FileHash -Algorithm SHA256 -LiteralPath $l30s).Hash -eq $sha30) ('exit=' + $c30i.Code + ' line=' + (($c30i.Text -split "`n") | Where-Object { $_ -match 'stage_fields_rewrites_identity' } | Select-Object -First 1))
$p30n = Join-Path (Join-Path $r30s 'docs\relay') 'p30n.json'
[IO.File]::WriteAllText($p30n, '{"append_stage":{"id":"7a","title":"b30 bad id"}}', (New-Object Text.UTF8Encoding($false)))
$c30n = Run $g30s @('-Action','commit','-ExpectSha256',$sha30,'-Patch',$p30n)
Check 'b30_non_numeric_append_stage_id_is_refused' ($c30n.Code -eq 2 -and $c30n.Text -match 'append_stage_id_not_an_integer value=7a') ('exit=' + $c30n.Code + ' tail=' + (($c30n.Text -split "`n" | Select-Object -Last 2) -join ' | '))

# bumping the counter parses current_stage now; [int] on 'two' used to kill the
# gate with a cast error (exit 1) instead of its own exit 2
$r30b = New-GateRepo 'repo-b30-bump-nonnumeric' @{ status = 'running'; current_stage = 'two'; max_stages = 3; stages = @(@{ id = 1; title = 'b30 bump'; status = 'done' }) }
$g30b = Join-Path $r30b 'docs\relay\relay-ledger.ps1'
$l30b = Join-Path $r30b 'docs\relay.json'
$p30b = Join-Path (Join-Path $r30b 'docs\relay') 'p30b.json'
[IO.File]::WriteAllText($p30b, '{"bump_current_stage":true}', (New-Object Text.UTF8Encoding($false)))
$c30b = Run $g30b @('-Action','commit','-ExpectSha256',(Get-FileHash -Algorithm SHA256 -LiteralPath $l30b).Hash,'-Patch',$p30b)
Check 'b30_bump_needs_a_numeric_current_stage' ($c30b.Code -eq 2 -and $c30b.Text -match 'current_stage_not_an_integer value=two') ('exit=' + $c30b.Code + ' tail=' + (($c30b.Text -split "`n" | Select-Object -Last 2) -join ' | '))

# the sweep: one clean ledger, one written before ids, one path that is not there
$r30x = New-Repo 'repo-b30-batch'
New-Item -ItemType Directory -Path (Join-Path $r30x 'docs\relay') -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $tplDir 'relay-ledger.ps1') -Destination (Join-Path $r30x 'docs\relay\relay-ledger.ps1') -Force
$g30x = Join-Path $r30x 'docs\relay\relay-ledger.ps1'
function Write30Ledger([string]$Path, [hashtable]$Over) {
  $seed = [ordered]@{ goal = 'b30 sweep'; plan_doc = 'docs\plan.md'; workspace_dir = $r30x; status = 'running'; auto_relay = $true; current_stage = 1; max_stages = 2; next_session_id = $null; stages = @(@{ id = 1; status = 'in_progress' }); sessions = @(); notes = @(); blocked_on = @() }
  foreach ($k in $Over.Keys) { $seed[$k] = $Over[$k] }
  [IO.File]::WriteAllText($Path, ($seed | ConvertTo-Json -Depth 6), (New-Object Text.UTF8Encoding($false)))
}
$b30clean = Join-Path $r30x 'docs\relay\b30-clean.json'
$b30stage = Join-Path $r30x 'docs\relay\b30-stagekey.json'
$b30gone = Join-Path $r30x 'docs\relay\b30-absent.json'
Write30Ledger $b30clean @{}
Write30Ledger $b30stage @{ current_stage = 2; stages = @(@{ stage = 1; title = 'b30 s1'; status = 'done' }, @{ stage = 2; title = 'b30 s2'; status = 'pending' }) }
$m30x = Run $g30x @('-Action','migrate-hint','-LedgerPaths', ($b30clean + ',' + $b30stage + ',' + $b30gone))
Check 'b30_batch_scan_judges_every_ledger' ($m30x.Code -eq 3 -and $m30x.Text -match 'MIGRATE_SCAN_VERDICT ledgers=3 hints=2 unreadable=1') ('exit=' + $m30x.Code + ' line=' + (($m30x.Text -split "`n") | Where-Object { $_ -match 'MIGRATE_SCAN_VERDICT' }))
Check 'b30_batch_scan_keeps_going_after_a_missing_ledger' (([regex]::Matches($m30x.Text, 'MIGRATE_SCAN path=')).Count -eq 3 -and $m30x.Text -match 'readable=false reason=' -and ([regex]::Matches($m30x.Text, 'MIGRATE_HINT path=')).Count -eq 2) ('scans=' + ([regex]::Matches($m30x.Text, 'MIGRATE_SCAN path=')).Count + ' hints=' + ([regex]::Matches($m30x.Text, 'MIGRATE_HINT path=')).Count)
$m30y = Run $g30x @('-Action','migrate-hint','-LedgerPaths', $b30clean)
Check 'b30_clean_batch_exits_zero' ($m30y.Code -eq 0 -and $m30y.Text -match 'MIGRATE_SCAN_VERDICT ledgers=1 hints=0 unreadable=0') ('exit=' + $m30y.Code + ' line=' + (($m30y.Text -split "`n") | Where-Object { $_ -match 'MIGRATE_SCAN_VERDICT' }))

# --- B31: the hand-over gate has to actually reach the prompt --------------------
# Two defects that no case could see, because the gate MECHANISM worked (case b25
# drives relay-lock.ps1 directly) and nobody had checked whether the PROMPT told the
# agent to use it:
#   1. $spawnGateRule was assigned nowhere. The if-block held a bare string literal,
#      so the hand-over gate never reached the prompt and the template kept an empty
#      "- " bullet exactly where the rule belonged.
#   2. the openclaw branch told the agent to hand the lock over with "-Action adopt"
#      in one sentence and "-Action verify -Nonce" in the next, and never ran
#      prespawn: the nonce it asked for could not exist, so that chain could not
#      hand over at all.
$r31 = New-Repo 'repo-b31-gate'
Set-Content -LiteralPath (Join-Path $r31 'docs\plan-b31.md') -Value '# plan b31' -Encoding utf8
$i31 = Run $installer @('-RepoRoot', $r31, '-Target', 'b31', '-PlanDoc', 'docs\plan-b31.md', '-MaxStages', '2')
Check 'b31_install_exit_zero' ($i31.Code -eq 0) ('exit=' + $i31.Code)
$l31 = Join-Path $r31 'docs\relay\start-relay.ps1'
function Get31Prompt([string]$Text) {
  $m = [regex]::Match($Text, '(?s)DRYRUN prompt_preview_begin\r?\n(.*?)\r?\nDRYRUN prompt_preview_end')
  if ($m.Success) { return $m.Groups[1].Value }
  return ''
}
$d31 = Run $l31 @('-Target', 'b31', '-MaxStages', '2', '-DryRun')
$p31 = Get31Prompt $d31.Text
Check 'b31_prompt_carries_the_hand_over_gate' ($p31 -match 'Hand-over gate \(mechanical, not advisory\)') ('exit=' + $d31.Code + ' chars=' + $p31.Length)
Check 'b31_prompt_has_no_empty_rule_bullet' (-not ($p31 -match '(?m)^-\s*$')) ('chars=' + $p31.Length)
$o31 = Run $l31 @('-Target', 'b31', '-MaxStages', '2', '-Runtime', 'openclaw', '-DryRun')
$q31 = Get31Prompt $o31.Text
Check 'b31_openclaw_prompt_uses_the_permit_flow' ($q31 -match '-Action verify -SessionId <the new session id> -Nonce <the nonce from SPAWN_PERMIT>') ('exit=' + $o31.Code + ' chars=' + $q31.Length)
Check 'b31_openclaw_prompt_never_adopts_the_lock' (-not ($q31 -match '-Action adopt')) ('exit=' + $o31.Code)
# B31, third defect: the descriptor the installer stamped used to override an
# explicit -Runtime, so the link mode silently stayed on the installed runtime.
# The parameter must win, and the disagreement has to be loud.
Check 'b31_explicit_runtime_beats_the_descriptor' ($q31 -match '-Action verify -SessionId <the new session id> -Nonce <the nonce from SPAWN_PERMIT>' -and $q31 -match 'sessions_spawn tool') ('exit=' + $o31.Code)
Check 'b31_runtime_mismatch_is_loud' ($o31.Text -match 'runtime_differs_from_install') ('exit=' + $o31.Code)
$r31o = New-Repo 'repo-b31-openclaw'
Set-Content -LiteralPath (Join-Path $r31o 'docs\plan-b31o.md') -Value '# plan b31o' -Encoding utf8
$i31o = Run $installer @('-RepoRoot', $r31o, '-Target', 'b31o', '-PlanDoc', 'docs\plan-b31o.md', '-MaxStages', '2', '-Runtime', 'openclaw')
Check 'b31_openclaw_install_exit_zero' ($i31o.Code -eq 0) ('exit=' + $i31o.Code)
$l31o = Join-Path $r31o 'docs\relay\start-relay.ps1'
$o31c = Run $l31o @('-Target', 'b31o', '-MaxStages', '2', '-DryRun')
$q31c = Get31Prompt $o31c.Text
Check 'b31_openclaw_install_yields_the_permit_flow' ($q31c -match '-Action verify -SessionId <the new session id> -Nonce <the nonce from SPAWN_PERMIT>' -and -not ($q31c -match '-Action adopt')) ('exit=' + $o31c.Code + ' chars=' + $q31c.Length)
$src31 = [IO.File]::ReadAllText((Join-Path $tplDir 'start-relay.ps1'))
Check 'b31_spawn_gate_rule_is_assigned' ($src31 -match '\$spawnGateRule\s*=') ('hits=' + ([regex]::Matches($src31, '\$spawnGateRule\s*=')).Count)

# --- B31: the ledger gate on a ledger this kit did not write --------------------
# Ten defects that only bite when the ledger carries no array at all, when a
# payload is an object, or when a number is not a number. Every one of them ended
# in a commit that refused to close its own session trail (F1), wrote a null into
# a gate-owned array (F2), flattened an object into a string (F5), let a stage be
# pre-marked done (F7), wrote a field named Length (F8), accepted the word true
# (F10), ignored -LedgerPaths (F11), wedged forever on a clock skewed lock (F4),
# or died with an exit code the contract does not define (F3).
function New-GateRepoRaw([string]$Name, [string]$Body) {
  $d = New-Repo $Name
  New-Item -ItemType Directory -Path (Join-Path $d 'docs\relay') -Force | Out-Null
  Copy-Item -LiteralPath (Join-Path $tplDir 'relay-ledger.ps1') -Destination (Join-Path $d 'docs\relay\relay-ledger.ps1') -Force
  [IO.File]::WriteAllText((Join-Path $d 'docs\relay.json'), $Body, (New-Object Text.UTF8Encoding($false)))
  return $d
}
function Patch31([string]$Dir, [string]$Name, [string]$Body) {
  $p = Join-Path (Join-Path $Dir 'docs\relay') $Name
  [IO.File]::WriteAllText($p, $Body, (New-Object Text.UTF8Encoding($false)))
  return $p
}
$json31a = '{"status":"running","current_stage":1,"max_stages":2,"next_session_id":"sess-b31-trail","stages":[{"id":1,"title":"b31 trail","status":"in_progress"}]}'
$json31b = '{"status":"running","current_stage":1,"max_stages":2,"stages":[{"id":1,"title":"b31 plain","status":"in_progress"}]}'

# F1: a ledger with no sessions array must still accept the gate's own trail
$r31a = New-GateRepoRaw 'repo-b31-ledger-trail' $json31a
$g31a = Join-Path $r31a 'docs\relay\relay-ledger.ps1'
$l31a = Join-Path $r31a 'docs\relay.json'
$p31a = Patch31 $r31a 'p31a.json' '{"stage_done":1}'
$c31a = Run $g31a @('-Action','commit','-ExpectSha256',(Get-FileHash -Algorithm SHA256 -LiteralPath $l31a).Hash,'-Patch',$p31a)
Check 'b31_ledger_missing_sessions_array_still_accepts_stage_done' ($c31a.Code -eq 0 -and $c31a.Text -match 'LEDGER_COMMITED') ('exit=' + $c31a.Code + ' line=' + (($c31a.Text -split "`n") | Where-Object { $_ -match 'LEDGER_FAIL|LEDGER_COMMITED' } | Select-Object -First 1))
$led31a = Get-Content -LiteralPath $l31a -Raw | ConvertFrom-Json
Check 'b31_ledger_missing_sessions_array_registers_the_trail' (@($led31a.sessions).Count -eq 1 -and [string]@($led31a.sessions)[0] -eq 'sess-b31-trail') ('count=' + @($led31a.sessions).Count)

# F2: appending to an array the seed never carried must not write a null
$r31b = New-GateRepoRaw 'repo-b31-ledger-null' $json31b
$g31b = Join-Path $r31b 'docs\relay\relay-ledger.ps1'
$l31b = Join-Path $r31b 'docs\relay.json'
$p31b = Patch31 $r31b 'p31b.json' '{"sessions_append":["sess-b31-x"]}'
$c31b = Run $g31b @('-Action','commit','-ExpectSha256',(Get-FileHash -Algorithm SHA256 -LiteralPath $l31b).Hash,'-Patch',$p31b)
$led31b = Get-Content -LiteralPath $l31b -Raw | ConvertFrom-Json
$sess31b = @($led31b.sessions)
$nulls31b = @($sess31b | Where-Object { $null -eq $_ }).Count
Check 'b31_ledger_append_to_missing_array_writes_no_null' ($c31b.Code -eq 0 -and $nulls31b -eq 0 -and $sess31b.Count -eq 1 -and [string]$sess31b[0] -eq 'sess-b31-x') ('exit=' + $c31b.Code + ' sessions=' + ($sess31b | ConvertTo-Json -Compress))

# F9: the counts on the commit line must be real counts, not the ghost of a null
$commitLine31b = (($c31b.Text -split "`n") | Where-Object { $_ -match 'LEDGER_COMMITED' } | Select-Object -First 1)
Check 'b31_ledger_commit_counts_match_status_action_counts' ($commitLine31b -match 'sessions=0->1' -and $commitLine31b -match 'notes=0->0') ('line=' + $commitLine31b)

# B31: a non numeric TTL or stage cap must be refused with a verdict line and
# exit 2. A typed integer parameter would instead be refused by the binder,
# which ends the run with exit 1 and a stack trace.
$r31t = New-LauncherRepo 'repo-b31-ttl-invalid'
$k31t = Join-Path $r31t 'docs\relay\start-relay.ps1'
$c31t = Run $k31t @('-Target', 'b31 ttl batch', '-TtlSeconds', 'abc', '-DryRun')
Check 'b31_launcher_ttl_invalid_exit_two' ($c31t.Code -eq 2 -and $c31t.Text -match 'FAIL reason=ttl_invalid') ('exit=' + $c31t.Code + ' text=' + $c31t.Text)
$r31m = New-LauncherRepo 'repo-b31-maxstages-invalid'
$k31m = Join-Path $r31m 'docs\relay\start-relay.ps1'
$c31m = Run $k31m @('-Target', 'b31 cap batch', '-MaxStages', 'abc', '-DryRun')
Check 'b31_launcher_max_stages_invalid_exit_two' ($c31m.Code -eq 2 -and $c31m.Text -match 'FAIL reason=max_stages_invalid') ('exit=' + $c31m.Code + ' text=' + $c31m.Text)
$r31i = New-Repo 'repo-b31-install-ttl-invalid'
$c31i = Run $installer @('-RepoRoot', $r31i, '-Target', 'b31 install ttl batch', '-TtlSeconds', 'abc')
Check 'b31_installer_ttl_invalid_exit_two' ($c31i.Code -eq 2 -and $c31i.Text -match 'FAIL reason=ttl_invalid') ('exit=' + $c31i.Code + ' text=' + $c31i.Text)
$r31j = New-Repo 'repo-b31-install-maxstages-invalid'
$c31j = Run $installer @('-RepoRoot', $r31j, '-Target', 'b31 install cap batch', '-MaxStages', 'abc')
Check 'b31_installer_max_stages_invalid_exit_two' ($c31j.Code -eq 2 -and $c31j.Text -match 'FAIL reason=max_stages_invalid') ('exit=' + $c31j.Code + ' text=' + $c31j.Text)

# F5: an object payload must stay a JSON object
$r31c = New-GateRepoRaw 'repo-b31-ledger-object' $json31b
$g31c = Join-Path $r31c 'docs\relay\relay-ledger.ps1'
$l31c = Join-Path $r31c 'docs\relay.json'
$p31c = Patch31 $r31c 'p31c.json' '{"notes_append":[{"text":"hello","ts":"2026-01-01"}]}'
$c31c = Run $g31c @('-Action','commit','-ExpectSha256',(Get-FileHash -Algorithm SHA256 -LiteralPath $l31c).Hash,'-Patch',$p31c)
$led31c = Get-Content -LiteralPath $l31c -Raw | ConvertFrom-Json
$notes31c = @($led31c.notes)
Check 'b31_ledger_append_object_payload_stays_json_object' ($c31c.Code -eq 0 -and $notes31c.Count -eq 1 -and $notes31c[0] -is [System.Management.Automation.PSCustomObject] -and [string]$notes31c[0].text -eq 'hello') ('exit=' + $c31c.Code + ' notes=' + ($notes31c | ConvertTo-Json -Compress -Depth 5))

# F7: a stage may not arrive already marked done
$r31d = New-GateRepoRaw 'repo-b31-ledger-premark' $json31b
$g31d = Join-Path $r31d 'docs\relay\relay-ledger.ps1'
$l31d = Join-Path $r31d 'docs\relay.json'
$sha31d = (Get-FileHash -Algorithm SHA256 -LiteralPath $l31d).Hash
$p31d = Patch31 $r31d 'p31d.json' '{"append_stage":{"id":2,"title":"b31 two","status":"done"}}'
$c31d = Run $g31d @('-Action','commit','-ExpectSha256',$sha31d,'-Patch',$p31d)
Check 'b31_ledger_append_stage_cannot_pre_mark_done' ($c31d.Code -eq 2 -and $c31d.Text -match 'append_stage_status_not_allowed' -and (Get-FileHash -Algorithm SHA256 -LiteralPath $l31d).Hash -eq $sha31d) ('exit=' + $c31d.Code + ' line=' + (($c31d.Text -split "`n") | Where-Object { $_ -match 'append_stage_status_not_allowed' } | Select-Object -First 1))

# F8: stage_fields must be an object, not a string
$r31e = New-GateRepoRaw 'repo-b31-ledger-fields' $json31b
$g31e = Join-Path $r31e 'docs\relay\relay-ledger.ps1'
$l31e = Join-Path $r31e 'docs\relay.json'
$sha31e = (Get-FileHash -Algorithm SHA256 -LiteralPath $l31e).Hash
$p31e = Patch31 $r31e 'p31e.json' '{"stage_done":1,"stage_fields":"hello"}'
$c31e = Run $g31e @('-Action','commit','-ExpectSha256',$sha31e,'-Patch',$p31e)
Check 'b31_ledger_stage_fields_non_object_is_rejected' ($c31e.Code -eq 2 -and $c31e.Text -match 'stage_fields_not_an_object' -and (Get-FileHash -Algorithm SHA256 -LiteralPath $l31e).Hash -eq $sha31e) ('exit=' + $c31e.Code + ' line=' + (($c31e.Text -split "`n") | Where-Object { $_ -match 'stage_fields_not_an_object' } | Select-Object -First 1))

# F10: bump_current_stage must be a real boolean
$r31f = New-GateRepoRaw 'repo-b31-ledger-bump' $json31b
$g31f = Join-Path $r31f 'docs\relay\relay-ledger.ps1'
$l31f = Join-Path $r31f 'docs\relay.json'
$sha31f = (Get-FileHash -Algorithm SHA256 -LiteralPath $l31f).Hash
$p31f = Patch31 $r31f 'p31f.json' '{"bump_current_stage":"true"}'
$c31f = Run $g31f @('-Action','commit','-ExpectSha256',$sha31f,'-Patch',$p31f)
Check 'b31_ledger_bump_current_stage_requires_real_boolean' ($c31f.Code -eq 2 -and $c31f.Text -match 'bump_current_stage_not_a_boolean' -and (Get-FileHash -Algorithm SHA256 -LiteralPath $l31f).Hash -eq $sha31f) ('exit=' + $c31f.Code + ' line=' + (($c31f.Text -split "`n") | Where-Object { $_ -match 'bump_current_stage_not_a_boolean' } | Select-Object -First 1))

# F11: -LedgerPaths outside migrate-hint is refused instead of ignored
$r31g = New-GateRepoRaw 'repo-b31-ledger-paths' $json31b
$g31g = Join-Path $r31g 'docs\relay\relay-ledger.ps1'
$l31g = Join-Path $r31g 'docs\relay.json'
$c31g = Run $g31g @('-Action','status','-LedgerPaths',($l31g + ',' + $l31g))
Check 'b31_ledger_paths_is_refused_for_non_batch_actions' ($c31g.Code -eq 2 -and $c31g.Text -match 'ledger_paths_not_supported_for_action') ('exit=' + $c31g.Code + ' line=' + (($c31g.Text -split "`n") | Where-Object { $_ -match 'ledger_paths_not_supported_for_action' } | Select-Object -First 1))

# F4: a lock whose own timestamp sits in the future is taken over, not waited out
$r31h = New-GateRepoRaw 'repo-b31-ledger-futurelock' $json31b
$g31h = Join-Path $r31h 'docs\relay\relay-ledger.ps1'
$l31h = Join-Path $r31h 'docs\relay.json'
$lock31h = Join-Path $r31h 'docs\relay\.ledger.lock'
$future31h = ([DateTimeOffset]::Now.AddHours(1)).ToString('o')
[IO.File]::WriteAllText($lock31h, ('pid=1 host=b31 taken_at=' + $future31h), (New-Object Text.UTF8Encoding($false)))
(Get-Item -LiteralPath $lock31h).LastWriteTime = (Get-Date).AddHours(1)
$p31h = Patch31 $r31h 'p31h.json' '{"sessions_append":["sess-b31-x"]}'
$c31h = Run $g31h @('-Action','commit','-TimeoutMs','2000','-LockStaleSeconds','30','-ExpectSha256',(Get-FileHash -Algorithm SHA256 -LiteralPath $l31h).Hash,'-Patch',$p31h)
Check 'b31_ledger_lock_with_future_timestamp_is_taken_over' ($c31h.Code -eq 0 -and $c31h.Text -match 'LEDGER_LOCK_TAKEOVER') ('exit=' + $c31h.Code + ' line=' + (($c31h.Text -split "`n") | Where-Object { $_ -match 'LEDGER_LOCK_TAKEOVER' } | Select-Object -First 1))

# F3: an unreadable ledger is a refusal with a contract exit code, not a bare exit 1
$r31i = New-GateRepoRaw 'repo-b31-ledger-unreadable' $json31b
$g31i = Join-Path $r31i 'docs\relay\relay-ledger.ps1'
$dir31i = Join-Path $r31i 'docs\relay\adir'
New-Item -ItemType Directory -Path $dir31i -Force | Out-Null
$c31i = Run $g31i @('-Action','status','-LedgerPath',$dir31i)
Check 'b31_ledger_unreadable_returns_gate_exit_code_not_one' ($c31i.Code -eq 3 -and $c31i.Text -match 'ledger_unreadable') ('exit=' + $c31i.Code + ' line=' + (($c31i.Text -split "`n") | Where-Object { $_ -match 'LEDGER_FAIL' } | Select-Object -First 1))

# --- B31: the protocol must document the gate the launcher actually uses -------
# The launcher told the link to run prespawn and to hand the lock over with
# verify -Nonce, but the protocol shipped with the kit never mentioned either:
# a link that reads the protocol had no way to know the permit flow exists.
# --- B31: the lock side of the hand-over gate ---------------------------------
# B31 fixed four defects on the lock: the ttl parameter had no consumer at all,
# a broken heartbeat crashed the script with a stack, a verify that carried no
# nonce was accepted anyway, and an adopt without any credential could take the
# lock away from a running chain.
$b31lLock = Join-Path $script:root 'b31l\.relay.lock'
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $b31lLock) | Out-Null
$b31lTpl = Join-Path (Split-Path -Parent $PSScriptRoot) 'tool\templates\relay-lock.ps1'
function B31LockRun([string[]]$b31lArgs) {
  $b31lOut = & pwsh -NoProfile -ExecutionPolicy Bypass -File $b31lTpl @b31lArgs 2>&1 | Out-String
  [pscustomobject]@{ Code = $LASTEXITCODE; Text = $b31lOut }
}
$b31la = B31LockRun @('-Action','acquire','-SessionId','b31l-a','-TtlSeconds','600','-LockPath',$b31lLock)
Check 'b31l_lock_acquired' ($b31la.Code -eq 0 -and $b31la.Text -match 'LOCK_ACQUIRED holder=b31l-a') ('exit=' + $b31la.Code + ' text=' + $b31la.Text)
Check 'b31l_lock_reports_the_ttl_source' ($b31la.Text -match 'ttl_s=600 ttl_source=parameter') ('text=' + $b31la.Text)
$b31lp = B31LockRun @('-Action','prespawn','-Stage','2','-LockPath',$b31lLock)
$b31lnonce = ''
if ($b31lp.Text -match 'SPAWN_PERMIT ok nonce=(\w+)') { $b31lnonce = $matches[1] }
Check 'b31l_prespawn_issues_a_permit' ($b31lp.Code -eq 0 -and $b31lnonce.Length -eq 16) ('exit=' + $b31lp.Code + ' text=' + $b31lp.Text)
$b31lv0 = B31LockRun @('-Action','verify','-SessionId','b31l-b','-LockPath',$b31lLock)
Check 'b31l_verify_without_a_nonce_is_refused' ($b31lv0.Code -eq 6 -and $b31lv0.Text -match 'PERMIT_INVALID reason=nonce_required') ('exit=' + $b31lv0.Code + ' text=' + $b31lv0.Text)
$b31lv1 = B31LockRun @('-Action','verify','-SessionId','b31l-b','-Nonce',$b31lnonce,'-LockPath',$b31lLock)
Check 'b31l_verify_with_a_nonce_is_accepted' ($b31lv1.Code -eq 0 -and $b31lv1.Text -match 'SPAWN_VERIFIED ok nonce=') ('exit=' + $b31lv1.Code + ' text=' + $b31lv1.Text)
# an adopt without a credential must not be able to take the lock away
$b31lLock2 = Join-Path $script:root 'b31l2\.relay.lock'
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $b31lLock2) | Out-Null
$b31lb = B31LockRun @('-Action','acquire','-SessionId','b31l-c','-LockPath',$b31lLock2)
Check 'b31l_second_lock_acquired' ($b31lb.Code -eq 0) ('exit=' + $b31lb.Code)
$b31lc = B31LockRun @('-Action','adopt','-SessionId','b31l-d','-LockPath',$b31lLock2)
Check 'b31l_adopt_without_a_permit_is_refused' ($b31lc.Code -eq 3 -and $b31lc.Text -match 'LOCK_REFUSED reason=permit_required') ('exit=' + $b31lc.Code + ' text=' + $b31lc.Text)
$b31ld = B31LockRun @('-Action','prespawn','-Stage','2','-LockPath',$b31lLock2)
$b31lnonce2 = ''
if ($b31ld.Text -match 'SPAWN_PERMIT ok nonce=(\w+)') { $b31lnonce2 = $matches[1] }
$b31le = B31LockRun @('-Action','adopt','-SessionId','b31l-d','-LockPath',$b31lLock2)
Check 'b31l_adopt_without_a_nonce_is_refused' ($b31le.Code -eq 3 -and $b31le.Text -match 'LOCK_REFUSED reason=nonce_required') ('exit=' + $b31le.Code + ' text=' + $b31le.Text)
$b31lf = B31LockRun @('-Action','adopt','-SessionId','b31l-d','-Nonce',$b31lnonce2,'-LockPath',$b31lLock2)
Check 'b31l_adopt_with_a_nonce_is_accepted' ($b31lf.Code -eq 0 -and $b31lf.Text -match 'LOCK_ADOPTED holder=b31l-d') ('exit=' + $b31lf.Code + ' text=' + $b31lf.Text)
# a lock file that cannot be read is taken over instead of crashing the script
$b31lLock3 = Join-Path $script:root 'b31l3\.relay.lock'
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $b31lLock3) | Out-Null
[IO.File]::WriteAllText($b31lLock3, 'not a json lock')
$b31lg = B31LockRun @('-Action','acquire','-SessionId','b31l-e','-LockPath',$b31lLock3)
Check 'b31l_broken_lock_is_taken_over' ($b31lg.Code -eq 0 -and $b31lg.Text -match 'LOCK_TAKEOVER .*reason=unreadable_lock') ('exit=' + $b31lg.Code + ' text=' + $b31lg.Text)
Check 'b31l_broken_lock_leaves_no_stack' ($b31lg.Text -notmatch 'At line:\d+ char:\d+' -and $b31lg.Text -notmatch 'FullyQualifiedErrorId') ('text=' + $b31lg.Text)
[IO.File]::WriteAllText($b31lLock3, 'not a json lock')
$b31lh = B31LockRun @('-Action','status','-LockPath',$b31lLock3)
Check 'b31l_status_of_a_broken_lock' ($b31lh.Code -eq 0 -and $b31lh.Text -match 'LOCK_STATE state=UNREADABLE') ('exit=' + $b31lh.Code + ' text=' + $b31lh.Text)
# the ttl of a lock comes from the runtime descriptor when nobody passes one
$b31lDir = Join-Path $script:root 'b31l4'
New-Item -ItemType Directory -Force -Path $b31lDir | Out-Null
Copy-Item $b31lTpl (Join-Path $b31lDir 'relay-lock.ps1') -Force
[IO.File]::WriteAllText((Join-Path $b31lDir 'relay-runtime.json'), '{"runtime":"mcode","lock_ttl_seconds":60}')
$b31lOut = & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $b31lDir 'relay-lock.ps1') -Action acquire -SessionId 'b31l-f' -LockPath (Join-Path $b31lDir '.relay.lock') 2>&1 | Out-String
$b31lCode = $LASTEXITCODE
Check 'b31l_ttl_comes_from_the_descriptor' ($b31lCode -eq 0 -and $b31lOut -match 'ttl_s=60 ttl_source=descriptor') ('exit=' + $b31lCode + ' text=' + $b31lOut)
# a new chain starts with a clean permit
$b31lDir2 = Join-Path $script:root 'b31l5'
New-Item -ItemType Directory -Force -Path $b31lDir2 | Out-Null
[IO.File]::WriteAllText((Join-Path $b31lDir2 '.spawn-permit.json'), '{"nonce":"abcdef0123456789","consumed_at":""}')
$b31lOut2 = & pwsh -NoProfile -ExecutionPolicy Bypass -File $b31lTpl -Action acquire -SessionId 'b31l-g' -LockPath (Join-Path $b31lDir2 '.relay.lock') 2>&1 | Out-String
$b31lCode2 = $LASTEXITCODE
Check 'b31l_new_chain_clears_a_leftover_permit' ($b31lCode2 -eq 0 -and $b31lOut2 -match 'LOCK_PERMIT_CLEARED') ('exit=' + $b31lCode2 + ' text=' + $b31lOut2)
# the protocol has to name every new refusal reason
$b31lProto = [IO.File]::ReadAllText((Join-Path $tplDir 'AGENT-RELAY.md'))
$b31lTokens = @('nonce_required','permit_required','LOCK_DIR_MISSING','LOCK_REFUSED','LOCK_PERMIT_CLEARED','unreadable_lock','ttl_source')
$b31lMissing = @($b31lTokens | Where-Object { $b31lProto -notmatch [regex]::Escape($_) })
Check 'b31l_protocol_documents_the_new_refusals' ($b31lMissing.Count -eq 0) ('missing=' + ($b31lMissing -join ','))
$proto31 = [IO.File]::ReadAllText((Join-Path $tplDir 'AGENT-RELAY.md'))
Check 'b31_protocol_documents_the_permit_flow' ($proto31 -match 'SPAWN_PERMIT' -and $proto31 -match '-Action prespawn' -and $proto31 -match '-Action verify' -and $proto31 -match '-Nonce') ('chars=' + $proto31.Length)
$lockActions31 = @('acquire','renew','release','status','adopt','prespawn','verify','stop-mark','stop-clear','job-register','job-clear','gate-status')
$missingActions31 = @($lockActions31 | Where-Object { $proto31 -notmatch [regex]::Escape($_) })
Check 'b31_protocol_lists_every_lock_action' ($missingActions31.Count -eq 0) ('missing=' + ($missingActions31 -join ','))
$ledgerTokens31 = @('stage_fields_not_an_object','append_stage_status_not_allowed','bump_current_stage_not_a_boolean','ledger_paths_not_supported_for_action','ledger_unreadable','writeback_failed')
$gateSrc31 = [IO.File]::ReadAllText((Join-Path $tplDir 'relay-ledger.ps1'))
$missingGate31 = @($ledgerTokens31 | Where-Object { $gateSrc31 -notmatch [regex]::Escape($_) })
$missingDoc31 = @($ledgerTokens31 | Where-Object { $proto31 -notmatch [regex]::Escape($_) })
Check 'b31_ledger_refusal_tokens_are_documented' ($missingGate31.Count -eq 0 -and $missingDoc31.Count -eq 0) ('gate_missing=' + ($missingGate31 -join ',') + ' doc_missing=' + ($missingDoc31 -join ','))

# --- B32: a legacy ledger keyed its stages by stage, not by id ----------------
# R6 was decided by the user: the tool learns the old shape instead of rewriting
# the file. A stage_done commit closes a legacy stage through its legacy stage
# key, the key itself is never renamed, and when both shapes carry the same
# number the stage that has an id wins - guessing there would close the wrong
# stage, which is the trap the last case pins down with a mutant.
$legacy32 = @"
{
  "status": "running",
  "current_stage": 1,
  "max_stages": 2,
  "next_session_id": "sess-b32-legacy",
  "stages": [
    { "stage": 1, "title": "b32 legacy one", "status": "in_progress" },
    { "stage": 2, "title": "b32 legacy two", "status": "pending" }
  ],
  "sessions": [],
  "notes": []
}
"@
$r32a = New-GateRepoRaw 'repo-b32-legacy' $legacy32
$g32a = Join-Path $r32a 'docs\relay\relay-ledger.ps1'
$l32a = Join-Path $r32a 'docs\relay.json'
$p32a = Patch31 $r32a 'p32a.json' '{"stage_done":1}'
$c32a = Run $g32a @('-Action','commit','-ExpectSha256',(Get-FileHash -Algorithm SHA256 -LiteralPath $l32a).Hash,'-Patch',$p32a)
$led32a = Get-Content -LiteralPath $l32a -Raw | ConvertFrom-Json
$s32a = @($led32a.stages)[0]
$keys32a = @($s32a.PSObject.Properties.Name)
Check 'b32_legacy_stage_can_be_closed' ($c32a.Code -eq 0 -and $c32a.Text -match 'LEDGER_COMMITED' -and ([string]$s32a.status) -eq 'done') ('exit=' + $c32a.Code + ' status=' + [string]$s32a.status)
Check 'b32_legacy_stage_keeps_its_shape' (($keys32a -contains 'stage') -and -not ($keys32a -contains 'id') -and ([string]$s32a.title) -eq 'b32 legacy one') ('keys=' + ($keys32a -join ','))
Check 'b32_legacy_trail_records_the_stage_number' ($c32a.Text -match 'LEDGER_SESSION_REGISTERED session=sess-b32-legacy stage=1 ') ('line=' + (($c32a.Text -split "`n") | Where-Object { $_ -match 'LEDGER_SESSION_REGISTERED' } | Select-Object -First 1))
$s32b = @($led32a.stages)[1]
Check 'b32_other_legacy_stage_is_untouched' (([string]$s32b.status) -eq 'pending' -and ([string]$s32b.title) -eq 'b32 legacy two') ('status=' + [string]$s32b.status)

$amb32 = @"
{
  "status": "running",
  "current_stage": 0,
  "max_stages": 2,
  "next_session_id": "sess-b32-amb",
  "stages": [
    { "stage": 1, "title": "b32 legacy one", "status": "in_progress" },
    { "id": 1, "title": "b32 modern one", "status": "in_progress" }
  ],
  "sessions": [],
  "notes": []
}
"@
$r32b = New-GateRepoRaw 'repo-b32-ambiguous' $amb32
$g32b = Join-Path $r32b 'docs\relay\relay-ledger.ps1'
$l32b = Join-Path $r32b 'docs\relay.json'
$p32b = Patch31 $r32b 'p32b.json' '{"stage_done":1}'
$c32b = Run $g32b @('-Action','commit','-ExpectSha256',(Get-FileHash -Algorithm SHA256 -LiteralPath $l32b).Hash,'-Patch',$p32b)
$led32b = Get-Content -LiteralPath $l32b -Raw | ConvertFrom-Json
$leg32b = @($led32b.stages)[0]
$mod32b = @($led32b.stages)[1]
Check 'b32_modern_id_wins_over_legacy_key' ($c32b.Code -eq 0 -and ([string]$mod32b.status) -eq 'done' -and ([string]$leg32b.status) -eq 'in_progress') ('exit=' + $c32b.Code + ' legacy=' + [string]$leg32b.status + ' modern=' + [string]$mod32b.status)

$r32c = New-GateRepoRaw 'repo-b32-unknown' $legacy32
$g32c = Join-Path $r32c 'docs\relay\relay-ledger.ps1'
$l32c = Join-Path $r32c 'docs\relay.json'
$p32c = Patch31 $r32c 'p32c.json' '{"stage_done":9}'
$sha32c = (Get-FileHash -Algorithm SHA256 -LiteralPath $l32c).Hash
$c32c = Run $g32c @('-Action','commit','-ExpectSha256',$sha32c,'-Patch',$p32c)
Check 'b32_unknown_stage_is_still_refused' ($c32c.Code -eq 3 -and $c32c.Text -match 'stage_not_found stage_done=9' -and (Get-FileHash -Algorithm SHA256 -LiteralPath $l32c).Hash -eq $sha32c) ('exit=' + $c32c.Code)

# The mutant resolves a legacy key before an id, so the legacy stage wins the
# number 1 and the modern one stays open. If the check above still passed with
# this gate in place, it would prove nothing.
$r32d = New-GateRepoRaw 'repo-b32-mutant' $amb32
$g32d = Join-Path $r32d 'docs\relay\relay-ledger.ps1'
$mutant32 = [IO.File]::ReadAllText($g32d)
$mutOld32 = @"
      if (-not [int]::TryParse(([string]`$stageRef[`$i].id).Trim(), [ref]`$stageIdNum)) { continue }
"@
$mutNew32 = @"
      `$idText32 = ([string]`$stageRef[`$i].id).Trim()
      if (`$idText32 -eq '') { `$idText32 = ([string]`$stageRef[`$i].stage).Trim() }
      if (-not [int]::TryParse(`$idText32, [ref]`$stageIdNum)) { continue }
"@
$mutHits32 = ([regex]::Matches($mutant32, [regex]::Escape($mutOld32))).Count
if ($mutHits32 -ne 1) { Write-Output ('ABORT mutant anchor hits=' + $mutHits32); exit 9 }
$mutant32 = $mutant32.Replace($mutOld32, $mutNew32)
[IO.File]::WriteAllText($g32d, $mutant32, (New-Object Text.UTF8Encoding($false)))
$l32d = Join-Path $r32d 'docs\relay.json'
$p32d = Patch31 $r32d 'p32d.json' '{"stage_done":1}'
$c32d = Run $g32d @('-Action','commit','-ExpectSha256',(Get-FileHash -Algorithm SHA256 -LiteralPath $l32d).Hash,'-Patch',$p32d)
$led32d = Get-Content -LiteralPath $l32d -Raw | ConvertFrom-Json
$leg32d = @($led32d.stages)[0]
$mod32d = @($led32d.stages)[1]
Check 'b32_mutant_with_legacy_first_closes_the_wrong_stage' ($c32d.Code -eq 0 -and ([string]$leg32d.status) -eq 'done' -and ([string]$mod32d.status) -eq 'in_progress') ('exit=' + $c32d.Code + ' legacy=' + [string]$leg32d.status + ' modern=' + [string]$mod32d.status)

$proto32 = [IO.File]::ReadAllText((Join-Path $repoRoot 'protocol\AGENT-RELAY.md'))
$protoCopy32 = [IO.File]::ReadAllText((Join-Path $repoRoot 'tool\templates\AGENT-RELAY.md'))
Check 'b32_protocol_documents_the_legacy_compat' ($proto32 -match 'B32' -and $proto32 -match 'stage_not_found') ('hits=' + ([regex]::Matches($proto32,'B32')).Count)
Check 'b32_protocol_copies_are_identical' ($proto32 -ceq $protoCopy32) ('same=' + ($proto32 -ceq $protoCopy32))
# --- B33: goal confirmation round at activation --------------------------------
$proto33 = [IO.File]::ReadAllText((Join-Path $repoRoot 'protocol\AGENT-RELAY.md'))
$protoCopy33 = [IO.File]::ReadAllText((Join-Path $repoRoot 'tool\templates\AGENT-RELAY.md'))
$actTpl33 = [IO.File]::ReadAllText((Join-Path $repoRoot 'tool\templates\ACTIVATION-PROMPT.md'))
$block33 = [IO.File]::ReadAllText((Join-Path $repoRoot 'tool\templates\AGENTS-RELAY-BLOCK.md'))
$skill33 = [IO.File]::ReadAllText((Join-Path $repoRoot 'tool\SKILL.md'))
$sop33 = [IO.File]::ReadAllText((Join-Path $repoRoot 'tool\templates\RELAY-SOP.md'))
Check 'b33_protocol_documents_confirmation_round' ($proto33 -match 'B33' -and $proto33 -match 'goal confirmation round' -and $proto33 -match 'append-only' -and $proto33 -match 'exactly one round') ('hits=' + ([regex]::Matches($proto33,'B33')).Count)
Check 'b33_protocol_copies_are_identical' ($proto33 -ceq $protoCopy33) ('same=' + ($proto33 -ceq $protoCopy33))
$i033 = $actTpl33.IndexOf('STEP 0'); $i133 = $actTpl33.IndexOf('STEP 1')
Check 'b33_activation_step0_precedes_launcher' ($i033 -ge 0 -and $i133 -ge 0 -and $i033 -lt $i133) ('i0=' + $i033 + ' i1=' + $i133)
Check 'b33_activation_step0_is_one_round_and_append_only' ($actTpl33 -match 'exactly one confirmation round' -and $actTpl33 -match 'Append only' -and $actTpl33 -match 'B33') ''
Check 'b33_activation_step0_refuses_unclear_goal' ($actTpl33 -match 'DO NOT run the launcher') ''
$mutant33 = $actTpl33.Replace('STEP 0', 'STEP X')
$m033 = $mutant33.IndexOf('STEP 0'); $m133 = $mutant33.IndexOf('STEP 1')
Check 'b33_mutant_without_step0_is_detected' (-not ($m033 -ge 0 -and $m133 -ge 0 -and $m033 -lt $m133)) ('mutant_i0=' + $m033)
Check 'b33_managed_block_carries_confirmation_rule' ($block33 -match 'B33' -and $block33 -match 'ask_user') ('hits=' + ([regex]::Matches($block33,'B33')).Count)
Check 'b33_skill_documents_confirmation_round' ($skill33 -match 'B33' -and $skill33 -match 'STEP 0') ('hits=' + ([regex]::Matches($skill33,'B33')).Count)
Check 'b33_sop_documents_confirmation_round' ($sop33 -match 'B33') ('hits=' + ([regex]::Matches($sop33,'B33')).Count)
Check 'b33_installed_packet_carries_step0' ($act16m -match 'STEP 0' -and $act16m.IndexOf('STEP 0') -lt $act16m.IndexOf('STEP 1')) ('i0=' + $act16m.IndexOf('STEP 0'))
# --- B34 (a): -Force must propagate the CURRENT managed block and refresh the packet ---
$r34f = New-Repo 'repo-b34-force'
$ag34f = Join-Path $r34f 'AGENTS.md'
Set-Content -LiteralPath (Join-Path $r34f 'docs\plan-b34.md') -Value '# b34 force plan' -Encoding utf8
$null = Run $installer @('-RepoRoot', $r34f, '-Target', 'b34 force batch', '-PlanDoc', 'docs\plan-b34.md', '-MaxStages', '2')
$act34f = Join-Path $r34f 'docs\relay\ACTIVATION-PROMPT.txt'
Check 'b34_force_baseline_packet_present' (Test-Path $act34f) ('path=' + $act34f)
$txt34f = [IO.File]::ReadAllText($ag34f)
$bi34 = $txt34f.IndexOf($beginMark); $ei34 = $txt34f.IndexOf($endMark)
Check 'b34_force_baseline_markers_located' ($bi34 -ge 0 -and $ei34 -gt $bi34) ('begin=' + $bi34 + ' end=' + $ei34)
if ($bi34 -lt 0 -or $ei34 -le $bi34) { Say 'B34 ABORT managed markers not found'; exit 9 }
$stale34f = $txt34f.Substring(0, $bi34 + $beginMark.Length) + "`n" + 'STALE-B34-BLOCK' + "`n" + $txt34f.Substring($ei34)
[IO.File]::WriteAllText($ag34f, $stale34f, (New-Object Text.UTF8Encoding($false)))
[IO.File]::WriteAllText($act34f, 'STALE-B34-PACKET', (New-Object Text.UTF8Encoding($false)))
$f34 = Run $installer @('-RepoRoot', $r34f, '-Target', 'b34 force batch', '-PlanDoc', 'docs\plan-b34.md', '-MaxStages', '2', '-Force')
$after34f = [IO.File]::ReadAllText($ag34f)
Check 'b34_force_action_replaced' ($f34.Text -match 'AGENTS action=replaced') ('line=' + ((($f34.Text -split "`n") | Where-Object { $_ -match 'AGENTS action=' } | Select-Object -First 1)))
Check 'b34_force_drops_stale_block' (-not $after34f.Contains('STALE-B34-BLOCK')) ''
$block34 = [IO.File]::ReadAllText((Join-Path $repoRoot 'tool\templates\AGENTS-RELAY-BLOCK.md'))
$line34 = (($block34 -split "`n") | Where-Object { $_ -match 'B33' -and $_ -match 'ask_user' -and -not ($_ -match '\{\{') } | Select-Object -First 1)
Check 'b34_force_current_block_line_found' ($null -ne $line34) ''
if ($null -eq $line34) { Say 'B34 ABORT no B33 ask_user line in block template'; exit 9 }
Check 'b34_force_propagates_current_block' ($after34f.Contains($line34.TrimEnd("`r"))) ''
$pack34f = [IO.File]::ReadAllText($act34f)
Check 'b34_force_drops_stale_packet' (-not $pack34f.Contains('STALE-B34-PACKET')) ''
Check 'b34_force_packet_carries_step0' ($pack34f.IndexOf('STEP 0') -ge 0 -and $pack34f.IndexOf('STEP 0') -lt $pack34f.IndexOf('STEP 1')) ('i0=' + $pack34f.IndexOf('STEP 0'))
Check 'b34_force_keeps_project_prose' ($after34f.Contains('Be nice.')) ''
# --- B34 (b): real old-schema ledger drill on a COPY; the original stays read-only ---
$real34 = Join-Path $repoRoot 'examples\practilog\docs\relay.json'
$real34Sha = (Get-FileHash -Algorithm SHA256 -LiteralPath $real34).Hash
$real34Obj = ([IO.File]::ReadAllText($real34)) | ConvertFrom-Json
$topKeys34 = @($real34Obj.PSObject.Properties.Name)
$n34 = @($real34Obj.stages).Count
Check 'b34_real_sample_shape' (($topKeys34 -contains 'stages') -and ($n34 -ge 6)) ('keys=' + $topKeys34.Count + ' stages=' + $n34)
$idx34 = -1
for ($i = 0; $i -lt $n34; $i++) { if ([int]$real34Obj.stages[$i].stage -eq 3) { $idx34 = $i } }
Check 'b34_real_stage3_located' ($idx34 -ge 0) ('idx=' + $idx34)
if ($idx34 -lt 0) { Say 'B34 ABORT stage 3 not found in real sample'; exit 9 }
$sid34 = [string]$real34Obj.stages[$idx34].session_id
Check 'b34_real_stage3_has_session' ($sid34.Length -gt 0) ('len=' + $sid34.Length)
if ($sid34.Length -eq 0) { Say 'B34 ABORT stage 3 session_id empty'; exit 9 }
$real34Obj.status = 'running'
$real34Obj.current_stage = 3
$real34Obj.stages[$idx34].status = 'in_progress'
$copy34 = ConvertTo-Json -InputObject $real34Obj -Depth 100
$r34 = New-GateRepoRaw 'repo-b34-real-legacy' $copy34
$g34 = Join-Path $r34 'docs\relay\relay-ledger.ps1'
$l34 = Join-Path $r34 'docs\relay.json'
$st34 = Run $g34 @('-Action', 'status')
Check 'b34_real_status_ok' ($st34.Code -eq 0) ('code=' + $st34.Code)
Check 'b34_real_status_legacy_render' ($st34.Text -match 'LEDGER_CHAIN') ''
$before34 = ([IO.File]::ReadAllText($l34)) | ConvertFrom-Json
$stageSer34 = @($before34.stages | ForEach-Object { ConvertTo-Json -InputObject $_ -Depth 100 -Compress })
$topSer34 = @{}
foreach ($k in $topKeys34) { if ($k -ne 'stages') { $topSer34[$k] = ConvertTo-Json -InputObject $before34.$k -Depth 100 -Compress } }
$sha34pre = (Get-FileHash -Algorithm SHA256 -LiteralPath $l34).Hash
$bad34 = Run $g34 @('-Action', 'commit', '-ExpectSha256', ('0' * 64), '-Patch', (Patch31 $r34 'p34bad.json' '{"stage_done":3}'))
Check 'b34_real_cas_conflict_exit3' ($bad34.Code -eq 3) ('code=' + $bad34.Code)
Check 'b34_real_cas_conflict_reason' ($bad34.Text -match 'cas_conflict') ''
Check 'b34_real_cas_conflict_bytes_intact' ((Get-FileHash -Algorithm SHA256 -LiteralPath $l34).Hash -eq $sha34pre) ''
$c34 = Run $g34 @('-Action', 'commit', '-ExpectSha256', $sha34pre, '-Patch', (Patch31 $r34 'p34.json' '{"stage_done":3}'))
Check 'b34_real_commit_ok' ($c34.Code -eq 0) ('code=' + $c34.Code)
Check 'b34_real_commit_marker' ($c34.Text -match 'LEDGER_COMMITED') ''
# The real ledger already carries a sessions[] trail of entry objects, and the
# gate registers a stage session only once: an id already in the trail must
# yield ALREADY_REGISTERED and no second entry, a fresh id must yield
# REGISTERED with source=stage_field. Derive the expected branch from the
# pre-state so the check keeps its teeth on both paths (a mutant that double
# appends or silently skips registration goes red either way).
$pat34 = '"' + [regex]::Escape($sid34) + '"'
$known34 = $false
foreach ($s in @($before34.sessions)) { if ((ConvertTo-Json -InputObject $s -Compress -Depth 100) -match $pat34) { $known34 = $true; break } }
if ($known34) {
  Check 'b34_real_session_trail_stage_field' ($c34.Text -match ('LEDGER_SESSION_ALREADY_REGISTERED session=' + [regex]::Escape($sid34))) 'branch=already_registered'
} else {
  Check 'b34_real_session_trail_stage_field' ($c34.Text -match ('LEDGER_SESSION_REGISTERED session=' + [regex]::Escape($sid34) + ' stage=3 source=stage_field')) 'branch=stage_field'
}
$after34 = ([IO.File]::ReadAllText($l34)) | ConvertFrom-Json
$hits34 = 0
foreach ($s in @($after34.sessions)) { if ((ConvertTo-Json -InputObject $s -Compress -Depth 100) -match $pat34) { $hits34++ } }
Check 'b34_real_session_trail_exactly_once' ($hits34 -eq 1) ('hits=' + $hits34)
$delta34 = @($after34.sessions).Count - @($before34.sessions).Count
if ($known34) {
  Check 'b34_real_trail_append_delta' ($delta34 -eq 0) ('delta=' + $delta34 + ' branch=already_registered')
} else {
  Check 'b34_real_trail_append_delta' ($delta34 -eq 1) ('delta=' + $delta34 + ' branch=stage_field')
}
Check 'b34_real_stage3_done' ($after34.stages[$idx34].status -eq 'done') ('status=' + $after34.stages[$idx34].status)
Check 'b34_real_stage_count_kept' (@($after34.stages).Count -eq $n34) ('n=' + @($after34.stages).Count)
$k34b = @($before34.stages[$idx34].PSObject.Properties.Name | Sort-Object)
$k34a = @($after34.stages[$idx34].PSObject.Properties.Name | Sort-Object)
Check 'b34_real_stage3_keys_preserved' (@(Compare-Object $k34b $k34a).Count -eq 0) ('diff=' + @(Compare-Object $k34b $k34a).Count)
$idinj34 = $false
foreach ($s in $after34.stages) { if (@($s.PSObject.Properties.Name) -contains 'id') { $idinj34 = $true } }
Check 'b34_real_no_id_injection_any_stage' (-not $idinj34) ''
Check 'b34_real_finished_at_kept' (([string]$after34.stages[$idx34].finished_at) -eq ([string]$before34.stages[$idx34].finished_at)) ''
$same34 = $true
for ($i = 0; $i -lt $n34; $i++) { if ($i -ne $idx34) { if ((ConvertTo-Json -InputObject $after34.stages[$i] -Depth 100 -Compress) -cne $stageSer34[$i]) { $same34 = $false } } }
Check 'b34_real_other_stages_untouched' $same34 ''
$allow34 = @('status', 'current_stage', 'next_session_id', 'updated_at')
$afterKeys34 = @($after34.PSObject.Properties.Name)
$missing34 = $false; $keep34 = $true
foreach ($k in $topKeys34) {
  if (-not ($afterKeys34 -contains $k)) { $missing34 = $true }
  if (($k -ne 'stages') -and (-not ($allow34 -contains $k))) {
    if ((ConvertTo-Json -InputObject $after34.$k -Depth 100 -Compress) -cne $topSer34[$k]) { $keep34 = $false }
  }
}
Check 'b34_real_top_keys_survive' (-not $missing34) ''
Check 'b34_real_top_values_preserved' $keep34 ''
$onlyGate34 = $true
foreach ($k in $afterKeys34) { if (-not ($topKeys34 -contains $k) -and -not (@('updated_at', 'sessions') -contains $k)) { $onlyGate34 = $false } }
Check 'b34_real_only_gate_keys_added' $onlyGate34 ''
Check 'b34_real_original_readonly' ((Get-FileHash -Algorithm SHA256 -LiteralPath $real34).Hash -eq $real34Sha) ('sha=' + $real34Sha.Substring(0,16))
# --- case b35: the headless hand-over path (permit -> adopt -> child) -----------
# The hand-over path of a headless link had no gate at all: the driver takes a
# permit, hands the lock over BEFORE the child starts, and releases it again
# when the child dies. None of that was ever executed by a test, so a link could
# have started with the lock still in the hands of a dead link. The cases below
# run the real driver against a stub runtime, so the order is observable: the
# stub copies the lock file as it is at the moment the child starts.
$repo35 = New-Repo 'repo-b35-handover'
Set-Content -LiteralPath (Join-Path $repo35 'docs\plan-35.md') -Value '# plan 35' -Encoding utf8
$i35 = Run $installer @('-RepoRoot', $repo35, '-Target', 'b35 handover', '-PlanDoc', 'docs\plan-35.md', '-MaxStages', '2', '-Runtime', 'claude-code')
Check 'b35_install_exit_zero' ($i35.Code -eq 0) ('exit=' + $i35.Code)
$spawn35 = Join-Path $repo35 'docs\relay\relay-spawn.ps1'
$lock35 = Join-Path $repo35 'docs\relay\relay-lock.ps1'
$lockFile35 = Join-Path $repo35 'docs\relay\.relay.lock'
$permitFile35 = Join-Path $repo35 'docs\relay\.spawn-permit.json'
Check 'b35_kit_installed' ((Test-Path -LiteralPath $spawn35) -and (Test-Path -LiteralPath $lock35)) ''
$prompt35 = Join-Path $script:root 'relay-prompt-35.txt'
[IO.File]::WriteAllText($prompt35, ("b35 prompt`n"), (New-Object Text.UTF8Encoding($false)))
# The stub runtime. It answers --help with a build that knows only the flags
# this kit uses, and it copies the lock file into the marker file while it
# runs, so the test can see who owned the lock at that moment.
$stubDir35 = Join-Path $script:root 'shim35'
New-Item -ItemType Directory -Path $stubDir35 -Force | Out-Null
function Write-Stub35([string]$SessionId, [bool]$Fail, [bool]$KnowsTurns) {
  $lines = @('@echo off', 'if "%1"=="--help" (', '  echo --output-format json', '  echo --session-id uuid')
  # The turn cap must be advertised without angle brackets: in a batch file
  # "<turns" is an input redirection, the whole echo fails, and the help text
  # never mentions the flag at all.
  if ($KnowsTurns) { $lines += '  echo --max-turns turns' }
  $lines += @('  exit /b 0', ')', 'if exist "%RELAY_TEST_LOCK%" copy /y "%RELAY_TEST_LOCK%" "%RELAY_TEST_MARKER%" >nul 2>&1', ('echo {"type":"result","session_id":"' + $SessionId + '","result":"stub"}'))
  if ($Fail) { $lines += 'exit /b 1' } else { $lines += 'exit /b 0' }
  [IO.File]::WriteAllText((Join-Path $stubDir35 'claude.cmd'), (($lines -join "`n") + "`n"), (New-Object Text.UTF8Encoding($false)))
}
function Invoke-Spawn35([string]$SessionId, [bool]$Fail, [bool]$KnowsTurns, [bool]$Execute) {
  Write-Stub35 $SessionId $Fail $KnowsTurns
  $marker = Join-Path $script:root ('marker35-' + $SessionId + '.json')
  if (Test-Path -LiteralPath $marker) { Remove-Item -LiteralPath $marker -Force }
  $oldPath = $env:PATH
  $oldLock = $env:RELAY_TEST_LOCK
  $oldMarker = $env:RELAY_TEST_MARKER
  try {
    $env:PATH = $stubDir35 + [IO.Path]::PathSeparator + $oldPath
    $env:RELAY_TEST_LOCK = $lockFile35
    $env:RELAY_TEST_MARKER = $marker
    $argv = @('-Runtime', 'claude-code', '-PromptFile', $prompt35, '-WorkspaceDir', $repo35, '-SessionId', $SessionId)
    if ($Execute) { $argv += @('-Execute', '-AdoptLock') }
    return (Run $spawn35 $argv)
  } finally {
    $env:PATH = $oldPath
    $env:RELAY_TEST_LOCK = $oldLock
    $env:RELAY_TEST_MARKER = $oldMarker
  }
}
# scene 1: the hand-over happens before the child starts.
$acq35 = Run $lock35 @('-Action', 'acquire', '-SessionId', 'mvs_b35_old', '-Stage', '0')
Check 'b35_lock_acquired' ($acq35.Code -eq 0) ('exit=' + $acq35.Code)
$sid35 = [guid]::NewGuid().ToString()
$h35 = Invoke-Spawn35 $sid35 $false $false $true
Check 'b35_handover_exit_zero' ($h35.Code -eq 0) ('exit=' + $h35.Code)
Check 'b35_handover_pre_adopted' ($h35.Text -match ('SPAWN_LOCK_PRE_ADOPTED session_id=' + [regex]::Escape($sid35) + ' nonce=[0-9a-f]{16}')) ''
Check 'b35_handover_lock_adopted' ($h35.Text -match ('LOCK_ADOPTED holder=' + [regex]::Escape($sid35) + ' prev_holder=mvs_b35_old')) ''
$marker35 = Join-Path $script:root ('marker35-' + $sid35 + '.json')
$seen35 = $null
if (Test-Path -LiteralPath $marker35) { $seen35 = ([IO.File]::ReadAllText($marker35)) | ConvertFrom-Json }
Check 'b35_lock_handed_over_before_the_child_started' ($null -ne $seen35 -and [string]$seen35.holder -eq $sid35) ('holder=' + [string]$seen35.holder)
$rec35 = ([IO.File]::ReadAllText($lockFile35)) | ConvertFrom-Json
Check 'b35_lock_holder_is_the_new_link' ([string]$rec35.holder -eq $sid35) ('holder=' + [string]$rec35.holder)
$permit35 = ([IO.File]::ReadAllText($permitFile35)) | ConvertFrom-Json
Check 'b35_permit_is_consumed_by_the_handover' (([string]$permit35.consumed_by -eq $sid35) -and -not [string]::IsNullOrWhiteSpace([string]$permit35.consumed_at)) ('consumed_by=' + [string]$permit35.consumed_by)
# scene 2: a child that dies must not leave the lock behind.
$null = Run $lock35 @('-Action', 'release', '-SessionId', $sid35)
$null = Run $lock35 @('-Action', 'acquire', '-SessionId', 'mvs_b35_old2', '-Stage', '0')
$sid35b = [guid]::NewGuid().ToString()
$f35 = Invoke-Spawn35 $sid35b $true $false $true
Check 'b35_child_failure_exit_three' ($f35.Code -eq 3) ('exit=' + $f35.Code)
Check 'b35_child_failure_reports_the_reason' ($f35.Text -match 'FAIL reason=runtime_run_failed') ''
Check 'b35_child_failure_releases_the_lock' ($f35.Text -match ('SPAWN_LOCK_RELEASED session_id=' + [regex]::Escape($sid35b))) ''
Check 'b35_no_lock_is_left_behind' (-not (Test-Path -LiteralPath $lockFile35)) ('lock=' + $lockFile35)
# scene 3: a turn cap is only passed on when the build knows the flag.
Write-Stub35 ([guid]::NewGuid().ToString()) $false $false
$oldPath35 = $env:PATH
try {
  $env:PATH = $stubDir35 + [IO.Path]::PathSeparator + $oldPath35
  $t35 = Run $spawn35 @('-Runtime', 'claude-code', '-PromptFile', $prompt35, '-WorkspaceDir', $repo35, '-MaxTurns', '3')
} finally {
  $env:PATH = $oldPath35
}
$cmdLine35 = (($t35.Text -split "`n") | Where-Object { $_ -match 'SPAWN_COMMAND claude ' } | Select-Object -First 1)
Check 'b35_unknown_turn_flag_is_not_passed' (-not ($cmdLine35 -match '--max-turns')) ('line=' + $cmdLine35)
Check 'b35_unknown_turn_flag_is_reported' ($t35.Text -match 'WARN reason=max_turns_flag_unsupported') ''
Write-Stub35 ([guid]::NewGuid().ToString()) $false $true
try {
  $env:PATH = $stubDir35 + [IO.Path]::PathSeparator + $oldPath35
  $t35b = Run $spawn35 @('-Runtime', 'claude-code', '-PromptFile', $prompt35, '-WorkspaceDir', $repo35, '-MaxTurns', '3')
} finally {
  $env:PATH = $oldPath35
}
$cmdLine35b = (($t35b.Text -split "`n") | Where-Object { $_ -match 'SPAWN_COMMAND claude ' } | Select-Object -First 1)
Check 'b35_known_turn_flag_is_passed' ($cmdLine35b -match '--max-turns 3') ('line=' + $cmdLine35b)
Check 'b35_known_turn_flag_is_not_warned' (-not ($t35b.Text -match 'max_turns_flag_unsupported')) ''
# --- guard: no script may declare a parameter that shadows the read-only $PID ----
$lockGuard = [IO.File]::ReadAllText((Join-Path $repoRoot 'tool\templates\relay-lock.ps1'))
Check 'lock_param_not_shadowing_PID' (-not ($lockGuard -cmatch '\$Pid\b')) ('hits=' + ([regex]::Matches($lockGuard,'\$Pid\b')).Count)
# --- verdict -------------------------------------------------------------------
Say ('SUITE_END pass=' + $script:pass + ' fail=' + $script:fail + ' root=' + $script:root)
Say ('MANUAL_STEP real_session_activation: this suite never calls session_create. One live chain per changed ' +
  'kit is still an agent-side step; see tool\references\selftest-*.md for how it was last verified.')
if (-not [string]::IsNullOrWhiteSpace($EvidencePath)) {
  if (-not [IO.Path]::IsPathRooted($EvidencePath)) { Say 'WARN evidence_path_not_absolute_ignored' }
  else {
    New-Item -ItemType Directory -Path (Split-Path -Parent $EvidencePath) -Force | Out-Null
    [IO.File]::WriteAllText($EvidencePath, ((($log -join "`n") -replace "`r", '') + "`n"), (New-Object Text.UTF8Encoding($false)))
    Say ('EVIDENCE written=' + $EvidencePath + ' bytes=' + (Get-Item -LiteralPath $EvidencePath).Length)
  }
}
if ($Cleanup) {
  Remove-Item -LiteralPath $script:root -Recurse -Force -ErrorAction SilentlyContinue
  Say ('CLEANUP removed=' + $script:root)
}
if ($script:fail -gt 0) { exit 1 }
exit 0
