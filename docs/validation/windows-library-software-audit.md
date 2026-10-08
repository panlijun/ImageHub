# Windows 图库与处理软件收尾源码审查

审查日期：2026-10-08。范围：IMP-001..008、LIB-001..008、IMG-001..009、OUT-001..005、DAT-001..005、NFR-001..005，共 40 项 V1 要求。依据为当前 `AGENTS.md`、资源包 `documents/requirements-analysis.md` 和 `documents/unit-test-design.md`，以及当前生产代码和测试源码。资源包中的“设计，未执行”是原件状态，不能据此判断当前实现；旧实施台账也不作为未实现的证据。

当前结论：Windows 桌面 A 及其共同生产调用链具备下列适用软件行为。审查发现的本项目自身旧PNG描述与缓存问题已补有界重导入纠错和缓存代次；永久信息校验、历史快照保留及备份恢复的严格关系均已实施。主线程最终1314软件测试通过/1非Windows分支跳过，PNG/缓存/备份专项49通过，五个Windows原生子流程及Release/正常退出通过，详见 [最终完成记录](../milestone-27-windows-completion.md)。文末“待实现/待验证”保留修复前及子任务交付时点的事实，不代表当前仍有该软件缺口；冻结活动任务不会自动改写或重派发。

本报告是源码审核，不是测试执行报告；没有运行 Flutter、测试、构建或请求服务，没有据全量绿色结果概括逐项通过。表内“具备”表示真实入口和生产逻辑存在，并列出可验证行为的测试源码；最近修改的最终执行结果、构建结果由主线程串行验证记录负责。测试名称含“partial”的范围仍按其具体断言解释，不扩大为整条全平台验收。

## 当前真实入口与共同链

- Windows 始终采用桌面 A，窄窗口不会变为移动 M1。`features/gallery/presentation/gallery_screen.dart` 接入系统多选、停止、批次结果、整理、回收、修复、工具和原图入口；`desktop_gallery.dart` 展示共同状态。以下 `lib/` 路径均相对 `app/lib/`，测试路径相对 `app/test/`，IT 相对 `app/integration_test/`。
- 导入：`platform/import_gateway.dart` → `GalleryScreen._startImport/_acquireAndImport/_import` → `LibraryRepository.importBatch/_importResource/_complete` → `ManagedFileStore` 暂存、摘要、发布 → 同一 writer 事务关联资产/版本/副本。选择阶段也由 `_activeImport` 持有；确认退出等待真实选择取得器返回，取消令牌阻止迟到资源继续入库。
- 原图：`original_preview_screen.dart` → `application/original_preview_reader.dart`（永久版本租约、摘要）→ `platform/image_preview_codec.dart::decodeOriginalPreview`（SDK codec、共享预算）→ `original_preview_controller.dart`（最多当前和待显示帧、暂停和真实排空）。缩略图另经 `ImageInspector` 产生静态小图，不能替代原图。
- 处理：`ProcessingWorkbench` → `ProcessingCoordinator` → 共享 `ProcessingScheduler` → isolate `ImageProcessor`。输入保护持到真实线程及输出收尾；输出交给 `library_outputs.dart` 的日志和关联提交，保存复用永久导入，导出复用 `FileExporter`。
- 存储：`LibraryRepository.open` 与 `library_database.dart` 校验、恢复、实际 PRAGMA 验证；加载失败显示 `LibraryFailureView`，没有空库覆盖或清库按钮。`GalleryController.reload` 失败保留上一有效列表。维护/关闭在 writer 门外等待实际工作，而非仅观察取消状态。

## 导入 IMP

| 编号 | 当前生产证据与软件结论 | 有效测试源码证据 |
| --- | --- | --- |
| IMP-001 | 具备。`ImportGateway.pickFiles` 系统多选；`_acquireAndImport` 将选择/等待来源与永久提交分开，空选择不建资产/上传意图，逐个取得的资源继续交付批次。 | `core/cloud_import_batch_test.dart` UT-010/011 验证待获取项不阻断实际 PNG；`gallery_import_exit_test.dart` UT-011 取消迟到来源后允许新选择；IT `gallery_flow_test.dart` 真实 fixture 取得与导入。系统选框/权限 PT 另列排除。 |
| IMP-002 | 具备。`ImageInspector._format/_decode` 按实际字节识别、解码 PNG/JPEG/WebP/GIF/BMP，不依赖后缀；不支持及坏图为固定分类。PNG additionally 校验 eXIf/CRC/边界。 | `core/library_repository_test.dart` UT-002/IT-001 五种真实格式错误后缀、伪 JPG 文本、不支持字节；`core/png_orientation_test.dart` 畸形/重复 eXIf 不产生可用资产。 |
| IMP-003 | 具备。`_importResource/_complete/recover` 复制关闭、真实摘要与像素校验、发布后事务提交；失败保留/回收有日志依据的半成品，外部来源只读。 | `core/library_repository_test.dart` UT-003/091 各 ImportBoundary 中断及源流失败、UT-004 来源移除后重开；`core/import_source_cancellation_test.dart` 实际源清理/writer 等待；`core/storage_capacity_test.dart` 空间拒绝。 |
| IMP-004 | 具备。`_complete` SHA-256+实际字节数复用版本/资产，保留整理/历史；回收重复返回 needsRestore；不同内容新身份。 | `core/library_repository_test.dart` UT-005/006/007；`core/import_recycle_boundary_test.dart` 活跃资产优先、独立版本重用、坏/缺副本修复；`core/gallery_remote_query_test.dart` 远程关联按当前内容。旧错误 PNG 元信息重用限制见文末。 |
| IMP-005 | 具备。`ImportBatchResult` 独立逐项状态和计数；`GalleryScreen._import` 显示真实汇总/原因，系统文件入口可重新选择，单项失败不截断后续。 | `core/library_repository_test.dart` UT-008 两成功/失败/重复计数；`core/cloud_import_batch_test.dart` 单项待获取后有效图继续；IT `gallery_flow_test.dart` 实际 UI 批次。 |
| IMP-006 | 具备。版本写真实格式、方向后的尺寸、字节与帧数，资产/来源写名称、来源类型、UTC 导入/更新时间；永久可用性不依赖外部引用。 | `core/library_repository_test.dart` UT-009 实际元信息、UTC、稳定排序及 UT-004 来源移除；`core/png_orientation_test.dart` 八方向真实导入尺寸/元信息/原始字节。 |
| IMP-007 | 具备 Windows 软件分类。`PlatformResource/ResourceFailure` 区分取消、拒绝、缺失、cloudPending、暂不可用及 invalidImage；`platform/source_readiness.dart::SourceReadinessProbe` 预检普通本地路径，OFFLINE/RECALL_ON_DATA_ACCESS 时不开流；重选不会清整理。 | `core/cloud_import_batch_test.dart` 分类与下一项；`platform/source_readiness_test.dart` 标志位与路径边界；导入/重开真实副本测试。真实云提供者、授权变化和内核阻塞行为属于 PT 排除，不把预检称全云来源覆盖。 |
| IMP-008 | 具备。批次进度、同一取消令牌、未取得资源停止及最终汇总；`_activeImport` 在取得器前建立，`_exitRequested` 等选择/实际复制清理，不放迟到进度盖掉停止反馈。多选完整，目录/拖放是可选能力。 | `core/library_repository_test.dart` UT-011 未打开后续源跳过；`import_stop_feedback_test.dart`；`core/import_source_cancellation_test.dart`；`gallery_import_exit_test.dart` 停止、拒绝退出、失败取得器与确认退出等待。 |

## 图库 LIB

| 编号 | 当前生产证据与软件结论 | 有效测试源码证据 |
| --- | --- | --- |
| LIB-001 | 具备。桌面卡片/详情显示整理、版本、本机状态和普通远程结果；`AssetPreviewImage` 显示经校验的小图，缺损可重生/重选；原图入口使用永久版本 reader 和 SDK codec，支持动画播放/暂停，不用缩略图冒充。 | `core/library_repository_test.dart` “thumbnail regenerates after cache removal and does not replace original”；`core/library_organization_test.dart` UT-012 缺损与重开；`gallery/original_preview_reader_test.dart` 摘要与租约；`gallery/original_preview_controller_test.dart` 帧/暂停/关闭；`core/original_preview_orientation_test.dart` 真实 SDK PNG 八方向、JPEG6、WebP6、APNG。 |
| LIB-002 | 具备。UUID 选择集、`_selectMatching` 使用数据库全匹配 UUID；查询变化不增选，批量 `_review` 展示实际对象/数量再执行。 | `desktop_gallery_test.dart` UT-013/017 当前筛选选择与核对；`gallery_controller_test.dart` 查询代次、旧分页隔离、计数变化首批重读。 |
| LIB-003 | 具备。`LibraryOrganizationEditor` 保留连续编辑草稿；`TextPolicy` trim/Unicode17 NFC/完整 folding/再次 NFC，按 scalar 限 1–64、资产标签 ≤50；`updateOrganization` 先全验证再一笔事务，不截断。 | `desktop_gallery_test.dart` 标签连续输入；`core/library_organization_test.dart` UT-014/015 Unicode、50/51、非法成员使全批回滚。 |
| LIB-004 | 具备。`library_organization.dart` 分类 UUID 创建/赋值/重命名/移除、收藏与批量编辑；只修改确认字段，移除分类不删字节。 | `core/library_organization_test.dart` UT-016 规范化重用、重命名碰撞回滚、移除保留身份/标签/收藏/字节；桌面整理交互测试。 |
| LIB-005 | 具备。仓储 `_matches/_galleryRemotePredicate` 在分页前共同 SQL 计数/查询/全 UUID；本机字段与目标 UUID/服务/输入/结果状态/普通 URL 条件取交集，同条远程记录匹配；先脱敏再折叠检索。 | `core/library_organization_test.dart` UT-017 本机 AND/Unicode；`core/gallery_remote_query_test.dart` 远程同条记录、失败目标、分页及秘密遮蔽；`gallery_remote_filter_screen_test.dart` 与 IT `gallery_remote_flow_test.dart` 共用筛选入口。 |
| LIB-006 | 具备。`_galleryOrder` 导入/名称/大小/最近真实确认 MAX UTC；无确认时间始终末尾，最终资产 UUID 稳定收尾。 | `core/library_organization_test.dart` UT-018 跨页/重开同值排序；`core/gallery_remote_query_test.dart` 最近确认、空值两方向末尾。 |
| LIB-007 | 具备。`library_recycle.dart` 移除只标回收，恢复身份/整理；30 天仅提示；清理计划分别确认记录与字节，持久依赖/实际租约阻止，不调用远端删除。 | `core/library_recycle_test.dart` UT-019 精确到期仍可恢复、UT-020 分别确认/共享保护/外部来源不动；IT-010 清理日志恢复；`desktop_gallery_test.dart` 明确影响确认。 |
| LIB-008 | 具备。同摘要/字节重导入修复副本保留逻辑身份，不同内容新版本；仅清记录保留独立版本/字节，仅清副本保留整理和普通链接；有效共享引用/使用保护阻止删除或替换。 | `core/library_repository_test.dart` UT-021；`core/import_recycle_boundary_test.dart` orphan/坏副本修复；`core/library_recycle_test.dart` UT-020/102 实际 IO 未结束保护和 SQL 释放失败收尾。旧 PNG 冻结元信息与“字节修复”分别解释，见文末。 |

## 图片处理 IMG

| 编号 | 当前生产证据与软件结论 | 有效测试源码证据 |
| --- | --- | --- |
| IMG-001 | 具备。工作台不依赖账号；`ProcessingCoordinator/ImageProcessor` 读取指定版本、独立独占输出，不写输入，取消等实际 isolate 收尾。 | `processing/image_processor_test.dart` UT-022 输入摘要成功/失败/取消不变、输出拒绝；IT `processing_flow_test.dart` 真实工作台处理。 |
| IMG-002 | 具备。默认 fidelity 保持尺寸/透明，动画无法保真时拒绝并要求显式静态选帧；JPEG/不透明转换先确认背景；真实结果提示有损/特征变化及可能增大，无自动有损回退。 | `processing/image_processor_test.dart` UT-023/027、颜色 ICC/cICP 保留/未知色彩拒绝；`processing/processing_workbench_test.dart` 动画选择、透明背景确认、实际失败反馈。不承诺动画重编码。 |
| IMG-003 | 具备。`fitLongestSide` BigInt 比例四舍五入最小1且不放大，最长边1–16384；JPEG/WebP质量1–100默认85，PNG无无效质量；输出读实际尺寸/字节比较。 | `processing/image_processor_test.dart` UT-024/025 极端/比例/小图/格式质量；`processing/processing_workbench_test.dart` 默认策略、真实前后比较及更大输出提示。 |
| IMG-004 | 具备。共同解码五输入，三个输出编码器，压缩/裁剪/拼接共用同一已定向像素入口；动画原图 SDK 播放暂停，处理必须明确确认真实帧和静态转换；透明丢弃须背景确认。原样上传走受保护真实输入流而非改图。 | `processing/image_processor_test.dart` 实际5×3静态压缩矩阵、动画特征/选帧/背景；`core/png_orientation_test.dart` APNG准确帧缩略图/裁剪；`gallery/original_preview_controller_test.dart` 动画；`core/original_preview_orientation_test.dart` 两帧APNG像素/时长/循环；上传 adapter/coordinator 受控流测试。裁剪/拼接格式矩阵部分证据来自共同生产入口，不能说每种组合均已单独实测。 |
| IMG-005 | 新导入具备。`readPngOrientation` 共同解析真实 eXIf，严格边界/CRC/唯一/方向字段校验；Inspector 元信息/准确帧缩略图、Processor、SDK预览一致。`bakeImageOrientation` 方向3使用 copyRotate180，避免第三方奇数中央行错误；JPEG decoder已定向不二次bake，其他方向只应用一次。`MetadataPolicy` 白名单色彩/隐私去除，输出方向1；原始上传需隐私确认。旧错误冻结 PNG 安全保护限制见文末。 | `core/png_orientation_test.dart` 1–8全像素导入/尺寸/缩略图/压缩/裁剪/拼接，奇数宽高矩阵、重复/坏eXIf、原字节不变及 frozen inputChanged；`core/original_preview_orientation_test.dart` 真SDK PNG1–8/JPEG6/WebP6/APNG方向3/6；`processing/image_processor_test.dart` ICC色彩/隐私字段保护。 |
| IMG-006 | 具备。工作台区域预览及明确整数确认；`PixelCrop/fromSnapshot` 拒绝小数/非有限/零宽/负值/越界；正式坐标在方向后图像上应用，非静默修正。 | `processing/image_processor_test.dart` UT-029 边界与方向JPEG6；`core/png_orientation_test.dart` 1–8实际定向坐标裁剪全像素；工作台错误小数改整数后确认。 |
| IMG-007 | 具备。工作台改顺序撤销旧确认，冻结实际输入顺序；处理 plan 实现横纵/ceil-sqrt网格、最大单元格、间距0–1024、不缩放、剩余/2向下取整居中及空格背景。 | `processing/image_processor_test.dart` UT-030/031 横纵/顺序/三图空格/奇数余量/透明；工作台显式确认顺序；`core/png_orientation_test.dart` 八方向拼接像素不二次旋转。 |
| IMG-008 | 具备软件防护。plan BigInt 估算输入帧、输出画布、解码/方向/中间及编码缓冲，预算前拒绝大画布；worker再核字节/摘要/header；Scheduler 按实际保护与冻结预算分配，系统压力降低新派发。UI提示降低尺寸/减少输入。 | `processing/image_processor_test.dart` UT-032 分配前预算拒绝；`core/processing_scheduler_test.dart` FIFO/预算/取消；`core/processing_memory_pressure_test.dart` 旧预算不变/真实释放后派发。候选额度性能非硬件实测。 |
| IMG-009 | 具备。`_Draft`/`ProcessingRequest` 冻结版本、帧、顺序、策略、保留期；独立压缩逐项收尾，裁剪单项/拼接一组；既有任务不读后改默认值。上传处理依赖也冻结同一参数、不得原图回退。 | `processing/image_processor_test.dart` UT-033 参数快照/独立失败取消；`processing/processing_workbench_test.dart` 批次汇总；`core/upload_processing_*_test.dart` 冻结job、依赖输出校验/重开。 |

## 输出 OUT

| 编号 | 当前生产证据与软件结论 | 有效测试源码证据 |
| --- | --- | --- |
| OUT-001 | 具备。`library_outputs.dart::beginOutput/confirmOutput/_output/_recoverOutputs` 持久 writing/prepared/ready/failed/cancelled/deleting，实际文件摘要/格式/尺寸/来源参数/UTC到期；缺失或坏文件不作为usable操作输出。 | `processing/output_lifecycle_test.dart` UT-034 状态/重开/各提交边界；IT `processing_flow_test.dart` 真实结果重开；`processing/output_preview_reader_test.dart` 租约/摘要。 |
| OUT-002 | 具备。`saveOutput` 复用永久导入日志，`_commitOutputSave` 同关联事务保存 `SavedOutputOrigins`，最终提交后成功；永久副本与临时文件生命周期独立。 | `processing/output_lifecycle_test.dart` UT-035 保存失败、去重、来源、清临时后永久可读；IT `processing_flow_test.dart` 真实工作台保存/重开。 |
| OUT-003 | 具备 Windows 导出。目录取得器→共同 `FileExporter` 流式独占创建、关闭/摘要校验，同名生成新名；每项取消/失败独立报告，不删除应用副本。 | `processing/file_exporter_test.dart` UT-036 同名/并发冲突/权限/取消/来源变化/链接边界；IT `processing_flow_test.dart` fixture目录取得器后实际文件IO与原内容。真实系统选框 PT 排除；Android/iOS原生导出未接入不计Windows缺口。 |
| OUT-004 | 具备。启动及可运行每分钟 `_maintainOutputs/cleanupOutputs` 仅选到期无保护项，writer重验永久/任务/保存/租约，成功删文件后移记录；失败保留重试，无后台准时承诺。 | `processing/output_lifecycle_test.dart` UT-037 恰到期/删除失败、UT-038六状态依赖；`processing/output_preview_reader_test.dart` 实际线程未结束保护；SQL租约释放失败测试排空进程等待但留保护。 |
| OUT-005 | 具备。结果状态、错误、取消与半成品分别反馈，非ready不可保存/预览/上传；真实before/after格式尺寸字节与特征变化/负收益，无固定样本。 | `processing/output_lifecycle_test.dart` UT-034；`processing/processing_workbench_test.dart` 实际失败禁操作/负收益；`processing/output_preview_test.dart` 与reader测试验证真实预览小图、租约/预算/关闭。 |

## 数据 DAT 与非功能 NFR

| 编号 | 当前生产证据与软件结论 | 有效测试源码证据 |
| --- | --- | --- |
| DAT-001 | 具备。`LibraryRepository.open` 安全失败不建空默认；`GalleryController.reload` 失败保留旧列表；保存事务成功后才更新共同状态/反馈；`LibraryFailureView` 重试及数据保全说明，不给破坏性reset。 | `core/library_repository_test.dart` UT-090 已存图来源删除/重开、损坏/未来库不覆盖；`gallery_controller_test.dart` 读取失败旧列表；`library_failure_view_test.dart` UT-093/096 明确保全重试、未知异常不stringify；`core/settings_repository_test.dart` 失败旧值/重开。 |
| DAT-002 | 具备。FK/WAL/FULL实际验证，单writer/跨文件日志、关联事务、持久依赖与actual租约；导入/输出/结果/恢复各有幂等阶段，未确认半成品不可用。 | `core/library_repository_test.dart` UT-091 各边界；`processing/output_lifecycle_test.dart`；`core/upload_repository_test.dart` 结果事务/尝试；`core/backup_merge_restore_repository_test.dart`、`core/backup_replace_restore_repository_test.dart` 与恢复schema测试。这些是具体边界证据，不称真实断电全覆盖。 |
| DAT-003 | 具备。UUID区分资产/内容版本/设备副本，SHA+bytes定内容；处理任务和恢复快照冻结身份/真实摘要，重命名/外部mtime不改远端关联。 | `core/library_repository_test.dart` UT-005/006同大小不同字节/整理保留；`core/import_recycle_boundary_test.dart` 独立版本再入库；`core/backup_merge_plan_test.dart` 内容/身份碰撞；`core/gallery_remote_query_test.dart` 当前版本关联。 |
| DAT-004 | 具备。`TimeSource` UTC clock和Stopwatch monotonic分离；结果按独立attempt/result身份唯一，意图幂等账本保留；恢复映射保留独立身份，重放不按显示时间造事件。执行/退避基于单调持续时间。 | `core/queue_policy_test.dart` UT-067 墙钟跳变不改变实际执行、UT-061不剪Retry-After；`core/upload_history_repository_test.dart` 同intent重试保留一批；`core/backup_result_merge_test.dart` UT-078确认重放幂等；`core/backup_restore_plan_test.dart` 来源/终态历史重放；UT-009 UTC元信息。 |
| DAT-005 | 具备安全演进/待修复软件状态。own schema1–9→10校验，6–9有恢复日志先拒绝，future/损坏/规范版本不兼容保留现场；`LibraryFailureView` 指导完整目录保全、兼容版本/独立新库备份校验与重试。无法确认完整性时不伪造业务备份，未静默重置，也无旧项目迁移。 | `core/library_migration_test.dart` UT-093真实旧schema、非法升级回滚、future原DB/文件不变；`core/restore_schema_recovery_test.dart` 关联保留/畸形日志保全；`core/upload_processing_schema_test.dart` 当前升级保护；`library_failure_view_test.dart` 可理解恢复说明。旧PNG语义修正不自动更改version，见文末。 |
| NFR-001 | 软件响应基础具备，数值性能另行排除。像素/备份重活isolate，流式IO、进度/停止、分页检索，工作台运行仍能读已载入元信息/任务；没有用动画代替持久完成。 | controller/workbench取消与进度测试、gallery分页/revision测试、processing真实worker取消与IO排空测试。300ms与P95≤1s及30/100次参考硬件测量不由源码或单测证明。 |
| NFR-002 | 渐进加载具备，5秒数值另行排除。`GalleryController.build/listAssets(limit:60)` 先读元信息，分页与按显示对象产生缓存预览，不读取全部原图后才展示；缺损状态不清空其他对象。启动必要恢复/日志校验会阻止不安全库使用，不能绕过以追求速度。 | `gallery_controller_test.dart` 首批/分页/旧结果隔离；UT-012 缺损保留元信息；缓存再生及original reader独立测试。四端/参考硬件冷启动时间未在本报告宣称通过。 |
| NFR-003 | 具备当前Windows软件接线。设置缓存64–2048MiB/输出保留期，LRU登记日志及保护；空间探测先于新增写入；Scheduler预算/并发有界。`SystemMemoryPressureMonitor` 在Windows建 `Kernel32MemoryPressureSignal`（Create/QueryMemoryResourceNotification），即时读/2秒候选轮询+Flutter binding；`LibrarySession` 先订阅再start，事件调用reportMemoryPressure，降低新派发/反馈、不取消旧预算；关闭释放定时器/观察/handle。 | `core/processing_scheduler_test.dart`、`core/processing_memory_pressure_test.dart`；`core/system_memory_pressure_monitor_test.dart` native边缘/失败/关闭；`core/windows_memory_pressure_signal_test.dart` Win32 API边界；`core/memory_pressure_session_test.dart` 真实session→scheduler/设置反馈；`core/cache_policy_test.dart`、`core/storage_repository_test.dart` 真实缓存日志/清理与storage容量测试。API接线是源码证据，最终主机验证及硬件压力阈值不在本审查冒充通过。 |
| NFR-004 | 具备可验证状态/保留待修复路径。启动先恢复替换日志，再其他维护；各日志白名单路径/归属/摘要校验后才清，篡改或未知文件保留现场；流/线程/network actual收尾前保护不可解除。异常单项/批次状态真实，无静默清库。 | 导入boundary/源取消、output生命周期、upload提交/晚到证据、backup merge/replace/restore故障测试及IT-010；`core/backup_zip_reader_test.dart` “changed verified image digest preserves every known file ... allows restored bytes retry”避免旧fixture期待被当作生产清理要求。真实断电/文件系统硬件行为排除。 |
| NFR-005 | 具备常见操作中文说明/单位/恢复入口。错误固定分类；界面区分获取、已保存、取消等待、缺损、未知远端结果、原图隐私、静态转换、有损/增大；损坏打开指导保全而不假修复。需求原件有逐条来源与UT/IT/PT/AT设计，本报告提供当前软件映射。 | `library_failure_view_test.dart`、`import_stop_feedback_test.dart`、`gallery_import_exit_test.dart`、workbench状态/背景/静态帧测试及桌面IT。完整人工AT未执行不自动等于缺软件，也不能仅凭widget通过声称每条文案/平台人工验收完成。 |

## 排除项与证据强度

1. 本轮不以 PT 实机、真实硬件性能/压力阈值/断电及系统云来源行为阻断软件开发，也不记为通过。NFR-001/002 的数字、IMG-008/NFR-003 候选额度及 Native 信号出现的硬件表现仍需以后在参考条件测量。Windows系统能力源代码/主机自动化不能冒充其他三端实测。
2. 真实账号上传、删除、主动探测及服务精确契约 CT 独立排除；没有授权发请求。动画原样上传仅列真实生产输入链与受控软件证据，不称真实服务成功。Catbox匿名已按最新范围删除新功能，原件ACC匿名目标被用户决定覆盖；自身旧匿名身份只保留历史/备份读取，不重新启用。
3. Android/iOS导出、其他三端原生能力构建/设备结果不算Windows软件缺口；不把未接线的平台伪装为“只缺设备”。本报告没有据Windows SDK方向结果宣称macOS/Android/iOS方向通过。
4. 每条软件结论依赖当前实现及具体测试断言。共同解码/处理入口可证明静态格式共享实现，但不扩大为全部格式×裁剪×拼接的独立执行矩阵；完整人工AT也没有在本次源码审查中执行。主线程的最终分析、测试和Windows构建应作为执行证据另行记录。

## 自身旧冻结 PNG 元信息限制及安全解释

触发：本项目此前导入真实PNG eXIf方向2–8时，旧decoder未读取eXIf，旧version可能冻结orientation=1及未交换尺寸。此次代码修正后，相同永久字节被核心parser确认不同方向。

- 新导入版本使用真实方向；新生成的缩略图准确帧及原图SDK路径均正确定向，永久原字节保持不变。`library_storage.dart::_ThumbnailRecord` 当前登记formatVersion=1，`_thumbnailRecord` 可复用仍与版本/帧/摘要匹配的旧1缓存；已有错误方向缓存并不会因为生成算法更新而自动失配。这也是需要新缓存代次的软件原因，涉及LIB-001/IMG-005。
- `library_repository.dart::_complete` 相同SHA+bytes先查既有version。available重复返回既有asset；missing/damaged修复只更新DeviceCopy，并不改version元信息。因此普通重复导入/字节修复保留旧UUID、整理、历史、冻结依赖，不能声称已纠正旧尺寸。
- `ImageProcessor` 输入真实方向不等于冻结orientation时明确 `ProcessingFailureKind.inputChanged`，尺寸及摘要也重验；不重新旋转错误快照、不偷偷替换任务参数。`core/png_orientation_test.dart` “frozen legacy PNG version ... refuses inputChanged without mutation”证明这是一条刻意的安全拒绝。
- `library_backups.dart` 完整备份同时比对实际摘要/bytes/格式/尺寸/帧/方向。旧描述不一致列affectedVersions并拒绝完整成功，允许用户明确选择元数据包；不会把不一致版本写成已校验的完整备份。元数据包仍保留旧冻结描述，不能称恢复后语义自动修正。

当前没有显式纠正旧冻结元信息的入口。对普通新导入闭环这不是残余方向算法缺陷；对这些已存在的错误记录，IMG-005正确展示/处理、IMP-006尺寸以及完整备份存在兼容限制。完整备份的拒绝属于DAT-002/003、NFR-004要求的可解释保护状态，不是可降低校验标准的理由。

主线程已于本审查收尾明确后续方案，当前仍待实现及验证：只在同SHA+bytes重导入的真实新暂存检验后，确认旧PNG orientation=1、新方向2–8、帧数相同、旧尺寸恰为反算encoded尺寸的已知错误形状，且实际租约/持久versionReferences无保护时，才在writer/关联事务纠正width/height/orientation，保留身份、永久字节/路径、整理、时间与结果。受保护或其他不一致保留并拒绝，不自动恢复/派发，也不复活回收记录。自有缩略图登记需升格式代次2，仅复用当前代次；旧1严格读取并保留给既有安全LRU流程，未来代次拒绝，不删除未知/使用中/变化的缓存。本次审查未修改生产代码；本报告不能作为该后续修复已完成的证据。

## 2026-10-08 后续有界纠错实施补充（待主线程执行验证）

上述审查后的限定实施已写入 `library_repository.dart` 和 `library_storage.dart`，未在本子任务运行测试、分析或构建。`_pngImportMetadataCorrection` 只认同摘要/字节的已知旧PNG描述形状；available复用、孤立版本新资产、缺损副本发布分别在既有关联事务纠正三个字段。回收重复保持needsRestore；其他不一致invalidImage、file_leases或version_references保护activeUse。修正不改冻结任务/结果/整理/时间、当前永久路径或原字节，不自动执行任务。

available复用的关联提交使用已有committedReuse日志，冻结实际asset/version/copy关联；清stage或删日志失败仍报告已确认repaired/duplicate并保留RecoveryIssue。现有恢复先核对这些关系、完整元信息和真实永久字节，再清日志；不依据缺失stage猜成功，不走发布新字节分支。缓存登记默认formatVersion2，严格读1/2，change/toJson保持读入代次；仅复用2，旧1走既有保护、摘要、归属及LRU规则，未知/未来代次拒绝。

新增 `core/png_metadata_reimport_test.dart` 准备了方向1–8实际SQL/files/像素、身份/名称/标签/收藏/时间保留、处理及完整备份、孤立/缺损/回收、未知不一致、actual lease/持久引用与冻结任务拒绝、committedReuse已删stage+SQL触发器拒删日志及损坏关系保全测试。新增 `core/thumbnail_cache_test.dart` 准备了真实错误像素旧1缓存→正确2缓存、旧reader实际结束/释放前保护、published/deleting跨状态代次保留、使用/未知/变化字节保全及future3拒绝测试。现有 `storage_repository_test.dart` future fixture值为99，不受新增2影响，因此未修改。

另发现永久描述纠正后，旧普通结果/终态历史/来源审计中冻结的同UUID旧描述会与可携带Manifest严格一致性检查冲突。主线程已另行确定严格限制的审计描述关系，并由其他指定实施者处理backup Manifest/merge/restore纯规则；本子任务没有改历史或备份规则。带旧结果/终态历史的正向完整备份用例依赖该后续规则，保持审计SQL逐字段不变，不用改成期待失败或跳过来隐藏问题。此补充记录实施与待验证事实，不预先记为通过，也不据此宣称整个Windows验收完成。

允许的独立SDK格式化尝试在Dart CLI启动阶段失败（`_Platform.resolvedExecutable` 返回Null，exit1），未执行格式化；交主线程正常环境处理四个分配代码文件。未因此运行Flutter、analyze、test或build。
