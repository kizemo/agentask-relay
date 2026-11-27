---

## B25 · 前台已停止却还能起新会话：起环闸门前移到锁 + 工具改名（2026-11-27）

**用户指令（原话）**：「当一个会话前台已经显示停止，但还有后台任务执行，但撰写了Prompt时，是否会启动新会话接力任务。这种情况有可能会造成冲突，必须禁止。」「工具名称修改为 agentask-relay，同步修改cc-haha中，和Minimax中部署的工具」「检查是否存在其它bug」。

**对原问题的直接回答**：会。B24 及以前起环只看台账闸门（`in_progress` / `running+next_session_id` / `blocked` / 阶段耗尽）与链锁 `holder`；「前台点停止」在宿主侧不产生任何可读信号，链锁 holder 仍是那个会话，所以只要台账被改成可再起，已停的会话照样能 `session_create` 出下一环。本轮把「谁能 spawn」换成机械前置条件，见下。

**改动（模板与 device 逐字一致）**

1. `relay-lock.ps1` 新增 7 个动作，既有输出串与退出码语义一律不动：
   - `prespawn`：拒 `.stop`（`chain_stopped`）、拒锁缺失（`lock_missing`）、拒非 holder（`lock_not_mine` exit 5）、拒本人仍存活的后台作业（`background_jobs_live` exit 5）、拒未消费未过期 permit（`permit_outstanding` exit 3）；通过则签发 `docs\relay\.spawn-permit.json`（nonce/owner/stage/issued_at/expires_at=+300s）并打印 `SPAWN_PERMIT ...`。
   - `verify`：校验并**一次性消费** permit，同时把锁归属轮转到新会话（`SPAWN_VERIFIED ... driver_adopted=<id>`）；无 permit 时走 bootstrap 分支。
   - `stop-mark` / `stop-clear`：停止哨兵 `docs\relay\.stop`。
   - `job-register` / `job-clear`：后台作业登记 `docs\relay\.jobs.json`，按 PID 判活。
   - `gate-status`：一行 `GATE holder=.. stop=.. permit=.. jobs_live=N pids=.. lock=..`。
2. 交接权放在**前驱侧**：前驱 `prespawn` 拿 nonce → `session_create` → `verify -SessionId <新 id> -Nonce <n>` 一步完成「消费 permit + 锁归属轮转」。原因是 mcode 会话读不到自己的 session id，只有前驱能从 `session_create` 返回值拿到新 id；后驱首动作改为 `gate-status`。
3. `prespawn` 的 `-SessionId` 改为可选，省略时取锁记录 holder（解除「会话不知道自己 id」的死结）。
4. `start-relay.ps1`：`$stageSentence` 增 `You are relay stage <n>`；`$completionRule` 要求先 `prespawn` 后 `verify -Nonce`，明令 *Never adopt the lock without a permit*；`$stopRule` 增 `stop-mark -Note <why>`；新增 `$spawnGateRule`（仅 mcode 分支非空）；两处 `$nextHint2` 改为带 `-Nonce` 的 verify。`ACTIVATION-SPAWN-mcode.md` 同步并新增 PRE-SPAWN GATE 段。
5. `scripts\selftest.ps1`：新增 case b25（15 条断言）+ 防回归 `lock_param_not_shadowing_PID`。
6. 改名 `relay-port` → `agentask-relay`，现役 10 个文件：`AGENTS.md`、`README.md`、`README.zh-CN.md`、`device\relay-lock.ps1`、`scripts\publish-relay.ps1`、`scripts\selftest.ps1`、`tool\SKILL.md`、`tool\scripts\install-relay.ps1`、`tool\templates\ADAPTATION-QUESTIONS.json`、`tool\templates\RELAY-ADAPTATION.md`。**冻结契约保持原字面**：`<!-- BEGIN/END RELAY-PORT -->`、`relay-port/adaptation-answers@1`、`$env:RELAY_PORT_SKILL_ROOT`——三处是兼容遗留名，不要再当改名残留清掉（`-match` 大小写不敏感会误报）。
7. 三处已部署技能目录改名：`C:\Users\Duanyi\.claude\skills\agentask-relay`、`E:\Users\Duanyi\.claude\skills\agentask-relay`（原名目录已不存在、新名目录原已存在）、`E:\Users\Duanyi\.minimax\.minimax\skills\agentask-relay`。

**本轮新查出的 bug（全部已修，均可复现）**

- **B25-1 `$Pid` 影子参数（严重，装置级不可用）**：`relay-lock.ps1` 的 `param([int]$Pid = 0)` 与只读自动变量 `$PID` 冲突，**任何**调用在参数绑定阶段即崩（`无法覆盖变量 Pid，因为它是只读变量或常量`）。连带后果：`install-relay.ps1:795` 的 `-Action status` 崩 ⇒ `install-dryrun.txt` 从未写出 ⇒ 自测 case 1 抛未捕获异常。修复：参数改名 `-ProcId`（JSON 字段仍为 `pid`、输出串 `pid=` 保持不变），8 处引用同改。
- **B25-2 断言消息提前求值**：`scripts\selftest.ps1:118` 的 `Check` 第三参数无条件求值，`-and` 的短路保护不到它；产物缺失时抛 `ReadAllText` 异常，把「断言失败」升级为「整轮中断」。修复：先取 `$dry1`（缺失为 `<missing>`）再断言。
- **B25-3 全新仓库无 HEAD**：`install-relay.ps1:408` 对 `git rev-parse --short HEAD` 的空结果调 `.Trim()` ⇒ 零提交仓库安装即崩。修复：空值回落 `none`（探针实测 `REPO head=none`）。**未修完**：同类空值解引用还在启动器 `-DryRun` 内（探针 `EXIT=1`，`start-relay.ps1` 抛「不能对值为 Null 的表达式调用方法」），本轮不追。

### 本批门禁数字（实数，盘上回读）

- `SUITE_END pass=368 fail=0 root=C:\Users\Duanyi\AppData\Local\Temp\agentask-relay-selftest\20261127-192554` (进程退出码 `0`)
- raw：`tool\references\selftest-2026-11-27-b25.txt`（35142 B / 389 行 / CR=0 / BOM=no / SHA256 `F98CA83C073B4356487304F8F615433B366008B045B6A3375697D623B302876F`）
- `case b25`：15 条新断言 + 1 条防回归 `lock_param_not_shadowing_PID`，全绿
- `publish-relay.ps1 -Direction publish|verify` 与 `refresh-manifest.ps1` 的数字见本轮回答，不在本节抄写（避免 stale）

**已验证**

- 全量自测 `SUITE_END pass=368 fail=0 root=C:\Users\Duanyi\AppData\Local\Temp\agentask-relay-selftest\20261127-192554`，进程退出码 `0`。
- `case b25` 15 条 + 防回归 1 条全绿，六条拒绝路径均有实测输出串：`background_jobs_live`(exit 5)、`chain_stopped`(exit 3)、`lock_not_mine`(exit 5)、`permit_outstanding`(exit 3)、`permit_consumed`(exit 3)、`nonce_mismatch`(exit 3)。
- `prespawn` 签发 → `verify` 消费 → 锁归属轮转，`SPAWN_VERIFIED ok nonce=.. from=sess-a to=sess-b` 与二次消费被拒（`reason=permit_consumed consumed_by=sess-b`）双向实测。
- `gate-status` 一行实测：`GATE holder=sess-b stop=no permit=outstanding jobs_live=0`。
- `job-register` 实测 `JOB_REGISTERED pid=167548 owner=sess-b total=1` ⇒ 参数改名 `-ProcId` 后 JSON 字段 `pid` 与输出串 `pid=` 契约未变。
- 防回归 `lock_param_not_shadowing_PID hits=0` ⇒ `relay-lock.ps1` 形参不再与只读 `$PID` 冲突。
- 三处已部署技能目录改名实测：`C:\Users\Duanyi\.claude\skills`（RENAMED，新名目录在、旧名目录无）、`E:\Users\Duanyi\.claude\skills`（旧名目录本不存在、新名目录本已存在）、`E:\Users\Duanyi\.minimax\.minimax\skills`（RENAMED，新名在、旧名无）。

**未验证（不许当成已成立）**

- 宿主「前台显示停止」**没有可读信号**，装置不感知 Stop。它防的是「停掉的会话继续写 Prompt 并 spawn」：没有 permit（或 permit 已消费/过期）时 `prespawn` 拒、`verify` 拒。**若会话绕过装置直接调 `session_create`，装置拦不住**——这是宿主侧权限边界，必须如实告人。
- `job-register` 是**自报**登记：不登记的后台任务不会触发 `background_jobs_live`。
- permit 未消费且未过期（300 s）时 `prespawn` 返回 `permit_outstanding`；`session_create` 失败后不能立即重试，需等 TTL 或人工删 `docs\relay\.spawn-permit.json`（有意取舍）。
- 真链未实测：本轮未起任何 relay 真链（家规：起环权在目标项目内）。
- filemanager 链仍 `status=blocked`（第 4 环 `status=error`、`next_session_id` 陈旧），本轮未动对方仓库。

**留证**：raw `tool\references\selftest-2026-11-27-b25.txt`（35142 B / 389 行 / CR=0 / SHA256 `F98CA83C073B4356487304F8F615433B366008B045B6A3375697D623B302876F`）+ 同名 `.md` 留证小结。
