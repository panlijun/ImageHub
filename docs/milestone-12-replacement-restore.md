# 真实替换恢复与失败回滚

日期：2026-10-06。Windows 完整 V1 继续进行；本阶段启用独立确认的替换恢复。没有新增安装、依赖、数据库版本或外部请求；只读资源包保留，无提交、推送或发布。

## 实际行为

- 共同 RestoreCoordinator 先预检 ZIP，再暂停上传、排空实际文件使用并取得资料库维护保护。替换确认前生成当前独立 SQLite/登记字节快照，并在全新私有临时位置实际重建数据库和文件，重新核对结构、25 个业务表、外键、TextPolicy、所有登记文件及缺失状态；不只检查清单或可读性。
- 风险确认独立于默认合并。展示当前库及备份数量、实际字节、旧意图数量、禁用账号与元数据缺失说明；勾选风险后才可确认。取消保留原库，任务仍暂停，清理等待实际 IO 结束。
- 替换保持传入资产、版本、分类、标签、来源、普通结果及审计身份；相同内容的不同资产不合并。所有永久版本使用新设备副本 UUID 和管理路径。元数据替换明确缺失，不复用当前相同内容字节。
- 新图片独占创建暂存、流式复制、flush/关闭、摘要和像素校验，并独占发布。业务关系与 replace-committed 在同一 SQLite 事务内确认；此前原有永久字节和系统凭据保持原值。
- 提交前失败或取消校验全部证据后清理本次有归属的新字节，并用只读快照 ATTACH 在现有资料库单事务恢复全部业务关系及原秘密引用。Drift 原配置保持不变；局部 sqlite3 readWrite/uri:true 连接在已有 writer/drain 边界内使用，核实外键/WAL/FULL，事务中无 await。
- 成功切换 executionEpoch，清内存凭据、旧可执行意图并关闭旧上传 actor。保护释放后重置图库查询、UUID 选择、预览和账号/任务缓存；页面已经退出也会通知存活的 app scope。新 actor 无网络授权，导入账号禁用待配置，历史不可执行。
- 提交后核对当前引用、旧文件实际摘要和旧秘密摘要才清理。清理失败保留有效新库与日志供重开重试。replace-cleaned 先持久化，再删除私有快照，使快照删除中断可继续。晚到取消或显示回调异常不能推翻已确认提交。
- 启动先处理替换日志，再执行导入、输出到期、凭据及队列维护；恢复问题汇总保留。不能确认回滚时保留所有证据并阻止普通读写；未知文件、链接、篡改或未确认发布归属不猜测删除。

## 实际验证

| 类型 | 结果与边界 | 记录 |
| --- | --- | --- |
| UT-080 / IT-005 子范围重建与回滚 | 11/11 通过，2 秒；独立实际重建、取消/容量/关闭等待、未知内容与链接拒绝、启动关系回滚、暂停意图和受控秘密引用保留。链接实际执行，无跳过 | [回滚专项](validation/windows-replacement-rollback-tests.log) |
| UT-073/074/075 / IT-005 子范围仓储 | 21/21 通过，7 秒；六个提交前边界故障和取消、实际全量与元数据替换、同内容不同资产、提交后取消/回调异常、秘密清理失败重试、占用目标保留、容量失败、cleaned 中断重开。跨 await 旧会话写入断言另在最终全量执行通过 | [仓储专项](validation/windows-replacement-repository-tests.log) |
| UT-080 / AT-005 子范围应用/widget | 10/10 通过，55 秒；独立勾选/取消、真实文件/库/ZIP/重开、上传 actor 无授权、同 UUID 选择清除、页面退出后存活图库刷新和实际 IO 排空。秘密/发布为受控替身，M1 是主机 widget | [界面专项](validation/windows-replacement-ui-tests.log) |
| 启动既有回归 | 2/2 通过；自身 schema 5→6 保留稳定数据，畸形恢复日志逐项验证、不删已知首项/外部来源并保留提示 | [启动回归](validation/windows-replacement-startup-regression.log) |
| 全量 | 483 项通过，57 秒。首轮 482 通过/1 失败，启动后导入恢复覆盖了先前恢复提示；已修复并完整重跑。数量包含参数化、widget 及正式 UT/IT 的子范围，不是 483 个正式验收项 | [最终全量](validation/windows-replacement-full-tests.log)、[首轮](validation/windows-replacement-full-tests-initial.log) |
| 格式/静态 | 124 文件格式检查 0 改动；整 app analyze 无问题 | [格式](validation/windows-replacement-format.log)、[静态](validation/windows-replacement-analyze.log) |
| Windows 原生 IT-005 子流程 | 最终 1 项通过，4 秒/Debug 29.1 秒。实际 Windows 容量与 MoveFileExW、两模式替换、metadataWritten 故障实际回滚、系统合成凭据保留/清理、会话切换及关闭重开。首轮 1 项通过，4 秒/Debug 20.2 秒 | [原生首轮](validation/windows-replacement-integration.log)、[最终复核](validation/windows-replacement-integration-final.log) |
| Windows 原生 IT-004 回归子流程 | 1 项通过，3 秒/Debug 28.8 秒；真实文件受控传输、系统合成管理秘密、普通结果及关闭重开。无真实图床请求 | [上传原生回归](validation/windows-replacement-upload-integration.log) |
| Windows Release | 构建成功，54 秒；自有隐藏原生窗口正常创建、WM_CLOSE 并 exit 0 | [Release](validation/windows-replacement-release.log)、[启动退出](validation/windows-replacement-release-smoke.log) |
| 输入/台账 | 31 资源文件、56 本地引用完整；90 条 V1 需求原文完整。此项不是软件测试 | [资源](validation/windows-replacement-kit-integrity.log)、[台账](validation/windows-replacement-coverage-integrity.log) |
| 开发环境 | 宿主 Flutter 3.47.6 / Dart 3.13.5、Windows/VS 正常；用户 PATH 持久登记 1 条，不重复安装或修改配置。Android SDK 仍缺 | [宿主检查](validation/windows-replacement-host-environment.log) |

首轮回滚专项 10 通过/1 失败：Drift 连接未启用 URI，附加只读快照失败；改为局部启用 URI 的连接后通过。界面专项首轮 5 通过/5 失败：测试约 3 秒真实 IO 窗口不足，且一项误用 pumpAndSettle；改为有上限的真实 IO/fake zone 交替排空后全部通过。首轮及修正过程保留，未把卡住或失败包装成通过。测试多独立目录/独立 executor 的 Drift debug 多实例提醒保留。

## 修改文件

生产新增 `app/lib/features/gallery/data/library_replacement_restores.dart`、`library_replacement_rollback.dart`；修改 `library_repository.dart`、`library_restores.dart`、`app/lib/features/backup/application/restore_coordinator.dart`、`presentation/backup_screen.dart`、图库 `gallery_providers.dart`、`desktop_gallery.dart`、`mobile_gallery.dart`、账号 `accounts_screen.dart`、任务 `upload_tasks_screen.dart`。

验证新增 `app/test/core/backup_replace_restore_repository_test.dart`、`replacement_rollback_test.dart`、`app/test/backup_replacement_screen_test.dart`；扩展 `app/integration_test/backup_flow_test.dart`。更新根 `AGENTS.md`、根/app README、架构、环境、90 条台账及本记录，实际日志在 `docs/validation/windows-replacement-*`。

Sol 子代理实际参数为 `gpt-6.1-sol` / `high`，分别负责私有重建/回滚与确认/状态重置；主线程实现替换提交、审查实际代码、补跨 await 与启动问题汇总保护、执行仓储/全量/原生/构建并验收。额外仓储测试代理未成功启动（线程数限制），由主线程完成；没有启动 Luna/Astra。

## 剩余边界与下一阶段

BAK-004 核心替换生产闭环已有子流程证据，完整 IT-005/AT-005、真实强退/硬件断电、人工系统选择/普通退出、恶意并发原子 no-follow/file-ID 防护、大库性能和超过 4 GiB 实包仍未验收。发布介于实际移动与归属日志确认之间且无法证明所有权时，保留现场并拒绝自动回收；不能称所有故障均可自动处理。替换后清理失败保留新库，仍需核查/重试。

重建/摘要按 128 行分页，但排序/OFFSET 与同步 SQLite 完整性/VACUUM 成本未校准，不标为 PERF 通过。临时重建进程中断可能留下没有持久归属日志的私有临时目录，不能扫描并猜测删除。

Android SDK/设备、Mac/Xcode/Apple 设备仍缺；共享 Dart 业务、手机 M1 布局及配置存在不代表三端原生可运行。下一阶段继续完整链接管理、持久设置/诊断、网络观察、队列依赖及正式 PT/AT/CT/PERF。生产图床精确契约尚未核验，无真实上传授权或联调证据；Windows 完整首版和全部 90 条验收仍未完成。
