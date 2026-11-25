

## 自动接力（Relay）—— 硬规则

本项目启用会话自动接力。状态机文件：`docs\relay.json`。协议：`docs\AGENT-RELAY.md`（通用）+ `docs\RELAY-ADAPTATION.md`（本项目裁决，**优先级高于通用协议，低于本文件其余家规**）。

1. 开工第一步读 `docs\relay.json`。`status != "running"` ⇒ 不接力，正常收尾。
2. 本环身份 = `current_stage`；只允许写 `stages[current_stage].scope` 声明的写集，且必须先过 `RELAY-ADAPTATION.md` §5 并发检测。
3. `status == "running"` 且本环 acceptance 已达成 ⇒ **回复用户之前**必须：先只追加方式回写 `relay.json`（本环 `status/session_id/model/tool_calls/finished_at` + `current_stage += 1` + `stages` 追加下一环），回读核对条数与署名；再按 §9 模型策略用 `session_create` 起下一环：`workspace_dir` 指向本仓库根，**建环时直接显式传 `model`**。实测硬事实（2026-11-24 从 `session_create` 的 input_schema 回读坐实）：该工具**没有 `defer_first_turn`、没有 `effort`、没有 `parent_session_id` 字段** ⇒ 建环即开跑、没有「先建后校验再放行」的预检窗口，传不存在的字段会被 schema 拒。因此起环后**立刻** `session get` 回读 `model`/`workspace_dir`/`title` 三要素；降级判定只能在失败信号出现后事后做，每次降级必然以一轮失败或空转为代价。把返回的 `session_id` 回写 `next_session_id`。
4. 命中 `human_checkpoints` / `stop_conditions` / 写集冲突 ⇒ 写 `status="blocked"` + `note`，**不起新会话**，停下等人。
5. `current_stage > max_stages` ⇒ 写 `status="blocked"` 停链。不得自行加长 `max_stages`。
6. `docs\relay.json` 的 `status` 只有人能改成 `running`。agent 不得自行起链。
