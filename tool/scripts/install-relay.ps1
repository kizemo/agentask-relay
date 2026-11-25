<#
.SYNOPSIS
  Install the unattended relay (auto-advance) kit into a target git project.

.DESCRIPTION
  Idempotent installer. Copies the validated device scripts (start-relay.ps1,
  relay-lock.ps1, relay-ledger.ps1, relay-spawn.ps1), the generic relay protocol, the
  project adjudication skeleton and the managed rule block into the target repository,
  then self-checks the result and writes the activation prompt that starts the chain.

  Runtime selection (-Runtime):
    mcode        the built-in session_create tool starts the next link; rules go to AGENTS.md
    codex        Codex CLI, native AGENTS.md; the next link is a headless `codex exec`
    claude-code  Claude Code; rules go to BOTH AGENTS.md and CLAUDE.md (a CLAUDE.md in the
                 repo shadows AGENTS.md, so the block would never be read); the next link
                 is a headless `claude -p`
    openclaw     OpenClaw, AGENTS.md must sit in the agent workspace root; the next link
                 is spawned with the sessions_spawn tool

  Safety rules baked into this installer:
    * docs\relay.json is NEVER created or rewritten here; the launcher owns the
      ledger and only ever creates it.
    * An existing relay section in the rule file is ADOPTED with markers, never
      duplicated, and its text is kept unless -Force is given.
    * A rule file is only written when the managed block actually changes; the
      file is never truncated and its before/after hash is reported.
    * Project files that differ from the shipped templates are kept unless
      -Force is given.
    * The installed .ps1 files are checked for non-ASCII bytes and for a BOM.

.EXAMPLE
  pwsh -NoProfile -ExecutionPolicy Bypass -File install-relay.ps1 -RepoRoot D:\work\myapp -Target "Task 12 hardening"

.EXAMPLE
  pwsh -NoProfile -ExecutionPolicy Bypass -File install-relay.ps1 -RepoRoot D:\work\myapp -Target "..." -PlanDoc docs\plan-task12.md -MaxStages 6 -Runtime claude-code
#>
param(
  [Parameter(Mandatory = $true)]
  [string]$RepoRoot,

  [string]$Target = 'relay batch',
  [string]$PlanDoc = '',
  [string]$StageTitles = '',
  [int]$MaxStages = 6,
  [string]$WorkspaceDir = '',
  [int]$TtlSeconds = 1800,
  [string]$Runtime = 'mcode',
  [switch]$Force,
  [switch]$SkipVerify
)

$ErrorActionPreference = 'Stop'

$skillRoot   = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$templateDir = Join-Path $skillRoot 'templates'
$reportLines = New-Object System.Collections.Generic.List[string]
$warnLines   = New-Object System.Collections.Generic.List[string]

function Log { param([string]$Line) Write-Host $Line; $reportLines.Add($Line) }
function Warn { param([string]$Line) Write-Host "WARN $Line"; $warnLines.Add($Line) }

function Get-RelPath {
  param([string]$Base, [string]$Full)
  $b = $Base.TrimEnd('\') + '\'
  if ($Full.StartsWith($b, [System.StringComparison]::OrdinalIgnoreCase)) { return $Full.Substring($b.Length) }
  return $Full
}

function Read-TextOrEmpty {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return '' }
  $t = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
  if ($null -eq $t) { return '' }
  return [string]$t
}

function Expand-Template {
  param([string]$Text, [string]$RepoName, [string]$RepoPath, [string]$Plan, [string]$Goal, [int]$Stages, [string]$StagesText, [string]$RuntimeName, [string]$SpawnRule, [string]$RuleFiles)
  $t = [string]$Text
  $t = $t.Replace('{{REPO_ROOT}}', $RepoPath)
  $t = $t.Replace('{{REPO}}', $RepoPath)
  $t = $t.Replace('{{REPO_NAME}}', $RepoName)
  $t = $t.Replace('{{PLAN_DOC}}', $Plan)
  $t = $t.Replace('{{TARGET}}', $Goal)
  $t = $t.Replace('{{MAX_STAGES}}', [string]$Stages)
  $t = $t.Replace('{{STAGE_LIST}}', $StagesText)
  $t = $t.Replace('{{RUNTIME}}', $RuntimeName)
  $t = $t.Replace('{{SPAWN_RULE}}', $SpawnRule)
  $t = $t.Replace('{{RULE_FILES}}', $RuleFiles)
  $t = $t.Replace('{{DATE}}', (Get-Date -Format 'yyyy-MM-dd'))
  return $t
}

function Write-Utf8NoBom {
  param([string]$Path, [string]$Content)
  [IO.File]::WriteAllText($Path, [string]$Content, [Text.UTF8Encoding]::new($false))
}

function Get-FileStamp {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return 'absent' }
  $f = Get-Item -LiteralPath $Path
  $h = (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.Substring(0, 16)
  return "bytes=$($f.Length) sha16=$h"
}

function Install-File {
  param([string]$Src, [string]$Dst, [string]$Label)
  if (-not (Test-Path -LiteralPath $Src)) { Warn "$Label template_missing src=$Src"; return 'missing' }
  if (Test-Path -LiteralPath $Dst) {
    $ha = (Get-FileHash -Algorithm SHA256 -LiteralPath $Src).Hash
    $hb = (Get-FileHash -Algorithm SHA256 -LiteralPath $Dst).Hash
    if ($ha -eq $hb) {
      Log "SKIP $Label identical bytes=$((Get-Item -LiteralPath $Dst).Length)"
      return 'identical'
    }
    if (-not $Force) { Warn "$Label exists_different kept hint=rerun_with_-Force"; return 'kept' }
  }
  Copy-Item -LiteralPath $Src -Destination $Dst -Force
  $h = (Get-FileHash -Algorithm SHA256 -LiteralPath $Dst).Hash
  Log "COPY $Label bytes=$((Get-Item -LiteralPath $Dst).Length) sha16=$($h.Substring(0,16))"
  return 'copied'
}

# --- 0. runtime selection ------------------------------------------------------
# The runtime decides two things: which instruction files carry the managed rule
# block, and how the next link is started. An unknown runtime is a loud failure,
# never a silent fallback to the default.
$knownRuntimes = @('mcode', 'claude-code', 'codex', 'openclaw')
if ($knownRuntimes -notcontains $Runtime) {
  Write-Host ("FAIL reason=runtime_unsupported runtime=" + $Runtime + " known=" + ($knownRuntimes -join ','))
  exit 2
}
$spawnTplPath = Join-Path $templateDir ('ACTIVATION-SPAWN-' + $Runtime + '.md')
if (-not (Test-Path -LiteralPath $spawnTplPath -PathType Leaf)) {
  Write-Host ("FAIL reason=runtime_spawn_template_missing runtime=" + $Runtime + " path=" + $spawnTplPath)
  exit 2
}
$spawnTplText = Read-TextOrEmpty -Path $spawnTplPath
$spawnRuleMatch = [regex]::Match($spawnTplText, '(?s)<!-- SPAWN_RULE_BEGIN -->(.*?)<!-- SPAWN_RULE_END -->')
if (-not $spawnRuleMatch.Success) {
  Write-Host ("FAIL reason=runtime_spawn_rule_missing runtime=" + $Runtime)
  exit 2
}
$spawnRule = $spawnRuleMatch.Groups[1].Value.Trim()

# --- 1. resolve the target repository ----------------------------------------
if (-not (Test-Path -LiteralPath $RepoRoot -PathType Container)) {
  Write-Host "FAIL reason=repo_missing path=$RepoRoot"
  exit 2
}
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
$gitTop = (& git -C $repo rev-parse --show-toplevel 2>$null)
if ([string]::IsNullOrWhiteSpace($gitTop)) {
  Write-Host "FAIL reason=not_a_git_repo path=$repo"
  exit 2
}
$repo = (Resolve-Path -LiteralPath ($gitTop.Trim() -replace '/', '\')).Path
if ([string]::IsNullOrWhiteSpace($WorkspaceDir)) { $WorkspaceDir = $repo }
$repoName = Split-Path -Leaf $repo
Log "REPO root=$repo"
Log "REPO name=$repoName"
Log "REPO head=$((& git -C $repo rev-parse --short HEAD).Trim())"
Log ("RUNTIME name=" + $Runtime + " spawn_template=" + (Split-Path -Leaf $spawnTplPath))

# --- 2. resolve the plan doc ---------------------------------------------------
$planRel = ''
$planWillBeCreated = $false
if (-not [string]::IsNullOrWhiteSpace($PlanDoc)) {
  $p = $PlanDoc
  if (-not [IO.Path]::IsPathRooted($p)) { $p = Join-Path $repo $p }
  if (-not (Test-Path -LiteralPath $p -PathType Leaf)) {
    Write-Host "FAIL reason=plan_doc_missing path=$p"
    exit 2
  }
  $planRel = Get-RelPath -Base $repo -Full (Resolve-Path -LiteralPath $p).Path
} else {
  $cands = New-Object System.Collections.Generic.List[string]
  foreach ($pat in @('docs\plan-*.md', 'docs\plans\*.md', 'docs\superpowers\plans\*.md')) {
    $hits = @(Get-ChildItem -Path (Join-Path $repo $pat) -File -ErrorAction SilentlyContinue)
    foreach ($h in $hits) { $cands.Add($h.FullName) }
  }
  $uniq = @($cands | Sort-Object -Unique)
  if ($uniq.Count -eq 1) {
    $planRel = Get-RelPath -Base $repo -Full $uniq[0]
  } else {
    if ($uniq.Count -gt 1) { Warn "plan_doc_ambiguous candidates=$($uniq.Count) fallback=docs\plan-relay.md" }
    $planRel = 'docs\plan-relay.md'
    $planWillBeCreated = $true
  }
}
Log "PLAN doc=$planRel created=$planWillBeCreated"

# --- 3. stage list ------------------------------------------------------------
$stageList = New-Object System.Collections.Generic.List[string]
if ([string]::IsNullOrWhiteSpace($StageTitles)) {
  $stageList.Add('1. scope inventory and acceptance criteria')
  $stageList.Add('2. implementation against the declared write set')
  $stageList.Add('3. verification, evidence and gate run')
  $stageList.Add('4. closeout, handoff and ledger writeback')
} else {
  foreach ($s in ($StageTitles -split ';')) {
    $t = $s.Trim()
    if ($t.Length -gt 0) { $stageList.Add($t) }
  }
}
if ($stageList.Count -eq 0) { $stageList.Add('1. stage 1 scope inventory') }
$stageText = ($stageList -join "`n")

# --- 4. install the device ----------------------------------------------------
$docsDir  = Join-Path $repo 'docs'
$relayDir = Join-Path $docsDir 'relay'
New-Item -ItemType Directory -Force -Path $relayDir | Out-Null

$relayLockPath = Join-Path $relayDir 'relay-lock.ps1'
$relayStartPath = Join-Path $relayDir 'start-relay.ps1'
$relayLedgerPath = Join-Path $relayDir 'relay-ledger.ps1'
$relaySpawnPath = Join-Path $relayDir 'relay-spawn.ps1'
$agentRelayPath = Join-Path $docsDir 'AGENT-RELAY.md'
$sopPath = Join-Path $docsDir 'RELAY-SOP.md'
$adaptPath = Join-Path $docsDir 'RELAY-ADAPTATION.md'
$ledgerPath = Join-Path $docsDir 'relay.json'
$activationPath = Join-Path $relayDir 'ACTIVATION-PROMPT.txt'
$reportPath = Join-Path $relayDir 'install-report.md'

Install-File -Src (Join-Path $templateDir 'relay-lock.ps1') -Dst $relayLockPath -Label 'relay-lock.ps1' | Out-Null
Install-File -Src (Join-Path $templateDir 'start-relay.ps1') -Dst $relayStartPath -Label 'start-relay.ps1' | Out-Null
Install-File -Src (Join-Path $templateDir 'relay-ledger.ps1') -Dst $relayLedgerPath -Label 'relay-ledger.ps1' | Out-Null
Install-File -Src (Join-Path $templateDir 'relay-spawn.ps1') -Dst $relaySpawnPath -Label 'relay-spawn.ps1' | Out-Null
Install-File -Src (Join-Path $templateDir 'AGENT-RELAY.md') -Dst $agentRelayPath -Label 'AGENT-RELAY.md' | Out-Null
if (Test-Path -LiteralPath (Join-Path $templateDir 'RELAY-SOP.md')) {
  Install-File -Src (Join-Path $templateDir 'RELAY-SOP.md') -Dst $sopPath -Label 'RELAY-SOP.md' | Out-Null
}

# --- 5. plan doc (only when it is ours to create) ----------------------------
$planPath = Join-Path $repo $planRel
if ($planWillBeCreated -and -not (Test-Path -LiteralPath $planPath)) {
  $planDir = Split-Path -Parent $planPath
  if (-not (Test-Path -LiteralPath $planDir)) { New-Item -ItemType Directory -Force -Path $planDir | Out-Null }
  $planText = @"
# Relay plan: $Target

- installed: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
- repo: $repo
- runtime: $Runtime
- max_stages: $MaxStages
- protocol: docs/AGENT-RELAY.md
- adjudication: docs/RELAY-ADAPTATION.md

## Stages

$stageText

## Acceptance

TODO: fill the acceptance criteria of every stage before activating the chain.
This plan doc is the source of truth that each stage of the chain reads.
"@
  Write-Utf8NoBom -Path $planPath -Content $planText
  Log "CREATE plan_doc path=$planRel bytes=$((Get-Item -LiteralPath $planPath).Length)"
}

# --- 6. project adjudication skeleton ----------------------------------------
# Which instruction files carry the managed rule block. Claude Code reads CLAUDE.md
# first and only falls back to AGENTS.md when the repo has NO CLAUDE.md, so a repo that
# already ships a CLAUDE.md would shadow the whole relay block: the kit would look
# installed while the chain never starts. Hence claude-code writes both files.
$ruleTargets = New-Object System.Collections.Generic.List[object]
$ruleTargets.Add([pscustomobject]@{ Path = (Join-Path $repo 'AGENTS.md'); Label = 'AGENTS'; Markers = 'AGENTS_MARKERS' })
if ($Runtime -eq 'claude-code') {
  $ruleTargets.Add([pscustomobject]@{ Path = (Join-Path $repo 'CLAUDE.md'); Label = 'CLAUDE'; Markers = 'CLAUDE_MARKERS' })
}
$ruleFilesText = (($ruleTargets | ForEach-Object { Split-Path -Leaf $_.Path }) -join ', ')

$adaptSrc = Join-Path $templateDir 'RELAY-ADAPTATION.md'
if (Test-Path -LiteralPath $adaptSrc) {
  $adaptText = Expand-Template -Text (Read-TextOrEmpty -Path $adaptSrc) -RepoName $repoName -RepoPath $repo -Plan $planRel -Goal $Target -Stages $MaxStages -StagesText $stageText -RuntimeName $Runtime -SpawnRule $spawnRule -RuleFiles $ruleFilesText
  if (Test-Path -LiteralPath $adaptPath) {
    if ($Force) {
      Write-Utf8NoBom -Path $adaptPath -Content $adaptText
      Log "COPY RELAY-ADAPTATION.md replaced bytes=$((Get-Item -LiteralPath $adaptPath).Length)"
    } else {
      Log "SKIP RELAY-ADAPTATION.md exists kept (project edited it; fill the TODO sections in place)"
    }
  } else {
    Write-Utf8NoBom -Path $adaptPath -Content $adaptText
    Log "COPY RELAY-ADAPTATION.md bytes=$((Get-Item -LiteralPath $adaptPath).Length)"
  }
}

# --- 7. managed rule block -----------------------------------------------------
$blockSrc = Join-Path $templateDir 'AGENTS-RELAY-BLOCK.md'
$beginMark = '<!-- BEGIN RELAY-PORT -->'
$endMark = '<!-- END RELAY-PORT -->'
$blockText = Expand-Template -Text (Read-TextOrEmpty -Path $blockSrc) -RepoName $repoName -RepoPath $repo -Plan $planRel -Goal $Target -Stages $MaxStages -StagesText $stageText -RuntimeName $Runtime -SpawnRule $spawnRule -RuleFiles $ruleFilesText

function Install-RuleBlock {
  param([string]$Path, [string]$BlockText, [string]$BeginMark, [string]$EndMark)
  $before = Get-FileStamp -Path $Path
  $hasBom = $false
  if (Test-Path -LiteralPath $Path -PathType Leaf) {
    $rawBytes = [IO.File]::ReadAllBytes($Path)
    $hasBom = ($rawBytes.Length -ge 3 -and $rawBytes[0] -eq 0xEF -and $rawBytes[1] -eq 0xBB -and $rawBytes[2] -eq 0xBF)
  }
  $existing = Read-TextOrEmpty -Path $Path
  $eol = if ($existing.Contains("`r`n")) { "`r`n" } else { "`n" }
  $blockNorm = (($BlockText -replace "`r`n", "`n") -replace "`n", $eol)
  $action = 'none'
  $reason = ''
  $out = $existing
  $dirty = $false
  $hasBegin = $existing.Contains($BeginMark)
  $hasEnd = $existing.Contains($EndMark)

  if ($hasBegin -and $hasEnd) {
    $rx = [regex]::Escape($BeginMark) + '.*?' + [regex]::Escape($EndMark)
    $m = [regex]::Match($existing, $rx, [System.Text.RegularExpressions.RegexOptions]::Singleline)
    if ($m.Success) {
      if ($Force) {
        $out = $existing.Substring(0, $m.Index) + $blockNorm + $existing.Substring($m.Index + $m.Length)
        $dirty = $true
        $action = 'replaced'
      } else {
        $action = 'present_kept'
      }
    } else {
      $action = 'present_unparsed'
    }
  } else {
    if ($hasBegin -or $hasEnd) {
      Warn 'agents_markers_corrupt stray_marker_removed'
      $existing = $existing.Replace($BeginMark, '').Replace($EndMark, '')
      $out = $existing
    }
    # Locate the project's own relay section. Two detectors, in order:
    #   1) the heading names it (Relay / the CJK word for "relay"), which is the
    #      cheap and unambiguous case;
    #   2) failing that, a content fingerprint per level-2 section, because a
    #      hand-written section is often titled after something else entirely.
    #      Without (2) such a project got a second, duplicated rule block.
    $secStart = -1
    $secEnd = -1
    $hm = [regex]::Match($existing, '(?m)^##\s+.*(?:Relay|\u63A5\u529B).*$')
    if ($hm.Success) {
      $reason = 'title'
      $secStart = $hm.Index
      $tail = $existing.Substring($hm.Index + $hm.Length)
      $nm = [regex]::Match($tail, '(?m)^##\s')
      $secEnd = if ($nm.Success) { $hm.Index + $hm.Length + $nm.Index } else { $existing.Length }
    } else {
      $relaySignals = @(
        @{ n = 'relay.json';     r = 'relay\.json' },
        @{ n = 'relay-lock';     r = 'relay-lock\.ps1' },
        @{ n = 'start-relay';    r = 'start-relay\.ps1' },
        @{ n = 'relay-ledger';   r = 'relay-ledger\.ps1' },
        @{ n = 'AGENT-RELAY';    r = 'AGENT-RELAY' },
        @{ n = 'activation';     r = 'ACTIVATION-PROMPT' },
        @{ n = 'session_create'; r = 'session_create' },
        @{ n = 'in_progress';    r = 'in_progress' },
        @{ n = 'max_stages';     r = 'max_stages' },
        @{ n = 'next_session';   r = 'next_session_id' },
        @{ n = 'awaiting_user';  r = 'awaiting_user' }
      )
      $heads = @([regex]::Matches($existing, '(?m)^##\s.*$'))
      $qualified = New-Object System.Collections.Generic.List[object]
      for ($i = 0; $i -lt $heads.Count; $i++) {
        $s = $heads[$i].Index
        $e = if ($i -lt $heads.Count - 1) { $heads[$i + 1].Index } else { $existing.Length }
        $body = $existing.Substring($s, $e - $s)
        $hit = @($relaySignals | Where-Object { $body -match $_.r })
        if ($hit.Count -ge 4) {
          $qualified.Add([pscustomobject]@{
            Start   = $s
            End     = $e
            Signals = $hit.Count
            Names   = (($hit | ForEach-Object { $_.n }) -join '+')
          })
        }
      }
      if ($qualified.Count -eq 1) {
        $reason = 'content_signature count=' + $qualified[0].Signals + ' signals=' + $qualified[0].Names
        $secStart = [int]$qualified[0].Start
        $secEnd = [int]$qualified[0].End
      } elseif ($qualified.Count -gt 1) {
        # Do not guess which of several sections is "the" relay section: append
        # the managed block and let a human collapse the duplicates.
        Warn "agents_relay_section_ambiguous matches=$($qualified.Count) appended_managed_block review=keep_a_single_relay_section"
      }
    }
    if ($secStart -ge 0) {
      $section = ($existing.Substring($secStart, $secEnd - $secStart) -replace "`r`n", "`n")
      $section = $section -replace "`n", $eol
      $out = $existing.Substring(0, $secStart) + $BeginMark + $eol + $eol + $section + $eol + $EndMark + $eol + $eol + $existing.Substring($secEnd)
      $dirty = $true
      $action = 'adopted'
    } else {
      $sep = if ($existing.Length -gt 0) { $eol + $eol } else { '' }
      $out = $existing + $sep + $blockNorm + $eol
      $dirty = $true
      $action = 'appended'
    }
  }

  if ($dirty) {
    if ($hasBom) {
      [IO.File]::WriteAllText($Path, $out, [Text.UTF8Encoding]::new($true))
    } else {
      Write-Utf8NoBom -Path $Path -Content $out
    }
  }
  $after = Get-FileStamp -Path $Path
  return [pscustomobject]@{ Action = $action; Reason = $reason; Before = $before; After = $after; Bom = $hasBom }
}

foreach ($t in $ruleTargets) {
  $res = Install-RuleBlock -Path $t.Path -BlockText $blockText -BeginMark $beginMark -EndMark $endMark
  $reasonText = $res.Reason
  if ([string]::IsNullOrWhiteSpace($reasonText)) { $reasonText = 'n/a' }
  Log ($t.Label + " action=" + $res.Action + " reason=" + $reasonText + " before=[" + $res.Before + "] after=[" + $res.After + "] bom=" + $res.Bom)
}

# --- 8. activation packet -----------------------------------------------------
$actSrc = Join-Path $templateDir 'ACTIVATION-PROMPT.md'
if (Test-Path -LiteralPath $actSrc) {
  $actText = Expand-Template -Text (Read-TextOrEmpty -Path $actSrc) -RepoName $repoName -RepoPath $repo -Plan $planRel -Goal $Target -Stages $MaxStages -StagesText $stageText -RuntimeName $Runtime -SpawnRule $spawnRule -RuleFiles $ruleFilesText
  $spawnText = Expand-Template -Text $spawnTplText -RepoName $repoName -RepoPath $repo -Plan $planRel -Goal $Target -Stages $MaxStages -StagesText $stageText -RuntimeName $Runtime -SpawnRule $spawnRule -RuleFiles $ruleFilesText
  $actText = $actText.Replace('{{SPAWN_STEPS}}', ($spawnText -replace "`r`n", "`n"))
  Write-Utf8NoBom -Path $activationPath -Content ($actText -replace "`r`n", "`n")
  Log "WRITE ACTIVATION-PROMPT.txt bytes=$((Get-Item -LiteralPath $activationPath).Length)"
}

# --- 9. ledger must stay untouched --------------------------------------------
if (Test-Path -LiteralPath $ledgerPath) {
  Log "LEDGER exists left_untouched bytes=$((Get-Item -LiteralPath $ledgerPath).Length)"
} else {
  Log "LEDGER absent (the launcher creates it at activation; the installer never writes it)"
}

# --- 10. self check -----------------------------------------------------------
$verdict = 'PASS'
if (-not $SkipVerify) {
  foreach ($f in @($relayLockPath, $relayStartPath, $relaySpawnPath)) {
    if (-not (Test-Path -LiteralPath $f)) { Log "ASCII_CHECK file=$([IO.Path]::GetFileName($f)) missing=true"; $verdict = 'FAIL'; continue }
    $bytes = [IO.File]::ReadAllBytes($f)
    $nonAscii = 0
    foreach ($b in $bytes) { if ($b -gt 127) { $nonAscii++ } }
    $bom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    Log "ASCII_CHECK file=$([IO.Path]::GetFileName($f)) non_ascii=$nonAscii bom=$bom bytes=$($bytes.Length)"
    if ($nonAscii -gt 0 -or $bom) { $verdict = 'FAIL' }
  }

  foreach ($t in $ruleTargets) {
    $now = Read-TextOrEmpty -Path $t.Path
    $bc = ([regex]::Matches($now, [regex]::Escape($beginMark))).Count
    $ec = ([regex]::Matches($now, [regex]::Escape($endMark))).Count
    Log ($t.Markers + ' begin=' + $bc + ' end=' + $ec)
    if ($bc -ne 1 -or $ec -ne 1) { $verdict = 'FAIL' }
  }

  $lockOut = & $relayLockPath -Action status *>&1
  $lockExit = $LASTEXITCODE
  Log "LOCK_STATUS exit=$lockExit line=$(($lockOut | Select-Object -First 1))"

  $dryOut = & $relayStartPath -Target $Target -PlanDoc $planRel -MaxStages $MaxStages -WorkspaceDir $WorkspaceDir -DryRun *>&1
  $dryExit = $LASTEXITCODE
  $dryText = ($dryOut | ForEach-Object { [string]$_ }) -join "`n"
  $dryPath = Join-Path $relayDir 'install-dryrun.txt'
  Write-Utf8NoBom -Path $dryPath -Content ($dryText + "`n")
  if ($dryExit -eq 0) {
    Log "DRYRUN exit=0 verdict=OK artifact=$dryPath"
  } elseif ($dryExit -eq 3) {
    Warn "dryrun_gate_refused exit=3 (a chain is already running / ledger blocked or exhausted) artifact=$dryPath"
  } elseif ($dryExit -eq 4) {
    Warn "dryrun_lock_held exit=4 (another session owns the lock) artifact=$dryPath"
  } else {
    Log "DRYRUN exit=$dryExit verdict=FAIL artifact=$dryPath"
    $verdict = 'FAIL'
  }
} else {
  Log 'VERIFY skipped=true'
}

# --- 11. report ---------------------------------------------------------------
$md = New-Object System.Collections.Generic.List[string]
$md.Add('# Relay kit install report')
$md.Add('')
$md.Add("- installed_at: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
$md.Add("- tool: relay-port skill ($skillRoot)")
$md.Add("- repo: $repo")
$md.Add("- runtime: $Runtime")
$md.Add("- rule_files: $ruleFilesText")
$md.Add("- target: $Target")
$md.Add("- plan_doc: $planRel")
$md.Add("- max_stages: $MaxStages")
$md.Add("- verdict: $verdict")
$md.Add('')
$md.Add('## Console log')
$md.Add('')
$md.Add('```')
foreach ($l in $reportLines) { $md.Add($l) }
$md.Add('```')
if ($warnLines.Count -gt 0) {
  $md.Add('')
  $md.Add('## Warnings')
  $md.Add('')
  foreach ($w in $warnLines) { $md.Add("- $w") }
}
$md.Add('')
$md.Add('## Next step')
$md.Add('')
$zhAct = -join [char[]](0x6309)
$zhChain = -join [char[]](0x542F,0x52A8,0x63A5,0x529B,0x94FE)
$md.Add('Open a session whose workspace IS this repo and say:')
$md.Add('')
$md.Add('    ' + $zhAct + ' docs\relay\ACTIVATION-PROMPT.txt ' + $zhChain)
$md.Add('')
$md.Add('Before that, fill the TODO sections of docs\RELAY-ADAPTATION.md (write set, gate, model policy).')
Write-Utf8NoBom -Path $reportPath -Content ((($md -join "`n")) + "`n")

Write-Host "INSTALL_VERDICT=$verdict"
Write-Host "INSTALL_REPORT=$reportPath"
Write-Host "ACTIVATION_PROMPT=$activationPath"
Write-Host "INSTALL_RUNTIME=$Runtime"
Write-Host "WARN_COUNT=$($warnLines.Count)"
if ($verdict -ne 'PASS') { exit 5 }
exit 0
