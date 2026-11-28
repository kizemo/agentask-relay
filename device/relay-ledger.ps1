<#
.SYNOPSIS
  Relay ledger writeback gate: compare-and-swap + append-only invariants.

.DESCRIPTION
  docs\relay.json is the single source of truth for chain progress, and several
  sessions touch it (the finishing stage, the stage it just started, a human).
  Prose that says "reload before merging, append only" does not prevent lost
  updates: PROOF-DOC-DRIVEN-2026-11-24.md records a real cross-session race that
  was survived only because a model happened to notice it.

  This script turns that prose into a gate. A session never hand-edits the
  ledger; it declares its intent in a small ASCII JSON patch file and this
  script applies it under five rules:

    1. writer lock  - docs\relay\.ledger.lock, created with CreateNew (atomic on
                      NTFS). A lock older than -LockStaleSeconds is provably
                      abandoned and gets taken over, kept as .stale.<epoch_ms>
                      for forensics, so a crashed writer cannot wedge the chain.
    2. CAS          - -ExpectSha256 is the hash you read BEFORE you started
                      working. If the ledger on disk differs, your view is stale:
                      LEDGER_FAIL reason=cas_conflict, nothing is written, you
                      must re-read and rebase. Checked twice: before the lock and
                      again under the lock. This is what kills the lost update.
    3. append-only  - stages / sessions / notes / ledger_docs / blocked_on /
                      human_checkpoints / stop_conditions may only grow: every
                      pre-existing element must still be there, byte-identical,
                      at the same index. A stage entry may only be edited by the
                      stage that owns it (stage_done must match its id), and
                      only through the keys listed in stage_fields. Top-level
                      scalars outside the allowlist (status, current_stage,
                      next_session_id, updated_at) must not change, and no new
                      top-level key may be invented.
    4. read-back    - the bytes go to a temp file, move into place, then are
                      re-read and compared verbatim. LEDGER_COMMITED carries the
                      before/after hashes and the element counts.
    5. session trail- a stage_done commit registers the session that ran the
                      stage in sessions[] by itself, so the ledger keeps an
                      independent trail of every session even when a link
                      forgets the sessions_append intent. The registration is
                      append only, and a session id that is already in
                      sessions[] is never added twice.

  Protocol rules are enforced in code, not prose: set_status may never be
  "running" (AGENT-RELAY.md: only a human starts a chain). Unknown patch keys
  are rejected so a typo cannot silently no-op a required writeback.

  Intended flow: -Action status (read sha256) -> do the work -> write a patch
  file -> -DryRun commit to validate -> real commit. Re-running the same patch
  after a cas_conflict is safe: appends are de-duplicated, so a commit that
  already landed is rejected by CAS rather than applied twice.

  -Action doctor is read-only on purpose: it prints DOCTOR_STATE, one DANGLING
  line for every contradiction the ledger proves about itself (a current_stage
  no stage carries, a session id left behind on a stopped chain, a blocked
  status with no reason, a done status with open stages), and a DOCTOR_VERDICT.
  It takes no writer lock and writes no byte, so it is safe to run while another
  session is mid-commit. A session id that points at an ARCHIVED session needs
  the host's session store to judge; doctor does not guess at it.

  -Action migrate-hint is the read-only half of a schema migration. A ledger
  written by an older kit can be self-consistent (doctor says nothing) and still
  carry shapes this gate cannot act on: a stage keyed by stage instead of id
  (stage_done resolves by id, so such a stage can never be closed by a patch), a
  stage with no identity key at all, a max_stages no stage cap can be compared
  against, a stage status this gate never writes. It prints one MIGRATE_HINT
  line per shape and suggests the key to rename, takes no writer lock and writes
  no byte. Migrating a live chain is a human decision, so the action never
  rewrites the ledger itself.

  B30: -LedgerPaths scans several ledgers in one run. Porting a kit usually
  sweeps more than one project, and one path per process gave no combined
  verdict. Pass one value per argument or a comma/semicolon separated list.
  A batch prints MIGRATE_SCAN per ledger, MIGRATE_HINT lines carrying
  path=, and one MIGRATE_SCAN_VERDICT. A missing or unparsable ledger is
  reported and counted instead of aborting the sweep. Single-ledger output is
  unchanged, so every existing caller keeps its contract.

  Exit codes: 0 committed (or dry-run verified) / 2 bad arguments /
  3 CAS conflict, rule violation, or ledger missing / 4 writer lock timeout /
  5 patch file unparsable. doctor: 0 clean, 3 findings.
  migrate-hint: 0 nothing to migrate, 3 hints printed. In a batch, 3 when any
  ledger produced a hint or could not be read.

.EXAMPLE
  pwsh -NoProfile -File relay-ledger.ps1 -Action status

.EXAMPLE
  pwsh -NoProfile -File relay-ledger.ps1 -Action doctor

.EXAMPLE
  pwsh -NoProfile -File relay-ledger.ps1 -Action commit -ExpectSha256 <sha> -Patch docs\relay\stage-1-patch.json
#>
param(
  [Parameter(Mandatory = $true)]
  [ValidateSet('status', 'commit', 'doctor', 'migrate-hint')]
  [string]$Action,

  [string]$ExpectSha256 = '',
  [string]$Patch = '',
  [string]$LedgerPath = '',
  [string[]]$LedgerPaths = @(),
  [string]$LockPath = '',
  [int]$TimeoutMs = 5000,
  [int]$LockStaleSeconds = 30,
  [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
if ([string]::IsNullOrWhiteSpace($LedgerPath)) { $LedgerPath = Join-Path $repoRoot 'docs\relay.json' }
if ([string]::IsNullOrWhiteSpace($LockPath)) { $LockPath = Join-Path $repoRoot 'docs\relay\.ledger.lock' }

$protectedArrays = @('stages', 'sessions', 'notes', 'ledger_docs', 'blocked_on', 'human_checkpoints', 'stop_conditions')
$scalarAllowlist = @('status', 'current_stage', 'next_session_id', 'updated_at')
$gateOwnedKeys = @($scalarAllowlist + $protectedArrays)   # the gate may create these itself
$patchKeys = @('stage_done', 'stage_fields', 'append_stage', 'sessions_append', 'notes_append',
  'ledger_docs_append', 'blocked_on_append', 'set_status', 'bump_current_stage', 'next_session_id')

function Ser($value) {
  if ($null -eq $value) { return '<null>' }
  # B31-F6: piping into ConvertTo-Json unwraps a one-element array, so a scalar
  # and a one-element array serialised identically and the append-only check
  # could not see an array turned into a scalar. -InputObject keeps the shape.
  return (ConvertTo-Json -InputObject $value -Depth 100 -Compress)
}
function Get-LedgerSha { param([string]$Path) (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash }
function Say($text) { Write-Host $text }
function Fail {
  param([string]$Reason, [string]$Detail = '', [int]$Code = 3)
  Say ("LEDGER_FAIL reason=" + $Reason + $(if ($Detail) { ' ' + $Detail } else { '' }))
  exit $Code
}
# B31-F11: -LedgerPaths only ever did something for -Action migrate-hint. On
# the other actions it was parsed and then dropped, so a caller that swept a
# batch of ledgers and then asked for a status got one ledger's state and no
# word that the other paths were ignored. Refuse instead of pretending.
$batchPathsGiven = @(@($LedgerPaths) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
if ($Action -ne 'migrate-hint' -and $batchPathsGiven.Count -gt 0) {
  Fail 'ledger_paths_not_supported_for_action' ("action=" + $Action + " hint=-LedgerPaths_is_only_for_-Action_migrate-hint") 2
}
function Keys($obj) {
  if ($null -eq $obj) { return @() }
  return @($obj.PSObject.Properties.Name)
}

function Get-Elements($value) {
  # @($null).Count is 1 in PowerShell, so a ledger seed that never carried an
  # array was reported as one element ("stages=1" on a ledger with no stage at
  # all) and an append built on @($missing) wrote a null into a gate-owned
  # array. Every count and every append goes through this filter instead.
  return @(@($value) | Where-Object { $null -ne $_ })
}

function Read-Ledger {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) { Fail 'ledger_missing' ("path=" + $Path) }
  # B31-F3b: a path that cannot be read (a directory, a denied file) threw out
  # of the script with exit 1 and a stack trace, a code the gate contract does
  # not define. Every read failure is a refusal now.
  try { $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 }
  catch { Fail 'ledger_unreadable' ("path=" + $Path) }
  try { return $raw | ConvertFrom-Json } catch { Fail 'ledger_unparsable' ("path=" + $Path) }
}

function Enter-WriterLock {
  param([string]$Path, [int]$Timeout, [int]$StaleSeconds)
  $dir = Split-Path -Parent $Path
  if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  $deadline = (Get-Date).AddMilliseconds($Timeout)
  while ($true) {
    $fs = $null
    try {
      $fs = [IO.File]::Open($Path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
      $bytes = [Text.UTF8Encoding]::new($false).GetBytes("pid=$PID host=$env:COMPUTERNAME taken_at=$([DateTimeOffset]::Now.ToString('o'))")
      $fs.Write($bytes, 0, $bytes.Length)
      $fs.Flush($true)
      return $fs
    } catch [System.IO.IOException] {
      if ($null -ne $fs) { $fs.Dispose() }
      $fs = $null
    } catch {
      if ($null -ne $fs) { $fs.Dispose() }
      $fs = $null
      throw
    }
    # Somebody holds it: take it over only if it is provably abandoned.
    # B31-F4: the age came from the file mtime alone. A lock whose mtime sits
    # in the future (clock skew, a restored copy) could never grow older than
    # the stale window, so every writer timed out and the chain was wedged for
    # good. The lock file carries the timestamp its writer claimed, and a
    # claimed time in the future cannot prove the writer is alive.
    $age = $null
    try {
      $lockText = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
      if ($lockText -match 'taken_at=(?<ts>[^\s]+)') {
        $taken = [DateTimeOffset]::MinValue
        if ([DateTimeOffset]::TryParse([string]$Matches['ts'], [ref]$taken)) {
          $age = (([DateTimeOffset]::Now) - $taken).TotalSeconds
          if ($age -lt 0) { $age = $StaleSeconds + 1 }
        }
      }
    } catch { }
    if ($null -eq $age) {
      try { $age = ((Get-Date) - (Get-Item -LiteralPath $Path).LastWriteTime).TotalSeconds } catch { }
    }
    try {
      if ($null -ne $age -and $age -gt $StaleSeconds) {
        $kept = "$Path.stale.$([DateTimeOffset]::Now.ToUnixTimeMilliseconds())"
        Move-Item -LiteralPath $Path -Destination $kept -Force
        Say "LEDGER_LOCK_TAKEOVER age_s=$([int]$age) kept=$kept"
        continue
      }
    } catch { }
    if ((Get-Date) -ge $deadline) { return $null }
    Start-Sleep -Milliseconds 50
  }
}

function To-Map {
  # Accepts {"k":"v"} and [{"k":"v"},{"k2":"v2"}]: ConvertFrom-Json yields PSCustomObjects.
  param($v)
  $map = [ordered]@{}
  if ($null -eq $v) { return $map }
  foreach ($e in @($v)) {
    if ($e -is [System.Collections.IDictionary]) {
      foreach ($k in $e.Keys) { $map[[string]$k] = $e[$k] }
    } else {
      foreach ($k in (Keys $e)) { $map[$k] = $e.$k }
    }
  }
  return $map
}

function Set-NoteProp {
  param($Target, [string]$Name, $Value)
  $Target | Add-Member -Force -NotePropertyName $Name -NotePropertyValue $Value
}

# --- action: status ------------------------------------------------------------
if ($Action -eq 'status') {
  $l = Read-Ledger -Path $LedgerPath
  Say ("LEDGER_STATE path=" + $LedgerPath +
    " sha256=" + (Get-LedgerSha -Path $LedgerPath) +
    " status=" + [string]$l.status +
    " current_stage=" + [string]$l.current_stage +
    " max_stages=" + [string]$l.max_stages +
    " stages=" + @(Get-Elements $l.stages).Count +
    " sessions=" + @(Get-Elements $l.sessions).Count +
    " notes=" + @(Get-Elements $l.notes).Count +
    " updated_at=" + [string]$l.updated_at)
  # B19-a: the chain shape in the same words the launcher prints on its cap gate
  # (FAIL reason=chain_at_stage_cap). stages= here is the per-stage id:status
  # list, not the count on LEDGER_STATE above; the line prefix separates the two.
  # The two renderings are computed by separate code on purpose: the self test
  # feeds both the same ledger and compares them, so a drift in either one goes
  # red instead of being copied over from the other.
  $declaredStages = @(Get-Elements $l.stages)
  $chainParts = @()
  $doneStages = 0
  $chainIdx = 0
  foreach ($s in $declaredStages) {
    $stageStatus = [string]$s.status
    if ([string]::IsNullOrWhiteSpace($stageStatus)) { $stageStatus = 'unknown' }
    if ($stageStatus -eq 'done') { $doneStages++ }
    # B30: identity is id, with stage as the fallback doctor already uses. id
    # alone rendered an empty key (":done") on a ledger written before id
    # existed, which reads as a stage whose id is the empty string. A stage
    # carrying neither key is printed by index, never as an empty key.
    $chainKey = ([string]$s.id).Trim()
    if ($chainKey -eq '') { $chainKey = ([string]$s.stage).Trim() }
    if ($chainKey -eq '') { $chainKey = '#' + [string]$chainIdx }
    $chainParts += ('{0}:{1}' -f $chainKey, $stageStatus)
    $chainIdx++
  }
  $chainStages = 'none'
  $chainAllDone = 'unknown'
  $chainOpen = 'none'
  if ($declaredStages.Count -gt 0) {
    $chainStages = ($chainParts -join ',')
    $chainOpen = [string]($declaredStages.Count - $doneStages)
    if ($doneStages -eq $declaredStages.Count) { $chainAllDone = 'true' } else { $chainAllDone = 'false' }
  }
  # cap_reached stays unknown when either number is missing: reporting false there
  # would read as "there is room left" on a ledger that cannot even be compared.
  $capReached = 'unknown'
  $curStageNum = 0
  $maxStageNum = 0
  $curStageOk = [int]::TryParse([string]$l.current_stage, [ref]$curStageNum)
  $maxStageOk = [int]::TryParse([string]$l.max_stages, [ref]$maxStageNum)
  if ($curStageOk -and $maxStageOk) {
    if ($curStageNum -ge $maxStageNum) { $capReached = 'true' } else { $capReached = 'false' }
  }
  Say ("LEDGER_CHAIN current_stage=" + [string]$l.current_stage +
    " max_stages=" + [string]$l.max_stages +
    " cap_reached=" + $capReached +
    " stages=" + $chainStages +
    " all_done=" + $chainAllDone +
    " open_stages=" + $chainOpen)
  exit 0
}

# --- action: doctor (read only) -------------------------------------------------
# A relay port reported a ledger whose current_stage named a stage the ledger did
# not contain, and whose next_session_id still named the session of a chain that
# had already stopped. Every reader downstream (launcher, driver, next link)
# believes those fields, so the gate needs a command that says it out loud instead
# of leaving it to whoever happens to read the JSON. doctor reports only: no
# writer lock, no directory creation, no write. The self test proves that by
# comparing the ledger sha256 and the gate directory around a run.
#
# Nothing here invents a verdict it cannot prove from the file: whether a session
# id points at an ARCHIVED session lives in the host's session store, so doctor
# reports the shapes the ledger can check about itself.
if ($Action -eq 'doctor') {
  $l = Read-Ledger -Path $LedgerPath
  $findings = 0
  Say ("DOCTOR_STATE path=" + $LedgerPath +
    " sha256=" + (Get-LedgerSha -Path $LedgerPath) +
    " status=" + [string]$l.status +
    " current_stage=" + [string]$l.current_stage +
    " max_stages=" + [string]$l.max_stages +
    " stages=" + @(Get-Elements $l.stages).Count +
    " sessions=" + @(Get-Elements $l.sessions).Count +
    " notes=" + @(Get-Elements $l.notes).Count)

  $statusText = ([string]$l.status).Trim().ToLowerInvariant()
  if (@('running', 'pending', 'done', 'blocked') -notcontains $statusText) {
    $findings++
    Say ("DANGLING status=" + [string]$l.status + " reason=status_not_allowed allowed=running,pending,done,blocked")
  }

  $stageList = @(@($l.stages) | Where-Object { $null -ne $_ })
  # Stage identity is resolved once and shared by every check below. Current
  # ledgers key their stages by id; ledgers written before that key existed use
  # stage. Reading id alone made such a ledger look like it held no stage at all,
  # so current_stage was called missing and every unnamed stage produced its own
  # duplicate line. A stage that carries neither key is reported once, by index.
  $stageKeys = @()
  $stageIdx = 0
  foreach ($s in $stageList) {
    $k = ([string]$s.id).Trim()
    if ($k -eq '') { $k = ([string]$s.stage).Trim() }
    $stageKeys += [pscustomobject]@{ idx = $stageIdx; key = $k; status = ([string]$s.status).Trim().ToLowerInvariant() }
    $stageIdx++
  }
  $curNum = 0
  $maxNum = 0
  $curOk = [int]::TryParse([string]$l.current_stage, [ref]$curNum)
  $maxOk = [int]::TryParse([string]$l.max_stages, [ref]$maxNum)
  if (-not $curOk) {
    $findings++
    Say ("DANGLING current_stage=" + [string]$l.current_stage + " reason=not_an_integer")
  } else {
    if ($maxOk -and $curNum -gt $maxNum) {
      $findings++
      Say ("DANGLING current_stage=" + $curNum + " max_stages=" + $maxNum + " reason=beyond_stage_cap")
    }
    # Only judged once the ledger declares stages at all. The launcher seeds a
    # fresh ledger with current_stage=1 and stages=[] by design, and calling that
    # dangling would make every new chain start red.
    if ($stageList.Count -gt 0) {
      $hit = $false
      foreach ($sk in $stageKeys) {
        if ($sk.key -ne '' -and $sk.key -eq [string]$curNum) { $hit = $true; break }
      }
      if (-not $hit) {
        $findings++
        Say ("DANGLING current_stage=" + $curNum + " stage_missing=" + $curNum)
      }
      $seen = @{}
      foreach ($sk in $stageKeys) {
        if ($sk.key -eq '') {
          $findings++
          Say ("DANGLING stage_index=" + $sk.idx + " reason=stage_id_missing")
        } elseif ($seen.ContainsKey($sk.key)) {
          $seen[$sk.key] = $seen[$sk.key] + 1
        } else { $seen[$sk.key] = 1 }
      }
      foreach ($sid in @($seen.Keys | Sort-Object)) {
        if ($seen[$sid] -gt 1) {
          $findings++
          Say ("DANGLING stage_id=" + $sid + " reason=duplicate_stage_id count=" + $seen[$sid])
        }
      }
    }
  }

  $nextText = [string]$l.next_session_id
  if (-not [string]::IsNullOrWhiteSpace($nextText) -and $statusText -ne 'running') {
    $findings++
    Say ("DANGLING next_session_id=" + $nextText + " reason=dead_pointer status=" + $statusText)
  }

  if ($statusText -eq 'blocked') {
    $blockedList = @(@($l.blocked_on) | ForEach-Object { [string]$_ } | Where-Object { $_ -ne '' })
    if ($blockedList.Count -lt 1) {
      $findings++
      Say 'DANGLING status=blocked blocked_on_present=false'
    }
  }
  if ($statusText -eq 'done' -and $stageList.Count -gt 0) {
    $openIds = @($stageKeys | Where-Object { $_.status -ne 'done' } | ForEach-Object {
      if ($_.key -ne '') { $_.key } else { '#' + $_.idx }
    })
    if ($openIds.Count -gt 0) {
      $findings++
      Say ("DANGLING status=done reason=open_stages open_stages=" + ($openIds -join ','))
    }
  }

  if ($findings -eq 0) {
    Say 'DOCTOR_VERDICT ok findings=0'
    exit 0
  }
  Say ("DOCTOR_VERDICT dangling findings=" + $findings)
  exit 3
}

# --- action: migrate-hint (read only) -------------------------------------------
# A ledger written by an older kit can be perfectly self-consistent - doctor says
# nothing - and still carry shapes this gate cannot act on. The one that bites a
# live chain is the stage key: doctor falls back to it for identity, but commit
# resolves stage_done by id only, so such a stage can never be closed by a patch.
# The honest answer is not to rewrite the ledger under a running chain: it is to
# name every shape, say which key to rename, and let a human decide. Exit 3 means
# "there is advice", not "the ledger is broken"; doctor owns contradictions.
function Get-MigrateHintLines {
  # Reports instead of exiting: Fail calls exit, which would abort a sweep at the
  # first unreadable ledger. Nothing here takes the writer lock or writes a byte.
  param([string]$Path)
  $r = [pscustomobject]@{ path = $Path; readable = $true; reason = ''; sha = ''; stages = 0; max_stages = ''; lines = @() }
  if (-not (Test-Path -LiteralPath $Path)) { $r.readable = $false; $r.reason = 'ledger_missing'; return $r }
  try {
    $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    $l = $raw | ConvertFrom-Json
  } catch {
    $r.readable = $false; $r.reason = 'ledger_unparsable'; return $r
  }
  $r.sha = Get-LedgerSha -Path $Path
  $stageList = @(Get-Elements $l.stages)
  $r.stages = $stageList.Count
  $r.max_stages = [string]$l.max_stages

  $maxNum = 0
  if (-not [int]::TryParse([string]$l.max_stages, [ref]$maxNum)) {
    $rawMax = [string]$l.max_stages
    if ([string]::IsNullOrWhiteSpace($rawMax)) { $rawMax = '(none)' }
    $r.lines += ('scope=ledger item=stage_max_unknown value=' + $rawMax + ' effect=stage_cap_cannot_be_compared')
  }

  $allowedStageStatus = @('pending', 'in_progress', 'done')
  $hintIdx = 0
  foreach ($s in $stageList) {
    $idText = ([string]$s.id).Trim()
    $stageText = ([string]$s.stage).Trim()
    if ($idText -eq '' -and $stageText -ne '') {
      $r.lines += ('scope=stage index=' + $hintIdx + ' item=stage_key_not_id key=stage rename_to=id effect=commit_resolves_stage_done_by_id')
    } elseif ($idText -eq '') {
      $r.lines += ('scope=stage index=' + $hintIdx + ' item=stage_id_missing keys=' + ((Keys $s) -join ','))
    }
    $stageStatus = ([string]$s.status).Trim().ToLowerInvariant()
    if ($allowedStageStatus -notcontains $stageStatus) {
      $rawStatus = [string]$s.status
      if ([string]::IsNullOrWhiteSpace($rawStatus)) { $rawStatus = '(empty)' }
      $r.lines += ('scope=stage index=' + $hintIdx + ' item=stage_status_unknown status=' + $rawStatus)
    }
    $hintIdx++
  }
  return $r
}

if ($Action -eq 'migrate-hint') {
  # B30: -LedgerPaths scans several ledgers in one run. A missing or unparsable
  # ledger is reported and counted rather than aborting the sweep, because a
  # port that sweeps ten projects still wants the other nine judged. The
  # single-ledger path keeps its exact old vocabulary and exit codes.
  # A [string[]] parameter arrives as one element per call only when the caller
  # is PowerShell itself. `pwsh -File ... -LedgerPaths a.json,b.json` hands over
  # a single comma-joined string, which used to be treated as one path and made
  # the sweep report zero ledgers. Split a separator-joined value, but only when
  # the whole token is not itself an existing file, so a real path that happens
  # to contain a comma keeps working.
  $batch = @()
  foreach ($x in @($LedgerPaths)) {
    if ([string]::IsNullOrWhiteSpace([string]$x)) { continue }
    $raw = ([string]$x).Trim()
    $candidates = @($raw)
    if (-not (Test-Path -LiteralPath $raw)) { $candidates = $raw.Split([char[]]@(',', ';')) }
    foreach ($c in $candidates) {
      $t = ([string]$c).Trim()
      if ($t -ne '' -and $batch -notcontains $t) { $batch += $t }
    }
  }

  if ($batch.Count -eq 0) {
    $one = Get-MigrateHintLines -Path $LedgerPath
    if (-not $one.readable) { Say ("LEDGER_FAIL reason=" + $one.reason + " path=" + $LedgerPath); exit 3 }
    Say ("MIGRATE_STATE path=" + $LedgerPath +
      " sha256=" + $one.sha +
      " stages=" + $one.stages +
      " max_stages=" + $one.max_stages)
    foreach ($line in @($one.lines)) { Say ('MIGRATE_HINT ' + $line) }
    if (@($one.lines).Count -eq 0) {
      Say 'MIGRATE_VERDICT none hints=0'
      exit 0
    }
    Say ("MIGRATE_VERDICT suggested hints=" + @($one.lines).Count)
    exit 3
  }

  $totalHints = 0
  $unreadable = 0
  foreach ($pth in $batch) {
    $rep = Get-MigrateHintLines -Path $pth
    if (-not $rep.readable) {
      $unreadable++
      Say ("MIGRATE_SCAN path=" + $pth + " readable=false reason=" + $rep.reason)
      continue
    }
    Say ("MIGRATE_SCAN path=" + $pth + " readable=true sha256=" + $rep.sha +
      " stages=" + $rep.stages + " max_stages=" + $rep.max_stages +
      " hints=" + @($rep.lines).Count)
    foreach ($line in @($rep.lines)) { Say ('MIGRATE_HINT path=' + $pth + ' ' + $line) }
    $totalHints += @($rep.lines).Count
  }
  Say ("MIGRATE_SCAN_VERDICT ledgers=" + $batch.Count + " hints=" + $totalHints + " unreadable=" + $unreadable)
  if ($totalHints -gt 0 -or $unreadable -gt 0) { exit 3 }
  exit 0
}

# --- action: commit ------------------------------------------------------------
if ([string]::IsNullOrWhiteSpace($ExpectSha256)) { Fail 'missing_expect_sha256' 'hint=run_-Action_status_first_and_pass_the_sha256_you_read' 2 }
if ([string]::IsNullOrWhiteSpace($Patch)) { Fail 'missing_patch' 'hint=-Patch_<path_to_ascii_json>' 2 }
if (-not (Test-Path -LiteralPath $Patch)) { Fail 'patch_missing' ("path=" + $Patch) 2 }
if (-not (Test-Path -LiteralPath $LedgerPath)) { Fail 'ledger_missing' ("path=" + $LedgerPath) }

$patchRaw = Get-Content -LiteralPath $Patch -Raw -Encoding UTF8
try { $p = $patchRaw | ConvertFrom-Json } catch { Fail 'patch_unparsable' ("path=" + $Patch) 5 }
foreach ($k in (Keys $p)) {
  if ($patchKeys -notcontains $k) { Fail 'patch_unknown_key' ("key=" + $k + " allowed=" + ($patchKeys -join ',')) 2 }
}

try { $before = (Get-LedgerSha -Path $LedgerPath) } catch { Fail 'ledger_unreadable' ("path=" + $LedgerPath) }
if ($before -ne $ExpectSha256.Trim()) {
  Fail 'cas_conflict' ("expected=" + $ExpectSha256.Trim() + " disk=" + $before + " hint=reread_the_ledger_and_rebase_your_patch_before_retrying")
}
Say ("LEDGER_CAS_OK sha256=" + $before)

$lock = Enter-WriterLock -Path $LockPath -Timeout $TimeoutMs -StaleSeconds $LockStaleSeconds
if ($null -eq $lock) { Fail 'writer_lock_timeout' ("path=" + $LockPath + " timeout_ms=" + $TimeoutMs + " hint=a_concurrent_writer_is_still_commiting") 4 }

try {
  $old = Read-Ledger -Path $LedgerPath
  try { $nowSha = Get-LedgerSha -Path $LedgerPath } catch { Fail 'ledger_unreadable' ("path=" + $LedgerPath) }
  if ($nowSha -ne $ExpectSha256.Trim()) {
    Fail 'cas_conflict' ("expected=" + $ExpectSha256.Trim() + " disk=" + $nowSha + " stage=under_lock")
  }

  # Deep clone through a JSON round trip: $old stays pristine for the checks below.
  $new = (Ser $old) | ConvertFrom-Json
  $ownedIndex = -1
  $stageFieldNames = @()

  if ($null -ne $p.stage_done) {
    # [int] on a non-numeric value threw an unhandled cast error (exit 1, stack
    # trace) instead of the gate's own bad-argument exit. Parse first, then say no.
    $doneNum = 0
    if (-not [int]::TryParse([string]$p.stage_done, [ref]$doneNum)) {
      Fail 'stage_done_not_an_integer' ("value=" + [string]$p.stage_done + " hint=use_the_numeric_id_of_a_stage_in_the_ledger") 2
    }
    # B32: a ledger written by an older kit keyed its stages by stage, not by
    # id. Such a stage could never be closed by a patch, so the chain stalled on
    # a ledger doctor called healthy. The decision is to learn the old shape,
    # not to rewrite the file: pass 1 stays authoritative on id - a stage that
    # has an id is only ever matched by that id - and pass 2 then looks at
    # id-less stages whose legacy stage key carries that number, but only when
    # exactly one such stage matches. Two candidates with the same number stay
    # unclosed on purpose: guessing there would close the wrong stage.
    $resolvedStageText = ''
    $stageRef = @($new.stages)
    $idHit = -1
    for ($i = 0; $i -lt $stageRef.Count; $i++) {
      $stageIdNum = 0
      if (-not [int]::TryParse(([string]$stageRef[$i].id).Trim(), [ref]$stageIdNum)) { continue }
      if ($stageIdNum -eq $doneNum) { $idHit = $i; break }
    }
    if ($idHit -ge 0) { $ownedIndex = $idHit }
    if ($ownedIndex -lt 0) {
      $legacyHit = -1
      $legacyCount = 0
      for ($i = 0; $i -lt $stageRef.Count; $i++) {
        if (-not [string]::IsNullOrWhiteSpace([string]$stageRef[$i].id)) { continue }
        $legacyNum = 0
        if (-not [int]::TryParse(([string]$stageRef[$i].stage).Trim(), [ref]$legacyNum)) { continue }
        if ($legacyNum -eq $doneNum) { $legacyHit = $i; $legacyCount++ }
      }
      if ($legacyCount -eq 1) { $ownedIndex = $legacyHit }
    }
    if ($ownedIndex -lt 0) { Fail 'stage_not_found' ("stage_done=" + $doneNum + " hint=append_stage_first_or_use_an_id_already_in_the_ledger") }
    # The stage number that was actually resolved, so the session trail never
    # records an empty stage for a legacy stage that carries no id.
    $resolvedStageText = ([string](@($new.stages)[$ownedIndex].id)).Trim()
    if ($resolvedStageText -eq '') { $resolvedStageText = [string]$doneNum }
  }
  if ($null -ne $p.stage_fields -and $ownedIndex -lt 0) {
    Fail 'stage_fields_without_stage_done' 'hint=stage_fields_only_applies_to_the_stage_named_by_stage_done' 2
  }

  if ($ownedIndex -ge 0) {
    $entry = @($new.stages)[$ownedIndex]
    if ($null -ne $p.stage_fields) {
      # B31-F8: To-Map accepts anything, so a string payload became a map with
      # one "Length" key and was written onto the stage as a field named
      # Length. stage_fields is a map or the patch is refused.
      $sfValue = $p.stage_fields
      $sfIsObject = ($sfValue -is [System.Management.Automation.PSCustomObject]) -or ($sfValue -is [System.Collections.IDictionary])
      if (-not $sfIsObject) {
        Fail 'stage_fields_not_an_object' ("kind=" + $sfValue.GetType().Name + " hint=stage_fields_is_an_object_of_key_value_pairs") 2
      }
      $stageFieldMap = To-Map $p.stage_fields
      if ($stageFieldMap.Count -lt 1) { Fail 'stage_fields_empty' 'hint=an_object_of_key_value_pairs' 2 }
      $stageFieldNames = @($stageFieldMap.Keys)
      # A stage's identity key is not owner-authored. The verification loop below
      # skips stage_fields by design (they are the keys this commit may write),
      # so rewriting id or stage there passed every rule and left current_stage
      # pointing at a number no stage carried any more. Refused here, loudly.
      foreach ($k in $stageFieldNames) {
        if (@('id', 'stage') -contains ([string]$k).Trim().ToLowerInvariant()) {
          Fail 'stage_fields_rewrites_identity' ("stage_id=" + [string]$entry.id + " key=" + $k + " hint=identity_keys_are_not_stage_fields") 2
        }
      }
      foreach ($k in $stageFieldNames) { Set-NoteProp -Target $entry -Name $k -Value $stageFieldMap[$k] }
    }
    Set-NoteProp -Target $entry -Name 'status' -Value 'done'
    if (-not ((Keys $entry) -contains 'finished_at')) {
      Set-NoteProp -Target $entry -Name 'finished_at' -Value ([DateTimeOffset]::Now.ToString('o'))
    }
  }

  # --- rule 5: session trail -----------------------------------------------------
  # The session trail used to be a prose request only: a link had to add
  # sessions_append by itself, and a link that forgot left sessions[] empty
  # (that is what the B13 live chain ended with). The gate registers the
  # session that ran the stage by itself, so the ledger keeps an independent
  # trail of every session. Only an append is possible, and a session id that
  # is already in sessions[] is never added twice.
  if ($ownedIndex -ge 0) {
    $doneStage = @($new.stages)[$ownedIndex]
    $sessionId = [string]$doneStage.session_id
    $sessionSource = 'stage_field'
    $sessionSkip = ''
    if ([string]::IsNullOrWhiteSpace($sessionId)) {
      # The id of the link that is running right now is the one the previous
      # link wrote into next_session_id (the launcher writes it for the first
      # link of a cli chain). The fallback applies only while the chain is
      # running: on a blocked or finished chain next_session_id is a leftover,
      # and registering it would keep a stopped chain looking alive.
      $chainStatus = [string]$old.status
      if ($null -ne $p.set_status) { $chainStatus = ([string]$p.set_status).Trim().ToLowerInvariant() }
      if ($chainStatus -ne 'running') {
        $sessionSkip = 'chain_not_running status=' + $chainStatus
      } else {
        $sessionId = [string]$old.next_session_id
        $sessionSource = 'ledger_next_session_id'
      }
    }
    if ($sessionSkip -ne '') {
      Say ("LEDGER_SESSION_SKIPPED stage=" + $resolvedStageText + " reason=" + $sessionSkip)
    } elseif ([string]::IsNullOrWhiteSpace($sessionId)) {
      Say ("LEDGER_SESSION_SKIPPED stage=" + $resolvedStageText + " reason=no_session_id")
    } else {
      $known = $false
      $knownPattern = '"' + [regex]::Escape($sessionId) + '"'
      foreach ($s in @(Get-Elements $new.sessions)) {
        if ($s -is [string]) {
          # Substring matching called a short id "already registered" whenever it
          # happened to be a fragment of a longer one (abc inside abcdef), so the
          # trail silently lost the session that actually ran the stage. Only an
          # exact id counts here; an entry object matches on its own id fields or
          # on a whole quoted token in its serialised form.
          if (([string]$s).Trim().Equals($sessionId, [System.StringComparison]::OrdinalIgnoreCase)) { $known = $true; break }
          continue
        }
        $entryId = ''
        if ($null -ne $s.session_id) { $entryId = ([string]$s.session_id).Trim() }
        if ($entryId -eq '' -and $null -ne $s.id) { $entryId = ([string]$s.id).Trim() }
        if ($entryId.Equals($sessionId, [System.StringComparison]::OrdinalIgnoreCase)) { $known = $true; break }
        if ([regex]::IsMatch((Ser $s), $knownPattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)) { $known = $true; break }
      }
      if ($known) {
        Say ("LEDGER_SESSION_ALREADY_REGISTERED session=" + $sessionId)
      } else {
        Set-NoteProp -Target $new -Name 'sessions' -Value (@(@(Get-Elements $new.sessions) + @($sessionId)))
        Say ("LEDGER_SESSION_REGISTERED session=" + $sessionId +
          " stage=" + $resolvedStageText + " source=" + $sessionSource)
      }
    }
  }

  if ($null -ne $p.append_stage) {
    if ($null -eq $p.append_stage.id -or [string]::IsNullOrWhiteSpace([string]$p.append_stage.title)) {
      Fail 'append_stage_incomplete' 'hint=append_stage_needs_id_and_title' 2
    }
    # [int] on a stage id that is not a number threw an unhandled cast error
    # (exit 1 with a stack trace) instead of this gate's own refusal. Parse both
    # sides and compare numerically - the same rule stage_done already follows.
    $ids = @()
    foreach ($s in @(Get-Elements $new.stages)) {
      $sid = 0
      if ([int]::TryParse(([string]$s.id).Trim(), [ref]$sid)) { $ids += $sid; continue }
      # B32: a legacy stage carries its number under stage, not id. Count that
      # number as taken too, so appending an id that collides with it cannot
      # build a ledger where two stages claim the same number.
      $legacyNum = 0
      if ([int]::TryParse(([string]$s.stage).Trim(), [ref]$legacyNum)) { $ids += $legacyNum }
    }
    $appendNum = 0
    if (-not [int]::TryParse(([string]$p.append_stage.id).Trim(), [ref]$appendNum)) {
      Fail 'append_stage_id_not_an_integer' ("value=" + [string]$p.append_stage.id + " hint=append_stage_id_is_the_number_the_stage_cap_counts") 2
    }
    if ($ids -contains $appendNum) { Fail 'append_stage_duplicate_id' ("id=" + [string]$appendNum) }
    $item = $p.append_stage
    # B31-F7: a stage could arrive already marked done, which walked around the
    # rule that every stage must be closed by its own stage_done. Only pending
    # may be declared when a stage is appended.
    if ((Keys $item) -contains 'status') {
      $declaredStatus = ([string]$item.status).Trim().ToLowerInvariant()
      if ($declaredStatus -ne '' -and $declaredStatus -ne 'pending') {
        Fail 'append_stage_status_not_allowed' ("status=" + $declaredStatus + " hint=append_stage_declares_a_pending_stage_use_stage_done_to_close_it") 2
      }
    }
    Set-NoteProp -Target $item -Name 'status' -Value 'pending'
    Set-NoteProp -Target $new -Name 'stages' -Value (@(@(Get-Elements $new.stages) + @($item)))
  }

  # Append targets: only gate-owned arrays may be created when a seed lacks one.
  $appendPairs = @(
    @{ n = 'sessions_append';    f = 'sessions' },
    @{ n = 'notes_append';       f = 'notes' },
    @{ n = 'ledger_docs_append'; f = 'ledger_docs' },
    @{ n = 'blocked_on_append';  f = 'blocked_on' }
  )
  foreach ($pair in $appendPairs) {
    if ($null -eq $p.($pair.n)) { continue }
    if ($null -eq $new.($pair.f) -and $protectedArrays -notcontains $pair.f) {
      Fail 'ledger_field_missing' ("field=" + $pair.f + " hint=the_ledger_seed_is_missing_this_array")
    }
    # B31-F5/F2: the payload keeps its own shape. Casting an object to string
    # turned {"text":"hello"} into "@{text=hello; ts=...}", and @($null) on a
    # missing array wrote a null element into a gate-owned array, which then
    # poisoned every later commit. Dedupe compares the serialised form.
    $incoming = @(Get-Elements $p.($pair.n))
    $existing = @(Get-Elements $new.($pair.f))
    $fresh = @()
    foreach ($one in $incoming) {
      if ($one -is [string] -and [string]::IsNullOrWhiteSpace($one)) { continue }
      $dup = $false
      foreach ($e in $existing) {
        if ((Ser $e) -eq (Ser $one)) { $dup = $true; break }
        if (($e -is [string]) -and ($one -is [string]) -and $e.Equals($one, [System.StringComparison]::Ordinal)) { $dup = $true; break }
      }
      if ($dup) { continue }
      $fresh += $one
      $existing += $one
    }
    if ($fresh.Count -gt 0) {
      Set-NoteProp -Target $new -Name $pair.f -Value (@($existing))
    }
  }

  if ($null -ne $p.set_status) {
    $want = ([string]$p.set_status).Trim().ToLowerInvariant()
    if ($want -eq 'running') { Fail 'status_running_is_human_only' 'hint=AGENT-RELAY.md_only_a_human_starts_a_chain_use_done_or_blocked' }
    if (@('pending', 'done', 'blocked') -notcontains $want) {
      Fail 'status_not_allowed' ("value=" + $want + " allowed=pending,done,blocked") 2
    }
    # A terminal state has to agree with the stage list and with blocked_on.
    # Otherwise the ledger reads "done" while stages are still open, or reads
    # "blocked" without saying on what, and every reader downstream (launcher,
    # driver, next link) believes it.
    if ($want -eq 'done') {
      $openIds = @(@($new.stages) | Where-Object { ([string]$_.status).Trim().ToLowerInvariant() -ne 'done' } | ForEach-Object { [string]$_.id })
      if ($openIds.Count -gt 0) {
        Fail 'status_done_but_stages_open' ("open_stages=" + ($openIds -join ',') + " hint=send_stage_done_for_every_declared_stage_first")
      }
    }
    if ($want -eq 'blocked') {
      $blockedList = @(@($new.blocked_on) | ForEach-Object { [string]$_ } | Where-Object { $_ -ne '' })
      if ($blockedList.Count -lt 1) {
        Fail 'status_blocked_without_blocked_on' 'hint=send_blocked_on_append_in_the_same_patch_so_the_ledger_says_what_stopped'
      }
    }
    Set-NoteProp -Target $new -Name 'status' -Value $want
  }
  # B31-F10: the word "true" compared equal to $true, so a patch that carried
  # the string bumped the stage anyway. Only a real JSON boolean counts.
  if ($null -ne $p.bump_current_stage) {
    if ($p.bump_current_stage -isnot [bool]) {
      Fail 'bump_current_stage_not_a_boolean' ("value=" + [string]$p.bump_current_stage + " hint=bump_current_stage_is_a_json_boolean") 2
    }
    if ($p.bump_current_stage) {
      # [int] on a non-numeric current_stage threw an unhandled cast error (exit 1,
      # stack trace) instead of a refusal a link can act on. Parse first, then say no.
      $curNum = 0
      if (-not [int]::TryParse(([string]$new.current_stage).Trim(), [ref]$curNum)) {
        Fail 'current_stage_not_an_integer' ("value=" + [string]$new.current_stage + " hint=bump_current_stage_needs_a_numeric_current_stage_to_count_from") 2
      }
      Set-NoteProp -Target $new -Name 'current_stage' -Value ($curNum + 1)
    }
  }
  # An absent key means "do not touch it"; a present but empty value means
  # "clear it". Before B27 the empty value was dropped without a word, so the
  # stop recipe that tells a link to send set_status=blocked "with an empty
  # next_session_id" could not actually remove the claim it had written, and the
  # driver kept reading a dead id out of the ledger.
  if ((Keys $p) -contains 'next_session_id') {
    $nextRaw = [string]$p.next_session_id
    if ([string]::IsNullOrWhiteSpace($nextRaw)) {
      Set-NoteProp -Target $new -Name 'next_session_id' -Value ''
      Say ("LEDGER_NEXT_SESSION_CLEARED before=" + [string]$old.next_session_id + " after=(empty)")
    } else {
      Set-NoteProp -Target $new -Name 'next_session_id' -Value $nextRaw
      Say ("LEDGER_NEXT_SESSION_SET after=" + $nextRaw)
    }
  }
  Set-NoteProp -Target $new -Name 'updated_at' -Value ([DateTimeOffset]::Now.ToString('o'))

  # --- append-only verification, BEFORE anything is written -------------------
  foreach ($field in $protectedArrays) {
    if ($null -eq $old.$field -and $null -eq $new.$field) { continue }
    # B31-F1: @($null) is one element, so a ledger that never carried an array
    # was compared against the gate's own session trail and the commit was
    # refused as a rewrite of an existing entry. Get-Elements drops the null.
    $oldList = @(Get-Elements $old.$field)
    $newList = @(Get-Elements $new.$field)
    if ($newList.Count -lt $oldList.Count) { Fail 'rule_shrunk_array' ("field=" + $field + " before=" + $oldList.Count + " after=" + $newList.Count) }
    for ($i = 0; $i -lt $oldList.Count; $i++) {
      if ($field -eq 'stages' -and $i -eq $ownedIndex) {
        $oldEntry = $oldList[$i]
        $newEntry = $newList[$i]
        # @($oldEntry) enumerates the object itself (one element whose .Name is
        # null), so this guard compared '<null>' with '<null>' and could never
        # fire: a commit could have rewritten any key it did not declare. The
        # properties are what the rule is about.
        foreach ($prop in @($oldEntry.PSObject.Properties)) {
          if ($stageFieldNames -contains $prop.Name) { continue }
          if ($prop.Name -eq 'status') { continue }
          if ((Ser $prop.Value) -ne (Ser $newEntry.($prop.Name))) {
            Fail 'rule_edited_own_stage_key' ("stage_id=" + [string]$oldEntry.id + " key=" + $prop.Name)
          }
        }
        continue
      }
      if ((Ser $oldList[$i]) -ne (Ser $newList[$i])) { Fail 'rule_rewrote_existing_entry' ("field=" + $field + " index=" + $i) }
    }
  }
  foreach ($prop in @($new.PSObject.Properties)) {
    if ($gateOwnedKeys -contains $prop.Name -and -not ((Keys $old) -contains $prop.Name)) { continue }
    if (-not ((Keys $old) -contains $prop.Name)) { Fail 'rule_new_top_level_key' ("key=" + $prop.Name) }
  }
  foreach ($prop in @($old.PSObject.Properties)) {
    $k = $prop.Name
    if ($protectedArrays -contains $k) { continue }
    if ((Ser $old.$k) -eq (Ser $new.$k)) { continue }
    if ($scalarAllowlist -contains $k) { continue }
    Fail 'rule_changed_protected_field' ("field=" + $k)
  }
  Say ("LEDGER_RULES_OK stages=" + @(Get-Elements $old.stages).Count + "->" + @(Get-Elements $new.stages).Count +
    " sessions=" + @(Get-Elements $old.sessions).Count + "->" + @(Get-Elements $new.sessions).Count +
    " notes=" + @(Get-Elements $old.notes).Count + "->" + @(Get-Elements $new.notes).Count)

  $json = $new | ConvertTo-Json -Depth 100
  if ($DryRun) {
    Say ("LEDGER_DRYRUN verified=true before=" + $before + " would_be_stages=" + @(Get-Elements $new.stages).Count)
    exit 0
  }

  # B31-F3: an IO failure here ended the script with exit 1 and a stack trace,
  # a code the gate contract does not define, and left the temp file behind.
  $tmp = "$LedgerPath.tmp.$PID"
  try {
    [IO.File]::WriteAllText($tmp, $json, [Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $tmp -Destination $LedgerPath -Force
  } catch {
    try { if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue } } catch { }
    Fail 'writeback_failed' ("path=" + $LedgerPath + " hint=the_ledger_could_not_be_rewritten")
  }
  try { $after = Get-LedgerSha -Path $LedgerPath } catch { Fail 'ledger_unreadable' ("path=" + $LedgerPath) }
  $reread = Get-Content -LiteralPath $LedgerPath -Raw -Encoding UTF8
  if ($reread -ne $json) { Fail 'readback_mismatch' ("path=" + $LedgerPath + " sha=" + $after) }
  Say ("LEDGER_COMMITED before=" + $before + " after=" + $after +
    " stages=" + @(Get-Elements $old.stages).Count + "->" + @(Get-Elements $new.stages).Count +
    " sessions=" + @(Get-Elements $old.sessions).Count + "->" + @(Get-Elements $new.sessions).Count +
    " notes=" + @(Get-Elements $old.notes).Count + "->" + @(Get-Elements $new.notes).Count +
    " current_stage=" + [string]$old.current_stage + "->" + [string]$new.current_stage +
    " path=" + $LedgerPath)
  exit 0
} finally {
  try { $lock.Dispose() } catch { }
  try { Remove-Item -LiteralPath $LockPath -Force -ErrorAction SilentlyContinue } catch { }
}
