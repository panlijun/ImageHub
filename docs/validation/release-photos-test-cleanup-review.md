# Photos 验证与测试目录保全审查

日期：2026-10-09。Sol（`gpt-6.1-sol`，`high`）完成只读审查，主线程核对实际源码和修改 diff。本文件是源码审查记录，不是 Apple 编译或运行通过记录。

旧 addOnly 测试在保存回调结束后无条件递归删除验证根目录。`AppleFileEngine.finishPhoto` 允许保存已确认但 `cleanupPending=true`，也允许失败后保留不确定暂存；回调结束不能代替安全清理证据。新增格式测试虽有收尾标记，断言失败和未知子项仍不应触发递归删除。

主线程将 `app/ios/RunnerTests/RunnerTests.swift` 中四处 Photos 测试目录清理改为仅 `bridge.dispose()`：合成来源与失败现场保留到当轮自有模拟器确认 Shutdown 后整体退休。没有修改生产实现、预期结果、用例数量或断言；既有 owned-device 清理继续核对 run/attempt、UUID、名称、runtime/type、关闭与删除读回，不清其他设备。

源码核对结果：

- `RunnerTests.swift` 的 12 项与共同 `AppleFileEngineTests.swift` 的 15 项合计 27。工作流先以 addOnly 执行一项，再授予本轮自有设备 read-write 并要求 27 项零失败零跳过。`ImageHubFlutterIntegrationTests.m` 在默认关闭的 CI 宏内，不增加普通 Photos 套件计数。
- PNG/JPEG 必须真实保存并独立读回一致。GIF/WebP/BMP 成功时也必须读回原始字节，或明确报告 unsupported/unconfirmed；不能把后三项的安全失败记成格式支持。
- 仅按本次保存返回的规范化标识查询，限定 `.photo` 与本次原文件名。禁止网络资源读取，等待 PhotoKit completion 后核对实际字节数与 SHA-256；没有全图库查询或 Photos 删除。
- 来源字节与私有 stage 退休仍有原断言；等待超时、失败、暂存未确认及资源流未结束时，不再递归删除测试来源目录。

此改动尚未提交至 `ff84f1b` 的 CI；须由后续源的实际 Apple CI 验证编译、一项 addOnly、27 项全套、各格式结果和自有模拟器收尾。物理设备、最低系统、Files 提供者、完整 PT/PERF 仍不计通过。
