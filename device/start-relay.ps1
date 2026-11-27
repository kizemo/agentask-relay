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

  The caller then starts the next link with whatever the runtime uses: the
  built-in session_create tool on MCode, the spawn driver (relay-spawn.ps1) on a
  CLI runtime. The runtime is read from docs\relay\relay-runtime.json, which the
  installer stamps, or from -Runtime; without either, mcode is assumed.

.EXAMPLE
  pwsh -NoProfile -File start-relay.ps1 -Target "Task 69 l10n batch" -MaxStages 6
  pwsh -NoProfile -File start-relay.ps1 -Target "..." -DryRun
#>
param(
  # Target of the chain. The emptiness check lives in the body of the script
  # and not in the parameter binder: a mandatory parameter turns an empty
  # -Target into a binder error, and the script then ends with exit 1 and a
  # stack trace, which is outside the published exit code contract.
  [string]$Target,

  # Maximum number of stages of the chain. Typed as a string on purpose: a
  # non numeric value has to be refused with a verdict line, and a typed
  # integer is rejected by the binder before the script can say anything.
  [string]$MaxStages = '6',
  # Plan document, resolved at runtime. It used to default to one specific
  # project's plan path, which leaked a foreign file name into every fresh
  # chain. Resolution order now: this argument, then plan_doc in
  # docs\relay.json, then a probe of docs\plan-*.md, docs\plans\*.md and
  # docs\superpowers\plans\*.md. If nothing resolves, or the resolved file
  # does not exist, the launcher stops with exit 2 BEFORE taking the lock.
  [string]$PlanDoc = '',
  [string]$StageTitles = '',
  [string]$WorkspaceDir = '',
  [string]$PromptOut = '',
  # Lifetime of the chain lock in seconds. 0 means "the caller named no
  # value": the effective TTL is then the one the installer stamped into
  # docs\relay\relay-runtime.json (lock_ttl_seconds), and 1800 only when the
  # descriptor does not name one either. Typed as a string on purpose, like
  # -MaxStages: a typed integer is refused by the parameter binder before the
  # script can say anything, and that ends the run with exit 1 and a stack
  # trace, which is outside the published exit code contract.
  [string]$TtlSeconds = '0',
  # Runtime the chain runs on. Empty means "read it from the descriptor the
  # installer stamped into docs\relay\relay-runtime.json"; when that file is
  # absent too, the launcher falls back to mcode, which is exactly what this
  # script did before the runtime adaptation layer existed.
  [string]$Runtime = '',
  [switch]$DryRun,
  # Opt-in managed close (B19). When the chain sits at its stage cap and every
  # declared stage already reads done, the cap gate may flip the terminal status
  # itself instead of only telling the reader how to do it. Off by default: a
  # launcher that silently rewrote the ledger would break the promise that only a
  # human starts a chain. Even when on, the write still goes through
  # relay-ledger.ps1 (writer lock + CAS + append only rules + readback).
  [switch]$AutoFinalize,
  # Ephemeral workspace (B22). Off by default: a real project MUST stay visible
  # in the client project list. Only a throwaway fixture wants the entry gone,
  # and then the spawn command in the prompt carries the flag.
  [switch]$EphemeralWorkspace,

  # Host project (B23, promoted to a knob in B24). The project key every link
  # must pass as session_create project=, i.e. one workspace_dir of the client
  # project list, verbatim. Empty means "the repository root is the key". When a
  # value is recorded and it differs from the repository root, the launcher stops
  # before taking the lock: the chain would otherwise be filed under a project row
  # that the host creates on the fly, one per repository, which is exactly how a
  # second sidebar project appears. -AllowHostMismatch is the only way through,
  # and it declares parent hosting (the session directory is the parent project).
  [string]$ExpectedHostProject = '',

  # Initiator session (B24). No environment variable carries the id of the
  # session that runs a script, so the session activating a chain states its own
  # id here and the ledger records it. Empty is allowed: the launcher then says so
  # and records the placeholder "unknown" instead of pretending it knows.
  [string]$InitiatorSession = '',

  # Allow host project mismatch (B24). Off by default, because the default answer
  # to "the repository root is not the registered project" is to stop, not to
  # start a chain that every link has to file elsewhere. On, the operator declares
  # parent hosting: links run in the parent project directory, so the prompt
  # switches every path it hands out to an absolute one. This is an explicit
  # declaration, never an automatic fallback.
  [switch]$AllowHostMismatch
)

$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
if ([string]::IsNullOrWhiteSpace($WorkspaceDir)) { $WorkspaceDir = $repoRoot }
$ledgerPath = Join-Path $repoRoot 'docs\relay.json'
$lockScript = Join-Path $PSScriptRoot 'relay-lock.ps1'
$ledgerGate = Join-Path $PSScriptRoot 'relay-ledger.ps1'
if ([string]::IsNullOrWhiteSpace($PromptOut)) { $PromptOut = Join-Path $PSScriptRoot 'next-relay-prompt.txt' }

function Say { param([string]$Line) Write-Host $Line }

# --- 0. parameter validation --------------------------------------------------
# Every refusal in this section is exit 2 with a machine readable verdict line.
# The parameter binder cannot do that job: a mandatory parameter or a typed
# integer turns a bad value into a binder error, and the script then ends with
# exit 1 and a stack trace, which is outside the published exit code contract
# {0,2,3,4}.
if ([string]::IsNullOrWhiteSpace($Target)) {
  Say 'FAIL reason=bad_parameter target=empty'
  exit 2
}
# A newline in the target or in the stage titles would break the prompt into
# two blocks and let the value inject a rule line of its own, so both are
# folded into a single line before anything is written.
$Target = ($Target -replace '[\r\n]+', ' ').Trim()
$StageTitles = ($StageTitles -replace '[\r\n]+', ' ').Trim()
if ([string]::IsNullOrWhiteSpace($Target)) {
  Say 'FAIL reason=bad_parameter target=empty'
  exit 2
}
$maxStagesNum = 0
if (-not [int]::TryParse($MaxStages, [ref]$maxStagesNum)) {
  Say "FAIL reason=max_stages_invalid value=$MaxStages hint=expected_an_integer"
  exit 2
}
if ($maxStagesNum -lt 1 -or $maxStagesNum -gt 1000) {
  Say "FAIL reason=max_stages_invalid value=$maxStagesNum min=1 max=1000"
  exit 2
}
$ttlNum = 0
if (-not [int]::TryParse([string]$TtlSeconds, [ref]$ttlNum)) {
  Say "FAIL reason=ttl_invalid value=$TtlSeconds hint=expected_an_integer"
  exit 2
}
if ($ttlNum -lt 0 -or $ttlNum -gt 86400) {
  Say "FAIL reason=ttl_invalid value=$ttlNum min=0 max=86400"
  exit 2
}

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
$headRaw = (& git -C $WorkspaceDir rev-parse --short HEAD 2>$null)
if ([string]::IsNullOrWhiteSpace([string]$headRaw)) { $head = 'none' } else { $head = ([string]$headRaw).Trim() }
$dirtyCount = @(& git -C $WorkspaceDir status --porcelain -uall).Count
Say "OK head=$head dirty_files=$dirtyCount"

# --- 1b. runtime resolution ----------------------------------------------------
# The launcher writes the prompt that every link reads, so it has to know how the
# NEXT link is started: MCode calls session_create, a CLI runtime runs the spawn
# driver. The installer stamps that contract into docs\relay\relay-runtime.json
# next to this script; an explicit -Runtime always wins.
$descriptorPath = Join-Path $PSScriptRoot 'relay-runtime.json'
$descriptor = $null
if (Test-Path -LiteralPath $descriptorPath -PathType Leaf) {
  try {
    $descriptor = Get-Content -LiteralPath $descriptorPath -Raw -Encoding UTF8 | ConvertFrom-Json
  } catch {
    $descriptor = $null
  }
}
$knownRuntimes = @('mcode', 'claude-code', 'codex', 'openclaw')
$runtimeSource = 'default'
if ([string]::IsNullOrWhiteSpace($Runtime)) {
  if ($null -ne $descriptor -and -not [string]::IsNullOrWhiteSpace([string]$descriptor.runtime)) {
    $Runtime = [string]$descriptor.runtime
    $runtimeSource = 'descriptor'
  } else {
    $Runtime = 'mcode'
  }
} else {
  $runtimeSource = 'parameter'
}
if ($knownRuntimes -notcontains $Runtime) {
  Say "FAIL reason=runtime_unsupported runtime=$Runtime known=$($knownRuntimes -join ',')"
  exit 2
}
Say "OK runtime=$Runtime source=$runtimeSource"

# --- 1b2. lock TTL (the descriptor holds the project level knob) --------------
# The installer stamps the project TTL into docs\relay\relay-runtime.json as
# lock_ttl_seconds. The launcher used to ignore that field and always locked
# with its own default, which left the installer argument dead. Priority: an
# explicit -TtlSeconds wins, then the descriptor, then the built in default.
# The effective value is the one handed to relay-lock.ps1 -Action acquire.
$ttlEffective = 1800
$ttlSource = 'default'
if ($ttlNum -gt 0) {
  $ttlEffective = $ttlNum
  $ttlSource = 'parameter'
} elseif ($null -ne $descriptor) {
  $ttlDescriptor = 0
  if ([int]::TryParse([string]$descriptor.lock_ttl_seconds, [ref]$ttlDescriptor) -and $ttlDescriptor -gt 0) {
    $ttlEffective = $ttlDescriptor
    $ttlSource = 'descriptor'
  }
}
Say "TLAUNCH ttl_s=$ttlEffective ttl_source=$ttlSource"

# --- 1c. link mode and the chain session id ---------------------------------
# The link mode decides HOW the next link is started, and therefore whether the
# launcher has to allocate a session id up front. A CLI link has no session tool
# that hands an id back, so the launcher allocates one, writes it into the ledger
# and into the prompt: the link needs it to renew and to release the lock, and
# the driver of the next link reads it from the ledger.
$linkMode = 'session_tool'
if ($Runtime -eq 'claude-code' -or $Runtime -eq 'codex') {
  $linkMode = 'cli_driver'
} elseif ($Runtime -eq 'openclaw') {
  $linkMode = 'sessions_spawn_tool'
}
# The descriptor decides only when the caller did not name a runtime: an explicit
# -Runtime always wins, which is what the rule above says. B31: the descriptor used
# to override the parameter, so a chain launched with -Runtime openclaw on a kit
# installed for mcode silently got the mcode link mode and the wrong prompt.
if ($runtimeSource -ne 'parameter' -and $null -ne $descriptor -and -not [string]::IsNullOrWhiteSpace([string]$descriptor.next_link_mode)) {
  $linkMode = [string]$descriptor.next_link_mode
}
if ($runtimeSource -eq 'parameter' -and $null -ne $descriptor -and -not [string]::IsNullOrWhiteSpace([string]$descriptor.runtime) -and [string]$descriptor.runtime -ne $Runtime) {
  Say "WARN runtime_differs_from_install runtime=$Runtime installed=$($descriptor.runtime) hint=reinstall_with_-Force_when_you_switch_runtimes"
}
$cliRuntime = ($linkMode -eq 'cli_driver')
$toolRuntime = ($linkMode -eq 'sessions_spawn_tool')
$chainSessionId = ''
if ($cliRuntime) {
  $chainSessionId = [guid]::NewGuid().ToString()
}
if ($chainSessionId -eq '') {
  Say "OK link_mode=$linkMode chain_session_id=none"
} else {
  Say "OK link_mode=$linkMode chain_session_id=$chainSessionId"
}

# --- 1d. host project key (B23, hardened in B24) -------------------------------
# Both session keyed hosts (mcode, claude-code) file a session under the project
# whose workspace path is EXACTLY the directory the session runs in, and a
# directory that is not a registered key is not refused: the host INSERTS a new
# project row and files the session there. One row per repository, invisible until
# somebody looks at the sidebar - that is how a relay chain ends up in a second,
# near empty project while the human keeps watching the project they started from.
#
# The launcher cannot move a session into another project, but it owns the value
# every link passes to session_create. From B24 on that value is the project key
# itself (project=..., never workspace_dir=...), and a key the launcher cannot
# vouch for is a hard stop instead of a warning:
#   default         the repository root is the project key
#   parent hosting  -AllowHostMismatch plus a differing expectation: links run in
#                   the parent project and every command carries an absolute path
$hostProjectKey = $repoRoot
Say "INFO host_project_key exact_workspace_dir=$hostProjectKey"
$expectedHostProject = $ExpectedHostProject
if ([string]::IsNullOrWhiteSpace($expectedHostProject)) {
  $expectFile = Join-Path $PSScriptRoot 'host-project.txt'
  if (Test-Path -LiteralPath $expectFile -PathType Leaf) {
    try {
      $expectedHostProject = [IO.File]::ReadAllText($expectFile).Trim()
    } catch {
      $expectedHostProject = ''
    }
  }
}
$hostProjectValue = $hostProjectKey
$hostProjectSource = 'repo_root'
$hostProjectMode = 'exact'
if (-not [string]::IsNullOrWhiteSpace($expectedHostProject)) {
  $expectedNorm = $expectedHostProject.TrimEnd('\', '/')
  $actualNorm = $hostProjectKey.TrimEnd('\', '/')
  if ($expectedNorm -ieq $actualNorm) {
    Say "OK host_project_expected_matches expected=$expectedNorm"
    $hostProjectSource = 'expectation'
  } else {
    Say "WARN host_project_mismatch expected=$expectedNorm actual_key=$actualNorm reason=host_projects_are_keyed_by_exact_workspace_path hint=the_chain_runs_in_the_repository_root_and_cannot_be_filed_under_another_project; register_the_repository_root_as_a_project_or_re-run_with_-AllowHostMismatch_for_parent_hosting"
    if ($AllowHostMismatch) {
      $hostProjectValue = $expectedNorm
      $hostProjectSource = 'expectation'
      $hostProjectMode = 'parent'
      Say "WARN host_project_parent_hosting project=$hostProjectValue reason=explicit_allow_host_mismatch rule=every_command_must_carry_an_absolute_path"
    } elseif ($DryRun) {
      Say 'DRYRUN skip=host_project_gate reason=a_dry_run_previews_the_mismatch_and_never_stops'
    } else {
      Say "FAIL reason=host_project_mismatch expected=$expectedNorm actual_key=$actualNorm rule=sessions_are_filed_under_the_exact_session_directory hint=a_link_started_from_here_would_create_a_new_project_row; register_the_repository_root_as_a_project_or_re-run_with_-AllowHostMismatch_and_absolute_paths"
      exit 2
    }
  }
}
# The line below is the contract the prompt and the activation packet both quote:
# the value a link passes as project= must equal one workspace_dir in the client
# project list VERBATIM. A near miss is not a fallback, it is a new project row.
Say "OK host_project_value value=$hostProjectValue source=$hostProjectSource mode=$hostProjectMode"

# --- 1e. chain identity (B24) --------------------------------------------------
# A chain used to be identifiable only by its link ordinals, which says nothing
# about WHICH chain a link belongs to or which session started it. Both are now
# fixed at start time: chain_id and chain_tag land in the ledger seed and on the
# first line of every prompt, the title suffix carries the tag, and the session
# that activated the chain names itself through -InitiatorSession. There is no
# environment variable to read that id from, so it cannot be inferred - only
# recorded, and only when the caller says it.
$chainStartedAt = [DateTimeOffset]::Now
$chainTag = $chainStartedAt.ToString('MMdd-HHmm')
$chainId = 'relay-chain-' + $chainStartedAt.ToString('yyyyMMdd-HHmmss')
$chainSuffix = '[' + $chainTag + ']'
$initiatorSession = $InitiatorSession.Trim()
if ([string]::IsNullOrWhiteSpace($initiatorSession)) {
  $initiatorSession = 'unknown'
  Say 'WARN initiator_session_missing hint=pass_-InitiatorSession_<your own session id>_so_the_chain_records_which_session_activated_it'
} else {
  Say "OK initiator_session=$initiatorSession"
}
# The chain identity line is printed further down, after the ledger readback:
# a chain that already exists keeps the identity its first link registered, and
# the line has to name that chain, not the one this run would have minted.

# --- 2. concurrency detection against the ledger ----------------------------
$ledger = $null
$curNum = 1
$maxNum = $maxStagesNum
if (Test-Path -LiteralPath $ledgerPath) {
  $raw = Get-Content -LiteralPath $ledgerPath -Raw -Encoding UTF8
  $ledgerHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $ledgerPath).Hash
  try { $ledger = $raw | ConvertFrom-Json } catch {
    Say "FAIL reason=ledger_unparsable path=$ledgerPath"
    exit 3
  }
  # A ledger that cannot be read as a state machine is not a ledger. It used to
  # pass every gate: an empty object, a null, an array and a ledger without a
  # status all read as "nothing is running here", so the launcher started a
  # chain and reported success on top of a file it never understood.
  $allowedLedgerStatus = @('running', 'pending', 'done', 'blocked')
  $ledgerStatusRaw = ''
  if ($null -ne $ledger) { $ledgerStatusRaw = ([string]$ledger.status).Trim() }
  if ([string]::IsNullOrWhiteSpace($ledgerStatusRaw) -or $allowedLedgerStatus -notcontains $ledgerStatusRaw.ToLowerInvariant()) {
    Say "FAIL reason=ledger_shape_invalid path=$ledgerPath status=$ledgerStatusRaw allowed=running,pending,done,blocked"
    exit 3
  }
  # The stage cap has to be comparable before it can be compared at all: a
  # ledger whose current_stage or max_stages is not an integer, or is missing
  # altogether, cannot say whether the chain sits at its cap. Casting it used
  # to raise an unhandled cast error, which ended the script with exit 1, a
  # code outside the published contract, so both values are parsed here.
  $curOk = [int]::TryParse([string]$ledger.current_stage, [ref]$curNum)
  $maxOk = [int]::TryParse([string]$ledger.max_stages, [ref]$maxNum)
  if (-not ($curOk -and $maxOk)) {
    Say "FAIL reason=ledger_stage_cap_unknown path=$ledgerPath current_stage=$([string]$ledger.current_stage) max_stages=$([string]$ledger.max_stages) hint=the_stage_cap_cannot_be_compared_run_relay-ledger.ps1_-Action_migrate-hint"
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
  # Backstop (B16): a chain whose last stage finished but whose status was never
  # flipped to done would otherwise pass the two gates above and boot stage N+1,
  # i.e. work outside the declared plan. Refuse here; never advance the status
  # ourselves, the ledger writer owns every status change.
  if ($ledger.status -eq 'running' -and $curNum -ge $maxNum) {
    # The cap is reached in three different shapes and the HINT must not mix
    # them up: every declared stage really done (the chain only misses its
    # terminal status), at least one stage still open (a link is running or
    # stalled), or no stage recorded at all (completion cannot be proven).
    # Telling the reader to close the chain in the second or third shape would
    # drop a stage silently, so the shape is reported on the FAIL line and the
    # HINT is chosen from it.
    $stageSummary = 'none'
    $allDoneState = 'unknown'
    $declaredStages = @($ledger.stages | Where-Object { $null -ne $_ })
    if ($declaredStages.Count -gt 0) {
      $stageParts = @()
      $doneCount = 0
      $stageIdx = 0
      foreach ($s in $declaredStages) {
        $stageStatus = [string]$s.status
        if ([string]::IsNullOrWhiteSpace($stageStatus)) { $stageStatus = 'unknown' }
        if ($stageStatus -eq 'done') { $doneCount++ }
        # B30: same identity rule as relay-ledger.ps1 -Action status (id, then the
        # legacy stage key, then the index). The self test compares this line with
        # LEDGER_CHAIN on the same ledger, so the two must resolve identity the
        # same way or a legacy ledger renders ":done" on one side and "1:done" on
        # the other.
        $stageKey = ([string]$s.id).Trim()
        if ($stageKey -eq '') { $stageKey = ([string]$s.stage).Trim() }
        if ($stageKey -eq '') { $stageKey = '#' + [string]$stageIdx }
        $stageParts += ('{0}:{1}' -f $stageKey, $stageStatus)
        $stageIdx++
      }
      $stageSummary = ($stageParts -join ',')
      if ($doneCount -eq $declaredStages.Count) { $allDoneState = 'true' } else { $allDoneState = 'false' }
    }
    Say "FAIL reason=chain_at_stage_cap current_stage=$($ledger.current_stage) max_stages=$($ledger.max_stages) stages=$stageSummary all_done=$allDoneState"
    if ($allDoneState -eq 'true') {
      # B20: this is the one shape -AutoFinalize acts on, so the hint must not
      # tell the reader to hand close a chain the same run closes. The token is
      # kept identical in both wordings: it names the shape, not the remedy.
      if ($AutoFinalize) {
        Say 'HINT=all_stages_done_but_status_running: every declared stage is done but status is still running. -AutoFinalize closes it through relay-ledger.ps1 on this run, and the outcome line below says whether it wrote or was skipped by a dry run; a refused write only warns. Do not raise -MaxStages to keep going.'
      } else {
        Say 'HINT=all_stages_done_but_status_running: every declared stage is done but status is still running. Close the chain with relay-ledger.ps1 -Action status, then submit a patch {"set_status":"done"}. Do not raise -MaxStages to keep going.'
      }
    } elseif ($allDoneState -eq 'false') {
      Say 'HINT=stage_cap_reached_with_open_stage: the stage cap is reached but at least one declared stage is not done. Drive or unblock the open stage first, and close the chain only once every stage reads done. Do not raise -MaxStages to keep going.'
    } else {
      Say 'HINT=stage_cap_reached_with_no_stage_records: the stage cap is reached but the ledger records no stage, so completion cannot be proven. Inspect the ledger with relay-ledger.ps1 -Action status, record the stage result, then close the chain. Do not raise -MaxStages to keep going.'
    }
    # Opt-in managed close (B19). Reaching this point means every declared stage
    # is done and only the terminal status is missing - exactly the shape the
    # first HINT above describes. With -AutoFinalize the launcher performs that
    # writeback instead of leaving it to the reader. It never edits the ledger by
    # itself: the one line patch is handed to relay-ledger.ps1, which owns the
    # writer lock, the CAS check, the append only rules and the readback. Any
    # failure only warns, the ledger is left as it was, and the exit code stays 3
    # because this invocation did not start a chain.
    if ($AutoFinalize -and $allDoneState -eq 'true') {
      if ($DryRun) {
        Say 'DRYRUN skip=auto_finalize reason=every_declared_stage_is_done_but_a_dry_run_never_writes'
      } else {
        $finalizeErr = ''
        $finalizeAfter = 'unknown'
        try {
          $childHost = ''
          try { $childHost = (Get-Process -Id $PID).Path } catch { }
          if ([string]::IsNullOrWhiteSpace($childHost)) { throw 'child_host_unresolved' }
          $statusOut = @(& $childHost -NoProfile -ExecutionPolicy Bypass -File $ledgerGate -Action status -LedgerPath $ledgerPath 2>&1 | ForEach-Object { [string]$_ })
          if ($LASTEXITCODE -ne 0) { throw ('status_exit=' + $LASTEXITCODE) }
          $stateLine = @($statusOut | Where-Object { $_ -match '^LEDGER_STATE ' })
          if ($stateLine.Count -lt 1) { throw 'status_line_missing' }
          $ledgerSha = ''
          if ($stateLine[0] -match ' sha256=([0-9a-f]{64})') { $ledgerSha = $Matches[1] }
          if ([string]::IsNullOrWhiteSpace($ledgerSha)) { throw 'status_sha256_missing' }
          # The patch is written outside the repo: it is a one shot input to the
          # gate, not an artifact anyone should find later and trust.
          $patchFile = Join-Path ([IO.Path]::GetTempPath()) ('relay-autofinalize-' + [guid]::NewGuid().ToString('N') + '.json')
          try {
            [IO.File]::WriteAllText($patchFile, '{"set_status":"done"}', [Text.UTF8Encoding]::new($false))
            $commitOut = @(& $childHost -NoProfile -ExecutionPolicy Bypass -File $ledgerGate -Action commit -LedgerPath $ledgerPath -ExpectSha256 $ledgerSha -Patch $patchFile 2>&1 | ForEach-Object { [string]$_ })
            $commitCode = $LASTEXITCODE
            if ($commitCode -ne 0) {
              $whyLine = @($commitOut | Where-Object { $_ -match '^LEDGER_FAIL ' })
              $whyText = 'no_ledger_fail_line'
              if ($whyLine.Count -gt 0) { $whyText = $whyLine[0] }
              throw ('commit_exit=' + $commitCode + ' ' + $whyText)
            }
          } finally {
            Remove-Item -LiteralPath $patchFile -Force -ErrorAction SilentlyContinue
          }
          $verifyOut = @(& $childHost -NoProfile -ExecutionPolicy Bypass -File $ledgerGate -Action status -LedgerPath $ledgerPath 2>&1 | ForEach-Object { [string]$_ })
          $verifyLine = @($verifyOut | Where-Object { $_ -match '^LEDGER_STATE ' })
          if ($verifyLine.Count -lt 1) { throw 'readback_line_missing' }
          if (-not ($verifyLine[0] -match ' status=done ')) { throw 'readback_status_not_done' }
          if ($verifyLine[0] -match ' sha256=([0-9a-f]{64})') { $finalizeAfter = $Matches[1] }
          Say ('AUTO_FINALIZED status=done before=' + $ledgerSha + ' after=' + $finalizeAfter + ' path=' + $ledgerPath)
          Say 'HINT=chain_closed_by_auto_finalize: every declared stage is done and status is now done, so a re-run of the launcher reports chain_exhausted. To keep going, start a fresh chain with -MaxStages greater than the previous one, or archive the old ledger.'
        } catch {
          $finalizeErr = $_.Exception.Message
        }
        if ($finalizeErr -ne '') {
          Say ('WARN auto_finalize=failed reason=' + ($finalizeErr -replace '\s+', '_'))
        }
      }
    }
    exit 3
  }
  if ($ledger.status -eq 'done' -and $curNum -ge $maxNum) {
    Say "FAIL reason=chain_exhausted current_stage=$($ledger.current_stage) max_stages=$($ledger.max_stages)"
    Say 'HINT=start a fresh chain by passing -MaxStages greater than the previous chain, or archive the old ledger.'
    exit 3
  }
  if ($ledger.status -eq 'blocked') {
    Say "FAIL reason=chain_blocked blocked_on=$($ledger.blocked_on -join ',')"
    Say 'HINT=blocked chains need a human decision first; do not silently resume.'
    exit 3
  }
} else {
  Say "OK ledger_absent path=$ledgerPath (will bootstrap)"
}

# --- 2c. chain identity readback ----------------------------------------------
# A ledger that already exists keeps the values its first link registered: the
# bootstrap is skipped, so the ledger still carries the chain_id, the chain_tag
# and the goal of that first link, while this run would mint new ones. The
# protocol titles every link with relay.json.chain_tag, so the prompt and the
# ledger have to name the same chain: the ledger wins. The values minted by
# this run are kept when the ledger does not know them.
$chainIdentitySource = 'generated'
if ($null -ne $ledger) {
  $ledgerChainId = ([string]$ledger.chain_id).Trim()
  $ledgerChainTag = ([string]$ledger.chain_tag).Trim()
  $ledgerGoal = ([string]$ledger.goal).Trim()
  if ($ledgerChainId -ne '') { $chainId = $ledgerChainId; $chainIdentitySource = 'ledger' }
  if ($ledgerChainTag -ne '') { $chainTag = $ledgerChainTag; $chainSuffix = '[' + $chainTag + ']'; $chainIdentitySource = 'ledger' }
  if ($ledgerGoal -ne '') { $Target = $ledgerGoal; $chainIdentitySource = 'ledger' }
  # The banner carries the start time of the chain. A ledger that already
  # exists knows when its chain started, and a start time of this run next to
  # the chain id of the first link would name two different chains.
  $ledgerStartedAt = ([string]$ledger.started_at).Trim()
  if ($ledgerStartedAt -ne '') {
    $parsedStartedAt = $null
    try { $parsedStartedAt = [DateTimeOffset]::Parse($ledgerStartedAt) } catch { $parsedStartedAt = $null }
    if ($null -ne $parsedStartedAt) { $chainStartedAt = $parsedStartedAt }
  }
}
Say "OK chain_id=$chainId chain_tag=$chainTag"
if ($chainIdentitySource -eq 'ledger') { Say 'OK chain_identity source=ledger' }

# --- 1d. stage list resolution ------------------------------------------------
# The stage list is what the prompt advertises as the plan of the chain. The
# installer may have been given one (-StageTitles), and the launcher used to
# ignore it: it always wrote one hard coded line, so every link of a multi
# stage chain was told "1. stage 1 scope inventory" no matter which stage it
# ran. Resolution order: this argument, then the ledger (a chain carries its
# own plan), then the descriptor the installer stamped, then the default.
$stageTitlesText = ''
$stageTitlesSource = 'default'
if (-not [string]::IsNullOrWhiteSpace($StageTitles)) {
  $stageTitlesText = $StageTitles
  $stageTitlesSource = 'argument'
} elseif ($null -ne $ledger -and -not [string]::IsNullOrWhiteSpace([string]$ledger.stage_titles)) {
  $stageTitlesText = [string]$ledger.stage_titles
  $stageTitlesSource = 'ledger'
} elseif ($null -ne $descriptor -and -not [string]::IsNullOrWhiteSpace([string]$descriptor.stage_titles)) {
  $stageTitlesText = [string]$descriptor.stage_titles
  $stageTitlesSource = 'descriptor'
}
Say "OK stage_titles source=$stageTitlesSource"

# --- 2b. resolve the plan document -------------------------------------------
# Runs BEFORE the lock is taken: a chain that cannot name its source of truth
# must not leave a held lock behind. Mirrors the installer's probe list so both
# ends of the kit agree on where a plan doc lives.
function To-RelPath {
  param([string]$Full)
  if ($Full.Length -gt $repoRoot.Length -and $Full.StartsWith($repoRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    return $Full.Substring($repoRoot.Length + 1)
  }
  return $Full
}

$planSource = 'argument'
if ([string]::IsNullOrWhiteSpace($PlanDoc) -and $null -ne $ledger -and -not [string]::IsNullOrWhiteSpace([string]$ledger.plan_doc)) {
  $PlanDoc = [string]$ledger.plan_doc
  $planSource = 'ledger'
}
if ([string]::IsNullOrWhiteSpace($PlanDoc)) {
  $probe = New-Object System.Collections.Generic.List[System.IO.FileInfo]
  foreach ($pat in @('docs\plan-*.md', 'docs\plans\*.md', 'docs\superpowers\plans\*.md')) {
    foreach ($h in @(Get-ChildItem -Path (Join-Path $repoRoot $pat) -File -ErrorAction SilentlyContinue)) { $probe.Add($h) }
  }
  $uniq = @($probe | Sort-Object -Property FullName -Unique)
  if ($uniq.Count -eq 1) {
    $PlanDoc = To-RelPath -Full $uniq[0].FullName
    $planSource = 'probe'
  } elseif ($uniq.Count -gt 1) {
    # Unlike the installer, the launcher never creates a plan file, so an
    # ambiguous probe falls back to the newest candidate and says so.
    $newest = @($uniq | Sort-Object -Property LastWriteTime -Descending)
    $PlanDoc = To-RelPath -Full $newest[0].FullName
    $planSource = 'probe_newest_of_' + $uniq.Count
    Say "WARN plan_doc_ambiguous candidates=$($uniq.Count) picked=$PlanDoc by=newest_mtime pass_-PlanDoc_to_disambiguate"
  }
}
if ([string]::IsNullOrWhiteSpace($PlanDoc)) {
  Say 'FAIL reason=plan_doc_missing hint=pass_-PlanDoc_or_set_plan_doc_in_docs\relay.json_or_add_docs\plan-<batch>.md'
  exit 2
}
$planAbs = $PlanDoc
if (-not [IO.Path]::IsPathRooted($planAbs)) { $planAbs = Join-Path $repoRoot $planAbs }
if (-not (Test-Path -LiteralPath $planAbs -PathType Leaf)) {
  Say "FAIL reason=plan_doc_not_found path=$planAbs source=$planSource"
  exit 2
}
$PlanDoc = To-RelPath -Full $planAbs
Say "OK plan_doc=$PlanDoc source=$planSource bytes=$((Get-Item -LiteralPath $planAbs).Length)"

# --- 3. lock acquisition ----------------------------------------------------
if ($DryRun) {
  Say 'DRYRUN skip=lock_acquire skip=ledger_bootstrap skip=prompt_write'
} else {
  if (-not (Test-Path -LiteralPath $ledgerGate -PathType Leaf)) {
    Say "FAIL reason=ledger_gate_missing path=$ledgerGate (re-run install-relay.ps1)"
    exit 2
  }
  # A missing lock script used to end the run with an unhandled
  # CommandNotFoundException, so the failure was exit 1 with a stack trace
  # instead of a verdict line.
  if (-not (Test-Path -LiteralPath $lockScript -PathType Leaf)) {
    Say "FAIL reason=lock_script_missing path=$lockScript hint=re-run_install-relay.ps1"
    exit 2
  }
  & $lockScript -Action acquire -Stage 1 -Title 'relay-start' -TtlSeconds $ttlEffective
  if ($LASTEXITCODE -ne 0) {
    Say "FAIL reason=lock_unavailable exit=$LASTEXITCODE"
    exit 4
  }
}

# --- 4. ledger bootstrap (create only; never rewrite an existing ledger) -----
$ledgerBootstrapped = $false
if (-not $DryRun -and -not (Test-Path -LiteralPath $ledgerPath)) {
  $now = [DateTimeOffset]::Now.ToString('o')
  $seed = [ordered]@{
    goal            = $Target
    plan_doc        = $PlanDoc
    stage_titles    = $(if ($stageTitlesText -ne '') { $stageTitlesText } else { $null })
    ledger_docs     = @('docs\relay\stage-1-inventory.md')
    workspace_dir   = $repoRoot
    host_project    = $hostProjectValue
    host_project_mode = $hostProjectMode
    chain_id        = $chainId
    chain_tag       = $chainTag
    initiator_session = $initiatorSession
    status          = 'running'
    auto_relay      = $true
    current_stage   = 1
    max_stages      = $maxStagesNum
    next_session_id = $(if ($chainSessionId -ne '') { $chainSessionId } else { $null })
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
      'current_stage > max_stages with every stage done -> status=done (chain complete)',
      'current_stage > max_stages with an open blocked_on item -> status=blocked',
      'same acceptance failed twice -> status=blocked',
      'two consecutive stages over the tool call budget -> status=blocked'
    )
    stages            = @()
    sessions          = @()
    notes             = @()
    blocked_on        = @()
  }
  $json = $seed | ConvertTo-Json -Depth 6
  [IO.File]::WriteAllText($ledgerPath, $json, [Text.UTF8Encoding]::new($false))
  $ledgerBootstrapped = $true
  Say "OK ledger_bootstrapped path=$ledgerPath bytes=$((Get-Item $ledgerPath).Length)"
}

# --- 5. next relay prompt (full path pointers only) -------------------------
$stageList = if ([string]::IsNullOrWhiteSpace($stageTitlesText)) {
  '1. stage 1 scope inventory'
} else {
  $stageTitlesText
}
# A stage title may carry a path of its own (the artifact it has to write).
# On a CLI runtime that path has to follow the runtime path style too.
if ($cliRuntime) { $stageList = [regex]::Replace($stageList, '(?<=[A-Za-z0-9_.-])\\(?=[A-Za-z0-9_.-])', '/') }

# --- 5a. runtime-specific fragments ---------------------------------------------
# The mcode prompt stays byte-identical to the text that has been running
# chains for months. Every other runtime gets a prompt that hands the chain over
# with the spawn driver, because those runtimes have no session_create tool at
# all: telling them to call session_create is what breaks a CLI chain on its
# first hand-off.
# How the NEXT link is started depends on the runtime, not on the launcher:
#   session_tool         the runtime starts it with its own session tool (mcode)
#   cli_driver           a headless CLI process (claude-code, codex)
#   sessions_spawn_tool  a child session of the same workspace (openclaw)
# The link mode was already resolved in section 1c, together with the chain
# session id, because the ledger bootstrap in section 4 needs that id.
$stageNo = 1
if ($null -ne $ledger) { $stageNo = $curNum }
$nextStageNo = $stageNo + 1

# Session naming of a relay link. The ordinal is what a human reads the chain
# order from in the session list, so it is zero padded and the chain length
# travels with it: relay-02of05. The bare form relay-2-<short> sorted beside
# relay-20 and said nothing about how much chain was left.
$maxStageNo = $maxStagesNum
if ($null -ne $ledger) { $maxStageNo = $maxNum }
$linkTag = 'relay-' + ('{0:00}' -f $stageNo) + 'of' + ('{0:00}' -f $maxStageNo)
$nextLinkTag = 'relay-' + ('{0:00}' -f $nextStageNo) + 'of' + ('{0:00}' -f $maxStageNo)

$spawnCommand = ''
if ($cliRuntime) {
  $raw = ''
  if ($null -ne $descriptor -and -not [string]::IsNullOrWhiteSpace([string]$descriptor.spawn_command)) {
    $raw = [string]$descriptor.spawn_command
  }
  if ([string]::IsNullOrWhiteSpace($raw)) {
    $raw = 'pwsh -NoProfile -ExecutionPolicy Bypass -File {REPO}\docs\relay\relay-spawn.ps1 -Runtime {RUNTIME} -PromptFile {REPO}\docs\relay\next-relay-prompt.txt -WorkspaceDir {REPO} -Execute -AdoptLock'
  }
  $spawnCommand = $raw.Replace('{REPO}', $repoRoot).Replace('{RUNTIME}', $Runtime)
  # Ephemeral workspace (B22): the chain runs in a throwaway fixture, so the
  # spawn driver has to move the project entry its own child creates out of the
  # registry of the client. The flag travels inside the command, because the
  # link that runs the command is the one that starts the child.
  if ($EphemeralWorkspace) { $spawnCommand = $spawnCommand + ' -EphemeralWorkspace' }
}
# The copy of the spawn command that travels in the prompt is executed by the
# link through the Bash tool, and bash eats the backslashes of a Windows path.
# The prompt therefore carries the forward slash form; the human facing
# activation packet keeps the Windows form.
$spawnCommandPrompt = $spawnCommand
if ($cliRuntime) { $spawnCommandPrompt = $spawnCommand.Replace('\', '/') }

# The prompt hands the link the paths it has to act on, and on a CLI runtime the
# link runs them through a real bash, which eats the backslashes of a Windows
# path. Every path in the prompt is therefore written with forward slashes
# there. The mcode runtime has no such parser, so its prompt keeps the
# Windows paths byte for byte.
$pathSep = if ($cliRuntime) { '/' } else { '\' }
$promptRepoRoot = if ($cliRuntime) { $repoRoot.Replace('\', '/') } else { $repoRoot }
# The host project key is a path too, and on a CLI runtime the prompt is read
# by a real bash, which eats the backslashes of a Windows path. The prompt
# therefore carries the forward slash form there, like every other path.
$hostProjectPrompt = $hostProjectValue
if ($cliRuntime) { $hostProjectPrompt = $hostProjectValue.Replace('\', '/') }
$workspaceNote = if ($cliRuntime) { 'absolute path, forward slashes' } else { 'absolute path, backslashes' }
if ($hostProjectMode -eq 'parent') { $workspaceNote = $workspaceNote + '; this session runs in the parent project directory ' + $hostProjectPrompt + ', so every path must be absolute and every git call must use git -C ' + $promptRepoRoot }
$relayDirPrompt = 'docs' + $pathSep + 'relay'
$ledgerPrompt = 'docs' + $pathSep + 'relay.json'
$lockPrompt = $relayDirPrompt + $pathSep + '.relay.lock'
$gateLockPrompt = $relayDirPrompt + $pathSep + '.ledger.lock'
$planDocPrompt = if ($cliRuntime) { $PlanDoc.Replace('\', '/') } else { $PlanDoc }
$docProtocolPrompt = 'docs' + $pathSep + 'AGENT-RELAY.md'
$docAdaptationPrompt = 'docs' + $pathSep + 'RELAY-ADAPTATION.md'
$launcherPrompt = $relayDirPrompt + $pathSep + 'start-relay.ps1'
$lockScriptPrompt = $relayDirPrompt + $pathSep + 'relay-lock.ps1'
$ledgerScriptPrompt = $relayDirPrompt + $pathSep + 'relay-ledger.ps1'
$spawnScriptPrompt = $relayDirPrompt + $pathSep + 'relay-spawn.ps1'
$runtimeDescPrompt = $relayDirPrompt + $pathSep + 'relay-runtime.json'
$nextPromptFile = $relayDirPrompt + $pathSep + 'next-relay-prompt.txt'
$artifactRel = $relayDirPrompt + $pathSep + "stage-$stageNo-inventory.md"
$nextArtifactRel = $relayDirPrompt + $pathSep + "stage-$nextStageNo-inventory.md"

$promptHeader = ''
$readItem8 = ''
$stageSentence = "You are relay stage $stageNo of an unattended relay chain in this repository."
$sessionRule = 'Never pass an effort field to session_create (the schema has no such field).'
$completionRule = 'On completion: write docs\relay\stage-' + $stageNo + '-inventory.md, then commit that hand-off through the ledger gate (recipe above; it re-reads what it wrote and refuses to rewrite entries you did not create), then run relay-lock.ps1 -Action prespawn -Stage ' + $stageNo + ' and refuse to spawn unless it prints SPAWN_PERMIT, then start the next stage with session_create using the same recipe, then hand the lock over with relay-lock.ps1 -Action verify -SessionId <new session id> -Nonce <the nonce from SPAWN_PERMIT>. Never adopt the lock without a permit.'
$nextHint = 'NEXT call session_create with agent_name=me, title=' + $linkTag + '-<short stage name> ' + $chainSuffix + ', project=' + $hostProjectValue + ', content=<contents of the prompt file>. Never pass workspace_dir: it is mutually exclusive with project, and a directory that is not an exact project key makes the host insert a NEW project row.'
$nextHint2 = 'NEXT then hand the lock over: relay-lock.ps1 -Action verify -SessionId <new session id> -Nonce <nonce from SPAWN_PERMIT>'
# The stop rule is the same sentence in every runtime, except that a CLI link
# knows its own session id and must name it when it releases the lock.
$stopRule = 'If the chain must stop: commit status=blocked with what is missing through the ledger gate (blocked_on_append plus set_status=blocked and an empty next_session_id), release the lock with relay-lock.ps1 -Action release, mark the chain stopped with relay-lock.ps1 -Action stop-mark -Note <why>, and explain in the final reply. Never start a next session in that case.'

$nameRule = 'Session naming: this link is ' + $linkTag + ', the next one is ' + $nextLinkTag + '-<short stage name> ' + $chainSuffix + '. Keep the relay- prefix, the zero padded ordinal and the chain length intact: the session list is how a human reads the chain order, and relay-10 must not sort beside relay-1. Append the chain tag ' + $chainSuffix + ' to the end of every title of this chain: it is what tells two chains apart, and the title is the only place where the newest link and its chain are readable from the sidebar alone.'

if ($cliRuntime) {
  $promptHeader = "RELAY_STAGE=$stageNo`nRELAY_LINK=$linkTag`nRELAY_ARTIFACT=$artifactRel`nRELAY_SESSION_ID=$chainSessionId`n`n"
  $readItem8 = "`n8. $promptRepoRoot$pathSep$spawnScriptPrompt (spawn driver: starts the next link in this runtime)"
  $stageSentence = "You are relay stage $stageNo of an unattended relay chain in this repository."
  $sessionRule = 'This runtime has no session_create tool: never call it. The next link is started by the spawn driver, see the hand-off rule below. Command style for this runtime: one command per call, no chained commands and no quoted flag values. Paths: the Bash tool runs a real bash and eats the backslashes of a Windows path, so write every path with forward slashes there (docs/relay/relay-ledger.ps1); the native PowerShell tool takes Windows backslash paths. Example for the Bash tool: pwsh -NoProfile -ExecutionPolicy Bypass -File docs/relay/relay-ledger.ps1 -Action status . A chained or quoted command is refused by the runtime permission layer and a headless link cannot approve it.'
  $completionRule = 'On completion: write the file named in RELAY_ARTIFACT, then commit that hand-off through the ledger gate (recipe above; it re-reads what it wrote and refuses to rewrite entries you did not create) with THREE intents in ONE patch: stage_done=<your stage id>, bump_current_stage, and next_session_id=<a fresh UUID that you allocate for the next link>; then write the next-stage prompt: copy this prompt file over ' + $nextPromptFile + ', change RELAY_STAGE=' + $stageNo + ' to RELAY_STAGE=' + $nextStageNo + ', change the phrase "relay stage ' + $stageNo + '" to "relay stage ' + $nextStageNo + '", change RELAY_ARTIFACT=' + $artifactRel + ' to RELAY_ARTIFACT=' + $nextArtifactRel + ', change RELAY_SESSION_ID=' + $chainSessionId + ' to RELAY_SESSION_ID=<the fresh UUID you wrote into the ledger as next_session_id>, change RELAY_LINK=' + $linkTag + ' to RELAY_LINK=' + $nextLinkTag + ', and change nothing else; then start the next link with: ' + $spawnCommandPrompt + ' (the driver reads next_session_id from the ledger and hands the lock over before the new link starts).'
  $stopRule = 'If the chain must stop: commit status=blocked with what is missing through the ledger gate (blocked_on_append plus set_status=blocked and an empty next_session_id), release the lock with relay-lock.ps1 -Action release -SessionId <the RELAY_SESSION_ID value above>, and explain in the final reply. Never start a next session in that case.'
  $nextHint = 'NEXT run this command to start the first link: ' + $spawnCommand
  $nextHint2 = 'NEXT the driver hands the lock over to the new link before it starts'
} elseif ($toolRuntime) {
  $promptHeader = "RELAY_STAGE=$stageNo`nRELAY_LINK=$linkTag`nRELAY_ARTIFACT=$artifactRel`n`n"
  $readItem8 = "`n8. $promptRepoRoot$pathSep$runtimeDescPrompt (runtime contract: how the next link is started)"
  $stageSentence = "You are relay stage $stageNo of an unattended relay chain in this repository."
  $sessionRule = 'This runtime has no session_create tool: never call it. The next link is started with the sessions_spawn tool of this workspace, see the hand-off rule below.'
  $completionRule = 'On completion: write the file named in RELAY_ARTIFACT, then commit that hand-off through the ledger gate (recipe above; it re-reads what it wrote and refuses to rewrite entries you did not create) with THREE intents in ONE patch: stage_done=<your stage id>, bump_current_stage, and next_session_id=<the session id the spawn tool returns>; then write the next-stage prompt: copy this prompt file over ' + $nextPromptFile + ', change RELAY_STAGE=' + $stageNo + ' to RELAY_STAGE=' + $nextStageNo + ', change the phrase "relay stage ' + $stageNo + '" to "relay stage ' + $nextStageNo + '", change RELAY_ARTIFACT=' + $artifactRel + ' to RELAY_ARTIFACT=' + $nextArtifactRel + ', change RELAY_LINK=' + $linkTag + ' to RELAY_LINK=' + $nextLinkTag + ', and change nothing else; then run relay-lock.ps1 -Action prespawn -Stage ' + $stageNo + ' and refuse to spawn unless it prints SPAWN_PERMIT, then start the next link with the sessions_spawn tool (workspace = ' + $repoRoot + ', task = ' + $nextLinkTag + '-<short stage name>, prompt = the full text of docs\relay\next-relay-prompt.txt), then hand the lock over with relay-lock.ps1 -Action verify -SessionId <the new session id> -Nonce <the nonce from SPAWN_PERMIT>. Never adopt the lock without a permit.'
  $nextHint = 'NEXT spawn the first link with the sessions_spawn tool (workspace = ' + $repoRoot + ')'
  $nextHint2 = 'NEXT then hand the lock over: relay-lock.ps1 -Action verify -SessionId <new session id> -Nonce <nonce from SPAWN_PERMIT>'
}

# The project rule is the mechanism that keeps every link inside the project the
# human started from. It is a rule in the prompt and not a decision in the
# launcher, because only the link can read the project list of its own runtime.
$spawnGateRule = '' 
if (-not $cliRuntime) {
  # The mcode runtime opens the next writer with session_create and has no driver;
  # the openclaw runtime opens it with its own sessions_spawn tool. Both write from
  # inside the chain, so both go through the same hand-over gate. The CLI runtimes
  # are excluded: their driver (relay-spawn.ps1) performs the hand-over itself.
  # B31: the assignment was missing, so the gate text never reached the prompt and
  # the template kept a bare "- " bullet where the rule belonged.
  $spawnGateRule = '- Hand-over gate (mechanical, not advisory): before you open the next writer you MUST run relay-lock.ps1 -Action prespawn -Stage <your stage number>. It refuses with exit 3 or 5 when the chain is stopped (stop sentinel present), when the chain lock is held by another link, when background jobs you registered are still alive, or when an unconsumed permit is younger than its TTL. A refusal means: do not spawn, commit status=blocked through the ledger gate, and report. Only the SPAWN_PERMIT line authorises a spawn. After the spawn returns the new session id, run relay-lock.ps1 -Action verify -SessionId <new session id> -Nonce <the nonce from SPAWN_PERMIT>: it consumes the permit exactly once and moves the lock to the new link. If verify refuses, do not spawn again; report instead. If you start background work that outlives your turn, register it with relay-lock.ps1 -Action job-register -ProcId <pid> so that no later link can spawn on top of it. Rationale: a front end that already displays this session as stopped must not be able to open a second writer while background work is still running.'
}

$hostRule = '- Session project: call session_create with project=' + $hostProjectPrompt + ' (mode=' + $hostProjectMode + ') and NEVER with workspace_dir. That value must match a workspace_dir or a name in the project_list tool output VERBATIM. If nothing matches, do not start a session and do not fall back to workspace_dir: commit status=blocked through the ledger gate with a note naming the value you tried. Rationale: the host files a session under the project keyed by the exact session directory and inserts a NEW project row when the key is unknown, so a near miss detaches the chain from its project and litters the sidebar.'
if ($hostProjectMode -eq 'parent') {
  # Parent hosting: the session directory is the parent project, so any relative
  # docs\relay\... path in a recipe resolves under the wrong directory.
  $hostRule = $hostRule + ' Parent hosting is on: this session runs in the parent project directory, not in the repository root, so every path you act on must be absolute under ' + $promptRepoRoot + ' and every git call must be git -C ' + $promptRepoRoot + '.'
  $completionRule = $completionRule.Replace('docs\relay\', $promptRepoRoot + '\docs\relay\')
}

# The ledger recipe is part of the prompt, and on a CLI runtime the PATH STYLE in
# it decides whether the command works at all: the Bash tool of claude-code is a
# real bash, and bash eats the backslashes of a Windows path
# (docs\relay\relay-ledger.ps1 becomes docsrelayrelay-ledger.ps1 and the script
# is not found, exit 64). The mcode runtime has no such parser, so its prompt
# keeps the Windows paths byte for byte.
$ledgerRuleText = '- Ledger writes go through the gate docs\relay\relay-ledger.ps1, never by hand. Recipe: (1) run pwsh -NoProfile -File docs\relay\relay-ledger.ps1 -Action status and read sha256 from its LEDGER_STATE line. (2) Write an ASCII JSON patch file under docs\relay\ using only append-only intent: stage_done, stage_fields, append_stage, sessions_append, notes_append, ledger_docs_append, blocked_on_append, set_status, bump_current_stage, next_session_id. (3) Validate it with -DryRun on the same command. (4) Commit it with -Action commit and that same sha256. A stale sha means the ledger moved under you: re-read status, rebuild the patch, retry once. Exit codes: 0 committed, 2 bad argument, 3 refused (CAS conflict or rule violation), 4 lock timeout, 5 unreadable patch. status=running is reserved for the human who starts the chain. If the gate refuses and you cannot satisfy it, stop and report rather than editing the ledger directly.'
$ledgerRule = $ledgerRuleText
if ($cliRuntime) { $ledgerRule = $ledgerRuleText.Replace('docs\relay\', 'docs/relay/') }
if ($hostProjectMode -eq 'parent' -and -not $cliRuntime) {
  # A bare docs\relay\... path resolves under the parent project directory and the
  # gate is not there, so the recipe has to name the repository copy in full.
  $ledgerRule = $ledgerRule.Replace('docs\relay\', $promptRepoRoot + '\docs\relay\')
}

$chainBanner = 'CHAIN ' + $chainId + ' | link ' + $linkTag + ' | started ' + $chainStartedAt.ToString('yyyy-MM-dd HH:mm') + ' | initiator ' + $initiatorSession + ' | host project ' + $hostProjectPrompt + ' (' + $hostProjectMode + ')'

$prompt = @"
$promptHeader$chainBanner
$stageSentence

WORKSPACE: $promptRepoRoot ($workspaceNote). Work only inside it.

READ FIRST (full paths, read in this order):
1. $promptRepoRoot$pathSep$ledgerPrompt            (state machine truth)
2. $promptRepoRoot$pathSep$docProtocolPrompt        (protocol)
3. $promptRepoRoot$pathSep$docAdaptationPrompt   (project adjudication)
4. $promptRepoRoot$pathSep$planDocPrompt                   (source of truth for the target batch)
5. $promptRepoRoot$pathSep$launcherPrompt (this launcher, for the next stage)
6. $promptRepoRoot$pathSep$lockScriptPrompt  (lock protocol)
7. $promptRepoRoot$pathSep$ledgerScriptPrompt (ledger write gate)$readItem8

TARGET: $Target

STAGE PLAN:
$stageList

RULES:
- Validate $ledgerPrompt before touching anything: status must be running, current_stage must equal your stage, current_stage must not exceed max_stages. If any check fails, commit status=blocked through the ledger gate (see RULES), explain what is missing, and stop.
- Exactly one stage per session. A stage owns a declared write set; the controller never edits product code directly, dispatch a worker sub-session for code changes and state the single allowed write set in the dispatch brief.
- $nameRule
$hostRule
- $sessionRule
$spawnGateRule
- Concurrency: the lock file $lockPrompt is owned by you. Call relay-lock.ps1 -Action renew every few turns. Do not create a second chain while the ledger has an in_progress stage.
$ledgerRule
- Git write operations (commit, push, tag, stash, checkout) are a human checkpoint: never perform them, stop and report instead.
- Write intermediate artifacts to files. Keep the conversation to pointers and conclusions. Do not fabricate acceptance evidence.
- $completionRule
- $stopRule
The gate holds its own lock $gateLockPrompt, separate from the chain lock, so a ledger write cannot interleave with another writer.
"@

if ($DryRun) {
  Say 'DRYRUN prompt_preview_begin'
  Write-Host $prompt
  Say 'DRYRUN prompt_preview_end'
} else {
  try {
    [IO.File]::WriteAllText($PromptOut, $prompt, [Text.UTF8Encoding]::new($false))
  } catch {
    # A half started chain is worse than a chain that never started: the lock
    # is held and the ledger says running, so the project waits for a whole
    # TTL before anything can run again. The ledger this run created is
    # removed again and the lock is released, so the next run starts clean.
    $promptErrorType = $_.Exception.GetType().Name
    $promptErrorText = ([string]$_.Exception.Message) -replace '\s+', '_'
    if ($ledgerBootstrapped -and (Test-Path -LiteralPath $ledgerPath)) {
      try { Remove-Item -LiteralPath $ledgerPath -Force } catch { }
    }
    $lockReleased = 'no'
    try {
      & $lockScript -Action release -SessionId ('start-relay:' + $PID) | Out-Null
      if ($LASTEXITCODE -eq 0) { $lockReleased = 'yes' }
    } catch { }
    Say "FAIL reason=prompt_write_failed path=$PromptOut exception=$promptErrorType hint=$promptErrorText lock_released=$lockReleased"
    exit 2
  }
  Say "OK prompt_written path=$PromptOut bytes=$((Get-Item $PromptOut).Length)"
  Say $nextHint
  Say $nextHint2
}
Say "DONE exit=0 target=$Target"
exit 0
