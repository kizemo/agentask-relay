# selftest 2026-11-25m —— 运行时适配层（B9）

- 权威 raw 日志：`tool\references\selftest-2026-11-25m.txt`
  （`len=12715 cr=0 sha16=0B8246FFDD9F17F9`，139 行，`CASE_PASS=135` / `CASE_FAIL=0`）
- 跑法：`pwsh -NoProfile -ExecutionPolicy Bypass -File scripts\selftest.ps1 -EvidencePath "<绝对路径>"`
- 判绿口径：`SUITE_END pass=135 fail=0` **且** 进程 `EXIT=0`
- 上一轮基线：`selftest-2026-11-25l` = 106 条断言 / 0 失败 ⇒ 本轮净增 **29 条**

---

## 1. 这一轮改了什么（B9 运行时适配层）

装置本体一套，**运行时**决定两件事：**家规落到哪些文件**、**下一环怎么起**。

| 件 | 动作 |
|---|---|
| `tool\scripts\install-relay.ps1` | 重写：新增 `-Runtime`（`mcode` / `claude-code` / `codex` / `openclaw`）；原 AGENTS.md 注入逻辑整体搬进 `Install-RuleBlock`，支持多目标文件、逐文件 EOL 归一化、BOM 保留；新增按目标文件回读 marker 与 spawn 脚本 ASCII/BOM 自检 |
| `tool\templates\relay-spawn.ps1` | **新**：起环驱动（claude-code / codex）。默认只干跑打印命令，`-Execute` 才真跑；从输出抽 `"session_id"` / `"thread_id"`；`-AdoptLock` 自动转交锁 |
| `device\relay-spawn.ps1` | **新**：模板逐字副本（`sha16=D267199D611CC109`） |
| `tool\templates\ACTIVATION-SPAWN-<runtime>.md` | **新** 4 份：每份含 `<!-- SPAWN_RULE_BEGIN -->…<!-- SPAWN_RULE_END -->` 单一真源 + STEP 2/3/4 正文 |
| `tool\templates\ACTIVATION-PROMPT.md` | 重写：runtime 参数化，STEP 2-4 用 `{{SPAWN_STEPS}}` 占位 |
| `tool\templates\AGENTS-RELAY-BLOCK.md` | §A.5 改为「运行时 = `{{RUNTIME}}` + `{{SPAWN_RULE}}`」；§B.9 改为「按 §A.5 的起环方式起下一环」 |
| `tool\templates\RELAY-ADAPTATION.md` | 增第 9 节「运行时与起环方式」，含 `{{RUNTIME}}` / `{{SPAWN_RULE}}` / `{{RULE_FILES}}` 与四运行时约束 |
| `tool\templates\AGENT-RELAY.md` | 增 §10「运行时适配」（10.1 对照表 / 10.2 双写原因 / 10.3 链形态差异 / 10.4 起环驱动 / 10.5 OpenClaw 硬约束 / 10.6 换运行时规矩）；§3 标注「MCode 运行时专用」并指向 §10 |
| `protocol\AGENT-RELAY.md` | 与模板逐字镜像（`Copy-Item`，硬不变式） |
| `tool\SKILL.md` | 装置件清单加 `relay-spawn.ps1`；调用参数加 `-Runtime`；新增「运行时适配」节；装置契约补起环驱动；自检口径从「两个 `.ps1`」改为「三个 `.ps1`」；边界补 `relay-spawn.ps1` |
| `scripts\publish-relay.ps1` | 装置件硬不变式表加 `relay-spawn.ps1`（templates ↔ device） |
| `scripts\selftest.ps1` | 增 case 16；前置件清单加 `relay-spawn.ps1`；交叉字面量 token 加 `CLAUDE_MARKERS` |
| `README.md` / `README.zh-CN.md` | 重写：去掉重复 badge；补「作用 / 价值 / 安装部署」三段；补运行时选择表与四家部署指导索引 |
| `tool\references\runtime-portability-2026-11-25.md` | **新**：四运行时可移植性分析（已验证 / 推断 / 未验证分栏） |
| `tool\references\deployment-claude-code.md` / `deployment-codex.md` / `deployment-openclaw.md` | **新**：逐家部署指导 |

---

## 2. case 16 覆盖了什么（29 条断言）

### 2.1 运行时落点与注入（17 条）

- `runtime_cc_*`（8 条）：`-Runtime claude-code` 装完 **同时**有 `AGENTS.md` 与 `CLAUDE.md` 两份家规块；
  安装器回显 `AGENTS_MARKERS begin=1 end=1` **且** `CLAUDE_MARKERS begin=1 end=1`；
  `AGENTS.md` 里注入了 Claude Code 版的起环规则（`Claude Code has no \`session_create\` tool`）；
  激活包里有 `-Runtime claude-code` 与 `RELAY_SPAWN_OK runtime=claude-code`。
- `runtime_cx_*`（4 条）：`-Runtime codex` 只写 `AGENTS.md`，**不产 `CLAUDE.md`**；家规块注入 Codex 版起环规则。
- `runtime_oc_*`（3 条）：`-Runtime openclaw` 写 `AGENTS.md`，家规块注入 `sessions_spawn` 版起环规则。
- `runtime_unknown_*`（2 条）：`-Runtime gemini-cli` ⇒ 退出码 `2` + `reason=runtime_unsupported`（**响亮失败**，不静默退回默认）。
- `runtime_default_is_mcode` / `runtime_mcode_activation_uses_session_create` / `runtime_shards_present`（3 条）：
  默认运行时仍是 `mcode` 且行为不变；激活包仍走 `session_create`；`ACTIVATION-SPAWN-*.md` 四份齐全。

### 2.2 起环驱动 `relay-spawn.ps1`（12 条）

- `spawn_installed_into_relay_dir` / `spawn_device_copy_matches_template`（2 条）：装进 `docs\relay\`；与 `device\` 逐字一致。
- `spawn_dryrun_*`（4 条）：干跑退出码 0、打印 `SPAWN_COMMAND claude … --output-format json`、
  末行 `SPAWN_EXECUTE=false`（**默认不执行**）、**prompt 不内联进命令行**（用 `<prompt from file>` 占位）。
- `spawn_codex_dryrun`（1 条）：`-Runtime codex` 打印 `SPAWN_COMMAND codex exec …`。
- `spawn_rejects_non_cli_runtime`（1 条）：`-Runtime mcode` ⇒ 退出码 `2` + `reason=runtime_not_cli`。
- `spawn_missing_prompt_file`（1 条）：prompt 文件不存在 ⇒ 退出码 `2` + `reason=prompt_file_missing`。

---

## 3. 这一轮踩的坑（新）

1. **重写安装器时把机读字面量 `AGENTS_MARKERS` 改成了动态拼接**
   （原为 `Log ($t.Label + '_MARKERS …')`）。case 13f 的「文档 ↔ 代码交叉字面量检查」因此判红：
   `protocol_documents_installer_literals INSTALLER doc_missing=[] code_missing=[AGENTS_MARKERS]`。
   修法：给每个规则目标加**显式** `Markers` 字段（`AGENTS_MARKERS` / `CLAUDE_MARKERS`），日志打 `$t.Markers`；
   同时把 `CLAUDE_MARKERS` 加进 selftest 的 token 清单，让双写这条新不变式也被交叉检查守住。
   **教训**：装置的机读字面量是 selftest 的**契约面**，重构时不能把字面量变成运行时拼接的结果 ——
   拼出来运行时对，源码里查不到，检查照样红。
2. 第一次跑完是 `pass=134 fail=1`，**只有这一条红**，其余 134 条全绿 ⇒
   安装器重写没有改变既有行为（case 1–15 的 106 条基线 + 新增 28 条）。
3. `write` 重写长文件后仍要**按节标题回读**（本轮 `tool\scripts\install-relay.ps1` 23773 B、
   `AGENT-RELAY.md` 21489 B 均已逐节核对），沿用上一轮记下的教训。

---

## 4. 仍未验证 / 遗留

- **三家 CLI 运行时的真起链一律未实测**：本机只装了 Claude Code（`%USERPROFILE%\.local\bin\claude.exe`），
  `codex` 与 `openclaw` **未安装**。case 16 只验证到「装置装配正确 + 起环命令构造正确 + 干跑不执行」，
  **没有**真的跑过一条 `claude -p` 链。跑通后应把结论回写本文件与
  `tool\references\runtime-portability-2026-11-25.md` 的「未验证」栏。
- `via=probe-multi` 多命中择优、`profile_probe_disabled` 降级路径仍未实测（沿用上一轮）。
- case 15 在 CI（`windows-latest` 无已装 skill ⇒ 走 `loud_fail` 分支）的线上稳定性未验证。
- 套件仍不调 `session_create`：真实起链一跳属人工。
- **LICENSE 未决**：用户未授权选许可证，本次不擅自新增；README 与 `HANDOFF.md` 保留「保留所有权利」并列为开放项。
