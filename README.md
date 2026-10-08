# ImageHub

ImageHub 是用 Flutter 从零实现的本地个人图片工具。应用源码在 `app/`，实施资料在 `docs/`；`imagehost-new-project-kit/` 是只读输入，原件保持不变。产品没有应用云账号或图库云同步。

公共仓库：[panlijun/ImageHub](https://github.com/panlijun/ImageHub)。正式名称于 2026-10-08 确定；资源包、历史记录及稳定内部标识沿用 ImageHost，不据此迁移本项目的数据。

Windows 和 Android 在用户确认范围内的软件开发及适用验证已完成，包括本地图库和永久副本、图片处理与结果保存、账号安全存储、持久上传队列、按网络类型控制派发、链接管理与主动检测、独立远端删除审计，以及备份恢复、诊断和设置。Android 采用 M1，已接入真实系统文件/照片取得、SAF 文件保存及 MediaStore 相册保存；API36 x86_64 模拟器上的正常 Release 应用闭环已验证。ARM64 APK 已构建，物理手机、最低 API29 和硬件验收仍未执行。

Apple 云端验证使用标准 macOS arm64 runner。macOS 已通过完整软件测试、独立进程恢复与锁、三个真实原生用例及正常应用入口 Release 构建；iOS Simulator 的三个原生用例和正常应用入口构建已有通过记录。后续 iOS CI 的准备故障按真实日志修正：明确固定预装 iOS26.2/iPhone17 后已真实完成启动，但状态查询超时，专用查询期限已调整并待复验；历史失败和取消均保留。原生用例覆盖永久副本、SQLite、图库、像素解码、实际 IO 保护、Keychain 和被动网络桥接。具体提交、运行和边界见[GitHub 与 Apple 验证记录](docs/github-publication.md)。iOS 原生导出仍未接入，Mac 备份取得及其余平台功能按真实接入记录验收，不能把核心用例通过等同四端产品完成。

图床账号仅支持 Catbox userhash 和 ImgBB APIKey。Catbox 匿名上传已从产品中移除；本项目已有匿名身份只供读取普通历史和备份，不能创建、选择、入队或派发。真实图床上传、删除、探测没有获得联调授权；服务的精确大小与格式限制仍未知，因此生产能力守卫继续阻止未确认能力的派发。受控测试不代表真实服务可用。

Windows/Android 运行方式、功能入口和开发命令见[应用 README](app/README.md)。当前 SDK、构建条件及本机证据见[环境记录](docs/environment.md)，范围与验收边界见[软件完成范围](docs/software-completion-scope.md)、[Windows 完成记录](docs/milestone-27-windows-completion.md)及[Android 完成记录](docs/milestone-28-android-completion.md)。新增 Android 工具及 Gradle/AVD 缓存位于 `D:\Workspace\DevelopmentTools`，复用 C 盘 Flutter，不修改系统 PATH。

公共仓库与 Apple CI 的准备、公开范围和实际运行结果见[GitHub 与 Apple 验证记录](docs/github-publication.md)。工作流使用标准 macOS arm64 runner；文件存在不代表构建或测试已通过。

桌面采用 A，手机按用户选择采用 M1；M1 的设计与实现记录见[M1 里程碑](docs/milestone-02-m1.md)和[M1 设计记录](docs/mobile-m1-design.md)。旧里程碑保留各自当时的历史结论，当前状态以最新平台完成记录为准。

历史实现记录： [图库](docs/milestone-03-gallery-processing.md)、[处理输出](docs/milestone-04-processing-outputs.md)、[账号安全](docs/milestone-05-accounts.md)、[队列与暂停](docs/milestone-07-durable-upload-queue.md)、[备份恢复](docs/milestone-10-merge-restore.md)、[替换恢复](docs/milestone-12-replacement-restore.md)、[图库远程筛选](docs/milestone-14-gallery-remote.md)、[历史清理](docs/milestone-15-upload-history.md)、[链接检测](docs/milestone-16-link-availability.md)、[设置与调度](docs/milestone-17-settings-scheduling.md)、[诊断](docs/milestone-18-diagnostics.md)、[缓存与空间](docs/milestone-19-storage.md)、[单项暂停](docs/milestone-20-item-pause.md)、[网络类型](docs/milestone-21-network-types.md)、[上传前处理](docs/milestone-22-upload-processing.md)、[备份设置](docs/milestone-23-backup-settings.md)和[远端删除审计](docs/milestone-24-remote-deletion.md)。

工作区根目录运行 `node design/serve.mjs` 可预览 `http://127.0.0.1:8775/mobile-m1/index.html`。原型中的图片和操作仅用于布局演示，不是生产数据或持久化实现。
