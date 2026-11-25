# 在 Codex CLI 上部署 relay-port 接力装置

> 适用：目标仓库用 **Codex CLI** 干活，链的每一环是一个无头 `codex exec` 子进程。
> 装置本体与 MCode 版本完全一样；Codex 原生读 `AGENTS.md`，所以**不需要双写规则文件**。

---

## 0. 前置检查

```powershell
codex --version          # 能打印版本号即可
cd <你的仓库根>
git rev-parse --is-inside-work-tree
```

- 本机（2026-11-25）**未安装** `codex`，因此本文件是**按官方文档写出的部署指导，真起链未实测**。
- 装好之后，**必须能在这个仓库里跑 Codex**（cwd = 仓库根），否则子进程读不到仓库。

---

## 1. 安装（一条命令）

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File "<skill目录>\scripts\install-relay.ps1" `
  -RepoRoot "<仓库绝对路径>" `
  -Target "<本轮目标批次>" `
  -Runtime codex `
  [-PlanDoc "<仓库相对路径的计划文档>"] `
  [-MaxStages 6] [-Force]
```

落盘的东西与 Claude Code 版**完全一样**，只有两点不同：

- **不写 `CLAUDE.md`**（Codex 不读它）。
- 激活包里的起环步骤是 `codex exec` 版。

---

## 2. 装完必看一行

```
AGENTS_MARKERS begin=1 end=1
```

再确认结尾是 `INSTALL_VERDICT=PASS`、倒数第二行是 `INSTALL_RUNTIME=codex`。

---

## 3. 补 `docs\RELAY-ADAPTATION.md` 的 TODO

同 Claude Code 版：写集 / 验收门禁 / 模型策略，三处必补。

---

## 4. 激活

在 **cwd = 仓库根** 的 Codex 会话里说：

```
follow docs\relay\ACTIVATION-PROMPT.txt to start the relay chain
```

四步：

1. `start-relay.ps1`（退出码 `0` 才继续；`2` / `3` / `4` 都不许起环）。
2. 干跑起环驱动：

   ```powershell
   pwsh -NoProfile -ExecutionPolicy Bypass -File "<repo>\docs\relay\relay-spawn.ps1" -Runtime codex -PromptFile "<repo>\docs\relay\next-relay-prompt.txt" -WorkspaceDir "<repo>"
   ```

3. 真跑：

   ```powershell
   pwsh -NoProfile -ExecutionPolicy Bypass -File "<repo>\docs\relay\relay-spawn.ps1" -Runtime codex -PromptFile "<repo>\docs\relay\next-relay-prompt.txt" -WorkspaceDir "<repo>" -Execute -AdoptLock
   ```

4. 确认锁：

   ```powershell
   pwsh -NoProfile -ExecutionPolicy Bypass -File "<repo>\docs\relay\relay-lock.ps1" -Action status
   ```

---

## 5. 怎么判成功

| 证据 | 期望 |
|---|---|
| 干跑输出 | `SPAWN_COMMAND codex exec --json --sandbox workspace-write -a never <prompt from file>` |
| 干跑末行 | `SPAWN_EXECUTE=false (add -Execute to run the command above)` |
| 真跑末行 | `RELAY_SPAWN_OK runtime=codex session_id=<id>`（id 取自输出 JSON 的 `"thread_id"`） |
| 锁状态 | 锁的 session id = 上面那个 id |
| 台账 | `docs\relay.json`：`status=running`、`current_stage=1`、`sessions[]` 有记录 |

**Codex 的特殊语义：`codex exec` 的退出码就是这一环的成败。**
退出码非 0 ⇒ 这一环失败，链在该环停住 —— 这跟 MCode 的「会话起来了就算成功」不一样，
所以链的自转必须靠台账里的 `status` 判定，不要靠「进程退没退」。

---

## 6. 常见坑

### 6.1 沙箱与审批要显式给

起环驱动默认 `--sandbox workspace-write` + `-a never`（无人值守链不能等人点批准）。
- `--sandbox` 可选 `read-only` / `workspace-write` / `danger-full-access`。
- `-a`（审批策略）默认 `never`。**只要链里有任何一步需要人工批准，这一环就必然卡死**，所以 `-a never` 是无人值守的前提。

### 6.2 `AGENTS.md` 有体量上限

Codex 把**全局 `~/.codex/AGENTS.md` 与项目根向下的各级 `AGENTS.md` 合并**加载，合并上限约 32 KiB。
家规块量级远小于这个数，但同一个仓库里**不要堆多份接力家规**（装置的收编逻辑正是为此存在）。

### 6.3 `codex` 不在 PATH

`FAIL reason=runtime_cli_missing exe=codex`（退出码 `3`）。先确认 `codex --version` 能跑。

### 6.4 会话 id 取不到

起环驱动从输出里正则抽 `"thread_id"`；抽不到就 `FAIL reason=session_id_not_found`（退出码 `4`）。
这种情况说明 Codex 的 JSON 输出形状和预期不同 ⇒ **记下来，不要硬编正则**，回到 `tool\templates\relay-spawn.ps1` 改抽取逻辑并重跑 selftest。

### 6.5 续跑上一环

Codex 侧可以用 `codex resume --last` / `codex exec resume`。
但本装置的链**不依赖人工续跑** —— 每一环自己起下一环，`resume` 只在需要人工介入时用。

### 6.6 换运行时

换运行时必须重装并带 `-Force`，否则家规块、`docs\RELAY-ADAPTATION.md`、激活包三处各说各话。

---

## 7. 相关文件

- 可移植性分析与四家对照：`tool\references\runtime-portability-2026-11-25.md`
- 协议 §10 运行时适配：`<repo>\docs\AGENT-RELAY.md` 第 10 节
- 装置契约：`tool\SKILL.md`
