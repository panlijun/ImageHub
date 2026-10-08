# GitHub 公共仓库与 Apple 验证

当前阶段：[公共仓库 panlijun/ImageHub](https://github.com/panlijun/ImageHub) 已创建并推送。当前应用源提交 `a6d0640` 的[第八轮 Apple CI](https://github.com/panlijun/ImageHub/actions/runs/37795607653)整体 **success**，macOS 与 iOS 作业均成功，应用验证产物已生成。历史失败与取消均保留，不改记通过；核心CI通过不等于Apple全部产品接入或正式发行完成。

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

macOS 任务执行资源包完整性、分析/格式、完整软件测试、独立进程恢复/锁、真实 Apple engine 集成验证和 Release 构建。iOS 任务复用预装且可用的运行时与兼容 iPhone 类型，创建本轮自有模拟器，执行同一原生验证，再构建未签名模拟器应用；缺运行时明确失败，不自动大型下载。命令失败通过 `pipefail` 保留，不能因 `tee` 把失败记成功。

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

## 第四轮 Mac 核心验证与应用构建

[第四轮 run 37778807585](https://github.com/panlijun/ImageHub/actions/runs/37778807585) 的源提交为 `c39dccda51d78bc80630289ca65a4d78a54774fc`。macOS 作业 `113316386036` 终态 success，iOS 原生步骤在超过 30 分钟后由本轮代理正常中止以取得退出日志，整体终态 **cancelled**；[终态及产物证据](validation/github-fourth-ci-attempt1-state.json)、[中止请求](validation/github-fourth-ci-cancel-request.json)。这不是用例断言失败，也不计 iOS 通过。

- 标准 `macos-26` arm64 主机分析无问题，CI 检查的 `lib/test/integration_test` 共 266 个 Dart 文件格式 0 改动；完整软件测试 **1396 通过、4 个平台分支跳过，8 分 41 秒**。本机 269 文件检查另含工具范围，计数不同不代表遗漏失败。[Mac 原始日志](validation/github-macos-c39dccd-job.log)保留实际命令、输出和时间。
- 六个导入提交边界的独立进程退出恢复、UUID/字节核对、正常关闭重开及跨进程资料库排他锁全部通过。
- **三个真实 Mac 原生用例全部通过**（用例执行 8 秒，Debug 原生编译另计），包含真实空间/独占发布、SQLite/永久副本/缩略图/SDK 解码/桌面 A 图库/关闭重开/实际 IO 保护、Keychain 写读删及被动网络桥接。日志仍有 CI 无法前置窗口的提示；它不阻止真实 engine 用例执行，也不能当作人工窗口/设备验收。
- 正常应用入口的 `flutter build macos --release` 成功，生成 **63.2 MB `ImageHub.app`**。已上传[开发验证产物 11552630764](https://github.com/panlijun/ImageHub/actions/runs/37778807585/artifacts/11552630764)，包含应用 ZIP 与四份日志；artifact 共 25,272,998 字节，SHA-256 为 `fada61ef98f750d3179e48f142980e2c453d3900774b4509558b1fa28a7a41ae`，2026-10-15 到期。artifact 摘要不是未压缩应用目录摘要；没有正式 Developer ID 签名、公证或发布。

## iOS 等待日志与 CI 准备修正

- 第四轮 iOS 的 Xcode 原生编译 **431.2 秒完成**，随后约 22 分钟没有进入第一条用例。它的 `bootstatus` 已输出 `Status=3, isTerminal=YES` 与 `Data Migration Failed`，退出码仍被脚本视为成功；[原始退出日志](validation/github-ios-c39dccd-attempt1-cancelled-job.log)。645 字节的 iOS artifact 只有等待日志，没有正常入口应用包。
- 进一步对比发现，成功的第三轮也有同一系统迁移提示。因此不能断言迁移失败是本次等待的唯一原因。当前 Flutter SDK 的真实调用链在 Xcode 完成后还包含 `simctl install → launch → VM Service` 等待，原普通日志不足以定位具体一段。
- CI 改为从现有兼容类型/运行时创建独立模拟器并登记本轮 UUID 所有权；按 [Apple 官方命令说明](https://developer.apple.com/documentation/xcode/xcode-command-line-tool-reference)与 [Simulator 自动化说明](https://developer.apple.com/videos/play/wwdc2019/418/)使用完整标识和 JSON 状态。两流的明确迁移失败拒绝就绪，随后核对 Booted 及 SpringBoard 正 PID；当前运行时的具体探针行为仍须下一轮实际验证。
- 所有命令有界；原生步骤 20 分钟、正常构建 15 分钟，并保存 verbose 启动证据。清理只针对严格匹配本轮登记 UUID/name/runtime/type 的设备，关闭及删除后读回核对，未知保留。每个 artifact 增加 run_attempt，避免同源补跑与旧失败日志冲突。
- 主机的 **15 项控制逻辑验证通过**，包含两份真实失败文本、退出 0 的 stderr 失败、超时、假 PID、外来 marker 与身份变化拒绝清理、保存就绪许可时机及删除失败/未确认保留；[验证范围](validation/github-ios-boot-script-logic.json)。Dart yaml 真实解析和工作流结构检查通过；[记录](validation/github-ios-boot-workflow-verified.log)。这些不是 Windows 上执行的 Apple 原生测试。

## 第五轮自有模拟器启动与有界恢复

[第五轮 run 37786875678](https://github.com/panlijun/ImageHub/actions/runs/37786875678) 对应 `aa165c4766acb8e4a64b77bc9165b1ce5a5772c2`，整体终态 failure。macOS 作业 `113343767834` success，iOS 作业 `113343768275` 的启动检查 failure；[逐步骤终态及产物](validation/github-fifth-ci-state.json)保留两者的真实结果。

- macOS 完整软件测试再次 **1396 通过、4 跳过，9 分 11 秒**，独立进程六个导入边界、正常重开及跨进程锁通过，**三个原生用例通过**（执行 6 秒），正常入口 Release `ImageHub.app` **63.2 MB** 构建通过；[Mac 原始日志](validation/github-macos-aa165c4-job.log)。artifact `11555778329` 为 25,273,271 字节、SHA-256 `050ae79574ef5f054113e8fcc18042a0fadab481f65cf210ff2721e3fc5004a0`，包含应用 ZIP 和四份验证日志，保留 7 天；不是签名发行验收。
- 已真实创建本轮独立模拟器 `ddebfa41-c60a-4702-8962-ab60d06ce4a4`，首次 `bootstatus` 仍报告 `Status=3, isTerminal=YES` / `Data Migration Failed`。检查拒绝就绪，原生用例和正常应用构建均跳过；[iOS 原始日志](validation/github-ios-aa165c4-job.log)。不能把这轮记为 iOS 应用失败或通过，也不能认定前轮等待的唯一原因。
- 本轮登记身份核对、关闭、读回 Shutdown、删除及读回 UUID 缺席均在真实 runner 成功；只处理本轮设备，没有擦除预装设备。14,324 字节 artifact `11554144445` 只有启动/清理日志，没有应用包。
- 修正只对明确的终态迁移失败增加一次同 UUID 重启：先重新核对所有权并确认关闭，第二次启动每次最多 180 秒；第二次失败、超时、未知命令错误或身份变化均停止。只有最终 Booted 和 SpringBoard 正 PID 均确认才写入测试设备标识。不改变运行时，不下载镜像，不擦除其他设备。
- **7 项有界重启控制检查通过**，覆盖健康首次启动、明确失败后仅重启一次、再次失败拒绝、两次未知错误不追加重试、身份变化及无真实 PID 拒绝；[检查记录](validation/github-ios-boot-retry-logic.json)。这些只验证脚本逻辑，实际重启恢复、原生用例和应用构建仍须下一轮 runner 结果。

## 第六轮重启失败与明确运行时选择

[第六轮 run 37790708848](https://github.com/panlijun/ImageHub/actions/runs/37790708848) 对应 `61bc5662e6eedf11247400c8cf8ef456c263c6bd`，整体终态 failure。iOS 作业 `113357043856` failure，macOS 作业 `113357044240` success；[逐步骤终态与产物](validation/github-sixth-ci-state.json)保留两者。同 SHA 另一次 push run `37790706939` 终态 cancelled，不计通过；[触发快照](validation/github-sixth-ci-dispatch.json)保留两条实际记录。

- macOS 完整软件测试 **1396 通过、4 跳过，9 分 41 秒**，独立进程恢复/重开/锁及 **三个原生用例**（执行 7 秒）再次通过，正常入口 Release `ImageHub.app` **63.2 MB** 构建成功；[Mac 原始日志](validation/github-macos-61bc566-job.log)。artifact `11557361945` 为 25,273,135 字节、SHA-256 `5ba3968b84033081599ce4a0857a63cf71baff15052535844207d79f96ce57ae`，保留 7 天。重复验证数不与此前相加。
- 真实 iOS26.5 自有模拟器 `b304a5c8-e30e-4f45-8198-b05c2a4b1759` 首次迁移失败，核对同 UUID/运行时/类型/名称后关闭并读回 Shutdown；唯一重启仍在 6 秒的迁移阶段报告 `Status=3, isTerminal=YES` / `Data Migration Failed`。脚本拒绝就绪，原生与应用构建均跳过；关闭、删除及读回缺席成功。[原始日志](validation/github-ios-61bc566-job.log)保留两次输出；2,330 字节 artifact `11556652634` 只有准备/清理日志。
- 第五轮的真实完整 simctl JSON 同时登记可用的 iOS26.2、26.4、26.5 与各自兼容的 iPhone 类型；[提取证据](validation/github-ios-preinstalled-runtime-evidence.json)保留源 run/job/SHA 及原始日志摘要。下一轮从这些已安装配置中明确选定 **iOS26.2 / iPhone17**，不再自动选最高版本；CLI 必须给出完整运行时/类型，实际缺失或不可用就失败，无 fallback 或下载。选择依据证明已安装，不证明这个运行时已健康或已经通过原生测试。
- **21 项控制检查通过**，覆盖精确运行时/类型选择、缺失和不可用拒绝、无真实 PID 不授予许可、同 UUID 一次重启与失败保留、CLI 选择和 marker-only 清理；[记录](validation/github-ios-runtime-selection-logic.json)。工作流 YAML 的真实解析与两个标准作业、只读权限、有界准备/原生/清理及 7 天证据保留检查通过；[记录](validation/github-ios-runtime-workflow-verified.log)。Sol（`gpt-6.1-sol`，`high`）只读审查未发现阻断问题，主线程另审实际 diff；这些不计 Apple 原生通过。
- 第二次明确迁移失败增加严格本轮设备的只读状态及 30 秒进程探针诊断；即使正 PID 已出现仍拒绝就绪，诊断异常也保留原迁移失败。**8 项诊断控制检查通过**，包含身份变化、未 Booted、无 PID、未知命令、非法 JSON 和原失败传播；[记录](validation/github-ios-failed-boot-diagnostic-logic.json)。Sol 补充审查与主线程实际 diff 核对均未发现阻断问题；实际诊断仍待 runner 执行。

## 第七轮真实启动完成与状态查询超时

[第七轮 run 37794103833](https://github.com/panlijun/ImageHub/actions/runs/37794103833) 对应 `6a8a9661fb9089dfe698bd21042772e3e892446c`，整体终态 **cancelled**。iOS 作业 `113368915742` failure；macOS 起初排队，后来开始软件测试，在新版触发后正常取消，没有完整测试/原生/构建成功结果，不计本轮通过。[触发](validation/github-seventh-ci-dispatch.json)、[正常取消请求](validation/github-seventh-ci-cancel-request.json)、[官方终态](validation/github-seventh-ci-state.json)和[iOS 原始日志](validation/github-ios-6a8a966-job.log)保留实际阶段。被取消的 Mac 作业日志接口返回 404，未取得其完整日志，不伪造记录。

- 本轮已核对明确配置并新建 iOS26.2/iPhone17，自有 UUID `6fbb7dad-5977-43e0-a239-ffba8d687c73`。`bootstatus` 完成真实迁移、System App 等待及 `Status=4294967295, isTerminal=YES` / `Finished`，没有本轮迁移失败证据。后续 `simctl list devices --json` 在默认 60 秒期限内未返回，脚本拒绝就绪；原生与正常应用构建均跳过，不能把启动完成计为用例通过。
- 自有设备在 `always()` 清理中读回 Booted，再关闭、读回 Shutdown、删除及读回缺席均成功。1,693 字节 artifact `11558341718` 只有准备/清理日志，没有应用包。
- 只将启动完成后的该次状态读取期限改为 **120 秒**；保持真实所有权、Booted、30 秒 SpringBoard 正 PID 和失败拒绝，不重试未知查询，不降低原生测试要求。**5 项控制检查通过**，包括健康读取、超时、未 Booted、身份变化和无 PID；[记录](validation/github-ios-post-boot-query-logic.json)。脚本语法与实际 diff 检查通过，真实长查询及后续应用结果仍待新 runner。

## 第八轮当前源的真实 Apple 验证

[第八轮 run 37795607653](https://github.com/panlijun/ImageHub/actions/runs/37795607653) 的源提交为 `a6d0640298de4ebbf4126bacec138dd656f18a97`，整体终态 **success**。iOS 作业 `113376555917` 与 macOS 作业 `113376556025` 均 success；[逐步骤终态及产物](validation/github-eighth-ci-state.json)、[触发记录](validation/github-eighth-ci-dispatch.json)保留当前源与执行身份。

- macOS 分析无问题（40.7 秒），`lib/test/integration_test` **266 文件格式 0 改动**；完整软件测试 **1396 通过、4 平台分支跳过，8 分 19 秒**，六导入提交边界的独立进程退出恢复、正常关闭重开及跨进程排他锁全部通过。**三个真实原生用例全部通过，执行 10 秒**，正常入口 Release `ImageHub.app` **63.2 MB** 构建成功；[Mac 原始完整日志](validation/github-macos-a6d0640-job.log)。这些验证共享当前应用源，数字不与之前重跑相加。
- [Mac 开发验证产物 11559873041](https://github.com/panlijun/ImageHub/actions/runs/37795607653/artifacts/11559873041) 为 25,272,201 字节，SHA-256 `89a6825aaa4d5cd8c6aeeb33e2dcff899568aa74b8cd750cff2cc327453c6488`，包含正常 Release 应用 ZIP 与四份软件/进程/原生/构建日志，保留 7 天，2026-10-15 到期；没有正式 Developer ID 签名、公证或发布。
- 本轮真实确认预装 iOS26.2/iPhone17，新建自有 UUID `81949823-b988-41fa-95ca-5dc6b6e83964`。启动完成后读回同一登记设备的 Booted，`launchctl list` 返回 SpringBoard 正 PID `2984`，严格检查通过后才授予测试设备标识。状态查询在本轮成功，不据此断言前一轮超时的唯一原因；清理关闭、读回 Shutdown、删除和读回缺席全部通过。
- **iOS 三个真实原生用例全部通过，执行 16 秒**；首次原生 Xcode 编译另计 234.3 秒。正常应用入口的未签名 Simulator Debug `Runner.app` 构建成功，Xcode 编译 144.7 秒；[iOS 原始完整日志](validation/github-ios-a6d0640-job.log)保留实际 install/launch/VM 服务及用例输出。用例覆盖永久副本/SQLite/缩略图/SDK 预览/M1 图库/关闭重开/实际 IO 保护、独立 UUID 的 Keychain 写读删和被动网络；同进程 Keychain 新实例读取仍不是跨进程或物理设备验收。
- [iOS 开发验证产物 11558902790](https://github.com/panlijun/ImageHub/actions/runs/37795607653/artifacts/11558902790) 为 70,326,995 字节，SHA-256 `dea253aea1e33b0340c847415f6f3742a50ffc9fee604f44d97542c23fb7ab5a`，包含正常应用 ZIP 及启动/原生/构建/清理日志，保留 7 天，2026-10-15 到期。它是 Simulator 包，不能当作真实 iPhone 的 IPA 或正式签名发行。

## 交付与下一阶段

- 正式名称、原生应用标签/窗口、新导出名称和当前设计原型已统一 ImageHub；本轮补齐预览服务器启动提示并通过 `node --check design/serve.mjs`。稳定包 ID、存储身份和资源包原件保留。
- Windows Release `imagehub.exe` 的实际启动/正常退出、改名后的 ARM64/x86_64 APK 构建与系统标签已验证，见前述本机证据；本轮 Apple CI 修正未改变对应生产代码。Android 的正常应用闭环仍以 API36 模拟器记录为准。
- 剩余软件工作：iOS 原生图片/文件/备份/诊断导出，以及 Mac 备份文件取得与相关沙盒授权接入。最低系统、物理设备 PT/性能/断电、四端人工闭环及正式签名/公证/发行未计通过。真实图床契约与账号联调仍未授权且单列，不因本轮 CI 成功开启未知服务能力派发。
- 最后的记录提交仅更新记录、范围说明和预览服务器名称提示；交付前按 Git tree 核对 `app/`、`.github/workflows/apple.yml` 与资源包均与成功 CI 的源提交一致，再确认远端 `main` 和公共状态。
