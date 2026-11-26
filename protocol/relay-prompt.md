# 接力 Prompt 模板（路径 A · session_create 自接力）

状态机文件：`%USERPROFILE%\.minimax\.minimax\maintenance\relay\relay.json`
交接卡（由现有 Stop Hook 每轮自动刷新）：`%USERPROFILE%\.minimax\.minimax\maintenance\task-state\LATEST.md`

占位符全部替换后再发送：`<PLAN>` 计划文档绝对路径、`<WORKSPACE>` 仓库绝对路径、`<N>` 阶段号。

---

## A. 启动 prompt（阶段 1，人工粘贴一次）

```text
按 <PLAN> 建立无人值守接力链，本次是第 1 阶段。

1. 读 <PLAN>，把阶段拆成 relay.json 的 stages[]（每项含 id / title / deliverable / acceptance / status=pending），
   写 %USERPROFILE%\.minimax\.minimax\maintenance\relay\relay.json：
   status=running、goal、plan_doc=<PLAN>、workspace_dir=<WORKSPACE>、current_stage=1、
   auto_relay=true、max_stages=<最大阶段数>、chain_started_at=当前 ISO8601 时间。
2. 只推进 current_stage 这一个阶段，做到 acceptance 判据成立并亲自跑出证据为止。
3. 阶段收尾三件事（顺序不得颠倒）：
   3.1 把本阶段结论写进 <PLAN> 所在仓库的 docs/（handoff 文档），含全路径指针、已验证 / 推断 / 未验证三档、证据路径；
   3.2 回写 relay.json：本阶段 status=done、current_stage 前进一步、sessions[] 追加本次会话 ID、updated_at 刷新；
   3.3 按本文件「B. 接力 prompt」的内容，调用 session_create 开下一会话，workspace_dir=<WORKSPACE>，
       title="relay-<NN>of<MM>-<阶段短名>"（NN=<N+1> 零填充两位、MM=<最大阶段数> 零填充两位，如 relay-02of05），并在其 content 里明确要求：完成后把 relay.json 的 sessions[] 追加其自身会话 ID。
4. 若 relay.json 不存在、status 非 running、或 current_stage 已达 max_stages，或本阶段需要我做人工验收：
   不要新建会话。把 relay.json 的 status 写成 blocked（人工验收点）或 done（全部完成），
   在回答里说明阻塞原因或收链结论，等我介入。
5. 禁止：跨项目目录读别人的交接卡；把密钥/令牌写进任何落盘文件；在存在未终态后台任务时接力。
6. 回执条款：若你被下一环会话的回执消息唤醒（不是我的新指令），只输出一行
   `STAGE-1 RECEIVED|<下游 session id>` 后立即结束本轮；不得调用工具、不得重做阶段工作、不得再建会话。
```

---

## B. 接力 prompt（阶段 N ≥ 2，由上一环 session_create 自动投递）

```text
你是无人值守接力链的第 <N> 环，只做这一个阶段，不要问我任何问题。

1. 先读 %USERPROFILE%\.minimax\.minimax\maintenance\relay\relay.json，再读 relay.json.plan_doc 指向的计划文档。
   （不要依赖 maintenance\task-state\LATEST.md：它是 agent 级共享交接卡，任意其它会话的 Stop Hook 都会覆写它，
   内容可能完全不属于本链。进度真相只有 relay.json + 本仓库 docs/。）
   以 relay.json 为唯一进度真相：若 status 不是 running 或 current_stage 已 ≥ max_stages，
   直接把结论写进仓库 docs/ 后停止，不得再新建会话。
2. 只做 current_stage 对应阶段，做到其 acceptance 判据成立并亲自跑出证据；
   单阶段工具调用超过 40 次仍未收敛，就停下并如实写「未完成」。
3. 收尾三件事（顺序不得颠倒）：
   3.1 阶段结论落盘进该仓库 docs/（handoff-*.md 续编，不新建跨项目指针）；
   3.2 回写 relay.json：本阶段 status=done、current_stage +1、sessions[] 追加自身会话 ID、updated_at 刷新；
   3.3 调 session_create 开下一环，workspace_dir 沿用 relay.json.workspace_dir，
       title="relay-<NN>of<MM>-<阶段短名>"（NN 为 <N+1> 零填充两位，如 relay-02of05），content 用本模板正文、把 <N> 换成 <N+1>，
       并要求下一环完成后把 relay.json 的 sessions[] 追加其自身会话 ID。
4. 必须停下、不得接力的情形：命中 stop_conditions；本阶段涉及提交/发布/删除数据/付费/不可逆操作；
   缺权限或缺外部输入；连续两轮同一阶段无实质进展。
   此时把 relay.json.status 写成 blocked（并写明缺什么）或 done（全部完成），在回答里向我汇报，等我介入。
5. 纪律：中间产物写文件、对话只留指针与结论；不得伪造验收证据；
   取证类具体值（口令/令牌/ID/哈希）必须当场回读文件并给出长度 + sha16 前 16 位 + 尾部 4 字符。
6. 回执条款：你完成后运行时的结果会自动回传给上一环并唤醒它，这是契约、无法禁止。
   因此若你在本轮开头看到的是**下游会话发来的回执消息**（形如 STAGE-<N+1> … 或 relay 链的 ALIVE/OK 行），
   而不是我的新指令：只输出一行 `STAGE-<N> RECEIVED|<下游 session id>` 后立即结束本轮，
   不得调用任何工具、不得重做阶段工作、不得再建会话。
```

---

## C. 收链 prompt（人工验收后，让我继续跑时用）

```text
读 relay.json，把 status 改回 running、current_stage 设为 <M>，
按 B 模板从第 <M> 环继续接力；其余纪律不变。
```

---

## 使用要点

- 链条能自转的**唯一支点**：每一环的 content 里都包含「3.3 调 session_create 开下一环」这条硬义务。任何一环漏写，链就断。
- `session_create` 的 `content` 不得为空；`workspace_dir` 传绝对路径，不传则用 Agent 默认工作区（接力务必显式传，否则阶段落在错误目录）。
  **实测订正（2026-11-24）**：不传时落在 `…\.minimax\sessions\<sid>\workspace` 私有临时目录，看不到项目仓库 ⇒ 不传 = 链必断。
- **回执唤醒条款（必须写进每环 prompt）**：子会话完成后会自动把结果 `session send` 回创建者会话，
  这会让上一环再跑一轮。因此在 B 段末尾固定加一条：
  「若你被下游会话的回执消息唤醒，只输出一行 `STAGE-<N> RECEIVED|<下游 session id>` 后立即结束本轮；
  不得调用任何工具、不得重做阶段工作、不得再建会话。」漏写会让被唤醒的旧会话误当新任务重跑，白烧额度。
- 调用形状：`mcp_invoke(tool_name="session_create", …)`；`mavis` 的 `session create` 子命令不存在（报 `SESSION_CREATE_MOVED`）。
- 成本口径：每完成一环 ≈「新会话 1 轮 + 父会话被唤醒 1 轮」。`max_stages` 要按这个双份算。
- 需要新会话把结果回传到某个会话时，在其 content 里写明「完成后用 `session send` 把结论发到 `<session_id>`」。
- 可选强化（默认**不启用**）：见 `RELAY-SOP.md` 附录的 Stop Hook 门禁，需你在「设置 → 钩子 → 全局」自行打开。
