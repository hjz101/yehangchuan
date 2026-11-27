# 夜航船

iOS 小说阅读器 Demo，按 **iOS 27 原生 Liquid Glass（液态玻璃）** 重做界面，并把《iOS 小说阅读器产品规划 v5》的功能纳入可操作演示。

书源相关链路（搜索、目录、正文、发现、段评、换源、调试）已经接上真实的 Legado 规则引擎，会真的联网；导入、阅读、听书、统计、备份走真实本机能力。内置一条**离线示例书源**：规则是完整的 Legado 3.0 JSON，内容由本机提供，开箱即可验证搜索→目录→正文，不连外网也不访问私网。**AI、TTS、iCloud 同步、漫画与音频格式解析仍是 `MockBackend` 模拟**，界面上都标了「模拟」。

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

一条命令跑完全部门禁：YeHangCore（91 项）+ LegadoCore（5 项）单测与 App 构建。PR 由 `.github/workflows/ci.yml` 自动跑同一套门禁（需 Xcode 27.2 的 macOS runner）。脚本会识别 Rosetta shell 并以原生 arm64 跑 `swift test`，避免「0 tests passed 但退出码为 0」的假通过。

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
| **导入** | 系统文件选择；TXT 真实编码探测与章节切分；EPUB 真实按需解析章节与正文；漫画 ZIP / 音频元数据模拟导入；链接与剪贴板 |
| **漫画** | 页漫 / 条漫切换、进度恢复、图片缓存、系统语音描述 |
| **实验室** | AI 摘要 / 封面 / TTS、JS 书源沙箱、在线发现、多角色与后台播放配置 |

### 听书
利用 iOS 26+ 的 `tabViewBottomAccessory`，标签栏上方常驻迷你播放条（优先显示正在播放的音频，否则显示继续阅读）。阅读页的「听书」使用 `AVSpeechSynthesizer` **真实发声**，支持暂停、进度、前后跳转与 1×–2× 变速；后台播放、锁屏信息、CarPlay 与多角色在声音实验室中模拟配置。

### 段评
玻璃浮层只读展示原文引用与评论列表；命中本地词表的内容隐藏；可一键屏蔽该源段评。不提供发表、点赞或举报入口。

## 清单对照（产品规划 v5）

| 规划项 | Demo 落地 |
| --- | --- |
| TXT 导入 / 编码 / 章节切分 | 真实读取 UTF-8、GB18030、UTF-16，正则切章，重复标题合并 |
| EPUB / 漫画 / 音频解析 | EPUB 真实按需读取 ZIP 内章节与正文；漫画 ZIP 与音频元数据以演示章节进入书架，漫画可读 |
| 分页与三种翻页 | 平移、覆盖、无动画；另有上下滚动 |
| 进度恢复 | 章节 + 段落 ID + UTF-16 offset 持久化，字号变化后可回到同一段 |
| 阅读设置 / 目录 / 书签 / 笔记 | 即时生效并持久化；书签备注可编辑 |
| iCloud 私有同步 | 模拟账号、同步、冲突与保留副本 |
| 正文导出 | 阅读页「⋯ → 导出正文」把已解析段落拼成 TXT，经系统分享面板发出；未加载章节如实标注 |
| 数据迁移 | books.json / notes.md / annotations.md 预览、复制与分享 |
| 多类型书架 | 小说 / 漫画 / 有声同架与筛选 |
| 音量键翻页 | 阅读设置开关 + `AVAudioSession` 音量变化监听 |
| 书源 JSON / 换源 / 权限 | 导入默认关闭、启用警告、私网拒绝；换源会检索同名书并做四步验证后才提交 |
| JS 书源沙箱（v1.1） | 权限警告、严格模式、私网拦截；规则里的 JS 在 JavaScriptCore 中真实执行；实验室的「沙箱演示」仍是模拟日志 |
| AI 封面 / 摘要 / TTS（v1.2） | 用户自配 Key 占位、摘要 / 封面方案 / 系统语音试听（模拟请求） |
| 在线发现与缓存（v1.3） | 分类从已启用书源的 `exploreUrl` 解析，书目真实抓取；订阅与章节缓存为模拟 |
| 听书与多角色（v2.0–v2.1） | 系统语音真实播放；后台、锁屏、CarPlay、多角色映射模拟 |
| 隐私 / 内容来源 / 分发 | 首次与设置常驻说明，自签安装（Sign to Run Locally），无内购 |

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

## 未实现

- CBZ / RAR / 7z 解包，真实 mp3/m4a/m4b 文件播放（EPUB 已能真实按需读取章节与正文）。
- CloudKit、WKWebView 执行 JS（规则 JS 走的是 JavaScriptCore）、真实 AI 请求与本机 ZIP 打包。
- App Store 分发与内购；当前为自签安装定位，`DEVELOPMENT_TEAM` 留空，Xcode 选 **Sign to Run Locally**。已提供 AppIcon、隐私清单（`PrivacyInfo.xcprivacy`）与后台音频声明，真机安装前在 Xcode 的 Devices 里选好目标设备即可。

标着「模拟」的入口（AI、TTS、iCloud 同步、漫画与音频解析）不会发出真实网络请求。**书源链路例外：启用书源后，搜索、目录、正文、发现、段评与换源都会真的联网**，请求地址可在「设置 → 网络日志」里查看（需要先打开记录开关）。
