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

