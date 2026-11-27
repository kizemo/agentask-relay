<#
.SYNOPSIS
  Relay chain cross-session mutex lock (agentask-relay kit).

.DESCRIPTION
  Guarantees that at most ONE relay session may act as writer for a project.
  The lock is a single file created with CreateNew semantics, which is atomic
  on NTFS: the loser of a race gets IOException instead of overwriting.

  Lock file contents (ASCII JSON):
    holder      : session id or "start-relay:<pid>" that owns the lock
    prev_holder : previous owner, for audit trail
    stage       : stage number the owner is working on
    title       : human readable title
    acquired_at : ISO8601
    heartbeat_at: ISO8601, refreshed by -Action renew
    ttl_seconds : stale threshold

  A lock whose heartbeat is older than ttl is considered abandoned and is
  taken over (the stale file is kept as .stale.<epoch_ms> for forensics). The
  ttl comes from the runtime descriptor the installer stamped next to this
  script (lock_ttl_seconds); a caller that passes -TtlSeconds explicitly
  overrides it, and a lock that was written with a ttl keeps that ttl when it
  is renewed. A lock whose heartbeat cannot be read, or whose heartbeat lies
  in the future, is treated like an abandoned lock: nobody can prove that its
  holder is alive.

  HAND-OVER GATE (the reason a stopped foreground cannot start a second ring)
    A link may start the next link only after it has taken a one-time permit:
      relay-lock.ps1 -Action prespawn -SessionId <me> -Stage <next stage>
    prespawn refuses when the chain is stopped, when the lock belongs to
    another session, when a background job registered by this session is still
    alive, or when an unused, unexpired permit is outstanding. The printed
    nonce must travel inside the next prompt; the next link consumes it as its
    first action:
      relay-lock.ps1 -Action verify -SessionId <me> -Nonce <nonce>
    verify re-checks the permit, rotates the lock onto the new session and
    marks the permit consumed. The nonce is not optional: a verify without it
    is refused, because a call that carries no proof proves nothing. The same
    rule guards the hand-over: -Action adopt refuses without an outstanding
    permit and with a wrong nonce, and it refuses while the chain is stopped.
    A duplicate ring (same prompt, spawned twice)
    therefore loses: the second verify finds the permit consumed, the first
    verify already moved the lock, and the second session must stop without
    writing anything. A session whose foreground was stopped but whose
    background job wakes up again cannot spawn either: it is no longer the
    holder, it has no permit, or it still holds the one it never consumed.

  SIBLING STATE FILES (same directory as the lock)
    .spawn-permit.json : one-time spawn permit, ttl 300s
    .jobs.json         : background jobs registered by a session (pid + owner)
    .stop              : stop sentinel; whoever creates it stops the chain.
                         -Action stop-clear marks it cleared instead of
                         deleting it, so the audit trail survives.

.EXAMPLE
  pwsh -NoProfile -File relay-lock.ps1 -Action acquire -Stage 1 -Title relay-1
  pwsh -NoProfile -File relay-lock.ps1 -Action renew
  pwsh -NoProfile -File relay-lock.ps1 -Action adopt -SessionId mvs_xxx
  pwsh -NoProfile -File relay-lock.ps1 -Action prespawn -SessionId mvs_xxx -Stage 2
  pwsh -NoProfile -File relay-lock.ps1 -Action verify -SessionId mvs_yyy -Nonce <nonce>
  pwsh -NoProfile -File relay-lock.ps1 -Action stop-mark -SessionId mvs_xxx -Note "human stop"
  pwsh -NoProfile -File relay-lock.ps1 -Action job-register -SessionId mvs_xxx -ProcId 4242
  pwsh -NoProfile -File relay-lock.ps1 -Action job-clear -ProcId 4242
  pwsh -NoProfile -File relay-lock.ps1 -Action gate-status
  pwsh -NoProfile -File relay-lock.ps1 -Action release
  pwsh -NoProfile -File relay-lock.ps1 -Action status
#>
param(
  [Parameter(Mandatory = $true)]
  [ValidateSet('acquire', 'renew', 'release', 'status', 'adopt', 'prespawn', 'verify', 'stop-mark', 'stop-clear', 'job-register', 'job-clear', 'gate-status')]
  [string]$Action,

  [string]$SessionId = '',
  [string]$Title = '',
  [int]$Stage = 0,
  # 0 means the caller did not choose a ttl. The effective value then comes from
  # the runtime descriptor the installer stamped and falls back to the built-in
  # default; a number that is passed always wins.
  [int]$TtlSeconds = 0,
  [string]$LockPath = '',
  [string]$Nonce = '',
  [int]$ProcId = 0,
  [string]$Note = ''
)

$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
if ([string]::IsNullOrWhiteSpace($LockPath)) {
  $LockPath = Join-Path $repoRoot 'docs\relay\.relay.lock'
}

$lockDir = Split-Path -Parent $LockPath
if ([string]::IsNullOrWhiteSpace($lockDir)) { $lockDir = '.' }
$permitPath = Join-Path $lockDir '.spawn-permit.json'
$jobPath = Join-Path $lockDir '.jobs.json'
$stopPath = Join-Path $lockDir '.stop'
$permitTtlSeconds = 300
$bootstrapHolderPrefix = 'start-relay:'
$defaultTtlSeconds = 1800
# The runtime descriptor the installer stamped lives next to this script. It
# carries the project level ttl (lock_ttl_seconds), so that the installer
# parameter is not a dead one and no caller has to remember the number.
$descriptorPath = Join-Path $PSScriptRoot 'relay-runtime.json'

function Get-LockRecord {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) { return $null }
  try {
    return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json)
  } catch {
    return $null
  }
}

function Save-LockRecord {
  param([string]$Path, $Record)
  $json = $Record | ConvertTo-Json -Depth 4
  $tmp = "$Path.tmp"
  [IO.File]::WriteAllText($tmp, $json, [Text.UTF8Encoding]::new($false))
  Move-Item -LiteralPath $tmp -Destination $Path -Force
}

function New-LockAtomically {
  param([string]$Path, $Record)
  $json = $Record | ConvertTo-Json -Depth 4
  try {
    $fs = [IO.File]::Open($Path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
  } catch [System.IO.IOException] {
    return $false
  }
  try {
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes($json)
    $fs.Write($bytes, 0, $bytes.Length)
    $fs.Flush($true)
  } finally {
    $fs.Dispose()
  }
  return $true
}

function New-LockRecord {
  param([string]$Holder, [string]$PrevHolder, [int]$StageNo, [string]$TaskTitle, [int]$Ttl)
  $nowRec = [DateTimeOffset]::Now
  return [ordered]@{
    holder       = $Holder
    prev_holder  = $PrevHolder
    stage        = $StageNo
    title        = $TaskTitle
    acquired_at  = $nowRec.ToString('o')
    heartbeat_at = $nowRec.ToString('o')
    ttl_seconds  = $Ttl
    repo_root    = $repoRoot
  }
}

function Read-JsonFile {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) { return $null }
  try {
    return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json)
  } catch {
    return $null
  }
}

function Get-RecordHeartbeat {
  param($Record)
  if ($null -eq $Record) { return $null }
  $raw = ''
  try { $raw = [string]$Record.heartbeat_at } catch { $raw = '' }
  if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
  $parsed = [DateTimeOffset]::MinValue
  if (-not [DateTimeOffset]::TryParse($raw, [ref]$parsed)) { return $null }
  return $parsed
}

function Get-RecordTtl {
  param($Record)
  if ($null -eq $Record) { return 0 }
  try { return [int]$Record.ttl_seconds } catch { return 0 }
}

# The ttl of a lock is a project level decision: the installer stamps it into
# the runtime descriptor, a caller may pass it explicitly, and a lock that was
# written with a ttl keeps that ttl when it is renewed. Precedence: explicit
# parameter, recorded value, descriptor, built-in default.
function Resolve-EffectiveTtl {
  param([int]$RecordedTtl = 0)
  if ($TtlSeconds -gt 0) { return @{ Value = $TtlSeconds; Source = 'parameter' } }
  if ($RecordedTtl -gt 0) { return @{ Value = $RecordedTtl; Source = 'recorded' } }
  $descriptorTtl = 0
  $descriptor = Read-JsonFile -Path $descriptorPath
  if ($null -ne $descriptor) {
    try { $descriptorTtl = [int]$descriptor.lock_ttl_seconds } catch { $descriptorTtl = 0 }
  }
  if ($descriptorTtl -gt 0) { return @{ Value = $descriptorTtl; Source = 'descriptor' } }
  return @{ Value = $defaultTtlSeconds; Source = 'default' }
}

function Write-JsonAtomic {
  param([string]$Path, $Record)
  $json = $Record | ConvertTo-Json -Depth 6
  $tmp = "$Path.tmp"
  [IO.File]::WriteAllText($tmp, $json, [Text.UTF8Encoding]::new($false))
  Move-Item -LiteralPath $tmp -Destination $Path -Force
}

function Test-StopActive {
  if (-not (Test-Path -LiteralPath $stopPath)) { return $false }
  $stopRec = Read-JsonFile -Path $stopPath
  if ($null -eq $stopRec) { return $true }
  return [string]::IsNullOrWhiteSpace([string]$stopRec.cleared_at)
}

function Get-StopNote {
  $stopRec = Read-JsonFile -Path $stopPath
  if ($null -eq $stopRec) { return '' }
  return [string]$stopRec.note
}

function Get-LiveJobPids {
  param([string]$Owner)
  $result = @()
  $doc = Read-JsonFile -Path $jobPath
  if ($null -eq $doc) { return $result }
  foreach ($job in @($doc.jobs)) {
    if ($null -eq $job) { continue }
    if (-not [string]::IsNullOrWhiteSpace($Owner) -and [string]$job.owner -ne $Owner) { continue }
    if ([string]$job.state -eq 'done') { continue }
    $procId = 0
    if (-not [int]::TryParse([string]$job.pid, [ref]$procId)) { continue }
    if ($null -ne (Get-Process -Id $procId -ErrorAction SilentlyContinue)) { $result += [string]$procId }
  }
  return $result
}

function Test-PermitExpired {
  param($Permit, $Now)
  try {
    return (([DateTimeOffset]::Parse([string]$Permit.expires_at)) -le $Now)
  } catch {
    return $true
  }
}

$now = [DateTimeOffset]::Now

switch ($Action) {

  'acquire' {
    if (-not (Test-Path -LiteralPath $lockDir -PathType Container)) {
      Write-Host "LOCK_DIR_MISSING path=$lockDir"
      exit 2
    }
    $ttl = Resolve-EffectiveTtl
    $effectiveTtl = $ttl.Value
    $ttlSource = $ttl.Source
    $existing = Get-LockRecord -Path $LockPath
    if ($null -eq $existing) {
      if (Test-Path -LiteralPath $LockPath) {
        # The lock file is there but cannot be read as json. Nobody can prove
        # that its holder is alive, so the chain may take it over and the broken
        # file is kept for forensics.
        $stale = "$LockPath.stale.$($now.ToUnixTimeMilliseconds())"
        Move-Item -LiteralPath $LockPath -Destination $stale -Force
        Write-Host "LOCK_TAKEOVER stale_holder=unknown age_s=-1 reason=unreadable_lock kept=$stale"
      }
    } else {
      $hb = Get-RecordHeartbeat -Record $existing
      $age = if ($null -eq $hb) { -1.0 } else { ($now - $hb).TotalSeconds }
      # A heartbeat in the future proves nothing either: the holder cannot be
      # shown to be alive, so such a lock is treated like an abandoned one.
      $alive = ($null -ne $hb) -and ($age -ge 0) -and ($age -le $effectiveTtl)
      if ($alive) {
        Write-Host "LOCK_HELD holder=$($existing.holder) stage=$($existing.stage) age_s=$([int]$age) ttl_s=$effectiveTtl path=$LockPath"
        exit 2
      }
      $reason = if ($null -eq $hb) { 'unreadable_heartbeat' } elseif ($age -lt 0) { 'future_heartbeat' } else { 'expired' }
      $stale = "$LockPath.stale.$($now.ToUnixTimeMilliseconds())"
      Move-Item -LiteralPath $LockPath -Destination $stale -Force
      Write-Host "LOCK_TAKEOVER stale_holder=$($existing.holder) age_s=$([int]$age) reason=$reason kept=$stale"
    }

    $holder = if ([string]::IsNullOrWhiteSpace($SessionId)) { "start-relay:$PID" } else { $SessionId }
    $rec = New-LockRecord -Holder $holder -PrevHolder '' -StageNo $Stage -TaskTitle $Title -Ttl $effectiveTtl
    if (-not (New-LockAtomically -Path $LockPath -Record $rec)) {
      Write-Host "LOCK_RACE holder=$holder path=$LockPath"
      exit 2
    }
    # A new chain starts with a clean permit. A permit left over by a dead
    # holder would refuse the first link, whose verify is the bootstrap one.
    $leftoverPermit = Read-JsonFile -Path $permitPath
    if ($null -ne $leftoverPermit) {
      Remove-Item -LiteralPath $permitPath -Force -ErrorAction SilentlyContinue
      Write-Host "LOCK_PERMIT_CLEARED path=$permitPath"
    }
    Write-Host "LOCK_ACQUIRED holder=$holder stage=$Stage ttl_s=$effectiveTtl ttl_source=$ttlSource path=$LockPath"
    exit 0
  }

  'renew' {
    $existing = Get-LockRecord -Path $LockPath
    if ($null -eq $existing) {
      Write-Host 'LOCK_MISSING action=renew'
      exit 3
    }
    if (-not [string]::IsNullOrWhiteSpace($SessionId) -and $existing.holder -ne $SessionId) {
      Write-Host "LOCK_NOT_MINE holder=$($existing.holder) requester=$SessionId"
      exit 5
    }
    $ttl = Resolve-EffectiveTtl -RecordedTtl (Get-RecordTtl -Record $existing)
    $existing.heartbeat_at = $now.ToString('o')
    $existing.ttl_seconds = $ttl.Value
    Save-LockRecord -Path $LockPath -Record $existing
    Write-Host "LOCK_RENEWED holder=$($existing.holder) heartbeat_at=$($existing.heartbeat_at) ttl_s=$($ttl.Value) ttl_source=$($ttl.Source)"
    exit 0
  }

  'adopt' {
    if ([string]::IsNullOrWhiteSpace($SessionId)) {
      Write-Host 'LOCK_BAD_ARG action=adopt missing -SessionId'
      exit 6
    }
    if (Test-StopActive) {
      Write-Host "LOCK_REFUSED reason=chain_stopped note=$(Get-StopNote) path=$stopPath"
      exit 3
    }
    $existing = Get-LockRecord -Path $LockPath
    if ($null -eq $existing) {
      Write-Host 'LOCK_MISSING action=adopt'
      exit 3
    }
    # The hand-over is a one-time permit, exactly like the verify flow: the
    # driver takes a permit first and hands it over together with its nonce.
    # Without that, any session could take the lock away from a running chain.
    $permit = Read-JsonFile -Path $permitPath
    if ($null -eq $permit) {
      Write-Host 'LOCK_REFUSED reason=permit_required hint=take a permit with -Action prespawn before the hand-over'
      exit 3
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$permit.consumed_at)) {
      Write-Host "LOCK_REFUSED reason=permit_consumed consumed_by=$($permit.consumed_by)"
      exit 3
    }
    if ([string]::IsNullOrWhiteSpace($Nonce)) {
      Write-Host 'LOCK_REFUSED reason=nonce_required'
      exit 3
    }
    if ([string]$permit.nonce -ne $Nonce) {
      Write-Host "LOCK_REFUSED reason=nonce_mismatch permit_nonce=$($permit.nonce)"
      exit 3
    }
    if (Test-PermitExpired -Permit $permit -Now $now) {
      Write-Host "LOCK_REFUSED reason=permit_expired expires_at=$($permit.expires_at)"
      exit 3
    }
    $permit.consumed_at = $now.ToString('o')
    $permit.consumed_by = $SessionId
    Write-JsonAtomic -Path $permitPath -Record $permit
    $existing.prev_holder = $existing.holder
    $existing.holder = $SessionId
    $existing.heartbeat_at = $now.ToString('o')
    if ($Stage -gt 0) { $existing.stage = $Stage }
    if (-not [string]::IsNullOrWhiteSpace($Title)) { $existing.title = $Title }
    Save-LockRecord -Path $LockPath -Record $existing
    Write-Host "LOCK_ADOPTED holder=$SessionId prev_holder=$($existing.prev_holder) stage=$($existing.stage) nonce=$($permit.nonce)"
    exit 0
  }

  'prespawn' {
    if ([string]::IsNullOrWhiteSpace($SessionId)) {
      # The mcoderuntime link cannot read its own session id, so the recorded
      # holder is the identity of the caller. An explicit id still wins.
      $probe = Get-LockRecord -Path $LockPath
      if ($null -ne $probe) { $SessionId = [string]$probe.holder }
    }
    if ([string]::IsNullOrWhiteSpace($SessionId)) {
      Write-Host 'SPAWN_REFUSED reason=missing_session'
      exit 6
    }
    if (Test-StopActive) {
      Write-Host "SPAWN_REFUSED reason=chain_stopped note=$(Get-StopNote) path=$stopPath"
      exit 3
    }
    $existing = Get-LockRecord -Path $LockPath
    if ($null -eq $existing) {
      Write-Host 'SPAWN_REFUSED reason=lock_missing'
      exit 3
    }
    if ($existing.holder -ne $SessionId) {
      Write-Host "SPAWN_REFUSED reason=lock_not_mine holder=$($existing.holder) requester=$SessionId"
      exit 5
    }
    $livePids = @(Get-LiveJobPids -Owner $SessionId)
    if ($livePids.Count -gt 0) {
      Write-Host "SPAWN_REFUSED reason=background_jobs_live owner=$SessionId pids=$($livePids -join ',') hint=clear them with -Action job-clear once they finished"
      exit 5
    }
    $permit = Read-JsonFile -Path $permitPath
    if ($null -ne $permit -and [string]::IsNullOrWhiteSpace([string]$permit.consumed_at)) {
      if (-not (Test-PermitExpired -Permit $permit -Now $now)) {
        Write-Host "SPAWN_REFUSED reason=permit_outstanding nonce=$($permit.nonce) expires_at=$($permit.expires_at)"
        exit 3
      }
    }
    $newNonce = [guid]::NewGuid().ToString('N').Substring(0, 16)
    $permitRec = [ordered]@{
      nonce       = $newNonce
      owner       = $SessionId
      stage       = $Stage
      issued_at   = $now.ToString('o')
      expires_at  = $now.AddSeconds($permitTtlSeconds).ToString('o')
      consumed_at = ''
      consumed_by = ''
      repo_root   = $repoRoot
    }
    Write-JsonAtomic -Path $permitPath -Record $permitRec
    Write-Host "SPAWN_PERMIT ok nonce=$newNonce owner=$SessionId stage=$Stage expires_in_s=$permitTtlSeconds path=$permitPath"
    Write-Host "NEXT put the nonce into the next prompt, then spawn; the next link must run relay-lock.ps1 -Action verify -SessionId <its own session id> -Nonce $newNonce as its first action"
    exit 0
  }

  'verify' {
    if ([string]::IsNullOrWhiteSpace($SessionId)) {
      Write-Host 'PERMIT_INVALID reason=missing_session'
      exit 6
    }
    if (Test-StopActive) {
      Write-Host "PERMIT_INVALID reason=chain_stopped note=$(Get-StopNote)"
      exit 3
    }
    $existing = Get-LockRecord -Path $LockPath
    if ($null -eq $existing) {
      Write-Host 'PERMIT_INVALID reason=lock_missing'
      exit 3
    }
    $permit = Read-JsonFile -Path $permitPath
    if ($null -eq $permit) {
      # Bootstrap: only the very first link, before any permit was ever issued,
      # may take a lock that still carries the launcher placeholder holder.
      if ($existing.holder -eq $SessionId) {
        Write-Host "SPAWN_VERIFIED ok bootstrap=false already_holder=$SessionId"
        exit 0
      }
      if ([string]$existing.holder -like ($bootstrapHolderPrefix + '*')) {
        $existing.prev_holder = $existing.holder
        $existing.holder = $SessionId
        $existing.heartbeat_at = $now.ToString('o')
        if ($Stage -gt 0) { $existing.stage = $Stage }
        Save-LockRecord -Path $LockPath -Record $existing
        Write-Host "SPAWN_VERIFIED ok bootstrap=true from=$($existing.prev_holder) to=$SessionId"
        exit 0
      }
      Write-Host "PERMIT_INVALID reason=no_permit holder=$($existing.holder)"
      exit 3
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$permit.consumed_at)) {
      Write-Host "PERMIT_INVALID reason=permit_consumed consumed_by=$($permit.consumed_by)"
      exit 3
    }
    # The nonce IS the permit: a verify that carries none proves nothing, so it
    # is refused instead of silently accepted.
    if ([string]::IsNullOrWhiteSpace($Nonce)) {
      Write-Host 'PERMIT_INVALID reason=nonce_required'
      exit 6
    }
    if ([string]$permit.nonce -ne $Nonce) {
      Write-Host "PERMIT_INVALID reason=nonce_mismatch permit_nonce=$($permit.nonce)"
      exit 3
    }
    if (Test-PermitExpired -Permit $permit -Now $now) {
      Write-Host "PERMIT_INVALID reason=permit_expired expires_at=$($permit.expires_at)"
      exit 3
    }
    $permitOwner = [string]$permit.owner
    $driverAdopted = ($existing.holder -eq $SessionId)
    if (-not $driverAdopted -and $existing.holder -ne $permitOwner) {
      Write-Host "PERMIT_INVALID reason=holder_changed holder=$($existing.holder) permit_owner=$permitOwner"
      exit 3
    }
    $permit.consumed_at = $now.ToString('o')
    $permit.consumed_by = $SessionId
    Write-JsonAtomic -Path $permitPath -Record $permit
    if (-not $driverAdopted) {
      $existing.prev_holder = $permitOwner
      $existing.holder = $SessionId
      $existing.heartbeat_at = $now.ToString('o')
      if ($Stage -gt 0) { $existing.stage = $Stage }
      Save-LockRecord -Path $LockPath -Record $existing
    } else {
      $existing.heartbeat_at = $now.ToString('o')
      Save-LockRecord -Path $LockPath -Record $existing
    }
    Write-Host "SPAWN_VERIFIED ok nonce=$($permit.nonce) from=$permitOwner to=$SessionId driver_adopted=$($driverAdopted.ToString().ToLower()) stage=$($existing.stage)"
    exit 0
  }

  'stop-mark' {
    $rec = [ordered]@{
      marked_at  = $now.ToString('o')
      marked_by  = $SessionId
      note       = $Note
      cleared_at = ''
      cleared_by = ''
      repo_root  = $repoRoot
    }
    Write-JsonAtomic -Path $stopPath -Record $rec
    Write-Host "STOP_MARKED marked_by=$SessionId note=$Note path=$stopPath"
    Write-Host 'NEXT every prespawn and every verify is refused until a human clears it with relay-lock.ps1 -Action stop-clear'
    exit 0
  }

  'stop-clear' {
    if (-not (Test-Path -LiteralPath $stopPath)) {
      Write-Host 'STOP_NOT_MARKED nothing_to_clear'
      exit 0
    }
    $rec = Read-JsonFile -Path $stopPath
    if ($null -eq $rec) {
      $rec = [ordered]@{ marked_at = ''; marked_by = ''; note = '' }
    }
    $rec | Add-Member -NotePropertyName cleared_at -NotePropertyValue $now.ToString('o') -Force
    $rec | Add-Member -NotePropertyName cleared_by -NotePropertyValue $SessionId -Force
    Write-JsonAtomic -Path $stopPath -Record $rec
    Write-Host "STOP_CLEARED cleared_by=$SessionId path=$stopPath"
    exit 0
  }

  'job-register' {
    if ([string]::IsNullOrWhiteSpace($SessionId)) {
      Write-Host 'LOCK_BAD_ARG action=job-register missing -SessionId'
      exit 6
    }
    if ($ProcId -le 0) {
      Write-Host 'LOCK_BAD_ARG action=job-register missing -ProcId'
      exit 6
    }
    $doc = Read-JsonFile -Path $jobPath
    $list = @()
    if ($null -ne $doc) { $list = @($doc.jobs | Where-Object { $null -ne $_ }) }
    $entry = [ordered]@{
      pid           = $ProcId
      owner         = $SessionId
      label         = $Title
      state         = 'registered'
      registered_at = $now.ToString('o')
      cleared_at    = ''
    }
    $list = @($list) + $entry
    if ($list.Count -gt 40) { $list = @($list | Where-Object { [string]$_.state -ne 'done' }) }
    Write-JsonAtomic -Path $jobPath -Record ([ordered]@{ updated_at = $now.ToString('o'); jobs = @($list) })
    Write-Host "JOB_REGISTERED pid=$ProcId owner=$SessionId total=$(@($list).Count)"
    exit 0
  }

  'job-clear' {
    $doc = Read-JsonFile -Path $jobPath
    if ($null -eq $doc) {
      Write-Host 'JOB_NOT_FOUND nothing_to_clear'
      exit 0
    }
    $list = @($doc.jobs | Where-Object { $null -ne $_ })
    $changed = 0
    foreach ($job in $list) {
      if ([string]$job.state -eq 'done') { continue }
      $match = $false
      if ($ProcId -gt 0) { $match = ([string]$job.pid -eq [string]$ProcId) }
      elseif (-not [string]::IsNullOrWhiteSpace($SessionId)) { $match = ([string]$job.owner -eq $SessionId) }
      if (-not $match) { continue }
      $job | Add-Member -NotePropertyName state -NotePropertyValue 'done' -Force
      $job | Add-Member -NotePropertyName cleared_at -NotePropertyValue $now.ToString('o') -Force
      $changed++
    }
    Write-JsonAtomic -Path $jobPath -Record ([ordered]@{ updated_at = $now.ToString('o'); jobs = @($list) })
    Write-Host "JOB_CLEARED changed=$changed pid=$ProcId owner=$SessionId"
    exit 0
  }

  'gate-status' {
    $existing = Get-LockRecord -Path $LockPath
    $holderText = if ($null -eq $existing) { 'none' } else { [string]$existing.holder }
    $stopText = if (Test-StopActive) { 'yes' } else { 'no' }
    $permitText = 'none'
    $permit = Read-JsonFile -Path $permitPath
    if ($null -ne $permit) {
      if (-not [string]::IsNullOrWhiteSpace([string]$permit.consumed_at)) { $permitText = 'consumed' }
      elseif (Test-PermitExpired -Permit $permit -Now $now) { $permitText = 'expired' }
      else { $permitText = 'outstanding' }
    }
    $livePids = @(Get-LiveJobPids -Owner '')
    Write-Host "GATE holder=$holderText stop=$stopText permit=$permitText jobs_live=$($livePids.Count) pids=$($livePids -join ',') lock=$LockPath"
    exit 0
  }

  'release' {
    $existing = Get-LockRecord -Path $LockPath
    if ($null -eq $existing) {
      Write-Host 'LOCK_FREE action=release'
      exit 0
    }
    if (-not [string]::IsNullOrWhiteSpace($SessionId) -and $existing.holder -ne $SessionId) {
      Write-Host "LOCK_NOT_MINE holder=$($existing.holder) requester=$SessionId"
      exit 5
    }
    Remove-Item -LiteralPath $LockPath -Force
    Write-Host "LOCK_RELEASED holder=$($existing.holder)"
    exit 0
  }

  'status' {
    $existing = Get-LockRecord -Path $LockPath
    if ($null -eq $existing) {
      if (Test-Path -LiteralPath $LockPath) {
        Write-Host "LOCK_STATE state=UNREADABLE holder=unknown prev_holder= stage= age_s=-1 ttl_s=0 path=$LockPath reason=unreadable_lock"
        exit 0
      }
      Write-Host "LOCK_FREE path=$LockPath"
      exit 0
    }
    $ttl = Resolve-EffectiveTtl -RecordedTtl (Get-RecordTtl -Record $existing)
    $hb = Get-RecordHeartbeat -Record $existing
    $age = if ($null -eq $hb) { -1.0 } else { ($now - $hb).TotalSeconds }
    $state = if ($null -eq $hb) { 'UNREADABLE' } elseif ($age -lt 0) { 'STALE' } elseif ($age -le $ttl.Value) { 'LIVE' } else { 'STALE' }
    Write-Host "LOCK_STATE state=$state holder=$($existing.holder) prev_holder=$($existing.prev_holder) stage=$($existing.stage) age_s=$([int]$age) ttl_s=$($ttl.Value) path=$LockPath"
    exit 0
  }
}