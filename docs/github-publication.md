# GitHub 公共仓库与 Apple 验证

当前阶段：[公共仓库 panlijun/ImageHub](https://github.com/panlijun/ImageHub) 已创建并推送。第三轮 iOS Simulator 原生验证及应用构建通过；Mac 软件/进程检查通过，图库 smoke 的目录准备问题正在修复并继续验证。

## 已公开内容

- 用户于 2026-10-08 确认正式名称 **ImageHub**，授权公开 `panlijun/ImageHub`、提交推送及运行 CI。新建空公共仓库成功，未接管旧项目；[创建元数据](validation/github-repository-created.json)记录仓库 ID、public 状态及创建时间。
- 保留首次 PC 提交 `d642ebc`；纳入当前 Android 已完成改动、实施记录及 Apple CI。原资源包不改写，不加入旧项目源码或应用数据。
- 当前扫描未发现真实图床凭据、私钥、生产资料库或个人照片。测试值和图片为合成样本。SDK、依赖缓存、应用 build 产物及 Android 机器配置保持忽略。
- 现有提交历史的作者姓名/邮箱、验证日志的本机用户名/目录，以及部分 Word 作者和模拟器状态元信息会随公开历史可见。这些不是应用秘密，但不能称历史已彻底脱敏。若要避免公开这些元信息，需要另行决定公开内容与历史，不能擅自重写首次提交或修改资源包。
- 未指定项目开源许可证；公开托管不等于自行授予 MIT 等许可。保留现有第三方版权说明。
- 当前显示名称、窗口标题、系统应用标签和新导出名称统一 ImageHub；资源包及历史原件不改，Dart package/应用 ID/永久库和秘密命名空间保持稳定。Windows CompanyName/ProductName 技术身份参与 `path_provider_windows` 的目录生成，保留这些字段，避免应用改名后另开资料库。Windows 新二进制为 `imagehub.exe`，macOS 新应用为 `ImageHub.app`。

## Apple CI

工作流为 `.github/workflows/apple.yml`，只使用 GitHub 的标准 `macos-26` Apple Silicon runner。无大型收费 runner、主动扩容缓存、App Store/TestFlight 发布、真实图床调用或 Apple 签名凭据。

每个任务从项目声明读取 Flutter 3.47.6 基线，在[官方 macOS 发布元数据](https://storage.googleapis.com/flutter_infra_release/releases/releases_macos.json)中查找唯一 stable arm64 档案并验证 SHA-256。2026-10-08 只读核实的档案 SHA-256 为 `a1946d3b6b3de15ce247dc89649df9035ce29e6b4e7ebe91919a25890ea2e79a`，HEAD 返回 200、2,263,212,963 字节；本机没有下载此档案。SDK 只安装在该任务的临时目录；依赖按提交的锁文件解析。没有设置长期付费缓存。

macOS 任务执行资源包完整性、分析/格式、完整软件测试、独立进程恢复/锁、真实 Apple engine 集成验证和 Release 构建。iOS 任务选择预装且可用的 iPhone 模拟器，执行同一原生验证，再构建未签名模拟器应用；缺运行时明确失败，不自动大型下载。命令失败通过 `pipefail` 保留，不能因 `tee` 把失败记成功。

证据及压缩应用产物只保留 7 天；应用产物供开发验证，不声称已签名、公证、可在真实 iPhone 安装或正式发行。CI 任务之间不存在永久图库；重开测试使用测试自有暂存及合成图，在同一任务中完成。

## 验证边界

- 只有实际远端运行的日志、提交 SHA、job 状态和产物才能证明 Apple 构建/测试结果。工作流源文件存在不代表通过。
- 本轮 GitHub 目标不把 macOS/iOS 全部产品接入工作缩减为构建成功。iOS 保存/导出、macOS 备份取得和其余设备验收仍按真实实现及证据记录。
- 测试不读取个人图库，不枚举其他凭据；安全存储只使用独立 UUID 的合成值并执行清理。缺系统后端不使用明文或 fake 后备。
- Keychain 用例中的“新实例读取”仍在同一进程，不能表述为 Keychain 跨进程重开。图库 SQLite 关闭/重开与 Mac 主机独立进程恢复另有真实验证入口。
- 公开标准 runner 的计算时间按 GitHub 当前规则免费；产物存储另核对账户用量。没有授权计费、签名发行或其他外部服务开通。

## 本机准备验证

- 269 个 Dart 文件格式检查：0 改动；[记录](validation/github-apple-format-verified.log)。
- 当前应用和新 Apple 用例分析：无问题，5.9 秒；[记录](validation/github-apple-analyze-verified.log)。首次两处 lint 已修正，首次输出保留。
- 工作流 YAML 解析与两任务结构检查通过；[记录](validation/github-workflow-yaml.log)。两份 Python 脚本语法编译通过；不是 Apple 运行结果。
- 资源包 31 文件、56 引用完整性通过，未修改原件。
- 完整 Windows 软件回归：**1399 通过、1 个非 Windows 分支跳过，6 分 41 秒**；[记录](validation/github-software-tests.log)。本次使用并发 2；测试时长不是应用性能指标，也不新增正式 UT/PT 通过数。
- 修改后的独立进程工具通过：6 个提交边界的实际子进程退出恢复、稳定 UUID/字节校验、正常关闭重开，以及跨进程排他锁拒绝与释放；[记录](validation/github-process-recovery.log)。这些是 Windows 主机结果，不是 Apple 进程验证或硬件断电验收。
- ImageHub 名称修改后：269 文件格式 0 改动、分析无问题，受影响图库/分享/ZIP/诊断 **69 项回归通过**；[格式](validation/imagehub-format.log)、[分析](validation/imagehub-analyze.log)、[回归](validation/imagehub-brand-regression.log)。这 69 项是已有软件用例的重跑，不与 1399 相加。Android manifest、Apple plist 与 macOS scheme 的 XML/属性表语法检查通过；原生编译待实际构建。

## 发布授权

先前自动审批未将目标状态识别为直接公开发布授权，已在用户本轮明确确认后解除。现有 Git Credential Manager 登录与 GitHub 连接器均确认账号 `panlijun`；通过官方 GitHub API 创建公共 `ImageHub` 仓库成功。没有在聊天、日志、文件或远端 URL 中保存令牌。

## 首次发布与实际失败

`e10e4c09a2cc4b555e1828503e303cf4f57bb1fd` 已推送 `main` 并设置 `origin/main`。无凭据 `git ls-remote` 取得同一 SHA，公共 API visibility 为 public；[远端证据](validation/github-first-remote-state.json)。原 `d642ebc` 历史保留。

[首轮 run 37772582915](https://github.com/panlijun/ImageHub/actions/runs/37772582915) 终态 failure、零 jobs，不能计 Apple 测试或构建通过；[实际状态](validation/github-first-ci-failure.json)。工作流在 job.env 使用了未允许的 runner context；[官方上下文范围](https://docs.github.com/en/actions/reference/workflows-and-actions/contexts#context-availability)确认该限制，改为运行步骤从 RUNNER_TEMP 写入 GITHUB_ENV，再验证新提交。

本机改名后的 Windows 第一次构建也失败：[日志](validation/imagehub-windows-release.log)。CMakeCache 的旧自动 CMAKE_INSTALL_PREFIX 为 `$<TARGET_FILE_DIR:imagehost>`，当前 target 已改 imagehub，来源是本项目已有构建缓存。只对该已确认缓存项重新配置，不更改资料库或依赖源码；修正后的实际结果另记。

## ImageHub 名称构建与第二轮 CI

- Windows 只刷新已确认的旧 `CMAKE_INSTALL_PREFIX` 缓存后，Release 构建通过（61.3 秒），`imagehub.exe` 原生启动并正常关闭、退出码 0；[构建](validation/imagehub-windows-release-verified.log)、[启动](validation/imagehub-windows-release-smoke.log)、[名称与摘要](validation/imagehub-windows-release-metadata.json)。exe 的摘要不等于包含 DLL 和 data 的完整程序目录摘要。
- Android 第一次 `--no-pub` 构建使用了之前测试流程留下的 `integration_test` 注册器，Release Gradle 不包含该开发插件，Java 编译失败；[原始输出](validation/imagehub-android-release.log)。Flutter SDK 的正常构建入口会按 Release 模式重新生成并排除开发插件，未手改生成文件或删除测试依赖。正常构建的 ARM64/x86_64 APK 已通过，系统标签为 ImageHub，应用 ID 保持 `io.imagehost.imagehost`；本轮最终 APK 记录见[构建](validation/imagehub-android-release-verified.log)和[元信息](validation/imagehub-android-release-metadata.json)。新相册保存目录采用 `Pictures/ImageHub`，先前文件不迁移、不删除；此名称修改的编译检查与此前真实系统保存验证分开。
- [第二轮 run 37773260834](https://github.com/panlijun/ImageHub/actions/runs/37773260834) 对应 `5f666e04a3aee775c73a8826ec769acc2fc0de0d`，两个作业实际使用标准 `macos-26` arm64，整体终态 failure；[终态及逐步骤证据](validation/github-second-ci-state.json)。macOS 26.6.2 / Xcode 26.6 主机的完整软件测试 **1396 通过、4 跳过，8 分 2 秒**，独立进程恢复六个边界、正常重开及跨进程锁全部通过；[原始 Mac 日志](validation/github-macos-5f666e0-job.log)。平台跳过不计通过，测试时长不代表应用性能。
- 该轮 macOS 和 iOS Simulator 的原生编译都在 `Darwin.statfs(path, &statistics)` 失败，Swift 将模块限定的同名引用解析为结构体；[原始 iOS 日志](validation/github-ios-5f666e0-job.log)。改为 `statfs(path, &statistics)`，与 [Swift 官方 Foundation 的 Darwin 实现](https://github.com/swiftlang/swift-corelibs-foundation/blob/main/Sources/Foundation/FileManager%2BPOSIX.swift)一致，继续使用真实 `f_bavail × f_bsize` 及溢出保护，不改未知空间时停止写入的规则。该轮 Apple 原生测试及应用包构建均不计通过。
- 只读复核同时发现进程验证工具的失败清理缺口：现已登记自己创建的两个锁进程，失败也请求其正常关闭并等待真实退出，无法确认时保留临时目录。工具改动的主机检查见[分析](validation/github-apple-fix-analyze.log)和[独立进程重验](validation/github-process-recovery-cleanup.log)。正常成功路径的既有结果不替代失败路径保护审查。

## 第三轮真实 Apple 结果

[第三轮 run 37775981963](https://github.com/panlijun/ImageHub/actions/runs/37775981963) 对应 `7fe7645d9d0366437f990aed17f6fcf86cda36c3`，整体 failure；[逐步骤终态与产物元信息](validation/github-third-ci-state.json)保留 iOS 成功与 Mac 失败，不能把整体记绿。

- iOS Simulator **3 项原生用例全部通过**（用例执行 34 秒；首次原生 Xcode 编译另计 267.7 秒），涵盖真实空间/独占发布、SQLite/永久副本/缩略图/SDK 解码/M1 图库/关闭重开/实际 IO 保护，以及独立 UUID 的 Keychain 写读删和被动网络桥接。正常应用入口的未签名 Simulator Debug 构建也通过；[iOS 原始日志](validation/github-ios-7fe7645-job.log)。已生成 artifact `11551031375`，70,211,378 字节，包含应用 ZIP 与验证记录，保留 7 天；不能作为真实 iPhone 安装包或发行签名证明。
- macOS 完整软件测试 **1396 通过、4 跳过，9 分 26 秒**，修改后的独立进程恢复及锁全部通过；原生 Debug `ImageHub.app` 已编译成功，Keychain 和被动网络两项用例通过。图库用例在测试自身准备阶段失败：系统返回的本应用 Caches 子目录尚不存在，`resolveSymbolicLinks` 抛 `PathNotFoundException`，此轮没有验证 Mac 图库闭环，Release 步骤跳过；[Mac 原始日志](validation/github-macos-7fe7645-job.log)。38,400 字节的 Mac artifact 只有三份日志，没有 Release 应用包。
- 已补齐 smoke 在解析系统临时根前创建目录，与生产 `locateLibrary` / `mobileTemporaryParent` 的既有准备顺序一致；保留随后自有目录及链接保护，不改变生产持久化规则。修复后的主机静态检查见[分析记录](validation/github-apple-temp-fix-analyze.log)，下一轮真实 Mac 运行仍须通过。
- 名称改动的最终 APK 同时核对了 DEX 中的新相册目录常量及完整 APK 摘要；[记录](validation/imagehub-android-folder-compiled.json)。该项只证明实际编译内容，不称新执行了 MediaStore 保存或手机实机验收。
