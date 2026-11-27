# Claude Code 项目登记册：为什么临时夹具会变成「一堆新建项目」（2026-11-27）

本文回答一个现场问题：**在 Claude Code 桌面端（cc-haha）用 relay-port 接力，链子没有进原来的项目，
侧栏反而多出一堆新项目**。结论先给：

> **不是装置把链接错了项目，也不是桌面端的 bug。是「真链验证用的临时夹具」在 Claude Code 的
> 用户级项目登记册里留下了条目，而桌面端正是把这个目录当项目列表渲染的。**

---

## 1. 机制：Claude Code 按「工作目录」分项目

Claude Code 把每个会话按 **cwd** 归档到：

```
<user profile>\.claude\projects\<mangled-cwd>\
```

`mangled-cwd` 的规则是：**路径里所有非字母数字字符一律换成 `-`**。实测：

| 真实 cwd | 登记册目录名 |
|---|---|
| `C:\Users\Duanyi\AppData\Local\Temp\relay-b10-exp4-d1` | `C--Users-Duanyi-AppData-Local-Temp-relay-b10-exp4-d1` |
| `F:\soft\00selfmade\agentask-relay` | `F--soft-00selfmade-agentask-relay` |

桌面端（cc-haha）**没有自己的 projects 表**（`cc-haha\db\index-v1.sqlite` 里没有 `projects` 表），
它直接扫描 `~/.claude/projects\` 下的目录，把每个目录当成一个「项目」显示。所以：

- **真实项目跑链** → 登记册里出现该项目的目录 → 侧栏里这是对的（应当出现）；
- **临时夹具跑链** → 登记册里出现 `C--Users-...-Temp-relay-b17-e2e-...-repo` 这种目录 →
  侧栏里就是一堆用户从没要求过的「新项目」。

登记册是**用户级**的，不随夹具目录一起消失：夹具删了，条目还在，于是「新建了很多项目」。

## 2. 污染从哪来：真链验证的临时夹具

本仓库的 relay-port 在 claude-code 运行时上做真链验证（`tool\references\live-chain-b10-*.md`、
`live-chain-b13-*.md`、`tool\references\selftest-2026-11-26-b17.md`），做法是：在 `%TEMP%` 下建一个
一次性 git 仓库当夹具，在里面真跑 `claude -p`。**每一次这样的运行都会在用户级登记册里落一个条目。**

2026-11-27 现场清点：`~/.claude/projects` 共 44 个目录，其中 **17 个**是本次验证留下的夹具条目
（`relay-b10-exp3/exp4/exp5/live2/live3/live4/permt`、`relay-b13-e2e*`、`relay-b17-e2e*`），
它们与 cc-haha 侧栏里那批 `repo` / `e1`~`e4` / `d1`~`d4` 一一对应。

**这些条目不是「链子接错项目」**：真正的链子落点一直是对的（例：ecclaw 的链全部落在
`F--soft-00selfmade-ecclaw`，142 个 jsonl，cwd 均为 `F:\soft\00selfmade\ecclaw`）。

## 3. 踩过的坑：CLAUDE_CONFIG_DIR 在本机 Claude 构建上不生效

最直觉的隔离办法是把 `CLAUDE_CONFIG_DIR` 指向一个临时目录，让夹具的会话落在临时登记册里。
**实测失败**（`reports\iso-probe.ps1`，claude `999.0.0-local`）：

```
CLAUDE_EXIT=0                      # 隔离目录为空：构建根本没用它
CLAUDE_OUT={"type":"result",...,"result":"OK",...}
NEW_USER_PROJECT_DIRS=C--Users-Duanyi-AppData-Local-Temp-relay-iso-probe-20261127-103419-work
CFG_TREE_BEGIN
CFG_TREE_END                        # 临时配置目录里一个文件都没有
```

即：该构建仍写 `<user profile>\.claude\projects\`，且照常读用户级 `~/.claude.json` / `~/.claude\settings.json`。
⇒ **隔离环境变量这条路在当前构建上走不通**，只能用「跑完把条目挪走」的办法。

## 4. 处置：`-EphemeralWorkspace`（本次新增）

`relay-spawn.ps1` 新增开关 `-EphemeralWorkspace`（claude-code 运行时生效）：

1. 起子进程**之前**快照所有候选登记册：`CLAUDE_CONFIG_DIR\projects`，以及**运行时推导**出来的
   profile 下的 `.claude\projects`（`HOMEDRIVE`+`HOMEPATH` 与 `ApplicationData` 上溯两路都查，
   因为不同构建挑的落点不同）。装置代码里**不写死**任何 home 路径（家规：代码里不许出现 home 字面量），
   全部由环境变量在运行时算出来；
2. 子进程跑完后，把**本次子进程新建的那一个**条目（键名 = 工作目录的 mangled 形式）从登记册挪到
   登记册旁边的 `_relay-ephemeral\<key>-<时间戳>\`；
3. **挪走而不是删掉**：会话转写仍在盘上（留证），只是不再被桌面端当成项目显示；
4. 条目是快照里就有的 ⇒ **绝不碰**（真实项目目录不会被误伤）。

启动器 `start-relay.ps1` 同步加了同名开关：带 `-EphemeralWorkspace` 起链时，写进 prompt 的
spawn 命令会带上该开关，于是**链上每一环**（子环自己再起下一环）都自动清理自己那条条目。

```powershell
# 临时夹具里起一条链（不污染用户项目列表）
pwsh -NoProfile -ExecutionPolicy Bypass -File '<fixture>\docs\relay\start-relay.ps1' `
  -Target '<批次>' -MaxStages 2 -EphemeralWorkspace
```

**默认关闭**：真实项目**必须**继续出现在桌面端的项目列表里，装置无权替用户隐藏它。

## 5. 判据（鉴别力：好样本 / 坏样本各跑一次）

`scripts\selftest.ps1` 的 case 27 用一个假 `claude`（PATH 优先的 `claude.cmd`）真实跑起环驱动两遍：

| 样本 | 命令 | 期望 | 实际判据 |
|---|---|---|---|
| 坏样本 | 不带 `-EphemeralWorkspace` | 条目**留下**（证明夹具真的会写登记册，否则下面的绿是假绿） | `ephemeral_entry_appears_without_the_switch` |
| 好样本 | 带 `-EphemeralWorkspace` | 条目**消失**、转写**留证**、别的登记册**不受影响** | `ephemeral_entry_is_gone_after_the_switch` / `ephemeral_transcript_is_kept_as_evidence` / `ephemeral_cleanup_touches_no_other_registry` |

## 6. 已清理的存量（2026-11-27）

17 个夹具条目已用可恢复删除（`mavis-trash.cmd`）清出 `~/.claude/projects`，随后又补回一个误删的
真实项目目录 `F--soft-00selfmade-agentask-relay`（原为空目录，已按原样恢复）。
清理后登记册 29 个目录（2026-11-27 11:0x 复点），全部对应真实项目（ecclaw / filemanager /
agentask-relay / …），**无 relay 夹具条目、无探针残留**。

**桌面端需要刷新或重启才会不再显示那些条目** —— 它的列表是渲染时扫描目录得到的。
