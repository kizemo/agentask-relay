$ErrorActionPreference = 'Stop'

# B18 discriminating-power experiment for the link naming rule (case 23).
#
# The case 23 assertions read the GENERATED prompt. This script proves they have
# teeth: it builds the same fixture twice, once with the shipped template and
# once with a mutated template that goes back to the old naming
# (relay-1-<stage> instead of relay-01of02), and reports the hit counts of both
# patterns for each run.
#
# The mutation happens on a COPY in %TEMP%. The repository tree is never touched.
# Pure ASCII, no BOM.

$repoRoot = 'F:\soft\00selfmade\agentask-relay'
$tplDir   = Join-Path $repoRoot 'tool\templates'
$launcher = Join-Path $tplDir 'start-relay.ps1'

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$script:root = Join-Path $env:TEMP ('relay-b18-mutation-' + $stamp)
New-Item -ItemType Directory -Path $script:root -Force | Out-Null
$script:lines = New-Object System.Collections.Generic.List[string]

function Say([string]$s) { Write-Output $s }

function New-Fixture([string]$Name, [string]$LauncherSrc) {
  $dir = Join-Path $script:root $Name
  New-Item -ItemType Directory -Path (Join-Path $dir 'docs\relay') -Force | Out-Null
  New-Item -ItemType Directory -Path (Join-Path $dir 'docs\plans') -Force | Out-Null
  Copy-Item -LiteralPath $LauncherSrc -Destination (Join-Path $dir 'docs\relay\start-relay.ps1') -Force
  Copy-Item -LiteralPath (Join-Path $tplDir 'relay-lock.ps1') -Destination (Join-Path $dir 'docs\relay\relay-lock.ps1') -Force
  Copy-Item -LiteralPath (Join-Path $tplDir 'relay-ledger.ps1') -Destination (Join-Path $dir 'docs\relay\relay-ledger.ps1') -Force
  $plan = '# plan' + "`n`n" + '1. first stage' + "`n" + '2. second stage' + "`n"
  [IO.File]::WriteAllText((Join-Path $dir 'docs\plans\link.md'), $plan, (New-Object Text.UTF8Encoding($false)))
  & git -C $dir init -q 2>&1 | Out-Null
  & git -C $dir add -A 2>&1 | Out-Null
  & git -C $dir -c user.email=t@t -c user.name=t commit -qm init 2>&1 | Out-Null
  return $dir
}

function Measure-Prompt([string]$Dir, [string]$Label) {
  $launcherPath = Join-Path $Dir 'docs\relay\start-relay.ps1'
  & pwsh -NoProfile -ExecutionPolicy Bypass -File $launcherPath -Target 'link batch' -MaxStages 2 -Runtime claude-code -PlanDoc 'docs\plans\link.md' *>&1 | Out-Null
  $code = $LASTEXITCODE
  $promptPath = Join-Path $Dir 'docs\relay\next-relay-prompt.txt'
  if (-not (Test-Path -LiteralPath $promptPath)) {
    $script:lines.Add(($Label + ' exit=' + $code + ' PROMPT_MISSING'))
    return @{ Exit = $code; New = 0; Legacy = 0; Missing = $true }
  }
  $text = [IO.File]::ReadAllText($promptPath)
  $newHits = [regex]::Matches($text, 'relay-\d{2}of\d{2}').Count
  $legacyHits = [regex]::Matches($text, 'relay-\d+-').Count
  $script:lines.Add(($Label + ' exit=' + $code + ' new_form_hits=' + $newHits + ' legacy_hits=' + $legacyHits))
  return @{ Exit = $code; New = $newHits; Legacy = $legacyHits; Missing = $false }
}

# --- baseline: the shipped template -------------------------------------------------
$baseDir = New-Fixture 'baseline' $launcher
$base = Measure-Prompt $baseDir 'BASELINE'

# --- mutant: the old naming, on a copy ----------------------------------------------
$mutSrc = Join-Path $script:root 'start-relay-legacy.ps1'
$txt = [IO.File]::ReadAllText($launcher)
$pattern = '(?m)^\$linkTag = .*\r?\n\$nextLinkTag = .*$'
$hits = [regex]::Matches($txt, $pattern).Count
Say ('MUTATION_ANCHOR_HITS=' + $hits)
if ($hits -ne 1) { Say 'FAIL mutation_anchor_not_unique'; exit 2 }
$legacyLines = '$linkTag = ''relay-'' + $stageNo' + "`n" + '$nextLinkTag = ''relay-'' + $nextStageNo'
$mutated = [regex]::Replace($txt, $pattern, $legacyLines)
if ($mutated -eq $txt) { Say 'FAIL mutation_no_change'; exit 2 }
[IO.File]::WriteAllText($mutSrc, $mutated, (New-Object Text.UTF8Encoding($false)))
Say ('MUTATION_WROTE=' + $mutSrc)

$mutDir = New-Fixture 'mutant' $mutSrc
$mut = Measure-Prompt $mutDir 'MUTANT'

foreach ($l in $script:lines) { Say $l }

# --- verdict ------------------------------------------------------------------------
$baselineGreen = ($base.Exit -eq 0 -and $base.New -gt 0 -and $base.Legacy -eq 0)
$mutantRed = ($mut.New -eq 0 -or $mut.Legacy -gt 0)
Say ('BASELINE_CASE23_GREEN=' + $baselineGreen)
Say ('MUTANT_CASE23_RED=' + $mutantRed)
Say ('MUTATION_VERDICT=' + $(if ($baselineGreen -and $mutantRed) { 'ASSERTION_HAS_TEETH' } else { 'ASSERTION_WEAK' }))
Say ('ROOT=' + $script:root)
if ($baselineGreen -and $mutantRed) { exit 0 } else { exit 3 }
