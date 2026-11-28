import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(AppStore.self) private var store

    /// 缓存与空间：三类缓存都要数一遍磁盘目录。
    /// 这个数**不能在 body 里现算**：一次 body 求值就枚举上百个文件，
    /// 切到设置页时会明显顿一下。改成进页面后异步算一次，算完再显示。
    static func storageLabel(bytes: Int) -> String {
        String(format: "%.1f MB", Double(bytes) / 1_048_576)
    }

    /// 版本号从 Info.plist 读，别在界面里手写一份会跟工程设置对不上的字符串。
    static let versionLabel: String = {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let system = UIDevice.current.systemVersion
        return "\(version) · iOS \(system)"
    }()

    @State private var showReaderSettings = false
    @State private var showDistribution = false
    @State private var showGoal = false
    @State private var showImport = false
    @State private var showSync = false
    @State private var showBackup = false
    @State private var showCache = false
    @State private var showNetworkLogs = false
    @State private var showExport = false
    @State private var showAI = false
    @State private var showSandbox = false
    @State private var showDiscover = false
    @State private var showVoice = false
    @State private var showCompliance = false
    @State private var showEyeCare = false
    @State private var showThemeEditor = false
    @State private var readerForFrameAdjust: Book?
    /// 各类缓存的真实占用，进页面后异步统计一次。
    /// nil 表示还没算出来，这时候显示「计算中」而不是显示一个假的 0。
    @State private var cacheUsage: CacheUsage.Snapshot?

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackdrop()

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 18) {
                            profileCard

                            group("阅读") {
                                Button {
                                    showReaderSettings = true
                                } label: {
                                    SettingsRow(
                                        title: "阅读偏好",
                                        value: "\(Int(store.settings.fontSize)) pt · \(store.settings.theme.rawValue)",
                                        systemImage: "textformat.size"
                                    )
                                }
                                .buttonStyle(.plain)

                                Button {
                                    showGoal = true
                                } label: {
                                    SettingsRow(
                                        title: "每日目标",
                                        value: "\(store.goalMinutes) 分钟",
                                        systemImage: "target"
                                    )
                                }
                                .buttonStyle(.plain)

                                Toggle(isOn: Binding(
                                    get: { store.showExcerptsTab },
                                    set: { value in
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            store.showExcerptsTab = value
                                        }
                                        store.saveSnapshot()
                                    }
                                )) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("显示「摘录」标签")
                                            .font(.system(size: 15))
                                            .foregroundStyle(Palette.text)
                                        Text("关掉后底部只留四个标签；摘录数据不会删除")
                                            .font(.system(size: 10.5))
                                            .foregroundStyle(Palette.tertiary)
                                    }
                                }
                                .tint(Palette.accent)
                                .padding(.horizontal, 15)
                                .padding(.vertical, 10)

                                // P3-03：入口统一为「外观与主题」，护眼/主题为其子项。
                                Button {
                                    showThemeEditor = true
                                } label: {
                                    SettingsRow(
                                        title: "主题",
                                        value: ThemeStore.shared.activeTheme.name,
                                        systemImage: "paintpalette",
                                        iconTint: Palette.accent,
                                        isLast: false
                                    )
                                }
                                .buttonStyle(.plain)

                                Button {
                                    showEyeCare = true
                                } label: {
                                    SettingsRow(
                                        title: "护眼与外观",
                                        value: store.eyeCare.enabled
                                            ? "\(store.appearance.rawValue) · 暖度 \(Int(store.eyeCare.warmth * 100))%"
                                            : "\(store.appearance.rawValue) · 护眼关闭",
                                        systemImage: "leaf",
                                        iconTint: Palette.jade,
                                        isLast: true
                                    )
                                }
                                .buttonStyle(.plain)
                            }

                            group("数据") {
                                Button {
                                    showImport = true
                                } label: {
                                    SettingsRow(
                                        title: "导入本地书",
                                        value: "TXT / EPUB / CBZ / ZIP",
                                        systemImage: "square.and.arrow.down"
                                    )
                                }
                                .buttonStyle(.plain)

                                Button {
                                    showBackup = true
                                } label: {
                                    SettingsRow(
                                        title: "本地备份",
                                        value: "\(store.backup.backups.count) 份",
                                        systemImage: "externaldrive.badge.timemachine"
                                    )
                                }
                                .buttonStyle(.plain)

                                Button {
                                    showCache = true
                                } label: {
                                    SettingsRow(
                                        title: "缓存与空间",
                                        value: cacheUsage == nil
                                            ? "计算中…"
                                            : Self.storageLabel(
                                                bytes: (cacheUsage?.chapterBytes ?? 0)
                                                    + (cacheUsage?.imageBytes ?? 0)
                                                    + (cacheUsage?.audioBytes ?? 0)
                                            ),
                                        systemImage: "internaldrive"
                                    )
                                }
                                .buttonStyle(.plain)

                                Button {
                                    showExport = true
                                } label: {
                                    SettingsRow(
                                        title: "导出书架数据",
                                        value: "JSON / Markdown",
                                        systemImage: "square.and.arrow.up",
                                        isLast: true
                                    )
                                }
                                .buttonStyle(.plain)
                            }

                            group("实验室") {
                                LazyVGrid(
                                    columns: [GridItem(.flexible(), spacing: 9), GridItem(.flexible(), spacing: 9)],
                                    spacing: 9
                                ) {
                                    labTile("AI 阅读助手", "摘要 · 封面 · 语音", "sparkles", Palette.accent) {
                                        showAI = true
                                    }
                                    labTile("JS 书源沙箱", "不预装脚本 · 私网拦截", "curlybraces.square", Palette.jade) {
                                        showSandbox = true
                                    }
                                    labTile("在线发现", "只用已启用书源", "safari", Palette.blue) {
                                        showDiscover = true
                                    }
                                    labTile("声音实验室", "多角色 · 后台播放", "waveform", Palette.sand) {
                                        showVoice = true
                                    }
                                }
                                .padding(9)
                            }

                            group("关于") {
                                Button {
                                    showSync = true
                                } label: {
                                    SettingsRow(
                                        title: "账户与同步",
                                        value: "\(store.backend.account.title) · \(store.backend.syncState.title)",
                                        systemImage: "person.crop.circle"
                                    )
                                }
                                .buttonStyle(.plain)

                                Button {
                                    showCompliance = true
                                } label: {
                                    SettingsRow(
                                        title: "隐私与内容来源",
                                        value: "无内置内容 · 无预装书源",
                                        systemImage: "hand.raised"
                                    )
                                }
                                .buttonStyle(.plain)

                                Button {
                                    showDistribution = true
                                } label: {
                                    SettingsRow(
                                        title: "安装与更新",
                                        value: "TestFlight · 免费",
                                        systemImage: "shippingbox"
                                    )
                                }
                                .buttonStyle(.plain)

                                Button {
                                    showNetworkLogs = true
                                } label: {
                                    SettingsRow(
                                        title: "网络日志",
                                        // 这里原来显示的是演示后端的开关状态，与真实网络无关。
                                        // 改成如实反映「记录是开着还是关着」。
                                        value: store.diagnostics.isRecording ? "记录中" : "未记录",
                                        systemImage: "network"
                                    )
                                }
                                .buttonStyle(.plain)

                                SettingsRow(
                                    title: "版本",
                                    value: Self.versionLabel,
                                    systemImage: "info.circle",
                                    showsChevron: false,
                                    isLast: true
                                )
                            }

                            Text("夜航船 · 本地优先的阅读器")
                                .font(.system(size: 10.5, design: .serif))
                                .foregroundStyle(Palette.tertiary)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 4)
                            .id("settingsFooter")
                        }
                        .padding(.horizontal, 18)
                        .padding(.top, 6)
                        .padding(.bottom, 40)
                    }
                    .scrollIndicators(.hidden)
                    .task {
                        // 只在第一次进设置页时算一次；后面再进来沿用结果。
                        guard cacheUsage == nil else { return }
                        cacheUsage = await CacheUsage.snapshot()
                    }
                    .onAppear {
                        #if DEBUG
                        // 用来截图核对页面底部，正常使用不会触发。
                        if ProcessInfo.processInfo.arguments.contains("-settingsBottom") {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                                withAnimation(nil) { proxy.scrollTo("settingsFooter", anchor: .bottom) }
                            }
                        }
                        #endif
                    }
                }
            }
            .navigationTitle("设置")
            .toolbarTitleDisplayMode(.inlineLarge)
        }
        .sheet(isPresented: $showThemeEditor) {
            ThemeEditor(theme: ThemeStore.shared.activeTheme) { applied in
                ThemeStore.shared.catalog.themes.removeAll { $0.id == applied.id }
                ThemeStore.shared.catalog.themes.append(applied)
                ThemeStore.shared.selectTheme(id: applied.id)
            }
            .presentationDetents([.large])
            .presentationCornerRadius(38)
        }
        .sheet(isPresented: $showEyeCare) {
            EyeCareSheet()
                .presentationDetents([.large])
                .presentationCornerRadius(38)
                // sheet 是独立宿主，根视图的护眼层盖不进来；它自己也要跟随明暗。
                .themedChrome(store)
        }
        .sheet(isPresented: $showReaderSettings) {
            ReaderSettingsSheet(
                settings: store.settings,
                onAdjustFrame: {
                    // 正文不在这一屏，抓手没法拖；直接送读者进最近在读的书。
                    showReaderSettings = false
                    readerForFrameAdjust = store.continueBook
                        ?? store.books.first { $0.kind == .novel && $0.progress > 0 }
                        ?? store.books.first { $0.kind == .novel }
                }
            )
                .presentationDetents([.large])
                .presentationCornerRadius(38)
                .themedChrome(store)
        }
        .fullScreenCover(item: $readerForFrameAdjust) { book in
            ReaderView(book: book, startInFrameAdjust: true)
        }
        .sheet(isPresented: $showDistribution) {
            DistributionSheet()
                .presentationDetents([.medium])
                .presentationCornerRadius(38)
                .themedChrome(store)
        }
        .sheet(isPresented: $showGoal) {
            GoalSheet(minutes: store.goalMinutes) { value in
                store.goalMinutes = value
                store.saveSnapshot()
                store.showToast("每日目标已设为 \(value) 分钟")
            }
            .presentationDetents([.height(320)])
            .presentationCornerRadius(38)
            .themedChrome(store)
        }
        .sheet(isPresented: $showImport) {
            SmartImportSheet()
                .presentationDetents([.large])
                .presentationCornerRadius(38)
                .themedChrome(store)
        }
        .sheet(isPresented: $showSync) {
            SyncCenterSheet()
                .presentationDetents([.large])
                .presentationCornerRadius(38)
                .themedChrome(store)
        }
        .sheet(isPresented: $showBackup) {
            BackupSheet()
                .presentationDetents([.large])
                .presentationCornerRadius(38)
                .themedChrome(store)
        }
        .sheet(isPresented: $showCache) {
            CacheSheet()
                .presentationDetents([.medium, .large])
                .presentationCornerRadius(38)
                .themedChrome(store)
        }
        .sheet(isPresented: $showNetworkLogs) {
            NetworkLogSheet()
                .presentationDetents([.medium, .large])
                .presentationCornerRadius(38)
                .themedChrome(store)
        }
        .sheet(isPresented: $showExport) {
            DataExportSheet()
                .presentationDetents([.large])
                .presentationCornerRadius(38)
                .themedChrome(store)
        }
        .sheet(isPresented: $showAI) {
            AIStudioSheet()
                .presentationDetents([.large])
                .presentationCornerRadius(38)
                .themedChrome(store)
        }
        .sheet(isPresented: $showSandbox) {
            JSSandboxSheet()
                .presentationDetents([.large])
                .presentationCornerRadius(38)
                .themedChrome(store)
        }
        .sheet(isPresented: $showDiscover) {
            DiscoverSheet()
                .presentationDetents([.large])
                .presentationCornerRadius(38)
                .themedChrome(store)
        }
        .sheet(isPresented: $showVoice) {
            VoiceLabSheet()
                .presentationDetents([.large])
                .presentationCornerRadius(38)
                .themedChrome(store)
        }
        .sheet(isPresented: $showCompliance) {
            ComplianceSheet()
                .presentationDetents([.large])
                .presentationCornerRadius(38)
                .themedChrome(store)
        }
        .task {
            #if DEBUG
            let arguments = ProcessInfo.processInfo.arguments
            if arguments.contains("-openSync") { showSync = true }
            if arguments.contains("-openBackup") { showBackup = true }
            if arguments.contains("-openCache") { showCache = true }
            if arguments.contains("-openNetworkLogs") { showNetworkLogs = true }
            if arguments.contains("-openExport") { showExport = true }
            if arguments.contains("-openAI") { showAI = true }
            if arguments.contains("-openSandbox") { showSandbox = true }
            if arguments.contains("-openDiscover") { showDiscover = true }
            if arguments.contains("-openVoice") { showVoice = true }
            if arguments.contains("-openCompliance") { showCompliance = true }
            if arguments.contains("-openEyeCare") { showEyeCare = true }
            #endif
        }
    }

    private var profileCard: some View {
        HStack(spacing: 15) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Palette.accent, Palette.gold.opacity(0.75)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 54, height: 54)

                Text("夜")
                    .font(.system(size: 22, weight: .semibold, design: .serif))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("夜读者")
                    .font(.system(size: 16, weight: .semibold, design: .serif))
                    .foregroundStyle(Palette.text)

                Text("连续 \(store.streak) 天 · 累计 \(store.totalMinutes / 60) 小时")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.secondary)
            }

            Spacer()

            VStack(spacing: 1) {
                Text("\(store.books.count)")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(Palette.text)
                Text("本藏书")
                    .font(.system(size: 9))
                    .foregroundStyle(Palette.tertiary)
            }
        }
        .padding(15)
        .glassSurface(cornerRadius: 26)
    }

    private func labTile(
        _ title: String,
        _ detail: String,
        _ symbol: String,
        _ tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 9) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 30, height: 30)
                    .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(Palette.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Text(detail)
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.tertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }

                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
            .background(Palette.glassTint.opacity(0.55), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .strokeBorder(Palette.hairline, lineWidth: 0.6)
            }
            .contentShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        }
        .buttonStyle(PressableStyle(scale: 0.97))
    }

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionHeading(text: title)

            VStack(spacing: 0) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassSurface(cornerRadius: 22)
        }
    }
}

// MARK: - Eye care

struct EyeCareSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var showPreview = false

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackdrop()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        statusCard

                        VStack(alignment: .leading, spacing: 10) {
                            SectionHeading(text: "界面明暗", trailing: store.appearance.rawValue)

                            GlassSegmented(
                                items: AppAppearance.allCases,
                                title: { $0.rawValue },
                                selection: Binding(
                                    get: { store.appearance },
                                    set: { newValue in
                                        withAnimation(.easeInOut(duration: 0.35)) {
                                            store.appearance = newValue
                                        }
                                    }
                                )
                            )
                        }
                        .padding(14)
                        .glassSurface(cornerRadius: 20)

                        VStack(alignment: .leading, spacing: 14) {
                            Toggle(isOn: Binding(
                                get: { store.eyeCare.enabled },
                                set: { store.eyeCare.enabled = $0; store.saveSnapshot() }
                            )) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("暖色滤光")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(Palette.text)
                                    Text("降低蓝光刺激，阅读页与书架同步生效")
                                        .font(.system(size: 10.5))
                                        .foregroundStyle(Palette.tertiary)
                                }
                            }
                            .tint(Palette.jade)

                            sliderRow(
                                title: "暖度",
                                value: Binding(
                                    get: { store.eyeCare.warmth },
                                    set: { store.eyeCare.warmth = $0; store.saveSnapshot() }
                                ),
                                range: 0.05...0.75,
                                label: "\(Int(store.eyeCare.warmth * 100))%"
                            )

                            sliderRow(
                                title: "亮度",
                                value: Binding(
                                    get: { store.eyeCare.dim },
                                    set: { store.eyeCare.dim = $0; store.saveSnapshot() }
                                ),
                                range: 0...0.35,
                                label: "\(Int((1 - store.eyeCare.dim) * 100))%"
                            )
                        }
                        .padding(14)
                        .glassSurface(cornerRadius: 20)

                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeading(
                                text: "休息提醒",
                                trailing: store.eyeCare.restReminder ? "开启" : "关闭"
                            )

                            HStack {
                                Text("每 \(store.eyeCare.restMinutes) 分钟")
                                    .font(.system(size: 13))
                                    .foregroundStyle(Palette.text)

                                Spacer()

                                Toggle("", isOn: Binding(
                                    get: { store.eyeCare.restReminder },
                                    set: { store.eyeCare.restReminder = $0; store.saveSnapshot() }
                                ))
                                .labelsHidden()
                                .tint(Palette.jade)
                            }

                            Button {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    showPreview.toggle()
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "eye")
                                    Text("预览休息提醒")
                                }
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Palette.jade)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .glassCapsule(tint: Palette.jade.opacity(0.1), interactive: true)
                            }
                            .buttonStyle(PressableStyle())

                            if showPreview {
                                Text("已读 20 分钟。看看 6 米外，让眼睛休息 20 秒。")
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(Palette.secondary)
                                    .padding(10)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .glassSurface(cornerRadius: 14, tint: Palette.jade.opacity(0.08))
                                    .transition(.opacity.combined(with: .move(edge: .top)))
                            }
                        }
                        .padding(14)
                        .glassSurface(cornerRadius: 20)

                        Text("护眼设置全 App 生效，只保存在本机。")
                            .font(.system(size: 10))
                            .foregroundStyle(Palette.tertiary)
                            .padding(.horizontal, 2)
                    }
                    .padding(18)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("护眼与外观")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            // sheet 是独立宿主：根视图上的护眼层盖不住它，明暗偏好也不会自动
            // 传进来。这两句都得写在这里，否则一边拖暖度/亮度、
            // 一边切深浅，当前这张卡片本身毫无变化。
            .themedChrome(store)
            .onDisappear { store.saveSnapshot() }
            .task {
                #if DEBUG
                // 截图核对用：在这个弹层打开的状态下切一次明暗，验证明暗会即时生效。
                if ProcessInfo.processInfo.arguments.contains("-cycleAppearance") {
                    try? await Task.sleep(for: .seconds(5))
                    store.appearance = store.appearance == .dark ? .light : .dark
                }
                #endif
            }
        }
    }

    private var statusCard: some View {
        HStack(spacing: 13) {
            Image(systemName: "leaf.fill")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Palette.jade)
                .frame(width: 42, height: 42)
                .background(Palette.jade.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(store.eyeCare.enabled ? "已开启" : "已关闭")
                    .font(.system(size: 15, weight: .semibold, design: .serif))
                    .foregroundStyle(Palette.text)
                Text("暖度 \(Int(store.eyeCare.warmth * 100))% · 亮度 \(Int((1 - store.eyeCare.dim) * 100))%")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Palette.tertiary)
                    .monospacedDigit()
            }

            Spacer()
        }
        .padding(14)
        .glassSurface(cornerRadius: 20)
    }

    private func sliderRow(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        label: String
    ) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(Palette.secondary)
                .frame(width: 32, alignment: .leading)
            Slider(value: value, in: range)
                .tint(Palette.jade)
            Text(label)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(Palette.tertiary)
                .monospacedDigit()
                .frame(width: 34, alignment: .trailing)
        }
    }
}

struct GoalSheet: View {
    @Environment(\.dismiss) private var dismiss

    let minutes: Int
    let onSave: (Int) -> Void

    @State private var value: Int = 60

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackdrop()

                VStack(spacing: 22) {
                    VStack(spacing: 5) {
                        Text("\(value)")
                            .font(.system(size: 46, weight: .semibold, design: .rounded))
                            .foregroundStyle(Palette.text)
                            .monospacedDigit()

                        Text("分钟 / 天")
                            .font(.system(size: 12))
                            .foregroundStyle(Palette.tertiary)
                    }
                    .padding(.top, 14)

                    Slider(
                        value: Binding(
                            get: { Double(value) },
                            set: { value = Int($0 / 5) * 5 }
                        ),
                        in: 10...180,
                        step: 5
                    )
                    .tint(Palette.accent)
                    .padding(.horizontal, 6)

                    HStack(spacing: 8) {
                        ForEach([20, 30, 60, 90], id: \.self) { preset in
                            Button {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    value = preset
                                }
                            } label: {
                                Text("\(preset) 分")
                                    .font(.system(size: 12, weight: value == preset ? .semibold : .medium))
                                    .foregroundStyle(value == preset ? Palette.onAccent : Palette.secondary)
                                    .padding(.horizontal, 13)
                                    .padding(.vertical, 8)
                                    .background {
                                        if value == preset { Capsule().fill(Palette.accentSolid) }
                                    }
                                    .glassCapsule(tint: value == preset ? nil : Palette.glassTint, interactive: true)
                                    .contentShape(Capsule())
                            }
                            .buttonStyle(PressableStyle())
                        }
                    }

                    Spacer(minLength: 0)

                    Button {
                        onSave(value)
                        dismiss()
                    } label: {
                        Text("保存目标")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Palette.onAccent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(Palette.accentSolid, in: Capsule())
                    }
                    .buttonStyle(PressableStyle(scale: 0.97))
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 18)
            }
            .navigationTitle("每日目标")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("取消") { dismiss() }
                }
            }
            .onAppear { value = minutes }
        }
    }
}

struct DistributionSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackdrop()

                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 13) {
                        Image(systemName: "shippingbox")
                            .font(.system(size: 21, weight: .light))
                            .foregroundStyle(Palette.accent)
                            .frame(width: 30)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("TestFlight / 自签安装")
                                .font(.system(size: 16, weight: .semibold, design: .serif))
                                .foregroundStyle(Palette.text)

                            Text("当前为演示构建，仅用于界面与交互评估。")
                                .font(.system(size: 11.5))
                                .foregroundStyle(Palette.secondary)
                        }
                    }
                    .padding(15)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassSurface(cornerRadius: 22)

                    VStack(spacing: 0) {
                        infoRow("安装方式", "TestFlight", isLast: false)
                        infoRow("构建有效期", "约 90 天（自签 / TestFlight 由 Apple 决定）", isLast: false)
                        infoRow("更新渠道", "GitHub Releases", isLast: false)
                        infoRow("价格", "免费", isLast: true)
                    }
                    .glassSurface(cornerRadius: 22)

                    Button {
                        UIApplication.shared.open(URL(string: "https://github.com/hjz101/yehangchuan/releases")!)
                    } label: {
                        Label("打开发布页", systemImage: "arrow.up.right.square")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Palette.onAccent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(Palette.accentSolid, in: Capsule())
                    }
                    .buttonStyle(PressableStyle(scale: 0.97))

                    Spacer()
                }
                .padding(18)
            }
            .navigationTitle("安装与更新")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private func infoRow(_ title: String, _ value: String, isLast: Bool) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.secondary)

                Spacer()

                Text(value)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Palette.text)
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 12)

            if !isLast {
                Rectangle()
                    .fill(Palette.hairline)
                    .frame(height: 0.6)
                    .padding(.leading, 15)
            }
        }
    }
}

// MARK: - Sync

struct SyncCenterSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var email = "reader@yehangchuan.app"
    @State private var isBusy = false
    @State private var useRealCloud = false
    /// 演示模式下的冲突演练：默认不制造冲突。
    @State private var demoConflict = false
    @State private var message = ""

    private var syncTint: Color {
        switch store.backend.syncState {
        case .synced: Palette.jade
        case .conflict, .failed: Palette.accent
        case .syncing: Palette.gold
        case .idle: Palette.tertiary
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackdrop()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        statusCard
                        accountSection
                        syncSection
                        logHint
                    }
                    .padding(18)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("账户与同步")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private var statusCard: some View {
        HStack(spacing: 14) {
            Image(systemName: store.backend.syncState.symbol)
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(syncTint)
                .frame(width: 48, height: 48)
                .background(syncTint.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(useRealCloud ? "iCloud 同步" : "同步（演示）")
                    .font(.system(size: 17, weight: .semibold, design: .serif))
                    .foregroundStyle(Palette.text)

                Text(store.backend.syncState.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(syncTint)

                Text(lastSyncText)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Palette.tertiary)
            }

            Spacer()

            if isBusy { ProgressView().themedProgress() }
        }
        .padding(15)
        .glassSurface(cornerRadius: 24)
    }

    private var lastSyncText: String {
        guard let date = store.backend.lastSyncAt else {
            return useRealCloud ? "尚未同步 · 本机数据优先" : "演示状态 · 本机数据优先"
        }
        let stamp = date.formatted(date: .abbreviated, time: .shortened)
        return useRealCloud ? "上次同步 \(stamp)" : "上次演示同步 \(stamp) · 未上传"
    }

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeading(text: "账号")

            VStack(alignment: .leading, spacing: 12) {
                switch store.backend.account {
                case .guest:
                    TextField("邮箱", text: $email)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.emailAddress)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 11)
                        .glassSurface(cornerRadius: 15)

                    Button {
                        isBusy = true
                        Task { @MainActor in
                            let ok = await store.backend.signIn(email: email)
                            // 这是演示账号，不存在真实会话，更不会影响书源 Cookie。
                            message = ok ? "已登录演示账号（本机模拟，不联网）" : "登录失败，请检查模拟网络状态"
                            isBusy = false
                        }
                    } label: {
                        Text("登录演示账号")
                            .readableButtonStyle(tint: Palette.accentSolid)
                    }
                    .buttonStyle(PressableStyle(scale: 0.97))
                case .signedIn(let email):
                    HStack(spacing: 12) {
                        Image(systemName: "person.crop.circle.badge.checkmark")
                            .font(.system(size: 22, weight: .light))
                            .foregroundStyle(Palette.jade)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(email)
                                .font(.system(size: 13))
                                .foregroundStyle(Palette.text)
                            Text("本机 + 云端模拟副本")
                                .font(.system(size: 10))
                                .foregroundStyle(Palette.tertiary)
                        }

                        Spacer()

                        Button("退出") {
                            store.backend.signOut()
                            message = "已退出演示账号，本机数据保留"
                        }
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Palette.accent)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .glassCapsule(tint: Palette.accent.opacity(0.08), interactive: true)
                    }
                }

                if !message.isEmpty {
                    Text(message)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Palette.tertiary)
                }
            }
            .padding(14)
            .glassSurface(cornerRadius: 20)
        }
    }

    private var syncSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeading(text: "同步")

            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: $useRealCloud) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("使用真实 iCloud 私有库")
                            .font(.system(size: 13))
                            .foregroundStyle(Palette.text)
                        Text("需要登录 iCloud 并在 Xcode 开启 iCloud capability")
                            .font(.system(size: 10))
                            .foregroundStyle(Palette.tertiary)
                    }
                }
                .tint(Palette.jade)

                if !useRealCloud {
                    Toggle(isOn: $demoConflict) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("演练冲突流程")
                                .font(.system(size: 13))
                                .foregroundStyle(Palette.text)
                            Text("只切换演示状态，不产生真实的云端数据")
                                .font(.system(size: 10))
                                .foregroundStyle(Palette.tertiary)
                        }
                    }
                    .tint(Palette.accent)
                }

                Button {
                    if useRealCloud {
                        Task { @MainActor in await uploadToCloud() }
                    } else {
                        isBusy = true
                        Task { @MainActor in
                            _ = await store.backend.sync(forceConflict: demoConflict)
                            demoConflict = false
                            isBusy = false
                        }
                    }
                } label: {
                    Label(useRealCloud ? "上传到 iCloud" : "立即同步", systemImage: "arrow.triangle.2.circlepath")
                        .readableButtonStyle(tint: Palette.accentSolid)
                }
                .buttonStyle(PressableStyle(scale: 0.97))

                if useRealCloud {
                    Button {
                        Task { @MainActor in await downloadFromCloud() }
                    } label: {
                        Label("从 iCloud 拉取并恢复", systemImage: "arrow.down.to.line")
                            .readableButtonStyle(tint: Palette.jade)
                    }
                    .buttonStyle(PressableStyle(scale: 0.97))
                    .disabled(isBusy)
                }

                if store.backend.syncState == .conflict {
                    HStack(spacing: 9) {
                        Button {
                            store.backend.resolveConflict(useLocal: true)
                            message = "已保留本机版本"
                        } label: {
                            Text("保留本机")
                                .readableButtonStyle(tint: Palette.jade)
                        }
                        .buttonStyle(PressableStyle())

                        Button {
                            store.backend.resolveConflict(useLocal: false)
                            message = "已使用云端版本"
                        } label: {
                            Text("使用云端")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Palette.text)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 13)
                                .glassSurface(cornerRadius: 22, tint: Palette.gold.opacity(0.1), interactive: true)
                        }
                        .buttonStyle(PressableStyle())
                    }
                }

                Text(useRealCloud
                     ? "真实模式会读写当前 Apple ID 的 CloudKit 私有数据库；未登录或权限不足会如实报错。"
                     : "演示同步只改本机状态，不发送任何请求，也不会连接 iCloud。")
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.tertiary)
            }
            .padding(14)
            .glassSurface(cornerRadius: 20)
        }
    }

    private func uploadToCloud() async {
        isBusy = true
        defer { isBusy = false }
        do {
            try await CloudSyncService.shared.upload(store.exportedSnapshotData())
            message = "快照已写入真实 iCloud 私有数据库"
        } catch {
            message = "iCloud 上传失败：\(error.localizedDescription)"
        }
    }

    private func downloadFromCloud() async {
        isBusy = true
        defer { isBusy = false }
        do {
            guard let data = try await CloudSyncService.shared.download() else {
                message = "iCloud 里还没有本站的快照"
                return
            }
            try store.importSnapshotData(data)
            message = "已从 iCloud 恢复快照"
        } catch {
            message = "iCloud 拉取失败：\(error.localizedDescription)"
        }
    }

    /// 同步页不再展示「最近请求」。
    ///
    /// 那一栏原来读的是 MockBackend 自己记的假记录，连演示模式下的
    /// “同步成功”都是编出来的状态。现在演示同步与真实 iCloud 都明确标注，
    /// 真实网络请求统一去「设置 → 网络日志」看（读 LegadoCore 的 DiagnosticLog）。
    private var logHint: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "list.bullet.rectangle")
                .font(.system(size: 12))
                .foregroundStyle(Palette.tertiary)
            Text("真实请求记录在「设置 → 网络日志」；这一页不另外维护一份日志。")
                .font(.system(size: 10))
                .foregroundStyle(Palette.tertiary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(cornerRadius: 16)
    }
}

// MARK: - Backup

struct BackupSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var scopes: Set<BackupScope> = [.sources, .library, .preferences]
    @State private var message = ""
    @State private var restoreTarget: BackupRecord?

    private var backups: [BackupRecord] { store.backup.backups }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackdrop()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionHeading(text: "创建备份")

                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(BackupScope.allCases) { scope in
                                    Toggle(scope.toggleLabel, isOn: binding(for: scope))
                                }

                                Button {
                                    Task { @MainActor in
                                        let payload = store.makeBackupPayload(scopes: scopes)
                                        guard let record = await store.backup.create(
                                            name: "夜航船",
                                            scopes: scopes,
                                            payload: payload
                                        ) else {
                                            message = "备份写入失败，请检查存储空间"
                                            return
                                        }
                                        message = "已写入 \(record.name)（\(record.sizeLabel)）"
                                    }
                                } label: {
                                    Label("创建备份", systemImage: "externaldrive.badge.plus")
                                        .readableButtonStyle(tint: Palette.accentSolid)
                                }
                                .buttonStyle(PressableStyle(scale: 0.97))
                                .disabled(store.backup.isBusy || scopes.isEmpty)

                                Text("备份写在 Application Support/Backups 下，卸载 App 会一并删除。")
                                    .font(.system(size: 9.5))
                                    .foregroundStyle(Palette.tertiary)

                                if !message.isEmpty {
                                    Text(message)
                                        .font(.system(size: 10.5))
                                        .foregroundStyle(Palette.tertiary)
                                }
                            }
                            .font(.system(size: 13))
                            .tint(Palette.accent)
                            .padding(14)
                            .glassSurface(cornerRadius: 20)
                        }

                        VStack(alignment: .leading, spacing: 9) {
                            SectionHeading(text: "本机备份", trailing: "\(backups.count) 份")

                            if backups.isEmpty {
                                Text("还没有备份。勾选要包含的内容后点「创建备份」。")
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(Palette.tertiary)
                                    .padding(14)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .glassSurface(cornerRadius: 20)
                            } else {
                                VStack(spacing: 0) {
                                    ForEach(backups) { record in
                                        HStack(spacing: 12) {
                                            Image(systemName: "archivebox")
                                                .font(.system(size: 15))
                                                .foregroundStyle(Palette.gold)
                                                .frame(width: 32, height: 32)
                                                .background(Palette.gold.opacity(0.1), in: RoundedRectangle(cornerRadius: 9))

                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(record.displayName)
                                                    .font(.system(size: 12.5, weight: .medium))
                                                    .foregroundStyle(Palette.text)
                                                    .lineLimit(1)
                                                Text("\(record.createdAt.formatted(date: .abbreviated, time: .shortened)) · \(record.sizeLabel) · \(record.includesLabel)")
                                                    .font(.system(size: 9.5))
                                                    .foregroundStyle(Palette.tertiary)
                                                    .lineLimit(1)
                                            }

                                            Spacer()

                                            Button("恢复") {
                                                restoreTarget = record
                                            }
                                            .font(.system(size: 11.5, weight: .semibold))
                                            .foregroundStyle(Palette.accent)
                                        }
                                        .padding(.horizontal, 13)
                                        .padding(.vertical, 10)
                                        .contextMenu {
                                            Button("删除备份", role: .destructive) {
                                                Task { await store.backup.delete(record) }
                                            }
                                        }
                                    }
                                }
                                .glassSurface(cornerRadius: 20)
                            }
                        }
                    }
                    .padding(18)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("本地备份")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .task { await store.backup.refresh() }
            .alert(item: $restoreTarget) { record in
                Alert(
                    title: Text("恢复备份？"),
                    message: Text("\(record.displayName) 会覆盖当前的书源、书籍进度与偏好设置。"),
                    primaryButton: .destructive(Text("恢复")) {
                        Task { @MainActor in
                            guard let package = await store.backup.load(record) else {
                                message = "\(record.displayName) 无法读取，可能已损坏"
                                return
                            }
                            store.restore(from: package.payload)
                            message = "已恢复 \(record.displayName)"
                        }
                    },
                    secondaryButton: .cancel()
                )
            }
        }
    }

    private func binding(for scope: BackupScope) -> Binding<Bool> {
        Binding(
            get: { scopes.contains(scope) },
            set: { isOn in
                if isOn { scopes.insert(scope) } else { scopes.remove(scope) }
            }
        )
    }
}

// MARK: - Cache

struct CacheSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var message = ""
    /// 三类缓存都按真实磁盘内容统计，进页后再算一次（枚举目录不进 body）。
    @State private var usage: CacheUsage.Snapshot?

    private var totalBytes: Int {
        (usage?.chapterBytes ?? 0) + (usage?.imageBytes ?? 0) + (usage?.audioBytes ?? 0)
    }

    private var totalMB: Double { Double(totalBytes) / 1_048_576 }

    private func refreshUsage() async {
        usage = await CacheUsage.snapshot()
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackdrop()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(spacing: 14) {
                            RingProgress(
                                value: min(totalMB / 160, 1),
                                lineWidth: 7,
                                tint: Palette.jade,
                                label: String(format: "%.1f", totalMB),
                                caption: "MB"
                            )
                            .frame(width: 62, height: 62)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("阅读缓存")
                                    .font(.system(size: 16, weight: .semibold, design: .serif))
                                    .foregroundStyle(Palette.text)
                                Text(usage == nil ? "正在统计磁盘占用…" : "章节正文、漫画页图与本地音频的磁盘占用")
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(Palette.tertiary)
                            }
                            Spacer()
                        }
                        .padding(14)
                        .glassSurface(cornerRadius: 22)

                        cacheRow("章节", bytes: usage?.chapterBytes, symbol: "doc.text", kind: "章节")
                        cacheRow("图片", bytes: usage?.imageBytes, symbol: "photo", kind: "图片")
                        cacheRow("音频", bytes: usage?.audioBytes, symbol: "waveform", kind: "音频")

                        Button {
                            Task { @MainActor in
                                let chapterFreed = await CacheUsage.clearChapters()
                                let imageFreed = CacheUsage.clearImages()
                                let audio = CacheUsage.clearAudio()
                                await refreshUsage()
                                var text = String(
                                    format: "已清理 %.1f MB",
                                    Double(chapterFreed + imageFreed + audio.freed) / 1_048_576
                                )
                                if audio.skipped > 0 {
                                    text += "；\(audio.skipped) 个音频正在使用，未能删除"
                                }
                                message = text
                            }
                        } label: {
                            Text("清理全部缓存")
                                .readableButtonStyle(tint: Palette.accentSolid)
                        }
                        .buttonStyle(PressableStyle(scale: 0.97))
                        .disabled(usage == nil)

                        Text("三项都按真实磁盘统计：章节是书源正文缓存，图片是降采样后的漫画页图，音频是导入到沙箱的音频副本。清除音频等于删除这本书的本地音频，需重新导入。")
                            .font(.system(size: 10))
                            .foregroundStyle(Palette.tertiary)

                        storageMigrationCard

                        if !message.isEmpty {
                            Text(message)
                                .font(.system(size: 10.5))
                                .foregroundStyle(Palette.tertiary)
                        }
                    }
                    .padding(18)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("缓存与空间")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .task { await refreshUsage() }
        }
    }

    /// 书架存储的实况：书架与正文怎么存的、占多少盘、有没有出过问题。
    /// 不显示「模拟」字样 —— 这些数字是真的从磁盘读出来的。
    @ViewBuilder
    private var storageMigrationCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "externaldrive.badge.checkmark")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Palette.jade)
                Text("书架存储")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Palette.text)
                Spacer()
                if store.libraryStoreWarning != nil {
                    Label("有问题", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 9.5))
                        .foregroundStyle(Palette.accent)
                        .labelStyle(.titleAndIcon)
                        .lineLimit(1)
                } else if let report = store.migrationReport, !report.warnings.isEmpty {
                    Text("\(report.warnings.count) 条提示")
                        .font(.system(size: 9.5))
                        .foregroundStyle(Palette.accent)
                }
            }

            if let summary = store.migratedLibrarySummary {
                Text("\(summary.books) 本 · \(summary.chapters) 章 · 索引与正文分开存放")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Palette.secondary)
                Text(String(format: "占用 %.1f MB", Double(store.migratedLibraryBytes) / 1_048_576))
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.tertiary)
            } else {
                Text("书架仍保存在单个快照文件里。")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Palette.secondary)
            }

            // 读写出过问题时如实说出来。宁可让用户知道「这次读到的是上一版」，
            // 也不要让他以为一切正常、直到某天发现书签全没了。
            if let warning = store.libraryStoreWarning {
                ForEach(warning.components(separatedBy: "\n"), id: \.self) { line in
                    Text("· \(line)")
                        .font(.system(size: 9.5))
                        .foregroundStyle(Palette.accent)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let report = store.migrationReport {
                Text(report.message)
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                if let archived = report.archivedFile {
                    Text("旧文件已留档：\(archived.lastPathComponent)")
                        .font(.system(size: 9.5))
                        .foregroundStyle(Palette.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                ForEach(report.warnings, id: \.self) { warning in
                    Text("· \(warning)")
                        .font(.system(size: 9.5))
                        .foregroundStyle(Palette.accent)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(cornerRadius: 18)
    }

    /// 单类缓存行。`bytes` 为 nil 表示还在统计，显示「计算中」而不是一个假的 0。
    private func cacheRow(_ title: String, bytes: Int?, symbol: String, kind: String) -> some View {
        let size = Double(bytes ?? 0) / 1_048_576
        return HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Palette.jade)
                .frame(width: 32, height: 32)
                .background(Palette.jade.opacity(0.1), in: RoundedRectangle(cornerRadius: 9))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Palette.text)
                Text(bytes == nil ? "计算中…" : String(format: "%.1f MB", size))
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.tertiary)
            }

            Spacer()

            Button("清理") {
                Task { @MainActor in
                    var text: String
                    switch kind {
                    case "章节":
                        let freed = await CacheUsage.clearChapters()
                        text = String(format: "已清理 %.1f MB %@", Double(freed) / 1_048_576, title)
                    case "图片":
                        let freed = CacheUsage.clearImages()
                        text = String(format: "已清理 %.1f MB %@", Double(freed) / 1_048_576, title)
                    default:
                        let result = CacheUsage.clearAudio()
                        text = String(format: "已清理 %.1f MB %@", Double(result.freed) / 1_048_576, title)
                        if result.skipped > 0 {
                            text += "；\(result.skipped) 个文件正在使用，未能删除"
                        }
                    }
                    await refreshUsage()
                    message = text
                }
            }
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(Palette.accent)
            .disabled(size == 0)
            .opacity(size == 0 ? 0.35 : 1)
        }
        .padding(13)
        .glassSurface(cornerRadius: 18)
    }
}
