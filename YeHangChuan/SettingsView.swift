import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(AppStore.self) private var store

    /// 缓存与空间：章节 / 音频是演示估算值，图片缓存读磁盘真实占用。
    static func storageLabel(store: AppStore) -> String {
        let imageMB = Double(ImageCacheStore.totalBytes()) / 1_048_576
        let total = store.backend.cacheChapterMB + imageMB + store.backend.cacheAudioMB
        return String(format: "%.1f MB", total)
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
    @State private var showAlert: SettingsAlert?

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackdrop()

                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
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
                                        value: "TXT / EPUB / PDF / ZIP",
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
                                        value: Self.storageLabel(store: store),
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
                                    labTile("JS 书源沙箱", "权限隔离 · 私网拒绝", "curlybraces.square", Palette.jade) {
                                        showSandbox = true
                                    }
                                    labTile("在线发现", "多源聚合 · 订阅", "safari", Palette.gold) {
                                        showDiscover = true
                                    }
                                    labTile("声音实验室", "多角色 · 后台", "waveform", Palette.jade) {
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
                                        title: "网络诊断",
                                        value: store.backend.isOnline ? "在线" : "离线",
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

                            VStack(spacing: 6) {
                                Button {
                                    showAlert = .support
                                } label: {
                                    Text("支持开发者")
                                        .font(.system(size: 11.5, weight: .medium))
                                        .foregroundStyle(Palette.accent)
                                }
                                .buttonStyle(PressableStyle())

                                Text("夜航船 · 本地优先的阅读器")
                                    .font(.system(size: 10.5, design: .serif))
                                    .foregroundStyle(Palette.tertiary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 2)
                            .id("settingsFooter")
                        }
                        .padding(.horizontal, 18)
                        .padding(.top, 6)
                        .padding(.bottom, 40)
                    }
                    .scrollIndicators(.hidden)
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
        .sheet(isPresented: $showEyeCare) {
            EyeCareSheet()
                .presentationDetents([.large])
                .presentationCornerRadius(38)
        }
        .sheet(isPresented: $showReaderSettings) {
            ReaderSettingsSheet(settings: store.settings)
                .presentationDetents([.large])
                .presentationCornerRadius(38)
        }
        .sheet(isPresented: $showDistribution) {
            DistributionSheet()
                .presentationDetents([.medium])
                .presentationCornerRadius(38)
        }
        .sheet(isPresented: $showGoal) {
            GoalSheet(minutes: store.goalMinutes) { value in
                store.goalMinutes = value
                store.saveSnapshot()
                store.showToast("每日目标已设为 \(value) 分钟")
            }
            .presentationDetents([.height(320)])
            .presentationCornerRadius(38)
        }
        .sheet(isPresented: $showImport) {
            SmartImportSheet()
                .presentationDetents([.large])
                .presentationCornerRadius(38)
        }
        .sheet(isPresented: $showSync) {
            SyncCenterSheet()
                .presentationDetents([.large])
                .presentationCornerRadius(38)
        }
        .sheet(isPresented: $showBackup) {
            BackupSheet()
                .presentationDetents([.large])
                .presentationCornerRadius(38)
        }
        .sheet(isPresented: $showCache) {
            CacheSheet()
                .presentationDetents([.medium, .large])
                .presentationCornerRadius(38)
        }
        .sheet(isPresented: $showNetworkLogs) {
            NetworkLogSheet()
                .presentationDetents([.medium, .large])
                .presentationCornerRadius(38)
        }
        .sheet(isPresented: $showExport) {
            DataExportSheet()
                .presentationDetents([.large])
                .presentationCornerRadius(38)
        }
        .sheet(isPresented: $showAI) {
            AIStudioSheet()
                .presentationDetents([.large])
                .presentationCornerRadius(38)
        }
        .sheet(isPresented: $showSandbox) {
            JSSandboxSheet()
                .presentationDetents([.large])
                .presentationCornerRadius(38)
        }
        .sheet(isPresented: $showDiscover) {
            DiscoverSheet()
                .presentationDetents([.large])
                .presentationCornerRadius(38)
        }
        .sheet(isPresented: $showVoice) {
            VoiceLabSheet()
                .presentationDetents([.large])
                .presentationCornerRadius(38)
        }
        .sheet(isPresented: $showCompliance) {
            ComplianceSheet()
                .presentationDetents([.large])
                .presentationCornerRadius(38)
        }
        .alert(item: $showAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("好"))
            )
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
                        .padding(.horizontal, 14)
                        .padding(.vertical, 13)
                        .glassSurface(cornerRadius: 20)

                        VStack(spacing: 14) {
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
                            Toggle("每 \(store.eyeCare.restMinutes) 分钟提醒休息", isOn: Binding(
                                get: { store.eyeCare.restReminder },
                                set: { store.eyeCare.restReminder = $0; store.saveSnapshot() }
                            ))
                            .font(.system(size: 13))
                            .tint(Palette.jade)

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
            .onDisappear { store.saveSnapshot() }
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

enum SettingsAlert: Identifiable {
    case export
    case support

    var id: String {
        switch self {
        case .export: "export"
        case .support: "support"
        }
    }

    var title: String {
        switch self {
        case .export: "导出数据"
        case .support: "支持开发者"
        }
    }

    var message: String {
        switch self {
        case .export: "演示版本暂未实现导出，这里用于确认入口位置。"
        case .support: "演示版本不接入支付，仅保留站外支持入口。"
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
                        infoRow("构建有效期", "2027-05-24", isLast: false)
                        infoRow("更新渠道", "GitHub Releases", isLast: false)
                        infoRow("价格", "免费", isLast: true)
                    }
                    .glassSurface(cornerRadius: 22)

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
    @State private var forceConflict = false
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
                        logSection
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
                Text("iCloud 同步")
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

            if isBusy { ProgressView() }
        }
        .padding(15)
        .glassSurface(cornerRadius: 24)
    }

    private var lastSyncText: String {
        guard let date = store.backend.lastSyncAt else {
            return "尚未同步 · 本机数据优先"
        }
        return "上次同步 \(date.formatted(date: .abbreviated, time: .shortened))"
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
                            message = ok ? "登录成功，书源 Cookie 将随会话复用" : "登录失败，请检查模拟网络状态"
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
                Toggle(isOn: $forceConflict) {
                    Text("下一次同步制造冲突")
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.text)
                }
                .tint(Palette.accent)

                Button {
                    isBusy = true
                    Task { @MainActor in
                        _ = await store.backend.sync(forceConflict: forceConflict)
                        forceConflict = false
                        isBusy = false
                    }
                } label: {
                    Label("立即同步", systemImage: "arrow.triangle.2.circlepath")
                        .readableButtonStyle(tint: Palette.accentSolid)
                }
                .buttonStyle(PressableStyle(scale: 0.97))

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

                Text("演示同步会写入本机状态并记录请求，不会连接真实 iCloud。")
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.tertiary)
            }
            .padding(14)
            .glassSurface(cornerRadius: 20)
        }
    }

    private var logSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionHeading(text: "最近请求", trailing: "\(store.backend.requestCount) 次")

            if store.backend.logs.isEmpty {
                Text("还没有同步请求。")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.tertiary)
                    .padding(13)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassSurface(cornerRadius: 18)
            } else {
                VStack(spacing: 0) {
                    ForEach(store.backend.logs.prefix(4)) { log in
                        HStack {
                            Text(log.method)
                                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                                .foregroundStyle(log.status == 200 ? Palette.jade : Palette.accent)
                            Text(log.path)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(Palette.secondary)
                                .lineLimit(1)
                            Spacer()
                            Text("\(log.status) · \(log.milliseconds) ms")
                                .font(.system(size: 9, design: .rounded))
                                .foregroundStyle(Palette.tertiary)
                                .monospacedDigit()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                    }
                }
                .glassSurface(cornerRadius: 18)
            }
        }
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
    /// 图片缓存是真实落盘的清单文件，单独按磁盘内容统计，
    /// 不再用 MockBackend 里那个写死的 48.6 MB。
    @State private var imageCacheBytes = ImageCacheStore.totalBytes()

    private var imageCacheMB: Double { Double(imageCacheBytes) / 1_048_576 }

    private var total: Double {
        store.backend.cacheChapterMB + imageCacheMB + store.backend.cacheAudioMB
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackdrop()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(spacing: 14) {
                            RingProgress(
                                value: min(total / 160, 1),
                                lineWidth: 7,
                                tint: Palette.jade,
                                label: String(format: "%.1f", total),
                                caption: "MB"
                            )
                            .frame(width: 62, height: 62)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("阅读缓存")
                                    .font(.system(size: 16, weight: .semibold, design: .serif))
                                    .foregroundStyle(Palette.text)
                                Text(store.backend.lastDownloadLabel)
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(Palette.tertiary)
                            }
                            Spacer()
                        }
                        .padding(14)
                        .glassSurface(cornerRadius: 22)

                        cacheRow("章节", size: store.backend.cacheChapterMB, symbol: "doc.text", kind: "章节")
                        cacheRow("图片", size: imageCacheMB, symbol: "photo", kind: "图片")
                        cacheRow("音频", size: store.backend.cacheAudioMB, symbol: "waveform", kind: "音频")

                        Button {
                            let mockFreed = store.backend.clearCache("全部")
                            let diskFreed = Double(ImageCacheStore.removeAll()) / 1_048_576
                            imageCacheBytes = ImageCacheStore.totalBytes()
                            message = String(format: "已清理 %.1f MB", mockFreed + diskFreed)
                        } label: {
                            Text("清理全部缓存")
                                .readableButtonStyle(tint: Palette.accentSolid)
                        }
                        .buttonStyle(PressableStyle(scale: 0.97))

                        Text("章节与音频为演示数据估算值；图片缓存是漫画页清单，真实写在 Application Support 下。")
                            .font(.system(size: 10))
                            .foregroundStyle(Palette.tertiary)

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
        }
    }

    private func cacheRow(_ title: String, size: Double, symbol: String, kind: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Palette.jade)
                .frame(width: 32, height: 32)
                .background(Palette.jade.opacity(0.1), in: RoundedRectangle(cornerRadius: 9))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Palette.text)
                Text(String(format: "%.1f MB", size))
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.tertiary)
            }

            Spacer()

            Button("清理") {
                if kind == "图片" {
                    let freed = Double(ImageCacheStore.removeAll()) / 1_048_576
                    imageCacheBytes = ImageCacheStore.totalBytes()
                    message = String(format: "已清理 %.1f MB %@", freed, title)
                } else {
                    let freed = store.backend.clearCache(kind)
                    message = String(format: "已清理 %.1f MB %@", freed, title)
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
