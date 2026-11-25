import SwiftUI

struct SettingsView: View {
    @Environment(AppStore.self) private var store

    @State private var showReaderSettings = false
    @State private var showDistribution = false
    @State private var showGoal = false
    @State private var showAlert: SettingsAlert?

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackdrop()

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

                            SettingsRow(
                                title: "段评",
                                value: store.settings.hideSourceComments ? "已屏蔽" : "显示",
                                systemImage: "text.bubble",
                                showsChevron: false,
                                isLast: true
                            )
                        }

                        group("外观") {
                            VStack(alignment: .leading, spacing: 11) {
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
                            .padding(15)
                        }

                        group("数据") {
                            Button {
                                showAlert = .export
                            } label: {
                                SettingsRow(
                                    title: "导出书架数据",
                                    value: "JSON / Markdown",
                                    systemImage: "square.and.arrow.up"
                                )
                            }
                            .buttonStyle(.plain)

                            SettingsRow(
                                title: "摘录",
                                value: "\(store.excerpts.count) 条",
                                systemImage: "quote.opening",
                                showsChevron: false
                            )

                            SettingsRow(
                                title: "本机占用",
                                value: "12.4 MB",
                                systemImage: "internaldrive",
                                showsChevron: false,
                                isLast: true
                            )
                        }

                        group("分发") {
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
                                showAlert = .support
                            } label: {
                                SettingsRow(
                                    title: "支持开发者",
                                    value: "站外链接",
                                    systemImage: "heart",
                                    iconTint: Palette.accent,
                                    isLast: true
                                )
                            }
                            .buttonStyle(.plain)
                        }

                        group("关于") {
                            SettingsRow(
                                title: "版本",
                                value: "0.2.0 Liquid",
                                systemImage: "info.circle",
                                showsChevron: false,
                                isLast: true
                            )
                        }

                        Text("夜航船 · 本地优先的阅读器")
                            .font(.system(size: 10.5, design: .serif))
                            .foregroundStyle(Palette.tertiary)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 2)
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 6)
                    .padding(.bottom, 40)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("设置")
            .navigationSubtitle("无账号 · 数据留在本机")
            .toolbarTitleDisplayMode(.inlineLarge)
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
                store.showToast("每日目标已设为 \(value) 分钟")
            }
            .presentationDetents([.height(320)])
            .presentationCornerRadius(38)
        }
        .alert(item: $showAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("好"))
            )
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

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionHeading(text: title)

            VStack(spacing: 0) {
                content()
            }
            .glassSurface(cornerRadius: 22)
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
