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

--- STEP 0: goal confirmation round (B33) - BEFORE the launcher ---

Read the goal sources first: the target line above and the plan doc "{{PLAN_DOC}}".
Goal CLEAR (verifiable acceptance criteria, one unambiguous reading, no contradiction
with the plan doc or repo rules, all key inputs present) => skip to STEP 1.

Goal UNCLEAR => run exactly one confirmation round with the user (ask_user): batch
every goal question into that single round. Do not re-ask the adaptation rulings
(write set / gate / model - those belong to the installer answers file).

After the user confirms:
1. Append a new section titled "目标确认（B33）" to the plan doc. Append only:
   timestamp + the user's ruling verbatim + the confirmed goal sentence. Never rewrite
   or delete existing plan content. This append is the only authorized plan-content
   write and must rest on the user's explicit answer.
2. Use the confirmed goal sentence as -Target in STEP 1.

Still unclear after that one round, or the user declines / does not answer:
DO NOT run the launcher. Report what remains unclear and stop.
No plan doc can be resolved: DO NOT create one (only the installer may); stop and
ask the user for -PlanDoc.

Chain links never ask questions and never edit plan content; new ambiguity found
mid-chain still writes blocked (protocol section 6).

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
