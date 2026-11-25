# 运行时可移植性分析：MCode / Claude Code / Codex CLI / OpenClaw

- 日期：2026-11-25
- 结论一句话：**四个运行时都能部署这套接力装置**，但「家规落在哪个文件」「下一环怎么起」两件事**因运行时而异**，所以本轮给装置加了 `-Runtime` 适配层。
- 证据口径：Claude Code / Codex CLI / OpenClaw 的行为来自 2026-11-25 的官方文档与源码查阅（不凭记忆）；本机只装了 Claude Code，`codex` 与 `openclaw` **未安装**，因此这两家的「真起链」属于**未实测**。

---

## 1. 装置原本假设了什么

未适配时，本装置假设目标会话跑在 **MCode 桌面端**，具体三条假设：

| 假设 | 体现在哪 | 别的运行时能不能满足 |
|---|---|---|
| 会话读 `AGENTS.md` | 家规块写进 `<repo>\AGENTS.md` | Codex CLI ✅ / OpenClaw ⚠️（见 §3.3）/ Claude Code ❌（见 §3.1） |
| 有内置 `session_create` 工具能开下一环 | 激活包 STEP 2 直接调 `mcp_invoke(session_create)` | 只有 MCode 有；其余三家都没有 |
| 下一环是**常驻会话**，自己会接着干活 | 台账 `next_session_id` 语义 | CLI 运行时的下一环是**跑完即退的无头子进程**，链要靠「本环再跑一次 spawn」推进 |

三条假设里，**第二条在三个 CLI 运行时上全不成立**，第三条在两个 CLI 运行时上不成立。这就是本轮扩展的全部动因。

---

## 2. 四家运行时能力对照

| 能力 | MCode | Claude Code | Codex CLI | OpenClaw |
|---|---|---|---|---|
| 规则文件 | `AGENTS.md` | `CLAUDE.md`（**只有仓库没有 `CLAUDE.md` 时才回退读 `AGENTS.md`**） | `AGENTS.md`（全局 `~/.codex/AGENTS.md` + 项目根向下，合并上限 32 KiB） | workspace 根的 `AGENTS.md`（子 agent 额外注入 `TOOLS.md`） |
| 起下一环的工具 | 内置 `session_create` | 无（用 CLI 子进程） | 无（用 CLI 子进程） | `sessions_spawn` 工具 |
| 无头/非交互跑法 | — | `claude -p "<prompt>" --output-format json` | `codex exec "<prompt>" --json` | gateway 常驻，靠 `sessions_spawn` |
| 会话 id 从哪来 | 工具返回值 | 输出 JSON 里的 `"session_id"`（也可用 `--session-id` 预置） | 输出 JSON 里的 `"thread_id"` | `sessions_spawn` 返回值 |
| 续跑上一环 | `session send` / `resume` | `--resume` / `--continue` / `--session-id` | `codex resume --last` / `codex exec resume` | 会话列表 + 续跑 |
| 沙箱 / 审批 | 运行时自管 | `--permission-mode`（如 `acceptEdits`） | `--sandbox workspace-write` + `-a never\|on-request` | agent 自带权限 |
| 规则文件体量限制 | 无特殊限制 | 无特殊限制 | 合并 32 KiB | 单文件 20,000 字符 / 总计 60,000 字符 |
| 本机是否已装 | ✅ 是（当前会话） | ✅ 是（`%USERPROFILE%\.local\bin\claude.exe`） | ❌ 否 | ❌ 否 |

---

## 3. 各家具体结论

### 3.1 Claude Code —— 能部署，但原装置会被**遮蔽**（真缺陷）

- Claude Code 的规则文件是 `CLAUDE.md`。**只有仓库里没有 `CLAUDE.md` 时，它才回退读 `AGENTS.md`**。
- 所以一个已经带 `CLAUDE.md` 的仓库装上原装置后：家规块被写进 `AGENTS.md`，但 Claude Code 根本不读它 ⇒
  **装完看着像成功，链永远起不来**。这是本次扩展修掉的主要缺陷。
- 修法：`-Runtime claude-code` 时**同时写 `AGENTS.md` 和 `CLAUDE.md`**，并对两份文件各打一行
  `AGENTS_MARKERS begin=1 end=1` / `CLAUDE_MARKERS begin=1 end=1` 复核判据。
- 另一个差异：Claude Code 没有 `session_create`。下一环用无头进程起：
  `claude -p "<prompt>" --output-format json --session-id <uuid> --add-dir <repo>`。
  本装置用 `--session-id` **预置**会话 id，所以即使输出里没有可解析的 `"session_id"`，id 也已知。

### 3.2 Codex CLI —— 能部署，规则文件天然兼容

- `AGENTS.md` 原生支持（全局 `~/.codex/AGENTS.md` + 从项目根逐级向下），**不需要双写**。
- 但没有 `session_create`。下一环用 `codex exec "<prompt>" --json`，**退出码即成败**（非 0 = 这一环失败）。
- 沙箱与审批要显式给：`--sandbox workspace-write -a never`。
- 注意规则体量：全局 + 各级合并上限 32 KiB，家规块远小于这个量，但**同一个仓库里不要堆多份接力家规**。

### 3.3 OpenClaw —— 能部署，但有一条**硬约束**

- OpenClaw 是常驻 gateway。每次新会话把 **workspace 根目录**的 `AGENTS.md` / `SOUL.md` / `IDENTITY.md` /
  `USER.md` / `BOOTSTRAP.md` / `MEMORY.md` 注入 system prompt；子 agent 只注入 `AGENTS.md` + `TOOLS.md`。
- **硬约束**：它只注入「它自己的 workspace 根目录」那份 `AGENTS.md`。
  所以目标仓库必须**就是**该 OpenClaw agent 的 workspace；不是的话，家规块必须先复制到 workspace 根的
  `AGENTS.md`，否则那块规则根本进不了 system prompt —— 链同样起不来。
- 起环用 `sessions_spawn` 工具（可以 `runtime:"acp"` 起 Claude Code 会话），不是 CLI 子进程，
  所以**不需要** `relay-spawn.ps1`；但锁转交仍然要手动跑 `relay-lock.ps1 -Action adopt`。
- 规则体量限制：单文件 20,000 字符、总计 60,000 字符 —— 家规块量级没问题。

### 3.4 MCode —— 原生路径不变

- 内置 `session_create` 工具，参数只有 `agent_name` / `title` / `workspace_dir` / `model` / `content`。
- `workspace_dir` 必须显式传**反斜杠绝对路径**；传正斜杠会落到私有 workspace，链就断在那儿。
- 下一环是常驻会话，链自转靠每环执行「起下一环 + 转交锁 + 回写台账」。

---

## 4. 本轮为此扩展了什么

### 4.1 安装器加 `-Runtime`

```
pwsh -NoProfile -ExecutionPolicy Bypass -File "<skill>\scripts\install-relay.ps1" `
  -RepoRoot "<仓库绝对路径>" -Target "<批次>" [-Runtime mcode|claude-code|codex|openclaw] ...
```

- 默认 `mcode`，**行为与扩展前逐字等价**（原有 selftest 全部照旧通过）。
- 不认识的运行时**响亮失败**：`FAIL reason=runtime_unsupported` + 退出码 `2`，不静默退回默认。
  （没用 `ValidateSet`：它的绑定失败退 1，与装置退出码约定不符。）
- 运行时同时决定两件事：**家规落到哪些文件** + **下一环怎么起**。

### 4.2 起环驱动 `relay-spawn.ps1`（新装置件）

- 位置：`<repo>\docs\relay\relay-spawn.ps1`（与 `tool\templates\` 里的同名件逐字一致）。
- 默认**只干跑**：打印将要执行的命令行（prompt 用 `<prompt from file>` 占位，不把几十 KB 的 prompt 塞进一行日志），**不跑任何东西**；加 `-Execute` 才真跑。
- prompt 从文件读（启动器写的 `docs\relay\next-relay-prompt.txt`），不过 shell 引号往返。
- 取会话 id：claude-code 从 `"session_id"` 正则提取，取不到就退回预置的 `--session-id`；codex 从 `"thread_id"` 提取。
- `-AdoptLock` 自动调同目录 `relay-lock.ps1 -Action adopt` 转交锁（这是唯一支持的转交方式）。
- 退出码：`0` 建好命令 / 起环成功且取到 id；`2` 参数非法、运行时不是 CLI 运行时、prompt 文件缺失或超 60000 字符；`3` CLI 不存在、运行失败、锁转交失败；`4` 跑完了但取不到会话 id。

### 4.3 激活包按运行时分片

`ACTIVATION-SPAWN-<runtime>.md` 四份，每份用 `<!-- SPAWN_RULE_BEGIN -->…<!-- SPAWN_RULE_END -->` 标出
**唯一真源**的一条起环规则；安装器正则抽出来注入到家规块 §A.5 与 `docs\RELAY-ADAPTATION.md` 第 9 节。
这样「家规块说怎么起环」和「激活包怎么做」不会各说各话 —— 改文案只改一处。

### 4.4 家规块与协议改成运行时中立

- 家规块 §A.5 从写死 `session_create` 改成「运行时 = `{{RUNTIME}}`，起环方式见 `docs\relay\ACTIVATION-PROMPT.txt`」；
  §B.9 改成「按 §A.5 的起环方式起下一环」。
- `docs\AGENT-RELAY.md` 增 §10「运行时适配」，§3 标注为「MCode 运行时专用」并指向 §10。

### 4.5 换运行时必须重装

`-Runtime` 变了以后，家规块、`docs\RELAY-ADAPTATION.md`、激活包三处都要跟着变 ⇒ **换运行时必须重装
（`-Force`）**，否则三处各说各话。这一点写进了 `RELAY-ADAPTATION.md` 第 9 节。

---

## 5. 已验证 / 推断 / 未验证

| 项 | 状态 | 依据 |
|---|---|---|
| `-Runtime claude-code` 双写 `AGENTS.md` + `CLAUDE.md`，两份各 `begin=1 end=1` | **已验证** | selftest case 16（`runtime_cc_*` 断言） |
| `-Runtime codex` 只写 `AGENTS.md`，不产 `CLAUDE.md` | **已验证** | selftest case 16（`runtime_cx_*`） |
| `-Runtime openclaw` 家规块注入 `sessions_spawn` 起环规则 | **已验证** | selftest case 16（`runtime_oc_*`） |
| 未知运行时 exit 2 + `reason=runtime_unsupported` | **已验证** | selftest case 16（`runtime_unknown_*`） |
| `relay-spawn.ps1` 干跑打印命令、不执行、prompt 不内联 | **已验证** | selftest case 16（`spawn_dryrun_*`） |
| `relay-spawn.ps1` 拒绝非 CLI 运行时 / 缺 prompt 文件 | **已验证** | selftest case 16（`spawn_rejects_*` / `spawn_missing_*`） |
| Claude Code 「有 `CLAUDE.md` 就遮蔽 `AGENTS.md`」 | **已查证**（官方文档） | 见 §3.1 |
| Codex CLI `codex exec` 退出码即成败、`--sandbox` / `-a` | **已查证**（官方文档） | 见 §3.2 |
| OpenClaw 只注入自己 workspace 根的 `AGENTS.md` | **已查证**（官方文档） | 见 §3.3 |
| Claude Code **真起链**（`claude -p` 跑完整链） | **未实测** | 本机有 `claude`，但未跑通完整链 |
| Codex CLI 真起链 | **未实测** | 本机未安装 `codex` |
| OpenClaw 真起链 | **未实测** | 本机未安装 `openclaw`；且 workspace 约束需按部署环境核对 |
| `-Runtime` 切回 `mcode` 后行为与扩展前完全一致 | **已验证** | selftest 原有 case 1–15 全绿 + case 16 的 `runtime_default_is_mcode` |

---

## 6. 部署指导在哪

- `tool\references\deployment-claude-code.md`
- `tool\references\deployment-codex.md`
- `tool\references\deployment-openclaw.md`

每份都是「装什么 → 装哪 → 怎么激活 → 怎么判成功 → 常见坑」五段式，命令可直接复制。
