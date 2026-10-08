# ImageHost 应用

ImageHost 是本地个人图片工具。Windows 软件开发及本轮适用主机验证已完成，用户排除的实机/硬件与真实账号项目不计通过。新库从空库开始；导入来源只读，永久副本、数据库、暂存文件和可再生缓存分别管理。完整范围和当前验收状态见[软件完成范围](../docs/software-completion-scope.md)及[Windows 完成记录](../docs/milestone-27-windows-completion.md)。

## Windows 运行

在本目录执行：

```powershell
flutter pub get
flutter run -d windows
```

当前 SDK 为 Flutter 3.47.6 / Dart 3.13.5，安装在 `C:\Users\PAN\development\flutter` 并已加入用户 PATH。已打开的终端需重新打开，也可调用 `C:\Users\PAN\development\flutter\bin\flutter.bat`。本机已配置 Visual Studio 2022 和 ATL。

Release 目录为 `app/build/windows/x64/runner/Release/`，运行时须保留 `imagehost.exe`、同目录 DLL、`data/` 与其他构建产物。此目录是本机构建输出；项目尚未制作安装包、签名或发布。当前构建、启动和验证结果以 Windows 完成记录为准。

## 功能入口

桌面 A 提供真实本地图库、分类标签、组合检索、批量整理、回收恢复和副本校验。导入后先完成永久副本校验再报告成功；删除来源不会删除已保存副本。处理工作台支持压缩、裁剪、拼接与动画选帧，输出可重开、预览、独立永久保存和桌面导出；导出同名时创建新名称。移动原生导出尚未接入，必须保持禁用。

账号页仅支持 Catbox userhash 和 ImgBB APIKey。配置可用系统安全存储或明确选择仅本次会话；保存账号不代表健康验证，应用不会自动试传。Catbox 匿名上传已移除，不能新建或重新启用；本项目既有匿名身份仅保留普通历史和备份读取。

任务页保存批次、逐项状态、尝试、结果及处理依赖，支持单项和整批暂停/继续。进入页面或入队不授权网络；只识别网络类型，按用户保存的网络类型策略控制已确认任务的派发，不读取计费状态，也不提供图库云同步。Catbox/ImgBB 精确大小与格式限制仍未知，生产能力守卫会阻止未确认能力的派发。没有真实账号联调授权，受控传输测试不能证明真实图床可用。

链接页支持普通结果筛选、复制、文本分享、明确确认后的主动检测和单独确认的远端删除审计。主动检测不会自动执行；远端删除无法确认时保留本机记录且不自动重试。HTTP 成功不能被当作远端删除成功。普通结果的本地移除与远端删除是两项独立操作。

备份页支持完整/元数据 ZIP、预检、合并及单独确认的替换恢复。备份不携带凭据、管理秘密、活动上传意图或来源路径；恢复的历史不会重新执行任务。诊断和空间管理提供已接入的本机记录、脱敏导出、缓存清理和到期临时输出清理。其他平台已有部分共享业务及平台源码，但未构建验证；不能据此报告平台可运行。

## 开发与验证

常用生成、格式、分析与测试命令：

```powershell
dart run build_runner build
dart format lib test integration_test tool
flutter analyze
flutter test --reporter expanded
```

Windows 集成测试及独立进程恢复工具：

```powershell
flutter test integration_test/gallery_flow_test.dart -d windows --reporter expanded
flutter test integration_test/mobile_gallery_flow_test.dart -d windows --reporter expanded
flutter test integration_test/processing_flow_test.dart -d windows --reporter expanded
flutter test integration_test/accounts_flow_test.dart -d windows --reporter expanded
flutter test integration_test/upload_flow_test.dart -d windows --reporter expanded
flutter test integration_test/backup_flow_test.dart -d windows --reporter expanded
flutter test integration_test/links_flow_test.dart -d windows --reporter expanded
flutter test integration_test/gallery_remote_flow_test.dart -d windows --reporter expanded
flutter test integration_test/history_flow_test.dart -d windows --reporter expanded
flutter test integration_test/link_probe_flow_test.dart -d windows --reporter expanded
flutter test integration_test/settings_flow_test.dart -d windows --reporter expanded
flutter test integration_test/diagnostics_flow_test.dart -d windows --reporter expanded
flutter test integration_test/storage_flow_test.dart -d windows --reporter expanded
flutter test integration_test/item_pause_flow_test.dart -d windows --reporter expanded
flutter test integration_test/network_flow_test.dart -d windows --reporter expanded
flutter test integration_test/upload_processing_flow_test.dart -d windows --reporter expanded
dart run tool/verify_process_recovery.dart
dart run tool/verify_output_recovery.dart
flutter build windows --release
powershell -NoProfile -File tool/verify_release_smoke.ps1
```

测试命令是开发入口，不表示本轮已执行或通过。受控图床传输不请求真实服务；设备 PT、真实硬件性能和断电验收排除在本轮之外，均不计通过。Android 尚无 SDK，macOS/iOS 需要 Mac/Xcode。具体已执行项、结果和未完成项记录在 Windows 完成记录中。

历史实现与验证记录：图库和处理见[图库里程碑](../docs/milestone-03-gallery-processing.md)、[处理输出](../docs/milestone-04-processing-outputs.md)；账号和队列见[账号安全](../docs/milestone-05-accounts.md)、[持久队列](../docs/milestone-07-durable-upload-queue.md)、[单项暂停](../docs/milestone-20-item-pause.md)和[上传前处理](../docs/milestone-22-upload-processing.md)；备份恢复见[合并恢复](../docs/milestone-10-merge-restore.md)、[替换恢复](../docs/milestone-12-replacement-restore.md)和[备份设置](../docs/milestone-23-backup-settings.md)；链接、系统管理和网络见[主动检测](../docs/milestone-16-link-availability.md)、[远端删除审计](../docs/milestone-24-remote-deletion.md)、[网络类型](../docs/milestone-21-network-types.md)、[诊断](../docs/milestone-18-diagnostics.md)、[设置与调度](../docs/milestone-17-settings-scheduling.md)及[缓存与空间管理](../docs/milestone-19-storage.md)。这些旧记录保留当时证据，不代替本轮完成记录。
