# 里程碑25：软件补齐与设备验收拆分

日期：2026-10-07。按用户最新决定，本轮排除剩余设备验收，继续代码与现有Windows主机自动化。完整拆分见 [范围表](software-completion-scope.md)。排除项保留为未执行，不计通过；真实图床契约单列。没有读取旧项目或旧数据，没有提交、推送、发布、安装、系统配置或实际图床请求。

## 已实现的生产行为

- IMG-004/LIB-001：桌面A与M1共用永久副本原图预览。读取确认的同一版本并重新核对SHA-256/字节数，SDK支持五种静态格式与GIF/WebP逐帧动画，支持暂停、恢复、有限循环、缩放。缩略图不充当原图。显示最长边最多2048像素，不修改永久字节；128MiB共享许可等候选预算不冒充设备峰值实测。
- 文件租约持有到实际isolate读取结束，像素预算保留到SDK解码/显示帧收尾。暂停保留已解码待显示帧；返回、系统退出、替换与重试都等待实际工作。SDK的ImageDescriptor及ImmutableBuffer必须晚于Codec.dispose释放。原图窗口采用共同上传退出确认；确认后先结束本页解码，再关闭资料库。
- IMP-001/007：Windows普通本地路径采用元信息预检，明确OFFLINE/RECALL_ON_DATA_ACCESS状态时反馈“云资源待获取”并不开数据流。拒绝网络/设备路径及reparse祖先的元信息查询；EA不能被误认成召回证据。未知来源仍按实际读取处理，不根据异常文字猜原因。逐项失败策略保留，其他已经取得的图片继续，失败不覆盖已保存整理。
- ACC-003：合法普通确认显示“可用”；明确非unknown的授权失败显示“授权失效”，网络/限流/超时/目标暂不可用显示“暂时不可用”。无健康接口不自动试上传；unknown、取消、文件或能力错误不猜健康。观察与结果同事务，展示事件不撤销执行授权。持久开始标记按writer实际开始顺序处理回拨及迟到；任务历史删除不清标记。合并保留、可携带包排除、替换清理、私有回滚保留；坏/未来格式拒绝打开及写入，原记录保留。
- 有效会话凭据尚无结果时显示“未验证”；已观察结果可显示，重开没有会话值仍为“未配置”。账号列表观察刷新保留打开的编辑草稿，页面旧“上传尚未接入”文案已更新。
- SEC-006：设置补充临时输出、诊断及凭据留存说明，提供真实备份入口；进入备份再返回保留未保存设置草稿。
- BAK-004/LIB-003：超过50标签仍阻止提交，展示双方对象、标签、数量及完整映射的并集数量，提供取消、整理、重导出、重新预检指引。同内容描述冲突展示双方格式/尺寸/方向/摘要/字节，不修改清单来凑成功，不自动替换绕过冲突。
- PLT-004：桌面多选卡片读出选择动作与selected状态；选定动画帧缩略图的重试重新读取实际选帧。

schema10/28表、可携带Manifest2、自有设置格式3均不变。ffi2.2.0从已经锁定的传递依赖改为显式依赖，实际offline pub get只调整依赖角色，没有新版本或额外下载。

## 修改文件

- 新增预览：`app/lib/features/gallery/application/original_preview_reader.dart`、`presentation/original_preview_controller.dart`、`presentation/original_preview_screen.dart`及`app/lib/platform/image_preview_codec.dart`。
- 新增来源预检：`app/lib/platform/source_readiness.dart`；修改`platform/import_gateway.dart`、`core/platform_resource.dart`、`pubspec.yaml`与实际解析的`pubspec.lock`。
- 图库接线：`gallery/presentation/desktop_gallery.dart`、`mobile_gallery.dart`、`asset_widgets.dart`及`upload/presentation/upload_exit.dart`。
- 账号观察：`gallery/data/library_repository.dart`、`library_accounts.dart`、`library_uploads.dart`、`library_replacement_restores.dart`及`accounts/presentation/accounts_screen.dart`。
- 设置/恢复：`settings/presentation/settings_screen.dart`、`backup/presentation/backup_screen.dart`。
- 新增测试：`app/test/gallery/original_preview_reader_test.dart`、`original_preview_controller_test.dart`、`test/platform/source_readiness_test.dart`、`test/core/cloud_import_batch_test.dart`、`account_health_observation_test.dart`。补充既有desktop/mobile/settings/accounts/backup的widget测试及`integration_test/gallery_flow_test.dart`。
- 更新根`AGENTS.md`、本记录、范围表、`windows-v1-coverage.md`、`environment.md`及实际验证日志。资源包保持原件，独立设计原型不变。

Sol（`gpt-6.1-sol`，`high`）实现/自检读取、测试、预检与账号观察；Luna（`gpt-6-luna`，`high`）按已确定方案补设置入口/文案及备份指引。主线程阅读实际文件、完成SDK播放与UI接线、处理生产缺陷、执行串行验证并验收；没有子代理继续委派。

## 实际验证

以下专项包含于全量，不累加为独立正式UT通过数。widget里的AT/IT编号仅表示对应软件子场景，不代表完整人工或设备方案通过。

| 类别 | 本轮实际结果及证据 |
| --- | --- |
| 原图读取/播放、设置、桌面/M1 widget | 57通过，41秒：[专项](validation/windows-original-preview-focused-second.log)；读取12、SDK/控制器10及相关既有UI回归 |
| Windows来源预检 | 9通过、1跳过，1秒：[预检](validation/windows-source-readiness-focused.log)；跳过项是非Windows分支，不计通过 |
| 账号观察/真实云来源批次/账号widget | 51通过，9秒：[修正后专项](validation/windows-software-health-cloud-second.log)；核心观察42、批次5、widget4 |
| 备份恢复widget | 16通过，23秒：[冲突与回归](validation/windows-software-backup-guidance.log) |
| 原图系统退出/播放/桌面/任务widget | 28通过，36秒：[退出专项](validation/windows-software-preview-exit.log) |
| 全量首次通过版本 | 1122通过、1跳过，128秒：[全量](validation/windows-software-full.log)；随后新增系统退出测试及共同退出接线，最终版本另列 |
| 最终完整unit/widget | 1123通过、1跳过，123秒：[最终全量](validation/windows-software-full-final.log)。包含85项新增参数化/场景检查；不是1123个完整正式UT |
| Windows原生IT-001/002子流程 | 1通过，Debug36.4秒/运行5秒：[最终原生](validation/windows-software-gallery-native-final.log)。真实800×520原图/许可释放/永久副本及身份版本重开，仅临时库/文件，系统取得器由fixture替换 |
| 最终格式 | 226文件0改动，2.08秒：[最终格式](validation/windows-software-format-final.log) |
| 最终分析 | 无问题，6.2秒：[最终分析](validation/windows-software-analyze-final.log)；包含最终原生夹具 |
| Windows Release | 53.3秒构建成功：[构建](validation/windows-software-build.log)；仅本次自有隐藏runner窗口核对所属PID后正常WM_CLOSE退出0：[启动关闭](validation/windows-software-smoke.log)。当前AOT为14,123,912字节、19:14:16生成；C++启动器未改变因而复用原时间戳。未签名、安装或发布 |
| 资源包与需求原文 | 31文件/56引用及90条权威原文完整性通过：[资源包](validation/windows-software-kit.log)、[台账](validation/windows-software-coverage.log)；不是软件测试 |
| PT/人工AT/参考设备PERF | 本轮排除并未执行，不计通过 |
| 真实服务CT | 未授权执行，不计通过；受控确认不冒充服务可用 |

## 失败与修正

- 原图首轮53通过/4失败，61秒：[首轮](validation/windows-original-preview-focused.log)。有效PNG在首帧失败，隔离证明SDK描述对象过早释放：[定位](validation/windows-original-preview-codec-diagnostic.log)。改为codec实际dispose后释放描述对象及缓冲区；[单项复核](validation/windows-original-preview-codec-ownership.log)1通过，后续57通过。没有删除格式断言或替换真实解码器。
- 账号测试首轮缺必填参数，只有云批次5通过/账号加载失败：[编译失败](validation/windows-software-health-cloud-focused.log)。补显式anonymous和恢复历史空集。
- 下一轮46通过/5失败，13秒：[失败记录](validation/windows-software-health-cloud-final.log)。其中1项生产回归为有效会话凭据仍显示未配置，补当前会话的未验证显示，同时保留真实结果观察；另4项夹具错误为固定未来开始时间与实际结束时间不一致，以及同版本旧租约正确阻止新历史清理。夹具改为同一时钟及不同字节的真实资产，不放宽生产租约或备份时间校验。修正后51通过。
- 初次分析1条构造参数提示：[初次分析](validation/windows-software-analyze.log)；采用初始化参数修正，最终结果另列。格式记录保留实际改动，不将格式写入伪报0改动。
- 原生首次运行0通过/1失败，Debug42秒/运行2秒：[首次原生](validation/windows-software-gallery-native.log)。失败清理路径的占用掩盖了原测试错误，夹具改为完整LibrarySession关闭后删除其自有临时目录。第二次因捕获的nullable会话缺显式局部引用而编译失败，30.2秒：[编译记录](validation/windows-software-gallery-native-second.log)。第三次Debug36.4秒/运行2秒仍失败，明确为转场期间全页面RawImage定位同时匹配原图和旧缩略图：[定位记录](validation/windows-software-gallery-native-third.log)。改为精确限定OriginalPreviewScreen内图像并等待路由实际消失；保留800×520、许可释放、身份/版本/字节重开断言，没有修改生产路径或放宽断言。
- 最终原生子流程通过后，主线程已查看[Windows实际图库截图](validation/windows-software-gallery.png)，原图入口与800×520副本信息可见；截图在关闭原图后取得，不以此静态图证明动画播放。首次失败留下的本次临时目录在核对其绝对路径与系统Temp父目录后清理，未遍历其他应用数据。

## 本轮排除后的剩余边界

设备验收暂不挡本轮代码推进，包括真实权限/云占位取得、网络切换/后台、系统选择器/剪贴板接收、输入/读屏/DPI、四设备安装互读、卸载保留、硬件断电和参考性能。Windows原生自动化在现有主机执行仍保留。

真实Catbox/ImgBB精确字节/格式能力、响应与上传/删除确认仍需服务证据；未知能力默认等待，不自动试上传。Catbox公开协议缺可靠删除确认，不能猜200成功；本轮没有真实外部请求。它们不是被排除的设备项。

Android/iOS原生输出、备份与诊断导出仍是代码适配缺口，入口禁用；其他三端工具链/设备未具备，不报告可运行。Windows未知阻塞云资源和其他端取得协议不由本次明确标记预检覆盖。完整格式/方向/隐私契约、全部故障组合和90条正式验收不能据本轮绿色检查宣称完成。后续按这些实际范围推进，不重新安装SDK、引入计费状态或扩大V2/V3。
