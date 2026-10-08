# 里程碑23：可携带设置与可用项恢复

日期：2026-10-07。完整 Windows V1 目标保持 active，本阶段不代表首版全部验收。

## 实际规则

补齐 BAK-005 的设置路径；需求规定只恢复当前平台可用项并报告跳过。可携带 Manifest 升为格式2，明确读取本项目之前生成的格式1；旧包没有设置时保留本机值。未知版本、缺少格式2的设置字段、未知字段或畸形值拒绝，不隐式默认覆盖。资源包原件及90条需求原文不改，不涉及旧应用源码或旧数据库。

两种备份都携带当前已实现的八项设置：上传/处理并发、有损质量、体积优先最长边、处理模式、缓存上限、临时输出默认保留、允许上传的网络类型。每项有严格四端适用范围；当前生产导出的这八项共同设置适用于全部声明平台。包内明确不适用的项跳过并保留本机值，没有虚构一个尚未实现的平台设置。设置不携带设备路径、凭据、删除秘密、默认目标选择或会话上传许可。网络仍按用户最新决定只识别类型，不判断计费。

## 提交与数据保护

导出在原有写入门和同一SQL快照中读取严格有效的本机设置；随后改设置不会改变已取得的备份字节。仍先读取本库拥有的秘密并注册脱敏；设置枚举或数字与秘密相撞时拒绝出包，不改写结构值或把秘密带出。

合并和替换的准备对象持有不可变设置提议和确认时当前值。准备时读取实际SQL，损坏或与已加载有效状态不一致时拒绝。建立恢复日志前核对，关联提交事务再次核对；设置与图库关系在同一事务写入，失败/取消一并回滚。只有确认提交后才更新内存策略、共同处理调度器和settingsChanges；现有会话订阅更新后续上传并发/网络类型策略，不授予许可，也不改变被冻结的输入与处理参数。

替换仍先证明内部快照实际可恢复；失败回滚保留旧设置，成功恢复可用备份值并切换执行epoch，使旧设置快照失效。旧格式1包及全部不可用项保留本机对应值。默认合并保留当前默认目标身份，备份账号仍禁用待配置，历史不成为执行意图。数据库仍为schema10/28表，不新增表、依赖或软件安装。

桌面A与M1使用同一个恢复页：确认前列出将覆盖的具体值、跳过名称及保留规则；提交后显示实际恢复/跳过计数。取消、失败、清理未完成、关闭等待等继续沿用原有真实恢复边界。

## 修改文件

- 新增领域契约 `app/lib/features/backup/domain/backup_settings.dart`；修改Manifest与纯合并恢复规划。
- 修改 `library_repository.dart` 的导入、`library_backups.dart` 的SQL快照、`library_settings.dart` 的设置计划/持久提交/运行策略、`library_restores.dart` 和 `library_replacement_restores.dart` 的关联事务与报告。
- 修改共同 `backup_screen.dart`，增加确认及提交反馈中的设置说明。
- 新增 `test/core/backup_settings_test.dart`、`backup_settings_repository_test.dart`、`test/backup_settings_screen_test.dart`；更新既有 `backup_manifest_test.dart`、`backup_replace_restore_repository_test.dart`、`settings_repository_test.dart`、`link_probe_repository_test.dart` 和Windows `integration_test/backup_flow_test.dart`。模型、仓储、界面/原生三个子任务均显式Sol（gpt-6.1-sol/high），主线程阅读实际源码并完成接线、审查与串行验证。
- 更新根AGENTS、两份README、架构、环境与90条覆盖台账。无Git初始化、提交、推送、发布或真实外部请求。

## 验证记录

- 格式/契约首轮25通过1失败：[首次契约](validation/windows-backup-settings-contract.log)。发现格式2缺少nullable settings键会被视为null；主线程补必须存在键的严格校验，未放宽断言。设置/Manifest/纯恢复规划/真实快照/ZIP读写专项64项通过，4秒：[基础专项](validation/windows-backup-settings-foundations.log)。
- 真实合并/替换/设置仓储首次51通过1失败，22秒：[首次仓储](validation/windows-backup-settings-repository.log)。失败是测试误将结构秘密冲突的BackupFailure写为BackupSnapshotFailure；修正为严格BackupFailure.invalidManifest，继续验证拒绝出包且不改SQL/运行策略。
- 生产源码首次分析1项错误：[首次生产分析](validation/windows-backup-settings-lib-analyze.log)。确认回调改为显式使用实际持有恢复保护的session，修正未定义会话字段。全app首次分析2条测试样式提示：[首次全分析](validation/windows-backup-settings-analyze.log)，移除重复导入、补控制语句花括号，最终结果另列。
- 新仓储及新/既有恢复页面专项48项全部通过，84秒：[页面/仓储专项](validation/windows-backup-settings-ui-repository.log)。含新真实仓储16项、新widget7项、390/1280宽度及2倍字号；真实取消、风险确认、旧包保留、不适用质量保留91、覆盖/跳过具体值、成功关库重开均有断言。窗口尺寸不能代替手机实机。
- 首次全量958通过3失败，113秒：[首次全量](validation/windows-backup-settings-full.log)。两处既有链接测试仍固定格式1、一处设置测试仍假定包不含设置；更新明确的新格式2/快照值及冻结断言，保留本机链接观察不携带、已存在处理输入不受新默认影响，并补捕获后保存不改包。
- 当前完整unit/widget全量961项全部通过，112秒：[最终全量](validation/windows-backup-settings-full-final.log)。本轮新增核心24项（设置模型6、Manifest2、真实仓储16）和widget7项已包含在961内；不能将专项重复累加或视为961个完整正式UT通过。完整90条软件验收数量不因此增加。
- Windows真实引擎子流程1项通过，Debug42.1秒/运行6秒：[原生](validation/windows-backup-settings-native.log)。两种实际ZIP、真实容量/独占发布、系统合成秘密写入/排除、合并/替换设置、metadataWritten失败回滚、正常重开、当前生产确认与无会话许可均执行。Drift多实例debug警告原样保留，不是共用同一连接，不压制警告。
- [实际设置确认截图](validation/windows-backup-settings.png)由上述Windows引擎运行生成，主线程已查看，八项实际快照值均可见。系统目录/备份选择器使用受控入口，不能声称真实选择器PT-003完成；截图只是当前视口。
- 当前206文件格式0改动，1.78秒：[格式](validation/windows-backup-settings-format-check.log)；完整app最终静态分析无问题，6.0秒：[分析](validation/windows-backup-settings-analyze-final.log)。
- 当前Windows Release构建成功，68.3秒：[构建](validation/windows-backup-settings-build.log)；只启动本轮自有隐藏Release实例，确认窗口归属后正常WM_CLOSE、退出0：[启动退出](validation/windows-backup-settings-smoke.log)。未签名、打安装包、安装或发布。
- 资源包31文件/56本地引用及90条V1需求原文完整性通过：[资源包](validation/windows-backup-settings-kit.log)、[台账](validation/windows-backup-settings-coverage.log)。文档更新后终验另写同日志；完整性检查不是软件测试。

四平台纯规划不代表四设备互读。Android仍缺SDK/设备，macOS/iOS仍缺Mac/Xcode/设备；Windows系统选择器、完整CT-006/PT-005/AT-005、大包、硬件强退及性能验收仍需补证。下一阶段继续远端删除、服务契约和经授权的实际联调，以及完整Windows首版验收。
