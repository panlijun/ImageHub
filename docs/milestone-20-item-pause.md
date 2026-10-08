# 第二十阶段：单项暂停与独立派发控制

2026-10-07。继续 Windows 完整 V1 的90条范围，本阶段补 QUE-003、UT-054/061 及相关升级/恢复保护；共同领域、调度、持久层与任务页从开始供桌面与 M1 共用。资源包只读；未安装、下载、改系统配置、提交、推送或发布，未请求真实服务。

## 实际行为与边界

单项用户暂停和整批暂停分别持久保存。仅 queued/waiting/paused/interrupted 项可单独暂停或继续；running、unknown、成功、失败和取消项拒绝该操作并保持数据与证据。运行请求不因暂停其他项或整批后续派发而取消，可以正常完成；暂停不宣称服务支持续传。

审查发现既有整批暂停直接 interrupted→paused 与需求8.1合法后续表不符，而QUE-003允许暂停未运行项。当前不改状态表：在同一事务和写入门内记录 interrupted→queued→paused 两个合法转换，中间不通知调度或派发。真实事件序列逐项通过 PublishTransitions 校验，尝试/租约数不增加。

整批恢复不清单项暂停。整批暂停期间解除单项暂停，只清独立用户意图，项仍 paused；整批恢复后才能检查条件。原等待原因、完整重试延迟、尝试数、输入和目标快照保持，重复同一用户意图不新增事件、尝试或租约。仓储写入门在 wake、setWaiting、begin 再次核对单项及整批控制，旧调度列表不能绕过已经提交的暂停。

调度中的暂停重试保留原单调截止时间，不制造唤醒计时器或增加尝试；恢复仍满足全部条件，墙钟改变和重复唤醒不剪短 Retry-After。新进程继续保守等待完整持久延迟，未保存进程单调起点。恢复维护期间禁止继续派发；协调器关闭中或关闭后拒绝新暂停操作。

共同任务页按 UUID 提供“暂停本项/继续本项”，明确展示独立暂停和整批仍暂停。运行、unknown、终态不提供单项暂停按钮；业务状态变化后仓储再验证，失败给已有固定反馈并保留数据。仅点击继续不授予会话网络权限，打开页与重开也不上传。

## 数据保护与修改文件

自身 schema9 在 UploadPublications 增加 NOT NULL/默认 false 的 user_paused，仍为27表，真实 Drift 生成代码。只升级本新项目自身1–8格式，不读取或兼容任何旧应用。6/7/8存在恢复日志时在改动前拒绝升级，保留原数据库、私有快照和回滚证据；未来格式及失败事务不重置库。可携带备份 formatVersion1 不变、不携带活动任务控制；当前私有快照、真实重建与回滚保留新列。

- 生产：`app/lib/features/upload/domain/upload_queue_models.dart`、`application/upload_queue_store.dart`、`application/upload_coordinator.dart`、`data/library_upload_queue_store.dart`、`presentation/upload_tasks_screen.dart`；`app/lib/features/gallery/data/library_database.dart`、实际生成的`library_database.g.dart`、`library_uploads.dart`。
- 新测试：`app/test/core/upload_item_pause_repository_test.dart`、`app/integration_test/item_pause_flow_test.dart`；现有`upload_coordinator_test.dart`、`upload_tasks_screen_test.dart`补行为与共同界面。现有9份迁移/版本夹具更新当前版本预期及真实移除新列的历史结构；内部快照/故障回滚补 true 标记被改变后保留验证，不放宽原关系/字节/秘密断言。
- 文档：根`AGENTS.md`、两份README、架构、环境、90条台账与本记录。

Sol代理按显式 gpt-6.1-sol/high 分别实现已确定的持久层及调度边界，无继续委派；主线程检查实际源码、修正测试枚举与编号、实现共同界面与原生流程，串行生成和验证。当前未初始化Git，未声称存在Git diff或提交。

## 当前验证

- 真实 build_runner 23秒成功：[生成](validation/windows-item-pause-generation.log)，未手写数据库生成文件。
- 首轮专项46项混合 core/widget 回归通过，51秒：[专项](validation/windows-item-pause-focused-first.log)。包含真实文件/SQLite及两个宽度的界面交互；不等于46个正式UT。首轮仓储用例标签 UT-053 已校正为 UT-054，重试标签校正为 UT-061，业务断言不变。
- 首轮全量842项通过，130秒：[首轮全量](validation/windows-item-pause-full-first.log)。之后上述合法转换修正及追加用例仍需最终回归，不能把首轮结果作为修正后全量。
- 修正后队列、真实私有快照/重建与故障回滚61项通过，9秒：[转换与恢复](validation/windows-item-pause-transition-tests.log)。新仓储测试最终13项；当前版本历史/未来夹具不再依赖硬编码8/9。
- 首轮静态仅发现测试替身两处缺大括号，已修正，失败结果保留：[首轮分析](validation/windows-item-pause-analyze.log)。最终结果见下方，不把首轮结果作为最终通过证据。
- 修正后最终843项现有unit/widget混合全量通过，104秒：[最终全量](validation/windows-item-pause-full-final.log)。不是843个正式UT，不等于90条首版验收。
- Windows原生IT-004子流程最终1项通过，Debug44.5秒/运行5秒：[原生](validation/windows-item-pause-native-read-diagnostic.log)、[当前视口截图](validation/windows-item-pause.png)。真实引擎页面、SQL、独立输入文件、单项/整批两类意图、正在运行项正常完成、关闭重开及新会话再次明确许可；适配器只读实际文件并门控返回合成确认，没有HTTP，不代表真实图床或完整人工AT/PT。
- 原生首两轮没有达到预期下一次受控调用，诊断发现项按异常保护进入unknown。测试适配器内expect可能被生产回调异常边界捕获，现将字节/格式严格断言移到测试主体，实际调用和顺序断言保留，最终通过；未放宽生产unknown判断。临时诊断字符串一次编译失败已修正，所有失败日志保留。
- 最终187文件格式0改动：[格式](validation/windows-item-pause-format-check.log)；整app静态分析无问题，34.5秒：[分析](validation/windows-item-pause-analyze-final.log)。
- 新库版本的Windows IT-005原生备份/合并/替换/系统合成秘密排除与重开回归1项通过，Debug49.3秒/运行6秒：[备份回归](validation/windows-item-pause-backup-native.log)。
- 当前Windows Release构建成功，54.3秒：[构建](validation/windows-item-pause-build.log)；仅本次自有隐藏窗口实际创建并正常WM_CLOSE退出0：[启动退出](validation/windows-item-pause-smoke.log)。这是本机构建与烟雾验证，不是安装包、发布或完整人工PT/AT。
- 资源包31文件/56引用及90条规范原文完整性通过：[资源](validation/windows-item-pause-kit-final.log)、[台账](validation/windows-item-pause-coverage-final.log)。资源检查不是软件测试，最新网络决定位于台账范围说明，不改原文。

全 Windows 首版目标保持 active。系统网络类型观察及按类型派发、自动处理依赖、远端删除、完整服务契约和明确授权后的真实联调、跨平台设置转移、性能及完整人工验收仍未完成。2026-10-07用户明确取消计费状态，仅按网络类型控制已有确认上传任务自动继续；最新决定覆盖QUE-008/UT-063中的计费要求，资源包原文不改。Android SDK/设备与Mac/Xcode/Apple设备缺失；共同逻辑和小屏widget不能替代其他三端构建/实机证据。
