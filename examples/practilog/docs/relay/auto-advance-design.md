# 自动推进（Relay）激活与互斥设计

> 目的：把「起环权」从**项目外的监督会话**搬回**项目内** —— 用户在目标项目里打一条指令即可激活自动推进，
> 链在本仓库内自转；并用一把**原子锁 + 三道台账闸门**保证同一项目同一时刻只有一个会话在写。
> 本文件是设计说明，不是台账；台账真源仍是 `docs\relay.json`。

## 1. 为什么要改（本次问题的根因）

| 错位 | 现象 | 代价 |
|---|---|---|
| **起环权在项目外** | 靠一个 `workspace=%USERPROFILE%` 的监督会话读 `relay.json`，再 `session_create` 把本仓库拉起来 | 跨项目、跨会话；监督会话一挂链就没人看；为一个项目动另一个项目 |
| **没有原子互斥** | 「同一时刻只允许一个环」靠人记 | 两次并发起环 → 两环写同一 `relay.json` 与同一写集 → **静默丢数据**（已实测跨环读到比前一环更旧的台账版本） |
| **自愈靠外部 cron** | 排程挂在全局 cron 里，prompt 还被混入过与本链无关的产品需求 | 链的行为受外部文本影响；末环只能等人，无法自愈 |

## 2. 目标形态：三层切分

- **共享层** `%USERPROFILE%\.minimax\.minimax\maintenance\relay\`：只放**协议与模板**
  （`AGENT-RELAY.md` / `RELAY-SOP.md`）。跨项目共享，**不含任何项目状态**。
- **项目层** `<repo>\docs\`：状态机 `relay.json` + 裁决 `RELAY-ADAPTATION.md` + 阶段报告 `docs\relay\stage-N-*.md`。
- **项目层** `<repo>\docs\relay\*.ps1`：装置层 —— **启动器** 与 **互斥锁**。

铁律：**状态与执行留在项目内；外部会话不常驻、不代起链。**

## 3. 激活路径（用户在目标项目里打这一句）

```
启动接力链：目标批次 = <台账里最近一个未闭环批次>，最大阶段数 = 6，不重做已完成的事。
```

本项目会话随即按 `AGENTS.md` §A 走完四步，**全程不需要任何外部监督会话**：

1. `pwsh -NoProfile -ExecutionPolicy Bypass -File docs\relay\start-relay.ps1 -Target "<目标批次>" -MaxStages <N>`
2. 退出码 `0` ⇒ 取 `docs\relay\next-relay-prompt.txt` 全文作 `content`
3. `session_create(agent_name="me", title="relay-1-<短名>", workspace_dir="<仓库根，反斜杠绝对路径>", model=<档位>, content=<prompt 全文>)`
4. `relay-lock.ps1 -Action adopt -SessionId <新会话 id>` 转交锁

此后每一环**自己**起下一环（`AGENTS.md` §B.9）⇒ 链自转，外部零参与。

## 4. 四道防冲突闸门（回答「避免两个会话同时执行」）

| # | 闸门 | 机制 | 判据 |
|---|---|---|---|
| 1 | **原子互斥锁** | `docs\relay\.relay.lock`，用 `FileMode.CreateNew` 创建 —— NTFS 上原子，竞态失败方拿到 IOException 而非覆盖 | 第二个 `acquire` 必失败（exit 2） |
| 2 | **台账闸门** | 启动器读 `relay.json`：存在 `in_progress` 阶段 / `status=running` 且 `next_session_id` 非空 / `status=blocked` / `current_stage >= max_stages` ⇒ **拒绝起链** | exit 3，附原因与当前持有者 |
| 3 | **写集指纹** | 每环开工记 `git status --porcelain -uall` 计数 + `HEAD` + 目标文件指纹，收尾比对 | 不符 ⇒ 判写集冲突，停链（`human_checkpoints` 已含此条） |
| 4 | **CAS 回写** | 回写 `relay.json` 前必须重读盘并比对 sha256，只追加、不改写他人条目 | 竞态已实测（读到更旧版本）⇒ 重读合并是硬要求 |

配套：**心跳续租**（`renew`，TTL 1800 秒）。持锁环失联后，后继会话 `acquire` 会回收陈旧锁并留 `.stale.<epoch_ms>` 存证，不会死锁。
配套：**幂等闸门** —— `stages[]` 同一时刻只允许一条 `in_progress`，台账闸门已覆盖。

## 5. 三件套（已落盘并实测）

| 文件 | 作用 | 接口 |
|---|---|---|
| `docs\relay\relay-lock.ps1` | 跨会话互斥锁 | `acquire` / `renew` / `adopt` / `release` / `status` |
| `docs\relay\start-relay.ps1` | 激活入口：工作区校验 → 台账闸门 → 加锁 → 台账初始化（只新建不覆写）→ 生成下一环 prompt | `-Target` / `-MaxStages` / `-DryRun` / `-PlanDoc` / `-StageTitles` |
| `docs\relay\auto-advance-design.md` | 本文件 | — |

**实测证据（2026-11-25 11:10，命令与原始输出见当轮对话）**

- ASCII 纯度：两脚本 `non_ascii=0`、无 BOM（`reports\task57-ps1-ascii-scan.ps1` 的 scope 只含 `reports` 与 `tools`，本处为额外自查）。
- 锁往返：`status → LOCK_FREE`；`acquire → LOCK_ACQUIRED`；**第二个 acquire → LOCK_HELD（exit 2）**；`renew → LOCK_RENEWED`；
  **非持有者 release → LOCK_NOT_MINE（exit 5）**；持有者 release → LOCK_RELEASED`；再 `status → LOCK_FREE`。
- 启动器闸门（对本仓库真实台账）：正确识别 `status=done / current_stage=6 / max_stages=6`
  ⇒ `FAIL reason=chain_exhausted`（exit 3），未误起链。

## 6. 复制到别的项目（5 步）

1. 拷 `docs\AGENT-RELAY.md`（通用协议）+ `docs\relay\relay-lock.ps1` + `docs\relay\start-relay.ps1`。
2. 写该项目的 `docs\RELAY-ADAPTATION.md`（本项目裁决：人工验收点清单、并发检测口径、模型策略与降级档）。
3. 往该项目的 `AGENTS.md` 追加 §A（启动）/ §B（每环自律）两段（从本项目 `AGENTS.md:487` 起那段整段拷走即可）。
4. 先用 `start-relay.ps1 -DryRun` 看校验输出，再正式起链。
5. 约定阶段报告落 `docs\relay\stage-N-*.md`，台账只追加。

> 共享层的 `AGENT-RELAY.md` / `RELAY-SOP.md` 可继续放在 `maintenance\relay\`；**不要**把状态机放共享层。

## 7. 自动化不碰的边界（仍然必须人工）

`git commit / push / tag`、发布与分发、删除或覆盖用户数据、改用户级配置、付费/额度/账号/权限决定、
验收口径本身含糊或互相矛盾、写集与并发会话冲突 —— 一律 `status=blocked` 停下等人。

## 8. 三档状态

**已验证**
- 锁的五种动作与「第二个持有者被拒 / 非持有者释放被拒 / 陈旧锁可回收」的实测输出（本轮）。
- 启动器对本仓库真实台账的闸门判定（`chain_exhausted`）。
- 两脚本 ASCII 纯度与无 BOM。
- `AGENTS.md` 接力段已改写为 §A/§B 结构，且订正了失效指令（`defer_first_turn` 在 `session_create` schema 中不存在）。

**推断**
- 换到别的项目只要照 §6 五步复制即可生效（依据：启动器与锁不依赖 PractiLog 专有内容，仅读 `docs\relay.json` 与 git 仓库根）。
- 锁的 TTL 1800 秒对单环足够（实测单环 20–60 分钟量级），但若某环单轮超 30 分钟不 `renew`，会被后继会话误判为陈旧。

**未验证**
- 跨项目复制的实际落地效果（本次只在 PractiLog 内实测）。
- 项目级 hook 做「关键词自动触发」这条增强路径（本次用 AGENTS.md 规则 + 用户显式指令实现，hook 配置字段未在本机验证）。
- `start-relay.ps1` 的**台账初始化**分支（`-DryRun` 在本仓库走的是闸门拒绝分支，`ledger_absent` 分支尚未实跑）。
