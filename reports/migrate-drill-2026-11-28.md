# R6 演练报告（只读，未改工具本体）

- 生成时间：2026-11-28 11:15:08
- 演练根目录：C:\Users\Duanyi\AppData\Local\Temp\relay-r6-drill-20261128-111458
- 被测产品文件（只读）：F:\soft\00selfmade\agentask-relay\tool\templates\relay-ledger.ps1（sha256 9331CE155AFA9DA1387D712C3376F111A509D7110CF5F6E8F2FFCC4BA2834062）
- 本报告只描述**夹具**上的实测结果：任何「改写」都发生在一次性临时目录里，没有碰任何真实仓库的台账。

## 结论速览

| 路线 | 结果 |
| --- | --- |
| 现状（不改产品） | 旧台账的阶段**关不掉**，`stage_done=1` 被拒；体检不报这个毛病，链视图还能照常显示 |
| 兼容读取（小改，~10 行） | 旧台账可以正常结项，且**不改动旧字段名** |
| 朴素兼容（易踩坑） | 数字撞车时会**关错阶段**，必须做两遍扫描 |
| 自动改名（写盘） | 今天的闸门**没有任何补丁能表达「改名」**，要自动改名必须新写一条路径并绕开只追加不变式 |

## 原始实测输出

```
DRILL_ROOT C:\Users\Duanyi\AppData\Local\Temp\relay-r6-drill-20261128-111458
PRODUCT gate sha256 9331CE155AFA9DA1387D712C3376F111A509D7110CF5F6E8F2FFCC4BA2834062
STEP_A_STATUS exit=0 | LEDGER_CHAIN current_stage=0 max_stages=2 cap_reached=false stages=1:pending,2:pending all_done=false open_stages=2
STEP_B_DOCTOR exit=3 | DOCTOR_VERDICT dangling findings=1
STEP_C_HINT exit=3
  MIGRATE_STATE path=C:\Users\Duanyi\AppData\Local\Temp\relay-r6-drill-20261128-111458\a-legacy\docs\relay.json sha256=6BB45038A6AB63871291662B6D9347DB9BE6542A28A9594784CD533921886E41 stages=2 max_stages=2
  MIGRATE_HINT scope=stage index=0 item=stage_key_not_id key=stage rename_to=id effect=commit_resolves_stage_done_by_id
  MIGRATE_HINT scope=stage index=1 item=stage_key_not_id key=stage rename_to=id effect=commit_resolves_stage_done_by_id
  MIGRATE_VERDICT suggested hints=2
STEP_D_COMMIT_TODAY exit=3 sha_same=True | LEDGER_FAIL reason=stage_not_found stage_done=1 hint=append_stage_first_or_use_an_id_already_in_the_ledger
STEP_E_PATCH_HITS hits=1 (expect 1)
STEP_F_ANCHOR_HITS hits=1 (expect 1)
STEP_F_NAIVE_LEGACY exit=0 | LEDGER_SESSION_REGISTERED session=sess-legacy-1 stage= source=ledger_next_session_id // LEDGER_COMMITED before=6BB45038A6AB63871291662B6D9347DB9BE6542A28A9594784CD533921886E41 after=612623570593C810F16CD260C3F6FA360F8BF289B96234EF311AA2067BBF7224 stages=2->2 sessions=0->1 notes=0->0 current_stage=0->0 path=C:\Users\Duanyi\AppData\Local\Temp\relay-r6-drill-20261128-111458\a-legacy\docs\relay.json
STEP_F_NAIVE_LEGACY stage1_status=done title=Legacy stage one keys=stage,title,status,finished_at
STEP_G_NAIVE_AMBIG exit=0
STEP_G_NAIVE_AMBIG legacy_title=Legacy stage one status=done | modern_title=Modern stage one status=pending
STEP_H_TWOPASS_AMBIG exit=0 | LEDGER_COMMITED before=56A2BCE1E34E0F8B109A6C3EC73655521094EE362D46FF8BD775C72E76359BDC after=D53E8A02489EF7479DC7E45E19A89036A6DA0B0FA4155E03482C991D83E0E8B9 stages=2->2 sessions=1->1 notes=0->0 current_stage=0->0 path=C:\Users\Duanyi\AppData\Local\Temp\relay-r6-drill-20261128-111458\b-ambiguous\docs\relay.json
STEP_H_TWOPASS_AMBIG legacy_title=Legacy stage one status=done | modern_title=Modern stage one status=done
STEP_I_TWOPASS_LEGACY exit=0 sha_changed=True | LEDGER_SESSION_ALREADY_REGISTERED session=sess-legacy-1 // LEDGER_COMMITED before=612623570593C810F16CD260C3F6FA360F8BF289B96234EF311AA2067BBF7224 after=6EDF291242DF440E563A363FDC00CE70E9938D1E2CED6FAE47376A3A792B900A stages=2->2 sessions=1->1 notes=0->0 current_stage=0->0 path=C:\Users\Duanyi\AppData\Local\Temp\relay-r6-drill-20261128-111458\a-legacy\docs\relay.json
STEP_I_TWOPASS_LEGACY stage1_status=done keys=stage,title,finished_at,status | stage2_status=pending title2=Legacy stage two
STEP_J_PROBE stage_done=9 exit=3 | LEDGER_FAIL reason=stage_not_found stage_done=9 hint=append_stage_first_or_use_an_id_already_in_the_ledger
STEP_K_RENAME_VIA_PATCH exit=3 sha_same=True | LEDGER_FAIL reason=stage_not_found stage_done=1 hint=append_stage_first_or_use_an_id_already_in_the_ledger
STEP_L_RENAME_PREVIEW { "status": "running", "current_stage": 0, "max_stages": 2, "next_session_id": "sess-legacy-1", "stages": [ { "id": 1, "title": "Legacy stage one", "status": "pending" }, { "id": 2, "title": "Legacy stage two", "status": "pending" } ], "sessions": [], "notes": [] }
```

## 追加：干净的歧义对照 + doctor / 链视图明细（均在一次性临时目录）

```
TWOPASS_AMBIG exit=0 legacy=Legacy stage one/pending modern=Modern stage one/done
NAIVE_AMBIG  exit=0 legacy=Legacy stage one/done modern=Modern stage one/pending
DOCTOR_LEGACY(current_stage=0) exit=3 DANGLING current_stage=0 stage_missing=0
DOCTOR_LEGACY(current_stage=1) exit=0
  DOCTOR_STATE path=C:\Users\Duanyi\AppData\Local\Temp\relay-r6-drill3-20261128-111639\docs\relay.json sha256=B124DCBBEAC1628DB4F22D8BE07F1DF65F02C5B9483F35FBAAD21A8790ACABE4 status=running current_stage=1 max_stages=2 stages=2 sessions=0 notes=0
  DOCTOR_VERDICT ok findings=0
STATUS_LEGACY(current_stage=1) exit=0
  LEDGER_STATE path=C:\Users\Duanyi\AppData\Local\Temp\relay-r6-drill3-20261128-111639\docs\relay.json sha256=B124DCBBEAC1628DB4F22D8BE07F1DF65F02C5B9483F35FBAAD21A8790ACABE4 status=running current_stage=1 max_stages=2 stages=2 sessions=0 notes=0 updated_at=
  LEDGER_CHAIN current_stage=1 max_stages=2 cap_reached=false stages=1:in_progress,2:pending all_done=false open_stages=2
COMMIT_LEGACY(current_stage=1) exit=3
  LEDGER_FAIL reason=stage_not_found stage_done=1 hint=append_stage_first_or_use_an_id_already_in_the_ledger
```
