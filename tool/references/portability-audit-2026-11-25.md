# 静态可移植性审计（B7 候选 #5）· 2026-11-25

对象：relay-port 交付件（kit）本体。目的：把「照搬到别的项目/别的机器需要改哪些地方」查清楚，
并把结论固化成 selftest 断言，防止以后回潮。

## 一、范围与判据

扫描集合 = 会被安装进目标项目的全部 `.ps1`，本轮实测 **7 件**：

| 目录 | 件数 | 文件 |
| --- | --- | --- |
| `tool\templates\` | 3 | `start-relay.ps1` `relay-lock.ps1` `relay-ledger.ps1`（真源） |
| `tool\scripts\` | 1 | `install-relay.ps1`（安装器） |
| `device\` | 3 | 上表 templates 的逐字镜像（家规 3） |

三类判据（对应 `scripts\selftest.ps1` 的 case 14）：

1. `kit_no_absolute_paths_in_code` —— 代码里不得出现 `[A-Za-z]:\` 形式的绝对盘符路径。
   **判据只看剥掉注释后的代码**：安装器帮助块里的用法示例
   `install-relay.ps1 -RepoRoot D:\work\myapp` 是文档示例、不是缺陷，按代码判会误红。
2. `kit_no_home_literals_in_code` —— 代码里不得出现 `USERPROFILE` / `$HOME` / `.minimax`。
   这三样会把「某台机器的安装位置」写死进交付件。
3. `kit_no_foreign_project_name` —— **全文（含头注释）**不得出现别的项目名 `PractiLog`。
   头注释是使用者第一眼读到的东西，写错项目名 = 交付件来源不干净，属于要判死的项。

配套：`kit_device_specific_ids_flagged` —— `tool\templates\RELAY-ADAPTATION.md` 里既保留了
`provider-*` 这类本机 id，就必须同时带 ASCII 哨兵串 `device-specific, refill`，
即「换机器时要重填」这句话不许丢。

## 二、结论（已盘上复核）

**干净的部分**：7 件 kit `.ps1` 的代码里 0 处绝对盘符、0 处 `$env:USERPROFILE` / `$HOME` / `.minimax`。
路径一律由 `-RepoRoot` / 参数 / `Join-Path` 推出，`$repoRoot` 在 selftest 里也是规范化得来。
⇒ kit 可以搬到任意盘符、任意用户名、任意项目。

### F1（已修）头注释自称别的项目名

`tool\templates\relay-lock.ps1:3` 原写：

```
  Relay chain cross-session mutex lock (PractiLog auto-advance kit).
```

改为 `(relay-port kit).` 并按家规 3 同步设备件：

```powershell
Copy-Item tool\templates\relay-lock.ps1 device\relay-lock.ps1 -Force
```

复核值：两件均 `len=6429 cr=0 bom=False sha16=23E51FB2619230DC`，`LOCK_MIRROR_SAME=True`。
这是整个 kit `.ps1` 里 `PractiLog` 的**唯一**命中处（`device\relay-lock.ps1:3` 是其镜像）。

### F2（有意保留值，只加说明 + 守卫）本机 provider 注册 id 写进便携模板

`tool\templates\start-relay.ps1:188-190` 的默认 `model_policy`：

```
preferred      = 'minimax/MiniMax-M3'
fallback_day   = 'custom_provider:provider-aa5659/auto'
fallback_night = 'custom_provider:provider-aa5659/deepseek-v4.1-flash-1017'
```

`provider-aa5659` 是**本机 BYOK provider 的注册 id**，换一台机器（或换一个账号）就不存在，
起链那一跳会直接失败。`device\start-relay.ps1:188-190` 逐字镜像同样三行。

裁决：**不改值**。理由——改这三个默认值会改变起链的默认行为，代价不可逆（用户在其他机器上
的 provider id 未知），且 `scripts\selftest.ps1` 对 `aa5659` / `MiniMax-M3` 零命中，说明它不是
测试耦合项，而是真·本机配置。改为：

- `tool\templates\RELAY-ADAPTATION.md` 的「首选 / 日间回退 / 夜间回退」三行下方加说明，
  显式标为 **`device-specific, refill`**（换机器/换账号必须重填，含本文件指针）；
- selftest case 14 用 `kit_device_specific_ids_flagged` 守住这句说明不丢。

⇒ 待办归属：目标项目装完后，这三行要在该项目自己的 `docs\relay\RELAY-ADAPTATION.md` 里重填，
安装器已具备「该文件已存在则 SKIP 保留项目改动」的行为（`install-relay.ps1:225-237`），
所以重填结果不会被下次安装覆盖。

### F3（判据设计取舍，非缺陷）安装器帮助里的示例盘符

`tool\scripts\install-relay.ps1:23` 与 `:26` 是 `.SYNOPSIS` 用法示例：
`-RepoRoot D:\work\myapp`、`-PlanDoc docs\plan-task12.md`。保留，判据按「代码 only」剥离注释。

### F4（已修，2026-11-25 用户裁决「改成读 activeDataDir」）`publish-relay.ps1` 的默认 skill root

原缺省值指向 `$env:USERPROFILE\.minimax\.minimax\skills\relay-port`，而本机
`$env:USERPROFILE = C:\Users\Duanyi`、真正的运行时数据目录（activeDataDir）在 **E 盘**
`E:\Users\Duanyi\.minimax\.minimax\skills\relay-port` ⇒ 不带 `-SkillRoot` 会
`skill_root_not_found` / `exit 3`，每次收尾都得手传绝对路径。

现在由 `scripts\publish-relay.ps1` 的 `Get-RelaySkillCandidate` 按这个顺序解析：

1. `-SkillRoot` —— 显式参数最优先，输出 `via=parameter`；
2. `$env:RELAY_PORT_SKILL_ROOT` —— 给 CI / 多 profile / 非默认目录留的手感，
   `Test-Path` 通过即采用，输出 `via=env`；
3. 自动探测（命中唯一 ⇒ `via=probe`；多命中 ⇒ `via=probe-multi`，打印
   `skill_root_candidates=` 清单并 `WARN skill_root_ambiguous`）：候选根包括
   `MAVIS_DATA_DIR` / `MINIMAX_DATA_DIR` 指向的 profile、`$HOME` 与 `$env:USERPROFILE` 下的
   `.minimax\.minimax` 与 `minimax\.minimax`，再逐盘（`Get-PSDrive` 的 `Fixed` 盘根）扫
   `<drive>:\<userleaf>\.minimax\.minimax` —— 即「读 activeDataDir」的做法，
   **零硬编码盘符与用户名**（盘符在 `Get-PSDrive` 之前不可知）；
4. 多命中时按 profile 活跃度择一：取 `<profile>\v2\sessions` 的 `LastWriteTime` 最新者
   （MCode 把会话落在 `<dataDir>\v2\sessions\<date>\`，活跃 profile 必然最近更新），
   该目录不存在才退回 skill 目录自身的 mtime；
5. 三者皆空才 `skill_root_not_found` / `exit 3`。

改后盘上回读值：`len=13344 cr=0 bom=False nonascii=0 sha16=D4ED0FBEACCD23FC PARSE_ERRORS=0`。

三分支实测（`-Direction verify`，前两条均**不带** `-SkillRoot`）：

```
[INFO] skill_root=E:\Users\Duanyi\.minimax\.minimax\skills\relay-port via=probe
[INFO] tracked_files=28
[RESULT] DIRECTION=verify STATUS=OK fail=0 warn=2      # EXIT=0，warn=2 是 examples 快照漂移
```

`RELAY_PORT_SKILL_ROOT=<临时空目录>` ⇒ `via=env`（`EXIT=2`，因该目录缺 `SKILL.md`
= 缺省值确实被采纳的证据）；显式 `-SkillRoot` ⇒ `via=parameter`。
⇒ 收尾三步不再需要手传路径；在 profile 有歧义的机器上仍建议显式传参。

守卫：selftest **case 15**（6 条断言）`publish_probe_tokens_present` /
`publish_probe_has_no_hardcoded_drive` / `publish_skill_root_doc_describes_probe` /
`publish_skill_root_env_pin` / `publish_skill_root_parameter_wins` /
`publish_skill_root_probe_branch`。最后一条**刻意不硬编码盘符**：本机命中真根走 `mode=found`，
没有已装 skill 的机器（如 CI）要求它**响亮失败**（`EXIT_CODE=3` + `skill_root_not_found`
+ 确实走到 `every_drive` 全盘分支），两种都判绿 —— 否则「探测静默命中错目录」与
「探测根本没跑」会被一并放过。复现：

```powershell
$ErrorActionPreference='Stop'; $r='F:\soft\00selfmade\agentask-relay'
& pwsh -NoProfile -File "$r\scripts\publish-relay.ps1" -Direction verify   # via=probe
$env:RELAY_PORT_SKILL_ROOT='<abs-path>'; & pwsh -NoProfile -File "$r\scripts\publish-relay.ps1" -Direction verify
$env:RELAY_PORT_SKILL_ROOT=''   # 清理：赋空值，不用 Remove-Item Env:（安全网关按删除拦截）
```

## 三、复现配方

一条命令即可复跑这三类判据（纯 ASCII、绝对路径、不 `cd`）：

```powershell
$ErrorActionPreference='Stop'; $r='F:\soft\00selfmade\agentask-relay'
$fs=@(); $fs+=@(Get-ChildItem -LiteralPath "$r\tool\templates" -File -Filter '*.ps1')
$fs+=@(Get-ChildItem -LiteralPath "$r\tool\scripts" -File -Filter '*.ps1')
$fs+=@(Get-ChildItem -LiteralPath "$r\device" -File -Filter '*.ps1')
'FILES='+$fs.Count
foreach ($f in $fs) { $t=[IO.File]::ReadAllText($f.FullName)
  '{0} abs={1} home={2} proj={3}' -f $f.Name,
  ([regex]::Matches($t,'[A-Za-z]:\\')).Count,
  ([regex]::Matches($t,'USERPROFILE|\$HOME|\.minimax')).Count,
  ([regex]::Matches($t,'PractiLog')).Count }
```

正式判据以 selftest case 14（交付 kit 的 `.ps1` 扫描）与 case 15（仓库侧门禁 `publish-relay.ps1`
的 skill root 解析）为准，两者都剥离注释后再判；全套跑法见
`F:\soft\00selfmade\agentask-relay\tool\references\selftest-2026-11-25l.md`。

## 四、已验证 / 推断 / 未验证

- **已验证**：F1 修复值与镜像一致性（盘上 sha 回读）；7 件扫描集合的三类命中计数；
  `install-relay.ps1` 两处示例盘符的行号；F2 的 `start-relay.ps1:188-190` 三行原文；
  selftest `scripts\selftest.ps1` 改后 `cr=0 bom=False PARSE_ERRORS=0`；
  F4 修复后的三分支实跑（`via=probe` / `via=env` / `via=parameter`），以及
  selftest **106 条 / 0 失败 / `EXIT=0`**（raw log
  `F:\soft\00selfmade\agentask-relay\tool\references\selftest-2026-11-25l.txt`）。
- **推断**（未实测）：case 14 在真实起链场景下的价值 —— 套件本身不调 `session_create`，
  「换机器 provider id 失效」这一跳仍属人工步骤（见留证里的 `MANUAL_STEP real_session_activation`）。
- **未验证**：F4 择一启发式在本机走的是**单命中**分支（`via=probe`），`probe-multi` +
  `skill_root_ambiguous` + `<profile>\v2\sessions` 活跃度择优**本机没有多候选可测**，
  只由代码走查与 case 15 的参数/env 分支间接覆盖；`profile_probe_disabled`（盘符枚举异常时
  静默降级）同理。CI（`windows-latest`，无已装 skill）上 case 15 依赖 `loud_fail` 分支，
  待一次线上运行确认；本批未 push。
  `RELAY-ADAPTATION.md` 的重填流程在真实目标项目里是否顺畅（B 批 dogfood 只装不起链）。
