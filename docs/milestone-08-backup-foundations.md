# 真实备份导出与恢复预检

日期：2026-10-06。Windows 完整 V1 仍在进行。此阶段实现导出及恢复前校验，尚未实现合并、替换或实际恢复提交。Flutter/Windows ATL 已具备，本阶段没有重复安装 SDK、改变系统配置、安装 Android SDK、开通服务、提交、推送或发布。

## 已接入的行为

- 独立白名单 Manifest formatVersion 1，保存逻辑身份、内容描述、整理、永久来源、去敏账号标识、普通结果及已结束历史；排除设备来源路径、秘密/引用、临时输出及待执行任务。当前 schema 仍为 5，未复制活跃 SQLite，也不涉及旧应用数据。
- 唯一写入协调器及事务捕获一致的已提交关系。完整模式同时取得所有永久版本的文件租约，包含回收区以及仅清记录后保留的独立内容；元数据模式不含图片字节。长摘要与像素检查在协调门外执行，保护持续至实际 IO 结束。
- 所有本库拥有的凭据和管理秘密先经系统存储读取并注册脱敏；无法取得安全视图时失败。普通文本可遮蔽；结构 UUID、摘要或参数与秘密冲突时拒绝包，不通过改身份或截断制造成功。
- 完整模式校验 SHA-256、实际字节数、格式、尺寸、帧数及方向。必要副本缺损时列出受影响版本并停止；界面只在用户明确点击后重新选择目录导出元数据，不能静默降级。
- archive 4.3.0 为已解析的既定配套库，本次从传递依赖改为显式运行依赖，真实 pub get 更新锁文件。清单和图片均使用 STORE，文件流在 isolate 内有界写入；预读及实际写出的图片分别核对摘要和大小，关闭/flush 后才发布，不使用整包内存编码。
- Windows 原生空间查询采用 GetDiskFreeSpaceExW 的当前用户可用值。归档在所选目录的私有同卷暂存中完成，以 MoveFileExW 无 REPLACE_EXISTING/COPY_ALLOWED 发布；目标存在时保留两文件并重选新身份。提交后到达的取消不会删除已完成导出。
- 预检先取得自有暂存副本，解析原始 ZIP/ZIP64 中央/本地记录，保留重复项证据，检查连续范围、路径白名单、链接属性、加密/压缩/descriptor、重复名、实际累计大小及资源预算。按块核对 CRC32/SHA-256，再验证真实图片信息；返回临时已校验文件，不写当前图库。
- 桌面侧栏及 M1 工具入口使用共同备份页，具有加载/空态/读取失败、两模式说明、空间估算、进度、取消等待及提交汇总。重新进入刷新统计。非 Windows 原生导出和实际恢复操作明确禁用。

## 验证证据

| 类别 | 实际范围及结果 | 日志 |
| --- | --- | --- |
| 领域/实际数据/归档专项 | 47 项通过：清单 18、真实 SQLite/文件快照 6、ZIP 写入 6、原始 ZIP/ZIP64 预检 10、导出协调器 5、平台契约 2 | [串行专项](validation/windows-backup-target-tests-serial.log) |
| 共同页面 | 修复重入统计后 9 项通过；320/390/1280 与 1.6 字号、目录取消、真实元数据包、损坏不降级、等待实际操作结束 | [页面专项](validation/windows-backup-widget-tests.log) |
| Windows 原生 IT-005 子流程 | 1 项通过，2 秒；Debug 43.4 秒。实际空间/无覆盖发布、真实系统受保护合成凭据、两模式导出、独立预检、侧栏进入页面、真实导出与重开 | [原生 UI 日志](validation/windows-backup-integration-ui.log)、[截图](validation/windows-backup-export.png) |
| 静态/格式 | Dart analyze 无问题；104 个文件格式检查 0 改动 | [静态](validation/windows-backup-analyze.log)、[格式](validation/windows-backup-format.log) |
| 当前全量 | 344 项通过，3 分 6 秒；包含既有图库、处理、账号及上传回归，不计作 344 个正式 UT | [全量日志](validation/windows-backup-full-tests.log) |
| Release | Windows 构建通过，85.9 秒；真实原生窗口创建、正常 WM_CLOSE 退出，退出码 0 | [构建日志](validation/windows-backup-release.log)、[启动退出](validation/windows-backup-release-smoke.log) |
| 输入完整性 | 31 文件、56 本地引用通过；90 条 V1 属性、行为和验收原文全部保持 | [资源检查](validation/windows-backup-input-integrity.log)、[台账检查](validation/windows-backup-coverage-integrity.log) |

上述是含参数化和 widget 的实际测试数量，不是正式 UT 数或需求完成数。空间不足由注入容量值验证，不冒充真实磁盘耗尽；目录选择由测试网关注入，不计系统选择器 PT。归档边界注入和正常重开不代表硬件断电、强退或全部故障验收。原生测试只使用全新临时库和合成凭据，清理其自有引用，未请求图床。

首次专项运行出现 Windows 本机 socket 10055 加载失败；改用 concurrency=1 后 47 项通过，未修改系统。首次全量发现备份页重入统计过期，已通过进入页显式刷新修正并补回归；初始失败记录保留在 [原始全量日志](validation/windows-backup-full-tests-initial.log)。

格式契约已与真实领域对齐：ImageInspector 保存 PNG/JPEG/WebP/GIF/BMP，清单不能只接受小写；仅包内后缀小写。ZIP64 同时验证所选 archive 的 EOCD sentinel/完整中央额外字段，不把纯规范小夹具当作库输出兼容证据。

## 修改范围与下一阶段

新增 backup 领域/快照/协调器/ZIP reader-writer/共同界面，图库增加 library_backups part；平台新增 storage_capacity.dart 与 Windows runner 窄通道；桌面/M1 增加入口。新增六份 core 测试、共同页面测试和 backup_flow 原生测试，依赖清单只显式加入既定 archive。根 AGENTS/README、应用 README、架构、环境及 V1 台账分别记录当前边界。

下一阶段必须实现 BAK-004 的默认合并、身份/来源/结果重映射、标签与分类冲突汇总；暂停派发及排空实际在途操作；不可执行历史存储；替换的可恢复内部快照、单独确认、旧意图取消、库执行代次隔离与失败回滚。预检成功不能冒充完成恢复。

四端共同 DTO/校验/归档服务已建立，其他三端的系统导出、空间、原子发布、沙盒及设备恢复仍须补齐和分别实测。预算为候选值，当前未执行大于 4 GiB 实包、恶意外部进程路径竞态、完整 CT-006/IT-005/PT-005/AT-005。Windows 全部 V1、真实图床服务契约、链接管理、设置/诊断及其余平台验收仍未完成。
