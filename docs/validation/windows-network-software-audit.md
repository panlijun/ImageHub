# Windows 账号、上传、网络与链接软件收尾审查

日期：2026-10-08。执行者：Sol（`gpt-6.1-sol`，`high`）。这是当前源码与已有测试代码的只读审查，仅新增本报告；没有运行 Flutter、测试、构建、Git、安装或外部请求。

主线程最终复验已完成：1314软件测试通过/1非Windows分支跳过，五个Windows原生子流程、独立进程、Release与正常退出通过，[结果记录](../milestone-27-windows-completion.md)。以下初跑/待最终运行描述保留原审查时点事实，不代表当前仍未回归。真实账号/服务与设备/硬件边界保持未验证，生产unknown保护未放宽。

## 结论与判定边界

本次逐链路检查没有发现需要继续实现的 Windows 账号、上传、队列、网络类型控制、普通链接或秘密保护软件缺口。下面的“具备”指对应 Windows/共同软件行为已接入实际生产调用链，并存在所列本机测试边界；不等于每项资源包人工 AT、真实服务 CT 或四端 PT 已通过。

用户最新范围覆盖资源包原文：不提供 Catbox 匿名上传，仅支持 Catbox userhash 账号与 ImgBB APIKey；本项目自身已有匿名目标、普通结果与备份身份保留读取，不改 UUID、不转换为账号、不重新启用。网络只识别类型，不实现计费判定。资源包原文件保持不变。

生产 Catbox/ImgBB 的精确服务能力仍为 unknown，任务可以持久入队并等待，不能实际上传。适配器、实际文件校验、处理依赖、授权门及结果提交代码均已接入；缺的是 API 精确大小/格式/GIF 契约及真实服务证据，不能将测试注入的能力当作契约，也不能声称生产上传已可用。按当前“未知能力不派发”规则，这不是遗漏派发代码；若要改变这项保护或启用生产能力，需要新的有效契约证据或用户另行决定产品规则。Catbox 删除响应确认同理：已实现严格账号授权与请求收尾，派发后的结果仍 unknown，不猜测成功。

本次核查依据：`AGENTS.md`、资源包 `requirements-analysis.md` 对应条文、`unit-test-design.md` 对应 V1 用例及反查表、当前 `app/lib`/`app/test`/`app/integration_test`。没有依赖旧 coverage 表把旧“未实现”状态直接带入结论。

## 证据读法

下表生产路径均相对 `app/lib/`；测试名称相对 `app/test/`，IT 路径相对 `app/integration_test/`。每行列出的 UT 是当前可定位的代码证据，不把资源包中的“设计，未执行”当作实际运行结果。

已读取本轮专项日志 [windows-completion-account-sdk-final.log](windows-completion-account-sdk-final.log)：19 项通过，实际为 `account_target_scope_screen_test.dart` 的 5 项账号 widget 测试，以及 `core/original_preview_orientation_test.dart` 的 14 项实际 SDK 像素/生命周期测试；该日志不包含匿名仓储、默认/旧冻结任务 guard 或适配器异常收尾专项。`core/account_target_scope_test.dart` 与 `core/provider_adapters_test.dart` 的断言已在主线程全量初跑中通过，仍待最终回归确认。主线程报告该全量初跑为 1251 通过、1 失败、1 skip；失败为备份夹具篡改文件后仍要求清理的旧断言，已由主线程修正。最终全量回归和 native 内存压力桥验证仍由主线程串行完成，本报告不将待完成的运行记为通过。

## 账号 ACC

| 编号 | 当前真实链路与软件判定 | 本机测试证据与边界 |
| --- | --- | --- |
| ACC-001 | **具备，生产能力保护生效。** `accounts/domain/account_models.dart: ProviderInformation.values` 提供两家账号上传资料；`gallery/presentation/gallery_providers.dart: LibrarySession.uploads` 注入真正 `CatboxAdapter`/`ImgBBAdapter`；`upload/data/provider_adapters.dart` 固定 HTTPS multipart。未知 limits 在协调器派发前等待，适配器也拒绝。匿名已移出产品。 | `core/accounts_repository_test.dart` UT-039；`core/provider_adapters_test.dart` UT-047 的两家默认 unknown、格式独立限额、非法限额与实际文件校验。真实 API CT 排除，不能据注入 limits 开启生产。 |
| ACC-002 | **具备，按最新范围。** `library_accounts.dart: saveTarget/_target` UUID 独立于别名，同名可重复；UI 显示服务、别名与 identityMarker。创建匿名及编辑遗留匿名在凭据登记/写入前拒绝；遗留行有效 enabled/default 为 false，原行身份保留。 | `core/accounts_repository_test.dart` UT-040；`core/account_target_scope_test.dart` 匿名创建/编辑无秘密写入、旧行保持；`account_target_scope_screen_test.dart` 遗留目标只有本地移除、新建对话框无匿名选项；适配器同别名账号秘密隔离。 |
| ACC-003 | **具备。** `saveTarget/_resolveTarget` 本地验证必填凭据；保存策略明确选择系统保存或本次会话。配置不自动试上传。`library_accounts.dart` 健康读取与 `library_uploads.dart` 普通确认观察只更新同 UUID/凭据代次的有效证据；无结果显示未验证，重开缺会话凭据显示未配置。 | `core/accounts_repository_test.dart` UT-041；`core/account_health_observation_test.dart` 成功/明确失败、unknown 不观察、旧代次/旧 epoch/已移除/同名新目标隔离、新开始顺序拒绝旧晚到确认。真实凭据有效性不在本轮证明范围。 |
| ACC-004 | **具备。** `accounts_screen.dart` 默认开关、`library_settings.dart: loadSettings/saveSettings` 同事务保存默认目标；上传页只提交用户核对的 UUID 集合，入队冻结目标。匿名有效默认为 false，显式默认选择也拒绝；后来新增/改名不改旧批次。 | `core/accounts_repository_test.dart` UT-042；`core/settings_repository_test.dart` 默认快照与失效校验；`core/account_target_scope_test.dart` 匿名默认拒绝；`upload_tasks_screen_test.dart` 多目标 UUID/入队快照。 |
| ACC-005 | **具备。** `accounts_screen.dart: _performSave/_confirmRemove/_confirmImpact` 停用启用中的目标或移除前异步读影响并独立确认；`library_accounts.dart: targetUploadImpact` 在 `_serial` 按 target_id 统计发布项，返回 UUID、待执行/运行/unknown，终态不计。查询失败不报零、不修改；取消保留草稿。`saveTarget/removeTarget` writer 串行及凭据日志先阻止新派发，协调器 accountChanges 按同 UUID 尽力停止旧在途授权；`beginUploadAttempt/authorizeUploadRequest` 重解析当前凭据、代次和状态。历史快照/普通 URL 不删。 | `core/account_target_scope_test.dart` 同名不同 UUID、三类计数、终态排除、无尝试/租约/秘密副作用、无效/移除 ID 拒绝；`account_target_scope_screen_test.dart` 停用/移除分别取消与读取失败；`core/upload_coordinator_test.dart` UT-043 最后授权门；`core/accounts_repository_test.dart` UT-043/095 更新/删除恢复日志。确认窗口与退出见专项审查。 |
| ACC-006 | **具备资料入口，契约证据未扩大。** `ProviderInformation` 给官方 URL、2026-10-07 核查日期、文件 multipart/认证/限制/续传/管理能力及第三方去向；账号页展示，上传页解释能力等待。Catbox 说明账号上传与既有匿名历史，不能保证永久；ImgBB 管理链接与通用删除 API 分开。 | `core/accounts_repository_test.dart` UT-039；[provider-contract-evidence.md](../provider-contract-evidence.md) 保留官方公开资料证据等级与缺失契约。没有把网页阈值推断为 API 服务器保证。 |

## 上传 UPL

| 编号 | 当前真实链路与软件判定 | 本机测试证据与边界 |
| --- | --- | --- |
| UPL-001 | **具备。** `upload_tasks_screen.dart: _enqueue` 提交幂等 intent；`library_uploads.dart: enqueueUploads` 冻结真实版本 SHA/字节数、输入类型、目标 UUID/服务/别名、隐私和策略；`_uploadInputFile/beginUploadAttempt` 派发前重新校验真实永久副本或确认输出，不重新解释全局默认。原图需明确隐私确认。 | `core/upload_repository_test.dart` UT-044/048 冻结与重新派发当前凭据、失效来源；`upload_tasks_screen_test.dart` UT-094 意图/原图隐私/重开；`upload_flow_test.dart` 本机 Drift/文件/受控 transport，非真实图床。 |
| UPL-002 | **具备。** 每版本×目标有独立 publication，尝试和结果独立；`UploadCoordinator._pump/_execute` 独立运行和提交，`queue_policy.dart` 集合聚合与五计数不按回调累计成功。没有按别名或相同 URL 合并账号身份。 | `core/queue_policy_test.dart` UT-045/065 集合聚合；`core/upload_repository_test.dart` 多目标独立结果；适配器 UT-041/045 同别名账号；`upload_flow_test.dart` 受控混合结果。 |
| UPL-003 | **具备。** `UploadProcessingCoordinator` 独立本地 actor；`library_upload_processing.dart` 持久 schema10 job/冻结处理计划、同批次共享像素工作、只有校验 ready 输出才关联 processed 输入。失败仅结束依赖项，paused 项继续时合法处理失败；来源缺失明确等待修复/重试，没有原图 fallback；就绪项不等待全批。 | `core/upload_processing_repository_test.dart` UT-046/062/066 实际像素输出、共享目标、失败隔离、处理 receipt 复用/显式重建、unknown 阻止重执行、实际引用保护；`upload_processing_screen_test.dart` 与 `upload_processing_flow_test.dart`。硬件性能排除。 |
| UPL-004 | **具备校验，精确服务契约待证。** `_pump` 在 attempt/lease 前拒绝 unknown limits；适配器按真实输出长度/格式、全局与 formatMaximumBytes 取小值、认证和取消校验，超限不读流/不派发。不存在分片或原图替换。 | `core/provider_adapters_test.dart` UT-047 实际 size/format/missing/credential、GIF 独立 fixture 限额、不可变快照；`core/upload_coordinator_test.dart` unknown 能力无 attempt/lease。服务精确阈值不是这些夹具的证明。 |
| UPL-005 | **具备。** 适配器严格有效服务响应形成 `ProviderUploadSuccess`；`library_uploads.dart: finishUploadAttempt` 按 attempt UUID 唯一关联 ordinary result，保留冻结目标和真实输入身份；ImgBB 管理秘密通过独立 journal/UUID 引用/摘要写 SecretStore，不入普通 SQL/UI。无效或不完整响应留 unknown。 | 适配器 UT-048 畸形/不一致成功/部分正文；`core/upload_repository_test.dart` 重复确认、改名/删除后历史、秘密写读回故障；`core/account_health_observation_test.dart` 普通成功与管理秘密恢复隔离。 |
| UPL-006 | **具备。** `enqueueUploads` 按内容版本、稳定目标与策略复用严格普通确认，保留 unavailable/unknown 边界；幂等 intent 不增加出版项。显式 forceAgain 创建新身份，不覆盖旧结果；处理计划相同才复用已确认 receipt。 | `core/upload_repository_test.dart` UT-049/072 幂等、复用、unknown/forceAgain；`core/upload_processing_repository_test.dart` 相同冻结计划复用、删 receipt 或强制重建。不能将 recorded 当实时服务可访问。 |
| UPL-007 | **具备，删除确认保守。** `library_links.dart: removeLocalLinkResults` typed action 同事务解除普通结果关联，独立秘密清理日志且核对全部引用；不调用远端。`library_remote_deletions.dart` + `RemoteDeletionCoordinator` 仅当前同 UUID 非匿名 Catbox 账号、代次、精确单文件普通直链授权，单独确认网络和远端删除，固定 deletefiles 请求。ImgBB 不猜管理链接 API；所有发出删除结果 unknown，重开不重放。 | `core/link_repository_test.dart` UT-070 本地移除保留资产/字节/历史、共享/篡改秘密保护与故障恢复；`core/remote_deletion_repository_test.dart` UT-050 同名新 UUID/匿名拒绝、generation/fingerprint、HTTP200 unknown/实际收尾/重开 prepared 与 sending。真实 CT 排除。 |

## 队列 QUE

| 编号 | 当前真实链路与软件判定 | 本机测试证据与边界 |
| --- | --- | --- |
| QUE-001 | **具备。** `library_uploads.dart` schema5+ 持久批次/发布项/尝试/结果/事件，意图提交后才回执；恢复 running 分为无发送证据 interrupted 与可能提交 unknown。页面只是读取真实状态。 | `core/upload_repository_test.dart` UT-051 正常重开与恢复；`upload_flow_test.dart` 实际自有临时库及文件。硬件强退/断电不据故障注入宣称通过。 |
| QUE-002 | **具备。** `UploadCoordinator._pump` bounded running map、任务唯一 attempt；处理独立 scheduler/actor，共享预算及 FIFO；降低上限不取消实际工作，无就绪不空转。 | `core/upload_coordinator_test.dart` UT-052/053 构造 idle、并发上限、降低不杀 IO；处理 scheduler/coordinator 的真实 worker 收尾测试。候选预算和真实 PERF 分列。 |
| QUE-003 | **具备。** `setUploadBatchPaused/setUploadItemPaused` 持久且相互独立；仅 queued/waiting/paused/interrupted 可单项控制，running/unknown/终态拒绝。恢复先重验条件，保持 retry/冻结输入，暂停不取消运行项也不耗重试。 | `core/upload_item_pause_repository_test.dart`；`core/upload_coordinator_test.dart` UT-054 批次与单项先后、重试 deadline、重复 wake、运行项不停；`item_pause_flow_test.dart` 自有库受控尝试。 |
| QUE-004 | **具备。** `cancelUploadItems` 先持久终态再取消令牌；`finishUploadAttempt` 按尝试/代次保存独立晚到成功，不覆盖 cancelled 或其他新尝试。实际网络/输入/响应结束前执行租约仍保护真实源和处理输出；不把取消 future 当 IO 停止。 | `core/upload_repository_test.dart` UT-055/056/102；适配器实际 fetch/输入/响应 cancel 延迟及晚到源；`core/upload_history_repository_test.dart` cancelled+late 仍保护、SQL 租约释放失败不误清；协调器 graceful close 等真实 IO。 |
| QUE-005 | **具备。** `provider_models.dart` typed failure/交付证据分授权、额度、限流、网络、超时、文件、格式、处理、协议、unknown；`upload_retry_policy.dart` 据证据决策，任务页安全文案给下一步。异常/原始响应不进入备用字符串。 | 适配器 UT-058/059 拒绝、Retry-After、408/5xx/redirect、不受信 transport 超时；`core/upload_retry_policy_test.dart` typed 分类与 unknown 保护。真实服务分类集合不据合成正文穷尽证明。 |
| QUE-006 | **具备。** retry policy 只对可靠无不确定副作用的暂时失败重试，最多初次+3、2/4/8 秒并不剪短 Retry-After；旧 attempt 结束、新 attempt 新流；未知/授权/格式不自动重传，暂停/离线不派发计次。 | `core/upload_retry_policy_test.dart` UT-059/060/061/067；`core/upload_coordinator_test.dart` 单调时钟、UTC 跳变、网络 wake、paused deadline、unknown 无第二请求；适配器每新尝试 fresh multipart/stream。 |
| QUE-007 | **具备本机软件恢复。** `_recoverUploads` 按请求开始证据恢复 unknown/interrupted；处理 job 按冻结计划/确认输出完整性继续。`LibraryUploadQueueStore` 创建时冻结 executionEpoch，每次调用及 writer 门再次核对；替换后旧 actor 关闭/会话许可清空。丢失输入需修复或取消。 | `core/upload_repository_test.dart` UT-062/068；`core/upload_epoch_test.dart` 旧对象/执行拒绝；`core/upload_processing_repository_test.dart` ready 关联/未完成重执行/缺来源；真实强退计时与断电排除。 |
| QUE-008 | **具备最新网络类型规则。** `core/network_state.dart` 严格本机协议及 wifi/ethernet/cellular/other/offline/unknown；默认仅 Wi-Fi/有线，明确所有已识别网络才含移动。`SystemNetworkMonitor` listen 握手成功+严格 read 才有效、错误/超时/结束 unknown、generation/revision 隔离晚到。Windows `network_bridge.cpp` WinRT 默认本机 profile，无计费/SSID/IP/联网探测。`LibrarySession` 观察与设置独立会话许可，writer mayDispatch 和请求前再校验；可见桌面失焦继续观察，隐藏停止新派发，前台重读。 | `core/network_state_test.dart`、`core/system_network_monitor_test.dart` UT-063 协议/握手/缺后端/晚到/生命周期；`core/network_session_test.dart` persisted policy 不授新会话许可；协调器 UT-063 retry/pause/unknown/运行 IO 独立；`network_flow_test.dart` Windows 本机原生只读观察，不证明真实切网 PT。低存储/依赖/授权均有独立等待原因。 |
| QUE-009 | **具备。** `UploadCoordinator` progress 只统计实际传输活动及新增字节；`ExecutionBudget` 区分 UTC/单调时间，等待暂停退避不累计执行，真实 timer 检查 120 秒无活动与 30 分钟累计；`queue_policy.dart` 六聚合/五计数以 publication 为单位。页显示阶段/unknown，无假百分比，独立晚到结果不加 publication。 | `core/queue_policy_test.dart` UT-064/065；`core/upload_coordinator_test.dart` UT-068 watchdog 重复字节不续命；`core/upload_repository_test.dart` checkpoints/汇总；实际硬件计时精度排除。 |
| QUE-010 | **具备。** `library_upload_history.dart: prepareUploadHistoryClear/clearUploadHistory` owner/epoch/完整选择指纹，同门重验，仅显式本机 succeeded/failed/cancelled 或恢复终态。unknown/实际尝试/处理/租约/残留引用/管理日志均保护；普通结果/秘密/资产不删，空批次保留 intent 账本。`upload_exit.dart` 退出确认等待真实收尾，页面说明后台限制。 | `core/upload_history_repository_test.dart` UT-038/066 六活跃状态、晚到、lease 错误、后来终态不增清、命名空间隔离、替换/重开失效；`upload_history_screen_test.dart`；`history_flow_test.dart`。 |

## 链接 LNK

| 编号 | 当前真实链路与软件判定 | 本机测试证据与边界 |
| --- | --- | --- |
| LNK-001 | **具备。** `upload/domain/link_format.dart` 安全普通 URL + URL/Markdown/HTML/BBCode 按格式转义；`library_links.dart: listLinkResults/listLinkTargets` 脱敏后 Unicode 折叠关键词，与稳定历史 target UUID/服务/input/状态取交集后 count/page，排序用结果 UUID 收尾，移除/同名新账号不替代冻结身份。 | `core/link_format_test.dart` UT-069；`core/link_repository_test.dart` UT-069 名称/URL/冻结别名、秘密不命中、同名删除重建、稳定 count/paging；`link_results_screen_test.dart` 实际共同页面。 |
| LNK-002 | **具备。** `prepareVisibleLinkCopy` 保持明确已展示有序 ID；`prepareAssetLinkCopy` 当前永久版本按资产顺序×用户目标顺序，不扩大至隐形/筛选外/其他处理版本。LinkCopyPlan owner/epoch/完整普通指纹，执行前验证，精确格式去重、换行、缺失报告。 | `core/link_repository_test.dart` UT-070 两种范围与顺序、missing/dedupe、当前 digest+bytes、变化/新秘密使计划失效；`core/link_transfer_test.dart` 旧 owner/替换/空集合不调用系统。 |
| LNK-003 | **具备 Windows 系统入口。** `platform/link_transfer_gateway.dart: SystemLinkTransferGateway` 严格 `flutter/platform` JSON Clipboard 通道避免 OptionalMethodChannel 吞后端错误；share_plus 仅普通文本，取消/未确认/不支持/失败分别反馈。`LinkTransferCoordinator` 重试仅本地调用、不上传/删结果。 | `core/link_transfer_test.dart` UT-071 SDK 协议成功、拒绝/缺后端/未知对象不 stringify、分享结果映射；`links_flow_test.dart` 本机系统复制路径。接收方保存及设备分享 UI 不据返回成功宣称。 |
| LNK-004 | **具备主动检测及保留语义。** `LinkProbeCoordinator` 仅独立确认范围/网络后，`link_probe_gateway.dart` 固定 HTTPS 白名单 HEAD，无凭据/重定向/GET fallback/周期/重试。200 image/* 空体为当时可访问、410 空体服务报告不再提供、404/离线/其他为未知。`library_link_probes.dart` generation 拒绝旧晚到并保留 lastAccessible，实际流收尾才放保护，普通结果/秘密/字节不删。页说明历史匿名不保证永久。 | `core/link_probe_repository_test.dart` UT-072 惰性、Gone/失败不删、筛选/分页、generation、实际 transport 与 close/restore、损坏保留；gateway/coordinator 合成 HTTP；`link_probe_flow_test.dart` 受控请求，不是真实服务 CT。 |

## 安全 SEC

| 编号 | 当前真实链路与软件判定 | 本机测试证据与边界 |
| --- | --- | --- |
| SEC-001 | **具备 Windows 最小文件授权。** `platform/import_gateway.dart: pickFiles` 用户选文件才取得只读资源，已保存资料库不依赖外部相册/来源权限；取消为空明确结果、未知错误固定分类。账号/网络观察不要求无关图片权限。Windows 普通路径来源预检不打开明确 cloudPending 文件流。 | `core/cloud_import_batch_test.dart`、`core/import_source_cancellation_test.dart` 真实自有文件与取消流；`gallery_flow_test.dart`。Android/iOS 相册授权/恢复验证属于其他平台，不据此认定 Windows 软件缺口。 |
| SEC-002 | **具备。** `platform/system_secret_store.dart` 生产注入 flutter_secure_storage、应用新命名空间与 UUID 单项引用，串行写/删/读回，无枚举清全库或明文 fallback；账号与管理秘密日志确认所有权/摘要，明确 session 仅内存关闭清空。普通任务/历史/可携带包无秘密。 | `core/secret_store_test.dart` UT-074/095 写删读回/异常；`core/accounts_repository_test.dart` session 替换旧密钥不复活、删除恢复；`core/upload_repository_test.dart` 管理秘密；`accounts_flow_test.dart` 合成凭据 Windows 系统后端。真实账号验证排除。 |
| SEC-003 | **具备。** upload/probe/delete 全部固定认证 HTTPS，Dio 不设证书绕过或重定向；成功普通 URL 严格 host/协议/控制符/userinfo/query/fragment，允许普通 http 时明确标识。管理 URL 只入受保护包装；远端响应只是受预算的解析输入，不执行脚本。 | 适配器 UT-048/096 unsafe URL/HTML/不一致证据/64KiB；`core/link_format_test.dart` 危险协议/格式注入；probe/delete gateway HTTPS 边界。真实 TLS/服务 CT 排除。 |
| SEC-004 | **具备当前出口边界。** `SecretRedactor.register/redact/redactText` 真实秘密先登记，历史值持续遮蔽，未知对象不 toString。账号安全异常、适配器固定 DioException、`DiagnosticSanitizer` 先脱敏再截断/白名单化；新秘密注册后重遮 ordinary 本机/恢复显示快照；链接 SQL、诊断读取/导出及备份白名单取得安全视图，否则拒绝。结构身份与秘密冲突时不改 UUID。 | `core/secret_redactor_test.dart` UT-097 嵌套/参数/短值/循环/异常；适配器 transport factory/同步 fetch/raw response/close 测试；`core/diagnostic_repository_test.dart` UT-085 导出执行再遮蔽/后端失败拒绝；backup snapshot/export 与 links 新秘密计划失效。不是对未知未来出口的承诺。 |
| SEC-005 | **具备。** 打开页面/保存账号/健康检查/入队不授网络许可，`UploadCoordinator` 初始 false；用户单独允许仅本次会话，类型策略与会话许可独立，网络恢复只调度已确认意图，不解 pause/unknown/退避。替换/关闭清许可并先 gate 新派发。本地 processing 独立运行，无遥测、自动云账号或周期探测。 | 协调器 UT-063 构造 idle、观察/设置不授许可、最后 runtime gate；`core/network_session_test.dart` 重开无许可；upload task widget 原图隐私；probes 惰性；备份/诊断出口需确认。 |
| SEC-006 | **具备说明与独立清除。** `settings_screen.dart` “保留、备份与卸载”解释永久/回收/缓存/临时/诊断/凭据；回收30天仅提示，备份路径可达，卸载不保证系统凭据删除且不删远端；`link_results_screen.dart` 本地移除/远端删除独立确认。真实文件由持久引用及实际租约保护。 | `settings_screen_test.dart` UT-099 草稿/说明与真实备份路由；history/link/result/recycle/cache 清理测试各验证不越界与不扩大范围。真实卸载和设备保留行为排除，不伪称系统已删除凭据。 |

## 平台 PLT：仅 Windows 软件与共同行为

| 编号 | 当前真实链路与本轮判定 | 剩余证据边界 |
| --- | --- | --- |
| PLT-001 | Windows 桌面 A 路由使用实际 LibrarySession、共同账号/任务/链接工作流和 Drift/文件/系统能力；M1 与桌面共用业务入口。此审查范围的软件链路具备。 | 四端 UC 全流程 PT/AT 不由共同 domain 证明；其他端尚未接入能力不改记 Windows 软件缺口，不声称四端支持通过。 |
| PLT-002 | Windows `ImportGateway` 文件选择、只读资源、source readiness、取消后真实 IO 收尾；来源丢失不影响已保存永久副本。软件具备。 | 云 provider 未明确待获取的潜在内核阻塞不保证全部覆盖；外部设备/相册授权 PT 排除。 |
| PLT-003 | `SystemNetworkMonitor` 可见 inactive 与 hidden 区分、前台重读；会话 close/restore gates 与 `upload_exit.dart` 实际网络/处理/文件收尾，持久队列恢复。软件具备且说明限制。 | PT-002 真切网、系统后台/强退、硬件断电与计时精度排除；不承诺桌面隐藏或移动后台持续执行。 |
| PLT-004 | 账号、任务、链接使用可聚焦 Material controls，按钮 tooltip/动作文字、状态与原因文字，不仅颜色；公共 widget 有 Windows 尺寸测试，核心操作软件入口具备。 | 人工全键盘/读屏/触摸/去颜色 AT/PT 未由源码或 widget 自动证明；不将“尚未做完整人工验收”直接判为软件未实现。 |
| PLT-005 | Windows 选择目录真实导出、严格 Clipboard 和系统分享映射；拒绝/取消/缺能力分别反馈，本机路径不写可携带输入身份。软件具备。 | 设备系统分享接收方保存、其他端原生导出 PT 单列；已禁用的移动导出不是 Windows 缺口。 |
| PLT-006 | `AGENTS.md` 与当前环境/平台文档分别记系统目标、Windows 构建证据及未实测平台；账号资料维护入口不宣称真实远端通过。 | 正式发行安装方式/签名/完整四端支持矩阵和设备证据仍为发布/设备验收，不由本报告宣告正式四端交付。 |

## 本轮重点安全链复核

### 账号影响确认与窗口生命周期

`TargetUploadImpact` 只有稳定 targetId 和三个整数，无文件路径、凭据、网络 actor 或执行意图。仓储检查本库目标存在且未移除，在同一个串行门读 publication 状态；同别名按 UUID 分开，批次汇总不代替项计数。确认文案显示非秘密身份标记，并明确这是可能变化的当前快照。它不锁住队列，也不声称显示的 running 请求立刻被撤销；后续安全依靠原有 writer/当前凭据代次授权。

停用取消返回“编辑草稿保留”；读取异常进入安全反馈，不能以零项继续。移除同样先读后确认，取消不调用 removeTarget。账号页只保存自己创建的 `DialogRoute`/Navigator，`_dismissImpact` 在 dispose、replacement、exit 时只移除这条窗口，不通用 pop 其他窗口。`_exitPending` 阻止查询晚到后又创建确认窗口，退出等待 `_activeFuture` 然后共同 `requestLibraryExit`。确认的后续仓储调用仍核对旧目标 UUID、凭据日志和当前库维护门。生命周期这一部分为源码证据；本轮专项 widget 直接覆盖取消/读取失败和 legacy UI，没有将尚未单独运行的系统退出人工路径算作通过。

### 匿名拒绝与历史保持

拒绝链：账号 UI 无选项且固定 false → `saveTarget` 在秘密注册、凭据恢复/写入或配置事务前拒绝新匿名及任何遗留匿名编辑 → `_target`/设置快照给有效 enabled/default false → `saveSettings` 拒绝显式默认 → `enqueueUploads` 拒绝新 intent → `_resolveTarget` 拒绝 → `beginUploadAttempt` 授权等待、不建立 attempt/lease → `authorizeUploadRequest` 再拒绝 → 适配器在检查文件或创建 transport 前硬拒绝。旧 intent 的幂等读取仍保留，不把读取历史当执行授权；重开旧冻结项也不能绕过 resolve/authorize。远端删除额外拒绝匿名普通结果及匿名当前目标。

旧 anonymous 字段继续在冻结 TargetSnapshot/普通历史/本项目自身备份格式读取；不删记录、不改 UUID、不借新同名账号执行。恢复目标本来禁用且不恢复秘密，匿名再有有效状态 guard，不能成为可执行目标。`core/account_target_scope_test.dart` 使用当前自有临时库直接建立 legacy fixture；这是本项目历史语义，不是旧应用兼容。

### 适配器故障脱敏与实际收尾

`_TrackedTransport.fetch` 自身是 async，注册 done 后将 delegate.fetch 放入 try/finally；包括 delegate 同步 throw 的情况下 done 都完成。catch 只建立固定安全 DioException，不保留原错误对象/响应正文，避免 Dio 格式化不可信异常。`_BoundedResponse` 的 raw source onError 输出固定 `_MalformedResponse` 并启动 stop；stop 等真实 subscription.cancel，再完成 settled。Dio close 失败记录 cleanupFailed；source 拒绝订阅则标记 `_subscribeFailed`，不能猜安全结束。上传 finally 同时等待 fetch/所有 raw response 与实际 input.stop，无法确认收尾抛固定 `ProviderCleanupException`，协调器保留未结束 IO 保护并拒绝安全退出/恢复。

专项测试明确覆盖同步 `_UnsafeFailure`（其字符串访问会暴露问题）、raw source error 的延迟 cancel（完成前 operation 不返回）、拒绝订阅的 cleanup failure、64KiB 超限延迟取消、fetch 晚到响应和真实输入 cancellation；这比仅检查状态 cancelled 更能说明实际保护链。

### UI 刷新与文件保护

账号健康观察事件与 accountChanges 授权事件分离，后台健康刷新在 busy/loading 草稿期间延后。任务页监听上传/账号变更，手动刷新先重读/重建本机网络观察，失败仍独立读取资料库并保留最后有效列表/失败提示，不授许可。图库远程条件和普通链接目标由本机上传/账号事件刷新，不创建网络请求 actor。默认目标修改只改变后续新意图，不用 accountChanges 撤销当前已发出的授权。

真实文件链为冻结身份/摘要校验 → 持久 UploadTaskReferences/处理 job 引用 → 执行 FileLease → 适配器 fetch、输入及响应源实际收尾 → ordinary result 提交 → 执行租约释放。取消、历史清理、远端删/探测、关闭或恢复都不能用 UI 终态代替 IO 结束。SQL 租约清理失败保留保护，但 finally 排空已结束工作的进程内等待；无依据文件/外部来源/共享引用不猜测删除。

## 单列排除与待补证

1. **真实服务/真实账号**：API 精确字节/实际格式/GIF 契约、真实上传成功/拒绝/限流/格式保持、真实账号有效性、真实远端 HEAD/删除契约，均未请求、不记通过。生产 unknown 等待是明确保护；远端删除发出后 unknown 是缺可靠确认契约。Catbox 匿名上传功能已取消，不能再列成待联调功能。
2. **设备与硬件**：真实网络切换 PT、真实设备相册/系统分享/读屏验收、硬件强退断电、真实内存/存储压力及 PERF，按本轮范围排除且不记通过。其他三端构建/设备互读仍独立未证，不作为本次 Windows 缺口；源码接入和本机自动化不能替代物理证据。
3. **主线程待完成运行与人工证据**：最终全量回归及 native 内存压力桥验证按主线程调度串行完成；本报告只读取已存在的账号/SDK 19 项通过日志，没有追加运行或推断最终全量绿色。本次没有单独执行完整人工 AT，保留这一证据边界，不把它伪记通过，也不据此断言源码未实现。

本报告没有新增业务方案、放宽 unknown/匿名/秘密/文件保护，未发现需回报主线程修复的新增软件缺陷。最终 Windows 交付结论仍由主线程结合最终检查、构建及本轮其余范围审查作出。
