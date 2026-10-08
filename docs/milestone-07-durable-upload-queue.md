# 持久上传队列与共同任务页

日期：2026-10-06。Windows 完整 V1 目标仍在进行，本阶段不代表首版完成。Flutter、Dart、Windows ATL 已安装，本次没有重复安装、改系统配置、安装 Android SDK、开通外部服务或真实上传。

## 当前实现

- schema 5 增加批次、发布项、尝试、普通远端结果、受保护管理信息提交意图和事件。新项目 schema 1–4 事务升级，保留既有图库、整理、输出和账号；未来格式拒绝打开并保留内容，不涉及旧项目兼容。
- 输入×目标固定排序、意图 UUID 幂等入队；冻结实际版本/摘要/字节、处理策略哈希、去敏名称及目标 UUID/别名。创建时保留永久版本或临时输出依赖；派发检查实际文件并解析当前凭据，持久授权前复核账号代次。
- 默认上传并发 3，可降低而不终止已运行项。整批暂停、取消、条件等待、最多初次加三次的 2/4/8 秒退避和重开恢复已接线。墙钟不缩短退避，未知结果不自动再传。默认复用同内容/目标/策略的已确认成功；明确再传使用新意图和独立结果。
- 看门计时器只累计实际执行和增加的字节活动；等待/暂停不记执行。运行累计写入持久检查点，执行 120 秒无活动、30 分钟累计边界；这不是硬件强退计时精度验证。
- 取消先终结意图，实际输入保护等到传输和文件读流收尾。晚到完整确认以尝试身份唯一保存，不覆盖取消计数。结果提交先保留可恢复提案，管理秘密只写新 UUID 的系统受保护存储并核对读回摘要，普通 SQL 不保存秘密。
- 新管理秘密注册后，关联事务遮蔽本库历史展示快照；重开仅读取本库引用注册，不枚举其他凭据。安全后端故障不会恢复已经遮蔽的历史文本。
- 桌面与 M1 复用上传页：默认确认处理输出，原图另需元数据隐私确认，不能暗中回退；真实入队反馈、九状态/六聚合/五计数、逐项原因和尝试、整批暂停/继续/取消、独立普通结果及四格式复制。读取失败保留最后有效列表，提交不确定保留原意图供核查重试。
- 页面离开不关闭应用级队列。系统退出等真实 IO；收尾未确认则保留保护并拒绝伪报安全退出。

## 实际验证

| 类别 | 实际结果 | 证据 |
| --- | --- | --- |
| 新增专项 | 41 项通过；真实库/文件 23、调度 8、链接格式 3、共同 widget 5、受控实际 multipart 子流程 2 | [专项日志](validation/windows-upload-target-tests.log) |
| 当前全量 | 288 项通过，41 秒；含参数化、widget 和 UT/IT 子场景，不能写成 288 个正式 UT | [全量日志](validation/windows-upload-full-tests.log) |
| M1 导航 | 1 项专项通过；真实任务页返回后图库滚动及关键词保留 | [导航日志](validation/windows-upload-m1-navigation.log) |
| 静态/格式 | Dart analyze 无问题；88 个文件格式化 0 改动 | [静态](validation/windows-upload-analyze.log)、[格式](validation/windows-upload-format.log) |
| Windows 引擎 IT-004 子流程 | 1 项通过，3 秒；Debug 构建 20.3 秒；受控传输、真实输出/库/系统秘密与重开，不请求服务 | [原生日志](validation/windows-upload-integration.log)、[实际截图](validation/windows-upload-tasks.png) |
| Release/正常关闭 | 构建成功，41.5 秒；真实自有窗口创建、正常 WM_CLOSE，exit0 | [构建](validation/windows-upload-release.log)、[启动退出](validation/windows-upload-release-smoke.log) |
| 输入完整性 | 31 文件、56 本地引用通过，不是软件测试 | [资源包检查](validation/windows-upload-input-integrity.log) |
| CT/IT-008/PT/完整 AT | 未执行真实服务请求和全部设备/人工流程 | [V1 台账](windows-v1-coverage.md) |

专项初跑暴露真实 Material/ListTile ink 背景断言，已将任务面板改为 Material。链接 UTF-8 校验先使用 URI 规范化表示，避免拒绝合法中文。两处 fixture 改正：确认输出采用实际尺寸压缩，不能要求保真编码必然不同于原图；刷新准确定位 IconButton 并等原生 IO。全量回归的旧 M1 测试仍断言“任务未接入”，已更新真实数据库等待和 material_ui 返回按钮，保留滚动/查询断言。原生测试初跑使用精确文本“全部成功”，而实际标题包含批次身份，已改用真实标题子串并继续核对持久计数/结果。没有增加超时或放松数据保护断言。

截图已由主线程实际查看：两目标身份独立、普通链接与真实尝试展示，没有布局异常或管理秘密。截图归档第一次使用了错误的相对路径，随后按工作区根目录正确复制；构建与运行本身未失败。Release 必须保留同目录 DLL 与 data，不能只搬运 exe。

## 生产与平台限制

当前生产默认服务限制仍为 unknown，任务会入队等待能力确认。2026-10-06 再次只读核查官方资料：Catbox [首页](https://catbox.moe/) 200 MB、[FAQ](https://catbox.moe/faq.php) GIF 20 MB 未说明精确字节；[上传表单 JS](https://catbox.moe/resources/uploadform.js) 的 maxFilesize 1000 与首页不同，不能作为 API 上限。ImgBB [API 文档](https://api.imgbb.com/) 写 32 MB，同页前端配置 32000000 bytes，但实际网页 [JS](https://simgbb.com/8179/ibb.js) 使用 /json/、source，与公共 API /1/upload、image/key 不同。网页前端值不能冒称公共 API 精确契约。测试注入限制属于夹具。

Windows 是本阶段实际引擎/构建验证平台；Android 无 SDK/设备，macOS/iOS 无 Mac/Xcode/设备，均未构建或运行。M1 的主机 widget 不替代手机平台验收。

仍缺单项暂停、系统网络与计费/低存储观察、自动处理依赖图、完整成功链接检索/批量复制、历史与结果移除、独立远端删除、备份恢复、设置诊断及平台/性能/无障碍完整验收。真实上传或删除测试须另有明确授权。

## 修改文件与审查

| 范围 | 主要文件 |
| --- | --- |
| 队列领域/调度 | `app/lib/features/upload/domain/upload_queue_models.dart`、`link_format.dart`；`application/upload_coordinator.dart`、`upload_queue_store.dart`；`data/library_upload_queue_store.dart` |
| 数据提交与恢复 | `app/lib/features/gallery/data/library_uploads.dart`、`library_database.dart`、真实生成 `library_database.g.dart`、`library_repository.dart`、`library_accounts.dart` |
| 共同入口/关闭 | `upload_tasks_screen.dart`、`upload_exit.dart`；图库 `gallery_providers.dart`、`gallery_screen.dart`、`desktop_gallery.dart`、`mobile_gallery.dart`；处理/账号退出接线 |
| 核心与 widget | `app/test/core/upload_repository_test.dart`、`upload_coordinator_test.dart`、`upload_pipeline_test.dart`、`link_format_test.dart`；`upload_tasks_screen_test.dart`、`mobile_gallery_test.dart`；自身 schema 迁移夹具 |
| Windows 引擎 | `app/integration_test/upload_flow_test.dart` |
| 约定/记录 | 根/app README、AGENTS、architecture/environment/coverage、本记录、validation |

两个实现 Sol 子代理（实际参数 gpt-6.1-sol、high）分别负责限定的持久队列和共同任务 UI，未继续委派。主线程实现调度/链接与测试、阅读实际 schema/恢复/安全/页面调用链，要求补齐历史秘密遮蔽和真实 IO 边界并统一执行验证。两个只读 Sol 子代理同参数分别核查官方限制及备份边界；资料研究不算软件测试。工作区未初始化 Git，因此没有 git diff；没有提交、推送或发布，资源包保留不变。
