# M1 视觉优化原型

用户已选 M1 图库优先并接受优化方向。本目录是独立设计参考；真实 M1 图库已在 `app/` 接入，记录见 `../../docs/milestone-02-m1.md`。本原型还包含尚未实现的业务，不是生产应用。

在工作区根目录启动：

```powershell
node design/serve.mjs
```

- 总览：`http://127.0.0.1:8775/mobile-m1/index.html`
- 完整交互：`http://127.0.0.1:8775/mobile-m1/prototype.html`
- 两张已选：`prototype.html?selection=selected`
- 图片详情：`prototype.html?page=detail`
- 空图库：`prototype.html?scenario=empty`
- 照片权限受限：`prototype.html?scenario=permission`
- 处理保存失败：`prototype.html?page=editor&scenario=save-error`
- 链接/任务：`prototype.html?page=links`、`prototype.html?page=tasks`

服务仅监听本机回环地址，只提供读取页面。若 8775 已有本目录预览运行，直接使用，不重复启动。原 M1 对照链接使用独立资源包预览服务 8774；新版自身不依赖它。

所有数据、导入、处理、上传、凭据、任务、备份和复制均为模拟；刷新重置。不操作设备图库、真实文件、剪贴板或外部服务，不输入真实凭据。空图库参数只用于图库空态评审，不是应用完整首次启动场景。

`base.css` 和交互基础来自本工作区资源包的设计原型；`refined.css` 与组合页面表达本轮优化。它们不能作为 Flutter 生产业务模型。`../assets/sample-atlas.png` 是从资源包复制的 OpenAI ImageGen 合成设计夹具（2026-10-03）；没有复制参考产品图片。显示的文件名、格式、大小均不是该 PNG 的真实元信息，不能用于格式验证或预置生产数据。

官方参考、具体取舍与实际验证见 `../../docs/mobile-m1-design.md`。截图在 `../validation/`，记录的是浏览器原型，不能替代 Android/iOS 实机验收。
