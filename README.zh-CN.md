# agentask-relay —— 无人值守接力装置（relay-port）的工程目录

[![selftest](https://github.com/kizemo/agentask-relay/actions/workflows/selftest.yml/badge.svg)](https://github.com/kizemo/agentask-relay/actions/workflows/selftest.yml)

<p align="left">
  <a href="./README.md"><img alt="English" src="https://img.shields.io/badge/lang-English-2ea44f?style=for-the-badge"/></a>
  <a href="./README.zh-CN.md"><img alt="Chinese (Simplified)" src="https://img.shields.io/badge/lang-Chinese_Simplified-0969da?style=for-the-badge"/></a>
</p>

[![selftest](https://github.com/kizemo/agentask-relay/actions/workflows/selftest.yml/badge.svg)](https://github.com/kizemo/agentask-relay/actions/workflows/selftest.yml)

[English](./README.md) | **中文（简体）**

[![selftest](https://github.com/kizemo/agentask-relay/actions/workflows/selftest.yml/badge.svg)](https://github.com/kizemo/agentask-relay/actions/workflows/selftest.yml)

这个目录是「把自动接力链装进任意项目」这件工具的**可演进工程面**：让一条 prompt 就能启动
一条自我推进的会话链，每个阶段只有一个写入者。

[![selftest](https://github.com/kizemo/agentask-relay/actions/workflows/selftest.yml/badge.svg)](https://github.com/kizemo/agentask-relay/actions/workflows/selftest.yml)

工具本体同时以全局 skill 形式发布在 `<MCode 数据目录>\skills\relay-port\`
（Windows 上是 `%USERPROFILE%\.minimax\.minimax\skills\relay-port\`）。
本目录是它的**真源 / 工作副本**：在这里改 → 跑一键自测 → 再同步回全局 skills 目录才算生效，
否则新会话拿到的还是旧版。

[![selftest](https://github.com/kizemo/agentask-relay/actions/workflows/selftest.yml/badge.svg)](https://github.com/kizemo/agentask-relay/actions/workflows/selftest.yml)

## 工具一句话

[![selftest](https://github.com/kizemo/agentask-relay/actions/workflows/selftest.yml/badge.svg)](https://github.com/kizemo/agentask-relay/actions/workflows/selftest.yml)

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File tool\scripts\install-relay.ps1 `
  -RepoRoot "<仓库绝对路径>" -Target "<本轮目标批次>" `
  [-PlanDoc "<计划文档路径>"] [-StageTitles "1. xxx;2. yyy"] [-MaxStages 6] `
  [-WorkspaceDir "<工作区目录>"] [-TtlSeconds 1800] [-Force] [-SkipVerify]
```

[![selftest](https://github.com/kizemo/agentask-relay/actions/workflows/selftest.yml/badge.svg)](https://github.com/kizemo/agentask-relay/actions/workflows/selftest.yml)

`-PlanDoc` **可省**：不给时按「显式 `-PlanDoc` → 台账 `plan_doc` → 探测
`docs\plan-*.md` / `docs\plans\*.md` / `docs\superpowers\plans\*.md`」解析
（唯一取之；多个 `WARN` 后按 mtime 取最新；零个 `exit 2` 拒绝起链）——
安装与起链用的是同一份清单，不会出现「装完还得手敲计划路径」。
**绝不会为起链而创建计划文档。**

[![selftest](https://github.com/kizemo/agentask-relay/actions/workflows/selftest.yml/badge.svg)](https://github.com/kizemo/agentask-relay/actions/workflows/selftest.yml)

装完在**目标项目内**说一句即可起链：

[![selftest](https://github.com/kizemo/agentask-relay/actions/workflows/selftest.yml/badge.svg)](https://github.com/kizemo/agentask-relay/actions/workflows/selftest.yml)

```
按 docs\relay\ACTIVATION-PROMPT.txt 启动接力链
```

[![selftest](https://github.com/kizemo/agentask-relay/actions/workflows/selftest.yml/badge.svg)](https://github.com/kizemo/agentask-relay/actions/workflows/selftest.yml)

启动器退出码决定能不能起环：

[![selftest](https://github.com/kizemo/agentask-relay/actions/workflows/selftest.yml/badge.svg)](https://github.com/kizemo/agentask-relay/actions/workflows/selftest.yml)

| 退出码 | 含义 | 能否起环 |
|---|---|---|
| `0` | 闸门全过，已生成下一环 prompt | 能 |
| `2` | 工作区非法（或计划文档解析不出来、台账闸门缺失） | **不能** |
| `3` | 已有链在跑 / 有阶段 `in_progress` / `blocked` / 阶段已耗尽 | **不能** |
| `4` | 锁被别的会话持有 | **不能** |

[![selftest](https://github.com/kizemo/agentask-relay/actions/workflows/selftest.yml/badge.svg)](https://github.com/kizemo/agentask-relay/actions/workflows/selftest.yml)

激活包把起链写死成四步：跑启动器 → `session_create` 只传 `agent_name` / `title` /
`workspace_dir`（**反斜杠绝对路径**）/ `model` / `content`（**禁止** `effort`、
`defer_first_turn`、`parent_session_id`）→ `relay-lock.ps1 -Action adopt` 带上新会话 id
→ 回读会话核对 `workspace_dir` / 生效模型 / 状态。任一步失败就 `-Action release` 并如实汇报，
不重试。

[![selftest](https://github.com/kizemo/agentask-relay/actions/workflows/selftest.yml/badge.svg)](https://github.com/kizemo/agentask-relay/actions/workflows/selftest.yml)

## 装完目标仓库自动落地

[![selftest](https://github.com/kizemo/agentask-relay/actions/workflows/selftest.yml/badge.svg)](https://github.com/kizemo/agentask-relay/actions/workflows/selftest.yml)

- `docs\relay\start-relay.ps1` + `docs\relay\relay-lock.ps1` + `docs\relay\relay-ledger.ps1`
  —— 装置，与 `device\` 逐字一致；台账回写**只许走 `relay-ledger.ps1`**
  （锁 + CAS + 只追加 + 写后回读），不要在文档或 prompt 里教裸 `Set-Content`。
- `docs\AGENT-RELAY.md` + `docs\RELAY-SOP.md` + `docs\RELAY-ADAPTATION.md`
  —— 协议 / 规程 / 项目裁决骨架。
- `AGENTS.md` 里的受管家规块（`<!-- BEGIN RELAY-PORT -->` 标记），幂等注入；
  已有家规**收编**而非重复追加；标题不含「接力」字样的等价段落现在也能被内容指纹判据认出来。
- `docs\plan-relay.md` —— 探测不到既有计划文档时才生成的计划文档。
- `docs\relay\ACTIVATION-PROMPT.txt`（激活包）+ `docs\relay\install-report.md`。

[![selftest](https://github.com/kizemo/agentask-relay/actions/workflows/selftest.yml/badge.svg)](https://github.com/kizemo/agentask-relay/actions/workflows/selftest.yml)

**`docs\relay.json` 台账由启动器在起链那一刻创建，安装器绝不写它。**

[![selftest](https://github.com/kizemo/agentask-relay/actions/workflows/selftest.yml/badge.svg)](https://github.com/kizemo/agentask-relay/actions/workflows/selftest.yml)

四道并发闸门：原子锁（`FileMode.CreateNew`）/ 台账闸门（有 `in_progress`、`running` 已带
`next_session_id`、`blocked` 或阶段耗尽 ⇒ 拒绝起链）/ 写集指纹
（`git status --porcelain -uall` + `HEAD` + 目标文件指纹）/ 回写 CAS（重读盘比对 `sha256`，只追加）。

[![selftest](https://github.com/kizemo/agentask-relay/actions/workflows/selftest.yml/badge.svg)](https://github.com/kizemo/agentask-relay/actions/workflows/selftest.yml)

## 目录地图

[![selftest](https://github.com/kizemo/agentask-relay/actions/workflows/selftest.yml/badge.svg)](https://github.com/kizemo/agentask-relay/actions/workflows/selftest.yml)

| 路径 | 内容 | 来源 |
|---|---|---|
| `tool/` | **工具本体**（relay-port skill 源）：安装器 + 6 件模板 + 说明书 + 自测证据 | `skills\relay-port\` |
| `device/` | 装置本体 `start-relay.ps1` / `relay-lock.ps1` / `relay-ledger.ps1` + 设计版台账样例 `relay.json` | PractiLog 实测版本 + `maintenance\relay\` |
| `protocol/` | 共享协议层：通用协议 / SOP / 接力 prompt / 指针 / 证据驱动说明（5 件） | `maintenance\relay\` |
| `protocol/probe-ws/` | **通用仓库上的真实链路探针**（非 PractiLog 仓库跑完 3 环的完整产物，5 件） | `maintenance\relay\probe-ws\` |
| `examples/practilog/` | PractiLog 生产级落地面：22 key 完整台账 + 项目裁决实例 + 6 环链路产物 + 门禁与督导留证 + 其 `AGENTS.md` 接力段抽取件 | PractiLog 仓库 |
| `scripts/` | **本仓库自有的维护脚本**（非工具本体）：`selftest.ps1` 一键自测、`publish-relay.ps1` 一致性对账 + 同步、`refresh-manifest.ps1` 清单刷新 | 本仓库生成 |
| `MANIFEST.txt` | 全部文件的 `<sha16> \| <字节> \| <相对路径>`（拷贝留证；**条目数 = 目录文件数 − 1**，不含自身。刷新：`pwsh -File scripts\refresh-manifest.ps1`，必须放在一轮工作的**最后一步**） | 本仓库生成 |
| `HANDOFF.md` | 交接：背景 / 进度 / 已验证·推断·未验证 / 证据路径 / 后续候选 / 工具坑 | 本仓库生成 |
| `AGENTS.md` | 本项目家规 | 本仓库生成 |

[![selftest](https://github.com/kizemo/agentask-relay/actions/workflows/selftest.yml/badge.svg)](https://github.com/kizemo/agentask-relay/actions/workflows/selftest.yml)

所有文件与目录名均为 ASCII，两份 README 的文件列表里都不出现中文。

[![selftest](https://github.com/kizemo/agentask-relay/actions/workflows/selftest.yml/badge.svg)](https://github.com/kizemo/agentask-relay/actions/workflows/selftest.yml)

## 本仓库自带的两个一键脚本

[![selftest](https://github.com/kizemo/agentask-relay/actions/workflows/selftest.yml/badge.svg)](https://github.com/kizemo/agentask-relay/actions/workflows/selftest.yml)

```powershell
# 家规 1 的强制自测：在 %TEMP% 建一次性 git 仓库，真跑安装器/启动器/锁
# （安装、幂等重跑、收编双判据、-PlanDoc 解析、真激活起链、二次起链被拒、锁互斥）。
# 要求 EXIT=0 且 fail=0 才算绿。
pwsh -NoProfile -File scripts\selftest.ps1 -EvidencePath "$env:TEMP\relay-selftest.log"

[![selftest](https://github.com/kizemo/agentask-relay/actions/workflows/selftest.yml/badge.svg)](https://github.com/kizemo/agentask-relay/actions/workflows/selftest.yml)

# 发布口径：device<->templates 硬不变式 + tool<->全局 skill 逐件 sha16 对账，同步 + 复核一次做完
pwsh -NoProfile -File scripts\publish-relay.ps1 -Direction verify    # 只报不改
pwsh -NoProfile -File scripts\publish-relay.ps1 -Direction publish   # 本目录 -> 全局 skill
```

[![selftest](https://github.com/kizemo/agentask-relay/actions/workflows/selftest.yml/badge.svg)](https://github.com/kizemo/agentask-relay/actions/workflows/selftest.yml)

`examples\practilog\docs\relay\` 是历史留证快照，只报 `SNAPSHOT_DRIFT`、不参与判定、
**不要为它同步**。

[![selftest](https://github.com/kizemo/agentask-relay/actions/workflows/selftest.yml/badge.svg)](https://github.com/kizemo/agentask-relay/actions/workflows/selftest.yml)

## 当前状态

[![selftest](https://github.com/kizemo/agentask-relay/actions/workflows/selftest.yml/badge.svg)](https://github.com/kizemo/agentask-relay/actions/workflows/selftest.yml)

- 语料**已全部拷贝进本目录**：逐件与源 sha16 一致（`SHA_MATCH=42 / SHA_MISMATCH=0`）；
  全库 `BOM=0 / .ps1 非 ASCII=0 / md+txt 的 CR=0`，对账留证见 `MANIFEST.txt`。
- 工具**已实现并通过端到端实测**：首批 14 项用例全 PASS
  （`tool\references\selftest-2026-11-25.md`）；批次 B2/B3 的断言集与 raw 日志见同目录
  `-b2.md` / `-b3.md`。最新一轮为 **cases 1-15 / 106 条断言 / 0 失败 / `EXIT=0`**，
  留证 `tool\references\selftest-2026-11-25l.txt` 与 `selftest-2026-11-25l.md`。
- 已修缺陷：**D1** 幂等分支输出变量未初始化 ⇒ 目标项目 `AGENTS.md` 被截断成 0 字节；
  **D2** 干跑证据 0 B；**D3** 安装器 `.ps1` 里写了汉字字面量 ⇒ 无 BOM 时在 Windows PowerShell 5.1
  下会变乱码，已改为码点构造并复测 `NON_ASCII=0 / PARSE_ERRORS=0 / 真实安装 PASS`；
  **D4** 启动器 `-PlanDoc` 默认值是 PractiLog 专用路径 ⇒ 改为解析链，零命中明确报错不静默降级。
- 批次 B3 补上**台账写闸门** `relay-ledger.ps1`（`-Action status` / `-Action commit`）：
  锁 + CAS + 只追加不变式 + 写后回读，文档里的回写配方一律指向它。
- 本仓库已 `git init` 并推到
  [github.com/kizemo/agentask-relay](https://github.com/kizemo/agentask-relay)。
- 还没做：**dogfood**（把 relay-port 装进本仓库自己，让工具的后续候选由链来推进）；
  跨平台审计（macOS/Linux 路径是推断、未实测）；起链前的模型预检。
  见 `HANDOFF.md` 的后续候选清单。
- 自动化覆盖不到的一点：真起链依赖 `session_create`，自测从不调它，
  只断言生成的激活包内容 —— 属「未验证」，别当已验证读。

[![selftest](https://github.com/kizemo/agentask-relay/actions/workflows/selftest.yml/badge.svg)](https://github.com/kizemo/agentask-relay/actions/workflows/selftest.yml)

## 与全局 skill 的关系

[![selftest](https://github.com/kizemo/agentask-relay/actions/workflows/selftest.yml/badge.svg)](https://github.com/kizemo/agentask-relay/actions/workflows/selftest.yml)

| | 作用 | 何时改 |
|---|---|---|
| `tool\`（本目录） | 工作面 / 真源 / 演进位 | 改工具时改这里 |
| `<MCode 数据目录>\skills\relay-port\`（全局） | 实际被会话调用的那一份 | 本目录改完自测通过后**同步过去** |

[![selftest](https://github.com/kizemo/agentask-relay/actions/workflows/selftest.yml/badge.svg)](https://github.com/kizemo/agentask-relay/actions/workflows/selftest.yml)

同步用 `scripts\publish-relay.ps1 -Direction publish`（覆盖 `SKILL.md` / `scripts\` /
`templates\` / `references\` 四处并逐件复核）。改装置模板后还要让 `device\` 保持逐字一致
（`Copy-Item tool\templates\<f> device\<f> -Force`），否则 `publish-relay.ps1` 直接判硬不变式失败。

[![selftest](https://github.com/kizemo/agentask-relay/actions/workflows/selftest.yml/badge.svg)](https://github.com/kizemo/agentask-relay/actions/workflows/selftest.yml)

## 许可

[![selftest](https://github.com/kizemo/agentask-relay/actions/workflows/selftest.yml/badge.svg)](https://github.com/kizemo/agentask-relay/actions/workflows/selftest.yml)

本仓库尚未添加许可（LICENSE）文件，默认保留所有权利。是否选一个许可证属待办，
见 `HANDOFF.md`。
