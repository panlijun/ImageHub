# 里程碑22：上传前自动处理依赖

日期：2026-10-07。Windows完整V1目标继续active，本里程碑不代表全部90条首版验收完成。

## 业务与实现

按UPL-001/002/003/004、QUE-007、UT-033/046/062和IT-004执行。没有修改资源包规则。手机M1和桌面A复用共同页面与处理业务；网络仅识别类型，按用户本日决定不实现计费状态。本地像素处理和已确认图床任务自动继续均不增加图库云同步。

默认“上传前自动处理”，确认入队时冻结资产、完整版本、帧、参数、目标UUID和保留期。处理工作台已有ready结果仍可直接选择；原图需单独隐私确认并新建任务。同批有序版本与像素策略共享一份实际结果，固定版本×目标发布项不因尝试增加；就绪B不等待A，A失败只跳过依赖，暂停项保持暂停到明确继续。动画/颜色不能保真或透明JPEG背景未确认时明确失败，不回退原图。

schema10的UploadProcessingJobs及发布项processing_job_id持久关联计划、实际输出和状态。先记录输出身份，再启动真实线程；只有文件摘要/长度和ready状态验证成功才关联processed输入。派发写入门在处理未解决时拒绝创建尝试，不读取原图。成功复用按稳定目标和完整冻结策略核对普通结果，deleted排除复用；unknown不自动重传，也不被其他目标的新处理完成或失败覆盖。明确forceAgain才创建新意图。

输出意图与job输出保护在同一事务登记，处理ready到发布关联的间隙也不能被到期清理；确认事务把保护交给各发布项，失败或重排在实际IO结束后释放旧输出保护。恰到期测试使用真实像素/SQL/文件与注入UTC，不能当硬件时间跳变或平台性能证明。

UploadProcessingCoordinator与网络actor独立、由LibrarySession拥有，使用共同ProcessingScheduler预算。来源在实际线程途中变化时，先完成输出收尾、真实输入租约及预算释放，再将任务置等待修复；修复相同冻结内容后需明确重试。关闭/恢复同步阻止新claim，恢复先持久暂停批次再等待真实工作结束。释放维护不恢复批次或网络许可；旧epoch对象不能写新会话。

启动可直接关联已ready但日志未收尾的同一输出；其他局部像素工作按原计划重执行，没有远端副作用推断。全部依赖取消的旧运行日志退休并释放任务引用。取消终态但真实线程仍活跃时禁止清完成历史和导出完成审计；迟到ready可保存独立输出，不改变取消终态。

自身schema1–9升级至10，schema6–9存在恢复日志先拒绝修改，原结构/身份/证据保留。私有替换快照及实际回滚覆盖28表。可携带formatVersion1仍是原白名单，不导出job、执行参数、设备路径或活动意图；失败/取消仅是审计，不是已上传原图的证据。不兼容旧应用，不读取旧项目。

## 修改范围

生产：新增`upload_processing_models.dart`、`upload_processing_coordinator.dart`、`library_upload_processing.dart`；修改处理coordinator、上传coordinator/模型、资料库数据库及真实生成文件、仓储/上传/回收/备份/历史、私有快照与回滚、LibrarySession和任务页。领域、执行、持久化与文件保护分别位于原有边界，不增依赖或软件安装。

测试：新增模型、schema、真实仓储、真实actor、共同widget和Windows引擎集成6个测试文件；更新自身schema降级夹具、28表回滚断言和默认入口空态。Sol（gpt-6.1-sol/high）完成明确范围的复杂实现和边界测试，Luna（gpt-6-luna/high）机械更新迁移样本，主线程阅读实际源码并串行执行验证。未初始化Git、提交、推送、发布、开通服务或真实HTTP上传/删除。

文档：根AGENTS、两份README、架构、环境、90条台账及本记录。原资源包保持不变。

主要源文件（均在`app/`）：

| 范围 | 文件 |
| --- | --- |
| 领域与执行 | `lib/features/upload/domain/upload_processing_models.dart`、`upload_queue_models.dart`；`lib/features/upload/application/upload_processing_coordinator.dart`、`upload_coordinator.dart`；`lib/features/processing/application/processing_coordinator.dart` |
| 资料库与恢复 | `lib/features/gallery/data/library_database.dart`、`library_database.g.dart`、`library_repository.dart`、`library_upload_processing.dart`、`library_uploads.dart`、`library_recycle.dart`、`library_backups.dart`、`library_upload_history.dart`、`library_replacement_snapshot.dart`、`library_replacement_rollback.dart` |
| 共同会话与页面 | `lib/features/gallery/presentation/gallery_providers.dart`；`lib/features/upload/presentation/upload_tasks_screen.dart` |
| 新验证 | `test/core/upload_processing_models_test.dart`、`upload_processing_schema_test.dart`、`upload_processing_repository_test.dart`、`upload_processing_coordinator_test.dart`；`test/upload_processing_screen_test.dart`；`integration_test/upload_processing_flow_test.dart` |
| 既有测试夹具 | `test/core/restore_schema_recovery_test.dart`、`output_schema_migration_test.dart`、`diagnostic_schema_migration_test.dart`、`upload_item_pause_repository_test.dart`、`upload_repository_test.dart`、`replacement_rollback_test.dart`、`link_probe_repository_test.dart`；`test/upload_tasks_screen_test.dart` |

## 实际验证与边界

- 真实build_runner成功，19秒，265个生成输出：[生成](validation/windows-processing-upload-generate.log)。没有手写生成代码。
- 新共同widget4项通过，22秒：[页面](validation/windows-processing-upload-widget-first.log)。390/1280宽度、2倍字号、真实PNG处理、多目标UUID、草稿不受后改默认影响，透明JPEG/动画失败不回退，零网络请求。不是Android/iOS实机。
- Windows真实Flutter引擎自动处理/任务页面/同身份重开1项通过，Debug36.8秒/运行3秒：[原生](validation/windows-processing-upload-native-first.log)、[真实当前视口](validation/windows-upload-processing.png)。真实透明PNG保留alpha，只有一个ready输出，任务仍等待本次会话网络许可，零尝试/普通结果；主线程已查看截图。不是系统选择器、真实图床或硬件强退。
- schema10相关Windows真实容量、独占ZIP、两模式合并/替换、失败回滚、合成系统秘密及重开回归1项通过，Debug36.8秒/运行6秒：[备份恢复回归](validation/windows-processing-upload-backup-native.log)。既有Drift重复构造Debug提示保留，未压制警告；不代表并用同一连接。
- 首次分析17项、第二次2项问题已修正：可空结果处理、实际设置字段、重复多行分支括号和稳定Drift隔离异常导入；第三次分析无问题40.8秒：[第三次分析](validation/windows-processing-upload-analyze-third.log)。后续补强代码以最终分析为准。
- 早期基础专项40通过6失败、49通过4失败均保留。失败为旧样本新增列差异及后台Drift异常包装断言；修正严格类型/固定消息后schema+仓储21项通过。原证据完整断言保留，不将失败日志计通过：[第一次](validation/windows-processing-upload-foundations-first.log)、[第二次](validation/windows-processing-upload-foundations-second.log)、[第三次](validation/windows-processing-upload-foundations-third.log)。
- 首轮全量909通过5失败，81秒：[首轮全量](validation/windows-processing-upload-full-first.log)。两项旧schema6夹具未移除新表/列，三项大字号空态仍按旧默认入口断言；已更正夹具并验证自动空态后显式切换已有结果，保留原隐私、零请求和布局异常检查。最终全量另列。
- 模型/actor/schema与相关链接迁移、任务页面边界56项通过，36秒：[保护边界](validation/windows-processing-upload-boundaries.log)。包含真实worker途中字节变化、等待修复/明确重试、8项版本字段及帧顺序不混用、旧格式拒绝/迁移和大字号空态。
- 首次扩展仓储14通过1失败，6秒：[扩展首次](validation/windows-processing-upload-receipts.log)。失败夹具的deleted观察缺少必要generation，生产严格读取拒绝；已补完整有效观察，未放宽生产保护。最终验证另列。
- 最终输出保护及unknown隔离后的Windows原生复验1项通过，Debug44.8秒/运行3秒：[最终原生](validation/windows-processing-upload-native-final.log)。当前截图由此运行生成并由主线程查看，之前36.8秒属于早期版本。
- 当前最终全量930项现有unit/widget混合测试全部通过，118秒：[最终全量](validation/windows-processing-upload-full-final.log)。本轮新增核心47项（模型12/schema14/真实仓储16/真实actor5），widget4项均包含在930内，不能与专项重复累加成正式UT通过数。包含恰到期job→发布项保护交接、未知与新目标混合成功/失败不改证据、deleted合法观察排除和明确forceAgain。
- 当前最终202文件格式0改动、3.30秒：[格式](validation/windows-processing-upload-format-check.log)；整app分析无问题、34.3秒：[分析](validation/windows-processing-upload-analyze-final.log)。
- 最终Windows Release72.2秒构建成功：[构建](validation/windows-processing-upload-build.log)。没有安装包、签名、发布或真实图床联调。
- 只启动本轮自有隐藏Release runner，实际创建原生窗口，请求正常WM_CLOSE并退出0：[启动退出](validation/windows-processing-upload-smoke.log)。没有强杀其他进程；这仅证明正常原生启动/退出，不代替完整人工窗口验收。
- 资源包31文件/56本地引用及90条V1规范原文完整性通过：[资源](validation/windows-processing-upload-kit.log)、[台账](validation/windows-processing-upload-coverage.log)。这是文档完整性检查，不是软件测试。

Android仍缺SDK/设备，macOS/iOS缺Mac/Xcode/设备；共同Dart业务及M1源码接线不能报告这些平台已构建或可运行。实际服务精确字节/格式能力仍unknown，生产请求保持等待；受控响应保存不能当作远端成功证据。硬件断电、设备后台、真实服务CT/IT-008、完整人工AT与预算PERF仍待补证。下一阶段继续远端删除、服务契约与授权联调、跨平台设置转移及完整Windows首版验收。
