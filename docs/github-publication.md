# GitHub 公共仓库与 Apple 验证

当前阶段：[公共仓库 panlijun/ImageHub](https://github.com/panlijun/ImageHub) 已创建；正在提交和推送，尚未获得 Apple 构建结果。

## 待公开内容

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
