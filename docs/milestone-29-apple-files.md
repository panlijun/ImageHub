# 里程碑 29：Apple 文件与照片能力

日期：2026-10-09。推进 iOS 原生导出与 macOS/iOS 备份取得；保留 Windows/Android 完成基线、正式 ImageHub 名称和稳定存储身份，资源包只读。

## 实现

- 新增共享 Swift 文件引擎与真正生成的 Pigeon 接口；iOS Files 目录独占导出和 Photos addOnly 保存、Apple 备份 ZIP 选择及授权收尾已接入共同工作台/备份/诊断路径。
- 共同私有备份复制从现有 Android 实现提取，保持原行为；macOS 桌面导出仍走既有 file_selector/FileExporter。
- 默认同名生成新名，实际 SHA/长度及源/目标身份校验，取消等待真实 IO，晚到成功保留；关闭/清理不确定保留现场和授权登记。
- 选型 8.1/8.2 的具体差异、实现边界和官方依据见 [Apple 原生文件说明](apple-native-files.md)。

## 当前验证进度

- 初次定向测试：122 通过、2 失败；两项为新增导出 URI 校验，原始失败记录保留于 `validation/apple-transfer-focused-tests.log`。
- 修正带空格文件名的 URI 解码比较和点路径归一化拒绝；10 项 Apple 导出测试全部通过，见 `validation/apple-export-correction-tests.log`。
- 完整 Flutter 分析无问题（47.1 秒），273 文件格式 0 改动；新增真实通道 smoke 随后单文件分析通过。
- XCTest 结果检查器的成功样本及六种缺失/跳过/失败/类型/计数错误拒绝检查通过；原生结果尚待 CI，不据检查器通过宣称 Apple API 通过。
- 资源包 31 文件、56 引用完整性通过，实际 diff 空白检查通过。

Apple 云端 XCTest、当前源完整软件测试、构建与 Windows 回归仍在本轮推进中；终态记录在取得真实结果后补齐。iOS 照片真实用例预期必须执行，不允许跳过后记通过。

## 未计通过

物理设备、最低 Apple 系统、真实选择器/Files 提供者 UI、权限拒绝与撤回的系统行为、参考硬件 PERF/断电、四端人工互读、正式签名/公证/发行均保留。真实 Catbox/ImgBB 联调没有授权，精确能力 unknown 守卫不变。
