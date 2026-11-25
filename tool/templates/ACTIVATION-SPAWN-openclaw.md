<!-- SPAWN_RULE_BEGIN -->
OpenClaw has no `session_create` tool: start the next link with the `sessions_spawn` tool inside the same workspace (repo root), then run `docs\relay\relay-lock.ps1 -Action adopt -SessionId <new id>`.
<!-- SPAWN_RULE_END -->

--- STEP 2: start the first link (runtime = openclaw) ---

OpenClaw has no session_create tool. It spawns a child session with its own
`sessions_spawn` tool, inside the workspace that is already configured for this repo.

Read {{REPO}}\docs\relay\next-relay-prompt.txt in full, then spawn one session with:

  tool      : sessions_spawn
  workspace : {{REPO}}
  prompt    : <full text of next-relay-prompt.txt>
  task      : relay-1-<short stage name>

The spawn tool returns the new session id. Keep it.

Note: OpenClaw injects the workspace bootstrap files (AGENTS.md among them) into the
system prompt of every new session, so the managed block in this repo's AGENTS.md is what
the child link reads. If the OpenClaw workspace is NOT this repo, copy the managed block
into the workspace root AGENTS.md first.

--- STEP 3: hand the lock over to the new session ---

pwsh -NoProfile -ExecutionPolicy Bypass -File "{{REPO}}\docs\relay\relay-lock.ps1" -Action adopt -SessionId <new session id>

--- STEP 4: read the session back and verify ---

Read the spawned session back with the OpenClaw session reader and check that its
workspace is {{REPO}} and that it is running. Then check the lock:

pwsh -NoProfile -ExecutionPolicy Bypass -File "{{REPO}}\docs\relay\relay-lock.ps1" -Action status
