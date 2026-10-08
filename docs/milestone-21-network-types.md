# 里程碑21：网络类型观察与已确认任务自动继续

日期：2026-10-07。全 Windows V1 目标继续 active，本里程碑不代表首版全部完成。

## 最新规则与实际行为

用户明确不需要计费状态，只识别网络类型并据此控制自动继续。覆盖需求 QUE-008、测试 UT-063 的计费及“仅非计费”部分，以及技术选型7.3中的成本API；资源包原文不改。“自动同步”遵循既有已确认图床上传意图，不增加应用云账号或图库云同步。

本机策略默认“仅 Wi-Fi / 有线网络”，可主动保存“所有已识别网络（含移动网络）”。离线或观察未确认一律等待；混合 Wi-Fi 与移动网络也不能绕过默认限制。类型只代表系统当前路径，不保证图床可达；应用不发HTTP/DNS探测，不读取计费、SSID、IP或网卡名称。参考 [Microsoft 默认网络信息](https://learn.microsoft.com/en-us/uwp/api/windows.networking.connectivity.networkinformation)、[Android 默认网络观察](https://developer.android.com/develop/connectivity/network-ops/reading-network-state)、[Apple NWPathMonitor](https://developer.apple.com/documentation/network/nwpathmonitor)。

网络许可和网络条件独立：进入页面、保存策略、入队、网络恢复均不会授予本次会话许可。得到许可后，符合网络策略的等待意图自动继续；重复通知不创建任务，unknown不自动重传，单项/整批暂停和单调退避仍生效。只改变观察或策略不取消正在执行的请求；用户主动关闭会话许可仍按原边界尽力停止，真实传输结束与确认独立处理。

派发写入门在真实文件/凭据校验后再次核对运行时条件；拒绝则带网络原因等待，不创建尝试或租约。开始后、实际适配器读取或发送前仍再次核对；明确notSent才允许自动继续意图，不推测未确认请求无副作用。当前默认服务精确限制仍unknown，生产任务会等待能力核验；受控验证不是实际图床可用证明。

观察器属于 LibrarySession。正常关闭先阻止新派发，再停止监听及等待上传/文件真实收尾；替换会话建立新上传actor，策略和当前本机观察可用，但上传许可清空。页面离开不自行创建或关闭另一网络actor。桌面可见但失去焦点仍观察；隐藏窗口停止新派发。移动inactive/隐藏/后台保守等待，返回前台重新读取，不承诺后台持续执行。

任务页“刷新上传资料”会重新读取网络并重建已失效监听，不授予上传许可，也不创建外部请求。网络重读失败时仍独立读取资料库，读取失败保留上次有效列表并显示原有提示；操作反馈使用固定安全文案，不展示原始异常。关闭会话后的刷新回归曾发现网络重读错误跳过资料库失败反馈，已用finally确保独立读取，原保护断言保留。

## 平台、持久化与保护

- Windows：C++/WinRT NetworkInformation首选连接，WLAN/WWAN/IANA类型6分别映射Wi-Fi/移动/有线，其余为other。原生事件回调只PostMessage；UI线程查询与发送，代次和共享安全状态拒绝取消或销毁后的回调。WinRT/COM初始化与窗口析构顺序由runner管理。
- Android：ConnectivityManager默认网络回调，等待能力事件再识别类型；不在onAvailable中同步读能力。主工程声明ACCESS_NETWORK_STATE及既有上传所需INTERNET，回调代次与引擎销毁关闭观察。
- iOS/macOS：NWPathMonitor，只读status和usesInterfaceType，requiresConnection为unknown，不主动建立连接。主线程发送事件，取消/销毁排空本地观察引用。macOS补出站client工程声明，依据 [Apple 沙箱出站权限](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.network.client)；未签名或更改系统配置。
- Dart：严格的两字段协议，握手成功前不发布可派发快照；缺后端、错误、畸形、超时或事件终止即unknown。自有StandardMethodCodec事件接收保留Flutter协议，避免SDK将握手原始异常报告到FlutterError；重读/事件以revision防迟到覆盖，监听以generation隔离。3秒是可注入候选防护预算，并非四端性能实测。
- DeviceSettings自有JSON格式3，加入networkUploadPolicy；自身格式1/2只读取默认，不改输入。未来或损坏设置拒绝，SQL原值及最后有效值保留。仍使用LibraryMetadata，不新增表或依赖；schema9/27表和可携带备份formatVersion1不变。设置编辑继续按确认保存才应用，共同桌面/M1页面展示实际类型和等待原因。

## 修改文件

生产Dart：`core/network_state.dart`、`platform/system_network_monitor.dart`、设置域和设置页、`gallery_providers.dart`、上传coordinator/store接口/持久store、`library_uploads.dart`和任务页。原生：Windows runner六文件、Android三个文件、Apple桥接两文件及macOS两份entitlements。

新增测试：network_state、system_network_monitor、network_session及Windows原生network_flow。既有队列、设置、任务页及原生上传/单项暂停夹具显式注入已确认的网络观察，不能靠默认联网绕过；没有修改生产默认为联网。测试顶端导航补实际sliver布局校正，保持offset必须0；下拉操作真实打开菜单及选择，保留唯一可点击/退出后唯一显示和草稿/失败保护断言。

文档：根AGENTS、两份README、架构、环境、90条验收台账及本记录。三项Sol子代理均按显式gpt-6.1-sol/high、限定写入范围实现；主线程审查实际代码，完成运行时接线、写入门和最终串行验证。未初始化Git、提交、推送、发布、安装组件或新增依赖。

## 实际验证

- 修正后的网络/设置专项85项通过，21秒：[专项](validation/windows-network-focused-second.log)。模型3项、观察器18项及既有共享业务/UI混合范围；之后补桌面inactive两用例及真实会话/写入门用例纳入最终全量。
- 真SQLite、文件和受控multipart的会话流程1项通过：[会话](validation/windows-network-session-final.log)。策略保存后自动继续同一意图，重开和actor重建不恢复旧许可；它不代表真正替换全流程或真实图床测试。
- 写入门与相关队列仓储61项通过，3秒：[写入门](validation/windows-network-gate-tests.log)。实际SQL核对被拒派发后尝试、文件租约、输出租约均0；同一持久意图经网络许可后只有一个尝试。
- 首轮全量879项混合unit/widget通过，77秒：[首轮全量](validation/windows-network-full.log)。之后写入门增强以最终全量为当前证据。
- Windows实际原生观察与生产任务页1项通过，Debug23.5秒/运行1秒：[原生](validation/windows-network-native-final.log)、[当前视口截图](validation/windows-network.png)。本机实际Wi-Fi，方法读取与首次事件监听均有返回，进入页面无任务/授权/外部请求。没有切换用户网络、没有实机离线/移动网络切换，不能声明完整PT-002通过。
- 当前手动刷新接线的Windows原生复验1项通过，Debug25.0秒/运行1秒：[刷新原生](validation/windows-network-refresh-native.log)。真实点击刷新并等待操作结束，再核对网络类型显示、无会话许可及无活动尝试；当前视口截图由这次运行生成，主线程已查看。
- 首轮专项发现派发前notSent后未进入网络等待，已修正；后续失败包含普通test误用widget takeException、sliver导航校正和菜单退出期的双文本，已修正且原断言保留。最初原生测试夹具缺导入/可空类型编译失败已修正。失败日志保留，不计通过。
- 写入门增强后879项现有混合unit/widget通过，75秒：[写入门版全量](validation/windows-network-full-final.log)。不是879个完整正式UT，不能据此认定90条首版全部验收。
- 加入手动网络刷新后首次全量878项通过、1项失败：[刷新首次](validation/windows-network-refresh-full-final.log)。失败是会话已关闭时跳过资料库读取失败反馈；修正后原断言保留，相关9项通过、24秒：[刷新专项](validation/windows-network-refresh-focused.log)，当前最终879项全量通过、74秒：[当前全量](validation/windows-network-refresh-full-fixed.log)。
- 最终Windows单项/整批暂停、真实输入IO与重开原生回归1项通过，Debug24.8秒/运行9秒：[暂停回归](validation/windows-network-item-pause-native.log)、[本轮截图副本](validation/windows-network-item-pause.png)。原测试固定的windows-item-pause.png也更新为当前视口，不将该更新图像作为过去阶段的像素证据；历史运行日志保留。
- 手动刷新接线前Windows Release50.4秒成功：[前版构建](validation/windows-network-build.log)；只对本轮自有隐藏runner请求正常WM_CLOSE，实际创建窗口、退出0：[前版启动退出](validation/windows-network-smoke.log)。没有安装包、签名、发布或真实图床联调；当前最终版本的构建另列。
- Android Manifest与macOS两份entitlements均静态XML解析成功；无计费API调用。资源包31文件/56引用及90条规范完整性通过：[资源](validation/windows-network-kit.log)、[台账](validation/windows-network-coverage.log)，不是软件测试。
- 当前最终Windows Release43.8秒成功：[当前构建](validation/windows-network-refresh-build.log)；真实自有隐藏runner创建窗口、正常WM_CLOSE退出0：[当前启动退出](validation/windows-network-refresh-smoke.log)。当前源码已实际构建运行。
- 当前最终193文件格式0改动：[格式](validation/windows-network-refresh-format-check.log)；整app分析无问题、4.9秒：[分析](validation/windows-network-refresh-analyze.log)。
- 最终文档更新后再次检查资源包31文件/56引用及90条规范原文，均通过：[最终资源](validation/windows-network-refresh-kit.log)、[最终台账](validation/windows-network-refresh-coverage.log)。资源包仍保持原件，不将完整性检查计为软件测试。

Android缺SDK/设备，Apple缺Mac/Xcode/设备，三端桥接仅源码与结构审查。完整Windows下一阶段仍包括自动处理依赖、远端删除、服务契约及授权后的真实联调、跨平台设置转移、性能和完整人工验收；低空间/系统限制仍需分别补证。网络类型切换受控测试不能替代四端实机PT。
