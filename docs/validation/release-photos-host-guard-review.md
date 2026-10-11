# Photos 宿主身份检查与失败收尾审查

2026-10-11。第九轮源 `09b849de824c38a9dbe714ce1e4c390f1f871c65`、[run 38137413108](https://github.com/panlijun/ImageHub/actions/runs/38137413108) 整体 failure；原始产物大小、SHA、闭合白名单及来源映射见 [第九轮记录](release-apple-ninth-ci.json)。

## 实际证据与不能确定的内容

- prepare 的真实 build-for-testing、install 均 exit 0 且 host/reader 已关闭。所记录 built/installed 指纹完全相同。
- add-only 命名 XCTest 实际 1 passed、0 failed、0 skipped，Xcode exit 0 且 host/reader 已关闭；合成 PNG 保存事务及来源、暂存保护通过。
- 后验控制器拒绝 `photos-prepared-host-changed`，仅表示冻结 built/installed、当前两者、安装位置或 generated entitlements 的聚合比较失败；没有逐项当前记录。
- 比较使用短路求值，不能确认 generated entitlements 在后验已经读取；末尾 prepared 原始 SHA 检查也未到达。具体不等字段和实际安装位置是否变化均 unknown。
- 成功 add-only result/identity 不存在，read-write 的前置门槛未完成。full 27 未执行；没有其摘要，也没有新的格式资源读回或 invalid 像素解码断言通过。
- 同一 owned app stop、模拟器 Shutdown 读回、delete 和缺席确认通过。不能把本轮整体记绿或倒推第八轮六项失败已修正。

## 官方依据与本项目判断

Apple 的 [TN2339](https://developer.apple.com/library/archive/technotes/tn2339/_index.html) 说明 build-for-testing 与 test-without-building 的分离：使用 scheme 时，后者从 build root 查找已构建测试包。该文没有承诺 Simulator 中已安装 app 的绝对容器位置永久不变。

Apple 的 [TN2285](https://developer.apple.com/library/archive/technotes/tn2285/_index.html) 说明 app 更新会替换 bundle 并改变容器绝对路径，应查询当前位置。这是一般更新行为说明，不能证明第九轮发生了更新或迁址。

本项目据此将绝对安装位置视为本轮位置观测，将稳定 bundle ID、固定 owned UUID、普通路径、内容与签名等检查作为身份门槛。允许同一自有设备内合法 application-container UUID 改变属于受限控制器修正；第九轮的具体失败根因仍未知。

## 修正与验收边界

- 历史位置只做严格类型、canonical 语法和同 owned UUID 校验，不访问可能已退休的历史目录。当前位置始终由固定 UUID、固定 bundle ID 的 simctl 查询取得，所有祖先必须普通且无链接/reparse。
- 冻结与当前 built/installed 的记录字段、两者相互比较、版本、strict ad-hoc 签名、signature/generated entitlements、context 和 prepared 原始 SHA 都必须一致。不得重写冻结 proof 或以不同内容承接历史身份。
- 后验在真实 Xcode host/reader 关闭后独占发布逐组件观测，区分 observed、readFailed、unobserved 及 bool/null 比较；prepared 在末尾再次闭合读取，未读到不能当作相同。成功 result 绑定观测 SHA；read-write 严格核验前次 add-only 的完整字段、上下文、1 项通过、关闭和停止证明。
- 日志生成或出口故障必须保留主要失败，不能抹掉实际关闭状态或阻止独立 owned guard/stop。诊断只使用固定分类，不 stringify 未知异常；停止、权限、读取、计数或收尾不确定仍拒绝成功。
- 最终源码审查发现的三处异常路径已补齐并独立复核：post 使用首份已验证 proof 的 context，当前版本读取失败仍逐组件观测；Xcode 日志全部生成进入 typed closed 捕获；安全诊断回调贯穿 stop 的归属打印、输出和退出记录，出口失败不阻断实际动作，默认调用行为保留。最终按 workflow 原命令执行186项本机控制、六文件编译通过；[控制记录](release-photos-frozen-host-controls-02.json)与[原始日志](release-photos-frozen-host-controls-02.log)保留受限fixture适配及源指纹，日志SHA-256 `fccf3b1585355a7b281ea47ee7d9f32f8fe797ca077c6520ad7a2b9eecb855b5`。中间170项及构造失败保留为过程证据，不替代最终结果；下一轮Apple仍须实跑。

现有指纹独立记录 Runner 全文件 SHA/长度、Info SHA/长度、原生版本、strict ad-hoc 签名元信息及 entitlements。Runner 包含嵌入签名，可能间接封存其他内容；本记录不宣称独立证明整个 bundle 字节树，也没有证据断言 nested 内容可绕过签名。边界前后观测不等于运行全过程的原子快照。

Python 控制及源码审查只证明控制器行为。PNG/JPEG 的独立原始资源读回、其他格式的实际支持或受保护拒绝、27 项严格终态，均须后续实际 Apple CI；物理设备、最低系统、硬件性能、真实服务和 Apple 正式发行仍单列。
