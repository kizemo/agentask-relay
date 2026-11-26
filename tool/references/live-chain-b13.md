# B13 真链实录 —— 整链端到端：第 1 环写产物 → 台账 stage_done → 自举第 2 环（2026-11-26）

本文件是 B13 的原始留证索引：

| 留证 | 路径 |
|---|---|
| 门禁 raw 日志 | `tool\references\selftest-2026-11-26.txt` |
| 门禁小结 | `tool\references\selftest-2026-11-26.md` |
| 真链 stdout（安装 ×2 + 起链 + spawn） | `tool\references\live-chain-b13-stdout.txt` |
| 最终台账全文 | `tool\references\live-chain-b13-ledger-final.txt` |
| 两环产物 + 锁状态 + 链尾 prompt | `tool\references\live-chain-b13-artifacts.txt` |
| 三份 prompt（HEAD mcode / 新 mcode / 新 cli） | `tool\references\live-chain-b13-prompts.txt` |
| 第 1 环实际收到的 prompt | `tool\references\live-chain-b13-prompt-stage1.txt` |
| 子环会话记录（2 份） | `tool\references\live-chain-b13-transcript-1.txt` / `-2.txt` |

---

## 1. 为什么要有 B13（B10 留下的缺口）

B10 把 Claude Code 的权限层与命令行形状钉死了，但**整链从来没有跑过**：
B10 的「验证到哪一步」明写「只验到单次 CLI 调用被正确喊起来」。
链的三个关键动作——**写产物 → 台账 `stage_done` → 自举下一环**——一次都没在真链上跑过。

B13 的目标：在**干净真链仓**（临时 git 仓 + 真实安装 + 真实 `claude` 子进程）里
把「第 1 环 → 产物 → `stage_done` → 第 2 环 → 收尾」整条跑通，并把结论回填进本仓库。

---

## 2. 夹具与环境

| 项 | 值 |
|---|---|
| 夹具仓 | `C:\Users\Duanyi\AppData\Local\Temp\relay-b13-e2e2-20261126-153941\repo` |
| git HEAD | `08e6009`（3 个跟踪文件：`docs\plan-b13.md` / `README.md` / `src\inventory.ps1`） |
| 运行时 | `claude-code`（`claude` 999.0.0-local，`C:\Users\Duanyi\.local\bin\claude.exe`） |
| 计划文档 | `docs\plan-b13.md`（写明 `max_stages=2`，第 2 环提交后不再起链） |
| 阶段清单 | `-StageTitles '1. inventory tracked files into docs\relay\stage-1-inventory.md;2. summarize into docs\relay\stage-2-inventory.md'` |

夹具仓是从上一轮（修复前）的真链仓**克隆后清干净**得到的：`docs\relay\` 与 `docs\relay.json`
全部删除、锁文件删除，git 提交保持 `08e6009`。适配答案文件（8 项，取工具自身探测默认值）
沿用上一轮的那一份，避免二次提问。

---

## 3. 跑法（四步）

```powershell
# 1) 安装（首跑：适配状态 pending）
install-relay.ps1 -RepoRoot <repo> -Target '...' -PlanDoc 'docs\plan-b13.md' `
  -StageTitles '<两条阶段>' -MaxStages 2 -Runtime claude-code
# 2) 把适配答案写进 <repo>\docs\relay\adaptation-answers.json，再装一次（状态 confirmed）
install-relay.ps1 ... -AnswersFile <repo>\docs\relay\adaptation-answers.json
# 3) 起链（写台账 + 写下一环 prompt + 取锁）
<repo>\docs\relay\start-relay.ps1 -Target '...' -MaxStages 2
# 4) 真起第 1 环（子进程跑 claude；第 2 环由第 1 环自己起）
<repo>\docs\relay\relay-spawn.ps1 -Runtime claude-code `
  -PromptFile <repo>\docs\relay\next-relay-prompt.txt -WorkspaceDir <repo> -Execute -AdoptLock
```

安装首跑 `INSTALL_VERDICT=PASS` / `ADAPTATION_STATUS=pending` / `WARN_COUNT=1`
（`adaptation_defaults_unconfirmed`）；二跑 `ADAPTATION_STATUS=confirmed` /
`ADAPTATION_SOURCE=answers` / `WARN_COUNT=0` / `ADAPT answers=… applied=8/8`。

---

## 4. 真链结果（逐环，全部盘上回读）

### 4.1 起链

```
OK runtime=claude-code source=descriptor
OK link_mode=cli_driver chain_session_id=b47a9c35-c96a-4b13-b501-27b7463c431f
OK stage_titles source=descriptor          ← 阶段清单从描述符取到（修复前恒为通用清单）
OK plan_doc=docs\plan-b13.md source=probe bytes=1087
OK ledger_bootstrapped path=…\docs\relay.json bytes=2086
OK prompt_written path=…\docs\relay\next-relay-prompt.txt bytes=5989
DONE exit=0
```

### 4.2 第 1 环

- 会话 id `b47a9c35-c96a-4b13-b501-27b7463c431f`（= 驱动命令行里的 `--session-id`）
- 锁转交：`LOCK_ADOPTED holder=b47a9c35-… prev_holder=start-relay:296240 stage=1`，
  `SPAWN_LOCK_PRE_ADOPTED session_id=b47a9c35-…`
- 产物：`docs\relay\stage-1-inventory.md`（745 B）
- 台账：`stage_done=1` + `bump_current_stage` + `next_session_id=4dcfed63-…`
  （两段 CAS：先 dry-run，再用回读到的 sha 提交）
- 下一环 prompt：子环自己把 `next-relay-prompt.txt` 改成 `RELAY_STAGE=2` /
  `RELAY_SESSION_ID=4dcfed63-…`，并用 spawn 驱动自举第 2 环
- 台账回写：`stages[1].status=done`，`tool_calls=23`，`finished_at=2026-11-26T15:43:42`

### 4.3 第 2 环

- 会话 id `4dcfed63-ffb5-41d4-a2fe-d560129ae073`
- 产物：`docs\relay\stage-2-inventory.md`（608 B）
- 台账：`stage_done=2`，`stages[2].status=done`，`tool_calls=12`，
  `finished_at=2026-11-26T15:47:21`
- 锁：终态 `LOCK_ABSENT`（子环释放了锁）

### 4.4 终态台账

```
status=blocked   current_stage=3   max_stages=2
stages=2（两条均 status=done）   notes=1   blocked_on=1   sessions=[]
```

`notes[0]` 原文（节选）：

> stage 2 done by session 4dcfed63-…: docs/relay/stage-2-inventory.md written …
> Gate green before write-back: LEDGER_STATE status=running sha256=A6C97CD1…
> Chain stop per AGENTS.md CLAUDE.md B.11: current_stage 3 > max_stages 2 -> status=blocked,
> no next link spawned. Lock released. Pending human checkpoint (RELAY-ADAPTATION section 6):
> git commit of stage-2 artifact + ledger write-back.

`blocked_on[0]`：「stage budget exhausted (max_stages=2 reached, chain complete as designed);
handoff awaiting human git commit」

**没有起第 3 环、没有卡死、没有残留锁** —— 链按设计收尾。

---

## 5. 真链暴露的事实（4 项 + 2 项新发现）

### 5.1 缺陷 D1：CLI prompt 里的 Windows 反斜杠路径会被真 bash 吃掉（**已修**）

Claude Code 的 Bash 工具是**真 bash**。prompt 的「命令风格」规则强制用 Bash 工具，
示例却写 Windows 路径：`docs\relay\relay-ledger.ps1` 在 bash 里变成
`docsrelayrelay-ledger.ps1`，**exit 64「无法识别为脚本文件名」**。

上一轮（修复前）真链里子环因此**丢了两条命令**；这一轮（修复后）**子环工具调用零错误**：

| 真链 | Bash 命令失败 | 子环工具错误数 |
|---|---|---|
| 修复前 | 2 条（exit 64） | ≥2 |
| 修复后 | 0 | **0**（transcript 里 `is_error` 计数 = 0） |

修法：CLI 运行时下，**prompt 里所有路径统一走正斜杠**（`$pathSep` 抽象）：
WORKSPACE 行、必读文件清单 8 条、RULES 里的 `docs/relay.json` / `docs/relay/.relay.lock` /
`docs/relay/.ledger.lock`、台账配方、交接规则里的 `next-relay-prompt.txt` 与产物名、
以及 spawn 命令。实测修复后 CLI prompt **反斜杠计数 = 0**，正斜杠 relay 引用 19 处。

### 5.2 缺陷 D2：`-StageTitles` 从未传到启动器（**已修**）

安装器收了 `-StageTitles`，但描述符 `docs\relay\relay-runtime.json` 里没有这个字段，
启动器拿不到 ⇒ prompt 的 `STAGE PLAN` 永远是写死的 `1. stage 1 scope inventory`，
**多环链每一环都显示「stage 1」**（子环是从 `RELAY-ADAPTATION.md` 的 Stages 段读到真阶段名的）。

修法（两段式，保住 mcode 兼容）：

1. 描述符新增 `stage_titles` 字段，**只有用户显式传 `-StageTitles` 时才带**；
   不传就不带 ⇒ 未配置阶段的既有安装，mcode 的 prompt **逐字不变**。
2. 启动器新增阶段清单解析，优先级：`-StageTitles` 参数 > 台账 `stage_titles` >
   描述符 `stage_titles` > 默认；回显 `OK stage_titles source=descriptor`。

实测：`DESCRIPTOR_STAGE_TITLES` 带真清单，启动器 `OK stage_titles source=descriptor`，
prompt 的 `STAGE PLAN` 是两条真阶段，通用清单 `1. stage 1 scope inventory` **不再出现**。

### 5.3 事实 D3：B10 记的「原生 PowerShell 工具恒报 malformed syntax」**本轮未复现**

本轮子环用了 **16 次原生 PowerShell 工具，0 错误**（另有 Bash=1 / Read=16 / Write=5 /
Edit=1 / Glob=1，全部 `is_error=false`）。B10 的那条结论在本机 build 上不成立，
**不要**把「PowerShell 工具不可用」当既成事实。

### 5.4 事实 D4：`--session-id` 在本 build **被遵守**

transcript 文件名就是传入的链 session id：
`b47a9c35-c96a-4b13-b501-27b7463c431f.jsonl` / `4dcfed63-ffb5-41d4-a2fe-d560129ae073.jsonl`。
与 B10 记的「部分版本不遵守」不同。装置的设计**不依赖**这个行为（链 id 由装置分配），
但真链里它可被观测 ⇒ 记一笔。

### 5.5 新发现 F5：终态是 `status=blocked`，不是 `status=done`

修复前那一轮终态是 `status=done` / `current_stage=2`；本轮是
`status=blocked` / `current_stage=3`。原因：prompt 的交接规则让**每一环**都 `bump_current_stage`，
第 2 环因此把计数顶到 3；而装置自己的 `stop_conditions` 写着
「`current_stage >= max_stages -> status=blocked`」⇒ 子环照章办事。

**判断**：这是**语义瑕疵，不是功能缺陷**。链确实跑完了（两环 done、产物齐、锁释放、没起第 3 环），
`blocked_on` 里也写明了「阶段预算耗尽、链已完成、等人做 git commit」；
启动器对 `blocked` 与 `done` 同样拒绝再起链（安全行为一致）。
但字面 `blocked` 会被读成「需要人决策」，而启动器另有 `status=done && current_stage >= max_stages`
⇒ `chain_exhausted` 的判据，两处口径不一致。

**本轮不改**：改它要么动 mcode prompt（违反 B10 的「mcode prompt 逐字不变」约束），
要么只改 CLI 分支（让 mcode 与 CLI 语义分叉）。留作下一批候选，见
`HANDOFF.md`「批次 B13 实录 → 遗留候选」。

### 5.6 新发现 F6：台账 `sessions[]` 这次是空的

终态 `sessions=[]`，而 `stages[].session_id` 有值（两环各一个）。
说明「会话记录」不是装置强制的，是子环自选的 patch intent：
修复前那轮用了 `sessions_append`（`sessions=2`），本轮只用了 `stage_done`。
信息没丢（`stages[].session_id` 有），但**台账里没有独立的会话流水**。
若要让台账天然可审计，下一批可考虑让 `stage_done` 顺带登记会话。

---

## 6. 修复后重跑（决定性证据）

最终留证**全部来自修复后的安装件**，不是修复前那次运行：

| 证据 | 修复前那一轮 | 修复后这一轮（本文件） |
|---|---|---|
| CLI prompt 反斜杠 | 多处（必读清单 / RULES / 台账配方） | **0** |
| 阶段清单 | 恒为 `1. stage 1 scope inventory` | 真清单（描述符带下来） |
| 子环工具错误 | ≥2（exit 64） | **0** |
| 第 1 环工具调用 | 28 | 23 |
| 第 2 环工具调用 | 10 | 12 |
| 产物 | 两份都写了 | 两份都写了（745 B / 608 B） |
| 终态 | `done` / `current_stage=2` / `sessions=2` | `blocked` / `current_stage=3` / `sessions=[]`（见 F5、F6） |
| mcode prompt | —— | **与 `git HEAD` 渲染逐字节相同** |

---

## 7. mcode 兼容证明（B10 的硬要求）

B10 要求「未配置阶段的既有安装，mcode prompt 逐字不变」。本轮用同一临时仓分别渲染：

- `git show HEAD:tool/templates/start-relay.ps1`（修复前的 launcher）
- 工作区的 `tool\templates\start-relay.ps1`（修复后的 launcher）

两份 mcode prompt **逐字节相同**（`MCODE_PROMPT_BYTE_IDENTICAL=True`），
三份原文见 `live-chain-b13-prompts.txt`。
CLI prompt 则完全相反：`CLI_PROMPT_BACKSLASH_COUNT=0`。

---

## 8. 遗留（下一批候选，本轮未做）

1. **终态语义**：链跑完却落 `status=blocked`（F5）。候选改法：prompt 的交接规则里
   「`current_stage >= max_stages` 时不要 bump，改置 `status=done`」。
   代价：会动 mcode prompt ⇒ 需要同时决定是否放弃「mcode prompt 逐字不变」这条约束。
2. **台账会话流水**：`sessions[]` 空（F6）。候选：`stage_done` 自动登记会话。
3. **codex / openclaw 真链仍未实测**（本机未安装 codex；openclaw 无对应 CLI）。
4. **git 写操作仍是人工验收点**：本轮两环产物与台账回写都留在工作树里，
   子环按家规停链等人 commit（`blocked_on` 里写明了这一点）。
