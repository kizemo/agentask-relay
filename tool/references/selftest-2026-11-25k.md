# selftest 留证 2026-11-25 k（B7 收口跑）

raw 日志：`F:\soft\00selfmade\agentask-relay\tool\references\selftest-2026-11-25k.txt`
（本文件与 raw 日志同批收口，LF / `cr=0`）

## 结论

`EXIT=0`、**`pass=100 fail=0`**（`SUITE_END pass=100 fail=0`）。
本批套件从 95 断言增至 100 断言（+5，全部来自新 case 14），新增项**首跑即绿**。

## 跑法（本轮实测可用）

```powershell
$ErrorActionPreference='Stop'; $r='F:\soft\00selfmade\agentask-relay'
& pwsh -NoProfile -ExecutionPolicy Bypass -File "$r\scripts\selftest.ps1" `
  -EvidencePath "$r\tool\references\selftest-2026-11-25k.txt" *>&1 |
  Out-File -FilePath "$r\reports\selftest-2026-11-25k-console.txt" -Encoding utf8
'REAL_EXIT=' + $LASTEXITCODE
```

`-EvidencePath` **必须给绝对路径**，否则套件打 `WARN evidence_path_not_absolute_ignored` 且不落盘。
全量耗时约 65-75 s（本轮 `20:10:45` 建根 → `20:11:48` 写证据），建议在后台跑。
套件在 `%TEMP%\relay-port-selftest\<时间戳>` 建一次性 git 仓库，默认**不清理**（保留以便复验），
要清理加 `-Cleanup`。

## 证据文件回读值（当场复核，非抄摘要）

| 项 | 值 |
| --- | --- |
| bytes | 10234 |
| sha256 前 16 | `BB5ADE29E1AF316C` |
| CR 字节数 | 0 |
| 行数（按 `\n` 切） | 104 |
| `CASE_PASS` 行 | 100 |
| `CASE_FAIL` 行 | 0 |
| 末行 | `SUITE_END pass=100 fail=0 root=C:\Users\Duanyi\AppData\Local\Temp\relay-port-selftest\20261125-201045` |

判绿只数 `CASE_PASS` / `CASE_FAIL` 两种行：日志里 `line=FAIL reason=...`、`WARN` 是**通过用例的
detail**（断言的就是失败字面量本身，例如 `plan_arg_missing_reason line=FAIL reason=plan_doc_not_found`），
不要按 `FAIL` 子串统计。

## 为什么覆盖重写同一个证据文件

本轮 95 断言那一次（bytes=9893 / sha16 `3102DF2C09F154E4`）跑完之后，**又改了工具本体**：
`tool\templates\relay-lock.ps1` 头注释（连带 `device\relay-lock.ps1` 镜像）、
`tool\templates\RELAY-ADAPTATION.md` 的 `device-specific, refill` 说明、
`scripts\selftest.ps1` 新增 case 14。按家规 1「改工具本体必须重跑且要求 EXIT=0 / fail=0」，
重跑必须与**最终代码**一致 ⇒ 覆盖 `-2026-11-25k.txt` 而不是再开一个后缀，
避免留证与被留证的代码错位。被覆盖的那次结果（95/0）本身也是绿的，无信息损失。

## 新 case 14：静态可移植性守卫（候选 #5）

5 条断言，扫 `tool\templates\`（3 件）+ `tool\scripts\`（1 件）+ `device\`（3 件）= `scanned=7`：

| 断言 | 判据 | 本轮 detail |
| --- | --- | --- |
| `kit_scanned_file_count` | 集合非空（`>= 7`），防「扫了个空」自证 | `scanned=7` |
| `kit_no_absolute_paths_in_code` | **剥注释后**代码里 0 处 `[A-Za-z]:\` | `files= scanned=7` |
| `kit_no_home_literals_in_code` | 剥注释后 0 处 `USERPROFILE` / `$HOME` / `.minimax` | `files= scanned=7` |
| `kit_no_foreign_project_name` | **全文（含头注释）** 0 处 `PractiLog` | `files= scanned=7` |
| `kit_device_specific_ids_flagged` | `RELAY-ADAPTATION.md` 保留 `provider-` 时必带哨兵串 `device-specific, refill` | `has_provider_id=True has_refill_note=True` |

绝对路径与家目录两类**只看代码**：安装器帮助里的示例 `-RepoRoot D:\work\myapp`
（`tool\scripts\install-relay.ps1:23` 与 `:26`）不是缺陷，按全文判会误红；
项目名一类**看全文**：头注释写错项目名同样是要判死的来源不干净。
细节与裁决记录在 `F:\soft\00selfmade\agentask-relay\tool\references\portability-audit-2026-11-25.md`。

## 本批其它同轮变更（都被这 100 条覆盖）

- `tool\templates\AGENT-RELAY.md` 新增 §8（计划文档解析链）+ §9（收编 `AGENTS.md` 双判据），
  协议现 9 个编号节；`protocol\AGENT-RELAY.md` 重拷为逐字镜像（17917 B / `59A2BE933174F63C` / cr=0）。
- `scripts\publish-relay.ps1` 硬不变式改表驱动 `$copyPairs`（3 件 device `.ps1` + protocol 镜像），
  落地 B3 遗留；protocol 定位是 **templates 的托管镜像**，不是第二真源。
- `scripts\selftest.ps1` 新增 case 12（启动器计划解析 / blocked / 垃圾台账 / 锁大小写）与
  case 13（安装器收编双判据 + protocol 镜像 + 文档-代码 token 双向交叉核对），
  并修掉撞号注释（`case 9: ledger write gate` → `case 9b`，真 case 9 是 L221 的锁互斥）。
  改后自检：`len=42077 cr=0 bom=False sha16=878CBB357CDD539D`，`PARSE_ERRORS=0`。

## 未验证 / 人工步骤

- **真实起链一跳不在套件内**：日志自带
  `MANUAL_STEP real_session_activation: this suite never calls session_create.`
  ⇒ 本留证**不证明**真实链能起环；换机器后 `custom_provider:provider-aa5659/*` 失效这一跳
  仍属人工验收（见上文审计 §四）。
- 全局 skill 同步（`publish-relay.ps1 -Direction publish -SkillRoot <绝对路径>`）与
  `MANIFEST.txt` 刷新**不属套件断言范围**，是套件之后的独立闸门，见本仓库 `tool\SKILL.md`
  的收尾顺序 selftest → publish → refresh-manifest。
- B7 只做了静态审计，未在别的机器/别的账号上实测重填 `RELAY-ADAPTATION.md` 的流程。
