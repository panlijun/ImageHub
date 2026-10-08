# Windows 备份、设置、诊断与空间管理软件审查

日期：2026-10-08。主线程 Sol 对当前生产调用链、相关测试代码和实际结果分别核对。范围是 Windows 软件；设备、硬件压力与真实账号测试按用户决定排除，不记通过。没有读取旧项目、安装、发布或真实服务请求。

## 逐编号核对

下表路径相对 `app/lib/`，测试名称相对 `app/test/`。源码具备不等于资源包每项人工 AT、四端 PT 或真实服务 CT 已通过；最终运行结果统一见 [收尾记录](../milestone-27-windows-completion.md)。

| 编号 | 实际生产行为 | 验证入口与边界 |
| --- | --- | --- |
| BAK-001 | `gallery/data/library_backups.dart` 在一致事务取得全部永久版本与租约。完整包包含永久字节，包括回收及仅清记录后的独立版本；元数据包没有图片。真实摘要和像素校验失败列明 UUID 并拒绝完整成功，用户须明确改选元数据。恢复元数据创建 missing 副本，不借用原设备路径。 | `core/backup_snapshot_test.dart`、`backup_merge_restore_repository_test.dart`、`backup_screen_test.dart`；真实小图 SQL/files，非大包性能证明。 |
| BAK-002 | 同一 writer 事务取得关系与实际文件租约，退出 writer 后校验/流式写 ZIP。Manifest 白名单排除秘密引用、路径、临时输出、活动意图及本机诊断/观察；终态取消但真实工作未结束的项不进入可携带历史。所有本库秘密引用必须可读取并注册脱敏，返回 null 同样拒绝导出。 | `core/backup_manifest_test.dart`、`backup_snapshot_test.dart`、`missing_owned_secret_test.dart`；故障拒绝后资产、字节、租约状态及原库可重开均有断言。 |
| BAK-003 | `backup_zip_reader.dart` 手工检查 ZIP/ZIP64 原始目录、重复名字、中央/本地一致、范围、STORE、CRC/SHA/真实像素和预算；只写新私有暂存。恢复 prepare 与 commit 均校验空间、关系和当前 epoch，校验失败不改当前库。 | `core/backup_zip_reader_test.dart`、`backup_restore_plan_test.dart`、`backup_merge_restore_repository_test.dart`；大于 4 GiB 实包及硬件容量压力未验证。 |
| BAK-004 | 纯计划按内容映射资产、版本、来源、结果与历史，UUID 碰撞分配新身份；标签并集超 50 拒绝，不截断。维护先阻止新派发并排空实际 IO；合并保持现有任务暂停，替换先建可重建私有快照，独立确认、关联提交、会话切换及旧 epoch 拒绝。失败按日志用快照单事务回滚，成功仅有证据清旧文件/秘密。 | `core/backup_merge_plan_test.dart`、`backup_result_merge_test.dart`、`backup_restore_plan_test.dart`、`backup_replace_restore_repository_test.dart`、`replacement_rollback_test.dart`；本轮 PNG 审计描述修复另列，冻结历史不能被永久描述改写。 |
| BAK-005 | 自有 Manifest 2/1 只带相对包内资源标识；恢复通过当前平台目录/独占发布服务创建新副本。账号恢复禁用、没有秘密。八项设备设置独立严格 envelope，只恢复声明可用项，确认列出覆盖/跳过；默认目标、凭据、会话许可与旧冻结任务不恢复。 | `core/backup_settings_test.dart`、`backup_settings_repository_test.dart`、`backup_settings_screen_test.dart`；Windows 实际互读子流程可验证，四设备互读 PT 未执行。 |
| BAK-006 | `BackupCoordinator`/`RestoreCoordinator` 与共同页面有阶段进度、空间估算、取消及结果汇总。真实 writer/reader 完成、文件关闭后才收尾保护；独占发布是导出提交点，迟到取消不撤销用户文件。暂存按登记、关闭证据与摘要清理，未知子项、链接、变化字节或无法确认 IO 时保留现场；暂存清理与资料库保护清理分别反馈。 | `core/backup_coordinator_test.dart`、`backup_zip_reader_test.dart`、`backup_screen_test.dart`；系统目录窗口用 fixture，未计 PT/完整人工 AT。 |
| OPS-001 | `library_settings.dart` 在绑定 owner/epoch/旧设置与目标指纹的事务校验并保存，成功后才更新共同调度策略。默认输入只作用于新工作台/任务；运行中的输入、预算及旧草稿不变。损坏/未来设置拒绝加载，不覆盖为默认值，恢复失败保留旧设置。 | `core/device_settings_test.dart`、`settings_repository_test.dart`、`backup_settings_repository_test.dart`、`settings_screen_test.dart`。 |
| OPS-002 | `library_diagnostics.dart` 白名单事件独立于业务外键，业务提交后记录，日志失败不回滚业务。按真实 UTF-8 字节和 30 天/10,000,000 字节先到清最旧；共同页支持筛选、任务/尝试关联与确认清理，绑定冻结行，不增清后来事件。 | `core/diagnostic_runtime_test.dart`、`diagnostic_repository_test.dart`、`diagnostics_screen_test.dart`；读/导出故障不串改业务记录。 |
| OPS-003 | 诊断读取、确认和实际导出重新核对本库秘密引用；缺值拒绝安全视图，不枚举其他凭据。先遮蔽再截断，排除来源完整路径、秘密引用、图片、URL query/fragment、正文与不可信异常字符串。用户主动导出，实际 IO 收尾后反馈，清理只操作自有窗口和登记暂存。 | `core/diagnostic_sanitizer_test.dart`、`diagnostic_exporter_test.dart`、`missing_owned_secret_test.dart`；移动原生导出尚未接入且禁用，不计 Windows 缺口或移动完成。 |
| OPS-004 | `library_storage.dart`/`storage_screen.dart` 按实际文件长度展示永久/回收/缓存/输出/诊断占用。缩略图登记日志、使用序号 LRU 与冻结清理计划保留保护项、未知文件、链接和变化字节。原图、输出和缓存新写入先检查实际可用空间；不足时停相关新写入并解释，不自动牺牲永久副本。 | `core/storage_repository_test.dart`、`storage_capacity_test.dart`、`storage_screen_test.dart` 与 Windows 原生接口；空间余量与总体资源预算是候选值，未做硬件 PERF。 |
| OPS-005 | 设置显示合法范围、单位、实际有效并发/预算及恢复默认草稿；须保存才生效。`ProcessingScheduler` FIFO 实际预算动态约束并发，内存压力后本会话降低到最多一个候选任务，不取消旧运行许可。Windows 原生低内存信号接入严格失败反馈；不可用的移动导出等能力不提供假控制。 | `core/settings_repository_test.dart`、`processing_scheduler_test.dart`、`processing_memory_pressure_test.dart`、`system_memory_pressure_monitor_test.dart`；实际低内存/四端预算校准未执行。 |

## 本轮修正的保护边界

- 备份私有暂存清理先核对整个目录清单，再逐个核对已登记普通文件的 SHA/长度。未知目录、链接、篡改或 IO 不确定时拒绝清理，保留现场；已发布导出的原暂存名称不再拥有，后来同名文件不能误删。`ValidatedBackup.dispose` 清理失败可重试。
- 备份和诊断对本库拥有但读取为 null 的秘密采取拒绝安全读取/导出。真实秘密恢复可读并完成遮蔽后可重试，普通资产与永久字节不删除。
- 系统内存观察器失败只写固定诊断，不字符串化未知异常；退出继续等待实际图库 IO。Win32 句柄关闭失败不声称已释放，观察器停止后可重试关闭。
- 根库损坏/未来格式使用共用保护页解释保全目录、兼容版本及有效备份恢复；不提供空库覆盖、猜修 SQL、删除原库的捷径。

Windows 低内存接入使用官方 [CreateMemoryResourceNotification](https://learn.microsoft.com/en-us/windows/win32/api/memoryapi/nf-memoryapi-creatememoryresourcenotification) 和 [QueryMemoryResourceNotification](https://learn.microsoft.com/en-us/windows/win32/api/memoryapi/nf-memoryapi-querymemoryresourcenotification)，实际当前信号读取与句柄关闭由主机自动化验证。默认两秒轮询、128 MiB 后续像素预算仍为候选策略，未诱导硬件低内存，也不保证实时信号精度。

主线程已阅读新增PNG审计描述关系实现并完成真实SQL/ZIP/合并/替换/再备份测试。49项PNG/缓存/备份专项、1314项全量及五个Windows原生子流程通过，详细结果见完成记录。本报告不替代测试日志；正式四端发行、签名、真实账号/服务、设备PT、硬件断电、PERF及完整人工AT仍未记通过。
