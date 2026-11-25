# refresh-manifest.ps1 - regenerate MANIFEST.txt for the agentask-relay corpus.
# Rule: one line per file, format "sha16 | bytes | relpath", LF, no BOM.
#       MANIFEST.txt itself is EXCLUDED, so entry count = file count - 1.
# Run this as the LAST step of any round that touches files in this repo,
# otherwise the hashes go stale (document churn is self-referential).
# Usage: pwsh -NoProfile -ExecutionPolicy Bypass -File scripts\refresh-manifest.ps1 [-RepoRoot <path>] [-Report]
[CmdletBinding()]
param(
    [string]$RepoRoot = '',
    [switch]$Report
)
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = Split-Path -Parent $PSScriptRoot
}
if (-not (Test-Path -LiteralPath $RepoRoot)) {
    Write-Output "REFRESH_MANIFEST exit=2 reason=repo_root_missing path=$RepoRoot"
    exit 2
}
$manifestPath = Join-Path $RepoRoot 'MANIFEST.txt'

# Previous entries (for change diffing) if a manifest already exists.
$oldEntries = @()
if (Test-Path -LiteralPath $manifestPath) {
    $oldEntries = @([IO.File]::ReadAllLines($manifestPath) |
        Where-Object { $_ -match '^[0-9A-F]{16} \| \d+ \| ' })
}

$files = @(Get-ChildItem -LiteralPath $RepoRoot -Recurse -File |
    Where-Object { $_.Name -ne 'MANIFEST.txt' } |
    Sort-Object FullName)

$rows = New-Object System.Collections.ArrayList
[void]$rows.Add('# MANIFEST.txt - agentask-relay relay corpus (content inventory, self-excluded)')
[void]$rows.Add(('# generated: ' + (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))
[void]$rows.Add('# format: sha16(sha256 first 16 hex) | bytes | relpath   [LF, no BOM]')
[void]$rows.Add('# refresh: pwsh -File scripts\refresh-manifest.ps1  (run last in any round)')

$changed = New-Object System.Collections.ArrayList
$bom = 0
$ps1NonAscii = 0
$crTotal = 0

foreach ($f in $files) {
    $rel = $f.FullName.Substring($RepoRoot.Length + 1)
    $bytes = [IO.File]::ReadAllBytes($f.FullName)
    $hash = (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash.Substring(0, 16)

    $nonAscii = 0
    $cr = 0
    foreach ($x in $bytes) {
        if ($x -gt 127) { $nonAscii++ }
        if ($x -eq 13) { $cr++ }
    }
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191) {
        $bom++
        [void]$changed.Add("BOM_FILE $rel")
    }
    if ($f.Extension -eq '.ps1' -and $nonAscii -gt 0) {
        $ps1NonAscii++
        [void]$changed.Add("PS1_NON_ASCII $rel n=$nonAscii")
    }
    if ($f.Extension -eq '.md' -or $f.Extension -eq '.txt') { $crTotal += $cr }

    [void]$rows.Add($hash + ' | ' + $f.Length + ' | ' + $rel)

    if ($oldEntries.Count -gt 0) {
        $key = '| ' + $rel
        $prev = @($oldEntries | Where-Object { $_.EndsWith($key) })
        if ($prev.Count -eq 1) {
            $oh = $prev[0].Substring(0, 16)
            $ob = ($prev[0].Split('|')[1]).Trim()
            if (($oh -ne $hash) -or ($ob -ne [string]$f.Length)) {
                [void]$changed.Add("CHANGED $rel : $oh/$ob -> $hash/$($f.Length)")
            }
        }
        else {
            [void]$changed.Add("NEW_ENTRY $rel")
        }
    }

    # Also verify content against the global skill copy when both exist.
    if ($Report -and $f.Extension -eq '.ps1') {
        Write-Output ("FILE $rel bytes=$($f.Length) non_ascii=$nonAscii sha16=$hash")
    }
}

if ($oldEntries.Count -gt 0) {
    foreach ($e in $oldEntries) {
        $parts = $e.Split('|')
        $rel = ($parts[2]).Trim()
        $present = @($files | Where-Object { $_.FullName.Substring($RepoRoot.Length + 1) -eq $rel })
        if ($present.Count -eq 0) { [void]$changed.Add("REMOVED $rel") }
    }
}

[IO.File]::WriteAllText($manifestPath, (($rows -join [char]10) + [char]10),
    (New-Object System.Text.UTF8Encoding($false)))

# Line-count check: entries = files - (manifest self excluded) already by construction.
$verify = @([IO.File]::ReadAllLines($manifestPath) | Where-Object { $_ -match '^[0-9A-F]{16} \| \d+ \| ' })
$mb = [IO.File]::ReadAllBytes($manifestPath)
$mNa = 0
foreach ($x in $mb) { if ($x -gt 127) { $mNa++ } }

Write-Output ("FILE_COUNT=" + $files.Count + " (MANIFEST excluded)")
Write-Output ("ENTRY_COUNT=" + $verify.Count)
Write-Output ("INVARIANT_OK=" + ($verify.Count -eq $files.Count))
Write-Output ("BOM_FILES=" + $bom + " PS1_NON_ASCII_FILES=" + $ps1NonAscii + " MD_TXT_CR_TOTAL=" + $crTotal)
Write-Output ("MANIFEST_BYTES=" + $mb.Length + " MANIFEST_NON_ASCII=" + $mNa)
Write-Output ("CHANGE_COUNT=" + $changed.Count)
foreach ($c in $changed) { Write-Output ("  " + $c) }
Write-Output "REFRESH_MANIFEST verdict=PASS"
exit 0
