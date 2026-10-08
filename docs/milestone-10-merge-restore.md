# 实际合并恢复

日期：2026-10-06。Windows 完整 V1 目标继续进行，默认合并恢复已接入生产持久层和桌面/M1 共用页面。此阶段无新增软件安装、依赖、大型下载或真实图床请求；资源包原件不变，无 Git 初始化、提交、推送或发布。

## 实现范围

- 对永久元信息、无路径来源、账号和冻结目标、普通结果、终态历史统一重映射。相同 URL 的独立确认保留；冲突关联拒绝并列明；内容描述矛盾和标签并集超过 50 阻止提交。当前活动尝试及临时处理输出身份不能误绑定备份确认或来源。
- schema 6 独立保存恢复来源、不可执行历史及恢复操作日志；1–5 的本项目格式迁移保留原资料。导入账号禁用、待重配且无秘密；普通链接没有导入管理秘密或删除能力。
- 在预检后，暂停上传并排空实际 IO，再冻结资料库的新普通读写。确认等待期间也保留两层保护；拒绝或取消不恢复批次/网络权限。只通过本库维护保护调用私有提交，持久任务引用继续保护坏副本修复。
- 完整模式重新复制、校验摘要/大小/真实像素、用平台独占发布到本设备管理位置；全部关联和 committed 日志在一笔 SQLite 事务确认。元数据模式创建 missing 副本，不能伪报图片可用；后续完整模式修复保持副本 UUID。
- 提交前失败/取消保持有效元信息，按持久日志回收确认归属的半成品。日志全部位置先验证再删除；发布归属不确定保留现场待核查。关闭等待真实恢复 IO 和清理结束后才释放根锁。提交后回调失败/迟到取消不撤销已确认成功。
- 去敏视图不能写回已有本机资产名、分类、标签、账号或时间来源；新导入条目仍用去敏可携带内容。恢复后可关闭重开、重复合并及再导出，来源/历史不丢失。
- Windows 页面可选 ZIP，预检后展示模式、实际数量及分页冲突，默认合并需要确认；阻断计划没有成功按钮。取消/退出/销毁会完成等待确认并继续等待实际收尾，完成后刷新现有会话相关视图。替换按钮保持禁用。

## 实际验证

| 类型 | 实际结果及边界 | 日志 |
| --- | --- | --- |
| UT 关系/原规则回归 | 初轮 48 项通过；后补活动尝试和临时输出身份保护在最终全量通过。纯计划不替代设备验证 | [专项](validation/windows-restore-relations-tests.log)、[最终全量](validation/windows-merge-restore-full-tests.log) |
| UT/IT 子范围真实仓储 | 专项 13 项通过；增加去敏本机名称保护及事务取消边界后，当前 14 项在最终全量通过。真库→ZIP→预检→提交→重开→再备份，故障注入不是硬件断电 | [专项](validation/windows-merge-restore-tests.log)、[全量](validation/windows-merge-restore-full-tests.log) |
| UT-093/IT-006 及日志子范围 | 2 项通过：schema 5→6 原表/身份/凭据/暂停意图完整保留；后续损坏日志不得造成前一项半清理或删外部字节 | [迁移与日志](validation/windows-restore-schema-recovery-tests.log) |
| widget 子范围 | 专项 14 项通过；新增 ZIP 选择取消后，当前 15 项在最终全量通过。真实 ZIP、确认前无新资产、确认后可用副本、取消/销毁/阻断、missing、390 宽/1.6 倍文字及旧备份回归 | [专项](validation/windows-merge-restore-ui-tests.log)、[全量](validation/windows-merge-restore-full-tests.log) |
| 全量 | 420 项通过，1 分 5 秒。首轮一项旧迁移夹具断言 schema 5 失败，保留日志；夹具移除全部新表并改为当前版本断言后完整重跑 | [最终](validation/windows-merge-restore-full-tests.log)、[首轮](validation/windows-merge-restore-full-tests-initial.log) |
| 格式/静态/生成 | 116 个文件格式检查 0 改动，整 app analyze 无问题；实际 build_runner 生成 schema 6，未手写生成文件 | [格式](validation/windows-merge-restore-format.log)、[静态](validation/windows-merge-restore-analyze.log)、[生成](validation/windows-restore-schema-generation.log) |
| Windows 原生 IT-005 子流程 | 1 项通过，运行 3 秒/Debug 构建 41.9 秒。实际空间/MoveFileExW 无覆盖发布，两模式导出及全新库恢复重开，受保护合成秘密排除、账号禁用、真实恢复界面确认与幂等。系统选择器用受控选择器替换，非完整 PT/AT | [原生](validation/windows-merge-restore-integration.log)、[实际截图](validation/windows-backup-merge-restore.png) |
| Windows Release | 当前代码构建通过，56.7 秒；隐藏自有原生窗口创建并正常 WM_CLOSE，退出码 0 | [构建](validation/windows-merge-restore-release.log)、[启动退出](validation/windows-merge-restore-release-smoke.log) |
| 输入/台账 | 31 资源文件、56 本地引用完整；90 条 V1 属性/业务/验收原文保留 | [资源](validation/windows-merge-restore-kit-integrity.log)、[台账](validation/windows-merge-restore-coverage-integrity.log) |

主线程已阅读实际截图：1267×685 桌面恢复提交状态，按钮/文案无溢出。多独立资料库夹具触发 Drift 的 debug 多实例提醒，各实例分别使用目录和 executor；没有隐藏提醒或共享同一活跃数据库执行器。没有请求图床、枚举其他应用凭据或读取旧项目。

资源检查不是软件测试，测试数量含参数化而非 420 个正式 UT 或 90 条完整验收。窗口正常关闭也不能替代系统强退、断电及完整设备生命周期验证。

## 修改文件

生产：`backup_restore_plan.dart`、`backup_merge_plan.dart`；`library_database.dart` 及实际生成的 `library_database.g.dart`；`library_repository.dart`、`library_restores.dart`、`library_backups.dart`、`library_outputs.dart`、`library_recycle.dart`、`library_uploads.dart`；`restore_coordinator.dart`、`backup_import_gateway.dart`、`backup_screen.dart`。

验证：恢复计划、真实合并仓储、schema/恢复日志及备份页面测试；现有迁移版本断言/夹具和 Windows `backup_flow_test.dart`。更新根约定、README、架构、环境、V1 台账及本记录。

Sol 子代理的实际参数均为 `gpt-6.1-sol` / `high`：分别实现关系计划、真实仓储验证和界面接入；主线程阅读实际代码、处理维护/退出/去敏/活动身份边界并验收。没有使用 Luna 或 Astra。

## 尚未闭合

替换恢复需要真正可恢复的内部当前快照、单独确认、旧执行意图取消、执行代次隔离及故障回滚，尚未实现。当前合并不等于完整 BAK-004 或完整 V1。发布归属不确定的日志保留待核查，尚无完整诊断修复界面；大包/大量数据性能及完整 PT/AT/CT/硬件断电没有通过证据。

Android SDK/设备、Mac/Xcode/Apple 设备缺失；三端原生空间/独占发布/备份选择导出及设备生命周期未验收。共享领域/仓储和 M1 页面存在，不代表三端可运行。其余链接管理、持久设置/诊断、网络观察和完整队列依赖仍按 90 条台账推进。
