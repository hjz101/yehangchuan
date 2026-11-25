# 夜航船

iOS 小说阅读器 Demo，围绕 iOS 26/27 的 **Liquid Glass（液态玻璃）** 设计语言重做界面。所有书籍、书源与段评均为本地模拟数据，无真实后端。

## 运行

打开 `YeHangChuan.xcodeproj`，选择 iPhone 模拟器运行（**iOS 26+**）。

```bash
xcodebuild -project YeHangChuan.xcodeproj -scheme YeHangChuan \
  -destination 'platform=iOS Simulator,name=iPhone 17e' build
```

> 若命令行构建报 `swift-plugin-server produced malformed response`，说明宏插件被沙盒拦截，追加 `OTHER_SWIFT_FLAGS="-disable-sandbox"` 即可（Xcode 内构建不受影响）。

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

### 滚动折射层
`ScrollRefraction.swift` + `Shaders.metal` 在内容层上加了一层随滚动变化的折射：

- 每个页面用 `onScrollGeometryChange` 采集滚动位移与逐帧增量，写入 `ScrollPulse` 环境值
- Metal 的 `glassRefraction` 只在靠近顶部/底部玻璃条的区域产生横向位移（最大 7pt），中部正文不受影响
- 玻璃条上的 `.glassSheen()` 是一层斜向高光：亮度跟随滚动速度，位置跟随滚动位移
- 静止时 `distortionEffect` 自动停用，不产生离屏渲染；没有常驻的波纹

### 翻页
`PageTurnReader` 用 `matchedGeometryEffect` 让同一条「纸边」从书堆右侧移动到左侧，成为新页的前缘。正文始终以整页尺寸排版，只被逐帧裁切露出，所以换行位置在动画全程不变——不会出现形变时文字被压扁或重新换行的问题。点击左右边缘或横向轻扫均可翻页。

## 页面

| 页面 | 内容 |
|------|------|
| **书架** | 继续阅读卡、类型/状态筛选、网格密度切换（2/3 列）、搜索、长按管理 |
| **阅读** | 纸边共享元素翻页 / 上下滚动、4 套主题（日间/羊皮纸/夜航/夜间）、字号行距、目录搜索、书签、沉浸模式、段落摘录 |
| **书源** | 书源池环形概览、启用开关、添加书源（JSON/JS 模板、快速填充）、按源检索并加入书架 |
| **摘录** | 摘录流、按书筛选、只看收藏、写笔记、复制 |
| **统计** | 今日目标环、7 日柱状图、13 周 91 天热力图、连续天数与偏好星期洞察 |
| **设置** | 阅读偏好、每日目标、界面明暗（系统/浅色/深色）、数据与分发入口 |

### 听书
利用 iOS 26 的 `tabViewBottomAccessory`，标签栏上方常驻迷你播放条（优先显示正在播放的音频，否则显示继续阅读），可展开为全屏玻璃播放页，支持进度拖动、快进快退、1× / 1.25× / 1.5× / 2× 变速。

### 段评
玻璃浮层展示原文引用与评论列表，支持点赞，并可从底部批量屏蔽该源段评。

## 调试启动参数

`#if DEBUG` 下支持以下参数，便于截图与验收：

```
-light                  强制浅色外观
-openReader             直接打开《夜航船》阅读页
-hideChrome             阅读页隐藏工具栏（沉浸模式）
-scrollMode             切换为上下滚动阅读（可配合 -showRefraction 观察正文折射）
-showReaderSettings     打开阅读设置
-showComments           打开段评浮层
-autoTurn               进入阅读页后自动翻一页
-slowTurn               把翻页动画放慢 5 倍（配合 -autoTurn 观察中间帧）
-showRefraction         冻结一个「正在滚动」的状态，用来检查折射层
-openSource / -openSettings / -openExcerpts / -openStats
-startAudio             开始播放有声书（显示迷你播放条）
-openPlayer             打开全屏播放页
-openSearch / -showAddSource / -showSearch
```

## 未实现

真实导入解析、书源网络请求、持久化（重启后进度与摘录重置）、漫画阅读器、音频真实播放、iCloud 同步。
