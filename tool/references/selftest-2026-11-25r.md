# selftest 2026-11-25r —— 首跑自动提问（B11 case 18）+ B10 命令行顺序修复转绿

- 权威 raw 日志：`tool\references\selftest-2026-11-25r.txt`
  （`len=18990 cr=0 sha16=B2BD694CD9A51441`，219 行，`CASE_PASS=215` / `CASE_FAIL=0`）
- 跑法：`pwsh -NoProfile -ExecutionPolicy Bypass -File scripts\selftest.ps1 -EvidencePath "<绝对路径>"`
- 判绿口径：`SUITE_END pass=215 fail=0` **且** 进程 `EXIT=0`（本轮实测 `EXIT=0`、`FAIL_LINES=0`）
- 上一轮绿基线：`selftest-2026-11-25p` = 182 条 / 0 失败 ⇒ 本轮净增 **33 条**
- 中间那一版 `selftest-2026-11-25q` = `pass=183 fail=3`（**红**，17d 未修完），不是基线，勿引用其数字

---

## 1. 这一轮改了什么

两件事同批收口。

**B11 —— 首跑自动提问**（用户新需求：装完不再由人手工补 TODO）

| 件 | 动作 |
|---|---|
| `tool\templates\RELAY-ADAPTATION.md` | §3/§4/§5 的 `TODO` 全部换成 9 个占位符（`{{WRITE_SET_ALLOW}}` / `{{WRITE_SET_DENY}}` / `{{CONCURRENCY_CHECK}}` / `{{GATE_COMMAND}}` / `{{GATE_VERDICT_FIELD}}` / `{{MODEL_PRIMARY}}` / `{{MODEL_FALLBACK_DAY}}` / `{{MODEL_FALLBACK_NIGHT}}` / `{{ADAPTATION_SOURCE}}`）；三节标题改成 `## 3. 写集与并发检测（source: {{ADAPTATION_SOURCE}}）` 形式，让读者一眼看出填的是探测默认值还是用户裁决值 |
| `tool\templates\ADAPTATION-QUESTIONS.json` | **新增**，125 行 / 8 问（schema `relay-port/adaptation-questions@1`）：`title` / `intro`（写明「`default` 不是用户确认值」、一次问 2-3 项）、6 个中文渲染标签 + `footer`、3 组（write_set / gate / models，各带 `ask_hint`）、8 项 `questions`（`id` / `group` / `section` / `label` / `answer_key` / `type` / `prompt` / `hint`）、`answers_example` |
| `tool\scripts\install-relay.ps1` | 新增 `-AnswersFile`；新增探测块 `Get-AdaptationProbe`（8 键真值默认，`gate_verdict_field` 默认 `none` 而非说明句）、`Find-GateScript`、`Get-WriteSetProbe`、`Format-BulletList`、`Split-Section`、`Update-AdaptationSections`、`Write-AdaptationAnswersTemplate`、`Write-AdaptationQuestionPacket`；`Expand-Template` 追加 `-Adapt`；§6 适配块重写；`§11 Next step` 改成三状态分支；stdout 新增 `ADAPTATION_STATUS=` / `ADAPTATION_SOURCE=` / `ADAPTATION_DOC=` / `ADAPTATION_QUESTIONS=` |
| `tool\SKILL.md` | 文件表、调用示例、参数说明补 `-AnswersFile`；`装完之后必须做的两件事` 重写为「① 把三项裁决问出来（`pending` 不许起链）② 在目标项目内激活」 |

**B10 —— 命令行形状修复**（上一批遗留的红）

`relay-spawn.ps1` 的 `$cmdArgs` 重排（旗标全在前、`@('-p', $promptText)` 最后），`$headlessSettings` 改成嵌套键位 `permissions.defaultMode`，`$display` 镜像真实 argv。装置镜像 sha16：`relay-spawn.ps1` = `438D5C375C7D92F4`、`start-relay.ps1` = `D795D14DDAE16FCC`（`tool\templates\` 与 `device\` 逐字一致，本机实测 `match=True`）。

---

## 2. case 18 覆盖了什么（29 条断言）

**首跑（`source=defaults`，8 条）**：`EXIT=0` / `INSTALL_VERDICT=PASS` / `ADAPTATION_STATUS=pending` /
`ADAPTATION_SOURCE=defaults` / `ADAPTATION_QUESTIONS=docs\relay\adaptation-questions.md` /
`WARN adaptation_defaults_unconfirmed` / `ADAPT_CHECK … placeholders=0 source=defaults`。

**文档本身（3 条）**：无 `TODO` 残留、无 `{{…}}` 残留、`source: defaults` 恰好出现 3 次。

**问题包三件（6 条）**：`.md` / `.json` / `.answers.template.json` 都在；JSON 里 `questions` 恰 8 项、
`repo` 已填、`answer_key` 集合与 8 键**完全相等**（`concurrency_check,gate_command,gate_verdict_field,model_fallback_day,model_fallback_night,model_primary,write_set_allow,write_set_deny`）；`md` 必须逐一点名每个 `answer_key` 且含 `2-3`。

**答案回填（9 条）**：`EXIT=0`、`ADAPT … applied=5/8`（5 个答案键 / 8 个探测键）、
`PATCH RELAY-ADAPTATION.md sections=3,4,5 missing= answers=…`、`ADAPTATION_STATUS=confirmed`、
`ADAPTATION_SOURCE=answers`、问题包指针清空、不再出 `adaptation_defaults_unconfirmed`、
文档里出现答案值（`GATE_VERDICT=PASS` / `secrets/` / `tests/`）、`source: answers` 恰 3 次、**§6/§9 手改区未被顶掉**。

**失败码（1 条）**：`-AnswersFile` 指向不存在文件 ⇒ `EXIT=2` 且 `reason=answers_file_missing`。

---

## 3. 这一轮踩的坑

1. **待答不能用非零退出码表达**：`selftest` 里既有断言要求 `install_exit_zero`，又有 `INSTALL_VERDICT=PASS` ⇒
   `ADAPTATION` 待答只能走 `ADAPTATION_STATUS=pending` 这一行 + 问题包文件 + `SKILL.md` 硬性要求，
   退出码保持 0。同理 `Warn` 不进 `$verdict`，新增 `adaptation_defaults_unconfirmed` 才没打破既有 PASS。
2. **安装器不能交互提问**：无 TTY，`Read-Host` 会挂死 ⇒ 改成「写问题包三件 + 打 `ADAPTATION_*` 行」，
   由托管 agent 按包发问后 `-AnswersFile` 重跑。
3. **探测默认值必须是可用的真值**：`gate_verdict_field` 最初塞的是说明句，会原样写进文档；改成 `none`。
   判绿口径的措辞交给模板承载，不能混进默认值。
4. **CJK 不得进 `.ps1`**：8 问的中文文案全部外置到 `ADAPTATION-QUESTIONS.json`（`.json` 不受 ASCII 约束），
   安装器保持 `BOM=False NONASCII=0 CR=0`。
5. **定点更新而非整篇覆盖**：已有文档只替换 §3/§4/§5（`Split-Section` + 逐节 `[regex]`），
   无 `-AnswersFile` 且文档已存在时 `SKIP … kept`，保护用户手改；`-Force` 才整篇覆盖。实测 `sec6_kept=True`。
6. **`edit` 顶掉相邻条目**：改 `SKILL.md` 参数表时，新条目把「幂等」那条顺带顶掉了，已补回。
   改列表条目时新内容要自带旧条目原文。

---

## 4. 仍未验证 / 遗留

- **B10 端到端未复验**：`$cmdArgs` 顺序 + 嵌套键位修好后，尚未在干净真链仓跑通「第 1 环跑 pwsh → 写产物 →
  台账 `stage_done` → 推进 4 token → 自举第 2 环」。已核对的是**命令行形状**（case 17d）与**权限配方可用**（实测矩阵），
  不是整链。
- codex / openclaw 真链仍未实测（本机未安装）。
- `relay-ledger.ps1` 不校验 `next_session_id` 形态（文档漂移，沿用 B9）。
- 下一环 prompt 的推进靠 LLM 复制 4 个 token；若真跑显示做不好，转候选（`advance` / `NextPromptOnly`）。
- LICENSE 未决（用户未授权选许可证，沿用 B9）。
- `tool\references\selftest-2026-11-25q.txt` 是红证据且删不掉，只能靠新后缀文件区隔；引用基线时要用 25p / 25r，别用 25q。