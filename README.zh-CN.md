# agentask-relay —— 无人值守接力装置（`agentask-relay`）

[![selftest](https://github.com/kizemo/agentask-relay/actions/workflows/selftest.yml/badge.svg)](https://github.com/kizemo/agentask-relay/actions/workflows/selftest.yml)

[English](./README.md) | **简体中文**

把**无人值守接力链**装进任意 git 项目。**一句话**就能起一条自推进的会话链：
同一时刻只有一个写者、每个阶段都有验收判据、碰到人工验收点自动停下等人。

支持 **MCode**、**Claude Code**、**Codex CLI**、**OpenClaw** 四种运行时。

---

## 一、它做什么（作用）

没有接力装置时，「一直干到完」意味着人要不停往聊天窗口里粘贴「继续」；
每一次粘贴都要重读整个仓库、丢掉上下文，还经常和另一个会话同时改同一个文件。
接力装置把这件事变成**机器驱动的链**：

| | 没有装置 | 有装置 |
|---|---|---|
| 谁起下一阶段 | 人粘贴「继续」 | 上一阶段自己起下一阶段 |
| 并发 | 两个会话同时改一个文件 | 一个项目一个写者，原子锁强制 |
| 状态在哪 | 在某个人的脑子里 | `docs\relay.json` —— 只追加、CAS 保护 |
| 什么会让它停 | 什么都停不了它 | 验收判据、`max_stages`、写集规则、人工验收点 |
| 怎么续 | 只能从头重读一遍 | 从台账续 |

装完之后，目标仓库里会多出：

- **启动器** `start-relay.ps1` —— 工作区校验 + 并发闸门 + 取锁 + 台账初始化（只新建不覆写）+ 生成下一环的接力 prompt；
- **原子锁** `relay-lock.ps1` —— `FileMode.CreateNew`，两个会话绝不可能同时持有一个项目；
- **台账写闸门** `relay-ledger.ps1` —— 写锁 + 比对交换（`sha256`）+ 只追加不变式 + 写后回读；
- **协议** `docs\AGENT-RELAY.md`、**规程** `docs\RELAY-SOP.md`、**本项目裁决骨架** `docs\RELAY-ADAPTATION.md`；
- **家规块** —— 幂等注入项目的家规文件，不重复、不覆盖项目自己写的规则；
- **激活包** `docs\relay\ACTIVATION-PROMPT.txt` —— 写死四步命令 + 人要说的那一句话。

---

## 二、值在哪（价值）

- **无人值守是设计出来的，不是碰巧**。链只有在上一阶段**验收判据成立、证据落盘、台账已追加**时才推进。「它停了」永远能在 `docs\relay.json` 里查到原因，不是凭感觉。
- **睡觉时也能跑**。四道闸门挡在「模型想继续」和「模型动手写」之间：原子锁、台账闸门、写集指纹、回写 CAS。陈旧视图不可能悄悄盖掉更新的视图。
- **可审计**。每个阶段都留下台账条目、阶段文档、锁心跳。证据在盘上，不在聊天记录里。
- **跨运行时可移植**。同一套装置跑在 MCode / Claude Code / Codex CLI / OpenClaw 上。一个命令选定运行时，家规落点和起环方式自动适配。
- **零常驻进程**。两轮之间什么都不在后台跑。链完全由文件 + 当前持锁的那个会话扛起来。

---

## 三、安装部署

### 3.1 前置

- PowerShell 7（`pwsh`）—— Windows / Linux / macOS 均可。
- 目标必须是 **git 仓库** —— 启动器在别处会拒绝起链。
- 一份描述阶段的计划文档；没有也行，安装器会生成一份。

### 3.2 装进目标项目

工具以全局 skill 形式发布在 `<MCode 数据目录>\skills\agentask-relay\`
（Windows 上是 `%USERPROFILE%\.minimax\.minimax\skills\agentask-relay\`）。
本仓库是它的真源与工作副本。

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File "<skill>\scripts\install-relay.ps1" `
  -RepoRoot "<目标仓库绝对路径>" `
  -Target "<本轮目标批次>" `
  -Runtime mcode `
  [-PlanDoc "<计划文档路径，仓库相对>"] `
  [-StageTitles "1. 摸底;2. 实现;3. 验证;4. 收口"] `
  [-MaxStages 6] [-WorkspaceDir "<仓库根>"] [-TtlSeconds 1800] [-Force]
```

退出码：`0` 装好、`2` 参数或工作区非法、`5` 自检不过。
安装末尾会跑一次启动器干跑，干跑结果只记录，不影响安装本身的退出码。

### 3.3 选运行时

`-Runtime` 决定两件事：**家规落到哪些文件**、**下一环怎么起**。

| `-Runtime` | 家规落点 | 下一环怎么起 | 需要起环驱动 |
|---|---|---|---|
| `mcode`（默认） | `AGENTS.md` | 内置 `session_create` 工具 | 否 |
| `claude-code` | `AGENTS.md` **和** `CLAUDE.md` | 无头 `claude -p` 子进程 | 是 |
| `codex` | `AGENTS.md` | 无头 `codex exec` 子进程 | 是 |
| `openclaw` | `AGENTS.md` | 运行时自带的 `sessions_spawn` 工具 | 否（锁要手工转交） |

不认识的运行时**响亮失败**（`FAIL reason=runtime_unsupported`，退出码 `2`），不静默退回默认。

> **为什么 Claude Code 要写两个文件**：Claude Code 读 `CLAUDE.md`，**只有仓库没有 `CLAUDE.md` 时**才回退读 `AGENTS.md`。
> 仓库里只要已经有 `CLAUDE.md`，`AGENTS.md` 里的家规就被整份遮蔽 —— 装完看着像成功，链却永远起不来。
> 所以 `claude-code` 双写两个文件，并分别打 `AGENTS_MARKERS begin=1 end=1` 与 `CLAUDE_MARKERS begin=1 end=1` 供复核。
>
> **OpenClaw 的硬约束**：它只注入**它自己 workspace 根目录**那份 `AGENTS.md`。
> 目标仓库必须就是那个 workspace；不是的话，家规块要先复制过去。

逐家部署指导（前置、激活、怎么判成功、常见坑）：

- `tool\references\deployment-claude-code.md`
- `tool\references\deployment-codex.md`
- `tool\references\deployment-openclaw.md`
- `tool\references\runtime-portability-2026-11-25.md` —— 四家运行时完整分析

### 3.4 装完必做两件事

1. **补全 `docs\RELAY-ADAPTATION.md` 的 TODO** —— 写集（哪些目录可改、哪些禁止碰）、验收门禁命令与判绿口径、模型策略。
   **不补这一份，链会在第一环就因「写集不明」停链。**
2. **在目标项目内激活**。起环权属于目标项目，不属于外部监督会话。

```
follow docs\relay\ACTIVATION-PROMPT.txt to start the relay chain
```

激活包里写死四步：跑启动器 → 起第一环 → `relay-lock.ps1 -Action adopt` 转交锁 → 回读新会话校验。
任何一步失败：释放锁并如实汇报，**不许重试起环**。

### 3.5 启动器的退出码说了算

| 退出码 | 含义 | 能不能起环 |
|---|---|---|
| `0` | 所有闸门通过，下一环 prompt 已生成 | 能 |
| `2` | 工作区非法，或计划文档解析不出来 | **不能** |
| `3` | 已有链在跑 / 有阶段 `in_progress` / 台账 blocked 或耗尽 | **不能** |
| `4` | 锁被别的会话持有 | **不能** |

计划文档在**取锁之前**解析：显式 `-PlanDoc` → 台账 `plan_doc` → 探测
`docs\plan-*.md` / `docs\plans\*.md` / `docs\superpowers\plans\*.md`。
唯一命中直接用；多命中告警并按 mtime 取最新；零命中退出码 `2`。
**绝不为起链临时创建计划文档。**

---

## 四、装完之后目标仓库里多了什么

- `docs\relay\start-relay.ps1` —— 启动器
- `docs\relay\relay-lock.ps1` —— 原子锁
- `docs\relay\relay-ledger.ps1` —— 台账写闸门（锁 + CAS + 只追加 + 写后回读）
- `docs\relay\relay-spawn.ps1` —— 起环驱动（仅 CLI 运行时；默认只干跑，`-Execute` 才真跑）
- `docs\AGENT-RELAY.md`、`docs\RELAY-SOP.md`、`docs\RELAY-ADAPTATION.md` —— 协议 / 规程 / 本项目裁决
- `docs\relay\ACTIVATION-PROMPT.txt`、`docs\relay\install-report.md` —— 激活包 / 安装报告
- `docs\plan-relay.md` —— 计划文档（只在没找到既有计划时才生成）
- `AGENTS.md`（`claude-code` 时还有 `CLAUDE.md`）里一段家规块，标记是 `<!-- BEGIN RELAY-PORT -->` / `<!-- END RELAY-PORT -->`

**`docs\relay.json`（台账）由启动器在起链那一刻创建，安装器绝不写它。**

项目里已有的接力规则节会被**收编**（原地包进标记，正文一字不动），而不是再追加一份 ——
先按标题判据，再按内容指纹判据。两节都合格时安装器**不猜**，追加托管块并告警
`WARN agents_relay_section_ambiguous matches=N`。

---

## 五、目录地图

| 路径 | 内容 |
|---|---|
| `tool/` | **工具本体** —— 安装器、模板（装置脚本 / 协议 / 激活包）、留证 |
| `device/` | 装置本体 `start-relay.ps1` / `relay-lock.ps1` / `relay-ledger.ps1` / `relay-spawn.ps1` + 一份设计样例台账 |
| `protocol/` | 共享协议层，与 `tool\templates\AGENT-RELAY.md` 逐字一致 |
| `examples/practilog/` | 真实落地样本：台账、项目裁决记录、链产物、门禁与监督证据 |
| `scripts/` | **本仓库自己的维护脚本**（不随工具发布）：`selftest.ps1`、`publish-relay.ps1`、`refresh-manifest.ps1` |
| `MANIFEST.txt` | 每个文件一行 `<sha16>` / `<bytes>` / `<相对路径>`；用 `scripts\refresh-manifest.ps1` 刷，**永远放在最后一步** |
| `HANDOFF.md` | 交接：背景 / 进度 / 已验证 / 推断 / 未验证 / 证据路径 / 候选清单 / 工具坑 |
| `AGENTS.md` | 本项目的家规 |

---

## 六、维护这个工具

```powershell
# 家规 1 的落地：改 tool\ 或 device\ 之后必跑。
# 在 %TEMP% 下建一次性 git 仓库，真跑安装器 / 启动器 / 锁 / 台账 / 编码 / 逐字一致。
# 判绿 = EXIT=0 且 fail=0。
pwsh -NoProfile -File scripts\selftest.ps1 -EvidencePath "$env:TEMP\relay-selftest.log"

# 发布：device<->templates 硬不变式 + tool\ 与全局 skill 的逐件 sha16 对账，一条命令做完。
pwsh -NoProfile -File scripts\publish-relay.ps1 -Direction verify    # 只查不改
pwsh -NoProfile -File scripts\publish-relay.ps1 -Direction publish   # 本仓库 -> 全局 skill
```

顺序固定：**selftest → publish → refresh-manifest**（清单含自身，必须最后）。

`examples\practilog\docs\relay\` 是历史留证快照：只报 `SNAPSHOT_DRIFT`、不参与判定、**不要为它同步**。

---

## 七、当前状态

- 装置已实现并由 `scripts\selftest.ps1` 覆盖验证（case 1–16，**135 条断言 / 0 失败 / `EXIT=0`**）。每轮的原始日志与说明在
  `tool\references\selftest-*.txt` / `.md`。
- 修过的缺陷值得一提：**D1** 未初始化变量把目标 `AGENTS.md` 截成 0 字节；**D2** 干跑留证 0 B；
  **D3** `.ps1` 里的 CJK 字面量在 Windows PowerShell 5.1 无 BOM 时乱码；**D4** 启动器的 `-PlanDoc` 默认值是某个项目的专用路径。
- 运行时适配层（B9）新增了 `-Runtime`、起环驱动 `relay-spawn.ps1`、按运行时分片的激活包、协议 §10。
- 还没做：把这套装置装到本仓库自己身上（dogfood）、macOS/Linux 真机执行审计（那些路径是推断的）、起环前的模型预检。清单见 `HANDOFF.md`。
- 任何自动化跑批都覆盖不到的：**真实起链** —— 它要真起一个新会话，自测不会做，只校验生成的激活包。

---

## 八、与全局 skill 的关系

| | 角色 | 什么时候动 |
|---|---|---|
| `tool\`（本仓库） | 工作面 / 真源 / 演进位 | 改工具时 |
| `<MCode 数据目录>\skills\agentask-relay\` | 会话真正加载的那份 | 本仓库改动过了自测之后，**同步过去** |

用 `scripts\publish-relay.ps1 -Direction publish` 同步，覆盖 `SKILL.md`、`scripts\`、
`templates\`、`references\`，并逐件复核。改完装置模板后 `device\` 必须与真源逐字一致
（`Copy-Item tool\templates\<f> device\<f> -Force`），否则 `publish-relay.ps1` 直接判硬不变式失败。

---

## License

本仓库尚未加入 LICENSE 文件，默认保留所有权利。选哪份许可证是开放项（见 `HANDOFF.md`）。
