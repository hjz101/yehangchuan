import SwiftUI

@main
struct YeHangChuanApp: App {
    @State private var store = AppStore()

    init() {
        // 内置离线示例书源：引擎与规则都是真的，内容由本机提供，
        // 让没有网络时也能完整验证搜索 → 目录 → 正文。
        BuiltinDemoContent.install()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .tint(Palette.accent)
        }
    }
}

struct RootView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab: AppTab = .shelf

    var body: some View {
        @Bindable var player = store.player

        ZStack {
            TabView(selection: $tab) {
                Tab("书架", systemImage: "books.vertical.fill", value: AppTab.shelf) {
                    ShelfView()
                        .eyeCareFilter(store.eyeCare)
                }

                Tab("书源", systemImage: "antenna.radiowaves.left.and.right", value: AppTab.source) {
                    SourceView()
                        .eyeCareFilter(store.eyeCare)
                }

                Tab("摘录", systemImage: "quote.opening", value: AppTab.excerpts) {
                    ExcerptView()
                        .eyeCareFilter(store.eyeCare)
                }

                Tab("统计", systemImage: "chart.bar.xaxis", value: AppTab.stats) {
                    StatsView()
                        .eyeCareFilter(store.eyeCare)
                }

                Tab("设置", systemImage: "slider.horizontal.3", value: AppTab.settings) {
                    SettingsView()
                        .eyeCareFilter(store.eyeCare)
                }
            }
            .tabBarMinimizeBehavior(.onScrollDown)
            .tabViewBottomAccessory {
                AccessoryBar()
            }
        }
        .overlay(alignment: .top) {
            if let toast = store.toast {
                ToastView(text: toast)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: store.toast)
        .preferredColorScheme(store.appearance.colorScheme)
        .fullScreenCover(isPresented: $player.showFullPlayer) {
            if let book = player.book {
                AudioPlayerView(book: book)
                    .eyeCareFilter(store.eyeCare)
            }
        }
        .onAppear {
            CarPlaySupport.store = store
            handleLaunchArguments()
        }
        .onChange(of: store.settings.snapshot) { _, _ in store.saveSnapshot() }
        .onChange(of: store.eyeCare) { _, _ in store.saveSnapshot() }
        .onChange(of: store.appearance) { _, _ in store.saveSnapshot() }
        .onChange(of: store.goalMinutes) { _, _ in store.saveSnapshot() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { store.flushSnapshot() }
        }
    }

    private func handleLaunchArguments() {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-light") { store.appearance = .light }
        if arguments.contains("-openSource") { tab = .source }
        if arguments.contains("-openSettings") { tab = .settings }
        if arguments.contains("-openExcerpts") { tab = .excerpts }
        if arguments.contains("-openStats") { tab = .stats }
        if arguments.contains("-openImport") { tab = .shelf }
        if arguments.contains("-openComic") { tab = .shelf }
        if arguments.contains("-openReader") { tab = .shelf }
        if arguments.contains("-openSync") { tab = .settings }
        if arguments.contains("-openBackup") { tab = .settings }
        if arguments.contains("-openCache") { tab = .settings }
        if arguments.contains("-openSourceDetail") { tab = .source }
        if arguments.contains("-openAI") { tab = .settings }
        if arguments.contains("-openSandbox") { tab = .settings }
        if arguments.contains("-openDiscover") { tab = .settings }
        if arguments.contains("-openVoice") { tab = .settings }
        if arguments.contains("-openCompliance") { tab = .settings }
        if arguments.contains("-openExport") { tab = .settings }
        if arguments.contains("-openSourceImport") { tab = .source }
        if arguments.contains("-eyeCare") {
            store.eyeCare.enabled = true
            store.eyeCare.warmth = 0.42
            store.eyeCare.dim = 0.08
            store.saveSnapshot()
        }
        if arguments.contains("-startAudio"), let audio = store.books.first(where: { $0.kind == .audio }) {
            store.player.load(audio)
        }
        if arguments.contains("-openPlayer"), let audio = store.books.first(where: { $0.kind == .audio }) {
            store.player.load(audio)
            store.player.showFullPlayer = true
        }
        #endif
    }
}

enum AppTab: Hashable {
    case shelf
    case source
    case excerpts
    case stats
    case settings
}

/// 标签栏上方的玻璃配件：优先显示听书播放条，否则显示继续阅读
struct AccessoryBar: View {
    @Environment(AppStore.self) private var store
    @State private var openReader: Book?

    var body: some View {
        Group {
            if let book = store.player.book {
                MiniPlayerBar(book: book)
            } else if let book = store.continueBook {
                ContinueReadingBar(book: book) {
                    if book.kind == .novel {
                        openReader = book
                    } else {
                        store.player.load(book)
                    }
                }
            } else {
                EmptyView()
            }
        }
        .fullScreenCover(item: $openReader) { book in
            ReaderView(book: book)
        }
    }
}

private struct ContinueReadingBar: View {
    let book: Book
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                BookCover(book: book, cornerRadius: 6)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 3) {
                    Text(book.title)
                        .font(.system(size: 13, weight: .semibold, design: .serif))
                        .foregroundStyle(Palette.text)
                        .lineLimit(1)

                    Text(book.lastPosition)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Palette.tertiary)
                        .lineLimit(1)
                }

                Spacer(minLength: 6)

                ProgressBar(value: book.progress, tint: Palette.accent, height: 2.5)
                    .frame(width: 54)

                Image(systemName: "play.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Palette.accent)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(scale: 0.985))
    }
}

struct MiniPlayerBar: View {
    @Environment(AppStore.self) private var store
    let book: Book

    var body: some View {
        @Bindable var player = store.player

        HStack(spacing: 11) {
            BookCover(book: book, cornerRadius: 6)
                .frame(width: 32)
                .onTapGesture { player.showFullPlayer = true }

            VStack(alignment: .leading, spacing: 4) {
                Text(book.title)
                    .font(.system(size: 13, weight: .semibold, design: .serif))
                    .foregroundStyle(Palette.text)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    ProgressBar(value: player.progress, tint: Palette.accent, height: 2)
                        .frame(width: 62)

                    Text(player.elapsedLabel)
                        .font(.system(size: 9.5, weight: .medium, design: .rounded))
                        .foregroundStyle(Palette.tertiary)
                        .monospacedDigit()
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { player.showFullPlayer = true }

            Spacer(minLength: 2)

            Button {
                player.skip(-15)
            } label: {
                Image(systemName: "gobackward.15")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Palette.text)
            }
            .buttonStyle(PressableStyle())

            Button {
                player.toggle()
            } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Palette.onAccent)
                    .frame(width: 30, height: 30)
                    .background(Palette.accent, in: Circle())
            }
            .buttonStyle(PressableStyle())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }
}

// MARK: - Full Screen Player

struct AudioPlayerView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let book: Book

    @State private var showChapterList = false
    @State private var showSleepTimer = false
    @State private var showComments = false
    @State private var exportFile: ExportedTextFile?

    var body: some View {
        @Bindable var player = store.player

        ZStack {
            AppBackdrop()

            VStack(spacing: 0) {
                header

                Spacer(minLength: 18)

                cover

                Spacer(minLength: 20)

                titleBlock

                scrubber

                transport

                Spacer(minLength: 14)

                extras
            }
            .padding(.horizontal, 26)
            .padding(.bottom, 24)
        }
        .sheet(isPresented: $showChapterList) { chapterListSheet }
        .sheet(isPresented: $showSleepTimer) { sleepTimerSheet }
        .sheet(isPresented: $showComments) { commentsSheet }
        .sheet(item: $exportFile) { file in
            ExportSheet(file: file, bookTitle: book.title)
                .presentationDetents([.fraction(0.42)])
                .presentationCornerRadius(32)
        }
        .onAppear {
            // 书架只塞了书，没有章节；这里补上，章节列表与切章才有真实数据。
            // autoplay 传 false：已经在播的别被打断，只补状态。
            store.player.load(book, chapters: store.chapters(for: book), autoplay: false)
        }
    }

    private var header: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Palette.text)
                    .glassCircle(diameter: 38)
            }
            .buttonStyle(PressableStyle())

            Spacer()

            VStack(spacing: 2) {
                Text("正在播放")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.6)
                    .foregroundStyle(Palette.tertiary)
                Text("潮汐电台 · 第 \(book.chapterCount) 期")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.secondary)
            }

            Spacer()

            Button {
                store.player.stop()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Palette.text)
                    .glassCircle(diameter: 38)
            }
            .buttonStyle(PressableStyle())
        }
        .padding(.top, 8)
    }

    private var cover: some View {
        VStack(spacing: 16) {
            BookCover(book: book, cornerRadius: 26, prominent: true)
                .frame(maxWidth: 210)

            GlassSegmented(
                items: [1.0, 1.25, 1.5, 2.0],
                title: { SpeedLabel.text($0) },
                selection: Binding(
                    get: { store.player.speed },
                    set: { store.player.speed = $0 }
                )
            )
            .frame(width: 190)
        }
    }

    private var titleBlock: some View {
        VStack(spacing: 5) {
            Text(book.title)
                .font(.system(size: 24, weight: .semibold, design: .serif))
                .foregroundStyle(Palette.text)

            Text("\(book.author) · 有声书")
                .font(.system(size: 12))
                .foregroundStyle(Palette.secondary)
        }
    }

    private var scrubber: some View {
        let player = store.player
        return VStack(spacing: 7) {
            Slider(
                value: Binding(
                    get: { player.elapsed },
                    set: { player.seek(to: $0) }
                ),
                in: 0...max(player.duration, 1)
            )
            .tint(Palette.accent)

            HStack {
                Text(player.elapsedLabel)
                Spacer()
                Text(player.remainingLabel)
            }
            .font(.system(size: 10.5, weight: .medium, design: .rounded))
            .foregroundStyle(Palette.tertiary)
            .monospacedDigit()
        }
        .padding(.top, 20)
    }

    private var transport: some View {
        let player = store.player
        return HStack(spacing: 30) {
            Button { player.skip(-15) } label: {
                Image(systemName: "gobackward.15")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(Palette.text)
            }
            .buttonStyle(PressableStyle())

            Button { player.toggle() } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(Palette.onAccent)
                    .frame(width: 72, height: 72)
                    .background(Palette.accentSolid, in: Circle())
                    .shadow(color: Palette.accentSolid.opacity(0.35), radius: 16, y: 8)
            }
            .buttonStyle(PressableStyle(scale: 0.92))

            Button { player.skip(30) } label: {
                Image(systemName: "goforward.30")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(Palette.text)
            }
            .buttonStyle(PressableStyle())
        }
        .padding(.top, 22)
    }

    private var extras: some View {
        HStack(spacing: 10) {
            glassPill("list.bullet", "章节") { showChapterList = true }
            glassPill("moon.zzz", store.player.sleepMinutes > 0 ? "定时 \(store.player.sleepMinutes)′" : "定时") {
                showSleepTimer = true
            }
            glassPill("text.bubble", "段评") { showComments = true }
            glassPill("square.and.arrow.up", "分享") { exportFile = exportAudioBook() }
        }
    }

    private func glassPill(_ symbol: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .medium))
                Text(title)
                    .font(.system(size: 10))
            }
            .foregroundStyle(Palette.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .glassSurface(cornerRadius: 18, interactive: true)
        }
        .buttonStyle(PressableStyle())
    }

    // MARK: - Player actions

    private var chapterListSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(store.player.chapters.indices, id: \.self) { index in
                        let chapter = store.player.chapters[index]
                        Button {
                            store.player.selectChapter(index)
                            showChapterList = false
                            store.showToast("已切到\(chapter.title)")
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: index == store.player.chapterIndex ? "play.circle.fill" : "play.circle")
                                    .foregroundStyle(index == store.player.chapterIndex ? Palette.accent : Palette.tertiary)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(chapter.title)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(Palette.text)
                                    Text("\(chapter.paragraphs.count) 段")
                                        .font(.system(size: 10))
                                        .foregroundStyle(Palette.tertiary)
                                }
                                Spacer()
                            }
                            .padding(14)
                            .glassSurface(cornerRadius: 16, interactive: true)
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
                .padding(18)
            }
            .navigationTitle("章节")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { showChapterList = false }.fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationCornerRadius(32)
    }

    private var sleepTimerSheet: some View {
        NavigationStack {
            VStack(spacing: 10) {
                ForEach([0, 5, 15, 30, 60], id: \.self) { minutes in
                    Button {
                        store.player.setSleepTimer(minutes)
                        showSleepTimer = false
                        store.showToast(minutes == 0 ? "已关闭睡眠定时" : "\(minutes) 分钟后停止播放")
                    } label: {
                        HStack {
                            Text(minutes == 0 ? "不开启" : "\(minutes) 分钟")
                                .font(.system(size: 13))
                            Spacer()
                            if store.player.sleepMinutes == minutes {
                                Image(systemName: "checkmark").foregroundStyle(Palette.accent)
                            }
                        }
                        .foregroundStyle(Palette.text)
                        .padding(14)
                        .glassSurface(cornerRadius: 16, interactive: true)
                    }
                    .buttonStyle(PressableStyle())
                }
            }
            .padding(18)
            .navigationTitle("睡眠定时")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { showSleepTimer = false }.fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.fraction(0.45)])
        .presentationCornerRadius(32)
    }

    private var commentsSheet: some View {
        let comments = store.player.currentChapter?.paragraphs.flatMap(\.comments) ?? []
        return NavigationStack {
            Group {
                if comments.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "text.bubble")
                            .font(.system(size: 34, weight: .light))
                            .foregroundStyle(Palette.tertiary)
                        Text("本章暂无段评")
                            .font(.system(size: 13))
                            .foregroundStyle(Palette.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(spacing: 10) {
                            ForEach(comments) { comment in
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text(comment.author)
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundStyle(Palette.accent)
                                        Spacer()
                                        Text("\(comment.likes) 赞")
                                            .font(.system(size: 10))
                                            .foregroundStyle(Palette.tertiary)
                                    }
                                    Text(comment.text)
                                        .font(.system(size: 13))
                                        .foregroundStyle(Palette.text)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(14)
                                .glassSurface(cornerRadius: 16)
                            }
                        }
                        .padding(18)
                    }
                }
            }
            .navigationTitle("段评")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { showComments = false }.fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationCornerRadius(32)
    }

    /// 把这本书的章节正文导出成 TXT，交给 ShareLink 面板分享。
    private func exportAudioBook() -> ExportedTextFile? {
        let all = store.chapters(for: book)
        guard !all.isEmpty else { return nil }
        var text = book.title + "\n"
        if !book.author.isEmpty { text += "作者：\(book.author)\n" }
        text += "\n"
        for chapter in all {
            text += chapter.title + "\n\n"
            let body = chapter.paragraphs.map(\.text).joined(separator: "\n")
            text += (body.isEmpty ? "【演示音轨，无正文】" : body) + "\n\n"
        }
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("YeHangExports", isDirectory: true)
        let folder = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let file = folder.appendingPathComponent("\(book.title).txt")
            try text.write(to: file, atomically: true, encoding: .utf8)
            return ExportedTextFile(url: file, chapterCount: all.count, emptyChapters: 0)
        } catch {
            store.showToast("导出失败：\(error.localizedDescription)")
            return nil
        }
    }
}
