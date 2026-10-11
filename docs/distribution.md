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

第八轮 Apple CI [run37938849959](https://github.com/panlijun/ImageHub/actions/runs/37938849959)是历史整体failure；当时四来源矩阵为11方向/22模式，详见[第八轮记录](validation/release-apple-eighth-ci.json)。

第九轮 Apple CI [run38137413108](https://github.com/panlijun/ImageHub/actions/runs/38137413108)源`09b849de824c38a9dbe714ce1e4c390f1f871c65`/attempt 1整体failure。Mac job成功：134项本机控制、1,456项软件通过/4个Windows平台分支跳过、4项Flutter原生、8项进程边界、23项XCTest零失败零跳过、Release 64.5 MB及独立版本核验通过；备份4个命名业务（本机导出和三个外部来源），自身来源跳过1项不计业务。iOS→macOS完整与元数据恢复、关闭重开及8项设置通过。iOS job因后验控制器`photos-prepared-host-changed`失败：native和backup各4项Dart业务/4项callback/1项XCTest通过，ad-hoc签名、owned stop及native真实Keychain流程通过；backup三个外部来源双模式/重开/8项设置通过；正常入口Simulator构建/版本通过。Photos prepare阶段真实闭合构建和安装且所记录指纹相同；addOnly真实XCTest 1通过/0失败/0跳过，Xcode exit 0，host/reader关闭。具体指纹差异未知，不能认定路径迁移已发生，也不能认定原生保存测试失败。没有成功的addOnly result/identity，因此完整read-write 27项未执行且无摘要；owned app stop和Simulator Shutdown/delete/absence通过。32份闭合白名单证据及两个artifact大小/SHA见[第九轮记录](validation/release-apple-ninth-ci.json)。四来源矩阵已完成12方向/24模式，详见[完整矩阵receipt](validation/release-interop-four-origin-complete.json)；这不等于四台物理设备人工互读/PT通过。第八轮Photos 21通过/6失败仍保留为历史，不倒推成修正通过。测试控制器逐项诊断、受限当前位置查询及三处异常收尾缺口已修正并独立复核；186项本机控制与六文件编译通过，见[最终控制记录](validation/release-photos-frozen-host-controls-02.json)。源码审查见[Photos host guard审查](validation/release-photos-host-guard-review.md)。第九轮收尾时“下一轮Apple实际运行待补”是当时状态；第十、十一轮见后续各节。物理设备/PT/PERF、最低系统实测、Apple正式签名发行和真实图床联调仍未通过，服务能力为unknown时继续拒绝派发。

第十轮 Apple CI源`acdbb2bb3d788d7bb6711d0c9439b012ded7dba4`的[run38141681520/attempt 1](https://github.com/panlijun/ImageHub/actions/runs/38141681520)终态failure。Mac job `114476650793` success：186项本机控制（7.198秒）、1,456项软件/4个Windows分支跳过、8项独立进程边界、4项Flutter原生、23项XCTest零失败零跳过、Release 64.5 MB及原生版本0.1.0+1；备份4项业务（本机1、外部3），自身来源skip 1不计业务；Windows/Android/iOS来源双模式恢复、关闭重开及8项设置通过。iOS job `114476650544`在Verify native IO and exact synthetic Photos resource readback失败：native与backup各4项Dart业务/4项callback/1项XCTest通过，ad-hoc与owned stop通过，native Keychain真实新实例流程通过；backup三外部来源full/meta/reopen及8项设置通过；正常入口Simulator构建/版本、Photos prepare真实闭合构建/安装、addOnly真实XCTest 1通过/0失败/0跳过及Xcode exit0、host/reader关闭、owned stop和成功result均通过。完整readWrite 27项为22通过/5失败/0跳过，Xcode exit65且JSON摘要计数为真实结果。BMP、GIF、JPEG、PNG、WebP在保存前均观察到notDetermined(0)，预期authorized(3)；实际grant photos命令exit0，但五格式外部资源独立读回均未确认。invalid PNG的像素解码失败断言（CGImageSourceCreateImageAtIndex返回nil）与safe-unconfirmed、precancel通过。两次post观察均观察到四组件，冻结字段、生成entitlements和prepared SHA不变；owned app当前位置与初始不同，但位置变化不能判定授权根因或反推第九轮。10条failure records不等于10个失败用例。owned app stop及Simulator Shutdown/delete/absence通过。receipt [第十轮CI摘要](validation/release-apple-tenth-ci.json) SHA-256 `81f785016045e9117893967343be3b152c2a4954d9acef3802cd3e9f228fac3a`，另有41份原证据/摘录（摘录不等于完整原日志）。完整Mac/iOS archive分别为26,004,863 bytes/SHA-256 `b0e57af4b8b74a5f2190a2556376be220d76ae2913ca354f5415a55b7f3e8c26`和124,347,713 bytes/SHA-256 `589f0895a6acf1006a3ac251c409f2cab326f8258ee46ea89999bfe9712545b0`；首次不完整iOS下载私有保留，不作证据。Windows ZIP及Android专用签名ARM64 APK未重打包；`formal-final-audit`的09b源只是历史核验，不代表acdb新包或clean源构建。第十轮记录当时，Photos测试路径候选修改已完成源码复核；Swift编译和实际授权仍待下一次Apple CI，不表示已修复授权根因或保证读回成功。第九轮的`photos-prepared-host-changed`仍仅为当轮后验失败记录，未知原因不被后续推断。


## 第十一轮 Apple CI

第十一轮Apple CI源`3588ed69b298cbdcfb5bc2c78041f3d587f1e8fc`/ [run38145131826](https://github.com/panlijun/ImageHub/actions/runs/38145131826)整体failure。Mac作业成功，iOS失败于Photos完整读回；27项为22通过/5失败/0跳过。SDK helper已在Apple runner实际编译运行，但首个请求30秒未收到授权callback；grant photos命令exit0未证明授权，五格式独立读回未确认。完整证据、artifact指纹及当前pending候选见[里程碑30](milestone-30-versioned-delivery.md)和[授权审查](validation/release-photos-sdk-authorization-review.md)。四来源矩阵及Windows/Android本地包维持既有状态；设备PT、最低系统、硬件PERF、真实服务及Apple正式发行未通过。

## 第十二轮 Apple CI

第十二轮源`13db3d47f5e5b45c0205953723c49dc9b5daaabd`/[run38149991827](https://github.com/panlijun/ImageHub/actions/runs/38149991827)整体failure：Mac 217项controller检查有1项失败，后续步骤skip且无Mac artifact；iOS native/backup、Debug构建与版本、addOnly 1项通过。readWrite 17项starts中有15个AppleFileEngine终态通过，BMP/GIF无终态；无完整suite摘要或五格式独立读回。6条SDK诊断为readWrite 0，两个PID下callback均为-1；严格控制器在PID变化时拒绝继续。首次host退出原因未知，CLI grant exit 0不证明SDK授权或造成退出；IO/owned stop/Simulator清理通过。见[第十二轮receipt](validation/release-apple-twelfth-ci.json)和[里程碑30](milestone-30-versioned-delivery.md)；UI授权候选尚未实际Apple编译或运行。
