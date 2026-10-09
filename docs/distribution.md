# ImageHub 本地发行与交付核验

本地发行脚本只打包 Windows x64 与 Android arm64。它按 `app/versions.json` 选择独立的平台版本目录；版本相同也不会覆盖已有发行目录。

在 PowerShell 中从仓库根目录运行：

```powershell
app/tool/package_release.ps1 -Platform windows
app/tool/package_release.ps1 -Platform android
```

首次在本机建立 Android 长期签名身份时，在确认目标 Windows 用户账户后运行：

```powershell
app/tool/package_release.ps1 -Platform android -InitializeAndroidSigning
```

Android 私钥与受保护口令保存在 Git 忽略的 `.local/signing/android/release.p12` 和 `vault.json`。已有完整保险库仅重新核验；不完整、内容变化或无法解密时拒绝继续，不替换既有密钥。口令由当前 Windows 用户的 DPAPI 保护，文件 ACL 限定于当前 SID 与 SYSTEM；脚本在构建期间临时设置签名环境变量，并在结束时精确恢复原环境。不会把口令写入命令行、Git、诊断或交付包，也不会在 Release 构建失败时退回 debug 签名。当前登记的公开证书 SHA-256 为 `457656fcb19a9873cc8c8036d74bbd4a1a8658b823f2de4febdd6bb5aa37749e`。本说明不读取或展示本机保险库内容。

DPAPI `CurrentUser` 只保证当前 Windows 用户可解开口令；复制签名目录不能保证系统重装或更换 Windows 用户后可恢复。离线、可移植的密钥备份流程尚未实现，因此不能据此声称已有跨机器恢复能力。正式 Android 发行后必须保留并持续使用同一私钥。

先前若安装了相同 application ID、但由 debug 密钥签署的 APK，正式密钥签署的 APK 会发生签名冲突。请先备份资料库，再由用户决定如何处理已安装应用；此流程不指导自动卸载或清除数据。

成功发行目录形如 `dist/windows/0.1.0+1/` 或 `dist/android/0.1.0+1/`，各自包含平台 artifact、`release.json`、`SHA256SUMS` 和安全构建日志。Windows artifact 是完整 Flutter Release 目录 ZIP，包含 app-local MSVC release CRT；脚本检查 ZIP 与解包后的文件摘要及正常启动退出，不另加安装器。Flutter 的 Windows 构建方式见[官方文档](https://docs.flutter.dev/platform-integration/windows/building)，MSVC 运行库分发规则见[微软文档](https://learn.microsoft.com/en-us/cpp/windows/redistributing-visual-cpp-files)。

Android artifact 是 arm64 Release APK，固定 `io.imagehost.imagehost` application ID、最低 API 29，使用上述专用签名。脚本核验 APK 的 package、版本/build、ABI、debuggable 状态、内核元信息、签名证书及 v2 签名。

构建同时指定 `--target-platform android-arm64 --split-per-abi`，只交付 `app-arm64-v8a-release.apk`；用 `-P force-version-code-ignoring-abi=true` 保留 `versions.json` 中的 Android build，不附加 Flutter 默认的 ABI 偏移。这是当前 SDK 源码和 [Flutter 官方 APK 指导](https://docs.flutter.dev/deployment/android#build-an-apk) 支持的选项，实际 APK 仍须通过上述核验。

每次打包会在构建前后计算 Git 源状态与文件指纹，并复核 `versions.json` 摘要；构建期间源发生变化则保留失败阶段证据，不发布成功发行目录。成功清单记录实际源身份、版本清单摘要、artifact 大小与 SHA-256，以及平台核验结果。相同平台版本/build 的目标目录已存在时，脚本拒绝覆盖。

2026-10-09 已完成 Windows x64 ZIP 与 Android arm64 APK 的本地正式 release 打包，包与逐项校验见[版本化本地交付里程碑](milestone-30-versioned-delivery.md)及对应的 [Windows receipt](validation/release-windows-formal.json)、[Android receipt](validation/release-android-formal.json)。这两份 receipt 记录的源提交为 `cfd55d0518f6448f409f3b221b9b2d32fe652074`，且工作区 `dirty=true`，当时仅有两张既有 Windows 验证截图未提交；因此这些包不是由 clean commit 构建的声明。receipt 记录的源指纹完整，仍可据其核对实际构建输入。

Apple CI `37913146736`（源 `d5bb06d`）已结束，macOS 作业成功，iOS 作业在原生测试应用构建和启动返回进程 ID 后未取得 VM 服务地址，20 分钟超时，整个 workflow 失败，见[第二轮记录](validation/release-apple-second-ci.json)。此前 `37908256215` 的 Mac job 成功，iOS 四项 Flutter 原生通过后备份应用未进入测试、步骤超时，整个 workflow 也失败。iOS 来源、完整四来源互读矩阵和新增 Photos 独立读回仍待验证。物理设备/PT/PERF、最低系统实测、Apple 正式签名发行和真实图床联调也未计通过；服务能力为 unknown 时继续拒绝派发。
