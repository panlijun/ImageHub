# 里程碑24：独立远端删除与持久未确认记录

日期：2026-10-07。完整Windows V1目标保持active，本阶段不表示90条全部验收。网络按用户最新决定只识别类型，不判断计费；继续已确认图床上传，不新增图库云同步。

## 服务证据与实际行为

本轮只读核验 [Catbox官方API](https://catbox.moe/tools.php)、[Catbox FAQ](https://catbox.moe/faq.php) 和 [ImgBB公开API](https://api.imgbb.com/)。Catbox有deletefiles/userhash/files请求协议，但该页面没有可靠的删除成功确认响应规范；ImgBB当前公开文档只描述上传及返回delete_url，没有可据此执行的通用删除协议。因此当前只接入Catbox账号单文件请求，任何派发后HTTP或正文均未确认；不猜测ImgBB管理链接动作、不用200或空正文伪报成功。具体缺口是UPL-007/CT-003的真实删除确认契约及实际联调，已明确说明影响。

桌面A/M1共享链接页新增“请求远端删除”，与本地移除分开。准备确认时使用同一历史目标UUID的当前有效账号，严格文件标识/精确直链；同别名新账号不能替代原身份。确认明确授权此次网络请求及可能失去远端内容，取消确认0请求。确认与请求前再次校验结果摘要、owner/epoch和目标代次/凭据。请求发送后不会自动重试，关闭重开只展示审计。

普通结果/永久副本/秘密/任务历史保留。原来的可访问观察在sending事务中置未知，保留lastAccessible；删除审计不会成为链接已删除证据。响应正文/秘密/引用/URL不进入审计或普通日志。请求后仅安全HTTP状态可记录；结果保存失败保留prepared/sending证据，重开保守分类。持久prepared为未发送，sending为未知，未来/畸形记录保留现场并拒绝打开。

适配器固定HTTPS multipart POST，禁止重定向与重试，响应正文丢弃且原始累计限16KiB；20秒/16KiB为候选防护预算。实际fetch、multipart输入与原始响应订阅收尾后才完成。无法确认收尾时保留保护并拒绝安全关闭/恢复，取消不能提前解除。恢复/关闭在writer门外等IO，避免阻塞finalizer；本地移除和检测拒绝与运行删除交错。

审计使用既有LibraryMetadata的remote_delete_v1/UUID严格格式1。合并保留当前审计，可携带Manifest2排除；替换同事务清旧审计，即使备份复用结果UUID也不误挂旧动作；替换失败私有快照回滚保留原审计。schema10/28表不变，无依赖/安装/系统配置变更。

## 修改范围

- 新增 `app/lib/features/links/domain/remote_deletion.dart`、`data/remote_deletion_gateway.dart`、`application/remote_deletion_coordinator.dart` 和 `gallery/data/library_remote_deletions.dart`。
- 修改 `gallery/data/library_repository.dart`、`library_links.dart`、`library_link_probes.dart`、`library_restores.dart`、`library_replacement_restores.dart` 的导入/恢复/关闭和关联保护；`gallery/presentation/gallery_providers.dart` 的LibrarySession延迟创建及关闭/替换隔离；`links/presentation/link_results_screen.dart` 的共同确认/取消/审计；`accounts/domain/account_models.dart` 的真实实现能力说明。
- 新增 `test/core/remote_deletion_gateway_test.dart`、`remote_deletion_repository_test.dart`、`remote_deletion_coordinator_test.dart`、`remote_deletion_restore_test.dart`，共同页面 `test/remote_deletion_screen_test.dart` 和Windows原生 `integration_test/remote_deletion_flow_test.dart`；更新既有 `test/core/accounts_repository_test.dart` 的实现标记/能力断言。
- 更新根AGENTS、两份README、架构、环境及90条台账。保留只读资源包，不读取旧应用、不初始化Git、不提交/推送/发布。传输和页面、核心测试任务均实际启动Sol（gpt-6.1-sol/high），主线程审查实际源码并串行执行验证。

## 实际验证

- 首次分析4个TargetSnapshot字段名错误，修正为真实id：[首次分析](validation/windows-remote-deletion-analyze-first.log)。
- 首次gateway/widget专项38通过3失败，35秒：[首次专项](validation/windows-remote-deletion-gateway-ui.log)。失败均为390两倍字号初始等待懒加载按钮，测试补真实滚动而不降低字号/扩大视口/放宽断言。
- 第二次专项41通过3加载失败，30秒：[第二次专项](validation/windows-remote-deletion-focused.log)。新仓储/actor测试缺少ImageHostService所在account_models导入，补真实导入；无生产放宽。
- 最终新增专项77项全部通过，16秒：[最终专项](validation/windows-remote-deletion-focused-final.log)。核心68项（gateway32、真实仓储23、actor10、恢复3）及widget9项；包含390/1280/390两倍字号、本地复制/移除及取消0请求、明确确认1请求、正常重开无自动派发、目标身份/授权变化、未知保留、真实IO drain、坏格式/未来保留及合并/替换/故障回滚。各专项不与全量重复累加，也不称77个完整正式UT。
- Windows当前真实引擎删除子流程1项通过，Debug36.5秒/运行3秒：[原生删除](validation/windows-remote-deletion-native-first.log)。生产页面/实际SQLite/字节、实际Dio multipart及原始收尾经过受控HttpClientAdapter，明确确认和普通关闭重开均执行。合成会话授权无系统存储写入，无外部上传/删除。
- [真实Windows页面截图](validation/windows-remote-deletion.png)由上述引擎生成，主线程已查看；显示unknown/可能已生效/不会自动重试及原普通链接。仅当前视口，不能代替手机实机或完整人工验收。
- 本轮第一次全app格式216文件0改动，1.85秒：[格式](validation/windows-remote-deletion-format-check.log)。当前版本终验结果另列如下。
- 首次全量1037通过1失败，92秒：[首次全量](validation/windows-remote-deletion-full.log)。既有UT-039仍断言uploadImplemented=false，和已接入真实适配器不符；改为实现标记true并补账号删除/匿名缺能力判断，继续保留凭据无副作用验证/续传/远程列表unknown，不声明账号健康或精确限制已验证。
- 首次完整分析1条测试花括号提示，59.5秒：[全分析](validation/windows-remote-deletion-analyze.log)。补恢复测试控制语句块，不改变其业务断言；最终216文件格式0改动，1.66秒：[最终格式](validation/windows-remote-deletion-format-final.log)。
- 更新账号旧断言后1038项全量通过，89秒：[全量复验](validation/windows-remote-deletion-full-final.log)。随后审查将删除审计格式校验前置到普通过期/凭据/上传恢复之前，补未完成上传尝试在坏/未来审计拒绝打开时原样保留断言；当前源版本终验另列。当前216文件格式0改动，2.01秒：[当前格式](validation/windows-remote-deletion-format-confirmed.log)。
- 当前Windows真实备份/合并替换/设置/故障回滚子流程1项通过，Debug28.1秒/运行6秒：[备份原生回归](validation/windows-remote-deletion-backup-native.log)。多数据库debug警告原样保留，未压制；不代表硬件断电或实际系统选择器验收。
- 资源包31文件/56引用和全部90条需求原文完整性通过：[资源包](validation/windows-remote-deletion-kit.log)、[台账](validation/windows-remote-deletion-coverage.log)。完整性检查不是软件测试。
- 当前源码（含审计前置校验与未完成尝试保护）完整unit/widget混合全量1038项全部通过，87秒：[当前全量终验](validation/windows-remote-deletion-full-confirmed.log)。新增77包含于总数，不重复累加；原生IT子流程另计。并非1038个完整正式UT、90条正式软件验收或四端实机通过。
- 当前源码最终静态分析无问题，4.7秒：[最终分析](validation/windows-remote-deletion-analyze-final.log)。
- 当前Windows Release构建成功，46.6秒：[构建](validation/windows-remote-deletion-build.log)。实际AOT `Release/data/app.so` 为14,009,224字节、本轮18:00:36生成；未签名、打安装包、安装或发布。
- 只启动本轮自有隐藏Release实例，核对窗口所属PID后正常WM_CLOSE退出0：[启动退出](validation/windows-remote-deletion-smoke.log)。未操纵其他窗口或改系统配置。

## 未完成与下一阶段

真实服务CT-003/IT-008尚未授权或运行，可靠删除确认仍未知；不能从HTTP200猜测成功。此轮无外部上传、远端删除、账号开通或网络切换。gateway清理故障与仓储保留保护分别测试，actor抛cleanup失败后保留私有执行的分支未直接注入widget/actor；不为测试添加绕过真实保护的销毁接口。已审查该分支实际接线。

Android仍缺SDK/设备，macOS/iOS缺Mac/Xcode/设备。共同源码/主机390布局不等于三端构建或实测。Windows完整PT/AT/PERF、真实选择器与真实服务契约等仍按90条台账推进；下一阶段核验其余阻断项与实际可运行能力。
