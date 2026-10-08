# ImageHost 新项目实施资源包

整理日期：2026-10-04｜需求 1.1｜技术选型 1.0｜手机原型 2.1

**把本文件夹整体复制到新项目工作区，即可作为重新实现的输入。** 这是独立交接包，不是旧项目改造包，也不是已实现的新应用；无需取得旧项目源码、数据库或旧应用数据。

## 从这里开始

1. 阅读 [实施约定](AGENTS.md) 与 [新项目实施路线](IMPLEMENTATION.md)。
2. 以 [需求分析](documents/requirements-analysis.md) 为业务基线，并对照 [需求二次检验](documents/requirements-review.md)、[单元测试设计](documents/unit-test-design.md)。
3. 按 [技术栈选型](documents/technology-selection.md) 实施 Flutter 四端项目；[选型审查](documents/technology-selection-review.md) 保留依赖例外、平台限制和待验证事项。
4. 打开 [设计入口](design/index.html)：桌面 A 已选定；手机保留 M1、M2 候选，默认推荐 M1，最终选择仍由用户决定。
5. 使用 [图床接入约定](providers/README.md) 及 Catbox、ImgBB 两份专用说明，不读取旧图床实现代码。

documents 内五类正式文档均提供 Markdown 和 Word，共十份；内容原样保留，Markdown 为统一内容源。正式文档附录中的 src/、src-tauri/、docs/ 和 .codex/ 路径是旧项目需求来源记录，不是本包缺失文件或新项目目录要求；这些旧文件刻意不随包交付。文档间相对链接保持有效。

## 包内目录

| 位置 | 用途 |
| --- | --- |
| documents/ | 完整需求、二次检验、测试设计、选型及选型审查，MD/Word |
| design/desktop/ | 仅已选桌面 A 的可操作设计样本、样式与规格 |
| design/mobile/ | 手机 M1/M2 对比与当前交互原型、规格 |
| design/assets/ | 原型必需的合成九宫格图片及用途说明 |
| design/implementation-notes.md | 设计取舍、权威顺序及尚未实现/验收的事项 |
| providers/ | 两个首版图床的协议与接入边界，无真实凭据 |
| AGENTS.md、IMPLEMENTATION.md | 面向新项目的执行约束与实现顺序 |
| MANIFEST.json | 文件清单、版本和 SHA-256，用于搬运完整性核对 |
| serve.mjs | 无第三方依赖的本地设计预览工具，仅监听回环地址 |
| verify-kit.mjs | 搬运后核对文件摘要和本地资源链接，不执行应用测试 |

没有放入旧应用源码、旧锁文件、旧数据库、旧技能默认技术建议、未选桌面 B/C、已否定手机稿、Cloudinary 候选说明、历史截图/检查日志、续跑记录、Figma 构建准备脚本或旧项目构建产物。

## 预览设计

已有 Node.js 时，在本文件夹执行：

```text
node serve.mjs
```

打开 http://127.0.0.1:8770/design/index.html 。`serve.mjs` 不依赖 npm 安装，也不属于 Flutter 应用技术栈。预览不写应用数据、不接入真实图床；使用 Ctrl+C 停止。其他程序占用端口时，可通过环境变量 IMAGEHOST_UI_PORT 指定空闲端口。

手机 prototype.html 可以直接作为本地文件打开；文档及多页面导航通过预览工具查看更方便。桌面样本仅作为宽屏桌面参考，窄屏请使用手机原型，不能沿用旧手机布局。

搬运后可执行 `node verify-kit.mjs` 核对清单摘要、本地引用和原型语法。通过仅说明交接包完整，不能说明新应用功能或正式测试已通过。后续主动修改包内文件时应同步清单摘要，避免把预期修订误认为搬运损坏。

## 当前状态和边界

产品定位为个人工具；首版 Windows、macOS、Android、iOS 都需要本地独立使用、永久副本和完整数据闭环。无团队空间、多人权限、旧数据迁移或首版应用云账户；V2 云同步仅是后续可选方向。

本包未初始化 Flutter 项目、编写生产代码或执行正式 UT/AT。Word 仅经过内容与结构核验，未逐页视觉验收。HTML 是会话内模拟；它的固定样本、状态变化及算法不构成生产实现。

Figma 尚未同步最新设计，最近访问被 Starter MCP 额度限制；它是辅助参考，不能覆盖当前规格与本地原型。Figma 准备脚本和平台调用日志不是新应用实现所需资源，未放入包。桌面样本的历史交互简化也不能覆盖需求 1.1 或当前手机共同规则。

## 可用于新聊天的启动指令

> 请在这个新工作区全新实现 ImageHost。先读本资源包的 README.md、AGENTS.md、IMPLEMENTATION.md，以及 documents 中的需求 1.1、技术选型 1.0 和测试设计。使用 Flutter 四端方向，从新数据开始，不依赖旧项目源码、格式或数据。桌面按 A；手机 M1/M2 尚待最终选择，先实现共用业务和桌面，手机路由按候选隔离。HTML 只作设计参考，不作为生产代码模板。按实施路线逐步实现、验证并记录每条 V1 需求；不要以原型演示或文档检查宣称软件完成。安装工具、签名发布及外部资源开通先遵守用户许可约定。
