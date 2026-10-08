# ImgBB 接入说明

核查日期：2026-10-04｜首版既定服务｜新项目尚未接入

## 官方协议

使用 multipart POST `https://api.imgbb.com/1/upload`，必需字段 key、image；可选 name。API支持文件、base64、图片URL，文档限制为32 MB。expiration可选，范围60–15552000秒；本地文件官方推荐POST。[官方 API](https://api.imgbb.com/)

首版默认上传用户明确选定的本机版本，不无意设定到期删除，不自动增加URL转存能力。32 MB的精确字节阈值和格式能力在实现核查时固定，不从文字单位猜测为无限制。key只存受保护秘密服务。

## 响应与管理

先核对JSON成功/status及有效data；普通链接取image.url或适当的直接url，url_viewer是网页查看地址。响应还可能有展示/缩略图及delete_url。缺字段、错误JSON、HTML错误页和成功标志不一致不能静默标成功。[官方响应示例](https://api.imgbb.com/)

delete_url视为敏感管理链接，只在受保护操作中使用。官方上传文档未提供通用删除API、资产列表、配额查询或断点续传保证，不把返回管理URL解释为统一程序化删除能力。

## 验证

覆盖缺失/失效授权、超限、有效/缺字段JSON、429/5xx、取消、请求后无确认、同名账号独立身份及key/delete_url脱敏。大小边界、格式支持和真实服务响应单列契约/集成验证；本次未执行真实上传、密钥验证或删除。
