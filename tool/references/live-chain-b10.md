# B10 真链实录 —— Claude Code 无人值守接力（2026-11-25）

本文件是 B10 的原始留证：`selftest-2026-11-25o.txt` 是门禁 raw 日志，
`live-chain-b10-stdout.txt` 是真链驱动 stdout，`live-chain-b10-transcript-*.txt`
是真链子环的 Claude Code 会话记录。

---

## 1. 为什么要有 B10

B9 把「运行时适配层」装进了 kit：安装器知道运行时、家规落到哪些文件、
起环驱动 `relay-spawn.ps1` 存在。但**启动器自己还写死 MCode**：
`tool/templates/start-relay.ps1` 生成的下一环 prompt 直接喊 `session_create`。

于是 claude-code / codex 的链是**装配全对、第一棒交接断掉**：
前面所有零件都装好了，交接那一步没有可执行的东西。

B10 补的就是这一段，并且**真跑一条 Claude Code 链**把它验住。

---

## 2. 第一条真链暴露的三个缺陷

### 2.1 驱动没切工作目录（子环跑在错误的仓库里）

`relay-spawn.ps1` 用 `--add-dir <WorkspaceDir>` 把活链仓加进权限范围，
但**没有把子进程的工作目录切过去**。headless CLI 的工作目录来自进程本身，
`--add-dir` 只放宽权限、**不改 cwd**。

实测后果（第一次真链，session `657c00d0-7b31-40a4-a95d-993646a7a9d2`）：
子环的 cwd 是 `F:\soft\00selfmade\agentask-relay`（驱动被调用时所在目录），
于是它 tail 了工具仓库的 selftest 日志、跑了工具仓库的 `git diff --stat`，
最后因为拿不到活链仓的 prompt 与台账而放弃，**一个产物都没写**，
而驱动照样报 `RELAY_SPAWN_OK`。

修法：跑前 `Set-Location -LiteralPath $WorkspaceDir`，跑完在 `finally` 里恢复。

### 2.2 权限模式会向一个不在场的人提问

驱动默认 `-PermissionMode acceptEdits`。acceptEdits 只自动接受**文件编辑**，
**每一次 Bash 仍然要等人批准**；无头场景下没有人，于是 Bash 全被拦。

更隐蔽的是：这台机器的 `~/.claude/settings.json` 里 `defaultMode` 本来就是
`bypassPermissions`，是驱动的**显式参数把它覆盖掉了**。

同时 `settings.json` 里还有 `autoQuestion.enabled=true`：子环走到歧义处会调
`AskUserQuestion`，无头场景下这一等就是 5 分钟。

修法：默认 `-PermissionMode bypassPermissions`（无人值守链不该等人），
并给 claude-code 追加 `--settings '{"autoQuestion":{"enabled":false}}'`。

### 2.3 prompt 里没有 session id，子环没法释放自己的锁

`relay-lock.ps1 -Action release -SessionId <id>` 会校验归属
（`LOCK_NOT_MINE`，exit 5，见 selftest `lock_release_by_wrong_owner_refused`）。
CLI 子环拿不到自己的 session id（MCode 那边是 `session_create` 返回的），
所以启动器必须**预先分配**一个，并把它同时写进：

- 台账 `next_session_id`（下一环的驱动从这里读，spawn 已是 `source=ledger`）；
- prompt 的 `RELAY_SESSION_ID=` 行（子环据此 renew / release / 交接）。

同时 prompt 的交接指令从「推进三个 token」变成「推进四个 token」，
第四个就是 `RELAY_SESSION_ID`（必须等于它写进台账的那个 UUID）。

mcode 路径不受影响：session_tool 模式不分配 id、prompt 不含该行、
台账 `next_session_id` 仍为 `null`（mcode 由 `session_create` 回填）。

---

## 3. 顺带坐实的本机事实

| 事实 | 证据 |
|---|---|
| `claude` 可用，版本 `999.0.0-local`，`--print` 模式可用 | `claude --version` |
| `--session-id <uuid>` **不被这个本地版遵守**：驱动请求 `60d790e6-…`，实际会话是 `657c00d0-…` | 真链 transcript 首行 `sessionId` |
| `--output-format json` 的结果里**没有** `session_id` 字段 | 驱动回落到请求值，日志 `SPAWN_SESSION_ID … source=generated` |
| `--allowedTools` / `--max-budget-usd` / `--add-dir` / `--settings` 均受支持 | `claude --help` |
| `--bare` 不可用（会跳过 CLAUDE.md 自动发现，而家规正是双写 AGENTS.md + CLAUDE.md） | B9 记录 |
| 本机 `~/.claude/settings.json` 的 `defaultMode=bypassPermissions`、`autoQuestion.enabled=true` | 设置文件回读 |

**推论**：链的「逻辑 session id」必须由装置自己分配并贯穿 prompt 与台账，
不能指望 runtime 回填一个 id 回来。这也是 §2.3 的根因。

---

## 4. 修完之后的设计（这一版是什么）

```
start-relay.ps1
  §1b  runtime resolution : -Runtime > docs\relay\relay-runtime.json > mcode
  §1c  link mode + session id
        session_tool(mcode) / cli_driver(claude-code,codex) / sessions_spawn_tool(openclaw)
        cli_driver 时分配 chain session id，写进台账 next_session_id 与 prompt RELAY_SESSION_ID
  §5a  prompt 生成：mcode 分支逐字不变；cli 分支带 RELAY_SESSION_ID 与 release -SessionId

relay-spawn.ps1
  -PermissionMode 默认 bypassPermissions
  --settings {"autoQuestion":{"enabled":false}}（claude-code）
  跑前 Set-Location $WorkspaceDir，跑完 finally 恢复
  原始输出落盘 docs\relay\relay-spawn-output\<session_id>.txt
  claude-code 跑前 pre-adopt 锁；失败自动 release（release 带 -SessionId 会校验归属，安全）
```

**mcode 路径逐字等价的证明**：同一临时仓路径下，
`git HEAD:tool/templates/start-relay.ps1` 与新版 launcher 生成的 prompt
**逐字节相同**（`OLD_LEN=3770 NEW_LEN=3770 EQUAL=True`）。

---

## 5. 真链结果

> 本节由 **B13（2026-11-26）** 回填 —— B10 当时只验到「单次 CLI 调用被正确喊起来」，整链端到端留白；B13 在干净真链仓跑通了完整两环。
> 完整实录见 `tool\references\live-chain-b13.md`。

### 5.1 整链结论：通过

干净夹具仓（`claude-code` 运行时，git HEAD `08e6009`）里跑通全链：

```
install(两段)  →  start-relay 起链  →  spawn 子环
      ↓
第 1 环：写 docs\relay\stage-1-inventory.md → 台账 stage_done → bump_current_stage → 写 next_session_id
      ↓
第 2 环（自举）：写 docs\relay\stage-2-inventory.md → 锁最终释放（LOCK_ABSENT）
```

关键数字：`chain_session_id=b47a9c35-c96a-4b13-b501-27b7463c431f`；第 1 环 `tool_calls=23`；第 2 环 `tool_calls=12`；终态 `current_stage=3 / max_stages=2`；**transcript 里 `is_error=true` 计数 = 0**。

### 5.2 真链逼出来的两个真缺陷（B13 已修）
- **D1 反斜杠路径**：Claude Code 的 Bash 工具是真 bash，prompt 里的 `docs\relay\relay-ledger.ps1` 被吃掉成 `docsrelayrelay-ledger.ps1` ⇒ `exit 64`。修法：CLI 分支 prompt 内所有路径统一正斜杠。
- **D2 阶段清单没下发**：安装器收了 `-StageTitles` 但启动器不读描述符 ⇒ 阶段名退回默认。修法：启动器按「参数 > 台账 > 描述符 > 默认」解析，并打印 `OK stage_titles source=…`。

### 5.3 没变的硬要求
mcode 分支的 prompt **必须逐字节不变**（B10 硬要求）。B13 的阶段清单只在用户显式配置时才进描述符，因此未配置阶段的既有安装不受影响。证明方式：`git show HEAD:tool/templates/start-relay.ps1` 与工作区新版在同一夹具渲染出的 mcode prompt 逐字节相同（`MCODE_PROMPT_BYTE_IDENTICAL=True`）。

### 5.4 遗留（本轮有意不改）
- **F5**：链跑完终态 `status=blocked` 而非 `done`（`current_stage 3 > max_stages 2`）。改它要么动 mcode prompt（违反 5.3），要么让 mcode/CLI 语义分叉 ⇒ 下一批候选。
- **F6**：终态台账 `sessions=[]` 为空，session 信息只在 `stages[].session_id`。

---

## 6. 证据路径

- `tool\references\live-chain-b13.md` —— B13 整链实录（主证据）
- `tool\references\live-chain-b13-stdout.txt` —— 起链 + spawn 原始输出
- `tool\references\live-chain-b13-ledger-final.txt` —— 终态台账全文
- `tool\references\live-chain-b13-artifacts.txt` —— 两环产物内容
- `tool\references\live-chain-b13-prompts.txt` / `live-chain-b13-prompt-stage1.txt` —— prompt 全文
- `tool\references\live-chain-b13-transcript-1.txt` / `-transcript-2.txt` —— 两环 transcript（`is_error` 判据）
- `tool\references\selftest-2026-11-26.txt` / `.md` —— 门禁 raw 日志与小结（pass=233 fail=0 / EXIT=0）
- `scripts\selftest.ps1` case 19 —— 本轮新增 18 条断言
- `HANDOFF.md` 批次 B13 实录 —— 修复清单与取舍
