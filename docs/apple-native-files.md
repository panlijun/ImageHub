# Apple 原生文件能力

2026-10-09 本轮实现；实际构建和测试结论以 [里程碑 29](milestone-29-apple-files.md) 为准。`imagehost-new-project-kit/` 原件不变。没有新增依赖、数据库格式、图床或云同步。

## 入口和边界

| 入口 | 接入方式 | 交付证据 |
| --- | --- | --- |
| macOS/iOS 备份 ZIP 取得 | Swift NSOpenPanel / UIDocumentPicker → 临时 UUID 资源句柄 → 64 KiB 原生读取 → 共同私有复制服务 | 真实关闭、长度/SHA 登记且来源授权退休后才交给恢复预检 |
| iOS 单个/批量文件、备份、诊断保存 | UIDocumentPicker 选目录 → 注册本批 operation UUID → 独占创建新文件、冲突生成新名 | 实际流式复制、fsync、关闭、目标读回 SHA/长度以及来源身份复核 |
| iOS 图片保存 | Photos addOnly → PHAssetCreationRequest 文件资源，shouldMoveFile=false | 真实 performChanges 回调确认，返回有界不透明 ph URI；永久来源字节保留 |
| macOS 桌面文件导出 | 保留已有 file_selector 与 FileExporter | 已有真实流式复制和同名保护 |

`app/pigeons/apple_files.dart` 由现有 Pigeon 29.0.7 生成 Dart/Swift 配套接口。UIKit/AppKit 只负责自有选择器及授权，`app/apple/AppleFileEngine.swift` 管理范围授权和实际 IO；Dart/UI 不把外部 URL 当作永久副本。外部 URL、bookmark 和范围授权不进入业务 SQL、诊断或可携带备份。

原生引擎在选择登记时不打开数据；第一次真正读取才冻结 inode/device/长度/修改时间，逐块读前后复核，禁止链接和不普通文件。来源有明确未下载的 ubiquitous 标记时报告 cloudPending，不主动下载。其他提供者、阻塞云来源和真实系统 UI 仍需 PT，不承诺任意提供者可在限时内收尾。

导出仅接受本应用私有根中的闭合副本，先校验真实 SHA/长度，再用 O_CREAT|O_EXCL 和 O_NOFOLLOW 写入目标。取消等待实际原生完成，确认后迟到取消保留 saved 证据。只有确属本次创建、实际关闭且 inode/长度/摘要未变化的半成品才可清理；不确定关闭、变化、链接或未知归属保留现场和授权登记，不能记为成功清理。

PhotoKit 使用独立已校验暂存文件；实际系统事务结束后才收尾。照片保存成功与私有暂存清理失败分别反馈，不以分享返回、URI 生成或授权成功充当照片保存成功。共同工作台、备份页和诊断页复用既有能力路由，不在原生端复制图库或恢复业务。

选择器单实例、严格 v4 UUID、规范小写身份与有界退休记录共同隔离迟到回调；只取消自己的窗口。已退休选择 ID 不能复用。目录登记每批最多 1,000 项、句柄最多 256、会话操作/退休记录最多 10,000 为防护候选上限；达到上限拒绝新操作，不悄悄遗忘旧证据。它们不是性能验收结果。

## 与选型 1.0 的差异

- **8.1** 原文通用文件入口为 file_selector。Apple 备份 ZIP 改由现有已选 Swift/Pigeon 桥持有范围授权和 NSFileCoordinator，避免外部位置或插件临时路径成为恢复长期依赖；其他图片导入入口不在本轮改造。Android 前阶段差异单列于 [Android 原生文件说明](android-native-files.md)。
- **8.2** iOS 原文描述 UIDocumentPicker 导出副本。本实现仍从已闭合私有副本导出，但选择目录后由原生独占复制，确保 **OUT-003** 默认同名生成新名而不覆盖，并可以逐项校验实际目标。系统提供者若不支持该方式明确失败，不改为猜测成功或分享后备；真实第三方 Files 提供者仍待 PT。
- **8.3/T-12** 使用既定 Flutter Pigeon/Swift 系统桥；不变更框架选型。**OUT-003、PLT-005、BAK-006、OPS-003** 的失败、取消、保护及成功证据要求继续执行。

## 验证分层

Dart 受控协议测试验证 URI/身份边界、取消与迟到保存、授权收尾以及私有复制；不称原生 API 已通过。共享 Swift XCTest 使用真实临时文件验证有界读取、独占复制、同名保护、摘要/身份变化、链接拒绝、取消和关闭不确定保护。macOS panel 和 iOS picker 测试注入窗口回调，只证明所有权/收尾协议；不会记系统 UI 的人工选择和拒绝为通过。

CI 在已确认自有 iOS26.2/iPhone17 Simulator 上仅给本应用 photos-add 授权，真实 PhotoKit 用例创建合成 PNG、执行系统事务并检查来源保留及暂存退休；不会读取已有用户照片。xcresult 摘要必须包含全部预期 XCTest、零失败、零跳过。真实 Pigeon 原生 smoke 单独验证宿主登记、类型通道与无授权 IO 拒绝。

最低 macOS12/iOS15、物理设备、真实 Files 云提供者、Photos 格式互操作、PT/PERF、四端人工闭环与正式签名发行不据自动化软件检查计通过。

## 官方依据

- [Apple 目录访问](https://developer.apple.com/documentation/uikit/providing-access-to-directories)：目录选择、范围授权及协调读取。
- [macOS 沙盒用户文件访问](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox)：用户选择授权与沙盒边界。
- [PhotoKit 文件资源](https://developer.apple.com/documentation/photos/phassetcreationrequest/addresource%28with%3Afileurl%3Aoptions%3A%29)、[shouldMoveFile](https://developer.apple.com/documentation/photos/phassetresourcecreationoptions/shouldmovefile)：从文件添加、保留来源副本。
- [Xcode 测试](https://developer.apple.com/documentation/xcode/running-tests-and-interpreting-results)、[命令行工具](https://developer.apple.com/documentation/xcode/xcode-command-line-tool-reference)：xcodebuild 与 xcresult 原生结果。
