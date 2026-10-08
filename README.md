# ImageHost

ImageHost 是用 Flutter 从零实现的本地个人图片工具。应用源码在 `app/`，实施资料在 `docs/`；`imagehost-new-project-kit/` 是只读输入，原件保持不变。产品没有应用云账号或图库云同步。

当前 Windows 软件开发及本轮适用主机验证已完成，包括本地图库和永久副本、图片处理与结果保存、账号安全存储、持久上传队列、按网络类型控制派发、链接管理与主动检测、独立远端删除审计，以及备份恢复、诊断和设置。M1 是已选定的手机方向；其他平台源码接线不等于已构建或可运行。移动原生导出仍是软件缺口。

图床账号仅支持 Catbox userhash 和 ImgBB APIKey。Catbox 匿名上传已从产品中移除；本项目已有匿名身份只供读取普通历史和备份，不能创建、选择、入队或派发。真实图床上传、删除、探测没有获得联调授权；服务的精确大小与格式限制仍未知，因此生产能力守卫继续阻止未确认能力的派发。受控测试不代表真实服务可用。

Windows 运行方式、功能入口和开发命令见[应用 README](app/README.md)。当前 SDK、构建条件及本机证据见[环境记录](docs/environment.md)，本轮范围与验收边界见[软件完成范围](docs/software-completion-scope.md)及[Windows 完成记录](docs/milestone-27-windows-completion.md)。

桌面采用 A，手机按用户选择采用 M1；M1 的设计与实现记录见[M1 里程碑](docs/milestone-02-m1.md)和[M1 设计记录](docs/mobile-m1-design.md)。旧里程碑保留各自当时的历史结论，最新 Windows 软件状态以本轮记录为准。

历史实现记录： [图库](docs/milestone-03-gallery-processing.md)、[处理输出](docs/milestone-04-processing-outputs.md)、[账号安全](docs/milestone-05-accounts.md)、[队列与暂停](docs/milestone-07-durable-upload-queue.md)、[备份恢复](docs/milestone-10-merge-restore.md)、[替换恢复](docs/milestone-12-replacement-restore.md)、[图库远程筛选](docs/milestone-14-gallery-remote.md)、[历史清理](docs/milestone-15-upload-history.md)、[链接检测](docs/milestone-16-link-availability.md)、[设置与调度](docs/milestone-17-settings-scheduling.md)、[诊断](docs/milestone-18-diagnostics.md)、[缓存与空间](docs/milestone-19-storage.md)、[单项暂停](docs/milestone-20-item-pause.md)、[网络类型](docs/milestone-21-network-types.md)、[上传前处理](docs/milestone-22-upload-processing.md)、[备份设置](docs/milestone-23-backup-settings.md)和[远端删除审计](docs/milestone-24-remote-deletion.md)。

工作区根目录运行 `node design/serve.mjs` 可预览 `http://127.0.0.1:8775/mobile-m1/index.html`。原型中的图片和操作仅用于布局演示，不是生产数据或持久化实现。
