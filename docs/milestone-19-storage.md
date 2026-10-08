# 第十九阶段：真实缓存、空间管理与预览文件保护

2026-10-07。继续完整 Windows V1 的90条目标，本阶段实现 OPS-004，并补 OPS-001/005、OUT-004/005、NFR-003 的相关行为；正式条款仍按台账逐项验收。本轮没有新增依赖、安装、下载、系统配置、真实服务请求、提交、推送或发布；资源包只读不变。

## 实际行为

共同设置提供磁盘缩略图容量：默认256 MiB，合法整数64–2048；新输出默认保留可选1小时/24小时/7天。DeviceSettings 自身格式2在既有 LibraryMetadata 中保存，严格读取自身格式1并使用新增默认值，不自动改写原记录；未来/损坏格式拒绝而保留。设置提交后才生效，已有草稿、输出参数和到期不变，替换保留本机策略；可携带设置转移仍待完成。

“空间管理”在桌面与M1复用：真实普通文件长度分别计活跃永久、回收、仅清记录后保留的独立永久字节、缩略图、临时处理结果、操作暂存、数据库/WAL及未登记文件。诊断UTF-8内容单列，不重复加入数据库文件合计。文件长度不等于文件系统分配簇占用，扫描不是正在写入文件的原子快照。系统可用空间未知保留为未知，读失败保留最后有效视图，链接不跟随并明确未计量。

缓存以 LibraryMetadata 的 thumbnail_cache_v1/ 登记独立UUID路径、源版本UUID/真实SHA/字节/帧及实际缓存SHA。writing/prepared/published/ready/deleting记录控制独占暂存、原生发布确认、重开恢复与摘要重验删除。成功原生返回后持久published，准备状态遇到目标即使同摘要也不接管/删除，暂停新增缓存；原生调用成功与SQL确认之间的中断保留未知现场。只恢复未完成状态，稳定缓存在使用/清理时验证，避免每张图重新检查全部已就绪文件。

持久使用序号LRU不因墙钟逆跳倒序；删除最旧且无保护的可再生缓存，未知、变化、未结束或正在使用项保留。保护/未知超限停止新增缓存而解释原因。清理计划冻结全部确认行并绑定owner/epoch，后来新增不加入，使用变化重新核对，逐项删除失败保留日志/字节重试。临时结果入口只清实际执行时到期且无保护的输出；日志入口复用诊断页。永久图片不因这些清理删除。

图库先取得显示保护，实际读取在第一次await前登记进程内IO保护、检查关闭/恢复/epoch，不排在后续缓存生成之后；数据库与文件发布仍只经过唯一写入门。释放等真实读取结束，再把校验字节交Image.memory。维护开始拒绝新的实际读取，已有读取在写入门外排空。页面失效后不发布旧字节或关闭错误。文件路径在实际IO前仍重新检查，不以优化为理由绕过管理路径边界。

处理结果预览原先直接Image.file，已改为OutputPreviewReader：取得真实OutputFileLease、共享FIFO像素许可，isolate有界读取/SHA校验并生成最长边480px、最多2MiB单帧PNG，实际decoder结束后才释放文件和预算。销毁/取消只请求停止，内存小图完成后不依赖临时文件继续存在。第0帧可能是动画容器，先分离准确帧，再做方向/缩放及单帧编码；动画红/蓝指定帧回归保留像素断言。工作台收到替换通知清旧UUID选择与确认，不在同UUID新库上沿用旧选择；未知异常不转字符串。

生产导入前和每个实际写入块、处理输出意图前及缓存发布前检查可用空间；探测未知或余量不足给固定失败反馈和释放途径。32MiB余量、输出估算、Flutter解码缓存32MiB移动/64MiB桌面及100/200数量是候选防护预算，不能据此声称全应用/live image内存上限或四端性能校准。

## 平台边界

Windows复用实际GetDiskFreeSpaceExW和不允许覆盖/跨卷复制的MoveFileExW。正常路径原生测试使用真实通道，无容量或发布mock。低层Dart文件测试可省略探测及使用rename后备，仅验证日志/摘要语义，不代表生产独占发布契约。

Android接StatFs.availableBytes和Files.createLink(destination,source)后unlink；Apple接statfs与POSIX link/unlink。独占目标已存在返回false，跨卷/权限等固定失败，发布后源unlink失败保留已确认目标供安全暂存收尾。路径拒绝非绝对、越界形式、符号链接祖先和非普通源；上层提供私有、关闭、同卷暂存。它不是基于目录描述符的恶意并发祖先置换防御。Application Support现有基目录先解析系统别名，再添加本应用全新命名空间。

Apple Runner已登记PrivacyInfo及磁盘空间/文件时间理由，未添加签名或外部权限。Android SDK/设备缺失；macOS/iOS需要Mac/Xcode/设备，三端仅源码和协议验证，不报告构建或运行通过。参考实际接口来源：[Android StatFs](https://developer.android.com/reference/android/os/StatFs)、[Files.createLink](https://developer.android.com/reference/java/nio/file/Files#createLink(java.nio.file.Path,%20java.nio.file.Path))、[Apple link](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man2/link.2.html)、[Apple statfs](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man2/statfs.2.html)。

## 修改文件

- 新生产：`features/storage/domain/storage_models.dart`、`presentation/storage_screen.dart`；`features/gallery/data/library_storage.dart`；`features/processing/application/output_preview_reader.dart`、`presentation/output_preview.dart`。
- 修改共同接线：`core/managed_file_store.dart`、`platform_resource.dart`、`image_inspector.dart`；`library_repository.dart`、`library_outputs.dart`、`library_settings.dart`；`gallery_providers.dart`、`asset_widgets.dart`；`processing_coordinator.dart`、`processing_workbench.dart`；`device_settings.dart`、`settings_screen.dart`；`platform/storage_capacity.dart`、`library_location.dart`及`main.dart`。以上生产路径均在`app/lib/`，未改schema8/27表或锁文件。
- 原生：Android MainActivity；iOS AppDelegate、macOS MainFlutterWindow及两端PrivacyInfo/project.pbxproj资源登记。Windows通道源码沿用已有实现。
- 新验证：缓存策略、真实空间仓储、空间页、平台协议、处理预览reader/widget及`integration_test/storage_flow_test.dart`。修改设置/未来格式夹具、工作台替换选择和桌面/M1原生IO交替辅助函数；没有放宽原业务/字节/选择/清理断言。
- 根`AGENTS.md`、两份README、架构、环境、90条台账及本记录同步。

主线程已阅读实际生产与测试接线；Sol子代理均以gpt-6.1-sol/high完成限定平台、设置/页面及验证文件，无继续委派。全部Flutter/native/build由主线程串行执行，未仅凭代理总结验收。

## 实际验证

- 初轮专项83项core/widget/protocol通过，27秒：[专项](validation/windows-storage-focused-second.log)。发布归属追加后仓储/策略37项通过，5秒：[核心](validation/windows-storage-core-third.log)；不是正式UT数量，最终还追加两个读取/维护边界用例纳入全量。
- 处理预览8项核心、4项widget全部通过，8秒：[预览](validation/windows-storage-preview-tests.log)。门控在可替换decoder的真实File.openRead循环，生产isolate另作真实解码/SHA验证；替换widget仅证明revision契约，不冒充完整恢复提交。
- 多图回归52项通过，39秒：[图库回归](validation/windows-storage-gallery-second-retest.log)。保留原200次20ms的名义4秒IO轮询预算，改为2000次2ms、更细fake tick，提供更多原生/假时间交替，避免网格加载时人为推进每分钟维护。没有删去超时、选择或异常断言。
- 当前最终821项全部现有单元/widget混合测试通过，79秒：[全量](validation/windows-storage-full-second.log)。不等于821个正式UT或90条首版通过。全部首轮失败与边界追踪记录保留。
- 资源包31文件/56引用完整性通过：[资源](validation/windows-storage-kit.log)；90条V1规范原文完整性通过：[台账](validation/windows-storage-coverage-integrity.log)。这是文档完整性，不是软件测试。
- Windows原生IT-006子流程第二轮1项通过，Debug27.0秒/运行6秒：[原生](validation/windows-storage-integration-second.log)、[真实截图](validation/windows-storage.png)。真实容量/独占发布、清理范围、保护/未知字节、新缩略图、设置SQL与重开；模拟低空间和门控读明确仅受控注入。截图为默认MaterialApp测试入口，不是生产主题或完整PT。

- 最终185文件格式检查0改动：[格式](validation/windows-storage-format-final-check.log)；整app静态分析无问题，5.5秒：[分析](validation/windows-storage-analyze-pass.log)。
- 最终Windows空间流程1项通过，Debug27.3秒/运行7秒：[最终空间原生](validation/windows-storage-integration-final.log)；设置保存/重开及真实像素工作台回归1项通过，Debug27.8秒/运行11秒：[设置回归](validation/windows-storage-settings-regression.log)；图库远程条件/本机刷新/移除/重开回归1项通过，Debug28.7秒/运行2秒：[图库原生回归](validation/windows-storage-gallery-native.log)。这些是对应编号的子流程，不等于完整IT或人工AT。
- 最终资源包31文件/56引用及90条原文完整性仍通过：[资源最终复核](validation/windows-storage-kit-final.log)、[台账最终复核](validation/windows-storage-coverage-final.log)。

- 当前Windows Release重新构建成功，92.0秒：[构建](validation/windows-storage-build.log)。仅启动本次自有隐藏原生窗口，确认创建后正常WM_CLOSE退出0：[启动退出](validation/windows-storage-release-smoke.log)。没有发布；这不是完整人工功能、系统对话框或性能验收。

首轮动画第0帧带多帧容器生成APNG，被严格单帧校验拒绝，已分离指定帧且不放宽校验；新增原生下拉测试被文本caret动画改变滚动位置，已先释放焦点并验证hitTestable后真实点击；全量暴露稳定缓存恢复重复IO、实际读取排在后续生成之后，以及销毁后迟到错误，已修边界并通过全量。临时追踪仅输出合成测试边界，现已移除，失败日志保留。

## 下一阶段

完整Windows首版仍未完成：网络/计费观察、单项暂停、远端删除、自动处理依赖、完整服务契约及明确授权联调、跨平台设置转移、参考负载性能与完整人工平台验收继续推进。完整IT-006/AT-004/005/PT和真实磁盘耗尽未执行；缓存、内存、输出和空间候选预算仍待设备校准。共同源码支持四端业务，不把其他三端配置当运行证据。
