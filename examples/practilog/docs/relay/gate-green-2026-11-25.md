# 门禁复绿与自动推进装置落盘记录（2026-11-25）

本文件是接力链（`docs\relay.json`）在 `status=done` 之后的两项补记：**门禁绿线的一手证据** 与 **自动推进装置的落地状态**。
只登记实测值，不改写历史结论；与 `docs\relay\stage-6-report.md` 第十三章并列阅读（该章记的是 00:04:17 那轮的 `PASS` + `68.4g` 终判 `FAIL`）。

---

## 一、门禁绿线（2026-11-25 11:19:58 起跑 → 11:21:40 落盘，一手实测）

命令（绝对路径，脚本零改动）：

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File 'F:\soft\00selfmade\practilog\reports\task51-gate.ps1' -ExpectDesktopTests 882
```

| 判据 | 值 | 说明 |
|---|---|---|
| `GATE_VERDICT` | **PASS** | |
| `GATE_FAILURES` | **0** | 无 FAIL_ITEM |
| `DESKTOP_TESTS` / `DESKTOP_EXPECTED` | **882 / 882** | 相等 ⇒ 计数硬判据满足 |
| `DESKTOP_BASELINE` / `DESKTOP_DELTA` | 596 / 286 | `:38` 的 `$baseline` 仍是历史常量，未改 |
| `CORE_DATA_TESTS` / `CORE_DB_TESTS` / `CORE_DOMAIN_TESTS` | 204 / 96 / 91 | 三包与脚本内建期望值相等 |
| 四包 `ANALYZE` | 全 `VERBATIM` | 逐字 `No issues found!` |
| `VIOLATIONS` / `OUT_OF_SET` | 0 / 0 | `packages/**` 未越界；写集边界零越界 |
| `GATE_EXCLUDED` | 4 | `docs/relay/*`、`docs/relay.json`、`docs/AGENT-RELAY.md`、`docs/RELAY-ADAPTATION.md` |
| `PS1_ASCII_VIOLATIONS` | 0 | `PS1_SCANNED=493` / `PS1_NEW_NON_ASCII=0` |
| `STATUS_LINES` / `HEAD` / `AHEAD` / `GIT_EXIT` | 57 / `9ef1c9e` / 4 / 0 | 计数带 `--untracked-files=all` |

证据：

- `reports\task51-gate\summary.txt` — 3749 B / sha16 `EC9029E8BCDD5E25` / `RUN_AT=2026-11-25 11:21:40`
- `reports\gate-rerun-2026-11-25.log` — 本轮控制台全文

### 前置条件（本轮实测，可复用）

1. **必须等并发会话的 `flutter test` 退出**再启动门禁。本轮并发会话的 `dart` / `dartaotruntime` 进程 11:18:16 起、11:18:58 退；`reports\task51-gate.ps1:22` 的 `Move-Item apps\desktop\build\test_cache\build` 在被占用时会抛 `file is being used by another process` ⇒ 脚本 exit 1 且**不产出新摘要**（旧摘要三项指纹逐字不变 ⇒ 可据此判「本轮没跑起来」）。
2. 失败轮次留证（不删除、不覆盖）：11:15:51 那轮 `GATE_VERDICT=FAIL` / `FAIL_ITEM=desktop.test:COUNT=882 EXPECT=836`（真实用例数已涨到 882，带的期望值仍是旧数），摘要 3794 B / sha16 `CDB789757B89152F`；其后 11:1x 那轮崩在 `:22`，摘要指纹与 11:15:51 完全相同 ⇒ 该轮**未产出新结果**。
3. 判绿必须带当轮真实用例数 `-ExpectDesktopTests 882`（口径同 `AGENTS.md:57`）；**不得**改 `:38` 的 `$baseline=596`（改门禁属人工验收点）。
4. 本机坑已登记进 `AGENTS.md` §5 第 **94** 条（搬缓存崩溃/等窗口）与第 **95** 条（只认 `summary.txt` 的 `GATE_VERDICT`，不认管道末端 `$LASTEXITCODE`；`git status` 核数必须带 `-uall`）。

---

## 二、待提交面现状（2026-11-25 11:2x，`git status --porcelain --untracked-files=all`）

总数 **60 行**（`git status --porcelain --untracked-files=all`，2026-11-25 11:3x 复核；本文件与台账回写各占 3 行），归属二分：

### 2.1 接力链自身写集（7 件：家规 + 台账 + 报告 + 三件装置）

| 文件 | 说明 |
|---|---|
| `AGENTS.md` | 接力硬规则改写为 §A 启动 / §B 每环自律；§5 追加坑 94–95 |
| `docs/relay.json` | 台账追加 `post_closure_2026_11_25`（门禁绿线 + 装置状态 + 待人工裁决），不改 status / stages |
| `docs/relay/stage-6-report.md` | 追加第十四章「复绿补记」 |
| `docs/relay/gate-green-2026-11-25.md` | 本文件（新增） |
| `docs/relay/relay-lock.ps1` | 互斥锁（acquire / renew / adopt / release / status） |
| `docs/relay/start-relay.ps1` | 项目内启动器（闸门 → 加锁 → 台账初始化 → 生成下一环 prompt） |
| `docs/relay/auto-advance-design.md` | 设计说明（三层切分 / 激活路径 / 四道并发闸门 / 跨项目复制五步） |

### 2.2 并发会话写集（53 件，**不属于本链**）

Task 64/65/66 的 goals 功能（`apps/desktop/lib/src/pages/goals_*.dart`、`data/goal_store.dart`、`l10n/parts/goals.dart`、`widgets/goal_*.dart`、`providers.dart`、`app.dart`、`nav_rail.dart`、`key_bar.dart`、测试 `task64_*`/`task65_*`/`task66_*`/`task69_*`/`goal_test.dart`）、Task 68/69 的 l10n 收口（`l10n_keys.dart`、`l10n/parts/{projects,shell}.dart`、`app_localizations.dart`、`project_store.dart`、`projects_page.dart`、`test/l10n_base_test.dart`、`test/l10n_harness.dart`、`test/shell_*`、`test/nav_*`、`test/task61_*`）、`packages/core_db/**`（schema v3 goal 表 + migration + oplog）、`packages/core_domain/lib/src/goal.dart`、`packages/core_data/lib/src/recurring.dart`、计划文档与 `docs/task62/模块规划.md`。

**处置原则**：这 53 件**不由本链提交**（属并发会话的在制品，且其中 `projects_page.dart` 等文件正被并发会话编辑）。本链若要改同一批文件，必须先做并发检测并停链等人。

### 2.3 `68.4h` 的现状

`68.4h`（git commit / push）**已于 2026-11-25 08:04 按用户授权「只提交，不推送」落地**，提交序列：

| 顺序 | 短 hash | 主题 |
|---|---|---|
| 1 | `c1a4bf7` | `chore(w9): W9 l10n 收口——27 条新键落地与落库值显示层映射`（21 files / +3833 / −64） |
| 2 | `ebb8996` | `docs(relay): 追加接力链监护日志（2026-11-24 / 2026-11-25）` |
| 3 | `efa3f65` | `docs(relay): 台账收口 —— 68.4h 已按授权提交（只提交不推送）` |
| 4 | `9ef1c9e` | `docs(relay): 订正 68.4h 提交序列登记（补台账收口 commit efa3f65）` |

`push` 0 次 / `tag` 0 次；`AHEAD=4` 至今**全部提交仅存本地**。本文件与装置 4 件属新增载荷，**未获新授权 ⇒ 不自行提交**。

---

## 三、自动推进装置落地状态（用户两问的落地形态）

### 3.1 回答「如何在项目内用一条指令激活自动推进」

三件套全在**项目内**（`docs\relay\`），外部会话 / cron 只看链、不再代起链：

1. `relay-lock.ps1` — 互斥锁。`FileMode.CreateNew` 原子创建 ⇒ 第二个 `acquire` 必失败（实测 `LOCK_HELD` / exit 2）；TTL 1800 s；陈旧锁回收改名为 `.stale.<epoch_ms>` 不删。
2. `start-relay.ps1` — 启动器。工作区校验 → 台账闸门 → 加锁 → 台账初始化（只新建不覆写）→ 生成 `next-relay-prompt.txt`。退出码：`0`=可起环 / `2`=工作区非法 / `3`=闸门拒绝 / `4`=锁不可得；支持 `-DryRun`。
3. `auto-advance-design.md` — 设计说明，含**跨项目复制五步**。

台账 `docs\relay.json` 保持 `status=done` / `current_stage=6` / `max_stages=6` ⇒ 启动器对本仓真实台账判定 `FAIL reason=chain_exhausted` / exit 3，**不会误起链**（实测）。

### 3.2 回答「如何避免同一项目同时两个会话执行」

四道闸门（设计见 `auto-advance-design.md`）：

1. **原子锁**：`FileMode.CreateNew` —— 第二个获取者必然失败（实测 `acquire → LOCK_ACQUIRED`；第二次 → `LOCK_HELD` exit 2）。
2. **台账闸门**：存在 `in_progress` / `status=running` 且 `next_session_id` 非空 / `blocked` / 阶段耗尽 ⇒ 拒绝起链。
3. **写集指纹**：开工记 `porcelain -uall` 计数 + HEAD + 目标文件指纹，收尾比对。
4. **台账回写 CAS**：重读盘比对 sha256，只定点追加，不整文件覆写。

链内纪律已写进 `AGENTS.md` §B：每环开工 `acquire`、在途 `renew` 心跳、命中人工点写 `blocked` 并 `release` 锁、收尾回写台账。

### 3.3 本机实测轨迹（2026-11-25 11:10）

`status → LOCK_FREE` → `acquire → LOCK_ACQUIRED` → 第二个 `acquire → LOCK_HELD`（exit 2）→ `renew → LOCK_RENEWED` → 非持有者 `release → LOCK_NOT_MINE`（exit 5）→ 持有者 `release → LOCK_RELEASED` → 再 `status → LOCK_FREE`；两脚本纯 ASCII、无 BOM。

---

## 四、仍待人工裁决（本文件不代做）

1. **推送**：`AHEAD=4` 的 4 个提交是否 push（上一轮授权只到「提交」，明确不推）。
2. **本链 4 件新载荷是否提交**（`AGENTS.md` + `docs/relay/` 三件）。
3. **`68.4g` 的 5 条一手发现是否派 worker 处置**：其中 3 条需改 `apps/**`（`projects_page.dart:298-313` 的 `_messageOf` 在 `ArgumentError` 分支原样上屏中文、`tool_rail.dart:304` 硬编码全角 `＋`、En mixin 泄漏 `dialog.dart:1048`/`:1174` 与 `settings.dart:239`），与并发会话写集重叠 ⇒ 须先做并发检测。
4. **门禁脚本白名单口径**：`reports\task51-gate.ps1:302-305` 把 4 条 `docs/**` 项写进 `$patterns` ⇒ `GATE_EXCLUDED` 由 2 降为 0，与计划 §68.5 第 5 条「排除项不得塞进 `$patterns`」相悖；改门禁属人工验收点，**未动**。
5. **是否把这套装置复制到其它项目**（五步法见 `auto-advance-design.md` §6）。
