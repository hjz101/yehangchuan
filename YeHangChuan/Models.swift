import SwiftUI
import Observation

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

    var unitLabel: String { kind == .comic ? "话" : "章" }
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
}

struct SegmentComment: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let author: String
    let text: String
    var likes: Int = 0
    var liked: Bool = false
    var minutesAgo: Int = 0
}

struct Chapter: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let title: String
    var paragraphs: [Paragraph]
}

struct ReaderPage: Identifiable {
    let id: String
    let chapterTitle: String
    let paragraphs: [Paragraph]
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
}

struct ImportDraft: Identifiable {
    let id = UUID()
    var title: String
    var author: String
    var kind: BookKind
    var detail: String
    var chapters: [Chapter]
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
    var speed: Double = 1
    var showFullPlayer = false

    @ObservationIgnored private var ticker: Task<Void, Never>?

    var progress: Double {
        duration <= 0 ? 0 : min(max(elapsed / duration, 0), 1)
    }

    var elapsedLabel: String { Self.label(elapsed) }
    var durationLabel: String { Self.label(duration) }
    var remainingLabel: String { "-" + Self.label(max(duration - elapsed, 0)) }

    func load(_ book: Book, autoplay: Bool = true) {
        if self.book?.id == book.id {
            if autoplay && !isPlaying { resume() }
            return
        }
        self.book = book
        duration = Self.seconds(book.duration) ?? 340
        elapsed = min(duration * 0.22, duration - 8)
        isPlaying = autoplay
        if autoplay { startTicking() } else { ticker?.cancel() }
    }

    func toggle() {
        isPlaying ? pause() : resume()
    }

    func resume() {
        guard book != nil else { return }
        isPlaying = true
        startTicking()
    }

    func pause() {
        isPlaying = false
        ticker?.cancel()
    }

    func seek(to value: Double) {
        elapsed = min(max(value, 0), duration)
    }

    func skip(_ seconds: Double) {
        elapsed = min(max(elapsed + seconds, 0), duration)
    }

    func stop() {
        pause()
        book = nil
        elapsed = 0
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

// MARK: - Store

@MainActor
@Observable
final class AppStore {
    var books: [Book] = MockData.books
    var sources: [BookSource] = MockData.sources
    var settings = ReaderSettings()
    var excerpts: [Excerpt] = MockData.excerpts
    var days: [DayStat] = MockData.dayStats
    var goalMinutes: Int = 60
    var appearance: AppAppearance = .dark
    var player = AudioPlayer()
    var speech = SpeechPlayer()
    var backend = MockBackend()
    var bookmarks: [Bookmark] = []
    var positions: [String: ReadingPosition] = [:]
    var groups: [String] = ["夜读", "待读"]
    var customChapters: [String: [Chapter]] = [:]
    var eyeCare = EyeCareSettings()
    var toast: String?
    var syncSheetRequested = false

    private static let legacySnapshotKey = "yehangchuan.snapshot.v5"

    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var pendingSnapshot: Snapshot?
    @ObservationIgnored private var pendingSequence: Int = 0

    init() {
        loadSnapshot()
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
        showToast("已从书架移除")
        saveSnapshot()
    }

    func addToShelf(_ book: Book) {
        guard !books.contains(where: { $0.id == book.id }) else { return }
        books.insert(book, at: 0)
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

    func addSource(name: String, kind: SourceKind) {
        let source = BookSource(
            id: UUID().uuidString,
            name: name.isEmpty ? "未命名书源" : name,
            host: kind == .js ? "script.local" : "custom.example.com",
            kind: kind,
            enabled: false,
            bookCount: 0
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
        saveSnapshot()
    }

    func removeSource(_ sourceID: String) {
        sources.removeAll { $0.id == sourceID }
        showToast("已删除书源")
        saveSnapshot()
    }

    func updateSource(_ source: BookSource) {
        guard let index = sources.firstIndex(where: { $0.id == source.id }) else { return }
        sources[index] = source
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

    func importBook(_ draft: ImportDraft) {
        let book = Book(
            id: "import-\(UUID().uuidString.prefix(8))",
            title: draft.title,
            author: draft.author,
            kind: draft.kind,
            coverStyle: abs(draft.title.hashValue) % 6,
            chapterCount: draft.chapters.count,
            progress: 0,
            lastPosition: "未开始",
            pageCount: draft.kind == .comic ? max(draft.chapters.count * 8, 20) : nil,
            duration: draft.kind == .audio ? "12:30" : nil,
            isFinished: false,
            group: groups.first,
            sourceID: "local"
        )
        customChapters[book.id] = draft.chapters
        books.insert(book, at: 0)
        showToast("已导入《\(book.title)》· \(draft.chapters.count) 章")
        saveSnapshot()
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

    func switchSource(bookID: String, to sourceID: String) {
        guard let index = books.firstIndex(where: { $0.id == bookID }) else { return }
        books[index].sourceID = sourceID
        let name = sources.first { $0.id == sourceID }?.name ?? "本地"
        showToast("已切换到「\(name)」，阅读位置保留")
        saveSnapshot()
    }

    // MARK: Bookmarks

    func bookmarks(for bookID: String) -> [Bookmark] {
        bookmarks.filter { $0.bookID == bookID }.sorted { $0.createdAt > $1.createdAt }
    }

    func isBookmarked(bookID: String, pageIndex: Int) -> Bool {
        bookmarks.contains { $0.bookID == bookID && $0.pageIndex == pageIndex }
    }

    @discardableResult
    func toggleBookmark(book: Book, chapterTitle: String, pageIndex: Int, progress: Double) -> Bool {
        if let existing = bookmarks.firstIndex(where: { $0.bookID == book.id && $0.pageIndex == pageIndex }) {
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
                createdAt: Date()
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

    /// 合并写入：连续调用只会在最后一次之后 0.6 秒真正落盘，编码在后台线程完成。
    /// 翻页这类高频写回不再每次都序列化整座书库。
    func saveSnapshot() {
        let snapshot = makeSnapshot()
        let sequence = SnapshotStore.shared.nextSequence()
        pendingSnapshot = snapshot
        pendingSequence = sequence
        saveTask?.cancel()
        saveTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(600))
            } catch {
                return
            }
            await Self.persist(snapshot, sequence: sequence)
            if pendingSequence == sequence { pendingSnapshot = nil }
        }
    }

    /// 立即落盘，用于进入后台这类「必须马上生效」的时机。
    /// 会取消尚未触发的合并写入，并以更高序号写入，保证覆盖掉旧数据。
    func flushSnapshot() {
        saveTask?.cancel()
        saveTask = nil
        pendingSnapshot = nil
        let snapshot = makeSnapshot()
        let sequence = SnapshotStore.shared.nextSequence()
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        SnapshotStore.shared.write(data, sequence: sequence)
    }

    private static func persist(_ snapshot: Snapshot, sequence: Int) async {
        await Task.detached(priority: .utility) {
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            SnapshotStore.shared.write(data, sequence: sequence)
        }.value
    }

    private func loadSnapshot() {
        if let data = SnapshotStore.shared.read() {
            if let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) {
                apply(snapshot)
                return
            }
            // 文件损坏：先留档再回落到默认数据，避免静默覆盖掉用户的书库。
            SnapshotStore.shared.quarantineCorruptFile()
        }

        // 一次性迁移旧版 UserDefaults 快照
        guard let data = UserDefaults.standard.data(forKey: Self.legacySnapshotKey),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        apply(snapshot)
        if let encoded = try? JSONEncoder().encode(snapshot) {
            SnapshotStore.shared.write(encoded, sequence: SnapshotStore.shared.nextSequence())
        }
        UserDefaults.standard.removeObject(forKey: Self.legacySnapshotKey)
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
    }
}

// MARK: - Paginator

enum Paginator {
    /// 按屏幕实际可用宽高估算每页容量，避免出现半页空白
    static func pages(
        for chapters: [Chapter],
        fontSize: Double,
        lineSpacing: Double,
        viewport: CGSize = CGSize(width: 390, height: 844),
        sideMargin: Double = 28
    ) -> [ReaderPage] {
        let horizontalInset = sideMargin * 2
        let verticalChrome: Double = 78 + 150   // 顶部页眉 + 底部浮层避让

        let lineHeight = fontSize * (1 + lineSpacing)
        let usableWidth = max(Double(viewport.width) - horizontalInset, 200)
        let usableHeight = max(Double(viewport.height) - verticalChrome, 260)

        let charsPerLine = usableWidth / fontSize
        let linesPerPage = usableHeight / lineHeight
        // 0.88 用于吸收标点挤压、段首缩进与段间距带来的额外占位
        let capacity = max(120, Int(charsPerLine * linesPerPage * 0.88))

        var result: [ReaderPage] = []

        for (chapterIndex, chapter) in chapters.enumerated() {
            var buffer: [Paragraph] = []
            var length = 0

            for paragraph in chapter.paragraphs {
                let count = max(1, paragraph.text.count)
                if !buffer.isEmpty && length + count > capacity {
                    result.append(
                        ReaderPage(
                            id: "\(chapterIndex)-\(result.count)",
                            chapterTitle: chapter.title,
                            paragraphs: buffer
                        )
                    )
                    buffer.removeAll()
                    length = 0
                }
                buffer.append(paragraph)
                length += count
            }

            if !buffer.isEmpty {
                result.append(
                    ReaderPage(
                        id: "\(chapterIndex)-\(result.count)",
                        chapterTitle: chapter.title,
                        paragraphs: buffer
                    )
                )
            }
        }
        return result
    }
}

// MARK: - Snapshot storage

/// 快照落盘。放在 Application Support 下的独立文件里，用原子写；
/// 序号保证后发起的写入覆盖先发起的，避免后台编码完成后把新数据盖回旧数据。
final class SnapshotStore: @unchecked Sendable {
    static let shared = SnapshotStore()

    private let queue = DispatchQueue(label: "yehangchuan.snapshot", qos: .utility)
    private var lastWrittenSequence = 0
    private var lastSequence = 0
    private let fileURL: URL?

    private init() {
        let manager = FileManager.default
        let base = manager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        var directory = base?.appendingPathComponent("YeHangChuan", isDirectory: true)
        if let directory {
            try? manager.createDirectory(at: directory, withIntermediateDirectories: true)
        } else {
            directory = base
        }
        fileURL = directory?.appendingPathComponent("snapshot.json")
    }

    func nextSequence() -> Int {
        queue.sync {
            lastSequence += 1
            return lastSequence
        }
    }

    func read() -> Data? {
        guard let fileURL else { return nil }
        return try? Data(contentsOf: fileURL)
    }

    func write(_ data: Data, sequence: Int) {
        queue.async { [fileURL, weak self] in
            guard let self, let fileURL else { return }
            guard sequence > lastWrittenSequence else { return }
            lastWrittenSequence = sequence
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    /// 把无法解码的快照文件改名留档，供之后排查，同时让下一次写入从干净状态开始。
    func quarantineCorruptFile() {
        guard let fileURL else { return }
        let stamped = fileURL
            .deletingPathExtension()
            .appendingPathExtension("corrupt-\(Int(Date().timeIntervalSince1970)).json")
        try? FileManager.default.moveItem(at: fileURL, to: stamped)
    }
}
