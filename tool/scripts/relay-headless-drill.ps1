<#
.SYNOPSIS
  Drill the headless link of the relay kit on the REAL claude build.

.DESCRIPTION
  The routine selftest never starts a real runtime: it runs the driver against a
  stub, so it proves the wiring but not the runtime. This drill proves the
  runtime as well, on the build that is actually installed on this machine.

  It runs three scenes, in this order:

    1. wiring, zero cost : the launcher writes its own chain prompt and the
       driver runs it against a STUB claude. This proves the chain prompt, the
       command that is built, the lock hand-over and the output capture
       without spending a cent and without any risk of a recursive spawn.
    2. runtime, bounded cost : the driver runs the SAME path against the REAL
       claude build with a minimal prompt and a budget cap. This proves that
       the built command is accepted by the installed build, that the session
       id comes back, and that the raw output lands on disk.
    3. hygiene : the registry of the desktop client must not grow, the project
       entry of the fixture must be moved away and its transcript kept.

  Every step writes its raw output to the evidence directory, so the result can
  be read long after the run and compared with the selftest evidence.

  Nothing outside the fixture and the evidence directory is written, and the
  fixture is removed at the end unless -KeepFixture is given.

.PARAMETER EvidenceDir
  Where the evidence is written. Default: <repo>\reports\headless-drill when a
  repository root is found, otherwise <cwd>\headless-drill.

.PARAMETER WorkDir
  Where the fixture is built. Default: <temp>\agentask-relay-headless\<stamp>.

.PARAMETER MaxBudgetUsd
  Budget cap for the one real run. 0 means no cap. Default 0.60: one link on a
  machine with a large global context (hooks, plugins, project rules) was measured
  at about 0.09 USD of input alone, so a cap below that cuts the link off
  before it can answer anything.

.PARAMETER TimeoutSeconds
  Wall clock cap for one child process. Default 300.

.PARAMETER SkipRealRun
  Only run the zero cost scenes. Use it on a machine without a usable claude.

.PARAMETER KeepFixture
  Keep the fixture directory instead of deleting it.

.EXAMPLE
  pwsh -NoProfile -File tool\scripts\relay-headless-drill.ps1
.EXAMPLE
  pwsh -NoProfile -File tool\scripts\relay-headless-drill.ps1 -SkipRealRun
#>
param(
  [string]$EvidenceDir = '',
  [string]$WorkDir = '',
  [double]$MaxBudgetUsd = 0.60,
  [int]$TimeoutSeconds = 300,
  [switch]$SkipRealRun,
  [switch]$KeepFixture
)

$ErrorActionPreference = 'Stop'

$script:pass = 0
$script:fail = 0
$script:facts = New-Object System.Collections.Generic.List[string]

function Say([string]$Text) { Write-Host $Text }

function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  if ($Ok) {
    $script:pass++
    Say ('  [PASS] ' + $Name + $(if ($Detail -ne '') { '  (' + $Detail + ')' } else { '' }))
  } else {
    $script:fail++
    Say ('  [FAIL] ' + $Name + $(if ($Detail -ne '') { '  (' + $Detail + ')' } else { '' }))
  }
  $script:facts.Add(($Name + '|' + $(if ($Ok) { 'PASS' } else { 'FAIL' }) + '|' + $Detail))
}

function Save-Text([string]$Path, [string]$Text) {
  $dir = Split-Path -Parent $Path
  if (-not (Test-Path -LiteralPath $dir -PathType Container)) {
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
  }
  [IO.File]::WriteAllText($Path, ($Text -replace "`r", ''), (New-Object Text.UTF8Encoding($false)))
}

# A redirected child process writes CRLF. This corpus keeps every .md and .txt
# on LF, so captured evidence is normalized on the way in.
function Normalize-Lf([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return }
  $raw = [IO.File]::ReadAllText($Path)
  if (-not $raw.Contains([char]13)) { return }
  [IO.File]::WriteAllText($Path, ($raw -replace "`r", ''), (New-Object Text.UTF8Encoding($false)))
}

# The profile directory is derived at run time and never written down: the kit
# is installed into other machines and other users.
function Get-ProfileDirectories {
  $list = New-Object System.Collections.Generic.List[string]
  if (-not [string]::IsNullOrWhiteSpace($env:HOME)) { $list.Add($env:HOME) }
  $drive = $env:HOMEDRIVE
  $tail = $env:HOMEPATH
  if (-not [string]::IsNullOrWhiteSpace($drive) -and -not [string]::IsNullOrWhiteSpace($tail)) {
    if ($tail -notmatch '^[\\/]') { $tail = '\' + $tail }
    $list.Add($drive + $tail)
  }
  $appData = [Environment]::GetFolderPath('ApplicationData')
  if (-not [string]::IsNullOrWhiteSpace($appData)) {
    $profile = Split-Path -Parent (Split-Path -Parent $appData)
    if (-not [string]::IsNullOrWhiteSpace($profile)) { $list.Add($profile) }
  }
  return @($list | Select-Object -Unique)
}

function Get-RegistryCandidates {
  $list = New-Object System.Collections.Generic.List[string]
  $cfg = $env:CLAUDE_CONFIG_DIR
  if (-not [string]::IsNullOrWhiteSpace($cfg)) { $list.Add((Join-Path $cfg 'projects')) }
  foreach ($profile in @(Get-ProfileDirectories)) {
    $list.Add((Join-Path $profile '.claude\projects'))
  }
  return @($list | Select-Object -Unique)
}

function Get-ClaudeProjectKey([string]$Path) {
  return ($Path -replace '[^A-Za-z0-9]', '-')
}

function Get-RegistryNames {
  $map = @{}
  foreach ($reg in @(Get-RegistryCandidates)) {
    if (-not (Test-Path -LiteralPath $reg -PathType Container)) { continue }
    $names = @(Get-ChildItem -LiteralPath $reg -Directory -ErrorAction SilentlyContinue | ForEach-Object { $_.Name })
    $map[$reg] = $names
  }
  return $map
}

# Start-Process joins the argument list with spaces and does not quote an
# element that contains one, so a value like "headless drill" would arrive as
# two arguments and the next named parameter would be swallowed. Every
# argument is quoted here before it is handed over.
function Quote-Arg([string]$Value) {
  if ($Value -match '[\s"]') { return '"' + ($Value -replace '"', '\"') + '"' }
  return $Value
}

function Invoke-Child([string]$Exe, [string[]]$ChildArgs, [string]$OutFile, [string]$ErrFile, [int]$TimeoutSec) {
  $text = ''
  $code = -1
  $timedOut = $false
  $proc = $null
  try {
    $proc = Start-Process -FilePath $Exe -ArgumentList @($ChildArgs | ForEach-Object { Quote-Arg $_ }) -NoNewWindow -PassThru `
      -RedirectStandardOutput $OutFile -RedirectStandardError $ErrFile -ErrorAction Stop
    $finished = $proc.WaitForExit($TimeoutSec * 1000)
    if (-not $finished) {
      $timedOut = $true
      try { $proc.Kill($true) } catch { }
      try { $proc.WaitForExit(15000) | Out-Null } catch { }
    } else {
      $code = $proc.ExitCode
    }
  } catch {
    $text = 'spawn_failed: ' + $_.Exception.Message
    Save-Text $OutFile $text
    Save-Text $ErrFile ''
    return [pscustomobject]@{ Code = 125; TimedOut = $false; Text = $text }
  } finally {
    if ($null -ne $proc) { try { $proc.Dispose() } catch { } }
  }
  Normalize-Lf $OutFile
  Normalize-Lf $ErrFile
  if (Test-Path -LiteralPath $OutFile) { $text = [IO.File]::ReadAllText($OutFile) }
  return [pscustomobject]@{ Code = $code; TimedOut = $timedOut; Text = $text }
}

function Read-Json([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
  try { return ([IO.File]::ReadAllText($Path)) | ConvertFrom-Json } catch { return $null }
}

# --- 0. locate the kit and the evidence directory --------------------------------
$kitRoot = Split-Path -Parent $PSScriptRoot
$templateDir = Join-Path $kitRoot 'templates'
$installer = Join-Path $PSScriptRoot 'install-relay.ps1'
if (-not (Test-Path -LiteralPath $installer -PathType Leaf)) {
  Say ('FAIL reason=installer_missing path=' + $installer)
  exit 2
}
if (-not (Test-Path -LiteralPath (Join-Path $templateDir 'relay-spawn.ps1') -PathType Leaf)) {
  Say ('FAIL reason=templates_missing dir=' + $templateDir)
  exit 2
}

$repoRoot = ''
$probe = $kitRoot
for ($i = 0; $i -lt 5; $i++) {
  if (Test-Path -LiteralPath (Join-Path $probe 'MANIFEST.txt') -PathType Leaf) { $repoRoot = $probe; break }
  $parent = Split-Path -Parent $probe
  if ($parent -eq $probe -or [string]::IsNullOrWhiteSpace($parent)) { break }
  $probe = $parent
}
if ([string]::IsNullOrWhiteSpace($EvidenceDir)) {
  if ($repoRoot -ne '') { $EvidenceDir = Join-Path $repoRoot 'reports\headless-drill' }
  else { $EvidenceDir = Join-Path (Get-Location).Path 'headless-drill' }
}
if (-not (Test-Path -LiteralPath $EvidenceDir -PathType Container)) {
  New-Item -ItemType Directory -Path $EvidenceDir -Force | Out-Null
}
$EvidenceDir = (Resolve-Path -LiteralPath $EvidenceDir).Path

$stamp = (Get-Date -Format 'yyyyMMdd-HHmmss')
if ([string]::IsNullOrWhiteSpace($WorkDir)) {
  $WorkDir = Join-Path ([IO.Path]::GetTempPath()) ('agentask-relay-headless\' + $stamp)
}
if (-not (Test-Path -LiteralPath $WorkDir -PathType Container)) {
  New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null
}
$WorkDir = (Resolve-Path -LiteralPath $WorkDir).Path
$fixture = Join-Path $WorkDir 'repo'
$stubDir = Join-Path $WorkDir 'stub'

$pwshExe = 'pwsh'
$pwshCmd = Get-Command $pwshExe -ErrorAction SilentlyContinue
if ($pwshCmd) { $pwshExe = $pwshCmd.Source }

Say ('DRILL_START evidence=' + $EvidenceDir)
Say ('DRILL_WORKDIR work=' + $WorkDir)

# --- 1. preflight: the installed build -------------------------------------------
$preOut = Join-Path $EvidenceDir 'preflight.txt'
$preLines = New-Object System.Collections.Generic.List[string]
$claudeCmd = Get-Command 'claude' -ErrorAction SilentlyContinue
if (-not $claudeCmd) {
  $preLines.Add('claude: MISSING from PATH')
  Save-Text $preOut ($preLines -join "`n")
  Say 'FAIL reason=claude_cli_missing'
  Check 'drill_claude_cli_present' $false 'claude not on PATH'
  Say ('DRILL_RESULT pass=' + $script:pass + ' fail=' + $script:fail)
  exit 3
}
$ver = (& $claudeCmd.Source --version 2>&1 | Out-String).Trim()
$preLines.Add('claude_path: ' + $claudeCmd.Source)
$preLines.Add('claude_version: ' + $ver)
$helpText = (& $claudeCmd.Source --help 2>&1 | Out-String)
$preLines.Add('help_bytes: ' + $helpText.Length)
$flagNames = @('--output-format', '--session-id', '--add-dir', '--settings', '--permission-mode', '--allowedTools', '--max-budget-usd', '--max-turns', '--print')
$flagRows = New-Object System.Collections.Generic.List[string]
foreach ($f in $flagNames) {
  $supported = $helpText.Contains($f)
  $flagRows.Add($f + '=' + $(if ($supported) { 'supported' } else { 'ABSENT' }))
  $preLines.Add('flag ' + $f + ': ' + $(if ($supported) { 'supported' } else { 'ABSENT' }))
}
Save-Text $preOut ($preLines -join "`n")
Say ('DRILL_CLAUDE version=' + $ver)
Check 'drill_claude_cli_present' $true $ver
# The driver passes --max-turns only when the caller asks for it. A build that
# does not know the flag makes every such link fail, so the drill records the
# answer instead of guessing it.
$maxTurnsSupported = $helpText.Contains('--max-turns')
Say ('DRILL_FLAG --max-turns=' + $(if ($maxTurnsSupported) { 'supported' } else { 'ABSENT' }))

$credPresent = $false
foreach ($profile in @(Get-ProfileDirectories)) {
  $cred = Join-Path $profile '.claude\.credentials.json'
  if (Test-Path -LiteralPath $cred -PathType Leaf) { $credPresent = $true }
}
Check 'drill_credentials_present' $credPresent ''

# --- 2. fixture ------------------------------------------------------------------
if (Test-Path -LiteralPath $fixture) { Remove-Item -LiteralPath $fixture -Recurse -Force }
New-Item -ItemType Directory -Path (Join-Path $fixture 'docs') -Force | Out-Null
& git -C $fixture init -q 2>&1 | Out-Null
Save-Text (Join-Path $fixture 'docs\plan-headless.md') "# headless drill plan`n`nOne stage: prove the headless link.`n"
$installOut = Join-Path $EvidenceDir 'install.txt'
$installArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $installer,
  '-RepoRoot', $fixture, '-Target', 'headless drill', '-PlanDoc', 'docs\plan-headless.md',
  '-MaxStages', '2', '-Runtime', 'claude-code')
$inst = Invoke-Child $pwshExe $installArgs $installOut (Join-Path $EvidenceDir 'install.err.txt') $TimeoutSeconds
Check 'drill_install_exit_zero' ($inst.Code -eq 0) ('exit=' + $inst.Code)

$spawnInstalled = Join-Path $fixture 'docs\relay\relay-spawn.ps1'
$launcher = Join-Path $fixture 'docs\relay\start-relay.ps1'
$lockScript = Join-Path $fixture 'docs\relay\relay-lock.ps1'
Check 'drill_kit_installed' ((Test-Path -LiteralPath $spawnInstalled) -and (Test-Path -LiteralPath $launcher)) ''

# --- 3. the launcher writes the chain prompt and takes the lock -------------------
$drillSession = 'mvs_headless_drill'
$launchOut = Join-Path $EvidenceDir 'launcher.txt'
$launchArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $launcher,
  '-Target', 'headless drill', '-MaxStages', '2', '-Runtime', 'claude-code',
  '-InitiatorSession', $drillSession, '-ExpectedHostProject', $fixture)
$launch = Invoke-Child $pwshExe $launchArgs $launchOut (Join-Path $EvidenceDir 'launcher.err.txt') $TimeoutSeconds
Check 'drill_launcher_exit_zero' ($launch.Code -eq 0) ('exit=' + $launch.Code)
$chainPrompt = Join-Path $fixture 'docs\relay\next-relay-prompt.txt'
$chainPromptText = ''
if (Test-Path -LiteralPath $chainPrompt -PathType Leaf) { $chainPromptText = [IO.File]::ReadAllText($chainPrompt) }
Check 'drill_launcher_wrote_the_chain_prompt' ($chainPromptText.Length -gt 200) ('chars=' + $chainPromptText.Length)
Check 'drill_chain_prompt_names_the_spawn_driver' ($chainPromptText -match 'relay-spawn\.ps1' -and $chainPromptText -match '-Runtime claude-code') ''
$ledgerPath = Join-Path $fixture 'docs\relay.json'
$ledger = Read-Json $ledgerPath
Check 'drill_ledger_created' ($null -ne $ledger) ('status=' + [string]$ledger.status)
Check 'drill_ledger_status_running' ([string]$ledger.status -eq 'running') ('status=' + [string]$ledger.status)
$lockPath = Join-Path $fixture 'docs\relay\.relay.lock'
$lockRec = Read-Json $lockPath
Check 'drill_lock_taken_by_the_launcher' ($null -ne $lockRec) ('holder=' + [string]$lockRec.holder)
$launcherHolder = [string]$lockRec.holder

# --- 4. scene 1: the chain prompt against a STUB runtime (zero cost) --------------
if (-not (Test-Path -LiteralPath $stubDir -PathType Container)) {
  New-Item -ItemType Directory -Path $stubDir -Force | Out-Null
}
$stubSession = [guid]::NewGuid().ToString()
$stubBody = @(
  '@echo off',
  'echo {"type":"result","session_id":"' + $stubSession + '","result":"stub"}',
  'exit /b 0'
) -join "`r`n"
[IO.File]::WriteAllText((Join-Path $stubDir 'claude.cmd'), ($stubBody -replace "`r`n", "`n"), (New-Object Text.UTF8Encoding($false)))
$oldPath = $env:PATH
$stubOut = Join-Path $EvidenceDir 'stub-run.txt'
try {
  $env:PATH = $stubDir + [IO.Path]::PathSeparator + $oldPath
  $stubArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $spawnInstalled,
    '-Runtime', 'claude-code', '-PromptFile', $chainPrompt, '-WorkspaceDir', $fixture,
    '-SessionId', $stubSession, '-Execute', '-AdoptLock')
  $stub = Invoke-Child $pwshExe $stubArgs $stubOut (Join-Path $EvidenceDir 'stub-run.err.txt') $TimeoutSeconds
} finally {
  $env:PATH = $oldPath
}
Check 'drill_stub_run_exit_zero' ($stub.Code -eq 0) ('exit=' + $stub.Code)
Check 'drill_stub_pre_adopted' ($stub.Text -match 'SPAWN_LOCK_PRE_ADOPTED') ''
Check 'drill_stub_lock_handed_over' ($stub.Text -match ('LOCK_ADOPTED holder=' + [regex]::Escape($stubSession))) ''
Check 'drill_stub_prev_holder_named' ($stub.Text -match ('prev_holder=' + [regex]::Escape($launcherHolder))) ''
$stubLock = Read-Json $lockPath
Check 'drill_stub_lock_holder_is_the_new_link' ($null -ne $stubLock -and [string]$stubLock.holder -eq $stubSession) ('holder=' + [string]$stubLock.holder)
$stubOutFile = Join-Path $fixture ('docs\relay\relay-spawn-output\' + $stubSession + '.txt')
Check 'drill_stub_output_captured' (Test-Path -LiteralPath $stubOutFile) ''

# The stub took the lock over. The real run needs a link of its own, so the lock
# is handed back and taken again by the drill itself.
$rel = Invoke-Child $pwshExe @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $lockScript,
  '-Action', 'release', '-SessionId', $stubSession) (Join-Path $EvidenceDir 'release.txt') (Join-Path $EvidenceDir 'release.err.txt') 60
Say ('DRILL_RELEASE exit=' + $rel.Code)

# --- 5. scene 2: the REAL runtime --------------------------------------------------
$realSession = [guid]::NewGuid().ToString()
$drillPromptFile = Join-Path $WorkDir 'drill-prompt.txt'
Save-Text $drillPromptFile ("Reply with exactly RELAY_HEADLESS_OK and nothing else. Do not use any tool.`n")
$registryBefore = Get-RegistryNames
$registryBeforeCount = 0
foreach ($k in $registryBefore.Keys) { $registryBeforeCount += @($registryBefore[$k]).Count }
$fixtureKey = Get-ClaudeProjectKey $fixture
$realOut = Join-Path $EvidenceDir 'real-run.txt'
$realOk = $false
$realCode = -1
if ($SkipRealRun) {
  Say 'DRILL_SKIP real_run skipped by request'
  Check 'drill_real_run_skipped' $true 'skipped'
} else {
  # The link is given the lock first, so the driver can hand it over before the
  # child starts: that is the order a real chain uses.
  $acq = Invoke-Child $pwshExe @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $lockScript,
    '-Action', 'acquire', '-SessionId', $drillSession, '-Stage', '0') (Join-Path $EvidenceDir 'acquire.txt') (Join-Path $EvidenceDir 'acquire.err.txt') 60
  Say ('DRILL_ACQUIRE exit=' + $acq.Code)
  $realArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $spawnInstalled,
    '-Runtime', 'claude-code', '-PromptFile', $drillPromptFile, '-WorkspaceDir', $fixture,
    '-SessionId', $realSession, '-Execute', '-AdoptLock', '-EphemeralWorkspace')
  if ($MaxBudgetUsd -gt 0) { $realArgs += @('-MaxBudgetUsd', ([string]$MaxBudgetUsd)) }
  $real = Invoke-Child $pwshExe $realArgs $realOut (Join-Path $EvidenceDir 'real-run.err.txt') $TimeoutSeconds
  $realCode = $real.Code
  $realOk = ($real.Code -eq 0)
  Check 'drill_real_run_exit_zero' $realOk ('exit=' + $real.Code + ' timed_out=' + $real.TimedOut)
  Check 'drill_real_run_not_timed_out' (-not $real.TimedOut) ('timeout_s=' + $TimeoutSeconds)
  Check 'drill_real_pre_adopted' ($real.Text -match 'SPAWN_LOCK_PRE_ADOPTED') ''
  Check 'drill_real_lock_handed_over' ($real.Text -match ('LOCK_ADOPTED holder=' + [regex]::Escape($realSession))) ''
  Check 'drill_real_session_id_matches_request' ($real.Text -match ('RELAY_SPAWN_OK runtime=claude-code session_id=' + [regex]::Escape($realSession))) ''
  $realOutFile = Join-Path $fixture ('docs\relay\relay-spawn-output\' + $realSession + '.txt')
  $realOutText = ''
  if (Test-Path -LiteralPath $realOutFile -PathType Leaf) { $realOutText = [IO.File]::ReadAllText($realOutFile) }
  Check 'drill_real_output_file_written' ((Test-Path -LiteralPath $realOutFile) -and $realOutText.Length -gt 0) ('chars=' + $realOutText.Length)
  Check 'drill_real_output_carries_the_session_id' ($realOutText -match ([regex]::Escape($realSession))) ''
  Check 'drill_real_output_carries_a_result' ($realOutText -match '"result"') ''
  # The cost of one link is a fact the chain budget depends on, so it is read
  # out of the runtime output instead of being guessed.
  $realCost = 0.0
  $costMatch = [regex]::Match($realOutText, '"total_cost_usd"\s*:\s*([0-9.]+)')
  if ($costMatch.Success) { $realCost = [double]$costMatch.Groups[1].Value }
  Say ('DRILL_COST usd=' + $realCost)
  Check 'drill_real_run_was_not_cut_off' ($realOutText -notmatch 'error_max_budget_usd') ('cost_usd=' + $realCost)
  $realLock = Read-Json $lockPath
  Check 'drill_real_lock_holder_is_the_new_link' ($null -ne $realLock -and [string]$realLock.holder -eq $realSession) ('holder=' + [string]$realLock.holder)

  # --- 6. hygiene: the registry of the desktop client must not grow --------------
  $registryAfter = Get-RegistryNames
  $registryAfterCount = 0
  foreach ($k in $registryAfter.Keys) { $registryAfterCount += @($registryAfter[$k]).Count }
  $keyStillThere = $false
  foreach ($k in $registryAfter.Keys) { if (@($registryAfter[$k]) -contains $fixtureKey) { $keyStillThere = $true } }
  Check 'drill_registry_did_not_grow' ($registryAfterCount -le $registryBeforeCount) ('before=' + $registryBeforeCount + ' after=' + $registryAfterCount)
  Check 'drill_fixture_project_not_in_the_registry' (-not $keyStillThere) ('key=' + $fixtureKey)
  $stashFound = $false
  foreach ($profile in @(Get-ProfileDirectories)) {
    if (Test-Path -LiteralPath (Join-Path $profile '.claude\_relay-ephemeral') -PathType Container) { $stashFound = $true }
  }
  Check 'drill_transcript_kept_as_evidence' $stashFound ''
}

# --- 7. summary --------------------------------------------------------------------
$summary = New-Object System.Collections.Generic.List[string]
$summary.Add('drill_stamp=' + $stamp)
$summary.Add('drill_claude_version=' + $ver)
$summary.Add('drill_max_turns_supported=' + $maxTurnsSupported)
$summary.Add('drill_real_run_exit=' + $realCode)
$summary.Add('drill_pass=' + $script:pass)
$summary.Add('drill_fail=' + $script:fail)
foreach ($f in $script:facts) { $summary.Add('fact=' + $f) }
Save-Text (Join-Path $EvidenceDir 'summary.txt') ($summary -join "`n")
Save-Text (Join-Path $EvidenceDir 'flags.txt') (($flagRows -join "`n") + "`n")

Say ('DRILL_RESULT pass=' + $script:pass + ' fail=' + $script:fail + ' evidence=' + $EvidenceDir)

if (-not $KeepFixture) {
  Remove-Item -LiteralPath $WorkDir -Recurse -Force -ErrorAction SilentlyContinue
  Say ('DRILL_CLEANUP removed=' + $WorkDir)
}
if ($script:fail -gt 0) { exit 3 }
exit 0
