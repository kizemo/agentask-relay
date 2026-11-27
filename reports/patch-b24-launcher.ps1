$ErrorActionPreference = 'Stop'
$target = 'F:\soft\00selfmade\agentask-relay\tool\templates\start-relay.ps1'
$script:text = [IO.File]::ReadAllText($target)
$eol = if ($script:text.Contains("`r`n")) { "`r`n" } else { "`n" }
Write-Host ("INFO target_bytes=" + $script:text.Length + " eol=" + $(if ($eol -eq "`r`n") { 'CRLF' } else { 'LF' }))

function Patch {
  param([string]$Tag, [string]$Old, [string]$New)
  $o = $Old.Replace("`r`n", "`n").Replace("`n", $eol)
  $n = $New.Replace("`r`n", "`n").Replace("`n", $eol)
  $count = 0
  $idx = 0
  while (($idx = $script:text.IndexOf($o, $idx)) -ge 0) { $count++; $idx += $o.Length }
  if ($count -eq 0) { Write-Host ("PATCH_FAIL tag=" + $Tag + " reason=anchor_missing"); exit 2 }
  if ($count -ne 1) { Write-Host ("PATCH_FAIL tag=" + $Tag + " reason=anchor_not_unique count=" + $count); exit 3 }
  $i = $script:text.IndexOf($o)
  $script:text = $script:text.Substring(0, $i) + $n + $script:text.Substring($i + $o.Length)
  Write-Host ("PATCH_OK tag=" + $Tag)
}

# ---- 1. param block: host project becomes a knob, initiator + escape hatch ----
Patch 'param_host_project' @'
  # Expected host project (B23). The path (or the client side label) of the
  # project the operator believes the chain belongs to. It is a check, never a
  # knob: the host files a session under the project whose workspace path is
  # exactly the directory the session runs in, so the chain can only land in
  # the project keyed by the repository root. When the expectation differs, the
  # launcher says so at start time instead of letting the mismatch surface in
  # the client sidebar weeks later. Empty means "no expectation recorded".
  [string]$ExpectedHostProject = ''
)
'@ @'
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
'@

# ---- 2. section 1d rewrite + new section 1e (chain identity) -----------------
Patch 'section_1d_1e' @'
# --- 1d. host project key (B23) ------------------------------------------------
# Both session keyed hosts (mcode, claude-code) file a session under the project
# whose workspace path is EXACTLY the directory the session runs in, and there is
# no parent project mapping: a session that runs in <repo>\root can never appear
# under the project registered for <repo>, and a host that is given both a
# project and a workspace directory refuses the call outright. The launcher
# cannot move a link into another project, but it can name the project the chain
# WILL be filed under, so a mismatch is visible at start time instead of in the
# client sidebar weeks later.
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
if (-not [string]::IsNullOrWhiteSpace($expectedHostProject)) {
  $expectedNorm = $expectedHostProject.TrimEnd('\', '/')
  $actualNorm = $hostProjectKey.TrimEnd('\', '/')
  if ($expectedNorm -ieq $actualNorm) {
    Say "OK host_project_expected_matches expected=$expectedNorm"
  } else {
    Say "WARN host_project_mismatch expected=$expectedNorm actual_key=$actualNorm reason=host_projects_are_keyed_by_exact_workspace_path hint=the_chain_runs_in_the_repository_root_and_cannot_be_filed_under_another_project; rename_the_project_in_the_client_app_or_point_host-project.txt_at_the_repository_root"
  }
}
'@ @'
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
    if ($DryRun) {
      Say 'DRYRUN skip=host_project_gate reason=a_dry_run_previews_the_mismatch_and_never_stops'
    } elseif (-not $AllowHostMismatch) {
      Say "FAIL reason=host_project_mismatch expected=$expectedNorm actual_key=$actualNorm rule=sessions_are_filed_under_the_exact_session_directory hint=a_link_started_from_here_would_create_a_new_project_row; register_the_repository_root_as_a_project_or_re-run_with_-AllowHostMismatch_and_absolute_paths"
      exit 2
    } else {
      $hostProjectValue = $expectedNorm
      $hostProjectSource = 'expectation'
      $hostProjectMode = 'parent'
      Say "WARN host_project_parent_hosting project=$hostProjectValue reason=explicit_allow_host_mismatch rule=every_command_must_carry_an_absolute_path"
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
$chainId = 'relay-' + $chainStartedAt.ToString('yyyyMMdd-HHmmss')
$chainSuffix = '[' + $chainTag + ']'
$initiatorSession = $InitiatorSession.Trim()
if ([string]::IsNullOrWhiteSpace($initiatorSession)) {
  $initiatorSession = 'unknown'
  Say 'WARN initiator_session_missing hint=pass_-InitiatorSession_<your own session id>_so_the_chain_records_which_session_activated_it'
} else {
  Say "OK initiator_session=$initiatorSession"
}
Say "OK chain_id=$chainId chain_tag=$chainTag"
'@

# ---- 3. ledger seed: identity fields -----------------------------------------
Patch 'seed_identity' @'
    workspace_dir   = $repoRoot
    status          = 'running'
'@ @'
    workspace_dir   = $repoRoot
    host_project    = $hostProjectValue
    host_project_mode = $hostProjectMode
    chain_id        = $chainId
    chain_tag       = $chainTag
    initiator_session = $initiatorSession
    status          = 'running'
'@

# ---- 4. the mcode next hint: project= instead of workspace_dir ----------------
Patch 'next_hint_project' @'
$nextHint = 'NEXT call session_create with agent_name=me, title=' + $linkTag + '-<short stage name>, workspace_dir=<repoRoot backslashes>, content=<contents of the prompt file>'
'@ @'
$nextHint = 'NEXT call session_create with agent_name=me, title=' + $linkTag + '-<short stage name> ' + $chainSuffix + ', project=' + $hostProjectValue + ', content=<contents of the prompt file>. Never pass workspace_dir: it is mutually exclusive with project, and a directory that is not an exact project key makes the host insert a NEW project row.'
'@

# ---- 5. session naming rule carries the chain tag -----------------------------
Patch 'name_rule' @'
$nameRule = 'Session naming: this link is ' + $linkTag + ', the next one is ' + $nextLinkTag + '-<short stage name>. Keep the relay- prefix, the zero padded ordinal and the chain length intact: the session list is how a human reads the chain order, and relay-10 must not sort beside relay-1.'
'@ @'
$nameRule = 'Session naming: this link is ' + $linkTag + ', the next one is ' + $nextLinkTag + '-<short stage name> ' + $chainSuffix + '. Keep the relay- prefix, the zero padded ordinal and the chain length intact: the session list is how a human reads the chain order, and relay-10 must not sort beside relay-1. Append the chain tag ' + $chainSuffix + ' to the end of every title of this chain: it is what tells two chains apart, and the title is the only place where the newest link and its chain are readable from the sidebar alone.'
'@

# ---- 6. host project rule + parent hosting rewrites --------------------------
Patch 'host_rule' @'
  $nextHint = 'NEXT spawn the first link with the sessions_spawn tool (workspace = ' + $repoRoot + ')'
  $nextHint2 = 'NEXT then run relay-lock.ps1 -Action adopt -SessionId <new session id>'
}
'@ @'
  $nextHint = 'NEXT spawn the first link with the sessions_spawn tool (workspace = ' + $repoRoot + ')'
  $nextHint2 = 'NEXT then run relay-lock.ps1 -Action adopt -SessionId <new session id>'
}

# The project rule is the mechanism that keeps every link inside the project the
# human started from. It is a rule in the prompt and not a decision in the
# launcher, because only the link can read the project list of its own runtime.
$hostRule = '- Session project: call session_create with project=' + $hostProjectValue + ' (mode=' + $hostProjectMode + ') and NEVER with workspace_dir. That value must match a workspace_dir or a name in the project_list tool output VERBATIM. If nothing matches, do not start a session and do not fall back to workspace_dir: commit status=blocked through the ledger gate with a note naming the value you tried. Rationale: the host files a session under the project keyed by the exact session directory and inserts a NEW project row when the key is unknown, so a near miss detaches the chain from its project and litters the sidebar.'
if ($hostProjectMode -eq 'parent') {
  # Parent hosting: the session directory is the parent project, so any relative
  # docs\relay\... path in a recipe resolves under the wrong directory.
  $hostRule = $hostRule + ' Parent hosting is on: this session runs in the parent project directory, not in the repository root, so every path you act on must be absolute under ' + $promptRepoRoot + ' and every git call must be git -C ' + $promptRepoRoot + '.'
  $completionRule = $completionRule.Replace('docs\relay\', $promptRepoRoot + '\docs\relay\')
}
'@

# ---- 7. RULES: insert the host rule right after the naming rule ---------------
Patch 'rules_insert' @'
- $nameRule
- $sessionRule
'@ @'
- $nameRule
$hostRule
- $sessionRule
'@

# ---- 8. workspace note explains parent hosting --------------------------------
Patch 'workspace_note' @'
$workspaceNote = if ($cliRuntime) { 'absolute path, forward slashes' } else { 'absolute path, backslashes' }
'@ @'
$workspaceNote = if ($cliRuntime) { 'absolute path, forward slashes' } else { 'absolute path, backslashes' }
if ($hostProjectMode -eq 'parent') { $workspaceNote = $workspaceNote + '; this session runs in the parent project directory ' + $hostProjectValue + ', so every path must be absolute and every git call must use git -C ' + $promptRepoRoot }
'@

# ---- 9. ledger recipe absolute under parent hosting ---------------------------
Patch 'ledger_rule_absolute' @'
$ledgerRule = $ledgerRuleText
if ($cliRuntime) { $ledgerRule = $ledgerRuleText.Replace('docs\relay\', 'docs/relay/') }
'@ @'
$ledgerRule = $ledgerRuleText
if ($cliRuntime) { $ledgerRule = $ledgerRuleText.Replace('docs\relay\', 'docs/relay/') }
if ($hostProjectMode -eq 'parent' -and -not $cliRuntime) {
  # A bare docs\relay\... path resolves under the parent project directory and the
  # gate is not there, so the recipe has to name the repository copy in full.
  $ledgerRule = $ledgerRule.Replace('docs\relay\', $promptRepoRoot + '\docs\relay\')
}
'@

# ---- 10. chain banner as the first line of every prompt -----------------------
Patch 'chain_banner' @'
$prompt = @"
$promptHeader$stageSentence
'@ @'
$chainBanner = 'CHAIN ' + $chainId + ' | link ' + $linkTag + ' | started ' + $chainStartedAt.ToString('yyyy-MM-dd HH:mm') + ' | initiator ' + $initiatorSession + ' | host project ' + $hostProjectValue + ' (' + $hostProjectMode + ')'

$prompt = @"
$promptHeader$chainBanner
$stageSentence
'@

[IO.File]::WriteAllText($target, $script:text, (New-Object Text.UTF8Encoding($false)))
$bytes = [IO.File]::ReadAllBytes($target)
$bad = 0
foreach ($b in $bytes) { if ($b -gt 127) { $bad++ } }
$bom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
$lines = ([IO.File]::ReadAllText($target)).Split("`n").Count
Write-Host ("CHECK bytes=" + $bytes.Length + " lines=" + $lines + " non_ascii=" + $bad + " bom=" + $bom)
if ($bad -ne 0 -or $bom) { Write-Host 'CHECK_FAIL encoding'; exit 4 }
Write-Host 'PATCH_ALL_OK'
exit 0