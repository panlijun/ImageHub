# 第十八阶段：真实本机诊断与主动导出

2026-10-07。继续全部 90 条 Windows V1 目标，本阶段推进 OPS-002/003、SEC-004、UT-084/085/089 与 IT-006 子范围。没有新增依赖、安装、下载、系统配置、真实图床请求、提交、推送或发布。资源包只读保持原样，其他三端仍缺构建或设备环境。

## 实际能力及保护

设置中的“本机诊断”是共同 Flutter 页面。实际读取结构化 SQLite 日志，提供类型、级别、完整批次/尝试 UUID 筛选、数据库分页及计数、加载/空态/失败重试。数量和 UTF-8 内容字节数来自真实行；页面明确它不是 SQLite 文件物理空间。

失败批次与真实尝试记录均提供对应诊断入口，初始筛选直接进入同一SQL查询。读取尝试期间重复点击不会打开多个窗口；对话框实际结束后才进入诊断，替换/退出/销毁只关闭自有窗口，不授予网络权限。

schema8 新增 DiagnosticRecords，自身共27表，三个时间/批次/尝试索引。独立日志没有业务外键或级联删除。事件是严格 schema1 白名单 JSON，固定 UUID、UTC 毫秒、有限文案和不可变 JSON；未知格式、坏字节计数及索引/正文不一致拒绝读取、追加或导出，保留现场。新项目 schema1–7 升级到8；schema6/7存在恢复日志时，改动前拒绝升级。私有回滚快照包含诊断；成功替换保留本机日志；可携带备份不加入诊断。

导入、处理提交/停止、永久保存、账号配置/移除、上传状态与实际批次/尝试、设置保存、永久清除/输出到期、备份完成和恢复结果已接线。业务事件先在唯一写入门中收集，在业务事务结束后保存；诊断 SQL 故障不会回滚已经提交的业务，失败提示不递归记日志。恢复诊断在实际维护释放后保存，不能改动准备阶段的回滚基线。

FlutterError 与 PlatformDispatcher 生产入口只记录固定安全分类、摘要和恢复动作，不保留原始异常或堆栈，不调用未知对象 toString。资料库打开前最多保留100条固定事件；会话分离和关闭等待真实写入结束。它不能重建被排除的异常细节，也不代表所有未来诊断出口已验证。

日志在启动、写入、读取及可运行期间每分钟维护。30天边界包含恰好到期项，容量使用实际序列化 UTF-8 内容10,000,000字节，达到任一边界按 UTC/UUID 稳定顺序清最旧。不是数据库压缩或物理空间回收承诺。单事件64KiB、递归深度/节点/字符串限额为防护预算，性能仍待参考负载实测。

清理和导出计划绑定仓储 owner/epoch、明确筛选范围及全部已确认行。后来新增记录不加入，消失/篡改或旧会话拒绝执行；当前秘密引起的纯脱敏更新允许原范围继续执行。清理只删日志，保留任务、普通结果、秘密、资产和文件。

共同 SecretRedactor 先遮蔽真实注册值和敏感字段，诊断再排除图片/二进制、原始正文、秘密引用、完整外部路径以及 URL 查询和片段。查看和导出逐项读取本库已有秘密引用，不枚举其他应用；后端无法确认安全视图时拒绝导出。新秘密注册后事务重新遮蔽持久诊断，身份冲突拒绝，不把被遮蔽的 UUID 改成另一身份。

导出前列明数量、范围和排除项，用户确认后通过平台目录入口写 JSON，不外发。暂存 JSON 独立私有目录、关闭/flush后交给共同 FileExporter 独占创建/同名避让/摘要读回。取消等待实际 IO 收尾；仅清除内容证据仍匹配的自有文件和空目录，未知子文件或篡改保留。已确认的用户文件不会因暂存清理失败改报未保存，清理问题单独反馈。Android/iOS原生导出未接入而禁用，macOS配置不等于实测。

## 修改文件

新增生产文件：`app/lib/features/diagnostics/domain/diagnostic_models.dart`、`application/diagnostic_sanitizer.dart`、`application/diagnostic_runtime.dart`、`application/diagnostic_exporter.dart`、`presentation/diagnostics_screen.dart`、`app/lib/features/gallery/data/library_diagnostics.dart`。

修改生产接线：`library_database.dart`及真实生成的`library_database.g.dart`；`library_repository.dart`、`library_accounts.dart`、`library_outputs.dart`、`library_uploads.dart`、`library_recycle.dart`、`library_settings.dart`、`library_replacement_snapshot.dart`、`library_replacement_restores.dart`；`gallery_providers.dart`、`settings_screen.dart`、`upload_tasks_screen.dart`、`backup_coordinator.dart`、`restore_coordinator.dart`、`backup_screen.dart`和`main.dart`。

新增测试：`diagnostic_sanitizer_test.dart`、`diagnostic_runtime_test.dart`、`diagnostic_schema_migration_test.dart`、`diagnostic_repository_test.dart`、`diagnostic_exporter_test.dart`、`diagnostics_screen_test.dart`、`integration_test/diagnostics_flow_test.dart`。关联迁移、私有快照/回滚、成功替换、链接/任务页面测试按真实新增日志和当前 schema 更新；不放宽原业务/字节/秘密断言。

主线程阅读实际实现与生成结果；三位 Sol 子代理（gpt-6.1-sol/high）分工领域、schema、UI及一位Sol编写仓储验证。全部 Flutter/native 命令由主线程串行执行，不仅凭子代理总结验收。

## 验证记录

- 真实生成：51秒，见 [生成日志](validation/windows-diagnostics-generation.log)，未手写生成代码。
- 初轮51项核心重测通过，12秒，见 [核心](validation/windows-diagnostics-core-retest.log)。新增默认10MB真实内容和后端拒绝视图用例随后加入全量验证。
- 诊断/导出与设置回归27项通过，16秒，见 [界面](validation/windows-diagnostics-ui-tests.log)。包含320大字、冻结范围、真实导出、确认窗口退出/销毁及实际IO退出。
- 任务页6项专项重测通过，11秒，见 [导航](validation/windows-diagnostics-task-ui-final.log)；最终全量还验证重复点击只打开一个自有窗口，batch/attempt精确范围包含自动业务事件且不授网。
- 最终752项现有单元与widget混合测试通过，72秒，见 [全量](validation/windows-diagnostics-full-pass.log)。这不是752个正式UT或90条需求通过。
- 最终格式173文件0改动，见 [格式](validation/windows-diagnostics-format-check.log)；整app分析无问题，9秒，见 [静态](validation/windows-diagnostics-analyze-final-pass.log)。
- Windows IT-006子闭环1项通过，最新Debug26.9秒/运行4秒，见 [最终原生](validation/windows-diagnostics-integration-pass.log)及 [截图](validation/windows-diagnostics.png)。真实SQL、正常重开、会话秘密后注册/持久遮蔽、独立JSON、清日志与PNG字节保留。截图为测试入口默认Material主题的真实组件页面；系统目录选择器由测试入口替换，不代表PT-003通过。
- 资源包31文件/56本地引用完整性通过，见 [资源](validation/windows-diagnostics-kit.log)；全部90条V1属性、必需行为、验收原文保留，见 [台账完整性](validation/windows-diagnostics-coverage-integrity.log)。这两项不是软件测试。
- Windows IT-005备份/合并恢复回归1项通过，Debug26.7秒/运行6秒，见 [备份回归](validation/windows-diagnostics-backup-regression.log)。数据库增加诊断表后仍验证真实空间、独占ZIP、秘密排除、合并与重开；不是完整IT-005或PT验收。
- Windows Release51.0秒成功，见 [构建](validation/windows-diagnostics-build.log)；仅启动本次自有隐藏runner并正常WM_CLOSE退出0，见 [运行](validation/windows-diagnostics-release-smoke.log)。没有安装包、签名、发布或真实HTTP请求。

保留全部首轮失败日志：URL公共脱敏插入空格后诊断解析遗留查询尾部，已修正并保持严格秘密排除断言；新诊断错误事件导致成功替换测试追加一行，改为原行完整保留加真实新增错误断言；旧schema3/4/5夹具误留未来表，修正夹具而没有使生产迁移容忍未来结构；链接测试在真实收尾前调用禁用回调，改为等待实际可操作状态；原生测试反馈在惰性列表滚走位置，按真实视图定位。未把失败包装成通过，SQLite多实例debug提醒保持原样。

任务导航新增测试的同名DiagnosticLevel导入冲突已明确排除；按实际惰性列表滚动、等待旧route真正移除后定位自有对话框，精确范围数量以真实SQL包含自动业务事件校验，不再假定只有手动合成一条。失败日志仍保留，最终全量通过。

## 未完成范围

完整Windows首版仍未完成。缓存容量/分类空间管理、网络及计费观察、单项暂停、远端删除、自动处理依赖、完整服务契约/明确授权联调、参考负载性能和完整人工平台验收仍待推进。本阶段日志不等于全部未来事件覆盖；四端性能、真实系统目录PT与三端原生导出/设备验收未执行。不得以测试数代替90条正式需求完成数。
