# Windows 软件收尾：来源取消与图床能力边界

日期：2026-10-07。延续用户“排除实机验收，继续Windows开发”的范围。未提交、推送、发布、安装软件或执行真实图床上传/删除；资源包原件不变。

2026-10-08 范围更新：用户明确取消 Catbox 匿名上传功能。本阶段记载的手动合成图准备工具已删除，五张已准备图片未发送；以下工具说明和运行结果仅保留为当时的历史记录。当前账号范围及最终 Windows 软件验证见 [收尾记录](milestone-27-windows-completion.md)。

## 实际完成

- IMP-007/008：复制等待首块或下一块来源数据时可以请求停止，不再仅在收到下一块后检查。竞争的只是数据交付；实际源取消清理、正在进行的本机写入结束后，才关闭文件并清理未提交日志/暂存。等待期间保留唯一写入门和资料库根锁，关闭不能提前完成。
- 取得器收到同一取消令牌，在异步来源就绪检查后、打开数据流前再次检查。停止后不重新取得后续资源，既有成功资产保留。已取消的进度不能覆盖等待提示；等待来源/写入结束期间保持禁用再次导入。
- 源清理错误不能报告取消成功：映射本机保存失败，保留 writing 日志及半成品供重开恢复。测试夹具明确先结束实际读操作再抛清理异常，不冒充未知实际 IO 已收尾。源适配器必须遵守取消 Future 等实际 IO 结束的契约；操作系统永不返回的读取仍保持等待，未实现内核强制终止或以超时提前释放保护。
- UPL-004/UT-047：能力模型支持额外格式限额，键大小写归一、独立不可变快照，拒绝归一冲突。格式限额与全局上限取小值；非法、零、负数或未支持格式的额外限额使能力保持未核验。两适配器请求前共用判断，较小GIF限额不被通用上限覆盖。生产默认仍 unknown；本次小整数仅合成测试夹具。
- 已核查两家官方公开文档、页面及直接引用脚本，仅GET。[官方证据记录](provider-contract-evidence.md)区分网页上传器与API服务器契约。Catbox GIF独立文字限制、网页与主页上限不一致及删除确认缺证均单列，不能据此宣布生产服务可用。

## 修改文件

- `app/lib/core/managed_file_store.dart`、`platform_resource.dart`：可取消的来源交付、实际清理等待及取得令牌边界。
- `app/lib/platform/import_gateway.dart`：就绪检查前后取消重验。
- `app/lib/features/gallery/presentation/gallery_screen.dart`：等待提示、重复停止/导入禁用、取消进度隔离。
- `app/lib/features/upload/domain/provider_models.dart`、`data/provider_adapters.dart`：按格式额外字节上限与真实请求前校验。
- `app/test/core/import_source_cancellation_test.dart`、`cloud_import_batch_test.dart`、`provider_adapters_test.dart`、`app/test/import_stop_feedback_test.dart`：实际临时库/文件、等待与持久恢复、取得前取消、界面等待和合成传输边界。
- `app/tool/verify_catbox_synthetic.dart`：独立手动CT准备工具；默认不接受隐式运行，`--prepare-only`不创建适配器或请求；真实上传须另获用户授权且使用明确标志。仅本轮生成五种32×32图片，不打开资料库或秘密存储，没有删除/重试；首个未确认结果后停止，逐项保存普通确认，测试100KiB预算不作为生产服务限额。
- `docs/provider-contract-evidence.md`、本文件、软件范围/Windows台账/环境记录及根`AGENTS.md`：最新规则、证据与未闭合项。

## 验证

- 来源取消核心14项通过，覆盖UT-003/010/011/091子场景：[日志](validation/windows-source-cancel-core.log)。
- 最终来源/取得器/界面专项21项通过，测试运行2秒：[日志](validation/windows-source-cancel-focused-final.log)。这是参数化核心与widget用例数量，不是21个完整正式UT或实机PT。
- 初次组合运行38项通过、新widget未完成；第二/诊断轮也未完成，均保留原日志。主线程只终止已核对父子归属的本次测试进程，没有操作用户应用。诊断显示取消回调已到，测试断言未先重绘且finally直接等待混合fake zone/原生IO导致错误被等待掩盖。修正交替排空方式后暴露原断言，再补重绘，最终widget1项通过：[日志](validation/windows-source-cancel-widget-final.log)。这些失败/未完成不计通过。
- 最终全量软件测试1147项通过、1项跳过，测试运行123秒：[日志](validation/windows-source-cancel-full.log)。跳过的是来源就绪检查的非Windows分支；不计通过。含本机UT子场景、受控传输、widget和文件/SQL集成子场景，不等于1147个完整正式UT。
- 静态检查无问题，分析运行79.1秒：[日志](validation/windows-source-cancel-analyze.log)。格式化228个文件，1个测试文件调整：[日志](validation/windows-source-cancel-format.log)。
- Windows原生IT-001/002子流程1项通过，Debug构建43.7秒、测试5秒：[日志](validation/windows-source-cancel-gallery-native.log)。真实独立副本、SDK原图、关闭重开、失败保留；系统选择器用fixture，不计PT通过。
- Windows Release构建72.8秒成功：[日志](validation/windows-source-cancel-build.log)。当前AOT14,140,296字节，2026-10-07 20:37:39生成；自有隐藏runner窗口创建及正常WM_CLOSE退出0通过：[日志](validation/windows-source-cancel-smoke.log)。未签名/安装/发布。
- 手动CT准备工具编译并执行prepare-only成功：[日志](validation/windows-catbox-synthetic-prepare.log)；5张图总5903字节，报告全部prepared-not-sent、network=false、生产能力未改。工具单独分析无问题：[日志](validation/windows-catbox-synthetic-analyze.log)。没有真实上传/删除；合成文件在app/build下独立UUID目录，不进入生产图库。仅小图联调即使通过，也不能证明API精确大小上限。
- 最终格式检查229文件0改动、1.82秒：[日志](validation/windows-source-cancel-format-final.log)。资源包31文件/56引用完整性及90条V1原文保留检查通过：[资源包](validation/windows-source-cancel-kit.log)、[台账](validation/windows-source-cancel-coverage.log)；这两项不是软件测试。
- 格式限额子代理写入3个分配文件后异常退出，主线程接管、阅读实际文件并完成全量验证；不凭子代理交付状态认定通过。
- 三次未完成测试的独立临时目录已逐项核对绝对路径位于系统Temp、自有新前缀、无链接、文件白名单及排他打开锁成功后清理；未读取或删除用户图库。

## 剩余事项

2026-10-07用户回复“不需要Catbox匿名上传”：取消本轮五张合成图的匿名真实联调安排，全部保持未发送。此前授权问题已按此答复结束，不转为账号上传或其他服务请求。记录仅调整本次联调安排，未修改生产图床功能或默认能力保护。

Windows本机导入/取消保护已有真实软件验证，不能承诺所有未知网络盘、云来源或内核阻塞都能在固定时间停止。系统选择器、真实云下载、强退等设备验收仍按本轮排除记未执行。

Android SDK/设备与Mac/Xcode/Apple设备缺口不变；本轮没有构建运行另外三端，手机M1主机widget不替代移动验收。

真实图床CT-001/002/003/005和IT-008不是实机排除。默认未知能力仍阻止上传；开启生产需要补API字节/格式证据，或由用户明确选择并批准另行设计的应用保守限额政策。真实格式/边界请求须另外授权；服务方没有可靠删除确认时，不得以HTTP成功或链接探测推断已删除。
