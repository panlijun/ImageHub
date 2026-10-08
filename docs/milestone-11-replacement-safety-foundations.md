# 替换恢复的内部快照与执行会话保护

日期：2026-10-06。Windows 完整 V1 继续进行。本阶段实现内部当前快照与旧执行对象隔离；**尚未实现替换提交、实际快照回滚或替换确认界面，替换入口仍禁用**。未新增安装、依赖或外部服务请求；资源包原件保持不变，无提交、推送或发布。

## 实际实现

- `captureReplacementSnapshot` 在全库维护保护排空实际租约后，用 SQLite `VACUUM INTO` 生成独立数据库，不复制活跃 DB/WAL。校验 schema 6、完整性、外键、TextPolicy、26 表和已知索引，再比较当前关系与快照关系摘要。
- 内部快照保留当前真实资产、整理、回收、来源、账号的系统秘密 UUID 引用、暂停任务与处理输出。永久字节和所有已登记状态输出（包括 `.part`）复制后关闭、flush 并校验实际 SHA/字节；缺失单独记录，不作为复制成功。已损坏的原始文件可按实际字节保留，不伪称有效图片。
- 内部数据库可能包含本机原始显示内容及受保护引用，只放在当前资料库私有暂存；不进入可携带 ZIP、普通结果或导出界面。秘密值仍由 SecretStore 保管；普通快照日志与已注册秘密冲突时拒绝操作，不改 UUID 或伪造去敏路径。
- schema 6 的现有 RestoreOperations 持久化 `snapshot-writing` / `snapshot-ready` 和严格白名单载荷；目录归属先为 `unclaimed`，确认新建安全空目录后才持久 `owned`。未归属目录即使有 `current.sqlite` 也不删除；仅移除本次未归属日志。未知文件、缺失预留位置突然出现文件、链接、越界或损坏载荷均保留现场。
- 启动恢复目前只清理有归属证据的未使用内部快照，不替换当前库或删除当前永久字节、系统秘密。不能据此声称已有实际回滚。未归属私有目录可能留存，后续不得扫描并猜测删除。
- capture/verify/discard 与合并准备/提交共享实际维护 drain；关闭等待真实工作完成再释放根锁。已有快照或恢复日志阻止同一保护内的另一合并提议/提交，避免两种维护交错。
- LibraryUploadQueueStore 固定创建时的运行会话 UUID；每次调用及写入门再次校验，异步等待后仍保留会话。UploadExecution 的确认另核对会话，不能仅凭相同任务、尝试或序号关联。关闭后运行会话失效，重开产生新会话；未来替换确认提交后还须切换会话并重建执行对象，当前未接入该替换路径。

## 验证记录

| 类型 | 实际证据与范围 | 日志 |
| --- | --- | --- |
| UT-080 / IT-005 子范围快照 | 18/18 通过：真实库与文件、组织/回收、所有输出状态、暂停意图、受控凭据引用、缺失、空间不足、取消、目录占用/未归属、篡改、未知模式/触发器、链接、实际 lease 和关闭等待。链接用例实际执行，无跳过；非系统秘密后端 | [快照专项](validation/windows-internal-replacement-snapshot-tests.log) |
| UT-080 子范围旧会话 | 3/3 通过：同尝试身份的外来会话确认被拒绝、旧 store 关闭后不能改变重开意图、跨 await 且重新解析 repository 的回调仍被拒绝；当前会话正常提交 | [会话专项](validation/windows-upload-epoch-tests.log) |
| 全量 | 441 项通过，46 秒；数量含参数化、widget 和 UT/IT 子范围，不等于完整正式需求验收 | [全量](validation/windows-replacement-foundation-full-tests.log) |
| 格式与静态 | 119 文件格式检查 0 改动；整 app analyze 无问题。首次新增原生断言有一个冗余非空断言 warning，修正后重跑通过，首轮保留 | [格式](validation/windows-replacement-foundation-format.log)、[静态](validation/windows-replacement-foundation-analyze.log)、[首轮](validation/windows-replacement-foundation-analyze-initial.log) |
| Windows 原生 IT-005 子流程 | 1 项通过，运行 3 秒 / Debug 构建 30.6 秒。实际容量/独占发布、两模式恢复及重开回归；新增当前快照 capture/verify/关闭/重开安全清理，实际系统受保护合成凭据关联及原图保留。非完整 PT/AT/替换回滚 | [原生备份恢复](validation/windows-replacement-foundation-integration.log) |
| Windows 原生 IT-004 回归子流程 | 1 项通过，运行 3 秒 / Debug 构建 20 秒。当前运行会话入队、实际文件受控传输、系统受保护管理结果和重开通过；无真实图床请求 | [原生上传回归](validation/windows-replacement-foundation-upload-integration.log) |
| Windows Release | 当前实现构建成功，60.2 秒；自有隐藏原生窗口创建并正常 WM_CLOSE，exit 0 | [构建](validation/windows-replacement-foundation-release.log)、[启动退出](validation/windows-replacement-foundation-release-smoke.log) |
| 输入/台账 | 31 资源文件与 56 本地引用完整；90 条 V1 属性、业务和验收原文完整；不是软件测试 | [资源](validation/windows-replacement-foundation-kit-integrity.log)、[台账](validation/windows-replacement-foundation-coverage-integrity.log) |

多独立目录/executor 的 Drift debug 多实例提醒保留，不隐藏，也不作为同一 DB 竞争的证据。故障注入和正常关闭不等于硬件断电、系统强退或完整设备生命周期验收。

## 修改文件

生产：新增 `app/lib/features/gallery/data/library_replacement_snapshot.dart`；修改 `library_repository.dart`、`library_restores.dart`、`library_uploads.dart`、`app/lib/features/upload/data/library_upload_queue_store.dart` 与 `domain/upload_queue_models.dart`。

验证：新增 `app/test/core/internal_replacement_snapshot_test.dart`、`upload_epoch_test.dart`；扩展 `app/integration_test/backup_flow_test.dart`。更新工作区约定、README、架构、环境与 V1 台账。

Sol 子代理实际参数为 `gpt-6.1-sol` / `high`，负责内部快照和 18 项专项；主线程阅读实现与测试，补目录归属审查、旧会话及维护交错保护、原生验证并验收。未启动 Luna 或 Astra。

## 下一阶段与限制

BAK-004 / UT-080 仍未闭合：必须完成真实内部快照回滚、保持备份身份的替换计划、单独确认、新永久字节和关联事务提交、旧意图取消、成功后会话切换、系统秘密及旧字节有证据清理与重开恢复，然后才能启用替换。

内部快照当前按 128 行分页和全部列排序做摘要，内存有界，但大量数据排序及 OFFSET 成本未校准；不得标为性能通过。同步 SQLite 完整性/VACUUM 等待真实调用结束，不能承诺立即取消。现有路径检查不能代替平台原子的 no-follow/file-ID 防护。

Android SDK/设备、Mac/Xcode/Apple 设备仍缺；三端构建、原生空间/发布/备份适配和设备生命周期无通过证据。共同 Dart 边界存在，不等于三端可运行。完整链接管理、持久设置/诊断、网络观察、队列依赖与完整 PT/AT/CT/PERF 继续按 90 条 V1 台账推进。
