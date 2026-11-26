param(
  [Parameter(Mandatory = $true)][string]$Repo,
  [string]$Target = 'B20 auto finalize on a real chain: one stage, terminal flip left to the launcher'
)

$ErrorActionPreference = 'Stop'

# B21: rebuild the crash shape on a FRESH fixture built by reports\b20-e2e-setup.ps1,
# so reports\b20-verify-finalize.ps1 can produce a first-run PASS log on disk again.
#
# Honest scope: this is NOT a new real session_create chain. It replays only the
# ledger-side state machine of one stage (append_stage -> stage_done -> bump), plus
# the stage-1 artifact, so the launcher's -AutoFinalize path can be observed on a
# fixture that holds the shape the path needs. The real-chain evidence stays the
# B20 run; the B21 point is that the verifier's own log now survives.
#
# Starting shape (what b20-e2e-setup.ps1 leaves):
#   status=running current_stage=1 max_stages=1 stages=[] next_session_id=null
# Written by this script, in this order:
#   1. docs\relay\stage-1-inventory.md   every git ls-files path + bytes + total
#   2. ledger patch {"append_stage":{"id":1,"title":"inventory tracked files"}}
#   3. ledger patch {"stage_done":1,"bump_current_stage":true}
# Ending shape (what the verifier demands as its precondition):
#   status=running current_stage=2 max_stages=1 stages=[1:done] next_session_id=null
#
# Two separate commits on purpose: relay-ledger.ps1 resolves stage_done BEFORE it
# applies append_stage, so one patch carrying both fails with stage_not_found.
#
# The artifact is deliberately left untracked: committing it would add it to
# git ls-files, and the verifier requires the artifact to list every tracked path,
# which would then include itself. Untracked keeps both sides of that check honest.
#
# Every ledger write goes through relay-ledger.ps1 (lock + CAS + append-only +
# read-back). Nothing here calls Set-Content on the ledger.
#
# Pure ASCII on purpose (house rule 4).

$relay = Join-Path $Repo 'docs\relay'
$ledgerPath = Join-Path $Repo 'docs\relay.json'
$gate = Join-Path $relay 'relay-ledger.ps1'
$artifact = Join-Path $relay 'stage-1-inventory.md'

foreach ($p in @($Repo, $ledgerPath, $gate)) {
  if (-not (Test-Path -LiteralPath $p)) { Write-Host ('REBUILD_BAD_INPUT missing=' + $p); exit 2 }
}

function Read-LedgerState {
  $L = Get-Content -LiteralPath $ledgerPath -Raw -Encoding UTF8 | ConvertFrom-Json
  $st = @($L.stages)
  return [pscustomobject]@{
    Raw          = $L
    Status       = [string]$L.status
    CurrentStage = [int]$L.current_stage
    MaxStages    = [int]$L.max_stages
    Stages       = $st
    Shape        = ($st | ForEach-Object { [string]$_.id + '=' + [string]$_.status }) -join ','
    NextSession  = [string]$L.next_session_id
    Goal         = [string]$L.goal
  }
}
function Sha { return (Get-FileHash -LiteralPath $ledgerPath -Algorithm SHA256).Hash }
function Gate {
  param([string]$Label, [string[]]$Argv)
  $out = @(& pwsh -NoProfile -ExecutionPolicy Bypass -File $gate @Argv 2>&1 | ForEach-Object { [string]$_ })
  $code = $LASTEXITCODE
  Write-Host ('=== ' + $Label + ' exit=' + $code + ' ===')
  foreach ($line in $out) { Write-Host $line }
  if ($code -ne 0) { Write-Host ('REBUILD_GATE_FAIL label=' + $Label + ' exit=' + $code); exit 1 }
  return $out
}
function CommitPatch {
  param([string]$Label, [string]$PatchPath)
  $s = Sha
  Gate ($Label + '_DRYRUN') @('-Action', 'commit', '-ExpectSha256', $s, '-Patch', $PatchPath, '-DryRun') | Out-Null
  if ((Sha) -ne $s) { Write-Host ('REBUILD_DRYRUN_WROTE label=' + $Label); exit 1 }
  $lines = Gate ($Label + '_COMMIT') @('-Action', 'commit', '-ExpectSha256', $s, '-Patch', $PatchPath)
  if (-not (($lines -join "`n") -match 'LEDGER_COMMITED before=')) {
    Write-Host ('REBUILD_NO_COMMITED_LINE label=' + $Label); exit 1
  }
}

# --- precondition: a fresh fixture, nothing advanced yet -----------------------
$pre = Read-LedgerState
Write-Host ('PRE_SHAPE status=' + $pre.Status + ' current_stage=' + $pre.CurrentStage + ' max_stages=' + $pre.MaxStages +
  ' stages=[' + $pre.Shape + '] next_session_id=[' + $pre.NextSession + ']')
if ($pre.Status -ne 'running' -or $pre.CurrentStage -ne 1 -or $pre.MaxStages -ne 1 -or $pre.Stages.Count -ne 0 -or $pre.NextSession) {
  Write-Host 'REBUILD_PRECONDITION_MISMATCH hint=run_reports\b20-e2e-setup.ps1_first_and_pass_its_fresh_repo'
  exit 2
}
if ($pre.Goal -ne $Target) {
  Write-Host ('REBUILD_GOAL_MISMATCH disk=' + $pre.Goal)
  Write-Host ('REBUILD_GOAL_EXPECTED=' + $Target)
  exit 2
}

# --- 1. the stage-1 artifact --------------------------------------------------
$tracked = @(& git -C $Repo ls-files)
if ($LASTEXITCODE -ne 0 -or $tracked.Count -lt 1) {
  Write-Host ('REBUILD_NO_TRACKED_FILES in=' + $Repo + ' exit=' + $LASTEXITCODE)
  exit 2
}
$tracked = @($tracked | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ -ne '' } | Sort-Object)
$lines = New-Object System.Collections.Generic.List[string]
$lines.Add('# Stage 1 inventory: tracked files')
$lines.Add('')
$lines.Add('One line per path reported by git ls-files at the moment stage 1 closed.')
$lines.Add('Paths are kept in git form (forward slashes). Sizes are the on-disk bytes.')
$lines.Add('')
$total = 0
foreach ($rel in $tracked) {
  $full = Join-Path $Repo ($rel -replace '/', '\')
  $n = 0
  if (Test-Path -LiteralPath $full) { $n = [int](Get-Item -LiteralPath $full).Length }
  $total += $n
  $lines.Add('- ' + $rel + ' (' + $n + ' bytes)')
}
$lines.Add('')
$lines.Add('TOTAL tracked=' + $tracked.Count + ' bytes=' + $total)
$utf8 = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($artifact, (($lines -join "`n") + "`n"), $utf8)
$artifactBytes = [int](Get-Item -LiteralPath $artifact).Length
Write-Host ('ARTIFACT path=' + $artifact + ' bytes=' + $artifactBytes + ' tracked_listed=' + $tracked.Count)

$text = [IO.File]::ReadAllText($artifact, [Text.Encoding]::UTF8)
$missing = @($tracked | Where-Object { $text -notmatch [regex]::Escape($_) })
if ($missing.Count -ne 0) {
  Write-Host ('REBUILD_ARTIFACT_INCOMPLETE missing=' + $missing.Count + ' first=' + $missing[0])
  exit 2
}
Write-Host 'ARTIFACT_LISTS_TRACKED ok=true'

# --- 2 and 3. the two ledger commits -----------------------------------------
$patchDir = Join-Path ([IO.Path]::GetTempPath()) ('relay-b21-patch-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
[void](New-Item -ItemType Directory -Path $patchDir -Force)
$p1 = Join-Path $patchDir 'stage-append.json'
$p2 = Join-Path $patchDir 'stage-done.json'
[IO.File]::WriteAllText($p1, '{"append_stage":{"id":1,"title":"inventory tracked files","status":"pending"}}', $utf8)
[IO.File]::WriteAllText($p2, '{"stage_done":1,"bump_current_stage":true}', $utf8)
Write-Host ('PATCH_DIR=' + $patchDir)

Gate 'PATCH1_STATUS' @('-Action', 'status') | Out-Null
CommitPatch 'PATCH1' $p1
Gate 'PATCH2_STATUS' @('-Action', 'status') | Out-Null
CommitPatch 'PATCH2' $p2

# --- verify the rebuilt shape, read straight off the disk --------------------
$post = Read-LedgerState
$preSha = Sha
Write-Host ('POST_SHAPE status=' + $post.Status + ' current_stage=' + $post.CurrentStage + ' max_stages=' + $post.MaxStages +
  ' stages=[' + $post.Shape + '] next_session_id=[' + $post.NextSession + ']')
$ok = ($post.Status -eq 'running' -and $post.CurrentStage -eq 2 -and $post.MaxStages -eq 1 -and
  $post.Stages.Count -eq 1 -and [string]$post.Stages[0].id -eq '1' -and [string]$post.Stages[0].status -eq 'done' -and
  -not $post.NextSession -and $post.Goal -eq $Target)
if (-not $ok) { Write-Host 'REBUILD_SHAPE_WRONG hint=the_verifier_would_report_seven_red_checks'; exit 2 }

$status0 = Gate 'FINAL_STATUS' @('-Action', 'status')
if (-not (($status0 -join "`n") -match 'status=running')) {
  Write-Host 'REBUILD_GATE_DISAGREES hint=status_action_does_not_see_running'
  exit 2
}

Write-Host ('FIXTURE_REPO=' + $Repo)
Write-Host ('PRE_SHA=' + $preSha)
Write-Host 'NEXT=pwsh -NoProfile -File reports\b20-verify-finalize.ps1 -Root <fixture-root-above-repo> -ExpectPreSha ' + $preSha
Write-Host 'REBUILD_OK'
exit 0