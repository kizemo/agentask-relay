# 纯文档驱动接力 · 实测记录（2026-11-24 20:47–20:50）

对应问题：「交一份 md 给项目 Agents，之后无人接入，项目能否自己一环环交接接力直到目标完成？」
答案：**能**。本轮实测三跳全通，且没有任何一环收到过人类指令。

## 一、实验条件

工作区：`E:\Users\Duanyi\.minimax\.minimax\maintenance\relay\probe-ws`（普通目录，非 git 仓库）

投入该项目的东西只有两份文档：

- `AGENTS.md` 1336 B —— 7 条硬规则：读 `docs/relay.json` → 完成 `current_stage` 的活 → 写 `docs/stage-<N>.md`（含 `STAGE-N-BY|<自己的 session id>`）→ 回写状态 → `session_create` 起下一环（content 只有一句协议）→ 超 `max_stages` 则 `status=done` 不再建会话 → 禁止提问。
- `docs/relay.json` 初值 303 B —— `status=running, current_stage=1, max_stages=3, workspace_dir=<本项目绝对路径>`。

人类输入总共一句，发给第 1 环：`请把项目当前阶段的活儿做完，并更新项目文档。不要问我问题。`
这句话里没有「接力」「新会话」「session_create」任何字眼。

## 二、实测结果（台账逐字回读）

`docs/relay.json` 的 `stages` 数组，20:50:33 回读：

| stage | 执行者 session | 它创建的下一环 | 产物署名 |
|---|---|---|---|
| 1 | `mvs_b8740844c4fe4c17b784a68d327e4c4a` | `mvs_f245bf8bdb31478193f42c0e919863f4` | `STAGE-1-BY\|mvs_b8740844…` |
| 2 | `mvs_f245bf8bdb31478193f42c0e919863f4` | `mvs_12e46516919f406e9b4dd87b49de5f41` | `STAGE-2-BY\|mvs_f245bf8b…` |
| 3 | `mvs_12e46516919f406e9b4dd87b49de5f41` | `null`（正确地不再建） | `STAGE-3-BY\|mvs_12e46516…` |

三个 stage 文件一一对应、无重名、无覆写冲突；每个执行者署名互不相同。

**链已自然收口**（20:50:58 哨兵回读，无人干预）：`status=done`、`current_stage=4`、`max_stages=3`、`next_session_id=null`，第 3 环的 `summary` 逐字写明「current_stage 4 > max_stages 3 故不建下一跳会话」。⇒ 目标达成后链自己停下，没有无限起链。全程 3 跳耗时约 2 分 18 秒（20:47:00 → 20:49:00 记录粒度），每环 12–20 秒级响应。

**并发写入竞态（真实发生一次，被模型自愈）**：第 3 环在 `relay.json` 的 `note` 里主动报告——第 2 环对 `stages[1].created_session_id` / `next_session_id` 的回写，落地晚于第 3 环的首次读取，属跨会话写入竞态而非漏写；第 3 环保留了该变更并在其上追加了自己的记录。这说明：① 链上各环不是串行独占状态文件的，② 「读-改-写」在模型手里**这次**没丢数据，但**这是运气而不是机制**。生产链必须把状态回写做成**只追加**（`stages` 数组 append，禁止改别人的条目），或者干脆每个 stage 写自己的 `docs/stage-<N>.md`、状态文件只由一个「记账」角色写。

## 三、这一轮新确立的三条硬事实

1. **`AGENTS.md` 确实自动注入**（上一轮探针 `mvs_b8740844…` 已证：首条 assistant 文本以协议要求的 `PROJMEM-SEEN|<sid>` 开头，且该轮**没有调用 read** 就逐字引用了文件内容）。所以「交给项目一份文档」这个动作本身成立。
2. **`session_create` 的「需用户明确要求」守卫不拦 agent 自起链**。工具描述写的是 `Call this only when the user explicitly asks for a new session`，实测项目文档里的规则被会话当成「用户已经明确要求」，运行时没有额外拒绝、没有人工确认弹窗。⇒ `AGENT-RELAY.md` 里那句「rules 优先于默认谨慎」不是必需，保留只是压制模型犹豫。
3. **回执向上唤醒没有造成重复干活**。运行时契约是每环完成后 `session send` 回它的创建者（第 2 环的回执投给第 1 环，不是投给我）。三跳跑下来，被回执唤醒的历史环**没有**重新执行协议、没有二次起链、没有把 `current_stage` 推错。⇒ 幂等守卫在实测里非必需，但生产链仍建议写死（判据：`current_stage` 等于自己领到的编号才干活），因为模型换了、阶段变重时不保证。

## 四、仍未验证（不得当已成立）

- 阶段内容是**写文档**，不是真实代码改动；真实改动型接力需要仓库写权限、门禁、提交策略，风险面完全不同。
- 链长只有 3 环。>3 环的累计成本与漂移率未测。
- 桌面端对自动新建会话的可见/可接管体验只确认了 API 层可读（`session list` / `session messages` 都能看到自动建的会话），没有人工进界面点过。
- 路径 B（Stop Hook + `mcode exec`）本机 `mcode` 不在 PATH，仍未装未测。

## 五、复现配方

1. 新建目录 `<ws>\AGENTS.md`（抄第一节那 7 条）与 `<ws>\docs\relay.json`（`status=running, current_stage=1, max_stages=3, workspace_dir=<ws 绝对路径>`）。
2. 用 `session_create` 建第 1 环：`agent_name="me"`、`workspace_dir=<ws>`、`content="请把项目当前阶段的活儿做完，并更新项目文档。不要问我问题。"`。
3. 判据只看 `<ws>\docs\relay.json` 与 `session list`，不要看回执文本（回执是子会话自己合成的短句，不反映它是否真起了下一环）。
4. 轮询到 `status != running` 收口。

关键坑：`workspace_dir` 必须在 `relay.json` 里写成绝对路径并被每环显式带上，漏传会让下一环落在私有临时目录、看不到本项目，链当场断。
