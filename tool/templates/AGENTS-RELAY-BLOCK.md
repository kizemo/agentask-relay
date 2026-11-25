<!-- BEGIN RELAY-PORT -->
## 自动接力（Relay）—— 硬规则

本项目（{{REPO_NAME}}）启用会话自动接力。状态机：`docs\relay.json`；通用协议：`docs\AGENT-RELAY.md`；本项目裁决：`docs\RELAY-ADAPTATION.md`（优先级高于通用协议，低于本文件其余家规）；装置：`docs\relay\start-relay.ps1`（启动器）+ `docs\relay\relay-lock.ps1`（互斥锁）+ `docs\relay\relay-spawn.ps1`（起环驱动，仅 CLI 运行时用）。

### A. 启动：只在本项目内、由用户指令激活

1. **激活触发**：仅当用户在**本项目会话**内明确下达「启动接力链 / 继续接力 / 自动推进」指令时才可起链。**禁止**由项目外的监督会话代起本仓库的链，也**禁止**为别的项目起链时把本仓库顺带拉进来（跨项目起链会落进私有 workspace，读不到仓库）。
2. **起链必须走启动器**，不得手写 `session_create`：`pwsh -NoProfile -ExecutionPolicy Bypass -File "<仓库根>\docs\relay\start-relay.ps1" -Target "<目标批次>" -PlanDoc "<仓库相对路径的计划文档>" -MaxStages <N>`。启动器负责工作区校验、并发闸门、锁获取、台账初始化（只新建不覆写）、生成 `docs\relay\next-relay-prompt.txt`。
3. **启动器退出码**：`0` 可起链（`content` = `docs\relay\next-relay-prompt.txt` 全文）；`2` 工作区非法；`3` 已有链在跑 / 存在 `in_progress` 阶段 / 台账耗尽或 blocked（**不得起环**，如实汇报）；`4` 锁拿不到（**不得起环**，另一会话正在跑）。
4. **起环后转交锁**：拿到 `session_id` 立刻 `docs\relay\relay-lock.ps1 -Action adopt -SessionId <id>`；起环失败则 `-Action release`，不留死锁。
5. **起环方式**：运行时 = `{{RUNTIME}}`。{{SPAWN_RULE}} 起环参数、禁止字段与失败回滚一律以 `docs\relay\ACTIVATION-PROMPT.txt` 为准。

### B. 每环自律

6. 开工第一步读 `docs\relay.json`。`status != "running"` ⇒ 不接力，正常收尾。
7. 本环身份 = `current_stage`；只允许写该阶段声明的写集，且必须先过 `docs\RELAY-ADAPTATION.md` 的并发检测。
8. 锁的持有者每几轮跑一次 `docs\relay\relay-lock.ps1 -Action renew` 续心跳（TTL 默认 1800 秒）；超时未续视为环已死，后继会话 `acquire` 会回收并留 `.stale.*` 存证。
9. `status == "running"` 且本环 acceptance 达成 ⇒ **回复用户之前**必须：先只追加方式回写 `relay.json`（本环 `status/session_id/model/tool_calls/finished_at` + `current_stage += 1` + `stages` 追加下一环），**回写前必须重读盘**，回读核对条数与署名；再按 §A.5 的起环方式起下一环（模型策略见 `docs\RELAY-ADAPTATION.md` 第 5 节），把返回的 `session_id` 回写 `next_session_id`；再 `relay-lock.ps1 -Action adopt -SessionId <新 id>` 转交锁。
10. 命中人工验收点 / 停链条件 / 写集冲突 ⇒ 写 `status="blocked"` + `note`，**不起新会话**，停下等人，并 `relay-lock.ps1 -Action release` 释放锁。
11. `current_stage > max_stages` ⇒ 写 `status="blocked"` 停链。不得自行加长 `max_stages`。
12. `docs\relay.json` 的 `status` 改成 `running` 只有人能做。**agent 不得自行起链** —— 唯一例外是满足 §A 全部条件（用户在本项目内明确指令 + 启动器放行 + 拿到锁）。
<!-- END RELAY-PORT -->
