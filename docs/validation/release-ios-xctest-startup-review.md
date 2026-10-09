# iOS XCTest 启动与签名修正

日期：2026-10-09。第五轮 CI 源 `1e5a5bd` / run `37925642129` 已实际执行四个 Dart 业务用例，严格报告两项失败。下一轮修正尚须真实 Apple CI 验证。

首项用例的 Pigeon 操作之后，`WidgetTester` 结束校验报告仍有 `SemanticsHandle`。当前 SDK 的 `testWidgets` 先记录基线，再建立本用例的语义 handle；结束时释放自身 handle，核对 binding 与 pipeline owner 的总数。`SemanticsBinding` 对真实平台启用回调另持有一个 handle。根据此实际源码与失败时序，平台启动晚于测试基线是待验证的原因，不能据日志称业务主动泄漏已被证明。

[Flutter 官方 FlutterEngine 文档](https://api.flutter.dev/ios-embedder/interface_flutter_engine.html)说明 Simulator 默认启用语义，启用与语义树可用不是同一时刻。新的 `registerAppleXctestStartup` 仅在 `IMAGEHUB_XCTEST_EVIDENCE=true` 且真实 iOS 平台注册一次 `setUpAll`，以 Stopwatch 和 20 秒上限等待实际 `platformDispatcher.semanticsEnabled` 与 binding 状态，记录固定普通状态后才开始业务用例。不调用假平台 setter，不替换系统回调，不关闭语义，不改变 `testWidgets` 的默认语义或结束泄漏断言。超时仍失败。Mac、Android 和普通应用入口不启用这一钩子。

Keychain 在初始读取及孤立 UUID 清理/读回时返回 `-34018`。生产 `SystemSecretStore` 没有设置 `groupId`；`accountName` 只是 `kSecAttrService`，不能当 access group。最终 XCTest 命令原来明确禁用签名；[Apple DTS 对 -34018 的官方排查](https://developer.apple.com/forums/thread/114456)要求检查实际构建 app 的 entitlement，而不只看源 plist。

新的 CI 命令仅对固定 Debug Simulator 使用 `CODE_SIGNING_ALLOWED=YES`、`CODE_SIGN_IDENTITY=-` 和 `CODE_SIGN_INJECT_BASE_ENTITLEMENTS=YES`。不硬编码 Team/AppIdentifierPrefix，不修改生产 `Runner.entitlements`、bundle ID 或秘密命名空间，不添加 groupId，不加载发行 profile。Flutter 的前置无签名构建保留；真正由 XCTest 执行的宿主来自 Xcode 的新独立 derivedData。

真实 Xcode host/reader 结束后，核对精确 `Runner.app` 的严格 codesign、ad-hoc、bundle ID、无 Authority/profile，并读回真实 Info.plist 和固定 Runner `.xcent`/`.xcent-simulated`（若产生）。所有文件保持普通路径、大小上限、双读身份/摘要一致；拒绝复用旧 derivedData、覆盖证据、重复 plist 键或畸形类型。未知 entitlement 仅记录键名，白名单记录普通标识；签名 XML 缺席或未知 Simulator 合成前缀不单独判 Keychain不可用。签名 JSON 的 `keychainPermissionConfirmed=false` 明确表示该记录本身不证明运行时权限；原四项真实 Keychain 读写删及 finally 清理仍须全部通过。

本机三组控制检查 80 项通过、`py_compile` 和范围内 diff 检查通过。主线程读取实际 diff 及完整结果，没有把合成 Python child/plist 当原生能力。初次沙盒运行的目录解析权限失败保留于工具记录，未因此放宽真实 Apple 路径保护。当前三个 Dart 测试入口格式 0 修改、分析复验 No issues。下一轮原生结果、真实签名表达及 Photos 独立资源读回均仍待核验。
