RELAY ACTIVATION PACKET (relay activation packet)
=====================================
repo        : {{REPO}}
runtime     : {{RUNTIME}}
target      : {{TARGET}}
plan doc    : {{PLAN_DOC}}
max stages  : {{MAX_STAGES}}
workspace   : {{REPO}}
ledger      : {{REPO}}\docs\relay.json
launcher    : {{REPO}}\docs\relay\start-relay.ps1
lock script : {{REPO}}\docs\relay\relay-lock.ps1
spawn driver: {{REPO}}\docs\relay\relay-spawn.ps1
prompt file : {{REPO}}\docs\relay\next-relay-prompt.txt

The user only has to say this in a session whose workspace IS this repo:

    follow docs\relay\ACTIVATION-PROMPT.txt to start the relay chain

The session then executes the steps below.

--- STEP 1: run the launcher (workspace check + concurrency gate + lock + prompt) ---

pwsh -NoProfile -ExecutionPolicy Bypass -File "{{REPO}}\docs\relay\start-relay.ps1" -Target "{{TARGET}}" -PlanDoc "{{PLAN_DOC}}" -MaxStages {{MAX_STAGES}}

Exit code reading:
  0 = the chain may start, continue with STEP 2
  2 = invalid workspace, stop and report, DO NOT start a link
  3 = a chain is already running / a stage is in_progress / the ledger is blocked or exhausted, stop and report, DO NOT start a link
  4 = the lock is held by another session, stop and report, DO NOT start a link

{{SPAWN_STEPS}}

If STEP 1 or STEP 2 fails: run
pwsh -NoProfile -ExecutionPolicy Bypass -File "{{REPO}}\docs\relay\relay-lock.ps1" -Action release
then report honestly. DO NOT retry starting a link.
