# 里程碑 30：版本化本地交付

日期：2026-10-09。Windows x64 与 Android arm64 的版本化本地正式 release 包已生成并完成 receipt 核验。整个软件收尾目标仍在进行；iOS 来源、完整四来源互读矩阵和新增 Photos 外部副本独立读回尚待验证。

## 版本与交付产物

`app/versions.json` 是版本单一来源，内核版本/revision 与 Windows、macOS、Android、iOS 的平台版本/build 分别维护。本次内核和四个平台的版本显示值均为 `0.1.0+1`。应用 schema 10 与备份 format 2 保持原值，不随产品版本重置。

| 平台 | 正式本地包 | 大小 | SHA-256 |
| --- | --- | ---: | --- |
| Windows x64 | [`ImageHub-windows-x64-0.1.0+1.zip`](../dist/windows/0.1.0+1/ImageHub-windows-x64-0.1.0+1.zip) | 16,872,605 bytes | `55f7780f11a9941397f95e857d555acb8cce63f4db6778c75ee0fcdbfdff3204` |
| Android arm64 | [`ImageHub-android-arm64-0.1.0+1.apk`](../dist/android/0.1.0+1/ImageHub-android-arm64-0.1.0+1.apk) | 27,400,002 bytes | `e23935ef68df5b9358be5f96a7addeeef95eb3e4b4328e0dbd0743f5bfd05562` |

发布目录还包含 `SHA256SUMS`、`release.json` 与安全构建日志。主线程实际运行两平台 `package_release.ps1`，均以退出码 0 完成；随后再次核验实际文件大小、SHA-256、`SHA256SUMS` 和 receipt。

Windows receipt 确认完整 ZIP 含 34 个文件/目录条目、app-local MSVC release CRT、ZIP 内容和解包文件摘要一致；原生版本为 `0.1.0+1`、架构 x64、非 debug。解包后的正常应用启动及 `WM_CLOSE` 退出码 0 均通过。该交付是完整 Flutter Release 目录 ZIP，不含额外安装器。

Android receipt 确认 application ID `io.imagehost.imagehost`、最低 API 29、唯一 ABI `arm64-v8a`、内核与平台版本 `0.1.0+1`、非 debug、证书 SHA-256 `457656fcb19a9873cc8c8036d74bbd4a1a8658b823f2de4febdd6bb5aa37749e`，且 v2 签名验证通过。本次正式 ARM64 APK 未安装到物理手机或模拟器。

原始记录：[Windows receipt](validation/release-windows-formal.json)；[Android receipt](validation/release-android-formal.json)。receipt 记录源 base 为 `cfd55d0518f6448f409f3b221b9b2d32fe652074`，`dirty=true`，当时仅两张既有 Windows 验证截图未提交。源状态、tracked diff、完整源文件数及源文件指纹均记录在 receipt 中；这不是 clean commit 构建声明。

首次 Windows 正式打包在 ZIP 已完成核验后，于 PowerShell 7 返回 `List[object]` 中的 `PSCustomObject` 结果时失败。实际复现后将返回方式改为 `$records.ToArray()`，随后完整重试成功。失败 stage 保留在忽略的 `dist/.staging/windows-08a4b17e6c15437cb735572ccb6d87c3/`；未清理或覆盖该证据。

## 本轮适用软件验证

- Windows 软件测试 1,459 项通过、1 个非 Windows 平台分支跳过；M1 快捷入口专项 20 项通过，五项 Windows 原生验证及正常 Release 启动/退出通过。
- 真实 4,328,697,800-byte ZIP64 备份完成默认预检、合并和重开后的全部字节核对；62 个冷缩略图在实际读取结束后租约为 0。
- Windows、Android、Mac 三个来源间的六个方向，均有完整备份及元数据备份恢复后实际重开的证据。该范围不是完整 12 个方向，也不是四端物理设备 PT。

此前 Apple CI `37908256215`（源 `95b94d3`）整体失败：Mac 1,456 项通过/4 个 Windows 分支跳过、四项 Flutter 原生、23 项 XCTest 和 Release 构建通过；iOS 四项 Flutter 原生通过，但备份应用构建完成后未进入备份测试，相关步骤超时，新增 Photos 独立读回未执行。这些结果不代表整体 Apple CI 成功，也不证明 iOS 业务用例失败。

第二轮 `37913146736`（源 `d5bb06d`）也已结束：Mac 的上述软件、原生、XCTest、互读、版本及 Release 核验成功；iOS 原生测试应用构建耗时 229.1 秒，`simctl launch` 返回应用 PID 20450，随后没有取得 VM 服务地址，步骤 20 分钟超时，测试用例未开始，后续备份和 Photos 步骤未执行。自有模拟器 Shutdown/delete 清理确认通过。原始 artifact 已按 GitHub 大小与 SHA-256 核对，[第二轮记录](validation/release-apple-second-ci.json)、[启动日志](validation/release-ci-second-ios-native-startup.log)和[清理日志](validation/release-ci-second-ios-simulator-cleanup.log)保留；尚不能据此确认底层应用或日志发现的具体原因。

后续 CI 验证采用自有模拟器的直接控制台采集，并通过 Flutter 的 [integrationDriver](https://api.flutter.dev/flutter/package-integration_test_integration_test_driver/integrationDriver.html) 连接已启动测试应用。该驱动仍须取得实际测试完成响应、真实 hostdriver 退出和控制台收尾，不能用启动 PID 或 VM 地址代替测试通过；本地控制检查也不代替后续 Apple CI。

主线程审查驱动后，本机 CI 控制测试 40 项通过（新增 iOS 驱动 29 项及已有版本/权限守卫 11 项），见[复验日志](validation/release-console-ci-controls-02.log)。首次默认沙盒运行因目录权限发生 setup/cleanup 错误，失败日志保留于[原运行](validation/release-console-ci-controls.log)；复验使用已有 Python 和工作区自有临时目录，仅设置并恢复当前进程环境，没有系统配置改动。Dart 驱动格式 2 文件/0 修改、五组独立版本/5 输出检查、`flutter analyze` No issues（105.8 秒）通过；[分析日志](validation/release-console-driver-analyze.log)与[资源包校验](validation/release-final-kit.log)留存。资源包 31 文件/56 本地引用完整性通过，不计为软件测试。

## 保留边界与待完成事项

尚待主线程验证 iOS 来源、完整四来源互读矩阵及新增 Photos 独立读回。真实图床服务能力仍为 unknown，继续拒绝派发；物理设备 PT、最低系统实测和硬件 PERF 未计通过。

本里程碑完成的是 Windows 与 Android 正式本地打包，不代表公开二进制发布、商店发布、Apple 正式签名发行或付费证书发行。Windows 完整 Release ZIP 不增加安装器。Android 签名私钥及口令继续只保存在 Git 忽略的本机 `.local`/受保护资料中；DPAPI CurrentUser 不能保证跨 Windows 用户或系统重装恢复，离线可移植密钥备份尚未实现。正式 Android 更新必须持续使用同一私钥。已安装的 debug 签名同 application ID APK 可能与正式签名冲突；由用户决定后续处理，脚本不自动卸载应用或清除数据。已有版本目录不覆盖。

发行流程和密钥保管细节见[本地发行与交付核验](distribution.md)。
