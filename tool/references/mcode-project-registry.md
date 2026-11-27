# MCode 侧栏项目归属机制（B23 实测 → B24 处置）

> **一句话结论**：MCode 的「项目」= **一个精确的工作目录**。会话归到哪个项目，只由会话的 cwd 决定，跟你在界面上怎么称呼它无关。
> 接力链因此**必然**归到「仓库根目录」对应的那一个项目；仓库被放在另一个目录下面时（`F:\...\filemanager\sigma-file-manager`），链看上去就「排进了另一个项目」。

## 1. 机制（数据层证据）

数据库：`<activeDataDir>\v2\sqlite\runtime-state.sqlite`（本机 `E:\Users\Duanyi\.minimax\.minimax\v2\sqlite\runtime-state.sqlite`，只读查询）。

- `local_runtime_projects`：项目表。`project_kind='workspace'` 时 `workspace_dir` 上有唯一索引 `idx_local_runtime_projects_workspace_v1` ⇒ **一个目录最多一个项目**。
- `local_runtime_sessions`：会话表，带 `workspace_dir` / `project_workspace_dir` / `project_id`。
- 触发器 `trg_local_runtime_project_session_insert_v5`：插入会话时按 `project_workspace_dir` **精确字符串匹配**项目，匹配不到就**自动插入一行新项目**。

三条推论：

1. **没有包含关系映射**：仓库在容器目录下，不会自动归到容器目录的项目里。
2. **首次在某个目录起链 ⇒ 该目录自动多出一个项目**（这就是「我没建过，怎么凭空多出一个项目」的来源）。
3. **不能为了迁就项目归属改 cwd**：链条的相对写入（`docs\relay\stage-N-inventory.md`）依赖 cwd = 仓库根；把 cwd 改成外层容器目录后，文件落错目录、`git` 也不在仓库里。

客户端自己的说明也对得上：`session_create` 的 schema 写着「Prefer project to workspace_dir」「The absolute path of a directory inside a registered project also works and **the session runs in that directory**」——**跑的目录就是归属**。

## 2. 探针（鉴别性实测，不是推断）

| 探针 | 调用 | 结果 |
|---|---|---|
| A：只给 `project`（指向注册项目内部的子目录） | `session_create(project="F:\soft\00selfmade\agentask-relay\tool", title="probe-project-mapping-b23", content="...")` | 成功，但**新建**了项目行 2577（`workspace_dir` = 该子目录的精确路径），会话 `project_workspace_dir` 同样是该子目录 ⇒ `project` 不做包含映射，它等于「在该目录里跑」 |
| B：同时给 `project` 和 `workspace_dir` | `session_create(project="F:\soft\00selfmade\filemanager", workspace_dir="F:\soft\00selfmade\filemanager\sigma-file-manager", ...)` | **被直接拒绝**：`SESSION_CREATE_INVALID_ARGUMENT` /「project 和 workspace_dir 只能填一个」⇒ **「归属外层项目但 cwd 在仓库根」这条路不存在** |
| C：只给 `workspace_dir`（链条的做法） | `workspace_dir="F:\soft\00selfmade\filemanager\sigma-file-manager"` | 会话落在项目 2565（该目录的精确项目）；旧会话批次（56–70 那一批）落在项目 7（容器目录） |

探针 B 发生在「project = 已注册项目、workspace_dir = 它的子目录」这个最强假设上，失败原因由运行时给出，不是推断。

## 3. 因此：装置能做什么、不能做什么

| 诉求 | 能不能靠装置参数做到 |
|---|---|
| 把链条会话归到外层（父目录）项目 | 只能用 `project=<父项目精确键>` + `-AllowHostMismatch`：会话 cwd 落到父目录，prompt 强制绝对路径；`project` + `workspace_dir` 同时传仍被拒（探针 B） |
| 把链条会话归到仓库根对应的项目 | 能（就是现状：`workspace_dir=<仓库根>`） |
| 让错配在起链时可见 | 能：`start-relay.ps1` 打 `INFO host_project_key exact_workspace_dir=<仓库根>`；若 `docs\relay\host-project.txt`（或 `-ExpectedHostProject`）记的期望项目 ≠ 仓库根，再打 `WARN host_project_mismatch expected=... actual_key=...` |
| 把已有会话迁到另一个项目 | 不能靠参数；客户端只能给**项目改名**，会话不能换项目（B24 未变） |

## 4. 现场结论（filemanager 案例；下列数字是 B23 当时快照，B24 未复测）

- 侧栏项目 **「filemanager」** = 容器目录 `F:\soft\00selfmade\filemanager`：实际 409 个会话（用户自己的会话都在这儿）。
- 侧栏项目 **「sigma-file-manager」** = 仓库根 `F:\soft\00selfmade\filemanager\sigma-file-manager`：3 个会话（接力链两环 + 一次后续会话），`project_id=2565`。
- 仓库根的**祖先项目只有容器目录这一个**（前缀查询只命中 id=7）。
- 这不是装置的 bug：MCode 就是按精确目录分组；链要写在仓库里，就必须以仓库根为 cwd，于是归到仓库根那个项目。
- 要让链条显示在「filemanager」名下，只能在客户端**改项目名**（仓库根项目改成习惯的名字，外层项目改名区分），或者接受现状。
- 容器目录里**没有** `docs\`，仓库外**没有**任何 `stage-*-inventory.md` ⇒ 链条的相对写入全部落在仓库内，「在其它目录生成错误文件」未发生。

## 5. 与 Claude Code 的对照

Claude Code 同理（按 cwd 建 `<profile>\.claude\projects\<mangled-cwd>` 登记项），B22 已用 `-EphemeralWorkspace` 处理「验证夹具污染用户级登记册」。差别在于：Claude Code 有 `CLAUDE_CONFIG_DIR` 可隔离（实测否决），MCode 侧**没有等价开关** ⇒ MCode 上的验证夹具只能「用完归档会话 + 移除项目」，不能靠环境变量隔离。
---

## 6. B24：装置侧的处置（只传 `project`，错配硬停）

B23 的结论是「宿主按精确目录分组」，但装置当时仍然把 `workspace_dir` 交给 `session_create`——于是每次起链都在重复「插入新项目行」这个动作，只是多打了一条 WARN。B24 把这条路径掐掉：

| 动作 | B24 的行为 |
|---|---|
| 起环参数 | `project=<host_project>`，**不再传 `workspace_dir`**；prompt 里写明「先在 `project_list` 逐字确认，找不到就写 `blocked`，绝不回退」 |
| 键从哪来 | `-ExpectedHostProject` > `docs\relay\host-project.txt` > 缺省 = 仓库根；恒打 `OK host_project_key exact_workspace_dir=` 与 `OK host_project_value value=... source=... mode=...` |
| 键 ≠ 仓库根 | 默认 `FAIL reason=host_project_mismatch` + `exit 2`（`-DryRun` 只 WARN）；要跑在父项目目录下必须显式 `-AllowHostMismatch` ⇒ `mode=parent`，prompt 全部路径改绝对、git 改 `git -C <repo>` |
| 链的身份 | 传 `-InitiatorSession <sid>`；台账 seed 记 `host_project` / `host_project_mode` / `chain_id` / `chain_tag` / `initiator_session`；标题追加 `[<chain_tag>]`；prompt 首行 `CHAIN <chain_id> \| link <linkTag> \| started ... \| initiator ... \| host project ... (...)` |

**已验证 / 未验证（不夸大）**：装置侧的判定、退出码、seed 字段、prompt 首行与标题后缀由 `scripts\selftest.ps1` case 28 的断言覆盖（`host_project_mismatch_hard_fails` / `host_project_parent_hosting_is_explicit` / `seed_records_chain_identity` / `prompt_carries_chain_banner` 等），可复跑。**未验证**的是宿主行为本身：`project=<父项目键>` 在「仓库根未注册、父目录已注册」时是否被接受，仍没有真链实测；B24 的设计因此不依赖宿主语义——只允许 `project_list` 里逐字存在的键，命中不到就 blocked，所以最坏结果是「链停下来等人」，不是「又新建一个项目」。
