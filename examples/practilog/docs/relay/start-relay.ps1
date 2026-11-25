<#
.SYNOPSIS
  Activate a relay (auto-advance) chain INSIDE this project, with a mutex guard.

.DESCRIPTION
  This script does NOT start a session. It performs the safety work that a
  session cannot be trusted to do on its own:

    1. workspace validation (repo root exists, is a git work tree)
    2. concurrency detection against docs\relay.json
    3. lock acquisition (docs\relay\.relay.lock, atomic CreateNew)
    4. ledger bootstrap or compatibility check (append only, never rewrite)
    5. generation of the next relay prompt (full-path pointers only)

  The caller then uses session_create with the printed prompt and adopts the
  lock to the new session id.

.EXAMPLE
  pwsh -NoProfile -File start-relay.ps1 -Target "Task 69 l10n batch" -MaxStages 6
  pwsh -NoProfile -File start-relay.ps1 -Target "..." -DryRun
#>
param(
  [Parameter(Mandatory = $true)]
  [string]$Target,

  [int]$MaxStages = 6,
  [string]$PlanDoc = 'docs\superpowers\plans\2026-11-07-b1-flutter-implementation.md',
  [string]$StageTitles = '',
  [string]$WorkspaceDir = '',
  [string]$PromptOut = '',
  [int]$TtlSeconds = 1800,
  [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
if ([string]::IsNullOrWhiteSpace($WorkspaceDir)) { $WorkspaceDir = $repoRoot }
$ledgerPath = Join-Path $repoRoot 'docs\relay.json'
$lockScript = Join-Path $PSScriptRoot 'relay-lock.ps1'
if ([string]::IsNullOrWhiteSpace($PromptOut)) { $PromptOut = Join-Path $PSScriptRoot 'next-relay-prompt.txt' }

function Say { param([string]$Line) Write-Host $Line }

# --- 1. workspace validation ------------------------------------------------
if (-not (Test-Path -LiteralPath $WorkspaceDir -PathType Container)) {
  Say "FAIL reason=workspace_missing path=$WorkspaceDir"
  exit 2
}
$gitTop = (& git -C $WorkspaceDir rev-parse --show-toplevel 2>$null)
if ([string]::IsNullOrWhiteSpace($gitTop)) {
  Say "FAIL reason=not_a_git_repo path=$WorkspaceDir"
  exit 2
}
Say "OK workspace=$($gitTop.Trim())"
$head = (& git -C $WorkspaceDir rev-parse --short HEAD).Trim()
$dirtyCount = @(& git -C $WorkspaceDir status --porcelain -uall).Count
Say "OK head=$head dirty_files=$dirtyCount"

# --- 2. concurrency detection against the ledger ----------------------------
$ledger = $null
if (Test-Path -LiteralPath $ledgerPath) {
  $raw = Get-Content -LiteralPath $ledgerPath -Raw -Encoding UTF8
  $ledgerHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $ledgerPath).Hash
  try { $ledger = $raw | ConvertFrom-Json } catch {
    Say "FAIL reason=ledger_unparsable path=$ledgerPath"
    exit 3
  }
  Say "OK ledger_sha256=$ledgerHash status=$($ledger.status) current_stage=$($ledger.current_stage) stages=$($ledger.stages.Count) sessions=$($ledger.sessions.Count)"

  $inProgress = @($ledger.stages | Where-Object { $_.status -eq 'in_progress' })
  if ($inProgress.Count -gt 0) {
    foreach ($s in $inProgress) {
      Say "CONFLICT stage=$($s.stage) session=$($s.session_id) status=$($s.status)"
    }
    Say 'FAIL reason=stage_in_progress rule=one_writer_per_project'
    exit 3
  }

  if ($ledger.status -eq 'running' -and -not [string]::IsNullOrWhiteSpace($ledger.next_session_id)) {
    Say "FAIL reason=chain_already_running next_session_id=$($ledger.next_session_id)"
    exit 3
  }
  if ($ledger.status -eq 'done' -and [int]$ledger.current_stage -ge [int]$ledger.max_stages) {
    Say "FAIL reason=chain_exhausted current_stage=$($ledger.current_stage) max_stages=$($ledger.max_stages)"
    Say 'HINT=start a fresh chain by passing -MaxStages greater than the previous chain, or archive the old ledger.'
    exit 3
  }
  if ($ledger.status -eq 'blocked') {
    Say "WARN reason=ledger_blocked blocked_on=$($ledger.blocked_on -join ',')"
    Say 'HINT=blocked chains need a human decision first; do not silently resume.'
    exit 3
  }
} else {
  Say "OK ledger_absent path=$ledgerPath (will bootstrap)"
}

# --- 3. lock acquisition ----------------------------------------------------
if ($DryRun) {
  Say 'DRYRUN skip=lock_acquire skip=ledger_bootstrap skip=prompt_write'
} else {
  & $lockScript -Action acquire -Stage 1 -Title 'relay-start' -TtlSeconds $TtlSeconds
  if ($LASTEXITCODE -ne 0) {
    Say "FAIL reason=lock_unavailable exit=$LASTEXITCODE"
    exit 4
  }
}

# --- 4. ledger bootstrap (create only; never rewrite an existing ledger) -----
if (-not $DryRun -and -not (Test-Path -LiteralPath $ledgerPath)) {
  $now = [DateTimeOffset]::Now.ToString('o')
  $seed = [ordered]@{
    goal            = $Target
    plan_doc        = $PlanDoc
    ledger_docs     = @('docs\relay\stage-1-inventory.md')
    workspace_dir   = $repoRoot
    status          = 'running'
    auto_relay      = $true
    current_stage   = 1
    max_stages      = $MaxStages
    next_session_id = $null
    started_at      = $now
    started_by      = "start-relay.ps1"
    protocol        = 'docs\AGENT-RELAY.md'
    adaptation_note = 'docs\RELAY-ADAPTATION.md'
    concurrency     = 'relay-lock.ps1 (atomic CreateNew) + one in_progress stage at a time'
    next_stage_target = $Target
    model_policy    = [ordered]@{
      preferred            = 'minimax/MiniMax-M3'
      fallback_day         = 'custom_provider:provider-aa5659/auto'
      fallback_night       = 'custom_provider:provider-aa5659/deepseek-v4.1-flash-1017'
      fallback_day_window  = '08:00-19:00 Asia/Shanghai'
      fallback_night_window = '19:01-08:00 Asia/Shanghai'
      effort_note          = 'session_create has no effort field; never pass it.'
    }
    human_checkpoints = @(
      'git commit / push / tag',
      'release or distribution of artifacts',
      'deletion or overwrite of user data',
      'changes to user level hooks or provider config',
      'paid, quota, account or permission decisions',
      'ambiguous or contradictory acceptance criteria',
      'write set conflict with a concurrent session'
    )
    stop_conditions   = @(
      'all acceptance criteria closed and gate green',
      'human checkpoint hit -> status=blocked',
      'current_stage >= max_stages -> status=blocked',
      'same acceptance failed twice -> status=blocked',
      'two consecutive stages over the tool call budget -> status=blocked'
    )
    stages            = @()
    sessions          = @()
  }
  $json = $seed | ConvertTo-Json -Depth 6
  [IO.File]::WriteAllText($ledgerPath, $json, [Text.UTF8Encoding]::new($false))
  Say "OK ledger_bootstrapped path=$ledgerPath bytes=$((Get-Item $ledgerPath).Length)"
}

# --- 5. next relay prompt (full path pointers only) -------------------------
$stageList = if ([string]::IsNullOrWhiteSpace($StageTitles)) {
  '1. stage 1 scope inventory'
} else {
  $StageTitles
}
$prompt = @"
You are relay stage 1 of an unattended relay chain in this repository.

WORKSPACE: $repoRoot (absolute path, backslashes). Work only inside it.

READ FIRST (full paths, read in this order):
1. $repoRoot\docs\relay.json            (state machine truth)
2. $repoRoot\docs\AGENT-RELAY.md        (protocol)
3. $repoRoot\docs\RELAY-ADAPTATION.md   (project adjudication)
4. $repoRoot\$PlanDoc                   (source of truth for the target batch)
5. $repoRoot\docs\relay\start-relay.ps1 (this launcher, for the next stage)
6. $repoRoot\docs\relay\relay-lock.ps1  (lock protocol)

TARGET: $Target

STAGE PLAN:
$stageList

RULES:
- Validate docs\relay.json before touching anything: status must be running, current_stage must equal your stage, current_stage must not exceed max_stages. If any check fails, write status=blocked, explain what is missing, and stop.
- Exactly one stage per session. A stage owns a declared write set; the controller never edits product code directly, dispatch a worker sub-session for code changes and state the single allowed write set in the dispatch brief.
- Never pass an effort field to session_create (the schema has no such field).
- Concurrency: the lock file docs\relay\.relay.lock is owned by you. Call relay-lock.ps1 -Action renew every few turns. Do not create a second chain while the ledger has an in_progress stage.
- Git write operations (commit, push, tag, stash, checkout) are a human checkpoint: never perform them, stop and report instead.
- Write intermediate artifacts to files. Keep the conversation to pointers and conclusions. Do not fabricate acceptance evidence.
- On completion: write docs\relay\stage-1-inventory.md, then append your own entry to docs\relay.json (reload it before merging, append only), then start the next stage with session_create using the same recipe, then call relay-lock.ps1 -Action adopt -SessionId <new session id>.
- If the chain must stop: write status=blocked with what is missing, release the lock with relay-lock.ps1 -Action release, and explain in the final reply. Never start a next session in that case.
"@

if ($DryRun) {
  Say 'DRYRUN prompt_preview_begin'
  Write-Host $prompt
  Say 'DRYRUN prompt_preview_end'
} else {
  [IO.File]::WriteAllText($PromptOut, $prompt, [Text.UTF8Encoding]::new($false))
  Say "OK prompt_written path=$PromptOut bytes=$((Get-Item $PromptOut).Length)"
  Say 'NEXT call session_create with agent_name=me, title=relay-1-<short>, workspace_dir=<repoRoot backslashes>, content=<contents of the prompt file>'
  Say 'NEXT then run relay-lock.ps1 -Action adopt -SessionId <new session id>'
}
Say "DONE exit=0 target=$Target"
exit 0
