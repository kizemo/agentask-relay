$ErrorActionPreference = 'Continue'

# Capture the next-relay prompt of a fixture chain as evidence that the
# ephemeral flag really travels into the spawn command of the prompt.
# Writes only under $env:TEMP, plus one snapshot under tool\references\.
$repo = 'F:\soft\00selfmade\agentask-relay'
$pwsh = (Get-Process -Id $PID).Path
$root = Join-Path $env:TEMP ('relay-nextprompt-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
$fix = Join-Path $root 'repo'
New-Item -ItemType Directory -Path (Join-Path $fix 'docs') -Force | Out-Null
Set-Content -LiteralPath (Join-Path $fix 'README.md') -Value '# next prompt fixture' -Encoding utf8
Set-Content -LiteralPath (Join-Path $fix 'AGENTS.md') -Value '# fixture rules' -Encoding utf8
& git -C $fix init -q 2>&1 | Out-Null
& git -C $fix -c user.name='relay-fixture' -c user.email='relay@example.invalid' add -A 2>&1 | Out-Null
& git -C $fix -c user.name='relay-fixture' -c user.email='relay@example.invalid' commit -q -m 'fixture' 2>&1 | Out-Null
Set-Content -LiteralPath (Join-Path $fix 'docs\plan-b22.md') -Value '# plan b22' -Encoding utf8
& git -C $fix -c user.name='relay-fixture' -c user.email='relay@example.invalid' add -A 2>&1 | Out-Null
& git -C $fix -c user.name='relay-fixture' -c user.email='relay@example.invalid' commit -q -m 'plan' 2>&1 | Out-Null

$ins = & $pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repo 'tool\scripts\install-relay.ps1') `
  -RepoRoot $fix -Target 'B22 ephemeral next prompt' -PlanDoc 'docs\plan-b22.md' -MaxStages 2 -Runtime claude-code *>&1 |
  ForEach-Object { $_.ToString() }
"INSTALL_EXIT=$LASTEXITCODE"
foreach ($l in $ins) { if ($l -match 'INSTALL_VERDICT|INSTALL_RUNTIME|FAIL') { "INSTALL_LINE " + $l.Trim() } }

$l = & $pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $fix 'docs\relay\start-relay.ps1') `
  -Target 'B22 ephemeral next prompt' -MaxStages 2 -EphemeralWorkspace *>&1 | ForEach-Object { $_.ToString() }
"LAUNCH_EXIT=$LASTEXITCODE"
foreach ($x in $l) { if ($x -match 'prompt_written|LOCK_|FAIL') { "LAUNCH_LINE " + $x.Trim() } }

$prompt = Join-Path $fix 'docs\relay\next-relay-prompt.txt'
"PROMPT_EXISTS=" + (Test-Path -LiteralPath $prompt)
if (Test-Path -LiteralPath $prompt) {
  $text = [IO.File]::ReadAllText($prompt)
  "PROMPT_BYTES=" + (Get-Item -LiteralPath $prompt).Length
  "PROMPT_HAS_FLAG=" + ($text -match '-EphemeralWorkspace')
  $dest = Join-Path $repo 'tool\references\next-prompt-2026-11-27-b22.txt'
  [IO.File]::WriteAllText($dest, ($text -replace "`r`n", "`n"), (New-Object Text.UTF8Encoding($false)))
  "SNAPSHOT=" + $dest + " bytes=" + (Get-Item -LiteralPath $dest).Length
}
"ROOT=$root"
