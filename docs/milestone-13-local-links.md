# 本地链接管理

日期：2026-10-06。继续 Windows 完整 V1，以真实普通确认结果为输入；桌面与 M1 使用同一仓储、确认计划、协调器和结果页。未修改资源包、读取旧应用或执行真实上传/远端删除。Flutter/Dart 和 Windows ATL 已具备，本阶段没有重复安装 SDK 或修改系统配置。

## 实际行为

- SQL 检索普通结果名称、普通 URL、冻结历史目标别名，Unicode NFC/完整默认 case folding 后，与稳定目标 UUID、服务及原图/处理类型取交集，再计数/分页。时间、名称、目标排序均以稳定结果 UUID 收尾。历史目标不被同名新账号替代；每个身份只查询最新冻结描述。
- 四格式复用既有安全编码器。两种批量范围分别确认：当前已展示结果的列表顺序，或资产当前永久版本的选择顺序后再按用户勾选的历史目标顺序。不加入未加载、筛选外或其他处理版本，完全相同的格式化文本去重、逐项换行，缺失明确跳过。
- 仓储创建 LinkCopyPlan，绑定 owner、执行 epoch 和普通字段摘要，系统操作前重新验证。无链接不调用系统；复制或分享失败保留数据库记录，重试不创建上传。分享只传普通文本，不请求 URI 元数据或传管理能力。
- 本地移除另行确认：操作日志、普通记录删除与 publication.resultId 解除在同一 SQLite 事务。系统管理秘密先核对摘要和全部相关所有权引用，再删除、读回，最后清日志；失败保留新删除事实和清理现场，重开幂等重试。不删除资产、文件、尝试、事件或远端文件，未完成管理操作仍阻止恢复维护。
- 新注册秘密可能与早先普通名称重合。SecretRedactor.revision 变化后，后续链接读取/查询先持久遮蔽普通快照，避免仍以秘密命中关键词和计数；计划再次验证拒绝旧文本。原有普通结果读取使用同一映射。
- 桌面侧栏“成功链接”、M1 底部“链接”和图库资产范围入口已接入，任务页单项复制复用协调器。加载失败保留最后有效列表并禁复制；替换后清查询和选择。操作期间禁止返回/切页，退出等待实际本地调用；只有当前可见页面负责资料库退出。

## 修改文件

新增：

- `app/lib/features/links/domain/link_query.dart`、`link_transfer.dart`
- `app/lib/features/links/application/link_transfer_coordinator.dart`
- `app/lib/features/links/presentation/link_results_screen.dart`
- `app/lib/features/gallery/data/library_links.dart`
- `app/lib/platform/link_transfer_gateway.dart`
- `app/test/core/link_repository_test.dart`、`link_transfer_test.dart`
- `app/test/link_results_screen_test.dart`
- `app/integration_test/links_flow_test.dart`

调整：`secret_redactor.dart`；`library_repository.dart`、`library_uploads.dart`、`library_replacement_restores.dart`；图库 desktop/mobile/screen 入口；`upload_tasks_screen.dart`；`mobile_gallery_test.dart` 必要新入口断言与真实 IO 等待。没有增加数据库表或格式版本；仍为 schema 6。

按既定 T-14 获取直接依赖 share_plus 13.3.1，真实 `pub get` 更新 `pubspec.yaml`、`pubspec.lock` 和 Windows/macOS 自动注册文件。额外解析 share_plus_platform_interface 7.2.0、url_launcher_linux 3.2.3、url_launcher_platform_interface 2.3.2、url_launcher_web 2.4.3、url_launcher_windows 3.1.6；传递依赖不代表增加 Web/Linux 应用，没有改框架选型或安装额外系统工具。行为语义依据 [share_plus 官方包说明](https://pub.dev/packages/share_plus)；SDK 剪贴板缺后端处理以实际安装版本源码及真实通道测试为证据。

工作区约定、两份 README、架构、环境与 90 条覆盖台账同步记录。本工作区没有 Git，未初始化、提交、推送、PR 或发布。

## 验证记录

| 类别 | 实际结果与边界 | 证据 |
| --- | --- | --- |
| 真实仓储 UT/IT 子范围 | **20/20 通过**，约 3 秒：SQL 交集/分页/稳定身份、两种复制计划、后注册秘密、确认/提交/删秘密故障、哈希变化/篡改/共享引用、重开、恢复门禁及实际替换回滚 | [仓储日志](validation/windows-links-repository-tests.log) |
| 平台协议/协调器 UT | **11/11 通过**：严格 SDK 通道、分享回执/安全锚点、未知异常不 stringify、空/失效计划、local retry 不改 SQL/不上传、真实替换失效；系统通道受控 | [最终日志](validation/windows-links-transfer-tests.log) |
| Widget | **20/20 通过**：链接页 7、M1 8、任务页 5；320/390/1280 与 1.5 字号、历史身份、51 项首批 50、失败重试/分享取消/本地移除、旧确认拒绝及原图库滚动保持 | [组合日志](validation/windows-links-ui-tests.log) |
| 全量回归 | **521 项通过，58 秒**；含最后修改的 Gallery 退出监听保护。不是 521 个正式 UT 或 90 条验收通过 | [全量日志](validation/windows-links-full-tests.log) |
| Windows 原生 IT-004/007 子流程 | **1/1 通过**，Debug 构建 30.1 秒/运行 1 秒：真实窗口、SQL/文件、实际系统受保护合成管理秘密、重开、仅本地删除及秘密读回。provider evidence、clipboard/share 为受控边界，无 HTTP | [原生日志](validation/windows-links-integration.log)、[引擎截图](../app/build/validation/windows-links.png) |
| Windows Release | **构建成功，45.9 秒**；只启动本次自有隐藏 runner，正常 WM_CLOSE **exit0**。没有安装器、签名或发布 | [构建](validation/windows-links-release.log)、[启动关闭](validation/windows-links-release-smoke.log) |
| 静态/格式 | 整 app 分析无问题；134 文件格式检查 0 改动 | [分析](validation/windows-links-analyze.log)、[格式](validation/windows-links-format.log) |
| 文档输入 | 31 文件/56 引用完整，90 条规范措辞保留；不是软件验证 | [Kit](validation/windows-links-kit-integrity.log)、[台账](validation/windows-links-coverage-integrity.log) |
| 安装只读复核 | Flutter 3.47.6 / Dart 3.13.5、通用 SDK 实际存在，宿主用户 PATH 持久登记 1 条；没有重复安装/改配置 | [SDK 状态](validation/windows-links-sdk-state.log) |

首轮平台测试真实发现：Flutter 3.47.6 的 Clipboard.setData 使用 OptionalMethodChannel，缺平台实现时仍返回完成，导致误报 copied。已改为相同 `flutter/platform` / JSONMethodCodec / Clipboard.setData 协议的严格通道；保留[初轮失败](validation/windows-links-transfer-tests-first-attempt.log)，最终 11 项通过。

Widget 日志保留调试失败及最终成功：旧“链接未接入”断言、lazy ListView/内部横向 Scrollable 定位，以及合成 Catbox remoteId 与普通 URL 不一致。仓储正确拒绝畸形成功；修正测试夹具和真实滚动/IO 等待后通过，没有放宽业务校验。故意同时打开不同隔离根的 Drift debug 提醒未被关闭；没有共用 QueryExecutor。

## 剩余范围

这一步完成 LNK-001/002/003 的本地业务与共享入口子范围，不能据此关闭正式验收。真实系统剪贴板、分享及权限拒绝 PT-003、完整 AT-003/004、服务 CT-005 和参考负载性能仍待实测；本原生测试没有改用户剪贴板或打开外部分享应用。

LNK-004 的主动探测、可达/删除/未知状态持久化和真实服务保留契约仍未完成；UPL-007 远端删除、QUE-010 完成历史清理、LIB-005 图库远程字段/失败目标组合检索与 LIB-006 最近上传排序仍待接线。持久设置/诊断、网络与计费观察、处理依赖和正式平台/负载验收继续按全部 90 条范围推进。

Android SDK/设备与 Mac/Xcode/Apple 设备仍缺，共同 Flutter/Dart 业务与 M1 主机测试不代表 Android/iOS/macOS 原生可运行。默认图床精确能力契约尚未核验，受控成功不能冒充真实服务可用；本阶段没有真实上传/删除授权。
