# Android 软件完成记录

日期：2026-10-08。用户要求持续推进 Android 软件开发至完成，并同意在 `D:\Workspace\DevelopmentTools` 安装所需工具、获取构建依赖及接受标准许可。**用户确认范围内的 Android 软件实现与本轮适用验证已完成；Windows 基线回归通过。** 物理设备、最低 API29、硬件性能/断电、真实账号服务及正式签名发行仍未验收，不据模拟器结果计通过。

## 实际能力和范围

Android 采用已选 M1，复用 Flutter/Dart 领域、Drift/SQLite、永久副本、整理检索、处理、账号、持久队列、网络类型策略、链接、备份恢复、诊断和设置。没有应用云账户、图库云同步、团队、新图床或计费状态。只支持 Catbox userhash 与 ImgBB APIKey，匿名不恢复为上传能力；两家精确生产限制仍 unknown，任务等待，不猜测限额或发送真实请求。

本轮补齐 Android 平台的软件缺口：

- 系统图片/文件选择后按项流式取得，并以独立永久副本完成图库闭环；未读取的选中项也释放授权，停止和退出等待真实 IO。
- M1 回收区恢复、分别确认清记录/永久字节、正常返回/退出和刷新失败反馈；保持最后有效图库，不将错误当空库。
- 处理结果通过 SAF 单文件/目录导出，PNG/JPEG/WebP 可保存到 MediaStore 相册；已关闭、摘要一致、真实读回并确认后才报告保存。
- 完整/元数据 ZIP 系统保存、原生 ZIP 来源复制及共同严格预检、合并/替换恢复；诊断 JSON 通过相同文件桥保存。iOS 未接入的导出保持禁用。
- 实际 StatFs 可用空间与 NDK 同卷原子不覆盖发布；未知平台能力或无法确认收尾时保留保护，不降级为覆盖式 rename、复制或假取消。

M1 从“工具与设置”进入图片处理、账号、备份和设置，任务页创建批次；详情中的编辑/上传快捷按钮仍禁用。业务入口已存在，不据此声称这两个快捷按钮已接线。schema10/28表、可携带Manifest2、DeviceSettings3和缩略图代次2未改。

资源包原件保持不变，未读取旧应用源码/数据库/图库。Android 选型的局部差异有编号和理由：实际插件的提前整批缓存与逐项取消/反馈要求冲突，按技术选型8.3既定Pigeon实现有界桥；详见[原生文件边界](android-native-files.md)，不重新展开框架选型。没有真实图床上传、删除、探测，也没有新增Git提交、推送、PR或发布。

## 修改文件

完整源文件/工具/文档清单见[修改清单](validation/android-changed-files.txt)。自动生成的Dart/Kotlin通道来自真实Pigeon29.0.7，非手写；pubspec.lock来自实际依赖解析。

| 范围 | 主要文件及变化 |
| --- | --- |
| Android原生 | `app/android/app/build.gradle.kts`，`MainActivity.kt`，`AndroidResourceBridge.kt`，`AndroidExportBridge.kt`，`AndroidPublication.kt`，`src/main/cpp/`：Pigeon接线、来源私有登记、有界流/关闭、SAF/MediaStore、真实空间与NDK独占发布。 |
| 平台与核心 | `app/pigeons/android_files.dart`及生成的Dart/Kotlin；`core/platform_resource.dart`；`platform/android_resource_gateway.dart`、`android_export_gateway.dart`、`mobile_file_workspace.dart`、`import_gateway.dart`、`export_gateway.dart`、`backup_import_gateway.dart`：UUID资源、授权释放、独立保存能力和登记暂存。 |
| 图库/M1 | `gallery_screen.dart`、`mobile_gallery.dart`：选择器和实际复制同一追踪、回收、返回和退出、失败反馈；`library_replacement_rollback.dart`只解析可信系统临时根别名，新子项仍严格禁止链接。 |
| 处理/备份/诊断 | `export_models.dart`、`processing_workbench.dart`、`backup_screen.dart`、`diagnostic_exporter.dart`、`diagnostics_screen.dart`：租约保留到真实系统操作结束、正常移动文件/照片保存、成功与清理失败分别反馈。 |
| 测试与工具 | 7个新增测试文件、2个Android原生集成文件；`tool/install_android_tools.ps1`、`android_environment.ps1`、`drive_android_bridge.ps1`、`verify_android_exports.ps1`：工具安装、进程环境、自有模拟器选择器及独立字节核验。 |
| 约定和状态 | 根`AGENTS.md`、两份README、`environment.md`、`software-completion-scope.md`、`windows-v1-coverage.md`及本记录：更新真实平台状态，保留90条原需求和历史里程碑。 |

主线程阅读实际diff及新增实现，核对选择→流→关闭/授权退休、租约→复制→系统发布、备份/恢复维护及秘密视图的调用链，再以实际结果验收。审查不只依据子代理总结或测试数量。本轮Windows回归的[备份设置截图](validation/android-windows-backup-settings.png)单独保留，原PC阶段截图按Git摘要确认恢复，不覆盖历史证据。

## 工具及构建产物

复用 C 盘 Flutter3.47.6 / Dart3.13.5。新增 Temurin JDK21.0.12.1+1、AndroidSDK36（插件另需API35）、BuildTools36.0.0、NDK28.2.13676358、CMake3.22.1、platform-tools37.0.1、emulator37.2.12、API36 Google APIs x86_64 rev7镜像；Gradle9.3.1、AGP9.1.0、Kotlin2.4.0。新增SDK/JDK/Gradle缓存/AVD数据均在D盘工具目录；既有Flutter和Dart依赖缓存继续复用。未迁移C盘工具、重复安装Flutter或修改系统PATH/虚拟化设置。WHPX原已具备。

最终[doctor](validation/android-doctor-final.log)无问题，Android许可全部接受，JDK/SDK实际使用D盘路径。[环境记录](environment.md)与[安装日志](validation/android-tools-install-final.log)保存具体值。自有AVD为 `ImageHost_API36` / `emulator-5558`，SwiftShader、2CPU/2GiB，仅用于软件验证。收尾只停止该自有模拟器，[停止记录](validation/android-emulator-shutdown.log)保留；工具、AVD数据及已安装本地APK不删除。

正常 `lib/main.dart` Release APK已实际构建，使用模板的本地debug签名，不是正式发行包：[构建日志](validation/android-build-release-verified.log)、[包信息](validation/android-release-apk-badging.log)、[摘要](validation/android-release-apk-hashes.json)。

| APK | 实际字节 | SHA-256 |
| --- | --- | --- |
| `app/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk` | 27,334,382 | B038D7ADC2105B3EB9BBF595E6ABFDFBADE25EB609F859A4CABF5A38587BFF22 |
| `app/build/app/outputs/flutter-apk/app-x86_64-release.apk` | 29,375,935 | FCE2EF42064DF724AB1F28D733051520DD3428FCC58DAE6F8375FBA4817B65DA |

minSdk29、target/compile36；ARM64只证明编译，不据此声称物理手机/API29已运行。构建有CupertinoIcons字体提示；当前应用源码无CupertinoIcons引用，实际Android界面的Material图标已检查，未为消除提示增加未使用依赖，也不能由此证明Apple界面正常。

## 实际验证结果

| 分类 | 实际结果和证据 | 证明边界 |
| --- | --- | --- |
| Dart格式 | 266文件，0改动，2.81秒；[日志](validation/android-format-verified.log) | 当前源码/测试/集成/工具。 |
| 分析 | 无问题，58.1秒；[日志](validation/android-analyze-final-success.log) | 整app静态检查，不代表运行或性能。 |
| 全量软件 | **1399通过/1跳过，128秒**；[日志](validation/android-full-tests-verified.log) | 相对Windows基线新增85个实际case（含平台参数化）；真实SQL/files/isolate/SDK、受控通道和widget。唯一非Windows分支在Windows主机跳过，不计通过；不是1399个正式UT。 |
| 新增软件范围 | 网关34、M1回收/退出/刷新18、处理导出10、诊断11、备份12，共85；包含于全量，不相加 | 取消等待、关闭不确定、迟到成功、失败列表、暂存保护、最后有效状态等；受控桥不冒充Android后端。 |
| Android原生共享闭环 | 1项通过，Debug45.3秒/测试40秒；[日志](validation/android-native-smoke-final.log) | 真实SystemSecretStore合成值写/新实例读/删、StatFs、不覆盖/Unicode发布、永久副本/来源移除/整理设置/SDK预览/像素处理/租约关闭、完整ZIP预检合并替换及二次重开、只读网络握手；非真实账号验证。 |
| Android真实系统文件桥 | 1项通过，Debug36.0秒/测试8分03秒；[日志](validation/android-file-bridge-final-success.log)、[运行状态](validation/android-file-bridge-state.json)、[最终驱动](validation/android-bridge-driver-owned-folder-final.log) | 实际文件/照片选择，280502字节/5块/一致SHA，取消，SAF单文件及目录同名两个文件，MediaStore同名两张照片；测试时长含驱动调整等待，不是性能指标。 |
| 源描述符专项 | 32次错误SHA，实际FD164→164；外部源/非图片均invalidInput，不插入拒绝照片 | 包含于真实文件桥，不另加测试通过数；检查显式Os.close实际所有权。 |
| 系统保存独立核验 | **5个结果全部名称/长度/SHA一致**；[日志](validation/android-export-independent-verified-success.log)、[字节结果](validation/android-export-independent-bytes.json)、[媒体状态](validation/android-media-verified.log) | 两张MediaStore pending0、三份SAF文件；SAF普通文件只拉取本任务目录，不给shell额外授权、不root或读取用户文件。 |
| Android正常Release入口 | 导入、正常退出重开、永久原图预览、处理、照片保存、ZIP导出/原生选择/确认合并恢复、JSON诊断保存、最终重开全部通过；证据见下节 | 实际安装正常main.dart包，未以integration_test入口替代用户入口；仅API36 x86_64。 |
| Windows原生回归 | 图库、M1、处理、备份各1项通过；[图库](validation/android-windows-gallery-regression.log)、[M1](validation/android-windows-m1-regression.log)、[处理](validation/android-windows-processing-regression.log)、[备份](validation/android-windows-backup-regression.log) | 本轮改动影响的真实SQL/files/SDK、备份合并替换/故障回滚及重开；不机械重复未受影响的全部原生夹具。 |
| WindowsRelease | 构建87.4秒、自有runner正常WM_CLOSE exit0；[构建](validation/android-windows-release-regression.log)、[退出](validation/android-windows-release-smoke.log) | Windows基线继续可运行，未制作安装包或发布。 |
| AndroidRelease | 两ABI构建123.9秒通过，x86_64正常安装/运行；上节产物/日志 | ARM64构建不是ARM64实机通过；没有正式签名。 |
| 资料完整性 | 资源包31文件/56引用、90条V1属性/业务/验收原文保留、diff空白检查通过 | [资源包](validation/android-kit-verified.log)、[原文](validation/android-coverage-verified.log)、[diff检查](validation/android-diff-check-verified.log)；不是软件测试。 |

## 正常应用入口的独立证据

测试只使用本任务创建的320×256 PNG合成图，280502字节，SHA-256为 `EC97FD77A2753CC22CD90B8DF3A79A13A40E7F5AA6A713F6010E011F72B57AB1`。没有真实用户图片或远端服务请求。[正常闭环记录](validation/android-main-persistence.json)、[实际导出产物及核验](validation/android-main-artifacts.json)。

1. 新装正常Release包展示真实[空图库](validation/android-main-empty.png)。通过“导入图片→从文件选择”选择合成图，收到[1已保存反馈](validation/android-main-imported.png)。
2. 独立核对本任务外部源摘要后删除该唯一测试源；Android正常返回到Launcher后重新启动，图库仍有该资产，[重开图库](validation/android-main-reopened.png)和[永久原图预览](validation/android-main-original-preview.png)都真实可读。未读Release应用私有目录或替换SQL数据。
3. 工作台选择现有资产，默认保真PNG真实处理为ready，并显示[实际输出和预览](validation/android-main-processed.png)。输入与输出同体积时如实显示未减小；相册保存反馈与MediaStore47/pending0相符，独立拉取字节SHA一致。
4. [完整备份已保存](validation/android-main-backup-saved.png)，实际ZIP282532字节，包含Manifest2及唯一永久PNG，PNG摘要与原图一致；经原生ZIP选择、严格预检和确认后[合并恢复提交](validation/android-main-merge-restored.png)，新增0资产，未产生重复或恢复上传许可。
5. [诊断JSON已导出](validation/android-main-diagnostics-saved.png)，实际1813字节、4条冻结事件，与导入/处理/备份/恢复真实事件对应；完整来源路径、秘密及图片均不在导出中。JSON不是只在内存生成，已从外部保存位置独立读取解析。
6. 处理、备份和诊断后再次正常返回Launcher、重新启动，仍有原资产；[正常退出](validation/android-main-normal-exit.xml)、[最终图库](validation/android-main-final-gallery.xml)保留UI证据。

## 遇到的失败与修正

- Android私有新目标硬链接失败，Os.link实际errno13；原因未据此断言为SELinux。改用NDK `renameat2/RENAME_NOREPLACE`，无覆盖/复制后备，再验证冲突保留原字节及中文emoji路径。Release正常导入也验证JNI/R8接线。
- 替换恢复将运行时系统临时根别名当不可信链接拒绝；仅先解析可信根，再创建新命名空间，子项检查不放宽。原生完整合并/替换/重开与Windows回归通过。
- MediaStore pending插入后没有实体字节，旧只读空流探测产生copy/STORAGE与cleanupPending。首次append创建、写前空流核对、真实关闭/摘要读回及所有者/pending检查修正；pending SIZE滞后不当作字节损坏，发布后读取实际名称，两个同名照片均独立确认。没有将cleanupPending改成saved。
- FileInputStream(fd)不拥有传入描述符；改显式Os.open/read/close，32次错误摘要真实FD计数不增长。外部源/伪图片在创建照片前拒绝。
- 系统选择器网格点击落到预览、目录祖先不可点且没有Show roots；驱动按真实UI列表/已观察的自有目录操作，未猜返回导航或放宽目标范围。最终桥测试和五项独立核验均成功。
- 独立ADB验证曾因文字流破坏二进制、URI带字面引号及shell没有SAF授权失败；修为有界exec-out原始字节，精确URI编码，SAF只读取已知测试普通文件。没有给shell新权限或root。
- 初次备份widget加载缺少暴露removeAssets扩展的repository import；修正测试import，不修改业务API。最终备份12专项和全量通过。分析发现native测试冗余typed_data import后移除，最终无问题。
- 初次手动原生文件测试以79/USER_REQUESTED/FORCE_STOP结束，没有据此断言应用崩溃；另一个临时诊断BuildConfig引用编译失败及DDS代理尝试均保留原日志。最终成功只采用上表日志；没有跳过失败断言、吞异常或改写失败日志。
- Drift在独立临时数据库实例的Debug恢复测试输出多实例提示，未据此修改共享executor或静音；正常Release入口另有证据。早期失败/诊断日志继续保留，与最终通过日志分开。

## 尚未验收和后续事项

- 物理Android ARM64、最低API29、厂商选择器/云占位来源/撤权、强杀来源恢复、后台/锁屏/网络切换、读屏/触控、卸载及秘密存储强度、PT/PERF/断电仍未验收；大于4GiB实包和预算校准未实测。不能以模拟器或测试注入当作这些证据。
- Catbox/ImgBB真实CT/IT-008及精确服务能力仍未核验，生产保持unknown等待；没有真实请求授权。下一步在取得服务契约及明确授权后联调，不再测试匿名或计费状态。
- macOS/iOS需要Mac/Xcode；iOS原生保存/导出尚未实现。其他端配置不能作为构建和运行证据。
- 正式Android签名、发行安装渠道和发布未执行。本地APK仅供当前软件预览与后续验收；未新增Git提交或改写PC基线。

以上边界分别保留，不把Android软件完成扩大为四端正式V1、所有正式UT/CT/PT/AT/PERF通过或真实图床已可用。
