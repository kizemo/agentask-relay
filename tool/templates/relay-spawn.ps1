<#
.SYNOPSIS
  Start the next relay link for a CLI-based agent runtime (Claude Code / Codex CLI).

.DESCRIPTION
  The MCode runtime starts the next link with its built-in session_create tool, which no
  other runtime has. A CLI runtime starts the next link with a headless process instead:

    claude-code : claude -p "<prompt>" --output-format json --session-id <uuid> ...
    codex       : codex exec "<prompt>" --json ...

  This script builds that command, prints it, and only runs it when -Execute is given.
  The prompt is read from a file (the launcher writes docs\relay\next-relay-prompt.txt),
  so a long prompt never has to survive a shell quoting round trip.

  The session id is extracted from the runtime output; for claude-code the id is also
  requested up front with --session-id, so the id is known even when the runtime prints
  nothing parseable.

  The runtime is started with the chain workspace as its working directory: a headless
  CLI takes its working directory from the process, and --add-dir only widens the
  permission scope. The permission mode never asks (bypassPermissions by default) and
  the interactive question box is switched off, because a headless link has nobody to
  answer either of them. Those rules travel in a settings FILE
  (docs\relay\relay-settings.json) that is handed over with --settings, and the
  prompt is the LAST argument of the command line: the argument parser of the CLI
  build measured in B10 stops at the first positional argument, so every flag
  placed after the prompt is dropped. The raw runtime output is kept under
  docs\relay\relay-spawn-output\ so that a link which did nothing can be told
  apart from a link which worked.

  With -AdoptLock the relay lock is handed over to the new link by calling the sibling
  relay-lock.ps1 -Action adopt, which is the only supported way to transfer it. On
  claude-code the hand-over happens BEFORE the child process starts, so the new link
  owns the lock from its very first second and renew always names the real owner. If
  the child then fails, the lock is released again, so a broken link never leaves the
  chain behind a dead holder.

  Exit codes
    0  the command was built (dry run) or the link started and the session id was found
    2  invalid parameters, unknown runtime, missing prompt file, prompt too large
    3  the runtime CLI is missing, or the run failed, or the lock hand-over failed
    4  the run finished but no session id could be extracted

.EXAMPLE
  pwsh -NoProfile -ExecutionPolicy Bypass -File relay-spawn.ps1 -Runtime claude-code -PromptFile C:\repo\docs\relay\next-relay-prompt.txt
.EXAMPLE
  pwsh -NoProfile -ExecutionPolicy Bypass -File relay-spawn.ps1 -Runtime claude-code -PromptFile C:\repo\docs\relay\next-relay-prompt.txt -Execute -AdoptLock
#>
param(
  [Parameter(Mandatory = $true)]
  [string]$Runtime,

  [Parameter(Mandatory = $true)]
  [string]$PromptFile,

  [string]$WorkspaceDir = '',
  [string]$Model = '',
  # A headless link cannot answer a permission prompt, so the default must be a
  # mode that never asks. acceptEdits only auto-accepts file edits: every Bash
  # call would still wait for a human that is not there, which is how a chain
  # dies on its first command.
  [string]$PermissionMode = 'bypassPermissions',
  [string]$Sandbox = 'workspace-write',
  [string]$Approval = 'never',
  # Tools the headless runtime may use. A headless run cannot answer a
  # permission prompt, so anything not listed here is simply denied.
  [string]$AllowedTools = 'Bash,Read,Write,Edit,Glob,Grep',
  # Cost cap for one link. 0 means no cap.
  [double]$MaxBudgetUsd = 0,
  # Session id to use for the new link. Must be a UUID on claude-code.
  [string]$SessionId = '',
  [int]$MaxTurns = 0,
  [switch]$Execute,
  [switch]$AdoptLock,
  # Ephemeral workspace (B22): the workspace is a throwaway fixture, not a real
  # project. Claude Code keys every session by its working directory and writes
  # the entry into <user profile>\.claude\projects\<mangled cwd>, and the desktop
  # client renders exactly that directory as its project list: a test run leaves
  # a project behind that the user never asked for. With this switch the driver
  # moves the entry its own child created out of the registry and keeps the
  # transcript as evidence next to the run output.
  [switch]$EphemeralWorkspace
)

$ErrorActionPreference = 'Stop'

function Say([string]$Text) { Write-Host $Text }

# Claude Code stores every session under a directory that is named after the
# working directory of the session, and the desktop client renders exactly that
# directory as its project list. The name is the path with every character that
# is not a letter or a digit replaced by a dash.
function Get-ClaudeProjectKey([string]$Path) {
  return ($Path -replace '[^A-Za-z0-9]', '-')
}
# The registry itself is looked up in every place a Claude build may keep it: a
# build that honours CLAUDE_CONFIG_DIR writes there, a build that ignores it
# writes under the profile of the current user. Both are checked, so the cleanup
# works on either build.
function Get-ProjectRegistryCandidates {
  $list = New-Object System.Collections.Generic.List[string]
  $cfg = $env:CLAUDE_CONFIG_DIR
  if (-not [string]::IsNullOrWhiteSpace($cfg)) { $list.Add((Join-Path $cfg 'projects')) }
  foreach ($profile in @(Get-ProfileDirectories)) {
    $list.Add((Join-Path $profile '.claude\projects'))
  }
  return @($list | Select-Object -Unique)
}

# The profile directory is derived at run time and never written down: the kit
# is installed into other machines and other users, so a home path of its own
# would be wrong everywhere else. Three sources, all of them optional:
# the shell home variable, the drive plus path pair Windows keeps for the
# profile, and the application data folder whose two parents are the profile.
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

# --- 1. parameters --------------------------------------------------------------
$cliRuntimes = @('claude-code', 'codex')
if ($cliRuntimes -notcontains $Runtime) {
  Say ("FAIL reason=runtime_not_cli runtime=" + $Runtime + " cli_runtimes=" + ($cliRuntimes -join ','))
  exit 2
}
if (-not (Test-Path -LiteralPath $PromptFile -PathType Leaf)) {
  Say ("FAIL reason=prompt_file_missing path=" + $PromptFile)
  exit 2
}
$promptPath = (Resolve-Path -LiteralPath $PromptFile).Path
$promptText = [IO.File]::ReadAllText($promptPath)
if ($promptText.Length -gt 60000) {
  Say ("FAIL reason=prompt_too_large chars=" + $promptText.Length + " limit=60000")
  exit 2
}
if ([string]::IsNullOrWhiteSpace($WorkspaceDir)) { $WorkspaceDir = (Get-Location).Path }
if (-not (Test-Path -LiteralPath $WorkspaceDir -PathType Container)) {
  Say ("FAIL reason=workspace_missing path=" + $WorkspaceDir)
  exit 2
}
$WorkspaceDir = (Resolve-Path -LiteralPath $WorkspaceDir).Path
if ($MaxTurns -lt 0) { $MaxTurns = 0 }

# --- 2. build the command ------------------------------------------------------
# Session id resolution. On claude-code the id is known BEFORE the run, and that
# is what makes an unattended chain work: the lock can be handed over to the new
# link before it starts, and the previous link can already record
# next_session_id in the ledger before spawning. Precedence: explicit
# -SessionId, then the ledger's next_session_id (the previous link wrote it),
# then a fresh UUID.
$requestedSessionId = ''
$sessionIdSource = 'none'
if ($Runtime -eq 'claude-code') {
  if (-not [string]::IsNullOrWhiteSpace($SessionId)) {
    $parsedId = [guid]::Empty
    if ([guid]::TryParse($SessionId, [ref]$parsedId)) {
      $requestedSessionId = $parsedId.ToString()
      $sessionIdSource = 'parameter'
    } else {
      Say ("FAIL reason=session_id_not_uuid value=" + $SessionId)
      exit 2
    }
  }
  if ($requestedSessionId -eq '') {
    # The ledger lives in the chain workspace, not next to this script: the driver
    # is a template that also runs from tool\templates, so the workspace is the
    # only trustworthy anchor.
    $ledgerNext = ''
    $ledgerFile = Join-Path $WorkspaceDir 'docs\relay.json'
    if (Test-Path -LiteralPath $ledgerFile -PathType Leaf) {
      try {
        $ledgerObj = Get-Content -LiteralPath $ledgerFile -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($null -ne $ledgerObj -and -not [string]::IsNullOrWhiteSpace([string]$ledgerObj.next_session_id)) {
          $ledgerNext = [string]$ledgerObj.next_session_id
        }
      } catch {
        $ledgerNext = ''
      }
    }
    $parsedLedger = [guid]::Empty
    if ($ledgerNext -ne '' -and [guid]::TryParse($ledgerNext, [ref]$parsedLedger)) {
      $requestedSessionId = $parsedLedger.ToString()
      $sessionIdSource = 'ledger'
    } else {
      $requestedSessionId = [guid]::NewGuid().ToString()
      $sessionIdSource = 'generated'
    }
  }
}

# --- 2a. chain gate: only a running chain may be spawned -----------------------
# A blocked or finished chain that is still spawned runs work no human approved:
# the driver used to read next_session_id out of the ledger without ever looking
# at status, so a chain a human had stopped could still take another turn. The
# ledger is the only place that knows, so it is read here even when the caller
# passed -SessionId. A workspace without a ledger is allowed on purpose: the
# driver is also used before a chain exists.
$spawnLedgerFile = Join-Path $WorkspaceDir 'docs\relay.json'
$spawnLedgerStatus = 'absent'
if (Test-Path -LiteralPath $spawnLedgerFile -PathType Leaf) {
  try {
    $spawnLedgerObj = Get-Content -LiteralPath $spawnLedgerFile -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($null -eq $spawnLedgerObj) {
      $spawnLedgerStatus = 'unreadable'
    } else {
      $spawnLedgerStatus = ([string]$spawnLedgerObj.status).Trim().ToLowerInvariant()
    }
  } catch {
    $spawnLedgerStatus = 'unreadable'
  }
}
Say ("SPAWN_LEDGER status=" + $spawnLedgerStatus + " path=" + $spawnLedgerFile)
if ($spawnLedgerStatus -ne 'absent' -and $spawnLedgerStatus -ne 'running') {
  $chainWhy = "status=" + $spawnLedgerStatus + " hint=a_blocked_done_pending_or_unreadable_chain_needs_a_human_decision_first"
  if ($Execute) {
    Say ("FAIL reason=chain_not_running " + $chainWhy)
    Say 'HINT=relay-ledger.ps1 -Action status shows the chain state; only a human moves a chain out of blocked.'
    exit 3
  }
  Say ("WARN reason=chain_not_running " + $chainWhy + " (dry_run_would_not_execute)")
}

# A headless link cannot answer a question, and a question nobody answers turns
# into a multi-minute stall in the middle of a stage.
#
# The permission rules travel in a settings FILE, not in CLI flags. Measured on
# claude 999.0.0-local (2026-11-25) two things decide whether they are honoured:
# the key has to sit inside "permissions" (a top level "defaultMode" is read and
# ignored, which is why the machine wide ~/.claude/settings.json never actually
# put the machine into bypass mode), and the settings file is only read at all
# when the prompt is the LAST argument of the command line, because the argument
# parser of that build stops at the first positional argument. The file doubles
# as evidence of what the link was allowed to do.
$headlessSettings = '{"autoQuestion":{"enabled":false},"defaultMode":"bypassPermissions","permissions":{"defaultMode":"bypassPermissions","allow":["Bash","Bash(pwsh:*)","Bash(powershell:*)","Read","Write","Edit","Glob","Grep"]}}'
$budgetArg = ''
if ($MaxBudgetUsd -gt 0) {
  $budgetArg = [string]::Format([System.Globalization.CultureInfo]::InvariantCulture, '{0:0.####}', $MaxBudgetUsd)
}

$settingsFile = Join-Path $WorkspaceDir 'docs\relay\relay-settings.json'

$cmdArgs = @()
$exe = ''

if ($Runtime -eq 'claude-code') {
  $exe = 'claude'
  # The prompt goes LAST, after every option. On the CLI build measured in B10 the
  # argument parser stops at the first positional argument, so a flag that follows
  # the prompt is dropped: with the prompt first, --settings, --permission-mode,
  # --add-dir, --session-id, --output-format and --max-budget-usd were all
  # ignored, the link ran in default mode and every pwsh call came back as
  # "This command requires approval". With the prompt last the same command
  # honours every flag.
  $cmdArgs = @('--output-format', 'json', '--session-id', $requestedSessionId, '--add-dir', $WorkspaceDir)
  if (-not [string]::IsNullOrWhiteSpace($Model)) { $cmdArgs += @('--model', $Model) }
  if (-not [string]::IsNullOrWhiteSpace($PermissionMode)) { $cmdArgs += @('--permission-mode', $PermissionMode) }
  if (-not [string]::IsNullOrWhiteSpace($AllowedTools)) { $cmdArgs += @('--allowedTools', $AllowedTools) }
  $cmdArgs += @('--settings', $settingsFile)
  if ($budgetArg -ne '') { $cmdArgs += @('--max-budget-usd', $budgetArg) }
  if ($MaxTurns -gt 0) {
    # A turn cap is only useful when the build knows the flag. The build that
    # was measured on this machine does not know it, and an unknown flag makes
    # the whole link fail before it does anything at all. The help of the build
    # is asked once and the cap is dropped with a warning when the flag is
    # unknown, so the link still runs and the budget cap still applies.
    $turnsFlagKnown = $false
    $exeProbe = Get-Command $exe -ErrorAction SilentlyContinue
    if ($null -ne $exeProbe) {
      try {
        foreach ($h in @(& $exeProbe.Source --help 2>&1 | ForEach-Object { [string]$_ })) {
          if ($h -match '--max-turns') { $turnsFlagKnown = $true; break }
        }
      } catch {
        $turnsFlagKnown = $false
      }
    }
    if ($turnsFlagKnown) {
      $cmdArgs += @('--max-turns', [string]$MaxTurns)
    } else {
      Say ("WARN reason=max_turns_flag_unsupported flag=--max-turns requested=" + $MaxTurns + " action=dropped hint=the_budget_cap_still_applies")
    }
  }
  $cmdArgs += @('-p', $promptText)
} else {
  $exe = 'codex'
  $cmdArgs = @('exec', '--json', '--sandbox', $Sandbox, '-a', $Approval)
  if (-not [string]::IsNullOrWhiteSpace($Model)) { $cmdArgs += @('--model', $Model) }
  $cmdArgs += $promptText
}

# The printed command MIRRORS the executed one: the real argument list is copied
# and only the prompt itself is replaced by a file reference, because a prompt can
# be tens of kilobytes and a log line that long is unreadable and unquotable.
# The order comes from the real list on purpose: a printed command that does not
# match the command that runs is worse than no log at all, and in B10 the wrong
# order in this very line is what hid the bug for hours.
$display = @()
if ($cmdArgs.Count -gt 1) { $display = $cmdArgs[0..($cmdArgs.Count - 2)] }
$display += '<prompt from file>'

Say ("SPAWN_RUNTIME runtime=" + $Runtime)
Say ("SPAWN_COMMAND " + $exe + ' ' + ($display -join ' '))
Say ("SPAWN_PROMPT_FILE file=" + $promptPath + " chars=" + $promptText.Length)
Say ("SPAWN_WORKSPACE dir=" + $WorkspaceDir)
Say ("SPAWN_SESSION_ID id=" + $requestedSessionId + " source=" + $sessionIdSource)
if ($Runtime -eq 'claude-code') {
  # The rules are printed as well as written: the log of a run says exactly which
  # permissions the link had, and a dry run shows them without touching the disk.
  Say ("SPAWN_SETTINGS_JSON " + $headlessSettings)
}
if ($EphemeralWorkspace) {
  Say ("SPAWN_EPHEMERAL_WORKSPACE=true key=" + (Get-ClaudeProjectKey $WorkspaceDir))
}

if (-not $Execute) {
  Say 'SPAWN_EXECUTE=false (add -Execute to run the command above)'
  exit 0
}

# --- 2b. permission settings file ----------------------------------------------
# The file has to exist before the runtime starts: a --settings path that is not
# there is a hard error in the CLI, and a chain that starts with a missing
# permission layer dies on its very first command.
if ($Runtime -eq 'claude-code') {
  try {
    $settingsDir = Split-Path -Parent $settingsFile
    if (-not (Test-Path -LiteralPath $settingsDir -PathType Container)) {
      New-Item -ItemType Directory -Path $settingsDir -Force | Out-Null
    }
    [IO.File]::WriteAllText($settingsFile, $headlessSettings, [Text.UTF8Encoding]::new($false))
    Say ("SPAWN_SETTINGS_FILE path=" + $settingsFile + " bytes=" + (Get-Item -LiteralPath $settingsFile).Length)
  } catch {
    Say ("FAIL reason=settings_write_failed path=" + $settingsFile + " error=" + $_.Exception.Message)
    exit 3
  }
}

# --- 3. hand the lock over BEFORE the child starts -----------------------------
# Only claude-code can do this: its session id is known up front, so the lock can
# name the new owner before the new owner exists. A lock that still names the
# previous link while the new link is already running makes renew meaningless and
# lets a second chain slip in.
$preAdopted = $false
if ($AdoptLock) {
  $lockScript = Join-Path $PSScriptRoot 'relay-lock.ps1'
  if (-not (Test-Path -LiteralPath $lockScript -PathType Leaf)) {
    Say ("FAIL reason=lock_script_missing path=" + $lockScript)
    exit 2
  }
  # The hand-over is a one-time permit, the same one the mcode flow uses: the
  # driver takes a permit as the current holder and hands it over together with
  # its nonce, so a second driver cannot take the lock away from the chain.
  $permitNonce = ''
  $permitOut = @(& (Get-Process -Id $PID).Path -NoProfile -ExecutionPolicy Bypass -File $lockScript -Action prespawn -Stage 0 | ForEach-Object { [string]$_ })
  $permitExit = $LASTEXITCODE
  foreach ($permitLine in $permitOut) {
    if ($permitLine -match 'SPAWN_PERMIT ok nonce=(\w+)') { $permitNonce = $matches[1] }
  }
  if ($permitExit -ne 0) {
    Say ("FAIL reason=lock_prespawn_failed exit=" + $permitExit)
    foreach ($permitLine in $permitOut) { Say ("SPAWN_OUTPUT " + $permitLine) }
    exit 3
  }
  if ($permitNonce -eq '') {
    Say 'FAIL reason=permit_nonce_missing'
    foreach ($permitLine in $permitOut) { Say ("SPAWN_OUTPUT " + $permitLine) }
    exit 3
  }
  if ($Runtime -eq 'claude-code' -and $requestedSessionId -ne '') {
    & (Get-Process -Id $PID).Path -NoProfile -ExecutionPolicy Bypass -File $lockScript -Action adopt -SessionId $requestedSessionId -Nonce $permitNonce
    $lockExit = $LASTEXITCODE
    if ($lockExit -ne 0) {
      Say ("FAIL reason=lock_adopt_failed exit=" + $lockExit + " session_id=" + $requestedSessionId)
      exit 3
    }
    Say ("SPAWN_LOCK_PRE_ADOPTED session_id=" + $requestedSessionId + " nonce=" + $permitNonce)
    $preAdopted = $true
  }
}

function Release-PreAdoptedLock {
  if (-not $preAdopted) { return }
  $lockScript = Join-Path $PSScriptRoot 'relay-lock.ps1'
  if (-not (Test-Path -LiteralPath $lockScript -PathType Leaf)) { return }
  & (Get-Process -Id $PID).Path -NoProfile -ExecutionPolicy Bypass -File $lockScript -Action release -SessionId $requestedSessionId | Out-Null
  if ($LASTEXITCODE -eq 0) {
    Say ("SPAWN_LOCK_RELEASED session_id=" + $requestedSessionId + " reason=link_failed")
  }
}

# --- 3b. ephemeral workspace: keep the project registry clean --------------------
# A link that runs in a throwaway fixture leaves a project behind in the
# registry of the client, and a whole test batch leaves a dozen of them. The
# driver can undo that for its own child: it remembers the registry before the
# child starts and moves away exactly the entry the child created. The entry is
# moved, not deleted: the transcript stays on disk as evidence, next to the
# registry but outside it, so the client does not show it as a project.
$ephemeralRegistries = @()
$ephemeralSnapshot = @{}
if ($EphemeralWorkspace) {
  $ephemeralRegistries = @(Get-ProjectRegistryCandidates)
  $ephemeralKey = Get-ClaudeProjectKey $WorkspaceDir
  foreach ($reg in $ephemeralRegistries) {
    if (-not (Test-Path -LiteralPath $reg -PathType Container)) { continue }
    $names = @(Get-ChildItem -LiteralPath $reg -Directory -ErrorAction SilentlyContinue | ForEach-Object { $_.Name })
    $ephemeralSnapshot[$reg] = $names
    Say ("SPAWN_EPHEMERAL_SNAPSHOT registry=" + $reg + " entries=" + $names.Count + " key=" + $ephemeralKey)
  }
}
function Clear-EphemeralProject {
  if (-not $EphemeralWorkspace) { return }
  $key = Get-ClaudeProjectKey $WorkspaceDir
  foreach ($reg in $ephemeralRegistries) {
    if (-not (Test-Path -LiteralPath $reg -PathType Container)) { continue }
    $target = Join-Path $reg $key
    if (-not (Test-Path -LiteralPath $target -PathType Container)) { continue }
    $before = @()
    if ($ephemeralSnapshot.ContainsKey($reg)) { $before = @($ephemeralSnapshot[$reg]) }
    if ($before -contains $key) {
      Say ("SPAWN_EPHEMERAL_PROJECT_KEPT registry=" + $reg + " key=" + $key + " reason=pre_existing")
      continue
    }
    try {
      # The stash sits next to the registry, not in the workspace: the registry
      # and the workspace are often on different volumes, and a move across
      # volumes is not a move.
      $stashDir = Join-Path (Split-Path -Parent $reg) '_relay-ephemeral'
      $stash = Join-Path $stashDir ($key + '-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
      if (-not (Test-Path -LiteralPath $stashDir -PathType Container)) { New-Item -ItemType Directory -Path $stashDir -Force | Out-Null }
      Move-Item -LiteralPath $target -Destination $stash -Force
      Say ("SPAWN_EPHEMERAL_PROJECT_CLEANED registry=" + $reg + " key=" + $key + " moved_to=" + $stash)
    } catch {
      Say ("WARN reason=ephemeral_project_not_cleaned registry=" + $reg + " key=" + $key + " error=" + $_.Exception.Message)
    }
  }
}

# --- 4. run ---------------------------------------------------------------------
$exeCmd = Get-Command $exe -ErrorAction SilentlyContinue
if (-not $exeCmd) {
  Release-PreAdoptedLock
  Say ("FAIL reason=runtime_cli_missing exe=" + $exe)
  exit 3
}
$outLines = @()
# The runtime must run INSIDE the chain workspace: a headless CLI takes its
# working directory from the process, and --add-dir only widens the permission
# scope. A link that starts in the wrong directory reads the wrong repo, writes
# the wrong files and still reports a clean run.
$prevCwd = (Get-Location).Path
try {
  Set-Location -LiteralPath $WorkspaceDir
  $outLines = & $exeCmd.Source @cmdArgs 2>&1 | ForEach-Object { [string]$_ }
} catch {
  Release-PreAdoptedLock
  Clear-EphemeralProject
  Say ("FAIL reason=runtime_run_threw exe=" + $exe + " error=" + $_.Exception.Message)
  exit 3
} finally {
  Set-Location -LiteralPath $prevCwd
}
$runExit = $LASTEXITCODE
Clear-EphemeralProject
$outText = ($outLines -join "`n")

# Keep the raw runtime output on disk: without it a link that did nothing is
# indistinguishable from a link that worked, because the driver only reports
# the exit code of the runtime.
$outFile = ''
try {
  $outDir = Join-Path $WorkspaceDir 'docs\relay\relay-spawn-output'
  if (-not (Test-Path -LiteralPath $outDir -PathType Container)) {
    New-Item -ItemType Directory -Path $outDir -Force | Out-Null
  }
  $outFile = Join-Path $outDir ($requestedSessionId + '.txt')
  [IO.File]::WriteAllText($outFile, $outText, [Text.UTF8Encoding]::new($false))
  Say ("SPAWN_OUTPUT_FILE path=" + $outFile + " bytes=" + (Get-Item -LiteralPath $outFile).Length)
} catch {
  Say ("WARN reason=output_not_written error=" + $_.Exception.Message)
}

if ($runExit -ne 0) {
  Release-PreAdoptedLock
  Say ("FAIL reason=runtime_run_failed exe=" + $exe + " exit=" + $runExit)
  foreach ($l in ($outLines | Select-Object -Last 20)) { Say ("SPAWN_OUTPUT " + $l) }
  exit 3
}

# --- 5. extract the session id --------------------------------------------------
$sessionId = ''
if ($Runtime -eq 'claude-code') {
  $m = [regex]::Match($outText, '"session_id"\s*:\s*"([^"]+)"')
  if ($m.Success) { $sessionId = $m.Groups[1].Value }
  if ($sessionId -eq '') { $sessionId = $requestedSessionId }
} else {
  $m = [regex]::Match($outText, '"thread_id"\s*:\s*"([^"]+)"')
  if ($m.Success) { $sessionId = $m.Groups[1].Value }
}
if ($sessionId -eq '') {
  Say ("FAIL reason=session_id_not_found runtime=" + $Runtime)
  foreach ($l in ($outLines | Select-Object -Last 20)) { Say ("SPAWN_OUTPUT " + $l) }
  exit 4
}

# --- 6. hand the lock over (only when it was not done up front) -----------------
if ($AdoptLock -and -not $preAdopted) {
  $lockScript = Join-Path $PSScriptRoot 'relay-lock.ps1'
  if (-not (Test-Path -LiteralPath $lockScript -PathType Leaf)) {
    Say ("FAIL reason=lock_script_missing path=" + $lockScript)
    exit 2
  }
  & (Get-Process -Id $PID).Path -NoProfile -ExecutionPolicy Bypass -File $lockScript -Action adopt -SessionId $sessionId -Nonce $permitNonce
  $lockExit = $LASTEXITCODE
  if ($lockExit -ne 0) {
    Say ("FAIL reason=lock_adopt_failed exit=" + $lockExit + " session_id=" + $sessionId)
    exit 3
  }
  Say ("SPAWN_LOCK_ADOPTED session_id=" + $sessionId)
} elseif ($preAdopted) {
  Say ("SPAWN_LOCK_ADOPTED session_id=" + $sessionId + " mode=pre")
}

Say ("RELAY_SPAWN_OK runtime=" + $Runtime + " session_id=" + $sessionId)
exit 0
