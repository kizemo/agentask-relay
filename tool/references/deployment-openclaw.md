# 在 OpenClaw 上部署 relay-port 接力装置

> 适用：目标仓库由 **OpenClaw**（旧名 Clawdbot / Moltbot）的常驻 gateway 驱动。
> OpenClaw 有自己的 `sessions_spawn` 工具，所以**不需要**起环驱动 `relay-spawn.ps1`；
> 但它有一条别的运行时都没有的**硬约束**，见 §6.1。

---

## 0. 前置检查

```powershell
cd <你的仓库根>
git rev-parse --is-inside-work-tree
```

- 本机（2026-11-25）**未安装** `openclaw`，因此本文件是**按官方文档写出的部署指导，真起链未实测**。
- 确认 OpenClaw 的 **workspace 根目录就是目标仓库**（硬约束，见 §6.1）。在 OpenClaw 里查当前 workspace 根，
  把它和仓库绝对路径对上；对不上就不要继续，先改 workspace 配置。

---

## 1. 安装（一条命令）

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File "<skill目录>\scripts\install-relay.ps1" `
  -RepoRoot "<仓库绝对路径>" `
  -Target "<本轮目标批次>" `
  -Runtime openclaw `
  [-PlanDoc "<仓库相对路径的计划文档>"] `
  [-MaxStages 6] [-Force]
```

落盘的东西与 Claude Code / Codex 版一样，区别在两点：

- **不写 `CLAUDE.md`**（OpenClaw 不读它）。
- 激活包里的起环步骤是 **`sessions_spawn` 工具版**，不是 CLI 子进程版。

---

## 2. 装完必看一行

```
AGENTS_MARKERS begin=1 end=1
```

再确认结尾是 `INSTALL_VERDICT=PASS`、倒数第二行是 `INSTALL_RUNTIME=openclaw`。

---

## 3. 补 `docs\RELAY-ADAPTATION.md` 的 TODO

同其它版：写集 / 验收门禁 / 模型策略，三处必补。

---

## 4. 激活

在 **workspace 就是本仓库** 的 OpenClaw 会话里说：

```
follow docs\relay\ACTIVATION-PROMPT.txt to start the relay chain
```

四步：

1. `start-relay.ps1`（退出码 `0` 才继续；`2` / `3` / `4` 都不许起环）。
2. 读 `docs\relay\next-relay-prompt.txt` 全文。
3. 用 `sessions_spawn` 起第一环（激活包里写好的形状）：

   ```text
   tool      : sessions_spawn
   workspace : <仓库绝对路径>
   prompt    : <next-relay-prompt.txt 全文>
   task      : relay-01of<MM>-<短阶段名>
   ```

   返回值里带新的会话 id。

4. 转交锁（OpenClaw 没有起环驱动，**这一步要手工跑**）：

   ```powershell
   pwsh -NoProfile -ExecutionPolicy Bypass -File "<repo>\docs\relay\relay-lock.ps1" -Action adopt -SessionId <新会话 id>
   ```

5. 回读校验：确认新会话的 workspace 就是本仓库、状态在跑，再看一眼锁。

---

## 5. 怎么判成功

| 证据 | 期望 |
|---|---|
| 家规块 | `<repo>\AGENTS.md` 里有且只有一对 `<!-- BEGIN RELAY-PORT -->` / `<!-- END RELAY-PORT -->` |
| 激活包 | `<repo>\docs\relay\ACTIVATION-PROMPT.txt` 里出现 `sessions_spawn` 与 `workspace` 两个关键词 |
| 锁状态 | `relay-lock.ps1 -Action status` 里的 session id = 新会话 id |
| 台账 | `docs\relay.json`：`status=running`、`current_stage=1`、`sessions[]` 有记录 |
| 下一环 | 新会话里能看到它自己读了 `docs\relay.json`（家规块 §B.6） |

---

## 6. 常见坑

### 6.1 **硬约束**：只注入自己 workspace 根的 `AGENTS.md`

OpenClaw 每次新会话都把 **workspace 根目录**的 `AGENTS.md` / `SOUL.md` / `IDENTITY.md` / `USER.md` /
`BOOTSTRAP.md` / `MEMORY.md` 注入 system prompt；**子 agent 只注入 `AGENTS.md` + `TOOLS.md`**。

所以：**目标仓库必须就是该 OpenClaw agent 的 workspace**。
仓库不在 workspace 根时，装置写进 `<repo>\AGENTS.md` 的家规块根本进不了 system prompt ⇒
**装完像成功，链起不来**（和 Claude Code 的 `CLAUDE.md` 遮蔽是同一类病，不同的病根）。

对不上时的两条出路：

1. 把 OpenClaw 的 workspace 改成这个仓库（推荐）。
2. 把托管块**复制**到 workspace 根的 `AGENTS.md`：

   ```powershell
   Get-Content "<repo>\AGENTS.md" -Raw | Select-String -Pattern '(?s)<!-- BEGIN RELAY-PORT -->.*<!-- END RELAY-PORT -->' -AllMatches |
     ForEach-Object { $_.Matches.Value } | Set-Content "<workspace根>\AGENTS.md" -Encoding utf8
   ```

   注意这样会造成**两份**家规块，后续改规则要同步改两处 —— 优先选第 1 条。

### 6.2 `sessions_spawn` 的参数形状

OpenClaw 的 spawn 工具参数名随版本演进（`workspace` / `runtime` / `task` 等）。
装置给的激活包里是一份**参考形状**，第一次跑之前先在交互会话里打一次 `sessions_spawn` 看本机版本的真实参数名，
对不上就改 `<repo>\docs\relay\ACTIVATION-PROMPT.txt` 里 STEP 2 的那一段（改激活包不影响装置本体）。

### 6.3 `runtime:"acp"` 选项

OpenClaw 的 `sessions_spawn` 可以带 `runtime:"acp"` 起一个 Claude Code 会话。
**混用运行时要小心**：那样起出来的会话读的是 Claude Code 的规则文件（`CLAUDE.md`），
而本装置在 `openclaw` 运行时只写 `AGENTS.md` ⇒ 规则落点对不上。
混用前请先把 `CLAUDE.md` 也补上（或者干脆别混用）。

### 6.4 规则文件体量

OpenClaw 限制：`AGENTS.md` **单文件 20,000 字符、注入总量 60,000 字符**。
家规块量级没问题，但如果仓库根已经有很长的 `AGENTS.md`，加上 `SOUL.md` 等一起注入时可能逼近上限 —— 装完顺手看一眼。

### 6.5 锁转交别忘了

OpenClaw 没有起环驱动 ⇒ `-AdoptLock` 这条自动化路径对它无效。
每次起环后**必须手工**跑 `relay-lock.ps1 -Action adopt -SessionId <新 id>`，否则锁留在上一环名下，
下一环会被并发闸门挡住（退出码 `4`）。

### 6.6 换运行时

换运行时必须重装并带 `-Force`，否则家规块、`docs\RELAY-ADAPTATION.md`、激活包三处各说各话。

---

## 7. 相关文件

- 可移植性分析与四家对照：`tool\references\runtime-portability-2026-11-25.md`
- 协议 §10 运行时适配：`<repo>\docs\AGENT-RELAY.md` 第 10 节
- 装置契约：`tool\SKILL.md`
