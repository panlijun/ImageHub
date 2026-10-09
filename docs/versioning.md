# ImageHub 版本管理

`app/versions.json` 是版本号的唯一人工维护来源。它分别记录内核版本与修订号，以及 Windows、macOS、Android、iOS 各自的平台版本与 build。当前五组值恰好都是 `0.1.0+1`；它们彼此独立，修改一组不会自动改动其他组。

版本采用三段数字 `major.minor.patch`，每段不超过 65535；build/revision 从 1 开始。Windows build 上限为 65535，Android 为 2100000000，其余平台及内核修订号为 2147483647。Android 版本校验与安装前检查使用同一上限。Dart `pubspec.yaml` 的 `version` 始终对应内核 `version+revision`，不是任一平台的原生版本号。

在 `app/` 目录执行：

```powershell
dart tool/versioning.dart check
dart tool/versioning.dart generate
dart tool/versioning.dart describe windows
```

`check` 验证清单、Dart 版本及原生版本元信息是否一致；`generate` 从清单生成这些文件，并只同步 `pubspec.yaml` 的版本行，保留依赖、注释和换行，不应手工编辑生成结果；`describe <platform>` 输出该平台与内核版本摘要，平台为 `windows`、`macos`、`android` 或 `ios`。版本生成器不写资源包或数据文件。

应用设置页展示版本信息。升级产品版本不会重置资料库 schema 或备份格式；产品版本也不改变 bundle/application ID、平台通道、永久库、凭据命名空间等存储身份。

正式目标范围和交付方式遵循资源包《技术选型》13.1、13.2：Windows 11 x64 发布目录 ZIP，Android 10/API 29+ arm64 签名 APK；macOS 与 iOS 通过已授权的 Apple CI 流程处理。详见[技术选型原文](../imagehost-new-project-kit/documents/technology-selection.md#13-构建发布与兼容范围)。
