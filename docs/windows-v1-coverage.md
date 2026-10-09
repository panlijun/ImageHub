# Windows 完整 V1 开发与动态验收基线

审计日期：2026-10-04；最新收尾 2026-10-09。业务基线 IH-SRS-001 1.1；测试设计 IH-UTD-001 1.1；技术选型 IH-TS-001 1.0。本台账保留 Windows 软件基线；Android增量及Windows回归见E35，本轮Apple与当前Windows增量见E36，正式本地打包及后续CI状态见E37。Windows完整Release ZIP和Android专用签名ARM64 APK已按收据生成并核验；这不代表公开二进制、商店发布、Apple正式签名发行或四端验收。真实账号测试与物理设备/硬件验收继续排除且不计通过。**Windows结果见E34/E36，Android增量见E35；90项业务定义及其逐项证据状态不因软件测试通过数改变。**

## 范围与判定

- 2026-10-08用户最新决定：不需要Catbox匿名上传。覆盖ACC-001/ACC-002/ACC-004的匿名目标行为，生产仅提供Catbox userhash和ImgBB APIKey；已有本项目匿名身份保留历史/备份读取，不能重新启用。原资源包条文保留，当前代码按此决定验收。

- 当前目标排除需要真实账号的测试；没有授权真实上传、删除或探测。精确服务能力unknown时等待、不派发，真实服务证据不计通过；也不以移除测试阻断为由猜测限额或伪造成功。

- 2026-10-07用户最新决定：本轮排除需要实机的剩余验收，继续软件代码和现有主机自动化；具体编号与边界见 [软件/设备拆分](software-completion-scope.md)。这优先于下文早期“全部必要验证均须本轮补齐”的工作安排。设备项保留原文并记未执行，不计通过；真实服务CT独立保留，平台未接入仍是代码缺口。

- 2026-10-07用户最新决定：不实现网络计费状态，只判断网络类型，并按允许的类型控制已确认上传任务自动派发/网络恢复继续。覆盖QUE-008及UT-063的计费判断与“仅非计费”策略；仍保留离线、移动网络需明确允许、条件恢复只派发一次等规则。以下权威原文不改，具体当前验收以此决定为准；不据“自动同步”新增应用云账户或图库云同步。

- 最新用户决定优先，其次为需求 1.1、技术选型 1.0、当前设计规格、HTML 原型。本文是可更新的验收台账，不能自行改变业务规则。
- Windows 11 x64 全部 V1 P0/P1 保留，四端共享业务从开始支持，平台适配分别补齐。Android已实际构建ARM64/x86_64 APK并完成API36 x86_64模拟器验证，物理设备/API29仍未验证；macOS主机软件验证见E36，iOS模拟器文件流程见[里程碑29](milestone-29-apple-files.md)。Apple真实系统选择器UI、Files提供者/照片格式互操作与设备PT仍待验收。不得把源码配置或主机布局模拟写成平台可运行。
- V2 的 SYN-001–008 和 V3 的 EXT-001–003 不进入 V1 功能完成数；REV-003 仍检查未来范围隔离。
- 资源包只读。首次只读审计未运行软件测试；后续真实实现/验证按阶段登记。始终不读取旧项目源码、数据库、图库或凭据，不未经授权上传、删除远端或写Git；用户授权的首次本地PC提交为d642ebc，Android阶段未新增提交、推送或发布。
- 本文逐条复制权威需求的属性、必需行为与验收条件，并关联权威测试矩阵；代码证据和里程碑运行记录分别标注。原始来源与验证类型均保留，避免摘要漏规则。
- “已实现”仅表示已找到满足该条核心行为的当前代码，**不等于该条全部验证通过**；“部分”表示行为/平台接线或验证缺口；“未实现”表示未找到正式生产闭环；“开发中”表示并行工作尚未由主线程审查验收；“缺设备/真实服务证据”表示必须独立补齐对应 PT/IT/CT/AT，不能以模拟替代。
- 2026-10-04 本轮并行 TextPolicy、ImageProcessor、图库整理/回收工作必须在主线程阅读实际变更和取得新验证证据后更新状态。已经出现的新文件不自动计通过；E10 登记本轮主线程真实结果，原两份里程碑保留为历史。
- 原始 52 项测试运行记录含参数化、widget 和部分需求场景，不是 52 个完整正式 UT，也不是 90 条需求通过。E1/E2 为历史记录；本轮新运行结果见 E10，不能叠加成正式需求通过数。

## 数量与发布门槛

| 对象 | 权威数量 | 本文处理 |
| --- | --- | --- |
| 正式需求 | 101：V1 90、V2 8、V3 3 | 逐条收录全部 90 条 V1，不含 SYN/EXT 功能通过数 |
| V1 优先级 | P0 51、P1 39 | 两级均是完整首版必须完成 |
| UT 设计 | 112：V1 102、V2 10 | 逐条链接原编号；V2 单列排除 |
| 非 UT 验证方案 | 39：CT 7、IT 10、PT 7、AT 7、PERF 4、REV 4 | 各自分开记录，不合并成“测试通过” |
| 无纯 UT 的 V1 | PLT-001/004/006、NFR-001/002/005 | 仍必须提交 PT/AT/PERF/REV 实际证据 |
| 四端正式 V1 全部必要验证闭合 | 尚未完成 | 当前 Windows 软件目标与四端/真实服务正式验收分开，软件审查与实际运行见 E34 |

全部 V1 必需行为完成且相应必要验证有证据，才可关闭条目。P0 数据保护、秘密泄露、误删除、unknown 盲重发不可遗留；P1 必需能力缺失也不能发布成完整首版。UT、CT、IT、widget、PT、AT、PERF、REV、构建独立统计；资源包 verify-kit 是文档完整性检查。

## 当前证据索引

| 标识 | 实际证据路径 | 已证明或可检查范围 | 不能据此声称 |
| --- | --- | --- | --- |
| E0 | 当前 [app/lib](../app/lib)、[schema](../app/lib/features/gallery/data/library_database.dart)、[应用入口](../app/lib/app.dart) 与 [架构](architecture.md) | schema 10 的 28 表分离图库、输出、账号、持久上传、处理依赖、链接观察、导入审计来源/历史、恢复日志及本机诊断；桌面/M1 共用处理、任务、链接、设置、诊断和备份恢复页 | 真实服务可用及全部平台验收通过 |
| E1 | [第一里程碑记录](milestone-01.md) | 当时 38 tests、1 Windows 引擎集成、6边界独立进程恢复/正常重开/锁、Windows Release、真实截图 | 全112 UT、全39方案、PT选择器/普通窗口关闭、硬件断电或四端通过 |
| E2 | [第二里程碑记录](milestone-02-m1.md) | 当时 52 tests、桌面/M1各1 Windows引擎集成、进程工具、Windows Release；名称/收藏、M1选择子范围 | 分类/标签/完整检索、Windows全部整理UI、Android/iOS实机、完整V1 |
| E3 | [repository](../app/lib/features/gallery/data/library_repository.dart)、[database](../app/lib/features/gallery/data/library_database.dart)、[file store](../app/lib/core/managed_file_store.dart)、[inspector](../app/lib/core/image_inspector.dart)、[核心测试](../app/test/core/library_repository_test.dart) | 导入日志/校验/同卷发布/关联事务、SHA去重、修复、失败保护与安全路径，真实小图夹具 | 输出/上传/备份/清理所有持久边界或四端预算实测 |
| E4 | [query](../app/lib/features/gallery/domain/gallery_query.dart)、[controller](../app/lib/features/gallery/presentation/gallery_providers.dart)、[query tests](../app/test/core/gallery_query_test.dart)、[controller test](../app/test/gallery_controller_test.dart)、[widget tests](../app/test/widget_test.dart)、[M1 tests](../app/test/mobile_gallery_test.dart)、[desktop integration](../app/integration_test/gallery_flow_test.dart)、[M1 integration](../app/integration_test/mobile_gallery_flow_test.dart) | 名称/收藏分页与UUID选择、真实临时库/文件；系统取得器由fixture替换 | 系统选择窗口授权或真实移动运行 |
| E5 | [独立进程工具](../app/tool/verify_process_recovery.dart)、[锁探针](../app/test/core/lock_probe.dart)；运行记录 E1/E2 | import 六边界 exit(73)、正常跨进程重开、排他锁释放；原图字节和身份核对 | 操作系统实际强退、硬件断电、队列/备份持久化通过 |
| E6 | 本轮并行 TextPolicy、ImageProcessor、图库整理/回收；已观察 [text policy](../app/lib/core/text_policy.dart)、[folding data](../app/lib/core/unicode_case_folding.dart)、[policy test](../app/test/core/text_policy_test.dart) | 共同文本/组织/回收/像素引擎已由主线程审查并运行，具体范围见 E10 | 不把真实引擎验证写成 OUT/任务/图床或四端实机完整交付 |
| E7 | [图床输入资料](../imagehost-new-project-kit/providers/README.md)、[Catbox](../imagehost-new-project-kit/providers/catbox.md)、[ImgBB](../imagehost-new-project-kit/providers/imgbb.md) | 只读官方资料与输入约束 | 生产适配器、凭据验证健康或真实服务联调 |
| E8 | [环境/四端状态](environment.md)、新 app/windows/macos/android/ios 源工程 | Windows Release与Android API36 x86_64正常Release应用已有运行证据；ARM64专用Release构建及元信息/签名检查见E36；Apple软件验证见[里程碑29](milestone-29-apple-files.md)/E36 | ARM64物理手机/最低API29、Apple真实系统选择器/Files提供者及照片格式互操作、设备符合或正式发行 |
| E9 | 本文件与 [需求](../imagehost-new-project-kit/documents/requirements-analysis.md)、[需求审查](../imagehost-new-project-kit/documents/requirements-review.md)、[测试设计](../imagehost-new-project-kit/documents/unit-test-design.md)、[选型审查](../imagehost-new-project-kit/documents/technology-selection-review.md) | 数量、业务规则、正反向验证关联与范围检查 | 文档闭合或技术选型闭合等于软件完成 |

E10：[本轮主线程记录](milestone-03-gallery-processing.md)；130 项现有 tests、桌面/M1 各一项 Windows 原生引擎、独立进程工具、静态检查和构建分别以链接日志登记。不等于 130 个正式 UT 或 90 条正式需求通过。

E11：[处理输出里程碑](milestone-04-processing-outputs.md)。共同处理工作台、schema 3 输出/永久来源/导出/安全清理由主线程审查；实际核心/widget、Windows 引擎 IT-003 子流程及进程恢复分别登记，不代表四端 PT、完整 AT 或 90 条首版验收闭合。

E12：[账号与安全边界](milestone-05-accounts.md)；共同账号/引用日志/会话/脱敏和表单有核心/widget证据；2026-10-05 授权补齐 ATL，Windows IT-007 原生子流程及账号版 Release/启动退出通过。三端后端与完整 IT/PT 未完成。

E13（历史阶段，当前接线见 E14）：[图床与队列基础](milestone-06-provider-foundations.md)；两适配器的受控传输、实际取消收尾、协议/秘密边界，以及纯队列状态/退避/聚合/单调时间子测试。默认精确限制 unknown 时不派发；尚无持久发布队列、用户上传入口、RemoteResult 提交或真实 CT/IT-008，不计完整上传流程通过。

E14：[持久上传与任务页](milestone-07-durable-upload-queue.md)；真实库/文件的入队、输入与目标快照、保护引用、当前凭据授权、尝试/取消/晚到结果、重开恢复及管理秘密日志；应用级有界调度/单调退避/持久运行检查点和共享任务页。新增 41 项专项、当前 288 项全量通过；原生引擎、构建及截图分别登记，不计真实图床 CT/IT-008、完整 AT/PT 或全部 V1 通过。

E15：[备份基础](milestone-08-backup-foundations.md)；两种导出范围、白名单一致视图、ZIP/ZIP64 写入与结构预检、SHA-256/CRC/真实像素校验、Windows 空间检查和独占发布、共享备份界面及来源租约已有实现证据。当前只证明导出和恢复预检基础；尚未证明实际恢复提交、合并/替换、身份与关联重映射、失败回滚、完整 IT-005/AT-005 或平台 PT。运行数量、原生界面运行状态及实际结果以里程碑记录为准；不据此增加正式 V1 通过数。

E16（历史阶段，当前接线见 E17）：[恢复合并规则与上传侧保护](milestone-09-restore-plan-and-gate.md)；永久元信息纯计划、普通确认去重、上传前维护及租约排空子范围验证。该阶段没有实际恢复或全库维护，不增加正式 V1 验收数。

E17：[实际合并恢复](milestone-10-merge-restore.md)；关系计划、schema 6、全库维护、持久文件/数据库提交、无路径来源与不可执行历史、禁用账号、metadata missing 与 full 修复、共同确认/冲突/取消界面已有实际实现与子范围验证。420 项全量通过；Windows 原生/构建结果单独登记在里程碑。不代表替换恢复、内部快照/执行代次、完整 PT/AT/CT、大包性能或全部 V1 完成。

E18：[替换安全基础](milestone-11-replacement-safety-foundations.md)；真实内部 SQLite/登记文件快照、全关系/字节验证、持久目录归属、缺失证据、维护交错保护与旧上传运行会话隔离。快照专项 18/18、会话专项 3/3、441 项全量通过；原生/构建证据单列。未实现实际替换提交、快照回滚或成功后会话切换，不增加正式 V1 验收数。

E19：[真实替换恢复](milestone-12-replacement-restore.md)；确认前实际重建当前快照，独立风险确认，保持备份身份的替换、单事务提交/失败回滚、旧意图取消、会话切换/迟到拒绝、图库与账号任务状态重置、旧字节/系统秘密有证据清理及中断重试。回滚 11/11、仓储 21/21、界面 10/10、483 项全量通过；原生和构建分开记录。未完成完整 IT/AT/CT/PT、硬件断电、大库性能或三端设备验证，不增加正式 V1 验收数。

E20：[本地链接管理](milestone-13-local-links.md)；真实 ordinary SQL 交集查询/分页/确定顺序、历史目标身份、两种明确复制范围、四格式/跳过/去重、本地复制分享反馈和结果移除日志/系统秘密清理。仓储20、系统适配11、链接widget7与相关mobile/task回归共20通过，当时全量521通过；Windows原生与构建单列。主动探测、远端删除、系统剪贴板/分享PT、完整AT及三端设备仍待补，不增加正式V1验收数。

E21：[图库远程组合检索](milestone-14-gallery-remote.md)；当前永久内容的普通结果/发布项/恢复终态审计检索、同项远程交集、历史目标身份、SQL计数分页与UUID、真实MAX UTC上传排序/NULL末尾、后注册秘密保护。仓储18、定向界面/controller24及最终全量548通过；Windows图库/备份引擎子流程和Release分别登记。完整AT-001/PERF-001及三端设备仍未通过，不增加正式V1验收数。

E22：[完成历史清理](milestone-15-upload-history.md)；共同仓储和桌面/M1明确范围确认，保留六类活动状态、真实租约、未完结果管理及依赖；SQL事务/指纹/epoch、普通结果/秘密/字节和空批次幂等账本保护。实际核心、widget、Windows引擎与构建结果分列；移动后台、完整人工AT/IT/PT仍待补，不增加正式V1验收数。

E23：[主动链接检测](milestone-16-link-availability.md)；明确范围确认、独立无凭据HEAD、四状态持久观察/SQL交集、generation与owner/epoch、真实取消/退出/维护排空、失败历史/字节/秘密保留。可携带两模式恢复不携带本机观察，自身schema7迁移及私有快照/回滚回归；核心/widget、Windows原生与构建分列。没有真实服务CT/IT-008、完整人工AT或三端设备证据，不增加正式V1验收数。

E24：[持久设置与处理调度](milestone-17-settings-scheduling.md)；严格数值/格式校验、真实SQL原子设置与默认目标保存/故障回滚/重开、owner/epoch/指纹失效、新工作台默认初始化及已有输出冻结、动态上传与共同FIFO处理候选预算。待凭据默认只保留原选择，实际输入租约/排队取消/关闭排空与固定编辑分区身份有子范围证据。核心、widget、Windows原生与构建分别记录；缓存/全局保留、诊断、网络计费观察、跨平台设置转移及完整AT/IT/PT未完成，不增加正式V1验收数。

E25：[本机诊断与主动导出](milestone-18-diagnostics.md)；真实结构化事件、批次/尝试关联查看、固定恢复动作、30天/实际UTF-8内容10MB最旧维护、确认范围清理和脱敏JSON。业务事务结束后独立记录，不因诊断故障回滚业务；未知格式保留现场，新秘密持久重遮蔽。Windows原生真实库/文件/重开/清日志保留PNG子流程通过；系统选择器、全部事件覆盖、参考负载与完整AT/PT及三端原生导出待补，不增加正式V1验收数。

E26：[缓存与空间管理](milestone-19-storage.md)；真实文件分类、诊断逻辑内容不双计、平台可用空间、逐块导入及处理意图前低空间拒绝；持久缓存LRU、独占发布归属、冻结确认、未知/变化/使用保护、实际读取排空、处理内存小图与替换通知失效接线。Windows原生容量/发布/清理/设置重开子流程及核心/widget有证据；三端源码配置不代表构建/设备通过，完整IT/AT/PT、参考负载校准与跨平台设置转移待补，不增加正式V1验收数。

E27：[独立单项暂停](milestone-20-item-pause.md)；schema9单项标记/整批控制隔离、重复幂等、保留冻结输入与退避、旧调度快照在写入门复验、自身升级与旧恢复证据保护、当前私有快照/真实回滚保留新列、桌面/M1共同任务页。具体实际运行及未执行项见阶段记录；完整PT/AT与真实服务不据受控子流程宣称通过。

E28：[网络类型与自动继续](milestone-21-network-types.md)；四端原生默认路径、严格安全事件/读取、共享类型策略、真实本机设置格式3、会话许可隔离、暂停/unknown/退避和派发写入门核对；Windows真实方法/首次监听及任务页有证据。具体软件检查与平台缺口见里程碑，不把受控切换当作完整PT或真实服务通过。

E29：[上传前自动处理依赖](milestone-22-upload-processing.md)；schema10/28表冻结计划与逐目标关联、独立本地actor/真实像素和共享预算、输出日志/关联事务、就绪项独立继续、失败跳过不回退原图、损坏来源明确修复重试、实际IO保护/维护/重开及unknown隔离。共同桌面/M1页面、Windows原生真实处理/重开与备份恢复回归已有子范围证据，具体运行及失败记录见里程碑。真实服务、多端设备、硬件断电和完整人工验收仍未通过，不增加正式90条验收数。

E30：[可携带设置与可用项恢复](milestone-23-backup-settings.md)；Manifest格式2/自身格式1严格读取、八项设置与平台名单、同SQL快照、准备/日志/事务复验、关联提交成功后更新运行策略、失败回滚/取消/旧包保留、共同确认与跳过反馈。具体实际运行与未验证项见阶段记录；不据纯四平台规划声明四设备互读或完整BAK/CT/PT完成。

E31：[独立远端删除与持久审计](milestone-24-remote-deletion.md)；Catbox账号严格单文件/同目标UUID当前授权、两项独立确认、请求前复验、prepared/sending持久证据与重开保守分类、真实fetch/源流收尾、未知保留本机数据、不自动重试、共同页面及合并/替换/回滚审计隔离。实际受控验证见阶段记录；公开协议缺可靠删除确认，ImgBB不猜测管理请求，真实CT-003/完整IT-008/AT未执行。

E32：[软件补齐与本轮排除](milestone-25-software-completion.md)；共用永久副本SDK原图/动画播放暂停、实际IO与预算收尾，Windows明确待获取来源分类，当前账号结果观察及持久先后隔离，留存/备份入口与冲突修正指引。实际自动化、原生子流程及构建数量按该记录登记；设备排除见[拆分表](software-completion-scope.md)，不是通过或删除正式需求，真实服务另列。

E33：[来源取消与图床能力边界](milestone-26-source-cancellation.md)；等待首块/下一块时取消交付，等待实际源清理/写入后清未提交项，资料库关闭及根锁保护、取得前取消重验与界面等待均有本机软件证据；格式独立限额与全局取小值，生产仍unknown。[官方契约核查](provider-contract-evidence.md)没有补足API精确上限/完整格式与可靠删除确认，真实CT/IT-008不计通过。

E34：2026-10-08 [Windows 软件收尾](milestone-27-windows-completion.md)，逐编号当前源码核对分为[图库/处理/输出/数据/非功能](validation/windows-library-software-audit.md)、[账号/上传/队列/链接/安全/平台](validation/windows-network-software-audit.md)、[备份/设置/诊断/空间](validation/windows-local-software-audit.md)。适用软件行为按最新用户规则检查，最终格式、分析、unit/widget、本机SQL/files/SDK、Windows原生子流程、独立进程与Release结果分别登记。以下逐条“当前证据”更新为此审查，不把90条源码映射当作90条正式需求全部验证通过；历史E1–E33保留当时证据。

E35：2026-10-08 [Android软件完成及Windows回归](milestone-28-android-completion.md)。Android M1接有界SAF照片/文件/ZIP来源、系统文件/目录及MediaStore保存、备份和诊断导出、回收和安全退出。1399软件测试通过/1非Windows分支跳过，API36 x86_64两项原生子流程、五个系统保存字节独立核对、正常Release入口闭环及ARM64/x86_64 APK构建有实际证据；四个受影响Windows原生流程和Release正常退出回归通过。来源/导出实现与选型8.1/8.3的具体关系见[原生边界说明](android-native-files.md)。本段不将模拟器证据记作整项PT、ARM64/API29或真实服务通过；以下Windows审查仍按其原范围读取。

E36：2026-10-09 当前增量证据。Apple文件能力代码与模拟器证据仍以[里程碑29](milestone-29-apple-files.md)为准；源提交`95b94d3`的标准Apple CI run `37908256215`中，macOS作业success，1456项软件测试通过/4个Windows分支跳过、4项Flutter原生测试、23项XCTest零失败零跳过、独立进程恢复/锁及Release构建通过，实际日志与元信息在`app/build/validation/apple-first-37908256215/`。同源iOS作业已终止失败：第二次Flutter备份测试的Xcode构建耗时62.6秒，未进入CT-006测试步骤；该步骤运行15分钟后超时。停止后的`ios-backup-interop.log`记录`Error waiting for a debug connection: The log reader failed unexpectedly`和`Unable to start the app`；`ios-simulator-cleanup.log`记录自有模拟器Shutdown/delete清理成功。此结果不能推断备份业务测试失败，也不计为通过。Windows真实大包证据见[ZIP64运行日志](validation/release-large-backup-01.log)及[结果摘要](validation/release-large-backup-result.json)：172张真实BMP，ZIP64归档4,328,697,800字节，默认预检、合并提交、重开并核对全部永久字节通过；这是Windows软件流程，不是其他三端大包验证或硬件PERF。冷缩略图证据见[批次记录](validation/release-thumbnail-cold-batch.json)：62项真实读取全部结束、图库关闭且fileLeases为0；1904ms是本次观察值，不是参考设备性能验收。Android专用ARM64 Release预构建的元信息/签名证据见[验证摘要](validation/release-android-dedicated-verification.json)：versionCode 1、kernel/platform version 0.1.0+1、最低API 29、非debug V2签名；正式dist交付物尚未生成。版本单一源及内核/四端独立版本接线已专项核对，但不据此宣称正式发行。

E37：2026-10-09 [版本化本地交付](milestone-30-versioned-delivery.md)。Windows完整Release ZIP 16,872,605字节、34个文件/目录条目及app-local MSVC CRT，逐项ZIP/解包摘要、原生独立版本、正常启动及WM_CLOSE退出0通过；Android唯一ARM64 Release APK 27,400,002字节，io.imagehost.imagehost/API29、内核/平台0.1.0+1、精确build1、非debug及专用证书V2签名通过。两平台package_release.ps1实际退出0，独立核对artifact/SHA256SUMS/receipt；源base cfd55d0、dirty=true仅两张既有验证截图，源指纹留存，不称clean源构建。证据为[Windows receipt](validation/release-windows-formal.json)和[Android receipt](validation/release-android-formal.json)。这两项是本地正式包，不代表公开二进制、商店发布、Apple正式签名发行或ARM64实机验收。

Windows软件1459项通过/1平台分支跳过，M1快捷入口20项、五项Windows原生及正常Release启动退出通过；真实4,328,697,800字节ZIP64默认预检、合并、重开全部字节核对通过。Windows、Android、Mac三个来源的六个方向已完成完整及元数据恢复重开；iOS来源和完整12方向矩阵、Photos新增独立资源读回仍待验证。Apple生产原生文件能力已接入，未完成的是适用验证，不是功能未实现。第五轮历史结果见[第五轮记录](validation/release-apple-fifth-ci.json)；不改其failure细节。第六轮源`5326d527962daad1de23f3340dda40b55aec6e78`历史结果见[第六轮记录](validation/release-apple-sixth-ci.json)，其停止根因当时未暴露，不由第七轮反推。第七轮[run37934102081](https://github.com/panlijun/ImageHub/actions/runs/37934102081)源`1cb16cfddcbd67cf8d744b5107a2797d3fdd2007`已整体failure：Mac成功（1456软件通过/4平台跳过、八项进程边界、四项Flutter原生、Windows/Android来源完整/元数据/重开、23项XCTest、Release64.5MB及版本核验）；iOS构建211.0秒，semantics基线handle=1，四项命名Dart和SDK回调4项、1项XCTest零失败/跳过、ad-hoc签名与Keychain实际流程通过、Xcode exit0及host/reader关闭。owned guard成功后simctl terminate exit3，实际闭合响应为六行NSPOSIXErrorDomain code3“found nothing to terminate”；源解析器未匹配，故`owned-app-stop-unconfirmed`，不能判断应用已停止。自有Simulator Shutdown/delete/absence成功；backup、新Photos和正常入口未执行。第七轮闭合artifact大小/SHA已核验，见[第七轮记录](validation/release-apple-seventh-ci.json)和九份白名单证据。本机94项控制2.637秒通过并离线匹配闭合日志，不代表Apple原生修正通过。新解析器仅接纳完整实测六行、固定bundleID/domain/code/TAB/顺序与exit3，旧分支不变，其他输出继续严格失败；Apple errno说明不是完整simctl文案契约。下一轮CI仍待实际执行。两份正式包receipt及第四至第七轮artifact均已按大小/SHA核验。最低系统实测、物理设备PT/PERF/断电、真实图床服务与硬件压力仍未计通过；unknown服务能力继续拒绝派发。

## 优先阻断与矛盾处理

1. 当前源码核对按E34覆盖90条适用Windows软件行为；旧阶段的“未实现”不再作为当前状态。软件保护缺陷必须修正并记录实际失败/复验，不能仅通过取消设备测试关闭。
2. Catbox匿名已移除，计费状态不实现。Catbox账号/ImgBB的精确服务能力仍unknown，生产任务只能等待；请求、授权、处理依赖及持久结果代码已接入，不将受控传输或配置成功当真实服务可用。
3. 真实账号/服务CT与IT-008没有执行，不计通过。检测/删除均须明确授权，删除发出后缺可靠确认保持unknown。设备PT、硬件压力/断电/PERF按本轮决定排除；完整人工AT亦未伪记通过。
4. 备份导出、预检、实际合并/替换、快照回滚及旧epoch隔离已有当前调用链和测试。PNG重导入纠错只改已校验永久元信息；冻结审计保留历史描述，永久描述冲突仍严格拒绝。未知暂存/发布归属和不可信秘密视图阻止操作，不猜测删除或空库覆盖。
5. Windows正式构建与原生子流程结果单独登记；系统选择窗口使用fixture的测试不是PT。主机原生秘密写/重开/删及低内存信号读取可以提供本机软件证据，不能代替真实账号有效性或硬件压力测量。
6. Android工具已安装，API36 x86_64正常Release与原生文件导出已有证据；Windows正式ZIP及Android专用签名ARM64 APK的实际本地交付见E37，物理设备/API29仍未验收。Apple文件保存接线及iOS模拟器子流程见[里程碑29](milestone-29-apple-files.md)；最新macOS主机验证见E37，iOS同源CI在启动/VM发现阶段超时并终止失败，底层原因尚未确认。真实系统选择器UI、Files提供者/照片格式互操作及设备PT仍待验收，不能将平台子流程扩大为完整平台验收。

已解决边界：BAK-004标签并集超LIB-003的50上限仍拒绝，并展示双方对象/数量及整理重导出指引；PNG永久纠错与DAT-003/UPL-001冻结身份的关系按E34严格区分。原型样本ID不得替代生产UUID。若后续真实服务或平台实测与IMG-004等要求不符，仍须报告具体编号和影响，不能用现有实现反改需求或测试。

## 逐条 V1 覆盖

以下“必要验证”保留原测试矩阵；本轮运行、未运行和用户排除项以E34分别记录。当前软件证据与原始条款逐项对照，不改需求原文，也不抹去历史运行证据。

### IMP

#### IMP-001 选择与取得资源

属性：P0｜V1｜来源 SRC-C1、SRC-U、WEB-04｜验证 UT、PT、AT

应用必须允许单项及多项导入；资源可以来自系统文件或图片入口。取得可读字节前仅标记获取中，不视为永久入库。取消选择无副作用。

验收：选择 3 项其中 1 项待云端获取，已取得的 2 项可继续；取消入口不创建资产或上传任务。

**当前状态：** Windows适用软件链已核对；最终运行与验收边界见E34，不代表正式四端条款全部验证通过。

**当前证据：** E34 [逐编号源码审查](validation/windows-library-software-audit.md)：具备。`ImportGateway.pickFiles` 系统多选；`_acquireAndImport` 将选择/等待来源与永久提交分开，空选择不建资产/上传意图，逐个取得的资源继续交付批次。 测试入口：`core/cloud_import_batch_test.dart` UT-010/011 验证待获取项不阻断实际 PNG；`gallery_import_exit_test.dart` UT-011 取消迟到来源后允许新选择；IT `gallery_flow_test.dart` 真实 fixture 取得与导入。系统选框/权限 PT 另列排除。

**缺失项/未验证：** Windows选择器/云来源/撤权实机PT未执行；未知内核读取不保证有界停止，不能提前释放保护。

**必要验证：** UT-001；AT-001、PT-001。UT验证业务判断；真实依赖和流程由其他方案补证。

#### IMP-002 真实图片校验

属性：P0｜V1｜来源 SRC-C2、SRC-O｜验证 UT、IT

必须校验内容是否为支持的图片，不能仅凭扩展名判断。首版导入与预览支持 PNG、JPEG、WebP、GIF、BMP；HEIC/HEIF 为能力协商扩展，不承诺首版全端可处理。

验收：伪装为 JPG 的文本被拒绝；真实支持内容具有错误扩展名时按内容处理；不支持格式有明确原因。

**当前状态：** Windows适用软件链已核对；最终运行与验收边界见E34，不代表正式四端条款全部验证通过。

**当前证据：** E34 [逐编号源码审查](validation/windows-library-software-audit.md)：具备。`ImageInspector._format/_decode` 按实际字节识别、解码 PNG/JPEG/WebP/GIF/BMP，不依赖后缀；不支持及坏图为固定分类。PNG additionally 校验 eXIf/CRC/边界。 测试入口：`core/library_repository_test.dart` UT-002/IT-001 五种真实格式错误后缀、伪 JPG 文本、不支持字节；`core/png_orientation_test.dart` 畸形/重复 eXIf 不产生可用资产。

**缺失项/未验证：** Windows选择器/云来源/撤权实机PT未执行；未知内核读取不保证有界停止，不能提前释放保护。

**必要验证：** UT-002；IT-001。UT验证业务判断；真实依赖和流程由其他方案补证。

#### IMP-003 永久副本提交

属性：P0｜V1｜来源 SRC-U、SRC-O｜验证 UT、IT、PT

内容复制及校验完成后才提交资产。副本复制失败、空间不足或取消不得生成已可用记录；残留半成品可回收，外部来源不修改。

验收：成功后外部来源被移动或权限撤销，本机副本仍可读；复制中断不留下可用资产。

**当前状态：** Windows适用软件链已核对；最终运行与验收边界见E34，不代表正式四端条款全部验证通过。

**当前证据：** E34 [逐编号源码审查](validation/windows-library-software-audit.md)：具备。`_importResource/_complete/recover` 复制关闭、真实摘要与像素校验、发布后事务提交；失败保留/回收有日志依据的半成品，外部来源只读。 测试入口：`core/library_repository_test.dart` UT-003/091 各 ImportBoundary 中断及源流失败、UT-004 来源移除后重开；`core/import_source_cancellation_test.dart` 实际源清理/writer 等待；`core/storage_capacity_test.dart` 空间拒绝。

**缺失项/未验证：** Windows选择器/云来源/撤权实机PT未执行；未知内核读取不保证有界停止，不能提前释放保护。

**必要验证：** UT-003、UT-004；IT-001、PT-001。UT验证业务判断；真实依赖和流程由其他方案补证。

#### IMP-004 内容去重

属性：P0｜V1｜来源 SRC-C2、SRC-O｜验证 UT、IT

同库内相同字节内容必须复用资产并保留分类、标签、收藏与远程历史；来源位置与文件大小不能单独决定内容身份。重复导入回收期资产应提示恢复，不静默创建副本。

验收：相同内容不同位置只产生一份有效资产；同位置同大小但内容不同产生新内容身份，不继承旧上传关联。

**当前状态：** Windows适用软件链已核对；最终运行与验收边界见E34，不代表正式四端条款全部验证通过。

**当前证据：** E34 [逐编号源码审查](validation/windows-library-software-audit.md)：具备。`_complete` SHA-256+实际字节数复用版本/资产，保留整理/历史；回收重复返回 needsRestore；不同内容新身份。 测试入口：`core/library_repository_test.dart` UT-005/006/007；`core/import_recycle_boundary_test.dart` 活跃资产优先、独立版本重用、坏/缺副本修复；`core/gallery_remote_query_test.dart` 远程关联按当前内容。旧错误 PNG 元信息重用限制见文末。

**缺失项/未验证：** Windows选择器/云来源/撤权实机PT未执行；未知内核读取不保证有界停止，不能提前释放保护。

**必要验证：** UT-005、UT-006、UT-007；IT-001。UT验证业务判断；真实依赖和流程由其他方案补证。

#### IMP-005 批次部分成功

属性：P0｜V1｜来源 SRC-C1、SRC-O｜验证 UT、IT、AT

每个资源独立报告成功、重复、失败或取消；一个坏文件不阻断其他项目。结束汇总必须与逐项结果相等，并提供失败原因及重新选择入口。

验收：2 个有效、1 个损坏、1 个重复的批次汇总为 2 成功、1 失败、1 重复。

**当前状态：** Windows适用软件链已核对；最终运行与验收边界见E34，不代表正式四端条款全部验证通过。

**当前证据：** E34 [逐编号源码审查](validation/windows-library-software-audit.md)：具备。`ImportBatchResult` 独立逐项状态和计数；`GalleryScreen._import` 显示真实汇总/原因，系统文件入口可重新选择，单项失败不截断后续。 测试入口：`core/library_repository_test.dart` UT-008 两成功/失败/重复计数；`core/cloud_import_batch_test.dart` 单项待获取后有效图继续；IT `gallery_flow_test.dart` 实际 UI 批次。

**缺失项/未验证：** Windows选择器/云来源/撤权实机PT未执行；未知内核读取不保证有界停止，不能提前释放保护。

**必要验证：** UT-008；AT-001、IT-001。UT验证业务判断；真实依赖和流程由其他方案补证。

#### IMP-006 元信息与来源

属性：P1｜V1｜来源 SRC-C1、SRC-C2｜验证 UT、IT

资产必须记录显示名称、实际格式、尺寸、字节数、导入时间、更新时间及来源类型。原始来源引用只用于解释来源，不作为永久可读性的承诺；时间保存须能跨时区解释。

验收：显示大小与已保存副本一致；时区切换不改变导入顺序；无可用外部路径也可保留资产。

**当前状态：** Windows适用软件链已核对；最终运行与验收边界见E34，不代表正式四端条款全部验证通过。

**当前证据：** E34 [逐编号源码审查](validation/windows-library-software-audit.md)：具备。版本写真实格式、方向后的尺寸、字节与帧数，资产/来源写名称、来源类型、UTC 导入/更新时间；永久可用性不依赖外部引用。 测试入口：`core/library_repository_test.dart` UT-009 实际元信息、UTC、稳定排序及 UT-004 来源移除；`core/png_orientation_test.dart` 八方向真实导入尺寸/元信息/原始字节。

**缺失项/未验证：** Windows选择器/云来源/撤权实机PT未执行；未知内核读取不保证有界停止，不能提前释放保护。

**必要验证：** UT-009；IT-001。UT验证业务判断；真实依赖和流程由其他方案补证。

#### IMP-007 权限与获取异常

属性：P0｜V1｜来源 WEB-04、WEB-05、WEB-06｜验证 UT、PT

区分授权拒绝、取消、来源丢失、云资源待获取、暂时不可用和内容损坏。重新授权或重选可恢复获取；这些异常不得清空已保存的整理信息。

验收：部分授权和无网络获取分别给出对应状态；已提交副本不因来源授权变化失效。

**当前状态：** Windows适用软件链已核对；最终运行与验收边界见E34，不代表正式四端条款全部验证通过。

**当前证据：** E34 [逐编号源码审查](validation/windows-library-software-audit.md)：具备 Windows 软件分类。`PlatformResource/ResourceFailure` 区分取消、拒绝、缺失、cloudPending、暂不可用及 invalidImage；`platform/source_readiness.dart::SourceReadinessProbe` 预检普通本地路径，OFFLINE/RECALL_ON_DATA_ACCESS 时不开流；重选不会清整理。 测试入口：`core/cloud_import_batch_test.dart` 分类与下一项；`platform/source_readiness_test.dart` 标志位与路径边界；导入/重开真实副本测试。真实云提供者、授权变化和内核阻塞行为属于 PT 排除，不把预检称全云来源覆盖。

**缺失项/未验证：** Windows选择器/云来源/撤权实机PT未执行；未知内核读取不保证有界停止，不能提前释放保护。

**必要验证：** UT-001、UT-010；PT-001。UT验证业务判断；真实依赖和流程由其他方案补证。

#### IMP-008 可控批量导入

属性：P1｜V1｜来源 SRC-C1、SRC-O｜验证 UT、PT、AT

导入必须支持进度、停止后续获取和最终汇总。桌面可提供拖放与目录选择，移动端采用平台可用入口；目录遍历不得默认跟随循环链接或越过用户授权范围。

验收：取消后不继续提交尚未取得的资源，已成功项保留；不支持拖放的平台仍有完整多选入口。

**当前状态：** Windows适用软件链已核对；最终运行与验收边界见E34，不代表正式四端条款全部验证通过。

**当前证据：** E34 [逐编号源码审查](validation/windows-library-software-audit.md)：具备。批次进度、同一取消令牌、未取得资源停止及最终汇总；`_activeImport` 在取得器前建立，`_exitRequested` 等选择/实际复制清理，不放迟到进度盖掉停止反馈。多选完整，目录/拖放是可选能力。 测试入口：`core/library_repository_test.dart` UT-011 未打开后续源跳过；`import_stop_feedback_test.dart`；`core/import_source_cancellation_test.dart`；`gallery_import_exit_test.dart` 停止、拒绝退出、失败取得器与确认退出等待。

**缺失项/未验证：** Windows选择器/云来源/撤权实机PT未执行；未知内核读取不保证有界停止，不能提前释放保护。

**必要验证：** UT-011；AT-001、PT-001。UT验证业务判断；真实依赖和流程由其他方案补证。

### LIB

#### LIB-001 浏览与可用状态

属性：P0｜V1｜来源 SRC-C1、SRC-U｜验证 UT、PT、AT

资产必须可浏览、预览并查看元信息、本机文件状态和远程结果。缩略图是可再生缓存，不是原图；损坏或缺失时可重新生成或重新关联，不能以空图伪报可用。

验收：删除缩略图不删除原图；本机不可用的资产仍显示整理信息和已有链接。

**当前状态：** Windows适用软件链已核对；最终运行与验收边界见E34，不代表正式四端条款全部验证通过。

**当前证据：** E34 [逐编号源码审查](validation/windows-library-software-audit.md)：具备。桌面卡片/详情显示整理、版本、本机状态和普通远程结果；`AssetPreviewImage` 显示经校验的小图，缺损可重生/重选；原图入口使用永久版本 reader 和 SDK codec，支持动画播放/暂停，不用缩略图冒充。 测试入口：`core/library_repository_test.dart` “thumbnail regenerates after cache removal and does not replace original”；`core/library_organization_test.dart` UT-012 缺损与重开；`gallery/original_preview_reader_test.dart` 摘要与租约；`gallery/original_preview_controller_test.dart` 帧/暂停/关闭；`core/original_preview_orientation_test.dart` 真实 SDK PNG 八方向、JPEG6、WebP6、APNG。

**缺失项/未验证：** 本机SQL/files与widget边界见E34；完整人工AT及参考硬件检索/显示PERF未执行。

**必要验证：** UT-012；AT-001、IT-010、PT-001。UT验证业务判断；真实依赖和流程由其他方案补证。

#### LIB-002 单项与批量选择

属性：P1｜V1｜来源 SRC-C1｜验证 UT、AT

必须支持单项、多项、选中当前筛选结果和清空选择；批量操作显示实际作用数量。筛选变化不得悄悄增加作用对象，执行前可核对选择集。

验收：选中筛选的 5 项后切换条件，不会意外执行在其他未选择资产上。

**当前状态：** Windows适用软件链已核对；最终运行与验收边界见E34，不代表正式四端条款全部验证通过。

**当前证据：** E34 [逐编号源码审查](validation/windows-library-software-audit.md)：具备。UUID 选择集、`_selectMatching` 使用数据库全匹配 UUID；查询变化不增选，批量 `_review` 展示实际对象/数量再执行。 测试入口：`desktop_gallery_test.dart` UT-013/017 当前筛选选择与核对；`gallery_controller_test.dart` 查询代次、旧分页隔离、计数变化首批重读。

**缺失项/未验证：** 本机SQL/files与widget边界见E34；完整人工AT及参考硬件检索/显示PERF未执行。

**必要验证：** UT-013；AT-001。UT验证业务判断；真实依赖和流程由其他方案补证。

#### LIB-003 标签编辑

属性：P1｜V1｜来源 SRC-C1、SRC-O｜验证 UT、AT

标签支持连续输入、增加、移除及批量增删，按共同规则规范化与去重。编辑中的分隔符不被立即吞掉；提交超限或非法值前给出明确原因，不截断用户输入。

验收：逐字输入两个标签可提交；A 与 a 归为同项；51 个标签或 65 字符名称拒绝且不改原值。

**当前状态：** Windows适用软件链已核对；最终运行与验收边界见E34，不代表正式四端条款全部验证通过。

**当前证据：** E34 [逐编号源码审查](validation/windows-library-software-audit.md)：具备。`LibraryOrganizationEditor` 保留连续编辑草稿；`TextPolicy` trim/Unicode17 NFC/完整 folding/再次 NFC，按 scalar 限 1–64、资产标签 ≤50；`updateOrganization` 先全验证再一笔事务，不截断。 测试入口：`desktop_gallery_test.dart` 标签连续输入；`core/library_organization_test.dart` UT-014/015 Unicode、50/51、非法成员使全批回滚。

**缺失项/未验证：** 本机SQL/files与widget边界见E34；完整人工AT及参考硬件检索/显示PERF未执行。

**必要验证：** UT-014、UT-015；AT-001。UT验证业务判断；真实依赖和流程由其他方案补证。

#### LIB-004 分类与收藏

属性：P1｜V1｜来源 SRC-C1｜验证 UT、AT

支持分类赋值、重命名、移除分类及收藏切换；移除分类只使关联资产变为未分类，不删除图片。批量操作保留无关字段。

验收：将 3 项改分类后标签、收藏和远程历史不变；移除分类后仍可检索全部资产。

**当前状态：** Windows适用软件链已核对；最终运行与验收边界见E34，不代表正式四端条款全部验证通过。

**当前证据：** E34 [逐编号源码审查](validation/windows-library-software-audit.md)：具备。`library_organization.dart` 分类 UUID 创建/赋值/重命名/移除、收藏与批量编辑；只修改确认字段，移除分类不删字节。 测试入口：`core/library_organization_test.dart` UT-016 规范化重用、重命名碰撞回滚、移除保留身份/标签/收藏/字节；桌面整理交互测试。

**缺失项/未验证：** 本机SQL/files与widget边界见E34；完整人工AT及参考硬件检索/显示PERF未执行。

**必要验证：** UT-016；AT-001。UT验证业务判断；真实依赖和流程由其他方案补证。

#### LIB-005 组合检索

属性：P1｜V1｜来源 SRC-C1、SRC-O｜验证 UT、AT、PERF

关键词匹配名称、来源显示信息、格式、分类、标签、图床/账号名称和普通远程 URL；多个筛选条件以交集组合。提供本机可用性、收藏、分类、标签及上传结果筛选。

验收：关键词不区分大小写；分类加失败目标筛选只返回同时符合者；秘密字段不进入检索索引。

**当前状态：** Windows适用软件链已核对；最终运行与验收边界见E34，不代表正式四端条款全部验证通过。

**当前证据：** E34 [逐编号源码审查](validation/windows-library-software-audit.md)：具备。仓储 `_matches/_galleryRemotePredicate` 在分页前共同 SQL 计数/查询/全 UUID；本机字段与目标 UUID/服务/输入/结果状态/普通 URL 条件取交集，同条远程记录匹配；先脱敏再折叠检索。 测试入口：`core/library_organization_test.dart` UT-017 本机 AND/Unicode；`core/gallery_remote_query_test.dart` 远程同条记录、失败目标、分页及秘密遮蔽；`gallery_remote_filter_screen_test.dart` 与 IT `gallery_remote_flow_test.dart` 共用筛选入口。

**缺失项/未验证：** 本机SQL/files与widget边界见E34；完整人工AT及参考硬件检索/显示PERF未执行。

**必要验证：** UT-017；AT-001、PERF-001。UT验证业务判断；真实依赖和流程由其他方案补证。

#### LIB-006 确定性排序

属性：P1｜V1｜来源 SRC-C1｜验证 UT、AT

支持按导入时间、最近确认上传时间、名称和大小排序；主排序值相同使用稳定身份作最终顺序。未上传资产的上传时间为空，不按加载时间造值。

验收：重复刷新相同输入顺序一致；无上传结果的资产在最近上传排序末尾。

**当前状态：** Windows适用软件链已核对；最终运行与验收边界见E34，不代表正式四端条款全部验证通过。

**当前证据：** E34 [逐编号源码审查](validation/windows-library-software-audit.md)：具备。`_galleryOrder` 导入/名称/大小/最近真实确认 MAX UTC；无确认时间始终末尾，最终资产 UUID 稳定收尾。 测试入口：`core/library_organization_test.dart` UT-018 跨页/重开同值排序；`core/gallery_remote_query_test.dart` 最近确认、空值两方向末尾。

**缺失项/未验证：** 本机SQL/files与widget边界见E34；完整人工AT及参考硬件检索/显示PERF未执行。

**必要验证：** UT-018；AT-001。UT验证业务判断；真实依赖和流程由其他方案补证。

#### LIB-007 移除与回收

属性：P0｜V1｜来源 SRC-D6、SRC-O｜验证 UT、IT、AT

移除资产只进入本地回收区，默认不删除副本和远程文件；恢复保留整理及历史。30 天到期仅提示可清理，用户未确认时不自动删除记录、远程链接或副本，仍可恢复。永久清除须显示影响并确认；有活跃依赖时阻止或先显式取消依赖。

验收：普通移除不调用图床删除、不改外部原图；回收期恢复后身份和标签不变。

**当前状态：** Windows适用软件链已核对；最终运行与验收边界见E34，不代表正式四端条款全部验证通过。

**当前证据：** E34 [逐编号源码审查](validation/windows-library-software-audit.md)：具备。`library_recycle.dart` 移除只标回收，恢复身份/整理；30 天仅提示；清理计划分别确认记录与字节，持久依赖/实际租约阻止，不调用远端删除。 测试入口：`core/library_recycle_test.dart` UT-019 精确到期仍可恢复、UT-020 分别确认/共享保护/外部来源不动；IT-010 清理日志恢复；`desktop_gallery_test.dart` 明确影响确认。

**缺失项/未验证：** 本机SQL/files与widget边界见E34；完整人工AT及参考硬件检索/显示PERF未执行。

**必要验证：** UT-007、UT-019、UT-020、UT-102；AT-004、IT-010。UT验证业务判断；真实依赖和流程由其他方案补证。

#### LIB-008 文件修复与永久清除

属性：P0｜V1｜来源 SRC-D2、SRC-O｜验证 UT、IT、AT

丢失或损坏的应用副本可通过重导入相同内容修复；不同内容不得冒充原版本。永久清除图片字节与清除记录分别确认，不能删除仍被其他有效资产引用的字节。

验收：错误内容修复被拒绝；共享字节仍有有效引用时不删除；仅删字节时远程链接可继续保留。

**当前状态：** Windows适用软件链已核对；最终运行与验收边界见E34，不代表正式四端条款全部验证通过。

**当前证据：** E34 [逐编号源码审查](validation/windows-library-software-audit.md)：具备。同摘要/字节重导入修复副本保留逻辑身份，不同内容新版本；仅清记录保留独立版本/字节，仅清副本保留整理和普通链接；有效共享引用/使用保护阻止删除或替换。 测试入口：`core/library_repository_test.dart` UT-021；`core/import_recycle_boundary_test.dart` orphan/坏副本修复；`core/library_recycle_test.dart` UT-020/102 实际 IO 未结束保护和 SQL 释放失败收尾。旧 PNG 冻结元信息与“字节修复”分别解释，见文末。

**缺失项/未验证：** 本机SQL/files与widget边界见E34；完整人工AT及参考硬件检索/显示PERF未执行。

**必要验证：** UT-020、UT-021、UT-102；AT-004、IT-001、IT-010。UT验证业务判断；真实依赖和流程由其他方案补证。

### IMG

#### IMG-001 独立且不覆盖

属性：P0｜V1｜来源 SRC-C4、SRC-D4｜验证 UT、IT、AT

压缩、裁剪、拼接可独立使用，无需配置图床。处理读取指定版本并生成新结果，任何成功、失败或取消均不得覆盖输入字节或修改外部原图。

验收：操作前后输入内容一致；输出写入失败不改变原资产。

**当前状态：** Windows适用软件链已核对；最终运行与验收边界见E34，不代表正式四端条款全部验证通过。

**当前证据：** E34 [逐编号源码审查](validation/windows-library-software-audit.md)：具备。工作台不依赖账号；`ProcessingCoordinator/ImageProcessor` 读取指定版本、独立独占输出，不写输入，取消等实际 isolate 收尾。 测试入口：`processing/image_processor_test.dart` UT-022 输入摘要成功/失败/取消不变、输出拒绝；IT `processing_flow_test.dart` 真实工作台处理。

**缺失项/未验证：** Windows实际SDK与像素测试范围见E34；四端格式设备契约、真实内存压力与性能额度未验证。

**必要验证：** UT-022；AT-002、IT-002。UT验证业务判断；真实依赖和流程由其他方案补证。

#### IMG-002 保真优先

属性：P0｜V1｜来源 SRC-D4、SRC-O｜验证 UT、IT

保真优先默认不缩小、不丢透明、不丢动画，不承诺一定减小体积。无法保持输入特征的处理必须停止并提示可选原图上传或明确的转换；不自动退回有损处理。

验收：透明 PNG 不自动变不透明 JPEG；动画处理能力不足时保持原图或等待用户选择，不能输出单帧并报保真成功。

**当前状态：** Windows适用软件链已核对；最终运行与验收边界见E34，不代表正式四端条款全部验证通过。

**当前证据：** E34 [逐编号源码审查](validation/windows-library-software-audit.md)：具备。默认 fidelity 保持尺寸/透明，动画无法保真时拒绝并要求显式静态选帧；JPEG/不透明转换先确认背景；真实结果提示有损/特征变化及可能增大，无自动有损回退。 测试入口：`processing/image_processor_test.dart` UT-023/027、颜色 ICC/cICP 保留/未知色彩拒绝；`processing/processing_workbench_test.dart` 动画选择、透明背景确认、实际失败反馈。不承诺动画重编码。

**缺失项/未验证：** Windows实际SDK与像素测试范围见E34；四端格式设备契约、真实内存压力与性能额度未验证。

**必要验证：** UT-023；CT-004、IT-002。UT验证业务判断；真实依赖和流程由其他方案补证。

#### IMG-003 体积优先

属性：P1｜V1｜来源 SRC-C4、SRC-O｜验证 UT、IT、AT

允许控制最长边、输出格式和质量策略，默认最长边 1600，合法范围为整数 1–16384 像素，不放大小图；极端尺寸仍受资源预算约束。JPEG/静态 WebP 的质量策略默认 85，取整数 1–100，表示编码器质量参数，不等于保真百分比；PNG 不提供无效的有损质量参数。缩小后尺寸采用等比例计算并四舍五入至整数，最小 1 像素。提供处理前后格式、尺寸与体积比较；输出更大或损失特征时不伪报压缩收益。

验收：800 像素图片不放大；4000 像素图片保持比例缩小；体积变大明确提示。

**当前状态：** Windows适用软件链已核对；最终运行与验收边界见E34，不代表正式四端条款全部验证通过。

**当前证据：** E34 [逐编号源码审查](validation/windows-library-software-audit.md)：具备。`fitLongestSide` BigInt 比例四舍五入最小1且不放大，最长边1–16384；JPEG/WebP质量1–100默认85，PNG无无效质量；输出读实际尺寸/字节比较。 测试入口：`processing/image_processor_test.dart` UT-024/025 极端/比例/小图/格式质量；`processing/processing_workbench_test.dart` 默认策略、真实前后比较及更大输出提示。

**缺失项/未验证：** Windows实际SDK与像素测试范围见E34；四端格式设备契约、真实内存压力与性能额度未验证。

**必要验证：** UT-024、UT-025；AT-002、CT-004、IT-002。UT验证业务判断；真实依赖和流程由其他方案补证。

#### IMG-004 格式与特殊特征

属性：P0｜V1｜来源 SRC-C4、SRC-O｜验证 UT、IT

首版必须对静态 PNG、JPEG、WebP、GIF、BMP 提供压缩、裁剪和拼接；处理输出至少支持 PNG、JPEG、静态 WebP，不要求重新编码 GIF 或 BMP。动画 GIF/动画 WebP 必须支持导入、动画播放预览和原样上传，支持暂停预览；裁剪拼接转静态图仅在显式选帧确认后执行，不承诺动画重新编码。保真模式不能满足输入特征时按 IMG-002 停止或采用经用户选择的原图。透明度丢弃必须确认背景颜色，默认白色。

验收：未知或不支持的转换在执行前拒绝；动画转静态与透明转不透明均有确定的用户选择记录。

**当前状态：** Windows适用软件链已核对；最终运行与验收边界见E34，不代表正式四端条款全部验证通过。

**当前证据：** E34 [逐编号源码审查](validation/windows-library-software-audit.md)：具备。共同解码五输入，三个输出编码器，压缩/裁剪/拼接共用同一已定向像素入口；动画原图 SDK 播放暂停，处理必须明确确认真实帧和静态转换；透明丢弃须背景确认。原样上传走受保护真实输入流而非改图。 测试入口：`processing/image_processor_test.dart` 实际5×3静态压缩矩阵、动画特征/选帧/背景；`core/png_orientation_test.dart` APNG准确帧缩略图/裁剪；`gallery/original_preview_controller_test.dart` 动画；`core/original_preview_orientation_test.dart` 两帧APNG像素/时长/循环；上传 adapter/coordinator 受控流测试。裁剪/拼接格式矩阵部分证据来自共同生产入口，不能说每种组合均已单独实测。

**缺失项/未验证：** Windows实际SDK与像素测试范围见E34；四端格式设备契约、真实内存压力与性能额度未验证。

**必要验证：** UT-023、UT-026、UT-027；CT-004、IT-002。UT验证业务判断；真实依赖和流程由其他方案补证。

#### IMG-005 方向与元数据

属性：P0｜V1｜来源 SRC-D1、SRC-O｜验证 UT、IT

展示与处理采用正确视觉方向，处理结果避免方向标记重复旋转。默认上传副本去除位置和设备识别等隐私元数据；关闭隐私处理需用户显式选择；原样字节上传须说明可能保留元数据。

验收：带方向标记的样例显示及裁剪位置一致；隐私处理默认输出不含定位字段，原始副本不被修改。

**当前状态：** Windows适用软件链已核对；最终运行与验收边界见E34，不代表正式四端条款全部验证通过。

**当前证据：** E34 [逐编号源码审查](validation/windows-library-software-audit.md)：新导入具备。`readPngOrientation` 共同解析真实 eXIf，严格边界/CRC/唯一/方向字段校验；Inspector 元信息/准确帧缩略图、Processor、SDK预览一致。`bakeImageOrientation` 方向3使用 copyRotate180，避免第三方奇数中央行错误；JPEG decoder已定向不二次bake，其他方向只应用一次。`MetadataPolicy` 白名单色彩/隐私去除，输出方向1；原始上传需隐私确认。旧错误冻结 PNG 安全保护限制见文末。 测试入口：`core/png_orientation_test.dart` 1–8全像素导入/尺寸/缩略图/压缩/裁剪/拼接，奇数宽高矩阵、重复/坏eXIf、原字节不变及 frozen inputChanged；`core/original_preview_orientation_test.dart` 真SDK PNG1–8/JPEG6/WebP6/APNG方向3/6；`processing/image_processor_test.dart` ICC色彩/隐私字段保护。

**缺失项/未验证：** Windows实际SDK与像素测试范围见E34；四端格式设备契约、真实内存压力与性能额度未验证。

**必要验证：** UT-028；CT-004、IT-002。UT验证业务判断；真实依赖和流程由其他方案补证。

#### IMG-006 裁剪规则

属性：P1｜V1｜来源 SRC-C4、SRC-O｜验证 UT、IT、AT

用户以可理解的区域确认裁剪，支持预览与调整。最终裁剪区域按已应用方向后的像素坐标定义，坐标、宽高均为整数，宽高至少 1 像素且在图内；确认前将交互区域转换为可核对的整数像素区域。正式输入中的小数、非法、非有限或越界区域拒绝执行，不静默修成意外区域。

验收：全图区域有效；零宽、负坐标、越界及非有限值均拒绝；输出尺寸等于确认区域。

**当前状态：** Windows适用软件链已核对；最终运行与验收边界见E34，不代表正式四端条款全部验证通过。

**当前证据：** E34 [逐编号源码审查](validation/windows-library-software-audit.md)：具备。工作台区域预览及明确整数确认；`PixelCrop/fromSnapshot` 拒绝小数/非有限/零宽/负值/越界；正式坐标在方向后图像上应用，非静默修正。 测试入口：`processing/image_processor_test.dart` UT-029 边界与方向JPEG6；`core/png_orientation_test.dart` 1–8实际定向坐标裁剪全像素；工作台错误小数改整数后确认。

**缺失项/未验证：** Windows实际SDK与像素测试范围见E34；四端格式设备契约、真实内存压力与性能额度未验证。

**必要验证：** UT-029；AT-002、IT-002。UT验证业务判断；真实依赖和流程由其他方案补证。

#### IMG-007 拼接顺序与布局

属性：P1｜V1｜来源 SRC-C4、SRC-D4、SRC-O｜验证 UT、IT、AT

至少两张图片可按用户确认的顺序拼接。两张支持横向和纵向，多张支持接近正方形网格；缺省不缩放输入，按方向正确后的实际像素尺寸布局，不裁掉内容。间距默认 0，取整数 0–1024 像素；背景默认白色，可选择透明或指定颜色，转不透明格式仍须确认。横向画布宽为各图宽之和加间距、高为最大图高，各图垂直居中；纵向反之并水平居中。网格列数缺省为向上取整平方根，行数为数量除列数向上取整，单元格为最大输入宽高，各图居中，单元格之间使用确认间距。过大画布按 IMG-008 处理。

居中偏移按剩余像素除以 2 向下取整，多余的单个像素留在右侧或下侧。

验收：调整输入顺序改变对应位置；3 张为 2 列 2 行，空格使用确认背景，不被计为第四张图片；奇数空余像素时偏移有唯一结果。

**当前状态：** Windows适用软件链已核对；最终运行与验收边界见E34，不代表正式四端条款全部验证通过。

**当前证据：** E34 [逐编号源码审查](validation/windows-library-software-audit.md)：具备。工作台改顺序撤销旧确认，冻结实际输入顺序；处理 plan 实现横纵/ceil-sqrt网格、最大单元格、间距0–1024、不缩放、剩余/2向下取整居中及空格背景。 测试入口：`processing/image_processor_test.dart` UT-030/031 横纵/顺序/三图空格/奇数余量/透明；工作台显式确认顺序；`core/png_orientation_test.dart` 八方向拼接像素不二次旋转。

**缺失项/未验证：** Windows实际SDK与像素测试范围见E34；四端格式设备契约、真实内存压力与性能额度未验证。

**必要验证：** UT-030、UT-031；AT-002、IT-002。UT验证业务判断；真实依赖和流程由其他方案补证。

#### IMG-008 处理资源预算

属性：P0｜V1｜来源 SRC-C4、SRC-O｜验证 UT、IT、PERF

处理前估算输入、输出像素及中间结果的资源需求，采用平台报告的有效预算。超过预算不得开始分配巨大画布，应提供降低尺寸、减少输入或取消选项；预算判断不只看压缩文件字节数。

验收：超预算样例在执行前拒绝；调整至预算内可执行；失败不生成有效输出或占用永久记录。

**当前状态：** Windows适用软件链已核对；最终运行与验收边界见E34，不代表正式四端条款全部验证通过。

**当前证据：** E34 [逐编号源码审查](validation/windows-library-software-audit.md)：具备软件防护。plan BigInt 估算输入帧、输出画布、解码/方向/中间及编码缓冲，预算前拒绝大画布；worker再核字节/摘要/header；Scheduler 按实际保护与冻结预算分配，系统压力降低新派发。UI提示降低尺寸/减少输入。 测试入口：`processing/image_processor_test.dart` UT-032 分配前预算拒绝；`core/processing_scheduler_test.dart` FIFO/预算/取消；`core/processing_memory_pressure_test.dart` 旧预算不变/真实释放后派发。候选额度性能非硬件实测。

**缺失项/未验证：** Windows实际SDK与像素测试范围见E34；四端格式设备契约、真实内存压力与性能额度未验证。

**必要验证：** UT-032；CT-004、IT-002、PERF-003。UT验证业务判断；真实依赖和流程由其他方案补证。

#### IMG-009 参数快照与批量处理

属性：P1｜V1｜来源 SRC-C1、SRC-O｜验证 UT、IT、AT

独立压缩支持多项批次；裁剪首版按单项确认，拼接按一组确认。任务使用创建时的输入、顺序和策略快照；随后改变设置不改变任务。取消与单项失败独立收尾。

验收：开始后调整默认质量不影响既有任务；批量压缩一个失败，其他项目仍完成并有汇总。

**当前状态：** Windows适用软件链已核对；最终运行与验收边界见E34，不代表正式四端条款全部验证通过。

**当前证据：** E34 [逐编号源码审查](validation/windows-library-software-audit.md)：具备。`_Draft`/`ProcessingRequest` 冻结版本、帧、顺序、策略、保留期；独立压缩逐项收尾，裁剪单项/拼接一组；既有任务不读后改默认值。上传处理依赖也冻结同一参数、不得原图回退。 测试入口：`processing/image_processor_test.dart` UT-033 参数快照/独立失败取消；`processing/processing_workbench_test.dart` 批次汇总；`core/upload_processing_*_test.dart` 冻结job、依赖输出校验/重开。

**缺失项/未验证：** Windows实际SDK与像素测试范围见E34；四端格式设备契约、真实内存压力与性能额度未验证。

**必要验证：** UT-033；AT-002、IT-003。UT验证业务判断；真实依赖和流程由其他方案补证。

### OUT

#### OUT-001 临时输出记录

属性：P1｜V1｜来源 SRC-C1、SRC-C4｜验证 UT、IT

有效输出必须记录实际文件状态、格式、尺寸、体积、来源版本、操作及参数、创建与到期时间；重启后恢复仍存在的临时结果。缺失文件不能继续显示为可操作输出。

验收：重启后未到期结果仍可见；来源关系能说明上传用了哪份结果。

**当前状态：** Windows适用软件链已核对；最终运行与验收边界见E34，不代表正式四端条款全部验证通过。

**当前证据：** E34 [逐编号源码审查](validation/windows-library-software-audit.md)：具备。`library_outputs.dart::beginOutput/confirmOutput/_output/_recoverOutputs` 持久 writing/prepared/ready/failed/cancelled/deleting，实际文件摘要/格式/尺寸/来源参数/UTC到期；缺失或坏文件不作为usable操作输出。 测试入口：`processing/output_lifecycle_test.dart` UT-034 状态/重开/各提交边界；IT `processing_flow_test.dart` 真实结果重开；`processing/output_preview_reader_test.dart` 租约/摘要。

**缺失项/未验证：** Windows实际导出IO已接入，系统选框PT未执行；Android原生导出及API36模拟器证据见E35；iOS仍未接入且禁用，不记Windows缺口。

**必要验证：** UT-034；IT-003。UT验证业务判断；真实依赖和流程由其他方案补证。

#### OUT-002 永久保存与入库

属性：P0｜V1｜来源 SRC-C1、SRC-O、SRC-U｜验证 UT、IT、AT

用户可将选定临时输出保存到永久图库。必须在永久字节与记录校验提交后才报成功，保留来源关系；临时文件删除后永久副本仍有效。

验收：保存后执行全部过期清理，入库结果可预览和再上传；保存失败不伪造永久记录。

**当前状态：** Windows适用软件链已核对；最终运行与验收边界见E34，不代表正式四端条款全部验证通过。

**当前证据：** E34 [逐编号源码审查](validation/windows-library-software-audit.md)：具备。`saveOutput` 复用永久导入日志，`_commitOutputSave` 同关联事务保存 `SavedOutputOrigins`，最终提交后成功；永久副本与临时文件生命周期独立。 测试入口：`processing/output_lifecycle_test.dart` UT-035 保存失败、去重、来源、清临时后永久可读；IT `processing_flow_test.dart` 真实工作台保存/重开。

**缺失项/未验证：** Windows实际导出IO已接入，系统选框PT未执行；Android原生导出及API36模拟器证据见E35；iOS仍未接入且禁用，不记Windows缺口。

**必要验证：** UT-035；AT-002、IT-003。UT验证业务判断；真实依赖和流程由其他方案补证。

#### OUT-003 输出导出

属性：P1｜V1｜来源 SRC-O｜验证 UT、IT、PT、AT

可将单个或批量结果导出到平台允许的位置；明确名称冲突并默认生成新名称，不覆盖既有文件。取消或失败逐项报告，导出不自动删除应用内副本。

验收：同名目标未确认覆盖时内容不变；移动端授权失败给恢复入口；批量导出结果数量准确。

**当前状态：** Windows适用软件链已核对；最终运行与验收边界见E34，不代表正式四端条款全部验证通过。

**当前证据：** E34 [逐编号源码审查](validation/windows-library-software-audit.md)：具备 Windows 导出。目录取得器→共同 `FileExporter` 流式独占创建、关闭/摘要校验，同名生成新名；每项取消/失败独立报告，不删除应用副本。 测试入口：`processing/file_exporter_test.dart` UT-036 同名/并发冲突/权限/取消/来源变化/链接边界；IT `processing_flow_test.dart` fixture目录取得器后实际文件IO与原内容。真实系统选框 PT 排除；Android原生导出证据见E35；iOS未接入不计Windows缺口。

**缺失项/未验证：** Windows实际导出IO已接入，系统选框PT未执行；Android原生导出及API36模拟器证据见E35；iOS仍未接入且禁用，不记Windows缺口。

**必要验证：** UT-036；AT-002、IT-003、PT-003。UT验证业务判断；真实依赖和流程由其他方案补证。

#### OUT-004 安全清理

属性：P0｜V1｜来源 SRC-D4、SRC-O｜验证 UT、IT

到期临时文件在应用启动和可运行期间尝试清理，不能承诺系统限制下准时执行。仅清理到期且无永久引用、无活跃任务依赖的结果；手动清理也适用保护规则，失败可重试。

验收：恰好到期的无保护项可清理；到期保护项保留；只移除实际清理成功的记录。

**当前状态：** Windows适用软件链已核对；最终运行与验收边界见E34，不代表正式四端条款全部验证通过。

**当前证据：** E34 [逐编号源码审查](validation/windows-library-software-audit.md)：具备。启动及可运行每分钟 `_maintainOutputs/cleanupOutputs` 仅选到期无保护项，writer重验永久/任务/保存/租约，成功删文件后移记录；失败保留重试，无后台准时承诺。 测试入口：`processing/output_lifecycle_test.dart` UT-037 恰到期/删除失败、UT-038六状态依赖；`processing/output_preview_reader_test.dart` 实际线程未结束保护；SQL租约释放失败测试排空进程等待但留保护。

**缺失项/未验证：** Windows实际导出IO已接入，系统选框PT未执行；Android原生导出及API36模拟器证据见E35；iOS仍未接入且禁用，不记Windows缺口。

**必要验证：** UT-037、UT-038、UT-088、UT-102；IT-003。UT验证业务判断；真实依赖和流程由其他方案补证。

#### OUT-005 输出失败与收益反馈

属性：P1｜V1｜来源 SRC-C1、SRC-O｜验证 UT、IT、AT

处理失败、取消、尚在写入和成功结果必须区分；半成品不进入预览、图库或上传。结果提供前后尺寸与大小，无法准确预估时注明，不能用固定假数据表示收益。

验收：编码中断不产生成功结果；体积比较可由真实字节数复算。

**当前状态：** Windows适用软件链已核对；最终运行与验收边界见E34，不代表正式四端条款全部验证通过。

**当前证据：** E34 [逐编号源码审查](validation/windows-library-software-audit.md)：具备。结果状态、错误、取消与半成品分别反馈，非ready不可保存/预览/上传；真实before/after格式尺寸字节与特征变化/负收益，无固定样本。 测试入口：`processing/output_lifecycle_test.dart` UT-034；`processing/processing_workbench_test.dart` 实际失败禁操作/负收益；`processing/output_preview_test.dart` 与reader测试验证真实预览小图、租约/预算/关闭。

**缺失项/未验证：** Windows实际导出IO已接入，系统选框PT未执行；Android原生导出及API36模拟器证据见E35；iOS仍未接入且禁用，不记Windows缺口。

**必要验证：** UT-034；AT-002、IT-003。UT验证业务判断；真实依赖和流程由其他方案补证。

### ACC

#### ACC-001 初始图床与能力

属性：P0｜V1｜来源 SRC-C5、SRC-D3、WEB-01、WEB-02、WEB-03｜验证 UT、CT、AT

首版支持 Catbox 和 ImgBB。每个平台必须说明支持的文件、上传方式、认证、限制、续传及删除能力；未知能力视为不支持，不能从品牌名称推断。已配置不等于健康可用。

验收：不支持的操作不能作为可用动作；平台限制未知时不虚构数值或无限容量。

**当前状态：** Windows适用软件链已核对；最终运行与验收边界见E34，不代表正式四端条款全部验证通过。

**当前证据：** E34 [逐编号源码审查](validation/windows-network-software-audit.md)：**具备，生产能力保护生效。** `accounts/domain/account_models.dart: ProviderInformation.values` 提供两家账号上传资料；`gallery/presentation/gallery_providers.dart: LibrarySession.uploads` 注入真正 `CatboxAdapter`/`ImgBBAdapter`；`upload/data/provider_adapters.dart` 固定 HTTPS multipart。未知 limits 在协调器派发前等待，适配器也拒绝。匿名已移出产品。 测试入口：`core/accounts_repository_test.dart` UT-039；`core/provider_adapters_test.dart` UT-047 的两家默认 unknown、格式独立限额、非法限额与实际文件校验。真实 API CT 排除，不能据注入 limits 开启生产。

**缺失项/未验证：** 按最新决定移除匿名，仅支持两家账号；真实账号有效性/服务契约未验证，精确能力unknown仍禁止生产派发。

**必要验证：** UT-039；AT-003、CT-001。UT验证业务判断；真实依赖和流程由其他方案补证。

#### ACC-002 多账号与匿名目标

属性：P1｜V1｜来源 SRC-D3、SRC-U、SRC-O｜验证 UT、AT

同平台可添加多个独立账号，具有稳定身份、显示名称、启用状态和凭据引用；Catbox 另支持匿名目标。账号显示名称允许重复，稳定身份不因重命名、停用或删除后重新添加而复用；目标展示服务、别名及非秘密的身份区分标记。同名账号和匿名目标仍独立，不同账号凭据和任务结果不能串用。

验收：同平台两个同名账号可辨别地选择并各产生独立上传结果；删除后新增同名账号使用新身份，不继承旧账号任务或秘密；匿名目标不要求伪造 userhash。

**当前状态：** Windows适用软件链已核对；最终运行与验收边界见E34，不代表正式四端条款全部验证通过。

**当前证据：** E34 [逐编号源码审查](validation/windows-network-software-audit.md)：**具备，按最新范围。** `library_accounts.dart: saveTarget/_target` UUID 独立于别名，同名可重复；UI 显示服务、别名与 identityMarker。创建匿名及编辑遗留匿名在凭据登记/写入前拒绝；遗留行有效 enabled/default 为 false，原行身份保留。 测试入口：`core/accounts_repository_test.dart` UT-040；`core/account_target_scope_test.dart` 匿名创建/编辑无秘密写入、旧行保持；`account_target_scope_screen_test.dart` 遗留目标只有本地移除、新建对话框无匿名选项；适配器同别名账号秘密隔离。

**缺失项/未验证：** 按最新决定移除匿名，仅支持两家账号；真实账号有效性/服务契约未验证，精确能力unknown仍禁止生产派发。

**必要验证：** UT-040；AT-003。UT验证业务判断；真实依赖和流程由其他方案补证。

#### ACC-003 配置验证与状态

属性：P0｜V1｜来源 SRC-C1、SRC-D3、SRC-O｜验证 UT、CT、AT

必填凭据和格式先做本地校验；有无副作用的官方验证能力时可检测，不存在时显示未验证而不是健康。不得为了验证凭据自动上传图片。状态区分未配置、未验证、可用、授权失效及暂时不可用。

验收：空 ImgBB Key 拒绝该目标；其他有效目标仍可创建任务；无健康接口不显示已验证。

**当前状态：** Windows适用软件链已核对；最终运行与验收边界见E34，不代表正式四端条款全部验证通过。

**当前证据：** E34 [逐编号源码审查](validation/windows-network-software-audit.md)：**具备。** `saveTarget/_resolveTarget` 本地验证必填凭据；保存策略明确选择系统保存或本次会话。配置不自动试上传。`library_accounts.dart` 健康读取与 `library_uploads.dart` 普通确认观察只更新同 UUID/凭据代次的有效证据；无结果显示未验证，重开缺会话凭据显示未配置。 测试入口：`core/accounts_repository_test.dart` UT-041；`core/account_health_observation_test.dart` 成功/明确失败、unknown 不观察、旧代次/旧 epoch/已移除/同名新目标隔离、新开始顺序拒绝旧晚到确认。真实凭据有效性不在本轮证明范围。

**缺失项/未验证：** 按最新决定移除匿名，仅支持两家账号；真实账号有效性/服务契约未验证，精确能力unknown仍禁止生产派发。

**必要验证：** UT-041；AT-003、CT-001。UT验证业务判断；真实依赖和流程由其他方案补证。

#### ACC-004 目标选择与默认

属性：P1｜V1｜来源 SRC-D3、SRC-O｜验证 UT、AT

启用账号只是进入可选集合；每次上传可选择一个或多个账号，默认选择可配置并允许核对。未选择目标不能收到上传，新增启用账号不追溯加入既有批次。

验收：启用 3 个账号但选择 1 个，仅产生该账号任务。

**当前状态：** Windows适用软件链已核对；最终运行与验收边界见E34，不代表正式四端条款全部验证通过。

**当前证据：** E34 [逐编号源码审查](validation/windows-network-software-audit.md)：**具备。** `accounts_screen.dart` 默认开关、`library_settings.dart: loadSettings/saveSettings` 同事务保存默认目标；上传页只提交用户核对的 UUID 集合，入队冻结目标。匿名有效默认为 false，显式默认选择也拒绝；后来新增/改名不改旧批次。 测试入口：`core/accounts_repository_test.dart` UT-042；`core/settings_repository_test.dart` 默认快照与失效校验；`core/account_target_scope_test.dart` 匿名默认拒绝；`upload_tasks_screen_test.dart` 多目标 UUID/入队快照。

**缺失项/未验证：** 按最新决定移除匿名，仅支持两家账号；真实账号有效性/服务契约未验证，精确能力unknown仍禁止生产派发。

**必要验证：** UT-042；AT-003。UT验证业务判断；真实依赖和流程由其他方案补证。

#### ACC-005 账号变更与移除

属性：P0｜V1｜来源 SRC-D2、SRC-O｜验证 UT、IT、AT

每次实际请求派发时解析目标账号当前有效凭据，包括更新前已创建但尚未派发的任务；目标身份不变，不将秘密固化到任务或历史。凭据缺失时进入授权条件等待。停用或删除账号时说明受影响任务、阻止后续请求并尽力停止在途请求；晚到结果按 QUE-004 留存。删除账号配置必须保留去敏的稳定目标身份、历史名称快照与普通远程 URL，除非用户另外按 UPL-007 显式清理远程结果记录；新增同名账号不继承旧账号身份、任务或秘密。

验收：更新后尚未派发项使用新凭据；删除账号清除秘密，历史身份、名称快照和普通远程 URL 保留，不自动请求远端删除；已创建任务不得绕过停用状态继续派发，也不得转交新同名账号。

**当前状态：** Windows适用软件链已核对；最终运行与验收边界见E34，不代表正式四端条款全部验证通过。

**当前证据：** E34 [逐编号源码审查](validation/windows-network-software-audit.md)：**具备。** `accounts_screen.dart: _performSave/_confirmRemove/_confirmImpact` 停用启用中的目标或移除前异步读影响并独立确认；`library_accounts.dart: targetUploadImpact` 在 `_serial` 按 target_id 统计发布项，返回 UUID、待执行/运行/unknown，终态不计。查询失败不报零、不修改；取消保留草稿。`saveTarget/removeTarget` writer 串行及凭据日志先阻止新派发，协调器 accountChanges 按同 UUID 尽力停止旧在途授权；`beginUploadAttempt/authorizeUploadRequest` 重解析当前凭据、代次和状态。历史快照/普通 URL 不删。 测试入口：`core/account_target_scope_test.dart` 同名不同 UUID、三类计数、终态排除、无尝试/租约/秘密副作用、无效/移除 ID 拒绝；`account_target_scope_screen_test.dart` 停用/移除分别取消与读取失败；`core/upload_coordinator_test.dart` UT-043 最后授权门；`core/accounts_repository_test.dart` UT-043/095 更新/删除恢复日志。确认窗口与退出见专项审查。

**缺失项/未验证：** 按最新决定移除匿名，仅支持两家账号；真实账号有效性/服务契约未验证，精确能力unknown仍禁止生产派发。

**必要验证：** UT-043、UT-095；AT-003、AT-004、CT-003、IT-007。UT验证业务判断；真实依赖和流程由其他方案补证。

#### ACC-006 平台资料维护

属性：P1｜V1｜来源 SRC-D3、SRC-S1、WEB-01、WEB-02、WEB-03｜验证 CT、REV

每个平台有官方来源、核查日期和应用实际支持能力记录；限制与条款变更可更新且不伪称旧历史结果仍有永久保障。首次使用可查阅服务限制及第三方数据去向。

验收：Catbox 匿名保留规则与账号上传分别说明；不将无期限表述当作应用备份承诺。

**当前状态：** Windows适用软件链已核对；最终运行与验收边界见E34，不代表正式四端条款全部验证通过。

**当前证据：** E34 [逐编号源码审查](validation/windows-network-software-audit.md)：**具备资料入口，契约证据未扩大。** `ProviderInformation` 给官方 URL、2026-10-07 核查日期、文件 multipart/认证/限制/续传/管理能力及第三方去向；账号页展示，上传页解释能力等待。Catbox 说明账号上传与既有匿名历史，不能保证永久；ImgBB 管理链接与通用删除 API 分开。 测试入口：`core/accounts_repository_test.dart` UT-039；[provider-contract-evidence.md](provider-contract-evidence.md) 保留官方公开资料证据等级与缺失契约。没有把网页阈值推断为 API 服务器保证。

**缺失项/未验证：** 按最新决定移除匿名，仅支持两家账号；真实账号有效性/服务契约未验证，精确能力unknown仍禁止生产派发。

**必要验证：** UT-039；CT-001、REV-001。UT验证业务判断；真实依赖和流程由其他方案补证。

### UPL

#### UPL-001 输入与策略快照

属性：P0｜V1｜来源 SRC-C1、SRC-O｜验证 UT、IT

每个上传任务绑定确定的图片版本、选定目标、处理与隐私策略和创建时间。批次创建时冻结选定目标的稳定身份、服务与账号别名的去敏显示快照；之后改名只影响新批次，不改写既有发布项。实际派发仍按 ACC-005 解析该稳定账号当前有效凭据，显示快照不含秘密。任务开始前检查本机字节可用，不从可变的全局默认值重新解释输入。

验收：编辑分类、默认账号、账号别名或处理设置不改变既有任务及目标显示快照；新批次使用新别名，已创建未派发项使用当前有效凭据；失效源进入可恢复错误。

**当前状态：** Windows适用软件链已核对；最终运行与验收边界见E34，不代表正式四端条款全部验证通过。

**当前证据：** E34 [逐编号源码审查](validation/windows-network-software-audit.md)：**具备。** `upload_tasks_screen.dart: _enqueue` 提交幂等 intent；`library_uploads.dart: enqueueUploads` 冻结真实版本 SHA/字节数、输入类型、目标 UUID/服务/别名、隐私和策略；`_uploadInputFile/beginUploadAttempt` 派发前重新校验真实永久副本或确认输出，不重新解释全局默认。原图需明确隐私确认。 测试入口：`core/upload_repository_test.dart` UT-044/048 冻结与重新派发当前凭据、失效来源；`upload_tasks_screen_test.dart` UT-094 意图/原图隐私/重开；`upload_flow_test.dart` 本机 Drift/文件/受控 transport，非真实图床。

**缺失项/未验证：** 真实图床与真实账号CT/IT未执行；未知精确能力不派发，发出后无可靠确认仍unknown，不据受控传输宣称生产上传可用。

**必要验证：** UT-033、UT-043、UT-044、UT-048；AT-003、IT-004。UT验证业务判断；真实依赖和流程由其他方案补证。

#### UPL-002 多目标隔离

属性：P0｜V1｜来源 SRC-C1、SRC-D3、SRC-O｜验证 UT、CT

每个图片版本与目标独立完成；一个目标的认证、额度或网络错误不阻断无依赖目标。批次总体按 8.2 的确定规则聚合，与回调顺序无关；计数以批次创建的发布项为单位，不把自动重试尝试或晚到独立结果增加为新发布项。

验收：同一结果集合以任意完成顺序处理，总体结果一致。

**当前状态：** Windows适用软件链已核对；最终运行与验收边界见E34，不代表正式四端条款全部验证通过。

**当前证据：** E34 [逐编号源码审查](validation/windows-network-software-audit.md)：**具备。** 每版本×目标有独立 publication，尝试和结果独立；`UploadCoordinator._pump/_execute` 独立运行和提交，`queue_policy.dart` 集合聚合与五计数不按回调累计成功。没有按别名或相同 URL 合并账号身份。 测试入口：`core/queue_policy_test.dart` UT-045/065 集合聚合；`core/upload_repository_test.dart` 多目标独立结果；适配器 UT-041/045 同别名账号；`upload_flow_test.dart` 受控混合结果。

**缺失项/未验证：** 真实图床与真实账号CT/IT未执行；未知精确能力不派发，发出后无可靠确认仍unknown，不据受控传输宣称生产上传可用。

**必要验证：** UT-045、UT-056、UT-065；CT-002、IT-008。UT验证业务判断；真实依赖和流程由其他方案补证。

#### UPL-003 上传前处理依赖

属性：P0｜V1｜来源 SRC-C1、SRC-D4、SRC-O｜验证 UT、IT

同一版本同一处理策略在批次内复用已确认输出；输出失败只影响相关上传。默认不偷偷改用原图；用户可明确选择原图重建任务。就绪项可上传，不必等待全部图片处理完成。

验收：一项处理失败，其依赖显示跳过原因，其他就绪项继续；没有永久等待任务。

**当前状态：** Windows适用软件链已核对；最终运行与验收边界见E34，不代表正式四端条款全部验证通过。

**当前证据：** E34 [逐编号源码审查](validation/windows-network-software-audit.md)：**具备。** `UploadProcessingCoordinator` 独立本地 actor；`library_upload_processing.dart` 持久 schema10 job/冻结处理计划、同批次共享像素工作、只有校验 ready 输出才关联 processed 输入。失败仅结束依赖项，paused 项继续时合法处理失败；来源缺失明确等待修复/重试，没有原图 fallback；就绪项不等待全批。 测试入口：`core/upload_processing_repository_test.dart` UT-046/062/066 实际像素输出、共享目标、失败隔离、处理 receipt 复用/显式重建、unknown 阻止重执行、实际引用保护；`upload_processing_screen_test.dart` 与 `upload_processing_flow_test.dart`。硬件性能排除。

**缺失项/未验证：** 真实图床与真实账号CT/IT未执行；未知精确能力不派发，发出后无可靠确认仍unknown，不据受控传输宣称生产上传可用。

**必要验证：** UT-046；IT-004。UT验证业务判断；真实依赖和流程由其他方案补证。

#### UPL-004 上传前限制校验

属性：P0｜V1｜来源 SRC-D3、WEB-01、WEB-02、WEB-03｜验证 UT、CT

按实际输出字节和目标能力校验格式、体积、认证及必要条件，不能只检查原图。明确超限时拒绝该目标并给出处理或换目标选择，不自行分片伪装支持。

验收：原图超限但确认输出合规时可上传；实际输出仍超限则不发请求。

**当前状态：** Windows适用软件链已核对；最终运行与验收边界见E34，不代表正式四端条款全部验证通过。

**当前证据：** E34 [逐编号源码审查](validation/windows-network-software-audit.md)：**具备校验，精确服务契约待证。** `_pump` 在 attempt/lease 前拒绝 unknown limits；适配器按真实输出长度/格式、全局与 formatMaximumBytes 取小值、认证和取消校验，超限不读流/不派发。不存在分片或原图替换。 测试入口：`core/provider_adapters_test.dart` UT-047 实际 size/format/missing/credential、GIF 独立 fixture 限额、不可变快照；`core/upload_coordinator_test.dart` unknown 能力无 attempt/lease。服务精确阈值不是这些夹具的证明。

**缺失项/未验证：** 真实图床与真实账号CT/IT未执行；未知精确能力不派发，发出后无可靠确认仍unknown，不据受控传输宣称生产上传可用。

**必要验证：** UT-047；CT-001、CT-002、IT-008。UT验证业务判断；真实依赖和流程由其他方案补证。

#### UPL-005 成功结果与版本关联

属性：P0｜V1｜来源 SRC-C5、SRC-D3、SRC-O｜验证 UT、CT、IT

仅在响应被确认有效后持久记录目标、普通直链、远端标识、确认时间及上传的版本身份；按实际能力保留展示/缩略图 URL 与受保护的删除管理信息。结果沿用对应发布项在批次创建时的目标稳定身份与服务、别名去敏快照；账号后续重命名或移除不改写历史展示。无有效结果不得报成功。

验收：错误、空或畸形成功响应进入协议错误；同一次确认重复送达不追加重复历史；创建后改名、确认后删除账号，结果仍保持原目标身份及名称快照。

**当前状态：** Windows适用软件链已核对；最终运行与验收边界见E34，不代表正式四端条款全部验证通过。

**当前证据：** E34 [逐编号源码审查](validation/windows-network-software-audit.md)：**具备。** 适配器严格有效服务响应形成 `ProviderUploadSuccess`；`library_uploads.dart: finishUploadAttempt` 按 attempt UUID 唯一关联 ordinary result，保留冻结目标和真实输入身份；ImgBB 管理秘密通过独立 journal/UUID 引用/摘要写 SecretStore，不入普通 SQL/UI。无效或不完整响应留 unknown。 测试入口：适配器 UT-048 畸形/不一致成功/部分正文；`core/upload_repository_test.dart` 重复确认、改名/删除后历史、秘密写读回故障；`core/account_health_observation_test.dart` 普通成功与管理秘密恢复隔离。

**缺失项/未验证：** 真实图床与真实账号CT/IT未执行；未知精确能力不派发，发出后无可靠确认仍unknown，不据受控传输宣称生产上传可用。

**必要验证：** UT-043、UT-048、UT-078；AT-003、CT-002、IT-004、IT-008。UT验证业务判断；真实依赖和流程由其他方案补证。

#### UPL-006 重复发布控制

属性：P0｜V1｜来源 SRC-D1、SRC-O｜验证 UT、CT

同内容版本、目标及发布策略已有成功结果时默认复用可用记录，并允许显式再次上传。可用记录指普通 URL 通过安全格式校验，且未被明确标记过期或远端已删除；这不等于实时验证远端仍可访问，不因暂时不可达自动再传。结果未知时不自动从头重传。用户确认再次上传才生成新的任务、尝试与历史。

验收：重复点击同批次不增加发布请求；明确再传记录保留独立时间而不覆盖旧结果。

**当前状态：** Windows适用软件链已核对；最终运行与验收边界见E34，不代表正式四端条款全部验证通过。

**当前证据：** E34 [逐编号源码审查](validation/windows-network-software-audit.md)：**具备。** `enqueueUploads` 按内容版本、稳定目标与策略复用严格普通确认，保留 unavailable/unknown 边界；幂等 intent 不增加出版项。显式 forceAgain 创建新身份，不覆盖旧结果；处理计划相同才复用已确认 receipt。 测试入口：`core/upload_repository_test.dart` UT-049/072 幂等、复用、unknown/forceAgain；`core/upload_processing_repository_test.dart` 相同冻结计划复用、删 receipt 或强制重建。不能将 recorded 当实时服务可访问。

**缺失项/未验证：** 真实图床与真实账号CT/IT未执行；未知精确能力不派发，发出后无可靠确认仍unknown，不据受控传输宣称生产上传可用。

**必要验证：** UT-049、UT-072；CT-002、IT-008。UT验证业务判断；真实依赖和流程由其他方案补证。

#### UPL-007 远程结果管理边界

属性：P1｜V1｜来源 SRC-D3、SRC-O｜验证 UT、CT、AT

允许查看、复制和移除本地远程结果记录；能力明确支持时提供独立远端删除确认。远端删除失败或结果未知不伪报已删除；缺少删除能力时说明仅能移除记录。

验收：移除本地结果不调用远端；缺少受保护删除信息时不猜测删除请求。

**当前状态：** Windows适用软件链已核对；最终运行与验收边界见E34，不代表正式四端条款全部验证通过。

**当前证据：** E34 [逐编号源码审查](validation/windows-network-software-audit.md)：**具备，删除确认保守。** `library_links.dart: removeLocalLinkResults` typed action 同事务解除普通结果关联，独立秘密清理日志且核对全部引用；不调用远端。`library_remote_deletions.dart` + `RemoteDeletionCoordinator` 仅当前同 UUID 非匿名 Catbox 账号、代次、精确单文件普通直链授权，单独确认网络和远端删除，固定 deletefiles 请求。ImgBB 不猜管理链接 API；所有发出删除结果 unknown，重开不重放。 测试入口：`core/link_repository_test.dart` UT-070 本地移除保留资产/字节/历史、共享/篡改秘密保护与故障恢复；`core/remote_deletion_repository_test.dart` UT-050 同名新 UUID/匿名拒绝、generation/fingerprint、HTTP200 unknown/实际收尾/重开 prepared 与 sending。真实 CT 排除。

**缺失项/未验证：** 真实图床与真实账号CT/IT未执行；未知精确能力不派发，发出后无可靠确认仍unknown，不据受控传输宣称生产上传可用。

**必要验证：** UT-050；AT-003、CT-003、IT-008。UT验证业务判断；真实依赖和流程由其他方案补证。

### QUE

#### QUE-001 持久任务与真实状态

属性：P0｜V1｜来源 SRC-C1、SRC-D1、SRC-O｜验证 UT、IT

创建任务意图、派发及结果转换必须可持久恢复；未经确认持久化不得表示已入队或已保存成功。使用本节状态，不以界面是否打开决定任务真实状态。

验收：成功入队后重启仍存在；重启不会把旧 running 原样当作仍在执行。

**当前状态：** Windows适用软件链已核对；最终运行与验收边界见E34，不代表正式四端条款全部验证通过。

**当前证据：** E34 [逐编号源码审查](validation/windows-network-software-audit.md)：**具备。** `library_uploads.dart` schema5+ 持久批次/发布项/尝试/结果/事件，意图提交后才回执；恢复 running 分为无发送证据 interrupted 与可能提交 unknown。页面只是读取真实状态。 测试入口：`core/upload_repository_test.dart` UT-051 正常重开与恢复；`upload_flow_test.dart` 实际自有临时库及文件。硬件强退/断电不据故障注入宣称通过。

**缺失项/未验证：** 不实现计费状态；本机网络类型策略与持久队列已接入，真实切网/后台/硬件强退计时PT未执行，unknown不自动重传。

**必要验证：** UT-051；IT-004。UT验证业务判断；真实依赖和流程由其他方案补证。

#### QUE-002 有界调度

属性：P0｜V1｜来源 SRC-C1、SRC-O｜验证 UT、PERF

上传与处理采用独立有效并发上限；同一任务尝试不重复派发。降低上限后不强杀已运行项，但在计数低于新上限前不派发新项；无就绪任务不空转。

验收：连续触发调度计数不超过当时可派发上限；运行中降低上限行为符合规则。

**当前状态：** Windows适用软件链已核对；最终运行与验收边界见E34，不代表正式四端条款全部验证通过。

**当前证据：** E34 [逐编号源码审查](validation/windows-network-software-audit.md)：**具备。** `UploadCoordinator._pump` bounded running map、任务唯一 attempt；处理独立 scheduler/actor，共享预算及 FIFO；降低上限不取消实际工作，无就绪不空转。 测试入口：`core/upload_coordinator_test.dart` UT-052/053 构造 idle、并发上限、降低不杀 IO；处理 scheduler/coordinator 的真实 worker 收尾测试。候选预算和真实 PERF 分列。

**缺失项/未验证：** 不实现计费状态；本机网络类型策略与持久队列已接入，真实切网/后台/硬件强退计时PT未执行，unknown不自动重传。

**必要验证：** UT-052、UT-053；PERF-003。UT验证业务判断；真实依赖和流程由其他方案补证。

#### QUE-003 暂停与继续

属性：P1｜V1｜来源 SRC-D1、SRC-O｜验证 UT、PT、AT

可暂停单项未运行任务或整批后续派发，运行项可完成；继续后根据条件进入 queued 或 waiting。暂停期间不消耗重试次数；不宣称目标支持断点续传。

验收：暂停批次后无新请求，既有请求完成正常记录；继续不生成重复任务。

**当前状态：** Windows适用软件链已核对；最终运行与验收边界见E34，不代表正式四端条款全部验证通过。

**当前证据：** E34 [逐编号源码审查](validation/windows-network-software-audit.md)：**具备。** `setUploadBatchPaused/setUploadItemPaused` 持久且相互独立；仅 queued/waiting/paused/interrupted 可单项控制，running/unknown/终态拒绝。恢复先重验条件，保持 retry/冻结输入，暂停不取消运行项也不耗重试。 测试入口：`core/upload_item_pause_repository_test.dart`；`core/upload_coordinator_test.dart` UT-054 批次与单项先后、重试 deadline、重复 wake、运行项不停；`item_pause_flow_test.dart` 自有库受控尝试。

**缺失项/未验证：** 不实现计费状态；本机网络类型策略与持久队列已接入，真实切网/后台/硬件强退计时PT未执行，unknown不自动重传。

**必要验证：** UT-054；AT-003、PT-002。UT验证业务判断；真实依赖和流程由其他方案补证。

#### QUE-004 取消与晚到事件

属性：P0｜V1｜来源 SRC-D1、SRC-O｜验证 UT、CT、PT

取消阻止后续派发并尝试停止本机执行；远端已发生的副作用可能无法撤回。取消意图已经终结不代表本机读写立即停止：在确认本机文件使用安全结束前，原有输入和输出仍受清理保护；保护不改变任务取消状态或批次计数。取消、成功与迟到回调采用尝试身份判定，不允许旧回调覆盖新的尝试或隐瞒已确认远端结果。

验收：取消后未派发项不上传；旧尝试迟到结果不会把新尝试改为成功或失败。

**当前状态：** Windows适用软件链已核对；最终运行与验收边界见E34，不代表正式四端条款全部验证通过。

**当前证据：** E34 [逐编号源码审查](validation/windows-network-software-audit.md)：**具备。** `cancelUploadItems` 先持久终态再取消令牌；`finishUploadAttempt` 按尝试/代次保存独立晚到成功，不覆盖 cancelled 或其他新尝试。实际网络/输入/响应结束前执行租约仍保护真实源和处理输出；不把取消 future 当 IO 停止。 测试入口：`core/upload_repository_test.dart` UT-055/056/102；适配器实际 fetch/输入/响应 cancel 延迟及晚到源；`core/upload_history_repository_test.dart` cancelled+late 仍保护、SQL 租约释放失败不误清；协调器 graceful close 等真实 IO。

**缺失项/未验证：** 不实现计费状态；本机网络类型策略与持久队列已接入，真实切网/后台/硬件强退计时PT未执行，unknown不自动重传。

**必要验证：** UT-055、UT-056、UT-057、UT-079、UT-102；CT-003、IT-008、PT-002。UT验证业务判断；真实依赖和流程由其他方案补证。

#### QUE-005 错误分类

属性：P0｜V1｜来源 SRC-D3、SRC-O｜验证 UT、CT

错误至少区分授权、额度、限流、网络、超时、文件失效、格式限制、处理失败、协议错误与未知；保留脱敏摘要和下一动作。缺少证据时不能误归为密码错误或远端失败。

验收：未授权要求更新凭据；额度不足要求换目标；网络离线进入条件等待。

**当前状态：** Windows适用软件链已核对；最终运行与验收边界见E34，不代表正式四端条款全部验证通过。

**当前证据：** E34 [逐编号源码审查](validation/windows-network-software-audit.md)：**具备。** `provider_models.dart` typed failure/交付证据分授权、额度、限流、网络、超时、文件、格式、处理、协议、unknown；`upload_retry_policy.dart` 据证据决策，任务页安全文案给下一步。异常/原始响应不进入备用字符串。 测试入口：适配器 UT-058/059 拒绝、Retry-After、408/5xx/redirect、不受信 transport 超时；`core/upload_retry_policy_test.dart` typed 分类与 unknown 保护。真实服务分类集合不据合成正文穷尽证明。

**缺失项/未验证：** 不实现计费状态；本机网络类型策略与持久队列已接入，真实切网/后台/硬件强退计时PT未执行，unknown不自动重传。

**必要验证：** UT-058；CT-002、IT-008。UT验证业务判断；真实依赖和流程由其他方案补证。

#### QUE-006 有限自动重试

属性：P0｜V1｜来源 SRC-D1、SRC-O｜验证 UT、CT

仅对明确无不确定远端副作用且可重试的网络、限流或暂时服务错误执行有限退避。当前失败尝试结束，任务进入 waiting，退避到期后新建下一尝试；每个任务最多初次加 3 次自动重试。授权、额度、格式、明确不可恢复与 unknown 不自动重试；耗尽后任务转 failed，用户重试新建任务及尝试。离线和暂停期间不派发、不增加次数；同时存在多种等待条件时全部满足才能派发。

验收：默认第 1、2、3 次重试等待 2、4、8 秒；授权失败不重试；unknown 不重复发请求。

**当前状态：** Windows适用软件链已核对；最终运行与验收边界见E34，不代表正式四端条款全部验证通过。

**当前证据：** E34 [逐编号源码审查](validation/windows-network-software-audit.md)：**具备。** retry policy 只对可靠无不确定副作用的暂时失败重试，最多初次+3、2/4/8 秒并不剪短 Retry-After；旧 attempt 结束、新 attempt 新流；未知/授权/格式不自动重传，暂停/离线不派发计次。 测试入口：`core/upload_retry_policy_test.dart` UT-059/060/061/067；`core/upload_coordinator_test.dart` 单调时钟、UTC 跳变、网络 wake、paused deadline、unknown 无第二请求；适配器每新尝试 fresh multipart/stream。

**缺失项/未验证：** 不实现计费状态；本机网络类型策略与持久队列已接入，真实切网/后台/硬件强退计时PT未执行，unknown不自动重传。

**必要验证：** UT-059、UT-060、UT-061、UT-067；CT-002、IT-008。UT验证业务判断；真实依赖和流程由其他方案补证。

#### QUE-007 中断恢复

属性：P0｜V1｜来源 SRC-D1、WEB-07、WEB-08｜验证 UT、IT、PT

重启时识别旧活动任务，检查输入与依赖；本机处理可按完整性重新执行，远端提交不确定先进入 unknown 并核查可用证据。无法核查时等待用户选择，不永久显示 running。

验收：执行中强制终止再启动，没有假运行项；输入丢失有明确恢复或取消入口。

**当前状态：** Windows适用软件链已核对；最终运行与验收边界见E34，不代表正式四端条款全部验证通过。

**当前证据：** E34 [逐编号源码审查](validation/windows-network-software-audit.md)：**具备本机软件恢复。** `_recoverUploads` 按请求开始证据恢复 unknown/interrupted；处理 job 按冻结计划/确认输出完整性继续。`LibraryUploadQueueStore` 创建时冻结 executionEpoch，每次调用及 writer 门再次核对；替换后旧 actor 关闭/会话许可清空。丢失输入需修复或取消。 测试入口：`core/upload_repository_test.dart` UT-062/068；`core/upload_epoch_test.dart` 旧对象/执行拒绝；`core/upload_processing_repository_test.dart` ready 关联/未完成重执行/缺来源；真实强退计时与断电排除。

**缺失项/未验证：** 不实现计费状态；本机网络类型策略与持久队列已接入，真实切网/后台/硬件强退计时PT未执行，unknown不自动重传。

**必要验证：** UT-062、UT-068、UT-100；IT-004、PT-002。UT验证业务判断；真实依赖和流程由其他方案补证。

#### QUE-008 条件等待与网络控制

属性：P1｜V1｜来源 WEB-07、WEB-09、SRC-O｜验证 UT、PT

移动网络上传默认需用户允许，提供仅非计费网络选项；离线、低存储及系统限制引起的等待必须说明原因，不记为重复业务失败。条件恢复后调度一次，不重复创建任务。

验收：不允许移动网络时切换网络不新增传输；恢复满足条件后同一尝试最多一次派发。

**当前状态：** Windows适用软件链已核对；最终运行与验收边界见E34，不代表正式四端条款全部验证通过。

**当前证据：** E34 [逐编号源码审查](validation/windows-network-software-audit.md)：**具备最新网络类型规则。** `core/network_state.dart` 严格本机协议及 wifi/ethernet/cellular/other/offline/unknown；默认仅 Wi-Fi/有线，明确所有已识别网络才含移动。`SystemNetworkMonitor` listen 握手成功+严格 read 才有效、错误/超时/结束 unknown、generation/revision 隔离晚到。Windows `network_bridge.cpp` WinRT 默认本机 profile，无计费/SSID/IP/联网探测。`LibrarySession` 观察与设置独立会话许可，writer mayDispatch 和请求前再校验；可见桌面失焦继续观察，隐藏停止新派发，前台重读。 测试入口：`core/network_state_test.dart`、`core/system_network_monitor_test.dart` UT-063 协议/握手/缺后端/晚到/生命周期；`core/network_session_test.dart` persisted policy 不授新会话许可；协调器 UT-063 retry/pause/unknown/运行 IO 独立；`network_flow_test.dart` Windows 本机原生只读观察，不证明真实切网 PT。低存储/依赖/授权均有独立等待原因。

**缺失项/未验证：** 不实现计费状态；本机网络类型策略与持久队列已接入，真实切网/后台/硬件强退计时PT未执行，unknown不自动重传。

**必要验证：** UT-061、UT-063；PT-002。UT验证业务判断；真实依赖和流程由其他方案补证。

#### QUE-009 进度与批次汇总

属性：P1｜V1｜来源 SRC-C1、SRC-O｜验证 UT、CT、AT

支持逐项状态、阶段、已知字节进度、错误和批次计数；进度未知时显示进行中，不使用假百分比。处理失败的依赖必须结束或明确等待用户决定，总体计数与项目一致。

验收：一个失败目标不使整个批次显示全部失败；终态计数加活动计数等于批次项数。

**当前状态：** Windows适用软件链已核对；最终运行与验收边界见E34，不代表正式四端条款全部验证通过。

**当前证据：** E34 [逐编号源码审查](validation/windows-network-software-audit.md)：**具备。** `UploadCoordinator` progress 只统计实际传输活动及新增字节；`ExecutionBudget` 区分 UTC/单调时间，等待暂停退避不累计执行，真实 timer 检查 120 秒无活动与 30 分钟累计；`queue_policy.dart` 六聚合/五计数以 publication 为单位。页显示阶段/unknown，无假百分比，独立晚到结果不加 publication。 测试入口：`core/queue_policy_test.dart` UT-064/065；`core/upload_coordinator_test.dart` UT-068 watchdog 重复字节不续命；`core/upload_repository_test.dart` checkpoints/汇总；实际硬件计时精度排除。

**缺失项/未验证：** 不实现计费状态；本机网络类型策略与持久队列已接入，真实切网/后台/硬件强退计时PT未执行，unknown不自动重传。

**必要验证：** UT-045、UT-064、UT-065、UT-068；AT-003、CT-002。UT验证业务判断；真实依赖和流程由其他方案补证。

#### QUE-010 历史与清理

属性：P1｜V1｜来源 SRC-C1、SRC-O｜验证 UT、IT、AT

保留任务输入摘要、尝试、时间、目标和结果；清理历史不删除资产或远端结果，不能静默删除活跃项。正在运行时关闭窗口的行为需说明，移动后台遵从平台条件。

验收：清理完成项保留活跃依赖；完成历史不因默认策略改变而重新显示为另一处理方案。

**当前状态：** Windows适用软件链已核对；最终运行与验收边界见E34，不代表正式四端条款全部验证通过。

**当前证据：** E34 [逐编号源码审查](validation/windows-network-software-audit.md)：**具备。** `library_upload_history.dart: prepareUploadHistoryClear/clearUploadHistory` owner/epoch/完整选择指纹，同门重验，仅显式本机 succeeded/failed/cancelled 或恢复终态。unknown/实际尝试/处理/租约/残留引用/管理日志均保护；普通结果/秘密/资产不删，空批次保留 intent 账本。`upload_exit.dart` 退出确认等待真实收尾，页面说明后台限制。 测试入口：`core/upload_history_repository_test.dart` UT-038/066 六活跃状态、晚到、lease 错误、后来终态不增清、命名空间隔离、替换/重开失效；`upload_history_screen_test.dart`；`history_flow_test.dart`。

**缺失项/未验证：** 不实现计费状态；本机网络类型策略与持久队列已接入，真实切网/后台/硬件强退计时PT未执行，unknown不自动重传。

**必要验证：** UT-038、UT-066；AT-003、IT-004、PT-002。UT验证业务判断；真实依赖和流程由其他方案补证。

### LNK

#### LNK-001 单个与多种格式

属性：P1｜V1｜来源 SRC-C1、SRC-D8、SRC-O｜验证 UT、PT、AT

普通远程结果可复制 URL、Markdown、HTML 和 BBCode。名称与 URL 按目标格式正确编码或转义，不将控制字符、脚本协议或删除管理秘密插入普通模板。提供独立的成功结果集合，可按结果名称、普通 URL 与历史目标名称进行大小写不敏感的关键词检索；稳定目标身份、原图或处理版本筛选与关键词取交集，无命中返回空集合。移除账号配置后仍能以其稳定身份筛选历史结果；不得以当前同名账号替代旧身份，秘密字段不进入检索。相同输入的列表顺序稳定，排序主值相同时用稳定结果身份确定最终顺序。

验收：含引号、括号、方括号和换行的名称不会破坏生成结构；无普通链接不执行复制；名称、普通 URL、历史目标名称与版本/目标交集检索准确，秘密不命中，账号移除后历史目标仍可筛选，同输入顺序一致。

**当前状态：** Windows适用软件链已核对；最终运行与验收边界见E34，不代表正式四端条款全部验证通过。

**当前证据：** E34 [逐编号源码审查](validation/windows-network-software-audit.md)：**具备。** `upload/domain/link_format.dart` 安全普通 URL + URL/Markdown/HTML/BBCode 按格式转义；`library_links.dart: listLinkResults/listLinkTargets` 脱敏后 Unicode 折叠关键词，与稳定历史 target UUID/服务/input/状态取交集后 count/page，排序用结果 UUID 收尾，移除/同名新账号不替代冻结身份。 测试入口：`core/link_format_test.dart` UT-069；`core/link_repository_test.dart` UT-069 名称/URL/冻结别名、秘密不命中、同名删除重建、稳定 count/paging；`link_results_screen_test.dart` 实际共同页面。

**缺失项/未验证：** 真实服务HEAD/删除契约及系统分享接收端PT未执行；主动检测须确认，远端删除无可靠确认时保留unknown与本机记录。

**必要验证：** UT-017、UT-069、UT-070；AT-003、AT-004、CT-005、PT-003。UT验证业务判断；真实依赖和流程由其他方案补证。

#### LNK-002 批量复制

属性：P1｜V1｜来源 SRC-O｜验证 UT、AT

批量复制先按用户确认的资产顺序、再按选择目标顺序生成；也允许用户确认以当前可见成功结果的列表顺序复制。两种确认范围与顺序明确区分，不自动扩大到筛选外或不可见结果。完全相同的格式化结果去重，默认每项换行。失败项可跳过但必须汇报，部分结果不得伪称全部完成。

验收：相同输入重复生成顺序相同；3 项中 1 项无链接，得到 2 项并明确跳过数量；确认按当前可见结果复制时保持该列表顺序与范围，不复制筛选外结果。

**当前状态：** Windows适用软件链已核对；最终运行与验收边界见E34，不代表正式四端条款全部验证通过。

**当前证据：** E34 [逐编号源码审查](validation/windows-network-software-audit.md)：**具备。** `prepareVisibleLinkCopy` 保持明确已展示有序 ID；`prepareAssetLinkCopy` 当前永久版本按资产顺序×用户目标顺序，不扩大至隐形/筛选外/其他处理版本。LinkCopyPlan owner/epoch/完整普通指纹，执行前验证，精确格式去重、换行、缺失报告。 测试入口：`core/link_repository_test.dart` UT-070 两种范围与顺序、missing/dedupe、当前 digest+bytes、变化/新秘密使计划失效；`core/link_transfer_test.dart` 旧 owner/替换/空集合不调用系统。

**缺失项/未验证：** 真实服务HEAD/删除契约及系统分享接收端PT未执行；主动检测须确认，远端删除无可靠确认时保留unknown与本机记录。

**必要验证：** UT-070；AT-004。UT验证业务判断；真实依赖和流程由其他方案补证。

#### LNK-003 剪贴板错误与分享

属性：P1｜V1｜来源 SRC-C1、SRC-O｜验证 UT、PT

系统允许时可复制或使用平台分享入口；必须反馈实际成功或失败。不能因剪贴板失败删除远程结果，重试只重复本地操作，不重新上传。

验收：拒绝剪贴板权限后链接仍保留，用户可重新复制。

**当前状态：** Windows适用软件链已核对；最终运行与验收边界见E34，不代表正式四端条款全部验证通过。

**当前证据：** E34 [逐编号源码审查](validation/windows-network-software-audit.md)：**具备 Windows 系统入口。** `platform/link_transfer_gateway.dart: SystemLinkTransferGateway` 严格 `flutter/platform` JSON Clipboard 通道避免 OptionalMethodChannel 吞后端错误；share_plus 仅普通文本，取消/未确认/不支持/失败分别反馈。`LinkTransferCoordinator` 重试仅本地调用、不上传/删结果。 测试入口：`core/link_transfer_test.dart` UT-071 SDK 协议成功、拒绝/缺后端/未知对象不 stringify、分享结果映射；`links_flow_test.dart` 本机系统复制路径。接收方保存及设备分享 UI 不据返回成功宣称。

**缺失项/未验证：** 真实服务HEAD/删除契约及系统分享接收端PT未执行；主动检测须确认，远端删除无可靠确认时保留unknown与本机记录。

**必要验证：** UT-071；PT-003。UT验证业务判断；真实依赖和流程由其他方案补证。

#### LNK-004 可用性与保留说明

属性：P1｜V1｜来源 WEB-01、WEB-02、SRC-O｜验证 UT、CT、AT

链接存在、可访问、远端已删除和未知状态分别表达；不根据一次离线或失败探测自动删除历史。探测为用户主动动作或已开启的明确策略，不通过定期访问规避服务保留规则。

验收：离线探测标为未能确认，历史不丢；Catbox 匿名链接不能显示成应用保证永久。

**当前状态：** Windows适用软件链已核对；最终运行与验收边界见E34，不代表正式四端条款全部验证通过。

**当前证据：** E34 [逐编号源码审查](validation/windows-network-software-audit.md)：**具备主动检测及保留语义。** `LinkProbeCoordinator` 仅独立确认范围/网络后，`link_probe_gateway.dart` 固定 HTTPS 白名单 HEAD，无凭据/重定向/GET fallback/周期/重试。200 image/* 空体为当时可访问、410 空体服务报告不再提供、404/离线/其他为未知。`library_link_probes.dart` generation 拒绝旧晚到并保留 lastAccessible，实际流收尾才放保护，普通结果/秘密/字节不删。页说明历史匿名不保证永久。 测试入口：`core/link_probe_repository_test.dart` UT-072 惰性、Gone/失败不删、筛选/分页、generation、实际 transport 与 close/restore、损坏保留；gateway/coordinator 合成 HTTP；`link_probe_flow_test.dart` 受控请求，不是真实服务 CT。

**缺失项/未验证：** 真实服务HEAD/删除契约及系统分享接收端PT未执行；主动检测须确认，远端删除无可靠确认时保留unknown与本机记录。

**必要验证：** UT-072；AT-004、CT-001、IT-008。UT验证业务判断；真实依赖和流程由其他方案补证。

### BAK

#### BAK-001 两种备份

属性：P0｜V1｜来源 SRC-U、SRC-O｜验证 UT、IT、AT

提供元数据备份与完整备份。前者包含整理、版本关联、普通远程链接和去敏历史，不含图片字节；后者额外包含永久副本。备份界面必须解释元数据备份不能恢复原图。完整备份范围内缺失或损坏必要副本时不得静默跳过并报告完整成功，必须列明受影响项，提供修复、取消或明确改为元数据备份的选择。

验收：仅元数据恢复仍保留链接但缺字节项标本机不可用；完整恢复可校验图片内容；必要副本不可读时不产生完整成功反馈，原库不受影响。

**当前状态：** Windows适用软件链已核对；最终运行与验收边界见E34，不代表正式四端条款全部验证通过。

**当前证据：** E34 [逐编号源码审查](validation/windows-local-software-audit.md)：`gallery/data/library_backups.dart` 在一致事务取得全部永久版本与租约。完整包包含永久字节，包括回收及仅清记录后的独立版本；元数据包没有图片。真实摘要和像素校验失败列明 UUID 并拒绝完整成功，用户须明确改选元数据。恢复元数据创建 missing 副本，不借用原设备路径。 测试入口：`core/backup_snapshot_test.dart`、`backup_merge_restore_repository_test.dart`、`backup_screen_test.dart`；真实小图 SQL/files，非大包性能证明。

**缺失项/未验证：** Windows实际小图恢复边界见E34，Windows>4GiB ZIP64软件流程见E36；四设备互读、真实系统选框/提供者及照片格式互操作、其他三端>4GiB实包与硬件PERF/PT未验收。

**必要验证：** UT-073；AT-005、CT-006、IT-005。UT验证业务判断；真实依赖和流程由其他方案补证。

#### BAK-002 备份一致性与秘密排除

属性：P0｜V1｜来源 SRC-O、WEB-10｜验证 UT、IT

备份具有版本、时间、内容清单与完整性校验，取得一致的数据视图；不包含凭据、删除管理秘密、临时输出和待执行任务。进行中的操作不能使备份成为半份关联数据。

验收：备份中找不到样例秘密；关联资产和版本完整；任务只可保留去敏的终态历史。

**当前状态：** Windows适用软件链已核对；最终运行与验收边界见E34，不代表正式四端条款全部验证通过。

**当前证据：** E34 [逐编号源码审查](validation/windows-local-software-audit.md)：同一 writer 事务取得关系与实际文件租约，退出 writer 后校验/流式写 ZIP。Manifest 白名单排除秘密引用、路径、临时输出、活动意图及本机诊断/观察；终态取消但真实工作未结束的项不进入可携带历史。所有本库秘密引用必须可读取并注册脱敏，返回 null 同样拒绝导出。 测试入口：`core/backup_manifest_test.dart`、`backup_snapshot_test.dart`、`missing_owned_secret_test.dart`；故障拒绝后资产、字节、租约状态及原库可重开均有断言。

**缺失项/未验证：** Windows实际小图恢复边界见E34，Windows>4GiB ZIP64软件流程见E36；四设备互读、真实系统选框/提供者及照片格式互操作、其他三端>4GiB实包与硬件PERF/PT未验收。

**必要验证：** UT-073、UT-074；CT-006、IT-005。UT验证业务判断；真实依赖和流程由其他方案补证。

#### BAK-003 校验与不覆盖失败

属性：P0｜V1｜来源 SRC-O｜验证 UT、IT

恢复前检查格式版本、清单、图片内容与可用空间；损坏、未知版本或容量不足不得修改当前有效图库。文件名和资源引用不得使备份写出用户确认的恢复范围。

验收：损坏包和含越界位置的清单被拒绝，现有数据内容与关联保持不变。

**当前状态：** Windows适用软件链已核对；最终运行与验收边界见E34，不代表正式四端条款全部验证通过。

**当前证据：** E34 [逐编号源码审查](validation/windows-local-software-audit.md)：`backup_zip_reader.dart` 手工检查 ZIP/ZIP64 原始目录、重复名字、中央/本地一致、范围、STORE、CRC/SHA/真实像素和预算；只写新私有暂存。恢复 prepare 与 commit 均校验空间、关系和当前 epoch，校验失败不改当前库。测试入口：`core/backup_zip_reader_test.dart`、`backup_restore_plan_test.dart`、`backup_merge_restore_repository_test.dart`；Windows>4GiB真实BMP ZIP64预检/合并/重开见E36，其他三端大包和硬件容量压力未验收。

**缺失项/未验证：** Windows实际小图恢复边界见E34，Windows>4GiB ZIP64软件流程见E36；四设备互读、真实系统选框/提供者及照片格式互操作、其他三端>4GiB实包与硬件PERF/PT未验收。

**必要验证：** UT-075；CT-006、IT-005。UT验证业务判断；真实依赖和流程由其他方案补证。

#### BAK-004 合并与替换

属性：P0｜V1｜来源 SRC-O｜验证 UT、IT、AT

默认合并；新增资产保留备份信息，重复内容合并标签和链接、收藏取真、当前非空分类与名称保留，分类冲突列入汇总。同内容不同资产身份复用当前资产并重映射备份内版本、来源与远程结果的关联；同身份但不同内容不得覆盖当前内容，恢复项分配新身份并报告冲突。合并已有资产时保留当前回收状态，不自动复活；新增资产保留备份回收状态。远程结果按稳定结果身份与确认事件身份去重，身份相同但内容冲突拒绝该关联并报告；仅 URL 相同不代表同次发布，显式再传历史保留。

恢复提交前暂停新派发，等待在途本机写入安全结束；不能安全结束时阻止恢复提交。当前活跃任务保留且保持暂停，不被备份历史覆盖；恢复历史只作为不可执行历史。替换恢复须先生成可恢复的当前快照并单独确认，取消旧执行意图且隔离迟到事件；恢复提交、任务写入和旧回调不得交错破坏新库。

验收：合并不清空现有库；同内容异身份的关联指向同一当前资产，同身份异内容不覆盖；两次上传同 URL 的不同确认历史仍保留；回收资产不自动复活；替换失败可回到原有效状态，旧回调不写入恢复后的图库。

**当前状态：** Windows适用软件链已核对；最终运行与验收边界见E34，不代表正式四端条款全部验证通过。

**当前证据：** E34 [逐编号源码审查](validation/windows-local-software-audit.md)：纯计划按内容映射资产、版本、来源、结果与历史，UUID 碰撞分配新身份；标签并集超 50 拒绝，不截断。维护先阻止新派发并排空实际 IO；合并保持现有任务暂停，替换先建可重建私有快照，独立确认、关联提交、会话切换及旧 epoch 拒绝。失败按日志用快照单事务回滚，成功仅有证据清旧文件/秘密。 测试入口：`core/backup_merge_plan_test.dart`、`backup_result_merge_test.dart`、`backup_restore_plan_test.dart`、`backup_replace_restore_repository_test.dart`、`replacement_rollback_test.dart`；本轮 PNG 审计描述修复另列，冻结历史不能被永久描述改写。

**缺失项/未验证：** Windows实际小图恢复边界见E34，Windows>4GiB ZIP64软件流程见E36；四设备互读、真实系统选框/提供者及照片格式互操作、其他三端>4GiB实包与硬件PERF/PT未验收。

**必要验证：** UT-076、UT-077、UT-078、UT-079、UT-080；AT-005、IT-005。UT验证业务判断；真实依赖和流程由其他方案补证。

#### BAK-005 跨端恢复与设备设置

属性：P1｜V1｜来源 SRC-U、SRC-O｜验证 UT、IT、PT

本版备份业务数据可在四端识别；设备路径不直接套用，恢复到本机管理位置。账号仅恢复去敏标识并要求重新配置凭据，平台设置只恢复当前平台可用项并报告跳过。

验收：桌面完整备份在移动端恢复后无桌面绝对路径依赖；不恢复旧任务为自动执行。

**当前状态：** Windows适用软件链已核对；最终运行与验收边界见E34，不代表正式四端条款全部验证通过。

**当前证据：** E34 [逐编号源码审查](validation/windows-local-software-audit.md)：自有 Manifest 2/1 只带相对包内资源标识；恢复通过当前平台目录/独占发布服务创建新副本。账号恢复禁用、没有秘密。八项设备设置独立严格 envelope，只恢复声明可用项，确认列出覆盖/跳过；默认目标、凭据、会话许可与旧冻结任务不恢复。 测试入口：`core/backup_settings_test.dart`、`backup_settings_repository_test.dart`、`backup_settings_screen_test.dart`；Windows 实际互读子流程可验证，四设备互读 PT 未执行。

**缺失项/未验证：** Windows实际小图恢复边界见E34，Windows>4GiB ZIP64软件流程见E36；四设备互读、真实系统选框/提供者及照片格式互操作、其他三端>4GiB实包与硬件PERF/PT未验收。

**必要验证：** UT-081；CT-006、IT-005、PT-005。UT验证业务判断；真实依赖和流程由其他方案补证。

#### BAK-006 备份结果与用户控制

属性：P1｜V1｜来源 SRC-O｜验证 UT、IT、PT、AT

备份与恢复具有进度、取消、成功/失败汇总及空间估算；备份仅用户主动导出，不默认上传云端。未完成文件不标为有效备份，取消后原库保持有效。

验收：导出目标不可写和中断被解释；完成备份清单可复核。

**当前状态：** Windows适用软件链已核对；最终运行与验收边界见E34，不代表正式四端条款全部验证通过。

**当前证据：** E34 [逐编号源码审查](validation/windows-local-software-audit.md)：`BackupCoordinator`/`RestoreCoordinator` 与共同页面有阶段进度、空间估算、取消及结果汇总。真实 writer/reader 完成、文件关闭后才收尾保护；独占发布是导出提交点，迟到取消不撤销用户文件。暂存按登记、关闭证据与摘要清理，未知子项、链接、变化字节或无法确认 IO 时保留现场；暂存清理与资料库保护清理分别反馈。 测试入口：`core/backup_coordinator_test.dart`、`backup_zip_reader_test.dart`、`backup_screen_test.dart`；系统目录窗口用 fixture，未计 PT/完整人工 AT。

**缺失项/未验证：** Windows实际小图恢复边界见E34，Windows>4GiB ZIP64软件流程见E36；四设备互读、真实系统选框/提供者及照片格式互操作、其他三端>4GiB实包与硬件PERF/PT未验收。

**必要验证：** UT-082；AT-005、IT-005、PT-003。UT验证业务判断；真实依赖和流程由其他方案补证。

### OPS

#### OPS-001 设置保存

属性：P0｜V1｜来源 SRC-C1、SRC-O｜验证 UT、IT

设置变更必须校验并明确保存结果；保存失败保留旧有效值并允许重试。默认目标、处理与隐私默认值仅影响新任务输入；并发、网络、暂停及缓存保留策略按 4.2 动态作用于尚未派发项或后续清理，不改变已运行任务输入，文件保护规则始终优先。

验收：保存被拒绝不显示已保存；重启读取最后成功值。

**当前状态：** Windows适用软件链已核对；最终运行与验收边界见E34，不代表正式四端条款全部验证通过。

**当前证据：** E34 [逐编号源码审查](validation/windows-local-software-audit.md)：`library_settings.dart` 在绑定 owner/epoch/旧设置与目标指纹的事务校验并保存，成功后才更新共同调度策略。默认输入只作用于新工作台/任务；运行中的输入、预算及旧草稿不变。损坏/未来设置拒绝加载，不覆盖为默认值，恢复失败保留旧设置。 测试入口：`core/device_settings_test.dart`、`settings_repository_test.dart`、`backup_settings_repository_test.dart`、`settings_screen_test.dart`。

**缺失项/未验证：** Windows系统能力及主机自动化见E34；真实内存/磁盘压力校准与系统窗口PT未执行，Android原生导出及模拟器证据见E35，Apple文件能力及iOS模拟器子流程见[里程碑29](milestone-29-apple-files.md)；真实系统选择器UI/Files提供者与格式互操作仍待验收。

**必要验证：** UT-053、UT-083、UT-088；IT-006。UT验证业务判断；真实依赖和流程由其他方案补证。

#### OPS-002 诊断事件

属性：P1｜V1｜来源 SRC-C1、SRC-D2｜验证 UT、IT、AT

记录导入、处理、队列、账号状态、保存、清理、恢复等关键事件，带时间、类型、批次或尝试关联与脱敏摘要；提供查看、筛选及清空。错误应包含恢复动作，不只显示内部异常。

验收：能从失败任务找到对应去敏事件；删除日志不删任务、资产或远程历史。

**当前状态：** Windows适用软件链已核对；最终运行与验收边界见E34，不代表正式四端条款全部验证通过。

**当前证据：** E34 [逐编号源码审查](validation/windows-local-software-audit.md)：`library_diagnostics.dart` 白名单事件独立于业务外键，业务提交后记录，日志失败不回滚业务。按真实 UTF-8 字节和 30 天/10,000,000 字节先到清最旧；共同页支持筛选、任务/尝试关联与确认清理，绑定冻结行，不增清后来事件。 测试入口：`core/diagnostic_runtime_test.dart`、`diagnostic_repository_test.dart`、`diagnostics_screen_test.dart`；读/导出故障不串改业务记录。

**缺失项/未验证：** Windows系统能力及主机自动化见E34；真实内存/磁盘压力校准与系统窗口PT未执行，Android原生导出及模拟器证据见E35，Apple文件能力及iOS模拟器子流程见[里程碑29](milestone-29-apple-files.md)；真实系统选择器UI/Files提供者与格式互操作仍待验收。

**必要验证：** UT-084、UT-089；AT-005、IT-006。UT验证业务判断；真实依赖和流程由其他方案补证。

#### OPS-003 诊断导出

属性：P1｜V1｜来源 SRC-D2、SRC-O、WEB-10｜验证 UT、IT、PT

可主动导出诊断信息，导出前列明范围并脱敏；默认不含图片、凭据、删除秘密和用户完整外部路径。服务响应仅保留必要的脱敏摘要，不无限保存原始正文。

验收：嵌套字段、URL 查询参数及异常文字中的样例秘密均不泄漏。

**当前状态：** Windows适用软件链已核对；最终运行与验收边界见E34，不代表正式四端条款全部验证通过。

**当前证据：** E34 [逐编号源码审查](validation/windows-local-software-audit.md)：诊断读取、确认和实际导出重新核对本库秘密引用；缺值拒绝安全视图，不枚举其他凭据。先遮蔽再截断，排除来源完整路径、秘密引用、图片、URL query/fragment、正文与不可信异常字符串。用户主动导出，实际 IO 收尾后反馈，清理只操作自有窗口和登记暂存。 测试入口：`core/diagnostic_sanitizer_test.dart`、`diagnostic_exporter_test.dart`、`missing_owned_secret_test.dart`；Android原生JSON导出见E35，Apple代码接线与iOS模拟器子流程见[里程碑29](milestone-29-apple-files.md)；真实系统选择器/Files提供者及完整PT仍待验收。

**缺失项/未验证：** Windows系统能力及主机自动化见E34；真实内存/磁盘压力校准与系统窗口PT未执行，Android原生导出及模拟器证据见E35，Apple文件能力及iOS模拟器子流程见[里程碑29](milestone-29-apple-files.md)；真实系统选择器UI/Files提供者与格式互操作仍待验收。

**必要验证：** UT-085、UT-089；IT-006、PT-003。UT验证业务判断；真实依赖和流程由其他方案补证。

#### OPS-004 空间管理

属性：P1｜V1｜来源 SRC-D4、SRC-O｜验证 UT、IT、AT

区分永久图片、回收区、缩略图、临时结果及日志占用；缓存可清理且可再生成。空间不足时暂停相关新写入，说明释放途径，不自动牺牲永久图片。

验收：清理缩略图与日志不影响原图；低空间时导入失败有逐项报告。

**当前状态：** Windows适用软件链已核对；最终运行与验收边界见E34，不代表正式四端条款全部验证通过。

**当前证据：** E34 [逐编号源码审查](validation/windows-local-software-audit.md)：`library_storage.dart`/`storage_screen.dart` 按实际文件长度展示永久/回收/缓存/输出/诊断占用。缩略图登记日志、使用序号 LRU 与冻结清理计划保留保护项、未知文件、链接和变化字节。原图、输出和缓存新写入先检查实际可用空间；不足时停相关新写入并解释，不自动牺牲永久副本。 测试入口：`core/storage_repository_test.dart`、`storage_capacity_test.dart`、`storage_screen_test.dart` 与 Windows 原生接口；空间余量与总体资源预算是候选值，未做硬件 PERF。

**缺失项/未验证：** Windows系统能力及主机自动化见E34；真实内存/磁盘压力校准与系统窗口PT未执行，Android原生导出及模拟器证据见E35，Apple文件能力及iOS模拟器子流程见[里程碑29](milestone-29-apple-files.md)；真实系统选择器UI/Files提供者与格式互操作仍待验收。

**必要验证：** UT-086；AT-004、IT-006。UT验证业务判断；真实依赖和流程由其他方案补证。

#### OPS-005 默认参数与可解释限制

属性：P1｜V1｜来源 SRC-C1、SRC-O｜验证 UT、AT

所有可配置默认值有合法范围、单位、实际生效值与恢复默认动作；平台采用更低并发或资源预算时明确说明。不可配置项不出现可编辑但无效的控制。

验收：并发 0、负数、非整数和非有限值拒绝，不默默解释成其他数；有效值跨重启保留。

**当前状态：** Windows适用软件链已核对；最终运行与验收边界见E34，不代表正式四端条款全部验证通过。

**当前证据：** E34 [逐编号源码审查](validation/windows-local-software-audit.md)：设置显示合法范围、单位、实际有效并发/预算及恢复默认草稿；须保存才生效。`ProcessingScheduler` FIFO 实际预算动态约束并发，内存压力后本会话降低到最多一个候选任务，不取消旧运行许可。Windows 原生低内存信号接入严格失败反馈；不可用的移动导出等能力不提供假控制。 测试入口：`core/settings_repository_test.dart`、`processing_scheduler_test.dart`、`processing_memory_pressure_test.dart`、`system_memory_pressure_monitor_test.dart`；实际低内存/四端预算校准未执行。

**缺失项/未验证：** Windows系统能力及主机自动化见E34；真实内存/磁盘压力校准与系统窗口PT未执行，Android原生导出及模拟器证据见E35，Apple文件能力及iOS模拟器子流程见[里程碑29](milestone-29-apple-files.md)；真实系统选择器UI/Files提供者与格式互操作仍待验收。

**必要验证：** UT-015、UT-025、UT-087、UT-088；AT-005。UT验证业务判断；真实依赖和流程由其他方案补证。

### DAT

#### DAT-001 持久化结果与加载保护

属性：P0｜V1｜来源 SRC-C3、SRC-O｜验证 UT、IT

加载失败或尚未加载时不得用默认空数据覆盖已有库；保存失败保留上一个有效状态并显式报告。用户已获成功反馈的整理、链接和设置在正常重启后必须存在。

验收：注入加载/保存异常，已有图片和关联不丢；失败状态没有假成功反馈。

**当前状态：** Windows适用软件链已核对；最终运行与验收边界见E34，不代表正式四端条款全部验证通过。

**当前证据：** E34 [逐编号源码审查](validation/windows-library-software-audit.md)：具备。`LibraryRepository.open` 安全失败不建空默认；`GalleryController.reload` 失败保留旧列表；保存事务成功后才更新共同状态/反馈；`LibraryFailureView` 重试及数据保全说明，不给破坏性reset。 测试入口：`core/library_repository_test.dart` UT-090 已存图来源删除/重开、损坏/未来库不覆盖；`gallery_controller_test.dart` 读取失败旧列表；`library_failure_view_test.dart` UT-093/096 明确保全重试、未知异常不stringify；`core/settings_repository_test.dart` 失败旧值/重开。

**缺失项/未验证：** 真实SQL/files及进程恢复边界见E34；硬件断电、实际系统强退、三端升级设备与正式格式契约验收未执行，不猜测修复或空库覆盖。

**必要验证：** UT-051、UT-083、UT-090；IT-004。UT验证业务判断；真实依赖和流程由其他方案补证。

#### DAT-002 关联一致性

属性：P0｜V1｜来源 SRC-C3、SRC-O｜验证 UT、IT

资产、副本、输出、任务与远程结果关联变更必须保持一致或可恢复；失败不形成可用记录引用半成品，删除不产生无解释的悬空活动依赖。

验收：在变更各阶段中断后可恢复为上一个有效状态或完整新状态，不能是混合状态。

**当前状态：** Windows适用软件链已核对；最终运行与验收边界见E34，不代表正式四端条款全部验证通过。

**当前证据：** E34 [逐编号源码审查](validation/windows-library-software-audit.md)：具备。FK/WAL/FULL实际验证，单writer/跨文件日志、关联事务、持久依赖与actual租约；导入/输出/结果/恢复各有幂等阶段，未确认半成品不可用。 测试入口：`core/library_repository_test.dart` UT-091 各边界；`processing/output_lifecycle_test.dart`；`core/upload_repository_test.dart` 结果事务/尝试；`core/backup_merge_restore_repository_test.dart`、`core/backup_replace_restore_repository_test.dart` 与恢复schema测试。这些是具体边界证据，不称真实断电全覆盖。

**缺失项/未验证：** 真实SQL/files及进程恢复边界见E34；硬件断电、实际系统强退、三端升级设备与正式格式契约验收未执行，不猜测修复或空库覆盖。

**必要验证：** UT-003、UT-035、UT-080、UT-091；IT-004。UT验证业务判断；真实依赖和流程由其他方案补证。

#### DAT-003 内容与版本身份

属性：P0｜V1｜来源 SRC-C2、SRC-O｜验证 UT、IT

内容身份基于真实字节，资产身份、内容版本与设备副本分离。处理版本、上传源和恢复关联均不能仅依赖名称、大小或修改时间。

验收：同大小同名不同字节不误合并；改显示名称不改变内容或远端关联。

**当前状态：** Windows适用软件链已核对；最终运行与验收边界见E34，不代表正式四端条款全部验证通过。

**当前证据：** E34 [逐编号源码审查](validation/windows-library-software-audit.md)：具备。UUID区分资产/内容版本/设备副本，SHA+bytes定内容；处理任务和恢复快照冻结身份/真实摘要，重命名/外部mtime不改远端关联。 测试入口：`core/library_repository_test.dart` UT-005/006同大小不同字节/整理保留；`core/import_recycle_boundary_test.dart` 独立版本再入库；`core/backup_merge_plan_test.dart` 内容/身份碰撞；`core/gallery_remote_query_test.dart` 当前版本关联。

**缺失项/未验证：** 真实SQL/files及进程恢复边界见E34；硬件断电、实际系统强退、三端升级设备与正式格式契约验收未执行，不猜测修复或空库覆盖。

**必要验证：** UT-005、UT-006、UT-021；IT-001。UT验证业务判断；真实依赖和流程由其他方案补证。

#### DAT-004 时间与事件幂等

属性：P0｜V1｜来源 SRC-C1、SRC-O｜验证 UT、IT

事件记录保留可跨时区解释的时间和独立事件身份；重复保存、恢复或回调不产生重复逻辑结果。持续时间与退避不因用户调整系统时钟而被无限推迟或跳过。

验收：同确认事件重放两次只有一份远端结果；时钟后退不使正在退避的任务无限等待。

**当前状态：** Windows适用软件链已核对；最终运行与验收边界见E34，不代表正式四端条款全部验证通过。

**当前证据：** E34 [逐编号源码审查](validation/windows-library-software-audit.md)：具备。`TimeSource` UTC clock和Stopwatch monotonic分离；结果按独立attempt/result身份唯一，意图幂等账本保留；恢复映射保留独立身份，重放不按显示时间造事件。执行/退避基于单调持续时间。 测试入口：`core/queue_policy_test.dart` UT-067 墙钟跳变不改变实际执行、UT-061不剪Retry-After；`core/upload_history_repository_test.dart` 同intent重试保留一批；`core/backup_result_merge_test.dart` UT-078确认重放幂等；`core/backup_restore_plan_test.dart` 来源/终态历史重放；UT-009 UTC元信息。

**缺失项/未验证：** 真实SQL/files及进程恢复边界见E34；硬件断电、实际系统强退、三端升级设备与正式格式契约验收未执行，不猜测修复或空库覆盖。

**必要验证：** UT-009、UT-048、UT-067、UT-092；IT-004。UT验证业务判断；真实依赖和流程由其他方案补证。

#### DAT-005 格式演进与损坏恢复

属性：P0｜V1｜来源 SRC-C3、SRC-U、SRC-O｜验证 UT、IT

新项目自身的数据升级需识别版本、校验并保留可恢复旧状态；损坏或不兼容数据进入明确修复/导出状态，不静默重置。此要求不包含旧项目格式迁移。

验收：遇到未来版本拒绝破坏性打开；失败升级保留原有效数据。

**当前状态：** Windows适用软件链已核对；最终运行与验收边界见E34，不代表正式四端条款全部验证通过。

**当前证据：** E34 [逐编号源码审查](validation/windows-library-software-audit.md)：具备安全演进/待修复软件状态。own schema1–9→10校验，6–9有恢复日志先拒绝，future/损坏/规范版本不兼容保留现场；`LibraryFailureView` 指导完整目录保全、兼容版本/独立新库备份校验与重试。无法确认完整性时不伪造业务备份，未静默重置，也无旧项目迁移。 测试入口：`core/library_migration_test.dart` UT-093真实旧schema、非法升级回滚、future原DB/文件不变；`core/restore_schema_recovery_test.dart` 关联保留/畸形日志保全；`core/upload_processing_schema_test.dart` 当前升级保护；`library_failure_view_test.dart` 可理解恢复说明。旧PNG语义修正不自动更改version，见文末。

**缺失项/未验证：** 真实SQL/files及进程恢复边界见E34；硬件断电、实际系统强退、三端升级设备与正式格式契约验收未执行，不猜测修复或空库覆盖。

**必要验证：** UT-093；CT-006、IT-006。UT验证业务判断；真实依赖和流程由其他方案补证。

### SEC

#### SEC-001 最小授权

属性：P0｜V1｜来源 WEB-04、WEB-05、WEB-10｜验证 UT、PT、REV

只请求实际功能必要的图片/文件授权；用户拒绝完整相册访问时，仍能使用平台允许的选图入口及已保存副本。无关权限不作为启动或本地使用条件。

验收：拒绝可选权限不阻断已保存图片整理；权限用途可解释。

**当前状态：** Windows适用软件链已核对；最终运行与验收边界见E34，不代表正式四端条款全部验证通过。

**当前证据：** E34 [逐编号源码审查](validation/windows-network-software-audit.md)：**具备 Windows 最小文件授权。** `platform/import_gateway.dart: pickFiles` 用户选文件才取得只读资源，已保存资料库不依赖外部相册/来源权限；取消为空明确结果、未知错误固定分类。账号/网络观察不要求无关图片权限。Windows 普通路径来源预检不打开明确 cloudPending 文件流。 测试入口：`core/cloud_import_batch_test.dart`、`core/import_source_cancellation_test.dart` 真实自有文件与取消流；`gallery_flow_test.dart`。Android/iOS 相册授权/恢复验证属于其他平台，不据此认定 Windows 软件缺口。

**缺失项/未验证：** 本库秘密和固定异常脱敏有本机边界证据；真实服务/账号及四端授权与存储PT未执行，未授权不外发。

**必要验证：** UT-094；PT-001、REV-002。UT验证业务判断；真实依赖和流程由其他方案补证。

#### SEC-002 凭据保护

属性：P0｜V1｜来源 SRC-D2、SRC-U、WEB-10｜验证 UT、IT、PT

图床凭据及删除管理秘密采用平台可用的受保护存储；普通配置、任务快照、日志、备份、导出和云同步不得包含秘密。无法安全保存时不得退回明文方案，允许不保存的会话使用。

验收：所有普通输出扫描样例秘密均为零；删除账号后秘密不可再读取。

**当前状态：** Windows适用软件链已核对；最终运行与验收边界见E34，不代表正式四端条款全部验证通过。

**当前证据：** E34 [逐编号源码审查](validation/windows-network-software-audit.md)：**具备。** `platform/system_secret_store.dart` 生产注入 flutter_secure_storage、应用新命名空间与 UUID 单项引用，串行写/删/读回，无枚举清全库或明文 fallback；账号与管理秘密日志确认所有权/摘要，明确 session 仅内存关闭清空。普通任务/历史/可携带包无秘密。 测试入口：`core/secret_store_test.dart` UT-074/095 写删读回/异常；`core/accounts_repository_test.dart` session 替换旧密钥不复活、删除恢复；`core/upload_repository_test.dart` 管理秘密；`accounts_flow_test.dart` 合成凭据 Windows 系统后端。真实账号验证排除。

**缺失项/未验证：** 本库秘密和固定异常脱敏有本机边界证据；真实服务/账号及四端授权与存储PT未执行，未授权不外发。

**必要验证：** UT-074、UT-095；IT-007、PT-006。UT验证业务判断；真实依赖和流程由其他方案补证。

#### SEC-003 传输与远程输入

属性：P0｜V1｜来源 SRC-C5、SRC-O｜验证 UT、CT、PT

远程操作采用认证的安全传输，不默认忽略证书问题。普通可复制链接只接受有效 http/https 图片链接，非安全 http 明示；远端名称、响应和 URL 不作为可执行内容。

验收：脚本、文件或其他危险协议被拒绝；证书异常不被当作成功。

**当前状态：** Windows适用软件链已核对；最终运行与验收边界见E34，不代表正式四端条款全部验证通过。

**当前证据：** E34 [逐编号源码审查](validation/windows-network-software-audit.md)：**具备。** upload/probe/delete 全部固定认证 HTTPS，Dio 不设证书绕过或重定向；成功普通 URL 严格 host/协议/控制符/userinfo/query/fragment，允许普通 http 时明确标识。管理 URL 只入受保护包装；远端响应只是受预算的解析输入，不执行脚本。 测试入口：适配器 UT-048/096 unsafe URL/HTML/不一致证据/64KiB；`core/link_format_test.dart` 危险协议/格式注入；probe/delete gateway HTTPS 边界。真实 TLS/服务 CT 排除。

**缺失项/未验证：** 本库秘密和固定异常脱敏有本机边界证据；真实服务/账号及四端授权与存储PT未执行，未授权不外发。

**必要验证：** UT-069、UT-096；CT-005、IT-008、PT-006。UT验证业务判断；真实依赖和流程由其他方案补证。

#### SEC-004 全链路脱敏

属性：P0｜V1｜来源 SRC-D2、WEB-10、SRC-O｜验证 UT、IT

对界面错误、日志、诊断、备份及普通导出实行一致脱敏，涵盖已知秘密值、敏感字段、URL 参数和嵌套结构。截断或格式异常不能使秘密出现在备用异常字符串中。

验收：提供包含 Key、userhash、删除秘密的响应及异常，所有普通输出均不含原值。

**当前状态：** Windows适用软件链已核对；最终运行与验收边界见E34，不代表正式四端条款全部验证通过。

**当前证据：** E34 [逐编号源码审查](validation/windows-network-software-audit.md)：**具备当前出口边界。** `SecretRedactor.register/redact/redactText` 真实秘密先登记，历史值持续遮蔽，未知对象不 toString。账号安全异常、适配器固定 DioException、`DiagnosticSanitizer` 先脱敏再截断/白名单化；新秘密注册后重遮 ordinary 本机/恢复显示快照；链接 SQL、诊断读取/导出及备份白名单取得安全视图，否则拒绝。结构身份与秘密冲突时不改 UUID。 测试入口：`core/secret_redactor_test.dart` UT-097 嵌套/参数/短值/循环/异常；适配器 transport factory/同步 fetch/raw response/close 测试；`core/diagnostic_repository_test.dart` UT-085 导出执行再遮蔽/后端失败拒绝；backup snapshot/export 与 links 新秘密计划失效。不是对未知未来出口的承诺。

**缺失项/未验证：** 本库秘密和固定异常脱敏有本机边界证据；真实服务/账号及四端授权与存储PT未执行，未授权不外发。

**必要验证：** UT-085、UT-097；IT-006、IT-007。UT验证业务判断；真实依赖和流程由其他方案补证。

#### SEC-005 用户主动外发

属性：P0｜V1｜来源 SRC-U、SRC-O｜验证 UT、PT、AT

原图、处理输出、备份和诊断仅在用户明确操作后发送到相应目标。首版不默认遥测、不自动云登录、不自动上传图床或备份；执行已确认任务的网络恢复不算新的外发授权。

验收：离线本地使用不产生图床请求；配置账号和健康状态本身不上传图片。

**当前状态：** Windows适用软件链已核对；最终运行与验收边界见E34，不代表正式四端条款全部验证通过。

**当前证据：** E34 [逐编号源码审查](validation/windows-network-software-audit.md)：**具备。** 打开页面/保存账号/健康检查/入队不授网络许可，`UploadCoordinator` 初始 false；用户单独允许仅本次会话，类型策略与会话许可独立，网络恢复只调度已确认意图，不解 pause/unknown/退避。替换/关闭清许可并先 gate 新派发。本地 processing 独立运行，无遥测、自动云账号或周期探测。 测试入口：协调器 UT-063 构造 idle、观察/设置不授许可、最后 runtime gate；`core/network_session_test.dart` 重开无许可；upload task widget 原图隐私；probes 惰性；备份/诊断出口需确认。

**缺失项/未验证：** 本库秘密和固定异常脱敏有本机边界证据；真实服务/账号及四端授权与存储PT未执行，未授权不外发。

**必要验证：** UT-063、UT-082、UT-098；AT-005、PT-006、REV-002。UT验证业务判断；真实依赖和流程由其他方案补证。

#### SEC-006 数据留存与卸载说明

属性：P1｜V1｜来源 SRC-U、WEB-10、SRC-O｜验证 UT、PT、AT

说明永久副本、回收、缓存、备份、日志和凭据的保留与清除方式。卸载可能清除应用数据但不会自动删除远程图床文件；用户应能在清除应用数据前导出备份。

验收：本地清除动作有影响说明；远端删除必须另行发起，不能暗示卸载已回收远端图片。

**当前状态：** Windows适用软件链已核对；最终运行与验收边界见E34，不代表正式四端条款全部验证通过。

**当前证据：** E34 [逐编号源码审查](validation/windows-network-software-audit.md)：**具备说明与独立清除。** `settings_screen.dart` “保留、备份与卸载”解释永久/回收/缓存/临时/诊断/凭据；回收30天仅提示，备份路径可达，卸载不保证系统凭据删除且不删远端；`link_results_screen.dart` 本地移除/远端删除独立确认。真实文件由持久引用及实际租约保护。 测试入口：`settings_screen_test.dart` UT-099 草稿/说明与真实备份路由；history/link/result/recycle/cache 清理测试各验证不越界与不扩大范围。真实卸载和设备保留行为排除，不伪称系统已删除凭据。

**缺失项/未验证：** 本库秘密和固定异常脱敏有本机边界证据；真实服务/账号及四端授权与存储PT未执行，未授权不外发。

**必要验证：** UT-019、UT-099；AT-004、PT-006、REV-002。UT验证业务判断；真实依赖和流程由其他方案补证。

### PLT

#### PLT-001 四端功能一致性

属性：P0｜V1｜来源 SRC-U｜验证 PT、AT

四端提供相同的核心业务能力及数据语义，允许针对键鼠、触摸和窗口形态使用不同交互。平台差异记录在能力矩阵，不强制相同页面、菜单或导航。

验收：四端分别完成 UC-01 至 UC-08，并保持相同业务断言。

**当前状态：** Windows适用软件链已核对；最终运行与验收边界见E34，不代表正式四端条款全部验证通过。

**当前证据：** E34 [逐编号源码审查](validation/windows-network-software-audit.md)：Windows 桌面 A 路由使用实际 LibrarySession、共同账号/任务/链接工作流和 Drift/文件/系统能力；M1 与桌面共用业务入口。此审查范围的软件链路具备。 测试入口：四端 UC 全流程 PT/AT 不由共同 domain 证明；其他端尚未接入能力不改记 Windows 软件缺口，不声称四端支持通过。

**缺失项/未验证：** Windows完整Release ZIP和Android专用签名ARM64 APK已本地生成并核验，见E37；这不是公开二进制或商店发布。Apple文件保存已接入，适用CI/模拟器验证与未完成项见E37及[里程碑29](milestone-29-apple-files.md)。真实系统选择器UI/Files提供者/照片格式互操作、iOS来源和完整四来源互读、物理设备/API29、设备PT及正式四端支持声明仍待完成。

**必要验证：** —；AT-006、PT-004、PT-005。四端实际功能一致性需设备与端到端证据，领域模拟无法证明交付。

#### PLT-002 系统资源生命周期

属性：P0｜V1｜来源 WEB-04、WEB-05、WEB-06｜验证 UT、PT

能处理部分授权、权限撤销、资源未下载、只读来源、未知原始大小和外部资源失效；永久副本已提交后不依赖原始授权保持可用。

验收：获取中撤权只影响未提交项；本机成功副本重启仍可读。

**当前状态：** Windows适用软件链已核对；最终运行与验收边界见E34，不代表正式四端条款全部验证通过。

**当前证据：** E34 [逐编号源码审查](validation/windows-network-software-audit.md)：Windows `ImportGateway` 文件选择、只读资源、source readiness、取消后真实 IO 收尾；来源丢失不影响已保存永久副本。软件具备。 测试入口：云 provider 未明确待获取的潜在内核阻塞不保证全部覆盖；外部设备/相册授权 PT 排除。

**缺失项/未验证：** Windows完整Release ZIP和Android专用签名ARM64 APK已本地生成并核验，见E37；这不是公开二进制或商店发布。Apple文件保存已接入，适用CI/模拟器验证与未完成项见E37及[里程碑29](milestone-29-apple-files.md)。真实系统选择器UI/Files提供者/照片格式互操作、iOS来源和完整四来源互读、物理设备/API29、设备PT及正式四端支持声明仍待完成。

**必要验证：** UT-004、UT-010、UT-094；PT-001。UT验证业务判断；真实依赖和流程由其他方案补证。

#### PLT-003 移动后台边界

属性：P0｜V1｜来源 WEB-07、WEB-08｜验证 UT、PT

允许在平台支持条件下继续任务，但不保证锁屏、退后台或强制退出后持续运行。系统终止与用户强制退出分别处理；重开恢复可解释状态并避免重复远端副作用。

验收：两类退出分别设备测试；没有无限 running 或虚假后台完成承诺。

**当前状态：** Windows适用软件链已核对；最终运行与验收边界见E34，不代表正式四端条款全部验证通过。

**当前证据：** E34 [逐编号源码审查](validation/windows-network-software-audit.md)：`SystemNetworkMonitor` 可见 inactive 与 hidden 区分、前台重读；会话 close/restore gates 与 `upload_exit.dart` 实际网络/处理/文件收尾，持久队列恢复。软件具备且说明限制。 测试入口：PT-002 真切网、系统后台/强退、硬件断电与计时精度排除；不承诺桌面隐藏或移动后台持续执行。

**缺失项/未验证：** Windows完整Release ZIP和Android专用签名ARM64 APK已本地生成并核验，见E37；这不是公开二进制或商店发布。Apple文件保存已接入，适用CI/模拟器验证与未完成项见E37及[里程碑29](milestone-29-apple-files.md)。真实系统选择器UI/Files提供者/照片格式互操作、iOS来源和完整四来源互读、物理设备/API29、设备PT及正式四端支持声明仍待完成。

**必要验证：** UT-062、UT-100；PT-002。UT验证业务判断；真实依赖和流程由其他方案补证。

#### PLT-004 输入与无障碍

属性：P1｜V1｜来源 SRC-S2、SRC-O｜验证 PT、AT

核心操作可通过平台主输入方式完成；提供可理解的操作名称、状态和错误，不能只靠颜色区分。桌面键盘可完成核心流程，移动端触摸目标与读屏语义可辨识。

验收：不识别颜色仍能区分成功失败；键盘或读屏能定位导入、选择、上传和错误恢复动作。

**当前状态：** Windows适用软件链已核对；最终运行与验收边界见E34，不代表正式四端条款全部验证通过。

**当前证据：** E34 [逐编号源码审查](validation/windows-network-software-audit.md)：账号、任务、链接使用可聚焦 Material controls，按钮 tooltip/动作文字、状态与原因文字，不仅颜色；公共 widget 有 Windows 尺寸测试，核心操作软件入口具备。 测试入口：人工全键盘/读屏/触摸/去颜色 AT/PT 未由源码或 widget 自动证明；不将“尚未做完整人工验收”直接判为软件未实现。

**缺失项/未验证：** Windows完整Release ZIP和Android专用签名ARM64 APK已本地生成并核验，见E37；这不是公开二进制或商店发布。Apple文件保存已接入，适用CI/模拟器验证与未完成项见E37及[里程碑29](milestone-29-apple-files.md)。真实系统选择器UI/Files提供者/照片格式互操作、iOS来源和完整四来源互读、物理设备/API29、设备PT及正式四端支持声明仍待完成。

**必要验证：** —；AT-006、PT-004。实际键盘/触摸/读屏、去颜色可辨识需设备验收。

#### PLT-005 系统复制保存与分享

属性：P1｜V1｜来源 SRC-U、SRC-O｜验证 UT、PT

遵从平台的文件导出、剪贴板和分享约束；拒绝、取消、能力缺失均反馈实际状态。不能把桌面绝对路径或无效系统引用当作跨端共享位置。

验收：移动端导出取消不报成功；在本机位置重建成功的恢复项可操作。

**当前状态：** Windows适用软件链已核对；最终运行与验收边界见E34，不代表正式四端条款全部验证通过。

**当前证据：** E34 [逐编号源码审查](validation/windows-network-software-audit.md)：Windows 选择目录真实导出、严格 Clipboard 和系统分享映射；拒绝/取消/缺能力分别反馈，本机路径不写可携带输入身份。软件具备。 测试入口：设备系统分享接收方保存、其他端原生导出 PT 单列；已禁用的移动导出不是 Windows 缺口。

**缺失项/未验证：** Windows完整Release ZIP和Android专用签名ARM64 APK已本地生成并核验，见E37；这不是公开二进制或商店发布。Apple文件保存已接入，适用CI/模拟器验证与未完成项见E37及[里程碑29](milestone-29-apple-files.md)。真实系统选择器UI/Files提供者/照片格式互操作、iOS来源和完整四来源互读、物理设备/API29、设备PT及正式四端支持声明仍待完成。

**必要验证：** UT-036、UT-071、UT-081；PT-003。UT验证业务判断；真实依赖和流程由其他方案补证。

#### PLT-006 平台支持声明

属性：P1｜V1｜来源 SRC-U、SRC-O｜验证 REV、PT

正式交付前分别公布四端支持的系统版本、安装方式、图片能力和后台限制，并在实际设备验证。具体最低版本与发布技术归后续技术设计，不以旧项目配置代替新版兼容性声明。

验收：发布验收有明确四端矩阵与设备证据；未验证平台不能标为已支持。

**当前状态：** Windows适用软件链已核对；最终运行与验收边界见E34，不代表正式四端条款全部验证通过。

**当前证据：** E34 [逐编号源码审查](validation/windows-network-software-audit.md)：`AGENTS.md` 与当前环境/平台文档分别记系统目标、Windows 构建证据及未实测平台；账号资料维护入口不宣称真实远端通过。 测试入口：正式发行安装方式/签名/完整四端支持矩阵和设备证据仍为发布/设备验收，不由本报告宣告正式四端交付。

**缺失项/未验证：** Windows完整Release ZIP和Android专用签名ARM64 APK已本地生成并核验，见E37；这不是公开二进制或商店发布。Apple文件保存已接入，适用CI/模拟器验证与未完成项见E37及[里程碑29](milestone-29-apple-files.md)。真实系统选择器UI/Files提供者/照片格式互操作、iOS来源和完整四来源互读、物理设备/API29、设备PT及正式四端支持声明仍待完成。

**必要验证：** —；PT-005、REV-001。支持系统版本/安装方式和实际设备证据由兼容性声明审查。

### NFR

#### NFR-001 操作响应

属性：P1｜V1｜来源 SRC-O｜验证 PERF、PT

常规操作在参考负载下 300 毫秒内给出已接收或可解释反馈，元数据检索与筛选 P95 不超过 1 秒；重处理期间仍能取消、切换任务信息和浏览已载入记录。

验收：每平台测量至少 30 次常规操作及 100 次检索，记录分位值与条件；不得以动画代替数据完成。

**当前状态：** Windows适用软件链已核对；最终运行与验收边界见E34，不代表正式四端条款全部验证通过。

**当前证据：** E34 [逐编号源码审查](validation/windows-library-software-audit.md)：软件响应基础具备，数值性能另行排除。像素/备份重活isolate，流式IO、进度/停止、分页检索，工作台运行仍能读已载入元信息/任务；没有用动画代替持久完成。 测试入口：controller/workbench取消与进度测试、gallery分页/revision测试、processing真实worker取消与IO排空测试。300ms与P95≤1s及30/100次参考硬件测量不由源码或单测证明。

**缺失项/未验证：** 软件保护/渐进加载/有界资源已接入；参考硬件响应、冷启动、内存/存储压力、断电与完整人工AT未测，候选预算不标实测。

**必要验证：** —；PERF-001、PT-007。时间与分位目标需固定参考负载实测，UT仅能检查逻辑。

#### NFR-002 首次可用与渐进加载

属性：P1｜V1｜来源 SRC-O｜验证 PERF、PT

参考元数据负载下冷启动 5 秒内进入可操作的本地工作状态；缩略图和后台校验渐进加载，不要求读取全部原图后才可使用。

验收：四端分别记录冷启动结果；图片缺失不阻断其他资产浏览。

**当前状态：** Windows适用软件链已核对；最终运行与验收边界见E34，不代表正式四端条款全部验证通过。

**当前证据：** E34 [逐编号源码审查](validation/windows-library-software-audit.md)：渐进加载具备，5秒数值另行排除。`GalleryController.build/listAssets(limit:60)` 先读元信息，分页与按显示对象产生缓存预览，不读取全部原图后才展示；缺损状态不清空其他对象。启动必要恢复/日志校验会阻止不安全库使用，不能绕过以追求速度。 测试入口：`gallery_controller_test.dart` 首批/分页/旧结果隔离；UT-012 缺损保留元信息；缓存再生及original reader独立测试。四端/参考硬件冷启动时间未在本报告宣称通过。

**缺失项/未验证：** 软件保护/渐进加载/有界资源已接入；参考硬件响应、冷启动、内存/存储压力、断电与完整人工AT未测，候选预算不标实测。

**必要验证：** —；PERF-002、PT-007。冷启动与渐进可用需实际设备计时。

#### NFR-003 空间与内存受控

属性：P0｜V1｜来源 SRC-C4、SRC-O｜验证 UT、PERF、PT

缓存有容量与到期边界，处理并发与输出预算受控；输入超预算不能导致无限排队、巨大无界画布或删除永久图片来腾空间。平台压力出现时降低新任务派发并反馈原因。

验收：大量长图与低空间压力场景可解释地拒绝或等待，已保存数据仍完整。

**当前状态：** Windows适用软件链已核对；最终运行与验收边界见E34，不代表正式四端条款全部验证通过。

**当前证据：** E34 [逐编号源码审查](validation/windows-library-software-audit.md)：具备当前Windows软件接线。设置缓存64–2048MiB/输出保留期，LRU登记日志及保护；空间探测先于新增写入；Scheduler预算/并发有界。`SystemMemoryPressureMonitor` 在Windows建 `Kernel32MemoryPressureSignal`（Create/QueryMemoryResourceNotification），即时读/2秒候选轮询+Flutter binding；`LibrarySession` 先订阅再start，事件调用reportMemoryPressure，降低新派发/反馈、不取消旧预算；关闭释放定时器/观察/handle。 测试入口：`core/processing_scheduler_test.dart`、`core/processing_memory_pressure_test.dart`；`core/system_memory_pressure_monitor_test.dart` native边缘/失败/关闭；`core/windows_memory_pressure_signal_test.dart` Win32 API边界；`core/memory_pressure_session_test.dart` 真实session→scheduler/设置反馈；`core/cache_policy_test.dart`、`core/storage_repository_test.dart` 真实缓存日志/清理与storage容量测试。API接线是源码证据，最终主机验证及硬件压力阈值不在本审查冒充通过。

**缺失项/未验证：** 软件保护/渐进加载/有界资源已接入；参考硬件响应、冷启动、内存/存储压力、断电与完整人工AT未测，候选预算不标实测。

**必要验证：** UT-032、UT-086、UT-088、UT-101；PERF-003、PT-007。UT验证业务判断；真实依赖和流程由其他方案补证。

#### NFR-004 故障可恢复

属性：P0｜V1｜来源 SRC-O｜验证 UT、IT、PT

导入、保存、上传结果提交、清理和恢复在任一阶段中断后，都能回到已验证状态或明确待修复状态。不能因一项失败静默清库或误报整批成功。

验收：故障注入检查每个持久化边界；已确认数据与外部原图保持完整。

**当前状态：** Windows适用软件链已核对；最终运行与验收边界见E34，不代表正式四端条款全部验证通过。

**当前证据：** E34 [逐编号源码审查](validation/windows-library-software-audit.md)：具备可验证状态/保留待修复路径。启动先恢复替换日志，再其他维护；各日志白名单路径/归属/摘要校验后才清，篡改或未知文件保留现场；流/线程/network actual收尾前保护不可解除。异常单项/批次状态真实，无静默清库。 测试入口：导入boundary/源取消、output生命周期、upload提交/晚到证据、backup merge/replace/restore故障测试及IT-010；`core/backup_zip_reader_test.dart` “changed verified image digest preserves every known file ... allows restored bytes retry”避免旧fixture期待被当作生产清理要求。真实断电/文件系统硬件行为排除。

**缺失项/未验证：** 软件保护/渐进加载/有界资源已接入；参考硬件响应、冷启动、内存/存储压力、断电与完整人工AT未测，候选预算不标实测。

**必要验证：** UT-003、UT-080、UT-091；IT-004、PERF-004、PT-007。UT验证业务判断；真实依赖和流程由其他方案补证。

#### NFR-005 可理解与可验证

属性：P1｜V1｜来源 SRC-S2、WEB-12、SRC-O｜验证 REV、AT

首版提供简体中文的业务名称、单位、进度、错误与恢复动作；“无损”“续传”“永久”“已保存”等词必须符合实际行为。每条需求有来源及验证方法，未来阶段不混入首版完成状态。

验收：用户不查看诊断细节也能处理常见失败；正式文档无无验收条件的“可靠”“快速”承诺。

**当前状态：** Windows适用软件链已核对；最终运行与验收边界见E34，不代表正式四端条款全部验证通过。

**当前证据：** E34 [逐编号源码审查](validation/windows-library-software-audit.md)：具备常见操作中文说明/单位/恢复入口。错误固定分类；界面区分获取、已保存、取消等待、缺损、未知远端结果、原图隐私、静态转换、有损/增大；损坏打开指导保全而不假修复。需求原件有逐条来源与UT/IT/PT/AT设计，本报告提供当前软件映射。 测试入口：`library_failure_view_test.dart`、`import_stop_feedback_test.dart`、`gallery_import_exit_test.dart`、workbench状态/背景/静态帧测试及桌面IT。完整人工AT未执行不自动等于缺软件，也不能仅凭widget通过声称每条文案/平台人工验收完成。

**缺失项/未验证：** 软件保护/渐进加载/有界资源已接入；参考硬件响应、冷启动、内存/存储压力、断电与完整人工AT未测，候选预算不标实测。

**必要验证：** —；AT-006、REV-001、REV-003。中文可理解性、术语与完整追踪需审查和用户流程。

## 全部 UT 设计登记（112）

下表是设计追踪，不是运行结果；V1 102项，V2 10项。实际每编号须逐参数化边界记录结果，不能按测试函数个数计算正式需求完成。

| 编号 | 原设计场景 | 阶段 | 正式需求关联 | 实际登记 |
| --- | --- | --- | --- | --- |
| UT-001 | 选图获取与取消 | V1 | IMP-001、IMP-007 | 本机实际结果见E34，对应源码/测试边界见逐编号审查；不据全量数量宣称本设计整项通过 |
| UT-002 | 内容识别不依赖扩展名 | V1 | IMP-002 | 本机实际结果见E34，对应源码/测试边界见逐编号审查；不据全量数量宣称本设计整项通过 |
| UT-003 | 副本提交故障边界 | V1 | IMP-003、DAT-002、NFR-004 | 本机实际结果见E34，对应源码/测试边界见逐编号审查；不据全量数量宣称本设计整项通过 |
| UT-004 | 提交后来源失权 | V1 | IMP-003、PLT-002 | 本机实际结果见E34，对应源码/测试边界见逐编号审查；不据全量数量宣称本设计整项通过 |
| UT-005 | 同内容去重保留整理 | V1 | IMP-004、DAT-003 | 本机实际结果见E34，对应源码/测试边界见逐编号审查；不据全量数量宣称本设计整项通过 |
| UT-006 | 同名同大小不同内容 | V1 | IMP-004、DAT-003 | 本机实际结果见E34，对应源码/测试边界见逐编号审查；不据全量数量宣称本设计整项通过 |
| UT-007 | 重复导入回收资产 | V1 | IMP-004、LIB-007 | 本机实际结果见E34，对应源码/测试边界见逐编号审查；不据全量数量宣称本设计整项通过 |
| UT-008 | 导入部分成功与重复事件 | V1 | IMP-005 | 本机实际结果见E34，对应源码/测试边界见逐编号审查；不据全量数量宣称本设计整项通过 |
| UT-009 | 元信息与时区 | V1 | IMP-006、DAT-004 | 本机实际结果见E34，对应源码/测试边界见逐编号审查；不据全量数量宣称本设计整项通过 |
| UT-010 | 获取错误分类与恢复 | V1 | IMP-007、PLT-002 | 本机实际结果见E34，对应源码/测试边界见逐编号审查；不据全量数量宣称本设计整项通过 |
| UT-011 | 停止批次与授权目录 | V1 | IMP-008 | 本机实际结果见E34，对应源码/测试边界见逐编号审查；不据全量数量宣称本设计整项通过 |
| UT-012 | 缩略图与本机可用性 | V1 | LIB-001 | 本机实际结果见E34，对应源码/测试边界见逐编号审查；不据全量数量宣称本设计整项通过 |
| UT-013 | 筛选变化不扩大选择 | V1 | LIB-002 | 本机实际结果见E34，对应源码/测试边界见逐编号审查；不据全量数量宣称本设计整项通过 |
| UT-014 | 标签连续输入与规范化 | V1 | LIB-003 | 本机实际结果见E34，对应源码/测试边界见逐编号审查；不据全量数量宣称本设计整项通过 |
| UT-015 | 标签数量与名称边界 | V1 | LIB-003、OPS-005 | 本机实际结果见E34，对应源码/测试边界见逐编号审查；不据全量数量宣称本设计整项通过 |
| UT-016 | 分类收藏保留无关字段 | V1 | LIB-004 | 本机实际结果见E34，对应源码/测试边界见逐编号审查；不据全量数量宣称本设计整项通过 |
| UT-017 | 字段检索与交集筛选 | V1 | LIB-005、LNK-001 | 本机实际结果见E34，对应源码/测试边界见逐编号审查；不据全量数量宣称本设计整项通过 |
| UT-018 | 稳定排序与空上传时间 | V1 | LIB-006 | 本机实际结果见E34，对应源码/测试边界见逐编号审查；不据全量数量宣称本设计整项通过 |
| UT-019 | 回收到期不自动清除 | V1 | LIB-007、SEC-006 | 本机实际结果见E34，对应源码/测试边界见逐编号审查；不据全量数量宣称本设计整项通过 |
| UT-020 | 永久清除的共享与活跃保护 | V1 | LIB-007、LIB-008 | 本机实际结果见E34，对应源码/测试边界见逐编号审查；不据全量数量宣称本设计整项通过 |
| UT-021 | 副本修复的内容匹配 | V1 | LIB-008、DAT-003 | 本机实际结果见E34，对应源码/测试边界见逐编号审查；不据全量数量宣称本设计整项通过 |
| UT-022 | 离线独立处理不覆盖 | V1 | IMG-001 | 本机实际结果见E34，对应源码/测试边界见逐编号审查；不据全量数量宣称本设计整项通过 |
| UT-023 | 保真能力不足停止 | V1 | IMG-002、IMG-004 | 本机实际结果见E34，对应源码/测试边界见逐编号审查；不据全量数量宣称本设计整项通过 |
| UT-024 | 等比尺寸与最长边边界 | V1 | IMG-003 | 本机实际结果见E34，对应源码/测试边界见逐编号审查；不据全量数量宣称本设计整项通过 |
| UT-025 | 质量策略与格式匹配 | V1 | IMG-003、OPS-005 | 本机实际结果见E34，对应源码/测试边界见逐编号审查；不据全量数量宣称本设计整项通过 |
| UT-026 | 静态和动画能力匹配 | V1 | IMG-004 | 本机实际结果见E34，对应源码/测试边界见逐编号审查；不据全量数量宣称本设计整项通过 |
| UT-027 | 透明转换背景确认 | V1 | IMG-004 | 本机实际结果见E34，对应源码/测试边界见逐编号审查；不据全量数量宣称本设计整项通过 |
| UT-028 | 方向和隐私计划 | V1 | IMG-005 | 本机实际结果见E34，对应源码/测试边界见逐编号审查；不据全量数量宣称本设计整项通过 |
| UT-029 | 裁剪像素边界 | V1 | IMG-006 | 本机实际结果见E34，对应源码/测试边界见逐编号审查；不据全量数量宣称本设计整项通过 |
| UT-030 | 横纵拼接与间距 | V1 | IMG-007 | 本机实际结果见E34，对应源码/测试边界见逐编号审查；不据全量数量宣称本设计整项通过 |
| UT-031 | 网格空格与居中 | V1 | IMG-007 | 本机实际结果见E34，对应源码/测试边界见逐编号审查；不据全量数量宣称本设计整项通过 |
| UT-032 | 资源预算先于分配 | V1 | IMG-008、NFR-003 | 本机实际结果见E34，对应源码/测试边界见逐编号审查；不据全量数量宣称本设计整项通过 |
| UT-033 | 批次处理参数快照 | V1 | IMG-009、UPL-001 | 本机实际结果见E34，对应源码/测试边界见逐编号审查；不据全量数量宣称本设计整项通过 |
| UT-034 | 临时结果恢复与收益 | V1 | OUT-001、OUT-005 | 本机实际结果见E34，对应源码/测试边界见逐编号审查；不据全量数量宣称本设计整项通过 |
| UT-035 | 临时结果永久保存 | V1 | OUT-002、DAT-002 | 本机实际结果见E34，对应源码/测试边界见逐编号审查；不据全量数量宣称本设计整项通过 |
| UT-036 | 导出同名与部分失败 | V1 | OUT-003、PLT-005 | 本机实际结果见E34，对应源码/测试边界见逐编号审查；不据全量数量宣称本设计整项通过 |
| UT-037 | 恰到期清理与删除失败 | V1 | OUT-004 | 本机实际结果见E34，对应源码/测试边界见逐编号审查；不据全量数量宣称本设计整项通过 |
| UT-038 | 六类活跃状态清理保护 | V1 | OUT-004、QUE-010 | 本机实际结果见E34，对应源码/测试边界见逐编号审查；不据全量数量宣称本设计整项通过 |
| UT-039 | 未知图床能力 | V1 | ACC-001、ACC-006 | 本机实际结果见E34，对应源码/测试边界见逐编号审查；不据全量数量宣称本设计整项通过 |
| UT-040 | 多账号与匿名目标隔离 | V1 | ACC-002 | 本机实际结果见E34，对应源码/测试边界见逐编号审查；不据全量数量宣称本设计整项通过 |
| UT-041 | 配置验证不上传图片 | V1 | ACC-003 | 本机实际结果见E34，对应源码/测试边界见逐编号审查；不据全量数量宣称本设计整项通过 |
| UT-042 | 目标选择和新增账号 | V1 | ACC-004 | 本机实际结果见E34，对应源码/测试边界见逐编号审查；不据全量数量宣称本设计整项通过 |
| UT-043 | 凭据更新停用与删除 | V1 | ACC-005、UPL-001、UPL-005 | 本机实际结果见E34，对应源码/测试边界见逐编号审查；不据全量数量宣称本设计整项通过 |
| UT-044 | 上传输入版本冻结 | V1 | UPL-001 | 本机实际结果见E34，对应源码/测试边界见逐编号审查；不据全量数量宣称本设计整项通过 |
| UT-045 | 多目标错误隔离 | V1 | UPL-002、QUE-009 | 本机实际结果见E34，对应源码/测试边界见逐编号审查；不据全量数量宣称本设计整项通过 |
| UT-046 | 处理依赖复用和失败 | V1 | UPL-003 | 本机实际结果见E34，对应源码/测试边界见逐编号审查；不据全量数量宣称本设计整项通过 |
| UT-047 | 校验实际输出限制 | V1 | UPL-004 | 本机实际结果见E34，对应源码/测试边界见逐编号审查；不据全量数量宣称本设计整项通过 |
| UT-048 | 有效响应与结果幂等 | V1 | UPL-005、DAT-004、UPL-001 | 本机实际结果见E34，对应源码/测试边界见逐编号审查；不据全量数量宣称本设计整项通过 |
| UT-049 | 成功复用与显式再传 | V1 | UPL-006 | 本机实际结果见E34，对应源码/测试边界见逐编号审查；不据全量数量宣称本设计整项通过 |
| UT-050 | 本地结果与远端删除 | V1 | UPL-007 | 本机实际结果见E34，对应源码/测试边界见逐编号审查；不据全量数量宣称本设计整项通过 |
| UT-051 | 入队持久化与重启 | V1 | QUE-001、DAT-001 | 本机实际结果见E34，对应源码/测试边界见逐编号审查；不据全量数量宣称本设计整项通过 |
| UT-052 | 独立有界并发 | V1 | QUE-002 | 本机实际结果见E34，对应源码/测试边界见逐编号审查；不据全量数量宣称本设计整项通过 |
| UT-053 | 动态降低有效并发 | V1 | QUE-002、OPS-001 | 本机实际结果见E34，对应源码/测试边界见逐编号审查；不据全量数量宣称本设计整项通过 |
| UT-054 | 暂停与继续派发 | V1 | QUE-003 | 本机实际结果见E34，对应源码/测试边界见逐编号审查；不据全量数量宣称本设计整项通过 |
| UT-055 | 成功先到取消后到 | V1 | QUE-004 | 本机实际结果见E34，对应源码/测试边界见逐编号审查；不据全量数量宣称本设计整项通过 |
| UT-056 | 取消先到旧尝试迟到 | V1 | QUE-004、UPL-002 | 本机实际结果见E34，对应源码/测试边界见逐编号审查；不据全量数量宣称本设计整项通过 |
| UT-057 | 取消阻止派发 | V1 | QUE-004 | 本机实际结果见E34，对应源码/测试边界见逐编号审查；不据全量数量宣称本设计整项通过 |
| UT-058 | 证据驱动错误分类 | V1 | QUE-005 | 本机实际结果见E34，对应源码/测试边界见逐编号审查；不据全量数量宣称本设计整项通过 |
| UT-059 | 四次执行与退避边界 | V1 | QUE-006 | 本机实际结果见E34，对应源码/测试边界见逐编号审查；不据全量数量宣称本设计整项通过 |
| UT-060 | 非自动重试类别 | V1 | QUE-006 | 本机实际结果见E34，对应源码/测试边界见逐编号审查；不据全量数量宣称本设计整项通过 |
| UT-061 | 多条件等待与服务端延时 | V1 | QUE-006、QUE-008 | 本机实际结果见E34，对应源码/测试边界见逐编号审查；不据全量数量宣称本设计整项通过 |
| UT-062 | 中断恢复区分副作用 | V1 | QUE-007、PLT-003 | 本机实际结果见E34，对应源码/测试边界见逐编号审查；不据全量数量宣称本设计整项通过 |
| UT-063 | 网络许可和重复唤醒 | V1 | QUE-008、SEC-005 | 本机实际结果见E34，对应源码/测试边界见逐编号审查；不据全量数量宣称本设计整项通过 |
| UT-064 | 真实进度与依赖收尾 | V1 | QUE-009 | 本机实际结果见E34，对应源码/测试边界见逐编号审查；不据全量数量宣称本设计整项通过 |
| UT-065 | 六种聚合及事件全排列 | V1 | UPL-002、QUE-009 | 本机实际结果见E34，对应源码/测试边界见逐编号审查；不据全量数量宣称本设计整项通过 |
| UT-066 | 历史清理不删依赖 | V1 | QUE-010 | 本机实际结果见E34，对应源码/测试边界见逐编号审查；不据全量数量宣称本设计整项通过 |
| UT-067 | 墙钟与持续时间 | V1 | QUE-006、DAT-004 | 本机实际结果见E34，对应源码/测试边界见逐编号审查；不据全量数量宣称本设计整项通过 |
| UT-068 | 无活动和总运行超时 | V1 | QUE-007、QUE-009 | 本机实际结果见E34，对应源码/测试边界见逐编号审查；不据全量数量宣称本设计整项通过 |
| UT-069 | 四格式转义与危险链接 | V1 | LNK-001、SEC-003 | 本机实际结果见E34，对应源码/测试边界见逐编号审查；不据全量数量宣称本设计整项通过 |
| UT-070 | 批量链接顺序与去重 | V1 | LNK-002、LNK-001 | 本机实际结果见E34，对应源码/测试边界见逐编号审查；不据全量数量宣称本设计整项通过 |
| UT-071 | 系统复制分享错误 | V1 | LNK-003、PLT-005 | 本机实际结果见E34，对应源码/测试边界见逐编号审查；不据全量数量宣称本设计整项通过 |
| UT-072 | 链接状态和主动探测 | V1 | LNK-004、UPL-006 | 本机实际结果见E34，对应源码/测试边界见逐编号审查；不据全量数量宣称本设计整项通过 |
| UT-073 | 两种备份的数据边界 | V1 | BAK-001、BAK-002 | 本机实际结果见E34，对应源码/测试边界见逐编号审查；不据全量数量宣称本设计整项通过 |
| UT-074 | 一致备份与秘密排除 | V1 | BAK-002、SEC-002 | 本机实际结果见E34，对应源码/测试边界见逐编号审查；不据全量数量宣称本设计整项通过 |
| UT-075 | 恢复预校验与越界保护 | V1 | BAK-003 | 本机实际结果见E34，对应源码/测试边界见逐编号审查；不据全量数量宣称本设计整项通过 |
| UT-076 | 合并整理和身份重映射 | V1 | BAK-004 | 本机实际结果见E34，对应源码/测试边界见逐编号审查；不据全量数量宣称本设计整项通过 |
| UT-077 | 身份内容冲突与回收状态 | V1 | BAK-004 | 本机实际结果见E34，对应源码/测试边界见逐编号审查；不据全量数量宣称本设计整项通过 |
| UT-078 | 同URL不同发布历史 | V1 | BAK-004、UPL-005 | 本机实际结果见E34，对应源码/测试边界见逐编号审查；不据全量数量宣称本设计整项通过 |
| UT-079 | 恢复提交与在途写入 | V1 | BAK-004、QUE-004 | 本机实际结果见E34，对应源码/测试边界见逐编号审查；不据全量数量宣称本设计整项通过 |
| UT-080 | 替换故障和旧事件隔离 | V1 | BAK-004、DAT-002、NFR-004 | 本机实际结果见E34，对应源码/测试边界见逐编号审查；不据全量数量宣称本设计整项通过 |
| UT-081 | 跨端位置和账号重配 | V1 | BAK-005、PLT-005 | 本机实际结果见E34，对应源码/测试边界见逐编号审查；不据全量数量宣称本设计整项通过 |
| UT-082 | 备份取消与完整性 | V1 | BAK-006、SEC-005 | 本机实际结果见E34，对应源码/测试边界见逐编号审查；不据全量数量宣称本设计整项通过 |
| UT-083 | 设置保存反馈与重启 | V1 | OPS-001、DAT-001 | 本机实际结果见E34，对应源码/测试边界见逐编号审查；不据全量数量宣称本设计整项通过 |
| UT-084 | 诊断关联查看与清空 | V1 | OPS-002 | 本机实际结果见E34，对应源码/测试边界见逐编号审查；不据全量数量宣称本设计整项通过 |
| UT-085 | 诊断导出全链路脱敏 | V1 | OPS-003、SEC-004 | 本机实际结果见E34，对应源码/测试边界见逐编号审查；不据全量数量宣称本设计整项通过 |
| UT-086 | 分类空间管理与低空间 | V1 | OPS-004、NFR-003 | 本机实际结果见E34，对应源码/测试边界见逐编号审查；不据全量数量宣称本设计整项通过 |
| UT-087 | 默认并发参数边界 | V1 | OPS-005 | 本机实际结果见E34，对应源码/测试边界见逐编号审查；不据全量数量宣称本设计整项通过 |
| UT-088 | 缓存容量与保护超限 | V1 | OUT-004、OPS-001、OPS-005、NFR-003 | 本机实际结果见E34，对应源码/测试边界见逐编号审查；不据全量数量宣称本设计整项通过 |
| UT-089 | 日志双留存边界 | V1 | OPS-002、OPS-003 | 本机实际结果见E34，对应源码/测试边界见逐编号审查；不据全量数量宣称本设计整项通过 |
| UT-090 | 加载失败禁止空库覆盖 | V1 | DAT-001 | 本机实际结果见E34，对应源码/测试边界见逐编号审查；不据全量数量宣称本设计整项通过 |
| UT-091 | 关联故障与恢复 | V1 | DAT-002、NFR-004 | 本机实际结果见E34，对应源码/测试边界见逐编号审查；不据全量数量宣称本设计整项通过 |
| UT-092 | 事件重放和跨时区 | V1 | DAT-004 | 本机实际结果见E34，对应源码/测试边界见逐编号审查；不据全量数量宣称本设计整项通过 |
| UT-093 | 自身格式升级失败保护 | V1 | DAT-005 | 本机实际结果见E34，对应源码/测试边界见逐编号审查；不据全量数量宣称本设计整项通过 |
| UT-094 | 最小权限不阻本地 | V1 | SEC-001、PLT-002 | 本机实际结果见E34，对应源码/测试边界见逐编号审查；不据全量数量宣称本设计整项通过 |
| UT-095 | 秘密存储不可用与删除 | V1 | SEC-002、ACC-005 | 本机实际结果见E34，对应源码/测试边界见逐编号审查；不据全量数量宣称本设计整项通过 |
| UT-096 | 传输安全与链接协议 | V1 | SEC-003 | 本机实际结果见E34，对应源码/测试边界见逐编号审查；不据全量数量宣称本设计整项通过 |
| UT-097 | 所有普通出口脱敏 | V1 | SEC-004 | 本机实际结果见E34，对应源码/测试边界见逐编号审查；不据全量数量宣称本设计整项通过 |
| UT-098 | 外发必须主动授权 | V1 | SEC-005 | 本机实际结果见E34，对应源码/测试边界见逐编号审查；不据全量数量宣称本设计整项通过 |
| UT-099 | 清除与卸载影响说明 | V1 | SEC-006 | 本机实际结果见E34，对应源码/测试边界见逐编号审查；不据全量数量宣称本设计整项通过 |
| UT-100 | 平台生命周期状态模型 | V1 | PLT-003、QUE-007 | 本机实际结果见E34，对应源码/测试边界见逐编号审查；不据全量数量宣称本设计整项通过 |
| UT-101 | 压力下新任务派发 | V1 | NFR-003 | 本机实际结果见E34，对应源码/测试边界见逐编号审查；不据全量数量宣称本设计整项通过 |
| UT-102 | 取消未安全结束仍保护文件 | V1 | QUE-004、OUT-004、LIB-007、LIB-008 | 本机实际结果见E34，对应源码/测试边界见逐编号审查；不据全量数量宣称本设计整项通过 |
| UT-103 | 同步启停与迟到响应 | V2，排除首版 | SYN-001 | V2排除首版，本轮未执行 |
| UT-104 | 同步字段白名单 | V2，排除首版 | SYN-002 | V2排除首版，本轮未执行 |
| UT-105 | 信息资产与本机重关联 | V2，排除首版 | SYN-003 | V2排除首版，本轮未执行 |
| UT-106 | 独立标签合并幂等 | V2，排除首版 | SYN-004 | V2排除首版，本轮未执行 |
| UT-107 | 并发字段冲突有效值 | V2，排除首版 | SYN-004 | V2排除首版，本轮未执行 |
| UT-108 | 冲突解决与重放 | V2，排除首版 | SYN-004 | V2排除首版，本轮未执行 |
| UT-109 | 删除传播与并发编辑 | V2，排除首版 | SYN-005 | V2排除首版，本轮未执行 |
| UT-110 | 重开基线和重复变更 | V2，排除首版 | SYN-006 | V2排除首版，本轮未执行 |
| UT-111 | 身份切换与秘密清除 | V2，排除首版 | SYN-007 | V2排除首版，本轮未执行 |
| UT-112 | 同步故障不阻本地 | V2，排除首版 | SYN-008 | V2排除首版，本轮未执行 |

## 全部其他验证方案登记（39）

各方案完整操作、预期与不变量在权威测试设计第6章。已有E1/E2仅部分IT/AT/PT子证据；尚无整套方案通过记录。

| 编号 | 原设计方案 | 阶段 | 正式需求关联 | 当前验证边界 |
| --- | --- | --- | --- | --- |
| CT-001 | 服务能力与官方限制 | V1 | ACC-001、ACC-003、ACC-006、UPL-004、LNK-004 | 依逐条缺口取得实际证据；本次未运行 |
| CT-002 | 图床响应与错误契约 | V1 | UPL-002、UPL-004、UPL-005、QUE-005、QUE-006、UPL-006、QUE-009 | 依逐条缺口取得实际证据；本次未运行 |
| CT-003 | 取消与远端删除契约 | V1 | UPL-007、QUE-004、ACC-005 | 依逐条缺口取得实际证据；本次未运行 |
| CT-004 | 图片能力契约 | V1 | IMG-002、IMG-003、IMG-004、IMG-005、IMG-008 | 依逐条缺口取得实际证据；本次未运行 |
| CT-005 | 链接与安全传输契约 | V1 | LNK-001、SEC-003 | 依逐条缺口取得实际证据；本次未运行 |
| CT-006 | 新版备份与版本契约 | V1 | BAK-001、BAK-002、BAK-003、BAK-005、DAT-005 | 依逐条缺口取得实际证据；本次未运行 |
| CT-007 | 未来同步载荷契约 | V2 | SYN-002、SYN-008 | 后续阶段设计，排除V1通过数 |
| IT-001 | 真实导入与副本 | V1 | IMP-002、IMP-003、IMP-004、IMP-005、IMP-006、LIB-008、DAT-003 | 依逐条缺口取得实际证据；本次未运行 |
| IT-002 | 真实编解码与几何 | V1 | IMG-001、IMG-002、IMG-003、IMG-004、IMG-005、IMG-006、IMG-007、IMG-008 | 依逐条缺口取得实际证据；本次未运行 |
| IT-003 | 输出生命周期 | V1 | IMG-009、OUT-001、OUT-002、OUT-003、OUT-004、OUT-005 | E11 Windows 原生引擎 1 项及 6 输出进程恢复子场景通过；系统取得边界替换，四端未闭合 |
| IT-004 | 任务持久化与中断 | V1 | QUE-001、QUE-007、QUE-010、UPL-001、UPL-003、UPL-005、DAT-001、DAT-002、DAT-004、NFR-004 | E14/E29真实库/文件/像素、运行日志恢复、关闭/维护排空及Windows原生任务/处理输出身份重开子流程通过；硬件强退/真实服务和完整四端方案仍待 |
| IT-005 | 真实备份恢复 | V1 | BAK-001、BAK-002、BAK-003、BAK-004、BAK-005、BAK-006 | E17–19/E29/E30有Windows真实两模式ZIP、合并/替换/失败回滚、永久字节/系统秘密及设置重开子流程；真实选择器、四端互读、完整人工与大包设计范围仍未全部运行 |
| IT-006 | 设置日志与版本恢复 | V1 | OPS-001、OPS-002、OPS-003、OPS-004、DAT-005、SEC-004 | E24设置及E25诊断Windows原生真实保存/重开/文件导出/清日志保留PNG子闭环通过；空间/完整版本恢复、系统选择器与全平台流程未验收 |
| IT-007 | 秘密存储集成 | V1 | ACC-005、SEC-002、SEC-004 | E12 Windows 原生构建/系统写读/资料库重开/同名隔离/删除读回通过；删除管理秘密和其他平台/完整集成待补 |
| IT-008 | 受控网络联调 | V1 | UPL-002、UPL-004、UPL-005、UPL-006、UPL-007、QUE-004、QUE-005、QUE-006、LNK-004、SEC-003 | 依逐条缺口取得实际证据；本次未运行 |
| IT-009 | 未来多设备同步集成 | V2 | SYN-001、SYN-002、SYN-003、SYN-004、SYN-005、SYN-006、SYN-007、SYN-008 | 后续阶段设计，排除V1通过数 |
| IT-010 | 图库回收与引用清除 | V1 | LIB-001、LIB-007、LIB-008 | 依逐条缺口取得实际证据；本次未运行 |
| PT-001 | 真实资源与授权 | V1 | IMP-001、IMP-003、IMP-007、IMP-008、LIB-001、SEC-001、PLT-002 | 依逐条缺口取得实际证据；本次未运行 |
| PT-002 | 平台生命周期和网络 | V1 | QUE-003、QUE-004、QUE-007、QUE-008、QUE-010、PLT-003 | E28 Windows真实默认路径读取/首次监听/任务页和无外发子流程通过；未切换用户网络，移动/离线/硬件强退及完整PT仍待 |
| PT-003 | 系统输出能力 | V1 | OUT-003、BAK-006、OPS-003、LNK-001、LNK-003、PLT-005 | 依逐条缺口取得实际证据；本次未运行 |
| PT-004 | 跨端主输入与无障碍 | V1 | PLT-001、PLT-004 | 依逐条缺口取得实际证据；本次未运行 |
| PT-005 | 跨端备份与支持声明 | V1 | BAK-005、PLT-001、PLT-006 | 依逐条缺口取得实际证据；本次未运行 |
| PT-006 | 平台秘密与留存 | V1 | SEC-002、SEC-003、SEC-006、SEC-005 | 依逐条缺口取得实际证据；本次未运行 |
| PT-007 | 设备负载与故障 | V1 | NFR-001、NFR-002、NFR-003、NFR-004 | 依逐条缺口取得实际证据；本次未运行 |
| AT-001 | 导入整理检索流程 | V1 | IMP-001、IMP-005、IMP-008、LIB-001、LIB-002、LIB-003、LIB-004、LIB-005、LIB-006 | 依逐条缺口取得实际证据；本次未运行 |
| AT-002 | 处理保存导出流程 | V1 | IMG-001、IMG-003、IMG-006、IMG-007、IMG-009、OUT-002、OUT-003、OUT-005 | E11 核心/widget/Windows 引擎真实处理保存导出子流程；完整人工 AT 未验收 |
| AT-003 | 多目标任务与管理流程 | V1 | ACC-001、ACC-002、ACC-003、ACC-004、ACC-005、UPL-001、UPL-005、LNK-001、UPL-007、QUE-003、QUE-009、QUE-010 | E12 账号配置 widget 子场景通过；上传/任务及完整人工 AT 尚未完成 |
| AT-004 | 链接清理留存流程 | V1 | LNK-001、LNK-002、LNK-004、ACC-005、LIB-007、LIB-008、OPS-004、SEC-006 | 依逐条缺口取得实际证据；本次未运行 |
| AT-005 | 备份设置诊断流程 | V1 | BAK-001、BAK-004、BAK-006、OPS-002、OPS-005、SEC-005 | 依逐条缺口取得实际证据；本次未运行 |
| AT-006 | 四端核心闭环与语言 | V1 | PLT-001、PLT-004、NFR-005 | 依逐条缺口取得实际证据；本次未运行 |
| AT-007 | 未来同步个人用户流程 | V2 | SYN-001、SYN-003、SYN-005、SYN-007、SYN-008 | 后续阶段设计，排除V1通过数 |
| PERF-001 | 常规响应与检索 | V1 | LIB-005、NFR-001 | 依逐条缺口取得实际证据；本次未运行 |
| PERF-002 | 冷启动可用 | V1 | NFR-002 | 依逐条缺口取得实际证据；本次未运行 |
| PERF-003 | 预算并发与内存 | V1 | IMG-008、QUE-002、NFR-003 | 依逐条缺口取得实际证据；本次未运行 |
| PERF-004 | 故障注入恢复成本 | V1 | NFR-004 | 依逐条缺口取得实际证据；本次未运行 |
| REV-001 | 来源声明与兼容性审查 | V1 | ACC-006、PLT-006、NFR-005 | 依逐条缺口取得实际证据；本次未运行 |
| REV-002 | 权限外发与留存审查 | V1 | SEC-001、SEC-005、SEC-006 | 依逐条缺口取得实际证据；本次未运行 |
| REV-003 | 范围与追踪审查 | V1 | EXT-001、EXT-002、EXT-003、NFR-005 | V1范围审查；EXT只审查范围，不记功能实现 |
| REV-004 | 未来同步边界审查 | V2 | SYN-002、SYN-007、SYN-008 | 后续阶段设计，排除V1通过数 |

## 更新与关闭规则

每次更新需记录实际修改路径、测试/方案编号、日期、平台OS/设备、输入夹具校验、事件序列、实际与预期、通过/失败/阻塞/不适用、证据路径及剩余缺口。并行实现完成后先主线程读实际改动，再执行适用验证；未验证代码保持开发中。每条关闭必须核对全部行为、验收与必要验证，不能由单一绿灯推断整体符合。

Windows进展与四端进展分别统计；仅源配置/模拟、缺环境或待服务授权均不得记通过。不适用项须解释本平台理由；不能把Windows完整首版缩成导入里程碑。资源包原文件与已有里程碑历史记录保持原样。
