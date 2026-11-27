$ErrorActionPreference = 'Continue'

# Restore the real project dir that was moved to the trash by mistake.
# The trash lives on C: and the target lives on E:, so Directory.Move cannot
# cross the volume boundary: copy first, then the source is dropped.
$trash = 'C:\Users\Duanyi\AppData\Local\Temp\claude'
$src = Join-Path $trash 'F--soft-00selfmade-agentask-relay'
$dst = 'E:\Users\Duanyi\.claude\projects\F--soft-00selfmade-agentask-relay'

if (Test-Path -LiteralPath $dst) {
  Write-Output 'RESTORE skip_target_exists'
} elseif (Test-Path -LiteralPath $src) {
  Copy-Item -LiteralPath $src -Destination $dst -Recurse -Force
} else {
  Write-Output 'RESTORE src_missing'
}

# The copy on disk is the proof that the restore worked: only then may the
# temporary duplicate be dropped.
$restored = @(Get-ChildItem -LiteralPath $dst -File -Recurse -ErrorAction SilentlyContinue).Count
Write-Output ('RESTORE_VERIFY files=' + $restored)
if ($restored -gt 0 -and (Test-Path -LiteralPath $src)) {
  Remove-Item -LiteralPath $src -Recurse -Force
  Write-Output ('TEMP_DUPLICATE_REMOVED=' + (-not (Test-Path -LiteralPath $src)))
}

$all = @(Get-ChildItem -LiteralPath 'E:\Users\Duanyi\.claude\projects' -Directory | ForEach-Object { $_.Name })
Write-Output ('PROJ_TOTAL=' + $all.Count)
$all | ForEach-Object { Write-Output ('PROJ ' + $_) }
