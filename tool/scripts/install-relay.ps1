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
  [string]$AnswersFile = '',
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
  param([string]$Text, [string]$RepoName, [string]$RepoPath, [string]$Plan, [string]$Goal, [int]$Stages, [string]$StagesText, [string]$RuntimeName, [string]$SpawnRule, [string]$RuleFiles, [string]$SpawnCommand, $Adapt = $null)
  $t = [string]$Text
  # The spawn command is substituted FIRST on purpose: the block it carries still
  # holds {{REPO}} placeholders, and the replacements below expand those too.
  $t = $t.Replace('{{SPAWN_COMMAND}}', $SpawnCommand)
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
  # Sections 3/4/5 of the adjudication doc used to ship as TODO. They are now filled
  # from a probe (or from an answers file). Every one of these placeholders is replaced
  # unconditionally when a value set is supplied: a doc that still shows {{...}} is a
  # kit bug, and the install check below fails loudly on it.
  if ($null -ne $Adapt) {
    $t = $t.Replace('{{WRITE_SET_ALLOW}}', (Format-BulletList -Items $Adapt['write_set_allow'] -Indent '  '))
    $t = $t.Replace('{{WRITE_SET_DENY}}', (Format-BulletList -Items $Adapt['write_set_deny'] -Indent '  '))
    $t = $t.Replace('{{CONCURRENCY_CHECK}}', [string]$Adapt['concurrency_check'])
    $t = $t.Replace('{{GATE_COMMAND}}', [string]$Adapt['gate_command'])
    $t = $t.Replace('{{GATE_VERDICT_FIELD}}', [string]$Adapt['gate_verdict_field'])
    $t = $t.Replace('{{MODEL_PRIMARY}}', [string]$Adapt['model_primary'])
    $t = $t.Replace('{{MODEL_FALLBACK_DAY}}', [string]$Adapt['model_fallback_day'])
    $t = $t.Replace('{{MODEL_FALLBACK_NIGHT}}', [string]$Adapt['model_fallback_night'])
    $t = $t.Replace('{{ADAPTATION_SOURCE}}', [string]$Adapt['ADAPTATION_SOURCE'])
  }
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

# --- adaptation probe ----------------------------------------------------------
# Sections 3/4/5 of docs\RELAY-ADAPTATION.md used to ship as TODO placeholders, so
# every install left the same three questions open. They are now PROBED here, rendered
# into the doc, and re-rendered from an answers file (-AnswersFile). A probe value is a
# guess, never a confirmation: the doc records the source and the packet below carries
# the questions a managed agent has to ask before the chain may start.

function Get-WriteSetProbe {
  param([string]$Repo)
  $skip = @('.github', 'node_modules', 'dist', 'build', 'out', 'bin', 'obj', '.venv', 'venv', '.idea', '.vscode', 'coverage', '.next', 'target', 'vendor')
  $set = New-Object System.Collections.Generic.HashSet[string]
  if (Test-Path -LiteralPath (Join-Path $Repo '.git')) {
    $tracked = @()
    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { $tracked = @(git -C $Repo ls-files 2>$null) } catch { $tracked = @() } finally { $ErrorActionPreference = $prevEap }
    if ($LASTEXITCODE -ne 0) { $tracked = @() }
    foreach ($p in $tracked) {
      if ([string]::IsNullOrWhiteSpace($p)) { continue }
      $norm = ([string]$p).Replace('\', '/')
      $i = $norm.IndexOf('/')
      if ($i -lt 1) { continue }
      $top = $norm.Substring(0, $i)
      if ($skip -contains $top) { continue }
      [void]$set.Add($top)
    }
  }
  if ($set.Count -eq 0) { return @() }
  $arr = @($set)
  [Array]::Sort($arr, [System.StringComparer]::Ordinal)
  return @($arr | ForEach-Object { $_ + '\' })
}

function Find-GateScript {
  param([string]$Repo)
  $roots = @(
    @{ Dir = ''; Depth = 0 },
    @{ Dir = 'scripts'; Depth = 2 },
    @{ Dir = 'reports'; Depth = 2 },
    @{ Dir = 'tools'; Depth = 2 },
    @{ Dir = 'ci'; Depth = 2 }
  )
  $cand = New-Object System.Collections.Generic.List[object]
  foreach ($r in $roots) {
    $dir = if ($r.Dir -eq '') { $Repo } else { Join-Path $Repo $r.Dir }
    if (-not (Test-Path -LiteralPath $dir -PathType Container)) { continue }
    $items = @(Get-ChildItem -LiteralPath $dir -Recurse -Depth $r.Depth -Filter '*gate*.ps1' -File -ErrorAction SilentlyContinue)
    foreach ($it in $items) {
      $rel = Get-RelPath -Base $Repo -Full $it.FullName
      $cand.Add([pscustomobject]@{ Rel = $rel; Depth = ($rel.Split('\').Count); Len = $rel.Length })
    }
  }
  if ($cand.Count -gt 0) {
    $best = @($cand | Sort-Object Depth, Len)[0]
    return [string]$best.Rel
  }
  if (Test-Path -LiteralPath (Join-Path $Repo 'scripts\selftest.ps1') -PathType Leaf) { return 'scripts\selftest.ps1' }
  return ''
}

function Get-AdaptationProbe {
  param([string]$Repo)
  $gate = Find-GateScript -Repo $Repo
  if ([string]::IsNullOrWhiteSpace($gate)) { $gate = 'none' }
  return [ordered]@{
    write_set_allow      = @(Get-WriteSetProbe -Repo $Repo)
    write_set_deny       = @(
      '.github\workflows\'
      '**\.env*'
      '**\*.key'
      '**\*.pem'
      '**\*.pfx'
      'scripts\publish-*'
      'scripts\release-*'
      'scripts\deploy-*'
      'scripts\sign-*'
      '**\gate*.ps1'
      'docs\relay\*.ps1'
    )
    concurrency_check    = 'pwsh -NoProfile -ExecutionPolicy Bypass -File docs\relay\relay-lock.ps1 -Action status'
    gate_command         = $gate
    gate_verdict_field   = 'none'
    model_primary        = 'minimax/MiniMax-M3'
    model_fallback_day   = 'custom_provider:provider-aa5659/auto'
    model_fallback_night = 'custom_provider:provider-aa5659/deepseek-v4.1-flash-1017'
  }
}

function Format-BulletList {
  param($Items, [string]$Indent)
  $arr = @($Items)
  if ($arr.Count -eq 0) { return ($Indent + '- `none` (nothing detected: fill this by hand)') }
  $out = New-Object System.Collections.Generic.List[string]
  foreach ($i in $arr) { $out.Add($Indent + '- `' + [string]$i + '`') }
  return (($out) -join "`n")
}

function Split-Section {
  param([string]$Text, [int]$Number)
  $m = [regex]::Match($Text, '(?m)^##\s+' + $Number + '\..*$')
  if (-not $m.Success) { return '' }
  $rest = $Text.Substring($m.Index + $m.Length)
  $nm = [regex]::Match($rest, '(?m)^##\s')
  $len = if ($nm.Success) { $m.Length + $nm.Index } else { $Text.Length - $m.Index }
  return $Text.Substring($m.Index, $len)
}

function Update-AdaptationSections {
  param([string]$Path, [string]$RenderedText, [int[]]$Numbers)
  $cur = Read-TextOrEmpty -Path $Path
  if ([string]::IsNullOrWhiteSpace($cur)) {
    return [pscustomobject]@{ Applied = @(); Missing = @($Numbers) }
  }
  $eol = if ($cur.Contains("`r`n")) { "`r`n" } else { "`n" }
  $out = $cur
  $applied = New-Object System.Collections.Generic.List[int]
  $missing = New-Object System.Collections.Generic.List[int]
  foreach ($n in $Numbers) {
    $new = Split-Section -Text $RenderedText -Number $n
    if ([string]::IsNullOrWhiteSpace($new)) { $missing.Add($n); continue }
    $m = [regex]::Match($out, '(?m)^##\s+' + $n + '\..*$')
    if (-not $m.Success) { $missing.Add($n); continue }
    $rest = $out.Substring($m.Index + $m.Length)
    $nm = [regex]::Match($rest, '(?m)^##\s')
    $len = if ($nm.Success) { $m.Length + $nm.Index } else { $out.Length - $m.Index }
    $flat = (($new -replace "`r`n", "`n").TrimEnd()) -replace "`n", $eol
    $out = $out.Substring(0, $m.Index) + $flat + $eol + $eol + $out.Substring($m.Index + $len)
    $applied.Add($n)
  }
  if ($applied.Count -gt 0) { Write-Utf8NoBom -Path $Path -Content $out }
  return [pscustomobject]@{ Applied = @($applied); Missing = @($missing) }
}

function Write-AdaptationAnswersTemplate {
  param([string]$Path, $Defaults)
  $obj = [ordered]@{
    schema               = 'relay-port/adaptation-answers@1'
    write_set_allow      = @($Defaults.write_set_allow)
    write_set_deny       = @($Defaults.write_set_deny)
    concurrency_check    = [string]$Defaults.concurrency_check
    gate_command         = [string]$Defaults.gate_command
    gate_verdict_field   = [string]$Defaults.gate_verdict_field
    model_primary        = [string]$Defaults.model_primary
    model_fallback_day   = [string]$Defaults.model_fallback_day
    model_fallback_night = [string]$Defaults.model_fallback_night
    confirmed_by         = 'REPLACE_WITH_USER_CONFIRMATION'
    confirmed_at         = (Get-Date -Format 'yyyy-MM-dd')
  }
  Write-Utf8NoBom -Path $Path -Content ((($obj | ConvertTo-Json -Depth 5)) -replace "`r`n", "`n")
}

function Write-AdaptationQuestionPacket {
  param([string]$Dir, [string]$SpecPath, $Defaults, [string]$Repo = '')
  $relayPacket = Join-Path $Dir 'adaptation-questions.md'
  $jsonPacket = Join-Path $Dir 'adaptation-questions.json'
  $answersTpl = Join-Path $Dir 'adaptation-answers.template.json'
  if (-not (Test-Path -LiteralPath $SpecPath -PathType Leaf)) {
    return [pscustomobject]@{ Md = ''; Json = ''; Answers = ''; Questions = 0 }
  }
  $spec = (Read-TextOrEmpty -Path $SpecPath) | ConvertFrom-Json
  $render = $spec.render
  $lines = New-Object System.Collections.Generic.List[string]
  $lines.Add('# ' + [string]$spec.title)
  $lines.Add('')
  foreach ($chunk in ([string]$spec.intro -split "`n")) { $lines.Add($chunk) }
  $lines.Add('')
  $questions = @($spec.questions)
  foreach ($g in @($spec.groups)) {
    $lines.Add('## ' + [string]$g.title)
    $lines.Add('')
    $lines.Add('> ' + [string]$g.ask_hint)
    $lines.Add('')
    foreach ($q in $questions) {
      if ([string]$q.group -ne [string]$g.id) { continue }
      $val = $Defaults[[string]$q.answer_key]
      $lines.Add('### ' + [string]$q.label)
      $lines.Add('')
      $lines.Add('- ' + [string]$render.answer_key_label + ': `' + [string]$q.answer_key + '`')
      $lines.Add('- ' + [string]$render.type_label + ': `' + [string]$q.type + '`')
      $lines.Add('- ' + [string]$render.default_label + ':')
      if ($q.type -eq 'list') {
        foreach ($v in @($val)) { $lines.Add('  - `' + [string]$v + '`') }
      } else {
        $lines.Add('  - `' + [string]$val + '`')
      }
      $lines.Add('- ' + [string]$render.question_label + ': ' + [string]$q.prompt)
      $lines.Add('- ' + [string]$render.hint_label + ': ' + [string]$q.hint)
      $lines.Add('')
    }
  }
  $lines.Add('---')
  $lines.Add('')
  foreach ($chunk in ([string]$render.footer -split "`n")) { $lines.Add($chunk) }
  Write-Utf8NoBom -Path $relayPacket -Content ((($lines -join "`n")) + "`n")

  $jsonObj = [ordered]@{
    schema       = [string]$spec.schema
    generated_at = (Get-Date).ToString('o')
    repo         = $Repo
    questions    = @($questions | ForEach-Object {
      [ordered]@{
        id         = [string]$_.id
        group      = [string]$_.group
        section    = [int]$_.section
        answer_key = [string]$_.answer_key
        type       = [string]$_.type
        prompt     = [string]$_.prompt
        default    = $Defaults[[string]$_.answer_key]
      }
    })
  }
  Write-Utf8NoBom -Path $jsonPacket -Content ((($jsonObj | ConvertTo-Json -Depth 8)) -replace "`r`n", "`n")
  Write-AdaptationAnswersTemplate -Path $answersTpl -Defaults $Defaults
  return [pscustomobject]@{ Md = $relayPacket; Json = $jsonPacket; Answers = $answersTpl; Questions = $questions.Count }
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
# The spawn command is the single source of truth for "how the next link starts".
# It lives in the same shard as the rule text, so the two can never drift apart.
# The descriptor keeps a portable form ({REPO}); the activation packet expands it.
$spawnCommandMatch = [regex]::Match($spawnTplText, '(?s)<!-- SPAWN_COMMAND_BEGIN -->(.*?)<!-- SPAWN_COMMAND_END -->')
$spawnCommand = ''
$spawnCommandTpl = ''
if ($spawnCommandMatch.Success) {
  $spawnCommandTpl = $spawnCommandMatch.Groups[1].Value.Trim()
  $spawnCommand = $spawnCommandTpl.Replace('{{REPO}}', '{REPO}')
}

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
$adaptDefaults = Get-AdaptationProbe -Repo $repo
$adaptSource = 'defaults'
$adaptAnswersRel = ''
$adaptPacket = $null
if (-not [string]::IsNullOrWhiteSpace($AnswersFile)) {
  $ansPath = $AnswersFile
  if (-not [IO.Path]::IsPathRooted($ansPath)) { $ansPath = Join-Path $repo $ansPath }
  if (-not (Test-Path -LiteralPath $ansPath -PathType Leaf)) {
    Write-Host "FAIL reason=answers_file_missing path=$ansPath"
    exit 2
  }
  $ansPath = (Resolve-Path -LiteralPath $ansPath).Path
  $ans = $null
  try { $ans = (Read-TextOrEmpty -Path $ansPath) | ConvertFrom-Json } catch { $ans = $null }
  if ($null -eq $ans) {
    Write-Host "FAIL reason=answers_file_unparsable path=$ansPath"
    exit 2
  }
  $overlaid = 0
  foreach ($k in @($adaptDefaults.Keys)) {
    $prop = $ans.PSObject.Properties[$k]
    if ($null -eq $prop) { continue }
    $val = $prop.Value
    if ($null -eq $val) { continue }
    if ($val -is [string] -and [string]::IsNullOrWhiteSpace([string]$val)) { continue }
    if ($val -is [array] -and @($val).Count -eq 0) { continue }
    $adaptDefaults[$k] = $val
    $overlaid++
  }
  if ($overlaid -eq 0) {
    Write-Host "FAIL reason=answers_file_empty path=$ansPath"
    exit 2
  }
  $adaptSource = 'answers'
  $adaptAnswersRel = Get-RelPath -Base $repo -Full $ansPath
  Log ("ADAPT answers=" + $adaptAnswersRel + " applied=" + $overlaid + "/" + @($adaptDefaults.Keys).Count)
}
$adaptValues = [ordered]@{}
foreach ($k in @($adaptDefaults.Keys)) { $adaptValues[$k] = $adaptDefaults[$k] }
$adaptValues['ADAPTATION_SOURCE'] = $adaptSource
$adaptStatus = 'pending'
if ($adaptSource -eq 'answers') { $adaptStatus = 'confirmed' }

if (Test-Path -LiteralPath $adaptSrc) {
  $adaptText = Expand-Template -Text (Read-TextOrEmpty -Path $adaptSrc) -RepoName $repoName -RepoPath $repo -Plan $planRel -Goal $Target -Stages $MaxStages -StagesText $stageText -RuntimeName $Runtime -SpawnRule $spawnRule -RuleFiles $ruleFilesText -Adapt $adaptValues
  if (-not (Test-Path -LiteralPath $adaptPath)) {
    Write-Utf8NoBom -Path $adaptPath -Content $adaptText
    Log ("WRITE RELAY-ADAPTATION.md created source=" + $adaptSource + " bytes=" + (Get-Item -LiteralPath $adaptPath).Length)
  } elseif ($Force) {
    Write-Utf8NoBom -Path $adaptPath -Content $adaptText
    Log ("WRITE RELAY-ADAPTATION.md replaced source=" + $adaptSource + " bytes=" + (Get-Item -LiteralPath $adaptPath).Length)
  } elseif ($adaptSource -eq 'answers') {
    # A project edits its own adjudication doc. Only sections 3/4/5 belong to the
    # installer, so an answers rerun patches exactly those and leaves the rest alone.
    $sect = Update-AdaptationSections -Path $adaptPath -RenderedText $adaptText -Numbers @(3, 4, 5)
    Log ("PATCH RELAY-ADAPTATION.md sections=" + (@($sect.Applied) -join ',') + " missing=" + (@($sect.Missing) -join ',') + " answers=" + $adaptAnswersRel)
    if (@($sect.Missing).Count -gt 0) { Warn ("adaptation_sections_missing numbers=" + (@($sect.Missing) -join ',')) }
  } else {
    Log "SKIP RELAY-ADAPTATION.md exists kept (no -AnswersFile: the project adjudication stays authoritative)"
  }
  if (Test-Path -LiteralPath $adaptPath) {
    $adaptNow = Read-TextOrEmpty -Path $adaptPath
    $phLeft = ([regex]::Matches($adaptNow, '\{\{[A-Z_]+\}\}')).Count
    Log ("ADAPT_CHECK doc=" + (Get-RelPath -Base $repo -Full $adaptPath) + " placeholders=" + $phLeft + " source=" + $adaptSource)
    if ($phLeft -gt 0) { Warn "adaptation_placeholder_left count=$phLeft path=docs\RELAY-ADAPTATION.md" }
  }
} else {
  Warn 'adaptation_template_missing section_3_4_5_not_rendered'
}

# The packet is the hand-off to the asking agent. It is only meaningful while the
# values are unconfirmed: once an answers file is applied the doc itself is the record.
if ($adaptStatus -eq 'pending' -and (Test-Path -LiteralPath $adaptPath)) {
  $adaptPacket = Write-AdaptationQuestionPacket -Dir $relayDir -SpecPath (Join-Path $templateDir 'ADAPTATION-QUESTIONS.json') -Defaults $adaptDefaults -Repo $repo
  if ($adaptPacket.Questions -gt 0) {
    Log ("WRITE adaptation-questions.md questions=" + $adaptPacket.Questions + " path=" + (Get-RelPath -Base $repo -Full $adaptPacket.Md))
    Log ("WRITE adaptation-answers.template.json path=" + (Get-RelPath -Base $repo -Full $adaptPacket.Answers))
    Warn "adaptation_defaults_unconfirmed ask_the_user_before_starting_the_chain packet=docs\relay\adaptation-questions.md"
  } else {
    Warn 'adaptation_question_spec_missing packet_not_written'
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

# --- 7b. runtime descriptor ----------------------------------------------------
# The launcher reads this file to learn how the NEXT link is started. It is stamped
# at install time so the launcher never has to guess, and it never holds an absolute
# path: {REPO} is replaced with the launcher's own repo root when the prompt is built.
$descriptorPath = Join-Path $relayDir 'relay-runtime.json'
$nextLinkMode = 'session_tool'
if ($Runtime -eq 'claude-code' -or $Runtime -eq 'codex') { $nextLinkMode = 'cli_driver' }
elseif ($Runtime -eq 'openclaw') { $nextLinkMode = 'sessions_spawn_tool' }
$descriptor = [ordered]@{
  runtime        = $Runtime
  next_link_mode = $nextLinkMode
  spawn_rule     = $spawnRule
  spawn_command  = $spawnCommand
  rule_files     = @($ruleTargets | ForEach-Object { Split-Path -Leaf $_.Path })
  installed_at   = (Get-Date).ToString('o')
}
Write-Utf8NoBom -Path $descriptorPath -Content (($descriptor | ConvertTo-Json -Depth 5) -replace "`r`n", "`n")
Log "WRITE relay-runtime.json bytes=$((Get-Item -LiteralPath $descriptorPath).Length) mode=$nextLinkMode"

# --- 8. activation packet -----------------------------------------------------
$actSrc = Join-Path $templateDir 'ACTIVATION-PROMPT.md'
if (Test-Path -LiteralPath $actSrc) {
  $actText = Expand-Template -Text (Read-TextOrEmpty -Path $actSrc) -RepoName $repoName -RepoPath $repo -Plan $planRel -Goal $Target -Stages $MaxStages -StagesText $stageText -RuntimeName $Runtime -SpawnRule $spawnRule -RuleFiles $ruleFilesText -SpawnCommand $spawnCommandTpl
  $spawnText = Expand-Template -Text $spawnTplText -RepoName $repoName -RepoPath $repo -Plan $planRel -Goal $Target -Stages $MaxStages -StagesText $stageText -RuntimeName $Runtime -SpawnRule $spawnRule -RuleFiles $ruleFilesText -SpawnCommand $spawnCommandTpl
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
$md.Add('## Adaptation status')
$md.Add('')
$md.Add("- status: $adaptStatus")
$md.Add("- source: $adaptSource")
$md.Add('- doc: docs\RELAY-ADAPTATION.md')
$adaptQuestionsRel = ''
if ($null -ne $adaptPacket -and $adaptPacket.Questions -gt 0) {
  $adaptQuestionsRel = Get-RelPath -Base $repo -Full $adaptPacket.Md
  $md.Add("- questions: $adaptQuestionsRel")
  $md.Add('- answers_template: docs\relay\adaptation-answers.template.json')
}
$md.Add('')
$md.Add('## Next step')
$md.Add('')
$zhAct = -join [char[]](0x6309)
$zhChain = -join [char[]](0x542F,0x52A8,0x63A5,0x529B,0x94FE)
if ($adaptStatus -eq 'pending' -and $adaptQuestionsRel -ne '') {
  $md.Add('Do NOT start the chain yet. Sections 3/4/5 of docs\RELAY-ADAPTATION.md currently hold')
  $md.Add('probe defaults that nobody confirmed.')
  $md.Add('')
  $md.Add('1. Ask the user every question listed in ' + $adaptQuestionsRel + '.')
  $md.Add('2. Record the answers in docs\relay\adaptation-answers.json')
  $md.Add('   (same shape as docs\relay\adaptation-answers.template.json).')
  $md.Add('3. Re-run this installer with -AnswersFile docs\relay\adaptation-answers.json.')
  $md.Add('   Only sections 3/4/5 are rewritten; the rest of the doc is left alone. It prints')
  $md.Add('   ADAPTATION_STATUS=confirmed when the answers landed.')
  $md.Add('4. Open a session whose workspace IS this repo and say:')
} elseif ($adaptStatus -eq 'pending') {
  $md.Add('The adaptation values are unconfirmed and no question packet was written (template missing).')
  $md.Add('Fill sections 3/4/5 of docs\RELAY-ADAPTATION.md by hand, then open a session')
  $md.Add('whose workspace IS this repo and say:')
} else {
  $md.Add('The adaptation values were confirmed from ' + $adaptAnswersRel + '.')
  $md.Add('Open a session whose workspace IS this repo and say:')
}
$md.Add('')
$md.Add('    ' + $zhAct + ' docs\relay\ACTIVATION-PROMPT.txt ' + $zhChain)
Write-Utf8NoBom -Path $reportPath -Content ((($md -join "`n")) + "`n")

Write-Host "INSTALL_VERDICT=$verdict"
Write-Host "ADAPTATION_STATUS=$adaptStatus"
Write-Host "ADAPTATION_SOURCE=$adaptSource"
Write-Host "ADAPTATION_DOC=$(Get-RelPath -Base $repo -Full $adaptPath)"
Write-Host "ADAPTATION_QUESTIONS=$adaptQuestionsRel"
Write-Host "INSTALL_REPORT=$reportPath"
Write-Host "ACTIVATION_PROMPT=$activationPath"
Write-Host "INSTALL_RUNTIME=$Runtime"
Write-Host "WARN_COUNT=$($warnLines.Count)"
if ($verdict -ne 'PASS') { exit 5 }
exit 0
