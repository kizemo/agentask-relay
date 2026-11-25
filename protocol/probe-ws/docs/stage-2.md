# Stage 2 — 纯文档驱动接力 · 第 2 跳

STAGE-2-BY|mvs_f245bf8bdb31478193f42c0e919863f4

## 触发方式

本会话同样没有收到任何用户指令：由 Stage 1 通过 `session_create` 建成后，以首条消息
`按项目 AGENTS.md 的硬规则执行当前阶段。` 唤醒。全部动作仍由 AGENTS.md 硬规则驱动，
再次验证「只靠 AGENTS.md + docs/relay.json 即可自链」。

## 执行前状态（实测读自 `docs/relay.json`）

| 字段 | 值 |
| --- | --- |
| status | `running` |
| current_stage | `2` |
| max_stages | `3` |
| stages | 1 条（Stage 1 记录） |
| next_session_id | `mvs_f245bf8bdb31478193f42c0e919863f4`（= 本会话 id） |
| workspace_dir | `E:\Users\Duanyi\.minimax\.minimax\maintenance\relay\probe-ws` |

## 本阶段完成的活

1. 读 `docs/relay.json` → `status == running` 且 `current_stage = 2`，故进入硬规则 2
   （非「文件不存在 / status 非 running ⇒ 不建会话不提问直接收工」分支）。
2. 回写 `docs/relay.json`：`stages` 追加本条记录；`current_stage` 由 2 改为 3；
   `next_session_id` 暂置 `null`。
   - 顺序说明：先回写 `current_stage = 3` 再建会话，避免第 3 跳会话被唤醒时读到
     `current_stage = 2` 而重复执行本阶段（跨会话并发写同一文件）。
3. 建下一跳会话：`session_create`，`workspace_dir` 取自 relay.json 的 `workspace_dir`，
   首条消息固定为 `按项目 AGENTS.md 的硬规则执行当前阶段。`（逐字，不加前缀）。
4. 把 `session_create` 返回的 session id 写回 `docs/relay.json` 的 `next_session_id`。
5. 写本阶段产物 `docs/stage-2.md`（本文件，含 `STAGE-2-BY` 行）。

## 真实结果

| 项 | 值 |
| --- | --- |
| Stage 2 执行会话 | `mvs_f245bf8bdb31478193f42c0e919863f4` |
| 阶段产物 | `docs/stage-2.md` |
| relay.json 变更 | `stages` 1 → 2 条；`current_stage` 2 → 3；`next_session_id` = 下一跳 session id |
| 下一跳 session id | `mvs_12e46516919f406e9b4dd87b49de5f41`（`session_create` 返回值；turn `turn_b2272dbd-0220-40d7-88ac-3af455b36eca`，mode `activated`） |
| 下一跳首条消息 | `按项目 AGENTS.md 的硬规则执行当前阶段。` |
| 下一跳 workspace_dir | `E:\Users\Duanyi\.minimax\.minimax\maintenance\relay\probe-ws` |
| 下一跳 location.mode | `current`（就地工作，非 worktree） |
| 下一阶段 | Stage 3（`current_stage = 3` ≤ `max_stages = 3`，链条继续） |
| 链条终点 | Stage 3 之后 `current_stage = 4 > max_stages = 3` ⇒ `status = done`，不再建会话 |

## 证据

- `docs/relay.json` —— 本阶段写后回读一次，字段变更如上表。
- `docs/stage-2.md` —— 本文件，含 `STAGE-2-BY|mvs_f245bf8bdb31478193f42c0e919863f4`。
- `AGENTS.md` —— 硬规则 1–7，本阶段执行的唯一依据。

## 本阶段未做（留给后续阶段）

- Stage 3 的产物 `docs/stage-3.md` 与 relay.json 收尾记录（`status = done`），由第 3 跳会话自行完成。
- Stage 3 会话同样需要向其创建方（本会话 `mvs_f245bf8bdb31478193f42c0e919863f4`）回执一行
  `STAGE-3-DONE|<session id>`；AGENTS.md 硬规则 7 明确禁止写交接卡，本阶段未写任何交接卡。
