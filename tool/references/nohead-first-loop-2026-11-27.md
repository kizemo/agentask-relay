# 零提交仓库（无 HEAD）跑到第一环之后：台账实测（2026-11-27）

补 `HANDOFF.md` B26 节登记的未验证项：「零提交仓库里跑到第一环之后的行为（台账写、写集指纹取 HEAD）未单独实测」。

两个夹具都是系统临时目录里**只 `git init`、零 commit** 的仓库，装置都用 `tool\scripts\install-relay.ps1` 现装。
差别只有一处：夹具 A 装的是**修复前**的模板（B26），夹具 B 装的是**修复后**的模板（B27）。

## 夹具 A：修复前（复现 R1 / R1b）

- 路径 `C:\Users\Duanyi\AppData\Local\Temp\relay-nohead-probe-20261127-195546`，安装时间 19:55
- 装完直接 `start-relay.ps1 -Target 'zero batch'`（非干跑，`REALRUN_EXIT=0`），台账由启动器自举：
  `LEDGER_STATE ... status=running current_stage=1 max_stages=6 stages=0 sessions=0 notes=0`
- 补丁序列（每步 `-Action commit -ExpectSha256 <status 里的 sha>`）：

| 补丁 | 补丁文本 | 退出码 | 关键输出 |
|---|---|---|---|
| p1 | `{"append_stage":{"id":1,"title":"zero-commit probe stage one"}}` | 0 | `LEDGER_RULES_OK stages=0->1` |
| p2 | `{"stage_done":1,"stage_fields":{"session_id":"mvs_zeroheadprobe1"}}` | 0 | `LEDGER_SESSION_REGISTERED session=mvs_zeroheadprobe1 stage=1 source=stage_field` |
| p3 | `{"next_session_id":"mvs_zeroheadprobe2","append_stage":{"id":2,"title":"..."}}` | 0 | `LEDGER_RULES_OK stages=1->2` |
| p4 | `{"stage_done":2}` | 0 | `LEDGER_SESSION_REGISTERED session=mvs_zeroheadprobe2 stage=2 source=ledger_next_session_id` |
| p5 | `{"blocked_on_append":["probe: stop test"],"set_status":"blocked","next_session_id":"","append_stage":{"id":3,"title":"..."}}` | 0 | **无清空提示**；盘上 `next_session_id` 仍是 `mvs_zeroheadprobe2` |
| p6 | `{"stage_done":3}` | 0 | **`LEDGER_SESSION_ALREADY_REGISTERED session=mvs_zeroheadprobe2`** |

两条缺陷在真实场景里都成立：

1. **R1b（清空语义）**：停链配方要求「`set_status=blocked` 且 `next_session_id` 为空」，但空值被**静默丢弃**，
   `next_session_id` 键原样保留旧值，退出码还是 0 —— 调用方以为已经放弃下一环。
2. **R1（F6 回落保护）**：链条已经 `status=blocked`（p5），p6 完成第 3 环时仍把**上一环写下的陈旧 id**
   当成「跑这一环的会话」登记进 `sessions[]`，于是停掉的链条在台账里继续留痕、看起来还活着。

盘上终态（夹具 A）：`status=blocked`、`next_session_id="mvs_zeroheadprobe2"`、`sessions=[mvs_zeroheadprobe1,mvs_zeroheadprobe2]`、
`stages=3`（第 2、3 环 `session_id` 均缺省）。

## 夹具 B：修复后（同一序列全绿）

- 路径 `C:\Users\Duanyi\AppData\Local\Temp\relay-nohead-b27-20261127-200521`，安装时间 20:05
- 装完的 `docs\relay\relay-ledger.ps1` SHA256 前缀 `8B44167DD7D8`，与 `device\relay-ledger.ps1` **逐字相同**
- `start-relay.ps1` 非干跑 → `LEDGER_BOOTSTRAP`（`bytes=2200`）、`REALRUN_EXIT=0`
- 同一序列，另加两条状态机拒绝用例：

| 补丁 | 补丁文本 | 退出码 | 关键输出 |
|---|---|---|---|
| p1 | `{"append_stage":{"id":1,"title":"zero commit b27 stage one"}}` | 0 | `LEDGER_RULES_OK stages=0->1` |
| p2 | `{"stage_done":1,"stage_fields":{"session_id":"mvs_zb27s1"}}` | 0 | `LEDGER_SESSION_REGISTERED session=mvs_zb27s1 stage=1 source=stage_field` |
| p3 | `{"next_session_id":"mvs_zb27s2","append_stage":{"id":2,"title":"..."}}` | 0 | `LEDGER_NEXT_SESSION_SET after=mvs_zb27s2`、`stages=1->2` |
| p4 | `{"stage_done":2}` | 0 | `LEDGER_SESSION_REGISTERED session=mvs_zb27s2 stage=2 source=ledger_next_session_id` |
| p5 | `{"set_status":"blocked"}` | **3** | `LEDGER_FAIL reason=status_blocked_without_blocked_on` |
| p6 | `{"blocked_on_append":["probe: stop test b27"],"set_status":"blocked","next_session_id":"","append_stage":{"id":3,"title":"..."}}` | 0 | `LEDGER_NEXT_SESSION_CLEARED before=mvs_zb27s2 after=(empty)`、`stages=2->3` |
| p7 | `{"stage_done":3}` | 0 | `LEDGER_SESSION_SKIPPED stage=3 reason=chain_not_running status=blocked`、`sessions=2->2` |
| p8 | `{"set_status":"bogus"}` | **2** | `LEDGER_FAIL reason=status_not_allowed value=bogus allowed=pending,done,blocked` |

盘上终态（夹具 B，回读 `docs\relay.json`）：

- `next_session_id` 长度 **0**（真正的空串，不是残留旧值）
- `status=blocked`、`sessions=[mvs_zb27s1,mvs_zb27s2]`、第 2、3 环 `session_id` 缺省（合乎预期）
- `LEDGER_STATE ... sha256=470AD2C6FEC3124180D9F31EC75173E9A4FA3BE18067FE4FDDEDAA6517E4EA83 stages=3 sessions=2`
- `LEDGER_CHAIN ... stages=1:done,2:done,3:done all_done=true open_stages=0`

## 复现命令

```powershell
$root = Join-Path $env:TEMP ("relay-nohead-b27-" + (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Path $root -Force | Out-Null
git -C $root init --quiet
pwsh -NoProfile -ExecutionPolicy Bypass -File 'F:\soft\00selfmade\agentask-relay\tool\scripts\install-relay.ps1' -RepoRoot $root -Target 'zero commit b27'
pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'docs\relay\start-relay.ps1') -Target 'zero commit b27'
# 之后按上表逐条 commit：
pwsh -NoProfile -File (Join-Path $root 'docs\relay\relay-ledger.ps1') -Action status
pwsh -NoProfile -File (Join-Path $root 'docs\relay\relay-ledger.ps1') -Action commit -ExpectSha256 <sha> -Patch <patch.json>
```

## 结论

- 零提交仓库（无 HEAD）在**第一环之后**的台账路径本身没有问题：自举、CAS、追加不变式、写后回读都正常，
  `git rev-parse HEAD` 为空只影响写集指纹与干跑显示，不阻断台账。
- 夹具 A 里看到的两个异常**不是零提交场景特有的**，而是 B27 修掉的 R1 / R1b 缺陷；在夹具 B（同为零提交）
  上它们不再复现。判别性来自「同序列、同场景、只差装置版本」。
- 夹具 A/B 均为一次性临时目录，未写入本仓库；本文件是它们的留证。