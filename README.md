# ImageHub

ImageHub 是用 Flutter 从零实现的本地个人图片工具。应用源码在 `app/`，实施资料在 `docs/`；`imagehost-new-project-kit/` 是只读输入，原件保持不变。产品没有应用云账号或图库云同步。

公共仓库：[panlijun/ImageHub](https://github.com/panlijun/ImageHub)。正式名称于 2026-10-08 确定；资源包、历史记录及稳定内部标识沿用 ImageHost，不据此迁移本项目的数据。

Windows 和 Android 在用户确认范围内的软件开发及适用验证已完成，包括本地图库和永久副本、图片处理与结果保存、账号安全存储、持久上传队列、按网络类型控制派发、链接管理与主动检测、独立远端删除审计，以及备份恢复、诊断和设置。Android 采用 M1，已接入真实系统文件/照片取得、SAF 文件保存及 MediaStore 相册保存；API36 x86_64 模拟器上的正常 Release 应用闭环已验证。ARM64 APK 已构建，物理手机、最低 API29 和硬件验收仍未执行。

本轮回归记录：Windows 软件测试 1459 项通过、1 项非 Windows 分支跳过，`flutter analyze` 为 No issues。M1 快捷入口专项 20 项通过；详情编辑/上传会打开共同工作台或任务草稿，用户仍需在工作台明确操作，不会立即处理、入队或授权网络。图库整理可用；资料库替换后，旧页面会拒绝继续操作。Windows 最终发布 ZIP 与 Android 正式专用签名 APK 正在按[本地发行流程](docs/distribution.md)核验，尚未报告为已生成或完成。内核及 Windows、macOS、Android、iOS 五组版本均由[版本管理](docs/versioning.md)中的 `app/versions.json` 独立维护，当前各为 `0.1.0+1`。

2026-10-09 已完成 iOS 文件/照片/备份/诊断原生保存与 macOS/iOS 备份取得，[源9715ce9的 Apple CI 两端成功](https://github.com/panlijun/ImageHub/actions/runs/37879708343)。macOS 完整软件测试1424通过/4平台分支跳过，独立进程恢复与锁、4项Flutter原生集成、23项XCTest及正常入口Release构建通过；iOS26.2/iPhone17 Simulator 4项Flutter原生、20项XCTest（含真实Photos合成PNG保存）、正常入口未签名构建与自有设备清理通过。Windows最终回归1427通过/1平台分支跳过，Release构建和正常启动退出通过，Android ARM64 Release也已构建。原生文件保护、实际范围和产物见[里程碑29](docs/milestone-29-apple-files.md)，历史失败/取消见[GitHub与Apple记录](docs/github-publication.md)。最低系统、物理设备、真实Files提供者/系统UI、四端人工互读及正式签名发行仍未验收。

本轮[源95b94d3的 Apple CI](https://github.com/panlijun/ImageHub/actions/runs/37908256215)已执行：macOS 1456项软件测试通过/4项平台分支跳过，4项Flutter原生、23项XCTest及Release通过；Windows/Android来源备份在Mac实际恢复重开通过。iOS的4项原生检查通过，但后续备份测试应用构建后未进入测试、步骤15分钟超时，新Photos读回尚未执行。Mac来源备份随后已在Windows与Android实际恢复重开通过；完整四来源矩阵仍在补证。原始失败和平台边界见[本轮CI记录](docs/validation/release-apple-first-ci.json)，不改变里程碑29及历史CI结论。实机、最低系统兼容和真实图床服务仍按既定范围排除。

图床账号仅支持 Catbox userhash 和 ImgBB APIKey。Catbox 匿名上传已从产品中移除；本项目已有匿名身份只供读取普通历史和备份，不能创建、选择、入队或派发。真实图床上传、删除、探测没有获得联调授权；服务的精确大小与格式限制仍未知，因此生产能力守卫继续阻止未确认能力的派发。受控测试不代表真实服务可用。

Windows/Android 运行方式、功能入口和开发命令见[应用 README](app/README.md)。当前 SDK、构建条件及本机证据见[环境记录](docs/environment.md)，范围与验收边界见[软件完成范围](docs/software-completion-scope.md)、[Windows 完成记录](docs/milestone-27-windows-completion.md)及[Android 完成记录](docs/milestone-28-android-completion.md)。正式本地打包入口和核验要求见[发行说明](docs/distribution.md)；新增 Android 工具及 Gradle/AVD 缓存位于 `D:\Workspace\DevelopmentTools`，复用 C 盘 Flutter，不修改系统 PATH。

公共仓库与 Apple CI 的准备、公开范围和实际运行结果见[GitHub 与 Apple 验证记录](docs/github-publication.md)。工作流使用标准 macOS arm64 runner；文件存在不代表构建或测试已通过。

桌面采用 A，手机按用户选择采用 M1；M1 的设计与实现记录见[M1 里程碑](docs/milestone-02-m1.md)和[M1 设计记录](docs/mobile-m1-design.md)。旧里程碑保留各自当时的历史结论，当前状态以最新平台完成记录为准。

历史实现记录： [图库](docs/milestone-03-gallery-processing.md)、[处理输出](docs/milestone-04-processing-outputs.md)、[账号安全](docs/milestone-05-accounts.md)、[队列与暂停](docs/milestone-07-durable-upload-queue.md)、[备份恢复](docs/milestone-10-merge-restore.md)、[替换恢复](docs/milestone-12-replacement-restore.md)、[图库远程筛选](docs/milestone-14-gallery-remote.md)、[历史清理](docs/milestone-15-upload-history.md)、[链接检测](docs/milestone-16-link-availability.md)、[设置与调度](docs/milestone-17-settings-scheduling.md)、[诊断](docs/milestone-18-diagnostics.md)、[缓存与空间](docs/milestone-19-storage.md)、[单项暂停](docs/milestone-20-item-pause.md)、[网络类型](docs/milestone-21-network-types.md)、[上传前处理](docs/milestone-22-upload-processing.md)、[备份设置](docs/milestone-23-backup-settings.md)和[远端删除审计](docs/milestone-24-remote-deletion.md)。

工作区根目录运行 `node design/serve.mjs` 可预览 `http://127.0.0.1:8775/mobile-m1/index.html`。原型中的图片和操作仅用于布局演示，不是生产数据或持久化实现。
