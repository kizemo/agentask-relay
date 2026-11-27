<!-- SPAWN_RULE_BEGIN -->
Start the next link with the built-in `session_create` tool: pass only `agent_name` / `title` / `project` (the exact backslash absolute path from `relay.json.host_project`, and it must appear verbatim in `project_list`) / `model` / `content`; never pass `workspace_dir` (the host keys projects by that exact directory and inserts a new row when it does not match) / `effort` / `defer_first_turn` / `parent_session_id`.
<!-- SPAWN_RULE_END -->

--- STEP 2: start the first link session (runtime = mcode) ---

Read {{REPO}}\docs\relay\next-relay-prompt.txt in full, then:

mcp_invoke(tool_name="session_create", arguments={
  agent_name   : "me",
  title        : "relay-01of<MM>-<short stage name> [<chain_tag>]",
  project      : "<the value the launcher printed as OK host_project_value value=...>",
  model        : "<model policy in section 5 of docs\RELAY-ADAPTATION.md>",
  content      : "<full text of next-relay-prompt.txt>"
})

Never pass `effort` / `defer_first_turn` / `parent_session_id` (the schema has no such fields).
Never pass `workspace_dir` either: `project` and `workspace_dir` are mutually exclusive, and
`workspace_dir` files the session under a project keyed by that exact directory -- which is
how a chain ends up adding a project row of its own. In the default exact mode the value above
is `{{REPO}}`; when the launcher reports `mode=parent` it is the parent directory instead, and
the prompt already forces absolute paths. If that value is not verbatim in `project_list`,
write `blocked` instead of starting the link; never fall back to `workspace_dir`.
`chain_tag` is what the launcher printed as `OK chain_tag=...`: it goes into the title so two
chains stay distinguishable in the sidebar and the newest link is identifiable.

--- STEP 3: hand the lock over to the new session ---

pwsh -NoProfile -ExecutionPolicy Bypass -File "{{REPO}}\docs\relay\relay-lock.ps1" -Action verify -SessionId <new session id> -Nonce <the nonce printed by SPAWN_PERMIT>

--- STEP 4: read the session back and verify ---

mavis session get {"session_id":"<new id>"} -- check `project_id` / `workspace_dir` / `effective_model` / `status`;
`project_id` must be the project whose key you passed, and `workspace_dir` must not be a private
`sessions\<sid>\workspace` directory.

## PRE-SPAWN GATE

Before `session_create`, run:

```
pwsh -NoProfile -File docs\relay\relay-lock.ps1 -Action prespawn -Stage <stage number>
```

It refuses (exit 3 or 5) when the chain is stopped, when the lock belongs to
another link, when jobs registered against this link are still alive, or when an
unconsumed permit is younger than its TTL. A refusal means: do not spawn.
Only a `SPAWN_PERMIT` line authorises a spawn, and the permit is consumed exactly
once by the `-Action verify` call above.
