# 夜航船

iOS 小说阅读器 Demo，按 **iOS 27 原生 Liquid Glass（液态玻璃）** 重做界面，并把《iOS 小说阅读器产品规划 v5》的功能纳入可操作演示。

书源相关链路（搜索、目录、正文、发现、段评、换源、调试）已经接上真实的 Legado 规则引擎，会真的联网；导入、阅读、听书、统计、备份走真实本机能力。内置一条**离线示例书源**：规则是完整的 Legado 3.0 JSON，内容由本机提供，开箱即可验证搜索→目录→正文，不连外网也不访问私网。CBZ/ZIP、CBR/RAR、7z 漫画都真实解包、按自然页序读取并降采样展示；TTS 系统语音朗读与 mp3/m4a/m4b 本地播放真实，角色声线也真切换。AI 摘要/封面会向用户自配的兼容服务发真实请求，iCloud 可切到真实 CloudKit 私有库，JS 沙箱用真实 WKWebView 执行脚本。**未登录 iCloud 或未配 AI Key 时保留演示降级并如实提示**，不会假装成功。

## 运行

打开 `YeHangChuan.xcodeproj`，选择 iPhone 模拟器运行（**iOS 27+**，当前使用 Xcode 27.2 / iOS 27.2 验证）。

```bash
xcodebuild -project YeHangChuan.xcodeproj -scheme YeHangChuan \
  -destination 'platform=iOS Simulator,name=iPhone 17e' build
```

> 若命令行构建报 `swift-plugin-server produced malformed response`，说明宏插件被沙盒拦截，追加 `OTHER_SWIFT_FLAGS="-disable-sandbox"` 即可（Xcode 内构建不受影响）。

## 验证

```bash
./Scripts/verify.sh
```

一条命令跑完全部门禁：YeHangCore + LegadoCore 单测与 App 构建。PR 由 `.github/workflows/ci.yml` 自动跑同一套门禁（需 Xcode 27.2 的 macOS runner）。脚本会识别 Rosetta shell 并以原生 arm64 跑 `swift test`，避免「0 tests passed 但退出码为 0」的假通过。

## 设计系统

### 色彩令牌
| 令牌 | 浅色 | 深色 | 用途 |
|------|------|------|------|
| `accent` | `#B6402A` | `#FF8E63` | 主操作、灯焰 |
| `jade` | `#1D6A66` | `#7ED9C9` | 书源、进度辅助 |
| `gold` | `#8A6A1F` | `#E9C179` | 连续天数等荣誉指标 |
| `text` | `#111A24` | `#F4F0E8` | 正文与标题 |
| `secondary` | `#5A6675` | `#A7B1BE` | 次级信息 |
| `tertiary` | `#87929F` | `#77828F` | 说明与元数据 |

全部令牌通过 `UIColor` 动态构造，随系统明暗自动切换，由 `Palette.adaptive(...)` 统一定义。

### 玻璃层次
- `glassSurface(cornerRadius:tint:interactive:)` — 卡片与工具条，附带极细高光描边
- `glassCircle(diameter:tint:)` — 悬浮圆形按钮（40–50pt，满足 44pt 触控下限）
- `glassCapsule(tint:interactive:)` — 状态胶囊、筛选 chip、提示条
- `GlassEffectContainer` 包裹相邻玻璃，触发 iOS 26 的融合效果

### 背景
`AppBackdrop` 用 `MeshGradient` + 两组缓慢漂移的径向光斑构成「夜色水面」，为玻璃提供可折射的内容层。这一层是液态玻璃能否成立的前提 —— 纯色背景下玻璃几乎不可见。光斑会遵循「减弱动态效果」辅助功能设置停止漂移。

## 页面

| 页面 | 内容 |
|------|------|
| **书架** | 继续阅读卡、类型/状态/分组筛选、网格密度切换（2/3 列）、搜索、长按管理、导入入口 |
| **阅读** | 分页 / 滚动、平移 / 覆盖 / 无动画、左右阅读方向、5 套主题（含护眼）、字号字重行距、独立留白、页眉页脚、目录正倒序、书签与备注、听书、换源、正文净化、音量键翻页 |
| **书源** | 书源池概览、默认关闭、启用权限警告、私网地址拦截、JSON 导入导出（Legado 3.0 字段）、分步调试、批量测试、网络日志（真实请求记录，默认关闭）、多源真实检索并加入书架；内置一条完整的离线示例源，默认启用，离线也能走完搜索→目录→正文 |
| **摘录** | 摘录流、按书筛选、只看收藏、写笔记、复制 |
| **统计** | 今日目标环、7 日柱状图、13 周 91 天热力图、连续天数与偏好星期洞察；数据来自真实翻页停留时间，落盘到本机 `read_records.json`，无记录时如实归零 |
| **设置** | 阅读偏好、每日目标、护眼与外观（界面明暗 + 暖色滤光）、备份、缓存、导出、账户与同步、分发与合规、功能实验室 |
| **导入** | 系统文件选择；TXT 真实编码探测与章节切分；EPUB 真实按需解析；mp3/m4a/m4b 真实导入并按真实时长播放；CBZ/ZIP、CBR/RAR、7z 漫画真实解包、按自然页序读取页图；链接与剪贴板 |
| **漫画** | 页漫 / 条漫切换、真实页图按需降采样、进度恢复、图片缓存落盘、系统语音描述；沙箱文件缺失时明确提示重新导入 |
| **实验室** | AI 摘要 / 封面真实请求、JS WKWebView 沙箱真实执行、在线发现、多角色声线与 CarPlay 场景 |

### 听书
利用 iOS 26+ 的 `tabViewBottomAccessory`，标签栏上方常驻迷你播放条（优先显示正在播放的音频，否则显示继续阅读）。阅读页的「听书」使用 `AVSpeechSynthesizer` **真实发声**，支持暂停、进度、前后跳转与 1×–2× 变速；正文按引号切成旁白/对话，各角色使用系统里真实存在的不同声线并连续朗读。后台音频模式与锁屏信息已接真实能力；CarPlay 场景提供「在听」章节列表与正在播放模板，开关持久化。

### 段评
玻璃浮层只读展示原文引用与评论列表；命中本地词表的内容隐藏；可一键屏蔽该源段评。不提供发表、点赞或举报入口。

## 清单对照（产品规划 v5）

| 规划项 | Demo 落地 |
| --- | --- |
| TXT 导入 / 编码 / 章节切分 | 真实读取 UTF-8、GB18030、UTF-16，正则切章，重复标题合并 |
| EPUB / 漫画 / 音频解析 | EPUB 真实按需读取；音频复制进沙箱后用 AVPlayer 真实播放；CBZ/ZIP、CBR/RAR、7z 均真实只读解包，按自然页序读取页图并降采样展示与缓存 |
| 分页与三种翻页 | 平移、覆盖、无动画；另有上下滚动 |
| 进度恢复 | 章节 + 段落 ID + UTF-16 offset 持久化，字号变化后可回到同一段 |
| 阅读设置 / 目录 / 书签 / 笔记 | 即时生效并持久化；书签备注可编辑 |
| iCloud 私有同步 | 可切到真实 CloudKit 私有库上传/拉取快照；未登录时如实报错，演示模式保留模拟账号、冲突与保留副本 |
| 正文导出 | 阅读页「⋯ → 导出正文」与有声书播放器「分享」都把已解析段落拼成 TXT，经系统分享面板发出；未加载章节如实标注 |
| 数据迁移 | books.json / notes.md / annotations.md 预览、复制与分享；可打包成一个真实 ZIP 一次导出 |
| 多类型书架 | 小说 / 漫画 / 有声同架与筛选 |
| 音量键翻页 | 阅读设置开关 + `AVAudioSession` 音量变化监听 |
| 书源 JSON / 换源 / 权限 | 导入默认关闭、启用警告、私网拒绝；换源会检索同名书并做四步验证后才提交 |
| JS 书源沙箱（v1.1） | 权限警告、严格模式、私网拦截；普通规则 JS 在 JavaScriptCore 中真实执行，`<webjs>` 规则与实验室沙箱在真实 WKWebView 独立进程中执行，页面网络被拦、只留受限原生桥并经私网闸门 |
| AI 封面 / 摘要 / TTS（v1.2） | 摘要与封面按 OpenAI 兼容协议向用户自配服务发真实请求，Key 存系统 Keychain，只上传当前书正文前 4000 字；TTS 试听仍用系统语音 |
| 在线发现与缓存（v1.3） | 分类从已启用书源的 `exploreUrl` 解析，书目真实抓取；章节正文缓存为真实预取落盘，订阅为模拟 |
| 听书与多角色（v2.0–v2.1） | 系统语音真实播放并按角色切换真实声线，锁屏显示章节/进度并支持播放/暂停/跳转远程控制，后台音频模式已声明；CarPlay 场景提供章节列表与正在播放模板；播放器章节切换、睡眠定时、段评、分享已接真实动作 |
| 隐私 / 内容来源 / 分发 | 首次与设置常驻说明，自签安装（Sign to Run Locally），已声明后台音频与 CarPlay entitlement；无内购。真机/TestFlight 需开发者账号 |

## 凭据存储迁移

书源登录 Header、Cookie 与 JS 变量目前以 SQLite 为权威副本，并**双写**到系统 Keychain（服务 `com.huaiju.yehangchuan.credentials`）。迁移是可回滚、分批推进的：

- 默认阶段 `dualWrite`：SQLite 仍权威、绝不删除；Keychain 作为第二份随写，写入后以 `PersistentRuntimeCache.reconcile()` 对账。
- 对账无 `missing` / `mismatch` 后，用 `backfillKeychain()` 补齐历史数据，再把 `CredentialSettings.shared.backend` 切到 `keychainPreferred` 才以 Keychain 优先读。
- 任一步异常，把 `backend` 切回 `.sqlite` 即完全回到迁移前行为（回滚开关，无需重启）。
- Keychain 不可用时写入失败被吞掉，登录态仍从 SQLite 读取，不会白屏。

尚未覆盖：WebDAV 密码仍存于 `servers` 表的配置 JSON（当前 App 无 WebDAV 入口，属休眠路径）。

## 护眼

全 App 暖色滤光与亮度压低；阅读页内置「护眼」绿色主题；支持可调暖度、亮度与 20 分钟休息提醒。护眼强度保存在本机。

## 调试启动参数

`#if DEBUG` 下支持以下参数，便于截图与验收：

```
-light                  强制浅色外观
-openReader             直接打开《夜航船》阅读页
-hideChrome             阅读页隐藏工具栏（沉浸模式）
-showReaderSettings     打开阅读设置
-showComments           打开段评浮层
-openSource / -openSettings / -openExcerpts / -openStats
-startAudio             开始播放有声书（显示迷你播放条）
-openPlayer             打开全屏播放页
-openSearch / -showAddSource / -showSearch
-openImport             打开智能导入
-openComic              打开漫画阅读器
-openSync / -openBackup / -openCache / -openNetworkLogs
-openEyeCare / -settingsBottom
-openSourceDetail / -openSourceImport / -showSourceDetail / -showSourceImport
-openExport / -openAI / -openSandbox / -openDiscover / -openVoice / -openCompliance
-showTOC / -showBookmarks / -showListen / -showSourceSwitch
-coverTurn / -noTurn    强制覆盖翻页 / 无动画
-scrollMode             滚动阅读
-eyeCare                开启暖色滤光
```

## 未实现 / 需外部配置

- AI TTS：试听仍用系统语音；要调用真实 AI 语音服务需再配置兼容 TTS 端点（书源里的 HttpTTS 已有真实实现，但实验室未接入）。
- App Store 分发与内购：当前为自签安装定位，`DEVELOPMENT_TEAM` 留空，Xcode 选 **Sign to Run Locally**。AppIcon、隐私清单、后台音频与 CarPlay entitlement 已备好；真机/TestFlight 归档需开发者账号并在 Signing & Capabilities 里启用 iCloud 与 CarPlay capability。
- 密码学 RAR 压缩包、加密 7z：解析器只支持未加密的公开格式，遇到加密包会明确报错。

需要外部条件的能力：**AI** 要用户自配兼容服务与 Key（Key 存 Keychain，不内置）；**iCloud** 要登录 Apple ID 并在工程里开启 iCloud capability（未登录时界面如实显示 CloudKit 错误）；**CarPlay** 要车机/模拟器配对且工程开启 CarPlay capability。未配置时界面会保留演示降级并明确说明，不会假装同步或请求成功。

**书源链路例外：启用书源后，搜索、目录、正文、发现、段评与换源都会真的联网**，请求地址可在「设置 → 网络日志」里查看（需要先打开记录开关）。
