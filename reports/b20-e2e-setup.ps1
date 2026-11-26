$ErrorActionPreference = 'Stop'

# B20 fixture builder: prove start-relay.ps1 -AutoFinalize closes a chain whose
# only stage is already done but whose terminal status was never flipped.
#
# Shape: ONE stage, ONE real link. The link writes the stage record and bumps
# current_stage to 2 (> max_stages 1) but is told NOT to set status=done - that
# is the shape an -AutoFinalize run exists for. The operator (controller) runs
# the launcher afterwards; this script only builds the fixture, starts the
# chain, and runs the negative control that must NOT close it.
#
# Pure ASCII on purpose (house rule 4). Writes only to $env:TEMP.

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$root  = Join-Path $env:TEMP ('relay-b20-e2e-' + $stamp)
$repo  = Join-Path $root 'repo'
$relay = Join-Path $repo 'docs\relay'
$log   = Join-Path $root 'b20-setup.log'
$installer = 'F:\soft\00selfmade\agentask-relay\tool\scripts\install-relay.ps1'
$script:fail = 0

function Log { param([string]$Line) Write-Host $Line; [IO.File]::AppendAllText($log, $Line + "`n") }
function Chk {
  param([string]$Name, [bool]$Cond, [string]$Detail)
  if ($Cond) { Log ('PASS ' + $Name + ' ' + $Detail) }
  else { Log ('FAIL ' + $Name + ' ' + $Detail); $script:fail++ }
}

New-Item -ItemType Directory -Path (Join-Path $repo 'docs') -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $repo 'src')  -Force | Out-Null
Log ('B20_ROOT=' + $root)

$plan = @'
# Plan b20 - one stage, the operator closes the chain

Goal: prove that `start-relay.ps1 -AutoFinalize` closes a chain whose only
declared stage is already done but whose terminal status was never flipped.
That is the crash shape: the last link wrote its stage record and died before
turning status into done.

## Fixture rule (binding for the link of this chain)
This chain has max_stages = 1. The single link must NOT commit
`set_status=done` and must NOT start a next session. The operator runs the
launcher with `-AutoFinalize` once the stage record is on disk; that writeback
is the only allowed way for this chain to reach status=done.

## Stage 1
List every git tracked file of this repository into
docs/relay/stage-1-inventory.md, with the byte size of each file and the total.

## Acceptance
- docs/relay/stage-1-inventory.md exists and lists every tracked file.
- docs/relay.json reads status=running, current_stage=2, max_stages=1,
  stages=[1:done] when the link stops.
- max_stages is 1: there is no second stage.
'@
[IO.File]::WriteAllText((Join-Path $repo 'docs\plan-b20.md'), $plan, [Text.UTF8Encoding]::new($false))

$readme = @'
# b20 fixture

Throwaway repository for the relay-port -AutoFinalize end-to-end check.
'@
[IO.File]::WriteAllText((Join-Path $repo 'README.md'), $readme, [Text.UTF8Encoding]::new($false))

$src = @'
param([string]$Path = '.')
Get-ChildItem -LiteralPath $Path -File -Recurse |
  Select-Object FullName, Length |
  Sort-Object Length -Descending
'@
[IO.File]::WriteAllText((Join-Path $repo 'src\inventory.ps1'), $src, [Text.UTF8Encoding]::new($false))

& git -C $repo init -q
& git -C $repo add -A
& git -C $repo -c user.name='relay-fixture' -c user.email='relay@example.invalid' commit -q -m 'fixture: b20 plan and sources'
if ($LASTEXITCODE -ne 0) { Log ('FAIL git_commit exit=' + $LASTEXITCODE); exit 2 }
Log 'OK fixture_committed'

$answersPath = Join-Path $repo 'docs\adaptation-answers.json'
$answers = @'
{
  "schema": "relay-port/adaptation-answers@1",
  "write_set_allow": ["docs/", "src/"],
  "write_set_deny": [
    ".github/workflows/",
    "**/.env*",
    "**/*.key",
    "**/*.pem",
    "**/*.pfx",
    "scripts/publish-*",
    "scripts/release-*",
    "scripts/deploy-*",
    "scripts/sign-*",
    "**/gate*.ps1",
    "docs/relay/*.ps1"
  ],
  "concurrency_check": "pwsh -NoProfile -ExecutionPolicy Bypass -File docs\\relay\\relay-lock.ps1 -Action status",
  "gate_command": "pwsh -NoProfile -ExecutionPolicy Bypass -File docs\\relay\\relay-ledger.ps1 -Action status",
  "gate_verdict_field": "LEDGER_STATE status=running",
  "model_primary": "minimax/MiniMax-M3",
  "model_fallback_day": "custom_provider:provider-aa5659/auto",
  "model_fallback_night": "custom_provider:provider-aa5659/deepseek-v4.1-flash-1017",
  "confirmed_by": "defaults-accepted-for-throwaway-fixture",
  "confirmed_at": "2026-11-26"
}
'@
[IO.File]::WriteAllText($answersPath, $answers, [Text.UTF8Encoding]::new($false))

$target = 'B20 auto finalize on a real chain: one stage, terminal flip left to the launcher'
$stages = '1. inventory tracked files into docs\relay\stage-1-inventory.md'

function Run([string]$Label, [string[]]$Argv) {
  $out = @(& pwsh -NoProfile -ExecutionPolicy Bypass @Argv 2>&1 | ForEach-Object { [string]$_ })
  $code = $LASTEXITCODE
  Log ('=== ' + $Label + ' exit=' + $code + ' ===')
  foreach ($line in $out) { Log $line }
  return [pscustomobject]@{ Code = $code; Lines = $out }
}

$installArgv = @('-File', $installer, '-RepoRoot', $repo, '-Target', $target, '-PlanDoc', 'docs\plan-b20.md',
  '-StageTitles', $stages, '-MaxStages', '1', '-Runtime', 'mcode')
$r1 = Run 'INSTALL_PASS_1' $installArgv
$r2 = Run 'INSTALL_PASS_2' ($installArgv + @('-AnswersFile', 'docs\adaptation-answers.json'))
Chk 'install_pass1_pending' (($r1.Lines -join "`n") -match 'ADAPTATION_STATUS=pending') ('exit=' + $r1.Code)
Chk 'install_pass2_confirmed' (($r2.Lines -join "`n") -match 'ADAPTATION_STATUS=confirmed') ('exit=' + $r2.Code)

$launcher = Join-Path $relay 'start-relay.ps1'
$r3 = Run 'LAUNCHER' @('-File', $launcher, '-Target', $target, '-MaxStages', '1')
Chk 'launcher_exit0' ($r3.Code -eq 0) ('exit=' + $r3.Code)
Chk 'launcher_bootstrap' (($r3.Lines -join "`n") -match 'OK ledger_bootstrapped') 'bootstrap line'
Chk 'launcher_prompt' (($r3.Lines -join "`n") -match 'OK prompt_written') 'prompt line'

$ledgerPath = Join-Path $repo 'docs\relay.json'
function Ledger {
  return (Get-Content -LiteralPath $ledgerPath -Raw -Encoding UTF8 | ConvertFrom-Json)
}
$L = Ledger
Log ('LEDGER status=' + $L.status + ' current_stage=' + $L.current_stage + ' max_stages=' + $L.max_stages + ' stages=' + @($L.stages).Count + ' next_session_id=[' + $L.next_session_id + ']')
Chk 'bootstrap_running' ($L.status -eq 'running' -and [int]$L.current_stage -eq 1 -and [int]$L.max_stages -eq 1) 'status/current/max'

# --- negative control: nothing is done yet, -AutoFinalize must refuse ---------
$negPath = Join-Path $root 'b20-negative.log'
$neg = @(& pwsh -NoProfile -ExecutionPolicy Bypass -File $launcher -Target $target -MaxStages 1 -AutoFinalize 2>&1 | ForEach-Object { [string]$_ })
$negCode = $LASTEXITCODE
[IO.File]::WriteAllText($negPath, (($neg -join "`n") + "`n"), [Text.UTF8Encoding]::new($false))
Log ('=== NEGATIVE_CONTROL exit=' + $negCode + ' log=' + $negPath + ' ===')
foreach ($line in $neg) { Log $line }
$negText = $neg -join "`n"
Chk 'neg_exit3' ($negCode -eq 3) ('exit=' + $negCode)
Chk 'neg_cap' ($negText -match 'FAIL reason=chain_at_stage_cap') 'cap line'
Chk 'neg_all_done_unknown' ($negText -match 'all_done=unknown') 'no stage record yet'
Chk 'neg_no_finalize' (-not ($negText -match 'AUTO_FINALIZED')) 'must not close the chain'
$L = Ledger
Chk 'neg_ledger_untouched' ($L.status -eq 'running') ('status=' + $L.status)

# --- the content handed to the single real link -------------------------------
# The link gets the launcher prompt byte for byte, preceded by a fixture control
# note. The note only removes work this chain must not do: it is the crash shape
# under test, not a shortcut around the ledger gate.
$promptPath = Join-Path $relay 'next-relay-prompt.txt'
if (-not (Test-Path -LiteralPath $promptPath)) { Log 'FAIL prompt_file_missing'; exit 2 }
$promptText = Get-Content -LiteralPath $promptPath -Raw -Encoding UTF8

$note = @'
[OPERATOR NOTE - controlled E2E fixture. This note wins over the rest of the prompt.]
This chain has max_stages = 1 and you are its ONLY link. Do exactly these four
steps, then stop. Do not do anything else.

1. Write docs\relay\stage-1-inventory.md: every git tracked file of this
   repository plus its byte size, and the total.
2. Through the ledger gate docs\relay\relay-ledger.ps1, commit TWO patches in
   this order (read sha256 from -Action status before each one, validate each
   one with -DryRun, then -Action commit -ExpectSha256):
   a. {"append_stage":{"id":1,"title":"inventory tracked files","status":"pending"}}
   b. {"stage_done":1,"bump_current_stage":true}
3. Then STOP. Do not set_status=done. Do not set_status=blocked. Do not call
   session_create and do not start a next link. Do not run git commit, push or
   tag. Do not release the chain lock. The launcher closes this chain on
   purpose: leaving status=running with current_stage=2 is the expected end
   state of this fixture.
4. Run docs\relay\relay-ledger.ps1 -Action status once and paste its
   LEDGER_STATE and LEDGER_CHAIN lines verbatim into your final reply.
'@
$ringPath = Join-Path $relay 'b20-ring-instruction.txt'
[IO.File]::WriteAllText($ringPath, ($note + "`n`n" + $promptText), [Text.UTF8Encoding]::new($false))
Log ('RING_CONTENT_PATH=' + $ringPath)
Log ('RING_CONTENT_BYTES=' + (Get-Item -LiteralPath $ringPath).Length)

Log ('B20_REPO=' + $repo)
Log ('B20_LEDGER=' + $ledgerPath)
Log ('B20_PROMPT=' + $promptPath)
Log ('SUMMARY fail=' + $script:fail)
if ($script:fail -gt 0) { exit 2 }
Write-Output 'SETUP_OK'
exit 0