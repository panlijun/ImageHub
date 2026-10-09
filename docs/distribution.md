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

每次打包会在构建前后计算 Git 源状态与文件指纹，并复核 `versions.json` 摘要；构建期间源发生变化则保留失败阶段证据，不发布成功发行目录。成功清单记录实际源身份、版本清单摘要、artifact 大小与 SHA-256，以及平台核验结果。相同平台版本/build 的目标目录已存在时，脚本拒绝覆盖。

macOS 与 iOS 通过已授权的 Apple CI 构建；截至本说明编写时，尚未完成这两端的正式签名发行。本说明描述打包流程与核验契约，不代表任何正式发行包或新 CI 已成功。物理设备/PT/PERF、最低系统实测和真实图床联调仍未计通过；服务能力为 unknown 时继续拒绝派发。
