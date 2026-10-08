# ImageHost 全新项目技术栈选型文档

文档编号：IH-TS-001  
版本：1.0  
决策日期与资料核查日期：2026-10-03  
适用对象：个人开发与使用的 Windows macOS Android iOS 图片工具  
需求输入：[需求分析文档](requirements-analysis.md)、[单元测试设计文档](unit-test-design.md)  
配套记录：[技术选型审查报告](technology-selection-review.md)

## 1 选型结论与状态

本项目确定采用 Flutter stable 与配套 Dart SDK，共用四端界面和业务代码。核心组合为 Riverpod、go_router、Drift 与 SQLite、Dio、Dart image。永久图片保存在应用管理的文件目录，秘密保存在系统受保护存储；系统导出、资源与网络限制通过少量原生适配实现。首版没有应用服务端、云账户或云同步依赖。

V2 可选个人元数据同步预选 Supabase 托管服务、PostgreSQL、Supabase Auth 与官方 supabase_flutter SDK。该选择不要求首版创建云资源、安装同步 SDK 或提前实现登录；原图和凭据不进入同步。

技术及职责已经确定。精确 SDK 补丁号、依赖锁文件、实机性能参数和签名环境属于初始化与验证产物。本次没有初始化应用、安装开发工具或依赖、编写业务或测试代码、开通云资源、部署或发布；资料核查不表示四端编译或设备测试通过。

### 1.1 最终技术栈总表

| 编号 | 能力 | 已选技术 | 维护类别 | 阶段 |
|---|---|---|---|---|
| T-01 | 主框架与语言 | Flutter stable 配套 Dart | Flutter 与 Dart 官方 | V1 |
| T-02 | 组件与自适应界面 | 官方material_ui Material 3 核心widgets ThemeMode LayoutBuilder Semantics | Flutter 官方 | V1 |
| T-03 | 状态与依赖注入 | flutter_riverpod 稳定 API 无 Riverpod 代码生成 | 上游独立作者与社区 | V1 |
| T-04 | 路由 | go_router 不增加路由生成器 | Flutter 官方 | V1 |
| T-05 | 元数据与持久任务 | Drift NativeDatabase sqlite3 捆绑 SQLite | Drift 上游与 SQLite 官方分别维护 | V1 |
| T-06 | 永久文件与目录 | dart:io path path_provider | SDK与 Dart Flutter 官方包 | V1 |
| T-07 | 图片处理 | image 与 Dart isolate 工作单元 | image 上游作者 SDK isolate | V1 |
| T-08 | 图片预览与交互 | Flutter 图像解码 RawImage InteractiveViewer 自有裁剪控制器 | SDK与应用自有代码 | V1 |
| T-09 | 上传网络 | Dio 独立 ProviderAdapter | CFUG 社区与应用自有代码 | V1 |
| T-10 | 队列 | 自有状态机 调度器 尝试日志 Drift 持久化 | 应用自有代码 | V1 |
| T-11 | 文件与照片导入 | file_selector image_picker | Flutter 官方 | V1 |
| T-12 | 文件导出与系统信息 | Pigeon Platform Channels Android Kotlin Apple Swift Windows C++ | Flutter 与系统官方 API 应用自有桥接 | V1 |
| T-13 | 密钥 | flutter_secure_storage 平台安全存储 | steenbakker 上游社区 | V1 |
| T-14 | 分享与外链 | share_plus url_launcher SDK Clipboard | FlutterCommunity Flutter 官方 SDK | V1 |
| T-15 | 内容摘要与稳定身份 | crypto SHA-256 uuid v4 | Dart 官方与 uuid 上游 | V1 |
| T-16 | 文本规则与本地化 | unorm_dart Unicode17 CaseFolding characters intl gen_l10n ARB 官方组件本地化 | 小型社区依赖与 Unicode Dart Flutter 官方 | V1 |
| T-17 | 模型与 JSON | Dart 不可变类 sealed class json_serializable json_annotation | SDK与 Google 官方包 | V1 |
| T-18 | 备份 | 自有版本化 Manifest JSON archive ZIP64 流式文件接口 | 应用自有代码与 archive 上游 | V1 |
| T-19 | 设置与诊断 | Drift 设备设置 脱敏诊断记录 SDK 错误入口 | 应用自有代码与 SDK | V1 |
| T-20 | 生成与质量工具 | build_runner drift_dev pigeon flutter_lints dart format analyze DevTools | Dart Flutter 官方与 Drift 上游 | V1 |
| T-21 | 验证工具 | flutter_test integration_test clock fake_async 手写依赖替身 | SDK与 Dart 官方包 应用自有代码 | V1 |
| T-22 | 开发与版本管理 | VS Code Dart Flutter 扩展 Git 官方 SDK 固定版本 | 工具上游维护 | V1 |
| T-23 | AI 开发 | 官方 Dart Flutter MCP 官方 agent skills 项目 AGENTS 约定 | Dart Flutter 官方与应用约定 | V1 |
| T-24 | 构建与交付 | Flutter CLI 各系统官方工具 手动签名与分发 | Flutter Microsoft Google Apple 官方 | V1 |
| T-25 | 可选个人云同步 | Supabase PostgreSQL Auth supabase_flutter 本地变更日志 | Supabase PostgreSQL 官方与应用自有代码 | V2 |

维护类别不是保证书。上游官方维护表示该项目自身的维护组织，不意味着所有项目属于 Google；道路图、下载量和近期发布也不能保证未来持续维护。[S01][S02]

## 2 决策范围与评价方法

### 2.1 必须满足的业务条件

需求基线的 V1 有 90 条要求。四端均须完成本地导入、独立副本保管、整理检索、静态处理、结果保留导出、多账号多目标上传、任务恢复和备份恢复。本地核心不依赖应用账户或网络。原图、应用副本、临时结果、缓存、远程文件有不同生命周期，不能用统一缓存策略处理。[需求基线第2至11章](requirements-analysis.md)

个人使用允许简化部署、组织权限、运维和界面分支；不允许降低已确认数据的持久化、清理保护、备份校验和敏感信息保护。现有源码、旧 UI、旧数据库格式和旧技术技能的默认推荐不决定新版选型。首版从新数据开始，但新版自身的未来升级仍须可恢复。

### 2.2 五项评价标准

| 标准 | 本次如何评价 | 不采用的推断 |
|---|---|---|
| 跨端支持 | 框架支持范围 依赖逐功能矩阵 系统接口与构建条件 | 四个平台标签等于所有功能一致 |
| 维护持续性 | 维护主体 正式稳定渠道 发布与变更记录 官方文档 | 官方名称等于永久不弃用 |
| 可靠性 | 成熟接口 类型检查 事务 故障恢复与验证路径 | 包评分或热度等于数据不会损坏 |
| 社区 | 上游公开仓库 包发布 维护说明 生态使用证据 | 单靠星数或下载量决定选择 |
| AI 支持 | 可访问文档 分析器 测试 运行检查 标准代码结构 | AI 写得出代码等于适配与性能合格 |

先按业务硬条件淘汰，再比较个人维护成本。没有统一实测性能、社区活跃排名或 AI 生成正确率数据，因此不制作伪精确评分。发布日期是检索当日观察值，完整兼容性必须在同一锁文件下验证。

### 2.3 官方优先的具体解释

优先使用 Flutter SDK、Dart 官方基础包和平台官方 API。状态、类型化数据库、上传进度、图片处理、安全存储没有一套同时满足本项目所有条件且全部由 Flutter 团队提供的组件组合，因此接纳明确列出的社区依赖。采用薄接口、固定版本、测试夹具和升级检查控制替换成本。

unorm_dart 是局部例外：它是较小、更新不频繁的纯 Dart 依赖，不能称为大型活跃生态。选择它是为了让四端使用相同 Unicode 数据与 NFC 规则，避免系统各自的 Unicode 版本产生判等差异；隔离在 TextPolicy 中，冻结规则版本并用标准语料验证。[S24]

### 2.4 应用结构与依赖边界

采用单一Flutter应用、按业务功能组织的轻量分层。界面与控制器发送操作意图；应用服务执行状态和数据规则；Repository协调SQLite与文件；系统及图床适配器提供可替换外部接口。TextPolicy、LinkFormatter、任务迁移与结果聚合保持纯Dart业务单元，便于独立测试。

| 层次 | 主要职责 | 禁止承担的职责 |
|---|---|---|
| 界面与Riverpod状态 | 展示 输入 局部交互 依赖注入 | 直接删文件 自动重试上传 修改数据库关联 |
| 应用服务 | 图库 处理 调度 备份 清理操作规则 | 复制一套平台UI业务或读取未脱敏秘密日志 |
| Repository与文件协调 | 数据真相 事务 暂存提交 日志与租约 | 将数据库成功当文件自动提交成功 |
| 外部适配器 | 图床响应 系统资源 导出 网络 安全存储 | 擅自决定结果未知重传与永久清除 |
| 纯业务模型 | 参数校验 状态迁移 格式规则 身份关联 | 绑定Widget 原生路径或具体图床JSON内部结构 |

服务通常按图库、处理、上传、备份和系统存储划分，避免为每个按钮建立独立UseCase、为每个表叠加接口链。核心数据与副作用有清楚边界即可，不引入CQRS、事件总线框架或完整DDD套件。

## 3 主框架候选比较

| 候选 | 主要优势 | 主要代价 | 本项目决策 |
|---|---|---|---|
| Flutter Dart | 四端同一框架 主体语言统一 自有渲染与官方分析测试 AI 工具 | 原生插件仍有差异 大图需测内存 需要学习 Dart | 选用 |
| Tauri 2 React Rust | Web UI经验可复用 Rust适合本地计算 插件可扩展 | TS Rust之外移动缺口还涉及 Kotlin Swift 四端系统语义需适配 | 不选 当前旧实现不构成约束 |
| React Native | 移动生态与 React经验 | Windows macOS属于独立平台项目 四端包组合维护增加 | 不选 |
| .NET MAUI | Microsoft维护 C#业务复用 | macOS基于Mac Catalyst 当前没有C#经验优势的证据 | 不选 |
| Compose Multiplatform | Kotlin业务复用 Android iOS桌面已稳定 | 桌面与移动构建体系不同 当前没有Kotlin经验优势的证据 | 不选 |

这些替代方案均可开发工具，不以技术偏见排除。Flutter 官方支持四端；Tauri 官方说明移动插件的原生语言；React Native 官方列出独立桌面项目；MAUI 和 Compose 的平台说明用于核对能力，而维护成本结论属于本项目判断。[S01][S03][S04][S05][S06]

选择 Flutter 的原因是四端同时交付和集中维护。没有新增 Web Linux 要求，不引入 Electron桌面加另一套移动应用，也不把浏览器持久存储当作本机永久图片库。

## 4 界面状态路由与模型

### 4.1 界面组件

选择 Flutter 官方独立material_ui稳定包提供Material 3组件与应用主题，核心widgets仍使用SDK。当前官方已发布独立组件包，SDK内旧Material/Cupertino贡献冻结；新项目采用持续更新的官方路径，不沿用旧教程的import作为长期方案。第一版不引入第三方整套UI框架、桌面皮肤、Tailwind式组件系统或四套原生界面。使用响应式约束、键盘Actions与Shortcuts、Focus、Semantics、触摸目标与系统字体。[S07]

组件本地化使用material_ui提供的GlobalMaterialLocalizations.delegates；不混用旧SDK与新包的ThemeData、页面和本地化类型。go_router与组件包在同一锁文件中验证，转场、Hero和返回行为列入widget及设备检查。兼容桥仅处理上游说明允许的旧组件上下文，不声称它能解决所有公开API类型冲突。cupertino_ui由组件生态按锁文件依赖，不为了iOS另做一套产品界面。

这项技术选择不固定旧项目页面结构。导航、布局和信息密度由新版任务场景决定。深浅主题使用 ThemeMode；简体中文为首版业务语言。主题跟随系统作为实现便利，不新增多语言产品承诺。

### 4.2 状态与依赖注入

最终选择 Riverpod 稳定 Provider、Notifier、AsyncNotifier API。它集中依赖生命周期、异步状态和测试替换，适合同时存在图库、任务、设置和多账号状态的应用。官方 ChangeNotifier 无额外运行依赖，但需要自行管理更多订阅；Bloc 的显式事件结构有价值，首版引入会增加样板。故不叠加 Provider Bloc GetX get_it。[S08]

只使用非生成方式声明 Riverpod，不增加 riverpod_generator。界面状态不是数据真相；上传调度器是应用级服务，生命周期不跟某页面的 autoDispose 绑定。Riverpod 3 的初始化自动重试、不可见订阅暂停和实验持久化不能承担业务上传重试或队列存储；Provider 初始化不得产生远端上传副作用。[S08]

### 4.3 路由

最终选择 Flutter 官方 go_router，以明确的目标与参数组织页面、详情、处理和任务入口。稳定资产身份用作路由参数，凭据和本机路径不写入 URL。相较手写 Navigator 路由，它减少导航状态维护；相较额外路由生成器，保持依赖简单。对话框和局部弹出仍可使用 SDK Navigator。[S09]

### 4.4 数据模型与序列化

选择 Dart 不可变类、枚举和 sealed class 表达状态；备份清单和外部 DTO 用官方 json_serializable 与 json_annotation，生成执行统一使用 build_runner。不引入 Freezed、built_value 或 Retrofit，减少生成体系与注解数量。Drift生成数据库类型，不将数据库行类型直接作为所有业务实体。[S10]

任务状态允许的迁移、Result类型、验证错误和能力矩阵使用显式业务代码。模型用不可变字段，List与Map防御复制后不可变，并明确值相等规则；不能仅把引用声明为final就称其内容不可变。生成器不决定状态机，不自动把缺少字段的远程响应解释成成功。

## 5 存储与文件一致性

### 5.1 数据库比较与决定

最终选择 Drift NativeDatabase 与 sqlite3，在独立数据库执行环境中提供类型化查询、事务、变更观察和新版迁移。直接 sqlite3 更轻，但 SQL映射和升级检查需要自行承担；sqflite_common_ffi 也支持四端，不是因为平台不支持而淘汰，而是本项目更需要类型化关联与迁移检查。不选键值库作为关系型图库和队列的主存储。[S11]

Drift 2.32之后结合 sqlite3 3.x 可通过 build hooks 捆绑 SQLite；不额外加入旧 sqlite3_flutter_libs。具体产物版本、扩展和四端加载结果在初始化时记录。不依赖设备预装 SQLite。[S11]

应用只启一个库写入协调者，图片工作 isolate 不直接竞争写库。明确启用外键；选择 WAL 与 synchronous=FULL 作为初始可靠性配置，校验实际生效值。事务处理记录及引用，不把 FULL 视为对所有硬件断电的绝对保证。不得直接复制活动 SQLite文件或遗漏WAL作为便携备份。[S12]

### 5.2 文件位置与用途

| 数据 | 保存方式 | 保留规则 |
|---|---|---|
| 资产 版本 标签 分类 远端普通结果 | SQLite | 事务与稳定身份维护 |
| 永久副本 | path_provider Application Support内应用管理目录 | 不按临时或缓存过期删除 |
| 临时处理文件 | 独立临时目录与数据库输出记录 | 到期且无保护才清理 |
| 缩略图 | 独立可再生缓存 | 容量策略 活跃引用保护 |
| 凭据与远程删除管理秘密 | 系统安全存储 | 数据库只保留秘密引用 |
| 设备设置与脱敏诊断 | SQLite | 与业务保存使用同一校验入口 |
| 便携备份 | Manifest与白名单图片ZIP | 用户主动导出 不含秘密 |

不为设置另加 shared_preferences，不将秘密保存到普通JSON或SQLite。Application Support是应用保管位置，不是系统承诺卸载后保留的位置。[S13]

### 5.3 跨资源提交与恢复

文件和数据库不具备共同事务，因此选用自有操作日志与暂存提交协议。导入或保存先记录意图，写入暂存文件、流式摘要、关闭并校验，再在同一文件系统发布到永久位置，最后事务提交可用版本及副本关系。仅在最终提交后反馈成功。跨卷导出不使用同卷重命名假设。

崩溃恢复根据意图、文件与校验恢复完整结果或回收未提交半成品；不能把数据库加载异常当空库。任务、临时输出和恢复操作使用保护引用与活动文件租约；取消后本机IO未安全结束，租约继续保护文件。清理通过StorageCoordinator串行协调，不直接遍历临时目录全删。

删除先进入回收状态。永久清除需要确认、无活跃引用，再逐项删除实际字节与更新记录。清理和恢复不能越过管理根目录、符号链接或系统资源授权边界。外部原文件不进入删除目标。

### 5.4 搜索

首版选择带索引的SQLite查询、业务层规范化键与分页；不部署搜索服务，不额外选全文搜索产品。中文子串搜索不以英文分词器替代。以需求基线10,000条元数据实测P95决定是否增加SQLite FTS；该扩展不是首版初始化依赖。显示名称、标签、分类和远程目标的规则由TextPolicy统一生成，不能误称SQLite NOCASE覆盖所有Unicode大小写。[S12][S24]

## 6 图片处理与资源预算

### 6.1 引擎选择

最终选择 Dart image 的稳定发行版作为四端共享静态处理引擎，通过自有 ImageProcessor 接口调用，在 Dart isolate 执行。当前维护者文档列出包括WebP的读写能力；不能沿用旧版本WebP只读结论。flutter_image_compress未列Windows并存在macOS WebP编码缺口，因此不作为共享唯一引擎。[S14][S15]

image的优势是纯Dart四端复用、可组合像素操作和容易构造夹具。主要成本是完整解码及中间画布的内存、编码耗时与色彩/元数据处理需要测量。现阶段不引入Rust C++通用图片引擎或FFmpeg；本项目不处理视频。没有实测证据时不宣称纯Dart一定比原生快或慢。

### 6.2 已选图片能力矩阵

| 输入类型 | 导入与预览 | 原样上传 | 静态处理与输出 | 隐私策略 |
|---|---|---|---|---|
| 静态PNG JPEG WebP | 必须支持 | 用户确认的确定字节 | 裁剪拼接缩放 输出PNG JPEG静态WebP | 默认去敏 方向与颜色信息按允许清单处理 |
| 静态GIF BMP | 必须支持 | 必须支持且匹配图床限制 | 解码后输出PNG JPEG静态WebP | 不要求重新编码GIF BMP |
| 动画GIF WebP | 必须支持播放与暂停 | 保留原字节及真实内容身份 | 显式选帧确认后静态化 | 不能保持动画并安全去敏时停止并要求选择 |
| HEIC HEIF | 首版非必需 | 仅识别能力确认后 | 不列全端承诺 | 不静默由系统转JPEG并称原格式 |

Flutter SDK图像解码作为预览基础。动画暂停使用自有逐帧控制与当前帧保留；不将全部帧同时解码缓存。处理预览用缩略尺寸，执行坐标基于方向修正后的原始像素。[S16]

### 6.3 图像规则由业务层执行

图像库只是执行器。先读取内容特征、估算资源、应用方向、校验参数，再调用处理；裁剪函数可能调整越界区域，必须在调用前拒绝非法正式输入。resize不使用默认最近邻作为所有缩小策略；初始选择平均下采样用于缩小，输出用夹具检查。JPEG或静态WebP质量整数1–100，PNG不提供伪有损质量参数。[S14]

裁剪交互、拼接网格、来源关系和处理快照使用自有控制器与业务模型，不依赖专用裁剪UI插件决定业务坐标。两张横纵拼接、多张网格和居中像素取整严格使用IMG-006与IMG-007规则。调色板输入先转为处理允许的像素格式再下采样，新画布合成不原地重叠覆盖同一对象。WebP体积优先显式设置lossless=false后应用quality；保真优先不得把无效quality变化显示成压缩策略生效。固定参数生成的新内容需重新计算摘要。

“保真优先”至少保留规定尺寸、透明和动画特征，不承诺一定更小；有损编码不能称数学无损。默认隐私处理使用MetadataPolicy：仅传递经过验证的必要方向与色彩信息，不无条件复制EXIF/XMP等。方向烘焙后移除重复旋转标记；元数据清理失败不回退原样上传。动画原样上传与默认去敏不能同时满足时，按需求请求用户明确选择，不静默丢帧。维护者格式支持清单不是隐私去除的验证证据。

### 6.4 工作单元与取消

选择有边界的图片工作单元与可终止isolate，传入管理文件引用和参数，返回暂存输出与检验信息；避免在主isolate完整读取图片再复制给工作isolate。默认处理并发1，批次逐项读取，不一次加载100张原图。终止工作单元后由主进程确认IO租约结束并回收半成品。

资源预算先按输入解码、输出画布、中间结果和编码临时空间估算，初始候选工作内存预算为移动256MiB、桌面512MiB，并非已测可用内存或需求新阈值。实施时在四端设备压力下校准，平台压力信号只降低新派发；超预算在巨大分配前拒绝并提供降尺寸或减少输入动作。isolate隔离UI计算，不保证操作系统后台存活。[S17]

图库采用分页和缩略图；SDK decoded image cache与应用磁盘缩略图缓存分别限额。不能因为设置了256MiB磁盘缓存就声称内存占用受控。

## 7 上传网络与任务状态

### 7.1 网络选择

最终选择Dio。官方http更精简且适合一般API请求，但本项目需要上传进度、取消、multipart、超时和统一响应分类；Dio减少自有网络样板。不上Retrofit，不将多图床包装成不能解释响应的通用插件。[S18]

CatboxAdapter与ImgBBAdapter独立实现声明能力、请求构造、输入限制、结果解析和错误分类。API协议来源继续使用既有官方图床资料，不引入额外图床。健康检查无安全接口时显示未验证，不用试上传验证密钥。

文件采用multipart流式上传，不批量base64化原图。每次新尝试重新创建FormData与MultipartFile，不能复用已消费的上传流。TLS证书校验默认开启，禁止为兼容而全局忽略证书错误。日志不得打印完整Dio请求、响应、headers或FormData；敏感值、字段、URL和备用异常文本经过统一脱敏。

### 7.2 持久队列与重试权威

选择自有Dart调度器与SQLite持久状态机，不使用远程队列或Dio重试插件。任务、尝试与批次分离，尝试身份、执行代次、依赖和取消意图可持久化。只有调度器决定初次加最多3次自动重试及2/4/8秒等待，遵守Retry-After和unknown边界。

运行时间使用SDK Stopwatch等单调计时，审计时间用UTC；等待与运行时间分别累计。统一可注入TimeSource，墙钟通过官方clock取得，测试用fake_async和模拟单调时钟，避免DateTime.now散落各模块。Dio超时配置不等同需求连续120秒无活动和累计实际运行30分钟，额外活动看门狗必须按上传/下载事件维护，暂停离线与退避不混入累计运行。

响应确认与RemoteResult提交采用事件唯一约束和事务。迟到结果根据尝试身份决定是否记录历史证据，不能覆盖新尝试。取消网络请求不能证明远端未收到图片。unknown不自动重复发送，恢复依照可用证据与用户选择。

### 7.3 网络许可与后台

选择原生网络观察适配，不增加connectivity_plus：它的连接类型不能独自证明非计费或互联网可达。Android用ConnectivityManager与NetworkCapabilities，iOS/macOS用NWPathMonitor的expensive/constrained信息；Windows用INetworkConnectionCost的GetCost及NLM_CONNECTION_COST分类。实际可达性以已授权请求结果判断。移动端非计费许可严格执行，桌面可按同一适配报告条件；unknown时保守等待或让用户明确选择，不将WiFi一律解释为免费网络。[S19]

首版前台执行与重开恢复，不选Workmanager或后台服务插件，不承诺锁屏连续上传。应用Lifecycle只用于安全收尾和状态保存。暂停停止新派发，运行项可完成；它不表示分片续传。桌面关闭主窗口首版选择退出前说明活动任务、保存状态与安全结束；不额外引入托盘常驻。[S20]

## 8 导入导出与系统适配

### 8.1 导入

选择官方file_selector用于文件入口，官方image_picker用于移动系统图片多选。path_provider获取应用目录，dart:io和path处理内部文件。Android启动时处理image_picker.retrieveLostData；临时选择器路径只用于取得字节，成功副本不依赖它长期有效。[S21]

资源类型通过PlatformResource抽象区分普通路径、content URI、照片资源和授权引用。读取完成前不宣称已入库；云照片下载、活动被终止、部分权限和格式转换分别报告。首版不引入permission_handler，不以完整图库读取或广泛文件权限作为导入前提。

桌面拖入不是既定必需入口。首版保留完整多选文件入口，不引入desktop_drop；未来加桌面拖入时可采用该包，但不能称其为四端统一能力。[S21]

### 8.2 导出与保存

| 平台 | 文件导出已选实现 | 图片位置保存已选实现 | 成功判定 |
|---|---|---|---|
| Windows | file_selector保存位置或目录 内部流式复制 | 用户选择的Pictures目录文件 不承诺专有Photos相册 | 关闭写入并校验实际目标 文件冲突生成新名 |
| macOS | file_selector 用户选择位置 沙盒授权 | 首版为文件导出 不操作Photos图库数据库 | 实际复制完成 且用户授权有效 |
| Android | Kotlin SAF单文件ACTION_CREATE_DOCUMENT 批量ACTION_OPEN_DOCUMENT_TREE | MediaStore.Images 写入后发布 | 完整写入关闭后解除IS_PENDING 返回实际URI |
| iOS | Swift UIDocumentPicker导出副本 | PhotoKit addOnly写入图片资源 | 系统完成成功与取消失败分别记录 |

file_selector移动端没有保存位置对话框；share_plus完成分享也不代表图片已保存，所以它们不能替代本节实现。iOS导出先生成完整导出副本，再调用系统选择器；批量项按系统返回证据归类，能力不允许验证时不伪称目标校验成功。[S21][S22]

Android和iOS原生系统API分别来自Google与Apple官方。桌面“保存图片文件”不显示成“已加入Photos”。移动保存系统照片是OUT-003与PLT-005的一种实现入口，不改变永久应用副本生命周期。[S22]

### 8.3 桥接技术及边界

确定使用Flutter官方Pigeon生成Platform Channel类型接口。Android实现Kotlin；iOS/macOS实现Swift；Windows实现C++。桥接限定资源流转、文件导出、照片写入、网络计费状态、可用空间及压力信息，不把图库、处理布局或调度业务复制到原生端。[S23]

采用稳定Platform Channels，不启用Pigeon实验Native Interop。锁定生成器版本，Dart和宿主生成代码一起更新；桥接以文件/资源句柄和结果传递为主，不通过Channel往返巨幅像素数组。

### 8.4 分享剪贴板与外链

选择share_plus提供用户主动系统分享；使用官方url_launcher打开普通http/https链接；使用SDK Clipboard复制。格式生成由自有LinkFormatter处理Markdown HTML BBCode转义与稳定去重，不依赖富文本或HTML渲染插件。不把远程内容当可执行代码，删除秘密不混入普通链接。[S21][S25]

分享区分系统返回的成功、取消、调用失败与结果不可确认。share_plus的unavailable可能表示平台无法判定用户动作，不等于分享功能缺失或失败；这时说明已打开分享但结果不可确认。success仅表示系统报告的分享动作结果，不能证明接收应用已保存文件或实际送达。url_launcher打开桌面文件不是资源管理器定位选中文件承诺，首版无必要时不增加reveal插件。

## 9 安全与隐私

### 9.1 密钥存储

选择flutter_secure_storage，身份记录只存secret reference。社区包调用平台受保护存储，仍要验证实际插件配置；不宣称四端安全后端完全一样或完全防御本机管理员。[S26]

iOS/macOS明确关闭synchronizable并使用ThisDeviceOnly前台可用的访问等级；Android排除秘密存储的云备份与设备迁移，同时配置旧与新备份规则。只设置allowBackup=false不足以保证所有厂商的设备间迁移关闭。Windows构建检查插件额外ATL要求。不能读取密钥时允许不保存的会话使用，不回退明文。[S26][S27]

删除账号、移动数据恢复和云账户退出使用不同秘密命名空间；应用备份不打包秘密。删除管理token单独保护，不通过RemoteResult普通序列化外发。

### 9.2 不额外引入的安全产品

首版不默认选择整库SQLCipher、图片加密库、生物识别登录或商业证书固定服务。原因是当前没有加密全部图库或应用登录的需求，这些会增加备份、恢复和跨端维护复杂度。系统设备保护、最小授权、TLS和秘密存储仍执行；用户未来提出新的威胁模型再独立设计。

统一SecretRedactor服务在记录前、导出前和异常显示前工作。敏感值注册、结构字段和URL规则均需验证；没有认证的弱哈希替代密钥保护，也不为了调试默认打开联网遥测。

## 10 文本身份与时间

内容摘要选官方crypto SHA-256，通过文件流计算；内容判等有摘要和字节数检查，涉及已有副本时保留可复核完整性证据。资产、版本、设备、操作、事件与尝试使用uuid v4稳定身份，任务顺序不依赖UUID自然顺序。[S28]

TextPolicy选unorm_dart实现统一NFC，characters用于界面字符边界。本技术基线明确解释需求中的Unicode字符长度：去首尾空白并NFC后，按Unicode标量数计数，保留原1–64上限；显示截断按grapheme边界，二者不混用。将组合emoji、重音组合等补入UT-014与UT-015实施夹具，避免测试者自行决定计数规则。

标签判等采用NFC、Unicode17默认完整CaseFolding、再NFC，显式选择官方CaseFolding.txt中C与F映射，不使用依区域变化的T映射。实施时从固定官方数据生成应用内纯Dart映射，记录来源版本和校验，运行时不下载Unicode数据；不以String.toLowerCase或SQLite NOCASE替代完整规则。保留首次显示名，Σ/σ/ς以及ß/SS的等价夹具用于验证一致判等。该策略是新版对不区分大小写要求的实现解释，规则升级需版本化检测冲突，不能静默改变已存标签身份。[S24]

本地化使用官方组件包本地化delegates、intl、gen_l10n与ARB；flutter_localizations的使用遵从所选组件版本，不混用旧设计组件delegate。首版只交付简体中文；格式化时间不改变UTC排序。持续时间和等待不依赖用户墙钟，跨重启采用可解释的剩余等待记录，不凭系统时间倒退无限等待。[S07][S29]

## 11 备份恢复与诊断

最终选择版本化JSON Manifest和ZIP64图片容器，archive使用文件流接口；完整备份的图片条目明确采用store无二次压缩方式。仅选择流式接口不能证明内存有界：上游部分压缩分支会缓存单项压缩结果，因此不默认对大图片使用deflate或bzip2。小型清单若压缩须先受大小预算限制；不调用内存版整包编码处理大备份。[S30]

备份通过写入协调器取得一致的已提交业务视图，并在完成前持有必要副本保护引用。清单含格式版本、范围、逻辑身份、条目字节数与SHA-256；严格白名单导出，不直接序列化全部数据库。缺少必要永久副本阻止完整成功，可明确改成元数据备份。

恢复先在暂存区域校验路径、重复条目、声明大小、实际累计解压大小、条目数量、摘要与可用空间，再提交。限制解压膨胀，禁止绝对路径、越界和符号链接逃逸。仅按ZIP内声明尺寸检查不足。合并与替换使用BAK-004的确定规则，当前快照和操作日志承担失败回滚，晚到任务回调有执行代次隔离。

诊断选择SQLite结构化事件与统一脱敏，保持30天和10MB默认边界；日志索引及压缩不引入独立监控平台。SDK FlutterError与PlatformDispatcher入口接入同一脱敏服务，默认不使用Sentry Crashlytics或分析SDK。开发调试指标用DevTools，发布给用户的诊断不携带原图或密钥。

## 12 测试与AI开发工具

### 12.1 验证体系

选择flutter_test进行业务与widget测试，integration_test进行应用集成流程，clock与fake_async配合TimeSource控制时间；网络存储权限图床通过手写替身与构造注入控制。首版不额外引入Mockito Mocktail Patrol或截图测试平台，避免多个测试生成与设备框架。原生权限对话框与系统文件选择采用真实设备验收，不将integration_test描述成自动覆盖所有系统UI。[S31]

测试设计复用unit-test-design.md，不因选技术栈而删除其映射。重点覆盖库加载保护、文件提交、去重、取消租约、迟到事件、unknown、有限重试、结果幂等、备份秘密排除和恢复冲突。原生接口契约分别测试，图片编解码用实际样例与输出字节校验。

### 12.2 AI工作方式

选择官方Dart/Flutter MCP与官方agent skills，使用支持这些接口的AI开发客户端；不将某个商业模型或产品登录作为应用运行依赖。MCP提供分析器、符号、测试与运行检查入口。没有证据证明某模型在Flutter全面优于React，因此不以模型排行榜替代本次架构判断。[S32]

后续新仓库用AGENTS说明已选依赖、业务不变量、禁止擅自添加库、生成命令和验证门禁。AI必须检查真实调用链和当前上游文档，按完整小功能提交改动并读取实际diff；不得把生成代码、编译或单元测试通过当成照片授权、性能与四端交付已完成。

选择VS Code与Dart Flutter扩展、Flutter DevTools。Flutter SDK固定到确切stable版本，Dart使用随附版本，不单独更新。Git管理源文件、pubspec.lock、数据库迁移、生成规则和四端宿主配置；不用FVM Melos作为首版必要工具，不拆成多包monorepo。[S33]

## 13 构建发布与兼容范围

### 13.1 本项目首版目标矩阵

| 平台 | 选定目标系统与架构 | 开发构建工具 | 首版分发方式 |
|---|---|---|---|
| Windows | Windows11 x64 | Windows Visual Studio C++ CMake Windows SDK ATL | Flutter release完整目录ZIP 手动解压运行 |
| macOS | macOS12或更高 arm64 | Mac Xcode 命令行工具 原生插件依赖工具 | release app ZIP 开发验证与手动分发 |
| Android | Android10 API29或更高 arm64 | Android SDK 固定项目Gradle AGP Kotlin Java17兼容组合 | 签名release APK 手动安装 |
| iOS | iOS15或更高 arm64 | Mac Xcode 签名与设备配置 | Xcode自用设备安装 正式持续分发走Apple允许渠道 |

这是本项目主动选择的首版兼容范围，属于PLT-006设计输入，不是声称Flutter不支持Windows10或macOS Intel。Windows arm64、macOS Intel、Android低于10、Web与Linux不纳入首版承诺；若实际个人设备需要，必须补兼容验证。macOS Intel另有Flutter弃用策略提示。[S01]

不凭当前机器推断用户拥有Mac或iPhone。Apple端构建与测试需要相应环境；没有环境证据前不得标四端已交付。免费开发签名不是长期无限分发保证，正式iOS分发需要遵循当前Apple规则。此处选定渠道方向，不开通账户或付费。[S34]

Flutter框架最低系统只是下限，所选插件可能提高要求。share_plus、安全存储和宿主模板的Java Kotlin AGP Gradle CocoaPods/SPM要求统一解析；不单独全部升级到最新。当前原生插件组合需要时保留CocoaPods，不假定全部已经支持Swift Package Manager。[S25][S34]

Windows不选额外安装器、自动更新框架和Store账户。macOS需要对外正常分发时增加Developer ID签名与公证，不能把解压app绕过安全提示作为可靠发布承诺。Android备份规则、iOS钥匙串及macOS沙盒权限进入打包检查，不只在debug环境验证。

### 13.2 构建与自动化

初期选择本机Flutter CLI构建、手动签名和手动验收，避免要求云构建账户。可选CI明确采用GitHub Actions官方工作流机制，不作为首版产品运行依赖；启用时使用官方checkout与artifact操作，固定提交版本，SDK从官方发行来源按校验值获取，不默认引入第三方Flutter安装Action或Fastlane。签名秘密不提交Git。实际启用外部CI仍属于后续操作。

## 14 未来云同步预选

### 14.1 候选比较与决定

| 候选 | 优点 | 对本项目的限制 | 决策 |
|---|---|---|---|
| Supabase PostgreSQL Auth | 官方Flutter SDK列四端 SQL与事务 可限定RLS 有托管和自托管路径 | 离线冲突与删除规则仍需应用设计 托管限额可能变化 | 预选V2 |
| Firebase Firestore Auth | 成熟Google服务 移动SDK生态 | 官方Flutter配置说明Windows不面向生产用途 桌面部分能力beta | 不选四端生产同步基座 |
| WebDAV | 普通文件交换服务可自行控制 | 不是业务变更与冲突协议 条件写入能力及账号差异需自建 | 不选 |
| Apple CloudKit | Apple生态官方服务 | 对四端并非统一Flutter官方SDK路径 跨平台认证与适配增加 | 不选 |

Firebase限制依据当前官方Flutter设置文档，不能从移动端成熟推断Windows生产承诺。Supabase Flutter SDK属于Supabase官方，不属于Flutter团队；SDK默认会话持久化需要额外安全配置。[S35][S36]

### 14.2 V2已选职责

选择Supabase托管PostgreSQL、Supabase Auth的邮箱密码登录、官方supabase_flutter SDK。个人实例由管理员预置本人账户并关闭公开注册，客户端不保存密码；不接入匿名身份、社交登录或手机号认证。默认邮件服务不作为持续登录或找回的可靠性依赖：初期账号恢复由本人通过服务管理端完成；若V2产品增加邮件找回，须另选SMTP并验证。应用用本地SQLite变更日志和同步适配器进行用户主动同步；服务端SQL事务/RPC分配变更游标与校验基础版本。Realtime不作为一致性或首版依赖；前台同步及用户刷新先实现，不要求常驻连接。

即使只有一个人，也必须按Auth用户身份配置RLS和写入权限，包括RPC执行权限；数据库函数优先security invoker，不默认绕过RLS。客户端只有允许公开的项目连接信息，绝不带service_role或其他管理员密钥。同步会话秘密用自定义LocalStorage接入已选安全存储，避免照抄SDK默认shared_preferences路径。登出与换身份清除对应会话并隔离旧同步执行代次，不能让旧响应写进新账户。[S36]

同一人不同设备仍可能离线冲突。按SYN-004保留并发候选与共同有效值，不靠设备墙钟最后写入胜出；稳定事件身份及基础修订处理重复、启停和退出。普通同步只含白名单逻辑记录和链接，不启用Supabase Storage保存原图，不把删除秘密当普通远程字段。

V1仅保留稳定身份和版本化数据接口，不创建V2云表、Auth、SDK依赖或登录入口。V2开始时检查地区可达性、隐私、服务条件、邮件投递与实际费用；本次不保证永久免费配额或永久可达。首版账户和离线边界保持不变。

## 15 依赖维护快照与升级规则

### 15.1 观察版本

下表是核查当日维护者页面显示的版本，不是已经执行pub解析的安装清单。实施必须固定完整锁文件；不能把多个独立最新版本拼起来就声明兼容。

| 依赖或工具 | 观察版本或渠道 | 维护身份 | 采用范围 |
|---|---|---|---|
| Flutter Dart | 官方stable 资料以Flutter3.47描述 | Flutter Dart官方 | SDK整套固定 |
| material_ui | 1.5.0 | flutter.dev | 官方Material 3组件 |
| flutter_riverpod | 3.4.3 | dash-overflow上游社区 | 稳定状态与注入 |
| go_router | 18.0.2 | flutter.dev | 导航 |
| drift sqlite3 | 2.35.1 与3.7.0 | Simon Binder上游 | NativeDatabase捆绑SQLite |
| dio | 5.11.1 | CFUG | HTTP上传 |
| image | 4.10.1 | Loki3D上游 | 静态处理 |
| file_selector | 1.1.0 | flutter.dev | 文件入口 |
| image_picker | 1.2.3 | flutter.dev | 照片选择 |
| path_provider | 2.1.6 | flutter.dev | 应用目录 |
| url_launcher | 6.3.3 | flutter.dev | 外链 |
| share_plus | 13.3.1 | FlutterCommunity | 分享 |
| flutter_secure_storage | 11.2.0 | steenbakker.dev | 秘密 |
| pigeon | 29.0.6 | flutter.dev | Platform Channel生成 |
| json_serializable | 6.14.1 | google.dev | JSON生成 |
| flutter_lints | 6.0.0 | flutter.dev | 静态检查 |
| unorm_dart | 0.3.2 Unicode17.0 | codingfeline.com | 规范化局部例外 |
| supabase_flutter | 2.18.0 | supabase.io | 仅V2 |

其他辅助包crypto path uuid archive intl characters fake_async build_runner drift_dev json_annotation的精确解析版本随锁文件记录，选择其稳定上游发行，不依赖git main或私有fork。包角色已选定，不需要为未初始化的应用伪造解析后的传递依赖清单。[S08至S36]

### 15.2 直接依赖职责清单

| 类别 | 已选依赖 | 声明原则 |
|---|---|---|
| V1运行依赖 | flutter SDK material_ui flutter_riverpod go_router drift sqlite3 dio image file_selector image_picker path_provider path crypto uuid archive unorm_dart characters intl json_annotation flutter_secure_storage share_plus url_launcher clock | 业务直接调用的包明确声明 不靠其他包偶然传递提供 |
| V1开发依赖 | flutter_test SDK integration_test SDK flutter_lints build_runner drift_dev json_serializable pigeon fake_async | 生成和测试工具不作为额外产品服务 |
| 框架生成与平台传递项 | flutter_localizations cupertino_ui 及所选插件平台实现 | 由固定组合解析 必要直接使用时声明 不人工拼装全量版本 |
| V2新增直接依赖 | supabase_flutter | 仅V2启用 不提前植入首版 |
| 自有实现 | 状态机 提交日志 租约 元数据策略 文本CaseFolding映射 Manifest LinkFormatter 原生适配 | 属于本项目代码 无未选语言框架或额外运行服务 |

Unicode映射生成使用固定官方数据和可重复的Dart开发脚本；不是下载后的运行时插件。镜像源仅用于按官方指引获取同一上游产物，不能随意使用未知fork替换依赖。

### 15.3 持续维护控制

应用发布以锁文件为准，SDK补丁、包主版本和宿主工具升级分别审查。不自动跟随latest；新主版本先看变更与弃用，生成代码、数据库升级与四端release构建通过后再替换。为每个直接依赖保留维护者、来源、许可证、版本、用途、平台限制和替代接口。

使用flutter pub outdated和上游公告定期查看兼容更新，安全或平台强制变化优先处理。发布频率低不自动等于停更，例如lints上游按批次更新；频繁发布也不自动等于可靠。发现维护中断时按接口与夹具迁移，不让业务直接绑死包的内部模型。

许可证在实际锁定版本核对，首选允许个人应用分发的开源许可；传递依赖及本地二进制许可说明随分发保留。没有执行解析与许可证扫描之前不宣称全量许可审核通过。

## 16 需求覆盖与实施门禁

### 16.1 技术职责覆盖矩阵

| 需求组 | 已选技术职责 | 重点验收 |
|---|---|---|
| IMP-001至008 | 系统选择 PlatformResource FileStore crypto Drift | 多选取得字节 副本提交 去重与撤权 |
| LIB-001至008 | Riverpod go_router Drift TextPolicy SDK界面 | 整理保留 搜索排序 回收与修复 |
| IMG-001至009 | image ImageProcessor isolate SDK控制器 | 格式方向坐标 透明动画 资源预算 |
| OUT-001至005 | FileStore 输出记录 租约 原生导出 | 永久保存 导出冲突 清理不误删 |
| ACC-001至006 | ProviderAdapter SecureStore Drift | 多账号隔离 能力真实性 无副作用验证 |
| UPL-001至007 | Dio MetadataPolicy 结果事务 | 精确版本 每目标结果 输入快照 |
| QUE-001至010 | Scheduler Drift 尝试身份 单调时钟 系统网络 | 有限重试 unknown 取消恢复 并发汇总 |
| LNK-001至004 | LinkFormatter Clipboard url_launcher share_plus | 转义稳定顺序 分享真实状态 |
| BAK-001至006 | Manifest archive 操作日志 暂存恢复 | 白名单 完整性 ZIP越界 合并替换 |
| OPS-001至005 | Drift Settings SecretRedactor StorageCoordinator | 保存失败 原因清晰 空间保护 |
| DAT-001至005 | SQLite事务 迁移 文件提交日志 身份摘要 | 加载不清库 一致性 新版本可恢复 |
| SEC-001至006 | 安全存储 TLS 最小权限 白名单 脱敏 | 密钥不外发 平台备份排除 |
| PLT-001至006 | SDK与四端宿主 Pigeon 系统适配 | 核心语义 真实设备 系统范围声明 |
| NFR-001至005 | 分页 isolate 缓存限额 测量工具 | 响应启动 性能压力 故障恢复 中文 |
| SYN-001至008 | V2 Supabase 本地变更日志 冲突规则 | 只同步信息 启停隔离 秘密排除 |
| V3扩展 | 稳定接口 新增需求另行设计 | 不计入首版完成 |

矩阵覆盖全部V1需求组，详细验证继续以原测试设计的编号映射为准。此表是技术职责映射，不声称替代逐条测试用例。

### 16.2 必须完成的实施门禁

| 门禁 | 执行时点 | 通过证据 | 失败处理 |
|---|---|---|---|
| GATE-01 SDK与依赖组合 | 新项目初始化 | 固定SDK pubspec.lock 四端release构建 官方组件路由类型转场 本地化 与许可证清单 | 调整兼容版本 更新选型记录 不降低功能 |
| GATE-02 图片样例与内存 | 核心处理前 | 五种静态格式 动画GIF/WebP 方向透明实际输出 12MP与长图测量 | 修复处理与预算 无法满足才修订引擎ADR |
| GATE-03 系统资源与导出 | 四端早期验证 | 照片云资源 文件多选拒权导出取消低空间 单项批量 | 修复系统适配 不用分享成功冒充保存 |
| GATE-04 故障与持久化 | 本地闭环完成前 | 提交边界强制中断 WAL恢复 清理保护 备份损坏与秘密扫描 | 阻止首版交付 |
| GATE-05 网络与任务 | 上传闭环完成前 | 模拟图床契约 真实授权联调 unknown 限流取消计费控制 | 不启用盲重试或无证据成功 |
| GATE-06 四端性能与交付 | 首版验收 | 四台实际基准设备信息 与NFR测量及安装证据 | 调整实现和预算 公开未通过项 |
| GATE-07 V2云边界 | V2实现前后 | RLS 会话秘密 白名单 冲突与退出重复测试 费用核查 | 不影响V1离线核心 |

每平台选择一台仍受支持的常用实际设备，记录型号系统CPU内存存储和数据集；当前没有设备清单，不能虚构型号或成绩。建议移动4GB级与桌面8GB级作为初始测量类别，实际设备以实施时可得资源为准。性能验收使用原NFR建议目标，不把这里的预算候选数字当实测。

## 17 分期实施与明确不选项

第一阶段锁定SDK、依赖和四端宿主，尽早跑通导入副本、预览、一次静态处理、文件导出和重启恢复；Apple端验证不能延至其他代码全部完成之后。第二阶段实现完整图库、处理、保护清理和备份恢复。第三阶段加入两图床与可靠多目标队列，完成故障与四端验收。V2之后才启用云SDK、服务端迁移和认证。

首版明确不选应用后端、多人角色体系、微服务、分布式队列、Redis、对象存储云备份、GraphQL、动态插件市场、AI识图服务、FFmpeg、托盘后台常驻、自动更新服务、后台持续上传插件、默认遥测和多套UI/状态框架。它们不是满足当前需求的必要条件。

不用为个人工具追求无依据的极限包体或吞吐量；数据保护、可解释失败和实际使用维护成本优先。任何未来扩展需要独立需求与验收，不通过安装一堆备用包提前实现。

## 18 来源与核查说明

所有外部来源于2026-10-03核查。以下使用框架或平台官方资料及包维护者资料；维护情况为当日观察，不保证将来。术语“选择”“使用”“必须”在本文描述新项目技术决策与实施约束，不表示已经实现。

| 来源 | 官方或上游资料 | 支持的结论 |
|---|---|---|
| S01 | [Flutter平台支持](https://docs.flutter.dev/reference/supported-platforms) [SDK发行](https://docs.flutter.dev/install/archive) | 四端范围 stable与架构边界 |
| S02 | [Flutter Dart路线图](https://flutter.dev/blog/flutter-darts-2026-roadmap) | 持续投入方向不等于固定保证 |
| S03 | [Tauri移动插件](https://v2.tauri.app/develop/plugins/develop-mobile/) | 移动原生适配语言 |
| S04 | [React Native独立平台](https://reactnative.dev/docs/out-of-tree-platforms) | Windows macOS维护结构 |
| S05 | [.NET MAUI平台](https://learn.microsoft.com/en-us/dotnet/maui/supported-platforms) | 四端与Mac Catalyst |
| S06 | [Compose稳定性](https://kotlinlang.org/docs/multiplatform/supported-platforms.html) | iOS Android桌面稳定支持 |
| S07 | [Material组件](https://docs.flutter.dev/ui/widgets/material) [material_ui](https://pub.dev/packages/material_ui) [官方独立组件迁移](https://docs.flutter.dev/release/breaking-changes/material-ui-and-cupertino-ui) [官方解耦说明](https://flutter.dev/blog/decoupling-material-cupertino) | 官方组件维护与类型本地化边界 |
| S08 | [Riverpod](https://pub.dev/packages/flutter_riverpod) [Riverpod3变化](https://riverpod.dev/docs/whats_new) | 作者版本 重试生命周期实验功能 |
| S09 | [go_router](https://pub.dev/packages/go_router) [路由变更](https://pub.dev/packages/go_router/changelog) [Flutter架构建议](https://docs.flutter.dev/app-architecture/recommendations) | 官方路由与职责分离 |
| S10 | [json_serializable](https://pub.dev/packages/json_serializable) [build_runner](https://pub.dev/packages/build_runner) | 官方JSON与构建工具 |
| S11 | [Drift平台](https://drift.simonbinder.eu/platforms/) [Drift](https://pub.dev/packages/drift) [sqlite3](https://pub.dev/packages/sqlite3) [sqflite_common_ffi](https://pub.dev/packages/sqflite_common_ffi) | 四端与捆绑方式 |
| S12 | [SQLite WAL](https://www.sqlite.org/wal.html) [PRAGMA](https://www.sqlite.org/pragma.html) [排序规则](https://www.sqlite.org/datatype3.html#collation) | 写入保护与NOCASE限制 |
| S13 | [path_provider](https://pub.dev/packages/path_provider) [path](https://pub.dev/packages/path) | 目录和路径基础包 |
| S14 | [image](https://pub.dev/packages/image) [image格式文档](https://github.com/brendan-duncan/image/blob/main/doc/formats.md) [copyCrop](https://pub.dev/documentation/image/latest/image/copyCrop.html) [copyResize](https://pub.dev/documentation/image/latest/image/copyResize.html) | 格式 编码与参数库行为 |
| S15 | [flutter_image_compress](https://pub.dev/packages/flutter_image_compress) | 非完整四端压缩能力 |
| S16 | [Flutter图像解码](https://api.flutter.dev/flutter/dart-ui/instantiateImageCodec.html) | 预览基础与帧解码 |
| S17 | [Dart isolate](https://docs.flutter.dev/perf/isolates) | UI计算隔离与传递成本 |
| S18 | [Dio](https://pub.dev/packages/dio) [http](https://pub.dev/packages/http) | 网络候选及维护来源 |
| S19 | [Android网络状态](https://developer.android.com/develop/connectivity/network-ops/reading-network-state) [Apple NWPath](https://developer.apple.com/documentation/network/nwpath) [Windows连接计费](https://learn.microsoft.com/en-us/windows/win32/api/netlistmgr/ne-netlistmgr-nlm_connection_cost) | 平台网络与计费提示 |
| S20 | [Apple后台策略](https://developer.apple.com/documentation/backgroundtasks/choosing-background-strategies-for-your-app) | 后台限制 |
| S21 | [file_selector](https://pub.dev/packages/file_selector) [image_picker](https://pub.dev/packages/image_picker) [url_launcher](https://pub.dev/packages/url_launcher) [desktop_drop](https://pub.dev/packages/desktop_drop) | 系统入口与插件边界 |
| S22 | [Android共享媒体](https://developer.android.com/training/data-storage/shared/media) [SAF](https://developer.android.com/training/data-storage/shared/documents-files) [Apple PhotoKit](https://developer.apple.com/documentation/photos) [Apple UIDocumentPicker](https://developer.apple.com/documentation/uikit/uidocumentpickerviewcontroller) | 原生导出与照片保存 |
| S23 | [Pigeon](https://pub.dev/packages/pigeon) [Platform Channels](https://docs.flutter.dev/platform-integration/platform-channels) | 官方四端类型桥接 |
| S24 | [unorm_dart](https://pub.dev/packages/unorm_dart) [characters](https://pub.dev/packages/characters) [Unicode17 CaseFolding](https://www.unicode.org/Public/17.0.0/ucd/CaseFolding.txt) [Dart小写规则](https://api.dart.dev/dart-core/String/toLowerCase.html) | NFC字符计数与默认完整判等规则 |
| S25 | [share_plus](https://pub.dev/packages/share_plus) | 分享能力与构建条件 |
| S26 | [flutter_secure_storage](https://pub.dev/packages/flutter_secure_storage) [Apple访问等级](https://pub.dev/documentation/flutter_secure_storage/latest/flutter_secure_storage/KeychainAccessibility.html) [Windows安全存储](https://pub.dev/documentation/flutter_secure_storage_windows/latest/) | 四端安全后端与配置 |
| S27 | [Android自动备份](https://developer.android.com/identity/data/autobackup) | 云备份与设备迁移限制 |
| S28 | [crypto](https://pub.dev/packages/crypto) [uuid](https://pub.dev/packages/uuid) | 摘要与身份生成 |
| S29 | [Flutter本地化](https://docs.flutter.dev/ui/internationalization) [intl](https://pub.dev/packages/intl) | ARB与本地化 |
| S30 | [archive](https://pub.dev/packages/archive) [上游编码器](https://github.com/brendan-duncan/archive/blob/main/lib/src/codecs/zip_encoder.dart) | ZIP与文件流接口 压缩分支内存边界 |
| S31 | [Flutter测试](https://docs.flutter.dev/testing/overview) [clock](https://pub.dev/packages/clock) [fake_async](https://pub.dev/packages/fake_async) | 测试层级和系统UI限制 |
| S32 | [Flutter AI开发](https://docs.flutter.dev/ai/get-started) [Dart AI仓库](https://github.com/dart-lang/ai) | 官方工具与skills |
| S33 | [Flutter VS Code](https://docs.flutter.dev/tools/vs-code) [Flutter lints](https://pub.dev/packages/flutter_lints) | 编辑器与质量检查 |
| S34 | [Windows配置](https://docs.flutter.dev/platform-integration/windows/setup) [iOS配置](https://docs.flutter.dev/platform-integration/ios/setup) [四端发布指南](https://docs.flutter.dev/deployment) [SPM](https://docs.flutter.dev/packages-and-plugins/swift-package-manager/for-app-developers) | 构建签名与分发 |
| S35 | [Firebase Flutter设置](https://firebase.google.com/docs/flutter/setup) | Windows生产用途限制 |
| S36 | [supabase_flutter](https://pub.dev/packages/supabase_flutter) [Supabase Flutter](https://supabase.com/docs/reference/dart/introduction) [Supabase RLS](https://supabase.com/docs/guides/database/postgres/row-level-security) [密码登录与邮件限制](https://supabase.com/docs/guides/auth/passwords) [数据库函数](https://supabase.com/docs/guides/database/functions) | 官方SDK 会话与云安全 |

## 19 文档交付核验

本文经框架与核心依赖研究、跨端和业务约束交叉分析、独立审查与主线程修订后作为技术选型基线。逐项发现与修订见配套审查报告。Markdown是统一内容源；Word核对正文、标题、表格、编号和链接，沿用既有内容结构验收方式，未进行逐页视觉验收。

旧应用与已有六份需求测试文件保持不变；没有将技术实现细节回写技术中立的需求正文。若实施门禁发现本选型不能满足正式需求，须更新技术决策与验证记录，不能让库默认行为悄悄改写需求。
