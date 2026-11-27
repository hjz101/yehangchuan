import SwiftUI
import Observation
import AVFoundation
import MediaPlayer
import LegadoCore
import YeHangCore

// MARK: - Book

enum BookKind: String, CaseIterable, Identifiable, Codable {
    case novel = "小说"
    case comic = "漫画"
    case audio = "有声"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .novel: "book.closed"
        case .comic: "rectangle.on.rectangle"
        case .audio: "headphones"
        }
    }

    var tint: Color {
        switch self {
        case .novel: Palette.accent
        case .comic: Palette.jade
        case .audio: Palette.gold
        }
    }
}

struct Book: Identifiable, Hashable, Codable, Sendable {
    let id: String
    var title: String
    var author: String
    var kind: BookKind
    var coverStyle: Int
    var chapterCount: Int
    var progress: Double
    var lastPosition: String
    var pageCount: Int?
    var duration: String?
    var isFinished: Bool
    var group: String? = nil
    var sourceID: String? = nil
    var lastReadAt: Date? = nil
    /// 来自网络书源时的书籍地址与目录地址；本地书与演示书为 nil。
    /// 这两个字段是重新进入阅读页后还能继续拉正文的前提，所以必须持久化。
    var networkBookURL: String? = nil
    var networkTocURL: String? = nil
    /// 本地音频文件名（相对 LibraryStore 的 AudioBooks 目录）。
    /// Optional 且有默认值，旧快照缺这个键时合成解码会容错为 nil。
    var audioFileName: String? = nil
    /// 本地漫画压缩包文件名（相对 LibraryStore 的 Comics 目录）。
    /// Optional 且有默认值，旧快照缺这个键时合成解码会容错为 nil。
    var comicFileName: String? = nil

    var unitLabel: String { kind == .comic ? "话" : "章" }

    /// 章节数文案。在线书在目录拉回来之前是 0 —— 这时候如实写「待加载」，
    /// 而不是显示一个像模像样的「0 章」骗自己。
    var chapterCountLabel: String {
        if chapterCount > 0 { return "\(chapterCount) \(unitLabel)" }
        return isNetworkBook ? "目录待加载" : "0 \(unitLabel)"
    }

    /// 是不是一本书源上的在线书。
    var isNetworkBook: Bool { networkBookURL?.isEmpty == false && sourceID != nil }
}

// MARK: - Source

enum SourceKind: String, CaseIterable, Codable {
    case json = "JSON"
    case js = "JS"
}

struct BookSource: Identifiable, Hashable, Codable, Sendable {
    let id: String
    var name: String
    var host: String
    var kind: SourceKind
    var enabled: Bool
    var bookCount: Int
    var group: String = "小说"
    var login: SourceLoginState = .signedOut
    var latency: Int? = nil
    var lastError: String? = nil
    var username: String = ""
    var rule: String = ""

    /// 规则的正文来源：Legado 书源的 `bookSourceUrl`。
    /// 与 `host` 的区别是这里保留原串（可能含协议、路径），用于去重与展示。
    var ruleSourceURL: String? {
        guard let data = rule.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return (object["bookSourceUrl"] ?? object["host"]) as? String
    }

    /// Legado 的 `bookSourceUrl` 允许逗号分隔多个备用域名，
    /// `https://a.com,https://b.com` 这种写法很常见。
    /// 逐个 normalize 后返回，空串与解析失败的丢弃。
    static func splitHosts(_ raw: String) -> [String] {
        raw.split(whereSeparator: { $0 == "," || $0 == "，" })
            .map { URLHost.normalize(String($0)) }
            .filter { !$0.isEmpty }
    }

    /// 规则里是否含 JS：`@js:` 前缀、`<js>` 块，或 searchUrl 是脚本。
    /// Legado 没有 App 自造的 `kind` 字段，判断是不是脚本源只能看规则本身。
    static func containsJavaScript(_ row: [String: Any]) -> Bool {
        func scans(_ value: Any?) -> Bool {
            guard let text = value as? String else { return false }
            let lower = text.lowercased()
            return lower.contains("@js:") || lower.contains("<js>") || lower.contains("webview")
        }
        if scans(row["searchUrl"]) { return true }

        for key in ["ruleSearch", "ruleBookInfo", "ruleToc", "ruleContent", "ruleExplore"] {
            guard let rule = row[key] as? [String: Any] else { continue }
            if rule.values.contains(where: scans) { return true }
        }
        return scans(row["jsLib"])
    }
}

enum SourceLoginState: String, Codable {
    case signedOut = "未登录"
    case signedIn = "已登录"
    case expired = "登录过期"
}

// MARK: - Reading Content

struct Paragraph: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let text: String
    var comments: [SegmentComment] = []

    private enum CodingKeys: String, CodingKey { case id, text, comments }

    /// 手写解码：`comments` 有默认值，但 Swift 自动合成的解码器**不会**用默认值
    /// 兜住缺失的键 —— 少一个 `comments` 整个书库都解不出来，
    /// 用户看到的就是「书架空了」。所以这里显式 `decodeIfPresent`。
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        text = try container.decode(String.self, forKey: .text)
        comments = try container.decodeIfPresent([SegmentComment].self, forKey: .comments) ?? []
    }

    init(id: String, text: String, comments: [SegmentComment] = []) {
        self.id = id
        self.text = text
        self.comments = comments
    }
}

struct SegmentComment: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let author: String
    let text: String
    var likes: Int = 0
    var liked: Bool = false
    var minutesAgo: Int = 0

    private enum CodingKeys: String, CodingKey { case id, author, text, likes, liked, minutesAgo }

    /// 同上：段评的计数与时间戳都是「有默认值、可缺省」的字段，
    /// 缺一个不该让整本书读不出来。
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        author = try container.decode(String.self, forKey: .author)
        text = try container.decode(String.self, forKey: .text)
        likes = try container.decodeIfPresent(Int.self, forKey: .likes) ?? 0
        liked = try container.decodeIfPresent(Bool.self, forKey: .liked) ?? false
        minutesAgo = try container.decodeIfPresent(Int.self, forKey: .minutesAgo) ?? 0
    }

    init(
        id: String,
        author: String,
        text: String,
        likes: Int = 0,
        liked: Bool = false,
        minutesAgo: Int = 0
    ) {
        self.id = id
        self.author = author
        self.text = text
        self.likes = likes
        self.liked = liked
        self.minutesAgo = minutesAgo
    }
}

struct Chapter: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let title: String
    var paragraphs: [Paragraph]
    /// 在线书源的章节地址。本地与演示章节为 nil，保证旧快照仍能解码。
    var networkURL: String? = nil
}

// MARK: - Appearance

enum AppAppearance: String, CaseIterable, Identifiable, Codable {
    case system = "跟随系统"
    case light = "浅色"
    case dark = "深色"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max.fill"
        case .dark: "moon.fill"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

// MARK: - Reader Settings

enum ReaderTheme: String, CaseIterable, Identifiable, Codable {
    case day = "日间"
    case paper = "羊皮纸"
    case eye = "护眼"
    case voyage = "夜航"
    case night = "夜间"

    var id: String { rawValue }

    var background: Color {
        switch self {
        case .day: Color(hex: 0xFAF7F1)
        case .paper: Color(hex: 0xF0E4CB)
        case .eye: Color(hex: 0xE7EFE3)
        case .voyage: Color(hex: 0x0D1B2A)
        case .night: Color(hex: 0x101013)
        }
    }

    var backgroundDeep: Color {
        switch self {
        case .day: Color(hex: 0xEFE9DD)
        case .paper: Color(hex: 0xE2D1B0)
        case .eye: Color(hex: 0xD3E1CE)
        case .voyage: Color(hex: 0x081119)
        case .night: Color(hex: 0x08080A)
        }
    }

    var text: Color {
        switch self {
        case .day: Color(hex: 0x1E1B16)
        case .paper: Color(hex: 0x3A2D1D)
        case .eye: Color(hex: 0x263829)
        case .voyage: Color(hex: 0xD9E2EC)
        case .night: Color(hex: 0xC9C4BA)
        }
    }

    var secondary: Color {
        switch self {
        case .day: Color(hex: 0x877B69)
        case .paper: Color(hex: 0x8C7656)
        case .eye: Color(hex: 0x667865)
        case .voyage: Color(hex: 0x6E869D)
        case .night: Color(hex: 0x7A766D)
        }
    }

    var accent: Color {
        switch self {
        case .day: Color(hex: 0xB6402A)
        case .paper: Color(hex: 0x96502C)
        case .eye: Color(hex: 0x4F7A55)
        case .voyage: Color(hex: 0xE8A76A)
        case .night: Color(hex: 0xB49C7E)
        }
    }

    var isDark: Bool { self == .voyage || self == .night }

    var symbol: String {
        switch self {
        case .day: "sun.max"
        case .paper: "text.book.closed"
        case .eye: "leaf"
        case .voyage: "moon.stars"
        case .night: "moon"
        }
    }
}

enum PageMode: String, CaseIterable, Identifiable, Codable {
    case slide = "横向翻页"
    case scroll = "上下滚动"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .slide: "rectangle.on.rectangle"
        case .scroll: "arrow.up.arrow.down"
        }
    }
}

enum PageTurnEffect: String, CaseIterable, Identifiable, Codable {
    case slide = "平移"
    case cover = "覆盖"
    case none = "无动画"

    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .slide: "arrow.left.and.right"
        case .cover: "rectangle.on.rectangle"
        case .none: "bolt.slash"
        }
    }
}

enum ReadingDirection: String, CaseIterable, Identifiable, Codable {
    case ltr = "从左到右"
    case rtl = "从右到左"

    var id: String { rawValue }
    var layoutDirection: LayoutDirection { self == .rtl ? .rightToLeft : .leftToRight }
}

enum ReaderFontDesign: String, CaseIterable, Identifiable, Codable {
    case serif = "宋体"
    case system = "系统"
    case rounded = "圆体"

    var id: String { rawValue }
    var design: Font.Design {
        switch self {
        case .serif: .serif
        case .system: .default
        case .rounded: .rounded
        }
    }
}

enum ReaderWeight: String, CaseIterable, Identifiable, Codable {
    case regular = "常规"
    case medium = "中等"
    case semibold = "加粗"

    var id: String { rawValue }
    var weight: Font.Weight {
        switch self {
        case .regular: .regular
        case .medium: .medium
        case .semibold: .semibold
        }
    }
}

@MainActor
@Observable
final class ReaderSettings {
    var fontSize: Double = 18
    var lineSpacing: Double = 0.75
    var theme: ReaderTheme = .voyage
    var pageMode: PageMode = .slide
    var pageTurnEffect: PageTurnEffect = .slide
    var direction: ReadingDirection = .ltr
    var fontDesign: ReaderFontDesign = .serif
    var fontWeight: ReaderWeight = .regular
    var sideMargin: Double = 28
    var indent: Bool = true
    var showHeaderFooter: Bool = true
    var volumeKeyTurn: Bool = false
    var hideSourceComments = false
    var purifyText = false

    var snapshot: ReaderSnapshot {
        ReaderSnapshot(
            fontSize: fontSize,
            lineSpacing: lineSpacing,
            theme: theme,
            pageMode: pageMode,
            pageTurnEffect: pageTurnEffect,
            direction: direction,
            fontDesign: fontDesign,
            fontWeight: fontWeight,
            sideMargin: sideMargin,
            indent: indent,
            showHeaderFooter: showHeaderFooter,
            volumeKeyTurn: volumeKeyTurn,
            hideSourceComments: hideSourceComments,
            purifyText: purifyText
        )
    }

    func apply(_ snapshot: ReaderSnapshot) {
        fontSize = snapshot.fontSize
        lineSpacing = snapshot.lineSpacing
        theme = snapshot.theme
        pageMode = snapshot.pageMode
        pageTurnEffect = snapshot.pageTurnEffect
        direction = snapshot.direction
        fontDesign = snapshot.fontDesign
        fontWeight = snapshot.fontWeight
        sideMargin = snapshot.sideMargin
        indent = snapshot.indent
        showHeaderFooter = snapshot.showHeaderFooter
        volumeKeyTurn = snapshot.volumeKeyTurn
        hideSourceComments = snapshot.hideSourceComments
        purifyText = snapshot.purifyText
    }
}

struct ReaderSnapshot: Codable, Equatable, Sendable {
    var fontSize: Double = 18
    var lineSpacing: Double = 0.75
    var theme: ReaderTheme = .voyage
    var pageMode: PageMode = .slide
    var pageTurnEffect: PageTurnEffect = .slide
    var direction: ReadingDirection = .ltr
    var fontDesign: ReaderFontDesign = .serif
    var fontWeight: ReaderWeight = .regular
    var sideMargin: Double = 28
    var indent: Bool = true
    var showHeaderFooter: Bool = true
    var volumeKeyTurn: Bool = false
    var hideSourceComments: Bool = false
    var purifyText: Bool = false

    private enum CodingKeys: String, CodingKey {
        case fontSize, lineSpacing, theme, pageMode, pageTurnEffect, direction
        case fontDesign, fontWeight, sideMargin, indent, showHeaderFooter
        case volumeKeyTurn, hideSourceComments, purifyText
    }

    /// 逐个字段兜底。阅读设置全是「可以再调」的偏好：
    /// 少一个键、或某个枚举值是这个版本不认识的，只该让那一项回到默认，
    /// 不该让整份设置读不出来，更不该连累书库。
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        fontSize = try c.decodeIfPresent(Double.self, forKey: .fontSize) ?? fontSize
        lineSpacing = try c.decodeIfPresent(Double.self, forKey: .lineSpacing) ?? lineSpacing
        theme = (try? c.decodeIfPresent(ReaderTheme.self, forKey: .theme)) .flatMap { $0 } ?? theme
        pageMode = (try? c.decodeIfPresent(PageMode.self, forKey: .pageMode)).flatMap { $0 } ?? pageMode
        pageTurnEffect = (try? c.decodeIfPresent(PageTurnEffect.self, forKey: .pageTurnEffect)).flatMap { $0 }
            ?? pageTurnEffect
        direction = (try? c.decodeIfPresent(ReadingDirection.self, forKey: .direction)).flatMap { $0 } ?? direction
        fontDesign = (try? c.decodeIfPresent(ReaderFontDesign.self, forKey: .fontDesign)).flatMap { $0 } ?? fontDesign
        fontWeight = (try? c.decodeIfPresent(ReaderWeight.self, forKey: .fontWeight)).flatMap { $0 } ?? fontWeight
        sideMargin = try c.decodeIfPresent(Double.self, forKey: .sideMargin) ?? sideMargin
        indent = try c.decodeIfPresent(Bool.self, forKey: .indent) ?? indent
        showHeaderFooter = try c.decodeIfPresent(Bool.self, forKey: .showHeaderFooter) ?? showHeaderFooter
        volumeKeyTurn = try c.decodeIfPresent(Bool.self, forKey: .volumeKeyTurn) ?? volumeKeyTurn
        hideSourceComments = try c.decodeIfPresent(Bool.self, forKey: .hideSourceComments) ?? hideSourceComments
        purifyText = try c.decodeIfPresent(Bool.self, forKey: .purifyText) ?? purifyText
    }

    init() {}

    init(
        fontSize: Double,
        lineSpacing: Double,
        theme: ReaderTheme,
        pageMode: PageMode,
        pageTurnEffect: PageTurnEffect,
        direction: ReadingDirection,
        fontDesign: ReaderFontDesign,
        fontWeight: ReaderWeight,
        sideMargin: Double,
        indent: Bool,
        showHeaderFooter: Bool,
        volumeKeyTurn: Bool,
        hideSourceComments: Bool,
        purifyText: Bool
    ) {
        self.fontSize = fontSize
        self.lineSpacing = lineSpacing
        self.theme = theme
        self.pageMode = pageMode
        self.pageTurnEffect = pageTurnEffect
        self.direction = direction
        self.fontDesign = fontDesign
        self.fontWeight = fontWeight
        self.sideMargin = sideMargin
        self.indent = indent
        self.showHeaderFooter = showHeaderFooter
        self.volumeKeyTurn = volumeKeyTurn
        self.hideSourceComments = hideSourceComments
        self.purifyText = purifyText
    }
}

// MARK: - Excerpts

struct Excerpt: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let bookID: String
    let bookTitle: String
    let chapterTitle: String
    let text: String
    var note: String
    let createdAt: Date
    var liked: Bool

    var relativeDate: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.unitsStyle = .short
        return formatter.localizedString(for: createdAt, relativeTo: Date())
    }
}

// MARK: - Bookmarks & Search

struct Bookmark: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let bookID: String
    let bookTitle: String
    let chapterTitle: String
    let pageIndex: Int
    let progress: Double
    var note: String
    let createdAt: Date
    /// 定位锚点：段落 ID。改字号重排后页序号会变，段落 ID 不会。
    /// 旧版本写入的书签没有这两个字段，解码后为 nil，回退用 pageIndex。
    var paragraphID: String? = nil
    var offset: Int? = nil

    var percentLabel: String { "\(Int((progress * 100).rounded()))%" }
}

struct TextHit: Identifiable, Hashable {
    let id: String
    let book: Book
    let chapterTitle: String
    let paragraphID: String
    let snippet: String
}

struct ReaderTarget: Identifiable {
    let book: Book
    var chapterTitle: String? = nil
    var id: String { "\(book.id)-\(chapterTitle ?? "start")" }
}

struct ReadingPosition: Codable, Equatable, Sendable {
    let bookID: String
    var chapterTitle: String
    var paragraphID: String
    var offset: Int
    var progress: Double
    var updatedAt: Date
}

// MARK: - Eye care

struct EyeCareSettings: Codable, Equatable, Sendable {
    var enabled = false
    var warmth: Double = 0.35
    var dim: Double = 0.08
    var restReminder = true
    var restMinutes = 20

    private enum CodingKeys: String, CodingKey { case enabled, warmth, dim, restReminder, restMinutes }

    /// 老快照里这一区经常只是个 `{}`（护眼功能后来才加）。
    /// 自动合成的解码器遇到缺键会直接抛错，整个书库跟着读不出来 ——
    /// 这里逐项兜底，缺什么就用默认值。
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? enabled
        warmth = try c.decodeIfPresent(Double.self, forKey: .warmth) ?? warmth
        dim = try c.decodeIfPresent(Double.self, forKey: .dim) ?? dim
        restReminder = try c.decodeIfPresent(Bool.self, forKey: .restReminder) ?? restReminder
        restMinutes = try c.decodeIfPresent(Int.self, forKey: .restMinutes) ?? restMinutes
    }

    init() {}
}

struct ImportDraft: Identifiable {
    let id = UUID()
    var title: String
    var author: String
    var kind: BookKind
    var detail: String
    var chapters: [Chapter]
    /// 音频导入时复制进沙箱的文件名；非音频书为 nil。
    var audioFileName: String? = nil
    /// 从音频文件读到的真实时长文案；读不到时为 nil。
    var durationLabel: String? = nil
    /// 漫画解包后的真实页数；非漫画书为 nil。
    var pageCount: Int? = nil
    /// 漫画导入时复制进沙箱的压缩包文件名；非漫画书为 nil。
    var comicFileName: String? = nil
}

// MARK: - Stats

struct DayStat: Identifiable, Hashable {
    let id: String
    let date: Date
    let minutes: Int

    var isToday: Bool { Calendar.current.isDateInToday(date) }

    var weekdayLabel: String {
        let symbols = ["日", "一", "二", "三", "四", "五", "六"]
        let index = Calendar.current.component(.weekday, from: date) - 1
        return symbols[max(0, min(6, index))]
    }
}

// MARK: - Audio Player

@MainActor
@Observable
final class AudioPlayer {
    var book: Book?
    var isPlaying = false
    var elapsed: Double = 0
    var duration: Double = 340
    var showFullPlayer = false
    /// 有声书的章节列表。书架只传书时为空，播放器会显式补上。
    var chapters: [Chapter] = []
    var chapterIndex = 0
    /// 睡眠定时（分钟），0 表示关闭。
    var sleepMinutes = 0

    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private var sleepTask: Task<Void, Never>?
    @ObservationIgnored private var avPlayer: AVPlayer?
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var endObserver: NSObjectProtocol?

    /// 有真实音频文件时走 AVPlayer，否则是演示计时器。
    var usesRealAudio: Bool { avPlayer != nil }
    var speed: Double = 1 {
        didSet {
            if let avPlayer, isPlaying { avPlayer.rate = Float(speed) }
            updateNowPlaying()
        }
    }

    var currentChapter: Chapter? {
        chapters.indices.contains(chapterIndex) ? chapters[chapterIndex] : nil
    }

    var progress: Double {
        duration <= 0 ? 0 : min(max(elapsed / duration, 0), 1)
    }

    var elapsedLabel: String { Self.label(elapsed) }
    var durationLabel: String { Self.label(duration) }
    var remainingLabel: String { "-" + Self.label(max(duration - elapsed, 0)) }

    func load(_ book: Book, chapters: [Chapter] = [], autoplay: Bool = true) {
        if self.book?.id == book.id {
            if !chapters.isEmpty { self.chapters = chapters }
            if autoplay && !isPlaying { resume() }
            return
        }
        teardownRealAudio()
        sleepTask?.cancel()
        sleepMinutes = 0
        self.book = book
        self.chapters = chapters
        chapterIndex = 0

        if let file = Self.audioFileURL(for: book) {
            setupRealAudio(url: file, autoplay: autoplay)
            return
        }
        duration = chapters.first.map(Self.chapterDuration) ?? (Self.seconds(book.duration) ?? 340)
        elapsed = min(duration * 0.22, max(duration - 8, 0))
        isPlaying = autoplay
        if autoplay { startTicking() } else { ticker?.cancel() }
        updateNowPlaying()
    }

    /// 切到指定章节。真实音频是单文件，按章节数均分到对应时间点；
    /// 演示音轨则按正文体量估算时长并从零开始。
    func selectChapter(_ index: Int) {
        guard chapters.indices.contains(index) else { return }
        chapterIndex = index
        if usesRealAudio {
            seek(to: duration * Double(index) / Double(max(chapters.count, 1)))
            return
        }
        duration = Self.chapterDuration(chapters[index])
        elapsed = 0
        if isPlaying { startTicking() }
        updateNowPlaying()
    }

    func setSleepTimer(_ minutes: Int) {
        sleepTask?.cancel()
        sleepMinutes = max(minutes, 0)
        guard sleepMinutes > 0 else { return }
        sleepTask = Task { [weak self] in
            for _ in 0..<minutes {
                try? await Task.sleep(for: .seconds(60))
                if Task.isCancelled { return }
            }
            await MainActor.run { [weak self] in
                self?.pause()
                self?.sleepMinutes = 0
            }
        }
    }

    private static func chapterDuration(_ chapter: Chapter) -> Double {
        let characters = chapter.paragraphs.map(\.text.count).reduce(0, +)
        return max(Double(characters) * 0.22, 60)
    }

    func toggle() {
        isPlaying ? pause() : resume()
    }

    func resume() {
        guard book != nil else { return }
        isPlaying = true
        if let avPlayer {
            avPlayer.rate = Float(speed)
        } else {
            startTicking()
        }
        updateNowPlaying()
    }

    func pause() {
        isPlaying = false
        avPlayer?.pause()
        ticker?.cancel()
        updateNowPlaying()
    }

    func seek(to value: Double) {
        let target = min(max(value, 0), duration)
        elapsed = target
        if let avPlayer {
            avPlayer.seek(to: CMTime(value: Int64(target * 1_000), timescale: 1_000))
        }
        updateNowPlaying()
    }

    func skip(_ seconds: Double) {
        seek(to: elapsed + seconds)
    }

    func stop() {
        pause()
        teardownRealAudio()
        sleepTask?.cancel()
        sleepMinutes = 0
        book = nil
        chapters = []
        chapterIndex = 0
        elapsed = 0
        updateNowPlaying()
    }

    // MARK: Real audio

    private static func audioFileURL(for book: Book) -> URL? {
        guard let name = book.audioFileName,
              let base = LibraryStore.shared.directory else { return nil }
        let url = base.appendingPathComponent("AudioBooks", isDirectory: true)
            .appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private func setupRealAudio(url: URL, autoplay: Bool) {
        let player = AVPlayer(url: url)
        avPlayer = player
        let seconds = CMTimeGetSeconds(player.currentItem?.duration ?? .zero)
        duration = seconds.isFinite && seconds > 0 ? seconds : (Self.seconds(book?.duration) ?? 340)
        elapsed = 0
        let interval = CMTime(value: 1, timescale: 4)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            let value = CMTimeGetSeconds(time)
            Task { @MainActor in
                guard let self, self.avPlayer === player else { return }
                self.elapsed = value
                self.updateNowPlaying()
            }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.isPlaying = false
                self.elapsed = 0
                self.updateNowPlaying()
            }
        }
        isPlaying = autoplay
        player.rate = autoplay ? Float(speed) : 0
        updateNowPlaying()
    }

    private func teardownRealAudio() {
        if let timeObserver, let avPlayer { avPlayer.removeTimeObserver(timeObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        avPlayer?.pause()
        avPlayer = nil
        timeObserver = nil
        endObserver = nil
    }

    private func updateNowPlaying() {
        let center = MPNowPlayingInfoCenter.default()
        // 不主动清空：听书（SpeechPlayer）也在写同一块 NowPlayingInfo，
        // 这里清空会把正在朗读的锁屏信息抹掉。
        guard let book, duration > 0 else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: currentChapter?.title ?? book.title,
            MPMediaItemPropertyArtist: book.author,
            MPMediaItemPropertyMediaType: MPMediaType.audioBook.rawValue,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? Double(speed) : 0
        ]
        center.nowPlayingInfo = info
    }

    private func startTicking() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard let self, self.isPlaying else { return }
                self.elapsed = min(self.duration, self.elapsed + 0.25 * self.speed)
                if self.elapsed >= self.duration {
                    self.isPlaying = false
                    return
                }
            }
        }
    }

    static func seconds(_ label: String?) -> Double? {
        guard let label else { return nil }
        let parts = label.split(separator: ":").compactMap { Double($0) }
        guard parts.count == 2 else { return nil }
        return parts[0] * 60 + parts[1]
    }

    static func label(_ value: Double) -> String {
        let total = Int(value.rounded())
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

// MARK: - Speed label

/// 倍速文案。`%.2g` 只有两位有效数字，1.25 会被格式化成「1.2」，
/// 与滑块实际取值不符；这里按是否有小数位分别输出。
enum SpeedLabel {
    static func text(_ value: Double) -> String {
        let rounded = (value * 100).rounded() / 100
        if rounded == rounded.rounded() {
            return "\(Int(rounded))×"
        }
        if (rounded * 10).rounded() == rounded * 10 {
            return String(format: "%.1f×", rounded)
        }
        return String(format: "%.2f×", rounded)
    }
}

// MARK: - Store

@MainActor
@Observable
final class AppStore {
    var books: [Book] = MockData.books
    var sources: [BookSource] = MockData.sources
    var settings = ReaderSettings()
    var excerpts: [Excerpt] = MockData.excerpts
    /// 真实阅读记录。统计页的每一项都从它派生，不再是写死的演示数组。
    var readRecords: [ReadRecord] = []
    var goalMinutes: Int = 60
    var appearance: AppAppearance = .dark
    var player = AudioPlayer()
    var speech = SpeechPlayer()
    var backend = MockBackend()
    /// 真实书源引擎。搜索、目录、正文走它；AI / TTS / 同步仍由 backend 模拟。
    var engine = SourceEngine()
    /// 真实请求日志。引擎的请求记在 LegadoCore 的 DiagnosticLog 里，
    /// 这里只做一层界面可观察的包装。
    var diagnostics = NetworkDiagnostics()
    var backup = BackupCenter()
    var bookmarks: [Bookmark] = []
    var positions: [String: ReadingPosition] = [:]
    var groups: [String] = ["夜读", "待读"]
    var customChapters: [String: [Chapter]] = [:]
    var eyeCare = EyeCareSettings()
    var toast: String?
    var syncSheetRequested = false

    private static let legacySnapshotKey = "yehangchuan.snapshot.v5"

    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var readingRepository: FileReadingActivityRepository?
    @ObservationIgnored private var readingSaveTask: Task<Void, Never>?
    private static let readingService = ReadingActivityService()
    /// 单机 Demo 没有账号体系，用一个固定设备 ID 汇总本机阅读记录。
    private static let deviceID = "local"

    /// 书架迁移结果。启动时跑一次，界面据此如实告诉用户搬了什么。
    var migrationReport: LibraryMigrationReport?

    /// 新存储在读写时遇到的问题（索引坏了、某本书正文读不出来）。
    /// 有值就说明这次读到 / 写下的数据并不完整，界面必须显示出来。
    var libraryStoreWarning: String?

    /// 顺序不能反：先迁移，再读。
    ///
    /// 读在前的话，首次启动会把旧快照（段落 ID 还是「章ID-p序号」）读进内存，
    /// 迁移随后写出的新结构立刻被内存里的旧数据覆盖回去，书签就白改了。
    init() {
        runLibraryMigration()
        loadSnapshot()
        loadReadingRecords()
    }

    private func loadReadingRecords() {
        guard let directory = LibraryStore.shared.directory else { return }
        let repository = FileReadingActivityRepository(
            bookmarksURL: directory.appendingPathComponent("reading_bookmarks.json"),
            recordsURL: directory.appendingPathComponent("read_records.json")
        )
        readingRepository = repository
        Task.detached { [repository] in
            let records = try? await repository.loadReadRecords()
            await MainActor.run { [weak self] in
                // 打开书可能在读取完成前就开始计时，别把刚记下的今天覆盖掉。
                guard let self, self.readRecords.isEmpty else { return }
                self.readRecords = records ?? []
            }
        }
    }

    // MARK: Shelf

    var continueBook: Book? {
        books.first { $0.progress > 0 && $0.progress < 1 }
    }

    var readingCount: Int {
        books.filter { $0.progress > 0 && !$0.isFinished }.count
    }

    var finishedCount: Int {
        books.filter(\.isFinished).count
    }

    func updateProgress(
        bookID: String,
        progress: Double,
        position: String,
        chapterTitle: String? = nil,
        paragraphID: String? = nil,
        offset: Int = 0
    ) {
        guard let index = books.firstIndex(where: { $0.id == bookID }) else { return }
        books[index].progress = min(max(progress, 0), 0.99)
        books[index].lastPosition = position
        books[index].lastReadAt = Date()
        if let chapterTitle, let paragraphID {
            positions[bookID] = ReadingPosition(
                bookID: bookID,
                chapterTitle: chapterTitle,
                paragraphID: paragraphID,
                offset: offset,
                progress: progress,
                updatedAt: Date()
            )
        }
        saveSnapshot()
    }

    func position(for bookID: String) -> ReadingPosition? {
        positions[bookID]
    }

    func toggleFinished(_ bookID: String) {
        guard let index = books.firstIndex(where: { $0.id == bookID }) else { return }
        books[index].isFinished.toggle()
        books[index].progress = books[index].isFinished ? 1 : 0.02
        books[index].lastPosition = books[index].isFinished ? "已读完" : "未开始"
        showToast(books[index].isFinished ? "已标记为读完" : "已移回在读")
        saveSnapshot()
    }

    func removeBook(_ bookID: String) {
        books.removeAll { $0.id == bookID }
        bookmarks.removeAll { $0.bookID == bookID }
        // 目录缓存按书 ID 存，而换源不改 ID。删书后如果留着缓存，
        // 下次从原书源重新入架会拿到「上一个源」的章节，正文却去原源取 —— 对不上。
        // 顺带也避免快照里堆积已删书籍的整份正文。
        customChapters[bookID] = nil
        showToast("已从书架移除")
        saveSnapshot()
    }

    func addToShelf(_ book: Book) {
        guard !books.contains(where: { $0.id == book.id }) else { return }
        books.insert(book, at: 0)
        if book.isNetworkBook {
            // 在线书加入书架后立刻拉一次目录，让章节数是真的而不是 0。
            // 拉取失败不影响入架，阅读页里还能重试。
            Task { @MainActor in
                _ = await loadNetworkChapters(for: book, force: true)
            }
        }
        showToast("已加入书架：\(book.title)")
        saveSnapshot()
    }

    func isOnShelf(_ bookID: String) -> Bool {
        books.contains { $0.id == bookID }
    }

    func book(id: String) -> Book? {
        books.first { $0.id == id }
    }

    // MARK: Sources

    func addSource(name: String, kind: SourceKind, host: String = "", rule: String = "") {
        let resolvedName = name.isEmpty ? "未命名书源" : name
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = BookSource(
            id: UUID().uuidString,
            name: resolvedName,
            host: trimmedHost.isEmpty ? (kind == .js ? "script.local" : "custom.example.com") : trimmedHost,
            kind: kind,
            enabled: false,
            bookCount: 0,
            rule: rule
        )
        sources.insert(source, at: 0)
        showToast("已添加书源：\(source.name) · 默认关闭")
        saveSnapshot()
    }

    func addSources(_ newSources: [BookSource]) {
        guard !newSources.isEmpty else { return }
        sources.insert(contentsOf: newSources, at: 0)
        showToast("已导入 \(newSources.count) 个书源")
        saveSnapshot()
    }

    func setSourceEnabled(_ sourceID: String, enabled: Bool) {
        guard let index = sources.firstIndex(where: { $0.id == sourceID }) else { return }
        sources[index].enabled = enabled
        syncPrivateAllowList()
        saveSnapshot()
    }

    /// 把「已启用且确实是私网地址」的书源同步给传输层。
    ///
    /// 私网地址默认拒绝，但用户可以在弹窗里显式放行——放行的意思就是
    /// 「这条书源允许访问私网」。传输层在别的线程上跑，不能用这里的状态，
    /// 所以每次书源启用状态变化时同步一份快照过去。
    func syncPrivateAllowList() {
        let allowed = sources
            .filter { $0.enabled }
            .compactMap { URLHost.isPrivate($0.host) ? URLHost.normalize($0.host) : nil }
        PrivateHostAllowList.shared.update(Set(allowed))
    }

    func removeSource(_ sourceID: String) {
        sources.removeAll { $0.id == sourceID }
        syncPrivateAllowList()
        showToast("已删除书源")
        saveSnapshot()
    }

    func updateSource(_ source: BookSource) {
        guard let index = sources.firstIndex(where: { $0.id == source.id }) else { return }
        sources[index] = source
        syncPrivateAllowList()
        saveSnapshot()
    }

    // MARK: Excerpts

    func addExcerpt(book: Book, chapter: String, text: String) {
        let excerpt = Excerpt(
            id: UUID().uuidString,
            bookID: book.id,
            bookTitle: book.title,
            chapterTitle: chapter,
            text: text,
            note: "",
            createdAt: Date(),
            liked: false
        )
        excerpts.insert(excerpt, at: 0)
        showToast("已摘录这一句")
        saveSnapshot()
    }

    func updateNote(_ excerptID: String, note: String) {
        guard let index = excerpts.firstIndex(where: { $0.id == excerptID }) else { return }
        excerpts[index].note = note
        saveSnapshot()
    }

    func toggleExcerptLike(_ excerptID: String) {
        guard let index = excerpts.firstIndex(where: { $0.id == excerptID }) else { return }
        excerpts[index].liked.toggle()
        saveSnapshot()
    }

    func removeExcerpt(_ excerptID: String) {
        excerpts.removeAll { $0.id == excerptID }
        showToast("已删除摘录")
        saveSnapshot()
    }

    func excerpts(for bookID: String) -> [Excerpt] {
        excerpts.filter { $0.bookID == bookID }
    }

    var excerptBooks: [(id: String, title: String, count: Int)] {
        var order: [String] = []
        var titles: [String: String] = [:]
        var counts: [String: Int] = [:]
        for excerpt in excerpts {
            if titles[excerpt.bookID] == nil { order.append(excerpt.bookID) }
            titles[excerpt.bookID] = excerpt.bookTitle
            counts[excerpt.bookID, default: 0] += 1
        }
        return order.map { (id: $0, title: titles[$0] ?? "", count: counts[$0] ?? 0) }
    }

    // MARK: Stats

    /// 近 91 天的真实阅读分钟，按 `ReadRecord.dailyReadTimes` 汇总。
    /// 没有任何记录时整条曲线都是 0 —— 这是如实反映，而不是拿演示数据充数。
    var days: [DayStat] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var totals: [String: Int64] = [:]
        for record in readRecords {
            for (day, milliseconds) in record.dailyReadTimes where milliseconds > 0 {
                totals[day, default: 0] += milliseconds
            }
        }
        return (0..<91).reversed().map { offset in
            let date = calendar.date(byAdding: .day, value: -offset, to: today) ?? today
            let key = ReadingActivityService.dayKey(for: date, calendar: calendar)
            return DayStat(id: key, date: date, minutes: Int((totals[key] ?? 0) / 60_000))
        }
    }

    /// 阅读页在翻页 / 离开时把停留时间交回来。只有 >= 1 秒的停留才计入，
    /// 避免连续拖动滑块式翻页刷出无意义的毫秒数。
    func recordReading(elapsedMilliseconds: Int64, bookName: String) {
        guard elapsedMilliseconds >= 1_000, !bookName.isEmpty else { return }
        let now = Int64(Date().timeIntervalSince1970 * 1_000)
        readRecords = Self.readingService.addingReadTime(
            elapsedMilliseconds,
            deviceID: Self.deviceID,
            bookName: bookName,
            now: now,
            to: readRecords
        )
        let snapshot = readRecords
        let previous = readingSaveTask
        let repository = readingRepository
        // 串行落盘：翻页很快时可能连续结算多次，不能让旧的快照后写覆盖新的。
        readingSaveTask = Task.detached {
            await previous?.value
            try? await repository?.saveReadRecords(snapshot)
        }
    }

    var todayMinutes: Int {
        days.last?.minutes ?? 0
    }

    var weekDays: [DayStat] {
        Array(days.suffix(7))
    }

    var weekMinutes: Int {
        weekDays.reduce(0) { $0 + $1.minutes }
    }

    var weekAverage: Int {
        let active = weekDays.filter { $0.minutes > 0 }
        guard !active.isEmpty else { return 0 }
        return active.reduce(0) { $0 + $1.minutes } / active.count
    }

    var streak: Int {
        var count = 0
        for day in days.reversed() {
            if day.minutes > 0 {
                count += 1
            } else if !day.isToday {
                break
            }
        }
        return count
    }

    var favoriteWeekday: String {
        let grouped = Dictionary(grouping: days.suffix(28)) { $0.weekdayLabel }
        let best = grouped.max { lhs, rhs in
            lhs.value.reduce(0) { $0 + $1.minutes } < rhs.value.reduce(0) { $0 + $1.minutes }
        }
        return best?.key ?? "—"
    }

    var totalMinutes: Int {
        days.reduce(0) { $0 + $1.minutes }
    }

    var goalProgress: Double {
        guard goalMinutes > 0 else { return 0 }
        return min(Double(todayMinutes) / Double(goalMinutes), 1)
    }

    // MARK: Library

    func chapters(for book: Book) -> [Chapter] {
        if let custom = customChapters[book.id], !custom.isEmpty { return custom }
        return MockData.chapters(for: book)
    }

    // MARK: 在线书源

    /// 把检索到的一本书加入书架。此时只有元数据，
    /// 目录与正文在打开阅读页时按需拉取（见 `loadNetworkChapters`）。
    func addNetworkBook(searchBook: SearchBook, sourceID: String) {
        guard !books.contains(where: { $0.id == searchBook.appBookID }) else {
            showToast("《\(searchBook.name)》已在书架")
            return
        }
        let book = searchBook.appBook(sourceID: sourceID, coverStyle: StableID.coverStyle(for: searchBook.name))
        books.insert(book, at: 0)
        showToast("已加入书架：《\(book.title)》")
        saveSnapshot()
    }

    /// 拉取并缓存目录。已缓存过就不再请求，除非强制刷新。
    @discardableResult
    func loadNetworkChapters(for book: Book, force: Bool = false) async -> [Chapter] {
        guard book.isNetworkBook else { return chapters(for: book) }
        if !force, let cached = customChapters[book.id], !cached.isEmpty { return cached }
        guard let appSource = sources.first(where: { $0.id == book.sourceID }),
              let engineSource = LegadoBridge.engineSource(from: appSource) else {
            engine.lastError = "书源已被移除或规则无法解析"
            return []
        }
        guard let bookURL = book.networkBookURL else { return [] }

        var searchBook = SearchBook(
            bookURL: bookURL,
            origin: engineSource.bookSourceUrl,
            originName: engineSource.bookSourceName,
            type: 0,
            name: book.title,
            author: book.author
        )
        if let toc = book.networkTocURL, !toc.isEmpty { searchBook.tocURL = toc }
        let result = await engine.chapters(searchBook: searchBook, source: engineSource)
        guard !result.chapters.isEmpty else { return [] }

        // 引擎章节 → App 章节，正文留空，打开时再拉。
        var mapped = result.chapters.map { $0.appChapter() }
        for index in mapped.indices {
            mapped[index].networkURL = result.chapters[index].url
        }

        // 上面在 await，期间可能换了源或把书删了。缓存只写回「发起请求时的那个源」，
        // 否则旧源的目录会盖掉换源后的新目录。
        guard let live = books.first(where: { $0.id == book.id }),
              live.sourceID == book.sourceID else { return mapped }

        customChapters[book.id] = mapped
        if let bookIndex = books.firstIndex(where: { $0.id == book.id }) {
            books[bookIndex].chapterCount = mapped.count
            books[bookIndex].networkTocURL = result.book.tocUrl.isEmpty ? nil : result.book.tocUrl
        }
        saveSnapshot()
        return mapped
    }

    /// 拉取指定章节的正文，成功后写回缓存。
    @discardableResult
    func loadNetworkContent(for book: Book, chapterID: String) async -> [Paragraph]? {
        guard book.isNetworkBook,
              let appSource = sources.first(where: { $0.id == book.sourceID }),
              let engineSource = LegadoBridge.engineSource(from: appSource),
              let bookURL = book.networkBookURL,
              let chapters = customChapters[book.id],
              let index = chapters.firstIndex(where: { $0.id == chapterID }),
              let url = chapters[index].networkURL else { return nil }
        // 已经拉过就不再请求。
        if !chapters[index].paragraphs.isEmpty { return chapters[index].paragraphs }

        var engineChapter = BookChapter(url: url, title: chapters[index].title, bookUrl: bookURL, index: index)
        engineChapter.baseUrl = bookURL
        let engineBook = LegadoCore.Book(bookUrl: bookURL, name: book.title, author: book.author, origin: engineSource.bookSourceUrl)

        let result = await engine.content(engineBook: engineBook, chapter: engineChapter, source: engineSource)
        guard !result.paragraphs.isEmpty else { return nil }

        // 上面在 await，期间可能换了源——旧下标指向的已经是另一章的缓存，
        // 甚至可能越界。按章节 ID 重新定位，找不到就只把正文交给调用方，不写缓存。
        guard let cached = customChapters[book.id],
              let liveIndex = cached.firstIndex(where: { $0.id == chapterID }) else {
            return result.paragraphs
        }
        customChapters[book.id]?[liveIndex].paragraphs = result.paragraphs
        saveSnapshot()
        return result.paragraphs
    }

    /// 把导入草稿加入书架。返回是否真的成功：
    /// 没有章节的草稿直接拒绝，界面才不会一边提示「已导入」一边给一本空书。
    @discardableResult
    func importBook(_ draft: ImportDraft) -> Bool {
        guard !draft.chapters.isEmpty else {
            showToast("导入失败：这本书没有任何章节")
            return false
        }
        let book = Book(
            id: "import-\(UUID().uuidString.prefix(8))",
            title: draft.title,
            author: draft.author,
            kind: draft.kind,
            coverStyle: StableID.coverStyle(for: draft.title),
            chapterCount: draft.chapters.count,
            progress: 0,
            lastPosition: "未开始",
            pageCount: draft.kind == .comic ? (draft.pageCount ?? max(draft.chapters.count * 8, 20)) : nil,
            // 时长读不出来就留空，界面会写「时长待读取」；不编造一个 "12:30"。
            duration: draft.kind == .audio ? draft.durationLabel : nil,
            isFinished: false,
            group: groups.first,
            sourceID: "local",
            audioFileName: draft.audioFileName,
            comicFileName: draft.comicFileName
        )
        customChapters[book.id] = draft.chapters
        books.insert(book, at: 0)
        let unit = book.kind == .comic ? "话" : "章"
        showToast("已导入《\(book.title)》· \(draft.chapters.count) \(unit)")
        saveSnapshot()
        return true
    }

    func setGroup(_ group: String?, for bookID: String) {
        guard let index = books.firstIndex(where: { $0.id == bookID }) else { return }
        books[index].group = group
        if let group, !groups.contains(group) { groups.append(group) }
        saveSnapshot()
    }

    func addGroup(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !groups.contains(trimmed) else { return }
        groups.append(trimmed)
        saveSnapshot()
        showToast("已创建分组「\(trimmed)」")
    }

    // MARK: 换源

    /// 换源所需的「当前书是谁、读到哪儿」。引擎只认它自己的 `Book`，
    /// 这一层把 App 的 `progress` / `lastPosition` 翻译成章节序号与标题。
    func switchTarget(for book: Book) -> TitleAuthor {
        let chapters = chapters(for: book)
        let position = positions[book.id]
        // 定位当前章节：优先用持久化的位置锚点，其次用 lastPosition 里记的标题。
        let currentTitle = position?.chapterTitle ?? book.lastPosition
        let index = chapters.firstIndex { $0.title == currentTitle } ?? 0

        // 当前段落在章内的 UTF-16 偏移。分三段写，别塞进一个闭包里 ——
        // 那样编译器会放弃类型检查。
        var offset = 0
        if let position,
           let chapter = chapters.first(where: { $0.title == position.chapterTitle }),
           let paragraphIndex = chapter.paragraphs.firstIndex(where: { $0.id == position.paragraphID }) {
            offset = chapter.paragraphs.prefix(paragraphIndex)
                .reduce(0) { $0 + $1.text.utf16.count }
        }

        let chapterTitle = chapters.indices.contains(index) ? chapters[index].title : nil
        let currentSource = sources.first { $0.id == book.sourceID }

        return TitleAuthor(
            title: book.title,
            author: book.author,
            bookURL: book.networkBookURL,
            tocURL: book.networkTocURL,
            origin: currentSource?.ruleSourceURL ?? currentSource?.host,
            chapterIndex: index,
            chapterTitle: chapterTitle,
            offset: offset,
            chapterCount: chapters.count
        )
    }

    /// 真实换源：去其它已启用书源搜同名书，逐个验证，只提交验证通过的那一个。
    ///
    /// 原来的实现只是把 `sourceID` 改一下就说「已切换」—— 那句话是假的，
    /// 章节内容一个字节都没变。现在验证通过才提交，失败就把原因说出来。
    @discardableResult
    func switchSource(bookID: String, to sourceID: String) async -> Bool {
        guard let index = books.firstIndex(where: { $0.id == bookID }) else { return false }
        let book = books[index]

        guard let appSource = sources.first(where: { $0.id == sourceID }),
              let engineSource = LegadoBridge.engineSource(from: appSource) else {
            showToast("书源规则无法解析，无法切换")
            return false
        }
        guard LegadoBridge.isSearchable(engineSource) else {
            showToast("「\(appSource.name)」没有搜索规则，无法换源")
            return false
        }
        // 本地书没有书源地址，换源无从谈起。
        guard book.isNetworkBook else {
            showToast("本地书不能换源")
            return false
        }

        let target = switchTarget(for: book)

        // 先在这个源里搜同名书。只接受规范化书名一致的候选，
        // 否则「换源」会把你带到另一本书上去。
        let candidates = await engine.switchCandidates(book: target, sources: [engineSource]) { _ in }
        guard let candidate = candidates.first else {
            showToast("「\(appSource.name)」里没有找到《\(book.title)》")
            return false
        }

        // 四步验证：详情 → 目录 → 章节匹配 → 正文。
        let prepared = await engine.prepareSwitch(
            book: target, candidate: candidate, source: engineSource
        )
        guard let report = prepared.error == nil ? prepared.report : nil,
              !report.chapters.isEmpty else {
            showToast(prepared.error ?? "候选书源无法读取")
            return false
        }

        // 验证通过才开始提交。上面几步都在 await，书可能已经被删了，
        // 所以这里重新定位一次：找不到就整件事作废，不要留下孤儿章节。
        guard let updated = books.firstIndex(where: { $0.id == bookID }) else {
            showToast("这本书已经不在书架上了")
            return false
        }

        var mapped = report.chapters.map { $0.appChapter() }
        for chapterIndex in mapped.indices {
            mapped[chapterIndex].networkURL = report.chapters[chapterIndex].url
        }
        customChapters[book.id] = mapped

        books[updated].sourceID = sourceID
        books[updated].chapterCount = mapped.count
        books[updated].networkBookURL = candidate.searchBook.bookURL
        books[updated].networkTocURL = candidate.searchBook.tocURL.isEmpty
            ? nil : candidate.searchBook.tocURL

        // 阅读位置迁到新源的对应章节。匹配上了就说匹配上，
        // 没匹配上退回同序号，并且如实告诉用户。
        let matchedTitle = report.matchedTitle
        let progress = books[updated].progress
        if let matchedTitle, report.exactChapterMatch {
            books[updated].lastPosition = matchedTitle
            positions[bookID] = ReadingPosition(
                bookID: bookID,
                chapterTitle: matchedTitle,
                paragraphID: "",
                offset: 0,
                progress: progress,
                updatedAt: Date()
            )
        } else {
            let fallback = mapped.indices.contains(report.matchedIndex)
                ? mapped[report.matchedIndex].title
                : mapped.first?.title ?? book.lastPosition
            books[updated].lastPosition = fallback
            positions[bookID] = ReadingPosition(
                bookID: bookID,
                chapterTitle: fallback,
                paragraphID: "",
                offset: 0,
                progress: progress,
                updatedAt: Date()
            )
        }
        saveSnapshot()

        if report.exactChapterMatch, let matchedTitle {
            showToast("已切换到「\(appSource.name)」，定位到「\(matchedTitle)」")
        } else {
            showToast("已切换到「\(appSource.name)」，但这个源缺少同名章节，已按序号就近定位")
        }
        return true
    }

    // MARK: Bookmarks

    func bookmarks(for bookID: String) -> [Bookmark] {
        bookmarks.filter { $0.bookID == bookID }.sorted { $0.createdAt > $1.createdAt }
    }

    /// 书签是否命中当前位置。优先按段落 ID 比较；没有锚点的旧书签回退到页序号。
    func isBookmarked(bookID: String, pageIndex: Int, chapterTitle: String?, paragraphID: String?) -> Bool {
        bookmarks.contains {
            $0.bookID == bookID && Self.bookmarkMatches(
                $0,
                pageIndex: pageIndex,
                chapterTitle: chapterTitle,
                paragraphID: paragraphID
            )
        }
    }

    private static func bookmarkMatches(
        _ bookmark: Bookmark,
        pageIndex: Int,
        chapterTitle: String?,
        paragraphID: String?
    ) -> Bool {
        if let anchor = bookmark.paragraphID, let paragraphID {
            return bookmark.chapterTitle == chapterTitle && anchor == paragraphID
        }
        return bookmark.pageIndex == pageIndex
    }

    @discardableResult
    func toggleBookmark(
        book: Book,
        chapterTitle: String,
        pageIndex: Int,
        progress: Double,
        paragraphID: String? = nil,
        offset: Int = 0
    ) -> Bool {
        if let existing = bookmarks.firstIndex(where: {
            $0.bookID == book.id && Self.bookmarkMatches(
                $0,
                pageIndex: pageIndex,
                chapterTitle: chapterTitle,
                paragraphID: paragraphID
            )
        }) {
            bookmarks.remove(at: existing)
            saveSnapshot()
            showToast("已移除书签")
            return false
        }
        bookmarks.insert(
            Bookmark(
                id: UUID().uuidString,
                bookID: book.id,
                bookTitle: book.title,
                chapterTitle: chapterTitle,
                pageIndex: pageIndex,
                progress: progress,
                note: "",
                createdAt: Date(),
                paragraphID: paragraphID,
                offset: offset
            ),
            at: 0
        )
        saveSnapshot()
        showToast("已添加书签")
        return true
    }

    func removeBookmark(_ bookmarkID: String) {
        bookmarks.removeAll { $0.id == bookmarkID }
        saveSnapshot()
    }

    func updateBookmarkNote(_ bookmarkID: String, note: String) {
        guard let index = bookmarks.firstIndex(where: { $0.id == bookmarkID }) else { return }
        bookmarks[index].note = note
        saveSnapshot()
    }

    // MARK: Full text

    func fullTextHits(query: String) -> [TextHit] {
        let key = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard key.count >= 1 else { return [] }
        var hits: [TextHit] = []
        for book in books where book.kind == .novel {
            for chapter in chapters(for: book) {
                for paragraph in chapter.paragraphs where paragraph.text.localizedCaseInsensitiveContains(key) {
                    let text = paragraph.text
                    let snippet: String
                    if let range = text.range(of: key, options: .caseInsensitive) {
                        let start = text.index(range.lowerBound, offsetBy: -18, limitedBy: text.startIndex) ?? text.startIndex
                        let end = text.index(range.upperBound, offsetBy: 28, limitedBy: text.endIndex) ?? text.endIndex
                        snippet = String(text[start..<end])
                    } else {
                        snippet = String(text.prefix(60))
                    }
                    hits.append(
                        TextHit(
                            id: "\(book.id)-\(paragraph.id)",
                            book: book,
                            chapterTitle: chapter.title,
                            paragraphID: paragraph.id,
                            snippet: snippet
                        )
                    )
                }
            }
        }
        return hits
    }

    // MARK: Toast

    func showToast(_ text: String) {
        toast = text
        Task {
            try? await Task.sleep(for: .seconds(2))
            if toast == text { toast = nil }
        }
    }

    // MARK: Persistence

    struct Snapshot: Codable, Sendable {
        var books: [Book]
        var sources: [BookSource]
        var excerpts: [Excerpt]
        var settings: ReaderSnapshot
        var goalMinutes: Int
        var appearance: AppAppearance
        var bookmarks: [Bookmark]
        var positions: [String: ReadingPosition]
        var groups: [String]
        var customChapters: [String: [Chapter]]
        var eyeCare: EyeCareSettings

        private enum CodingKeys: String, CodingKey {
            case books, sources, excerpts, settings, goalMinutes, appearance
            case bookmarks, positions, groups, customChapters, eyeCare
        }

        /// 逐分区兜底解码。整份快照是「用户书库的唯一副本」：
        /// 少一个分区键（旧版本没有、新版本才加）不该让整座书架读不出来。
        /// 只有 `books` 是必须的 —— 没有书架的「书架」没有意义。
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            books = try c.decodeIfPresent([Book].self, forKey: .books) ?? []
            sources = try c.decodeIfPresent([BookSource].self, forKey: .sources) ?? []
            excerpts = try c.decodeIfPresent([Excerpt].self, forKey: .excerpts) ?? []
            settings = try c.decodeIfPresent(ReaderSnapshot.self, forKey: .settings) ?? ReaderSnapshot()
            goalMinutes = try c.decodeIfPresent(Int.self, forKey: .goalMinutes) ?? 60
            appearance = try c.decodeIfPresent(AppAppearance.self, forKey: .appearance) ?? .dark
            bookmarks = try c.decodeIfPresent([Bookmark].self, forKey: .bookmarks) ?? []
            positions = try c.decodeIfPresent([String: ReadingPosition].self, forKey: .positions) ?? [:]
            groups = try c.decodeIfPresent([String].self, forKey: .groups) ?? []
            customChapters = try c.decodeIfPresent([String: [Chapter]].self, forKey: .customChapters) ?? [:]
            eyeCare = try c.decodeIfPresent(EyeCareSettings.self, forKey: .eyeCare) ?? EyeCareSettings()
        }

        init(
            books: [Book],
            sources: [BookSource],
            excerpts: [Excerpt],
            settings: ReaderSnapshot,
            goalMinutes: Int,
            appearance: AppAppearance,
            bookmarks: [Bookmark],
            positions: [String: ReadingPosition],
            groups: [String],
            customChapters: [String: [Chapter]],
            eyeCare: EyeCareSettings
        ) {
            self.books = books
            self.sources = sources
            self.excerpts = excerpts
            self.settings = settings
            self.goalMinutes = goalMinutes
            self.appearance = appearance
            self.bookmarks = bookmarks
            self.positions = positions
            self.groups = groups
            self.customChapters = customChapters
            self.eyeCare = eyeCare
        }
    }

    private func makeSnapshot() -> Snapshot {
        Snapshot(
            books: books,
            sources: sources,
            excerpts: excerpts,
            settings: settings.snapshot,
            goalMinutes: goalMinutes,
            appearance: appearance,
            bookmarks: bookmarks,
            positions: positions,
            groups: groups,
            customChapters: customChapters,
            eyeCare: eyeCare
        )
    }

    /// 给 iCloud 私有库上传用的快照数据，编码策略与本机落盘一致。
    func exportedSnapshotData() throws -> Data {
        try JSONEncoder().encode(makeSnapshot())
    }

    /// 从 iCloud 拉回快照并套用到当前状态；坏数据直接抛错，不污染本机。
    func importSnapshotData(_ data: Data) throws {
        let snapshot = try JSONDecoder().decode(Snapshot.self, from: data)
        apply(snapshot)
        saveSnapshot()
    }

    /// 合并写入：连续调用只会在最后一次之后 0.6 秒真正落盘，编码在后台线程完成。
    /// 落盘走的是新存储（`LibraryStore`）：索引只写元数据，正文按书分文件，
    /// 而且只重写这次真的改过的那一本。
    func saveSnapshot() {
        let snapshot = makeSnapshot()
        let sequence = LibraryStore.shared.nextSequence()
        saveTask?.cancel()
        saveTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(600))
            } catch {
                return
            }
            await Self.persist(snapshot, sequence: sequence)
        }
    }

    /// 立即落盘，用于进入后台这类「必须马上生效」的时机。
    /// 会取消尚未触发的合并写入，并以更高序号写入，保证覆盖掉旧数据。
    func flushSnapshot() {
        saveTask?.cancel()
        saveTask = nil
        let snapshot = makeSnapshot()
        let sequence = LibraryStore.shared.nextSequence()
        LibraryStore.shared.write(snapshot, sequence: sequence, synchronously: true)
    }

    private static func persist(_ snapshot: Snapshot, sequence: Int) async {
        await Task.detached(priority: .utility) {
            LibraryStore.shared.write(snapshot, sequence: sequence)
        }.value
    }

    /// 降级读到的旧快照里，段落 ID 还是旧式（`章ID-p序号`）。
    /// 写回新结构前统一换成内容寻址 ID，并同步重映射书签与阅读位置。
    ///
    /// 不做这一步的后果：下次启动读到的是**新结构**，里面却是一批旧式 ID。
    /// 一旦某章正文有变化（净化、换源、书源重排），按序号编的 ID 就会整体错位，
    /// 用户的书签会跳到不相干的段落，而且毫无提示。
    private func normalizeParagraphIDs() {
        var map: [String: [String: String]] = [:]
        for (bookID, chapters) in customChapters {
            var updated: [Chapter] = []
            for chapter in chapters {
                let texts = chapter.paragraphs.map(\.text)
                let newIDs = ContentID.paragraphIDs(chapterID: chapter.id, paragraphs: texts)
                var paragraphs: [Paragraph] = []
                for (index, paragraph) in chapter.paragraphs.enumerated() {
                    let newID = newIDs[index]
                    map[bookID, default: [:]][paragraph.id] = newID
                    paragraphs.append(
                        Paragraph(id: newID, text: paragraph.text, comments: paragraph.comments)
                    )
                }
                updated.append(
                    Chapter(
                        id: chapter.id,
                        title: chapter.title,
                        paragraphs: paragraphs,
                        networkURL: chapter.networkURL
                    )
                )
            }
            customChapters[bookID] = updated
        }

        for (bookID, position) in positions {
            guard let mapped = map[bookID]?[position.paragraphID] else { continue }
            var updated = position
            updated.paragraphID = mapped
            positions[bookID] = updated
        }
        for index in bookmarks.indices {
            guard let anchor = bookmarks[index].paragraphID,
                  let mapped = map[bookmarks[index].bookID]?[anchor] else { continue }
            bookmarks[index].paragraphID = mapped
        }
    }

    /// 读顺序：新结构 → 旧的一体化快照 → 迁移留档 → 早期 UserDefaults。
    ///
    /// 一级读不出来才降级到下一级，绝不合并两份数据：
    /// 旧快照里的段落 ID 还是「章ID-p序号」，与新结构的内容寻址 ID 混用
    /// 会让书签跳到不相干的段落。
    private func loadSnapshot() {
        if let contents = LibraryStore.shared.read(), apply(contents) {
            return
        }

        if let data = SnapshotStore.shared.read() {
            do {
                let snapshot = try JSONDecoder().decode(Snapshot.self, from: data)
                apply(snapshot)
                // 旧快照是唯一一份数据，立刻按新结构写下来，
                // 否则下次启动还得再降级一遍。
                normalizeParagraphIDs()
                flushSnapshot()
                return
            } catch {
                // 解码失败是最难查的一类问题：文件在、内容也有，但就是读不出来。
                // 把具体是哪个字段坏了一并写到同目录的文本里，
                // 否则用户和开发者都只剩「书架空了」这一个症状。
                let detail = String(describing: error)
                print("[YeHangChuan] 快照解码失败：\(detail)")
                SnapshotStore.shared.recordDecodeFailure(detail)
                // 文件损坏：先留档再回落到默认数据，避免静默覆盖掉用户的书库。
                SnapshotStore.shared.quarantineCorruptFile()
            }
        }

        // 一次性迁移旧版 UserDefaults 快照
        guard let data = UserDefaults.standard.data(forKey: Self.legacySnapshotKey),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        apply(snapshot)
        normalizeParagraphIDs()
        flushSnapshot()
        UserDefaults.standard.removeObject(forKey: Self.legacySnapshotKey)
    }

    /// 应用新结构读到的东西。索引分区解码失败时返回 false，
    /// 让调用方降级到旧快照 —— 半个空书架比读不出来更糟。
    ///
    /// 每个分区**单独**解码：某个分区少了字段（旧版本写的、将来版本加的），
    /// 只有那一块退回默认值，不能连累整个书架。
    /// 这正是旧方案的病根 —— 一个字段读不出来，整座书库就没了。
    @discardableResult
    private func apply(_ contents: LibraryStore.Contents) -> Bool {
        let sections = YeHangCore.JSONValue.object(contents.sections)

        func decode<T: Decodable>(_ key: String, as type: T.Type) -> T? {
            guard let value = sections[key],
                  let data = try? JSONEncoder().encode(value) else { return nil }
            return try? JSONDecoder().decode(type, from: data)
        }

        var warnings: [String] = []
        // 书架本身读不出来就没法继续：这是唯一「整份失效」的分区。
        guard let storedBooks = decode("books", as: [Book].self) else {
            let reason = "书架索引里的书架数据读不出来，已回退到旧快照。"
            SnapshotStore.shared.recordDecodeFailure(reason)
            libraryStoreWarning = reason
            return false
        }

        books = storedBooks
        sources = decode("sources", as: [BookSource].self) ?? []
        excerpts = decode("excerpts", as: [Excerpt].self) ?? []
        bookmarks = decode("bookmarks", as: [Bookmark].self) ?? []
        positions = decode("positions", as: [String: ReadingPosition].self) ?? [:]
        groups = decode("groups", as: [String].self) ?? []
        goalMinutes = decode("goalMinutes", as: Int.self) ?? goalMinutes
        appearance = decode("appearance", as: AppAppearance.self) ?? appearance
        eyeCare = decode("eyeCare", as: EyeCareSettings.self) ?? eyeCare

        if let readerSettings = decode("settings", as: ReaderSnapshot.self) {
            settings.apply(readerSettings)
        } else if contents.sections["settings"] != nil {
            // 阅读设置是「可再调」的偏好，读不出来就用默认值，
            // 但要说一声 —— 用户会发现字号变了。
            warnings.append("阅读设置读不出来，已使用默认设置。")
        }

        customChapters = contents.chapters
        syncPrivateAllowList()

        // 单本书正文读不出来时，那本书退回演示数据，但必须说出来。
        if contents.recoveredFromPreviousIndex {
            warnings.append("上次保存的书架读不出来，已使用上一版索引。")
        }
        for (bookID, reason) in contents.failures.sorted(by: { $0.key < $1.key }) {
            let title = books.first { $0.id == bookID }?.title ?? bookID
            warnings.append("《\(title)》的正文读取失败：\(reason)")
        }
        if warnings.isEmpty, let error = LibraryStore.shared.lastError {
            warnings.append(error)
        }
        libraryStoreWarning = warnings.isEmpty ? nil : warnings.joined(separator: "\n")
        return true
    }

    // MARK: 书架迁移

    /// 把旧的 `snapshot.json` 搬成「索引 + 章节文件」并留档旧文件。
    ///
    /// 必须在 `loadSnapshot` **之前**跑：读在前的话，首次启动会把旧快照
    /// （段落 ID 还是「章ID-p序号」）读进内存，迁移随后写出的新结构
    /// 立刻被内存里的旧数据覆盖回去，书签就白改了。
    private func runLibraryMigration() {
        guard let directory = SnapshotStore.shared.directoryURL else { return }
        let legacyURL = directory.appendingPathComponent("snapshot.json")
        let storage = LibraryStorage(root: directory)
        do {
            let report = try LibraryMigrator.migrate(legacyURL: legacyURL, storage: storage)
            migrationReport = report
        } catch {
            // 迁移失败不影响阅读：旧快照仍在原处，读路径会降级到它。
            migrationReport = LibraryMigrationReport(
                didRun: false,
                message: (error as? LocalizedError)?.errorDescription ?? "书架迁移未完成，旧数据已保留。"
            )
        }
    }

    /// 书架是否已经用上了新结构（索引 + 章节文件）。
    var hasMigratedLibrary: Bool {
        guard let directory = SnapshotStore.shared.directoryURL else { return false }
        return FileManager.default.fileExists(atPath: LibraryStorage(root: directory).indexURL.path)
    }

    /// 书架里有多少本 / 多少章。直接从索引与清单数出来，不依赖迁移状态：
    /// 全新安装（从没跑过迁移）也应该如实显示，而不是「没有数据」。
    var migratedLibrarySummary: (books: Int, chapters: Int)? {
        guard let directory = SnapshotStore.shared.directoryURL else { return nil }
        let storage = LibraryStorage(root: directory)
        guard let index = try? storage.loadIndex() else { return nil }
        var chapters = 0
        for bookID in index.booksWithChapters {
            chapters += (try? storage.chapterIDs(bookID: bookID).count) ?? 0
        }
        return (index.booksWithChapters.count, chapters)
    }

    /// 新结构（索引 + 章节文件）在磁盘上的真实占用。没有迁移过就是 0。
    var migratedLibraryBytes: Int {
        guard let directory = SnapshotStore.shared.directoryURL else { return 0 }
        let storage = LibraryStorage(root: directory)
        guard let index = try? storage.loadIndex() else { return 0 }
        var total = (try? Data(contentsOf: storage.indexURL).count) ?? 0
        for bookID in index.booksWithChapters {
            total += (try? storage.byteCount(bookID: bookID)) ?? 0
        }
        return total
    }

    private func apply(_ snapshot: Snapshot) {
        books = snapshot.books
        sources = snapshot.sources
        excerpts = snapshot.excerpts
        settings.apply(snapshot.settings)
        goalMinutes = snapshot.goalMinutes
        appearance = snapshot.appearance
        bookmarks = snapshot.bookmarks
        positions = snapshot.positions
        groups = snapshot.groups
        customChapters = snapshot.customChapters
        eyeCare = snapshot.eyeCare
        ensureBuiltinDemoSource()
        syncPrivateAllowList()
    }

    /// 老快照里只有两条没有解析规则的书源，搜不到书。补一条完整规则的
    /// 离线示例源即可，不动用户自己已有的源。
    private func ensureBuiltinDemoSource() {
        guard !sources.contains(where: { $0.id == "source-offline-demo" }) else { return }
        sources.append(contentsOf: MockData.sources)
    }

    // MARK: Backup

    /// 按勾选范围拼出备份载荷。没勾的部分留 nil，恢复时就不会动现有数据。
    func makeBackupPayload(scopes: Set<BackupScope>) -> BackupPayload {
        BackupPayload(
            sources: scopes.contains(.sources) ? sources : nil,
            books: scopes.contains(.library) ? books : nil,
            positions: scopes.contains(.library) ? positions : nil,
            bookmarks: scopes.contains(.library) ? bookmarks : nil,
            customChapters: scopes.contains(.library) ? customChapters : nil,
            excerpts: scopes.contains(.library) ? excerpts : nil,
            readerSettings: scopes.contains(.preferences) ? settings.snapshot : nil,
            eyeCare: scopes.contains(.preferences) ? eyeCare : nil,
            appearance: scopes.contains(.preferences) ? appearance : nil,
            goalMinutes: scopes.contains(.preferences) ? goalMinutes : nil,
            groups: scopes.contains(.library) ? groups : nil
        )
    }

    /// 真实恢复：把备份里的每一块合并回当前状态，并立即落盘。
    /// 只覆盖备份里确实带了的字段，避免用半份备份清空用户的书库。
    func restore(from payload: BackupPayload) {
        if let sources = payload.sources { self.sources = sources }
        if let books = payload.books { self.books = books }
        if let positions = payload.positions { self.positions = positions }
        if let bookmarks = payload.bookmarks { self.bookmarks = bookmarks }
        if let customChapters = payload.customChapters { self.customChapters = customChapters }
        if let excerpts = payload.excerpts { self.excerpts = excerpts }
        if let readerSettings = payload.readerSettings { settings.apply(readerSettings) }
        if let eyeCare = payload.eyeCare { self.eyeCare = eyeCare }
        if let appearance = payload.appearance { self.appearance = appearance }
        if let goalMinutes = payload.goalMinutes { self.goalMinutes = goalMinutes }
        if let groups = payload.groups { self.groups = groups }
        flushSnapshot()
    }
}

// MARK: - 旧快照（只读）

/// 旧的一体化 `snapshot.json`。
///
/// **写路径已经全部迁到 `LibraryStore`**，这里只保留三件事：
/// 读旧文件（首次启动的降级来源）、把坏文件改名留档、记录解码失败原因。
/// 留着它是因为：用户从旧版本升上来时，第一份数据只存在于这个文件里，
/// 删掉这套代码等于删掉唯一的入口。
final class SnapshotStore: @unchecked Sendable {
    static let shared = SnapshotStore()

    private let queue = DispatchQueue(label: "yehangchuan.snapshot", qos: .utility)
    private let fileURL: URL?
    /// 快照所在目录，供书架迁移定位旧文件与留档。
    let directoryURL: URL?

    private init() {
        let manager = FileManager.default
        let base = manager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        var directory = base?.appendingPathComponent("YeHangChuan", isDirectory: true)
        if let directory {
            try? manager.createDirectory(at: directory, withIntermediateDirectories: true)
        } else {
            directory = base
        }
        directoryURL = directory
        fileURL = directory?.appendingPathComponent("snapshot.json")
    }

    /// 读旧快照。`snapshot.json` 不存在时回落到最近一次书架迁移留下的留档：
    /// 迁移把旧文件改名而不是删除，就是为了这一刻 —— 新结构出了任何问题，
    /// 用户的书架和正文仍然读得回来。
    func read() -> Data? {
        guard let fileURL else { return nil }
        if let data = try? Data(contentsOf: fileURL) { return data }
        guard let directory = directoryURL,
              let archived = LibraryMigrator.newestArchivedSnapshot(in: directory) else { return nil }
        return try? Data(contentsOf: archived)
    }

    /// 把无法解码的快照文件改名留档，供之后排查。
    func quarantineCorruptFile() {
        guard let fileURL else { return }
        let stamped = fileURL
            .deletingPathExtension()
            .appendingPathExtension("corrupt-\(Int(Date().timeIntervalSince1970)).json")
        try? FileManager.default.moveItem(at: fileURL, to: stamped)
    }

    /// 把解码失败的具体原因写到同目录，方便事后直接从磁盘看到，
    /// 不必连调试器或翻设备日志。
    func recordDecodeFailure(_ detail: String) {
        guard let directoryURL else { return }
        let url = directoryURL.appendingPathComponent("snapshot-decode-error.txt")
        let text = "\(Date())\n\(detail)\n"
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }
}
