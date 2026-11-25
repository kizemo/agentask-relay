# selftest 2026-11-25p —— Claude Code 权限层（settings 文件）+ 命令风格规则（B10）

- 权威 raw 日志：`tool\references\selftest-2026-11-25p.txt`
  （`len=16000 cr=0 sha16=8A2E634100BADEE4`，186 行，`CASE_PASS=182` / `CASE_FAIL=0`）
- 跑法：`pwsh -NoProfile -ExecutionPolicy Bypass -File scripts\selftest.ps1 -EvidencePath "<绝对路径>"`
- 判绿口径：`SUITE_END pass=182 fail=0` **且** 进程 `EXIT=0`
- 上一轮基线：`selftest-2026-11-25o` = 175 条断言 / 0 失败 ⇒ 本轮净增 **7 条**

---

## 1. 这一轮改了什么

真链实跑（Claude Code headless）暴露了**权限层缺陷**：子环里所有 `pwsh` / `powershell` 与 Write 全被拒
（`This command requires approval`），台账因此没提交 `stage_done`，链在第 1 环内断掉。

根因（实测三例对照）：**本机 build 忽略 `--permission-mode` / `--allowedTools`**，
**只有 `--settings <文件>` 里的 `defaultMode` + `permissions.allow` 生效**。
完整实验矩阵见 `references\claude-code-permissions-2026-11-25.md`。

| 件 | 动作 |
|---|---|
| `tool\templates\relay-spawn.ps1` | 新增 `$headlessSettings`（单行 JSON）；`-Execute` 时落盘 `docs\relay\relay-settings.json` 并用 `--settings <该文件>` 引用（**不再是内联 JSON**）；新增日志 `SPAWN_SETTINGS_JSON` / `SPAWN_SETTINGS_FILE`；写文件失败 ⇒ `FAIL reason=settings_write_failed` exit 3 |
| `tool\templates\start-relay.ps1` | cli_driver 的 `$sessionRule` 末尾追加「命令风格」规则（Bash 工具、单条命令、相对路径、不串联、不给 flag 加引号）⇒ 规避实测三类拒绝文案；**mcode 分支未动** |
| `device\relay-spawn.ps1` / `device\start-relay.ps1` | 模板逐字副本（`sha16=5E79DC0509C945B2` / `D795D14DDAE16FCC`） |
| `scripts\selftest.ps1` | 增 case 17c（7 条断言） |

---

## 2. case 17c 覆盖了什么（7 条断言）

- `contract_spawn_settings_json_disables_question_box` / `contract_spawn_settings_json_bypass_mode` /
  `contract_spawn_settings_json_allows_pwsh`（3 条）：settings JSON 必须含
  `autoQuestion.enabled=false`、`defaultMode=bypassPermissions`，且 allow 里**显式**列
  `Bash(pwsh:*)` / `Bash(powershell:*)`。
- `contract_spawn_uses_settings_file`（1 条）：命令行必须出现
  `--settings <repo>\docs\relay\relay-settings.json`（**文件路径**，不是内联 JSON）。
- `contract_spawn_no_inline_settings_json`（1 条）：命令行里**不得**再出现内联 `--settings '{...}'`
  （此 build 把它当文件名）。
- `contract_cli_prompt_command_style` / `contract_mcode_prompt_has_no_command_style`（2 条）：
  cli_driver 的 prompt 必须带命令风格规则；**mcode 的 prompt 不得带**（逐字不变）。

---

## 3. 这一轮踩的坑

1. **`--settings` 内联 JSON 会被当文件名**：此 build 只吃文件 ⇒ 报 `Error: Settings file not found`。
2. **`Start-Process -ArgumentList` 数组不自动加引号**：含空格的 prompt 被拆成多个 argv ⇒
   `error: unknown option '-NoProfile'`；必须手工拼整条命令行字符串。
3. **原生 PowerShell 工具在此 build 不可用**：恒报
   `Command contains malformed syntax ... pwsh exited with code 1: 参数太长` ⇒ 子环只剩 Bash 一条路，
   prompt 必须写清命令风格。
4. **settings 写盘失败不能降级**：宁可 exit 3 也不起一个没有权限层的环。

---

## 4. 仍未验证 / 遗留

- codex / openclaw 真链仍未实测（本机未安装）。
- `relay-ledger.ps1` 不校验 `next_session_id` 形态（文档漂移，沿用 B9）。
- 下一环 prompt 的推进靠 LLM 复制 4 个 token（`RELAY_STAGE` / stage 短语 / `RELAY_ARTIFACT` /
  `RELAY_SESSION_ID`）；若真跑显示 LLM 做不好，转 B11 候选（`advance` / `NextPromptOnly`）。
- LICENSE 未决（用户未授权选许可证，沿用 B9）。
