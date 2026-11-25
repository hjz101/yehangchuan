import SwiftUI

@main
struct YeHangChuanApp: App {
    @State private var store = AppStore()

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
    @State private var tab: AppTab = .shelf

    var body: some View {
        @Bindable var player = store.player

        ZStack {
            TabView(selection: $tab) {
                Tab("书架", systemImage: "books.vertical.fill", value: AppTab.shelf) {
                    ShelfView()
                }

                Tab("书源", systemImage: "antenna.radiowaves.left.and.right", value: AppTab.source) {
                    SourceView()
                }

                Tab("摘录", systemImage: "quote.opening", value: AppTab.excerpts) {
                    ExcerptView()
                }

                Tab("统计", systemImage: "chart.bar.xaxis", value: AppTab.stats) {
                    StatsView()
                }

                Tab("设置", systemImage: "slider.horizontal.3", value: AppTab.settings) {
                    SettingsView()
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
            }
        }
        .onAppear(perform: handleLaunchArguments)
    }

    private func handleLaunchArguments() {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-light") { store.appearance = .light }
        if arguments.contains("-openSource") { tab = .source }
        if arguments.contains("-openSettings") { tab = .settings }
        if arguments.contains("-openExcerpts") { tab = .excerpts }
        if arguments.contains("-openStats") { tab = .stats }
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
                title: { $0 == 1.0 ? "1×" : String(format: "%.2g×", $0) },
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
            glassPill("list.bullet", "章节")
            glassPill("moon.zzz", "定时")
            glassPill("text.bubble", "段评")
            glassPill("square.and.arrow.up", "分享")
        }
    }

    private func glassPill(_ symbol: String, _ title: String) -> some View {
        Button {
            store.showToast("\(title)将在正式版接入")
        } label: {
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
}
