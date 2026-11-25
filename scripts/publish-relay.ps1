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
    3  the global skill root does not exist (pass -SkillRoot, or set RELAY_PORT_SKILL_ROOT)
    4  a copy or read failed mid-way (partial publish: re-run publish to converge)
.PARAMETER Direction
  verify   report only, change nothing (default)
  publish  mirror tool/templates -> device, then tool -> global skill
  pull     mirror global skill -> tool (rescue path), then templates -> device
.PARAMETER SkillRoot
  Absolute path of the installed global skill. Precedence: this parameter >
  $env:RELAY_PORT_SKILL_ROOT > probe of $env:MAVIS_DATA_DIR / $env:MINIMAX_DATA_DIR /
  $HOME / %USERPROFILE%. Pass this explicitly when the desktop profile does not sit
  under the user profile directory.
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
$resolvedRoot = ''
$rootSource = ''
if (-not [string]::IsNullOrWhiteSpace($SkillRoot)) { $resolvedRoot = $SkillRoot; $rootSource = 'parameter' }
elseif (-not [string]::IsNullOrWhiteSpace($env:RELAY_PORT_SKILL_ROOT)) { $resolvedRoot = $env:RELAY_PORT_SKILL_ROOT; $rootSource = 'env' }
else {
  # The desktop profile is NOT guaranteed to live under $HOME or %USERPROFILE%
  # (a redirected profile keeps the runtime data dir on another volume), so the
  # probe walks every candidate data root it can name and takes the first hit.
  $dataRoots = New-Object System.Collections.Generic.List[string]
  foreach ($v in @($env:MAVIS_DATA_DIR, $env:MINIMAX_DATA_DIR, $HOME, $env:USERPROFILE)) {
    if (-not [string]::IsNullOrWhiteSpace($v)) { $dataRoots.Add($v) }
  }
  foreach ($dr in $dataRoots) {
    foreach ($rel in @('.minimax\.minimax\skills\relay-port', 'minimax\.minimax\skills\relay-port', 'skills\relay-port')) {
      $cand = Join-Path $dr $rel
      if (Test-Path -LiteralPath $cand -PathType Container) { $resolvedRoot = $cand; $rootSource = 'probe'; break }
    }
    if (-not [string]::IsNullOrWhiteSpace($resolvedRoot)) { break }
  }
}
if ([string]::IsNullOrWhiteSpace($resolvedRoot)) {
  Say 'FAIL' ('skill_root_not_found probed=' + ($dataRoots -join ',') + ' hint=pass_-SkillRoot_or_set_RELAY_PORT_SKILL_ROOT_or_MAVIS_DATA_DIR')
  exit 3
}
Say 'INFO' ('skill_root=' + $resolvedRoot + ' via=' + $rootSource)

$fail = 0
$warn = 0

# --- hard invariant 1: device copies == templates ------------------------------
Say 'INFO' 'invariant=device_vs_templates kind=hard'
foreach ($name in @('start-relay.ps1', 'relay-lock.ps1', 'relay-ledger.ps1')) {
  $tpl = Join-Path $templateDir $name
  $dev = Join-Path $deviceDir $name
  if (-not (Test-Path -LiteralPath $tpl -PathType Leaf)) { Say 'FAIL' ("template_missing file=$name"); $fail++; continue }
  $a = Stamp $tpl
  $b = Stamp $dev
  if ($a -eq $b) { Say 'OK' ("device_matches_template file=$name stamp=$a") ; continue }
  if ($Direction -eq 'publish' -or $Direction -eq 'pull') {
    Copy-Item -LiteralPath $tpl -Destination $dev -Force
    $c = Stamp $dev
    if ($c -ne $a) { Say 'FAIL' ("device_sync_failed file=$name before=$b after=$c want=$a"); $fail++ }
    else { Say 'FIX' ("device_synced_from_template file=$name before=$b after=$c") }
  }
  elseif ($Direction -eq 'verify') {
    Say 'FAIL' ("device_template_drift file=$name template=$a device=$b fix=publish-relay.ps1_-Direction_publish")
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
