# 恢复合并规则与上传侧维护保护

日期：2026-10-06。接续真实备份导出和预检。此阶段完成共同业务规则及上传侧保护，尚未实现实际恢复提交，Windows 完整 V1 目标继续保持进行中。没有新增安装、系统配置、外部服务请求、提交、推送或发布。

## 已实现及实际边界

- BackupMergePlanner 是纯 Dart 永久版本/资产/分类/标签计划。按 SHA-256 与字节数复用版本；相同内容描述矛盾阻止提交。同身份异内容保留当前内容并以稳定 UUIDv5 派生恢复身份，重复应用同包不重复新增；已有独立永久版本保留。
- 资产同内容异身份复用当前资产并给出资产及版本映射；同身份异内容优先保留独立恢复身份。已有多个内容相同资产时按稳定 UUID 选择，同身份同内容优先。按 Unicode 17 规范名称合并标签/分类目录，保留当前拼写及非空名称/分类；收藏取真，当前回收状态、来源与时间保留，新增资产保留备份回收状态。
- BAK-004 的标签并集可能超过 LIB-003 每项 50 个标签限制。当前采用保留原值并阻止整个计划提交的保护，不静默截断、不扩大限制；报告具体规则编号，后续恢复界面仍需给用户可操作的冲突处理。
- BackupResultMergePlanner 接收已校验且已重映射的普通确认结果。独立尝试同 URL 保留两份；稳定结果身份或确认尝试身份重复且内容一致才复用；身份与内容冲突只拒绝该关联并报告，保留当前有效结果，不将两个确认历史融合。它不做来源/账号重映射，不恢复管理秘密，不持久化结果。
- UploadRestoreHold 立即阻止新派发并撤回运行授权，持久暂停当前非终态批次，等待已经开始的派发准备、实际尝试、结果关联及租约释放完成。不能确认收尾时仍保持阻断且不返回成功保护；暂停写入失败可重试。释放保护不自动取消暂停或恢复网络许可。派发授权返回后再次复核取消/维护状态，取消后不新调用适配器。

纯合并计划不是已完成恢复；来源、历史、账号、永久字节仍没有恢复提交。上传侧保护不能替代资料库的全部写入屏障；当前普通导入、处理、账号等写入未被它统一冻结，不能在此基础上直接执行替换。

## 验证记录

| 类别 | 实际结果及范围 | 日志 |
| --- | --- | --- |
| UT-076/077 子范围 | 26 项通过，纯永久元信息计划、幂等、UUID 冲突、Unicode/50 与 51 标签、回收及孤立版本；非真实提交 | [合并计划](validation/windows-backup-restore-persistence-tests.log) |
| UT-078 子范围 | 7 项通过，同 URL 独立确认、重复事件、稳定结果/尝试冲突；输入已重映射，不代替关联重映射验证 | [结果规则](validation/windows-backup-result-merge-tests.log) |
| UT-079 上传侧 | 4 项新受控调度验证通过，含在途结果提交、派发准备、暂停失败重试、收尾不确定拒绝；连同原 8 项调度及 7 项结果测试共 19 项通过 | [调度专项](validation/windows-backup-restore-gate-tests.log) |
| UT-079 真实存储子范围 | 1 项通过，真实 SQLite/永久文件/实际流读取，受控在途响应，租约未早释放，重开待执行批次仍暂停；没有真实图床请求。调整真实流读取及等待后单项再次通过 | [存储专项](validation/windows-backup-restore-persistence-tests.log)、[最终单项](validation/windows-restore-final-persistence.log) |
| 全量 | 382 项通过，2 分 36 秒；含既有图库/处理/账号/上传/备份界面回归。之后只调整一项存储测试的关闭方法、等待及实际流读取，并再次通过该项；生产代码未再变化 | [全量](validation/windows-restore-plan-full-tests.log) |
| 静态/格式 | 最终 Dart analyze 无问题；109 个文件格式检查 0 改动 | [静态](validation/windows-restore-plan-analyze.log)、[格式](validation/windows-restore-plan-format.log) |
| Windows 原生 IT-004 子流程回归 | 1 项通过，3 秒；Debug 构建 26.7 秒。真实永久文件、SQLite、系统合成凭据、受控上传及重开，未请求图床 | [原生日志](validation/windows-restore-plan-upload-integration.log) |
| Windows Release | 当前源代码构建通过，44.5 秒；真实原生窗口创建并正常 WM_CLOSE 关闭，退出码 0 | [构建](validation/windows-restore-plan-release.log)、[启动退出](validation/windows-restore-plan-release-smoke.log) |
| 输入/台账完整性 | 31 个资源文件、56 本地引用通过；90 条 V1 属性/行为/验收原文保留。两项都不是软件测试 | [资源](validation/windows-restore-plan-kit-integrity.log)、[台账](validation/windows-restore-plan-coverage-integrity.log) |

当前测试数量包含参数化，不等于正式 UT 或首版条款完成数。取消收尾以受控适配器验证，不冒充真实网络/系统强退；真实存储用全新临时库，外部来源和旧项目数据未访问。静态检查首次发现新测试的弃用关闭方法与缺少花括号，已修正。

## 修改文件

- 新增 `app/lib/features/backup/domain/backup_merge_plan.dart`、`backup_result_merge.dart`，及对应两份 core 测试。
- 修改 `app/lib/features/upload/application/upload_coordinator.dart`、`app/test/core/upload_coordinator_test.dart`；新增 `app/test/core/backup_restore_gate_test.dart`。
- 更新根 AGENTS、架构、环境、V1 台账及阶段记录。没有修改数据库 schema 或生成文件，没有改变资源包。

Sol 子代理以实际参数 `gpt-6.1-sol`、`high` 实现合并计划和测试；主线程阅读实际代码、确定身份/规范名优先级并执行所有 Flutter 测试。结果合并、上传保护及真实存储验证由主线程完成。

## 继续实施

需要将不可执行恢复历史、账号重配、路径无关来源及关联映射接入持久层；维护期间排空并冻结全部真实写入，计划提交前复核当前库。完整模式用持久恢复日志保管并验证永久字节；元数据模式没有本机副本，不能假报可处理。替换另需真正可恢复的内部当前快照、单独确认、库执行代次与迟到事件隔离及故障回滚。

当前恢复按钮仍禁用。只有上述实际提交及故障验证通过，才启用恢复成功路径。三端仍缺原生导出/空间/发布适配及设备条件，不能报告可运行；四端 DTO 与规则从共同业务层建立。
