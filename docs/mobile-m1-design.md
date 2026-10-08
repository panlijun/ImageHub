# M1 手机视觉优化与验证

2026-10-04。用户已选 M1 图库优先为基准，并要求改善视觉、更多参考成熟方案。本轮交付独立可交互优化稿 01，没有修改只读资源包或 Flutter 生产源码。M1 方向已确定，具体视觉仍可继续评审。

## 官方资料与取舍

| 成熟产品 | 查阅依据 | 适用于 ImageHost 的部分 | 本轮落实 |
| --- | --- | --- | --- |
| Apple Photos | [官方图库说明](https://support.apple.com/en-euro/guide/iphone/iph7d24753a5/ios)：图库、缩略图大小与网格比例可调整 | 图片优先，按需要调整密度 | 两列舒适视图保留名称和格式；三列紧凑视图突出图片 |
| Google Photos | [官方 2020 设计案例](https://blog.google/products-and-platforms/products/photos/redesigned-google-photos/)、[2022 图库整理案例](https://blog.google/products-and-platforms/products/photos/get-organized-google-photos-spring-cleaning/)；是历史设计案例，不声明其为当前界面 | 较大图片、醒目检索、少量长期目的地 | 图库、链接、任务三项底栏；导入放在图库标题旁；检索和筛选固定成组 |
| Ente Photos | [2026 官方更新](https://ente.com/news/)、[设计系统实践](https://ente.com/blog/ente-design-system/)；浏览了官方发布的新界面图 | 统一文字、图标、按钮和组件；控制圆角与装饰 | 中性色背景、单一蓝色主操作；11–14px 卡片圆角，文字层级和按钮状态一致 |
| Lightroom Mobile | [官方工作区说明](https://helpx.adobe.com/sg/lightroom/mobile/get-started/workspace-overview.html)、[网格排序与分组](https://helpx.adobe.com/ca/lightroom/mobile/review-rate-and-manage-versions/sort-and-segment-photos-in-the-grid-view.html) | 浏览、图片详情与处理参数按情境表达 | 多选后替换底栏；详情显示大图、文件信息和本机保管状态；进入编辑后才显示参数 |

这些是结合官方资料做出的本项目设计判断，不声称其他产品采用完全相同的布局。未复制产品素材、商标或源码；未新增它们的云账户、云同步、智能分类或相册自动扫描业务。配套 Flutter 技术选型保持原约定。

## 本轮设计

1. 图库采用 ImageHost 标识、小型本机状态、清楚的标题与导入入口，避免每个操作都占一个大卡片。
2. 图片用两列较大预览，缩略图下展示名称、格式和大小；长名称在网格省略，详情完整换行。收藏和成功链接以轻量标记呈现；没有把“待确认”当成成功链接。
3. 同一搜索框与三项筛选服务图库；可切换舒适/紧凑显示。导入日期分组使用设计夹具日期，正式应用应使用真实导入时间。
4. 多选显示数量、取消和全选，底栏切换压缩/拼接/上传/更多。零张禁用主要动作，一张禁用拼接；选择后的同页更新保留当前滚动位置，不回到顶端。
5. 详情首先展示大图，其后文件信息、本机副本状态、编辑与上传，远程结果按独立目标保留。失败状态不会遮盖已成功链接。
6. 空图库与搜索无匹配分别表达；照片授权受限、保存失败与可重试临时结果都有独立演示入口。标题、按钮、边框和图标统一；主要图库触控区域至少 44×44 CSS 像素。

## 修改范围与启动

新增 `design/serve.mjs`、`design/mobile-m1/{index.html,prototype.html,base.css,refined.css,mobile.js,README.md}`、`design/assets/sample-atlas.png`、`design/validation/` 截图与本记录。更新根目录 AGENTS/README、应用 README、架构及里程碑说明中的 M1 决定。

从工作区根目录执行 `node design/serve.mjs`，打开 `http://127.0.0.1:8775/mobile-m1/index.html`。总览包含图库、多选、详情三屏，可以独立打开体验，底部有研究来源和额外场景入口。原包对照在独立 8774 服务；新版 8775 服务不修改包文件。

## 实际验证

浏览器操作使用 computer-use / cua_repl，在 Codex 内置浏览器进行实际点击与 DOM/截图检查。

| 检查 | 实际结果 |
| --- | --- |
| 320×720、390×844、430×932 图库布局 | 两列正常，body/图库内部宽度等于视口，无横向溢出；320 下密度按钮右边界 304、与内容边缘对齐 |
| 显示密度 | 390 下点击紧凑后实际三列（约 113px/列），切回舒适为两列 |
| 多选启用条件 | 零张拼接禁用，一张禁用，两张启用；选择数量同步，取消恢复主导航 |
| 滚动后选择 | 滚至约 757px 选择咖啡，选择后约 710.5px（浏览器点击定位调整），未回到顶部；同页重绘保留位置 |
| 收藏、成功链接筛选 | 各有三张设计样本；清除后恢复九张 |
| 搜索空结果 | 输入“不存在”，显示“没有匹配图片”，清除筛选恢复九张；空图库场景为“把第一张图片放进来” |
| 导入弹层与键盘 | 显示照片/文件两个来源；背景 inert；Escape 关闭并将焦点还给导入按钮 |
| 长文件名详情 | 320 下完整换行，详情与远程结果无横向溢出 |
| 链接/任务页面 | 430 下内容无横向溢出，主导航保留；失败与待确认可查看 |
| 处理保存失败/重试 | 生成两项结果；首次模拟保存失败仍保留临时结果与重试入口；再次保存显示已保存，返回图库计数为 11 |
| 三屏总览 | 三个 iframe 均加载；在多选 iframe 点击取消，标题切回“我的图库” |
| 控制台 | 单独交互原型受测期间 error 日志为空；总览加载/重载各捕获一条 MutationObserver.observe 的 Node 参数错误。总览没有脚本，项目 design/ 中没有 MutationObserver 调用，来源尚未确认，可能来自浏览器注入；可见三屏和已测 iframe 交互正常，不据此声明控制台全部无错误 |
| JavaScript 语法 | `node --check design/mobile-m1/mobile.js`、`node --check design/serve.mjs` 均 exit 0 |
| 资源包完整性 | `node imagehost-new-project-kit/verify-kit.mjs` 通过：31 文件、56 本地引用；该检查不是应用测试 |

截图：`design/validation/m1-gallery.jpg`、`m1-selection.jpg`、`m1-detail.jpg`、`m1-overview.jpg`。临时手机视口覆盖已重置；预览服务保持运行供用户评审。

上述是设计原型检查，不记作需求测试设计中的生产 UT/IT/PT/AT 通过。没有四端构建、设备键盘/安全区/照片权限验证、完整无障碍或性能验收。此次未改生产源码，不重复执行此前 Flutter 测试；既有里程碑结果仍以 milestone-01.md 为准。Android 仍缺 SDK/设备，Apple 两端仍需 Mac/Xcode。

## 下一步

用户接受方向后，已按 M1 建立 Flutter 手机组件与导航，接入真实图库、独立副本、名称搜索、收藏和多选核对，详见 [M1 实现验收](milestone-02-m1.md)。上表仍记录此前 HTML 原型验证；不能替代生产测试。链接和任务待真实图床与持久队列实现后接入，不能把 HTML 的内存样本或模拟成功结果移植为生产业务。
