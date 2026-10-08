# 图库远程组合检索与上传排序

日期：2026-10-06。继续 Windows 完整 V1，补齐 LIB-005/006 的共同查询与桌面 A、手机 M1 入口。本阶段无新依赖、数据库迁移、软件安装或真实网络请求；原资源包保持不变。

## 实际规则

- 名称、来源显示、格式、分类、标签，以及冻结历史目标别名、图床服务、普通 URL 共同参与 Unicode NFC/完整默认 case folding 关键词检索。分类、收藏、标签、本机可用性和远程条件先在 SQL 中取交集，再计数和分页；全部匹配 UUID 使用相同谓词及顺序。
- 普通确认结果、当前发布项、恢复的终态审计历史，按 SHA-256 与字节数关联资产当前永久内容。原资产的不同处理版本不会自动归入原图；独立保存后的内容可关联自身历史。稳定目标 UUID 与历史别名独立，不用当前同名新账号替代已移除身份。
- 目标、服务、输入类型、状态及远程关键词必须来自同一项记录，不能把另一个目标的失败与本目标的成功拼成命中。状态筛选表示存在相应记录，允许同一资产同时存在失败、取消和确认链接，不能冒充资产整体聚合状态。
- “无普通链接”按选定远程范围判断；指定目标、服务或类型时还要求有该范围的发布或审计记录，避免加入从未使用该目标的资产。未结束项包括排队、等待、执行、暂停、中断；unknown 独立表示结果未知。
- 最近确认上传使用当前内容普通结果的真实 MAX UTC 确认时间，未确认项升序、降序均置末尾，同值最终按资产 UUID 升序。移除普通结果后重新计算，不从 succeeded 发布状态或当前墙钟制造日期。
- 本机事件刷新图库和历史目标选项，不创建上传 actor、不触发网络。共同筛选面板保留各项条件和明确清空；元数据读取失败保留筛选身份，固定安全提示和重试。搜索草稿 debounce 期间保留输入，明确清空后同步输入框。
- 新秘密注册后，查询先持久遮蔽普通远程及恢复历史快照；已知秘密关键词不命中，即使早先本机名称恰好含该值。本机整理原值不被改写。恢复片段须与审计行身份、批次、位置一致；损坏或未来格式拒绝读取或重开，保留库与现场。

unknown 不是终态。备份只携带 succeeded/failed/cancelled 审计历史；恢复检索不会复活原库 unknown 意图或生成可执行队列。

## 修改文件

新增 `app/lib/features/gallery/data/library_gallery_remote.dart`、`presentation/gallery_filter_controls.dart`、`app/test/core/gallery_remote_query_test.dart`、`app/test/gallery_remote_filter_screen_test.dart`、`app/integration_test/gallery_remote_flow_test.dart`。

调整 `domain/gallery_query.dart`、`domain/library_models.dart`、`data/library_repository.dart`、`data/library_uploads.dart`、`presentation/gallery_providers.dart`、`desktop_gallery.dart`、`mobile_gallery.dart`；工作区约定、README、架构、环境、90 条台账同步登记。仍为 schema 6。

旧 `desktop_gallery_test.dart` 的上传排序禁用断言更新为已启用；`mobile_gallery_test.dart` 的原 IO 等待增加已存在的“正在读取图片名称…”状态，不增加循环或超时预算。

## 验证

| 类别 | 实际结果与边界 | 证据 |
| --- | --- | --- |
| 仓储 UT-017/018、SEC 子范围 | **18/18 通过，6 秒**；真实 SQLite/文件、65 项跨 60 分页、同项交集、真实时间/NULL/UUID排序、当前内容关联、两模式备份恢复、秘密注册与坏片段保留 | [仓储日志](validation/windows-gallery-remote-repository-tests.log) |
| Widget/controller 定向回归 | **24/24 通过，78 秒**：新筛选8、M1 8、desktop 7、controller 1；320/390/1280及1.5字号。随后新增未知异常固定提示第9项在全量统一验证 | [界面日志](validation/windows-gallery-remote-ui-tests.log) |
| 全量回归 | **548 项通过，69 秒**；含最终安全提示及未知异常 toString 防护，不是548个正式UT或90条验收通过 | [全量](validation/windows-gallery-remote-full-tests.log) |
| Windows 原生图库 IT-003/004 子流程 | **1/1 通过，运行2秒/最终Debug20.5秒**；真实窗口、独立数据库/文件、实际缩略图解码、本机记录变化刷新、普通移除与重开；无HTTP/上传actor | [日志](validation/windows-gallery-remote-integration.log)、[截图](../app/build/validation/windows-gallery-remote.png) |
| Windows 备份 IT-005 原生回归 | **1/1 通过，运行4秒/Debug20.5秒**；真实系统容量、独占发布、两模式导出/合并/替换/重开与合成系统凭据保护 | [备份回归](validation/windows-gallery-remote-backup-regression.log) |
| Windows Release | **构建成功，56.5秒**；仅本次自有隐藏runner正常创建/WM_CLOSE **exit0**，无安装器/签名/发布 | [构建](validation/windows-gallery-remote-release.log)、[启动关闭](validation/windows-gallery-remote-release-smoke.log) |
| 静态/格式 | 整app分析无问题，139文件格式检查0改动；最终仅集成夹具补实际图像等待，单文件format/analyze通过 | [分析](validation/windows-gallery-remote-analyze.log)、[格式](validation/windows-gallery-remote-format.log) |
| 输入完整性/台账 | 31文件/56引用完整；全部90条规范属性、行为和验收措辞保留。不是软件测试 | [Kit](validation/windows-gallery-remote-kit-integrity.log)、[台账](validation/windows-gallery-remote-coverage-integrity.log) |
| 全局安装复核 | 通用 SDK Flutter3.47.6/Dart3.13.5、实际宿主用户 PATH 1条；没有重复安装或改配置 | [SDK状态](validation/windows-gallery-remote-sdk-state.log) |

首轮仓储18项中16通过、2失败。测试把 unknown 当成备份终态，已按真实备份规则修正夹具期望，不放宽恢复语义。界面原始失败及重跑均留在日志：旧禁用排序断言、新测试平台override复位、M1新增筛选行挤占图库高度、初始事件导致无意义整页/预览重建，以及旧helper没有等待真实名字IO。已将M1入口放搜索旁、共同provider仅监听数值revision、修复等待状态；没有延长原时限或把未完成IO包装成通过。

未知异常不 stringify：本轮桌面旧错误插值改为安全固定提示，仅可信 LibraryOpenException 读取其message。测试使用会抛出的 toString 并断言调用0次。恢复测试同时打开不同独立根/不同 executor 的 Drift debug提醒保留，没有隐藏警告或共用 executor。

## 剩余范围

本阶段不等于 AT-001、PERF-001 或完整 Windows V1 通过。正式 10,000 资产参考负载、真实人工操作/权限、三端设备与工具链验收仍待补。主动链接探测及状态持久化、远端删除、完成历史清理、设置/诊断、网络与计费观察、处理依赖及其余 90 条必要证据继续推进。

Android SDK/设备、Mac/Xcode/Apple 设备仍缺。共同 Flutter 代码、主机 M1 widget 和 Windows 引擎验证不能报告其他三端可运行。没有 Git 初始化、提交、推送、PR、发布或外部服务开通。

下一阶段 QUE-010 已只读核查真实链路，尚未实现清理：空 UploadBatches 必须保留为 intentId 幂等账本，任务展示可隐藏但仓储列表不能隐藏（页面用于核对未确认入队）。只看终态或 task reference 不足，须保留未结束 attempts、实际输入租约、残留依赖和未完成结果操作；复用成功项可能没有 own attempt，还要检查关联结果的 attempt。清理 native/imported 历史分别确认，保留普通结果、秘密及文件，计划在 owner/epoch 和指纹保护下重新校验并单事务提交。
