# Android 资源取得与保存边界

本记录说明 2026-10-08 Android 实现的局部技术决定。资源包原件未修改；应用仍采用既定 Flutter/Dart、共同领域和 Drift/SQLite，没有增加业务框架或图床。

## 需求与技术文档的具体差异

技术选型 1.0 第 8.1 节选择 `file_selector` / `image_picker`，第 8.2 节要求 Android 使用 SAF 与 MediaStore，第 8.3 节选择官方稳定 Pigeon 桥。实际解析的 `file_selector_android 0.5.2+11` 预先要求已知 SIZE、分配整块字节数组再复制；`image_picker_android 0.8.13+25` 在向 Dart 交付前预先复制整批 URI，并将部分逐项取得错误合并为空路径。

这影响 IMP-001、IMP-005、IMP-007、IMP-008 和 PLT-002：共同导入协调者无法在真实来源取得期间逐项反馈、观察停止和等待实际来源收尾。Android 因此使用第 8.3 节已确定的 Pigeon 通道；其他平台保留原插件。没有将 HTML 的内存资源或模拟成功复制到生产代码。

`app/pigeons/android_files.dart` 是通道的唯一输入；Dart/Kotlin 两端由真实 `pigeon 29.0.7` 生成，再按 Dart formatter 格式化。不得手写生成 API。

## 资源取得

- 文件、照片和 ZIP 通过系统 `ACTION_OPEN_DOCUMENT` 与相应 MIME 范围取得。照片是图片范围的系统文档选择器，不承诺所有厂商照片应用的专有能力。
- Dart 只收到 UUID 句柄、显示名和来源类别。URI 与实际授权只保存在应用私有 `noBackupFilesDir` 的严格格式 AtomicFile 登记，不进入业务 SQL、备份或普通诊断。
- 每项最多交付 64 KiB；未知长度可流式读取。明确 PARTIAL 标记才报告待取得，不用 provider 名称或一般读取失败猜测云状态。授权、缺失和未知失败分别反馈。
- 打开前持久标记 consumed，避免重开将已开始读取的来源误当作未执行选择。未开始且授权可持久保留的选择由启动恢复入口提示；备份来源不自动恢复为业务意图。
- 读与关闭在同一来源 lane 中排队。取消停止交付，仍等待真实 read、close 和授权退休。未打开的选中项也必须 release。无法确认关闭时保留登记，不以第二次可能为 no-op 的 close 证明首次已结束。
- 同进程 Activity 替换不能接管旧实例仍在使用的私有登记；未知、畸形或未来格式保留现场并拒绝取得。

## 文件和照片导出

共同 `ExportGateway` 分别暴露目录导出、文件导出和照片保存能力。Windows/macOS 原有目录流程保留；Android 接真实系统文件保存；iOS 未接入的导出仍禁用。

单文件使用 SAF `ACTION_CREATE_DOCUMENT`，多文件使用一次 `ACTION_OPEN_DOCUMENT_TREE` 并冻结本次操作 UUID。目录导出先枚举已有身份与名称，只写本次创建的新文档；同名产生新名称。照片保存仅支持当前实现明确验证的 JPEG、PNG、WebP，插入 MediaStore 时先设 pending，完成真实复制、关闭、SHA/长度读回后才公开。

MediaStore 新增 pending 记录不代表实体文件已经创建。首次写入以不截断的 append 模式创建字节，仍先核对本应用所有者及 pending 状态，再在实际写入前确认空流。pending 的 SIZE 是可能滞后的媒体索引，实际长度和 SHA 以有界读回为准；不把索引的初始零值当成已写字节丢失，也不据此猜删。发布后重新读取名称、MIME 和可用长度，再返回系统实际名称；不以发布前的名称冒充系统处理同名冲突后的名称。该差异来自模拟器中 `copy/STORAGE`、`cleanupPending` 及同名发布的实际故障；修复仍要求真实关闭、完整读回和发布观察。[Android pending 媒体流程](https://developer.android.com/training/data-storage/shared/media#toggle-pending-status)

源文件只允许系统提供的应用 files/cache 根目录下已关闭的普通文件。允许根目录自身的系统别名，拒绝根下链接和路径穿越；使用 O_NOFOLLOW 并核对 lstat/fstat 的设备及 inode。原生入口只返回固定分类，不将 provider/SDK 异常原文、堆栈或来源路径当作反馈。

Android `FileInputStream(FileDescriptor)` 不拥有传入的描述符，因此导出改为显式持有 Os.open/Os.read/Os.close 的源流。验证包括重复的错误 SHA 请求和实际进程描述符计数，不能仅据非成功回执声称没有插入照片。[AOSP FileInputStream 实现](https://android.googlesource.com/platform/prebuilts/fullsdk/sources/+/refs/heads/androidx-constraintlayout-release/android-35/java/io/FileInputStream.java)

取消不提前完成原生 future，不提前释放共同输入租约或删私有源。成功回执必须包含系统确认的 content URI 与实际文件名；仅为当次系统保存确认，不代表另一个应用已接收或云端已同步。失败清理只处理本次新建且身份、长度、摘要未变的目标；不确定时保留现场。若 Activity/进程在未消费新建文档时被强制终止，空文件可能保留，目前不跨重开猜测清理该外部目标；这项边界需后续设备 PT 补证。

## 应用私有文件发布

模拟器上的实际检查发现：原先 `Files.createLink` 对新目标失败，改用 Os.link 取得明确 errno 13；已有目标返回冲突且字节未改变。不修改 Android 权限或安全配置来绕过该失败。

私有发布改用 NDK 编译的 `renameat2(..., RENAME_NOREPLACE)` 系统调用：同卷、原子、目标已存在就拒绝，没有覆盖式 rename 或复制后备。路径以普通 UTF-8 字节跨 JNI，避免 modified UTF-8 对 emoji 路径的差异。Bionic 公共 wrapper 从 API30 才可用，编译时使用 NDK 各 ABI 的 syscall 定义保留 API29 配置；不支持的内核或文件系统拒绝发布。[Android Bionic 接口及不覆盖标记](https://android.googlesource.com/platform/bionic/+/c6c17ac1e8c7072d6744a6476f4cedb95be8d2ea%5E2..c6c17ac1e8c7072d6744a6476f4cedb95be8d2ea/)

目前原生后端证据来自 API36 x86_64 模拟器；API29 最低版本、ARM64 实机、断电、硬件性能均不据此计通过。

## 备份、恢复与诊断

处理工作台、备份和诊断复用同一文件导出入口。备份先在私有工作区得到已关闭且严格验证的 ZIP，随后交给 SAF；仅系统保存确认后才显示“备份已保存”。选择 ZIP 采用同一有界资源流复制到私有源，再交给现有严格预检、合并或替换协调者。当前资料库不因选择器取消或取得失败被重置。

私有暂存只清已登记、实际关闭、长度和摘要未变的普通文件；未知子项、链接、变化或关闭不确定保留现场。取消、页面销毁与退出等待真实协调者及系统 transfer 收尾；用户保存成功与私有清理失败分别反馈。

替换恢复的证明临时目录先解析运行时提供的系统临时根别名，再添加新私有命名空间；对新目录和所有子项继续严格禁止链接，避免将 Android 系统别名误报为用户植入链接。

本记录是实现边界说明；实际测试、构建与模拟器证据另见[Android完成记录](milestone-28-android-completion.md)。受控通道测试不代替真实系统后端，更不代替物理设备或真实图床联调。
