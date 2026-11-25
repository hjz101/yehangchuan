import SwiftUI
import Observation

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
}

enum SourceKind: String {
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

struct Paragraph: Identifiable, Hashable {
    let id: String
    let text: String
    var comments: [SegmentComment] = []
}

struct SegmentComment: Identifiable, Hashable {
    let id: String
    let author: String
    let text: String
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

enum ReaderTheme: String, CaseIterable, Identifiable {
    case day = "日间"
    case paper = "羊皮纸"
    case night = "夜间"

    var id: String { rawValue }

    var background: Color {
        switch self {
        case .day: Theme.paper
        case .paper: Color(hex: 0xEDE0C6)
        case .night: Color(hex: 0x14171C)
        }
    }

    var text: Color {
        switch self {
        case .day: Color(hex: 0x241F19)
        case .paper: Color(hex: 0x3B2E1E)
        case .night: Color(hex: 0xC7C2B7)
        }
    }

    var secondary: Color {
        switch self {
        case .day: Color(hex: 0x8A7C68)
        case .paper: Color(hex: 0x8C7656)
        case .night: Color(hex: 0x7C786F)
        }
    }

    var isDark: Bool { self == .night }
}

enum PageMode: String, CaseIterable, Identifiable {
    case slide = "横滑"
    case scroll = "上下滚动"

    var id: String { rawValue }
}

@MainActor
@Observable
final class ReaderSettings {
    var fontSize: Double = 18
    var lineSpacing: Double = 0.7
    var theme: ReaderTheme = .day
    var pageMode: PageMode = .slide
    var hideSourceComments = false
}

@MainActor
@Observable
final class AppStore {
    var books: [Book] = MockData.books
    var sources: [BookSource] = MockData.sources
    var settings = ReaderSettings()
    var toast: String?

    var continueBook: Book? {
        books.first { $0.progress > 0 && !$0.isFinished }
    }

    func updateProgress(bookID: String, progress: Double, position: String) {
        guard let index = books.firstIndex(where: { $0.id == bookID }) else { return }
        books[index].progress = min(max(progress, 0), 0.99)
        books[index].lastPosition = position
    }

    func toggleFinished(_ bookID: String) {
        guard let index = books.firstIndex(where: { $0.id == bookID }) else { return }
        books[index].isFinished.toggle()
        books[index].progress = books[index].isFinished ? 1 : 0.01
        books[index].lastPosition = books[index].isFinished ? "已读完" : "未开始"
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

    func showToast(_ text: String) {
        toast = text
        Task {
            try? await Task.sleep(for: .seconds(2))
            if toast == text { toast = nil }
        }
    }
}

enum Paginator {
    static func pages(for chapters: [Chapter], fontSize: Double) -> [ReaderPage] {
        let capacity = max(70, Int(103_680 / (fontSize * fontSize)))
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
