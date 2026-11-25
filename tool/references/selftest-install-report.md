# Relay kit install report

- installed_at: 2026-11-25 11:33:07
- tool: relay-port skill (E:\Users\Duanyi\.minimax\.minimax\skills\relay-port)
- repo: F:\soft\00selfmade\_relay-port-selftest
- target: selftest batch
- plan_doc: docs\plan-relay.md
- max_stages: 6
- agents_block: present_kept
- agents_before: bytes=3558 sha16=F482063537A97B5B
- agents_after: bytes=3558 sha16=F482063537A97B5B
- verdict: PASS

## Console log

```
REPO root=F:\soft\00selfmade\_relay-port-selftest
REPO name=_relay-port-selftest
REPO head=189b235
PLAN doc=docs\plan-relay.md created=False
SKIP relay-lock.ps1 identical bytes=6441
SKIP start-relay.ps1 identical bytes=9352
SKIP AGENT-RELAY.md identical bytes=8564
SKIP RELAY-SOP.md identical bytes=7129
SKIP RELAY-ADAPTATION.md exists kept (project edited it; fill the TODO sections in place)
AGENTS action=present_kept before=[bytes=3558 sha16=F482063537A97B5B] after=[bytes=3558 sha16=F482063537A97B5B] bom=False
WRITE ACTIVATION-PROMPT.txt bytes=2585
LEDGER absent (the launcher creates it at activation; the installer never writes it)
ASCII_CHECK file=relay-lock.ps1 non_ascii=0 bom=False bytes=6441
ASCII_CHECK file=start-relay.ps1 non_ascii=0 bom=False bytes=9352
AGENTS_MARKERS begin=1 end=1
LOCK_STATUS exit=0 line=LOCK_FREE path=F:\soft\00selfmade\_relay-port-selftest\docs\relay\.relay.lock
DRYRUN exit=0 verdict=OK artifact=F:\soft\00selfmade\_relay-port-selftest\docs\relay\install-dryrun.txt
```

## Next step

Open a session whose workspace IS this repo and say:

    按 docs\relay\ACTIVATION-PROMPT.txt 启动接力链

Before that, fill the TODO sections of docs\RELAY-ADAPTATION.md (write set, gate, model policy).
