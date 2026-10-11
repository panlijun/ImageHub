# 第十轮 Photos 权限证据与测试宿主 SDK 请求审查

日期：2026-10-11。第十轮源 `acdbb2bb3d788d7bb6711d0c9439b012ded7dba4`、run `38141681520`、attempt 1 整体失败。[闭合记录](release-apple-tenth-ci.json)与41份白名单日志、JSON或摘录保留实际边界。该记录不是后续修正的原生通过证据。

## 已观测事实

完整 XCTest JSON 摘要及27个唯一终态行一致：22通过、5失败、0跳过；10条文本断言失败记录不等于10个失败用例。五格式全部在保存前的 `readWrite` 授权检查失败：实际状态为 `notDetermined(0)`，预期 `authorized(3)`。同一运行的 `photos` grant 命令退出0、宿主与测试bundle ID正确、两项用途说明存在，`addOnly` 状态为3。它们不能证明已经获得读写授权。

invalid PNG 的真实像素解码失败断言、保存后的 `safe-unconfirmed`、来源保留和暂存退休通过；precancel 也通过。五种格式没有执行到原始资源独立读回，不能据其他通过项宣称PNG/JPEG字节已确认。

add-only与read-write的后验观察均实际读取四个组件，记录的宿主内容、签名、版本、生成entitlement和prepared原始摘要保持一致；本轮自有应用的位置与初始位置不同。这是第十轮位置观测，不包含权限撤回或安装事件，不证明权限失败原因，也不能反推第九轮的具体差异。宿主指纹范围是所记录字段，不是整个bundle字节树。

## 确定的最小候选

当前测试helper原来只查询 `authorizationStatus(for: .readWrite)`，没有调用读写授权请求。Apple在[保存照片指导](https://developer.apple.com/documentation/avfoundation/saving-captured-photos)中区分读取与添加权限，并在未决定时使用级别明确的SDK请求。[requestAuthorization文档](https://developer.apple.com/documentation/photos/phphotolibrary/requestauthorization%28for%3Ahandler%3A%29)说明handler返回系统决定后的状态；它不是强制grant接口，可能触发系统提示。本轮原始[simctl帮助](release-ci-tenth-ios-photos-privacy-help.log)也提醒测试grant不能替代应用遵守SDK请求规则。这些资料支持补齐缺少的调用路径，不保证其在无人交互CI中成功。

只修改 `app/ios/RunnerTests/RunnerTests.swift`：

- 先核验CI专用Simulator名称/UUID、固定宿主/测试bundle、两项用途说明以及真实addOnly授权。只有 `readBack=true` 且readWrite为未决定时请求一次真实SDK授权。
- 跨XCTest实例共享状态由NSLock保护。真实callback记录闭合，30秒XCTWaiter完成且callback与SDK重读都authorized，才允许生成来源、保存和查询。
- 请求拒绝、超时、等待失败或后续授权重验拒绝，锁存当前宿主失败。晚到或重复callback不能清除失败、重发请求或恢复保存；limited与未知状态仍失败。
- callback只处理授权状态与固定诊断，不持有图片读写任务。没有系统UI自动点击、TCC数据库修改、运行中追加grant、全库查询、资源删除或网络访问。

生产 `IOSFileBridge.swift` 继续只请求addOnly。原12项RunnerTests与15项AppleFileEngineTests、总27项及零跳过门槛不变；PNG/JPEG仍必须成功保存，并按本次返回的精确asset与原始resource核对长度和SHA-256，真实读取完成后才收尾。

## 审查与验证边界

Sol实现者、Sol只读审查及主线程均阅读实际diff。三处授权拒绝的失败锁存已补齐；未发现其余可操作的线程、actor或生命周期问题。源中测试名称、精确asset查询和CRLF核对通过，diff whitespace检查通过。这些属于源码审查，不计为新测试通过数量。

Windows没有Xcode，本次尚未编译Swift或运行新授权路径。六个Python控制器与其186项检查未被本次Swift修改，原本机及第十轮Mac控制证据保留。下一次Apple CI必须实际编译并执行原27项、取得真实SDK状态/回调、PNG/JPEG资源读回、冻结身份、host/reader结束及自有应用/设备收尾；提示、超时或非授权结果继续失败。没有提前记为修复或原生通过，也不涉及物理设备、最低系统、硬件性能、真实图床或Apple正式发行验收。
