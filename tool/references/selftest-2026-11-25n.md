# selftest 2026-11-25n —— 启动器运行时适配（B10）

- 权威 raw 日志：`tool\references\selftest-2026-11-25n.txt`
  （`len=14783 cr=0 sha16=89E182F7FD10279F`，168 行，`CASE_PASS=164` / `CASE_FAIL=0`）
- 跑法：`pwsh -NoProfile -ExecutionPolicy Bypass -File scripts\selftest.ps1 -EvidencePath "<绝对路径>"`
- 判绿口径：`SUITE_END pass=164 fail=0` **且** 进程 `EXIT=0`
- 上一轮基线：`selftest-2026-11-25m` = 135 条断言 / 0 失败 ⇒ 本轮净增 **29 条**

---

## 1. 这一轮改了什么（B10 启动器运行时适配）

B9 装了「运行时适配层」（安装器 + 家规落点 + 起环驱动），但**启动器自己还写死 MCode**：
`tool/templates/start-relay.ps1` 生成下一环 prompt 时直接喊 `session_create`，
于是 claude-code / codex 装完在**第一棒交接处断链** —— 前面全对，交接那一步没有可执行的东西。
本轮补的就是这一段，并真跑了一条 Claude Code 链。

| 件 | 动作 |
|---|---|
| `tool\templates\start-relay.ps1` | 新增 `-Runtime`；新增「§1b runtime resolution」（`-Runtime` > `docs\relay\relay-runtime.json` > `mcode`；未知运行时 ⇒ `FAIL reason=runtime_unsupported` exit 2）；prompt 按三种 link mode 分支生成：`session_tool`(mcode) / `cli_driver`(claude-code,codex) / `sessions_spawn_tool`(openclaw) |
| `tool\templates\relay-spawn.ps1` | 新增 `-AllowedTools` / `-MaxBudgetUsd` / `-SessionId`；session id 解析改为 `-SessionId` > 台账 `docs\relay.json` 的 `next_session_id` > 新 GUID；claude-code **跑前 pre-adopt** 锁、失败自动 release；干跑不再 pre-adopt |
| `tool\scripts\install-relay.ps1` | `Expand-Template` 新增 `-SpawnCommand`；新增抽取 `<!-- SPAWN_COMMAND_BEGIN/END -->` 标记块；新增写 `docs\relay\relay-runtime.json` 描述符（`runtime` / `next_link_mode` / `spawn_rule` / `spawn_command` / `rule_files` / `installed_at`） |
| `tool\templates\ACTIVATION-SPAWN-{claude-code,codex}.md` | 新增 `<!-- SPAWN_COMMAND_BEGIN/END -->` 单一起环命令真源；STEP 2 改为引用 `{{SPAWN_COMMAND}}`，不再复写命令 |
| `device\start-relay.ps1` / `device\relay-spawn.ps1` | 模板逐字副本（`sha16=E75E6642F56A6F43` / `38A1059B3ACD6B40`） |
| `scripts\selftest.ps1` | 增 case 17（29 条断言） |

**mcode 路径逐字等价**（本轮硬判据）：同一临时仓路径下，
`git HEAD:tool/templates/start-relay.ps1` 生成的 prompt 与新 launcher 生成的 prompt
**逐字节相同**（`OLD_LEN=3844 NEW_LEN=3844 EQUAL=True`）。

---

## 2. case 17 覆盖了什么（29 条断言）

### 2.1 claude-code 装配与启动器（13 条）

- `contract_cc_install_exit_zero` / `contract_descriptor_present` / `contract_descriptor_runtime` /
  `contract_descriptor_mode` / `contract_descriptor_command_portable` /
  `contract_descriptor_rule_files`（6 条）：装完有描述符；`runtime=claude-code`、
  `next_link_mode=cli_driver`；**`spawn_command` 必须是便携式 `{REPO}`**（不是本机绝对路径）；
  `rule_files=AGENTS.md,CLAUDE.md`。
- `contract_launcher_reads_descriptor`（1 条）：启动器**自己**能读描述符，
  回显 `OK runtime=claude-code source=descriptor`（不靠 `-Runtime` 硬传）。
- `contract_prompt_has_stage_header` / `contract_prompt_names_spawn_driver` /
  `contract_prompt_has_spawn_command` / `contract_prompt_no_session_create_call` /
  `contract_prompt_forbids_session_create`（5 条）：prompt 含 `RELAY_STAGE=1`、
  指名 `relay-spawn.ps1`、含起环命令、**不含** `session_create` 调用、且**显式禁止**调用它。
- `contract_launcher_rejects_unknown_runtime`（1 条）：未知运行时 ⇒ exit 2（响亮失败，不静默退回 mcode）。

### 2.2 mcode 与 openclaw 不回归（10 条）

- `contract_mcode_install_exit_zero` / `contract_mcode_mode` / `contract_mcode_no_spawn_command` /
  `contract_mcode_launcher_runtime` / `contract_mcode_prompt_uses_session_create` /
  `contract_mcode_prompt_has_no_stage_header`（6 条）：mcode 仍是 `session_tool`、
  `spawn_command` 为空、prompt 仍走 `session_create` 交接、**且不带** stage header（与 B9 形态一致）。
- `contract_oc_install_exit_zero` / `contract_oc_mode` / `contract_oc_prompt_uses_sessions_spawn` /
  `contract_oc_prompt_no_cli_driver`（4 条）：openclaw 走 `sessions_spawn_tool`，
  prompt 用 `sessions_spawn`，**不误用** CLI 驱动。

### 2.3 起环驱动与装置镜像（6 条）

- `contract_spawn_rejects_bad_session_id`（1 条）：`-SessionId` 非 UUID ⇒ exit 2（`session_id_not_uuid`）。
- `contract_spawn_reads_ledger_session_id`（1 条）：台账 `next_session_id` 优先于新生成，
  回显 `SPAWN_SESSION_ID id=… source=ledger`。
- `contract_spawn_dryrun_no_pre_adopt`（1 条）：干跑**不**碰锁（不 pre-adopt）。
- `contract_device_start_matches_template` / `contract_device_spawn_matches_template` /
  `contract_device_files_ascii_no_bom`（3 条）：`device\` 与 `tool\templates\` 逐字一致；
  `device\*.ps1` 纯 ASCII、无 BOM。

---

## 3. 这一轮踩的坑（新）

1. **断言串写错导致首跑 `pass=162 fail=1`**：唯一红条是 `contract_mcode_prompt_uses_session_create`。
   原断言去匹配 `call session_create with agent_name=me` —— 那句在 `$nextHint` 里、**只在 DryRun 打印**、
   且**不在 prompt 正文内**。改法：断言改成匹配 prompt 内的真实交接语
   `start the next stage with session_create using the same recipe`；
   同时把 CLI 侧反向加固为「**不得**出现 `start the next stage with session_create`」
   并新增 `contract_prompt_forbids_session_create`（匹配 `never call it`）。
   **教训**：写断言要对着**被测产物**（生成的 prompt）写，不要对着**源码变量**写。
2. **描述符必须用 `{REPO}` 占位而不是本机绝对路径**：描述符是要随仓走的。
   安装器把标记块里的 `{{REPO}}` 转成 `{REPO}` 存进描述符，启动器生成 prompt 时再替换成自己的 `$repoRoot`；
   activation packet 仍用原始 `{{REPO}}` 展开。两种形态各司其职，别混。
3. **锁转交前移（pre-adopt）是 claude-code 专属**：claude-code 的 session id 在**跑之前**就知道
   （`--session-id` 主动指定），所以子进程启动前就能把锁转给它，新链从第一秒起就是锁主；
   codex 的 id 只能从输出里抽 ⇒ 只能跑后 adopt。失败时 `release -SessionId` 会校验归属，安全。

---

## 4. 仍未验证 / 遗留

- **codex / openclaw 真链仍未实测**：本机 `codex`、`openclaw` **未安装**。
  两家只到「装配正确 + 命令构造正确 + 干跑不执行」这一层（同 B9）。
- **`relay-ledger.ps1` 不校验 `next_session_id` 形态**：grep `mvs_|sess_|next_owner_only` 零命中。
  `HANDOFF.md` B3 节「台账校验 session id」的说法与代码不符 ⇒ 属**文档漂移**，本批不修。
- **下一环 prompt 的推进靠 LLM 复制 3 个 token**（`RELAY_STAGE` / `relay stage N` 短语 / `RELAY_ARTIFACT`）。
  若真跑显示 LLM 做不好，转 B11 候选（`advance` / `NextPromptOnly` 机制）。
- `via=probe-multi` 多命中择优、`profile_probe_disabled` 降级路径仍未实测（沿用 B9）。
- case 15 在 CI（`windows-latest` 无已装 skill ⇒ 走 `loud_fail` 分支）的线上稳定性未验证。
- **LICENSE 未决**：用户未授权选许可证，本次不擅自新增（沿用 B9）。
