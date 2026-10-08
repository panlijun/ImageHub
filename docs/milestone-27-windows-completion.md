# Windows 软件完成记录

日期：2026-10-08。目标：完成 Windows 桌面端开发，排除用户指定的实机/硬件验收及真实账号测试。**本轮 Windows 软件开发及适用主机验证已完成。** 源码审查、全量回归、原生子流程、独立进程、Release 与正常启动退出全部完成；四端正式发行和真实图床可用性不由此结论宣告通过。

首次 PC 端完成基线：用户于2026-10-08授权建立本工作区的 Git 仓库并进行首次本地提交，提交主题为“首次完成 PC 端”。提交包含应用源码、设计参考、独立资源包及实施/验证记录，排除构建产物和本机应用数据；不推送或发布。完成范围仍以上述 Windows 软件验证边界为准。

## 范围与实际能力

Windows 桌面 A 已接入本地图库、独立永久副本、组织检索与回收、压缩/裁剪/拼接、真实原图和处理预览、永久保存与桌面导出、账号受保护存储、持久任务与自动处理依赖、按网络类型控制派发、普通链接/复制/分享、确认后的主动检测与独立远端删除审计、两种备份/合并/替换、设置/空间/诊断。关机前正常关闭与重开保存真实关系和字节，成功反馈只在提交后产生。

用户最新决定覆盖 ACC-001/ACC-002/ACC-004：**不提供 Catbox 匿名上传，只支持 Catbox userhash 和 ImgBB APIKey。** UI、配置、默认选择、入队、目标解析、请求前授权及适配器均拒绝匿名。本项目自身已有匿名普通历史/备份身份保留读取，不改 UUID，不删除，不重新启用。旧匿名准备发送工具已删除；此前五张合成图没有发送。

**生产实际上传仍等待精确服务能力核验。** 两家默认能力为 unknown；不能把测试注入限制或网页阈值当 API 精确契约。账号配置不自动试传，进入页面/入队不授予网络许可。没有真实上传、删除或探测请求；远端删除发出后没有可靠确认时保留 unknown。对应外部证据仍未验证，不与“Windows 软件已接入”混淆。

手机仍采用已选 M1；其他三端未构建运行，移动原生导出尚未接入并保持禁用。签名、安装包、发布与这些平台交付不属于本轮结果。软件开发与验证期间没有 Git 初始化、提交、推送、PR、软件安装、大型下载或系统配置；随后首次本地提交已获用户授权，见本记录开头。

## 本轮实际修改

本轮涉及 35 个生产文件、46 个测试/夹具文件、6 个原生集成夹具。完整路径见 [源码与夹具清单](validation/windows-completion-changed-files.txt)；生成清单时工作区尚未初始化 Git，没有用 Git diff 冒充变更证据。单独删除 `app/tool/verify_catbox_synthetic.dart`，历史运行记录与未发送合成图保留。

| 修改范围 | 文件与实际变化 |
| --- | --- |
| 账号、上传和适配器 | `account_models.dart`、`accounts_screen.dart`、`library_accounts.dart`、`library_settings.dart`、`library_uploads.dart`、`provider_adapters.dart`、`link_results_screen.dart`：匿名拒绝全链，按 UUID 读取停用/移除的待执行、运行和 unknown 影响并确认，取消保留草稿/查询失败不报零。适配器同步异常与原始响应错误固定脱敏，等待真实 fetch/输入/响应收尾；拒订阅无法确认收尾保留保护。 |
| 导入与安全打开 | `gallery_screen.dart`、`library_failure_view.dart`、`desktop_gallery.dart`、`mobile_gallery.dart`：选择器与复制同一操作追踪，停止后晚到资源不读取，退出先完整收尾；损坏/未来库展示重试和数据保全/恢复说明，不做空库覆盖或猜修。 |
| PNG 与真实预览 | `png_orientation.dart`、`bake_image_orientation.dart`、`image_inspector.dart`、`metadata_policy.dart`、`image_processor.dart`、`image_preview_codec.dart`：严格 CRC/chunk/TIFF 方向解析，1–8像素矩阵及奇数尺寸180度修正，缩略图/处理/SDK逐帧显示一致。原永久字节不重编码，SDK转换等真实图像工作完成再释放，保留帧时长/循环与预算。 |
| 同内容重导入、缓存与审计关系 | `library_repository.dart`、`library_storage.dart`、`version_description_policy.dart`、`backup_manifest.dart`、`backup_merge_plan.dart`、`backup_restore_plan.dart`：只纠正本项目已知旧PNG方向1/编码尺寸遗漏，真实同内容再导入后仅改三字段，身份/整理/字节不变；租约/持久引用或未知差异拒绝。复用提交用 committedReuse 日志收尾；缓存自身代次2，仅复用2，旧1保留保护和安全清理。永久描述之间严格一致，历史仅接受已知方向描述关系，恢复只重映射UUID，不改冻结元字段；同一个处理快照内混用两代描述仍拒绝。 |
| 内存压力 | `memory_pressure.dart`、`windows_memory_pressure_signal.dart`、`system_memory_pressure_monitor.dart`、`processing_scheduler.dart`、`gallery_providers.dart`、`settings_screen.dart`：实际 Win32 低内存信号即时读/候选轮询，加共同事件/FIFO预算。只降低后续派发，不取消已有许可；失败固定诊断，退出继续排空真实图库IO，关闭失败句柄保留重试。 |
| 备份/诊断保护 | `backup_temporary_workspace.dart`、`backup_zip_reader.dart`、`backup_coordinator.dart`、`backup_screen.dart`、`library_backups.dart`、`library_diagnostics.dart`：只清登记且关闭/摘要证据一致的暂存，未知/链接/篡改/IO不确定保留，已发布名称退出暂存归属；导出提交与保护/暂存收尾分别反馈。本库秘密引用读为null也拒绝安全读取/导出，恢复可读后再试，不删资产/字节。 |
| 测试和文件约定 | 新增账号范围/影响UI、选择器退出、PNG解析/SDK/重导入/缓存/备份审计、压力源/观察/会话、缺失秘密、安全打开等真实边界测试。原匿名夹具改为合成账号或自有遗留身份；关闭/重开使用同一自有安全存储。README、根AGENTS、范围、环境和验收台账同步最新决定。 |

主线程读取真实生产文件、事务关系及测试断言，审查 90 条适用软件行为的 [图库等40条](validation/windows-library-software-audit.md)、[账号等39条](validation/windows-network-software-audit.md)、[备份/设置11条](validation/windows-local-software-audit.md)。这个映射数量不是 90 条全部正式验收通过；原需求、必要验证及不适用/未运行边界保持独立。

## 实际验证结果

| 分类 | 实际结果与日志 | 证明边界 |
| --- | --- | --- |
| 格式 | 255 文件，0 改动，1.86 秒；[日志](validation/windows-completion-format-verified.log) | 当前 Dart 源码/测试/集成/工具；首轮必要格式改动已写入。 |
| 分析 | 无问题，4.9 秒；[日志](validation/windows-completion-analyze-verified.log) | 整 app，包括新代码和测试，不代表运行或性能。 |
| 全量 unit/widget/本机集成子场景 | **1314通过，1跳过，120秒**；[日志](validation/windows-completion-full-final.log) | 包含真实临时 SQL/files/isolate/SDK 和受控HTTP；不是1314个正式UT。唯一跳过 `platform/source_readiness_test.dart` 的非Windows分支，不计通过。 |
| 账号 UI 与 SDK 专项 | 19通过：账号影响/匿名UI 5项 + 原图方向/动画SDK 14项；[日志](validation/windows-completion-account-sdk-final.log) | 不是仓储或适配器19项，也不代表真实图床/手机SDK。 |
| 压力与真实 Win32 当前信号专项 | 46通过，2秒；[日志](validation/windows-completion-pressure-final.log) | scheduler/session/monitor及当前Win32读/关闭，不诱导硬件低内存；2秒轮询和128MiB仍候选。 |
| 备份保护与安全打开专项 | 16通过，6秒；[日志](validation/windows-completion-backup-protection-final.log) | 已确认暂存/保护和安全错误UI边界；与全量重复，不相加。 |
| PNG、重导入、旧缓存、冻结审计备份专项 | 49通过，5秒；[日志](validation/windows-completion-png-backup-focused-final.log) | 真实SQL/文件/像素/完整及元数据ZIP、合并/替换/再备份，冻结字段不变；包含故障日志恢复与保护。 |
| Windows 原生图库 | 1项通过，Debug40.2秒/测试4秒；[日志](validation/windows-completion-native-gallery.log) | IT-001/002子流程，真实永久副本、SDK原图、关闭重开；选择器fixture，非PT。 |
| Windows 原生处理/导出 | 1项通过，Debug30.1秒/测试5秒；[日志](validation/windows-completion-native-processing.log) | IT-003子流程，实际处理、永久保存、同名导出与重开。 |
| Windows 原生安全凭据 | 1项通过，Debug33.5秒/测试1秒；[日志](validation/windows-completion-native-accounts.log) | IT-007子流程，合成凭据经真实Windows后端写/重开/删；不是实际账号验证。 |
| Windows 原生自动处理与任务 | 1项通过，Debug32.7秒/测试2秒；[日志](validation/windows-completion-native-upload_processing.log) | UT-046/062、IT-004子流程，处理任务和身份重开；未授权网络不派发。 |
| Windows 原生备份/恢复 | 1项通过，Debug31.9秒/测试6秒；[日志](validation/windows-completion-native-backup.log) | IT-005/BAK-005子流程，真实容量、独占ZIP、设置、合并/替换/回滚、安全秘密排除和重开；不是四设备互读。 |
| 独立进程恢复 | 六个exit(73)导入边界、独立进程正常重开与排他锁/释放检查全部通过；[日志](validation/windows-completion-process-recovery.log) | 真正独立进程与字节/稳定身份核对；不是硬件断电或实际系统强退。 |
| Windows Release/正常退出 | Release63.7秒成功；自有隐藏runner创建窗口并正常WM_CLOSE退出0；[构建](validation/windows-completion-build-final.log)、[启动关闭](validation/windows-completion-smoke-final.log) | 未签名/安装/发布；只报告当前Windows运行能力。 |
| 文档完整性 | 资源包31文件/56引用完整，90条规范原文保留；[资源包](validation/windows-completion-kit-final.log)、[台账](validation/windows-completion-coverage-final.log) | 文档完整性不是软件测试。 |

可运行输出位于 `app/build/windows/x64/runner/Release/`。运行 `imagehost.exe` 须保留同目录插件DLL、`native_assets.json`、`sqlite3.dll`及 `data/`。当前Dart AOT `data/app.so` 为14,189,448字节，2026-10-08 10:08:17生成；原生host EXE未改变，因此其时间仍为上一构建阶段，不以EXE旧时间误判Dart构建未更新。

本轮已查看原生 [图库截图](../app/build/validation/windows-gallery.png) 和 [备份恢复截图](../app/build/validation/windows-backup-merge-restore.png)，没有溢出错误或以固定样本模拟生产成功。截图中的合成图片、账号和备份来自自有集成夹具，不是用户图库或真实服务证据。

## 失败与修正记录

- 初始全量1251通过/1失败/1跳过：[日志](validation/windows-completion-full-initial.log)。失败是旧备份测试故意篡改已校验文件后仍要求 dispose 删除。修正为明确拒绝、保留变化字节，测试自行恢复其自有已知字节后再验证可重试；不放宽生产保护。
- 初始SDK方向测试显示 Flutter 对PNG eXIf方向2–8未转换；补真实逐帧方向适配及资源等待，再用非对称像素矩阵确认。image180度对奇数高度中间行遗漏由共同转换修正，永久字节保持。
- 初始组合/账号widget未完成记录保留；只终止已经核对归属的自有测试进程。测试改用有限pump、真实异步排空与退出等待，不用无条件skip或吞异常消除失败。
- 新PNG/备份组合139通过/3失败：[日志](validation/windows-completion-png-backup-focused.log)。缓存断言的PNG decoder参数须为Uint8List，编译失败影响另一个加载；审计断言误假定恢复结果保留输入数组顺序，实际稳定结果排序按UUID。修正为强类型和按结果UUID核对两代冻结字段，正反输入顺序均保留真实历史，未改生产排序。最终49专项与全量均通过。
- 分析曾报告未用import/括号及nullable冗余，均在本轮分配文件内修正，最终无问题。子代理sandbox格式启动失败没有执行代码格式修改；主线程在已具备SDK环境完成统一格式与验证。
- Drift调试日志会提示多个数据库实例；这些恢复测试使用彼此独立的临时根和独立连接，并按实际IO关闭，不是同一个QueryExecutor被共享。未为静音修改业务或掩盖断言。

## 后续边界

本轮不记通过：实机PT、真实硬件PERF/内存与磁盘压力/断电、实际账号与真实图床CT/IT-008、完整人工AT、其他三端构建设备、正式发行/签名。系统未知云来源内核阻塞仍不能保证固定期限安全停止；大于4GiB实包和四端预算仍待实际测量。

下一阶段首先补服务契约/账号能力证据并在明确授权后联调，再推进Android/iOS原生导出及三端构建。Catbox匿名不再是待办，网络计费状态不再是待办；不会自动开启云账户、图库同步、团队或新图床。
