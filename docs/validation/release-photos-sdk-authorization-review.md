# Photos 权限证据与测试宿主 SDK 请求审查（第十至十二轮结果）

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

## 第十轮审查与验证边界（当时记录）

Sol实现者、Sol只读审查及主线程均阅读实际diff。三处授权拒绝的失败锁存已补齐；未发现其余可操作的线程、actor或生命周期问题。源中测试名称、精确asset查询和CRLF核对通过，diff whitespace检查通过。这些属于源码审查，不计为新测试通过数量。

第十轮记录时Windows没有Xcode，当时尚未编译Swift或运行新授权路径。六个Python控制器与其186项检查未被当轮Swift修改，原本机及第十轮Mac控制证据保留。当时计划下一次Apple CI实际编译并执行原27项、取得真实SDK状态/回调、PNG/JPEG资源读回、冻结身份、host/reader结束及自有应用/设备收尾；提示、超时或非授权结果继续失败。没有提前记为修复或原生通过，也不涉及物理设备、最低系统、硬件性能、真实图床或Apple正式发行验收。

## 第十一轮结果与下一候选

源`3588ed69b298cbdcfb5bc2c78041f3d587f1e8fc`、[run38145131826/attempt 1](https://github.com/panlijun/ImageHub/actions/runs/38145131826)整体failure。Mac job `114486776264`成功，iOS job `114486776379`失败于完整Photos读回步骤。SDK helper已真实编译运行：BMP前记录preflight，API调用前记录request-start；同一PID `76835`的readWrite为0、addOnly为3，30秒未观察到SDK授权callback，timeout失败锁存；后四格式在保存前停止。9条授权诊断由7项preflight、1项request-start、1项timeout组成。request-start先于API调用，不能证明dispatch交接或系统提示出现；实际grant photos命令exit0仍未获授权或资源读回，授权机制仍未知。完整套件27项/22通过/5失败/0跳过，Xcode65；invalid PNG像素解码nil、safe-unconfirmed与precancel通过，五格式没有独立资源读回。宿主冻结字段和生成entitlements/prepared SHA两阶段核对一致，owned app位置变化仅为该轮观察，不推断TCC或第九轮原因。完整摘要及41份白名单证据见[第十一轮记录](release-apple-eleventh-ci.json)。

候选实现和源码审查已完成：真实SDK调用返回后记录request-dispatched；控制器只在正常主循环观察精确信号、firstPID/owned UUID/冻结字段一致且授权仍pending时调用一次 `simctl privacy grant photos`。SDK 30秒超时不延长，grant exit0不代表授权；callback=3、SDK重读=3、27项及PNG/JPEG原字节读回、IO close、owned stop仍为门槛。215项本机控制检查通过（18.983秒/exit0），三处Python脚本内存编译及diffcheck通过，见[控制receipt](release-photos-live-controls-01.json)（SHA-256 `27aa095eac04455aa7afdd602570cf018537cbadda1a2b584ffa0f2cdbfb37c7`）及[terminal摘录](release-photos-live-controls-01.log)（SHA-256 `1dccd5620ae6c9a5f1736064588a0019244ceacfb421aa12d898ee3d57542dea`）。这是本机控制/源码证据，不是新Apple原生通过；下一次Apple CI尚未启动。新PID、第二请求、超时或未知状态继续失败锁存。生产仍为addOnly，无UI自动点击或TCC数据库操作。

第十一轮当时计划下一次Apple CI实跑原27项，并取得真实callback与SDK重读授权、PNG/JPEG原字节读回、IO关闭及owned app/Simulator收尾；grant exit0不作授权成功证据。实际第十二轮结果与新候选见下文。

官方资料：[Apple Photos授权请求](https://developer.apple.com/documentation/photos/phphotolibrary/requestauthorization%28for%3Ahandler%3A%29)、[Apple Photos保存指导](https://developer.apple.com/documentation/avfoundation/saving-captured-photos)、[Xcode 11.4关于simctl privacy的说明](https://developer.apple.com/documentation/xcode-release-notes/xcode-11_4-release-notes)；本轮实际`simctl help privacy`输出见[原始帮助摘录](release-ci-eleventh-ios-photos-privacy-help.log)，说明grant可绕过提示但不能替代用途说明与SDK API调用。


## 第十二轮结果与UI授权候选

第十二轮源`13db3d47f5e5b45c0205953723c49dc9b5daaabd`/[run38149991827](https://github.com/panlijun/ImageHub/actions/runs/38149991827)整体failure：Mac 217项controller检查有1项失败，后续步骤skip且无Mac artifact；iOS native/backup、Debug构建与版本、addOnly 1项通过。readWrite 17项starts中有15个AppleFileEngine终态通过，BMP/GIF无终态；无完整suite摘要或五格式独立读回。6条SDK诊断为readWrite 0，两个PID下callback均为-1；严格控制器在PID变化时拒绝继续。首次host退出原因未知，CLI grant exit 0不证明SDK授权或造成退出；IO/owned stop/Simulator清理通过。见[第十二轮receipt](release-apple-twelfth-ci.json)和[里程碑30](../milestone-30-versioned-delivery.md)；UI授权候选尚未实际Apple编译或运行。

下一候选采用独立顺序UI授权stage：官方`XCUIApplication`在固定owned Simulator及冻结同host内触发真实readWrite SDK请求，只在明确显示expected FullAccess alert时点按一次，并要求实际callback=3和SDK重读=3。授权证据后关闭host/reader、确认owned app停止并post核对冻结字段，再启动原27项RunnerTests；full阶段不做privacy mutations，同阶段PID变化仍失败。该候选尚未由Apple CI实际编译或运行，控制测试与源码审查不作原生通过证据。生产Photos仍为addOnly，不做TCC数据库操作或自动授权点击。

2026-10-12的新候选采用4个顺序阶段（prepare、add-only、authorize、read-write），使用独立`ImageHubPhotosCI` scheme；`authorize`通过官方UI测试读取真实SDK请求、预期系统Full Access按钮点按及一次callback=3/SDK重读=3证据。同run/attempt/owned UUID、冻结host、实际host/reader关闭、owned app停止及XCTest摘要均为后续门槛；完整read-write阶段不做任何privacy mutation，同阶段PID变化仍拒绝。CI探针仅由明确的Debug/Simulator编译条件和启动参数启用，生产默认入口及addOnly不变。全套本机Python控制240项通过（20.097秒/exit0），含45项严格协议与真实读取线程专项；10份相关来源字节在测试前后保持一致。见[UI控制receipt](release-photos-ui-controls-01.json)（SHA-256 `5264549809ceac1086e285231e56c6e0e09a2c4c688d5cad89c13609fe95ce6e`）及[终态摘录](release-photos-ui-controls-01.log)。这是本机合成控制证据，不是Swift编译、系统弹窗/Photos callback或资源读回通过。前一测试等待修正的218项为中间旧actor快照，保留[controls03](release-photos-live-controls-03.json)；原27项XCTest、PNG/JPEG原资源字节断言及Windows/Android正式包不变，下一轮Apple必须实跑。

系统预期提示按正常UI查询、等待、校验及明确事件处理，参考[Apple WWDC20的预期提示测试指导](https://developer.apple.com/videos/play/wwdc2020/10220/)；不使用通用中断处理器猜测按钮。此资料支持测试方式，不证明本项目实际授权已成功。
