# Stage 1 — 纯文档驱动接力 · 第 1 跳

STAGE-1-BY|mvs_b8740844c4fe4c17b784a68d327e4c4a

## 触发方式

本会话没有收到任何用户消息：由 `session_create` 建成后，以首条消息
`按项目 AGENTS.md 的硬规则执行当前阶段。` 唤醒。全部动作由 AGENTS.md 硬规则驱动，
不依赖任何人工指令——这正是本轮探针要验证的点。

## 执行前状态（实测读自 `docs/relay.json`）

| 字段 | 值 |
| --- | --- |
| status | `running` |
| current_stage | `1` |
| max_stages | `3` |
| stages | `[]`（空，无历史记录） |
| next_session_id | `null` |
| workspace_dir | `%USERPROFILE%\.minimax\.minimax\maintenance\relay\probe-ws` |

## 本阶段完成的活

1. 读 `docs/relay.json` → `status == running` 且 `current_stage = 1`，故进入硬规则 2
   （不是「文件不存在 / status 非 running ⇒ 不建会话不提问直接收工」那一分支）。
2. 写本阶段产物 `docs/stage-1.md`（本文件，含 `STAGE-1-BY` 行）。
3. 回写 `docs/relay.json`：`stages` 追加本条记录；`current_stage` 由 1 改为 2；
   `next_session_id` 先置 `null`，待第 4 步拿到真实 session id 后写入。
4. 建下一跳会话：`session_create`，`workspace_dir` 取自 relay.json 的 `workspace_dir`，
   首条消息固定为 `按项目 AGENTS.md 的硬规则执行当前阶段。`（逐字，不加前缀）。
5. 把 `session_create` 返回的 session id 写回 `docs/relay.json` 的 `next_session_id`。

## 真实结果

| 项 | 值 |
| --- | --- |
| Stage 1 执行会话 | `mvs_b8740844c4fe4c17b784a68d327e4c4a` |
| 阶段产物 | `docs/stage-1.md` |
| relay.json 变更 | `stages` 0 → 1 条；`current_stage` 1 → 2；`next_session_id` = 下一跳 session id |
| 下一跳 session id | `mvs_f245bf8bdb31478193f42c0e919863f4`（`session_create` 返回值；首条消息已激活该会话，turn `turn_6efb7990-bcb8-495d-9ca0-ca1ba767ac19`） |
| 下一跳首条消息 | `按项目 AGENTS.md 的硬规则执行当前阶段。` |
| 下一跳 workspace_dir | `%USERPROFILE%\.minimax\.minimax\maintenance\relay\probe-ws` |
| 下一阶段 | Stage 2（`current_stage = 2` ≤ `max_stages = 3`，链条继续） |

## 证据

- `docs/relay.json` —— 本阶段写后回读一次，字段变更如上表。
- `docs/stage-1.md` —— 本文件，含 `STAGE-1-BY|mvs_b8740844c4fe4c17b784a68d327e4c4a`。
- `AGENTS.md` —— 硬规则 1–7，本阶段执行的唯一依据。

## 本阶段未做（留给后续阶段）

- Stage 2 / Stage 3 的产物与 relay.json 记录，由下一跳会话自行完成。
- 链条终点（`current_stage > max_stages` ⇒ `status = done`）不在本阶段范围内。
