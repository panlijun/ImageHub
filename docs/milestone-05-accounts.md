# 账号配置与安全边界

日期：2026-10-04；2026-10-05 补齐 ATL 并继续原生验证。本阶段继续 Windows 完整 V1 目标，遵循需求 1.1、测试设计 1.1 和技术选型 1.0。资源包保持不变，未读取旧项目或旧数据，未提交、推送、发布或请求图床。

## 当前实现

- 桌面和 M1 工具入口共用账号页。支持 Catbox 多账号/匿名及 ImgBB 多账号；别名允许重复，稳定 UUID 与身份标记独立，启用/默认配置持久保存。本地校验后保持未验证，不试上传验证。
- schema 4 的 17 表增加 ProviderTargets 和 CredentialOperations。更新遵循意图→安全写入并读回→关联→清理旧秘密；失败保留恢复记录。删除先阻止后续解析，保留去敏身份，再确认秘密删除；同名新增不复用旧身份。
- 明确会话凭据只保留进程内值，关闭清空；替代持久凭据后不能在重开复活旧密钥。安全后端不可用时允许添加独立会话目标，本地图库仍可运行。普通 SQLite 不保存秘密。
- SecretStore 为纯 Dart 接口；平台 SystemSecretStore 由生产 provider 注入。无后端的 CLI 拒绝凭据操作，不回退明文。逐项调用写/读/删，写入与删除后读回核对，不使用 readAll/deleteAll。
- 已选 flutter_secure_storage 11.2.0 实际解析并更新锁文件。Android storageNamespace 隔离，禁迁移、禁错误重置，旧/新云备份及设备迁移排除 data/wrapped-key/config 三项 sharedpref。Apple ThisDeviceOnly、关闭同步；macOS 独立 Keychain。源配置不是平台运行证据。
- SecretRedactor 遮蔽注册值/编码、敏感字段/URL 和有字段上下文的截断文本；历史值、数字/布尔转换、循环/超限及未知对象有安全处理。账号别名已接线，未来网络、诊断、备份全部出口尚未实现。
- 解析当前账号凭据、启停及移除状态与冻结历史名分开；真实队列、在途停止、晚到结果、响应与链接仍待接线。没有把当前接口子测试计为完整 ACC-005 通过。

限制与协议核查来源：[Catbox API](https://catbox.moe/tools.php)、[FAQ](https://catbox.moe/faq.php)、[ImgBB API](https://api.imgbb.com/)、[安全存储 11.2.0 文档](https://pub.dev/packages/flutter_secure_storage/versions/11.2.0)。MB 标称值尚未确定精确字节契约，不猜作无限容量；配置与健康状态分开。

## 实际验证

| 检查 | 结果与边界 | 证据 |
| --- | --- | --- |
| 账号阶段 Flutter tests | 203 项通过，含核心/参数化/widget；不是 203 个完整正式 UT，后续新增测试另记 | [完整日志](validation/windows-accounts-full-tests.log) |
| 首批账号/安全/升级 | 36 项通过，含已有升级回归；不与全量相加 | [核心日志](validation/windows-accounts-core.log) |
| 表单/安全服务专项 | 19 项通过；320/1280 加载空态/失败、实际保存、失败保留输入/会话选择；不是手机实机 | [界面日志](validation/windows-accounts-widget.log) |
| 静态与格式 | Flutter analyze 无问题；69 文件格式检查 0 改动 | [静态](validation/windows-accounts-analyze.log)、[格式](validation/windows-accounts-format.log) |
| schema 4 输出进程恢复 | 5 个输出边界及 1 个永久关联保存场景通过，原始永久副本与身份保留 | [输出恢复](validation/windows-accounts-output-recovery.log) |
| schema 4 导入进程恢复 | 六个导入边界、正常跨进程重开、Windows 排他锁/释放通过 | [导入恢复](validation/windows-accounts-import-recovery.log) |
| Windows 安全后端 IT-007 子流程 | **1 项通过**：真实系统秘密写/读回、资料库关闭重开读取、同名与匿名隔离、账号页、删除读回及重开留存身份；合成凭据不请求服务 | [原生日志](validation/windows-accounts-integration.log)、[页面截图](validation/windows-accounts.png) |
| 账号版 Release | 构建通过（67.3 秒）；创建真实原生窗口，WM_CLOSE 正常退出码 0 | [构建](validation/windows-accounts-release.log)、[启动退出](validation/windows-accounts-release-smoke.log) |

实际插件 C++ 引用 atlstr.h，对应技术选型 9.1 的 ATL 要求。2026-10-05 用户明确授权后，仅给 VS 2022 Build Tools 17.14.40 添加 Microsoft.VisualStudio.Component.VC.ATL；安装器退出 0，vswhere 与实际头文件均确认，未重启或绕过安全后端。[安装证据](validation/windows-atl-install.log) 保留详情。

首次原生账号测试的系统写入/重开读取已执行，但导航点击早于图库加载完成，导致页面断言失败；修正为等待真实 ListTile 启用后点击，完整流程通过。未修改业务逻辑以掩盖测试失败。Windows 原生构建此前发现的 RadioGroup 回调类型问题已修正。

新项目自身 1/2/3→4 升级覆盖有效身份/整理/字节与失败回退；3→4 场景包含真实资产、标签、收藏及独立处理输出。基础安全存储测试使用合成替身，不能代替 Windows 原生安全后端或四端 SEC/PT 验收。进程退出工具不能冒充硬件断电。

## 修改文件

| 边界 | 路径 |
| --- | --- |
| 共同业务/接口 | `app/lib/features/accounts/domain/account_models.dart`；`app/lib/core/{secret_store,secret_redactor}.dart` |
| 平台安全存储 | `app/lib/platform/system_secret_store.dart` |
| 数据与恢复 | `app/lib/features/gallery/data/{library_accounts,library_database,library_database.g,library_repository}.dart` |
| 账号页与入口 | `app/lib/features/accounts/presentation/accounts_screen.dart`；`app/lib/features/gallery/presentation/{gallery_providers,gallery_screen,desktop_gallery,mobile_gallery}.dart` |
| 平台源配置 | AndroidManifest、`res/xml/{backup_rules,data_extraction_rules}.xml`；iOS Runner.entitlements/project.pbxproj |
| 验证 | `app/test/core/{accounts_repository,secret_store,secret_redactor,library_migration,output_schema_migration}_test.dart`；`app/test/accounts_screen_test.dart`；`app/integration_test/accounts_flow_test.dart` |
| 依赖/记录 | pubspec/真实 lock/Flutter 插件登记；AGENTS/README、architecture/environment/coverage、本记录及证据 |

Sol 子代理（gpt-6.1-sol，high）实现安全边界，Luna 子代理（gpt-6-luna，high）实现确定的表单；主线程阅读实际文件、修正接线并执行验证。

## 后续

继续完成图床适配器、持久队列、结果链接和账号变更与在途任务接线。备份恢复、设置、诊断与 Windows 平台/性能/无障碍验收仍保留。Android 缺 SDK，macOS/iOS 缺 Mac/Xcode 与设备；完整首版尚未完成。
