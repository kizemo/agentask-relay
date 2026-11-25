# AGENTS.md —— agentask-relay

本项目是「无人值守接力装置（relay-port）」的工程目录：工具真源 + 装置 + 协议 + 真实链路样例。
**目标**：把「照搬到别的项目需要做的事」做成任何会话调用一次即装完的工具，并持续完善它。

## 先读这三份

1. `README.md` —— 目录地图 + 工具一句话用法 + 与全局 skill 的关系
2. `HANDOFF.md` —— 交接：已验证 / 推断 / 未验证 / 证据路径 / 后续候选 / 工具坑
3. `tool\SKILL.md` —— 工具说明书（装什么、怎么装、怎么起链、四道闸门、边界）

## 工作规则

1. 改 `tool\`（或 `device\`）下的东西 = 改工具本体。改完**必须**重跑一键自测 `pwsh -NoProfile -File scripts\selftest.ps1 -EvidencePath <log>`（在系统临时目录建一次性 git 仓库，真跑安装器/启动器/锁；含安装、幂等重跑、收编双判据、`-PlanDoc` 解析、真激活起链、二次起链被拒、锁互斥），**要求 EXIT=0 且 fail=0**，再更新 `tool\references\selftest-*.md`（raw 日志与 `next-prompt.md` 留证一起收）。
2. **发布口径**：工具本体同时是全局 skill `E:\Users\Duanyi\.minimax\.minimax\skills\relay-port\`。本目录改完自测通过后要**同步回全局目录**才算生效，否则新会话拿到的还是旧版。要同步四处：`SKILL.md` / `scripts\` / `templates\` / `references\`。一键化：`pwsh -NoProfile -File scripts\publish-relay.ps1 -Direction publish`（同步 + 逐件复核一次做完，非零退出 = 仍有漂移）；只查不改用 `-Direction verify`。
3. 装置本体（`device\start-relay.ps1`、`device\relay-lock.ps1`、`device\relay-ledger.ps1`）与 `tool\templates\` 里的同名件必须**逐字一致**；改一处同步另一处（改完 `Copy-Item tool\templates\<f> device\<f> -Force`）。这是**硬不变式**，`publish-relay.ps1` 漂移即以 exit 2 失败；`examples\practilog\docs\relay\` 是历史留证快照，只报 `SNAPSHOT_DRIFT`、不参与判定、**不要为它同步**（家规 8）。台账回写**只许走 `relay-ledger.ps1`**（锁 + CAS + 只追加不变式 + 写后回读），不要在文档或 prompt 里教裸 `Set-Content`。
4. `.ps1` 一律**纯 ASCII、无 BOM**；仓库 Markdown 与 `tool\references\` 留证 `.txt` 一律 LF（CRLF=0）——门禁 `refresh-manifest.ps1` 的 `MD_TXT_CR_TOTAL` 同时统计 `.md` 与 `.txt`，**该数必须为 0**。
5. 中间产物写文件，对话只留指针 + 结论；不伪造验收证据。
6. 结论写进本仓库；**严禁读跨项目交接卡** `maintenance\task-state\LATEST.md`（那是别的项目的）。
7. 门禁脚本的阈值与白名单属**人工验收点**，不自行改。
8. 中间产物不要写进 `examples\`（那是留证快照，保持原样）。

## 自动接力（Relay）—— 硬规则

本项目尚未安装 relay kit。**装好之后**，本节会被 relay-port 安装器**收编**（加 `<!-- BEGIN RELAY-PORT -->` 标记、保留原文），不要另起一份重复家规。

链的语义（与 `tool\SKILL.md` 一致）：起环权在**目标项目内**、由用户指令激活；启动器负责工作区校验 / 并发闸门 / 取锁 / 台账初始化（只新建不覆写）/ 生成接力 prompt；`session_create` 只传 `agent_name` / `title` / `workspace_dir`（**反斜杠绝对路径**）/ `model` / `content`，**禁止**传 `effort` / `defer_first_turn` / `parent_session_id`；每环回写 `docs\relay.json` 前必须**重读盘**、只定点追加。计划文档由启动器按 `-PlanDoc` > 台账 `plan_doc` > 探测 `docs\plan-*.md` / `docs\plans\*.md` / `docs\superpowers\plans\*.md` 解析（唯一取之；多个 WARN 后按 mtime 取最新；零个 `exit 2`），**绝不为起链创建计划文档**。
