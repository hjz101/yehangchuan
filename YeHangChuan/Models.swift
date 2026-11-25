import SwiftUI
import Observation

// MARK: - Book

enum BookKind: String, CaseIterable, Identifiable {
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

struct Book: Identifiable, Hashable {
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

    var unitLabel: String { kind == .comic ? "话" : "章" }
}

// MARK: - Source

enum SourceKind: String, CaseIterable {
    case json = "JSON"
    case js = "JS"
}

struct BookSource: Identifiable, Hashable {
    let id: String
    var name: String
    var host: String
    var kind: SourceKind
    var enabled: Bool
    var bookCount: Int
}

// MARK: - Reading Content

struct Paragraph: Identifiable, Hashable {
    let id: String
    let text: String
    var comments: [SegmentComment] = []
}

struct SegmentComment: Identifiable, Hashable {
    let id: String
    let author: String
    let text: String
    var likes: Int = 0
    var liked: Bool = false
    var minutesAgo: Int = 0
}

struct Chapter: Identifiable, Hashable {
    let id: String
    let title: String
    let paragraphs: [Paragraph]
}

struct ReaderPage: Identifiable {
    let id: String
    let chapterTitle: String
    let paragraphs: [Paragraph]
}

// MARK: - Appearance

enum AppAppearance: String, CaseIterable, Identifiable {
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

enum ReaderTheme: String, CaseIterable, Identifiable {
    case day = "日间"
    case paper = "羊皮纸"
    case voyage = "夜航"
    case night = "夜间"

    var id: String { rawValue }

    var background: Color {
        switch self {
        case .day: Color(hex: 0xFAF7F1)
        case .paper: Color(hex: 0xF0E4CB)
        case .voyage: Color(hex: 0x0D1B2A)
        case .night: Color(hex: 0x101013)
        }
    }

    var backgroundDeep: Color {
        switch self {
        case .day: Color(hex: 0xEFE9DD)
        case .paper: Color(hex: 0xE2D1B0)
        case .voyage: Color(hex: 0x081119)
        case .night: Color(hex: 0x08080A)
        }
    }

    var text: Color {
        switch self {
        case .day: Color(hex: 0x1E1B16)
        case .paper: Color(hex: 0x3A2D1D)
        case .voyage: Color(hex: 0xD9E2EC)
        case .night: Color(hex: 0xC9C4BA)
        }
    }

    var secondary: Color {
        switch self {
        case .day: Color(hex: 0x877B69)
        case .paper: Color(hex: 0x8C7656)
        case .voyage: Color(hex: 0x6E869D)
        case .night: Color(hex: 0x7A766D)
        }
    }

    var accent: Color {
        switch self {
        case .day: Color(hex: 0xB6402A)
        case .paper: Color(hex: 0x96502C)
        case .voyage: Color(hex: 0xE8A76A)
        case .night: Color(hex: 0xB49C7E)
        }
    }

    var isDark: Bool { self == .voyage || self == .night }

    var symbol: String {
        switch self {
        case .day: "sun.max"
        case .paper: "text.book.closed"
        case .voyage: "moon.stars"
        case .night: "moon"
        }
    }
}

enum PageMode: String, CaseIterable, Identifiable {
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

@MainActor
@Observable
final class ReaderSettings {
    var fontSize: Double = 18
    var lineSpacing: Double = 0.75
    var theme: ReaderTheme = .voyage
    var pageMode: PageMode = .slide
    var hideSourceComments = false
}

// MARK: - Excerpts

struct Excerpt: Identifiable, Hashable {
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
    var toast: String?

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

    func updateProgress(bookID: String, progress: Double, position: String) {
        guard let index = books.firstIndex(where: { $0.id == bookID }) else { return }
        books[index].progress = min(max(progress, 0), 0.99)
        books[index].lastPosition = position
    }

    func toggleFinished(_ bookID: String) {
        guard let index = books.firstIndex(where: { $0.id == bookID }) else { return }
        books[index].isFinished.toggle()
        books[index].progress = books[index].isFinished ? 1 : 0.02
        books[index].lastPosition = books[index].isFinished ? "已读完" : "未开始"
        showToast(books[index].isFinished ? "已标记为读完" : "已移回在读")
    }

    func removeBook(_ bookID: String) {
        books.removeAll { $0.id == bookID }
        showToast("已从书架移除")
    }

    func addToShelf(_ book: Book) {
        guard !books.contains(where: { $0.id == book.id }) else { return }
        books.insert(book, at: 0)
        showToast("已加入书架：\(book.title)")
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
            enabled: true,
            bookCount: 0
        )
        sources.insert(source, at: 0)
        showToast("已添加书源：\(source.name)")
    }

    func setSourceEnabled(_ sourceID: String, enabled: Bool) {
        guard let index = sources.firstIndex(where: { $0.id == sourceID }) else { return }
        sources[index].enabled = enabled
    }

    func removeSource(_ sourceID: String) {
        sources.removeAll { $0.id == sourceID }
        showToast("已删除书源")
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
    }

    func updateNote(_ excerptID: String, note: String) {
        guard let index = excerpts.firstIndex(where: { $0.id == excerptID }) else { return }
        excerpts[index].note = note
    }

    func toggleExcerptLike(_ excerptID: String) {
        guard let index = excerpts.firstIndex(where: { $0.id == excerptID }) else { return }
        excerpts[index].liked.toggle()
    }

    func removeExcerpt(_ excerptID: String) {
        excerpts.removeAll { $0.id == excerptID }
        showToast("已删除摘录")
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

    // MARK: Toast

    func showToast(_ text: String) {
        toast = text
        Task {
            try? await Task.sleep(for: .seconds(2))
            if toast == text { toast = nil }
        }
    }
}

// MARK: - Paginator

enum Paginator {
    /// 按屏幕实际可用宽高估算每页容量，避免出现半页空白
    static func pages(
        for chapters: [Chapter],
        fontSize: Double,
        lineSpacing: Double,
        viewport: CGSize = CGSize(width: 390, height: 844)
    ) -> [ReaderPage] {
        let horizontalInset: Double = 56
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
