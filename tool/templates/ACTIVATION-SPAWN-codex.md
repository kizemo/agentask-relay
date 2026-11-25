<!-- SPAWN_RULE_BEGIN -->
Codex CLI has no `session_create` tool: start the next link with `docs\relay\relay-spawn.ps1 -Runtime codex -PromptFile docs\relay\next-relay-prompt.txt -WorkspaceDir <repo root> -Execute -AdoptLock` (the next link is a headless `codex exec` process).
<!-- SPAWN_RULE_END -->

<!-- SPAWN_COMMAND_BEGIN -->
pwsh -NoProfile -ExecutionPolicy Bypass -File {{REPO}}\docs\relay\relay-spawn.ps1 -Runtime codex -PromptFile {{REPO}}\docs\relay\next-relay-prompt.txt -WorkspaceDir {{REPO}} -Execute -AdoptLock
<!-- SPAWN_COMMAND_END -->

--- STEP 2: start the first link (runtime = codex) ---

Codex CLI has no session_create tool, so the next link is a headless `codex exec` process.
The launcher already wrote the prompt to {{REPO}}\docs\relay\next-relay-prompt.txt.

Dry run first (prints the exact command, runs nothing): run the command below without
`-Execute -AdoptLock`.

Then run it for real:

{{SPAWN_COMMAND}}

The line `RELAY_SPAWN_OK runtime=codex session_id=<id>` is the success marker.
The link runs to completion as a child process; it advances the chain itself by running
the same command again (see the house-rules block, section A.5).

--- STEP 3: hand the lock over to the new session ---

Already done by `-AdoptLock`. Without that flag, run it by hand:

pwsh -NoProfile -ExecutionPolicy Bypass -File "{{REPO}}\docs\relay\relay-lock.ps1" -Action adopt -SessionId <session id>

--- STEP 4: read the run back and verify ---

The spawn driver prints `RELAY_SPAWN_OK runtime=codex session_id=<id>`.
Check the id is non-empty and that the lock file now names that id:

pwsh -NoProfile -ExecutionPolicy Bypass -File "{{REPO}}\docs\relay\relay-lock.ps1" -Action status
