#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][ValidateSet('1', '2')][string]$Phase,
    [string]$SpecPath = 'F:\soft\00selfmade\agentask-relay\reports\b24-spec.txt',
    [string]$RepoRoot = 'F:\soft\00selfmade\agentask-relay',
    [string]$EvidencePath = '',
    [string]$RawLogRel = 'tool/references/selftest-2026-11-27-b24.txt'
)

$ErrorActionPreference = 'Stop'
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$fail = 0

function Read-TextLf {
    param([string]$Path)
    $t = [IO.File]::ReadAllText($Path)
    if ($t.Length -gt 0 -and $t[0] -eq [char]0xFEFF) { $t = $t.Substring(1) }
    $t = $t -replace "`r`n", "`n"
    $t = $t -replace "`r", "`n"
    return $t
}

function Write-TextNoBom {
    param([string]$Path, [string]$Text)
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        [void](New-Item -ItemType Directory -Path $dir -Force)
    }
    [IO.File]::WriteAllText($Path, $Text, $utf8NoBom)
}

function Count-Occurrence {
    param([string]$Haystack, [string]$Needle)
    if ([string]::IsNullOrEmpty($Needle)) { return 0 }
    $n = 0
    $i = 0
    while ($true) {
        $j = $Haystack.IndexOf($Needle, $i, [StringComparison]::Ordinal)
        if ($j -lt 0) { break }
        $n++
        $i = $j + $Needle.Length
    }
    return $n
}

# ---- 1. parse spec ---------------------------------------------------------
if (-not (Test-Path -LiteralPath $SpecPath)) {
    Write-Host ('APPLY_FAIL reason=spec_missing path=' + $SpecPath)
    exit 5
}

$specText = Read-TextLf -Path $SpecPath
$specLines = $specText.Split("`n")

$blocks = New-Object System.Collections.ArrayList
$curPhase = '1'
$blk = $null
$sect = ''
foreach ($ln in $specLines) {
    if ($null -eq $blk) {
        if ($ln -eq '###PHASE 2') { $curPhase = '2'; continue }
        if ($ln -eq '###PHASE 1') { $curPhase = '1'; continue }
        if ($ln.StartsWith('###EDIT ')) {
            $blk = [pscustomobject]@{
                Path  = $ln.Substring(8).Trim()
                Phase = $curPhase
                Old   = (New-Object System.Collections.ArrayList)
                New   = (New-Object System.Collections.ArrayList)
            }
            $sect = ''
            continue
        }
        if ($ln.Trim().Length -eq 0) { continue }
        Write-Host ('APPLY_FAIL reason=stray_line text=' + $ln)
        exit 2
    }
    if ($ln -eq '###OLD###') { $sect = 'old'; continue }
    if ($ln -eq '###NEW###') { $sect = 'new'; continue }
    if ($ln -eq '###END###') {
        [void]$blocks.Add($blk)
        $blk = $null
        $sect = ''
        continue
    }
    if ($sect -eq 'old') { [void]$blk.Old.Add($ln) }
    elseif ($sect -eq 'new') { [void]$blk.New.Add($ln) }
    else {
        Write-Host ('APPLY_FAIL reason=line_outside_section text=' + $ln)
        exit 2
    }
}
if ($null -ne $blk) {
    Write-Host ('APPLY_FAIL reason=unterminated_block path=' + $blk.Path)
    exit 2
}

$sel = @($blocks | Where-Object { $_.Phase -eq $Phase })
Write-Host ('SPEC path=' + $SpecPath + ' blocks_total=' + $blocks.Count + ' selected=' + $sel.Count + ' phase=' + $Phase)
if ($sel.Count -eq 0) {
    Write-Host 'APPLY_FAIL reason=no_blocks_for_phase'
    exit 2
}

# ---- 2. apply patches ------------------------------------------------------
$touched = New-Object System.Collections.ArrayList
$idx = 0
foreach ($b in $sel) {
    $idx++
    $target = $b.Path
    if (-not [IO.Path]::IsPathRooted($target)) { $target = Join-Path $RepoRoot $target }
    $old = (@($b.Old) -join "`n").TrimEnd("`n")
    $new = (@($b.New) -join "`n")

    if (-not (Test-Path -LiteralPath $target)) {
        if ($old.Length -ne 0) {
            Write-Host ('PATCH_FAIL n=' + $idx + ' path=' + $target + ' reason=target_missing')
            $fail++
            continue
        }
        $eol = "`n"
        $t = ''
        $mode = 'create'
    }
    else {
        $t = Read-TextLf -Path $target
        if ($t.Contains("`r`n")) { $eol = "`r`n" } else { $eol = "`n" }
        $mode = 'replace'
    }

    $newNorm = $new -replace "`n", $eol
    if ($old.Length -eq 0) {
        if ($mode -eq 'replace') {
            if ($t.Contains($newNorm)) {
                if (-not $touched.Contains($target)) { [void]$touched.Add($target) }
                Write-Host ('PATCH_SKIP n=' + $idx + ' path=' + $target + ' reason=already_appended')
                continue
            }
            if ($t.Length -gt 0 -and -not $t.EndsWith("`n")) { $t = $t + $eol }
            $mode = 'append'
        }
        $out = $t + $newNorm + $eol
    }
    else {
        $oldNorm = $old -replace "`n", $eol
        $cnt = Count-Occurrence -Haystack $t -Needle $oldNorm
        if ($cnt -eq 0) {
            if ((Count-Occurrence -Haystack $t -Needle $newNorm) -gt 0) {
                if (-not $touched.Contains($target)) { [void]$touched.Add($target) }
                Write-Host ('PATCH_SKIP n=' + $idx + ' path=' + $target + ' reason=already_applied')
                continue
            }
            Write-Host ('PATCH_FAIL n=' + $idx + ' path=' + $target + ' reason=anchor_missing')
            $fail++
            continue
        }
        if ($cnt -gt 1) {
            Write-Host ('PATCH_FAIL n=' + $idx + ' path=' + $target + ' reason=anchor_not_unique count=' + $cnt)
            $fail++
            continue
        }
        $out = $t.Replace($oldNorm, $newNorm)
    }

    Write-TextNoBom -Path $target -Text $out
    $bytes = [IO.File]::ReadAllBytes($target).Length
    if (-not $touched.Contains($target)) { [void]$touched.Add($target) }
    Write-Host ('PATCH_OK n=' + $idx + ' mode=' + $mode + ' path=' + $target + ' bytes=' + $bytes)
}

if ($fail -gt 0) {
    Write-Host ('APPLY_END phase=' + $Phase + ' fail=' + $fail + ' exit=3')
    exit 3
}

# ---- 3. phase 2 placeholders ----------------------------------------------
if ($Phase -eq '2') {
    if ([string]::IsNullOrEmpty($EvidencePath)) {
        Write-Host 'APPLY_FAIL reason=evidence_path_required_for_phase_2'
        exit 2
    }
    if (-not (Test-Path -LiteralPath $EvidencePath)) {
        Write-Host ('APPLY_FAIL reason=evidence_missing path=' + $EvidencePath)
        exit 5
    }

    $rawText = Read-TextLf -Path $EvidencePath
    $rawTarget = Join-Path $RepoRoot $RawLogRel
    Write-TextNoBom -Path $rawTarget -Text $rawText
    $rawBytes = [IO.File]::ReadAllBytes($rawTarget).Length
    $rawLines = ([IO.File]::ReadAllText($rawTarget) -split "`n").Count
    $rawSha = (Get-FileHash -Algorithm SHA256 -LiteralPath $rawTarget).Hash

    $suiteLine = ''
    $exitVal = ''
    foreach ($ln in $rawText.Split("`n")) {
        $s = $ln -replace '^\d{2}:\d{2}:\d{2}\s+', ''
        if ($s -match '^SUITE_END ') { $suiteLine = $s.Trim() }
        if ($s -match '^SELFTEST_EXIT=(\d+)') { $exitVal = $Matches[1] }
    }
    if ([string]::IsNullOrEmpty($suiteLine)) {
        Write-Host 'APPLY_FAIL reason=suite_end_line_not_found'
        exit 5
    }
    if ([string]::IsNullOrEmpty($exitVal)) {
        if ($suiteLine -match 'fail=(\d+)') {
            if ($Matches[1] -eq '0') { $exitVal = '0' } else { $exitVal = '1' }
        }
    }
    if ([string]::IsNullOrEmpty($exitVal)) {
        Write-Host 'APPLY_FAIL reason=selftest_exit_line_not_found'
        exit 5
    }

    Write-Host ('RAWLOG path=' + $rawTarget + ' bytes=' + $rawBytes + ' lines=' + $rawLines + ' sha=' + $rawSha)
    Write-Host ('EVIDENCE suite=' + $suiteLine + ' exit=' + $exitVal)

    $map = @{
        '@@SUITE@@'  = $suiteLine
        '@@EXIT@@'   = $exitVal
        '@@RAWLOG@@' = $RawLogRel
        '@@BYTES@@'  = [string]$rawBytes
        '@@LINES@@'  = [string]$rawLines
        '@@SHA@@'    = $rawSha
    }

    $total = 0
    foreach ($p in $touched) {
        $t = Read-TextLf -Path $p
        $hit = 0
        foreach ($k in $map.Keys) {
            $c = Count-Occurrence -Haystack $t -Needle $k
            if ($c -gt 0) { $hit += $c; $t = $t.Replace($k, $map[$k]) }
        }
        if ($hit -gt 0) {
            Write-TextNoBom -Path $p -Text $t
            $total += $hit
            Write-Host ('PLACEHOLDER_OK path=' + $p + ' replaced=' + $hit)
        }
    }
    Write-Host ('PLACEHOLDER_END replaced=' + $total)
}

Write-Host ('APPLY_END phase=' + $Phase + ' patches=' + $sel.Count + ' fail=0 exit=0')
exit 0