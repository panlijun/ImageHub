# 第十五阶段：完成历史清理

2026-10-06。Windows 完整 V1 目标持续有效；本阶段落实 QUE-010 的明确范围清理和恢复历史查阅，不等于全部 90 条正式验收完成。资源包及旧应用均未改动，没有 Git 初始化、提交、推送或发布，没有 HTTP 请求。

## 实际行为

桌面和 M1 复用 UploadTasksScreen。可逐项选择本机/恢复历史，或主动选择当前已加载的结束记录；确认页列出可清项、保留项及原因。新增完成项不会自动加入已确认范围。关闭确认、关闭页面或系统退出不构成清理授权；退出先解决确认等待，再等待实际事务结束。

共同仓储只清明确指定的 succeeded/failed/cancelled 本机项与严格终态的恢复审计。queued/waiting/running/paused/interrupted/unknown 六状态保留；取消后仍有未结束尝试、真实文件/输出租约、残留任务引用或未完结果管理日志也保留。复用已有成功结果的项可能没有自己的 attempt，仍检查关联普通结果的管理操作。

UploadHistoryClearPlan 绑定 repository owner、executionEpoch、全部已选记录的指纹。准备读取会先同步普通历史秘密遮蔽，身份/冻结输入/普通结果关联不一致拒绝处理。执行在同一写入门与 SQL 事务重验，然后原子删除指定事件、尝试和发布项或导入审计；故障回滚保留所有记录。保护结束或普通结果改变也需要新确认，不将旧计划中的保留项自动提升为可清项。

普通远端结果、管理秘密、账号、资产、整理数据、永久字节、处理输出及保护引用都不在删除范围。恢复的 attempt UUID 仅作审计，不用于删除本机尝试。空 UploadBatches 保留 intentId 幂等账本，页面隐藏空批次而仓储接口继续返回；重放同一意图不会再次上传。清理后本机事件刷新任务页和共同图库历史选项。

## 文件

新增 `app/lib/features/upload/domain/upload_history.dart`、`app/lib/features/gallery/data/library_upload_history.dart`；调整 `library_repository.dart` 的边界接线与 `upload_tasks_screen.dart` 的共同页面。没有依赖或 schema 迁移，仍为 schema 6 的 26 表。

新增 `app/test/core/upload_history_repository_test.dart`、`app/test/upload_history_screen_test.dart`、`app/integration_test/history_flow_test.dart`。更新根 AGENTS、两份 README、架构、环境及 Windows V1 台账，原资源包保持只读。

## 验证

| 类别 | 实际结果与边界 | 证据 |
| --- | --- | --- |
| UT-038/066 仓储子范围 | **26/26 通过，4 秒**：真实 SQLite/文件、六活动状态、取消晚到/实际租约、租约释放 SQL 故障、复用成功的未完管理、事务回滚、全选择指纹、同 owner 实际替换 epoch、关闭拒绝新计划、幂等账本、两模式真实恢复审计隔离、秘密/普通结果/字节保留 | [核心原始日志](validation/windows-upload-history-repository-tests.log) |
| Widget 与旧任务页回归 | **16/16 通过，17 秒**：新历史页11项、旧任务页5项，320/390/1280及1.6字号；取消确认、新完成不增选、旧证据拒绝、失败重试、dispose、实际租约、系统退出、真实元数据恢复查阅与独立清理 | [界面原始日志](validation/windows-upload-history-ui-tests.log) |
| 全量回归 | **585 项通过，62 秒**；不是585个正式UT或90条验收通过 | [全量日志](validation/windows-upload-history-full-tests.log) |
| Windows IT-004/007 子流程 | **1/1 通过，运行1秒/Debug29.7秒**：真实原生窗口、SQLite/独立文件、合成管理秘密的实际系统后端、清理后保留、同意图重放及重开；无HTTP | [原生日志](validation/windows-upload-history-integration.log)、[清理后截图](../app/build/validation/windows-upload-history.png) |
| 静态与格式 | 整app分析无问题；144文件格式检查0改动 | [分析](validation/windows-upload-history-analyze.log)、[格式](validation/windows-upload-history-format.log) |
| 资源包/台账 | 31文件/56引用完整，全部90条规范属性、行为和验收措辞保持；不是软件测试 | [Kit](validation/windows-upload-history-kit-integrity.log)、[台账](validation/windows-upload-history-coverage-integrity.log) |

核心原始日志保留首轮23/23及最终26/26；界面日志保留首轮13/13及补完整分支后的16/16。局部静态检查发现的新测试API拼写/按钮类型已在运行前按真实实现修正，没有改生产接口迎合测试。两个独立资料库/独立 executor 的 Drift debug 提醒原样保留，没有隐藏警告。

Windows Release **36.5秒构建成功**，见 [构建日志](validation/windows-upload-history-release.log)。仅本次自有隐藏原生runner创建后正常WM_CLOSE，**exit0**，见 [启动退出日志](validation/windows-upload-history-release-smoke.log)。必须保留整个Release目录的DLL与data，单独exe不是交付包。没有安装器、签名或发布验收。

## 平台与剩余事项

已只读复核宿主 Flutter 3.47.6/Dart 3.13.5，通用安装目录为 `C:\Users\PAN\development\flutter`，持久用户 PATH 中 SDK bin 一条；不重复安装 SDK/ATL，不增加系统配置。Android SDK/设备尚缺，macOS/iOS 需要 Mac/Xcode 和设备。本机 M1 widget 与共同业务不等于三端可运行或移动后台 PT 已验收。

完整 AT-003、IT-004、PT-002 和全90条正式验收仍未闭合。主动链接探测与状态持久化、远端删除、设置/诊断/空间管理、网络与计费观察、自动处理依赖、真实服务契约及对应 CT/IT/性能/人工平台验收继续推进；未经授权不做真实上传或远端删除。
