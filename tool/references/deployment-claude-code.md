# 在 Claude Code 上部署 relay-port 接力装置

> 适用：目标仓库用 **Claude Code CLI** 干活，链的每一环是一个无头 `claude -p` 子进程。
> 装置本体与 MCode 版本完全一样，只有「家规落点」和「起环方式」两处不同。

---

## 0. 前置检查

```powershell
claude --version          # 能打印版本号即可
cd <你的仓库根>            # 必须是 git 仓库根
git rev-parse --is-inside-work-tree
```

- Claude Code 装在哪不重要，只要 `claude` 在 `PATH` 里。本机实测路径是 `%USERPROFILE%\.local\bin\claude.exe`。
- 装好之后，**必须能在这个仓库里跑 Claude Code**（`claude` 的 cwd 就是仓库根），否则子进程读不到仓库。

---

## 1. 安装（一条命令）

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File "<skill目录>\scripts\install-relay.ps1" `
  -RepoRoot "<仓库绝对路径>" `
  -Target "<本轮目标批次>" `
  -Runtime claude-code `
  [-PlanDoc "<仓库相对路径的计划文档>"] `
  [-MaxStages 6] [-Force]
```

`skill目录` = 全局 skill 根下的 `relay-port\`（本机是 `E:\Users\Duanyi\.minimax\.minimax\skills\relay-port`）。
仓库里开发时用 `tool\scripts\install-relay.ps1`，效果一样。

装完落盘的东西：

| 路径 | 说明 |
|---|---|
| `<repo>\docs\relay\start-relay.ps1` | 启动器 |
| `<repo>\docs\relay\relay-lock.ps1` | 互斥锁 |
| `<repo>\docs\relay\relay-ledger.ps1` | 台账写闸门 |
| `<repo>\docs\relay\relay-spawn.ps1` | **起环驱动**（Claude Code / Codex 用，MCode 不用） |
| `<repo>\docs\AGENT-RELAY.md` | 通用协议 |
| `<repo>\docs\RELAY-SOP.md` | 操作规程 |
| `<repo>\docs\RELAY-ADAPTATION.md` | 本项目裁决骨架（要补 TODO） |
| `<repo>\AGENTS.md` | 家规块（`<!-- BEGIN RELAY-PORT -->`） |
| `<repo>\CLAUDE.md` | **同一份家规块**（Claude Code 双写，理由见 §6.1） |
| `<repo>\docs\relay\ACTIVATION-PROMPT.txt` | 激活包（内含 Claude Code 版四步） |
| `<repo>\docs\relay\install-report.md` | 安装报告 |

---

## 2. 装完必看两行

安装器最后会打机读复核判据，**这两行必须都在**：

```
AGENTS_MARKERS begin=1 end=1
CLAUDE_MARKERS begin=1 end=1
```

再确认结尾是 `INSTALL_VERDICT=PASS`、倒数第二行是 `INSTALL_RUNTIME=claude-code`。

---

## 3. 补 `docs\RELAY-ADAPTATION.md` 的 TODO（不做就起不了链）

至少补齐三处：

1. **写集**：哪些目录可改、哪些禁止碰（产品代码、门禁脚本、发布流程）。
2. **验收门禁**：命令 + 判绿口径（例：`npm run check` 全绿、`cargo test` 全过）。
3. **模型策略**：每环用哪个模型（写进 `model` 字段）。

台账 `docs\relay.json` 由启动器在激活那一刻创建，**安装器不碰它**。

---

## 4. 激活

在 **cwd = 仓库根** 的 Claude Code 会话里说这一句：

```
follow docs\relay\ACTIVATION-PROMPT.txt to start the relay chain
```

Claude Code 会照激活包的四步走：

1. 跑 `start-relay.ps1`（工作区校验 + 并发闸门 + 取锁 + 写台账 + 生成 prompt）。
   退出码 `0` 才继续；`2` / `3` / `4` 都**不许起环**，如实汇报即可。
2. 干跑一次起环驱动看命令：

   ```powershell
   pwsh -NoProfile -ExecutionPolicy Bypass -File "<repo>\docs\relay\relay-spawn.ps1" -Runtime claude-code -PromptFile "<repo>\docs\relay\next-relay-prompt.txt" -WorkspaceDir "<repo>"
   ```

3. 真跑：

   ```powershell
   pwsh -NoProfile -ExecutionPolicy Bypass -File "<repo>\docs\relay\relay-spawn.ps1" -Runtime claude-code -PromptFile "<repo>\docs\relay\next-relay-prompt.txt" -WorkspaceDir "<repo>" -Execute -AdoptLock
   ```

4. `-AdoptLock` 已经把锁转交给新会话了；要手工确认就再看一眼：

   ```powershell
   pwsh -NoProfile -ExecutionPolicy Bypass -File "<repo>\docs\relay\relay-lock.ps1" -Action status
   ```

---

## 5. 怎么判成功

| 证据 | 期望 |
|---|---|
| 干跑输出 | `SPAWN_COMMAND claude -p <prompt from file> --output-format json --session-id <uuid> --add-dir <repo>` |
| 干跑末行 | `SPAWN_EXECUTE=false (add -Execute to run the command above)` —— **默认不执行**，这是安全默认 |
| 真跑末行 | `RELAY_SPAWN_OK runtime=claude-code session_id=<uuid>` |
| 锁状态 | `relay-lock.ps1 -Action status` 里锁的 session id = 上面那个 uuid |
| 台账 | `docs\relay.json` 的 `status` = `running`，`current_stage` = 1，`sessions[]` 有记录 |

**链的形态与 MCode 不同**：每一环是**跑完即退的无头子进程**。当前环跑完后，由它自己再跑一次第 3 步的命令起下一环
（家规块 §A.5 / §B.9 写的就是这件事），所以整条链是「一串子进程」，不是「一串常驻会话」。

---

## 6. 常见坑

### 6.1 `CLAUDE.md` 会遮蔽 `AGENTS.md`

Claude Code 读 `CLAUDE.md`；**只有仓库里没有 `CLAUDE.md` 时**才回退读 `AGENTS.md`。
所以原版装置只写 `AGENTS.md` 时，只要仓库本来就有 `CLAUDE.md`，家规块就永远读不到 —— **装完像成功，链起不来**。

本装置对 `claude-code` **双写**（`AGENTS.md` + `CLAUDE.md`）来堵这个洞。
但如果你在装完之后**手工新建了 `CLAUDE.md`**，家规块又会被遮蔽 ⇒ 重装一次：

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File "<skill目录>\scripts\install-relay.ps1" -RepoRoot "<仓库>" -Target "<批次>" -Runtime claude-code -Force
```

### 6.2 `claude` 不在 PATH

起环驱动会响亮失败：`FAIL reason=runtime_cli_missing exe=claude`（退出码 `3`）。
先确认 `claude --version` 能跑；Windows 上装了但不在 PATH，就把它的目录加进 PATH。

### 6.3 权限模式

起环驱动默认 `--permission-mode acceptEdits`（自动接受文件编辑，但仍拒绝命令执行类操作）。
要更严就改成 `plan` 或 `default`；要放开才用 `bypassPermissions`（**不建议在无人值守链里用**）。

### 6.4 沙箱与工作目录

起环命令带 `--add-dir <仓库根>`，把仓库加进可访问目录。
链是**无人值守**的，所以写集必须由 `docs\RELAY-ADAPTATION.md` 圈死；Claude Code 的权限模式不是安全边界。

### 6.5 prompt 太大

接力 prompt 从文件读，超过 60000 字符会 `FAIL reason=prompt_too_large`（退出码 `2`）。
碰到就减少计划文档的规模或分批。

### 6.6 换运行时

从 Claude Code 换到别的运行时（或反过来）**必须重装并带 `-Force`**，否则家规块、
`docs\RELAY-ADAPTATION.md`、激活包三处会各说各话。

---

## 7. 相关文件

- 可移植性分析与四家对照：`tool\references\runtime-portability-2026-11-25.md`
- 协议 §10 运行时适配：`<repo>\docs\AGENT-RELAY.md` 第 10 节
- 装置契约：`tool\SKILL.md`
