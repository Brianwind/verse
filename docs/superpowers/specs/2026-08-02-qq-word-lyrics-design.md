# QQ Music Word-Timed Lyrics Design

## Goal

为 Verse 增加 QQ 音乐 QRC 逐字歌词来源，并与现有网易云 YRC、AMLLDB TTML 并发查询。最终选择顺序固定为：

1. 网易云真实 YRC
2. AMLLDB TTML
3. QQ 音乐真实 QRC
4. 网易云普通 LRC

只有来源本身提供真实逐字时间时，才参与前三项竞争。Verse 不根据普通 LRC 伪造逐字时间。

本功能作为独立验收点完成。用户确认后，才开始播放器背景功能。

## Scope

本阶段包含：

- 匿名调用 QQ 音乐搜索和歌词接口。
- 从当前网易云 `Song2` 元数据严格匹配 QQ 歌曲。
- 解密 QQ QDES + zlib 歌词数据。
- 解析 QRC 主歌词、翻译和罗马音。
- 并发启动三个来源，并按固定优先级选择。
- 请求超时、缓存、并发去重和快速切歌保护。
- 终端输出最终歌词来源，供人工验收。

本阶段不包含：

- QQ 音乐登录、播放、搜索页或账号功能。
- 用户可配置的歌词来源优先级。
- 手动选择 QQ 候选歌曲。
- 普通 LRC 的推测性逐字时间。
- 播放页可见的歌词来源标签。
- 播放器背景改造。

## Architecture

### Source Orchestration

`LyricResolver` 接收完整歌曲上下文，而不再只接收网易云歌曲 ID。上下文至少包含：

- 网易云歌曲 ID
- 歌名
- 歌手列表
- 专辑名
- 时长

解析开始时立即创建三个 Future：

- `NeteaseLyricsLoader`
- `AmllLyricsLoader`
- `QqLyricsLoader`

Future 创建后按优先级等待结果：

1. 网易云结果有真实 YRC 时立即返回。
2. 否则检查已经并发运行的 AMLLDB 结果；有逐字 TTML 时返回。
3. 否则检查已经并发运行的 QQ 结果；有逐字 QRC 时返回。
4. 三者均无逐字结果时，返回第一步保存的网易云普通 LRC。

低优先级请求不会阻止高优先级结果立即生效。每条来源链都有独立超时，因此总等待时间接近最慢的必要高优先级来源，而不是三条超时之和。

每个来源返回统一的 `LyricCandidate`：

- `LyricSource source`
- `LyricDocument document`
- `bool isWordTimed`

解析器只负责产生候选，`LyricResolver` 负责优先级。

### QQ Music Client

新增独立 `QqLyricClient`，使用自己的 `Dio`，不复用网易云 Cookie 或拦截器。生产请求保持匿名：

- Endpoint: `https://u.y.qq.com/cgi-bin/musicu.fcg`
- Search method: `DoSearchForQQMusicLite`
- Lyric method: `GetPlayLyricInfo`
- `uid: "0"`
- Cookie: `tmeLoginType=-1;`
- User-Agent: `okhttp/3.14.9`

QQ 链路分为：

1. 用歌名、歌手、专辑组成查询词，搜索最多 10 个歌曲候选。
2. 对候选进行本地严格匹配和排序。
3. 只为最佳可靠候选请求一次歌词。
4. 解密 `lyric`、`trans`、`roma` 字段。
5. 解析主 QRC，并按行时间对齐翻译和罗马音。

QQ 搜索与歌词请求共享一个约 5 秒的来源总预算。超时后该来源返回不可用，不影响其他来源。

### Strict QQ Matching

匹配策略优先避免错误歌词，允许漏掉可用候选。

歌名规范化包括：

- Unicode 大小写、空白和常规标点归一化。
- 移除不代表版本的括号翻译，例如 `アイドル (偶像)` 可匹配 `アイドル`。
- 保留 `Live`、`Remix`、`Instrumental`、`伴奏`、`Cover`、`Acoustic`、`Remaster` 等版本标记，使不同版本不能误配。

候选必须同时满足：

- 规范化歌名可靠匹配。
- 歌手或专辑至少一项可靠匹配。
- 双方均有有效时长时，时长差不超过 3 秒。

多个候选满足门槛时，按歌名、歌手、专辑和时长的综合分数选择最高项。只获取最高项歌词，不探测多个 QQ 歌词，控制网络和误匹配风险。

### QDES Decryption

QQ 的在线 QRC 使用 QDES 变体后再做 zlib 压缩。实测标准 TripleDES 无法正确解密，因此不能直接使用 PointyCastle 的标准 DESede。

Verse 将增加纯 Dart QDES 实现：

- 算法依据采用 MIT 许可的 `naiyQAQ/pyqdes`，保留源码 attribution 和 MIT notice。
- 不复制 Folia 或其他 AGPL/GPL 项目的实现。
- 固定 QQ QRC key 只封装在解密模块中。
- 解密输入必须是合法偶数长度十六进制且长度为 8 字节分组。
- 解密后使用 `dart:io` 的 zlib 解压，再以 UTF-8 解码。
- 主歌词、翻译和罗马音在同一个后台 isolate 中处理，避免阻塞 Flutter UI 线程。

解密或解压失败时返回来源不可用，不向 UI 暴露部分内容。

### QRC Parser

新增 `QqQrcParser`，转换为现有 `LyricDocument`、`LyricLine` 和 `LyricWord`。

支持两种线上常见布局：

```text
[1000,800](1000,250)你(1250,250)好
[1000,800]你(1000,250)好(1250,250)
```

解析规则：

- 行标签为 `[lineStartMs,lineDurationMs]`。
- 字词标签为 `(wordStartMs,wordDurationMs)`，可容忍额外第三参数。
- 保留原始文本中的空格。
- 丢弃空文本、逆序时间和无有效逐字标签的行。
- 行按开始时间排序。
- 翻译和罗马音既可为 QRC，也可为普通时间轴 LRC；按行开始时间就近对齐。
- 只有至少一行包含有效 `LyricWord` 时，文档才标记为逐字歌词。

QQ 返回普通 LRC 时不参与逐字来源竞争。

## Caching And Lifecycle

`QqLyricClient` 使用容量 100 的 LRU：

- QQ 搜索匹配结果按规范化歌曲上下文缓存。
- 成功解析的 QRC 文档按网易云歌曲 ID 缓存。
- 相同 key 的并发请求通过 in-flight map 合并。
- 仅缓存成功结果；超时、404、解密失败和无可靠候选不会缓存。

`LyricsView` 保留现有 generation token。切歌后旧请求可以自然结束或填充缓存，但不能更新当前页面。

## Error Handling

- 三个来源独立捕获网络、格式和解析错误。
- 网易云失败时，AMLLDB 和 QQ 仍可提供逐字歌词。
- AMLLDB 404、非 TTML 或超时只表示该来源不可用。
- QQ 搜索无可靠候选、歌词为空、非 QRC、QDES 解密失败或超时只表示该来源不可用。
- 三个来源均无逐字结果时使用网易云普通 LRC。
- 网易云本身也失败且其他来源无结果时显示“暂无歌词”。
- 最终选中后输出一次调试日志，例如 `歌词来源: QQ音乐`，不在正常失败路径反复刷屏。

## Testing

### Unit Tests

- 使用固定加密 fixture 验证 QDES 解密、zlib 解压和 UTF-8 输出。
- 非法 hex、非 8 字节分组、损坏压缩流返回失败。
- QRC 标签位于文字前后两种格式均保留准确时间。
- 翻译和罗马音可从 QRC 或 LRC 对齐。
- QQ 匹配覆盖：正确候选、错误歌手、错误专辑、错误版本、时长差超过 3 秒、多个候选选最佳。
- QQ 客户端覆盖匿名请求结构、只获取最佳候选、缓存、并发去重和超时。
- Resolver 验证三个来源在首个 await 前均已启动。
- Resolver 验证优先级 `网易云 > AMLLDB > QQ`。
- Resolver 验证高优先级失败或无逐字歌词时降级。
- Resolver 验证三者无逐字结果时保留网易云普通 LRC。

### Widget And Regression Tests

- `LyricsView` 能用 QQ QRC 渲染 `TimedLyricText`。
- 快速切歌时旧 QQ 搜索或解密结果不能覆盖当前歌曲。
- 暂停、恢复、seek 和原有 500ms 行切换动画保持不变。
- 运行歌词测试集、全量 Flutter 测试、目标静态分析和 Windows Debug 构建。

### Manual Acceptance

1. Counting Stars 继续命中网易云 YRC。
2. 《群青》同名单曲版，网易云 ID `1472480890`，命中 AMLLDB。
3. 《THE BOOK》版《群青》，网易云 ID `1500151581`，在网易云和 AMLLDB 无逐字数据时命中 QQ QRC。
4. 查看终端日志确认三首歌曲的最终来源。
5. 对三首歌曲执行暂停、恢复、seek 和快速切换，确认逐字动画同步且不串歌。

QQ 歌词源通过人工验收后，再单独设计和实现播放器背景功能。
