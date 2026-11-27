# 无人值守接力协议 · AGENT-RELAY.md

> **用法**：把本文件放进目标仓库 `docs/agent-relay.md`，再把 §7 那 6 行贴进仓库 `AGENTS.md`。
> 此后项目里的 Agent 自己完成「阶段收尾 → 落盘交接 → 开新会话 → 投递接力 Prompt」，
> 你只需要说一次「按 <计划文档> 起接力链」，之后不需要人在场。
>
> 本协议自包含：所有路径都是**仓库相对路径**，不含任何机器绝对路径，可直接搬进任意项目。

---

## 1. 文件契约（链的三条腿）

| 文件 | 角色 | 谁写 |
|---|---|---|
| `docs/relay.json` | **唯一进度真相**（状态机） | 每一环收尾时回写 |
| `docs/plan-*.md` | 目标 + 阶段拆分 + 人工验收点声明 | 起链前由人或首环写 |
| `docs/handoff-*.md` | 每阶段结论与证据，逐字编号续编 | 每一环写自己的那一节 |

铁律：**`relay.json` 不存在或 `status != "running"` ⇒ 不得开新会话。**
链上任何一环都不许把进度写进对话冒充落盘；不许依赖 `~/.minimax/.../task-state/LATEST.md`
（那是 agent 级共享交接卡，任何其它会话的 Stop Hook 都会覆写它，内容可能完全不属于本链）。
台账的回写只许走写闸门 `docs/relay/relay-ledger.ps1`：裸写整文件可能静默覆盖别环的追加，
下一环的 CAS 会把它判成冲突（`exit=3`）—— 那正是设计意图，不是故障。

### relay.json 骨架

```json
{
  "schema": "mcode-relay/1",
  "updated_at": "<ISO8601>",
  "status": "running",
  "goal": "<一句话目标>",
  "plan_doc": "docs/plan-xxx.md",
  "workspace_dir": "<仓库绝对路径，起链时填一次>",
  "auto_relay": true,
  "max_stages": 12,
  "current_stage": 1,
  "chain_started_at": "<ISO8601>",
  "stop_conditions": [
    "status 变为 blocked 或 done",
    "命中 plan_doc 声明的人工验收点（提交/发布/删数据/付费/不可逆）",
    "同一阶段连续两轮无实质进展",
    "current_stage > max_stages with every stage done -> status=done (chain complete)",
    "current_stage > max_stages with an open blocked_on item -> status=blocked",
    "存在未终态的后台任务"
  ],
  "stages": [
    { "id": 1, "title": "", "deliverable": "", "acceptance": "", "status": "pending", "session_id": null }
  ],
  "sessions": []
}
```

---

## 2. 每一环的四步义务（顺序不得颠倒）

任一环（含首环）在本轮内必须走完：

1. **读** `docs/relay.json` + `plan_doc`。校验：`status=="running"`、`current_stage <= max_stages`、
   自己负责的阶段号 == `current_stage`。任一不符 → 跳到第 4 步停链分支，**不得**新建会话。
2. **只做** `current_stage` 这一个阶段，做到其 `acceptance` 判据成立**并亲自跑出证据**为止。
   工具调用超过 40 次仍未收敛 → 停下，如实写「未完成」，走第 4 步。
3. **收尾三件事**：
   - 3.1 结论落盘 `docs/handoff-*.md`：含相对仓库根的指针、**已验证 / 推断 / 未验证** 三档、证据路径；
   - 3.2 回写 `docs/relay.json`：**只许通过写闸门 `docs/relay/relay-ledger.ps1`，禁止裸 `Set-Content` / 手工编辑**。
     配方（四步，缺一不算提交）：
     ① `pwsh -NoProfile -File docs\relay\relay-ledger.ps1 -Action status` → 记下输出里的 `sha256=<64hex>`；
     ② 写一个**纯 ASCII** 的 patch 文件表达意图，本环常用
     `{"stage_done":<阶段id>,"sessions_append":["<本环会话ID>"],"bump_current_stage":true,"next_session_id":"<下一环ID或null>"}`
     （键只有 10 个：`stage_done` / `stage_fields` / `append_stage` / `sessions_append` / `notes_append` /
     `ledger_docs_append` / `blocked_on_append` / `set_status` / `bump_current_stage` / `next_session_id`；
     未知键直接 `exit 2`，防拼错静默失效；`*_append` 去重后追加 ⇒ 同环重跑幂等）；
     **会话流水由闸门兜底**：`stage_done` 提交时闸门自己把本环会话 ID 登记进 `sessions[]`
     （先取 `stages[N].session_id`；没有就取台账里的 `next_session_id` —— 那正是当前在跑的这一环，
     **但只在链仍是 `running` 时回落**：`blocked` / `done` 的链上 `next_session_id` 是遗留值，
     再登记就等于让停掉的链条继续显得活着，闸门改为回显
     `LEDGER_SESSION_SKIPPED stage=… reason=chain_not_running status=…` 且不动 `sessions[]`），
     只追加、不改写、已登记过的不重复 ⇒ 忘了写 `sessions_append` 也不会留下空会话流水
     （回显 `LEDGER_SESSION_REGISTERED session=… stage=… source=…`；两个来源都没有时回显
     `LEDGER_SESSION_SKIPPED reason=no_session_id`，**不编造**会话 ID）；
     **`next_session_id` 按「键在不在」处理**：键缺省 = 不动；键存在但值为 `""` / `null` = **清空**
     （回显 `LEDGER_NEXT_SESSION_CLEARED before=… after=(empty)`），停链配方就靠这一条把旧 id 真正撤掉；
     非空 = 写值（回显 `LEDGER_NEXT_SESSION_SET after=…`）；
     ③ 加 `-DryRun` 先验一次（`LEDGER_DRYRUN_OK`，不写盘、不留锁文件）；
     ④ `-Action commit -Patch <p.json> -ExpectSha256 <第①步的sha>` 正式提交。
     闸门内部保证五件事：**独占写锁**（`docs\relay\.ledger.lock`，`FileMode.CreateNew`，被占 5s 超时、
     陈旧锁 30s 后接管）、**CAS**（sha 在锁外比一次、锁内再比一次，陈旧视图必被判死）、
     **只追加不变式**（`stages`/`sessions`/`notes`/`ledger_docs`/`blocked_on`/`human_checkpoints`/`stop_conditions`
     只许增长、别人的条目逐字保留，改写别人的 stage 条目判死）、**写后回读**（同卷 tmp + 原子 move，再回读逐字比对）、
     **会话流水兜底**（`stage_done` 自动登记本环会话 ID，只追加不重复，见上）。
     这就是「重读盘再合并」的机制化：2026-11-24 实测第 3 环读到比第 2 环最终落盘更早的台账，
     那种跨会话竞态现在由 CAS 判死，不再靠自觉。
     退出码：`0` 已提交（回显 `LEDGER_COMMITED before= after=`，`before` 必须等于你传的 sha）；
     `2` 参数/patch 键/意图非法（含 `missing_expect_sha256`、`stage_fields_not_an_object`、
     `append_stage_status_not_allowed`、`bump_current_stage_not_a_boolean`、`ledger_paths_not_supported_for_action`）；
     `3` `cas_conflict` 或不变式违反（另含 `ledger_unreadable` / `writeback_failed`）；
     `4` 写锁超时；`5` patch 不可解析。
     三条形状硬规矩：① `stage_fields` 必须是**对象**，字符串 / 数组一律 exit 2（否则它会被当成一个
     名为 `Length` 的字段写进阶段）；② `append_stage` 只能声明 `pending`，自带 `status:"done"` 一律 exit 2
     （否则绕过「每个阶段必须由自己的 stage_done 关掉」那条守卫）；③ `bump_current_stage` 必须是 JSON
     **布尔**，字符串 `"true"` 不算数（exit 2）。`append_stage` / `*_append` 的负载按原样落盘：对象仍是对象，
     不会被压成字符串；台账缺某个数组时追加**不会**往里写 `null`。
     拿到 `3 cas_conflict` 的**唯一正确动作**：重新 `-Action status` 取新 sha、按新台账重建 patch、再试一次；
     仍冲突就按第 4 步走停链分支，**绝不允许**改用裸写绕过闸门。判据：`exit=0` 且回显里自己的署名已入列。
   - 3.3 按运行时起下一环：**链内起环的运行时（MCode / OpenClaw）必须先过交接闸门**
     （`prespawn` → 起下一环 → `verify -Nonce`，配方见 §10.7）：不取 permit 就起环 = 开了第二个写者；
     Claude Code / Codex CLI 由 `relay-spawn.ps1` 驱动起环，驱动自己完成交接（见 §10）。
4. **停链分支**：需要人工验收 / 缺权限 / 连续两轮无进展 / 已达 `max_stages` / 全部完成
   → 同样走 3.2 的闸门写 `status`：**全部阶段完成且 `blocked_on` 无未结项 ⇒ `done`**
   （`current_stage > max_stages` 是完成信号，不是故障），其余停链原因 ⇒ `blocked` + `blocked_on_append` 写明缺什么
   —— `set_status` 只接受 `pending` / `done` / `blocked`（其余值 `exit 2 status_not_allowed`），`running` 是人类专属（会话身份提交会判死）；
   `done` 还要求**所有** `stages[].status` 都是 `done`，否则 `exit 3 status_done_but_stages_open open_stages=…`；
   `blocked` 还要求 `blocked_on` 非空（同一 patch 里 `blocked_on_append` + `"set_status":"blocked"` 合法），
   否则 `exit 3 status_blocked_without_blocked_on` —— 状态必须与阶段表、停链原因互相印证，
   在回答里说明，**不得**新建会话；`blocked` 的等人介入，`done` 的如实收尾。

**链条能自转的唯一支点 = 每一环都执行了 3.3。任何一环漏写，链当场断。**

---

## 3. `session_create` 调用配方（MCode 运行时专用）

> 本节只适用于 **MCode** 运行时（内置 `session_create` 工具）。Claude Code / Codex CLI / OpenClaw
> 没有这个工具，它们的起环方式见 §10；家规块 §A.5 会按安装时的 `-Runtime` 注入对应起环规则。

调用形状（MCode 桌面端 / 本机运行时实测）：

```text
mcp_invoke(
  tool_name = "session_create",
  arguments = {
    "agent_name": "me",
    "title": "relay-<NN>of<MM>-<阶段短名> [<relay.json.chain_tag>]",
    "project": "<relay.json.host_project，必须与 project_list 的某一项逐字相等>",
    "content": "<§4 的接力 prompt 正文，把 <N> 换成 <N+1>>"
  }
)
```

- 返回 `ok:true` 且 `turn.mode:"activated"` ⇒ 新会话**已自动开跑**，不需要人在场点发送。
- **只传 `project`，禁传 `workspace_dir`**：两者互斥，同时传会被 `SESSION_CREATE_INVALID_ARGUMENT` 拒绝；
  而 `workspace_dir` 会让宿主按该目录**精确匹配**项目，匹配不到就**自动插一行新项目**——这就是侧栏里
  「凭空多出一个项目」的唯一成因。
- `project` 的值**必须先在 `project_list` 里逐字找到**（等于某个项目的 `workspace_dir`）。找不到 ⇒
  **写 `blocked`，绝不回退传 `workspace_dir`**：回退等于给这个仓库新建一个项目行。
- 若新会话的 `location.workspace_dir` 落到了 `...sessions\<sid>\workspace` 之类的私有临时目录，
  说明 `project` 没被解析到 ⇒ 这一环等于没接上，写 `blocked` 重投，**不要补传 `workspace_dir`**。
- 注意 `mavis` 的 `session create` 子命令不存在（报 `SESSION_CREATE_MOVED`），必须走 tool_search + mcp_invoke。

---

## 4. 接力 prompt 正文（第 N 环，N ≥ 1 通用）

```text
你在无人值守接力链的第 <N> 环，只做这一个阶段，不要向人提问。

0. 仓库根见 relay.json.workspace_dir；会话 cwd 不一定是它（host_project_mode=parent 时跑在父目录），
   所以一切路径写绝对路径、git 一律 `git -C <repo>`。先读 docs/relay.json 与 docs/agent-relay.md（本协议），再读 relay.json.plan_doc。
1. 校验 relay.json：status 必须为 running、current_stage 必须等于 <N>、<N> 不得大于 max_stages。
   任一不符 → 按 §2 第 4 步停链，不得新建会话。
2. 只做 current_stage 阶段，做到 acceptance 判据成立并跑出证据；工具调用 >40 次未收敛就停下写「未完成」。
3. 收尾三件事（顺序不得颠倒）：
   3.1 结论落盘 docs/handoff-*.md（续编现有编号，不新建跨项目指针）；
   3.2 回写 docs/relay.json：一律走闸门 `docs/relay/relay-ledger.ps1`
      （status 取 sha -> 写 patch -> commit -ExpectSha256），禁止裸写整文件；
   3.3 先过交接闸门，再开下一环：
       3.3a 跑 `pwsh -NoProfile -File docs\relay\relay-lock.ps1 -Action prespawn -Stage <N>`，
             只认它打印的 `SPAWN_PERMIT ok nonce=<16 位>`；被拒（exit 3/5/6）就**不起环**，
             走第 4 步写 blocked 并汇报。
       3.3b 调 session_create 开下一环：project 沿用 relay.json.host_project（先在 project_list 里逐字确认），
             **禁传 workspace_dir**；title="relay-<NN>of<MM>-<阶段短名> [<chain_tag>]"，content 用本段正文、
             <N> 换成 <N+1>，并要求下一环完成后把 relay.json 的 sessions[] 追加其自身会话 ID。
             匹配不到 project ⇒ 写 blocked，不得回退传 workspace_dir。
       3.3c 把 nonce 写进下一环 prompt 的第一句，并要求下一环**第一件事**就是
             `pwsh -NoProfile -File docs\relay\relay-lock.ps1 -Action verify -SessionId <它自己的会话 id> -Nonce <nonce>`。
4. 命中停链条件（提交/发布/删数据/付费/不可逆、缺权限、无进展）：
   写 blocked（blocked_on 写明缺什么）并汇报，不得新建会话。
   全部阶段完成（current_stage > max_stages 且 stages 全 done）⇒ 写 done，同样不建会话。
5. 回执条款：你的结果会被运行时自动回传给创建你的会话并唤醒它。若你本轮开头收到的
   是**下游会话的回执消息**（形如 STAGE-<N+1> RECEIVED），而不是新指令：
   只输出一行 `STAGE-<N> RECEIVED|<下游 session id>` 后立即结束本轮，
   不得调用任何工具、不得重做阶段工作、不得再建会话。
6. 纪律：中间产物写文件、对话只留指针与结论；不得伪造验收证据；
   具体值（口令/令牌/ID/哈希）必须当场回读文件并给出长度 + sha16 前 16 位 + 尾部 4 字符。
```

---

## 5. 成本口径（必须按双份算）

实测：子会话完成后会**自动**把结果 `session send` 回创建者会话，这条回传会让上一环再跑一轮 agent 循环
（这是运行时契约，prompt 禁不掉）。所以

> **每推进一环 ≈ 新会话 1 轮 + 父会话被唤醒 1 轮。**

`max_stages` 和额度预算按 `2 × 阶段数` 估。§4 第 5 步的回执条款就是为了让「被唤醒的那一轮」退化成一行的空转，
避免旧会话把回执当新任务重跑。

---

## 6. 安全边界（不可协商）

- 需要人工验收的动作（提交、推送、发布、部署、删数据、付费、改用户线上配置）**一律停下写 `blocked`**，
  绝不自接力。
- 禁止跨项目目录读别人的交接卡；禁止把密钥/令牌写进任何落盘文件。
- 本轮结束前不得留未终态后台任务，否则会出现无人认领的唤醒。
- 链上任何一环若发现 `relay.json` 与仓库实际状态矛盾，以**仓库实际内容**为准，写 `blocked` 等人。

---

## 7. 贴进 `AGENTS.md` 的那 6 行

```markdown
## 无人值守接力链

- 本项目遵循 `docs/agent-relay.md`。任何会话开始工作前，先看 `docs/relay.json`。
- 若 `docs/relay.json` 存在且 `status == "running"`：本轮必须按 `docs/agent-relay.md` §2 推进
  `current_stage`，并在收尾时按 §3 自行 `session_create` 接力下一环（**必须显式传 project=<relay.json.host_project>，禁传 workspace_dir**）。
- 若不存在或 `status != "running"`：正常干活，不要擅自起链。
- 起链只能由人的明确指令触发（如「按 docs/plan-xxx.md 起接力链」），不得自我起链。
```

> **为什么要同时写进 AGENTS.md**：`AGENTS.md` 是否被自动注入到新建会话，取决于运行时与项目识别方式，
> 不保证。所以 §4 的接力 prompt 里**显式要求读 `docs/agent-relay.md`**——这样无论注入与否，
> 只要工作区指向仓库，协议就一定拿得到。AGENTS.md 那段的作用是让**人在新会话里随口说一句**
> 也能接上链，以及防止有人误起链。

---

## 8. 计划文档解析链（`device/start-relay.ps1`）

启动器要知道「本轮推进哪份计划」。它按**固定优先级**解析，**绝不**为了起链而创建计划文档 —— 计划内容属人工验收点（§6），装置只负责找到它。

| 优先级 | 来源 | 采用条件 | 回显 `source=` |
|---|---|---|---|
| 1 | `-PlanDoc <路径>`（相对或绝对均可） | 非空即采用（存在性同样在下一步统一校验） | `argument` |
| 2 | 台账 `plan_doc` | 非空即采用（存在性在下一步统一校验） | `ledger` |
| 3 | 探测 `docs\plan-*.md`、`docs\plans\*.md`、`docs\superpowers\plans\*.md` | 恰好一个命中 | `probe` |

四种情形的固定行为：

1. `-PlanDoc` 指向不存在的文件 ⇒ `FAIL reason=plan_doc_not_found path=...`，**`exit 2`**（拒绝起链，不建空文档）。
2. 台账 `plan_doc` **为空**（或压根没有台账）⇒ 静默继续走探测，**没有额外警告**。
   台账 `plan_doc` **非空但文件不存在** ⇒ 走第 1 条同一个出口：`FAIL reason=plan_doc_not_found ... source=ledger`，
   **`exit 2`**。也就是说存在性只有一处校验，来源只影响回显的 `source=`。
3. 探测命中**多个** ⇒ **不拒绝起链**：取 `LastWriteTime` 最新的那个，同时打
   `WARN plan_doc_ambiguous candidates=N picked=... by=newest_mtime pass_-PlanDoc_to_disambiguate`，
   回显 `source=probe_newest_of_N`。理由：陈旧计划副本与历史留证常同时存在，卡死整条链的代价远高于选错一次；
   警告把选择权交回人工，下一跳用 `-PlanDoc` 显式消歧即可。
4. 探测**零命中** ⇒ `FAIL reason=plan_doc_missing`（附三条探测路径与 `pass -PlanDoc` 提示），**`exit 2`**。

退出码口径：计划解析失败 = `2`；台账闸门拒绝 = `3`；取锁失败 = `4`（§2 的闸门表说的是**回写**闸门，别混）。
计划解析排在并发闸门**之后**、取锁**之前**，所以闸门拒绝时台账原样保留、锁也没取。闸门各拒绝情形的机器可见判据：

| 情形 | 判据行 | 退出码 |
|---|---|---|
| 台账存在但 `ConvertFrom-Json` 失败 | `FAIL reason=ledger_unparsable path=...` | `3` |
| 台账存在但结构无效（`status` 缺失，或不在 running·pending·done·blocked 内） | `FAIL reason=ledger_shape_invalid path=... status=... allowed=running,pending,done,blocked` | `3` |
| 台账的 `max_stages` / `current_stage` 不是整数（阶段上限无法比较） | `FAIL reason=ledger_stage_cap_unknown path=... current_stage=... max_stages=...` | `3` |
| 有阶段 `in_progress`（一人一棒被占） | `CONFLICT stage=... session=... status=in_progress` + `FAIL reason=stage_in_progress rule=one_writer_per_project` | `3` |
| `status=running` 且 `next_session_id` 非空 | `FAIL reason=chain_already_running next_session_id=...` | `3` |
| `status=running` 且 `current_stage >= max_stages`（触顶：末阶段已跑完却没人翻终态；**也可能还有阶段没跑**） | `FAIL reason=chain_at_stage_cap ... stages=<id:status,...\|none> all_done=<true\|false\|unknown>` + HINT 按形态三选一：`all_stages_done_but_status_running`（全 done，可提交 `{"set_status":"done"}` 收尾）/ `stage_cap_reached_with_open_stage`（还有阶段没跑，**禁止**收尾，先把该阶段跑完或解卡）/ `stage_cap_reached_with_no_stage_records`（台账里一条阶段记录都没有，完成性无法证明，先补记录）。显式传 `-AutoFinalize` 时启动器只在「全 done」形态替你收尾：内部调 `relay-ledger.ps1 -Action commit`（先 status 取 sha256、写后回读），成功打 `AUTO_FINALIZED status=done before=<sha> after=<sha>` 并把 HINT 换成 `chain_closed_by_auto_finalize`；失败只打 `WARN auto_finalize=failed reason=...`、台账不动。默认关闭，`-DryRun` 只打 `DRYRUN skip=auto_finalize`，退码始终 `3` | `3` |
| `status=done` 且 `current_stage >= max_stages` | `FAIL reason=chain_exhausted ...` + `HINT=start a fresh chain...` | `3` |
| `status=blocked` | `FAIL reason=chain_blocked blocked_on=...` + `HINT=blocked chains need a human decision first; do not silently resume.` | `3` |
| 无台账 | `OK ledger_absent path=... (will bootstrap)` | 继续 |

计划解析成功行固定为 `OK plan_doc=<相对路径> source=<来源> bytes=<N>`；`-DryRun` 时打 `DRYRUN skip=lock_acquire skip=ledger_bootstrap skip=prompt_write`。

前置校验排在计划解析**之前**，闸门脚本缺失与取锁排在**之后**，四者的失败字面量固定：

| 情形 | 判据行 | 退出码 |
|---|---|---|
| 工作区路径不存在 | `FAIL reason=workspace_missing path=...` | `2` |
| 工作区存在但不是 git 仓库 | `FAIL reason=not_a_git_repo path=...` | `2` |
| 非 `-DryRun` 且回写闸门脚本 `relay-ledger.ps1` 缺失 | `FAIL reason=ledger_gate_missing path=...`（附 `re-run install-relay.ps1`） | `2` |
| 锁脚本 `relay-lock.ps1` 缺失 | `FAIL reason=lock_script_missing path=...`（附 `re-run install-relay.ps1`） | `2` |
| `-MaxStages` 不是整数或不在 1…1000 | `FAIL reason=max_stages_invalid value=...` | `2` |
| `-TtlSeconds` 不是整数或不在 0…86400 | `FAIL reason=ttl_invalid value=...` | `2` |
| `-Target` 为空 | `FAIL reason=bad_parameter target=empty` | `2` |
| 写接力 prompt 失败（目标目录不可写等） | `FAIL reason=prompt_write_failed path=...`（已释放锁，并回滚本次自举出来的台账） | `2` |
| 取锁失败（透传 `relay-lock.ps1` 的退出码） | `FAIL reason=lock_unavailable exit=N` | `4` |

取锁时启动器固定传 `-Action acquire -Stage 1 -Title 'relay-start' -TtlSeconds <TTL>`，**不传** `-SessionId`、
**不传** `-LockPath`，于是 holder 取缺省值 `start-relay:$PID`。后果：**同一仓库第二次真跑即使台账闸门放行也会 `exit 4`**
——这是「二次起链被拒」的第三种来源（闸门看状态、锁看进程）。只有锁的 TTL 到期才会走 `LOCK_TAKEOVER stale_holder=... kept=...`，
过期锁文件被改名保留而不是删除。

两条易踩的性质：

- 解析结果转成**仓库相对路径**写入 prompt；首环 bootstrap 时同一相对路径写进台账。**台账已存在则 bootstrap 不执行**，
  所以后续跳的 prompt 用「当场解析值」，台账仍留首环登记值 —— 二者可能不同。要把计划文档换位置，
  用 `-PlanDoc` 显式传，或人工改台账；别指望重跑启动器改写台账。
- 计划解析发生在**取锁之前**：因计划问题退出时不会残留 `docs\relay.lock`，无需手工清锁。

---

## 9. 收编项目 `AGENTS.md` 的双判据（`scripts/install-relay.ps1`）

安装器要写目标项目的 `AGENTS.md`，先看托管标记对 `<!-- BEGIN RELAY-PORT -->` / `<!-- END RELAY-PORT -->`：

| 现状 | 动作 | 回显 `AGENTS action=` |
|---|---|---|
| 标记对齐全 | 默认**不动**（保留项目手改）；带 `-Force` 才整块替换 | `present_kept` / `replaced` |
| 标记对存在但块结构定位不出来 | **不动**，也不追加（避免双重托管块），交人工检查标记 | `present_unparsed` |
| 只有单侧标记 | 先 `WARN agents_markers_corrupt stray_marker_removed` 清掉游离标记，再走下面的收编判定 | `adopted` / `appended` |
| 无标记，但项目已有自己的接力节 | 把该节**原地包进**标记对，正文一字不动 | `adopted` |
| 无标记、无接力节 | 末尾追加托管块 | `appended` |

「项目已有自己的接力节」由两个判据**按序**认定（命中即止）：

1. **标题判据** `reason=title`：`(?m)^##\s+.*(?:Relay|接力)` 命中某个二级标题；
   节范围 = 该标题行到下一个 `## ` 标题（或文件末）。
2. **内容签名判据** `reason=content_signature`（标题不命中时才跑）：按 `## ` 切节，逐节统计 11 个特征信号
   （`relay.json` · `relay-lock.ps1` · `start-relay.ps1` · `relay-ledger.ps1` · `AGENT-RELAY` ·
   `ACTIVATION-PROMPT` · `session_create` · `in_progress` · `max_stages` · `next_session_id` · `awaiting_user`），
   命中数 **≥ 4** 的分节算候选：
   - 恰好 1 个候选 ⇒ 收编它，判据串形如 `content_signature count=6 signals=relay.json+relay-lock+...`；
   - **多于 1 个候选 ⇒ 不猜**：打 `WARN agents_relay_section_ambiguous matches=N appended_managed_block review=keep_a_single_relay_section`，
     退回**追加**托管块。宁肯多一节（人一眼可见、可手工合并），也不冒「改错别人项目规则节」的风险。
3. 两判据都不命中 ⇒ 追加。

收编的边界：被收编的节原文**不重写、不改写、不删行**，只在其首尾加上标记对；此后重跑安装默认 `present_kept`，
只有显式 `-Force` 会用最新模板替换标记对内的内容（标记对外的项目原文仍然保留）。
安装器每次都会打一行机读复核判据 `AGENTS_MARKERS begin=<N> end=<N>`：收编成功应当是 `begin=1 end=1`，
出现 `begin=2` 之类即托管块重叠，属于要人工处理的状态，别继续起链。

### 9.1 安装器的参数校验与拒绝原因（B31）

安装器的 `-MaxStages` / `-TtlSeconds` 都是**字符串参数**，解析通过后才使用：写成 `[int]` 时绑定器会先拒掉，
进程以 `exit 1` + 栈信息结束，而安装器的退出码契约是 `{0,2,5}`，里面没有 `1`。非法值一律 `exit 2`：

| 情形 | 判据行 | 退出码 |
|---|---|---|
| `-MaxStages` 不是整数 | `FAIL reason=max_stages_invalid value=... hint=expected_an_integer` | `2` |
| `-MaxStages` 不在 1…100 | `FAIL reason=max_stages_invalid value=... min=1 max=100` | `2` |
| `-TtlSeconds` 不是整数 | `FAIL reason=ttl_invalid value=... hint=expected_an_integer` | `2` |
| `-TtlSeconds` 不在 1…86400 | `FAIL reason=ttl_invalid value=... min=1 max=86400` | `2` |
| `-RepoRoot` 不存在 | `FAIL reason=repo_missing path=...` | `2` |
| 目标目录不是 git 仓库 | `FAIL reason=not_a_git_repo path=...` | `2` |
| `-WorkspaceDir` 不存在 | `FAIL reason=workspace_dir_invalid path=...` | `2` |
| `-Runtime` 不在已知集合 | `FAIL reason=runtime_unsupported runtime=... known=...` | `2` |
| `-AnswersFile` 不存在 | `FAIL reason=answers_file_missing path=...` | `2` |
| `-AnswersFile` 解析失败 | `FAIL reason=answers_file_unparsable path=...` | `2` |
| `-AnswersFile` 一个可用键都没有 | `FAIL reason=answers_file_empty path=...` | `2` |
| `-AnswersFile` 含未知键且一个可用键都没有 | `FAIL reason=answers_file_unknown_keys path=... ignored=...` | `2` |

`answers_file_unknown_keys` 只在**一个可用键都没有**时才拒绝：有可用键但夹带了陌生键时，打
`WARN adaptation_answers_unknown_keys ignored=...` 继续装，陌生键被忽略，不写进 `docs\RELAY-ADAPTATION.md`。

适配问答的确认口径：**8 个键全部答了**才是 `confirmed`，答了一部分就是 `partial`。
`ADAPT answers=... applied=N/8 status=... missing=...` 报实际落地的键数，缺键打
`WARN adaptation_answers_partial applied=N/8 missing=...`；一个都没答时是 `WARN adaptation_defaults_unconfirmed`。
控制台三行分别是 `ADAPTATION_STATUS=pending|confirmed|partial`（确认程度）、
`ADAPTATION_SOURCE=defaults|answers`（来源文件）、`ADAPTATION_QUESTIONS=docs\relay\adaptation-questions.md`（待答清单，仅 pending 时出现）；
生成出来的 `docs\RELAY-ADAPTATION.md` 里的来源标签在部分作答时写成 `answers (partial)`，不冒充已确认。

---

## 10. 运行时适配（MCode / Claude Code / Codex CLI / OpenClaw）

本协议默认按 **MCode** 写：起环靠内置 `session_create` 工具（§3）。其它运行时没有这个工具，
安装器 `install-relay.ps1 -Runtime <runtime>` 会把家规块、激活包、适配文档一起切成对应形状。

### 10.1 运行时对照表

| 运行时 | 家规落点 | 下一环怎么起 | 会话 id 从哪来 |
|---|---|---|---|
| `mcode`（默认） | `AGENTS.md` | `session_create` 工具（§3） | 工具返回值 |
| `claude-code` | `AGENTS.md` **+** `CLAUDE.md` | `docs\relay\relay-spawn.ps1 -Runtime claude-code -Execute -AdoptLock`（无头 `claude -p` 子进程） | 输出里的 `"session_id"`，或预置的 `--session-id` |
| `codex` | `AGENTS.md` | `docs\relay\relay-spawn.ps1 -Runtime codex -Execute -AdoptLock`（无头 `codex exec` 子进程） | 输出里的 `"thread_id"` |
| `openclaw` | `AGENTS.md` | 运行时自带的 `sessions_spawn` 工具 | 工具返回值 |

### 10.2 为什么 Claude Code 要写两个文件

Claude Code 读 `CLAUDE.md`；**只有仓库没有 `CLAUDE.md` 时才回退读 `AGENTS.md`**。
所以仓库里只要已经存在 `CLAUDE.md`，`AGENTS.md` 里的托管块就被整份遮蔽 —— 装完看着像成功，
链却永远起不来。安装器因此对 `claude-code` 同时写两个文件，并对两份文件各打一行
`AGENTS_MARKERS` / `CLAUDE_MARKERS` 复核判据。其余三个运行时只写 `AGENTS.md`。

### 10.3 CLI 运行时的链形态与 MCode 不同

MCode 的下一环是一个**常驻会话**，`session_create` 之后它自己接着干活；CLI 运行时的下一环是
**跑完即退的无头子进程**，所以「起下一环」这一步由当前环自己再跑一次 spawn 命令完成。
家规 §A.5 与 §B.9 的表述已改成运行时中立，起环方式由安装器按 `-Runtime` 注入。
**CLI 运行时的**锁转交走 `docs\relay\relay-lock.ps1 -Action adopt`（`relay-spawn.ps1 -AdoptLock` 会自动调它）；
**链内起环的运行时**（MCode / OpenClaw）不走 adopt，走 §10.7 的 permit 闸门。

### 10.4 起环驱动 `relay-spawn.ps1`

- 默认**只干跑**：打印将要执行的命令行（prompt 用 `<prompt from file>` 占位），不跑任何东西；
  加 `-Execute` 才真跑。
- prompt 从文件读（启动器写的 `docs\relay\next-relay-prompt.txt`），不过 shell 引号往返。
- 退出码：`0` 建好命令（或起环成功且取到会话 id）/ `2` 参数非法、运行时不对、prompt 文件缺失或超 60000 字符 /
  `3` 运行时 CLI 不存在、运行失败、锁转交失败 / `4` 跑完了但取不到会话 id。

### 10.5 OpenClaw 的硬约束

OpenClaw 只注入**它自己 workspace 根目录**的 `AGENTS.md`（子 agent 额外注入 `TOOLS.md`）。
所以目标仓库必须就是该 OpenClaw agent 的 workspace；不是的话，先把托管块复制到 workspace 根的
`AGENTS.md`，否则家规块根本不会进 system prompt。

### 10.6 换运行时的规矩

换运行时**必须重装**（`install-relay.ps1 -Runtime <新> -Force`），否则 `docs\RELAY-ADAPTATION.md`
与家规块里还写着旧运行时，两边会各说各话。`install-relay.ps1` 遇到不认识的 `-Runtime`
会响亮失败（`reason=runtime_unsupported`，退出码 2），不静默退回默认运行时。
---

## 11. 交接闸门：prespawn → 起下一环 → verify -Nonce

`session_create`（MCode）与 `sessions_spawn`（OpenClaw）都是**从链内开下一个写者**。前台会话在前端里
已经显示为「已停止」，若它还能随手再开一个写者，两个写者就会同时改同一个仓库 —— 这正是本 kit 要防的
事。所以这两种运行时在开下一环前必须先取一张**一次性 permit**：

1. **取 permit**：`pwsh -NoProfile -File docs\relay\relay-lock.ps1 -Action prespawn -Stage <下一环阶段号>`
   - `-SessionId` 可省：省略时装置用**当前锁持有者**当身份（链内环通常读不到自己的会话 id）。
   - 成功时打印 `SPAWN_PERMIT ok nonce=<16 位十六进制> owner=… stage=… expires_in_s=… path=…`，并退出 0。
   - 拒绝情形（**一律不起下一环**，走 §2 第 4 步写 `blocked` 并汇报）：
     | 拒绝 | 判据行 | 退出码 |
     |---|---|---|
     | 缺会话身份（既没给 `-SessionId`，盘上也没有锁） | `SPAWN_REFUSED reason=missing_session` | `6` |
     | 链已停（有人打了停链哨兵） | `SPAWN_REFUSED reason=chain_stopped note=…` | `3` |
     | 链锁不在（没有锁记录） | `SPAWN_REFUSED reason=lock_missing` | `3` |
     | 链锁在别人手上 | `SPAWN_REFUSED reason=lock_not_mine holder=… requester=…` | `5` |
     | 本会话登记的后台任务还活着 | `SPAWN_REFUSED reason=background_jobs_live owner=… pids=…` | `5` |
     | 上一张 permit 还没用掉也没过期 | `SPAWN_REFUSED reason=permit_outstanding nonce=… expires_at=…` | `3` |
2. **起下一环**：把 nonce 写进下一环 prompt 的第一句，然后按运行时开新会话（MCode `session_create` /
   OpenClaw `sessions_spawn`）。
3. **消费 permit**：`pwsh -NoProfile -File docs\relay\relay-lock.ps1 -Action verify -SessionId <新会话 id> -Nonce <nonce>`
   - 成功打印 `SPAWN_VERIFIED ok nonce=… from=… to=… driver_adopted=… stage=…`，退出 0；
     permit 被标记为已消费，链锁转到新会话。
   - 拒绝情形：`PERMIT_INVALID reason=chain_stopped|lock_missing|no_permit|permit_consumed|nonce_mismatch|permit_expired|holder_changed`
     （退出码 `3`；缺 `-SessionId` 是 `PERMIT_INVALID reason=missing_session`，退出码 `6`）。
   - **verify 被拒就不要再起一次**：同一张 prompt 被起两次时，第二次 verify 会撞上
     `permit_consumed`，第二个会话必须停手、不许写任何东西。

后台任务登记：起了会活过你这一轮的后台进程，先
`pwsh -NoProfile -File docs\relay\relay-lock.ps1 -Action job-register -ProcId <pid>`
（`-SessionId` 同上可省），任务结束后 `-Action job-clear -ProcId <pid>`。否则下一个环会在你还有活儿的时候
开新写者。

### 锁的全部动作（12 个）

`acquire` · `renew` · `release` · `status` · `adopt` · `prespawn` · `verify` ·
`stop-mark` · `stop-clear` · `job-register` · `job-clear` · `gate-status`

退出码：`0` 成功 / `2` 锁被占或竞争失败 / `3` 状态不允许（缺锁、已停、permit 失效…）/
`5` 锁不归我（`LOCK_NOT_MINE`）、后台任务还活着 / `6` 参数非法（`LOCK_BAD_ARG` / `missing_session`）。
`gate-status` 一次打印闸门全景：`GATE holder=… stop=… permit=… jobs_live=… lock=…`。
## 12. 锁的凭据、TTL 与新增拒绝原因（B31）

本节描述 `relay-lock.ps1` 的凭据规则与 B31 新增的拒绝原因。装置本体与 `tool\templates\relay-lock.ps1` 逐字一致。

### 12.1 一次交接 = 一个一次性凭据

- `prespawn` 发行一次性凭据（permit），nonce 为 16 位十六进制，TTL 300 秒；输出 `SPAWN_PERMIT ok nonce=<nonce> owner= stage= expires_in_s= path=`。
- `verify -SessionId <本环会话 id> -Nonce <nonce>`：**nonce 必填**。缺 nonce 的 verify 一律拒绝（`PERMIT_INVALID reason=nonce_required`，退出码 6）——不携带凭据的调用什么都证明不了。
- `adopt -SessionId <新环会话 id> -Nonce <nonce>`：**必须**先有未消费的 permit，且 nonce 匹配。CLI 运行时由 `relay-spawn.ps1` 先 `prespawn` 再 `adopt -Nonce`。
- permit 一经消费（verify 或 adopt）即失效；重复起环必然撞上 `permit_consumed`。

### 12.2 锁动作的凭据要求

| 动作 | 凭据要求 | 拒绝时退出码 |
| --- | --- | --- |
| `prespawn` | 持有者身份（缺 `-SessionId` 时回退为锁内 holder） | 3 / 5 / 6 |
| `verify` | `-Nonce`（permit 存在时必填） | 3 / 6 |
| `adopt` | 未消费的 permit + 匹配的 `-Nonce` | 3 |

### 12.3 TTL 的来源与优先级

TTL 是项目级决定：安装器把它写进 `docs\relay\relay-runtime.json` 的 `lock_ttl_seconds`；调用方显式传 `-TtlSeconds` 时以参数为准；锁被 `renew` 时保留它自己记录的值。优先级：**显式参数 > 锁内记录值 > 描述符 > 1800**。
`LOCK_ACQUIRED` / `LOCK_RENEWED` 打印 `ttl_s=<n> ttl_source=parameter|recorded|descriptor|default`。

`-TtlSeconds` 在启动器与安装器上都是**字符串参数**：写成 `[int]` 时绑定器会先拒掉，进程以 `exit 1` + 栈信息结束，
而退出码契约里没有 `1`（启动器 `{0,2,3,4}`、安装器 `{0,2,5}`）。所以两处都手工解析：非整数或越界一律
`FAIL reason=ttl_invalid value=...` + `exit 2`（启动器范围 0…86400，安装器 1…86400）。`-MaxStages` 同理，
两处都改成字符串参数后手工解析，越界仍是 `FAIL reason=max_stages_invalid` + `exit 2`（启动器 1…1000、安装器 1…100）。

### 12.4 B31 新增的拒绝原因与状态

| 字面量 | 含义 | 退出码 |
| --- | --- | --- |
| `PERMIT_INVALID reason=nonce_required` | verify 没有带 nonce | 6 |
| `LOCK_REFUSED reason=permit_required` | adopt 时没有未消费的 permit | 3 |
| `LOCK_REFUSED reason=nonce_required` | adopt 没有带 nonce | 3 |
| `LOCK_REFUSED reason=nonce_mismatch` | adopt 的 nonce 与 permit 不符 | 3 |
| `LOCK_REFUSED reason=permit_consumed` | permit 已被消费 | 3 |
| `LOCK_REFUSED reason=permit_expired` | permit 已过期 | 3 |
| `LOCK_REFUSED reason=chain_stopped` | 停止哨兵存在 | 3 |
| `LOCK_DIR_MISSING` | 锁目录不存在 | 2 |
| `LOCK_TAKEOVER reason=unreadable_lock` | 锁文件无法解析为 JSON，按「不可证明存活」处理并接管 | 0 |
| `LOCK_TAKEOVER reason=unreadable_heartbeat` | 心跳读不出，按「不可证明存活」处理并接管 | 0 |
| `LOCK_TAKEOVER reason=future_heartbeat` | 心跳落在未来，按「不可证明存活」处理并接管 | 0 |
| `LOCK_STATE state=UNREADABLE` | 锁文件存在但读不出内容 | 0 |
| `LOCK_PERMIT_CLEARED` | 新链取锁时清掉了上一个持有者遗留的 permit | 0 |

被接管的锁文件保留为 `.relay.lock.stale.<epoch_ms>` 供取证；新链取锁时会清掉遗留的 permit，使首环的 bootstrap verify 仍然成立。

### 12.5 退出码契约（未变）

`relay-lock.ps1`：`0` 成功 / `2` 锁被占或参数无效 / `3` 状态不允许 / `5` 锁不属于本会话 / `6` 参数缺失。
