# selftest 2026-11-25o —— 链逻辑 session id 前置分配 + 权限旗标（B10）

- 权威 raw 日志：`tool\references\selftest-2026-11-25o.txt`
  （`len=15577 cr=0 sha16=65C1B10CE6643FC6`，179 行，`CASE_PASS=175` / `CASE_FAIL=0`）
- 跑法：`pwsh -NoProfile -ExecutionPolicy Bypass -File scripts\selftest.ps1 -EvidencePath "<绝对路径>"`
- 判绿口径：`SUITE_END pass=175 fail=0` **且** 进程 `EXIT=0`
- 上一轮基线：`selftest-2026-11-25n` = 164 条断言 / 0 失败 ⇒ 本轮净增 **11 条**

---

## 1. 这一轮改了什么

上一轮（`n`）把「启动器运行时适配」铺好了，但真链实跑暴露两件事：

1. **CLI 运行时没有 `session_create` 回传会话 id** ⇒ 链的 session id 必须由**启动器**在起链前分配好，
   写进台账 `next_session_id` 与 prompt 的 `RELAY_SESSION_ID=` 行；子环据此 renew / release 锁。
2. **子环的权限闸门**原本靠 CLI 旗标（`--permission-mode` / `--allowedTools`）。

本轮把这两件事固化进装置与断言。**旗标那一半随后被实测证伪**，见
`selftest-2026-11-25p.md` 与 `references\claude-code-permissions-2026-11-25.md`。

| 件 | 动作 |
|---|---|
| `tool\templates\start-relay.ps1` | 分配链逻辑 session id，写进台账 `next_session_id` 与 prompt；prompt 的停链规则点名 `RELAY_SESSION_ID` |
| `tool\templates\relay-spawn.ps1` | session id 解析链 `-SessionId` > 台账 `next_session_id` > 新 GUID；新增 `-AllowedTools` / `-MaxBudgetUsd`；claude-code 分支加 `--permission-mode bypassPermissions` / `--allowedTools` / `--max-budget-usd` |
| `device\start-relay.ps1` / `device\relay-spawn.ps1` | 模板逐字副本 |
| `scripts\selftest.ps1` | 增 case 17b（11 条断言） |

---

## 2. case 17b 覆盖了什么（11 条断言）

- `contract_launcher_allocates_chain_session_id`（1 条）：启动器在 cli_driver 模式下分配链逻辑 session id，
  回显 `OK link_mode=cli_driver chain_session_id=<uuid>`。
- `contract_prompt_carries_session_id` / `contract_prompt_stop_rule_names_session_id`（2 条）：
  prompt 的 `RELAY_SESSION_ID=` 行与「停链时用哪个 id release 锁」的规则指向同一个 uuid。
- `contract_spawn_permission_mode_never_asks` / `contract_spawn_disables_question_box`（2 条）：
  起环命令恒带不提问的权限配置。
- `contract_mcode_prompt_has_no_session_id`（1 条）：mcode 分支**不**带 `RELAY_SESSION_ID`
  （mcode 的 id 由 `session_create` 返回，启动器不预分配 ⇒ mcode 路径不回归）。
- `contract_spawn_rejects_missing_workspace`（1 条）：`-WorkspaceDir` 缺失 ⇒ exit 2。
- `contract_live_install_exit_zero` / `contract_live_launcher_exit_zero`（2 条）：
  **真仓**（临时 git 仓 + 真实安装 + 真实启动）跑通。
- `contract_live_ledger_carries_session_id` / `contract_live_prompt_session_id_matches_ledger`（2 条）：
  真仓产出的台账 `next_session_id` 与 prompt 里的 `RELAY_SESSION_ID` **逐字一致**。

---

## 3. 这一轮踩的坑

1. **mcode prompt 不能带 session id**：mcode 的会话 id 是 `session_create` 的返回值，
   启动器预分配的 id 对它无意义 ⇒ 用 `contract_mcode_prompt_has_no_session_id` 钉死。
2. **`claude --session-id` 不被遵守**：本机 build 下子环的真实会话 id 与命令行给的 id 不同
   ⇒ **链的 session id 与运行时的内部会话 id 必须分开**，链只认台账里那一个。

---

## 4. 仍未验证 / 遗留

- **权限旗标那一半在下一轮被实测证伪**：`--permission-mode` / `--allowedTools` 在本机 build 上被忽略，
  只有 `--settings <文件>` 生效 ⇒ 见 `selftest-2026-11-25p.md` 与
  `references\claude-code-permissions-2026-11-25.md`。
- 真链（Claude Code）当时**仍在第 1 环内失败**：子环的 `pwsh` 与 Write 全被拒 ⇒ 见 `p`。
- codex / openclaw 真链仍未实测（本机未安装）。
