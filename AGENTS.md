# ImageHub 新项目工作区约定

## 输入与范围

- 2026-10-09第七轮Apple CI源`1cb16cfddcbd67cf8d744b5107a2797d3fdd2007`/run`37934102081`整体failure。Mac success：1456软件/4Windows跳过、8项独立进程、4项Flutter原生、Windows/Android来源完整/元数据/重开、23项XCTest零失败/跳过、Release64.5MB及版本成功。iOS构建211.0秒；semantics基线handle=1，4命名Dart/4 SDK callbacks均pass、1 XCTest零失败/跳过、ad-hoc签名/真实Keychain流程pass、Xcode exit0及host/reader关闭。owned guard成功后simctl terminate退出3、host/reader关闭，收到NSPOSIXErrorDomain code3的实际六行“found nothing to terminate”；本轮解析器未匹配，仍报owned-app-stop-unconfirmed。底层app是否停止不确定；自有设备Shutdown/delete/absence确认，backup/Photos/正常入口未执行。最新源只增加匹配这段完整观测六行、固定bundleID/domain/code/TAB顺序且exit3的解析分支，旧分支不变，混合/未知文本继续失败；Apple官方仅说明domain-specific ESRCH=3/no process，不定义整段simctl文案，原始文本以本CI日志为准。94项控制检查及闭合日志离线匹配仅为本机控制证据，不是Apple原生修正通过。证据见docs/validation/release-apple-seventh-ci.json、release-ci-seventh-ios/macos九份证据和release-xctest-esrch-controls-01.log（SHA-256 e0f597f5e14e66b44c7673fd77831052bd8860b2c4a8405bb93565b3a0d75393）。第六轮停止原因仍unknown，不逆推；下一CI须实跑。

- 2026-10-09第六轮Apple CI源`5326d527962daad1de23f3340dda40b55aec6e78`/run`37929517038`整体failure：Mac1456软件/4平台跳过、八项进程边界、四项Flutter原生、Windows/Android来源完整/元数据/重开、23项XCTest和Release/版本成功；iOS构建199.0秒，真实平台/框架semantics启用后基线handle=1，四个Dart业务用例及SDK回调4项、1项XCTest零失败/跳过、Xcode exit0及host/reader关闭，ad-hoc签名和实际Keychain读写/新实例读/删/清理断言通过。整体仍因owned-app-stop-unconfirmed失败；底层guard/stop/close原因未暴露，不能猜测应用已停止。自有模拟器Shutdown/delete/absence成功；backup、新Photos、正常入口未执行。framework+6含setup/teardown不计业务通过；signing evidence的keychainPermissionConfirmed=false仅表示该记录不能证明权限，runtimeKeychainFlowPassed=true来自独立实际用例。两artifact大小/SHA已核验，见docs/validation/release-apple-sixth-ci.json及release-ci-sixth-macos-*四份和release-ci-sixth-ios-*五份白名单证据。停止诊断仅XCTest启用，89项三模块本机控制测试通过2.600秒，见docs/validation/release-xctest-stop-controls-01.log（SHA-256 b560645c10e1606c079f4ad219da505c3f0912cb00eac23ba53d9bc5e1d0b5aa）；此项不能替代Apple实际运行。默认直接控制台路径不变；实际退出诊断仅在close_host真实返回后发出，强制结束码仍只作诊断且保持失败；guard/command输出固定分类，未知异常不调用toString。run_command关闭异常仍可能覆盖主失败语义，发生时仍严格失败。以上是第六轮当时诊断边界；当时下一次CI尚待实跑，第七轮见本节最新条目；其停止原因不能由第七轮反推。

- 2026-10-09第五轮源1e5a5bd/run37925642129整体failure、Mac success（1456软件/4跳过、八进程边界、四原生、两外部来源双模式、23XCTest/Release/版本）；两artifact大小/SHA已核验，见docs/validation/release-apple-fifth-ci.json。iOS新XCTest正常编译并完成四个Dart业务用例，真实存储/图库/IO与网络通过，首项SemanticsHandle结束检查与Keychain初始/清理读取OSStatus=-34018失败，XCTest拒绝成功，exit65且host/reader结束；tearDownAll不计业务通过。应用停止未确认，独立owned Shutdown/delete/缺席已确认。后续仅IMAGEHUB_XCTEST_EVIDENCE+iOS入口在setUpAll单调有界等待真实平台语义启用后再记录测试基线，不禁用回调/语义/泄漏断言；CI固定Debug Simulator xcodebuild采用本机ad-hoc及基础entitlement注入，同次全新derivedData实际host签名/Info/生成entitlement严格读回留证，原Keychain用例仍为门槛，不修改生产groupId/命名空间/身份或要求团队profile。80控制检查通过、三文件Dart分析No issues；当时实际下一轮Apple仍待验证，不记原生通过。
- 2026-10-09第四轮源ff84f1b/run37923129828的iOS构建/版本成功，Xcode destination使用小写UUID而未匹配其已列出的大写同一自有设备，exit70、host/reader真实关闭，Dart/XCTest未开始；应用停止未确认，后续owned Shutdown/delete/缺席确认通过。原始iOS artifact18765 bytes/SHA已核验，三份日志见docs/validation/release-ci-fourth-ios-*.log。新XCTest入口只将严格UUID的Xcode destination大写化，marker/simctl身份不变，无名称/booted后备；69本机控制检查通过，当时实际Apple运行仍待补。Photos源码计数12+15=27和精确本次资源读回已审查；四处测试合成根的递归删除改为保留到自有模拟器实际关闭后整体退休，失败/不确定暂存不因断言或callback被抹掉，生产代码及原断言不变。见docs/validation/release-photos-test-cleanup-review.md和里程碑30，不将这些控制检查/源码审查记为原生通过。

- 2026-10-09第三轮源17a7df2/run37918498083已结束：Mac1456软件测试/4平台跳过、四项Flutter原生、23XCTest及Release/独立版本再次成功；iOS正常构建和版本核验成功，直接控制台120秒内未取得VM，PID19538仅在自有应用停止后出现，Dart用例/hostdriver未开始。应用停止、真实console exit0及自有模拟器关闭删除确认，两artifact大小/SHA已核对；见docs/validation/release-apple-third-ci.json，不猜测底层原因或计作业务失败。后续仅测试target/CI采用run_ios_xctest_integration.py正常编译固定Dart入口和官方同进程IntegrationTestPlugin/FLTIntegrationTestRunner：明确单suite宏、仅CI -ObjC、不再静态链接另一份plugin；单调有界等待、精确四个Dart名称/成功/回调、一项XCTest零失败零跳过及真实host/app收尾全部确认才交付。备份仅测试编译flag允许写Library/Caches下新普通闭合白名单证据，owned容器双读/摘要/来源/全设置验证后复制，不覆盖或猜删。原控制台路径与失败记录保留。68本机控制测试通过，不代替Apple原生运行；Windows Python ctime诊断及原67项失败保留，Darwin仍比对完整六字段，见里程碑30。

- 2026-10-09用户设定持续目标：完成现有环境可继续的软件任务，再完成Windows与Android正式本地打包，并建立一个内核版本及四端独立版本。此授权包含本地Android长期release签名与打包，不含对外发布、商店开通或付费证书。Windows沿用选型13.1/13.2的完整Release目录ZIP，不引入额外安装器；Android为arm64签名Release APK。版本单一源为app/versions.json，内核与四端各自维护，数据schema/备份格式不随产品版本重置；app/tool/versioning.dart生成并检查Dart与四端原生元信息。签名私钥与密码仅放忽略的本机.local/受保护资料，不进Git、诊断、CI或交付包；默认release禁止debug签名降级。真实图床和实机排除继续遵循既有范围。

- 2026-10-09本轮收尾进行中：Windows1459软件测试通过/1平台跳过、M1快捷入口20项、五项Windows原生及正常Release启动退出已通过；真实4,328,697,800字节ZIP64默认预检/合并/重开全部字节、62冷缩略图实际读完后租约为0已验证。Windows正式ZIP与Android专用签名ARM64 APK已实际生成并核验，内核/平台0.1.0+1；源base cfd55d0、dirty=true仅两张既有验证截图，不能称clean源构建。Windows完整34条目及解包正常启动退出，Android精确build1、API29、唯一ARM64、非debug和专用v2证书通过，见里程碑30及两份formal receipt。源95b94d3/run37908256215与源d5bb06d/run37913146736的Mac均1456通过/4跳过、四项Flutter原生、23XCTest及Release成功；前轮iOS四项原生通过后备份启动超时，本轮iOS构建和启动PID成功却未取得VM服务，20分钟超时，均清理自有模拟器成功，不能称整体CI成功或业务用例失败。Windows/Android/Mac六个软件互读方向已有完整/元数据恢复重开证据；iOS来源、完整四源矩阵和新增Photos独立读回仍待补。详见docs/validation/release-apple-first-ci.json、release-apple-second-ci.json及E36，不以这些证据替代物理设备/PT/PERF/最低系统或真实服务。

- 用户于2026-10-08明确正式名称为 ImageHub，并授权创建公共仓库 `panlijun/ImageHub`、提交推送和运行标准 Apple CI。原资源包及历史记录沿用当时的 ImageHost 名称，保持原件。Dart package、应用 bundle/application ID、平台通道、Windows CompanyName/ProductName 技术存储身份、永久库与秘密命名空间保留，避免品牌更新改变本项目自身的数据位置；用户可见名称与新导出前缀统一 ImageHub。

- 2026-10-08标准 Apple CI 同源整体通过：源提交 `a6d0640`、run `37795607653` 的 macOS 与 iOS 作业均 success。Mac 1396软件测试通过/4平台分支跳过、六个独立进程恢复边界/重开/锁、三个原生用例及Release `ImageHub.app`构建通过；iOS26.2/iPhone17 Simulator三个原生用例、正常入口未签名Debug应用构建及自有设备清理通过。原生用例覆盖真实statfs/独占发布、SQLite/永久副本/图库/像素与IO保护、Keychain及被动网络，不等于Apple全部产品功能、最低系统兼容、签名发行或设备PT完成；早期失败/取消保留，详见 `docs/github-publication.md`。

- 2026-10-09 Apple原生文件软件实现及适用验证完成：源`9715ce9`、run`37879708343`两作业success，Mac1424软件测试通过/4Windows分支跳过、独立进程恢复/锁、四项Flutter原生、23项XCTest零失败零跳过及Release64.5MB通过；iOS26.2/iPhone17四项Flutter原生、20项XCTest零失败零跳过（含真实Photos addOnly合成PNG事务）、正常入口Simulator Debug构建和自有设备清理通过。本机Windows1427通过/1平台分支跳过，处理/备份/诊断原生回归、Release及正常启动退出通过，Android ARM64 Release构建通过。窗口回调为受控协议，addOnly没有独立读回Photos外部副本，未证明全部格式、最低系统/物理设备/正式发行；详见docs/milestone-29-apple-files.md。最终文档提交含应用README修正，运行代码/配置/工作流与成功源一致，不把文档提交记作新CI通过。

- 用户于2026-10-08要求持续推进 Android 软件开发至完成；复用现有 Flutter/Dart 工程与已选 M1，保留 Windows 完成基线。新增工具统一放 `D:\Workspace\DevelopmentTools`；C 盘已有工具保留并复用，不迁移、不重复安装。用户已明确同意下载和安装 JDK 21、官方 Android SDK/API36/Build Tools/NDK、模拟器/系统镜像及 Gradle 依赖，并接受相应标准许可；新增缓存和模拟器数据也放该 D 盘目录，先不改系统 PATH。实机/硬件和真实账号联调的既有排除范围继续保留，不以模拟器证明实机 PT 通过。

- 2026-10-08 Android 软件实现与本轮适用验证完成，见 `docs/milestone-28-android-completion.md`：1399软件测试通过/1非Windows分支跳过，API36 x86_64原生闭环及SAF/MediaStore桥、五个外部保存字节独立核验、正常Release应用导入/重开/处理/照片保存/ZIP合并恢复/诊断导出通过。ARM64和x86_64 APK均实际构建，沿用本地debug签名；ARM64实机/API29/PT/PERF/正式签名及真实服务仍不计通过。受影响的四个Windows原生流程和Release启动退出回归通过；该完成阶段未新增Git提交，后续公开与Apple CI见上述最新记录。

- 用户于2026-10-08明确不需要Catbox匿名上传，产品范围覆盖ACC-001/ACC-002/ACC-004的匿名目标：仅提供Catbox userhash账号和ImgBB APIKey。新配置、默认选择、入队、派发授权和适配器均拒绝匿名；本项目自身已有匿名身份仅保留普通历史/备份读取，不删除数据或转换UUID，禁止重新启用。资源包原件不变。
- 用户于2026-10-07取消Catbox匿名真实联调；已准备的五张合成图不得发送。当前目标排除需要真实账号的测试，没有授权真实上传/删除/探测，不以合成凭据和受控HTTP称真实服务通过。

- 2026-10-08本轮Windows软件开发及适用主机验证完成，见docs/milestone-27-windows-completion.md：1314软件测试通过/1非Windows分支跳过，五个Windows原生子流程、独立进程恢复/重开/锁、分析、Release及正常启动退出通过。此结论按用户排除范围限定，不等于真实图床已可用、四端正式发行或全部PT/AT/PERF通过；精确服务能力unknown仍等待。

- 用户于2026-10-07要求本轮排除需要实机的剩余验收，继续非实机软件开发。具体拆分见 `docs/software-completion-scope.md`：PT设备验证及真实硬件性能/断电不作为本轮开发阻断，不计通过；已有主机自动化SQL/files/codec/widget、构建与源码审查仍执行。平台代码未接入不能改记“缺设备”；真实图床契约/联调不是实机验收，仍独立保留且不得未经授权发请求。

- 用户于2026-10-07明确取消网络计费状态实现：只识别网络类型并按允许类型控制已确认上传任务的自动派发/网络恢复继续。“自动同步”当前按既有图床上传流程处理，仍无应用云账户或图库云同步。此决定覆盖QUE-008/UT-063中计费判断；资源包原件保持不变，验收台账保留原文并明确本项目采用的最新规则。

- NetworkSnapshot只读本机默认路径的wifi/ethernet/cellular/other与offline/unknown，不读取计费/SSID/IP，不做联网探测。LibrarySession持有观察器；严格原生协议与listen握手成功后才允许快照生效，失败/结束/超时为unknown，晚到读/监听隔离。桌面可见失焦继续观察，隐藏/移动后台停止新派发，前台重读；不能承诺后台持续执行。
- 任务页手动刷新可重读/重建失效网络监听，不授予许可；即使观察重读失败也独立读取资料库，保留最后有效列表与读取失败提示，不用通用操作反馈吞掉该保护。
- DeviceSettings自有格式3保存网络类型策略；默认Wi-Fi/有线，可明确允许含移动的所有已识别网络。自身1/2读默认不改输入，损坏/未来拒绝。策略与本次会话许可独立；恢复网络不授予许可、不解除暂停、不缩短退避、不重传unknown、不取消已运行请求。真实文件/凭据校验后在writer事务再次核对mayDispatch，拒绝不创建尝试/租约；请求前仍重验，只有明确notSent才允许继续。替换清许可，关闭先阻止新派发。

- 默认中文，结论先行。用户最新决定优先，其后依次为资源包需求 1.1、技术选型 1.0、当前设计规格、HTML 原型。矛盾须报告具体编号及影响，不自行改业务规则。
- `imagehost-new-project-kit/` 是独立只读实施输入，保留全部原文件；生产应用在 `app/`，实施与验证记录在 `docs/`。不读取、复制、修改旧项目源码、旧数据库或旧应用数据，不做旧格式兼容。
- 已完整阅读资源包 README、AGENTS、IMPLEMENTATION 和 documents 五份 Markdown；同内容 Word 不重复读取。桌面按 A；用户于 2026-10-04 选定手机以 M1 图库优先为基准并接受优化方向。原型在独立 `design/mobile-m1/`；Flutter M1 在 `app/`，资源包原件不变。按 Android/iOS 平台选择 M1，窄桌面仍采用 A；主机布局模拟不能作为手机实机验收。
- Flutter/Dart 四端目标：Windows 11 x64、macOS 12+ arm64、Android 10/API29+ arm64、iOS 15+ arm64。只有实际构建及设备验证过的平台才能报告可运行。
- V1 本地个人工具，无应用云账号、云同步、团队、新图床、Web/Linux；Catbox账号/ImgBB适配器及持久任务已接入，精确服务能力未知时仍等待、不派发。全部 V1 P0/P1 的适用软件行为仍保留，Windows本轮完成与四端正式发行/真实服务验收分别记录。

## 技术与边界

- 2026-10-09完成Apple文件能力：Pigeon29.0.7生成配套Dart/Swift接口，AppleFileEngine负责64KiB有界来源读取、范围授权、私有源校验及目录独占复制；iOS UIDocumentPicker选择目录后保存文件，PhotoKit addOnly从闭合私有暂存添加资源并shouldMoveFile=false，Mac NSOpenPanel/Apple备份来源接共同私有复制服务。真实IO结束和授权release后才交付；取消不提前释放，晚到保存与清理失败分别保留。关闭不确定保留句柄/授权登记，未知/变化/链接不得猜删。选型8.1/8.2差异和验证边界见docs/apple-native-files.md；当前真实XCTest与构建结果见docs/milestone-29-apple-files.md。系统选择器UI/Files提供者及物理设备PT仍排除。

- 导入选择窗口与实际复制属于同一受跟踪操作；打开选择器前建立取消令牌，停止/退出等待选择器返回及实际来源/写入收尾。停止后晚到资源不得打开，新导入保持禁用到完整收尾；未知异常只给固定反馈。
- PNG eXIf按完整PNG边界/CRC及有界TIFF严格读取方向1–8；缩略图、像素处理及原图SDK预览按同一方向转换且不改变永久字节。180度处理覆盖奇数高度中间行；SDK帧转换等待真实图像生成后释放源/画布资源，保留动画帧时长及循环。
- 本项目自身前阶段PNG方向遗漏只在用户同SHA/字节重导入并真实校验后纠正：旧方向1及编码尺寸与新方向2–8显示尺寸精确对应、帧数相同，仅改永久版本三字段，身份/整理/字节不变。实际租约或持久引用拒绝修改，回收对象先明确恢复，其余描述矛盾拒绝。复用分支的关联事务同时保存来源与committedReuse日志，已提交后清理失败保留证据重开重试，不回报未保存。
- 备份永久版本之间的描述冲突仍阻止；审计冻结描述只接受上述已知PNG旧1→确认2–8关系，不能反向用新审计覆盖旧永久。恢复只重映射已确认UUID，不改冻结方向/尺寸/参数。相同摘要不能作为任意描述差异的豁免。
- 缩略图登记自身格式2为修正后的像素生产代次，仅格式2可复用。严格读取本项目自身格式1并保留代次及实际使用保护；旧缓存经正常LRU/确认计划清理，不能冒充新代次或误删仍在读取的字节。未知/未来登记保留并拒绝安全操作。
- Windows低内存观察使用kernel32 Create/QueryMemoryResourceNotification，非阻塞读取与两秒候选轮询，保留Flutter binding事件；压力只降低本会话后续FIFO像素预算/并发，不撤销已运行许可。观察故障写固定诊断，不产生假压力；停止定时器和观察后句柄关闭失败保留重试，不阻断已结束观察之外的实际图库IO收尾，也不声称句柄释放成功。128MiB压力预算及四端总体额度仍非硬件实测。
- 备份私有暂存只清理已登记、实际关闭且摘要/长度未变的普通文件；先核对整个目录，未知子项/链接/变化或IO不确定保留现场，不递归猜删。已发布文件退出原暂存归属，后来同名文件不能接管。用户导出成功与暂存/资料库保护收尾问题分开反馈。
- 备份与诊断对本库拥有的秘密引用逐项读取注册；返回null同读取失败一样拒绝安全视图，不能略过而产生可能含秘密的导出。故障不清资产/字节/秘密引用，恢复可读后再重试。
- 原图预览读取确认的同一永久版本，持真实文件租约到 isolate 字节读取与摘要校验结束，再释放文件保护；共享像素预算持有到实际 SDK codec/帧收尾。编码缓冲区与 ImageDescriptor 必须晚于 Codec.dispose 释放。显示最多2048px为候选预算，不改永久字节；动画最多当前与待显示帧，暂停不丢已解码帧，关闭等待真实工作。桌面A与M1复用同一入口，主机SDK测试不代表四端设备通过。
- 账号健康只来自当前目标UUID/凭据代次的合法普通确认或明确非unknown失败，不自动试上传。account_health_started_v1/ 与 account_health_observation_v1/ 在既有LibraryMetadata保存严格格式1，开始标记与尝试/租约同事务，按writer开始顺序而非UTC排序；任务历史清理不清标记。旧尝试、旧代次、已移除或待凭据目标不改新观察。展示事件与accountChanges隔离，不撤销正在执行的授权；有效会话尚无结果时显示未验证，重开无会话凭据仍未配置。合并保留本机标记、可携带包排除、替换关联事务清理、私有回滚保留。畸形/未来观察原样保留并拒绝安全打开/写入。
- Windows导入来源预检只查询普通本地驱动路径的元信息，拒绝网络/设备路径及reparse祖先查询；GetFileAttributesW的OFFLINE或RECALL_ON_DATA_ACCESS为明确待获取，不能把0x40000的EA当作RECALL_ON_OPEN。明确待获取时不开数据流，逐项反馈cloudPending；未知仍按实际读取反馈，不声称覆盖所有阻塞云来源或其他三端原生取得器。

- 远端删除与本地移除独立确认。Catbox仅同目标UUID的当前账号授权、严格单文件标识及精确普通直链，固定multipart POST deletefiles；不以普通URL充当秘密，不向ImgBB管理链接猜测请求。当前公开协议缺可靠删除确认，所有派发后结果均unknown，不以200/410或空正文表示删除成功，不自动重试/重开派发。真实fetch、multipart输入和原始响应必须收尾，不能用取消状态提前释放保护。
- 删除审计使用既有LibraryMetadata的remote_delete_v1/UUID严格格式1，仅UUID/普通字段摘要/目标代次/分类/时间/安全HTTP状态；不写秘密、秘密引用、URL或响应正文。请求前持久sending并使旧可访问观察过期，保留lastAccessible及普通结果/文件/秘密/任务。prepared重开为notSent、sending为unknown，畸形/未来原样保留并拒绝打开。关闭与恢复在writer门外等待实际网络；无法确认保留保护。合并保留审计，可携带包排除，替换同事务清旧审计且失败回滚保留。

- 采用已选 Flutter stable 配套 Dart、官方 `material_ui`、非生成 Riverpod、go_router、Drift NativeDatabase + sqlite3 build hooks、image/isolate、file_selector/image_picker、path_provider/path、crypto SHA-256、uuid、clock。按实际调用分期加入其余已选依赖，不重新框架选型，不植入 V2 SDK。
- SDK 精确版本及依赖解析结果见 `docs/environment.md`、`app/pubspec.lock`；不得伪造锁文件或手写生成数据库代码。
- `domain` 表达独立资产、版本、副本与结果；`application` 协调意图和批次；`data` 管理 Drift 与文件提交；`platform` 只适配目录、资源取得和系统能力；UI 不直接改数据库或删文件。
- 永久字节在 Application Support 的全新 `imagehost_library_v1/` 命名空间，`originals/`、`staging/`、`cache/` 分开。外部原图只读，来源授权不作为副本可用的前提。
- 数据库外键开启、WAL、synchronous=FULL，并验证实际值。唯一写入协调者串行执行，跨资源采用持久操作日志、暂存校验、同卷发布、关联事务和幂等恢复。仅最终提交后报已保存。
- 稳定 UUID 分离资产、内容版本、设备副本、操作身份；去重基于真实 SHA-256 和字节数，保留已有整理和历史。回收重复须提示恢复，不自动复活。
- 未加载、加载失败、损坏或未来格式不能以空默认覆盖已有库；失败保留最后有效状态。管理文件路径不得越界、跟随符号链接或删除外部来源。只回收有操作日志依据的半成品。
- 预览/缩略图可再生，不能作为原图；检查缺失/损坏并明确反馈。像素工作在 isolate，预算是候选值，不能标为四端实测。
- 无网络遥测或自动外发。凭据与删除秘密未来仅进入系统受保护存储，普通数据不保存秘密。图床响应、任务和 UI 分离；用户未授权不做真实上传测试。
- 账号配置使用 schema 4 的 ProviderTargets/CredentialOperations，稳定 UUID 与重复别名独立，删除先阻止派发再以日志清理秘密并核对。更新使用新引用，确认安全写入后关联，旧引用删除失败可重试。配置不等于健康，没有验证端点不能试上传验证。
- SecretStore 是纯 Dart 接口，SystemSecretStore 放 platform/ 并由生产 provider 注入；无系统后端时拒绝凭据操作，不采用明文后备。明确会话凭据仅在内存，关闭清空；替换已保存凭据后不能在重开复活旧密钥。
- flutter_secure_storage 11.2 使用新 imagehost.credentials.v1 命名空间、UUID 引用、逐项操作与写删读回确认。Android storageNamespace/resetOnError=false/禁迁移配合旧新备份及设备迁移排除三项 sharedpref；Apple synchronizable=false、unlocked_this_device；macOS 独立 legacy Keychain。用户于 2026-10-05 授权补装现有 VS 2022 Build Tools 的 ATL；已安装成功，Windows 原生合成凭据写/重开/删流程通过。Android 与 Apple 主机/模拟器新增安全存储结果见对应完成记录及 `docs/github-publication.md`；Apple 的同进程新实例读取不等于跨进程重开或物理设备验收。
- SecretRedactor 注册真实值后再产生普通显示/事件，历史注册值持续遮蔽。未知异常或对象不调用 toString 兜底；当前账号别名和安全接口已接线，不能声称未来网络/诊断/备份等全部出口已脱敏。
- HTML 只参考布局，严禁复制模拟内存模型、固定样本、假处理/假网络/假成功逻辑到生产应用。
- 名称搜索与收藏筛选在数据库分页前执行；同一查询用于计数、分页和全部匹配 UUID。选择集按 UUID 保留，筛选不自动增选；查询变化拒绝旧分页结果，总数变化重新取得首批。未实现的处理、上传和成功链接筛选必须禁用或明确未接入。
- 图库远程条件按当前永久版本 SHA-256+字节数关联普通确认、当前发布或恢复终态历史；目标 UUID/服务/输入/状态/远程关键词须来自同项记录。最近确认上传使用普通结果真实 MAX UTC，无确认升降序均末尾，最终资产 UUID 升序。恢复历史不成为可执行意图，unknown 非终态不进入可携带历史。
- 图库、历史目标选项随本机上传/账号事件刷新，不创建网络 actor。新秘密注册后先遮蔽远程及导入历史快照再 SQL 查询，已知秘密搜索拒绝命中而不改本机整理原值；片段与审计行身份/批次/位置须一致。共同筛选入口复用桌面/M1，搜索 debounce 草稿保留、明确清空同步。
- 标签/分类使用共同 TextPolicy：提交时 trim、Unicode 17 NFC、默认完整 C/F case folding、再次 NFC；名称按 Unicode scalar 计 1–64，单资产最多 50 个去重标签。编辑草稿不即时截断或吞分隔符；批量整理须先验证所有对象和限额，再一笔元信息事务写入。
- 新项目自身 schema 1→2 升级保留资产/版本/副本身份，将分类名称迁为 UUID；不涉及旧应用兼容。text_policy 标识与固定 Unicode 数据可校验，未来版本或失败升级不能重置资料库。
- 回收 30 天到期只提示。清记录与清永久字节分别确认；仅清记录保留独立版本与字节，再导入须创建新资产并复用/修复内容。共享引用、持久依赖及文件使用租约必须阻止不安全清除和副本路径替换。
- 文件使用租约释放必须晚于实际 IO 结束，取消状态不等于工作线程结束；资料库关闭先排空租约取得，再等待租约释放，等待期间不占据写入协调门。重开拿到排他锁后可清除前进程临时租约，不能清除持久保护引用。
- 租约释放的数据库清理失败时保留保护记录并反馈失败，但必须在 finally 排空已结束 IO 的进程内等待，避免退出死锁。不得提前释放仍在实际读写的保护。
- ImageProcessor 是共享 isolate 像素引擎；ProcessingCoordinator 持有输入租约到实际线程退出。schema 3 保存 writing/prepared/ready/failed/cancelled/deleting 输出、独立文件、来源及参数快照。默认 24 小时，可选 1 小时/7 天；启动和可运行期间每分钟尝试仅清到期且无保护的结果，失败保留记录重试。
- 永久保存复用原导入日志与事务，并在同一关联提交中保留 SavedOutputOrigins；其生命周期独立于临时结果。导出由共同流式复制/关闭/摘要校验服务完成，桌面选择目录，同名独占创建新名称，不覆盖旧文件。Android已接Pigeon SAF单文件/目录及MediaStore照片保存；iOS已接Pigeon Files目录独占复制与Photos addOnly，必须取得实际保存确认，不以分享、授权或URI生成冒充保存。系统宿主缺失或结果不确定仍拒绝成功，原生验证边界见里程碑29。
- 桌面与 M1 工具入口复用 ProcessingWorkbench；系统退出只有当前可见工作页监听，取消等待 actual IO 后才释放租约/关闭库。动画裁剪缩略图必须来自确认的同一帧，不能用第 0 帧冒充其他帧。
- Catbox/ImgBB 适配器采用已选 Dio 5.11.1，固定 HTTPS 接口、禁重定向/日志、按需 multipart、新尝试新流、响应原始源流限 64 KiB。适配器不重试、不写历史、不把取消完成等同于网络刚返回；等待真实 fetch、输入及响应流收尾。有效远端确认与取消意图分开，后续队列须保留独立晚到证据。
- 默认服务精确字节/格式限制未知时拒绝派发；测试注入限制不是服务契约证据。秘密管理链接只放运行时受保护包装，尚未接入持久结果时不得落到普通 SQL/UI/日志。畸形成功、发送后无确认及 5xx 保留 unknown，不猜测自动重传安全。
- TimeSource 分离 clock UTC 与 Stopwatch 单调时间。QueuePolicy 遵循需求九状态、六聚合和五计数；重试最多初次加三次，2/4/8 秒且不剪短 Retry-After，结果未知/无可靠副作用证据不自动重传。UploadCoordinator 独立有界调度，只累计实际执行及增加的字节活动；暂停/离线/退避排除，120 秒无活动和 30 分钟累计由实际计时器与持久检查点执行。检查点测试不能冒充硬件强退计时精度证明。
- schema 5 的批次/发布项/尝试/结果/管理秘密意图/事件分别持久化；创建意图 UUID 幂等，输入、目标和策略冻结，派发前重新解析当前凭据并校验文件。原图必须明确隐私确认，不自动替代失败输出。任务持久引用与实际执行租约分别保护来源，关闭先等真实网络及文件 IO 收尾。
- 结果按尝试 UUID 唯一关联；取消终态不被晚到成功覆盖，完整确认以独立结果保存。管理链接只经日志中的新 UUID 引用和 SHA-256 校验提交到 SecretStore，普通 SQL 不保存秘密。新秘密注册后事务遮蔽本库历史展示快照，重开逐项读取本库引用注册，不枚举其他凭据。
- 上传页在桌面与 M1 复用；进入页面或入队不授予网络权限，用户明确允许仅本次会话网络上传。默认能力未知时只入队等待。系统网络类型观察和按类型派发、上传前自动处理依赖已接入；远端删除的软件行为按上述独立确认/派发后unknown审计规则执行，可靠服务确认仍缺证。实机网络切换PT及真实图床联调仍须独立补证，不据受控测试开启未知服务能力。

- 完成历史清理只针对明确选择的本机 succeeded/failed/cancelled 和恢复终态审计；unknown 及其余活动状态、未结束尝试、实际输入租约、残留任务引用和结果管理日志均保留。计划绑定 owner/epoch、全部选择指纹，确认后同门同事务重验，不增清后来完成项。普通结果/秘密/资产/字节不删除；空 UploadBatches 保留 intentId 幂等账本，仅页面隐藏空批次。本机与恢复历史分命名空间，不按恢复的 attempt UUID 删除本机记录。

- 备份采用自有 formatVersion 2 的白名单 Manifest，严格读取本项目自身 formatVersion 1；这不涉及旧应用数据。使用 archive 4.3.0 文件流 STORE ZIP/ZIP64。所有永久版本（含回收和仅清记录后独立字节）进入完整备份；元数据包无图片字节。格式名称保留领域的 PNG/JPEG/WebP/GIF/BMP，仅包内后缀小写。不直接复制活跃 SQLite，不导出来源路径、秘密引用、临时输出或活动意图。
- 备份在同一写入协调器/事务取得已提交关系及副本租约，再离开协调门校验摘要与真实像素。所有本库拥有的凭据/管理秘密须先注册脱敏，无法确认安全视图时拒绝导出；结构身份或参数与秘密冲突时失败，不改身份。缺损永久副本列 UUID 并拒绝完整成功，只有用户明确选择才改用元数据。
- ZIP 写入在 isolate 中使用有界文件流；预读及实际写出分别核对 SHA/字节，输出关闭并 flush 后才发布。取消哈希可按块，同步编码须等当前条目真实完成；等整个工作结束才释放租约。Windows 已接入 GetDiskFreeSpaceExW 和无 REPLACE/COPY 标记的 MoveFileExW，私有同卷暂存经独占原子发布，绝不以 File.rename 的覆盖行为代替该契约。
- 恢复预检只操作新私有暂存；原始 ZIP/ZIP64 目录保留重名证据，检查中央/本地一致、范围连续、STORE、CRC/SHA/像素、数量/实际大小预算及可用空间，不调用会吞重复条目的通用解码/自动解压。预检成功不是已恢复；默认合并经确认后用持久恢复日志、独占永久副本发布与一笔元信息事务提交。替换先验证当前快照实际可重建，再独立确认风险；保持备份资产/版本身份并创建新本机副本，元数据替换不沿用旧字节。预算为候选值；Windows大于4GiB实包软件流程见docs/validation/release-large-backup-result.json，其他三端大包及硬件容量压力仍未验证。
- BackupMergePlanner 仅输出四类永久元信息的纯合并提议及身份映射，按内容复用、保留当前回收/非空整理。同内容描述矛盾及 BAK-004/LIB-003 标签并集超 50 均阻止提交，不截断成功。BackupResultMergePlanner 接收已经完成身份重映射的普通确认，按结果/尝试身份去重；同 URL 不去重，冲突关联保留当前值并汇报。
- UploadRestoreHold 立即禁止新派发、持久暂停当前任务批次，等待派发准备、实际尝试与结果提交/租约释放结束后才返回。收尾不能确认时继续阻止派发；释放不自动恢复批次或网络授权。这只是上传侧维护屏障，不能代替整个资料库写入保护、实际恢复提交或库执行代次隔离。
- 内部 ReplacementSnapshot 仅放私有 staging/replacement-UUID；VACUUM INTO 后验证当前 librarySchemaVersion（schema 10）的全部 28 表、结构/关系及字节摘要，保留当前真实关系、秘密引用及登记永久/输出/.part 字节，missing 明确记录。它不是可携带备份，不导出、不新增凭据值；可能保留本机原始显示内容。目录归属 unclaimed/owned 持久确认，未归属目录或未知子文件绝不猜测删除。启动先处理有替换关联的恢复/清理，再清未使用快照；实际回滚见替换日志约定。
- 合并 prepare/commit 与内部快照共用实际维护 drain，已有恢复日志阻止交错。LibraryUploadQueueStore 固定创建时 executionEpoch，每次调用和 writer gate 再核对，确认另校验 UploadExecution.libraryEpoch；关闭/重开使旧对象失效。替换关联事务确认后切换会话、清除会话凭据并关闭旧上传 actor；保护释放后重置图库查询、UUID 选择及账号/任务缓存，备份页面退出也不能漏掉存活页面。
- 替换日志分 replace-writing/rollback/committed/cleaned；启动先处理替换日志，再运行处理输出到期、凭据和队列维护。提交前失败用只读 ATTACH 快照在当前库单事务恢复全关系；局部 sqlite3 uri:true 连接在已有 writer/drain 内使用，保持 Drift 主配置不变。提交后只清理已确认无引用且摘要一致的旧文件/秘密；清理失败保留新库与证据重试，cleaned 标记允许快照删除中断后继续。未知文件、篡改、未确认发布归属保留现场并阻止不安全读写，不猜测删除。
- schema 6 的 RestoredOutputOrigins/ImportedUploadHistories 保存无设备路径的来源和不可执行终态历史；RestoreOperations 保存文件/元信息提交证据。新账号禁用且不恢复秘密，普通结果不恢复管理能力；活动尝试及本机临时输出身份冲突不能把备份证据误挂当前执行对象。
- LibraryRestoreHold 同步拒绝新普通读写，先排空已接受调用，再在写入门外等待实际租约释放；收尾完成前允许必要 finalizer，维护就绪后只有持有本库保护的恢复私有入口可写。持久保护仍阻止坏副本替换；释放不自动恢复上传。资料库关闭等待实际恢复文件 IO 及日志清理，不提前释放管理根锁。
- 完整恢复重新复制、摘要/字节/像素校验并以当前平台独占发布服务写入新 originals UUID 位置；元数据仅创建 missing 副本，不删除或修复已有字节。提交前取消/失败回滚元信息并按证据清半成品，提交后迟到取消保留成功。全部日志位置先验证再清理，发布归属不确定保留现场，不猜测删除。去敏当前快照不允许改写已有本机名称、分类、标签、账号或时间来源。

- 链接集合以真实普通确认结果为准，SQL 名称/普通 URL/冻结历史目标关键词先脱敏再 Unicode 折叠，与稳定目标 UUID、服务、输入类型取交集后分页和计数；排序同值以结果 UUID 收尾。已移除账号不改历史身份，同名新账号不能替代。
- LinkCopyPlan 由仓储绑定 owner/epoch 和普通字段摘要。当前已展示列表顺序与资产当前永久版本/用户目标顺序分别确认；不增选未加载、筛选外或其他处理版本。逐项换行、完全相同格式去重、缺失明确跳过，执行前重验计划；重试只调用本地系统能力。
- Flutter Clipboard 的 OptionalMethodChannel 会吞缺后端错误，平台适配用同一 flutter/platform JSON 协议的严格通道；share_plus 13.3.1 只分享普通文本，明确取消/未确认/不支持/失败，不将系统返回成功冒充接收方已保存。其他端配置不等于已实测。
- 本地移除普通结果与远端删除分开：先确认，用 UploadResultOperations 的严格 typed action 在同一事务保留清理证据、解除 publication.resultId 并删普通记录；系统管理秘密先核对摘要及所有者引用再删并读回。失败保留日志重开重试，不删资产/字节/历史/远端；未完成结果管理操作仍阻止恢复维护。
- LNK-004 主动检测仅在明确范围网络确认后执行，打开/查询/重开不创建请求。使用独立 Dio HEAD、固定 HTTPS files.catbox.moe/i.ibb.co，无账号凭据、重定向、GET 回退、重试或定期访问；200 image/* 空响应体为当时可访问，410 空响应体为服务报告不再提供，404/离线/其他失败为未知。任何检测不删除普通结果、秘密、历史或图片，Catbox 匿名不能显示为应用保证永久。
- schema 7 仅在普通结果增加六项本机观察列，26 表不变。计划绑定 owner/epoch/完整普通字段指纹，开始先持久 unknown/interrupted，generation 拒绝迟到旧结果覆盖；lastAccessible 保留上次有效证据。退出和恢复维护先在写入门外等待实际 fetch/原始流收尾；无法确认时保留 IO 保护并拒绝安全退出/恢复，不用取消状态冒充结束。
- 可携带备份 formatVersion 2 白名单不携带本机检测观察，恢复普通结果从 recorded 开始；私有替换快照与回滚保留当前完整观察。新项目自身 schema 1–7 升级至 8；schema 6/7 有任何恢复日志时在修改前拒绝升级，须用兼容版本先完成恢复，避免破坏旧私有快照/回滚证据。未来版本、失败升级不重置库。20 秒/1 KiB 为候选防护预算，真实服务 CT 和四端性能仍待补证。

- DeviceSettings 在既有 LibraryMetadata 的 device_settings_v1 中严格校验并持久化，不另加 shared_preferences；上传 1–8/默认3，处理 1–4/默认1，有损质量 1–100/默认85，体积优先最长边 1–16384/默认1600。未来格式/损坏拒绝加载且保留原值。SettingsSnapshot 绑定 owner/epoch/设置与目标指纹，默认选择复用 ProviderTargets 标记并同事务写入；凭据待完成目标只允许保持原选择。
- 设置保存后才更新共同运行策略；默认目标变更不能发送撤销在途授权的 accountChanges。新工作台只在首次有效加载应用默认值，已有草稿和输出参数不变。可携带格式2包含严格八项设置和四端可用范围，合并/替换确认列出覆盖值与跳过项，同关联事务提交成功后才更新运行策略。不可用项或自身格式1未含设置时保留本机值；不恢复默认目标选择、凭据、会话许可或冻结任务。准备/日志建立前及提交事务重验当前有效设置，损坏/变化拒绝覆盖；私有快照/失败回滚保留旧设置，替换成功使旧设置快照失效。四端设备互读仍须实测，不据共同模型测试宣称完成全部BAK-005。
- ProcessingScheduler 是仓储共享的 FIFO 候选预算分配器，按每项128MiB折算有效并发；512MiB桌面/256MiB移动总预算尚非实测。排队持有真实输入租约，取消排队只释放自身保护；实际线程、输出收尾、输入释放完成后才释放预算。降低并发不取消运行项，调高也不能挤占旧冻结预算；关闭库先排空实际租约再终止调度器。
- 设置页的编辑分区有稳定身份，加载/错误/反馈槽位固定，防止保存期间销毁 EditableText 生命周期观察者。系统退出等待真实保存与库关闭；不可用/未接入的缓存或网络全局策略不得做假控制。
- schema 8 的 DiagnosticRecords 独立无业务外键，严格白名单事件及实际 UTF-8 大小按30天/10,000,000字节先到清最旧。业务事务完成后写日志，日志故障不能回滚业务；损坏或未来格式保留并拒绝安全读取/导出。私有回滚包含日志，成功替换保留本机日志，可携带包不包含。
- 诊断复用 SecretRedactor，先遮蔽真实秘密再截断，排除完整来源路径、图片、秘密引用、URL查询/片段及原始正文。读取/导出只核对本库秘密引用，不能确认安全视图则拒绝。新秘密注册后持久重新遮蔽；SDK异常只记录固定分类，不调用未知对象 toString 或保存原始堆栈。
- 诊断清理/导出绑定 owner/epoch 和全部已确认行，后来事件不增入；仅当前脱敏引起的变化允许计划继续。任务批次/真实尝试入口复用共同页面。确认取消、退出、替换及 dispose 只处理自有窗口；导出等待实际 IO 结束，已确认用户文件与私有暂存清理问题分别反馈。Android/iOS复用各自原生文件保存；缺宿主或无法确认结果时失败，不用分享冒充保存。

- DeviceSettings 自身格式2增加缓存整数64–2048 MiB/默认256及临时输出1小时/24小时/7天默认保留；当前自身格式3增加网络类型策略。严格读取自身格式1/2并应用新增默认值，不自动改写原记录。已有输出与草稿不改到期/参数；可携带设置使用独立严格格式1 envelope，只接受当前八项完整值和明确平台名单。
- 可再生缩略图在LibraryMetadata的thumbnail_cache_v1/登记UUID、内容/帧及SHA；writing/prepared/published/ready/deleting控制独占暂存及真实发布归属。prepared已存在目标即使同摘要也不接管/删除，暂停新增缓存。持久使用序号控制LRU，保护/未登记/变化文件保留；确认清理绑定owner/epoch及冻结行，后来新增不增清。只统计实际普通文件长度，链接不跟随，诊断内容不重复计入数据库文件。
- 生产注入四平台可用空间与独占发布接口；Windows主机、Android模拟器和Apple主机/模拟器的真实证据分列。32MiB余量/处理估算/Flutter解码缓存为候选预算，未知空间停止相关新增写入；Android StatFs已在API36模拟器验证，私有发布使用NDK renameat2/RENAME_NOREPLACE，硬链接方案在模拟器被errno13拒绝，不用覆盖式rename后备。Apple statfs/link已在Mac主机与iOS Simulator原生用例验证，物理设备及其他文件系统仍待验收。Application Support与恢复证明系统临时根别名先解析再追加本应用命名空间，子项仍禁止链接。
- 图库缩略图使用权等实际读取结束后释放，再以Image.memory显示；处理结果预览也必须取得真实OutputFileLease和共同像素预算，在isolate校验摘要/生成480px单帧PNG。页面销毁/取消只请求停止，实际worker结束后才释放租约和预算，显示内存小图不依赖临时文件继续存在。image第0帧可能包含动画容器，先分离准确帧再编码单帧，不以APNG或错误帧冒充静态预览。

## 操作与验证

- 修改前检查真实实现和当前文件，保护任务外文件。工作区`main`的“首次完成PC端”提交`d642ebc`保留。用户已授权提交推送至`panlijun/ImageHub`公共仓库并运行标准CI，Windows/Android本地正式打包与专用Android签名按2026-10-09持续目标执行；不重写首次历史、不对外发布、不做Apple正式签名发行或另行付费服务开通。其他范围仍未经要求不提交、推送、PR或发布。

- 来源复制用StreamIterator并在等待数据时观察同一CancellationToken；仅取消交付，必须等源订阅实际清理及已开始的writer IO结束再清暂存/日志。PlatformResource取得令牌在来源就绪检查后、打开数据流前重验。清理错误保留writing证据并反馈storage，不冒充取消成功；无法确认内核读取结束继续等待，不用超时提前释放写入门/根锁。Gallery等待期间提示并禁用再次导入，迟到进度不能覆盖停止反馈。
- ProviderUploadLimits支持formatMaximumBytes：大小写归一、冲突拒绝、不可变快照，格式与全局限额取小值；非法额外限额拒绝能力。官方网页配置不等于API服务器精确契约，生产Catbox/ImgBB默认unknown仍不派发；本次官方证据见docs/provider-contract-evidence.md，GIF独立上限与远端删除确认缺证分别保留。

- schema10新增UploadProcessingJobs和发布项processing_job_id；计划冻结完整版本、参数、帧和保留期，不保存设备路径。同批次按有序版本与策略共享像素工作，逐目标发布项保持固定；只在真实输出校验后关联processed输入，待依赖发布不得读取原图派发。失败仅跳过依赖项，暂停项继续时才合法进入失败；来源不可用等待修复后明确重试，禁止原图fallback。
- 本地处理actor与网络actor独立，关闭/维护同步禁止新执行，再等待实际像素线程、输出收尾和租约释放。维护先持久暂停批次；释放维护不恢复暂停或网络许可。启动ready输出可关联原冻结任务，未完成局部像素工作按原计划重执行，全部依赖已取消的日志退休并回收任务引用。取消终态但实际处理仍活跃时不能清历史或导出完成审计。
- 新项目自身1–9可升级至10；6–9存在恢复日志时修改前拒绝。私有快照/回滚包含28表；可携带formatVersion2保持白名单，不携带处理job、执行参数、活动意图或路径。终态失败/取消的摘要只是历史，不是已上传原图证据。完整平台和真实服务验收见docs/milestone-22-upload-processing.md。

- schema9 的 UploadPublications.user_paused 与整批暂停独立持久。仅 queued/waiting/paused/interrupted 可单项暂停/继续，running/unknown/终态拒绝且不取消实际请求；整批继续不清独立标记，整批仍暂停时单项继续仅解除本项意图。重复意图幂等，等待/重试期限与冻结输入保持，调度与写入门都核对。自身1–8升级至9，6/7/8有恢复日志时改动前拒绝；私有快照/回滚包含新列，可携带备份不携带活动控制。

- 用户已授权安装全 Windows 用户环境可用的 Flutter SDK（通用目录及用户 PATH）并获取本项目依赖；本轮Android工具安装范围见开头用户决定。该范围之外的软件、大型额外下载、签名、外部资源开通仍先征得同意。
- 在 `app/` 运行：`flutter pub get`；数据库生成 `dart run build_runner build`；格式 `dart format lib test integration_test`；检查 `flutter analyze`；测试 `flutter test`；Windows 构建 `flutter build windows --release`。
- 资源包完整性：工作区根目录 `node imagehost-new-project-kit/verify-kit.mjs`。此检查不是软件测试。
- Apple CI 在 `.github/workflows/apple.yml` 使用标准 `macos-26` arm64 runner、官方固定 SDK/SHA-256 与 `flutter pub get --enforce-lockfile`，无长期缓存或收费大型 runner。完整软件测试与真实 Apple engine 原生 smoke 分开，iOS 只用预装模拟器、不下载额外运行时，不签名发行。工作流存在不能记通过，远端证据见 `docs/github-publication.md`。系统临时根先解析别名，再创建自有目录；不放宽管理子项的符号链接保护。
- iOS CI通过完整标识显式固定已安装的iOS26.2运行时及iPhone17类型，缺失/不可用/不兼容拒绝，不按最新版本自动换目标、不下载。此选择有前轮真实simctl登记依据，健康仍须当轮验证。每轮create自有UUID，RUNNER_TEMP登记严格run/attempt/name/runtime/type所有权。bootstatus两流的明确迁移失败拒绝本次就绪；仅首次明确迁移失败允许核对本轮所有权、关闭并读回Shutdown后重启同一UUID一次，每次bootstatus最多180秒，第二次失败或未知错误立即停止。最终Booted与真实SpringBoard正PID仍不是应用测试通过。原VM发现与console-pty路径及失败证据保留为历史；当前run_ios_xctest_integration.py正常构建固定Dart入口、核验版本，在owned设备以全新derivedData编译XCTest宿主，由官方同进程plugin/runner交付精确四用例及四回调。真实host/reader关闭、XCTest一项零失败零跳过、实际签名证据与owned app收尾均须确认；备份还须真实闭合证据读回。构建与Xcode分别单调有界，步骤外层25分钟，控制检查、PID或完成标记不能代替实际用例通过。关闭/删除前重核自有身份，删除后读回缺席才退休marker，未知保留，不使用all/booted/unavailable擦除或清理别的设备。artifact以SHA+run_attempt命名，保留原失败/取消证据。
- 第七轮iOS26.2真实bootstatus已完成迁移及System App启动，随后默认60秒的设备状态读取超时。仅启动后的该次状态查询改为120秒；仍须核对本轮所有权、Booted与30秒SpringBoard正PID，任一超时或未知继续拒绝，不能把系统启动完成记为应用原生用例通过。
- Flutter 测试后构建 Release 使用正常 `flutter build` 入口，让 SDK 按实际模式重新生成插件注册器；`--no-pub` 会跳过该步骤，不能沿用含开发插件的登记文件。禁止手改生成注册器或删除必要测试依赖来消除构建失败。Android 新相册保存目录采用 `Pictures/ImageHub`，先前导出文件不迁移、不删除。
- 独立进程验证工具清理自有目录前必须确认所有自建锁进程实际退出；异常也请求关闭并等待，无法确认则保留目录。不因断言/超时提前删除仍在使用的文件。
- 测试依据 `imagehost-new-project-kit/documents/unit-test-design.md`，用例名称保留 UT/IT 编号及覆盖边界；实际结果单列 UT、IT、widget、构建、PT/AT。未执行、部分覆盖、缺环境必须直说。
- 文件提交与正常重启用真实临时数据库及文件验证；故障注入不冒充硬件断电或实机强制退出。一个平台通过不能替代其他平台验证。不存在测试时不得报告通过。
- 子代理遵循用户 Sol/Luna 分工，显式模型 ID 和 high；任务写入范围不重叠，子代理不得继续委派。主线程必须阅读实际变更并完成验收。
- 同一个 app/ 下 Flutter test、Windows 集成测试、build 及涉及 native assets 的 Dart run 串行执行，避免 Windows SQLite DLL 锁冲突。widget 测试须交替排空原生 IO 与 fake zone，不能将卡住的测试包装成通过。
- Android工具环境在app/中点载 `. ./tool/android_environment.ps1`；只设置本进程，JDK、SDK、Gradle/AVD缓存均在D盘，复用C盘Flutter。Pigeon生成 `dart run pigeon --input pigeons/android_files.dart` 后执行Dart格式化。Android源码边界与选型8.1的具体差异见 `docs/android-native-files.md`，不改资源包。
- Android图片/文件/ZIP取得走原生有界SAF桥，不走插件的预先整批缓存。私有AtomicFile只保存来源URI和授权恢复证据，不进入业务SQL/诊断/备份；Dart只持UUID句柄，未开始选择可提示恢复，consumed来源不重新打开。取消及未读取项release等待实际IO/授权退休，关闭不确定保留登记；Activity旧实例仍在工作时新实例不能接管。
- Android导出只写应用私有闭合源和本次创建的外部目标，真实关闭/读回摘要确认后才报告content URI及名称。媒体先pending后发布，未知不冒充成功；迟到saved独立保留。JNI路径以普通UTF-8字节传递，NDK按ABI选择系统调用，不依赖API30才有的renameat2公共wrapper。不支持的内核/文件系统拒绝发布，不降级为覆盖或复制。
- MobileFileWorkspace只清登记、实际关闭、长度/摘要未变的普通文件；备份先得到真实闭合ZIP，系统确认保存后才显示用户备份成功。Android与Apple备份来源共用复制与归属保护，复制后须等原生所有授权release完成才交付，归属/关闭不确定保留现场。M1直接刷新按钮捕获固定反馈，受跟踪整理/回收操作仍接收刷新失败，保留最后有效列表。

