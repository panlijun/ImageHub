# 图床适配与队列规则基础

日期：2026-10-05。继续 Windows 完整 V1，四端共同业务从开始复用；资源包不变，没有读取旧项目/数据、提交、发布、真实图床上传或删除。

## 本轮已完成

用户明确授权后，补装现有 VS 2022 Build Tools 的 ATL，安装器退出 0、无需重启。账号版 Windows 原生系统凭据流程及 Release/正常窗口退出通过，详见 [账号阶段补证](milestone-05-accounts.md)、[安装记录](validation/windows-atl-install.log)。原生测试只使用新临时库和合成凭据。

采用资源包既定 Dio；真实 pub get 固定 5.11.1，并更新真实锁文件。CatboxAdapter/ImgBBAdapter 独立构造固定 HTTPS multipart 请求，禁跳转、不放宽证书、不记录请求/响应，不健康试上传，不自动重试。每次调用新建表单和文件流；文件尺寸变化、失效与源异常有明确结果。默认精确大小/格式限制 unknown 时不派发，测试的 64 字节/PNG 限制只是夹具，不能当作服务保证。

Catbox 仅接受有效文件直链，ImgBB 核对 success/status/data/远端身份、直接 URL 和查看 URL；控制字符、危险协议、userinfo/query/fragment、异常主机与管理信息混入普通 URL 均拒绝。普通 HTTP 直链显式标记，未来用户提示仍待接线。delete_url 只进入无 JSON、toString 遮蔽的运行时管理秘密包装，尚未写入 RemoteResult 或 SecretStore。

明确拒绝、未发送、不确定副作用与取消分别表达。发送后超时/断连、5xx、重定向和畸形成功保留 unknown；不单凭异常类型推定无副作用。Retry-After 保存 delta-seconds、绝对 UTC 或无效证据；重试映射不剪短有效等待，不把畸形/溢出值退回较短延迟。

审查发现 Dio 默认 FormData 的生产流会独立预读文件、其响应包装取消未必传到原始源。实现按需 multipart、独立文件源订阅及背压；原响应源限 64 KiB。取消时显式启动源关闭与网络收尾，等待实际文件 source.cancel、fetch 和晚到响应关闭，不能把网络 Future 返回当作文件使用结束。完整有效的远端确认仍可作为证据返回，未来队列必须独立保留取消意图；只有部分 URL 或未取得完整响应不能报成功。收尾失败返回固定异常，调用方须保留保护，原始异常不得越界。

QueuePolicy 实现九种状态转换、六种批次判定和五类固定发布项计数；终态不能被取消或迟到事件改写，unknown 仍保护输入，取消后的实际 IO 保护另由租约承担。纯重试策略最多初次加三次，2/4/8 秒且服从更长服务端等待，所有等待条件满足才许可派发。TimeSource 分离 clock UTC 和 Stopwatch；ExecutionBudget 排除暂停/离线/退避，跨尝试累计实际执行，验证 120 秒无活动和 30 分钟累计边界，已耗尽预算不能再开始尝试。

## 验证与边界

| 类别 | 实际结果 | 证据 |
| --- | --- | --- |
| 当前全量核心/参数化/widget | **247 项通过，52 秒**；不是 247 个完整正式 UT，也不代表全部 90 条需求验收 | [全量日志](validation/windows-provider-full-tests.log) |
| 新增适配器/队列规则专项 | **44 项通过**；含全部 729 种有序三项状态组合、两图床 multipart/UTF-8 精确长度、秘密隔离、畸形响应、未知/重试、实际延迟取消 | [专项日志](validation/windows-provider-policy-tests.log) |
| 静态/格式 | Flutter analyze 无问题（16.2 秒）；77 个文件格式检查 0 改动 | [静态](validation/windows-provider-analyze.log)、[格式](validation/windows-provider-format.log) |
| Windows IT-007 账号子流程 | 1 项通过，真实系统写/重开读取/删除读回、同名/匿名隔离与原生页面 | [原生日志](validation/windows-accounts-integration.log)、[截图](validation/windows-accounts.png) |
| Windows 账号版 Release | 67.3 秒构建成功；实际窗口创建、正常 WM_CLOSE，exit0 | [构建](validation/windows-accounts-release.log)、[启动退出](validation/windows-accounts-release-smoke.log) |
| 输入资料完整性 | 31 个资源包文件、56 个本地引用通过；不属于软件测试 | [输入检查](validation/windows-provider-input-integrity.log) |
| CT/IT-008/PT/完整 AT | 未执行真实服务请求；本轮新适配器不计真实服务/设备验收 | [完整台账](windows-v1-coverage.md) |

首次专项暴露停滞文件源取消超时；已改为独立订阅显式关闭，并保留原停滞源、延迟关闭测试。两处测试误将图片二进制按 UTF-8 解码，也已修正为按字节检查，增加 body/Content-Length 和 UTF-8 凭据长度核对。最终 44 项专项和 247 项全量均在修复后执行。没有通过放松断言、塞入额外流事件或增加超时掩盖缺陷。

Windows 系统账号后端已经有运行证据；macOS/iOS 仍缺 Mac/Xcode 与设备，Android 缺 SDK/设备，未构建或运行。主机 M1 widget 不代替手机实机。新传输与队列规则是共同 Dart 代码，尚未接入 UI/调度，不据此声称手机可上传。

## 本轮修改文件

| 范围 | 文件 |
| --- | --- |
| 时间与纯策略 | `app/lib/core/time_source.dart`、`app/lib/features/upload/domain/queue_policy.dart` |
| 图床协议/结果 | `app/lib/features/upload/domain/provider_models.dart`、`app/lib/features/upload/data/provider_adapters.dart` |
| 错误到重试映射 | `app/lib/features/upload/application/upload_retry_policy.dart` |
| 规则验证 | `app/test/core/{provider_adapters,queue_policy,upload_retry_policy}_test.dart` |
| 账号原生测试 | `app/integration_test/accounts_flow_test.dart`：等待真实导航启用后点击 |
| 依赖 | `app/pubspec.yaml`、真实 `app/pubspec.lock` |
| 约定与证据 | 根/app README、AGENTS、environment/architecture/coverage、账号阶段补证、本记录、validation 日志/截图 |

Sol 子代理（实际参数 gpt-6.1-sol、high）实现限定的三个适配器/测试文件，并按主线程复验反馈修复实际 IO 收尾。主线程实现时间/队列策略及重试映射，阅读实际代码、补充公开异常边界，执行全部实际验证。工作区未初始化 Git，无 git diff；没有创建 Git、提交、推送或发布。

## 下一阶段

继续建立持久批次、发布项、尝试/执行代次和事件唯一约束；同一事务保存输入/目标/策略快照与永久版本/处理输出保护引用，再允许报已入队。派发解析当前凭据，停用/移除阻新请求并停止在途，完整晚到确认独立保存，不改取消终态。将预算计时器、独立有界并发、条件等待/退避、暂停与重开恢复接入真实调度器。

随后接入受保护管理信息提交、RemoteResult 与链接/任务 UI、重复发布复用、显式再传和独立远端管理确认。服务精确限制/格式仍须取得可靠契约证据；真实上传或删除另需用户明确授权。备份恢复、设置诊断、移动原生导出、Windows 平台/性能/无障碍及三端环境验收继续保留。完整 Windows V1 尚未完成。

输入协议依据资源包 Catbox/ImgBB 接入说明与技术 7.1/7.2；依赖及行为核查参考 [Dio 官方包与维护文档](https://pub.dev/packages/dio/versions/5.11.1)、[ImgBB 官方 API](https://api.imgbb.com/)。本轮只读 Catbox 官方页面返回访问错误，未据此编造新服务能力，精确限制保持未知。
