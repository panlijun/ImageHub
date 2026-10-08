# 第十七阶段：持久设置与共同处理调度

2026-10-06。继续完整 Windows90条V1目标，本阶段实现 OPS-001/005、UT-053/083/087 的真实设置与动态并发子范围，完整首版尚未完成。通用 Flutter3.47.6/Dart3.13.5 和 Windows ATL 已安装，宿主实际命令指向 `C:\Users\PAN\development\flutter\bin\flutter.bat`，持久用户PATH有且仅有一条SDK bin；无需重复安装。没有新增依赖、SDK下载、系统配置、外部服务、真实HTTP、Git初始化、提交、推送或发布。资源包保持不变。

## 实际能力和规则

桌面 A 侧栏现在有独立“设置”和“备份与恢复”；M1 从“工具与设置 → 设置”进入同一实际编辑页。合法值先留在草稿，保存与读取确认后显示已保存；失败保留完整草稿、旧持久值及当前运行策略，可以重试。加载、损坏、未来设置格式或失效计划不得以空默认覆盖；主动重新读取明确替换草稿。

| 项目 | 默认 | 合法范围与作用 |
| --- | --- | --- |
| 上传并发 | 3 | 1–8个，影响后续派发，不取消真实在途请求 |
| 处理并发 | 1 | 1–4个，按实际候选总预算折算有效值，不取消运行项 |
| 有损输出质量 | 85 | 1–100，只初始化新工作台草稿 |
| 体积优先最长边 | 1600 | 1–16384像素，只初始化新工作台草稿，原有禁止放大规则继续生效 |
| 处理模式 | 保真优先 | 保真/体积优先，只初始化新工作台草稿 |
| 默认上传目标 | 无 | 复用账号页同一稳定UUID标记，不建立另一套配置身份 |

非整数、非有限、非法类型和越界拒绝，不截断或偷偷调整。恢复默认先填入草稿再提交，不立即改持久值。已有禁用默认目标可以保留或取消，不能新增禁用默认目标；凭据操作待完成的目标不能改变选中状态。若已有选中目标待安全操作完成，暂禁整体恢复默认，数值仍可保存，页面说明原因。

按已选 T-19，设置保存在既有 Drift `LibraryMetadata.device_settings_v1` 的严格版本化六字段JSON中，不另加 shared_preferences；仍为自身 schema7/26表，无迁移、生成代码或锁文件变更。SettingsSnapshot 绑定仓储 owner/epoch 与设置、目标代次/默认标记、待凭据操作指纹；SQL事务同时保存数值与目标标记。运行缓存及通知只在提交后更新，失败不改变两者。

默认目标保存不能复用会撤销正在上传请求授权的 accountChanges。LibrarySession 通过独立 settingsChanges 更新已存在的上传调度器，新调度器读取最近成功值；打开设置或保存默认值不会创建网络 actor，也不会授予网络权限。真实held请求用例证明降为1后旧3项继续，后续只逐项派发。

每个仓储共享纯Dart FIFO ProcessingScheduler。桌面512MiB、移动256MiB总预算仍为既定候选值，按每项128MiB折算有效并发，低于折算基准时保留一项并显示实际预算。许可冻结每项预算：调低不取消，调高也不能挤占旧运行项预算。ProcessingCoordinator 先取得真实输入租约再排队；取消等待只释放自身保护，不创建像素输出。实际像素线程、输出收尾、输入租约释放完成后才释放许可。关闭资料库先等待真实租约，再关闭调度器，等待不占写入门。

SettingsScreen 编辑分区有稳定身份，加载/失败/反馈/待凭据提示保留固定位置。修复了保存反馈改变列表结构导致4个 EditableText 被销毁、Flutter退出观察者快照失效的真实问题；系统退出等待保存提交及实际库关闭，退出用例必须无异常。已有工作台草稿、任务、永久原图和输出策略不被后续默认值修改。

本机策略暂不进入可携带 Manifest formatVersion1；实际替换保留本机数值，旧计划因epoch失效，内部快照/回滚保留元信息。**BAK-005 的可用平台设置转移及跳过报告仍未实现**，不能把本阶段本机保留称为跨端恢复完成。固定敏感元数据移除和原图逐次风险确认继续使用实际规则，不做假可编辑隐私开关。

## 修改文件

新增生产文件：

- [DeviceSettings](../app/lib/features/settings/domain/device_settings.dart)：严格值对象与格式校验。
- [LibrarySettings](../app/lib/features/gallery/data/library_settings.dart)：真实SQL设置、稳定确认计划及事务。
- [ProcessingScheduler](../app/lib/features/processing/application/processing_scheduler.dart)：共同预算许可与FIFO。
- [SettingsScreen](../app/lib/features/settings/presentation/settings_screen.dart)：共同持久设置页与退出保护。

修改生产接线：

- [CancellationToken](../app/lib/core/platform_resource.dart)：稳定一次性取消Future，保留同步取消标记。
- [ProcessingCoordinator](../app/lib/features/processing/application/processing_coordinator.dart)：租约与共享许可覆盖真实工作生命周期。
- [LibraryRepository](../app/lib/features/gallery/data/library_repository.dart)：打开读取有效设置、共同运行缓存/通知/调度器和关闭排空。
- [LibrarySession](../app/lib/features/gallery/presentation/gallery_providers.dart)：延迟上传actor配置与动态调整。
- [ProcessingWorkbench](../app/lib/features/processing/presentation/processing_workbench.dart)：首次有效加载初始化新草稿。
- [GalleryScreen](../app/lib/features/gallery/presentation/gallery_screen.dart)、[桌面](../app/lib/features/gallery/presentation/desktop_gallery.dart)、[M1](../app/lib/features/gallery/presentation/mobile_gallery.dart)：真实设置与独立备份入口。

新增测试：[值对象](../app/test/core/device_settings_test.dart)、[仓储](../app/test/core/settings_repository_test.dart)、[调度](../app/test/core/processing_scheduler_test.dart)、[设置界面](../app/test/settings_screen_test.dart)、[Windows原生闭环](../app/integration_test/settings_flow_test.dart)。补充 [真实输出生命周期](../app/test/processing/output_lifecycle_test.dart) 和 [真实替换](../app/test/core/backup_replace_restore_repository_test.dart) 用例。更新根AGENTS/README、app/README、architecture、environment与90条动态台账。

主线程审查实际文件和调用链；两个 Sol（gpt-6.1-sol/high）分别在不重叠范围实现调度/原生测试、设置页/widget。子代理未运行原生命令，所有Flutter/native验证由主线程串行执行，未仅凭子代理总结验收。

## 实际验证结果

| 验证 | 实际结果 | 证据 |
| --- | --- | --- |
| 核心与关联回归 | **92/92通过，13秒**：纯调度26、设置值对象6、真实设置仓储10及既有输出/上传/替换回归；新设置事务失败回滚/重试、同名UUID、损坏拒空覆盖、真实替换保留本机值/旧计划拒绝、held上传降并发均有证据 | [日志](validation/windows-settings-core-retest.log) |
| 真实处理生命周期 | **18/18通过，2秒**：包含新增2项实际协调器共享冻结预算/排队取消释放自身租约、关闭排空活动与拒绝等待输出；确认结果由真实像素引擎生成 | [日志](validation/windows-settings-processing-lifecycle.log) |
| Widget与工作台 | **19/19通过，27秒**：设置13与既有工作台6；320/390/1280及1.8字体、真实SQL故障反馈/重试、默认草稿、同名目标、pending安全操作、加载/旧草稿保护、dispose与系统退出等待 | [最终日志](validation/windows-settings-ui-final.log) |
| Windows IT-006 子流程 | **1/1通过，9秒/Debug28.6秒**：真实页面保存、正常关闭重开、永久PNG字节及SQL身份保留；新工作台默认73/边16实际生成16×12 JPEG；再保存91/边24不改旧输出行/快照/字节。匿名目标、无HTTP | [最终原生日志](validation/windows-settings-integration-final.log)、[截图](validation/windows-settings.png) |
| 全量 | **704项通过，62秒**；不是704个完整正式UT或90条验收通过 | [日志](validation/windows-settings-full-tests.log) |
| 静态与格式 | 整app analyze无问题，10.4秒；163文件格式检查0改动 | [分析](validation/windows-settings-analyze.log)、[格式](validation/windows-settings-format.log) |
| 资源包/台账 | 31文件/56本地引用完整；90条规范属性、行为、验收措辞逐条与原需求一致。文档检查不算软件测试 | [Kit](validation/windows-settings-kit-integrity.log)、[台账](validation/windows-settings-coverage-integrity.log) |

保留首轮实际失败日志，未把它们计通过：初次命令误用了2个不存在的旧测试名，已改为真实文件；新值对象测试的castMap空值夹具及安全遮蔽断言修正。widget曾误匹配TextField内部滚动器、反馈位于滚走的惰性区域及异常未释放测试gate，已按实际外层滚动与真实IO排空修正。退出失败另揭示上述真实生产控件身份问题，已修复并由19项widget/704全量/最终原生验证。没有放宽持久化、秘密、取消或退出规则来迁就测试；Drift独立数据库/executor debug提醒原样保留。

Windows Release **57.2秒构建成功**：[构建](validation/windows-settings-release.log)。仅启动本次自有隐藏runner，窗口创建、正常WM_CLOSE退出 **exit0**：[启动退出](validation/windows-settings-release-smoke.log)。实际可运行文件为 `app/build/windows/x64/runner/Release/imagehost.exe`，须保留同目录DLL及data。没有安装器、签名或发布。

## 平台及下一阶段

Android SDK、模拟器/实机缺失；macOS/iOS缺Mac/Xcode和设备，三端未构建/运行，不能报告可运行。共同业务从开始支持四端，但主机窄布局、纯策略或Windows原生不能替代三端PT/设备生命周期。此次没有新增工具链安装。

OPS-001/005仍为部分覆盖：缓存64–2048MiB/默认256MiB、全局临时保留和网络/计费/暂停策略未接入；诊断关键事件、30天/10MB留存、脱敏导出、分类空间清理仍需实现。下一阶段继续诊断、缓存及空间管理，随后网络观察、远端删除、自动处理依赖与真实服务契约/授权联调、性能和完整人工平台验收。全部90条仍为目标，保持未完成。
