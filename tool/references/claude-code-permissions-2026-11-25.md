# Claude Code headless 权限层实测（B10，2026-11-25）

## 结论一句话

无头子进程要无人值守跑 `pwsh` / `Write`，**决定性因素不在"哪个旗标"，而在这条命令行的形状**：`claude` 的参数解析在**第一个位置参数（prompt）处停止**，写在 prompt 之后的每一个旗标都被丢弃——`--settings`、`--permission-mode`、`--allowedTools`、`--add-dir`、`--session-id`、`--output-format` 全都在内，于是链跑在 `default` 模式里，任何 `pwsh` 都在等一个永远不会来的批准。**旗标放在 prompt 之前**时，`--permission-mode bypassPermissions`、`--dangerously-skip-permissions --allow-dangerously-skip-permissions`、`--settings <文件>` **三者各自单独都有效**。

## 更正：本文件早前四条结论已被证伪

初稿把失败归因到"只有 `--settings` 生效"，那是**把同一条命令行的两个变量混成一个**。收尾轮逐条对照后作废：

| 早前结论 | 实测结论 |
|---|---|
| 只有 `--settings <文件>` 生效 | **伪**。三个旗标在 prompt 之前时各自单独有效 |
| `--permission-mode bypassPermissions` 被忽略 | **伪**。之前"被忽略"是因为它排在 prompt 之后 |
| `--allowedTools` 被忽略 | **伪**。同上，是位置问题，不是旗标问题 |
| 路径正反斜杠是分水岭 | **伪**。与成败无关 |
| prompt 未送达子进程 | **伪**。prompt 送达了，是它后面的旗标没送达 |

真正的第二个独立缺陷是 settings 的**键位嵌套**：顶层 `defaultMode` 本 build **读而不施**，有效键是 `permissions.defaultMode`。两个缺陷同现时症状一样（都是 `default` 模式、`pwsh` 需批准），把排查带偏了两轮。

## 现场

- 运行时：`C:\Users\Duanyi\.local\bin\claude.exe`，版本 `999.0.0-local`
- 真链仓（二次失败现场）：`C:\Users\Duanyi\AppData\Local\Temp\relay-b10-live2\repo`
- 子环会话：`181cde47-0b2f-45cd-bab5-28f2c6568a93`
- 子环 transcript：`C:\Users\Duanyi\.claude\projects\C--Users-Duanyi-AppData-Local-Temp-relay-b10-live2-repo\181cde47-0b2f-45cd-bab5-28f2c6568a93.jsonl`（68 条）
- 第三、四条真链：`relay-b10-live3` 子环 `5c8791d2-0e84-4c4e-8511-2759308c172e`（58 行 transcript）、`relay-b10-live4` 子环 `f30a847d-7a58-4d6c-919a-69d239f2021b`（`pmode=default`，旗标被丢弃的直接证据）

## 症状

子环（stage 1）所有 `pwsh` / `powershell` 调用与 Write 全被拒：

- `Bash pwsh ...` / `Bash powershell ...` → `This command requires approval`
- `Write docs\relay\stage-1-inventory.md` → `Claude requested permissions to write to ...`
- 原生 `PowerShell` 工具 4 次调用全部失败：`Command contains malformed syntax ... pwsh exited with code 1: 参数太长`（连 `Get-Location; Get-ChildItem docs/relay` 都挂）⇒ **此 build 的原生 PowerShell 工具不可用，只剩 Bash 一条路**
- 同一轮里 `Bash ls docs/relay` 与 `Bash find ...` **成功** ⇒ 不是工具坏了，是**嵌套 shell 命中了权限规则**

台账因此没有提交 `stage_done`，也没有起第 2 环。

## 排除法（本机实际查过）

| 怀疑对象 | 结论 |
|---|---|
| `~/.claude/settings.json` 的 `defaultMode=bypassPermissions` | 已存在；顶层键**读而不施**，不能作为放行依据 |
| hook `no-delete-gate.py` | ASK/DENY 模式表**不含** `pwsh`/`powershell`，`main()` 对安全命令直接放行 ⇒ 不是元凶 |
| hook `ctx-budget-guard.py` | 硬闸门 160,000 token，子环当时仅 ~68K ⇒ 不触发 |
| hook `tool-call-budget.py` | 明确 non-blocking（只加 additionalContext）⇒ 不阻断 |
| hook `guard-secret-files.js` / `subagent-guard.py` | 不覆盖 shell 命令前缀 |
| managed settings | 本机**无** `C:\ProgramData\ClaudeCode\managed-settings.json` |
| project policy | 真链仓**无** `.claude\` 目录；本机**无** `~/.claude/settings.local.json` |

## 命令行形状铁律（这就是缺陷本身）

```
# 错：旗标写在 prompt 之后 → 全部被丢弃（json=False / session_id 丢失 / default 模式）
claude -p "<prompt>" --output-format json --session-id <uuid> --add-dir <dir> --permission-mode bypassPermissions --allowedTools Bash,... --settings <file> --max-budget-usd 1.5

# 对：旗标全部在前，prompt 最后（json=True / session_id 命中 / 权限层生效）
claude --output-format json --session-id <uuid> --add-dir <dir> --permission-mode bypassPermissions --allowedTools Bash,... --settings <file> --max-budget-usd 1.5 -p "<prompt>"
```

`relay-spawn.ps1` 的 `$cmdArgs` 已按此重排（旗标在前、`@('-p', $promptText)` 最后），日志里 `SPAWN_COMMAND` 打的 `$display` 镜像真实 argv，selftest case 17d 断言四件事：`-p <prompt from file>` 必须是最后一个参数、`--settings` 在 prompt 之前、`--permission-mode` 在 prompt 之前、settings JSON 里 `"permissions":{"defaultMode":"bypassPermissions"`。

## 生效的 settings 配方

写入 `<workspace>\docs\relay\relay-settings.json`（`relay-spawn.ps1 -Execute` 自动落盘，内容同时打进日志 `SPAWN_SETTINGS_JSON`）：

```json
{"autoQuestion":{"enabled":false},"defaultMode":"bypassPermissions","permissions":{"defaultMode":"bypassPermissions","allow":["Bash","Bash(pwsh:*)","Bash(powershell:*)","Read","Write","Edit","Glob","Grep"]}}
```

- `permissions.defaultMode` 是**有效键**；顶层 `defaultMode` 留着只为兼容别的 build，本机不施效。
- `Bash(pwsh:*)` / `Bash(powershell:*)` 必须**单列**：实测普通 `Bash ls ...` 放行，而 `Bash pwsh ...` 这类嵌套 shell 需要显式规则才放行。
- `autoQuestion.enabled=false` 关掉交互提问框 —— headless 下没人回答，提问即挂死。
- 写文件失败时 `relay-spawn.ps1` 以 `FAIL reason=settings_write_failed`（exit 3）中止：**宁可不起环，也不起一个没有权限层的环**。

## 等效旗标（各自单独有效，仍须在 prompt 之前）

- `--permission-mode bypassPermissions`
- `--dangerously-skip-permissions --allow-dangerously-skip-permissions`

settings 文件与旗标**可叠加**，但把权限只押在旗标上会丢掉 `autoQuestion` 与 `allow` 明细，因此启动器固定走 settings 文件 + `--permission-mode` 双保险。

## 两条工程事实（同一 build）

1. `--settings` **只吃文件**。传内联 JSON 会被当成文件名 ⇒ `Error: Settings file not found`。
2. `Start-Process -ArgumentList` 传**数组时不自动加引号**。含空格的 prompt 会被按空格拆成多个 argv ⇒ `error: unknown option '-NoProfile'`。必须手工拼整条命令行字符串。

## 连带改的 prompt 规则

子环只剩 Bash 一条路，因此 cli_driver 的接力 prompt 追加了**命令风格**规则（见 `tool/templates/start-relay.ps1` 的 `$sessionRule`）：

> run every relay script with the Bash tool, one command per call, plain relative paths, no chained commands and no quoted flag values

针对的是实测三类拒绝文案：multiple operations / quoted characters in flag names / UNC path。mcode 分支的 prompt **逐字未改**（由 selftest `contract_mcode_prompt_has_no_command_style` 断言守住）。

## 已试过并确认无效的方法（别重试）

- 把任何旗标写在 prompt 之后（解析器在那里停止）。
- 在子环里用原生 `PowerShell` 工具跑任何命令（恒报 malformed syntax）。
- 只靠 `~/.claude/settings.json` 的顶层 `defaultMode`（读而不施）。
- `--settings` 传内联 JSON。
- `claude --model claude-haiku-4-5` ⇒ `API Error: 400 ... "Model not exist."`（不指定 model，用默认）。