<#
.SYNOPSIS
  One-shot release tool for the relay-port kit: enforce device/template identity and sync tool/ to the global skill.
.DESCRIPTION
  Why this exists
    Project rule 2 says: editing tool/ only takes effect after the four parts (SKILL.md, scripts/, templates/,
    references/) are synced back to the global skill directory. Rule 3 says device/*.ps1 must be byte-identical
    to the same-named tool/templates/*.ps1. Doing both by hand is error-prone, so this script does it in one
    call and prints a per-file hash ledger as evidence.

  Source of truth
    tool/templates/   is authoritative for the device copies; publish mirrors templates -> device/.
    tool/             is authoritative for the global skill; publish mirrors tool/ -> <skill root>/.
    The global skill is a distribution target, never an input. Use 'pull' only to rescue edits made directly there.
    examples/practilog/** is an evidence snapshot (rule 8): drift there is reported as SNAPSHOT_DRIFT, never fixed
    and never a failure.

  Idempotent
    Re-running publish with nothing changed prints SYNC for every file and changes no bytes.

  Exit codes
    0  requested direction completed; all hard invariants hold afterwards
    2  verify found a hard invariant violation (device vs templates)
    3  no global skill root was found by -SkillRoot, RELAY_PORT_SKILL_ROOT or the probe
    4  a copy or read failed mid-way (partial publish: re-run publish to converge)
.PARAMETER Direction
  verify   report only, change nothing (default)
  publish  mirror tool/templates -> device, then tool -> global skill
  pull     mirror global skill -> tool (rescue path), then templates -> device
.PARAMETER SkillRoot
  Absolute path of the installed global skill. Resolution order (finding F4 of
  tool\references\portability-audit-2026-11-25.md, fixed 2026-11-25): this parameter >
  $env:RELAY_PORT_SKILL_ROOT > probe. The probe walks $env:MAVIS_DATA_DIR /
  $env:MINIMAX_DATA_DIR, $HOME and %USERPROFILE% (each also with .minimax\.minimax and
  minimax\.minimax appended), then every filesystem drive at
  <drive>\Users\<user leaf>\.minimax\.minimax -- the active desktop profile is NOT
  guaranteed to sit under %USERPROFILE%'s drive. Prints 'skill_root=<path> via=<source>'.
  If several roots hold a copy it picks the most recently active profile, warns
  skill_root_ambiguous, and lists the candidates; pin it with this parameter or the
  environment variable when the heuristic would pick the wrong one.
.PARAMETER Strict
  With verify, also fail on SNAPSHOT_DRIFT. Off by default: the examples snapshot is allowed to lag.
.EXAMPLE
  pwsh -NoProfile -File scripts\publish-relay.ps1
.EXAMPLE
  pwsh -NoProfile -File scripts\publish-relay.ps1 -Direction publish
.NOTES
  Pure ASCII, no BOM, LF. Run scripts\refresh-manifest.ps1 after publishing.
#>
[CmdletBinding()]
param(
  [ValidateSet('verify', 'publish', 'pull')]
  [string]$Direction = 'verify',
  [string]$SkillRoot = '',
  [switch]$Strict
)

$ErrorActionPreference = 'Stop'

function Stamp([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return 'MISSING' }
  $h = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
  return ($h.Substring(0, 16) + ':' + (Get-Item -LiteralPath $Path).Length)
}

function Say([string]$Level, [string]$Text) { Write-Output ('[' + $Level + '] ' + $Text) }

$repoRoot = (Get-Item -LiteralPath (Split-Path -Parent $PSCommandPath)).Parent.FullName
$toolDir = Join-Path $repoRoot 'tool'
$deviceDir = Join-Path $repoRoot 'device'
$templateDir = Join-Path $toolDir 'templates'
$scriptDir = Join-Path $toolDir 'scripts'
$refDir = Join-Path $toolDir 'references'
$exampleRelayDir = Join-Path $repoRoot 'examples\practilog\docs\relay'

if (-not (Test-Path -LiteralPath $toolDir -PathType Container)) {
  Say 'FAIL' ('tool_dir_missing ' + $toolDir)
  exit 4
}

# --- resolve the global skill root ---------------------------------------------
# Finding F4 of tool\references\portability-audit-2026-11-25.md, fixed on 2026-11-25
# by human ruling. The desktop runtime data dir is NOT guaranteed to sit under
# %USERPROFILE%: a redirected profile keeps it on another volume (this very machine
# has %USERPROFILE% on C: and the active profile on E:). The old probe walked only
# $HOME / %USERPROFILE%, so it printed skill_root_not_found and exit 3 even though
# the skill was installed -- a false alarm that pushed every caller to pass
# -SkillRoot by hand. The probe now names every data root it can derive, adds a
# drive scan for the same relative profile path, and when several roots hold a
# copy it prefers the profile the desktop is actively writing to (new session dirs
# land in <profile>\v2\sessions, so that directory's timestamp tracks activity).
# Explicit -SkillRoot or RELAY_PORT_SKILL_ROOT still wins, so the behaviour stays
# overridable on a machine where the heuristic would pick the wrong copy.
function Get-RelaySkillCandidate {
  $found = New-Object System.Collections.Generic.List[object]
  $seen = @{}
  $roots = New-Object System.Collections.Generic.List[string]
  foreach ($v in @($env:MAVIS_DATA_DIR, $env:MINIMAX_DATA_DIR)) {
    if (-not [string]::IsNullOrWhiteSpace($v)) { $roots.Add($v) }
  }
  foreach ($v in @($HOME, $env:USERPROFILE)) {
    if ([string]::IsNullOrWhiteSpace($v)) { continue }
    $roots.Add($v)
    $roots.Add((Join-Path $v '.minimax\.minimax'))
    $roots.Add((Join-Path $v 'minimax\.minimax'))
  }
  $leaf = ''
  if (-not [string]::IsNullOrWhiteSpace($env:USERPROFILE)) { $leaf = Split-Path -Leaf $env:USERPROFILE }
  elseif (-not [string]::IsNullOrWhiteSpace($HOME)) { $leaf = Split-Path -Leaf $HOME }
  if (-not [string]::IsNullOrWhiteSpace($leaf)) {
    foreach ($d in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)) {
      $rt = [string]$d.Root
      if ($rt -notmatch '^[A-Za-z]:\\$') { continue }
      foreach ($sub in @('.minimax\.minimax', 'minimax\.minimax')) {
        $roots.Add((Join-Path $rt ('Users\' + $leaf + '\' + $sub)))
      }
    }
  }
  foreach ($root in $roots) {
    if ([string]::IsNullOrWhiteSpace($root)) { continue }
    $key = $root.ToLowerInvariant()
    if ($seen.ContainsKey($key)) { continue }
    $seen[$key] = $true
    $cand = Join-Path $root 'skills\relay-port'
    if (-not (Test-Path -LiteralPath $cand -PathType Container)) { continue }
    $activity = (Get-Item -LiteralPath $cand).LastWriteTime
    $live = Join-Path $root 'v2\sessions'
    if (Test-Path -LiteralPath $live -PathType Container) { $activity = (Get-Item -LiteralPath $live).LastWriteTime }
    $found.Add([pscustomobject]@{ Root = $cand; Profile = $root; Activity = $activity })
  }
  return $found
}

$resolvedRoot = ''
$rootSource = ''
if (-not [string]::IsNullOrWhiteSpace($SkillRoot)) { $resolvedRoot = $SkillRoot; $rootSource = 'parameter' }
elseif (-not [string]::IsNullOrWhiteSpace($env:RELAY_PORT_SKILL_ROOT)) { $resolvedRoot = $env:RELAY_PORT_SKILL_ROOT; $rootSource = 'env' }
else {
  $cands = @(Get-RelaySkillCandidate)
  if ($cands.Count -eq 1) {
    $resolvedRoot = $cands[0].Root; $rootSource = 'probe'
  } elseif ($cands.Count -gt 1) {
    $rank = @($cands | Sort-Object -Property Activity -Descending)
    $resolvedRoot = $rank[0].Root; $rootSource = 'probe-multi'
    Say 'INFO' ('skill_root_candidates=' + $cands.Count + ' chosen_by=profile_activity order=' + (($rank | ForEach-Object { $_.Profile }) -join '|'))
    Say 'WARN' 'skill_root_ambiguous pass -SkillRoot or set RELAY_PORT_SKILL_ROOT to pin it'
  }
}
if ([string]::IsNullOrWhiteSpace($resolvedRoot)) {
  Say 'FAIL' 'skill_root_not_found hint=pass_-SkillRoot_or_set_RELAY_PORT_SKILL_ROOT_or_MAVIS_DATA_DIR(probe_walked_userprofile_home_and_every_drive)'
  exit 3
}
Say 'INFO' ('skill_root=' + $resolvedRoot + ' via=' + $rootSource)

$fail = 0
$warn = 0

# --- hard invariant 1: generated copies == templates ----------------------------
# 1a: the three device scripts must be byte-identical to their templates (AGENTS.md rule 3).
# 1b: protocol\AGENT-RELAY.md is the human-readable mirror of the protocol that the installer
#     actually ships (tool\templates\AGENT-RELAY.md). B3 (2026-11-25) caught the two drifting
#     silently -- one clause lived only in the template -- and the fix was a manual re-sync
#     with nothing to stop a repeat. The mirror is gated like the device copies from now on.
Say 'INFO' 'invariant=templates_vs_copies kind=hard'
$copyPairs = @(
  [pscustomobject]@{ Name = 'start-relay.ps1';  Tpl = (Join-Path $templateDir 'start-relay.ps1');  Dst = (Join-Path $deviceDir 'start-relay.ps1') },
  [pscustomobject]@{ Name = 'relay-lock.ps1';   Tpl = (Join-Path $templateDir 'relay-lock.ps1');   Dst = (Join-Path $deviceDir 'relay-lock.ps1') },
  [pscustomobject]@{ Name = 'relay-ledger.ps1'; Tpl = (Join-Path $templateDir 'relay-ledger.ps1'); Dst = (Join-Path $deviceDir 'relay-ledger.ps1') },
  [pscustomobject]@{ Name = 'AGENT-RELAY.md';   Tpl = (Join-Path $templateDir 'AGENT-RELAY.md');   Dst = (Join-Path $repoRoot 'protocol\AGENT-RELAY.md') }
)
foreach ($cp in $copyPairs) {
  $name = $cp.Name
  $tpl = $cp.Tpl
  $dev = $cp.Dst
  if (-not (Test-Path -LiteralPath $tpl -PathType Leaf)) { Say 'FAIL' ("template_missing file=$name"); $fail++; continue }
  $a = Stamp $tpl
  $b = Stamp $dev
  if ($a -eq $b) { Say 'OK' ("copy_matches_template file=$name stamp=$a") ; continue }
  if ($Direction -eq 'publish' -or $Direction -eq 'pull') {
    Copy-Item -LiteralPath $tpl -Destination $dev -Force
    $c = Stamp $dev
    if ($c -ne $a) { Say 'FAIL' ("copy_sync_failed file=$name before=$b after=$c want=$a"); $fail++ }
    else { Say 'FIX' ("copy_synced_from_template file=$name before=$b after=$c") }
  }
  elseif ($Direction -eq 'verify') {
    Say 'FAIL' ("copy_template_drift file=$name template=$a copy=$b fix=publish-relay.ps1_-Direction_publish")
    $fail++
  }
}

# --- the four parts that must reach the global skill ---------------------------
function Get-FileSet([string]$base) {
  if (-not (Test-Path -LiteralPath $base -PathType Container)) { return @() }
  return @(Get-ChildItem -LiteralPath $base -Recurse -File | ForEach-Object { $_.FullName.Substring($base.Length + 1) })
}

$pairs = New-Object System.Collections.Generic.List[object]
$skillFile = Join-Path $toolDir 'SKILL.md'
if (Test-Path -LiteralPath $skillFile -PathType Leaf) {
  $pairs.Add([pscustomobject]@{ Rel = 'SKILL.md'; Tool = $skillFile; Global = (Join-Path $resolvedRoot 'SKILL.md') })
}
foreach ($sub in @('scripts', 'templates', 'references')) {
  $dir = Join-Path $toolDir $sub
  foreach ($rel in (Get-FileSet $dir)) {
    $pairs.Add([pscustomobject]@{
        Rel    = (Join-Path $sub $rel)
        Tool   = (Join-Path $dir $rel)
        Global = (Join-Path $resolvedRoot (Join-Path $sub $rel))
      })
  }
}
Say 'INFO' ('tracked_files=' + $pairs.Count)

# --- hard invariant 2: tool/ == global skill ------------------------------------
Say 'INFO' 'invariant=tool_vs_skill kind=hard'
foreach ($p in $pairs) {
  $a = Stamp $p.Tool
  $b = Stamp $p.Global
  if ($a -eq $b) { Say 'SYNC' ($p.Rel + ' ' + $a); continue }
  switch ($Direction) {
    'verify' { Say 'DRIFT' ($p.Rel + ' tool=' + $a + ' skill=' + $b); $fail++ }
    'pull' {
      Copy-Item -LiteralPath $p.Global -Destination $p.Tool -Force
      $c = Stamp $p.Tool
      if ($c -ne $b) { Say 'FAIL' ('pull_failed file=' + $p.Rel); $fail++ }
      else { Say 'PULL' ($p.Rel + ' ' + $b) }
    }
    'publish' {
      $dstDir = Split-Path -Parent $p.Global
      if (-not (Test-Path -LiteralPath $dstDir -PathType Container)) { New-Item -ItemType Directory -Path $dstDir -Force | Out-Null }
      Copy-Item -LiteralPath $p.Tool -Destination $p.Global -Force
      $c = Stamp $p.Global
      if ($c -ne $a) { Say 'FAIL' ('publish_verify_failed file=' + $p.Rel + ' want=' + $a + ' got=' + $c); $fail++ }
      else { Say 'PUBLISH' ($p.Rel + ' ' + $a) }
    }
  }
}

# files that exist only in the skill (leftovers from a deleted tool file)
$toolRel = @($pairs | ForEach-Object { $_.Rel })
foreach ($rel in (Get-FileSet $resolvedRoot)) {
  if ($rel -eq 'MANIFEST.txt') { continue }
  if ($toolRel -notcontains $rel) { Say 'WARN' ('skill_only_file ' + $rel + ' (not in tool/; remove by hand)'); $warn++ }
}

# --- soft: the examples snapshot is allowed to lag ------------------------------
Say 'INFO' 'invariant=examples_snapshot kind=soft'
foreach ($name in @('start-relay.ps1', 'relay-lock.ps1', 'relay-ledger.ps1')) {
  $snap = Join-Path $exampleRelayDir $name
  if (-not (Test-Path -LiteralPath $snap -PathType Leaf)) { Say 'INFO' ("snapshot_absent file=$name"); continue }
  $t = Stamp (Join-Path $templateDir $name)
  $s = Stamp $snap
  if ($t -eq $s) { Say 'OK' ("snapshot_matches_template file=$name stamp=$s") }
  else {
    Say 'WARN' ("SNAPSHOT_DRIFT file=$name template=$t snapshot=$s note=history_snapshot_keep_as_is")
    $warn++
    if ($Strict) { $fail++ }
  }
}

# --- verdict -------------------------------------------------------------------
if ($fail -gt 0) {
  Say 'RESULT' ('DIRECTION=' + $Direction + ' STATUS=FAIL fail=' + $fail + ' warn=' + $warn)
  if ($Direction -eq 'verify') { exit 2 }
  exit 4
}
Say 'RESULT' ('DIRECTION=' + $Direction + ' STATUS=OK fail=0 warn=' + $warn)
if ($Direction -ne 'verify') { Say 'INFO' 'reminder=run_scripts_refresh-manifest.ps1_after_publishing' }
exit 0
