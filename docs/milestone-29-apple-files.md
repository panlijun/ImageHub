# 里程碑 29：Apple 文件与照片能力

日期：2026-10-09。**本轮 Apple 原生文件能力的软件实现及适用验证已完成。** iOS 图片/文件/备份/诊断保存与 macOS/iOS 备份取得已接入，Windows/Android 完成基线保持。正式名称和稳定存储身份保留，资源包只读；设备及真实服务范围见末节。

## 实现

- 新增共享 Swift 文件引擎与真正生成的 Pigeon 接口；iOS Files 目录独占导出和 Photos addOnly 保存、Apple 备份 ZIP 选择及授权收尾已接入共同工作台/备份/诊断路径。
- 共同私有备份复制从现有 Android 实现提取，保持原行为；macOS 桌面导出仍走既有 file_selector/FileExporter。
- 默认同名生成新名，实际 SHA/长度及源/目标身份校验，取消等待真实 IO，晚到成功保留；关闭/清理不确定保留现场和授权登记。
- 选型 8.1/8.2 的具体差异、实现边界和官方依据见 [Apple 原生文件说明](apple-native-files.md)。

## 修改文件

| 文件或目录 | 修改职责 |
| --- | --- |
| `app/pigeons/apple_files.dart`、`app/apple/generated/AppleFiles.g.swift`、`app/lib/platform/generated/apple_files.g.dart` | 临时 UUID 资源/位置/操作、有界读块及严格结果协议，生成文件由 Pigeon 29.0.7 真实生成 |
| `app/apple/AppleFileEngine.swift` | 范围授权、协调读取、来源与目标身份/摘要、独占流式复制及已登记暂存收尾 |
| `app/ios/Runner/IOSFileBridge.swift`、`AppDelegate.swift`、`Info.plist`、iOS project | 自有 Files 选择器、PhotoKit addOnly、宿主注册、照片用途说明和原生源/测试编译接入 |
| `app/macos/Runner/MacFileBridge.swift`、`MainFlutterWindow.swift`、macOS project | 自有 NSOpenPanel ZIP 取得、沙盒范围授权、迟到回调及宿主注册 |
| `app/lib/platform/apple_resource_gateway.dart`、`apple_export_gateway.dart`、`backup_import_gateway.dart`、`export_gateway.dart`、`mobile_file_workspace.dart` | Dart 能力路由、实际 IO/取消等待、共同私有复制、授权退休及严格平台保存收据 |
| `app/lib/platform/export_mime.dart`、`android_export_gateway.dart` | 提取共同 MIME 映射，保留现有 Android 保存行为 |
| `app/lib/features/backup/presentation/backup_screen.dart` | iOS 文件收据确认成功，晚到保存与清理警告分别展示 |
| `app/apple/AppleFileEngineTests.swift`、两平台 `RunnerTests`、`app/test/platform/` 和 `mobile_backup_export_test.dart` | 真实原生文件 IO、窗口所有权、Photos 实际事务及 Dart/SQLite/ZIP/widget 回归 |
| 三个备份 widget 测试、`app/integration_test/backup_flow_test.dart` | 测试取得器明确宿主，避免 Mac 软件测试误打开真实选择器 |
| `app/integration_test/apple_native_smoke_test.dart`、`app/tool/ci/verify_apple_file_tests.py`、`.github/workflows/apple.yml` | 真实 Pigeon 通道、原生 XCTest 与严格 xcresult 数量/失败/跳过核对 |
| `AGENTS.md`、根/应用 README、`docs/apple-native-files.md`、环境/范围/GitHub/本记录及 `docs/validation/` | 更新约定、实际结果、原始失败证据和交付边界 |

## 实际验证结果

验证源为 `9715ce96b201eefe4192f8ca1eeffc13482d952d`；[Apple CI run 37879708343](https://github.com/panlijun/ImageHub/actions/runs/37879708343) 整体 **success**，Mac job `113656331164` 与 iOS job `113656331026` 均 success。[触发身份](validation/apple-files-second-ci-dispatch.json)、[终态与产物](validation/apple-files-second-ci-state.json)保存真实源和步骤。下表的混合软件测试数字是执行用例数，不能相加为独立正式 UT 或四端 PT 通过数。

| 验证 | 实际结果与记录 | 覆盖边界 |
| --- | --- | --- |
| 最终 Windows 软件回归 | **1,427 通过/1 平台分支跳过，6 分 18 秒**；[全量](validation/apple-transfer-final-windows-software-tests.log)，分析无问题66.7秒；[分析](validation/apple-transfer-final-analyze.log) | unit/widget、真实本机 SQL/files/SDK；跳过非Windows来源分支 |
| Windows 原生回归 | 处理、备份、诊断三个子流程各 **1 项通过**；[处理](validation/apple-transfer-windows-processing_flow.log)、[备份](validation/apple-transfer-windows-backup_flow.log)、[诊断](validation/apple-transfer-windows-diagnostics_flow.log) | 实际字节、SQLite、处理保存/同名保护、恢复重开和诊断出口，未请求图床 |
| Windows Release | 正常入口构建 **53.8秒**成功，自有隐藏runner真实创建/正常WM_CLOSE退出0；[构建](validation/apple-transfer-final-windows-release-build.log)、[启动退出](validation/apple-transfer-final-windows-release-smoke.log)、[产物摘要](validation/apple-transfer-final-windows-release-files.json) | 运行需要完整Release目录；EXE沿用未改的native host，当前Dart AOT真实重建 |
| Android ARM64 Release | 构建 **161.6秒**成功，**27,948,264字节**；[构建](validation/apple-transfer-android-arm64-build.log)、[SHA](validation/apple-transfer-android-arm64-apk.json) | 正常入口优化APK，沿用本地debug签名；本轮未新增ARM64设备运行证据 |
| Mac 软件/进程 | **1,424 通过/4 Windows分支跳过，6分47秒**；分析无问题39.3秒、273文件格式0改动；六提交边界独立进程exit恢复、正常重开和排他锁全部通过；[原始job](validation/apple-files-second-macos-job.log) | 真实macOS26.6.2 arm64/Xcode26.6，进程退出与故障注入不等于硬件断电 |
| Mac 原生/XCTest/Release | Flutter原生 **4项通过**；XCTest **23通过/0失败/0跳过**，其中共享引擎15项、panel8项；正常入口Release `ImageHub.app` **64.5MB**构建成功；[原始job](validation/apple-files-second-macos-job.log) | 实际statfs/独占发布、SQLite/永久副本/图库/像素/IO保护、Keychain/被动网络/Pigeon和共享文件IO；panel回调为受控窗口协议 |
| iOS 原生/XCTest/应用 | Flutter原生 **4项通过**（执行12秒，初次Xcode编译165.3秒）；XCTest **20通过/0失败/0跳过**，共享引擎15项、picker/Photos5项；正常入口未签名Simulator Debug构建成功（Xcode123.1秒）；[原始job](validation/apple-files-second-ios-job.log) | 真实iOS26.2/iPhone17 Simulator；PhotoKit合成PNG保存实际系统事务通过，来源保留/私有暂存退休；picker回调为受控窗口协议 |
| iOS 自有设备清理 | 本轮UUID `6ed2271c-e5c3-4038-87e7-d55074702812` 核对Booted及SpringBoard PID12423后使用；结束后核对本轮身份、关闭、读回Shutdown、删除及读回缺席均成功 | 未删除其他模拟器、未下载额外运行时；只给本应用photos-add授权 |
| 受控 iOS 备份收据回归 | **26项通过**；[定向记录](validation/apple-ios-backup-receipt-tests.log) | 真实SQLite/files/ZIP+受控系统回复，覆盖完整/元数据备份及取消后晚到保存/清理警告；这些不是原生Photos或Files UI证据 |

共同源码/原生结果检查器分别核对，不以协议模拟、构建或授权成功代替系统保存。共享引擎的关闭故障注入在真实关闭后报告未知，只证明保护分支，不证明硬件关闭故障。Photos addOnly用例核对闭合来源/私有暂存字节并取得系统事务成功，**没有独立读回Photos中的外部副本**，也未验证全部图片格式。

资源包31文件/56引用完整性、实际Git diff空白检查通过，依赖锁文件、schema10/28表、Manifest2及DeviceSettings3均未变更。

## 当前可运行产物

- Windows：`app/build/windows/x64/runner/Release/imagehub.exe`，保留同目录DLL、data等完整文件；本轮正常启动退出通过。
- Android：`app/build/app/outputs/flutter-apk/app-release.apk`，ARM64，SHA-256 `ED1813F4BE364F1A9CD041A7DCAFA1FAEACBF0E2D9093FDCD715B36016BC363D`；API36 x86_64正常应用闭环仍以里程碑28为准。
- [Mac CI产物11593999604](https://github.com/panlijun/ImageHub/actions/runs/37879708343/artifacts/11593999604)：25,969,424字节，SHA-256 `590e6df5271a59b15163c0c9c996f1aa62869982044d6eff976b0a455124943e`，含Release应用ZIP、xcresult/摘要及验证日志。
- [iOS CI产物11594480677](https://github.com/panlijun/ImageHub/actions/runs/37879708343/artifacts/11594480677)：70,958,594字节，SHA-256 `7c34d06155ab7ffc30fa421496f5ff3433c832ae9243dd5117169d907e54b90f`，含正常入口Simulator Debug应用ZIP、xcresult/摘要和设备/原生/构建/清理日志。它不能在物理iPhone作为IPA安装。

两个CI产物保留7天，2026-10-16到期；长期Git记录保留原始job日志和状态元数据。本轮没有正式签名、公证、安装包或商店发布。

## 失败与修正保留

- 初次定向测试122通过/2失败，带空格URI解码比较和点路径归一化拒绝两项修正后Apple导出10项通过；[初次](validation/apple-transfer-focused-tests.log)、[修正](validation/apple-export-correction-tests.log)。
- 新增元数据widget的初次枚举名称写错，修为既有`BackupMode.metadata`，未改业务枚举；[原始编译失败](validation/apple-ios-backup-receipt-initial.log)。iOS备份成功显示原先仅识别Android content收据，已修平台确认入口，新增回归验证实际ZIP及反馈。
- 首轮源`cd89fbd`的[run37877660868](https://github.com/panlijun/ImageHub/actions/runs/37877660868)两作业failure；Mac1420软件测试/4跳过及四原生用例通过，但XCTest回调throws类型转换编译失败；iOS四原生用例和应用构建通过，但XCTest目标匹配失败，小写UUID与列表的大写/多架构记录不一致。修正Mac非抛出断言及同一自有iOS UUID的大写+arm64后，第二轮真实通过；大小写与架构一起变更，没有隔离证明哪个因素单独导致匹配失败。
- [首轮状态](validation/apple-files-first-ci-state.json)、[Mac原始失败](validation/apple-files-first-macos-job.log)、[iOS原始失败](validation/apple-files-first-ios-job.log)保留，未将首轮XCTest/Photos记为通过。Windows首轮1423通过/1跳过属于较早源重跑，不与最终1427相加。

实现提交`cd89fbd`及修正提交`9715ce9`已按授权推送。最后记录提交只改说明/日志（包括应用README的旧禁用说明），使用文档提交跳过指令避免重复运行相同源码；运行代码、平台配置、生成接口、依赖和Apple工作流与成功源相同，见[交付前Git核对](validation/apple-files-delivery-source-check.json)。跳过方式依据[GitHub官方说明](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/skip-workflow-runs)，成功CI仍明确关联`9715ce9`，不冒充最终文档提交另有测试运行。

## 未计通过

物理设备、最低macOS12/iOS15/Android29、真实选择器/Files提供者UI、权限拒绝与撤回的系统行为、Photos其他格式/外部副本独立读回、参考硬件PERF/断电、四端人工互读、正式签名/公证/发行均保留。真实Catbox/ImgBB上传/删除/探测没有联调授权，精确能力unknown守卫继续拒绝派发。

下一阶段按用户选择处理真实服务契约与账号联调，或准备正式签名/分发；上述均需要相应授权。设备验收继续按用户排除范围保留，不计通过，也不据其缺失重新打开本轮已完成的软件开发事项。
