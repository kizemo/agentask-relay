<!-- SPAWN_RULE_BEGIN -->
Start the next link with the built-in `session_create` tool: pass only `agent_name` / `title` / `workspace_dir` (backslash absolute path) / `model` / `content`; never pass `effort` / `defer_first_turn` / `parent_session_id`.
<!-- SPAWN_RULE_END -->

--- STEP 2: start the first link session (runtime = mcode) ---

Read {{REPO}}\docs\relay\next-relay-prompt.txt in full, then:

mcp_invoke(tool_name="session_create", arguments={
  agent_name   : "me",
  title        : "relay-01of<MM>-<short stage name>",
  workspace_dir: "{{REPO}}",
  model        : "<model policy in section 5 of docs\RELAY-ADAPTATION.md>",
  content      : "<full text of next-relay-prompt.txt>"
})

Never pass `effort` / `defer_first_turn` / `parent_session_id` (the schema has no such fields).
`workspace_dir` must be the backslash absolute path above; a forward slash silently lands
in a private workspace, which means the link never sees the repo.

--- STEP 3: hand the lock over to the new session ---

pwsh -NoProfile -ExecutionPolicy Bypass -File "{{REPO}}\docs\relay\relay-lock.ps1" -Action adopt -SessionId <new session id>

--- STEP 4: read the session back and verify ---

mavis session get {"session_id":"<new id>"} -- check `workspace_dir` / `effective_model` / `status`.
