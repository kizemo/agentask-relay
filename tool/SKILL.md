---
name: agentask-relay
description: Install the unattended relay (auto-advance) kit into any git project so that a single prompt can start a continuous, self-advancing session chain with one-writer-per-project locking. Use when the user asks to 给别的项目装自动接力/自动推进装置, 把接力链搬到别的项目, port the relay kit to another repo, or make unattended auto-advance available in another project.
---

# agentask-relay —— 把「无人值守接力链」装置装进任意项目

一次性安装，之后**只要一句 Prompt** 就能在目标项目内启动连续接力任务。

## 它装了什么

| 目标路径 | 作用 |
|---|---|
| `<repo>\docs\relay\start-relay.ps1` | 启动器：工作区校验 + 并发闸门 + 取锁 + 台账初始化（只新建不覆写）+ 生成接力 prompt |
| `<repo>\docs\relay\relay-ledger.ps1` | 台账写闸门：写锁 + CAS(`-ExpectSha256`) + 只追加不变式 + 写后回读；动作只有 `-Action status` / `-Action commit` / `-Action doctor` / `-Action migrate-hint`，`-DryRun` 可先验。`doctor` 与 `migrate-hint` **都只读**：不取锁、不写一字节；`doctor` 报台账自相矛盾处（`DANGLING …`），`migrate-hint` 报旧 schema 的迁移建议（`MIGRATE_HINT …`，只建议、不迁移）。干净 / 无建议 exit 0，有 findings / 有建议 exit 3 |
| `<repo>\docs\relay\relay-lock.ps1` | 互斥锁：`FileMode.CreateNew` 原子创建，保证一个项目同时只有一个写会话 |
| `<repo>\docs\relay\relay-spawn.ps1` | 起环驱动（**仅 CLI 运行时用**）：把接力 prompt 交给 `claude -p` / `codex exec` 无头子进程，取回会话 id 并转交锁；默认只干跑，加 `-Execute` 才真跑。子进程在**链仓工作目录**内启动（`--add-dir` 只放宽权限、不改 cwd），权限模式默认 `bypassPermissions`（无人值守不提问），原始输出落盘 `docs\relay\relay-spawn-output\`。**铁律**：`claude` 的所有旗标必须写在 prompt **之前**，prompt 放最后，否则整批旗标被丢弃（拿不到 JSON、`session_id` 丢失、模式回落 `default`）；配方与实测见 `references/claude-code-permissions-2026-11-25.md`；**临时夹具跑真链必须加 `-EphemeralWorkspace`**（子进程建的项目条目会被驱动挪出登记册、转写留证），机制见 `references/claude-project-registry.md` |
| `<repo>\docs\AGENT-RELAY.md` | 通用协议（自包含、仓库相对路径，可直接搬） |
| `<repo>\docs\RELAY-SOP.md` | 操作规程 |
| `<repo>\docs\RELAY-ADAPTATION.md` | **本项目裁决骨架**（写集 / 门禁 / 模型策略）；首次运行自动探测默认值 + 生成提问包，答案经 `-AnswersFile` 回填（见「装完之后必须做的两件事」） |
| `<repo>\AGENTS.md` | 受管家规块 `<!-- BEGIN RELAY-PORT -->`（幂等注入，不重复、不覆盖项目自己写的规则） |
| `<repo>\docs\plan-relay.md` | 计划文档（未指定 `-PlanDoc` 且未探测到既有计划时自动生成） |
| `<repo>\docs\relay\ACTIVATION-PROMPT.txt` | **激活包**：目标确认轮（B33）+ 起链的四步命令 + 一句话激活语 |
| `<repo>\docs\relay\install-report.md` | 安装报告（文件清单、sha16、自检结果） |

**它绝不写 `docs\relay.json`** —— 台账由启动器在激活那一刻创建，安装器只读不碰。

## 怎么调用

在**任意会话**里执行一次安装：

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File "<skill目录>\scripts\install-relay.ps1" `
  -RepoRoot "<目标仓库绝对路径>" `
  -Target "<本轮目标批次>" `
  [-PlanDoc "<仓库相对路径的计划文档>"] `
  [-StageTitles "1. xxx;2. yyy"] `
  [-MaxStages 6] [-WorkspaceDir "<仓库根>"] [-TtlSeconds 1800] [-Force] `
  [-AnswersFile "<仓库相对路径的答案 JSON>"] `
  [-Runtime mcode|claude-code|codex|openclaw]
```

- 退出码 `0` = 装好；`2` = 参数/工作区非法；`5` = 自检不过。装完会顺带跑一次启动器干跑，干跑结果只记录不拉低退出码（`3` 链已在跑 / 台账 blocked 或耗尽、`4` 锁被占 —— 都不影响安装本身）。
- `-MaxStages` / `-TtlSeconds` 是**字符串参数**，脚本自己解析：非整数或越界 ⇒ `FAIL reason=max_stages_invalid` / `FAIL reason=ttl_invalid`，退出码 `2`。写成 `[int]` 会让参数绑定器先拒掉，进程以 `exit 1` + 栈信息结束，而契约里没有 `1`。
- `-Runtime` 指定目标会话跑在哪个运行时上（默认 `mcode`）。它同时决定**家规落到哪些文件**与**下一环怎么起**，见下面「运行时适配」。不认识的运行时响亮失败（`FAIL reason=runtime_unsupported`，退出码 `2`），不静默退回默认。
- `-PlanDoc` 省略时会自动探测 `docs\plan-*.md` / `docs\plans\*.md` / `docs\superpowers\plans\*.md`；探测到多份会告警（`WARN plan_doc_ambiguous`）并退回新建 `docs\plan-relay.md`。**安装器是唯一允许创建计划文档的地方**，启动器只解析、绝不创建（见「装置契约」）。
- `-AnswersFile` 把用户对三项裁决（写集 / 门禁 / 模型）的答案回填进 `docs\RELAY-ADAPTATION.md`：解析答案 → 逐键覆盖探测值 → **只重写 §3/§4/§5**（§6 之后的手改内容不丢）→ 打印 `ADAPT_CHECK doc=… placeholders=N source=answers`。答案文件缺失 / 解析失败 / 为空分别 `FAIL reason=answers_file_missing|answers_file_unparsable|answers_file_empty`，退出码 `2`。
- 答案文件夹带不认识的键时打 `WARN adaptation_answers_unknown_keys ignored=…` 继续装，陌生键不写进文档；但**一个可用键都没有**时是 `FAIL reason=answers_file_unknown_keys`（退出码 `2`），不当成空文件放过。
- 确认口径：8 个键全部答了才是 `ADAPTATION_STATUS=confirmed`；答了一部分是 `partial`（并打 `WARN adaptation_answers_partial applied=N/8 missing=…`），一个都没答是 `pending`。`ADAPTATION_SOURCE=defaults|answers` 说的是来源文件，确认程度看 `ADAPTATION_STATUS`。
- **幂等**：重复执行不产生重复家规块、不覆盖项目自己改过的文件（`SKIP ... kept`）。要强制覆盖用 `-Force`。装完看见 `ADAPT_CHECK ... placeholders=0` 即表示 §3/§4/§5 既无残留 `TODO`、也无未替换占位符。
- 已有未受管的接力家规时**收编**（adopt）该段并加标记，不追加第二份。收编判据是双层的：
  1. 标记块已存在 → `present_kept`；
  2. 标题命中「接力 / relay / 自动推进」→ `reason=title` 包裹收编；
  3. 标题不含关键词时按 **内容指纹**打分 —— 真实信号共 **11 条**：`relay.json` / `relay-lock` / `start-relay` / `relay-ledger` / `AGENT-RELAY` / `ACTIVATION-PROMPT` / `session_create` / `in_progress` / `max_stages` / `next_session_id` / `awaiting_user`，**单节命中 ≥4 条**即包裹收编（`reason=content_signature`）；
  4. **≥2 节都合格则不猜** → `WARN agents_relay_section_ambiguous matches=N` + 追加托管块，提示人工把接力规则合并成单一章节。

  原始内容一律保留，包裹不删字。

## 运行时适配（MCode / Claude Code / Codex CLI / OpenClaw）

装置本体一套，**运行时**决定两件事：**家规落到哪些文件** + **下一环怎么起**。

| `-Runtime` | 家规落点 | 下一环怎么起 | 需要起环驱动 |
|---|---|---|---|
| `mcode`（默认） | `AGENTS.md` | 内置 `session_create` 工具 | 否 |
| `claude-code` | `AGENTS.md` **+** `CLAUDE.md` | 无头 `claude -p` 子进程 | 是 |
| `codex` | `AGENTS.md` | 无头 `codex exec` 子进程 | 是 |
| `openclaw` | `AGENTS.md` | 运行时自带的 `sessions_spawn` 工具 | 否（但要手动转交锁） |

- **Claude Code 必须双写**：它读 `CLAUDE.md`，只有仓库没有 `CLAUDE.md` 时才回退读 `AGENTS.md`；
  仓库里只要存在 `CLAUDE.md`，`AGENTS.md` 里的家规就被整份遮蔽 ⇒ 装完看着像成功、链起不来。
  装完复核看两行：`AGENTS_MARKERS begin=1 end=1` 与 `CLAUDE_MARKERS begin=1 end=1`。
- **CLI 运行时的链形态不同**：下一环是**跑完即退的无头子进程**，链靠「本环自己再跑一次 spawn 命令」推进；
  MCode 的下一环是常驻会话。
- **锁转交只有一条路**：`relay-lock.ps1 -Action adopt -SessionId <id>`（`relay-spawn.ps1 -AdoptLock` 会自动调它）。
- **CLI 链的 session id 由启动器分配**：MCode 的会话 id 是 `session_create` 返回的，CLI 运行时没有这种回传，所以启动器预先分配一个 UUID，同时写进台账 `next_session_id` 与 prompt 的 `RELAY_SESSION_ID=` 行；子环据此 renew / release 锁，驱动从台账读它（`source=ledger`）。`claude --session-id` 在部分版本上不被遵守，**别把运行时的内部会话 id 当成链的 session id**。
- **换运行时必须重装**（`-Force`），否则家规块、`docs\RELAY-ADAPTATION.md`、激活包三处会各说各话。
- 完整分析与各家踩坑见 `references\runtime-portability-2026-11-25.md`；
  逐家部署步骤见 `references\deployment-claude-code.md` / `deployment-codex.md` / `deployment-openclaw.md`。

## 链条的项目归属（B24：只传 project，错配硬停）

**宿主按「会话的工作目录」分项目：一个目录一个项目，没有包含关系。** 探针实测：`session_create` 同时给 `project` 和 `workspace_dir` 会被直接拒绝（只能填一个）；只给 `workspace_dir` 时，宿主按该目录**精确匹配**项目，匹配不到就**自动插一行新项目**。

- **这就是「relay 的会话在侧栏里凭空多出一个项目」的唯一成因**：旧版装置一直教下一环传 `workspace_dir=<仓库根>`，于是每次起链都在重复「插入新项目行」这个动作。
- **B24 硬规则：起环只传 `project=<host_project 精确键>`，禁传 `workspace_dir`。** 键来源 `-ExpectedHostProject` > `docs\relay\host-project.txt` > 缺省仓库根；启动器恒打 `OK host_project_key exact_workspace_dir=` 与 `OK host_project_value value=... source=... mode=...`。
- **错配默认硬停**：键 ≠ 仓库根 ⇒ `FAIL reason=host_project_mismatch` + `exit 2`（`-DryRun` 只 WARN，便于预览）。要让链跑在已注册的父项目目录下，必须显式 `-AllowHostMismatch`（`mode=parent`，prompt 把全部路径改绝对、git 改 `git -C <repo>`）。
- **prompt 内置自检**：新建会话前必须先在 `project_list` 里逐字找到该键；找不到 ⇒ 写 `blocked`，**绝不回退传 `workspace_dir`**（回退就等于给这个仓库新建一个项目）。
- **链的身份可见**：传 `-InitiatorSession <sid>`；台账 seed 记 `host_project` / `host_project_mode` / `chain_id` / `chain_tag` / `initiator_session`；每条会话标题末尾追加 `[<chain_tag>]`（如 `relay-02of06-批次73 [1127-1432]`），侧栏即可区分两条链并认出最新一环；prompt 首行是 `CHAIN <chain_id> | link <linkTag> | started ... | initiator ... | host project ... (...)`。
- 机制、探针与现场数据见 `references\mcode-project-registry.md`。

## 装完之后必须做的两件事

### 1. 把 `docs\RELAY-ADAPTATION.md` 的三项裁决问出来

安装器**不交互提问**（无 TTY），它只做「探测 + 生成提问包」，发问由托管 agent 完成。

| 首跑输出 | 含义 | 你要做的 |
|---|---|---|
| `ADAPTATION_STATUS=pending` | 文档里的三项是**探测默认值**，不是用户确认值 | 按 `docs\relay\adaptation-questions.md` 逐项问用户 → 写 `docs\relay\adaptation-answers.json` → 带 `-AnswersFile` 重跑 |
| `ADAPTATION_STATUS=confirmed` | 三项已由答案文件落定 | 直接进第 2 步 |

- **`pending` 不许起链。** 默认值是猜的，硬起会在第一环撞上「写集不明」而停链。重跑后必须看到 `ADAPTATION_STATUS=confirmed`（或 `ADAPTATION_SOURCE=answers`）才能激活。
- 一次只问 **2-3 项**：按问题包的三组（写集 / 门禁 / 模型）分批，别把 8 项一次抛给用户。
- 答案文件是**平铺键值**，键名与问题包里的「答案键」逐字一致；只写要覆盖的键，其余保留探测值。安装器只定点替换 §3/§4/§5。
- 首跑落的三个文件：`docs\relay\adaptation-questions.md`（人读的问题包）、`docs\relay\adaptation-questions.json`（机读）、`docs\relay\adaptation-answers.template.json`（照着填）。
- 三个状态行：`ADAPTATION_STATUS`（`pending`/`confirmed`）、`ADAPTATION_SOURCE`（`defaults`/`answers`）、`ADAPTATION_QUESTIONS`（只有 `pending` 时非空）。

### 2. 在目标项目内激活（起环权必须在目标项目内）

```
按 docs\relay\ACTIVATION-PROMPT.txt 启动接力链
```

激活包 `docs\relay\ACTIVATION-PROMPT.txt` 在四步之前还有 **STEP 0 目标确认轮（B33）**；四步本身不变：跑启动器 → `session_create` 开第一环 → `relay-lock.ps1 -Action adopt` 转交锁 → `session get` 回读校验。目标项目会话照做即可。

**目标确认轮（B33）**：跑启动器之前，激活会话先核对目标（激活包 target 行 + 计划文档）。目标明确 ⇒ 直接跑启动器；目标不明确（验收判据不可验证 / 范围有多解 / 与计划或家规矛盾 / 关键输入缺失）⇒ 只做**一轮** `ask_user` 确认（全部目标问题合并成一轮，不重复问适配三项）。用户确认后，把裁决**只追加**进计划文档的「目标确认（B33）」节（时间戳 + 用户裁决原文 + 确认后目标句；不改写、不删除既有计划内容），再以确认后的目标句作 `-Target` 跑启动器，链即无人值守逐环推进直到全部阶段 done（受 `max_stages` 硬上限约束）。一轮之后仍不明确、用户拒答或未答 ⇒ 不起链；计划文档解析不出来 ⇒ 不创建（只有安装器可创建），停下要 `-PlanDoc`。链上各环仍禁止提问、禁止改计划内容；链中途新歧义照旧写 `blocked`。详见协议 §14。

## 装置契约（实测可用）

```powershell
# 启动器（-PlanDoc 可省）
pwsh -NoProfile -ExecutionPolicy Bypass -File '<repo>\docs\relay\start-relay.ps1' -Target '<批次>' -MaxStages 6
# 退出码 0 可起链 / 2 工作区非法、不是 git 仓库、计划文档解析不出来（plan_doc_missing / plan_doc_not_found）/
#         host_project_mismatch（期望项目 ≠ 仓库根，且没给 -AllowHostMismatch）/
#         3 已有链在跑或台账 blocked、耗尽 / 4 锁拿不到
# 干跑（只校验不起链）
pwsh -NoProfile -ExecutionPolicy Bypass -File '<repo>\docs\relay\start-relay.ps1' -Target '<批次>' -DryRun
# 起链时把发起会话的 id 记进链身份（台账 chain_* / initiator_session、标题后缀、prompt 首行都靠它）
pwsh -NoProfile -ExecutionPolicy Bypass -File '<repo>\docs\relay\start-relay.ps1' -Target '<批次>' -InitiatorSession '<你的 sessionId>'
# 仓库在别的目录下（期望项目 = 已注册的父目录）：显式托管，prompt 会强制绝对路径
pwsh -NoProfile -ExecutionPolicy Bypass -File '<repo>\docs\relay\start-relay.ps1' -Target '<批次>' -ExpectedHostProject '<父项目绝对路径>' -AllowHostMismatch

# 互斥锁
pwsh -NoProfile -ExecutionPolicy Bypass -File '<repo>\docs\relay\relay-lock.ps1' -Action status
pwsh -NoProfile -ExecutionPolicy Bypass -File '<repo>\docs\relay\relay-lock.ps1' -Action acquire -SessionId '<sid>' -Stage 1 -Title 'relay-1' -TtlSeconds 1800
pwsh -NoProfile -ExecutionPolicy Bypass -File '<repo>\docs\relay\relay-lock.ps1' -Action renew  -SessionId '<sid>'
pwsh -NoProfile -ExecutionPolicy Bypass -File '<repo>\docs\relay\relay-lock.ps1' -Action adopt  -SessionId '<new sid>'
pwsh -NoProfile -ExecutionPolicy Bypass -File '<repo>\docs\relay\relay-lock.ps1' -Action release -SessionId '<sid>'

# 交接闸门（B25 起加的 7 个动作，与上面 5 个链锁动作同属一个脚本）
pwsh -NoProfile -ExecutionPolicy Bypass -File '<repo>\docs\relay\relay-lock.ps1' -Action prespawn -Stage '<n>'
pwsh -NoProfile -ExecutionPolicy Bypass -File '<repo>\docs\relay\relay-lock.ps1' -Action verify -SessionId '<新 sid>' -Nonce '<n>'
pwsh -NoProfile -ExecutionPolicy Bypass -File '<repo>\docs\relay\relay-lock.ps1' -Action gate-status

# 起环驱动（仅 CLI 运行时 claude-code / codex；默认只干跑，加 -Execute 才真跑）
pwsh -NoProfile -ExecutionPolicy Bypass -File '<repo>\docs\relay\relay-spawn.ps1' -Runtime claude-code -PromptFile '<repo>\docs\relay\next-relay-prompt.txt' -WorkspaceDir '<repo>'
pwsh -NoProfile -ExecutionPolicy Bypass -File '<repo>\docs\relay\relay-spawn.ps1' -Runtime claude-code -PromptFile '<repo>\docs\relay\next-relay-prompt.txt' -WorkspaceDir '<repo>' -Execute -AdoptLock
```

起环驱动 `relay-spawn.ps1` 的退出码：`0` 建好命令（或起环成功且取到会话 id）/ `2` 参数非法、运行时不是 CLI 运行时、prompt 文件缺失或超 60000 字符 / `3` CLI 不存在、运行失败、锁转交失败 / `4` 跑完了但取不到会话 id。

**锁的 `-Action` 共 12 个合法值**（不是 5 个）：`acquire` / `renew` / `release` / `status` / `adopt`（链锁本体）+ `prespawn` / `verify` / `stop-mark` / `stop-clear` / `job-register` / `job-clear` / `gate-status`（**交接闸门**，B25 加的）。语义：`prespawn` 签发一次性 permit（nonce/owner/stage，300 s TTL）→ 新会话起来后 `verify -SessionId <新 id> -Nonce <n>` 一步完成「消费 permit + 锁归属轮转」；`stop-mark -Note <why>` / `stop-clear` 管停止哨兵 `docs\relay\.stop`；`job-register -ProcId <pid>` / `job-clear` 登记后台作业（**自报登记**，不登记的任务不会触发 `background_jobs_live`）；`gate-status` 一行回显 `GATE holder=.. stop=.. permit=.. jobs_live=N pids=.. lock=..`。

**锁的退出码**：`0` 成功 / `2` 锁被占（`LOCK_HELD` / `LOCK_RACE`）/ `3` 锁不存在（`LOCK_MISSING`）/ `5` 不是持有人（`LOCK_NOT_MINE`）/ `6` **参数非法**（`LOCK_BAD_ARG`、`missing_session` 这类 —— 即调用方漏了 `-SessionId`，不是怪癖）。

**启动器的计划文档解析链**（在取锁**之前**跑完，所以失败不会留下活锁）：
`-PlanDoc` → 台账 `plan_doc` → 探测 `docs\plan-*.md` / `docs\plans\*.md` / `docs\superpowers\plans\*.md`。
唯一命中直接用（打印 `OK plan_doc=<相对路径> source=probe bytes=<n>`）；多命中告警 `plan_doc_ambiguous` 后按 mtime 取最新并列出候选；
零命中 `FAIL reason=plan_doc_missing` + `exit 2`，提示补 `-PlanDoc` / 台账 `plan_doc` / 新增 `docs\plan-<批次>.md` 三条出路。
解析出的相对路径会写进台账 `plan_doc`，之后每一环读的是同一个文件；**启动器绝不创建计划文档**（那是安装器的职责）。

起环参数（`session_create`）：只传 `agent_name` / `title` / `project=<relay.json.host_project 精确键>` / `model` / `content`。
**禁止**传 `workspace_dir`（与 `project` 互斥，且会按目录新建项目行）/ `effort` / `defer_first_turn` / `parent_session_id`（schema 无此字段）。
建环后立刻 `session get` 回读 `project_id` / `workspace_dir` / `effective_model` / `status`：`project_id` 必须等于期望项目，`workspace_dir` 不许落进 `...sessions\<sid>\workspace`。

## 四道并发闸门

1. `FileMode.CreateNew` 原子锁 —— 抢不到就退出，不存在「两个会话同时写」。
2. 台账闸门 —— 有 `in_progress` 阶段 / `status=running` 且有 `next_session_id` / `status=running` 且 `current_stage >= max_stages`（`chain_at_stage_cap`，触顶；判据行带 `stages=` 与 `all_done=`，HINT 按「全 done / 还有阶段没跑 / 台账无阶段记录」三种形态分开给，**只有全 done 才可提交 `{"set_status":"done"}` 收尾**；显式传 `-AutoFinalize` 时启动器只在该形态下替你提交这一步，写仍走 `relay-ledger.ps1`，失败只 WARN、台账不动，退码仍是 3）/ 台账 blocked / `status=done` 且耗尽 ⇒ 拒绝起链。
3. 写集指纹 —— 每环先读 `docs\relay.json` 的阶段写集与 `RELAY-ADAPTATION.md` 的并发检测口径。
4. 台账回写 CAS —— 由 `relay-ledger.ps1` 机制化：回写前必须先 `-Action status` 取在盘 `sha256`，提交时用 `-ExpectSha256` 传入（锁外、锁内各比一次）。sha 陈旧 = 视图过期，直接被 `cas_conflict` 判死，只能重取 sha、重建 patch、重试一次。

## 自检（安装器自动跑）

- 三个 `.ps1`（锁 / 台账 / 起环驱动）的**非 ASCII 字节数 = 0**、**无 BOM**。
- 家规落点文件里 `BEGIN/END RELAY-PORT` 标记各 **1** 个（`claude-code` 是 `AGENTS.md` 与 `CLAUDE.md` 各一对 ⇒ 打两行 `AGENTS_MARKERS` / `CLAUDE_MARKERS`）。
- `relay-lock.ps1 -Action status` 可执行。
- `start-relay.ps1 -DryRun` 退出码 0（已有链在跑时是 3，只告警不判失败）。

结论落盘在 `<repo>\docs\relay\install-report.md`，控制台最后一行 `INSTALL_VERDICT=PASS`。

## 本仓库的开发件（不随 skill 发布）

真源仓库 `scripts\` 下有两个一键件，**只在仓库里跑**，不属于装进目标项目的东西，也不复制到全局 skill：

```powershell
# 一键自测（家规 1 的落地）：临时 git 仓库跑安装器/启动器/锁/台账/编码/逐字一致
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts\selftest.ps1 -EvidencePath "$env:TEMP\relay-selftest.log"
# 期望 exit 0 且日志 fail=0；改 tool\ 或 device\ 任何文件后必跑
```

它覆盖 ① fresh 仓（无家规无计划件）② 家规无 relay 字样（内容签名收编）③ 双 relay 节（歧义护栏）
④ `-PlanDoc` 解析链 5 个子用例 ⑤ 锁与并发 ⑥ `device\`↔`tool\templates\` 逐字一致 + 编码。
**不覆盖**真 `session_create` 起环 —— 日志里的 `MANUAL_STEP real_session_activation` 提醒那一环仍需人在目标项目内激活。

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts\publish-relay.ps1 -Direction publish   # 同步 + 复核 + 提示刷 manifest
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts\publish-relay.ps1 -Direction verify    # 只比对（exit 2 = 有漂移 / 3 = 找不到全局 skill 根 / 4 = 拷贝中断）
```

发布以**内容**为单位、不看目录形状：真源 `tool\SKILL.md` → 全局 `SKILL.md`，`tool\scripts\` / `tool\templates\` 整体镜像，
`tool\references\*.md|txt` 扁平到全局 `references\`；仓库 `scripts\` / `examples\` / `protocol\` 与根 `MANIFEST.txt` 不参与发布。
它会拒绝空源与缺装置件，并把 `device\` ↔ `tool\templates\` 逐字一致当作**发布前置条件**（不合格先 `Copy-Item tool\templates\<f> device\<f> -Force`）。
顺序固定：`selftest.ps1` → `publish-relay.ps1 -Direction publish` → `refresh-manifest.ps1`（清单必须最后，它包含自己）。

## 台账写闸门 `relay-ledger.ps1`

`docs\relay.json` 的回写不靠散文约束：闸门脚本是**唯一**允许的程序化写入口。

```powershell
# 1) 读在盘版本与它的 sha256（输出两行：LEDGER_STATE ... sha256=<64hex>，
#    以及 LEDGER_CHAIN ... cap_reached=<true|false|unknown> stages=<id:status,...|none>
#    all_done=<true|false|unknown> open_stages=<n|none>；阶段数与阶段列表同名不同义，靠行前缀区分）
pwsh -NoProfile -ExecutionPolicy Bypass -File '<repo>\docs\relay\relay-ledger.ps1' -Action status

# 2) 把本轮意图写成 ASCII JSON patch（放 docs\relay\ 下），只用追加式键：
#    stage_done / stage_fields / append_stage / sessions_append / notes_append /
#    ledger_docs_append / blocked_on_append / set_status / bump_current_stage / next_session_id

# 3) 先干跑（不落盘、不留锁）
pwsh -NoProfile -ExecutionPolicy Bypass -File '<repo>\docs\relay\relay-ledger.ps1' -Action commit -ExpectSha256 '<64hex>' -Patch '<repo>\docs\relay\p.json' -DryRun

# 4) 提交 => LEDGER_COMMITED before=<旧 sha> after=<新 sha>
pwsh -NoProfile -ExecutionPolicy Bypass -File '<repo>\docs\relay\relay-ledger.ps1' -Action commit -ExpectSha256 '<64hex>' -Patch '<repo>\docs\relay\p.json'
```

机制四层：① 写锁 `docs\relay\.ledger.lock`（`FileMode.CreateNew`，超 `-LockStaleSeconds` 可接管）；② CAS —— `-ExpectSha256` **必传**，锁外锁内各比一次，陈旧视图必被判死；③ 只追加不变式 —— `stages` / `sessions` / `notes` / `ledger_docs` / `blocked_on` / `human_checkpoints` / `stop_conditions` 只许追加，改写别人的条目直接拒；④ 写后回读 —— 写临时文件 + `Move-Item -Force` + 逐字比对后才报 `LEDGER_COMMITED`。

退出码：`0` 提交或干跑通过（`doctor` 干净、`migrate-hint` 无建议也返回 `0`）/ `2` 参数与 patch 键非法（含 `commit` 未带 `-ExpectSha256`、`stage_fields` 未配 `stage_done`）/ `3` 拒绝（CAS 冲突、规则违反、台账缺文件；`doctor` 有 findings、`migrate-hint` 有建议也返回 `3`）/ `4` 锁超时 / `5` patch 不可解析。

- **动作只有 `status`、`commit`、`doctor` 与 `migrate-hint`**，没有 `-Action blocked` 这类便捷动作；blocked 状态由 patch 里 `set_status` + `blocked_on_append` 表达。
- **体检用 `doctor`（R4，只读）**：`-Action doctor` 不取锁、不建目录、不写一字节（连临时文件都不留），只把「盘上可判的自相矛盾」逐条打成 `DANGLING …`：`status` 不在 `running|pending|done|blocked`、`current_stage` 非整数、`current_stage > max_stages`、`current_stage` 在 `stages[]` 里找不到（`stages` 为空时跳过，避免启动器自举误报；stage 身份键优先取 `id`，缺失时回退老台账用的 `stage`，两者都无则逐个报 `stage_index=<i> reason=stage_id_missing` 且不计入重复）、同一 stage id 重复（只报一次，带 `count=<n>`）、`next_session_id` 非空但 `status≠running`（`dead_pointer`）、`blocked` 却没有 `blocked_on`、`done` 却还有未完成阶段。首行 `DOCTOR_STATE path=… sha256=… …`（就是它实际读到的那个），末行 `DOCTOR_VERDICT ok findings=0` 或 `DOCTOR_VERDICT dangling findings=<n>`。**它不猜**：会话是否已被归档需要问宿主，doctor 不编 `session_archived` 结论。
  ```powershell
  pwsh -NoProfile -ExecutionPolicy Bypass -File '<repo>\docs\relay\relay-ledger.ps1' -Action doctor
  ```
- **旧 schema 只给建议、不迁移（R6，只读）**：`-Action migrate-hint` 与 `doctor` 问的不是同一个问题 —— `doctor` 查「台账自相矛盾」，`migrate-hint` 查「形状会让闸门行为变样」：`max_stages` 不是整数（阶段上限无法比较，`item=stage_max_unknown`）、`stages[]` 的身份键不是 `id`（`commit` 只按 `id` 解析 `stage_done`，这类阶段永远关不掉，`item=stage_key_not_id rename_to=id`）、阶段既无 `id` 也无 `stage`（`item=stage_id_missing keys=…`）、阶段状态不在 `pending|in_progress|done`（`set_status=done` 会永远被拒，`item=stage_status_unknown`）。首行 `MIGRATE_STATE path=… sha256=… stages=<n> max_stages=<raw|(none)>`，每条建议一行 `MIGRATE_HINT scope=… item=…`，末行 `MIGRATE_VERDICT none hints=0`（exit 0）或 `MIGRATE_VERDICT suggested hints=<n>`（exit 3）。**它只报不改**：迁移 `docs\relay.json` 是人决定的动作，本动作不取锁、不建目录、不写一个字节。
**B32 起老台账可以直接用**：`commit` 认得阶段键叫 `stage` 的老台账 —— 先按 `id` 匹配，认不到再按旧键 `stage` 唯一匹配；旧键**不改名**、老台账一个字节都不动；新旧同号时以带 `id` 的阶段为准，两个同号候选一律不认（`stage_not_found`）。缺 `ledger_docs` / `human_checkpoints` / `stop_conditions` 这类数组**不报** —— `commit` 追加时会自动创建，报了只会让每个老台账全红。
  ```powershell
  pwsh -NoProfile -ExecutionPolicy Bypass -File '<repo>\docs\relay\relay-ledger.ps1' -Action migrate-hint
  ```
- **一次扫多本台账（B30，只读）**：`-LedgerPaths` 收多个台账 —— 单参数逗号 / 分号分隔（`-LedgerPaths a.json,b.json`），或 PowerShell 里直接给数组。每本一行 `MIGRATE_SCAN path=… readable=true sha256=… stages=… max_stages=… hints=<n>`，其建议行写成 `MIGRATE_HINT path=<该台账> scope=… item=…`，末行 `MIGRATE_SCAN_VERDICT ledgers=<n> hints=<n> unreadable=<n>`；**hints>0 或 unreadable>0 ⇒ exit 3，否则 exit 0**。缺文件 / 不可解析的台账只回 `readable=false reason=…` 并计入 `unreadable`，**不中断其余台账** —— 搬装时一次扫十个项目，不该因为其中一个是空目录就整批无结论。单台账模式（`-LedgerPath` 或默认路径）的输出与退出码逐字不变。
  ```powershell
  pwsh -NoProfile -ExecutionPolicy Bypass -File '<repo>\docs\relay\relay-ledger.ps1' -Action migrate-hint -LedgerPaths 'D:\a\docs\relay.json,E:\b\docs\relay.json'
  ```
- **身份键与计数（B30）**：① `stage_fields` 是唯一绕过规则循环的写入通道，因此 `id` / `stage` 在 `stage_fields` 里出现即拒（exit 2 `stage_fields_rewrites_identity`）—— 改写身份键会让 `current_stage` 指向一个已不存在的阶段号；② `append_stage.id` 与 `bump_current_stage` 时的 `current_stage` 必须可解析为整数，否则 exit 2（`append_stage_id_not_an_integer` / `current_stage_not_an_integer`），不再以未捕获的转换异常退出 1；③ `sessions[]` 判重是**精确匹配**（字符串逐字比，对象先比 `session_id` 再比 `id`），子串命中不再算已登记 —— 旧逻辑把 `sess-abc` 当成 `sess-abc-long` 已登记，真跑过的那一环因此没进流水；④ 台账缺 `sessions` / `notes` 等数组时按 **0** 计（`@($null).Count` 是 1，旧实现会报 `sessions=1`）。`LEDGER_CHAIN` 与启动器 cap 行的阶段身份统一为 `id` → `stage` → `#<序号>` 三级回退，两侧逐字同形。
- **会话流水由闸门兜底（F6）**：`stage_done` 提交时，闸门自己把本环会话 ID 登记进 `sessions[]` —— 先取 `stages[N].session_id`，没有就取台账里的 `next_session_id`（那正是当前在跑的那一环，**且只在链仍为 `running` 时回落** —— `blocked` / `done` 的链上它只是遗留值，此时回显 `LEDGER_SESSION_SKIPPED stage=… reason=chain_not_running status=…` 并且不动 `sessions[]`）；只追加、不改写、已登记过的不重复。⇒ 环忘了写 `sessions_append` 也不会留下空会话流水（B13 真链终态 `sessions=[]`，本条为此新增）；两个来源都没有时回显 `LEDGER_SESSION_SKIPPED reason=no_session_id`，**不编造**会话 ID。
- `set_status: "running"` 是**人类专用**（起链时由人写入），会话侧提交一律被拒。
- **状态机（R3）**：`set_status` 只接受 `pending` / `done` / `blocked`（其余值 `exit 2 status_not_allowed`）；`done` 要求所有 `stages[].status` 都是 `done`，否则 `exit 3 status_done_but_stages_open open_stages=…`；`blocked` 要求 `blocked_on` 非空，同一 patch 里带 `blocked_on_append` 即合法，否则 `exit 3 status_blocked_without_blocked_on`。
- **`next_session_id` 按「键在不在」处理**：键缺省 = 不动；键存在但值为 `""` / `null` = 清空（回显 `LEDGER_NEXT_SESSION_CLEARED before=… after=(empty)`）；非空 = 写值（`LEDGER_NEXT_SESSION_SET`）。停链配方「`set_status=blocked` 且 `next_session_id` 为空」依赖这一条把旧 id 真正撤掉 —— 修前空值被静默丢弃。
- 正常收尾与停链分支（blocked / done）一律走闸门，不许手工编辑 `docs\relay.json`。
- 脚本按 `$PSScriptRoot\..\..` 推仓库根，所以它**必须**放在 `<repo>\docs\relay\` 下才能跑。

## 边界

- 安装器**不碰** `docs\relay.json`、不碰 `apps/**`、`packages/**` 等产品代码，不改门禁脚本。
- `.ps1` 一律纯 ASCII、无 BOM；仓库 Markdown 一律 LF。
- 装置的 `start-relay.ps1` / `relay-lock.ps1` / `relay-ledger.ps1` / `relay-spawn.ps1` 与 `tool\templates\`、`device\` 两侧**逐字一致**（sha16 见 `templates/`），`publish-relay.ps1` 按硬不变式判定，漂移 exit 2。项目差异一律落在参数与 `RELAY-ADAPTATION.md`，不改脚本本体。
## 锁的凭据与 TTL（B31）

- `prespawn` 发行一次性 permit（nonce 16 hex，TTL 300s）；`verify -SessionId <id> -Nonce <nonce>` 的 **nonce 必填**，缺则 `PERMIT_INVALID reason=nonce_required`（exit 6）。
- `adopt -SessionId <id> -Nonce <nonce>` 必须先有未消费的 permit 且 nonce 匹配，否则 `LOCK_REFUSED reason=permit_required|nonce_required|nonce_mismatch|permit_consumed|permit_expired`（exit 3）；停止哨兵存在时 `LOCK_REFUSED reason=chain_stopped`（exit 3）。CLI 运行时由 `relay-spawn.ps1` 先 `prespawn` 再 `adopt -Nonce`。
- TTL 优先级：显式 `-TtlSeconds` > 锁内记录值 > `relay-runtime.json` 的 `lock_ttl_seconds` > 1800；输出带 `ttl_source=`。启动器与安装器的 `-TtlSeconds` 都是字符串参数，非整数或越界 ⇒ `FAIL reason=ttl_invalid`（exit 2），不会走到绑定器的 exit 1。
- 锁文件读不出内容、或心跳落在未来 ⇒ 按「不可证明存活」接管并保留 `.stale.<epoch_ms>`；`status` 打印 `LOCK_STATE state=UNREADABLE`。
