# 第十六阶段：主动链接检测与持久状态

2026-10-06。继续 Windows 全部90条 V1 目标，本阶段落实 LNK-004/UT-072 的共同业务、页面与受控验证，不等于全部首版或真实服务验收通过。SDK/ATL 已按先前授权装在通用环境，本轮只读复核，不重复安装、改系统配置或新增依赖。没有真实上传、远端删除或图床探测，没有 Git 初始化、提交、推送或发布。原资源包不变。

## 实际行为

桌面“成功链接”和 M1“链接”复用 LinkResultsScreen。普通确认结果分别显示已记录、当时可访问、服务报告远端已删除、未能确认；检测时间和上次有效可访问时间独立显示。状态与名称、普通URL、历史目标身份、服务、输入类型在 SQL 层取交集后计数与分页，查询不发送网络请求。

逐项或当前展示选中范围可以主动检测。确认列出冻结图片名、历史目标和普通URL，说明访问可能计入服务统计、不能保证永久可用；未加载、筛选外或确认后新增结果不会自动加入。打开页面、准备计划、查询、重开和取消确认均不发请求。没有自动策略、后台定期访问或重传。Catbox匿名链接明确不由应用保证永久。

每次调用建立独立 Dio，仅向对应服务的精确 HTTPS 主机 files.catbox.moe/i.ibb.co 发送 HEAD。拒绝查询参数、用户信息、端口、fragment、危险字符或不同主机；不带账号凭据，不跟随重定向，不用GET回退，不自动重试，也不下载图片表示。200且图片类型、空HEAD体表示当时可访问；410空体仅记录服务Gone证据；404、403、405、429、5xx、离线、超时、畸形响应为未知。404不能证明永久删除，410表示来源报告资源不再提供，依据 [RFC 9110](https://www.rfc-editor.org/rfc/rfc9110.html#section-15.5.5)。这些通用HTTP规则不是Catbox/ImgBB已联调的证明。

所有检测均保留普通确认、管理秘密、任务历史、资产整理和永久字节；失败仍保留上次可访问时间。取消意图与实际网络结束分离：等待原始delegate.fetch和原始源流取消，包括迟到响应，才能保存取消观察并释放保护。20秒时限和1KiB原始响应防护为候选预算，不是四端或服务实測能力；HEAD中任何非空体都不能成为可访问证据。原始响应文本、头、秘密或未知异常对象不输出到普通展示。

## 数据与生命周期

LinkProbePlan 绑定 repository owner、executionEpoch、明确UUID与完整普通确认指纹；执行前重验失效或已移除记录，拒绝发请求。schema7仍26表，仅 RemoteUploadResults 增加 linkState/linkReason/linkCheckedUtc/lastAccessibleUtc/probeGeneration/probeHttpStatus 六列。真实检测开始前先持久 unknown/interrupted，防止进程中断后沿用旧健康判断；最新generation赢，迟到旧结果只释放自己的guard。

LinkProbeCoordinator 由 LibrarySession 在明确确认后延迟创建。退出、替换和dispose先解决页面拥有的确认route，再取消并等待真实操作。资料库关闭和恢复维护在writer gate之外排空实际检测，必要finalizer仍能写入；无法确认收尾时保留保护、拒绝安全关闭/恢复，唤醒等待者报告固定错误。状态事务失败保留interrupted证据，实际IO结束后排空进程内等待，避免退出死锁。

新项目自身schema1–6升级至7保留身份/字节/受保护引用，未来版本拒绝改写。**schema6仍有恢复日志时拒绝升级，须先用兼容版本完成恢复**，保护旧私有快照与回滚结构证据；本阶段没有增加旧应用数据兼容。生成代码由真实 build_runner 生成，没有手写数据库生成文件。

可携带备份 formatVersion1白名单不携带本机观察；两种模式恢复的普通结果以recorded开始，不把其他设备过去观察当当前健康证明。私有ReplacementSnapshot和回滚保留当前全部字段/26表，使用共同librarySchemaVersion检查。此边界不删备份中的普通链接或终态历史。

## 修改文件

新增生产文件：`links/domain/link_availability.dart`、`links/data/link_probe_gateway.dart`、`links/application/link_probe_coordinator.dart`、`gallery/data/library_link_probes.dart`（均在app/lib/features）。调整以下实际文件：

- `app/lib/features/gallery/data/library_database.dart`、`library_database.g.dart`、`library_repository.dart`、`library_restores.dart`、`library_links.dart`：schema7与真实生成代码、检测IO保护、维护排空、查询观察。
- `app/lib/features/gallery/data/library_replacement_snapshot.dart`、`library_replacement_rollback.dart`：当前schema常量与完整私有快照/回滚。
- `app/lib/features/gallery/presentation/gallery_providers.dart`：LibrarySession延迟actor、退出/替换收尾。
- `app/lib/features/links/domain/link_query.dart`、`presentation/link_results_screen.dart`：状态交集、明确确认与实际反馈。
- `app/lib/features/upload/domain/upload_queue_models.dart`：普通结果的独立本机观察值。

新增 `app/test/core/link_probe_gateway_test.dart`、`app/test/core/link_probe_repository_test.dart`、`app/integration_test/link_probe_flow_test.dart`。共同链接widget测试新增9项；自身迁移/快照/回滚相关现有夹具适配schema7，未来夹具用schema8。根AGENTS、两份README、架构、环境、V1台账与本记录更新，资源包保持只读。

现有夹具调整：`app/test/link_results_screen_test.dart` 和 `app/test/core/` 下 `accounts_repository_test.dart`、`library_migration_test.dart`、`output_schema_migration_test.dart`、`replacement_rollback_test.dart`、`restore_schema_recovery_test.dart`、`upload_repository_test.dart`、`internal_replacement_snapshot_test.dart`。未为本阶段改动无关业务或依赖锁文件。

## 验证

| 类别 | 实际结果与边界 | 证据 |
| --- | --- | --- |
| UT-072 传输子范围 | **35/35通过**：无授权/危险URI零请求，HEAD元信息四状态、无凭据/重试/GET、原始响应预算、真实迟到fetch及源流取消、未知错误不stringify、收尾失败保留 | [传输日志](validation/windows-link-probe-gateway-tests.log) |
| UT-072/073/093 仓储及迁移子范围 | **最终17/17通过，3秒**：真实SQLite/文件、普通/组织/历史保留、SQL状态分页、代次迟到/owner、关闭与维护实际排空、保存故障、schema6迁移/未完成恢复拒升级、未来观察拒写及两模式真实备份恢复；此前相关迁移/快照/账号/上传回归 **91/91通过，4秒**（15新+76旧） | [仓储与回归日志](validation/windows-link-probe-repository-tests.log) |
| Widget | **16/16通过，16秒**：新9项和旧7项，明确确认、取消、可访问→未知→Gone历史保留、冻结筛选内选中、后来结果排除、失效范围、dispose/系统退出、状态筛选及320/390放大字体布局 | [界面日志](validation/windows-link-probe-ui-tests.log) |
| Windows IT-008 子流程 | **1/1通过，运行2秒/Debug19.5秒**：真实原生页、SQLite/原字节/系统合成管理秘密，受控Dio HEAD200→404→410，重开观察保留/无自动请求/旧owner拒绝 | [原生日志](validation/windows-link-probe-integration.log)、[截图](../app/build/validation/windows-link-probe.png) |
| Windows IT-005 回归 | **1/1通过，运行4秒/Debug19.9秒**：实际Windows空间/独占发布、系统合成凭据排除与原库保护、完整/元数据合并替换及重开；无HTTP | [备份原生回归](validation/windows-link-probe-backup-integration.log) |
| 全量回归 | **646项通过，80秒**；不是646个正式UT或90条验收通过 | [全量日志](validation/windows-link-probe-full-tests.log) |
| 静态与格式 | 整app分析无问题；151文件格式检查0改动 | [分析](validation/windows-link-probe-analyze.log)、[格式](validation/windows-link-probe-format.log) |
| 资源包与台账 | 31文件/56引用完整，90条规范属性/行为/验收原措辞保持；不是软件测试 | [Kit](validation/windows-link-probe-kit-integrity.log)、[台账](validation/windows-link-probe-coverage-integrity.log) |

日志保留初轮失败：适配器URI点段被Dart规范化后的用例预期修正；新widget加载/实际滚动与重复状态文字断言修正，替换现在主动关闭所属确认route，旧用例相应不再点击消失按钮；两种备份测试补齐已有预检要求的实际私有目录。最终通过前没有改生产HTTP或备份规则迁就夹具。Drift独立资料库/executor的debug提醒原样保留。

Windows Release **37.0秒构建成功**，见 [构建日志](validation/windows-link-probe-release.log)。只启动本次自有隐藏runner，原生窗口创建、正常WM_CLOSE退出 **exit0**，见 [启动退出日志](validation/windows-link-probe-release-smoke.log)。可运行文件为 `app/build/windows/x64/runner/Release/imagehost.exe`，运行须保留整个Release目录的DLL与data；没有安装器、签名或发布验收。

## 平台及下一阶段

只读复核Flutter3.47.6/Dart3.13.5，通用目录 `C:\Users\PAN\development\flutter`，持久用户PATH中SDK bin一条；不是项目.tools安装。Android SDK/设备缺失，Apple两端需Mac/Xcode/设备，不能报告三端可运行。本机小屏widget只能证明布局和共同业务。

真实服务HEAD支持/官方契约及完整CT-001、IT-008、AT-004仍待独立验证；未执行真实图床请求。远端删除、设置/诊断/空间管理、系统网络/计费条件、自动处理依赖、真实服务上传和完整性能/人工平台验收继续按全部90条推进，目标保持未完成。
