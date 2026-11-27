$ErrorActionPreference = 'Continue'

# Focused probe for the two new behaviours of case 27:
#   1. the spawn driver moves the project entry its own child created away
#   2. the launcher carries the flag into the spawn command of the prompt
# Writes only under $env:TEMP. Pure ASCII, no BOM.

$repo = 'F:\soft\00selfmade\agentask-relay'
$tpl = Join-Path $repo 'tool\templates'
$pwsh = (Get-Process -Id $PID).Path
$root = Join-Path $env:TEMP ('relay-case27-probe-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Path $root -Force | Out-Null

$shimDir = Join-Path $root 'shim'
$cfgA = Join-Path $root 'cfgA'
$cfgB = Join-Path $root 'cfgB'
New-Item -ItemType Directory -Path $shimDir -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $cfgA 'projects') -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $cfgB 'projects') -Force | Out-Null

$shim = Join-Path $shimDir 'claude.cmd'
$body = @'
@echo off
setlocal
if not exist "%RELAY_TEST_REGISTRY%\%RELAY_TEST_PROJECT_KEY%" mkdir "%RELAY_TEST_REGISTRY%\%RELAY_TEST_PROJECT_KEY%"
echo {"type":"result","session_id":"22222222-3333-4444-5555-666666666666","result":"ok"}
exit /b 0
'@
[IO.File]::WriteAllText($shim, ($body -replace "`r`n", "`n"), (New-Object Text.UTF8Encoding($false)))

$work = Join-Path $root 'repo'
New-Item -ItemType Directory -Path (Join-Path $work 'docs') -Force | Out-Null
Set-Content -LiteralPath (Join-Path $work 'README.md') -Value '# probe' -Encoding utf8
& git -C $work init -q 2>&1 | Out-Null
$prompt = Join-Path $root 'prompt.txt'
[IO.File]::WriteAllText($prompt, ("probe`n"), (New-Object Text.UTF8Encoding($false)))
$key = ($work -replace '[^A-Za-z0-9]', '-')

function Invoke-Spawn([string]$Cfg, [bool]$Ephemeral) {
  $env:PATH = $shimDir + [IO.Path]::PathSeparator + $env:PATH
  $env:CLAUDE_CONFIG_DIR = $Cfg
  $env:RELAY_TEST_REGISTRY = (Join-Path $Cfg 'projects')
  $env:RELAY_TEST_PROJECT_KEY = $key
  $argv = @('-Runtime', 'claude-code', '-PromptFile', $prompt, '-WorkspaceDir', $work, '-Execute')
  if ($Ephemeral) { $argv += '-EphemeralWorkspace' }
  $out = & $pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $tpl 'relay-spawn.ps1') @argv *>&1 | ForEach-Object { $_.ToString() }
  return [pscustomobject]@{ Code = $LASTEXITCODE; Text = ($out -join "`n") }
}

$a = Invoke-Spawn $cfgA $false
"RUN_A_EXIT=" + $a.Code
"RUN_A_ENTRY_EXISTS=" + (Test-Path -LiteralPath (Join-Path (Join-Path $cfgA 'projects') $key))
$b = Invoke-Spawn $cfgB $true
"RUN_B_EXIT=" + $b.Code
foreach ($l in ($b.Text -split "`n")) { if ($l -match 'SPAWN_EPHEMERAL') { "RUN_B_LINE " + $l.Trim() } }
"RUN_B_ENTRY_EXISTS=" + (Test-Path -LiteralPath (Join-Path (Join-Path $cfgB 'projects') $key))
"RUN_B_STASH_EXISTS=" + (Test-Path -LiteralPath (Join-Path $cfgB '_relay-ephemeral'))
"RUN_A_ENTRY_STILL_THERE=" + (Test-Path -LiteralPath (Join-Path (Join-Path $cfgA 'projects') $key))

'--- launcher carries the flag ---'
$fixRepo = Join-Path $root 'fixrepo'
New-Item -ItemType Directory -Path (Join-Path $fixRepo 'docs') -Force | Out-Null
Set-Content -LiteralPath (Join-Path $fixRepo 'README.md') -Value '# fix' -Encoding utf8
Set-Content -LiteralPath (Join-Path $fixRepo 'AGENTS.md') -Value '# rules' -Encoding utf8
& git -C $fixRepo init -q 2>&1 | Out-Null
Set-Content -LiteralPath (Join-Path $fixRepo 'docs\plan-27.md') -Value '# plan 27' -Encoding utf8
$ins = & $pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repo 'tool\scripts\install-relay.ps1') -RepoRoot $fixRepo -Target 'e27' -PlanDoc 'docs\plan-27.md' -MaxStages 2 -Runtime claude-code *>&1 | ForEach-Object { $_.ToString() }
"INSTALL_EXIT=$LASTEXITCODE"
foreach ($l in $ins) { if ($l -match 'INSTALL_VERDICT|FAIL') { "INSTALL_LINE " + $l.Trim() } }
$l27 = & $pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $fixRepo 'docs\relay\start-relay.ps1') -Target 'e27' -MaxStages 2 -EphemeralWorkspace -DryRun *>&1 | ForEach-Object { $_.ToString() }
"LAUNCH_EXIT=$LASTEXITCODE"
foreach ($l in $l27) { if ($l -match 'relay-spawn') { "PROMPT_LINE " + $l.Trim() } }
$l27b = & $pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $fixRepo 'docs\relay\start-relay.ps1') -Target 'e27' -MaxStages 2 -DryRun *>&1 | ForEach-Object { $_.ToString() }
$flagInDefault = @($l27b | Where-Object { $_ -match '-EphemeralWorkspace' }).Count
"DEFAULT_PROMPT_FLAG_HITS=$flagInDefault"
"PROBE_ROOT=$root"
