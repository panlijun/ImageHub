# Catbox / ImgBB 官方公开契约核查

核查日期：2026-10-07（Asia/Shanghai）。范围为官方公开文档、页面 HTML 及其直接引用的公开 JavaScript，只执行 GET 读取；没有执行上传、删除、密钥验证或其他业务请求，没有运行服务脚本。资源包与生产代码保持不变。

## 结论

本次公开资料不足以把两家服务的生产 `ProviderUploadLimits.unknown()` 改为已核验能力。ImgBB 已找到明确的 **网页上传器** 32,000,000 字节及格式列表；尚未找到 `/1/upload` 的服务器精确边界、格式判定和 GIF 独立规则的契约。Catbox 的 API 精确字节上限仍缺证，且官方网页客户端限制与主页文字不同。Catbox `deletefiles` 入参已公开，可靠成功/失败确认契约仍未公开于本次读取材料。

“本次未找到”只描述下列材料的核查结果，不表示服务永远没有其他规则。真实服务契约/联调仍是独立未完成项，不能改记为缺实机。

## 官方来源及证据等级

| 来源 | 本次读取证据 | 能证明的范围 |
| --- | --- | --- |
| [Catbox 首页](https://catbox.moe/) | 展示上传上限 200 MB；直接引用 `resources/uploadform.js`、`resources/dropzone.js` | 服务面向用户的文字限制，未定义精确字节及边界比较 |
| [Catbox FAQ](https://catbox.moe/faq.php) | 禁止扩展名列表为 `.exe`、`.scr`、`.cpl`、`.doc*`、`.jar`；GIF 超过 20 MB 不允许 | 黑名单及 GIF 独立文字限制；未定义字节换算、MIME/实际内容判定 |
| [Catbox API 文档](https://catbox.moe/tools.php) | `fileupload` 使用 `fileToUpload`，匿名省略 `userhash`；`deletefiles` 使用 `userhash` 与空格分隔服务文件名；示例有 PNG/GIF | 请求字段与部分示例；未给精确上传字节边界或删除结果格式 |
| [Catbox 上传器脚本](https://catbox.moe/resources/uploadform.js) | `maxFilesize: 1000`；页面自定义 `accept` 只拒绝部分类型；没有 GIF 大小分支 | 当日网页客户端配置，不能代替服务器 API 限制 |
| [Catbox Dropzone 脚本](https://catbox.moe/resources/dropzone.js) | 校验表达式为 `file.size > this.options.maxFilesize * 1024 * 1024` | 网页客户端的比较语义 |
| [Catbox 无 JS 页](https://nofun.catbox.moe/) | 同样展示 200 MB；文件输入无格式白名单；本次 HTML 未见精确字节的 `MAX_FILE_SIZE` | 没有补足 API 精确边界 |
| [ImgBB API 文档](https://api.imgbb.com/) | `image` 可为二进制文件、base64 或 URL，文字限制 32 MB；成功示例为 GIF | API 的文字上限、输入方式及 GIF 示例；未给完整格式白名单及精确边界 |
| [ImgBB 首页](https://imgbb.com/) 与 [API 文档页 HTML](https://api.imgbb.com/) | 两页内联共享 `CHV.obj.config.image.max_filesize` 均为 **32000000**；`upload.image_types` 含 `png`、`jpe`、`jpeg`、`jpg`、`webp`、`gif`、`bmp` | 两页网页上传器的明确整数配置与扩展名列表 |
| [ImgBB 页面直接引用的脚本](https://simgbb.com/8179/ibb.js) | 网页队列先按 `n.size > CHV.obj.config.image.max_filesize` 拒绝，再查扩展名列表；实际网页上传走 `PF.obj.config.json_api`（首页为 `https://imgbb.com/json`） | 是网页 `/json` 上传器行为；不是 `/1/upload` 的服务器执行代码 |

JavaScript 由只读 HTTP 客户端读取，没有执行；不保存完整 HTML、运行时令牌或源码副本。浏览工具无法解析上述 JavaScript 内容类型，因此脚本证据来自本次直接 GET，而不是搜索摘要。FAQ 使用当日直接读取内容；搜索引擎旧快照不作为当前规则证据。

## 大小与格式逐项判断

| 项目 | Catbox | ImgBB |
| --- | --- | --- |
| 服务器 API 精确字节上限 | 未确定。200 MB 未定义为 200,000,000 或 209,715,200 字节 | 未确定。API 的 32 MB 文本与网页 32,000,000 字节配置不能直接建立服务器契约等价 |
| 网页客户端精确上限 | 当日脚本设 1000 × 1024 × 1024 = 1,048,576,000 字节，严格大于时拒绝；与主页 200 MB 不一致 | 当日配置 32,000,000 字节，严格大于时拒绝；等于该值通过此客户端大小检查，不保证服务器接受 |
| PNG / JPEG / WebP / GIF / BMP | 五种均未命中 FAQ 扩展名黑名单，但未找到 API 对五种实际内容的完整接受契约；示例只构成局部证据 | 五种均列入网页扩展名列表；API GIF 示例是局部证据，未找到 API 对五种实际内容的完整接受契约 |
| GIF 独立上限 | FAQ 明确单列 20 MB，精确字节仍未确定；不应使用通用 200 MB 放行 GIF | 本次网页大小检查未见 GIF 独立分支；API 文档未给独立规则。不能据此承诺 GIF 与静态格式同上限 |
| 动画/格式保持 | 本次没有验证实际服务解码、动画保留或字节保持 | 本次没有验证实际服务解码、动画保留或输出格式转换；网页说明动画 GIF 不缩放不等于 API 保证 |

不能用客户端较大的阈值覆盖服务文字限制，也不能把“未在黑名单”升级为实际内容白名单。32,000,000 是公开脚本配置的实际整数，不能改写成 32 MiB；Catbox 两项 MB 不自行换算。

## Catbox 删除确认

[官方 API 文档](https://catbox.moe/tools.php)公开 `deletefiles`、`userhash`、`files` 的请求形式，但本次材料没有定义：成功正文、逐文件成功/失败身份、错误正文集合、HTTP 状态与删除结果的对应关系、幂等性或部分删除语义。

因此仍应保留既有规则：仅按当前账号与稳定目标身份授权；严格单文件标识；一旦派发，HTTP 200、空正文或之后直链 410 都不能单独记为删除成功；响应未确认保持 unknown，不自动重试或重开派发。页面脚本的普通上传 `success` 回调也不能用于推导删除契约。没有向删除端点发送请求。

## 现有实现与后续可执行范围

- 核查时`app/lib/features/upload/domain/provider_models.dart`只有全局`maximumBytes`与`formats`。主线程随后确定方案并补`formatMaximumBytes`与两适配器的取小值校验，软件证据见`milestone-26-source-cancellation.md`；这不为Catbox文字MB补造字节值，生产能力仍未开启。
- `app/lib/features/upload/data/provider_adapters.dart` 的两家默认能力均为 unknown；派发前拒绝缺证能力。现有默认保持，测试注入能力继续仅作为测试夹具。
- 当前可安全完成的是证据登记、继续本机软件验证及已有适配器的合成响应/取消测试；本次没有改业务规则，没有运行这些测试。
- 要开启生产上传仍需 API 侧的精确字节阈值、五种实际格式与 GIF 规则证据。可由服务方公开或明确确认的 API 规范补齐；如改做真实边界/格式联调，须由用户另行授权请求，并将实测事实与服务长期契约区分。
- 若未来明确选择“本应用保守上限”政策，必须把该政策与“服务上限已核验”分开表达，经主线程确认范围后设计；本次没有用这一政策绕过既有 unknown 保护。

本文件仅记录官方公开契约证据，不计 CT/IT/PT/AT 通过，也不证明四端或真实图床上传/删除可用。
