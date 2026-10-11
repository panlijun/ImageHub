# 本轮软件开发与设备验收拆分

本文件记录验收范围的最新决定；资源包与正式需求原文、旧里程碑结论保留。旧记录描述其形成时的范围，不据此覆盖后续用户决定。未执行的项不计通过，不以模拟替代。

## 2026-10-09 最新范围

Windows 软件完成基线已记录；用户随后要求持续推进 Android 软件开发至完成，并同意在 D 盘安装 JDK、SDK、NDK、模拟器/系统镜像及 Gradle 依赖，复用 C 盘 Flutter，不改系统 PATH。当前 Android 软件实现与适用验证已完成，结果见 `milestone-28-android-completion.md`。真实账号图床联调、物理设备 PT、真实硬件性能及断电验收仍不作为本轮开发阻断，且均不计通过。排除联调或设备验收不会取消已授权的软件检查、代码审查和生产安全守卫。

Catbox 匿名上传已从产品范围移除，覆盖 ACC-001/ACC-002/ACC-004 中匿名账号的原目标。产品仅支持 Catbox userhash 账号和 ImgBB APIKey。新建或编辑账号、默认目标选择、新入队任务、派发授权及图床适配器都必须拒绝匿名身份；本项目已有匿名身份仅供普通历史和备份读取，不删除数据、不转换 UUID，也不得重新启用。资源包原件保持不变。

真实 Catbox/ImgBB 上传、删除和探测均未获授权，本轮不得发出这些真实服务请求。精确 API 大小与格式契约仍未知，生产能力守卫继续执行，未知能力不能派发；合成凭据、受控 HTTP 和五张合成图都不能证明真实服务通过。此前准备的五张合成图从未发送。过时的 `app/tool/verify_catbox_synthetic.dart` 已移除。

Windows 当前已接入的业务覆盖真实本地导入与持久图库、处理/永久保存/桌面导出、账号安全存储与健康观察、账号停用和移除影响确认、持久上传队列及处理依赖、网络类型派发策略、普通链接本地能力、明确主动检测、独立远端删除审计、备份合并与替换、诊断、设置及空间缓存管理。此清单描述当前软件范围，不是最终验收结论；本轮运行结果与未完成项另记于 `milestone-27-windows-completion.md`。

M1 已选定为手机方向，不再比较 M2。Android 已接真实有界 SAF 图片/文件/ZIP 取得、文件/目录导出、MediaStore 相册保存及备份/诊断接线；API36 x86_64 模拟器已验证原生子流程和正常 Release 应用。ARM64 与 x86_64 APK 均实际构建，ARM64 物理手机和最低 API29 尚未验证。用户已授权公开 `panlijun/ImageHub` 并运行标准 Apple CI。2026-10-09已完成iOS原生图片/文件/备份/诊断保存和Apple备份文件取得：源9715ce9的run37879708343整体success，Mac1424软件测试/4跳过、独立进程恢复/锁、四项Flutter原生、23项XCTest和Release通过；iOS26.2/iPhone17四项Flutter原生、20项XCTest（含真实Photos PNG事务）、正常入口Simulator Debug和自有设备清理通过。原始证据、软件与设备边界见[里程碑29](milestone-29-apple-files.md)和[GitHub记录](github-publication.md)，不以核心用例、构建或受控窗口协议代替全部设备验收。

2026-10-09本地正式包已完成：Windows完整34条目x64 Release ZIP与Android专用非debug/V2签名ARM64 APK实际生成并核验，内核/四端平台版本均为0.1.0+1；receipt记录源base `cfd55d0`且`dirty=true`，当时仅两张既有验证截图未提交。见[里程碑30](milestone-30-versioned-delivery.md)及两份formal receipt。它们不是公开二进制、商店发布、Apple正式签名发行或ARM64实机通过。Windows软件1459项通过/1平台分支跳过、M1快捷入口20项、五项Windows原生、正常Release启动退出及真实4,328,697,800字节ZIP64预检/合并/重开通过。Windows、Android、Mac互读方向及随后补齐的四来源软件矩阵现有12方向/24模式的完整/元数据恢复重开证据；四台设备人工互读/PT仍未验收。Photos完整读写授权与五格式资源独立读回仍是软件CI缺口；第十一轮已在Apple runner实际编译并运行SDK helper，但真实请求等待30秒无callback。Apple生产原生文件保存与备份取得已接入。

第六轮[Apple CI](validation/release-apple-sixth-ci.json)源`5326d527962daad1de23f3340dda40b55aec6e78`/run`37929517038`为历史结果：当时整体failure且停止阶段原因未暴露；不能由第七轮反推其根因。详见[第六轮记录](validation/release-apple-sixth-ci.json)。

第八轮[Apple CI](validation/release-apple-eighth-ci.json)源ca7877a379cce83616b53e730b5c2a28487dd319/run37938849959整体failure。Mac 1456软件测试通过/4平台跳过、94项本机控制、八项进程边界、四项Flutter原生、Windows/Android来源完整/元数据/重开、23项XCTest零失败零跳过、Release64.5MB及版本核验通过。iOS native与backup各四项命名Dart业务、四项SDK回调、一项XCTest、ad-hoc实际签名及owned app stop通过，native另有真实Keychain流程通过；backup三外部来源完整/元数据重开与八项设置通过；正常入口模拟器构建/版本与Photos addOnly一项通过。Full Photos 27唯一终态用例21通过/6失败，Xcode exit65；五格式read-write授权notDetermined(0)而预期3，未验证保存资源独立读回；invalidImageSource非空导致断言失败。底层授权机制未知，闭合日志有27条唯一终态用例行而无full XCTest JSON摘要；11条failure records不是11个失败用例。134项本机控制检查不是Apple原生修正通过。第八轮产物大小/SHA、受限证据和当时新互读详见[第八轮记录](validation/release-apple-eighth-ci.json)、[134项控制日志](validation/release-photos-controller-controls-01.log)和[里程碑30](milestone-30-versioned-delivery.md)。该轮四来源矩阵为11方向/22模式：Windows、Android既有已完成结果保留，新增iOS→Windows和iOS→Android的双模式恢复重开/8项设置通过，第八轮当时仅iOS→Mac一方向/两模式待补。Python prepare/test-without-building已通过本机控制验证，Swift像素解码断言与权限诊断已审查，均尚待Apple原生验证，第八轮记录时下一轮CI尚待实际执行。第七轮及更早失败细节保留，历史20项XCTest全绿不等于第八轮27项全绿。其余三端>4GiB大包、最低系统、物理设备PT/PERF/断电、真实服务和硬件压力仍待验证；DPAPI CurrentUser与离线可移植密钥备份限制、正式包与dirty源边界保持原记录。

M1当前已有详情页原图预览、编辑和上传快捷入口，批量整理可新增标签。现有类别筛选与链接底栏/所选项复制链接承接原需求；没有独立类别抽屉或专用添加标签、原图预览导出、详情查看链接按钮的独立要求，本轮不将其列成缺口或完成项。

范围分为三类：物理设备 PT/真实硬件性能/断电排除且不计通过；真实账号服务联调未授权且不计通过；生产守卫、Windows 主机、已授权 Android 模拟器和 Apple CI 的软件验证仍执行。Windows/Android 完成记录及 GitHub/Apple 验证记录分别承载实际运行数字和状态，模拟器结果不升级为物理设备验收，Apple 核心检查通过不表示全部平台业务接入完成。

## 本轮排除的设备验收

| 设计编号 | 需要设备或真实系统操作的部分 |
| --- | --- |
| PT-001 | 照片/文件选择器、部分授权与撤回、真实云占位照片下载、Android取得器进程丢失恢复 |
| PT-002 | Wi-Fi/有线/移动/离线实际切换、后台/锁屏、系统挂起或杀进程。没有网络计费检测 |
| PT-003 | 原生目录选择、实际剪贴板/分享接收方、系统拒绝和取消，以及移动原生保存验证 |
| PT-004 | 真实鼠标/键盘/触控/输入法、不同DPI与屏幕阅读器。软件语义及布局检查仍保留 |
| PT-005 | 四台设备备份互读、实际安装及最低系统版本兼容性。共同包格式及位置重建测试仍保留 |
| PT-006 | 系统秘密存储强度、卸载/重装/清数据后的平台保留行为。已记录Windows合成凭据证据保持原范围 |
| PT-007 | 设备负载、系统资源压力、硬件断电与真正系统强退后的恢复 |
| PERF-001–004 | 参考设备的响应分布、冷启动、峰值内存/吞吐及硬件故障恢复成本。算法、计数、预算和持久恢复正确性仍测试 |
| IT/AT 的设备部分 | 上述权限、系统能力、硬件故障、四端人工闭环及真实中文可理解性验收；不会整组抹掉可自动验证的IT/AT子场景 |

## 仍执行的软件工作

- UT及可在现有Windows主机自动运行的真实SQL、临时文件、摘要、像素/SDK解码、widget和本项目新格式恢复测试；故障注入仍只声称该边界。
- CT-004编解码本机子契约、CT-006 ZIP/ZIP64与Manifest版本契约；REV-001–003来源、权限/外发/留存、范围追踪审查。
- 全 app 分析、格式、软件回归，Android APK 构建与模拟器原生/正常入口验证；受影响的 Windows 原生子流程及 Release 回归。Android 工具安装已授权并完成；Apple 使用已授权标准 CI 的真实 Mac/Xcode，按真实运行记录验证，不要求本机 Windows 安装 Apple 工具。
- 真正未接入的生产功能继续列为软件缺口，不能因其最终需要PT而删掉开发任务。

## 真实服务单列

CT-001/002/003/005及IT-008的真实Catbox/ImgBB能力、响应、上传/删除和探测联调属于外部服务证据，并非实机排除。没有授权不发真实请求，未知精确能力仍不能开启派发。受控HTTP测试不冒充服务确认；不得把200或空正文当作远端删除成功。

## 本轮核对出的实际代码工作

| 编号 | 核对后的软件范围 |
| --- | --- |
| IMG-004、LIB-001 | 补共用永久副本预览、SDK逐帧动画播放/暂停、有限循环和关闭等待；桌面A/M1接线 |
| SEC-006 | 设置中的永久/缓存/临时/诊断/凭据留存说明，以及真实备份入口，保留未保存草稿 |
| ACC-003 | 合法普通确认或明确失败更新同目标/凭据代次的观察；旧尝试不覆盖新证据，展示事件不撤销执行授权 |
| BAK-004 | 保留50标签上限与拒绝事务，提供双方对象/数量及取消、整理、重导出指引 |
| IMP-001/007 | 明确Windows尚需召回的来源不打开数据流，逐项反馈云资源待获取，其余已取得项继续；未知来源不猜分类 |
| PLT-004 | 桌面多选卡片读出选择动作和selected状态；选帧缩略图重试重读实际选帧 |

## 2026-10-11 第九轮 Apple CI 与四来源矩阵

第九轮[Apple CI](validation/release-apple-ninth-ci.json)源`09b849de824c38a9dbe714ce1e4c390f1f871c65`/run`38137413108`/attempt 1整体failure。Mac job通过134项本机控制、1,456软件/4 Windows平台跳过、4项Flutter原生、8项进程边界、23项XCTest零失败零跳过、Release64.5MB及独立版本；备份4个命名业务（本机导出和三个外部来源），自身来源跳过1不计业务。iOS→macOS完整/元数据恢复、关闭重开和8项设置通过。iOS native与backup各4项Dart业务/4项callback/1项XCTest通过，ad-hoc签名、owned stop、native真实Keychain和backup三外部来源双模式/重开/8项设置通过；正常入口Simulator构建/版本通过。Photos prepare真实闭合构建/安装且所记录built/installed指纹相同；addOnly真实XCTest 1通过/0失败/0跳过、Xcode exit0且host/reader关闭。后验控制器以`photos-prepared-host-changed`失败，具体差异未知，不能认定发生路径迁移或原生保存测试失败。无成功addOnly result/identity，完整read-write 27项未执行且无摘要；owned app stop及Simulator Shutdown/delete/absence通过。32份闭合白名单证据和两artifact大小/SHA见第九轮记录及`release-ci-ninth-*`。

四来源矩阵已完整：`complete=true`、12方向/24模式、4个冻结来源、无缺项且关闭重开；每个consumer 6行、4 assets/5 versions、8项唯一设置。完整矩阵receipt SHA-256为`aa1c831e64dd46008ea06c945d038a5374543db8bc4b4b1e5e9d8cc0828bcda8`。离线验证器及控制测试60项通过，控制日志SHA-256为`5f6f8d90790c895ab7a631989fc17c5d512e0ae0f103d64f766e37a94f23de6d`；这只核验闭合证据字段，不替代原生harness或设备PT。第八轮partial 11/22和Photos 21通过/6失败均保留为历史，不倒推成修正通过。测试控制器逐项诊断、受限当前位置查询及三处异常收尾缺口已修正并独立复核；186项本机控制与六文件编译通过，见[最终控制记录](validation/release-photos-frozen-host-controls-02.json)。源码审查见[Photos host guard审查](validation/release-photos-host-guard-review.md)，下一轮Apple实际运行待补；物理设备、最低系统、硬件PERF、真实服务与Apple正式发行仍未通过。

第十轮Apple实际结果补充见[闭合记录](validation/release-apple-tenth-ci.json)：Mac作业成功；iOS完整Photos 27项为22通过/5失败/0跳过，五格式在保存前读写授权未决定，原始资源读回尚未确认。此前“下一轮待补”为第九轮收尾时态。当前仅测试宿主增加一次真实SDK请求与回调/SDK重读确认，保留超时失败锁存、27项和PNG/JPEG原字节断言，生产仍addOnly；[源码审查](validation/release-photos-sdk-authorization-review.md)不能代替下一次Apple实际运行。该CI软件缺口仍在本轮收尾范围，不能归为已排除的实机验收。

## 第十一轮 Apple CI

第十一轮run38145131826整体failure：Mac成功；iOS完整Photos 27项22通过/5失败/0跳过。新helper已真实编译运行，但首个SDK请求30秒无callback，五格式保存资源未独立读回。该项仍是授权范围内可继续的软件CI缺口，不属于物理设备/PT排除；完整证据和pending候选见[里程碑30](milestone-30-versioned-delivery.md)及[授权审查](validation/release-photos-sdk-authorization-review.md)。Windows/Android包不变，四来源矩阵仍为12方向/24模式。

## 保留的软件缺口与限制

- Android 工作台、备份、诊断的原生导出已接入并取得实际模拟器及正常 UI 证据；iOS 对应路径已接原生 Files/Photos，Mac/iOS 备份取得接入范围授权和共同私有复制。OUT-003/PLT-005/BAK-006/OPS-003 的软件验证记录见里程碑29及E36；真实选择器、Files提供者与照片格式互操作仍需PT，不将受控协议或模拟器子场景计为全部平台验收。
- Windows云占位来源的已知标记可预先拒绝；来源交付取消、实际清理等待和取得前令牌重验已接入，见`milestone-26-source-cancellation.md`。无法确认内核读取结束时继续等待，不能承诺所有未知阻塞来源有界停止；移动/Apple真实云取得器不能据此称全部完成。不加超时后提前释放保护的假取消。
- 处理输出固定默认去除隐私元数据；IMG-005关闭隐私处理的明确选择由原样字节上传及逐次风险确认承接。技术选型6.3的MetadataPolicy只传递必要方向与色彩白名单，不要求任意复制隐私字段。本轮不据旧台账文案增加一个无执行路径的“保留元数据”开关；完整方向/格式契约证据仍单列。

Windows 基线见 `milestone-27-windows-completion.md`，Android 收尾及 Windows 回归见 `milestone-28-android-completion.md`，Apple 文件能力和适用跨平台软件回归见 `milestone-29-apple-files.md`；截至2026-10-11的进展和待补项见`windows-v1-coverage.md`的E36–E39。25、26 等阶段保留历史证据。旧台账中的“未实现”按当前实现更新，历史证据不删除。本轮完成声明仅覆盖已授权的软件收尾和Windows/Android本地正式交付；Photos仍须以实际Apple CI结果为准。PT、外部服务、物理设备/最低系统、硬件PERF及Apple正式发行等验证边界继续保留，不据此宣称四端全部验收。
