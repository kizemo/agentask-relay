# RELAY-ADAPTATION.md —— 本项目接力裁决

> 通用协议见 `docs/AGENT-RELAY.md`（自包含、全部仓库相对路径）。
> 本文件是**本项目专属裁决**：优先级高于通用协议，低于 `AGENTS.md` 其余家规。
> 由 relay-port 安装器生成骨架；标了 `TODO` 的小节**必须在首次激活前补全**。

## 1. 项目身份

- 项目名：{{REPO_NAME}}
- 仓库根（绝对路径，反斜杠，用于 `session_create.workspace_dir`）：{{REPO}}
- 计划文档（仓库相对）：{{PLAN_DOC}}
- 本轮目标：{{TARGET}}
- 计划阶段数：{{MAX_STAGES}}
- 安装日期：{{DATE}}

## 2. 阶段拆分

{{STAGE_LIST}}

> 每阶段的 acceptance 判据写进计划文档（`{{PLAN_DOC}}`）；接力链每一环都把计划文档当真源读。

## 3. 写集与并发检测（TODO，必填）

- 允许被 agent 修改的目录 / 文件（逐条列全，写死）：
  - `TODO`
- 禁止触碰（发布脚本、CI、签名、密钥、用户数据、门禁阈值）：
  - `TODO`
- 并发检测口径（先跑什么命令，看到什么就停）：
  - `TODO`

## 4. 验收门禁（TODO，必填）

- 门禁命令：`TODO`（例：`pwsh -NoProfile -File reports\<gate>.ps1 -ExpectDesktopTests <N>`）
- 判绿口径：**只认产物文件里的结论字段**（例如 summary.txt 的 `GATE_VERDICT`），**不认管道末端的 `$LASTEXITCODE`**。
- 核数口径：`git status --porcelain` 一律带 `--untracked-files=all`。
- 门禁脚本的阈值与白名单属**人工验收点**，agent 不得自行修改。

## 5. 模型与额度策略（可沿用默认，勿传 effort）

- 首选：`minimax/MiniMax-M3`
- 日间回退：`custom_provider:provider-aa5659/auto`（08:00-19:00 Asia/Shanghai）
- 夜间回退：`custom_provider:provider-aa5659/deepseek-v4.1-flash-1017`（19:01-08:00 Asia/Shanghai）
- 上面两条 `custom_provider:provider-*` 是**本机 provider 注册 id**，属 device-specific, refill 项：换机器或换
  profile 必须重填，否则回退那一环会指向不存在的 provider，白烧一轮才暴露。`tool\scripts\install-relay.ps1`
  不会替你校验它（静态审计见 `tool\references\portability-audit-2026-11-25.md`）。
- `session_create` **没有** `effort` 字段，任何情况下都不传；同样禁传 `defer_first_turn` / `parent_session_id`。
- 建环即开跑（`turn.mode=activated`）：建环后立刻 `session get` 回读 `workspace_dir` / `effective_model` / `status` 三要素再登记。
- 判活看 `session messages` 末条 timestamp，**不看** `session get.updatedAt`。

## 6. 人工验收点（命中即停链写 blocked）

- git commit / push / tag / stash / checkout
- 发布 / 部署 / 分发产物
- 删除或覆盖用户数据
- 付费、配额、账号、权限
- 改用户级 hook / provider 配置
- 改门禁脚本阈值与白名单
- 与其它会话的写集冲突

## 7. 停链条件

- 全部验收判据成立且门禁绿 → `status=done`
- 命中人工验收点 → `status=blocked`（写明缺什么）
- `current_stage >= max_stages` → `status=blocked`
- 同一验收连续两次失败 → `status=blocked`
- 连续两阶段超出工具调用预算（单环 >40 次）→ `status=blocked`

## 8. 起链与交接

- 起链只能由**用户在本项目会话内**明确指令触发；启动器：`docs\relay\start-relay.ps1`。
- 激活包：`docs\relay\ACTIVATION-PROMPT.txt`（用户一句话即可起链）。
- 每环落盘：`docs\relay\stage-<N>-<短名>.md`，编号逐字续编，不新建跨项目指针。
- 台账：`docs\relay.json`，回写只许追加，回写前必须重读盘。
