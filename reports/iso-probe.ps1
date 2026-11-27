$ErrorActionPreference = 'Continue'

# Part A: restore the real project dir that was moved to the trash by mistake.
$trash = 'C:\Users\Duanyi\AppData\Local\Temp\claude'
$restoreSrc = Join-Path $trash 'F--soft-00selfmade-agentask-relay'
$restoreDst = 'E:\Users\Duanyi\.claude\projects\F--soft-00selfmade-agentask-relay'
if ((Test-Path -LiteralPath $restoreSrc) -and -not (Test-Path -LiteralPath $restoreDst)) {
  [IO.Directory]::Move($restoreSrc, $restoreDst)
  Write-Output ('RESTORE moved=' + (Test-Path -LiteralPath $restoreDst))
} elseif (Test-Path -LiteralPath $restoreDst) {
  Write-Output 'RESTORE skip_target_exists'
} else {
  Write-Output 'RESTORE src_missing'
}
Write-Output ('PROJ_TOTAL=' + @(Get-ChildItem -LiteralPath 'E:\Users\Duanyi\.claude\projects' -Directory).Count)

# Part B: probe whether CLAUDE_CONFIG_DIR isolates the claude project registry.
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$iso  = Join-Path $env:TEMP ('relay-iso-probe-' + $stamp)
$cfg  = Join-Path $iso 'cfg'
$work = Join-Path $iso 'work'
New-Item -ItemType Directory -Path $cfg -Force | Out-Null
New-Item -ItemType Directory -Path $work -Force | Out-Null

$projRoot = 'E:\Users\Duanyi\.claude\projects'
$before = @(Get-ChildItem -LiteralPath $projRoot -Directory | ForEach-Object { $_.Name })

$env:CLAUDE_CONFIG_DIR = $cfg
Push-Location -LiteralPath $work
$out = & claude -p 'Reply with exactly one word: OK' --output-format json 2>&1
$code = $LASTEXITCODE
Pop-Location

$after = @(Get-ChildItem -LiteralPath $projRoot -Directory | ForEach-Object { $_.Name })
$newDirs = @($after | Where-Object { $before -notcontains $_ })

Write-Output ('CLAUDE_EXIT=' + $code)
Write-Output ('CLAUDE_OUT=' + (($out | Out-String).Trim() -replace '\s+', ' '))
Write-Output ('NEW_USER_PROJECT_DIRS=' + ($newDirs -join ','))
Write-Output ('ISO=' + $iso)
Write-Output 'CFG_TREE_BEGIN'
Get-ChildItem -LiteralPath $cfg -Recurse -Depth 2 -Force -ErrorAction SilentlyContinue | ForEach-Object { Write-Output ('CFG ' + $_.FullName.Substring($cfg.Length)) }
Write-Output 'CFG_TREE_END'
foreach ($d in $newDirs) { Write-Output ('TRASH_TARGET=' + (Join-Path $projRoot $d)) }
