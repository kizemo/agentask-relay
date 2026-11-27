$ErrorActionPreference = 'Continue'

# Sync the changed kit files into the Claude Code skill copy so that cc-haha
# picks up the fix. Copy only, no git write: committing and pushing stay a
# human acceptance point.
$repo = 'F:\soft\00selfmade\agentask-relay'
$skill = 'C:\Users\Duanyi\.claude\skills\relay-port'
$map = @(
  @{ src = 'tool\SKILL.md'; dst = 'SKILL.md' },
  @{ src = 'tool\templates\relay-spawn.ps1'; dst = 'templates\relay-spawn.ps1' },
  @{ src = 'tool\templates\start-relay.ps1'; dst = 'templates\start-relay.ps1' },
  @{ src = 'tool\references\claude-project-registry.md'; dst = 'references\claude-project-registry.md' }
)
foreach ($m in $map) {
  $s = Join-Path $repo $m.src
  $d = Join-Path $skill $m.dst
  if (-not (Test-Path -LiteralPath $s)) { "SKIP source_missing " + $m.src; continue }
  $dir = Split-Path -Parent $d
  if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
  Copy-Item -LiteralPath $s -Destination $d -Force
  $hs = (Get-FileHash -Algorithm SHA256 -LiteralPath $s).Hash
  $hd = (Get-FileHash -Algorithm SHA256 -LiteralPath $d).Hash
  "SYNC {0} -> {1} equal={2} bytes={3}" -f $m.src, $m.dst, ($hs -eq $hd), (Get-Item -LiteralPath $d).Length
}
