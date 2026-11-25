import SwiftUI

struct SettingsView: View {
    @Environment(AppStore.self) private var store

    @State private var showReaderSettings = false
    @State private var showDistribution = false
    @State private var showExportAlert = false
    @State private var showSupportAlert = false

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.paper.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        header

                        group("阅读") {
                            Button {
                                showReaderSettings = true
                            } label: {
                                SettingsRow(
                                    title: "阅读设置",
                                    value: "\(Int(store.settings.fontSize)) pt · \(store.settings.theme.rawValue)",
                                    systemImage: "textformat.size"
                                )
                            }
                            .buttonStyle(.plain)
                        }

                        group("数据") {
                            Button {
                                showExportAlert = true
                            } label: {
                                SettingsRow(title: "导出书架数据", value: "JSON / Markdown", systemImage: "square.and.arrow.up")
                            }
                            .buttonStyle(.plain)

                            divider

                            SettingsRow(title: "本机占用", value: "12.4 MB", systemImage: "internaldrive", showsChevron: false)
                        }

                        group("分发") {
                            Button {
                                showDistribution = true
                            } label: {
                                SettingsRow(title: "安装与更新", value: "TestFlight · 免费", systemImage: "shippingbox")
                            }
                            .buttonStyle(.plain)

                            divider

                            Button {
                                showSupportAlert = true
                            } label: {
                                SettingsRow(title: "支持开发者", value: "站外链接", systemImage: "heart")
                            }
                            .buttonStyle(.plain)
                        }

                        group("关于") {
                            SettingsRow(title: "版本", value: "0.1.0 Demo", systemImage: "info.circle", showsChevron: false)
                        }

                        Text("夜航船 · 本地优先的阅读器")
                            .font(.system(size: 11, design: .serif))
                            .foregroundStyle(Theme.secondary.opacity(0.7))
                            .frame(maxWidth: .infinity)
                            .padding(.top, 4)
                    }
                    .padding(.top, 16)
                    .padding(.bottom, 112)
                }
                .scrollIndicators(.hidden)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .sheet(isPresented: $showReaderSettings) {
            ReaderSettingsSheet(settings: store.settings)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showDistribution) {
            DistributionSheet()
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .alert("导出数据", isPresented: $showExportAlert) {
            Button("好", role: .cancel) {}
        } message: {
            Text("演示版本暂未实现导出，这里用于确认入口位置。")
        }
        .alert("支持开发者", isPresented: $showSupportAlert) {
            Button("好", role: .cancel) {}
        } message: {
            Text("演示版本不接入支付，仅保留站外支持入口。")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("设置")
                .font(.system(size: 32, weight: .bold, design: .serif))
                .foregroundStyle(Theme.text)

            Text("无账号 · 数据留在本机")
                .font(.system(size: 13))
                .foregroundStyle(Theme.secondary)
        }
        .padding(.horizontal, 20)
    }

    private var divider: some View {
        Divider()
            .overlay(Theme.hairline)
            .padding(.leading, 50)
    }

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeading(text: title)
                .padding(.horizontal, 20)

            VStack(spacing: 0) {
                content()
            }
            .background(Color.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8).stroke(Theme.hairline)
            }
            .padding(.horizontal, 20)
        }
    }
}

struct DistributionSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.paper.ignoresSafeArea()

                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: "shippingbox")
                            .font(.system(size: 22, weight: .light))
                            .foregroundStyle(Theme.accent)
                            .frame(width: 30)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("TestFlight / 自签安装")
                                .font(.system(size: 16, weight: .semibold, design: .serif))
                                .foregroundStyle(Theme.text)

                            Text("当前为演示构建，仅用于界面与交互评估。")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.secondary)
                        }
                    }

                    Divider().overlay(Theme.hairline)

                    infoRow("安装方式", "TestFlight")
                    infoRow("构建有效期", "2027-05-24")
                    infoRow("更新渠道", "GitHub Releases")
                    infoRow("价格", "免费")

                    Spacer()
                }
                .padding(20)
            }
            .navigationTitle("安装与更新")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private func infoRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(Theme.secondary)

            Spacer()

            Text(value)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.text)
        }
    }
}
