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

  With -AdoptLock the relay lock is handed over to the new link by calling the sibling
  relay-lock.ps1 -Action adopt, which is the only supported way to transfer it.

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
  [string]$PermissionMode = 'acceptEdits',
  [string]$Sandbox = 'workspace-write',
  [string]$Approval = 'never',
  [int]$MaxTurns = 0,
  [switch]$Execute,
  [switch]$AdoptLock
)

$ErrorActionPreference = 'Stop'

function Say([string]$Text) { Write-Host $Text }

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
if ($MaxTurns -lt 0) { $MaxTurns = 0 }

# --- 2. build the command ------------------------------------------------------
$requestedSessionId = ''
$cmdArgs = @()
$exe = ''

if ($Runtime -eq 'claude-code') {
  $exe = 'claude'
  $requestedSessionId = [guid]::NewGuid().ToString()
  $cmdArgs = @('-p', $promptText, '--output-format', 'json', '--session-id', $requestedSessionId, '--add-dir', $WorkspaceDir)
  if (-not [string]::IsNullOrWhiteSpace($Model)) { $cmdArgs += @('--model', $Model) }
  if (-not [string]::IsNullOrWhiteSpace($PermissionMode)) { $cmdArgs += @('--permission-mode', $PermissionMode) }
  if ($MaxTurns -gt 0) { $cmdArgs += @('--max-turns', [string]$MaxTurns) }
} else {
  $exe = 'codex'
  $cmdArgs = @('exec', '--json', '--sandbox', $Sandbox, '-a', $Approval)
  if (-not [string]::IsNullOrWhiteSpace($Model)) { $cmdArgs += @('--model', $Model) }
  $cmdArgs += $promptText
}

# The printed command shows the prompt as a file reference, never inline: a prompt can
# be tens of kilobytes and a log line that long is unreadable and unquotable.
$display = @()
if ($Runtime -eq 'claude-code') {
  $display += @('-p', '<prompt from file>', '--output-format', 'json', '--session-id', $requestedSessionId, '--add-dir', $WorkspaceDir)
  if (-not [string]::IsNullOrWhiteSpace($Model)) { $display += @('--model', $Model) }
  if (-not [string]::IsNullOrWhiteSpace($PermissionMode)) { $display += @('--permission-mode', $PermissionMode) }
  if ($MaxTurns -gt 0) { $display += @('--max-turns', [string]$MaxTurns) }
} else {
  $display += @('exec', '--json', '--sandbox', $Sandbox, '-a', $Approval)
  if (-not [string]::IsNullOrWhiteSpace($Model)) { $display += @('--model', $Model) }
  $display += '<prompt from file>'
}

Say ("SPAWN_RUNTIME runtime=" + $Runtime)
Say ("SPAWN_COMMAND " + $exe + ' ' + ($display -join ' '))
Say ("SPAWN_PROMPT_FILE file=" + $promptPath + " chars=" + $promptText.Length)
Say ("SPAWN_WORKSPACE dir=" + $WorkspaceDir)

if (-not $Execute) {
  Say 'SPAWN_EXECUTE=false (add -Execute to run the command above)'
  exit 0
}

# --- 3. run ---------------------------------------------------------------------
$exeCmd = Get-Command $exe -ErrorAction SilentlyContinue
if (-not $exeCmd) {
  Say ("FAIL reason=runtime_cli_missing exe=" + $exe)
  exit 3
}
$outLines = @()
try {
  $outLines = & $exeCmd.Source @cmdArgs 2>&1 | ForEach-Object { [string]$_ }
} catch {
  Say ("FAIL reason=runtime_run_threw exe=" + $exe + " error=" + $_.Exception.Message)
  exit 3
}
$runExit = $LASTEXITCODE
$outText = ($outLines -join "`n")

if ($runExit -ne 0) {
  Say ("FAIL reason=runtime_run_failed exe=" + $exe + " exit=" + $runExit)
  foreach ($l in ($outLines | Select-Object -Last 20)) { Say ("SPAWN_OUTPUT " + $l) }
  exit 3
}

# --- 4. extract the session id --------------------------------------------------
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

# --- 5. hand the lock over -----------------------------------------------------
if ($AdoptLock) {
  $lockScript = Join-Path $PSScriptRoot 'relay-lock.ps1'
  if (-not (Test-Path -LiteralPath $lockScript -PathType Leaf)) {
    Say ("FAIL reason=lock_script_missing path=" + $lockScript)
    exit 2
  }
  & (Get-Process -Id $PID).Path -NoProfile -ExecutionPolicy Bypass -File $lockScript -Action adopt -SessionId $sessionId
  $lockExit = $LASTEXITCODE
  if ($lockExit -ne 0) {
    Say ("FAIL reason=lock_adopt_failed exit=" + $lockExit + " session_id=" + $sessionId)
    exit 3
  }
  Say ("SPAWN_LOCK_ADOPTED session_id=" + $sessionId)
}

Say ("RELAY_SPAWN_OK runtime=" + $Runtime + " session_id=" + $sessionId)
exit 0
