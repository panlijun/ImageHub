# 环境与构建条件

初始检查：2026-10-04；最新 Android 工具及 Apple 云端构建检查：2026-10-08。本地主机：Windows 11 25H2 x64，10.0.26200.9457。下方历次记录保留各阶段形成时的结论，当前平台状态以四端现状和最新里程碑为准。

## SDK 安装

原环境没有可用 Flutter/Dart。用户已同意安装，并要求整个 Windows 环境可用。现安装到通用目录 `C:\Users\PAN\development\flutter`，添加到现有 Windows 用户 PATH，保留原路径；不在项目内放 SDK，不改变机器级 PATH。当前用户的新终端可从任意工作目录使用 Flutter/Dart，原终端需要重开。已关闭 Flutter CLI analytics。

| 项目 | 实际值 |
| --- | --- |
| Flutter stable | 3.47.6 |
| Framework | 5fc346839b5d0eef006ed8404392afb4dfae428d |
| Dart | 3.13.5 |
| Engine | 692136cb65 |
| 官方 ZIP | flutter_windows_3.47.6-stable.zip，1,933,193,895 字节 |
| SHA-256 | a01bb0d26de91bc23c97cd9ccfaad281a612fb8304213fdd5df1119a09404796 |
| Visual Studio | Build Tools 2022 17.14.40，C++ x86/x64 与 CMake 已具备 |
| Windows SDK | 10.0.26100.0 |

安装依据：[Flutter 官方手动安装说明](https://docs.flutter.dev/install/manual)、[官方 Windows 发布元数据](https://storage.googleapis.com/flutter_infra_release/releases/releases_windows.json)。下载后 SHA-256 与官方发布值一致；SDK 自报版本与 framework 一致。安装档案 ZIP 保留于通用 development 目录，没有改动资源包。

初始 `flutter doctor -v` 中 Android toolchain 因缺 SDK 失败；用户于 2026-10-08 授权后已补装 Android 工具，最终 doctor 无问题、许可全部接受，JDK/SDK 实际路径均指向 D 盘，见[最终 doctor](validation/android-doctor-final.log)。Debug/Release APK、API36 模拟器原生子流程及正常应用闭环分别已有真实证据；doctor 整体 exit0 本身不代表平台通过。已有 Chrome/Edge 不改变本项目范围，不生成 Web/Linux 应用。

## Android 工具（2026-10-08）

新增工具统一位于 `D:\Workspace\DevelopmentTools`，不迁移或重复安装 C 盘 Flutter，不修改系统 PATH。JDK、Android 用户目录、AVD 和 Gradle 缓存通过 `app/tool/android_environment.ps1` 只设置当前 PowerShell 进程。配置写于该工具目录的 `android-environment.json`。

| 项目 | 实际安装值与位置 |
| --- | --- |
| JDK | Temurin 21.0.12.1+1，`Jdk21/jdk-21.0.12.1+1`，官方档案 SHA 核对通过 |
| SDK | `AndroidSdk`；API36 rev2，构建插件另需 API35 rev2 |
| Build Tools / NDK / CMake | 36.0.0 / 28.2.13676358 / 3.22.1 |
| 平台工具 / 模拟器 | platform-tools 37.0.1 / emulator 37.2.12 |
| 系统镜像 | Android36 Google APIs x86_64 rev7；自有 AVD `ImageHost_API36`，`emulator-5558` |
| 缓存 | `AndroidUser`、`Avd`、`Gradle` 均在上述 D 盘工具目录；既有 Flutter 与 Dart 依赖缓存继续复用 |
| 构建配置 | Gradle9.3.1、AGP9.1.0、Kotlin2.4.0；应用 minSdk29、target/compile36 |

已接受用户批准范围的标准工具许可。WHPX 原本可用，未安装或修改虚拟化组件；自有模拟器采用 SwiftShader、2 CPU、2 GiB 内存，不使用该配置声称参考设备性能通过。[安装日志](validation/android-tools-install-final.log)、[环境与模拟器原生验证](validation/android-native-smoke-final.log)。

## 四端现状

| 平台目标 | 项目配置 | 当前构建及运行证据 | 缺失条件 |
| --- | --- | --- | --- |
| Windows 11 x64 | 原生 runner，1280×720 初始窗口 | Debug 原生引擎集成测试通过；Release 构建通过，启动后创建全新默认图库 | 系统文件选择窗口、普通窗口退出中的对话框与键盘/读屏仍需人工平台验收 |
| macOS 12+ arm64 | 原生 runner，用户选择文件读写 entitlement；可用标准 `macos-26` arm64 CI | 云端完整软件测试1396通过/4跳过、独立进程恢复/锁、三个真实原生用例及正常入口Release `ImageHub.app`构建通过；[运行记录](github-publication.md) | 最低macOS12、人工选择器/沙盒授权、备份取得等剩余接入与设备验收、正式签名/公证 |
| Android API29+ arm64 | minSdk29、M1；有界 SAF/MediaStore、Pigeon 与私有 NDK 独占发布 | Debug 与 ARM64/x86_64 Release APK 已构建；API36 x86_64 原生子流程及正常 Release 应用导入/重开/预览/处理/照片保存/ZIP合并恢复/诊断导出通过，见[Android完成记录](milestone-28-android-completion.md) | ARM64 实机、API29 最低系统、物理设备 PT/PERF 与正式发行未验收；APK沿用本地debug签名 |
| iOS 15+ arm64 | 原生 runner，中文照片用途说明；复用云端预装运行时创建独立iPhone模拟器 | 第三轮iOS Simulator三个真实原生用例及正常入口未签名Debug应用构建通过；第四轮在编译后长期等待，已中止并保留日志，CI准备修正待验证；[运行记录](github-publication.md) | 原生保存/导出尚未接入；真实iPhone及最低iOS15、设备签名与其余PT验收 |

Android 安装和本地 APK 构建已获得授权；用户随后授权公开 GitHub 仓库并运行标准 Apple CI，已有真实 Mac 主机及 iOS Simulator 核心验证与应用构建证据。本机仍无 Mac/Xcode，Apple 工具只在 CI 临时 runner 使用，没有本机额外安装或正式签名/商店发布。模拟器应用不能作为真实 iPhone 安装包，核心原生用例不能代替四端全部功能验收。

早期 M1 阶段只验证 Windows 中的移动布局；当前新增 Android API36 模拟器证据单列，不改写早期 [M1 记录](milestone-02-m1.md)，也不代替 iOS 或物理设备验收。

## 依赖与数据位置

实际调用的直接依赖已固定版本，完整解析依赖及 SHA 由真实 `pub get` 写入 `app/pubspec.lock`：material_ui 1.5.0、flutter_riverpod 3.4.3、go_router 18.0.2、drift/drift_dev 2.35.1、sqlite3 3.7.0、image 4.10.1、file_selector 1.1.0、image_picker 1.2.3、path_provider 2.1.6、path 1.9.1、crypto 3.0.7、uuid 4.6.0、clock 1.1.3、intl 0.20.3。使用配套 Dart 原生 build hooks 获取并打包 SQLite；Windows Release 中确有 `sqlite3.dll`，未另装数据库服务器。

图库整理阶段补充 unorm_dart 0.3.2（包说明为 Unicode 17 NFC）、characters 1.4.1；真实 pub get 完成并更新锁文件。固定官方 Unicode 17 CaseFolding C/F 数据生成完整默认折叠映射，生成器 `--check` 和全数据 SHA/映射测试可复核。没有安装新的系统工具、Android SDK 或外部服务。最新构建和验证见 [图库/处理基础记录](milestone-03-gallery-processing.md)。

新 Windows 生产路径实测：`%APPDATA%\io.imagehost\imagehost\imagehost_library_v1\`。只创建并检查此新命名空间；不扫描、导入或兼容旧应用数据。Release 启动检查留下此路径下的新空库，没有注入测试图片。集成/进程测试均使用单独临时库并清理。

初始准备时没有 Git 仓库；用户随后授权建立 `main` 并提交“首次完成 PC 端”（`d642ebc`）。当前 Android 修改使用实际 `git diff` 审查，没有新增提交、推送或 PR。

处理输出阶段未增加依赖或系统安装。共同处理/持久输出、桌面导出和 schema 1/2→3 已有 Windows 证据，详见 [输出里程碑](milestone-04-processing-outputs.md)；原生系统选择器及 Apple/Android 设备证据仍单列缺失。

账号阶段已获取既定 flutter_secure_storage 11.2.0。2026-10-05 用户明确授权后，通过 Microsoft 签名的现有安装器，仅给 Build Tools 2022 添加 Microsoft.VisualStudio.Component.VC.ATL，退出码 0、无需重启。vswhere 检出组件，MSVC 14.44.35207 的 `atlmfc/include/atlstr.h` 实际存在；[安装记录](validation/windows-atl-install.log) 保存路径、版本与摘要。未修改另一个 Community 2026 实例。

补齐后 Windows 原生账号集成子流程通过：真实受保护合成凭据写入、资料库关闭重开读取、同名身份与匿名隔离、账号页展示、删除读回/重开留存身份。没有请求图床，不能代替其他三端或完整 PT-006 验收。最新构建证据见 [账号记录](milestone-05-accounts.md)。

安装参数按 [Microsoft 官方命令行说明](https://learn.microsoft.com/en-us/visualstudio/install/use-command-line-parameters-to-install-visual-studio?view=vs-2022) 使用 modify、指定现有安装路径/通道、单项 add、quiet/norestart；没有扩大工作负载或自动重启。

上传基础继续按既定选型获取 Dio 5.11.1，真实 pub get 另解析 dio_web_adapter 2.2.2；这不扩大产品为 Web。精确锁文件在 app/pubspec.lock。没有开通外部服务或执行真实上传。

2026-10-06 持久上传阶段：没有重复安装 Flutter/ATL 或改系统配置。当前 288 项全量测试通过，Windows IT-004 原生子流程 1 项通过（实际输出、SQLite、系统受保护管理信息与重开，传输受控）；Release 41.5 秒构建成功，隐藏自有窗口创建/正常 WM_CLOSE exit0。实际证据见 [上传阶段记录](milestone-07-durable-upload-queue.md)。Android SDK/设备与 Mac/Xcode/Apple 设备缺口不变，不能报告三端可运行。生产服务精确限制尚未核验，默认上传项等待能力确认。

2026-10-06 备份阶段：archive 4.3.0 从现有传递依赖改为显式依赖，真实 pub get 只变更这一依赖角色；没有新增系统安装或大型下载。该阶段 344 项全量回归通过。Windows 原生空间查询、无覆盖同卷发布、真实系统合成凭据排除、两模式导出/预检和重开已取得 IT-005 子流程证据；Release 85.9 秒构建成功，自有窗口创建/正常 WM_CLOSE exit0。共享页面已接入，恢复提交及三端原生备份导出仍未实现。详见 [备份记录](milestone-08-backup-foundations.md)。

2026-10-06 恢复规则阶段：未新增安装或依赖。非沙箱宿主只读核查确认通用 SDK 目录、持久用户 PATH 及当前 flutter 命令均指向 `C:\Users\PAN\development\flutter\bin`；无需重复安装。382 项全量通过，最终实际文件流单项复核通过；Windows IT-004 原生回归通过，当前 Release 44.5 秒构建成功，自有窗口创建/正常 WM_CLOSE exit0。共同合并计划与上传侧维护保护已有证据，实际恢复提交尚未接入，三端工具链/设备缺口不变。详见 [恢复规则记录](milestone-09-restore-plan-and-gate.md)。

2026-10-06 实际合并恢复阶段：未新增安装、依赖或外部请求。schema 6、永久字节/元信息日志提交及共同确认界面已接入；420 项全量通过，整 app analyze 无问题、116 文件格式检查 0 改动。Windows IT-005 原生子流程 1 项通过（3 秒/Debug 41.9 秒），实际空间/独占发布、完整与元数据恢复及重开、恢复界面幂等确认有证据。Release 56.7 秒构建成功，自有原生窗口正常关闭 exit0。三端缺环境/原生备份适配的限制不变；替换及完整首版尚未完成。详见 [真实恢复记录](milestone-10-merge-restore.md)。

2026-10-06 替换安全基础阶段：无新增安装、依赖、数据库版本或外部请求。内部当前快照与旧上传运行会话保护已接入共同仓储边界；441 项全量通过（46 秒），119 文件格式检查 0 改动，整 app analyze 无问题。Windows IT-005 子流程（Debug 30.6 秒/运行 3 秒）新增实际空间、当前快照与系统合成凭据关联保留/重开安全清理；IT-004 回归（Debug 20 秒/运行 3 秒）通过。Release 60.2 秒构建及自有隐藏窗口正常 WM_CLOSE exit0。实际替换提交、回滚与三端原生/设备验证仍未完成，详见 [替换安全基础](milestone-11-replacement-safety-foundations.md)。

2026-10-06 真实替换阶段：当前快照实际重建验证、独立风险确认、替换事务与失败回滚、旧会话拒绝、系统秘密有证据清理和重开接入。483 项全量通过（57 秒），124 文件格式 0 改动，整 app analyze 无问题；首轮启动提示覆盖失败保留并已修复。Windows IT-005 最终 1 项通过（Debug 29.1 秒/运行 4 秒）、IT-004 回归 1 项通过（Debug 28.8 秒/运行 3 秒）；Release 54 秒构建及自有隐藏窗口正常 WM_CLOSE exit0。完整首版仍未完成，详见 [真实替换记录](milestone-12-replacement-restore.md)。

本阶段宿主环境复核：Flutter 3.47.6 / Dart 3.13.5、Windows 和 Visual Studio 工具链正常；Windows 用户 PATH 真实持久登记 1 条 SDK bin，任意工作目录可使用，没有重复安装或改系统配置。受限工具环境的 PATH 检查与宿主结果不一致，以宿主实际结果为准。doctor 仍无法找到 Android SDK；Apple 构建需 Mac/Xcode，三端缺环境限制不变。[实际宿主检查](validation/windows-replacement-host-environment.log) 的 doctor exit0 不表示 Android 通过。

2026-10-06 本地链接阶段：已按既定选型真实获取 share_plus 13.3.1 及五项传递依赖，精确解析在锁文件与 [pub get](validation/windows-links-pub-get.log)，没有重复安装 SDK/ATL、改系统配置或增加 Web/Linux 应用。全量521项通过（58秒），Windows原生链接/合成系统管理秘密重开与本地清理子流程1项通过（Debug30.1秒/运行1秒）；Release45.9秒成功、自有隐藏窗口正常WM_CLOSE exit0。剪贴板/分享通道替身不等于实际系统PT，三端工具链/设备缺口不变。详见 [本地链接记录](milestone-13-local-links.md)。

2026-10-06 图库远程阶段：只读复核宿主 Flutter 3.47.6/Dart 3.13.5，通用目录及持久用户 PATH 1条已生效，不重复安装或改系统配置。无新增依赖/数据库迁移。548项全量通过（69秒），整app分析无问题；Windows图库原生子流程1项通过（最终Debug20.5秒/运行2秒，真实缩略图解码、本机记录刷新、重开，无HTTP），备份IT-005回归1项通过（Debug20.5秒/运行4秒）。当前Release56.5秒成功，仅自有隐藏窗口正常WM_CLOSE exit0。三端工具链/设备缺口不变；完整Windows90条正式验收未闭合。详见 [图库远程记录](milestone-14-gallery-remote.md)。

2026-10-06 历史清理阶段：宿主Get-Command flutter指向通用SDK，实际持久用户PATH有1条SDK bin，Flutter3.47.6/Dart3.13.5；受限工具环境PATH只见WindowsApps，不以该隔离视图误判安装失败。没有重复安装、额外下载、依赖或schema迁移。585项全量通过（62秒），144文件格式0改动、整app分析无问题；Windows原生历史清理/系统合成管理秘密保留/同意图重放/重开1项通过（Debug29.7秒/运行1秒）。Release36.5秒成功，仅自有隐藏runner正常WM_CLOSE exit0。Android SDK、Mac/Xcode和三端设备仍缺，详见 [历史清理记录](milestone-15-upload-history.md)。

2026-10-06 主动链接检测阶段：只读复核通用Flutter3.47.6/Dart3.13.5、实际flutter路径与持久用户PATH SDK bin一条，无重复安装/额外下载/依赖或外部请求。自身schema7仍26表，真实build_runner生成完成；646项全量通过（80秒），151文件格式0改动、整app分析无问题。Windows主动HEAD/真实系统合成管理秘密与重开子流程1项通过（Debug19.5秒/运行2秒），schema变化相关原生备份恢复回归1项通过（Debug19.9秒/运行4秒）。Release37.0秒成功、自有隐藏runner正常WM_CLOSE exit0。受控HTTP不等于真实服务验收，三端工具链/设备缺口不变，详见 [主动检测记录](milestone-16-link-availability.md)。

2026-10-06 持久设置/共同调度阶段：只读宿主复核Flutter3.47.6/Dart3.13.5、Get-Command指向通用SDK、持久用户PATH SDK bin恰1条；Android SDK仍缺，Apple需Mac/Xcode。不重复安装，无新增依赖、迁移或外部请求。704项全量通过（62秒）、163文件格式0改动、整app分析无问题；Windows IT-006设置真实保存/重开/新工作台JPEG与旧输出冻结1项通过（最终Debug28.6秒/运行9秒）。Release57.2秒成功、自有隐藏runner正常WM_CLOSE exit0。主机小屏检查不等于移动实机，完整首版仍未完成；实际文件、失败修正及范围见 [设置与调度记录](milestone-17-settings-scheduling.md)。

2026-10-07 本机诊断阶段：当前通用SDK缓存实际Flutter3.47.6/Dart3.13.5，无新增依赖、重复安装、额外下载或系统配置。自身schema8/27表由真实build_runner生成；最终752项现有单元/widget混合测试通过（72秒）、173文件格式0改动、整app分析无问题（9秒）。Windows IT-006诊断真实SQL/文件导出/清日志保留PNG/重开1项通过（Debug26.9秒/运行4秒）；IT-005备份合并恢复回归1项通过（Debug26.7秒/运行6秒）。Release51.0秒成功，仅自有隐藏runner正常WM_CLOSE退出0。资源包31文件/56本地引用及90条V1原文完整性通过；系统目录选择器、完整90条软件验收及三端工具链/设备仍待补，见 [诊断记录](milestone-18-diagnostics.md)。

2026-10-07 缓存/空间与预览保护阶段：沿用通用SDK和现有Windows编译环境，无新增安装、依赖、大型下载或系统配置，schema8/27表不变。821项现有单元/widget混合测试全部通过（79秒），185文件格式0改动、整app分析无问题（5.5秒）。Windows空间原生子流程1项通过（Debug27.3秒/运行7秒），设置重开/真实像素工作台回归1项通过（Debug27.8秒/运行11秒），图库远程/本机刷新/重开回归1项通过（Debug28.7秒/运行2秒）。当前Release92.0秒构建成功，仅本次自有隐藏runner正常WM_CLOSE退出0；资源包及90条原文最终复核通过。Android/Apple空间及独占发布已有源码/协议验证，仍缺工具链或设备，不报告三端构建运行通过；完整Windows首版尚未验收完成，见 [缓存与空间记录](milestone-19-storage.md)。

2026-10-07 独立单项暂停阶段：沿用Flutter3.47.6/Dart3.13.5与既有Windows工具，不新增安装、依赖、下载或系统配置。自身schema9/27表由真实build_runner生成（23秒）；最终843项现有unit/widget混合全量通过（104秒）、187文件格式0改动、整app分析无问题（34.5秒）。Windows单项/整批暂停、真实文件读取、正常完成及重开子流程1项通过（Debug44.5秒/运行5秒）；备份/真实恢复原生回归1项通过（Debug49.3秒/运行6秒）。当前Release54.3秒成功，仅本次自有隐藏runner正常WM_CLOSE退出0；资源包31文件/56引用及90条原文通过。用户本日明确取消计费状态，网络下一阶段仅类型观察与按类型自动继续。三端工具链/设备缺口和完整Windows首版未验收状态保留，见 [单项暂停记录](milestone-20-item-pause.md)。

2026-10-07 网络类型阶段：继续使用 Flutter3.47.6/Dart3.13.5、既有Windows SDK/VS/ATL，无安装、下载、系统配置或新增依赖。四端原生默认路径观察与共享策略/会话许可已接线，自有设置JSON格式3，数据库schema9/27表不变。最终879项现有unit/widget混合全量75秒通过，写入门相关61项3秒通过；Windows方法读取/首次监听及生产任务页1项通过（Debug23.5秒/运行1秒），实际Wi-Fi且无外部请求。最终单项/整批暂停及文件IO/重开原生回归1项通过（Debug24.8秒/运行9秒）。当前Release50.4秒成功，自有隐藏窗口正常WM_CLOSE退出0。Android Manifest及Apple entitlement源码结构已核查，三端仍缺工具链/设备；未切换用户网络，不声称完整PT-002或真实服务验收。详细文件、失败修正及最终分析见 [网络类型记录](milestone-21-network-types.md)。

2026-10-07 网络类型最终刷新接线复验：页面可手动重读/重建网络监听；观察失败仍独立读取资料库并保留最后有效列表，修复首次全量878通过/1失败的反馈回归，未放宽原断言。专项9项24秒及当前全量879项74秒通过；Windows真实原生读取/监听/点击刷新1项通过（Debug25.0秒/运行1秒），刷新不授予许可。当前最新Release43.8秒成功，自有隐藏窗口正常WM_CLOSE退出0；193文件格式0改动，整app分析无问题4.9秒。对应最终日志见 [网络类型记录](milestone-21-network-types.md)，前段50.4秒等属于刷新接线前版本；无额外安装、外部请求或网络切换，其他三端缺口及完整首版未验收状态不变。

2026-10-07 上传前自动处理依赖阶段：沿用Flutter3.47.6/Dart3.13.5和既有Windows工具，无新依赖、安装、大型下载、系统配置或真实图床请求。自身schema10/28表经真实build_runner生成（19秒）；最终930项现有unit/widget全量118秒通过，202文件格式0改动（3.30秒），整app分析无问题（34.3秒）。Windows真实自动处理/任务等待网络许可/输出与任务同身份重开原生子流程1项通过（最终Debug44.8秒/运行3秒）；备份/合并替换/故障回滚与重开原生回归1项通过（Debug36.8秒/运行6秒）。最终Release72.2秒构建成功，启动退出另见 [自动处理记录](milestone-22-upload-processing.md)。Android缺SDK/设备，macOS/iOS缺Mac/Xcode/设备；共同业务源码不等于三端构建运行。实际精确服务能力仍未知，完整90条软件验收、真实服务CT与设备PT/人工AT保留待补状态。

2026-10-07 可携带设置恢复阶段：沿用Flutter3.47.6/Dart3.13.5、既有Windows SDK/VS/ATL，无新依赖、安装、下载、系统配置或外部请求。Manifest当前格式2，严格读取本项目自身格式1；数据库仍schema10/28表。最终961项unit/widget混合全量112秒通过，206文件格式0改动（1.78秒），全app最终分析无问题（6.0秒）；Windows两模式ZIP/合并替换/设置冻结和事务失败回滚/系统合成秘密排除/重开及生产确认原生子流程1项通过（Debug42.1秒/运行6秒）。实际设置截图已由主线程查看；Release与启动结果见 [设置恢复记录](milestone-23-backup-settings.md)。Android缺SDK/设备，macOS/iOS缺Mac/Xcode/设备；四平台纯模型与共同页面不代替设备互读、完整CT/PT/AT或首版90条验收。

上述设置恢复阶段最终Windows Release68.3秒成功；本轮自有隐藏runner实际创建窗口并正常WM_CLOSE退出0。最终资源包31文件/56引用、90条需求原文完整性复查通过。日志与截图见设置恢复记录；这些证据仍不代替真实选择器、四设备互读或完整首版验收。

2026-10-07 独立远端删除阶段：沿用Flutter3.47.6/Dart3.13.5与既有Windows工具，无安装、下载、系统配置、新依赖或实际外部上传/删除。schema10/28表与Manifest2不变，严格本机审计在既有LibraryMetadata。当前1038项unit/widget混合全量87秒通过，新增专项77项16秒通过；216文件格式0改动2.01秒，最终完整分析无问题4.7秒。Windows真实删除页面/SQL/files/受控multipart/正常重开子流程1项通过（Debug36.5秒/运行3秒）；备份/合并替换/设置/故障回滚原生回归1项通过（Debug28.1秒/运行6秒）。真实截图已查看，资源包与90条原文完整性通过。当前Release/启动退出与所有失败修正见 [独立删除记录](milestone-24-remote-deletion.md)。未发现adb/Xcode工具；Android SDK/设备及Mac/Xcode/设备仍缺，不把共享代码或受控HTTP当作三端运行、真实服务删除确认或完整首版验收。

上述独立删除阶段最终Windows Release46.6秒成功；当前AOT文件14,009,224字节，本轮18:00:36生成。本轮自有隐藏runner窗口归属核对后正常WM_CLOSE退出0，未签名/安装/发布。完整Windows首版与真实服务确认仍按台账继续，不据构建启动关闭目标。

2026-10-07 软件补齐阶段：本轮按用户决定排除剩余设备验收，继续现有Windows主机软件自动化，详见[范围拆分](software-completion-scope.md)。只读SDK缓存版本确认Flutter3.47.6/Dart3.13.5；继续通用目录及既有Windows工具链，没有重复安装、额外软件下载、系统配置或真实图床请求。ffi2.2.0从已锁定传递依赖改为显式，offline pub get只调整依赖角色；schema10/28表、Manifest2与设置格式3不变。最终1123项unit/widget通过、1项非Windows来源分支跳过，123秒；226文件格式0改动，2.08秒；全app分析无问题，6.2秒。Windows真实原图/独立副本/预算释放及重开原生子流程1项通过，Debug36.4秒/运行5秒；实际截图已查看，失败夹具修正完整记录。当前Release53.3秒成功，AOT14,123,912字节于19:14:16生成，本轮自有隐藏runner正常WM_CLOSE退出0。未签名/安装/发布，三端未构建运行；移动原生导出仍是代码缺口，真实服务能力/联调不是被排除设备项。文件、失败及验证链接见[软件补齐记录](milestone-25-software-completion.md)。

2026-10-07 来源取消与图床能力边界阶段：沿用既有Flutter/Dart和Windows工具，无安装、新依赖、系统配置、真实图床上传/删除或Git操作。最终1147项软件测试通过、1项非Windows来源分支跳过，123秒；来源/取得器/界面专项21项通过2秒，完整分析无问题79.1秒。WindowsIT-001/002原生子流程1项通过（Debug43.7秒/运行5秒）；Release72.8秒成功，AOT14,140,296字节于20:37:39生成，自有隐藏runner正常WM_CLOSE退出0。来源在等待数据时请求取消并等实际清理/写入收尾，关闭/根锁保护与持久恢复有证据；未知内核阻塞不承诺固定期限安全终止。格式独立限额与全局取小值已接入，生产两服务仍unknown；官方公开材料未补足API精确字节/格式和可靠删除确认。手动Catbox CT工具只prepare-only，五张合成图5903字节全部未发送，不读取图库或凭据，独立工具分析通过。其他三端缺环境/设备限制不变。文件与失败修正见[阶段记录](milestone-26-source-cancellation.md)，实机排除不等于真实服务CT/IT或完整Windows首版闭合。

2026-10-08 Windows软件收尾：只读SDK缓存再次确认Flutter3.47.6/Dart3.13.5，沿用既有Windows SDK/VS/ATL，无新增依赖、安装、下载、系统配置、真实图床请求或Git操作。用户取消Catbox匿名功能，保留本项目普通历史身份；原资源包不变。schema10/28表、可携带Manifest2和DeviceSettings3不变，缩略图登记自有代次2严格读取1/2，仅复用2。最终255文件格式0改动（1.86秒）、整app分析无问题（4.9秒），1314项unit/widget/本机SQL/files/SDK全量通过、1项非Windows来源分支跳过（120秒）。Windows图库、处理导出、安全合成凭据、自动处理任务、备份合并/替换/回滚五个原生子流程各1项通过；六导入边界独立进程exit(73)、正常跨进程重开及排他锁通过。Release63.7秒成功，Dart AOT14,189,448字节于2026-10-08 10:08:17生成；原生host未改变，EXE保留原时间。自有隐藏runner实际窗口创建并正常WM_CLOSE退出0。仅当前Windows可运行；Android SDK与Apple Mac/Xcode环境仍缺，移动原生导出未接入且禁用。实机/真实硬件性能断电/真实账号与服务/完整人工AT/签名发行不记通过；生产服务unknown仍禁止派发。原生截图已查看，资源包31文件/56引用及90条规范原文检查通过；[完整文件、失败与实际验证记录](milestone-27-windows-completion.md)。
