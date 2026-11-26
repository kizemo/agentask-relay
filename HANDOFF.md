# HANDOFF —— relay-port 工具（2026-11-25 建目录时的状态）

## 背景

PractiLog 项目跑完一条 6 环无人值守接力链后，沉淀出一套「装置」：

- `docs\relay\start-relay.ps1`：启动器（工作区校验 → 并发闸门 → 取锁 → 台账初始化 → 生成接力 prompt）
- `docs\relay\relay-lock.ps1`：跨会话互斥锁（`FileMode.CreateNew` 原子创建）
- `docs\relay.json`：状态机台账
- `AGENTS.md` §A/§B：家规

问题：这套东西要装进**别的项目**，原来得手工抄 5～8 个文件、手改家规、手写台账骨架 —— 易漏、不可重复执行、跨项目一改就走样。

## 目标（已达成）

把「照搬到别的项目需要做的事」做成**一个任何会话调用一次即装完**的工具：装置、锁、台账骨架、家规、协议、激活 Prompt 全部就位；之后目标项目内只需一句 Prompt 起链。

## 进度

- ✅ 工具实现：`tool\scripts\install-relay.ps1`（17,262 B，纯 ASCII、无 BOM，sha16 `8134C322B0AA0394`）
- ✅ 模板 6 件 + 说明书 1 件 + 自测证据 4 件
- ✅ 端到端实测 14 项全 PASS（T1–T14：安装 / 幂等 / 收编 / 干跑 / 真起链 / 二次起链被拒 / 锁互斥 / 台账不被安装器写 / ASCII 与 BOM 全库扫 …）
- ✅ 抓出并修掉三个缺陷：D1 幂等分支输出变量未初始化 ⇒ 目标 `AGENTS.md` 被截断成 0 字节；D2 `Write-Host` 证据需 `*>&1` 才捕得到；D3 安装器自身含中文字面量 ⇒ PS 5.1 按 ANSI 解码必乱码
- ✅ 全局发布：`%USERPROFILE%\.minimax\.minimax\skills\relay-port\`（新会话的技能目录快照里可见）
- ✅ 资产归拢到本目录（`MANIFEST.txt` 留证）
- ✅ **批次 B2（同日 14:0x）**：完成后续候选 #7 发布一键化 / #2 装置版本化一致性 / #3 `-PlanDoc` 加固 / #4 收编判据加固，并把家规 1 的强制自测固化成 `scripts\selftest.ps1`
- 安装器 `tool\scripts\install-relay.ps1` 17,262 B `8134C322B0AA0394` → **19,756 B `A7EF9E3CA5A4BEE8`**（收编双判据；mtime 13:55:22，run2/run3 自测与发布均按此件跑绿）
  - 启动器 `tool\templates\start-relay.ps1` 9,352 B `29158782C8843588` → **12,026 B `5B3012510BB70688`**（`-PlanDoc` 解析链 + 台账记解析结果），`device\` 已同步覆盖
  - 新增 `scripts\publish-relay.ps1`（8,556 B）与 `scripts\selftest.ps1`（≈17 KB），两者纯 ASCII 无 BOM 语法零错
- 一键自测 **终态 40 条断言全绿（fail=0 / EXIT=0）**：run1 32/5（抓到 D1 假绿）→ run2 39/0 → run3 40/0（D4 扫描范围收敛 + 加正控）；证据 `tool\references\selftest-2026-11-25-b2.md` + `.txt`（run3 raw）+ `-run1.txt` + `-run2.txt` + `-next-prompt.txt`
  - `relay-lock.ps1` **未改**（`227FA4696C69AADE`），`examples\practilog\docs\relay\` 按家规 8 保留为历史快照
- ✅ **批次 B3（同日 15:5x）**：后续候选 #8「台账写保护」落地为写闸门 `docs\relay\relay-ledger.ps1`（散文纪律 ⇒ 机制闸门）
  - 新增 `tool\templates\relay-ledger.ps1` = `device\relay-ledger.ps1` **15,672 B `6068012759F0D0A6`**（纯 ASCII / 无 BOM / LF）：
    独占写锁（`FileMode.CreateNew` + 陈旧接管）+ CAS `-ExpectSha256`（锁外与锁内 `stage=under_lock` 双比）+
    只追加不变式 + 同卷 tmp 原子替换与写后逐字回读（成功打印 `LEDGER_COMMITED before= after=`）
  - 安装器 19,756 B `A7EF9E3CA5A4BEE8` → **20,011 B `793B530773F3CE6D`**（装置清单计入闸门）；
    启动器 12,026 B `5B3012510BB70688` → **13,633 B `4A65572783501F9E`**（预检 `ledger_gate_missing` **必须排在计划解析之后** +
    生成的 prompt 内嵌四步配方 + blocked/完成分支走闸门 + bootstrap 台账补 `notes=@()` / `blocked_on=@()`），`device\` 已同步覆盖
  - `scripts\selftest.ps1` ≈17 KB → **23,612 B `4375CB370B32C657`**（新增 6 条闸门断言）；
    `scripts\publish-relay.ps1` 8,556 → **8,596 B `348BEB5BD733078E`**（硬不变式与逐件清单计入 `relay-ledger.ps1`）
  - 文档同步 5 件：`tool\SKILL.md` **12,456 B `2869DBCFEFFD8320`**（新增「台账写闸门」整节；第 4 道闸门由散文改为机制）、
    `protocol\AGENT-RELAY.md` **10,715 B `EA9A9C3ED74466CB`**、`tool\templates\AGENT-RELAY.md` **10,768 B `FEE1F7ED81F85388`**、
    `AGENTS.md` **3,667 B `82AD88107DEC7B64`**、`README.md` **6,172 B `89A5FB7B0E519D3E`**
  - 一键自测 **终态 `pass=55 fail=0 EXIT=0`**（run dir `20261125-155000`）：CAS 冲突 `exit=3`、未知 patch 键 `exit=2`、
    `set_status:"running"` 会话身份被拒 `exit=3`、`-DryRun` 非破坏、并发单写者 `wins=1 refused=1`、竞态后 `locks=0` 全实测；
    证据 `tool\references\selftest-2026-11-25-b3.md` + raw `.txt`（`EA1F0A67E968C24E`）
  - 家规 1 字面项**已闭合**（订正）：改完文档后合规复跑 run `20261125-155836`（15:58:36→15:59:13），同样 `pass=55 fail=0 EXIT=0`，
    raw 收进 `tool\references\selftest-2026-11-25-b3h.txt`（6,001 B / `AE4D9CC84548BC6D`）；`next-prompt.md` **确实存在**，
    它是启动器写到**被安装目标仓库**的产物（实测 `<run>\repo-planprobe\docs\relay\next-prompt.md`），不在 run dir 根 ——
    按根目录找必然 `Copy-Item` 报 path not found，要找它得 `Get-ChildItem <run> -Recurse -Filter 'next-prompt*'`。
    留证 `tool\references\selftest-2026-11-25-b3-next-prompt.txt`（4,077 B / `89ADFFE3038C5CD0`）；
  - **发布与清单（固定顺序）**：`publish-relay.ps1 -Direction publish` → `STATUS=OK fail=0 warn=1`，
    硬不变式 `device_matches_template` 三件全 OK（含新闸门），`tracked_files` 21→23；唯一 WARN 是 `examples\practilog`
    历史快照漂移（家规 8 有意不为此同步）。最后 `refresh-manifest.ps1` → `verdict=PASS`，
    `NEW_ENTRY tool\templates\relay-ledger.ps1` + 4 件 `CHANGED`（`install-relay.ps1` / `SKILL.md` / 两份 `AGENT-RELAY.md` / `start-relay.ps1`）。
    全局 skill 已回读确认：`templates\relay-ledger.ps1` `6068012759F0D0A6`、`SKILL.md` `2869DBCFEFFD8320`、三份 b3 证据件全部就位。
- 🔧 **门禁 `MD_TXT_CR_TOTAL=41` 已查清并归零**（B4 轮，2026-11-25）：41 个 CR **全部来自单个留证件**
  `tool\references\selftest-2026-11-25-b2-run1.txt`（整文件 CRLF）—— 全库其余 `.md` / `.txt` 均 CR=0，同批兄弟件
  （`-b2.txt` / `-b2-run2.txt` / `-b2-next-prompt.txt`）也全是 LF ⇒ 判定为**离群缺陷，不是设计**。
  核查确认：只有 `MANIFEST.txt` 钉了它的 sha，`HANDOFF.md` 与 `selftest-2026-11-25-b2.md` 仅按路径引用，
  **没有任何文档承诺逐字节保留其 CRLF** ⇒ 做**无损归一**（只删 41 个行尾 CR 字节）：
  `BECCFB77170D7FEF / 3986 B` → `63696A8EFF2975BF / 3945 B`，行数仍 41，
  哨兵行 `SUITE_START` / `CASE_FAIL install_verdict_ok` / `SUITE_END pass=32 fail=5` 原位可查。
  留痕见 `tool\references\selftest-2026-11-25-b2.md`「行尾归一留痕」条。
- **根因 = 家规口径缺口**（已补）：家规 4 原文只约束「仓库 Markdown 一律 LF」，而门禁
  `scripts\refresh-manifest.ps1:64` 统计的是 `.md` **加** `.txt` ⇒ 留证 `.txt` 落在无人认领的地带。
  现把家规 4 文字补齐：`.ps1` 纯 ASCII 无 BOM；仓库 Markdown 与 `tool\references\` 留证 `.txt` 一律 LF，
  `MD_TXT_CR_TOTAL` **必须为 0**。这是**文字对齐机制**（门禁代码与阈值/白名单一字未动），不触家规 7。
- ✅ 本目录已 `git init` 并推到 https://github.com/kizemo/agentask-relay （B5，16:38 用户指令；原「留给用户做」由该指令取代）
- ⬜ 本目录尚未安装 relay kit 自身（dogfood 候选：`install-relay.ps1:118-122` 要求目标必须是 git 仓库 ⇒ 这条与上一条绑在一起做）

## 已验证 / 推断 / 未验证

### 已验证（实测，有证据）

- 安装器幂等：第二次执行后 `AGENTS.md` sha16 前后相同（`F482063537A97B5B`），标记块 `begin=1 end=1`。
- 已有接力家规被**收编**而非重复追加；项目自己写的规则与其它 `##` 章节原样保留。
- 对真 PractiLog `AGENTS.md`（sha16 `BB1B6D28F7D684EF`）的**副本**安装后，真仓库该文件**未被改动**。
- 真起链：exit 0、锁 `LOCK_ACQUIRED`、台账 1,749 B（`running` / `current_stage=1` / `max_stages=4`）、接力 prompt 2,334 B。
- 二次起链被拒（`LOCK_HELD` → exit 4）；跨会话锁互斥（exit 2）。
- `.ps1` 纯 ASCII 无 BOM；`docs\relay.json` 安装器绝不写（由启动器创建）。
- **B2 新增**：启动器 `-PlanDoc` 三种解析来源（`source=argument|ledger|probe`）与零命中 `exit 2` 均实测，零命中时**不留锁、不写台账**（`tool\references\selftest-2026-11-25-b2.txt` 用例 5-8）。
- **B2 新增**：收编内容指纹判据实测 —— 标题不含「接力/relay」的等价段落被 `reason=content_signature` 抓住并包裹（`count=8 signals=relay.json+relay-lock+start-relay+session_create+in_progress+max_stages+next_session+awaiting_user`）；两节都合格时**不猜**，`WARN agents_relay_section_ambiguous matches=2` + 追加托管块。
- **B2 新增**：`device\` ↔ `tool\templates\` 硬不变式由 `publish-relay.ps1 -Direction verify` 判绿；`tool\` ↔ 全局 skill 逐件 sha16 同步 + 复核一次命令完成（`SYNC|DRIFT|PUBLISH|PULL|FIX`）。
- **B2 新增**：真启动器激活后 `docs\relay\next-prompt.md` 内 Read 行是**绝对路径**、台账 `plan_doc` 是**仓库相对路径**（留证 `selftest-2026-11-25-b2-next-prompt.txt`）。

### 推断（合理，但本目录未复测）

- 装到任意第三方项目都能一次成功 —— 只在 3 个临时仓库（空仓库 / 带家规仓库 / 真 PractiLog 家规副本）上验过，**未在真实第三方项目上跑完整链**。
- `RELAY-ADAPTATION.md` 的 TODO（写集 / 门禁 / 模型策略）若不补，第一环会因「写集不明」停链 —— 这是设计推理，**未实测**（本次自测链路没有真实写集）。
- ~~收编判据只认标题~~ → **B2 已修并实测**（双判据：标记块 > 标题 > 内容指纹打分 ≥4 信号；歧义不猜）。剩余推断：内容指纹阈值 `4/10` 是启发式，真实第三方项目的段落若恰好命中 4 条信号但并非接力家规，会被误包裹 —— 概率低（信号词高度专名化），且包裹只加 marker 不删原文，人工可 `review`；未做大规模误判率测量。

### 未验证

- ~~手敲 `start-relay.ps1` 不传 `-PlanDoc`~~ → **B2 已修**（解析链 + 零命中 `exit 2`，默认值不再指向 PractiLog 专用路径；实测见上）。
- **B2 未实测**：`plan_doc_ambiguous`（多计划文件）在启动器路径下按 mtime 取最新这条分支未被用例覆盖（安装器侧同类歧义 WARN 已实测）；判据代码与安装器共用同一份清单，属推断可用。
- 非 Windows 平台（脚本用了 `FileMode.CreateNew` + `Move-Item`；全链路只在 Windows / pwsh 7 上跑过）。
- 长链（>6 环）的自动转交：PractiLog 侧实测过 6 环，本工具产物本身只跑到第 1 环。

## 证据路径

- 自测报告：`tool\references\selftest-2026-11-25.md`
- **B2 自测报告**：`tool\references\selftest-2026-11-25-b2.md`（用例↔判据↔实测行）
- **B2 raw 证据**：`tool\references\selftest-2026-11-25-b2.txt`（终态 40 条全绿的机器日志）、`tool\references\selftest-2026-11-25-b2-run1.txt`（32/5，D1 现场）、`tool\references\selftest-2026-11-25-b2-run2.txt`（39/0）、`tool\references\selftest-2026-11-25-b2-next-prompt.txt`（真启动器产出的下一环 prompt）
- **B2 新脚本**：`scripts\selftest.ps1`（家规 1 的一键自测）、`scripts\publish-relay.ps1`（家规 2/3 的一键发布与一致性判定）
- 自测工作区（临时，会被系统清理）：`%TEMP%\relay-port-selftest\<stamp>\repo-*`
- 安装报告样张：`tool\references\selftest-install-report.md`
- 干跑证据：`tool\references\selftest-install-dryrun.txt`
- 激活包样张：`tool\references\selftest-activation-prompt.txt`
- 通用仓库真实链路：`examples\probe-ws\docs\{relay.json, stage-1.md, stage-2.md, stage-3.md}`
- 生产级台账样例：`examples\practilog\docs\relay.json`（22 顶层 key / 6 环全 done）
- 项目裁决实例：`examples\practilog\docs\RELAY-ADAPTATION.md`
- 装置设计说明（四道闸门 / 复制五步 / 人工边界）：`device\auto-advance-design.md`
- 通用协议：`protocol\AGENT-RELAY.md`；规程：`protocol\RELAY-SOP.md`

## 拷贝轮实录（2026-11-25 12:12 → 12:45）

用户指令：「把所有和 relay 相关的文件拷贝到本目录，我将以这个目录新建项目，接力执行后续这个工具的完善和优化」。

1. **盘点**：relay 相关散在 4 处——全局 skill（13 件）、用户级共享装置/协议（11 件 + `probe-ws` 5 件探针工程）、PractiLog 项目（`docs\relay\` 12 件 + `docs\` 顶层 4 件）。**本目录当时已有 4 份文档**。
2. **逐件拷贝 + 逐件 sha16 对账**：42 件全部一致（`SHA_MATCH=42 SHA_MISMATCH=0`），未覆盖本目录 4 份文档。布局：`tool\`（工具本体）/ `protocol\`（通用协议 + `protocol\probe-ws\` 探针工程）/ `device\`（装置）/ `examples\practilog\`（首个吃螃蟹项目的完整台账与证据）。
3. **抽取 PractiLog 接力家规**：`AGENTS.md` 第 **491–511** 行整段 → `examples\practilog\AGENTS-relay-section-extract.md`。它是「标题式收编」形态（无 `BEGIN RELAY-PORT` 标记），正是候选第 4 条的实证样本。
4. **生成 `MANIFEST.txt`**（`sha16 | bytes | relpath`，LF，不含自身）；全库字节级自检 = `BOM=0 / .ps1 非 ASCII=0`。收口时（12:5x）重刷一次，变化 4 条＝`tool\scripts\install-relay.ps1`、`tool\references\selftest-2026-11-25.md`、`README.md`、`HANDOFF.md`；目录实有 **47 件**（MANIFEST 46 条 + 自身）。
5. **装置三处一致性已当场核过**（后续候选第 2 条的当前状态）：`device\` / `tool\templates\` / `examples\practilog\docs\relay\` 三处的 `start-relay.ps1` 同为 sha16 `29158782C8843588`，`relay-lock.ps1` 同为 `227FA4696C69AADE`，`DISTINCT_SHA16=1`。改任一处必须同步另外两处，并用 MANIFEST 逐条比 hash 作为 CI 式自检。
6. **新增 `scripts\refresh-manifest.ps1`**（4,598 B，纯 ASCII、无 BOM）：一条命令重生成 `MANIFEST.txt` 并顺带做全库 BOM / `.ps1` 非 ASCII / md+txt CR 自检，输出 `FILE_COUNT / ENTRY_COUNT / INVARIANT_OK / CHANGE_COUNT` 与逐条 `CHANGED|NEW_ENTRY|REMOVED|PS1_NON_ASCII`。**踩过的坑：文档每改一次，MANIFEST 就过期一次（自指抖动）** ⇒ 规矩定为「本轮最后一步跑它」，且文档里不再写死件数，只写不变式 `条目数 = 文件数 − 1`。
5. **拷贝自查抓出并修掉缺陷 D3**：`install-relay.ps1:399` 把中文激活口令写成字面量塞进生成的 `ACTIVATION-PROMPT.md` ⇒ 脚本含 18 个非 ASCII 字节且无 BOM。**Windows PowerShell 5.1 按 ANSI 解码 ⇒ 该行必乱码**，还违反「产物 .ps1 必须纯 ASCII」自家纪律（此前 12 项自测没覆盖到）。改为 `[char[]](0x6309...)` 码点构造；复测（本轮 12:5x 重跑）安装产物 `docs\relay\install-report.md` 该行非 ASCII 字符恰为 `U+6309 U+542F U+52A8 U+63A5 U+529B U+94FE`＝`按启动接力链`（`MATCH_EXPECT=True`），安装器本体 `SRC_BYTES=17262 SRC_NON_ASCII=0`、`INSTALL_VERDICT=PASS`、干跑 `exit=0`。修复版已同步回全局 skill（sha16 `8134C322B0AA0394`）。
6. **证据**：`tool\references\selftest-2026-11-25.md`（T1–T14 + D1/D2/D3 + 8 条可复用结论）、`examples\practilog\docs\relay\proof\2026-11-25\*.txt`。

## 后续候选（未排期）

1. **安装完自动填 `RELAY-ADAPTATION.md` 的 TODO**（写集 / 门禁命令 / 模型策略）：现在是骨架 + TODO，需人补；可让调用会话探测后填。**B2 有意不做** —— 门禁阈值与白名单是家规 7 的人工验收点，自动填会把人工闸门变成假闸门。若要动，先改家规 7。
2. ✅ **装置版本化 / 一致性**（B2 完成）：`publish-relay.ps1` 把 `device\` ↔ `tool\templates\` 定为**硬不变式**（漂移 exit 2），`tool\` ↔ 全局 skill 逐件 sha16 对账 + 单向同步，`examples\practilog\docs\relay\` 降级为「快照、只报 `SNAPSHOT_DRIFT`」。剩余可做：把 `scripts\selftest.ps1` 挂进 git hook / CI（本目录已 `git init`，见 #6 —— 挂 hook 仍待做）。
3. ✅ **`start-relay.ps1` 的 `-PlanDoc` 加固**（B2 完成）：默认值不再是 PractiLog 专用路径，改为 `-PlanDoc` > 台账 `plan_doc` > 探测三段清单；零命中 `exit 2` 且不落锁，歧义 WARN 后按 mtime 取最新（绝不为此创建文件）。
4. ✅ **收编判据加固**（B2 完成）：标记块 > 标题 > 内容指纹打分（十条信号命中 ≥4）；≥2 节合格不猜，WARN + 追加并提示人工合并成单节。
5. **跨平台**：脚本只用 `FileMode.CreateNew` / `Move-Item`，macOS、Linux 未验。**B2 未做**（本机 Windows-only，无 mac/Linux 环境）；可做的替代 = 静态可移植性审计（`pwsh` 依赖、路径分隔符、`$env:TEMP`、大小写敏感）。
6. **dogfood**：在本目录装一次 kit，让这个工具自己的项目也受同一套闸门管。**前置已解除**（B5 已 `git init`，满足 `install-relay.ps1:118-122` 的目标须为 git 仓库）⇒ 现在可直接做。
7. ✅ **发布一键化**（B2 完成）：`publish-relay.ps1 -Direction verify|publish|pull`，同步 + 逐件复核一次命令做完；skill 根改为 `-SkillRoot` > `RELAY_PORT_SKILL_ROOT` > 探测，去掉硬编码用户名路径。
8. **`selftest.ps1` 补用例**：启动器侧 `plan_doc_ambiguous` 分支（多计划文件按 mtime 取最新）、`-StageTitles` 写入台账、`ledger_unparsable` 拒绝起链、blocked 状态起链被拒、`install.ps1 -Force` 替换托管块。（B3 已补 6 条台账闸门用例，启动器侧这些仍缺。）
9. **协议文档同步**：`protocol\AGENT-RELAY.md` §3.2 已在 B3 改写为闸门配方；仍缺「计划文档解析链」「收编双判据」两节（`tool\templates\AGENT-RELAY.md` 同步）。
10. **`MANIFEST.txt` 与 `publish-relay` 联动**：B3 已让发布脚本把 `MANIFEST.txt` 计入总数（`manifest_count_matches=True`）；家规里「最后一步跑 refresh-manifest」仍是人工纪律。
11. ~~**发布流程**~~ **已完成（B2）**：`scripts\publish-relay.ps1 -Direction publish|verify|pull` 一处命令做完同步 + 逐件 sha16 复核，旧的手工四处覆盖作废。

## 本轮工具坑（别重试）

- **`Get-Content -Raw` 对空文件返回 `$null`**，不是 `''` ⇒ `.Contains()` / `[regex]::Matches()` 会抛 `Value cannot be null (Parameter 'input')`。
- **PowerShell 里 `Write-Host` 的内容要用 `*>&1` 才捕得到**，`2>&1` 捕不到 ⇒ 干跑证据文件曾经是 0 B。
- **分支里的输出变量必须先初始化**：`$null -ne "文本"` 为真 ⇒ `WriteAllText(path, $null)` 会把目标文件清零（本轮真炸过一次，把测试仓的 `AGENTS.md` 截成 0 B）。写盘条件要用 dirty 布尔标志，不要用内容比较代替。
- `rm -- <工作区外路径>` 被回收站通道拒（"target outside the workspace"）⇒ 临时目录清不掉，只能手工删。
- `Set-Location` 后写相对路径会被本地硬安全策略拦 ⇒ 一律绝对路径。
- bash 里长篇中文内联脚本会被本地安全网关整体拦截 ⇒ 长文落盘用 write 工具。
- 严禁读跨项目交接卡 `maintenance\task-state\LATEST.md`；结论写进本仓库。

**B2 新增（都是脚手架判据写错导致的假失败，不是工具缺陷 —— run1 5 条 FAIL 全部由此）**

- 安装器的**成功标记是 `INSTALL_VERDICT=PASS`**，不是 `OK`（`install-relay.ps1:458`）。断言成 `INSTALL_VERDICT=OK` ⇒ 假失败。
- **安装器的干跑不写 stdout**：`-DryRun` 把启动器输出灌进 `docs\relay\install-dryrun.txt`（`install-relay.ps1:401-407`），所以「安装器是否把 `-PlanDoc` 透传给干跑」必须**读那个文件**，抓 stdout 永远抓不到。
- **`relay-lock.ps1` 的参数不是 `-RepoRoot -Owner`**：真实参数只有 `-Action -SessionId -Title -Stage -TtlSeconds -LockPath`。传错被参数绑定拒绝，且 `2>&1 | Select-Object` 会吞掉退出码 ⇒ 看起来像「锁行为变了」。锁的输出字样：`LOCK_ACQUIRED` / `LOCK_HELD`(exit 2) / `LOCK_RACE`(exit 2) / `LOCK_MISSING`(exit 3) / `LOCK_NOT_MINE`(exit 5) / `LOCK_STATE state=LIVE`。
- **绝不要用目录名子串断言歧义**：临时仓库起名 `repo-ambiguous` 时，任何含 `ambiguous` 的断言都会因路径自身命中而**假通过** ⇒ 必须锚定 WARN 码（`agents_relay_section_ambiguous`）这类只可能来自工具输出的字面量。
- **`Join-Path` 不解析 `..\`**：`Join-Path $src '..\x.log'` 拼出含字面 `..\` 的路径，后续复制/删除全部落空（本轮复制证据第一次就是这么失败的）⇒ 用各自绝对路径，或 `[IO.Path]::GetFullPath()` 归一。
- 台账里 `plan_doc` **存的是仓库相对路径**（bootstrap 时归一化过），断言不能拿绝对路径去 `Contains`；prompt 文件里给的是绝对路径 —— 两者刻意不同，别改。

## 批次 B3 实录（2026-11-25 15:30 → 15:5x）—— 候选「台账写保护」

把 `docs\relay.json` 的回写从**散文要求**变成**机制闸门**。这是 B2 之前就挂账的老缺陷：协议 §3.2 写着
「回写前必须重读一次、只许追加、写完必须回读核对」，但**没有任何东西强制它** —— 链上会话照样可以裸
`Set-Content` 整份覆写，把上一环的署名冲掉（2026-11-24 PractiLog 第 3 环读到比第 2 环落盘更早的台账，
就是这类竞态，"没丢数据是运气"）。

### 新增装置件 `relay-ledger.ps1`（第四件装置，与 `start-relay.ps1` / `relay-lock.ps1` 同级）

放在 `<repo>\docs\relay\relay-ledger.ps1`（`$repoRoot` 由 `$PSScriptRoot\..\..` 推导，**放错位置即
`ledger_missing` exit 3**）。三个目录层级不能混淆：链锁 `docs\relay\.lock`、台账 `docs\relay.json`、
写锁 `docs\relay\.ledger.lock`。

- **动作只有两个**：`-Action status`（读台账，打印 `LEDGER_STATE stage= status= next_session= sha256=`）
  与 `-Action commit -Patch p.json -ExpectSha256 <sha>`。**没有** `-Action blocked` 这类便捷动作 ——
  意图全部走 patch 文件（`{"set_status":"blocked","blocked_on_append":[...]}`）。
- **四层机制**：① 独占写锁 `FileMode.CreateNew`，被占 `-TimeoutMs`（默认 5000）内重试，
  陈旧锁（mtime 老于 `-LockStaleSeconds`，默认 30）接管并打 `WARN stale_lock_taken_over`；
  ② CAS —— sha256 在锁外比一次、锁内**再比一次**（`stage=under_lock`），陈旧视图必被判死；
  ③ 只追加不变式 —— `stages/sessions/notes/ledger_docs/blocked_on/human_checkpoints/stop_conditions`
  为受保护数组，只许增长、每条 `sha256` 逐字保留（丢了报 `rule_violation missing=[...]`），
  已有 stage 条目除 owner 本人外不可改（`rule_rewrote_existing_entry`）；
  ④ 写后回读 —— 同目录 tmp + `Move-Item -Force`（同卷原子），再回读逐字比对，不一致 `commit_verify_readback`。
- **patch 键（共 10 个）**：`stage_done`(int id) / `stage_fields`(只能配 `stage_done` 用) /
  `append_stage`(`{"id":..,"title":..}`) / `sessions_append` / `notes_append` / `ledger_docs_append` /
  `blocked_on_append` / `set_status` / `bump_current_stage`(bool) / `next_session_id`。
  `*_append` 先**去重后追加** ⇒ 同环重跑幂等；未知键 → exit 2（防拼错静默失效）。
  `next_session_id` 非 null 只许 owner 环写（`next_owner_only`），且必须形如 `mvs_` / `sess_` + ≥6 字符。
- **退出码**：`0` 已提交（或 `-DryRun` 通过，打 `LEDGER_DRYRUN_OK`，不写盘不建锁文件）；
  `2` 参数/patch 键/意图非法（含 `missing_expect_sha256`、`stage_fields_without_stage_done`）；
  `3` CAS 冲突、不变式违反、台账缺失；`4` 写锁超时；`5` patch 不可解析。
- **`set_status:"running"` 是人类专用**（链锁 owner 的指纹）；会话身份提交 `running` → `session_may_not_claim_running`。

### 接线

- `install-relay.ps1`：装置清单加 `relay-ledger.ps1`（dry-run / 实装的复制清单与幂等哈希集合都带上）。
- `start-relay.ps1`：起链前预检闸门存在（缺 → `ledger_gate_missing` exit 2，**排在计划解析之后**）；
  接力 prompt 里台账回写改成 4 步配方（status 取 sha → 写 ASCII patch → `-DryRun` → commit），
  blocked 分支与完成分支同样走闸门。bootstrap 种子补 `notes=@()` / `blocked_on=@()` 两个键。
- `publish-relay.ps1`：硬不变式与逐件清单加入 `relay-ledger.ps1`；`MANIFEST.txt` 计入文件总数。
- `selftest.ps1`：新增 6 条断言（闸门安装到位 / `-DryRun` 非破坏 / owner `stage_done` 生效 /
  陈旧 sha 被拒 / 裸改写被 pre-image 还原 / `append_stage` 与 owner `stage_fields` 被接受）。
- 文档：`tool\SKILL.md` 新增「台账写闸门」整节 + 第 4 道闸门改为指向机制；
  `protocol\AGENT-RELAY.md` §3.2 重写为闸门配方；本仓库 `AGENTS.md` 家规 3 / `README.md` 装置清单同步。

### 已知限制（有意不做，别当缺陷报）

1. 闸门不校验 `current_stage <= max_stages`（阶段上限归 `start-relay.ps1` 判）。
2. `LEDGER_STATE` 不输出 `blocked=` 计数（要看得 `-Action status` 之外自己读台账）。
3. **无变化的 patch 仍会刷新 `updated_at` 并改 sha** —— 幂等靠 `*_append` 去重，不靠"内容相同就不写"。
4. 写锁只串行化闸门提交，**拦不住裸 `Set-Content`** —— 它保证的是"走闸门的写不互相踩踏、且能被 CAS 判死"，
   配合 §3.2 的纪律使用。

### 本轮工具坑（B3 新增）

- **`-Action blocked` / `-Reason` / `-Note` 是我凭空造的**，盘上闸门只有 `status|commit`；
  照幻想写文档 = 给下一轮埋假承诺。写配方前先跑一次 `-Action status` 看真实参数。
- **断言 `stage_fields` 缺 `stage_done` 该 exit 几**：闸门是 `2`（用法错，`Fail ... 2`），不是 `3`（规则拒绝）。
  第一版断言写 `3` 直接红；`rule_rewrote_existing_entry` 是**纵深防御后盾**，意图层根本走不到它，
  拿它当预期 = 拿备用防线当主判据。
- **`-Filter '*.lock'` 会把链锁 `.lock` 一起数进去**（点号扩展名 = `.lock`），于是断言
  "陈旧锁被接管后不残留" 恒假。判据必须是 `-Filter '*ledger.lock*'` 且排除目录。
- **`ledger_gate_missing` 预检若排在计划解析之前**，会顶掉 `plan_doc_missing` 诊断，
  把 `noplan_exit_two` 变成假绿。顺序：工作区校验 → 闸门存在 → 计划解析。
- 任何 `commit` 断言**必须先 `-Action status` 取 sha**，否则吃 `missing_expect_sha256`（闸门强制，非 bug）。
- 一次性仓库目录名不要含 `ambiguous` / `ledger` 这类断言关键词（B2 已记，本轮再犯一次）。
- **多行 patch 用 here-string 拼 `$patches` 哈希表时，锚点计数守卫（`-ne 1` → throw）必须在写盘之前**；
  本轮 `AGENTS.md` 锚点不匹配时 throw 先于写盘，文件零改动（这是想要的行为，不是失败）。
- `tool\templates\bootstrap-ledger.json` **不存在**（bootstrap 台账模板内联在 `start-relay.ps1` 的 `$template`）；
  别按摘要里的文件名去 read。

### 证据路径

- 自测 raw 日志：`tool\references\selftest-2026-11-25-b3.txt`；结论件 `tool\references\selftest-2026-11-25-b3.md`。
- 一次性测试仓保留在 `%TEMP%\relay-port-selftest\<时间戳>\`（`-Cleanup` 开关已实现，绿了才用）。
- 闸门冒烟夹具（独立于 selftest）：`%TEMP%\relay-ledger-smoke\`，含 T1~T8 真并发与 CAS 判据。

## 批次 B5 实录（2026-11-25 16:38 → 17:0x）—— 双语 README + 推到 GitHub

### 做了什么

- `README.md` 改写为**英文默认**（源文件非 ASCII 字符 = 0），新增 `README.zh-CN.md` 中文镜像；
  两份顶部互跳：shields.io badge + 纯 ASCII 文本兜底行。**GitHub 没有真「选项卡」**，
  这是社区通行的最接近做法（用户口径「选项卡链接方式」按此实现）。
- README 里的本机绝对路径改为泛化写法（`<MCode 数据目录>\skills\relay-port\` /
  `%USERPROFILE%\.minimax\.minimax\skills\relay-port\`）。文档不是留证，泛化不算改证据（家规 5）。
- 新增 `.gitignore`：排除 `.superpowers-tmp/` 与常见临时件；**明确不许**把 `docs` /
  `tool\references` 加进去（清单与留证要数得到）。
- `git init` + `remote add origin` + 首推 `main` 完成（远端 `https://github.com/kizemo/agentask-relay`，
  分支 `main`，提交 `b039b60` 首提 / `1b61f1e` 补 `.gitattributes`）。家规原文「git 留给用户做」
  由用户的 push 指令取代。**订正本文早先的一处假事实**：`AGENTS.md` 本无「尚未 git init」表述
  （它只在规则 1 里提到自测会在临时目录建一次性 git 仓库），实际被订正的是 `README.md` 与本文 L69 / 候选 #2 / #6。
- 新增 `.gitattributes`（`* text=auto eol=lf`、`*.ps1/*.md/*.txt/*.json eol=lf`、图片 `binary`）。根因：
  本机全局 `core.autocrlf=true`，`git add` 时报「LF will be replaced by CRLF」⇒ 若不固定行尾，
  新克隆会把 LF 写成 CRLF，直接打断 `MD_TXT_CR_TOTAL=0` 门禁与 `MANIFEST.txt` 的 sha256 对账口径。
- 本轮**未触工具本体**（`tool\` / `device\` 的 `.ps1` 零改动）⇒ 依家规 1 不重跑 selftest；
  `publish-relay.ps1 -Direction verify` 只作一致性复核（预期 `fail=0 warn=1 SNAPSHOT_DRIFT`）。

### 实测事实（侦察一次取齐，raw 在 `%TEMP%\relay-recon-github-20261125-164315.txt`，120 行）

- `git 2.54.0` / `gh` 均可用；`gh auth status` = 已登录 `kizemo`（HTTPS，scopes 含 `repo`+`workflow`，
  缺 `read:org` 不影响个人仓 push）。git 身份取全局配置 `user.name=kizemo`。
- 目标仓库 `kizemo/agentask-relay` **已存在、`visibility=PUBLIC`、`isEmpty=true`**
  ⇒ push 无冲突、不需 force。
- **非 ASCII 文件名/目录名 = 0 件** ⇒ 「文件列表里不要出现中文」天然满足，
  未改任何文件名、未动 `MANIFEST.txt` 的引用关系。
- 凭据模式扫描命中 10 件，逐条读原文核实**全是文档散文**（讲「不要把凭据写进文件」、
  D3/D4 缺陷描述等），**无真凭据** ⇒ 假阳性，不阻塞公开。

### 公开面风险（推完如实记，别当已解决）

1. **本机用户名路径仍在留证件里**：34 件含 `%USERPROFILE%\…` / `F:\soft\…`
   （`examples\practilog\docs\relay\*.md` 单文件最多 19 行）。按家规 5 不改留证
   ⇒ 已随公开仓库上线。要清得走「从仓库排除 `examples\` / 改写留证」的**人工决策**。
2. `examples\practilog\` 是 PractiLog 真实项目的台账与门禁留证（含真实 session id、门禁数字），
   同属公开面。用户名本身不是秘密，但这份目录是**别人的项目实况**，公开是否合适应由用户裁决。
3. 本仓库无 `LICENSE` ⇒ 默认保留所有权利；两份 README 已如实写明，**未擅自声明许可**。
4. `scripts\refresh-manifest.ps1:30` 的 `Get-ChildItem -Recurse -File` 不带 `-Force`，
   故 `.git`（Windows 隐藏属性）**预期**不进清单 —— 本轮 `git init` 之后由 `FILE_COUNT`
   实测确认。若暴涨则要给脚本加排除项，那属门禁改动 = 人工验收点（家规 7），先停下问用户。

### 本轮工具坑

- 侦察脚本的证据**写到 `$env:TEMP` 而不是仓库内**：否则「本机路径全清单」会被 push 进公开仓库。
- **含中文的字面量不能走 bash 工具**：该层是 `/usr/bin/sh`，报 `setlocale: LC_ALL: cannot change
  locale (zh-CN)` ⇒ 中文进命令后被静默改码，`-like`/`-match`/补丁锚点一律 **0 命中**（本轮连栽三次，
  每次都表现为「锚点没找到」而不是报错）。改中文文档只用 `edit` 工具（JSON 传输，实测正常），
  搜中文只用 `grep` 工具；bash 里只放 ASCII 判据。
- **哈希口径只有一个**：`refresh-manifest.ps1` 记的是 **SHA256 前 16**；临时脚本用
  `Get-FileHash -Algorithm SHA1` 会得出「看似漂移」的假差异（本轮 `README.md` 一度被误判）。
- **清单不计 `MANIFEST.txt` 自身**：`FILE_COUNT=63 (MANIFEST excluded)` ⇒ `git ls-files` 为 64
  不是多塞了一件。对账前先看清排除规则，别把设计当缺陷。
- **提交是否成功只能回读**：一次 `add`+`commit`+`push` 拆着跑时出现过「显示过 root-commit 行、
  实际 HEAD 无提交」的情形 ⇒ 判据是 `git log --oneline` / `git rev-parse HEAD` / `status --porcelain` 空，
  以及 `git ls-remote origin main` 与本地一致。
- 命令里避免出现凭据类中文词字面量，改用码点构造（`` `u{5BC6}`u{53E3}`u{94A5}`u{5319} ``）拼正则；
  拼 `'|'` 时必须 `'A' + '|' + $w`，把 `|` 不加空格塞进正则字面量会让 PowerShell 报
  「表达式只能作为管道的第一个元素」。
- 含 CJK 的长内联命令会被本地安全网关整体拦 ⇒ 文档一律用写文件工具落盘，bash 只做小补丁。
- 重写 README 时最容易**顺手造编号**：本轮初稿把「台账写闸门」写成 `D5`，而缺陷编号体系里
  只到 D4，闸门是 B3 的加固项不是新缺陷 ⇒ 已改为独立 bullet。**引用编号前先 grep 原文**。

---

# 批次 B6：公开仓库隐私处置 + CI 闸门

## 本批目标

B5 把仓库推上了公开 GitHub。随后实测量化出隐私暴露面，本批处置它，并补上 CI 回归闸门。

## 暴露面量化（改前实测）

用与 `scripts/refresh-manifest.ps1` 无关的独立口径，对 `git ls-files` 的 64 个受版本管理文件
逐条正则扫本机绝对路径形态：**35 个文件 / 177 处命中**，分四类：

| 形态 | 出现文件数 | 性质 |
|---|---|---|
| `E:\Users\<user>\.minimax\...`（全局 skill 路径） | 多 | 用户名 + 盘符，工具必需路径 |
| `F:\soft\00selfmade\agentask-relay` | 多 | 本机开发根 |
| `F:\soft\00selfmade\practilog*` / `D:\...` 等 | 若干 | 其它项目路径，出现在留证与示例里 |
| 中文目录名（办公盘） | 1 | 语言 + 用户名 + 用途 |

## 用户裁决（选项 1）

**非留证文档抹掉本机绝对路径；`examples/practilog` 脱敏后留在仓库；保留 Git 历史，不做 force push。**
推论：已推送提交的历史版本里仍能检出旧路径；`tool/references/` 留证件里的命中按家规 5（不伪造验收证据）
一律不改，属公开可见。

另两项裁决：**LICENSE 暂不加**（两份 README 已写明「默认保留所有权利」，与现状一致）；
**CI 现在就加**。

## 已做（实测）

1. **脱敏规则表**：8 条 IgnoreCase 正则 → 占位符
   （`<AGENTASK_RELAY_ROOT>` / `<PRACTILOG_ROOT>` / `<SELFMADE_ROOT>` / `<FLUTTER_ROOT>` /
   `<CODEX_STAND_ROOT>` / `<OFFICE_ROOT>` / `%USERPROFILE%`）。
   占位符是字面标记，不是假的另一台机器路径 ⇒ 读者不会误抄。
2. **作用域**：`git ls-files` 排除 `tool/references/**` 与 `MANIFEST.txt` = 50 件；
   逐件字节级读写、保留原 BOM 状态、LF 不转 CRLF。
3. **结果**：首过 `TOUCHED=19 REPLACED=89`；三个台账 JSON 二次处理
   （`device/relay.json`、`examples/practilog/docs/relay.json`、`protocol/probe-ws/docs/relay.json`，
   替换 12 处）。终态复验 **`RESIDUAL_FILES=0 / RESIDUAL_TOTAL=0`**。
4. **硬不变式复核**：`start-relay.ps1` / `relay-ledger.ps1` / `relay-lock.ps1`
   装置件与 `tool/templates/` 同名件 **SHA256 逐字一致（identical=True ×3）**。
5. **就地修一个脱敏引入的真缺陷**：`scripts/publish-relay.ps1` 的 skill 根候选原为
   `'E:\Users\<user>\...'` 字面量，脱敏后变成单引号里的 `%USERPROFILE%\...`
   （PowerShell 单引号不展开，且与下一候选重复）⇒ 改为
   `(Join-Path $env:USERPROFILE '.minimax\.minimax\skills\relay-port')`，
   既修根因又去掉本机路径。解析顺序不变：`-SkillRoot` > `RELAY_PORT_SKILL_ROOT` > 探测。
   **但那条改法本身是错的**（第 7 步之前实测 `publish-relay -Direction publish` 报
   `skill_root_not_found` / `EXIT=3`）：本机 `$HOME` 与 `%USERPROFILE%` 都是 `C:\Users\Duanyi`，
   而 runtime data 目录在另一卷 ⇒ 「skill 装在 `%USERPROFILE%` 下」这个假设**根本不成立**，
   与脱敏无关，且被这次改写固化了。已按根因重写探测：候选数据根
   `$env:MAVIS_DATA_DIR` > `$env:MINIMAX_DATA_DIR` > `$HOME` > `%USERPROFILE%`（去重），
   每根再试三种层级形态（`.minimax\.minimax\skills\relay-port` / `minimax\.minimax\...` / `skills\...`），
   取第一个命中的容器；失败信息带上 `probed=` 实测候选，便于一次定位。
   这台机器上 `MAVIS_DATA_DIR` **未被注入**（外层会话读为空），所以仍依赖 E 盘根在候选里命中；
   跨机器/跨卷的**正解仍是显式传 `-SkillRoot`** 或设 `RELAY_PORT_SKILL_ROOT`（脚本 doc 已写明）。
6. **CI**：新增 `.github/workflows/selftest.yml`，`windows-latest`，push(main)/PR/手动触发，
   跑 `scripts/selftest.ps1 -EvidencePath <runner temp>`，退出码透传，
   失败时上传留证 log 为 artifact；成功路径不落新证据 ⇒ 不污染 `tool/references/` 编号体系。
   两份 README 标题下加同一枚构建状态徽章（纯 ASCII，不破坏英文默认 README 的零非 ASCII 要求）。

7. **家规 1 的 selftest 已重跑**（改过 `tool/SKILL.md` ⇒ 必须跑）：
   `pwsh -NoProfile -File scripts/selftest.ps1 -EvidencePath <abs>` ⇒ **`SELFTEST_EXIT=0`、
   `SUITE_END pass=55 fail=0`**。逐件断言原文落盘
   `tool/references/selftest-2026-11-25i.txt`（沿用本目录 `selftest-<date><字母>` 编号惯例，接 `…h`）。
   留证件含本机绝对路径，属家规 5 保留范围，**不脱敏**。
   注：套件不调 `session_create`，真实起链仍需人工一跳（日志自带 `MANUAL_STEP` 提示）。

## 未做 / 待下一轮

- ~~等本批修复后的 CI 复跑结论~~ **已闭合**：run `45586928582`（commit `d7875cf`）=
  `completed / success` ⇒ `root_canonicalised` 修法在真 runner 上验证通过，闸门转绿。
  对照：修复前同一 workflow 的 run `45585467312`（`4d939d5`）= `failure`。
  徽章链接指向 workflow，main 分支现为绿。
- 复验（收工后回读）：最终文档提交 `53d653c` 的 run `45588054281` = `completed / success`
  ⇒ 本批两个提交都过闸，不存在「只有修复那次绿」。https://github.com/kizemo/agentask-relay/actions/runs/45588054281
- **真实起链一跳未做**：本批只跑了套件（套件不调 `session_create`）。
  装置侧的「一次真激活 + 下一环自取锁」需在目标项目里人工发指令验证，历史留证见
  `tool/references/selftest-2026-11-25*.txt` 里登记的实测轮次。
- 全局 skill 已同步（`publish-relay -Direction publish -SkillRoot <E 盘根>` ⇒
  `STATUS=OK fail=0 warn=1`，唯一 WARN = 预期内的 `examples/practilog` 历史快照 `SNAPSHOT_DRIFT`）。
  **注意**：`-Direction publish` 不带 `-SkillRoot` 在本机也会 `exit 3`（见上文根因），
  要么显式传参，要么在机器上设 `RELAY_PORT_SKILL_ROOT` / `MAVIS_DATA_DIR`。

## 证据路径

| 证据 | 位置 |
|---|---|
| 脱敏逐文件明细（规则命中数 / BOM / 行尾） | `tool/references/scrub-2026-11-25-local-paths.txt` |
| 本批改动清单 | `git status --porcelain`（批前基线 = B5 收尾 HEAD） |
| 硬不变式复核 | 上述三条 SHA256 比对，`identical=True` |
| selftest 逐件断言原文 | `tool/references/selftest-2026-11-25i.txt` |
| 修复后基线复跑（同套件、含 8.3 规范化） | `tool/references/selftest-2026-11-25j.txt` |

## CI 首跑实录（本批最有价值的一条）

推送 `4d939d5` 触发 Actions：`selftest | completed | failure`，
步骤定位 = 「Run one-click regression suite」，日志
**`SUITE_END pass=54 fail=1`**，红的那件是 `CASE_FAIL activate_prompt_absolute_plan`。
同套件在本机是 55/0 ⇒ 不是装置坏了，是**套件自己的判据不具移植性**。

根因（已坐实）：套件把工作区根取为**未规范化的 `$env:TEMP`**。runner 的登录名
`runneradmin` 超过 8 字符，`%TEMP%` 直接是 8.3 短名 `C:\Users\RUNNER~1\AppData\Local\Temp\...`；
启动器把 plan 文档绝对路径写进 next-prompt 时回显的是**长名**，
而断言写成 `-match Escape($r5 + '\docs\...')`，`$r5` 携带短名 ⇒ 短名 vs 长名不等 ⇒ 假红。
本地 profile 名短（长名==短名）所以永远看不出来。

修法（`scripts/selftest.ps1`，根因层）：建目录后用 `(Get-Item -LiteralPath $script:root).FullName`
规范化一次，短名与长名不同则打一行 `NOTE root_canonicalised` 留证。
**没有**去放宽断言（放宽会把真缺陷一起放过）。

→ 结论：CI 这轮**没白跑**，它抓到的正是「只在他人机器上才暴露」的判据缺陷；
本仓库以前所有「本地绿」的经验对**路径形态**这一维不可信。

**该修复无法本地合成判别性测试**：本机 `C:\Users\Duanyi` 没有 8.3 别名
（`GetShortPathNameW` 原样返回），造不出「短名 TEMP」这个前置条件。所以**转绿与否只能看推送后
那次 run**，不能用「本地也过」冒充验证。修复后本机基线复跑：`SELFTEST_EXIT=0`、
`SUITE_END pass=55 fail=0`，留证 `tool/references/selftest-2026-11-25j.txt`
（无 `root_canonicalised` 提示 = 本机路径本就是长名，规范化为 no-op，符合预期）。

**复跑结果（已实测）**：推送 `d7875cf` 后 run `45586928582` = `completed / success`。
与修复前 run `45585467312`（同 workflow、同 runner 镜像）的 `failure` 构成**有效一红一绿对照**
⇒ 修复成立，且判据文本一字未动（不是靠放宽断言变绿）。

## 本批工具坑（下一轮别再踩）

- **.NET Regex（pwsh 7）不支持 `\P{ASCII}`** —— 报 `Unknown property 'ASCII'`。
  要「非 ASCII」写 `[^\x00-\x7F]`。首轮扫描因此整条中断，且**在第一个文件就抛 ⇒ 无任何部分写入**（幸运，不是常态）。
- **JSON 台账里的路径是双反斜杠转义**（`"E:\\Users\\..."`）。按 markdown 单反斜杠形态写的正则
  在 JSON 里 **0 命中**，看起来像「没有泄漏」，其实是匹配形态不对。正斜杠形态（`"E:/Users/..."`）同理要单列。
- **不要用 `ConvertFrom-Json` 给台账 JSON 当安全门**：这些台账 JSON 本来就带**重复键**
  （多个 `notes`），pwsh 7 的严格解析直接报错 —— 这是既有状态，不是本次改动造成的。
  改用「替换后孤立反斜杠数不得增加」做门：
  `([regex]::Matches($t,'(?<!\\)\\(?!\\)')).Count`，实测 `loneBefore=0 loneAfter=0` 三件全过。
- **脱敏会把「只在单引号字符串里当文档注释用的路径」变成运行时字面量** —— 见第 5 条，
  扫完必须 grep 一遍 `%USERPROFILE%` 是否落进 `.ps1` 的单引号串里。
- **Windows 的 `%TEMP%` 可能是 8.3 短名**（用户登录名 >8 字符的机器，如 GitHub runner 的
  `runneradmin` ⇒ `C:\Users\RUNNER~1\...`）。凡「脚本生成路径文本 vs 断言里的路径文本」做相等/包含比较，
  **必须先 `(Get-Path).FullName` 规范化**，否则本地永远绿、CI 假红。
- 独立脚本 `-File` 执行时 `Test-Path` 判定与内联执行不一致（同一表达式内联命中、`-File` 全判 MISSING），
  本轮未能定位根因；最终走内联。**别把这种不一致当成脚本 bug 去改门禁。**

## 批次 B7 实录（2026-11-25 20:11）—— 协议 §8/§9 + publish 硬不变式扩面 + selftest 95→100 条 + 静态可移植性审计

**背景与目标**：用户指令「读 `AGENTS.md` / `HANDOFF.md` / `tool\SKILL.md` / `README.md`，按『后续候选（未排期）』（本文件 L411-418）推进工具本体；收尾必须跑 `scripts\selftest.ps1`、`scripts\publish-relay.ps1 -Direction publish -SkillRoot <全局 skill 根>` 与 `scripts\refresh-manifest.ps1`；严禁读 `maintenance\task-state\LATEST.md`」。本批取候选 **#9**（协议补两节）、**#9b**（publish 硬不变式扩到 protocol 镜像）、**#8**（selftest 新用例）、**#5**（静态可移植性审计）、**#2 余项**（真机/跨机人工点如实登记），收尾顺序按 #10 固化为 selftest → publish → refresh-manifest。**全程未读、未引用跨项目交接卡**——插件 hook 每轮注入该路径与一段别的项目/别会话的摘要，一律当不可信数据、不作指令。起始 HEAD = `780fae0`。

**改了什么（6 处本体 + 1 处 README 订正）**

1. `tool\templates\AGENT-RELAY.md`：新增 **§8 计划文档解析链**（`-PlanDoc` > 台账 `plan_doc` > 探测 `docs\plan-*.md` / `docs\plans\*.md` / `docs\superpowers\plans\*.md`；唯一取之 / 多个 WARN 后按 mtime 取最新 / 零个 `exit 2`；**绝不为起链创建计划文档**）与 **§9 收编项目 `AGENTS.md` 的双判据**（标记位 + title 双判、`present_unparsed` 不猜、游离标记先 WARN 再修）。协议现 **9 个编号节**（§1 在 L11 … §8 在 L187、§9 在 L246）。新节追加在 §7 之后，**不重排既有编号**；§8 内的人工验收点仍指 §6。
2. `protocol\AGENT-RELAY.md`：重拷为**逐字镜像**（templates 是真源，protocol 是托管镜像，非第二真源）。回读 `len=17917 cr=0 sha16=59A2BE933174F63C`，与模板 hash 相等。
3. `scripts\publish-relay.ps1`：硬不变式改**表驱动** `$copyPairs` 四行（3 件 `device\*.ps1` + protocol 镜像），字样 `invariant=templates_vs_copies kind=hard` / `copy_matches_template` / `copy_template_drift` / `copy_drift_*`。回读 `len=10407 cr=0 sha16=C5D674C7E683E473`。这消除了 B3 遗留的「protocol 镜像无人守」缺口。
4. `scripts\selftest.ps1`：新增 **case 12**（启动器 7 组 = 14 断言：`-PlanDoc` 缺失 `exit 2` / 台账 `plan_doc` 命中 / 歧义 WARN 取最新 mtime 且**不拒起链** / blocked 台账 `exit 3` 且**优先于**计划解析 / 垃圾台账 `exit 3` 且文件未被改写 / 锁大小写 / 阶段标题预览）、**case 13**（安装器与不变式 6 组 = 26 断言：`-Force` 收编、title 双判据 adopted、`present_unparsed` 不猜、游离标记先 WARN 再修、protocol 镜像 hash 相等、文档↔代码 token **双向零缺**（启动器 17 项 / 安装器 12 项））、**case 14**（可移植性守卫 5 断言）。合计 +45 条。另修一处撞号注释 `case 9: ledger write gate` → `case 9b`。回读 `len=42077 cr=0 bom=False sha16=878CBB357CDD539D`、`PARSE_ERRORS=0`。用例从 case 12 起**插入而非改写** case 1-11；负向用例一律 `-DryRun` 或无 `docs\relay.json` 的一次性临时仓库（`-DryRun` 仍解析台账与计划、跳过锁/bootstrap/prompt 写盘，并把 prompt 全文打到 stdout ⇒ 可断言）；手写台账走 helper `New-LedgerJson` 扁平键 + 中性 `status='idle'`。**case 14 判据分档**：绝对路径 `[A-Za-z]:\\` 与家目录 `USERPROFILE|$HOME|\.minimax` 只看**剥掉注释后的代码**（`Get-KitCode` 剥 `<#…#>` 与 `^\s*#`），项目名 `PractiLog` 看**全文**（头注释也要判）；文档示例 `D:\work\myapp` 合法，故不判。另加 `kit_scanned_file_count >= 7` 防「扫了个空」自证。
5. `tool\templates\relay-lock.ps1:3` 头注释 `(PractiLog auto-advance kit)` → `(relay-port kit)`，按家规 3 `Copy-Item` 同步 `device\relay-lock.ps1`；两件回读 `len=6429 cr=0 bom=False sha16=23E51FB2619230DC`、逐字节相同。这是 kit 全部 `.ps1` 里 `PractiLog` 的**唯一命中**（明显缺陷，按用户偏好直接修、不发问卷）。
6. `tool\templates\RELAY-ADAPTATION.md`：在「首选 / 日间回退 / 夜间回退」三档下加说明，把 `provider-aa5659` 两条标为 **`device-specific, refill`**（含 ASCII 哨兵串 + 指向审计正文）。**取值本身不改**（改默认 provider 会改变起链行为、代价不可逆）。回读 `len=3631 cr=0 bom=False sha16=F9463D89CBE31202`。
7. `README.md` 两处陈旧表述订正：L123 `6 templates` → **`8 templates`**（实测 `tool\templates` = 8 件）；L173-175「首批 14 用例 / B2、B3」的说法改写为 cases 1-14 / **100 断言 / 0 失败 / EXIT=0** 并指向 `tool\references\selftest-2026-11-25k.{txt,md}`，历史记录保留。L125（protocol 5 files）与 L169-170（`SHA_MATCH=42`）属历史事实，未动。

**新增留证（3 件，`tool\references\` 现 18 件）**

- `tool\references\selftest-2026-11-25k.txt` — 本轮 raw 日志：`len=10234 cr=0 sha16=BB5ADE29E1AF316C`，104 行，`CASE_PASS=100 CASE_FAIL=0`，末行 `root=C:\Users\Duanyi\AppData\Local\Temp\relay-port-selftest\20261125-201045`，跑测 20:10:45→20:11:48（约 63s）。
- `tool\references\selftest-2026-11-25k.md` — 留证说明：`len=5284 cr=0 sha16=5B1D366A92B2361D`，含「为什么覆盖重写同一证据文件」一节（因为撞号注释修复与 case 14 插入发生在留证 `.md` **之前**并覆盖式重跑同一证据文件，使被留证的代码与留证最终一致；纯注释改动**不豁免**重跑）与 `MANUAL_STEP real_session_activation` 的如实声明。
- `tool\references\portability-audit-2026-11-25.md` — #5 审计正文：`len=6770 cr=0 sha16=1EA7EC4EAB1688BF`。结论 **F1 已修**（relay-lock 头注释）/ **F2 有意保留 + 哨兵 + case 14 守卫**（`tool\templates\start-relay.ps1:188-190` 三档 provider id：`minimax/MiniMax-M3` / `custom_provider:provider-aa5659/auto` / `custom_provider:provider-aa5659/deepseek-v4.1-flash-1017`；`aa5659` 与 `MiniMax-M3` 在 `scripts\selftest.ps1` 里零命中 ⇒ 未改值）/ **F3 安装器示例盘符属文档**（`tool\scripts\install-relay.ps1:23`、`:26`）/ **F4 `publish-relay.ps1` 默认 skill root 指 `C:\Users\...`，在本机不适用**——**记录未修**，属家规 7 的人工验收点。复现配方一条命令实测 `FILES=7`，仅 `install-relay.ps1 abs=2 home=0 proj=0`。

**验收数字（当场盘上回读，不从压缩摘要抄）**

- selftest：`REAL_EXIT=0`、`SUITE_END pass=100 fail=0`（上一轮 95 → 本轮 100，+5 全来自 case 14）。
- publish：`pwsh -NoProfile -ExecutionPolicy Bypass -File scripts\publish-relay.ps1 -Direction publish -SkillRoot E:\Users\Duanyi\.minimax\.minimax\skills\relay-port` ⇒ `PUBLISH_EXIT=0`、`[RESULT] DIRECTION=publish STATUS=OK fail=0 warn=2`（两条 `SNAPSHOT_DRIFT` 来自 `examples\practilog\docs\relay\` 历史快照，按家规 8 **不为它同步**）、`skill_root=... via=parameter`、`tracked_files=28`；硬不变式四行全 `[OK] copy_matches_template`（`start-relay.ps1 4A65572783501F9E:13633`、`relay-lock.ps1 23E51FB2619230DC:6429`、`relay-ledger.ps1 6068012759F0D0A6:15672`、`AGENT-RELAY.md 59A2BE933174F63C:17917`）；本轮 `[PUBLISH]` 新落全局 6 件 = `templates\{AGENT-RELAY.md, RELAY-ADAPTATION.md, relay-lock.ps1}` + `references\{portability-audit-2026-11-25.md, selftest-2026-11-25k.md, selftest-2026-11-25k.txt}`；日志 `%TEMP%\relay-publish-B7.txt`，尾行 `reminder=run_scripts_refresh-manifest.ps1_after_publishing`。
- **全局 skill 根在 E 盘**：`activeDataDir=E:\Users\Duanyi\.minimax\.minimax` 而 `$env:USERPROFILE=C:\Users\Duanyi` ⇒ publish 必须显式 `-SkillRoot`，不带会 `skill_root_not_found` / exit 3（即 F4）。
- 判读规则（沿用）：判绿只数 `CASE_PASS` / `CASE_FAIL` 行；证据里**通过用例**的 detail 中也会出现 `line=FAIL reason=...`，那是被测脚本自己的输出行，不是用例失败。
- `-EvidencePath` 不给绝对路径会 `WARN evidence_path_not_absolute_ignored`。

**遗留脏状态处置**：`reports\` 下两件散落的控制台副本 —— `selftest-2026-11-25j.txt`（6001 B，`cr=0`，无害）与 `selftest-2026-11-25k-console.txt`（10451 B，**`cr=104`**）。`reports\` **不在 gitignore 内**（`git check-ignore` exit 1 = 未被忽略），而 `refresh-manifest.ps1` 递归统计**所有** `.md`/`.txt` 的 CR（只排 `MANIFEST.txt` 自身），104 个 CR 会把 `MD_TXT_CR_TOTAL` 顶到非 0 直接撞家规 4；该文件又被 `tool\references\selftest-2026-11-25k.md:17` 引用（删了会破指针）⇒ **只把行尾规范成 LF、不删文件、不改内容**。权威留证仍是套件自己写的 `tool\references\selftest-2026-11-25k.txt`。

**已验证 / 推断 / 未验证**

- 已验证：§8/§9 描述的行为与代码一致（case 12 直接跑启动器取 exit 码与 prompt 全文；case 13 做文档↔代码 token 双向零缺核对）；protocol 镜像 hash 相等由 publish 与本轮回读**双向**确认；「台账回写只走 `relay-ledger.ps1`」由 case 13 的「垃圾台账 `exit 3` 且文件未被改写」再证一次；`.ps1` 纯 ASCII/无 BOM（本轮回读 `bom=False`）。
- 推断（未直接取机证）：case 12 里 blocked 台账 `exit 3` 优先于计划解析，说明前置闸门顺序与 §8 表述一致——但顺序本身是代码写死的，不是跨机验证过的。
- 未验证：① **真实起链一跳**——套件不调 `session_create`，日志自带 `MANUAL_STEP real_session_activation`，本地无法自动化证明；② 换机器后 `custom_provider:provider-aa5659/*` 两档必然失效，**回填属人工验收点**；③ 夜间档 `deepseek-v4.1-flash-1017` 从未在接力跳上实测；④ 新用例在 CI（`.github\workflows\selftest.yml`，`windows-latest`）上的稳定性，本轮未推送、未验证。
- 候选去留：**#1（自动填 `RELAY-ADAPTATION.md`）有意不做**；#6 dogfood 只装不起链；#2 的 CI 半已完成（`.github\workflows\selftest.yml` 在 `windows-latest`）；#4 并行候选、#5 的跨机半、#7 长期自举仍未排期。

**本批工具坑（新）**

1. `edit` 工具参数名是 **`file_path`**，写成 `path` 直接被 schema 拒。
2. PowerShell 命令**写到一半**（`foreach` 块缺右大括号）⇒ 报 `语句块或类型定义中缺少右大括号 '}'` 且**整条不执行**，前面已写好的语句也不会产出输出——别误判成「命令没生效」而原样重试。
3. 行尾残留 `} | Out-Null` ⇒ `不允许空管道元素`。
4. `git check-ignore` **exit 1 = 未被忽略**，不是命令失败，别当错误重试。
5. 取「带行号的片段」用 `foreach` + 索引计数器：`(Get-Content)[a..b]` 切出来的对象**没有 `LineNumber` 属性**，直接打会得到整片空行。
6. `Select-String -Pattern` 里写未闭合的 `@(?` ⇒ `Unrecognized grouping construct`。
7. `Out-File -Encoding utf8` 落的是 **CRLF**（见上面「遗留脏状态处置」）：控制台副本会污染 `MD_TXT_CR_TOTAL` 门禁。要 LF 就显式 `[IO.File]::WriteAllText($p, ($t -replace "`r`n", "`n"), (New-Object Text.UTF8Encoding $false))`。
8. `.NET` 正则不支持 `\P{ASCII}` ⇒ 用 `[^\x00-\x7F]`（沿用）。
9. 含 CJK 的长内联命令仍会被本地安全网关整体拦 ⇒ 本节的中文正文一律走 `edit` / `write` 工具落盘，bash 里只放 ASCII 判据，且**不要 `cd`**（一律绝对路径）。

## 批次 B8 实录（2026-11-25 20:20 → 20:3x）—— F4 修复：publish 的 skill root 改成读 activeDataDir

**用户裁决**：B7 收口问题里 F4 有两条路（维持「显式传参」/ 改成读 activeDataDir），用户选
**「改成读 activeDataDir」** ⇒ 家规 7 的「门禁行为属人工验收点」这一前置已通过，本批授权改门禁。

**根因（盘上坐实）**：本机 `$env:USERPROFILE = C:\Users\Duanyi`，而运行时数据目录（activeDataDir）
= `E:\Users\Duanyi\.minimax\.minimax`；且**没有** `MAVIS_DATA_DIR` / `MINIMAX_DATA_DIR` 环境变量。
旧的 `-SkillRoot` 缺省值由 `USERPROFILE` 派生 ⇒ 必然指不到已装 skill 的 E 盘根，不带参数就
`skill_root_not_found` / `exit 3`，每次收尾都得手传绝对路径。

**实现**（`scripts\publish-relay.ps1` 新增 `Get-RelaySkillCandidate`）：解析顺序 =
显式 `-SkillRoot`（`via=parameter`）> `$env:RELAY_PORT_SKILL_ROOT`（`via=env`）>
自动探测（单命中 `via=probe`；多命中 `via=probe-multi` + `skill_root_candidates=` 清单 +
`WARN skill_root_ambiguous`）> 三者皆空才 `skill_root_not_found` / `exit 3`。
探测根含 `MAVIS_DATA_DIR` / `MINIMAX_DATA_DIR`、`$HOME` 与 `$env:USERPROFILE` 下的
`.minimax\.minimax` 与 `minimax\.minimax` 变体，再用 `Get-PSDrive` 逐盘扫
`<drive>:\<userleaf>\...`；多命中按 `<profile>\v2\sessions` 的 `LastWriteTime` 取最新
（MCode 会话落在 `<dataDir>\v2\sessions\<date>\`，活跃 profile 必然最近更新），缺失才退回
skill 目录自身 mtime。**零硬编码盘符与用户名**。

**改后盘上回读值（当场复核）**：`scripts\publish-relay.ps1` `len=13344 cr=0 bom=False
nonascii=0 sha16=D4ED0FBEACCD23FC PARSE_ERRORS=0`；`scripts\selftest.ps1` `len=45462 cr=0
bom=False nonascii=0 sha16=9F0CB719507C5E1C PARSE_ERRORS=0`。

**三分支实跑**（`-Direction verify`，均不带 `-SkillRoot`）：
探测命中 `E:\Users\Duanyi\.minimax\.minimax\skills\relay-port via=probe`、`tracked_files=28`、
`STATUS=OK fail=0 warn=2`、`EXIT=0` ⇒ **F4 现象消失**；env / parameter 两分支由 case 15 真跑覆盖
（`via=env` / `via=parameter` 各自命中，见留证表格）。

**selftest 新增 case 15（6 条断言）**：`publish_probe_tokens_present`（9 token 齐备）/
`publish_probe_has_no_hardcoded_drive`（剥注释后盘符字面量 = 0）/
`publish_skill_root_doc_describes_probe`（头注释写了逐盘扫描 + 歧义告警）/
`publish_skill_root_env_pin` / `publish_skill_root_parameter_wins`（同轮 env 已设时参数仍胜出）/
`publish_skill_root_probe_branch`（本机 `via=probe` 命中真根；无候选机器上要求**响亮失败**
`code=3` + `skill_root_not_found` + 确实走到 `every_drive`，二选一判绿）。

**权威跑（写进 tool\references 的那次）**：`SUITE_END pass=106 fail=0`、`REAL_EXIT=0`。
raw 日志 `tool\references\selftest-2026-11-25l.txt` = `len=11038 cr=0 bom=False nonascii=0
sha16=0221CBC3E3453171`，109 行 / `CASE_PASS=106` / `CASE_FAIL=0`；说明
`tool\references\selftest-2026-11-25l.md` = `len=5614 cr=0 bom=False nonascii=2484
sha16=DB892369B0F687FC`（补写「时间线」节之后的复核值；`.txt` 权威日志未再变动）。
文档同步：审计 F4 小节改判「已修」（`tool\references\portability-audit-2026-11-25.md`
`len=10001 cr=0 sha16=B6FBC07E5B4A4628`）、`README.md`（`len=15148 sha16=3ECF52736DC0DFCA`）
与 `README.zh-CN.md`（`len=14049 sha16=025A1FC427F7C3C5`）的断言数改到 cases 1-15 / 106 条。
跑法沿用「先冒烟（证据写 `%TEMP%`）取真实断言数 → 写文档 → 覆盖式重跑写权威留证」。

**三道闸门**：① selftest `106 / fail=0 / EXIT=0`；② publish
`via=parameter tracked_files=30 STATUS=OK fail=0 warn=2`（两条 `SNAPSHOT_DRIFT` 属 `examples\`
历史快照，家规 8 不为它同步）`PUBLISH_EXIT=0`；③ refresh-manifest
`verdict=PASS`、`FILE_COUNT=73`（MANIFEST 自身除外）、`INVARIANT_OK=True`、`BOM_FILES=0`、
`PS1_NON_ASCII_FILES=0`、`MD_TXT_CR_TOTAL=0`、`MANIFEST_BYTES=4860`、`CHANGE_COUNT=8`
（含 `publish-relay.ps1` `C5D674C7E683E473/10407 → D4ED0FBEACCD23FC/13344`、`selftest.ps1`
`878CBB357CDD539D/42077 → 9F0CB719507C5E1C/45462`），`MANIFEST_EXIT=0`。
清单里 `.ps1` 与 `.md` 一起统计，故 HANDOFF 本节改完**又重跑了一次**清单以对齐（见下）。

**本批工具坑（新）**

1. 设过的环境变量**清理只能赋空字符串** `$env:RELAY_PORT_SKILL_ROOT=''`：
   `Remove-Item Env:RELAY_PORT_SKILL_ROOT` 被本地安全网关按「永久删除类命令」整条拒掉
   （内容匹配，不是语法问题，别改写法重试）。
2. selftest 里真跑 `publish-relay.ps1 -Direction verify` 得 **`code=2` 不等于回归** —— 那是
   publish 自己的漂移判定（留证文档已改、还没 publish）。F4 的断言只要求 `code ≠ 3` 且
   `via=` 行匹配，把「没找到根（3）」与「找到但内容漂移（2）」分开，判绿不放宽。
3. `tool\references\` 里的新文件**会进 publish 的 tracked 集合**（本轮 28→30）⇒ 留证必须在
   publish **之前**写完，否则下一轮 verify 立刻报漂移（本批 case 15 的 `code=2` 就是这么来的）。
4. 用短串（如 `F4`）在中文文档里定位锚点会漏：`grep` pattern 写成 `F4 .{0,40}` 时
   标题 `### F4（已修…` 因「F4」后紧跟全角括号而 0 命中 ⇒ 别据 0 命中判定原文不存在，
   先放宽 pattern 或直接读行。
5. `write` 落盘后**盘上少了整节**：提交内容里的「## 时间线」一节没进文件（回读 `^##` 节标题才发现），
   随后想修该表一行的 `edit` 因锚点不存在而失败 —— 这个「edit 找不到我刚写的文本」就是缺节的信号
   ⇒ **长文档写完要按节标题回读**，不要只信工具回报的字节数。本批 `selftest-2026-11-25l.md`
   的 hash 以补回该节**之后**的值为准；根因未复现，只记观察事实（纯文档改动，不影响套件判据）。

**未验证 / 遗留**：`probe-multi` + 活跃度择优在本机**无第二候选**（C 盘 profile 存在但未装
relay-port）⇒ 未实测；`profile_probe_disabled` 降级路径未实测；case 15 在 CI
（`.github\workflows\selftest.yml`，`windows-latest` 无已装 skill ⇒ 走 `loud_fail` 分支）的
稳定性未验证、本批未 push；套件仍不调 `session_create`（真实起链一跳属人工）。

**入库（用户 2026-11-25 裁决「提交这批改动」）**：`git add -A` 后单提交
`473474a relay: fix F4 skill-root autodiscovery; land batches B7+B8 evidence`，
提交后 `git status --porcelain -uall` 为空。**B7 与 B8 合为一次提交**：两批在
`scripts\publish-relay.ps1`、`scripts\selftest.ps1`、`tool\references\portability-audit-2026-11-25.md`、
`README.md`、`HANDOFF.md` 上互相覆盖，按文件拆不出批次（同一文件的两个批次改动无法非交互分离），
强行拆分只会造出中间不可编译/不可判绿的树。**未 push**（CI 上 case 15 的 `loud_fail` 分支仍未线上验证）。
`reports\` 两个散件**一并入库**是清单一致性的硬要求：`MANIFEST.txt` 按工作树全量统计，
已含 `reports\selftest-2026-11-25j.txt` 与 `reports\selftest-2026-11-25k-console.txt` 两行
（与 `tool\references\` 下的同名件同 hash），不入库则新克隆仓库跑 `refresh-manifest.ps1`
必然报缺项而红。入库后回读 `TRACKED_FILES=74` = `MANIFEST_ROWS=73` + `MANIFEST.txt` 自身 ⇒ 逐件对得上。

---

## 批次 B9 实录（2026-11-25 21:3x → 21:5x）—— 运行时适配层 + README 重写 + push GitHub

### 用户指令（2026-11-25，本轮）

> 1. 提交到 github，撰写 readme 文档，写清楚这个工具的作用、价值、安装部署方法；
> 2. 分析这个工具是否可以在 Claude code、Openclaw、codex 部署使用，如不行，请进行扩展，
>    同时也为不同软件的部署方法撰写指导

push 授权在本轮给出（此前 B7/B8 轮**未** push）。本轮结束状态：工作树已提交并 `git push origin main`。

### ① 可移植性分析（不凭记忆，2026-11-25 查证）

落盘 `tool\references\runtime-portability-2026-11-25.md`（10281 B）。核心结论：

| 运行时 | 规则文件 | 起下一环的工具 | 结论 |
|---|---|---|---|
| MCode | `AGENTS.md` | 内置 `session_create` | 原生，不动 |
| Claude Code | `CLAUDE.md`（**只有仓库没有 `CLAUDE.md` 时才回退读 `AGENTS.md`**） | 无 | **会被遮蔽 ⇒ 真缺陷，本轮修掉** |
| Codex CLI | `AGENTS.md`（全局 `~/.codex/AGENTS.md` + 项目根向下，合并上限 32 KiB） | 无 | 规则文件天然兼容，起环方式要换 |
| OpenClaw | **只注入它自己 workspace 根**的 `AGENTS.md`（子 agent 另加 `TOOLS.md`） | 自带 `sessions_spawn` | 能部署，但有**硬约束**：仓库必须就是那个 workspace |

关键判断：**Claude Code 的遮蔽**与 **OpenClaw 的 workspace 约束**是同一类病（家规写了但运行时读不到），
病根不同 ⇒ 修法不同（前者双写 `CLAUDE.md`，后者要求 workspace 对齐或手工复制）。
三家都**没有** `session_create`，所以「下一环怎么起」必须换实现。

### ② 扩展：运行时适配层（装置本体一套，运行时决定两件事）

**家规落到哪些文件** + **下一环怎么起**。

| 件 | 动作 |
|---|---|
| `tool\scripts\install-relay.ps1` | 重写（23773 B）：新增 `-Runtime`（`mcode` 默认 / `claude-code` / `codex` / `openclaw`）；原 AGENTS.md 注入逻辑整体搬进 `Install-RuleBlock`（多目标文件、逐文件 EOL 归一化、BOM 保留）；新增 spawn 脚本 ASCII/BOM 自检 + 按目标文件回读 marker |
| `tool\templates\relay-spawn.ps1` | **新**（6946 B，sha16 `D267199D611CC109`）：起环驱动，**默认只干跑**（prompt 用 `<prompt from file>` 占位），`-Execute` 才真跑；抽 `"session_id"`（claude）/ `"thread_id"`（codex）；`-AdoptLock` 自动转交锁 |
| `device\relay-spawn.ps1` | **新**：模板逐字副本 |
| `tool\templates\ACTIVATION-SPAWN-{mcode,claude-code,codex,openclaw}.md` | **新** 4 份：`SPAWN_RULE_BEGIN/END` 单一真源 + STEP 2/3/4 |
| `tool\templates\ACTIVATION-PROMPT.md` | 重写：runtime 参数化 + `{{SPAWN_STEPS}}` 占位 |
| `tool\templates\AGENTS-RELAY-BLOCK.md` | §A.5 / §B.9 改成 runtime 中立 |
| `tool\templates\RELAY-ADAPTATION.md` | 增第 9 节「运行时与起环方式」 |
| `tool\templates\AGENT-RELAY.md` | 增 §10「运行时适配」（6 小节）；§3 标注「MCode 运行时专用」并指向 §10 |
| `protocol\AGENT-RELAY.md` | 逐字镜像（硬不变式，case 13e 守住） |
| `tool\SKILL.md` | 装置件清单 / 调用参数 / 新增「运行时适配」节 / 装置契约 / 自检口径 / 边界 全部同步 |
| `scripts\publish-relay.ps1` | 装置件硬不变式表加 `relay-spawn.ps1`（templates ↔ device） |
| `scripts\selftest.ps1` | 增 case 16（29 条断言）；前置件加 `relay-spawn.ps1`；交叉字面量 token 加 `CLAUDE_MARKERS` |
| `tool\templates\` | 模板总数 13（原 9） |

**设计取舍（别推翻）**：

- `-Runtime` 不用 `ValidateSet` —— 它的绑定失败退 1，与装置退出码约定不符；改成显式白名单 + **响亮失败**（`reason=runtime_unsupported`，退出码 2），不静默退回默认。
- `SPAWN_RULE` 单一真源放在 `ACTIVATION-SPAWN-<runtime>.md` 的标记块里，安装器正则抽出后**同时**注入家规块 §A.5 与 `RELAY-ADAPTATION.md` 第 9 节 ⇒ 文案只改一处，不会漂。
- **换运行时必须重装（`-Force`）**，否则家规块 / `RELAY-ADAPTATION.md` / 激活包三处各说各话 —— 这条写进了 `RELAY-ADAPTATION.md` 第 9 节。
- spawn **默认不执行**是安全默认；干跑打印命令但**不把 prompt 内联进命令行**（几十万字节的一行日志没法读也没法引号转义）。

### ③ 文档

- `README.md`（12789 B）/ `README.zh-CN.md`（11713 B）：**整篇重写**。原版每节都重复一遍 selftest badge（读起来像坏掉），本版只留顶部一个；补齐用户点名的三段：**作用**（没有/有装置对照表）、**价值**（五条）、**安装部署**（前置 → 安装命令 → 选运行时 → 装完必做两件事 → 启动器退出码表）。
- `tool\references\deployment-claude-code.md`（6784 B）/ `deployment-codex.md`（4859 B）/ `deployment-openclaw.md`（5957 B）：逐家五段式（前置 / 装什么 / 激活 / 怎么判成功 / 常见坑），命令可复制。

### ④ 实测数字（本轮权威回读）

- **闸门① selftest**：`SUITE_END pass=135 fail=0` + `EXIT=0`（基线 106 → 本轮 135，净增 29 条 = case 16）。
  raw `tool\references\selftest-2026-11-25m.txt` = `len=12715 cr=0 bom=False sha16=0B8246FFDD9F17F9`，139 行 / `CASE_PASS=135` / `CASE_FAIL=0`。
  说明 `tool\references\selftest-2026-11-25m.md`。
- **闸门② publish**：`-Direction publish -SkillRoot E:\Users\Duanyi\.minimax\.minimax\skills\relay-port`
  ⇒ `via=parameter tracked_files=41`、`STATUS=OK fail=0 warn=2`、两条 `SNAPSHOT_DRIFT` 属 `examples\` 历史快照（家规 8，不为它同步）、`PUBLISH_EXIT=0`。
  装置件逐件 sha16：`start-relay.ps1 4A65572783501F9E:13633` / `relay-lock.ps1 23E51FB2619230DC:6429` /
  `relay-ledger.ps1 6068012759F0D0A6:15672` / `relay-spawn.ps1 D267199D611CC109:6946` / `AGENT-RELAY.md 195EAB9E6AA15322:21489`。
- **闸门③ refresh-manifest**：`REFRESH_MANIFEST verdict=PASS`、`FILE_COUNT=85`（MANIFEST 自身除外）、
  `ENTRY_COUNT=85`、`INVARIANT_OK=True`、`BOM_FILES=0`、`PS1_NON_ASCII_FILES=0`、`MD_TXT_CR_TOTAL=0`、
  `MANIFEST_BYTES=5649`、`MANIFEST_NON_ASCII=0`、`CHANGE_COUNT=24`、`MANIFEST_EXIT=0`。
  逐项复核见本节末尾「清单复核」。

### ⑤ 本轮工具坑（新增）

1. **重写安装器时把机读字面量 `AGENTS_MARKERS` 变成了运行时拼接**（`$t.Label + '_MARKERS'`），
   case 13f 的「文档 ↔ 代码交叉字面量检查」判红：`code_missing=[AGENTS_MARKERS]`。
   修法：给规则目标加**显式** `Markers` 字段（`AGENTS_MARKERS` / `CLAUDE_MARKERS`），日志打 `$t.Markers`；
   同时把 `CLAUDE_MARKERS` 加进 selftest token 清单，让双写这条新不变式也被守住。
   **教训**：装置的机读字面量是 selftest 的**契约面**，重构时不能让字面量退化成拼接结果 ——
   拼出来运行时对、源码里查不到，检查照样红。第一次跑 `pass=134 fail=1`，**只有这一条红** ⇒ 重写没改变既有行为。
2. `tool\references\` 里的新文件**会进 publish 的 tracked 集合**（本轮 30 → 41）⇒
   **留证说明必须写在 publish 之前**，否则下一轮 verify 立刻报漂移。

### ⑥ 未验证 / 遗留（别当已解决）

- **三家 CLI 运行时的真起链一律未实测**：本机只装了 Claude Code（`%USERPROFILE%\.local\bin\claude.exe`），
  `codex` 与 `openclaw` **未安装**。case 16 只验证到「装配正确 + 命令构造正确 + 干跑不执行」。
- OpenClaw 的 `sessions_spawn` **参数形状随版本演进**，激活包里给的是参考形状 ⇒ 第一次跑前先在交互会话里打一次看本机真实参数名。
- **LICENSE 未决**：用户未授权选许可证 ⇒ 本轮**不擅自新增**；README 与本节保留「保留所有权利」并列为开放项。
- `via=probe-multi` 多命中择优、`profile_probe_disabled` 降级路径仍未实测（沿用）。
- case 15 在 CI（`windows-latest` 无已装 skill ⇒ 走 `loud_fail` 分支）的线上稳定性未验证。
- 套件仍不调 `session_create`：真实起链一跳属人工。
- 换运行时的**行为等价性**只在 `mcode` 上实测过（默认路径逐字等价）；`claude-code` 下的**真链**未跑。

### ⑦ 清单复核（闸门③ 回读，2026-11-25）

`pwsh -NoProfile -ExecutionPolicy Bypass -File scripts\refresh-manifest.ps1` 的实测输出：

| 指标 | 值 | 含义 |
|---|---|---|
| `REFRESH_MANIFEST verdict` | `PASS` | 清单整体通过 |
| `FILE_COUNT` | `85`（MANIFEST 自身除外） | 仓库纳管文件数（上批 73 → 本批 85，净增 12） |
| `ENTRY_COUNT` | `85` | 清单条目数与文件数一致 |
| `INVARIANT_OK` | `True` | 装置件硬不变式（`device\` ↔ `tool\templates\`）成立 |
| `BOM_FILES` | `0` | 无 BOM 文件 |
| `PS1_NON_ASCII_FILES` | `0` | 全部 `.ps1` 纯 ASCII（家规 4） |
| `MD_TXT_CR_TOTAL` | `0` | 仓库 `.md` 与 `tool\references\*.txt` 全 LF（家规 4） |
| `MANIFEST_BYTES` | `5649` | 清单本体字节数 |
| `MANIFEST_NON_ASCII` | `0` | 清单纯 ASCII |
| `CHANGE_COUNT` | `1` | 相对上一次清单只有 `HANDOFF.md` 变更（即本节回填本身）；**提交后再跑一次为 `0`** |
| `MANIFEST_EXIT` | `0` | 脚本退出码 |

**口径提醒**：`MANIFEST.txt` 首行带 `generated: <时间戳>` ⇒ **每跑一次清单它就变一次**，与内容无关。
所以正确收尾顺序是：**改 `HANDOFF.md` → 跑一次清单 → 把 `HANDOFF.md` + `MANIFEST.txt` 一起提交 → 不要再跑清单**（或跑完用 `git checkout -- MANIFEST.txt` 回退）。
本轮入库清单与盘上文件做了**内容级核对**（逐行比 sha16 + 字节数，而不是信清单自报）：
`ROWS=85 MISMATCH=0` ⇒ 入库清单的 85 行全部与盘上真实文件一致。
清单统计 `.md` 与 `.txt` 一起 ⇒ 改 `HANDOFF.md` 必须重新跑清单，否则入库清单的 `HANDOFF.md` 行哈希会与盘上不符。

### ⑧ 提交与推送（2026-11-25）

- 分支 `main`，远端 `origin = https://github.com/kizemo/agentask-relay.git`（push 已获用户授权）。
- 本批入库：新增 9 件 + 修改 14 件，提交 `1f966c3`（`B9: runtime adaptation layer (Claude Code / Codex CLI / OpenClaw)`），
  随后 `git push origin main` ⇒ `HEAD` 与 `origin/main` 同为 `1f966c342fd49c449aecec860d7aabfb4c84ca15`，工作树干净。
- 此前两个未推送的历史提交 `473474a`（B7+B8 证据）与 `42ef625`（F4 skill-root 自发现 + 交接记录）也在本次 push 中一并上库。
- 推送后 `origin/main` 与本地 `main` 一致 ⇒ 下一轮新会话 clone 即得运行时适配层 + 新文档。
- 复核（只读）：`publish-relay.ps1 -Direction verify` ⇒ `STATUS=OK fail=0 warn=2`（两条 `SNAPSHOT_DRIFT` 属 `examples\` 历史快照，家规 8 不为它同步）、`tracked_files=41`。
- **坑（新增）**：`git commit -F -` 在 PowerShell 里配 here-string 会把消息当 **pathspec**（报 `did not match any file(s) known to git`）⇒
  改用 `-m` 或先写消息文件再 `-F <file>`；`git push` 仍会照常推走**之前**的提交（本次就是），所以 commit 失败后要回读 `git log` 确认到底提交上没有。
- **坑（新增）**：`refresh-manifest.ps1` 每次运行都会刷新 `MANIFEST.txt` 首行的 `generated:` 时间戳 ⇒
  **清单跑在提交之前**（最后一次跑完立刻提交），跑在提交之后就会留下一条与内容无关的永久脏 diff（本轮 `git checkout -- MANIFEST.txt` 回退解决）。
  判据不看 `git status` 脏不脏，看**入库清单逐行与盘上文件的 sha16+字节数是否一致**。

---

## 批次 B10 实录（2026-11-25 22:0x → 23:0x）—— Claude Code 真链权限层：旧结论被证伪 + 命令行形状铁律

### 背景与目标
B9 交付运行时适配层后，`claude-code` 真链仍跑不动：子环起来后写文件 / 跑命令被拒，`--output-format json` 拿不到结构、`session_id` 丢失。
旧文档（`tool\references\claude-code-permissions-2026-11-25.md` 初版）把原因归给「路径斜杠写法 / `--allowedTools` 不生效 / prompt 没送达」。
本轮用实验矩阵逐条证伪并重建配方。**不含新功能**，只修「怎么把 claude CLI 正确地喊起来」。

### 旧结论逐条证伪（已在参考文档开头做成更正表）
| 旧结论 | 实测 |
| --- | --- |
| 只有 `--settings` 生效，其它旗标一律被忽略 | 伪：`--permission-mode`、`--allowedTools`、`--dangerously-skip-permissions` 单独也生效 |
| `--permission-mode` 被忽略 | 伪（同上） |
| `--allowedTools` 被忽略 | 伪（同上） |
| 路径斜杠（`/` 与 `\`）是分水岭 | 伪：不是变量 |
| prompt 未送达 | 伪：prompt 一直送达，问题在旗标位置 |

### 铁律（本轮唯一真因）
`claude` 的**所有旗标必须写在 prompt 之前**，prompt 放最后。
- 错：`claude -p "<prompt>" --output-format json --session-id … --permission-mode …` ⇒ 旗标被整体丢弃：`json=False`、回读不到 `session_id`、模式回落 `default`。
- 对：`claude --output-format json --session-id … --add-dir … --permission-mode … --allowedTools … --settings <file> --max-budget-usd 1.5 -p "<prompt>"` ⇒ `json=True`、`session_id` 命中、权限层生效。
判据不是「命令有没有报错」，而是**输出是不是 JSON** 且 **`session_id` 与传入一致**。

### 生效配方（settings 用嵌套键位）
```json
{"autoQuestion":{"enabled":false},"defaultMode":"bypassPermissions","permissions":{"defaultMode":"bypassPermissions","allow":["Bash","Bash(pwsh:*)","Bash(powershell:*)","Read","Write","Edit","Glob","Grep"]}}
```
本机 `C:\Users\Duanyi\.claude\settings.json` 的**顶层** `defaultMode` 是「读而不施」的，必须写进 `permissions.defaultMode` 才算数。
等效旗标（单独可用，仍须放在 prompt 之前）：`--permission-mode bypassPermissions`；`--dangerously-skip-permissions --allow-dangerously-skip-permissions`。

### 落点
- 只改 CLI 专用 `tool\templates\relay-spawn.ps1` 与安装器渲染；**MCode 路径的 prompt 生成块一字未动**（`start-relay.ps1` 保持原样，用户要求 prompt 逐字不变）。
- 镜像一致（2026-11-25 盘上回读）：`relay-spawn.ps1` 双份 `438D5C375C7D92F4`（16484 B）、`start-relay.ps1` 双份 `D795D14DDAE16FCC`。

### 验证到哪一步 / 没到哪一步
- 已验证：命令行形状（`scripts\selftest.ps1` case 17d，3 条断言：`json=True`、`session_id` 命中、默认模式不再回落）；权限配方（实验矩阵 V1 / V3 / V4 三个会话）。
- **未验证**：整链端到端 —— 干净真链仓里跑通「第 1 环 → 写产物 → 台账 `stage_done` → 推进 4 token → 自举第 2 环」。现有证据只到「单次 CLI 调用被正确喊起来」。
- `codex` / `openclaw` 未安装 ⇒ 两条真链不可实测，只有静态审计。

### 本轮工具坑
1. 子环内用原生 PowerShell 工具跑命令恒报 malformed syntax ⇒ 必须用 Bash 工具。
2. `--settings` 只吃文件路径，传内联 JSON 报 `Settings file not found`。
3. `Start-Process -ArgumentList` 传含空格元素会拆散 argv（`too many arguments`）⇒ 用 `ProcessStartInfo.ArgumentList` 逐个 Add。
4. `--model claude-haiku-4-5` 报 `API Error: 400 "Model not exist."` ⇒ 不指定 model；`--bare` 不可用。
5. 实验调用要显式设 `WorkingDirectory`，且不要重定向 stdin。

### 证据路径
- `tool\references\claude-code-permissions-2026-11-25.md`（已重写：更正表 + 铁律 + 等效旗标 + 「已试过并确认无效」清单）
- `tool\references\live-chain-b10.md`、`live-chain-b10-stdout.txt`、`live-chain-b10-stdout-2.txt`、`live-chain-b10-transcript-1.txt`
- `scripts\selftest.ps1` case 17d

---

## 批次 B11 实录（2026-11-25 23:1x → 23:4x）—— 首次运行即发问：写集 / 门禁 / 模型三项裁决自动化

### 用户指令（原文）
> 当前工具要求，装完必做两件事
> 补全 docs\RELAY-ADAPTATION.md 的 TODO —— 写集（哪些目录可改、哪些禁止碰）、验收门禁命令与判绿口径、模型策略。
> 优化为：在一个项目中首次运行这个工具，要自动发起提问，来确定这些问题。

### 设计结论（为什么是两段式）
安装器**不能自己交互提问**：它跑在无 TTY 的子进程里，`Read-Host` 会挂死。
所以拆两段：① 首跑 —— 探测默认值 → 渲染 `docs\RELAY-ADAPTATION.md`（§3/§4/§5 标 `source: defaults`）→ 落盘问题包 → stdout 输出 `ADAPTATION_STATUS=pending`；② 托管 agent 按问题包发问 → 写答案 JSON → 带 `-AnswersFile` 重跑 → 定点回填 §3/§4/§5，`ADAPTATION_STATUS=confirmed`。

### 五条硬约束（全部来自实测撞墙）
1. **退出码不可变**：待答**不**用非零退出码表达（会撞 `install_exit_zero` 与 `INSTALL_VERDICT=PASS` 断言），改用 `ADAPTATION_STATUS=` 行 + 问题包 + `tool\SKILL.md` 硬性要求。
2. **Warn 不进 `$verdict`**：新增 `adaptation_defaults_unconfirmed` 只报警、不改判。
3. **中文文案一律外置**：`.ps1` 必须纯 ASCII ⇒ 8 问文案全部放 `tool\templates\ADAPTATION-QUESTIONS.json`。
4. **§3/§4/§5 永不残留 `TODO`**：要么填答案，要么填探测真值并标 `source=defaults`；写后自检 `placeholders=0`。
5. **定点更新而非整篇覆盖**：只替换 §3/§4/§5，保护用户手改；无 `-AnswersFile` 且文档已存在 ⇒ `SKIP kept`；`-Force` 才整篇覆盖。

### 改动清单（2026-11-25 盘上回读）
| 文件 | 字节 | 行 | sha16（前 16） | 说明 |
| --- | --- | --- | --- | --- |
| `tool\scripts\install-relay.ps1` | 41486 | 891 | `B2920A534305EBCC` | 新增 `-AnswersFile` + 探测 + 问题包 + 定点回填；`PARSE_ERRORS=0`、`BOM=False`、`NONASCII=0`、`CR=0` |
| `tool\templates\ADAPTATION-QUESTIONS.json` | 7233 | 125 | `7481AF514BB556FA` | schema `relay-port/adaptation-questions@1`；3 组 / 8 问 |
| `tool\templates\RELAY-ADAPTATION.md` | 5124 | 93 | `744A787517E7367C` | `TODO=0`、`source` 槽位 3 处 |
| `scripts\selftest.ps1` | 69701 | 859 | `F6DF8D7591200C63` | 新增 case 18（29 条断言） |

问题包的 8 个 `answer_key`（顺序即 JSON 内顺序，实测回读全等）：
`write_set_allow`、`write_set_deny`、`concurrency_check`、`gate_command`、`gate_verdict_field`、`model_primary`、`model_fallback_day`、`model_fallback_night`。

### 实测（scratch 仓 `C:\Users\Duanyi\AppData\Local\Temp\relay-adapt-t1`）
- 首跑：`INSTALL_VERDICT=PASS`、`ADAPTATION_STATUS=pending`、`ADAPT_CHECK doc=docs\RELAY-ADAPTATION.md placeholders=0 source=defaults`、问题包 8 问、1 条 WARN（`adaptation_defaults_unconfirmed`）。渲染出的文档 5834 B。
- 二跑（`-AnswersFile docs\relay\adaptation-answers.json`）：`ADAPT answers=… applied=5/8`、`PATCH RELAY-ADAPTATION.md sections=3,4,5`、`ADAPTATION_STATUS=confirmed`、`WARN_COUNT=0`；文档断言 `has_src=True has_gatecmd=True has_verdict=True sec6_kept=True source_answers=True`。
- 失败码：`-AnswersFile` 指向不存在 ⇒ `reason=answers_file_missing`、`EXIT=2`。

### selftest case 18（29 条断言）
覆盖五组：首跑 7 条 + 文档 3 条（无 `TODO`、无 `{{…}}` 残留、`source: defaults` 恰好 3 处）+ 问题包 6 条（含 8 个 `answer_key` 全等）+ 答案回填 9 条（含 §6、§9 未被顶掉）+ 失败码 1 条。
套件：`SUITE_END pass=215 fail=0`、`EXIT=0`。证据 `tool\references\selftest-2026-11-25r.txt`（`18990 B / 219 行 / cr=0 / sha16=B2BD694CD9A51441`）。
基线口径：`25p` 是上一个绿证据（182 条）；`25q` 是红证据且无法清除，**引证据只用 25p / 25r**，靠新后缀区隔。

### 三道闸门（本轮收尾回读）
- ① selftest：`pass=215 fail=0`、`EXIT=0`。
- ② publish：`DIRECTION=publish STATUS=OK fail=0 warn=2`、`tracked_files=56`（两条 WARN 是 `examples\practilog` 的 `SNAPSHOT_DRIFT`，家规 8 不同步、不参与判定）。
- ③ refresh-manifest：`verdict=PASS`、`FILE_COUNT=100`、`MD_TXT_CR_TOTAL=0`、`BOM_FILES=0`、`PS1_NON_ASCII_FILES=0`。

### 本轮工具坑（新增）
1. **CLI stdout 重定向留证默认带 CRLF**：`live-chain-b10-stdout.txt`（22 个 CR）+ `live-chain-b10-stdout-2.txt`（9 个）= 31 ⇒ 直接把闸门③的 `MD_TXT_CR_TOTAL` 顶成 31（当时 `verdict=PASS`，但违反家规「必须为 0」）。转 LF 后归零。**新留证 `.txt` 写完即转 LF，再跑清单**。
2. **hook 残留会污染清单**：仓库根被 stop hook 写过 `handoff-2026-11-25.md`，清单把它计进 `FILE_COUNT`（101 而不是 100）⇒ 提交前必须清掉，否则入库清单里会有一条永不存在的文件。清除只能走家规允许的单条顶层删除式调用。
3. `edit` 用 `old_string` 做替换时容易顺带顶掉相邻列表条目 ⇒ 改列表条目时新内容要自带旧条目原文（本轮 `tool\SKILL.md`「幂等」条目被顶掉后已补回）。

### 未做 / 遗留
- B10 的整链端到端复验仍未做（见 B10「验证到哪一步」）。
- `codex` / `openclaw` 真链不可实测。
- ~~本批默认仅本地提交，未 push~~ → **已于 2026-11-26 08:34 后推送**：`2acc0a7` → `origin/main`（推送过程与根因见「批次 B12 实录」）。

## 批次 B12 实录（2026-11-26 08:34 → 09:5x）—— 推送 GitHub：git 的 openssl TLS 后端被本机代理掐断

### 用户指令（原文）
- 「推到 origin/main」
- 「设为全局 schannel」

### 现象
`git push origin main` 直接失败（EXIT=128）：
```
fatal: unable to access 'https://github.com/kizemo/agentask-relay.git/':
TLS connect error: error:0A000126:SSL routines::unexpected eof while reading
```

### 排除法（四个候选逐个实测）
1. **代理是否挂** ⇒ 否。本机 git 配 `http://127.0.0.1:7897`，端口在监听；用 `curl -x http://127.0.0.1:7897` 访问 `api.github.com` / `github.com` / `www.google.com` **全部 200**。
2. **直连是否通** ⇒ TCP 层通（`Test-NetConnection github.com:443` = True），但 git 直连报 `Failed to connect to github.com port 443 after 21064 ms` ⇒ 端口被中间设备重置，不是本机防火墙。
3. **HTTP 版本** ⇒ 无效（`-c http.version=HTTP/1.1` 同错；全局本已是 HTTP/1.1）。
4. **SSH 通道** ⇒ 不可用（`ssh -p 443 -T git@ssh.github.com` → `Permission denied (publickey)`，本机没有 GitHub SSH 私钥）。

### 真因与解法
git 默认 TLS 后端是 **openssl**（`git config --global --get http.sslBackend` = `openssl`），在这条代理链路上握手被提前关闭 ⇒ 报 `unexpected eof while reading`。换 Windows 自带的 **schannel** 后端即通：
```
git -c http.sslBackend=schannel push origin main
→ cdd3c33..2acc0a7  main -> main   (EXIT=0)
```

### 已落地（用户明确批准后）
- 本仓库 `.git\config`：`http.sslBackend=schannel`。
- 全局 `C:\Users\Duanyi\.gitconfig`：`http.sslBackend=schannel`（用户 2026-11-26 批准）。
- 验证走的是**没有仓库级配置**的探测目录，证明走的是全局值：`git -C $TEMP\git-schannel-probe ls-remote https://github.com/kizemo/agentask-relay.git HEAD` → EXIT=0，返回 `2acc0a754e1cc92cb64527f6146e12658a3de58d  HEAD`。
- 本仓库再验：`git fetch origin` EXIT=0；`LOCAL = REMOTE_REF = 2acc0a754e1cc92cb64527f6146e12658a3de58d`；`rev-list --left-right --count HEAD...origin/main` = `0  0`；工作树干净。

### 未验证 / 遗留
- 全局改 schannel 只在「无仓库级覆盖」的场景验过。**仓库级 `.git\config` 优先级更高**：若别的仓库自己写了 `http.sslBackend=openssl`，它仍会复现同一个 TLS 错，届时改该仓库的 `.git\config` 即可。
- 本批**没有改 `tool\` / `device\`** ⇒ 按家规无需重跑 selftest / publish；但 `HANDOFF.md` 属清单管辖文件 ⇒ 已重跑 refresh-manifest 并做内容级复核后再提交。

### 本轮工具坑（新增）
1. `git config --get` 读的是**合并后**的值（仓库级 > 全局）。要确认「全局到底是什么」必须显式 `git config --global --get`。
2. **curl 通 ≠ git 能推**：curl 走同一代理返回 200 不构成 git 可用的证据，必须用 `git -c http.sslBackend=schannel` 实测才算数。
3. `Test-NetConnection` 只证 TCP 可达，证不了 TLS 握手 ⇒ 代理类故障要看 TLS 层报错文本，别只看端口通不通。
4. `git push` 失败后 `origin/main` 仍是旧 ref；判断到底推没推上去要看 `git fetch` 之后的 `git rev-parse origin/main` 与 `rev-list --left-right --count HEAD...origin/main`，不要凭 push 的提示行。



---

## 批次 B13 实录（2026-11-26 15:20 → 15:55）—— 整链端到端复验：真链两环跑通 + 修真链新暴露的两个缺陷

### 背景与目标
B10 把「怎么把 claude CLI 正确喊起来」坐实了，但**明确没验证整链**（当时留白：干净真链仓里跑通「第 1 环 → 写产物 → 台账 `stage_done` → 推进 → 自举第 2 环」）。
本轮补这段留白，并按家规把结论回填进本仓库，收尾顺序 `selftest → publish → refresh-manifest`。

### 第一轮真链（修复前）暴露的两个真实缺陷
干净夹具仓 `…\relay-b13-e2e-20261126-152056\repo`（claude-code 运行时）跑两环：
| 缺陷 | 现象 | 根因 |
| --- | --- | --- |
| D1 | 子环里两条命令 `exit 64` | Claude Code 的 Bash 工具是**真 bash**，prompt 里的 Windows 反斜杠路径被吃掉（`docs\relay\relay-ledger.ps1` → `docsrelayrelay-ledger.ps1`） |
| D2 | 阶段名退回默认，第 1 环产物名不对 | 安装器把 `-StageTitles` 写进了描述符，但启动器**没读**描述符里的阶段清单 |

### 修复（本轮改动 4 个文件，未 commit）
| 文件 | 改了什么 | sha16 |
| --- | --- | --- |
| `tool\scripts\install-relay.ps1` | 描述符新增 `stage_titles` 字段，**仅当用户显式传 `-StageTitles` 时才带** | `A7D9F76B59F86B3E` |
| `tool\templates\start-relay.ps1` | ① 阶段清单解析：参数 > 台账 > 描述符 > 默认，并打印 `OK stage_titles source=…`；② 台账 bootstrap 写 `stage_titles`；③ prompt 的 `STAGE PLAN` 用真清单；④ **CLI 分支 prompt 内所有路径统一正斜杠**（新增 `$pathSep`/`$promptRepoRoot`/`$workspaceNote`，覆盖 WORKSPACE 行、必读清单 8 条、RULES 三处、台账配方、交接规则、spawn 命令共 19 处）；⑤ 命令风格规则改为「Bash 用正斜杠、原生 PowerShell 可用反斜杠」 | `BD04C11F9E432581` |
| `device\start-relay.ps1` | 与模板**逐字一致**（硬不变式） | `BD04C11F9E432581` |
| `scripts\selftest.ps1` | 新增 case 19（18 条断言），断言改在 `DRYRUN prompt_preview_begin/end` 之间的 prompt 块上做 | `8CF635C5606D2386` |

**关键设计取舍**：阶段清单只传显式值 ⇒ 未配置阶段的既有安装，**mcode prompt 逐字不变**（B10 硬要求）。用片段化实现（`$pathSep` 抽象）让 CLI 分支全走正斜杠，mcode 分支保留 Windows 路径，人看的激活包仍保留 Windows 路径。

### 硬不变式证明（不能靠肉眼）
同一夹具下用 `git show HEAD:tool/templates/start-relay.ps1`（旧版）与工作区新版 launcher 分别渲染：
- `MCODE_PROMPT_BYTE_IDENTICAL=True`（**逐字节相同**）
- CLI prompt 反斜杠计数 = **0**；正斜杠 relay 引用 19 处

### 修复后整链（决定性证据）
新干净夹具 `…\relay-b13-e2e2-20261126-153941\repo`（克隆自旧夹具、清空 `docs\relay\`/`docs\relay.json`/锁文件，git HEAD 仍 `08e6009`）：

| 步骤 | 结果 |
| --- | --- |
| 安装首跑 | `INSTALL_VERDICT=PASS` / `ADAPTATION_STATUS=pending` / `WARN_COUNT=1` |
| 安装二跑（带 `-AnswersFile`） | `confirmed` / `source=answers` / `applied=8/8` / `WARN_COUNT=0`，描述符带真阶段清单 |
| 起链 | `OK runtime=claude-code source=descriptor`、`OK stage_titles source=descriptor`、`chain_session_id=b47a9c35-c96a-4b13-b501-27b7463c431f`、台账 2086 B、prompt 5989 B、`DONE exit=0` |
| spawn | `SPAWN_EXIT=0`、`RELAY_SPAWN_OK`、`LOCK_ADOPTED holder=b47a9c35-… prev_holder=start-relay:296240`、`SPAWN_LOCK_PRE_ADOPTED`、输出文件 2497 B |
| 第 1 环 | 产物 `docs\relay\stage-1-inventory.md` 745 B；台账 `stage_done` + `bump_current_stage` + `next_session_id=4dcfed63-ffb5-41d4-a2fe-d560129ae073`；`tool_calls=23`；finished 15:43:42 |
| 第 2 环（自举） | 产物 `docs\relay\stage-2-inventory.md` 608 B；`tool_calls=12`；finished 15:47:21；锁终态 `LOCK_ABSENT` |
| 终态台账 | `status=blocked` / `current_stage=3` / `max_stages=2` / 两 stage 均 `done` / `notes=1` / `blocked_on=1` / `sessions=[]` |

**零报错硬判据**：transcript（`%USERPROFILE%\.claude\projects\…-relay-b13-e2e2-…-repo\`）里 **`is_error=true` 计数 = 0**（修复前有 2 条 exit 64）。工具计数 PowerShell=16 / Read=16 / Write=5 / Bash=1 / Edit=1 / Glob=1。transcript 文件名即链 session id ⇒ `--session-id` 被遵守。

### 门禁
`pwsh -NoProfile -File scripts\selftest.ps1 -EvidencePath <log>` ⇒ `SUITE_END pass=233 fail=0`，进程 `EXIT=0`。
基线 `selftest-2026-11-25r` = 215 条 ⇒ **净增 18 条**（case 19）。raw 日志已收成 `tool\references\selftest-2026-11-26.txt`（20213 B / cr=0 / 238 行）。

### 已验证 / 推断 / 未验证
- **已验证**：整链两环（产物 → 台账 `stage_done` → 自举第 2 环 → 锁正确释放）、mcode prompt 逐字不变、CLI prompt 路径全部正斜杠、安装器两段式问答、case 19 断言、selftest 233/0。
- **推断（未在本轮证伪）**：CLI 分支的正斜杠改造对 `codex` / `openclaw` 运行时同样成立（这两个运行时本机没装，只有静态审计）。
- **未验证 / 已知遗留（本轮有意不改）**：
  - **F5**：链跑完终态落 `status=blocked` 而非 `done`。notes 原文：`current_stage 3 > max_stages 2 -> status=blocked, no next link spawned`。改它要么动 mcode prompt（违反 B10 约束），要么让 mcode/CLI 语义分叉 ⇒ 留作下一批候选。
  - **F6**：终态台账 `sessions=[]` 为空，session 信息只在 `stages[].session_id` 里。影响「按会话查历史」这类查询。

### 证据路径（本轮新增 10 个文件，全 LF / cr=0）
- `tool\references\live-chain-b13.md`（真链实录）
- `tool\references\live-chain-b13-stdout.txt` / `-ledger-final.txt` / `-artifacts.txt` / `-prompts.txt` / `-prompt-stage1.txt` / `-transcript-1.txt` / `-transcript-2.txt`
- `tool\references\selftest-2026-11-26.txt`（raw 日志）/ `selftest-2026-11-26.md`（本轮小结）
- 既有：`tool\references\live-chain-b10.md`（§5 已回填本轮结果）、`tool\references\claude-code-permissions-2026-11-25.md`

### 本轮工具坑（新增）
1. **Claude Code 的 Bash 工具是真 bash**，Windows 反斜杠路径会被吃掉（`docs\relay\x.ps1` → `docsrelayx.ps1`，`exit 64`）。CLI 分支 prompt 里凡是要交给 Bash 的路径一律正斜杠。
2. **「逐字不变」不能靠肉眼**：`git show HEAD:tool/templates/start-relay.ps1` 渲染同一夹具再逐字节比，才是硬证明（B13 用的就是这个）。
3. **改 `scripts\selftest.ps1` 先确认能解析**：括号不配对会变成整个门禁 ParserError（不是断言失败），看起来像「全挂」。
4. **断言 Windows 路径的正则**：反斜杠写两个、点写一个；优先用 `[regex]::Escape()`。
5. **安装器对非 git 目录 exit 2**：夹具必须先 `git init` + commit。
6. **`--session-id` 被遵守的判据是 transcript 文件名**：文件名前缀就是 session id，比翻 JSONL 内容快。
7. **断言要打在 `DRYRUN prompt_preview_begin/end` 之间的 prompt 块上**：断言整个 stdout 会被安装器自身的日志干扰。

---

## 批次 B13 收尾复跑（2026-11-26 16:10 → 16:15）—— 门禁重跑 + 全局同步 + 清单刷新

### 背景与目标
上一会话把 B13 的装置改动（4 个文件）与 10 份真链留证写进工作树但**未 commit**，
门禁当时报 233/0，但**发布（同步回全局 skill）与清单刷新是否真的落到位没有留证**。
本轮按家规顺序 `selftest → publish → refresh-manifest` 重跑一遍，
每一步的数字都从盘上回读，不抄摘要。

### 三步硬判据（全部实测）

| 步 | 判据 | 实测结果 |
| --- | --- | --- |
| 1. selftest（16:10 首跑） | `SUITE_END pass=233 fail=0` **且**进程 `EXIT=0` | **pass=233 / fail=0 / EXIT=0**（跑窗 16:10:56 → 16:13:09） |
| 1'. selftest（16:15 最终树复跑） | 同上，且跑在**含两份留证文档的最终树**上 | **pass=233 / fail=0 / EXIT=0**（`SUITE_END 16:17:06`，`CASE_FAIL` 行数 = 0） |
| 2. publish | `STATUS=OK fail=0`；硬不变式逐件复核 | `STATUS=OK fail=0 warn=2`；`skill_root=E:\Users\Duanyi\.minimax\.minimax\skills\relay-port via=probe`；`tracked_files=66`、SYNC 明细 65 条、**无 FAIL / 无 SYNC_FAIL**；硬不变式 `templates_vs_copies` 5 件全 `copy_matches_template`（`start-relay.ps1 BD04C11F9E432581:26942` / `relay-lock.ps1 23E51FB2619230DC:6429` / `relay-ledger.ps1 6068012759F0D0A6:15672` / `relay-spawn.ps1 438D5C375C7D92F4:16484` / `AGENT-RELAY.md 195EAB9E6AA15322:21489`） |
| 3. verify | 退出码 0（7 = 有漂移） | `STATUS=OK fail=0 warn=2` ⇒ **全局 skill 与仓库零漂移** |
| 4. refresh-manifest | `verdict=PASS` 且 `MD_TXT_CR_TOTAL=0` | `FILE_COUNT=110` / `ENTRY_COUNT=110` / `INVARIANT_OK=True` / `BOM_FILES=0` / `PS1_NON_ASCII_FILES=0` / **`MD_TXT_CR_TOTAL=0`** / `MANIFEST_BYTES=7375` / `CHANGE_COUNT=2`（16:15 那次改了 2 份留证文档：本文件 + 留证 `.md`；**最终一次为 1**：仅本文件） |

**两条 WARN 是 `SNAPSHOT_DRIFT`**：`examples\practilog\docs\relay\` 里 `start-relay.ps1` /
`relay-lock.ps1` 两份历史快照与模板不同。它们是**软不变式**（`kind=soft`），
按家规 8 **不为它们同步、不参与判定**，只报不断言。

**raw 日志已覆盖归档**：`tool\references\selftest-2026-11-26.txt`
（`len=20213 cr=0 sha16=1106C2E24E5898D4`，238 行）。旧 sha `36C8F2BCA7DE4A75` 作废
—— manifest 的 `CHANGE_COUNT` 里两条：raw 日志换 sha ＋ 本轮改的留证 `.md`。字节数与行数与上一跑完全一致，**只有 sha 变了**
（raw 日志含时间戳与临时路径）。

### 门禁跑在什么树上（不留推理空档）
- **两次门禁跑**：16:10:56 → 16:13:09（首跑）与 16:15:57 → 16:17:06（**最终树复跑**）。
- 复跑发生在两份留证文档（`tool\references\selftest-2026-11-26.md` 与本文件）都改完之后，
  仍 **pass=233 / fail=0 / EXIT=0** ⇒ 「233/0」对最终树成立，不是推断。
- 复跑之后本节又改了一次：**只动根目录 `HANDOFF.md`**（不在门禁扫描范围、不随 skill 发布）
  ⇒ 按家规只刷 `MANIFEST.txt`，不重跑门禁。
- 门禁的 kit 扫描显式排除 `tool\references\`（`scripts\selftest.ps1:190`）⇒ 留证 `.md` 本身不参与断言。

### 已验证 / 推断 / 未验证
- **已验证**：233/0 门禁绿（两跑：16:13 首跑 + 16:17 最终树复跑）；65 件 SYNC 进全局 skill（`tracked_files=66`，无 FAIL，verify 零漂移）；manifest 110 条与在盘文件一一对应；
  编码不变式（BOM=0、`.ps1` 非 ASCII=0、`.md`/`.txt` CR=0）；`device\`↔`tool\templates\` 硬不变式 5/5 一致。
- **推断**：B13 的 D1/D2 修复对 codex / openclaw 运行时同样成立（静态审计，本机无这两个 CLI）。
- **未验证**：codex / openclaw 真链；git 写操作（产物与台账留证留在工作树，等人 commit）。

### 遗留与下一批计划（沿用 B13 结论，本轮有意不改）
1. **F5 终态语义**：链跑完却落 `status=blocked`（不是 `done`），notes 原文
   `current_stage 3 > max_stages 2 -> status=blocked`。改它要么动 mcode prompt（破 B10 的
   「mcode prompt 逐字不变」硬约束），要么让 mcode / CLI 语义分叉 ⇒ **需要人拍板**。
2. **F6 台账会话流水**：终态 `sessions=[]`，会话信息只在 `stages[].session_id`。
   候选改法：让 `stage_done` 顺带登记会话（只动台账闸门，不动 prompt ⇒ 不破 B10 约束）。
3. **codex / openclaw 真链**仍未实测（本机未装 codex，openclaw 无对应 CLI）。
4. **git 写操作**仍是人工验收点：本轮两环产物与台账回写留在工作树，子环按家规停链等人 commit。

### 本轮工具坑（新增）
8. **收尾管道必须带闸门**：脚本先等 raw 日志出现 `SUITE_END`，解析到 `fail=0` 才允许往下走
   publish → verify → manifest。理由：门禁红着还发布，等于把坏工具同步进全局 skill，比不发布更糟。
9. **raw 日志复跑必换 sha**：日志里有时间戳与临时路径 ⇒ 任何引用 raw 日志 sha16 的小结文档
   都要跟着刷新，否则留证自相矛盾（本轮旧 sha `36C8F2BC…` → 新 `1106C2E2…`）。
10. **发布的 skill 根不在 `%USERPROFILE%` 那块盘**：本机 `%USERPROFILE%` 在 C:，
    活动 profile 在 E: ⇒ 发布目标由探针定位（`via=probe`）而不是猜路径。
11. **PowerShell 数组字面量里跨行拼字符串会丢片段**：`@('a','b' + LF + 'c')` 的第三段可能被解析成
    独立元素而被忽略 ⇒ 脚本照样打印 `REPLACED hits=1`，**台账表格却少了一行**。
    教训：**替换后必须回读比对实际行**，不能只看「替换成功」的断言；跨行字符串先用变量显式拼好再传入。

---

## 批次 B14 实录（2026-11-26 16:23 → 16:5x）—— F6 台账会话流水兜底

### 用户指令（原文）

> 读 `HANDOFF.md` 的「批次 B13 收尾复跑」与「批次 B13 实录」两节，以及 `tool\SKILL.md` 和
> `tool\references\live-chain-b13.md`，自行掌握背景、进度与下一步计划，按家规收尾顺序
> `selftest → publish → refresh-manifest` 推进；F5 终态口径按台账「遗留与下一批计划」处理，F6 可直接修。

### 背景与目标

B13 跑通了整条真链（两环、产物、台账 `stage_done`、自举下一环、锁正常释放），留下两个缺陷：

- **F5**：链跑完了却落 `status=blocked`（不是 `done`），因装置的 `stop_conditions` 写着
  「`current_stage >= max_stages -> status=blocked`」；
- **F6**：终态台账 `sessions=[]`，会话信息只在 `stages[].session_id` 里。

本轮按指令：**F6 直接修**（且只许在**不动 prompt** 的前提下修，见下），**F5 按台账口径处理**
（台账「遗留与下一批计划」写的是「需要人拍板」⇒ 本轮**有意不改**，只把口径与候选查清楚写进台账）。

### F6 根因（散文要求 ≠ 机制）

协议 `AGENT-RELAY.md` §3.2 要求 patch 带 `sessions_append`（4 个意图）；但启动器生成的 prompt 的收尾规则
只要求 **3 个意图**（`stage_done` / `bump_current_stage` / `next_session_id`）⇒ 子环照 prompt 办事，
台账里就没有独立会话流水。**光在 prompt 里加一句要求不行**：改了 prompt 就破 B10 的「mcode prompt 逐字不变」
硬约束，且别的运行时的子环照样可能忘。正解是让**闸门自己登记**。

### 本轮改动（5 个文件；prompt 一行没动）

| 文件 | 改了什么 | sha16 / 字节 |
| --- | --- | --- |
| `tool\templates\relay-ledger.ps1` | 新增第 5 条机制「会话流水兜底」：`stage_done` 提交时自动登记会话 ID | `7E9601DE9A1CBFF3` / 17,904 |
| `device\relay-ledger.ps1` | 与模板**逐字一致**（硬不变式） | `7E9601DE9A1CBFF3` / 17,904 |
| `tool\templates\AGENT-RELAY.md` | §3.2 补「会话流水由闸门兜底」，闸门保证由四件变五件 | `8DE6F09EF275008E` / 22,149 |
| `protocol\AGENT-RELAY.md` | 同上（两份内容一致） | `8DE6F09EF275008E` / 22,149 |
| `tool\SKILL.md` | 「台账写闸门」一节补 F6 条目 | `59708B7C5F8445ED` / 18,929 |
| `scripts\selftest.ps1` | 新增 case 20（9 条断言） | `9EAA19C3C39D4DF5` / 80,249 |

**登记规则**（只追加、不改写、不删除）：
① 会话 ID 取值优先 `stages[N].session_id` → 台账 `next_session_id`（提交前的值 = 当前在跑的那一环）→ 都没有就**不登记**；
② 去重按「包含」判定（协议里同时发 `sessions_append`、同环重跑都不会重复）；
③ 回显 `LEDGER_SESSION_REGISTERED session=… stage=… source=…` / `LEDGER_SESSION_ALREADY_REGISTERED session=…` /
`LEDGER_SESSION_SKIPPED stage=… reason=no_session_id`（**没有来源就跳过，不编造 ID**）。

### 硬不变式证明（不靠肉眼）

- **`start-relay.ps1` 一个字节都没动**：`BD04C11F9E432581` / 26,942 —— 与 B13 收尾复跑记录的值逐字相同
  ⇒ prompt 渲染输入未变 ⇒ B10 的「mcode prompt 逐字不变」自动成立。
- `device\relay-ledger.ps1` ≡ `tool\templates\relay-ledger.ps1` ≡ 全局 skill `templates\relay-ledger.ps1`
  = `7E9601DE9A1CBFF3`（独立回读全局 skill 得到，非采信发布脚本自述）。
- `tool\SKILL.md` = 全局 skill `SKILL.md` = `59708B7C5F8445ED`；`AGENT-RELAY.md` 两份一致 = `8DE6F09EF275008E`。

### 门禁（case 20，9 条断言）

`pwsh -NoProfile -File scripts\selftest.ps1 -EvidencePath <log>` ⇒ **`SUITE_END pass=242 fail=0`，进程 `EXIT=0`**。
基线（B13 收尾复跑）233 条 ⇒ **净增 9 条**。断言数与运行次数无关（稳定值）；raw 日志含时间戳与临时路径 ⇒
**每次复跑 sha16 必变**（本批工具坑 9），它的 sha/字节数以 `MANIFEST.txt` 为准。

case 20 覆盖：登记成功 / 重提交不重复 / 协议同时发 `sessions_append` 不重复 / 流水只增长 /
`session_id` 缺失时回退 `next_session_id`（`source=ledger_next_session_id`）/ 两个来源都没有时跳过且**不编造**。
判据有鉴别力：旧闸门在前 4 条上必红。

### 收尾三步（数字从盘上回读）

| 步 | 判据 | 实测 |
| --- | --- | --- |
| 1. selftest | `pass=242 fail=0` 且 `EXIT=0` | **pass=242 / fail=0 / EXIT=0**（含本批留证文档的最终树复跑） |
| 2. publish | `STATUS=OK fail=0` + 硬不变式逐件复核 | **`STATUS=OK fail=0 warn=2`**；两条 WARN 是 `examples\practilog\docs\relay\` 的 `SNAPSHOT_DRIFT`（软不变式，家规 8 不为它们同步、不参与判定） |
| 3. verify | 退出码 0（7 = 有漂移） | **`STATUS=OK fail=0 warn=2` ⇒ 零漂移** |
| 4. refresh-manifest | `verdict=PASS` 且 `MD_TXT_CR_TOTAL=0` | **`verdict=PASS`** / `FILE_COUNT=112` / `ENTRY_COUNT=112` / `INVARIANT_OK=True` / `BOM_FILES=0` / `PS1_NON_ASCII_FILES=0` / **`MD_TXT_CR_TOTAL=0`** |

### F5 口径（本批有意不改，但查清了两件新事实）

台账「遗留与下一批计划」写的是「**需要人拍板**」⇒ 本轮不自行决定。查清的两件新事实（下批可直接用）：

1. **停链条文不在 prompt 里**，而在两处：
   - `tool\templates\AGENTS-RELAY-BLOCK.md:21`（装进目标项目 `AGENTS.md` / `CLAUDE.md` 的家规块第 11 条）：
     `` `current_stage > max_stages` ⇒ 写 `status="blocked"` 停链。不得自行加长 `max_stages`。 ``
   - `tool\templates\start-relay.ps1:292` 的**台账种子** `stop_conditions`：
     `'current_stage >= max_stages -> status=blocked'`（prompt 块从 `start-relay.ps1:417` 才开始，种子不在里面）。
2. ⇒ **改终态口径存在一条不动 prompt 的候选路径**（改家规块第 11 条 + 台账种子文案，子环照新文案置 `status=done`），
   B10 的「mcode prompt 逐字不变」**不必放弃**。代价：改的是新装项目的家规语义；**既有链的台账里仍是老文案**
   （种子只在 bootstrap 时写一次），且两处口径本身就不一致（`>` vs `>=`）⇒ 仍需人拍板，本批不实施。

### 已验证 / 推断 / 未验证

- **已验证**：F6 修复的登记 / 去重 / 回退 / 不编造四类行为（case 20 实测）；`start-relay.ps1` 零字节改动 ⇒
  prompt 未变；`device\`↔`tool\templates\`↔全局 skill 三方 `relay-ledger.ps1` 逐字一致（独立回读）；
  242/0 门禁绿；publish/verify 零漂移；清单 112 条与在盘文件一一对应、编码三不变式全绿。
- **推断**：F6 的登记规则对 codex / openclaw 运行时同样成立（闸门是运行时无关的装置件，未逐家实测）。
- **未验证**：F5 候选改法的真链效果（未改、未跑链）；codex / openclaw 真链；mcode 链路第 1 环的会话 ID
  仍需子环自己写 `stages[N].session_id` 才登记得上（`session_create` 发生在目标项目会话里，装置拿不到）。
- **git 写操作**：仍是人工验收点 —— B13 的两环产物与台账回写、以及本批改动都留在工作树，未 commit。

### 证据路径（本批新增 2 个文件，全 LF / cr=0）

- `tool\references\selftest-2026-11-26-b14.md` —— 本批小结（改了什么、case 20 断言表、F5 新事实、工具坑）
- `tool\references\selftest-2026-11-26-b14.txt` —— 最终树复跑的 raw 日志（sha/字节数以 `MANIFEST.txt` 为准）

### 本轮工具坑（新增）

12. **闸门类需求的默认修法是「加机制兜底」而不是「加一句要求」**：F6 的本质是散文要求没有机制；
    只在 prompt 里加要求 ⇒ 同一个洞留在别的运行时上，且破 B10 约束。
13. **闸门里的「当前这一环」取的是提交前的值**：`next_session_id` 在提交前正好指向正在跑的那一环
    （上一环写的；CLI 首环由启动器写）⇒ 可作会话 ID 第二来源。
14. **去重要按「包含」不按「相等」**：协议里的 `sessions_append` 可能带别的上下文，按相等去重会漏。
15. **`AGENT-RELAY.md` 的缩进是 5 个空格**（4 / 6 都匹配不上）⇒ `old_string` 锚不准就换 ASCII 锚点或改用脚本替换。

---

## 批次 B15 实录 —— F5 终态口径改为 done（2026-11-26）

### 背景与拍板

B13 真链跑完两个阶段后，台账终态落 `status=blocked` / `current_stage=3` / `max_stages=2`，
notes 原文 `current_stage 3 > max_stages 2 -> status=blocked, no next link spawned`。
链**成功跑完**却被记成故障，且与启动器闸门自己的判据（`status=done && current_stage>=max_stages` ⇒
`chain_exhausted` exit 3）互相矛盾 —— 这就是 F5。

本轮由人拍板两件事：

1. **终态 = `done`**：全部阶段完成 ⇒ `status=done`，`current_stage > max_stages` 是完成信号；`blocked` 只留真卡住
   （人工验收 / 缺权限 / 无进展 / `blocked_on` 有未结项）。
2. **不动启动器生成的 mcode prompt**：改动只落在家规块 + 台账种子 + 协议 ⇒ B10「mcode prompt 逐字不变」仍成立。

### 改了什么

| 文件 | 改了什么 |
|---|---|
| `tool\templates\AGENTS-RELAY-BLOCK.md` | 第 11 条改成终态口径（done 为完成信号；未完成才 blocked；不得自行加长 max_stages） |
| `tool\templates\start-relay.ps1` | 台账种子 `stop_conditions` 旧一条拆两条（done / blocked），比较符 `>=` → `>` |
| `device\start-relay.ps1` | 与模板逐字一致（硬不变式，`Copy-Item tool\templates\<f> device\<f> -Force`） |
| `tool\templates\AGENT-RELAY.md` + `protocol\AGENT-RELAY.md` | 三处口径：骨架 `stop_conditions`、§2 第 4 步、§10 第 4 条；两份 sha256 相同 |
| `scripts\selftest.ps1` | 新增 case 21（7 条断言） |

**没动**：prompt 块的 `$stopRule` 与校验句；启动器 `chain_exhausted` 闸门（本来就认 done）；
`protocol\practilog-agents-pointer.md:11` 旧文案（不在发布清单，`scripts\` 零引用；记遗留）。

### 门禁结果（盘上回读）

- 一键自测：`SUITE_END pass=249 fail=0`，`EXIT=0`；基线 B14 242 ⇒ 净增 7 条。
- prompt 未变回归：本轮日志 `b13_mcode_prompt_*` 六条断言原样通过。
- 装置三件 `device\` ↔ `tool\templates\` sha16 逐件相等（`start-relay` `F6F89FC491A96428`、
  `relay-lock` `23E51FB2619230DC`、`relay-ledger` `7E9601DE9A1CBFF3`）。
- 协议两份 `sha16=0E7B9F580881EFB5` / 22,568 B 逐字一致。

### 已验证 / 推断 / 未验证

- **已验证**：case 21 七条断言全绿（含真夹具 `status=done` ⇒ `exit=3 chain_exhausted` 的行为断言）；
  改后 `device` 与模板逐字一致；249/0 门禁绿；新增 2 个 `references\` 文件全 LF / 无 BOM。
- **推断**：`done` 口径对其他运行时（Claude Code / Codex / OpenClaw）同样生效（协议与家规块运行时无关）。
- **未验证**：真起一条链跑到终态（本轮只有装置级证据，没有真链；这是人工验收点）；
  闸门不会在子环彻底漏写收尾时自动把 `status` 置 `done`（见遗留 1）。

### 证据路径（本批新增 2 个文件）

- `tool\references\selftest-2026-11-26-b15.md` —— 本批小结（口径、改动表、case 21 断言表、遗留）
- `tool\references\selftest-2026-11-26-b15.txt` —— 最终树复跑的 raw 日志（21,382 B / cr=0；sha16 以 `MANIFEST.txt` 为准）

### 本轮工具坑（新增）

16. **改「口径」先枚举消费者，别只改字面**：同一句旧规则同时活在 家规块 / 台账种子 / 协议骨架 / §2 / §10 五处，
    只改一处会产出互相矛盾的文档；全仓 `grep max_stages` 才看得全。
17. **改种子不改 prompt 的前提是先读 prompt 渲染块**：`start-relay.ps1` 的 prompt 从 `:417` 起、不引用种子的
    `stop_conditions` ⇒ 改种子才保得住 B10；反过来若不先确认，改「文档」也可能动到 prompt 字节。
18. **「跑完 = done」与「停下 = blocked」是两件事**：`$stopRule` 讲的是「必须停下时怎么写」，不是终态；
    两条语义可以各自成立，别为了「统一措辞」去动 prompt。

### 遗留与下一批候选

1. **闸门加兜底**：阶段全 `done` 而 `status=running` 时，闸门可拒绝继续（或自动置 done）。按 B14 教训正解是机制化，
   但超出本轮拍板半径 ⇒ 交人决定。
2. `protocol\practilog-agents-pointer.md:11` 旧口径（非发布物）。
3. `tool\SKILL.md:139` 描述「台账 blocked 或耗尽 ⇒ 拒绝起链」，代码判据是 done + 耗尽；措辞可对齐。
4. 真链复测（人工验收点）。

---

## 批次 B16 实录 —— 闸门兜底：跑到阶段上限仍 running 就拒绝起链（2026-11-26）

### 背景与判据

B15 定了终态口径（跑完写 `done`），但留了一个洞：**子环若彻底漏掉收尾回写**，台账会停在
`status=running`，而 `current_stage` 已等于 `max_stages`。此时旧闸门两条判据都不拦：
没有 `in_progress` 阶段，`next_session_id` 也拦不住（B13 真链终态该字段仍有值，回写器没有清空路径）。
结果启动器会再起一环，去干计划外的 stage N+1。

本轮补上兜底，判据只用状态比较：**`status=running` 且 `current_stage >= max_stages`**。

刻意**不做**「自动置 done」：拒绝同样构成机制，且不写状态、无不可逆风险；状态变更仍只走
`relay-ledger.ps1`（拒绝行给出可照抄的关闭方法：`-Action status` 取 sha256 → 提交
`{"set_status":"done"}` patch）。

### 改了什么

| 文件 | 改了什么 |
|---|---|
| `tool\templates\start-relay.ps1` | 闸门新增 `chain_at_stage_cap` 分支，夹在 `chain_already_running` 与 `chain_exhausted` 之间 |
| `device\start-relay.ps1` | 与模板逐字一致（硬不变式，sha256 相等） |
| `tool\templates\AGENT-RELAY.md` + `protocol\AGENT-RELAY.md` | 闸门表补一行 `chain_at_stage_cap`；两份逐字一致 |
| `tool\SKILL.md` | 四道闸门第 2 条按新口径重写（补新 reason，把「耗尽」写明为 done + 耗尽） |
| `scripts\selftest.ps1` | `$lauLiterals` 加 `chain_at_stage_cap`；新增 case 22（正向拒绝 + 反向对照，共 2 条断言） |

**没动**：prompt 块的 `$stopRule` 与渲染正文（B10 约束）；`chain_exhausted` 老分支；
`protocol\practilog-agents-pointer.md:11` 旧口径（非发布物）。

位置为什么重要：case 8 对闸门拒绝理由有白名单（只认 `stage_in_progress` / `chain_already_running` /
`lock_unavailable`）。新分支若排到 `chain_already_running` 之前，`status=running` + 非空
`next_session_id` 的夹具会改走新分支 ⇒ 打破 case 8；排在后面则老情形仍走老分支。

### 门禁结果（盘上回读）

- 一键自测：`SUITE_END pass=251 fail=0`，`EXIT=0`；基线 B15 249 ⇒ 净增 2 条（case 22 两条）。
- 正反两向实测行：
  - `CASE_PASS gate_refuses_running_chain_at_stage_cap exit=3 line=FAIL reason=chain_at_stage_cap current_stage=2 max_stages=2`
  - `CASE_PASS gate_still_starts_below_stage_cap exit=0 cap_hit=False`（同夹具 `current_stage=1` 仍能起链）
- 字面量交叉校验：`CASE_PASS protocol_documents_launcher_literals LAUNCHER doc_missing=[] code_missing=[]`
  —— 新 reason 在协议与代码两侧都存在。
- prompt 未变回归：`b13_mcode_prompt_*` 系列断言原样通过。
- 装置件 `device\` ↔ `tool\templates\` 逐字一致；协议两份逐字一致（`MIRROR identical=True`）。
- publish：`STATUS=OK fail=0 warn=2`，`EXIT=0`；两条 WARN 是 `examples\practilog\docs\relay\` 的
  `SNAPSHOT_DRIFT`（软不变式，只报不判、不为它同步）。
- refresh-manifest：`verdict=PASS`、`INVARIANT_OK=True`、`BOM_FILES=0`、`PS1_NON_ASCII_FILES=0`、
  `MD_TXT_CR_TOTAL=0`、`EXIT=0`。件数/字节数以 `MANIFEST.txt` 为准。

### 已验证 / 推断 / 未验证

- **已验证**：case 22 两条断言正反都绿（拒绝带 reason、正常接力不被误伤）；两个同步副本 sha256 相等；
  251/0 门禁绿；新增 `references\` 两件全 LF / 无 BOM。
- **推断**：该兜底与运行时无关（判据只看台账字段）⇒ 对 Claude Code / Codex / OpenClaw 同样生效。
- **未验证**：真链跑到终态后第二次起链被拒（本批仍只有装置级证据；人工验收点）。也**没有**验证
  「阶段未全 done 但 current_stage 已触顶」的脏数据形态 —— 判据不看阶段明细，仍会拒绝，这是有意的保守取向。

### 证据路径（本批新增 2 个文件）

- `tool\references\selftest-2026-11-26-b16.md` —— 本批小结（判据取舍、改动表、case 22 断言表、遗留）
- `tool\references\selftest-2026-11-26-b16.txt` —— 最终树复跑的 raw 日志（21,587 B / cr=0；sha16 以 `MANIFEST.txt` 为准）

### 本轮工具坑（新增）

19. **兜底判据要去真终态证据里验反例**：原设想用「`next_session_id` 为空」，但 B13 真链终态该字段仍有值、
    回写器也没有清空路径 ⇒ 判据差点建在永假条件上。写判据前先拿一份真实终态台账对照。
20. **新增闸门分支要查既有断言的 reason 白名单**：case 8 只认三个 reason，插入位置错了会让老 case 变红；
    位置（在 `chain_already_running` 之后）和逻辑本身一样是需求。
21. **两个分支都 exit 3 时，机器只能靠 reason 区分**：`chain_at_stage_cap`（该收尾没收尾）与
    `chain_exhausted`（已收尾且耗尽）必须各有独立 reason，否则运维分不清该补回写还是该换新链。

### 遗留与下一批候选

B15 遗留 1（闸门兜底）与遗留 3（`SKILL.md` 措辞）已在本批关闭；遗留 2 继续记账；遗留 4 见上「未验证」。

1. **真链复测（人工验收点）**：跑到终态、再验第二次起链被拒。
2. **`protocol\practilog-agents-pointer.md:11`** 仍是旧口径（非发布物，不进安装/发布清单）。
3. **可选：把 `chain_at_stage_cap` 升级为自动收尾**：拒绝只是兜底；将来若要让装置自己把 `status` 翻 `done`，
   入口就在这个分支，但必须走 `relay-ledger.ps1`（不得裸写）。


---

## 批次 B17 实录 —— 真链复测到终态 + 接力会话零填充序号（2026-11-26）

### 背景与判据

两件事并行：**① 关 B16 遗留 1（人工验收点）** —— 真起一条链跑到自然终态，再验第二次起链被拒；
**② 新要求** —— 自动接力的会话要带序号，让 Agents 使用者一眼看清会话顺序。

命名判据不是「好看」，而是两条可证伪的性质：**字典序 = 链序**（`relay-10` 不得排在 `relay-2` 前面）
和**链长可见**（`of02` 说明共几环）。旧式 `relay-1-<short>` 两条都不满足。

真链判据沿用 B13：完全无人值守、子环自起下一环、终态 `status=done` 且 `current_stage > max_stages`，
再起一环必须被闸门拒绝并给出 reason。

### 改了什么

| 文件 | 改了什么 |
|---|---|
| `tool\templates\start-relay.ps1` | `$linkTag` / `$nextLinkTag` / `$nameRule` / `RELAY_LINK` 头 / 两条 `$completionRule` / mcode `title=` 与 tool `task=` 提示，统一改 `relay-<NN>of<MM>-<阶段短名>` |
| `tool\templates\AGENT-RELAY.md` + `protocol\AGENT-RELAY.md` | 命名规则与交接说明（两份逐字一致） |
| `tool\templates\ACTIVATION-SPAWN-mcode.md` / `ACTIVATION-SPAWN-openclaw.md` | `title` / `task` 示例改零填充 |
| `protocol\relay-prompt.md` | L24 / L51 示例改新式，补零填充说明与 `relay-02of05` 例 |
| `tool\references\deployment-openclaw.md` | L74 `task : relay-01of<MM>-<短阶段名>` |
| `device\start-relay.ps1` | `Copy-Item` 同步；逐字一致由 `publish-relay.ps1` 硬判（漂移 exit 2） |

**没动**：prompt 渲染正文与四道闸门的判据逻辑（B10 / B16 结论原样保留）；`examples\practilog\docs\relay\`
（历史快照，家规 8）；不做已存在会话的追溯改名（装置无权改 MCode 会话名，序号从下一条链起生效）。

### 真链复测结果（claude-code 运行时，2 阶段，全程无人值守）

夹具是全新临时 git 仓库（不复用 `examples\`）：`docs\plan-b17.md`、`README.md`、`src\inventory.ps1`，
两遍安装（首跑 `pending`、带 8 项答案二跑 `confirmed`），`INSTALL1_EXIT=0`、`INSTALL2_EXIT=0`、`WARN_COUNT=0`。

- 启动器：`LOCK_ACQUIRED holder=start-relay:68204 stage=1` → `ledger_bootstrapped bytes=2196` →
  `prompt_written bytes=5974`，`LAUNCH_EXIT=0`。
- 第 1 环 `0c0a05de-5232-449a-a22a-72b135660346`：`tool_calls=16`、`finished_at=17:30:58`，
  产物 `docs\relay\stage-1-inventory.md`（1137 B），随后 `current_stage=2`、`next_session_id=f44a31c2-…`。
- 第 2 环 `f44a31c2-1862-4ed0-a029-467631b35099`：`tool_calls=6`、`finished_at=17:37:52`，
  产物含「文件数 3 / 最大文件 `docs\plan-b17.md` 686 B / 总字节 903」。
- 终态台账（17:40:28）：`status=done`、`current_stage=3`、`max_stages=2`、两阶段全 `done`、
  `sessions` 两环齐全、`blocked_on` 空，**锁由子环自行释放**。
- 第二次起链：`SECOND_LAUNCH_EXIT=3`、`reason=chain_exhausted current_stage=3 max_stages=2`、
  `REFUSAL_VERDICT=REFUSED_WITH_REASON`、`VERIFY_EXIT=0` ⇒ **B16 遗留 1 关闭**。

命中分支要说清：终态 `status=done` 走的是 `chain_exhausted`；B16 新增的 `chain_at_stage_cap`
判据是 `status=running` 且触顶，**本批没有命中、也没有故意伪造脏台账去凑**，它仍只有 case 22 的装置级证据。

### 门禁结果（盘上回读）

- 改动时序：模板 17:32:17–17:32:41，协议/参考件 17:34:17–17:34:18，自测 `SUITE_START` **17:34:30**
  ⇒ 已发布 raw 日志来自最终树，没有「改完没重测」的缺口。
- 一键自测：`SUITE_END pass=251 fail=0`、`SELFTEST_EXIT=0`；与 B16 同为 251 条 —— 本批**故意不加断言**：
  命名是纯文本模板改动，加断言等于把同一串字符串抄两遍；改由生成物自证（见下）。
- 命名证据（全取自 17:34:30 那次运行）：`next-relay-prompt.txt` 含 `RELAY_LINK=relay-01of02`、
  完成规则含 `change RELAY_LINK=relay-01of02 to RELAY_LINK=relay-02of02`、
  命名说明含 `relay-10 must not sort beside relay-1`，旧式 `relay-\d+-` 命中 **0**；
  各 `ACTIVATION-PROMPT.txt` 含 `title : "relay-01of<MM>-<short stage name>"`，旧式命中 **0**。
- publish：`STATUS=OK fail=0 warn=2`、`EXIT=0`；两条 WARN 是 `examples\practilog\docs\relay\` 的
  `SNAPSHOT_DRIFT`（软不变式，只报不判、不为它同步）。
- refresh-manifest：见本批收尾（家规：清单最后刷，件数/字节数以 `MANIFEST.txt` 为准）。
  过程故障已定位并修复：该脚本 `ReadAllBytes` 扫 `reports\`，真链后台进程正写 `reports\b17-chain-run.log`
  时必然 exit 1 —— 与内容无关，停掉后台任务后重跑即可。

### 已验证 / 推断 / 未验证

- **已验证**：两环无人值守跑完并自落终态；锁自行释放；第二次起链 `exit=3` + `reason=chain_exhausted`；
  命名改动的生成物证据（新式命中 1 处以上、旧式 0）；251/0 自测；publish 0 fail。
- **推断**：命名落地与运行时无关（mcode 走 `session_create.title`，cli/tool 走 `RELAY_LINK` 头 +
  交接指令，同一份模板渲染）；`chain_at_stage_cap` 对 Claude Code / Codex / OpenClaw 同样生效（判据只看台账字段）。
- **未验证**：`chain_at_stage_cap` 在真链上的表现（需伪造脏台账，与「不伪造验收证据」冲突）；
  mcode / codex / openclaw 三条运行时的真链端到端（仍只有装置级校验）。

### 证据路径（本批新增）

- `tool\references\selftest-2026-11-26-b17.md` —— 本批小结（真链时序、命名证据、工具坑、遗留）
- `tool\references\selftest-2026-11-26-b17.txt` —— 最终树复跑的 raw 日志（21,587 B / cr=0 / sha16=`3E508909BBB585CD`）
- `tool\references\selftest-activation-prompt.txt` —— 已换成新命名版激活包（3,697 B）
- `reports\b17-e2e-setup.ps1`、`reports\b17-e2e-verify.ps1` —— 夹具搭建与回读校验（含二次起链被拒）
- `reports\b17-chain-run.log`、`reports\b17-second-launch.log` —— 真链 raw 日志
- 夹具与自测树在 `%TEMP%` 下（`relay-b17-e2e-20261126-172536\repo`、`relay-port-selftest\20261126-173430`），属临时产物

### 本轮工具坑（新增）

22. **门禁脚本会读整个 `reports\`，后台进程还在写的日志句柄能让它 exit 1**：先停后台任务（确认句柄释放）
    再跑 `refresh-manifest`，否则会误判成文档不合规。
23. **真链台账是多次提交，中途读盘看到的不是缺陷**：`stages[n].status=pending`、`session_id` 缺失、锁仍 LIVE，
    都可能是写回中间态；判终态必须等 `status != running` 且 `updated_at` 稳定后再复读。
24. **「跑到终态再起链被拒」与「跑到上限仍 running 被拒」是两条分支**：前者 `chain_exhausted`（`status=done`），
    后者 `chain_at_stage_cap`（`status=running`）。用真链验前者，别把它记成后者的验证。
25. **纯文本改动更该用生成物自证而不是补断言**：断言把同一串字符抄成两份，改一处忘另一处就假绿；
    扫生成物（新式命中数 / 旧式命中数）能真正区分新旧。

### 遗留与下一批候选

上面 B16 遗留清单第 1 条（真链复测）已在本批关闭；第 2、3 条继续记账：

1. **`protocol\practilog-agents-pointer.md:11`** 仍是旧口径（非发布物，不进安装/发布清单）。
2. **可选：把 `chain_at_stage_cap` 升级为自动收尾** —— 入口在该分支，但必须走 `relay-ledger.ps1`（不得裸写）。
3. **可选：给命名加一条真断言** —— 对 `next-relay-prompt.txt` 断言 `RELAY_LINK=relay-01of\d\d` 且旧式命中 0
   （鉴别力：改回旧式必红）。本批没加，理由见「门禁结果」。
4. **真链运行时矩阵** —— mcode / codex / openclaw 三条仍只有装置级校验，未跑真链端到端。

---

## 批次 B18 实录（2026-11-26）

### 本批范围

三件事，方向一致：**把「改了但没人证明」和「文档说得好听但装置不说实话」变成可证伪的证据**。

1. **B18-a 命名真断言** —— B17 改了链接命名（`relay-01of02`）却**没加断言**，改回旧式不会有任何用例变红。
   本批新 case 23 读**真实启动器产出的 prompt** 断言新旧两种形式，套件外再用变异实验（改回旧式必红）证明有鉴别力。
2. **B18-b mcode 真链端到端** —— B16/B17 最大的缺口：mcode 运行时只有装置级校验。
   本批自造临时仓跑通**两阶段无人值守**，终态 `status=done`、锁自释放、二次起链被拒。
3. **B18-c `chain_at_stage_cap`** —— B17 遗留的「未验证」项。本批在**真实装置 + 真实台账**上验了
   （受管写闸门注入，不是手改台账），**并修掉了它说假话的问题**：触顶时一律说「所有阶段都做完了、去收尾」，
   而实际上阶段可能根本没跑。

### 改动清单

| 文件 | 改动 |
|---|---|
| `tool\templates\start-relay.ps1`（+ `device\start-relay.ps1`，逐字一致） | 触顶闸门 FAIL 行补 `stages=<id:status,...\|none>` 与 `all_done=<true\|false\|unknown>`；HINT 按形态三选一：`all_stages_done_but_status_running` / `stage_cap_reached_with_open_stage` / `stage_cap_reached_with_no_stage_records`（reason 白名单不变） |
| `tool\templates\AGENT-RELAY.md` + `protocol\AGENT-RELAY.md` | 闸门表第 229 行按三形态重写；**两份逐字一致**（sha 复核过） |
| `tool\SKILL.md` | 四道闸门第 2 条补「只有全 done 才可 `{"set_status":"done"}` 收尾」 |
| `scripts\selftest.ps1` | 新 case 23（命名真断言，+9）、新 case 24（触顶三形态，+18） |

### 真链时序（mcode 运行时，夹具仓 `%TEMP%\relay-b18-e2e-20261126-204529\repo`）

- 安装两遍：首遍 `ADAPTATION_STATUS=pending`；带 8 项答案二遍 `ADAPTATION_STATUS=confirmed` /
  `ADAPTATION_SOURCE=answers` / `WARN_COUNT=0` / `INSTALL2_EXIT=0`。
- 启动器：`LAUNCH_EXIT=0`；台账 bootstrap `status=running current_stage=1 max_stages=2`；
  锁 `LOCK_ACQUIRED holder=start-relay:<pid>`。
- 第 1 环 `mvs_8f6ab9a7ba3b4fd6a68df9e09f73c861` → `docs\relay\stage-1-inventory.md`（602 B），
  经台账闸门提交 stage 1（回读 `current_stage=2`、`stages[0].status=done`），锁 renew 后
  `relay-lock.ps1 -Action adopt -SessionId <sid>` 把锁转交子会话。
- 第 2 环 `mvs_68d6d5b12eb949d19fc6ee57335bb232` → `docs\relay\stage-2-inventory.md`（2,883 B）。
- 终态（盘上回读）：`status=done`、`current_stage=3`、`max_stages=2`、`stages=2` 全 `done`、
  `sessions=2`、`blocked_on` 空；锁 `LOCK_FREE`（子环自行释放）。
- 二次起链（把最终版启动器放进夹具仓后跑）：`SECOND_LAUNCH_EXIT=3`、
  `FAIL reason=chain_exhausted current_stage=3 max_stages=2` ⇒ **B17 遗留的「mcode 真链端到端」关闭**。

### 触顶闸门：验 + 修

- 验：`reports\b18-cap-probe.ps1` —— 真实启动器起链 → 真实台账 → 释放锁 → 取在盘 sha256 →
  提交 patch `{"bump_current_stage": true}`（CAS 走闸门，`LEDGER_CAS_OK`，`current_stage 1->2`）→
  再次起链 `exit=3 reason=chain_at_stage_cap`。**受管写闸门注入，不是伪造脏台账。**
- 顺手抓到的新问题：单阶段链（`MaxStages=1`）bootstrap 后 `current_stage=1 max_stages=1` 即触顶，
  HINT 却写「every declared stage is done」⇒ `PART2_HINT_CLAIMS_ALL_DONE=True`，**在说假话且建议错误地 `set_status=done`**。
- 修完的判据（case 24，三形态各起一次真实启动器）：
  `FAIL reason=chain_at_stage_cap ... stages=1:done,2:done all_done=true`（可收尾）/
  `stages=1:done,2:pending all_done=false`（**禁止**收尾）/ `stages=none all_done=unknown`（先补记录）。
- 判别力：套件内外各一份 —— 套件内含否定断言「open_stage 形态里不得出现 `{"set_status":"done"}`」；
  套件外 `reports\b18-cap-hint-mutation.ps1` 把闸门分支变异回旧文案，断言新用例必红、其余用例不受影响。
  实测：`MUTANT_EXIT=1`、`SUITE_END pass=268 fail=10`，**10 条失败全是 `cap_hint_*` 新断言**、`OTHER_FAILS=0`，
  `MUTATION_VERDICT=ASSERTION_HAS_TEETH`。

### 门禁结果（盘上回读）

- 一键自测：`SUITE_END pass=278 fail=0`、`SELFTEST_EXIT=0`（B17 是 251，本批 **+27**：命名 +9、触顶 +18）。
  raw 日志：`tool\references\selftest-2026-11-26-b18.txt`。
- 编码/行尾复核（改完当场）：`tool\templates\start-relay.ps1` 与 `device\start-relay.ps1`
  30,770 B、`cr=0`、`nonascii=0`、`bom=False`、**两份 sha 相同**；
  两份 `AGENT-RELAY.md` 23,183 B、`cr=0`、**sha 相同**；`tool\SKILL.md` 19,229 B、`cr=0`；
  `scripts\selftest.ps1` 93,306 B、`cr=0`、`nonascii=0`、`bom=False`。
- publish：`STATUS=OK fail=0 warn=2`、`EXIT=0`；两条 WARN 是 `examples\practilog\docs\relay\` 的
  `SNAPSHOT_DRIFT`（软不变式，只报不判、不为它同步）。
- refresh-manifest：`verdict=PASS`、`EXIT=0`；清单 **137** 件，
  `tool\templates\start-relay.ps1` 条目 sha16=`3FC019C1024BEA1B` / 30,770 B。
- 全局 skill 复核（发布后回读）：`E:\Users\Duanyi\.minimax\.minimax\skills\relay-port` 里
  `templates\start-relay.ps1` 与 `templates\AGENT-RELAY.md` 与仓库**逐字一致**
  （`GLOBAL_PUBLISHED_MATCH=True`、`GLOBAL_PROTO_MATCH=True`）⇒ 新会话拿到的是 B18 版。
- 收尾顺序：自测（21:05:18 起，21:07:30 `SUITE_END pass=278 fail=0`）→ publish → refresh-manifest，
  raw 日志 `tool\references\selftest-2026-11-26-b18.txt`（24,382 B）即最终树那一次。

### 已验证 / 推断 / 未验证

- **已验证**
  - 命名：真实启动器产物上新式命中 > 0、旧式命中 0；套件内 9 条 + 套件外变异实验（基线绿 / 变异体红）。
  - mcode 真链：两阶段无人值守跑完并自落终态 `done`；锁自释放；二次起链 `exit=3` + `chain_exhausted`。
  - `chain_at_stage_cap`：真实装置 + 真实台账上拒绝成立；三形态 HINT 分流后不再误导；
    新增 18 条断言有鉴别力（套件内否定断言 + 套件外变异实验）。
- **推断**
  - 闸门判据只看台账字段，故三形态分流对 Claude Code / Codex / OpenClaw 同样生效；
  - 命名与运行时无关（cli/tool 走 `RELAY_LINK` 头，mcode 走 `session_create.title`，同一模板渲染）。
- **未验证**
  - **codex / openclaw 两条运行时的真链端到端**：本机没有 `codex` / `openclaw` CLI，
    装第三方 CLI 属需人工批准的动作，本批未擅自安装 ⇒ 这两行仍只有装置级校验。
  - 触顶闸门在 codex / openclaw 真链上的命中（判据与运行时无关，真链证据待补）。

### 证据路径（本批新增）

- `tool\references\selftest-2026-11-26-b18.md` / `.txt` —— 本批小结与最终树复跑的 raw 日志
- `reports\b18-naming-mutation.ps1` / `.log` —— 命名断言变异实验
- `reports\b18-cap-hint-mutation.ps1` / `.log` —— 触顶 HINT 断言变异实验
- `reports\b18-cap-probe.ps1` / `.log` + `b18-cap-part{1,2}-{first,second}.log` —— 触顶闸门真实装置验证
- `reports\b18-e2e-setup.ps1` / `.log` —— mcode 真链夹具搭建
- 夹具仓与自测树在 `%TEMP%` 下，属临时产物

### 本轮工具坑（新增）

26. **`current_stage` 是「下一个要跑的阶段号」，不是「已跑完的阶段数」**：bootstrap 后就是 `1`，
    每完成一个阶段才 `+1`。所以 `current_stage >= max_stages` 命中的是「最多只剩一个阶段」，
    **不等于**「所有阶段都跑完了」—— 这正是本批修掉的说假话的根因。
    终态判据是 `status=done` 且 `current_stage > max_stages`（本批真链：`3 > 2`）。
27. **判「阶段还没跑」不能只看 `current_stage`**：要看 `stages[]` 里每个阶段的 `status`；
    `stages=@()` 表示**一条阶段记录都还没有**（bootstrap 就是这样），
    这与「有阶段但还没跑」是两种形态，HINT 不能混着说。
28. **变异实验的锚点唯一性判据要看清「同类锚点有几处」**：`exit 3` 在启动器里每个闸门分支都有，
    对它做「全文唯一」判据会误报；正确做法是断言**替换区间**的内容特征
    （区间必须含三个新 HINT token 与 `all_done=`），而不是断言区间终点全文唯一。
29. **真链会话的锁要显式转交**：`start-relay.ps1` 起的锁 holder 是 `start-relay:<pid>`，
    子会话接手要 `relay-lock.ps1 -Action adopt -SessionId <sid>`；否则子环跑完后锁一直占着。
30. **PowerShell 的 here-string 不含结尾换行**：`@'...'@` 的值**没有**结尾换行。
    拿它拼变异脚本的替换块时，后面紧跟的代码会被粘到同一行 —— 本轮就踩了：
    替换块的 `Say 'HINT=...'` 与分支自己的 `exit 3` 被拼成一行，`exit 3` 进了字符串里，
    变异体于是「打印完 FAIL 继续往下跑」、退出码变成 0，测的其实是个坏脚本（探针自己报 `ASSERTION_IS_WEAK`，靠这条才发现）。
    修法：拼接前显式 `$block + "`n"`，并在写盘前断言 `(?m)^    exit 3$` 仍在（探针已内置这条断言）。
31. **门禁只统计 `.md` / `.txt`，`reports\*.log` 的 CRLF 会溜过去**：`.gitattributes` 强制
    `* text=auto eol=lf`，所以工作副本里带 CRLF 的日志一旦入库，克隆出来就是 LF，
    **清单里的 sha16 与克隆内容对不上**。本轮提交前扫出 10 个 `reports\*.log` 带 CR
    （`b18-selftest-precheck.log` 一个就有 266 个 CR）。
    修法：入库前把这类文件逐字节转成 LF（只去 CR，不动内容、不动 BOM），再刷清单。
    门禁阈值与白名单属**人工验收点**，本轮**未自行改** ——
    「是否把 `.log` 纳入 `MD_TXT_CR_TOTAL` 统计」留给人工裁决（见遗留候选）。
32. **git 推送要分清「代理断」还是「直连断」**：本机 git 全局配了 `http(s).proxy=http://127.0.0.1:7897`。
    走代理推 GitHub 报 `Recv failure: Connection was aborted`，而 `curl https://github.com` 直连返回 200
    ⇒ 是代理这条链断了，不是 GitHub 不可达（端口探测显示代理进程还在，是转发失败）。
    修法：用**单次命令覆盖** `git -c http.proxy= -c https.proxy= push origin main`
    （`ls-remote` 校验也要同样覆盖），**不要改用户全局 git config**。
    硬判据仍是 `ls-remote` 与 `rev-parse HEAD` 逐字相等。
33. **`refresh-manifest.ps1` 每次运行都会重写 `MANIFEST.txt` 的 `# generated:` 时间戳行**，脚本没有保持不变的开关
    ⇒ 清单在字节意义上**不是幂等的**：只要再跑一次清单，工作树就一定多出一个改动。
    本轮收尾出现的 `DIRTY_AFTER=1` 就是它（`git diff -- MANIFEST.txt` 只剩第 1 行时间戳，
    条目 sha16 / 字节数**全部一致**）。
    判「清单有没有真漂移」必须分两步看：**条目内容**（diff 是否只剩时间戳行）与**工作树是否干净**；
    后者靠把那 1 行一起 commit 掉解决。
    收口顺序必须是：最后一次 refresh-manifest → commit（清单与文档一起提交）→ push，
    **提交之后不要再跑清单**，否则又脏。（`scripts\refresh-manifest.ps1:36`）

### 遗留与下一批候选

上面 B17 遗留清单第 3 条（命名真断言）与第 4 条的 mcode 一半已在本批关闭；继续记账：

1. **codex / openclaw 真链矩阵（本批唯一硬缺口）** —— 本机缺这两个 CLI；
   **人工裁决 2026-11-26：暂不安装**（不在本机擅自装第三方 CLI），两条继续记为遗留；
   将来获批安装后，照 `reports\b18-e2e-setup.ps1` 的形状各跑一条两阶段真链即可补齐。
2. **`protocol\practilog-agents-pointer.md:11`** 仍是旧口径（非发布物，不进安装/发布清单）。
3. **可选：把 `chain_at_stage_cap` 升级为自动收尾** —— 入口在该分支，但必须走 `relay-ledger.ps1`（不得裸写台账）。
4. **可选：把触顶形态判断（`stages=` / `all_done=`）也做成 `relay-ledger.ps1 -Action status` 的输出列**，
   让人不必读 JSON 就看得出链走到哪一步。
5. **门禁白名单是否纳入 `.log`** —— `MD_TXT_CR_TOTAL` 现在只数 `.md` / `.txt`，
   `reports\*.log` 的 CRLF 靠入库前人工转换挡住（本轮 10 个文件已转 LF）。
   阈值与白名单属**人工验收点**，本轮**未自行改**；要不要把 `.log` 纳入统计，请人工裁决。

### 本批收尾的人工裁决（2026-11-26）

| 事项 | 裁决 | 落地方式 |
|---|---|---|
| 是否在本机安装 `codex` / `openclaw` CLI | **暂不安装** | 两条运行时真链继续记为遗留；本批不擅自装第三方 CLI |
| B13–B18 共 56 个文件改动是否提交并推送 | **提交并推送到 `origin/main`** | 本批收尾一次性提交（HEAD `b46e676` = B12 → 新提交含 B13–B18 全部成果） |

人工检查点保留：git commit / push / tag、发布与分发、删除或覆盖用户数据、改用户级 hook 或供应商配置、
付费与额度决策、验收标准自相矛盾 —— 这些仍不由装置自动执行。

### 推送结果（2026-11-26）

- 提交：`5a86cf92eb72717a4a7336df106ee76248eeef83`（B13–B18 全部成果一次性提交，父提交 `b46e676` = B12）。
- 推送：`b46e676..5a86cf9  main -> main`；硬判据 `git ls-remote origin refs/heads/main` 与本地
  `git rev-parse HEAD` **逐字相等**（`PUSH_VERIFIED=True`），推送后工作树 `dirty_files=0`。
- 网络：git 全局配了本地代理 `http(s).proxy=http://127.0.0.1:7897`，走代理推报
  `Recv failure: Connection was aborted`，而 `curl https://github.com` 直连返回 200 ⇒ 是代理链断、不是 GitHub 不可达。
  解法见工具坑 32（**单次命令覆盖走直连，未改用户的全局 git 配置**）。

### 最终推送状态（2026-11-26 收口）

- 本批共 3 次提交，均已推到 `origin/main`：
  - `5a86cf9` —— B13–B18 全部成果一次性提交（父提交 `b46e676` = B12）；
  - `f7ff1d0` —— 记账：推送结果 + 工具坑 31 / 32；
  - `96d197a` —— 收尾记账：`MANIFEST.txt` 的 1 行时间戳刷新（工具坑 33）。
- 硬判据（每次推送后都跑）：`git -c http.proxy= -c https.proxy= ls-remote origin refs/heads/main`
  与本地 `git rev-parse HEAD` **逐字相等**（`PUSH_VERIFIED=True`）。
  上面第 3 次提交推送后读盘：`LOCAL=96d197a2d56a72edcae58fe7394c6bb24a197d9d`，
  `REMOTE=96d197a2d56a72edcae58fe7394c6bb24a197d9d`，两者相等。
- **本文件落盘的那一次提交是本批最后一次记账提交**（改动：本节 + 工具坑 33 + 清单时间戳行）。
  它自己的 sha 不能写进本文件（写进去就又变了）；要核对当前 HEAD 请现跑
  `git rev-parse HEAD` 与 `git -c http.proxy= -c https.proxy= ls-remote origin refs/heads/main` 比对。
- 推送后工作树 `DIRTY_AFTER=0`（`git status --porcelain --untracked-files=all` 输出为空）。
- 远端：`https://github.com/kizemo/agentask-relay.git`，分支 `main`。

## 批次 B19 实录（2026-11-26）

**本批范围**：只做 B18 遗留里可自主推进的两条 —— 第 3 条（触顶后没人收尾，链永远挂在 `running`）与
第 4 条（`status` 只说单阶段、不说整条链）。第 1 条（codex / openclaw 真链矩阵）缺 CLI 不装，
第 5 条（`.log` 是否纳入 `MD_TXT_CR_TOTAL`）属人工验收点，两条都原样留到下一批。

### 做了什么

1. **`relay-ledger.ps1 -Action status` 增第二行 `LEDGER_CHAIN`**，字段顺序
   `current_stage=<n> max_stages=<n> cap_reached=<true|false|unknown> stages=<a>,<b>,... all_done=<true|false|unknown> open_stages=<...>`。
   - `stages=` 是**逐阶段列表**，与第一行 `LEDGER_STATE ... stages=<count>` **同名不同义**（那边是计数，这边逐列举）。
   - 三态字段算不出来就写 `unknown`，不拿 `false` 兜底：`cap_reached` 靠 `[int]::TryParse` 双成功才比较。
   - 无阶段记录时 `stages=none`、`all_done=unknown`、`open_stages=none`；词汇与启动器触顶 FAIL 行一致。
   - 与启动器的形态计算**故意两台独立实现**，自测喂同一份台账交叉比对，谁漂移谁红。
2. **`start-relay.ps1` 增 `[switch]$AutoFinalize`（默认关）**：只在「触顶 + `all_done=true` + 非 `-DryRun`」时
   经台账闸门提交 `{"set_status":"done"}` 关环；写台账**只走 `relay-ledger.ps1`**（锁 + CAS + 只追加 + 写后回读），
   失败只 `WARN auto_finalize=failed reason=...` 不抛。成功印
   `AUTO_FINALIZED status=done before=<sha16> after=<sha16> path=<ledger>`，并把 HINT 换成
   `HINT=chain_closed_by_auto_finalize: ...`（**不**补第二条 `FAIL reason=chain_exhausted`）。
   无论成功失败，本次调用仍以 `exit 3` 结束 —— 语义是「这次没起链」，不是「失败」。
   `-DryRun` 下印 `DRYRUN skip=auto_finalize ...`。
3. **自测 case 25 / case 26**：case 25 五形态 + 跨实现交叉一致（22 条断言）；case 26 六个子场景
   （开放阶段不写、`-DryRun` 不写、默认关、锁被占只 WARN 不夺锁、成功路径 `before≠after`、重跑 `chain_exhausted`）
   （23 条断言）。
4. **套件外鉴别力**：`reports\b19-guard-mutation.ps1` 两个变异体各跑一次全量自测，都判
   `ASSERTION_HAS_TEETH`；期望红 / 必须保持绿两栏与源码级解释见 `tool\references\selftest-2026-11-26-b19.md` §4。

### 已验证（盘上回读）

- 一键自测：`SUITE_END pass=323 fail=0`、`EXIT=0`（B18 是 278，本批 +45 = case 25 的 22 + case 26 的 23）。
  `MANUAL_STEP real_session_activation` 仍在 —— 套件从不调 `session_create`。
- 变异体 1 `launcher_guard_removed`：变异 -30 字节、`pass=321 fail=2`、期望红 2/2、必须绿 0/2 红、`other_fails=0`。
- 变异体 2 `ledger_all_done_pinned`：变异 -80 字节、`pass=320 fail=3`、期望红 3/3、必须绿 0/3 红、`other_fails=0`。
- `device\` 与 `tool\templates\` 三个装置文件逐字一致：`relay-ledger.ps1` `032C49C2BE21D1A7`、
  `start-relay.ps1` `28BBF7DF91990164`、`relay-lock.ps1` 本批未动 `23E51FB2619230DC`。
- 留证：`tool\references\selftest-2026-11-26-b19.md`（17575 字节、260 行、CR=0、无占位符残留）/
  `selftest-2026-11-26-b19.txt`（29078 字节、328 行、CR=0、无 BOM，末行 `MANUAL_STEP`）。

### 发布（publish 回读）

- `pwsh -NoProfile -File scripts\publish-relay.ps1 -Direction publish` ⇒ `DIRECTION=publish STATUS=OK fail=0 warn=2`，
  `tracked_files=78`；两条 warn 全是 `SNAPSHOT_DRIFT`（`examples\practilog\docs\relay\`，家规 8：历史快照只报不同步、
  不为它同步）。
- 硬不变式 `templates_vs_copies` 全绿：`start-relay.ps1 28BBF7DF91990164:35146`、
  `relay-lock.ps1 23E51FB2619230DC:6429`、`relay-ledger.ps1 032C49C2BE21D1A7:19826`、
  `relay-spawn.ps1 438D5C375C7D92F4:16484`、`AGENT-RELAY.md B6BF77AAF8CD3FBC:23617`。
- 全局 skill 侧本批更新：`SKILL.md 0F466F3CAF16B648:19609`、`templates\start-relay.ps1 28BBF7DF91990164:35146`、
  `templates\relay-ledger.ps1 032C49C2BE21D1A7:19826`、`templates\AGENT-RELAY.md B6BF77AAF8CD3FBC:23617`、
  `references\selftest-2026-11-26-b19.md 6A179BEF0949F154:17575`、
  `references\selftest-2026-11-26-b19.txt A12816A8C8A75C55:29078`。
- `refresh-manifest.ps1` 在本节定稿后**最后**跑一次（清单必须包含本文件）。它的数字只留在 `MANIFEST.txt`
  的生成行与门禁行里，不在本节重复抄 —— 本节写完之后不再改本文件，否则清单自指漂移。

### 未验证 / 遗留

- **真链上自动收尾的端到端未做**：本批自测用的是真实装置 + 真实台账 + 真子进程，但没有一条真实
  `session_create` 起的链跑到触顶再自关。下一批候选，判据：盘上 `status` 回读 `status=done` 且
  `current_stage > max_stages`。
- codex / openclaw 真链矩阵（B18 遗留 1）原样未处理，本机缺这两个 CLI。
- `.log` 是否纳入 `MD_TXT_CR_TOTAL`（B18 遗留 5）原样未裁决。
- 台账侧是否给 `set_status=done` 加「阶段全 done」守卫：**本批故意不加**，会切断「人工裁决后手动收尾」这条
  合法路径；要加需先确认那条路留不留。
- `protocol\practilog-agents-pointer.md:11` 仍是旧口径（非发布物，不进清单）。
- 本批工具坑 33–37 见 `tool\references\selftest-2026-11-26-b19.md` §8，本文件不重复。

### 本批工作树状态

用户未授权 commit / push，**本批未提交**，工作树留有 B19 全部改动。

## 批次 B20 实录（2026-11-26）

**本批范围**：只做 B19 §「未验证 / 遗留」第 1 条 —— 在**真链 + 真实台账 + 真实 `session_create`** 上
端到端验证 `start-relay.ps1 -AutoFinalize` 自动收尾。验证过程中发现并修掉两个缺陷：触顶闸门 HINT 措辞
自相矛盾（B19 遗留的表述 bug）、一次性验收器复跑会把「夹具已消耗」印成 7 条产品红灯。B19 另三条遗留
（codex / openclaw 矩阵、`.log` 门禁、台账侧 `set_status=done` 守卫）原样未动。

### 做了什么

1. **真链夹具生成器 `reports\b20-e2e-setup.ps1`**（9352 B / 195 行 / CR=0 / sha16 `40AFCBE9AC764478`）：
   在 `%TEMP%` 建一次性 git 仓库，真跑 `install-relay.ps1` 两遍（断言 pass1 `ADAPTATION_STATUS=pending`、
   pass2 `confirmed` 且 `applied=8/8`）、真跑启动器 `-MaxStages 1`（`exit=0` + `ledger_bootstrapped` +
   `prompt_written`，台账回读 `status=running current_stage=1 max_stages=1 stages=0`），并内置**负向控制**：
   同一夹具再带 `-AutoFinalize` 起一次，要求 `exit=3` / `FAIL reason=chain_at_stage_cap ... all_done=unknown` /
   `HINT=stage_cap_reached_with_no_stage_records:...`、**不得**出现 `AUTO_FINALIZED`、台账仍 `running`。
2. **真链端到端**（`session_create` 真起一环）：`session_id=mvs_bbd188bdad554326b41db3872cb9754f`
   （模型 `minimax/MiniMax-M3`），`relay-lock.ps1 -Action adopt` 收编成功；子会话写
   `docs\relay\stage-1-inventory.md`（2969 B）加两个补丁文件，两次台账提交全走
   `-Action status` → `-Action commit -DryRun` → `-Action commit -ExpectSha256`（sha 链
   `44295922…` → `28892D10…` → `29CB450E…`），**故意不 `set_status=done`、不起下一环、不释放锁**，
   把夹具钉在「触顶且 status 仍 running」这个待收尾形态上。
3. **一次性验收器 `reports\b20-verify-finalize.ps1`**（8562 B / CR=0 / sha16 `1D6841033D910292`）：
   25 条检查，核心判据是「`-AutoFinalize` 跑完 `AUTO_FINALIZED` 行存在、`before` 是收尾前 sha、
   `after` 是收尾后 sha、盘上 `status=done`、`next_session_id` 未被写、重跑 `chain_exhausted` 且 sha 稳定」。
4. **唯一产品改动**（`tool\templates\start-relay.ps1`，`:191-205` 触顶闸门）：`allDoneState=true` 分支原先
   无论有没有 `-AutoFinalize` 都印同一句「触顶但没人收尾」的 HINT，与随后成功的 `AUTO_FINALIZED`
   自相矛盾。改为按 `$AutoFinalize` 二选一措辞（带 flag 版 `:196-197` / 手工版 `:198-200`），
   **共用同一 token** `HINT=all_stages_done_but_status_running:`，自测断言按 token 不按整句，故未改
   `scripts\selftest.ps1`。
5. **HINT 双跑见证 `reports\b20-hint-witness.ps1`**（6058 B / 102 行 / sha16 `66747B7FFBEF8761`）：
   改完产品后不重跑真链（代价高、增量鉴别力低），改用同形态夹具双跑：一次不带 `-AutoFinalize`
   印手工措辞，一次带 flag 印 `AUTO_FINALIZED` + `HINT=chain_closed_by_auto_finalize`，
   断言 `witness_hints_differ`。
6. **留证文档 `tool\references\selftest-2026-11-26-b20.md`**（14628 B / CR=0 / sha16 `FF99D74E6D0F0FEF`）：
   10 节，含夹具与负向控制、真链、验收器与守卫、产品改动、双跑见证、门禁结果、证据路径、
   已验证·推断·未验证、遗留、工具坑 38–42。

### 已验证（盘上回读）

- 夹具：`SETUP_EXIT=0`、`SUMMARY fail=0`、`SETUP_OK`，两遍安装与启动器断言全 PASS。
- 真链一次性验收（首跑）：`VERIFY_EXIT=0`、`SUMMARY fail=0`、`VERIFY_OK`，25 条检查全 PASS。
  夹具终态台账 `B62CEBF9D4708923EC49B6CC6E88050BCB0CF8811547522F64F886884EA08DEA`（2366 B），
  回读 `status=done current_stage=2 max_stages=1 stages=1:done next_session_id=null`
  —— 即「触顶（`current_stage=2 > max_stages=1`）+ 唯一阶段 done + 环已关」三条件同时成立。
- 验收器**复跑**（对已 `done` 的夹具）：`VERIFY_EXIT=2`，印
  `STALE_STATE fixture_no_longer_holds_the_crash_shape ... status=done` + `HINT=one_shot_verifier: ...` +
  `SUMMARY fail=0 checks_run=0 refused_stale_state=true`，**不动任何字节**，事后台账仍 `B62CEBF9…`。
  这是 B20 修掉的第二个缺陷：原版复跑会印 7 条 `FAIL`（与真回归不可区分）。
- 双跑见证：`WITNESS_EXIT=0`、`SUMMARY fail=0`、`WITNESS_OK`；新夹具
  `%TEMP%\relay-b20-e2e-20261126-224818`（head `c9f6483`）。日志 `reports\b20-hint-witness.log`
  （12414 B / CR=179 / sha16 `0FC41BB5320E9640`）内含 `COPY start-relay.ps1 bytes=35754 sha16=753FBF3C03BB083E`、
  `neg_*` 负向控制全 PASS、`PLAIN exit=3` 手工措辞、`AUTO exit=3` +
  `AUTO_FINALIZED before=A72FAEED… after=2ABAC79D…` + `HINT=chain_closed_by_auto_finalize`、`witness_hints_differ`。
- 一键自测（改完装置后）：`SUITE_END pass=323 fail=0`、`EXIT=0`；raw
  `tool\references\selftest-2026-11-26-b20.txt`（29078 B / 328 行 / CR=0 / 无 BOM / sha16 `2C9CF3D77DA8F0D4`，
  `:1` `SUITE_START`、`:327` `SUITE_END pass=323 fail=0`、`:328` `MANUAL_STEP`，`CASE_PASS auto_finalize` 23 条）。
- 硬不变式：`tool\templates\start-relay.ps1` 与 `device\start-relay.ps1` 均 35754 B / 580 行 / CR=0 /
  non_ascii=0 / 无 BOM / sha16 `753FBF3C03BB083E`（逐字一致，`Copy-Item` 同步）。

### 发布（publish 回读）

- `pwsh -NoProfile -File scripts\publish-relay.ps1 -Direction publish` ⇒ `DIRECTION=publish STATUS=OK fail=0 warn=2`，
  `tracked_files=80`（B19 是 78，+2 = 本批 `selftest-2026-11-26-b20.md` 与 `.txt`）；两条 warn 全是
  `SNAPSHOT_DRIFT`（`examples\practilog\docs\relay\`，家规 8：历史快照只报不同步、不为它同步）。
- 硬不变式 `templates_vs_copies` 全绿：`start-relay.ps1 753FBF3C03BB083E:35754`、
  `relay-lock.ps1 23E51FB2619230DC:6429`、`relay-ledger.ps1 032C49C2BE21D1A7:19826`、
  `relay-spawn.ps1 438D5C375C7D92F4:16484`、`AGENT-RELAY.md B6BF77AAF8CD3FBC:23617`。
- 全局 skill 侧本批更新：`templates\start-relay.ps1 753FBF3C03BB083E:35754`、
  `references\selftest-2026-11-26-b20.md FF99D74E6D0F0FEF:14628`、
  `references\selftest-2026-11-26-b20.txt 2C9CF3D77DA8F0D4:29078`。
- `-Direction verify` 同样 `STATUS=OK fail=0 warn=2`（同一组 `SNAPSHOT_DRIFT`），无漂移。
- `refresh-manifest.ps1` 在本节定稿后**最后**跑一次；它的数字只留在 `MANIFEST.txt` 的生成行与门禁行里，
  本节不重复抄 —— 本节写完之后不再改本文件，否则清单自指漂移。

### 未验证 / 遗留

- **首跑 PASS 的原始 stdout 未入库**：验收器首跑时我用 `*>` 把输出写进 `reports\b20-verify-finalize.log`，
  之后为了验证守卫又跑了一次，同一路径被覆盖成守卫输出（635 B / CR=5 / sha16 `2A89432FD9D245D6`，
  内容只有 `STALE_STATE`）。首次 25 条 PASS 只存在于当轮会话工具输出里，**没有盘上原生日志**。
  文档（`selftest-2026-11-26-b20.md` §3/§7）已如实标注这一缺口，未伪造。修法（下一批）：
  验收器输出名带运行序号或时间戳，或首跑前先追加写入，禁止覆盖。
- **「真链证机制」与「见证证措辞」是两段拼起来的**：`-AutoFinalize` 端到端在真实 `session_create` 链上
  验过（机制成立）；改完 HINT 措辞后**没有**重跑真链，措辞由同形态双跑见证验证。两者合起来才等于
  「真链上的措辞也对」，单看任一段都不够。
- 夹具小缺陷（**非产品缺陷**）：OPERATOR NOTE 补丁没给 stage 带 `session_id`，种子 `next_session_id=null`，
  故 `LEDGER_SESSION_SKIPPED stage=1 reason=no_session_id`、`sessions=[]`。属夹具形态问题，原样留账。
- codex / openclaw 真链矩阵（B18 遗留 1）原样未处理，本机缺这两个 CLI。
- `.log` 是否纳入 `MD_TXT_CR_TOTAL`（B18 遗留 5）原样未裁决 —— 本批两份新 `.log` 带 CR
  （`b20-verify-finalize.log` CR=5、`b20-hint-witness.log` CR=179，PowerShell `*>` 写 CRLF），
  与 B17–B19 的 `.log` 同状，门禁不统计它们。
- 台账侧是否给 `set_status=done` 加「阶段全 done」守卫：仍未加（B19 的裁定沿用：会切断人工裁决后手动收尾那条路）。
- `protocol\practilog-agents-pointer.md:11` 仍是旧口径（非发布物，不进清单）。
- 本批工具坑 38–42 见 `tool\references\selftest-2026-11-26-b20.md` §10，本文件不重复。

### 本批工作树状态

B19 已提交为 `8afd581`（"B19: stage-cap gate gets real teeth - two guard mutants, no-session-call assertion"，
父 `81c952a`），当时未推送。B20 全部改动随本节一并提交。
