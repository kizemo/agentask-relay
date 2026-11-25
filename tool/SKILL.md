---
name: relay-port
description: Install the unattended relay (auto-advance) kit into any git project so that a single prompt can start a continuous, self-advancing session chain with one-writer-per-project locking. Use when the user asks to 给别的项目装自动接力/自动推进装置, 把接力链搬到别的项目, port the relay kit to another repo, or make unattended auto-advance available in another project.
---

# relay-port —— 把「无人值守接力链」装置装进任意项目

一次性安装，之后**只要一句 Prompt** 就能在目标项目内启动连续接力任务。

## 它装了什么

| 目标路径 | 作用 |
|---|---|
| `<repo>\docs\relay\start-relay.ps1` | 启动器：工作区校验 + 并发闸门 + 取锁 + 台账初始化（只新建不覆写）+ 生成接力 prompt |
| `<repo>\docs\relay\relay-ledger.ps1` | 台账写闸门：写锁 + CAS(`-ExpectSha256`) + 只追加不变式 + 写后回读；动作只有 `-Action status` / `-Action commit`，`-DryRun` 可先验 |
| `<repo>\docs\relay\relay-lock.ps1` | 互斥锁：`FileMode.CreateNew` 原子创建，保证一个项目同时只有一个写会话 |
| `<repo>\docs\relay\relay-spawn.ps1` | 起环驱动（**仅 CLI 运行时用**）：把接力 prompt 交给 `claude -p` / `codex exec` 无头子进程，取回会话 id 并转交锁；默认只干跑，加 `-Execute` 才真跑。子进程在**链仓工作目录**内启动（`--add-dir` 只放宽权限、不改 cwd），权限模式默认 `bypassPermissions`（无人值守不提问），原始输出落盘 `docs\relay\relay-spawn-output\`。**铁律**：`claude` 的所有旗标必须写在 prompt **之前**，prompt 放最后，否则整批旗标被丢弃（拿不到 JSON、`session_id` 丢失、模式回落 `default`）；配方与实测见 `references/claude-code-permissions-2026-11-25.md` |
| `<repo>\docs\AGENT-RELAY.md` | 通用协议（自包含、仓库相对路径，可直接搬） |
| `<repo>\docs\RELAY-SOP.md` | 操作规程 |
| `<repo>\docs\RELAY-ADAPTATION.md` | **本项目裁决骨架**（写集 / 门禁 / 模型策略）；首次运行自动探测默认值 + 生成提问包，答案经 `-AnswersFile` 回填（见「装完之后必须做的两件事」） |
| `<repo>\AGENTS.md` | 受管家规块 `<!-- BEGIN RELAY-PORT -->`（幂等注入，不重复、不覆盖项目自己写的规则） |
| `<repo>\docs\plan-relay.md` | 计划文档（未指定 `-PlanDoc` 且未探测到既有计划时自动生成） |
| `<repo>\docs\relay\ACTIVATION-PROMPT.txt` | **激活包**：起链的四步命令 + 一句话激活语 |
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
- `-Runtime` 指定目标会话跑在哪个运行时上（默认 `mcode`）。它同时决定**家规落到哪些文件**与**下一环怎么起**，见下面「运行时适配」。不认识的运行时响亮失败（`FAIL reason=runtime_unsupported`，退出码 `2`），不静默退回默认。
- `-PlanDoc` 省略时会自动探测 `docs\plan-*.md` / `docs\plans\*.md` / `docs\superpowers\plans\*.md`；探测到多份会告警（`WARN plan_doc_ambiguous`）并退回新建 `docs\plan-relay.md`。**安装器是唯一允许创建计划文档的地方**，启动器只解析、绝不创建（见「装置契约」）。
- `-AnswersFile` 把用户对三项裁决（写集 / 门禁 / 模型）的答案回填进 `docs\RELAY-ADAPTATION.md`：解析答案 → 逐键覆盖探测值 → **只重写 §3/§4/§5**（§6 之后的手改内容不丢）→ 打印 `ADAPT_CHECK doc=… placeholders=N source=answers`。答案文件缺失 / 解析失败 / 为空分别 `FAIL reason=answers_file_missing|answers_file_unparsable|answers_file_empty`，退出码 `2`。
- **幂等**：重复执行不产生重复家规块、不覆盖项目自己改过的文件（`SKIP ... kept`）。要强制覆盖用 `-Force`。装完看见 `ADAPT_CHECK ... placeholders=0` 即表示 §3/§4/§5 既无残留 `TODO`、也无未替换占位符。
- 已有未受管的接力家规时**收编**（adopt）该段并加标记，不追加第二份。收编判据是双层的：
  1. 标记块已存在 → `present_kept`；
  2. 标题命中「接力 / relay / 自动推进」→ `reason=title` 包裹收编；
  3. 标题不含关键词时按 **内容指纹**打分（`relay.json` / `relay-lock` / `start-relay` / `session_create` / `in_progress` / `max_stages` / `next_session` / `awaiting_user` / 接力 / relay），**单节命中 ≥4 条**即包裹收编（`reason=content_signature`）；
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

激活包 `docs\relay\ACTIVATION-PROMPT.txt` 里写死了四步：跑启动器 → `session_create` 开第一环 → `relay-lock.ps1 -Action adopt` 转交锁 → `session get` 回读校验。目标项目会话照做即可。

## 装置契约（实测可用）

```powershell
# 启动器（-PlanDoc 可省）
pwsh -NoProfile -ExecutionPolicy Bypass -File '<repo>\docs\relay\start-relay.ps1' -Target '<批次>' -MaxStages 6
# 退出码 0 可起链 / 2 工作区非法、不是 git 仓库、计划文档解析不出来（plan_doc_missing / plan_doc_not_found）/
#         3 已有链在跑或台账 blocked、耗尽 / 4 锁拿不到
# 干跑（只校验不起链）
pwsh -NoProfile -ExecutionPolicy Bypass -File '<repo>\docs\relay\start-relay.ps1' -Target '<批次>' -DryRun

# 互斥锁
pwsh -NoProfile -ExecutionPolicy Bypass -File '<repo>\docs\relay\relay-lock.ps1' -Action status
pwsh -NoProfile -ExecutionPolicy Bypass -File '<repo>\docs\relay\relay-lock.ps1' -Action acquire -SessionId '<sid>' -Stage 1 -Title 'relay-1' -TtlSeconds 1800
pwsh -NoProfile -ExecutionPolicy Bypass -File '<repo>\docs\relay\relay-lock.ps1' -Action renew  -SessionId '<sid>'
pwsh -NoProfile -ExecutionPolicy Bypass -File '<repo>\docs\relay\relay-lock.ps1' -Action adopt  -SessionId '<new sid>'
pwsh -NoProfile -ExecutionPolicy Bypass -File '<repo>\docs\relay\relay-lock.ps1' -Action release -SessionId '<sid>'

# 起环驱动（仅 CLI 运行时 claude-code / codex；默认只干跑，加 -Execute 才真跑）
pwsh -NoProfile -ExecutionPolicy Bypass -File '<repo>\docs\relay\relay-spawn.ps1' -Runtime claude-code -PromptFile '<repo>\docs\relay\next-relay-prompt.txt' -WorkspaceDir '<repo>'
pwsh -NoProfile -ExecutionPolicy Bypass -File '<repo>\docs\relay\relay-spawn.ps1' -Runtime claude-code -PromptFile '<repo>\docs\relay\next-relay-prompt.txt' -WorkspaceDir '<repo>' -Execute -AdoptLock
```

起环驱动 `relay-spawn.ps1` 的退出码：`0` 建好命令（或起环成功且取到会话 id）/ `2` 参数非法、运行时不是 CLI 运行时、prompt 文件缺失或超 60000 字符 / `3` CLI 不存在、运行失败、锁转交失败 / `4` 跑完了但取不到会话 id。

**启动器的计划文档解析链**（在取锁**之前**跑完，所以失败不会留下活锁）：
`-PlanDoc` → 台账 `plan_doc` → 探测 `docs\plan-*.md` / `docs\plans\*.md` / `docs\superpowers\plans\*.md`。
唯一命中直接用（打印 `OK plan_doc=<相对路径> source=probe bytes=<n>`）；多命中告警 `plan_doc_ambiguous` 后按 mtime 取最新并列出候选；
零命中 `FAIL reason=plan_doc_missing` + `exit 2`，提示补 `-PlanDoc` / 台账 `plan_doc` / 新增 `docs\plan-<批次>.md` 三条出路。
解析出的相对路径会写进台账 `plan_doc`，之后每一环读的是同一个文件；**启动器绝不创建计划文档**（那是安装器的职责）。

起环参数（`session_create`）：只传 `agent_name` / `title` / `workspace_dir`（**反斜杠绝对路径**）/ `model` / `content`。
**禁止**传 `effort` / `defer_first_turn` / `parent_session_id`（schema 无此字段）。建环后立刻 `session get` 回读 `workspace_dir` / `effective_model` / `status` 三要素。

## 四道并发闸门

1. `FileMode.CreateNew` 原子锁 —— 抢不到就退出，不存在「两个会话同时写」。
2. 台账闸门 —— 有 `in_progress` 阶段 / `status=running` 且有 `next_session_id` / 台账 blocked 或耗尽 ⇒ 拒绝起链。
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
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts\publish-relay.ps1 -Direction verify    # 只比对（exit 7 = 有漂移）
```

发布以**内容**为单位、不看目录形状：真源 `tool\SKILL.md` → 全局 `SKILL.md`，`tool\scripts\` / `tool\templates\` 整体镜像，
`tool\references\*.md|txt` 扁平到全局 `references\`；仓库 `scripts\` / `examples\` / `protocol\` 与根 `MANIFEST.txt` 不参与发布。
它会拒绝空源与缺装置件，并把 `device\` ↔ `tool\templates\` 逐字一致当作**发布前置条件**（不合格先 `Copy-Item tool\templates\<f> device\<f> -Force`）。
顺序固定：`selftest.ps1` → `publish-relay.ps1 -Direction publish` → `refresh-manifest.ps1`（清单必须最后，它包含自己）。

## 台账写闸门 `relay-ledger.ps1`

`docs\relay.json` 的回写不靠散文约束：闸门脚本是**唯一**允许的程序化写入口。

```powershell
# 1) 读在盘版本与它的 sha256（输出 LEDGER_STATE ... sha256=<64hex>）
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

退出码：`0` 提交或干跑通过 / `2` 参数与 patch 键非法（含 `commit` 未带 `-ExpectSha256`、`stage_fields` 未配 `stage_done`）/ `3` 拒绝（CAS 冲突、规则违反、台账缺文件）/ `4` 锁超时 / `5` patch 不可解析。

- **动作只有 `status` 与 `commit`**，没有 `-Action blocked` 这类便捷动作；blocked 状态由 patch 里 `set_status` + `blocked_on_append` 表达。
- `set_status: "running"` 是**人类专用**（起链时由人写入），会话侧提交一律被拒。
- 正常收尾与停链分支（blocked / done）一律走闸门，不许手工编辑 `docs\relay.json`。
- 脚本按 `$PSScriptRoot\..\..` 推仓库根，所以它**必须**放在 `<repo>\docs\relay\` 下才能跑。

## 边界

- 安装器**不碰** `docs\relay.json`、不碰 `apps/**`、`packages/**` 等产品代码，不改门禁脚本。
- `.ps1` 一律纯 ASCII、无 BOM；仓库 Markdown 一律 LF。
- 装置的 `start-relay.ps1` / `relay-lock.ps1` / `relay-ledger.ps1` / `relay-spawn.ps1` 与 `tool\templates\`、`device\` 两侧**逐字一致**（sha16 见 `templates/`），`publish-relay.ps1` 按硬不变式判定，漂移 exit 2。项目差异一律落在参数与 `RELAY-ADAPTATION.md`，不改脚本本体。
