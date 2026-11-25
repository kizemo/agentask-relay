# selftest 留证 2026-11-25 l（F4 修复收口跑）

raw 日志：`F:\soft\00selfmade\agentask-relay\tool\references\selftest-2026-11-25l.txt`
（本文件与 raw 日志同批收口，LF / `cr=0`）

## 结论

`EXIT=0`、**`pass=106 fail=0`**（`SUITE_END pass=106 fail=0`）。
本批套件从 100 断言增至 106 断言（+6，全部来自新 case 15），新增项**首跑即绿**。

本轮只动**仓库侧门禁** `scripts\publish-relay.ps1` 与套件 `scripts\selftest.ps1`：
交付 kit（`tool\templates\` / `device\`）**零改动**，故不存在 templates↔device 逐字同步问题
（publish 的硬不变式仍全 PASS）。改动内容是 F4 的 skill root 自动解析，见
`F:\soft\00selfmade\agentask-relay\tool\references\portability-audit-2026-11-25.md` 的 F4 小节。

## 跑法（本轮实测可用）

```powershell
$ErrorActionPreference='Stop'; $r='F:\soft\00selfmade\agentask-relay'
& pwsh -NoProfile -ExecutionPolicy Bypass -File "$r\scripts\selftest.ps1" `
  -EvidencePath "$r\tool\references\selftest-2026-11-25l.txt"
```

`-EvidencePath` **必须给绝对路径**，否则套件打 `WARN evidence_path_not_absolute_ignored` 且不落盘。
全量耗时约 75-80 s（本轮 `20:31:53` 建根 → `20:33:09` 写证据），建议后台跑。
套件在 `%TEMP%\relay-port-selftest\<时间戳>` 建一次性 git 仓库，默认**不清理**（保留以便复验），
要清理加 `-Cleanup`。

本轮**不再**把控制台副本写进 `reports\`：上一批 `Out-File -Encoding utf8` 落 CRLF，
`reports\selftest-2026-11-25k-console.txt` 带 104 个 CR，会污染 `refresh-manifest.ps1` 的
`MD_TXT_CR_TOTAL` 门禁（家规 4）。raw 日志由套件自己以无 BOM + LF 写出，权威留证只需 `.txt`。

## 证据文件回读值（当场复核，非抄摘要）

| 项 | 值 |
| --- | --- |
| bytes | 11038 |
| sha256 前 16 | `0221CBC3E3453171` |
| CR 字节数 | 0 |
| 非 ASCII 字节数 | 0 |
| 行数（按 `\n` 切） | 109 |
| `CASE_PASS` 行 | 106 |
| `CASE_FAIL` 行 | 0 |
| 末行 | `SUITE_END pass=106 fail=0 root=C:\Users\Duanyi\AppData\Local\Temp\relay-port-selftest\20261125-203153` |

判绿只数 `CASE_PASS` / `CASE_FAIL` 两种行；detail 里出现的 `line=FAIL ...`、`WARN` 是
**通过用例**的被测输出，不按 `FAIL` 子串统计（沿用上一批口径）。

## case 15（新增，6 条断言）逐条实测

| 断言 | raw detail | 判的是什么 |
| --- | --- | --- |
| `publish_probe_tokens_present` | `missing= wanted=9` | 剥注释后的代码里 9 个解析要素 token 齐备（函数名、`Get-PSDrive`、`skill_root_candidates`、`skill_root_ambiguous`、`RELAY_PORT_SKILL_ROOT`、`MAVIS_DATA_DIR`、`v2\sessions`、`.minimax\.minimax`、`skill_root_not_found`） |
| `publish_probe_has_no_hardcoded_drive` | `drive_literals_in_code=0` | 代码里零盘符字面量 ⇒ 探测不靠硬编码盘符/用户名 |
| `publish_skill_root_doc_describes_probe` | `missing=` | 头注释 `.PARAMETER SkillRoot` 确实写了逐盘扫描与歧义告警两件事 |
| `publish_skill_root_env_pin` | `code=2 pinned=%TEMP%\...\skill-root-env-pinned` | 环境变量被采纳（输出 `via=env`）且不是 `exit 3` |
| `publish_skill_root_parameter_wins` | `code=2 pinned=...\skill-root-arg-pinned env_was=...\skill-root-env-pinned` | 同轮 env 已设时 `-SkillRoot` 仍胜出（`via=parameter`）—— 优先级顺序被真跑锁住 |
| `publish_skill_root_probe_branch` | `line=[INFO] skill_root=E:\Users\Duanyi\.minimax\.minimax\skills\relay-port via=probe code=2 root_exists=True loud_fail=False` | 无 pin 时探测命中 E 盘 activeDataDir 下的真根（本机命中唯一候选） |

### `code=2` 的正确判读（别误读成回归）

三条真跑都返回 **2 = publish 自己的漂移判定**，因为跑套件时
`tool\references\portability-audit-2026-11-25.md` 已就地订正、尚未 publish 到全局 skill。
**不是** 3（`skill_root_not_found`）。断言只要求 `code ≠ 3` 且 `via=` 行正确 ⇒
判绿口径没有为 F4 放宽任何无关部分。收口时显式 publish 之后复验回到 `STATUS=OK / fail=0`。

## 已知限制 / 未验证（如实记）

- 套件**不调 `session_create`** ⇒ 「真实起链一跳」仍是人工步骤（日志自带
  `MANUAL_STEP real_session_activation`）。
- F4 的**多命中择一**分支（`via=probe-multi` + `WARN skill_root_ambiguous` + 按
  `<profile>\v2\sessions` mtime 择优）本机**没有第二个候选**可测：C 盘
  `C:\Users\Duanyi\.minimax\.minimax` 存在但未装 relay-port ⇒ 只走单命中。该分支目前靠代码走查。
- `profile_probe_disabled`（盘符枚举异常时的静默降级）同理未实测。
- CI（`.github\workflows\selftest.yml`，`windows-latest`）上没有已装 skill，case 15 的探测断言
  预期走 `loud_fail` 分支（`code=3` + `skill_root_not_found` + 走到 `every_drive`）；
  本批未推送，线上稳定性未验证。

## 时间线（本轮）

| 动作 | 证据 |
| --- | --- |
| 冒烟跑（先取真实断言数，再写文档） | `%TEMP%\relay-selftest-probe-F4.txt` 109 行 |
| 权威跑（同参数覆盖式写留证 `.txt`） | 本目录 `selftest-2026-11-25l.txt` |
| 三分支不带 `-SkillRoot` 的实跑 | 本文件「case 15」节 detail 字段 |

## 收尾顺序（家规固定）

selftest（本文件对应的这次）→ `scripts\publish-relay.ps1 -Direction publish`
→ `scripts\refresh-manifest.ps1`（清单必须最后，`MD_TXT_CR_TOTAL` 必须为 0）。
publish 现在**可以不带 `-SkillRoot`**（走 `via=probe`）；本轮仍显式传参以免歧义。
