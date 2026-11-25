import SwiftUI

struct StatsView: View {
    @Environment(AppStore.self) private var store

    @State private var hoveredDay: DayStat?

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackdrop()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        goalCard
                        weekCard
                        heatCard
                        insightCard
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 6)
                    .padding(.bottom, 40)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("阅读统计")
            .navigationSubtitle("连续 \(store.streak) 天 · 累计 \(formattedHours(store.totalMinutes))")
            .toolbarTitleDisplayMode(.inlineLarge)
        }
    }

    // MARK: Goal

    private var goalCard: some View {
        HStack(alignment: .center, spacing: 18) {
            RingProgress(
                value: store.goalProgress,
                lineWidth: 9,
                tint: Palette.accent,
                label: "\(store.todayMinutes)",
                caption: "/ \(store.goalMinutes) 分"
            )
            .frame(width: 84, height: 84)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text("今日阅读")
                        .font(.system(size: 16, weight: .semibold, design: .serif))
                        .foregroundStyle(Palette.text)

                    if store.todayMinutes >= store.goalMinutes {
                        Text("已达标")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Palette.onAccent)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2.5)
                            .background(Palette.jade, in: Capsule())
                    }
                }

                Text(goalMessage)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 14) {
                    metric("连续", "\(store.streak) 天", tint: Palette.gold)
                    metric("本周", formattedHours(store.weekMinutes), tint: Palette.jade)
                    metric("日均", "\(store.weekAverage) 分", tint: Palette.accent)
                }
                .padding(.top, 3)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .glassSurface(cornerRadius: 26)
    }

    private var goalMessage: String {
        let remaining = max(store.goalMinutes - store.todayMinutes, 0)
        if remaining == 0 {
            return "今天的灯已经点到位置了，留一点给明天。"
        }
        return "再读 \(remaining) 分钟就完成今天的目标。"
    }

    private func metric(_ title: String, _ value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(tint)
            Text(title)
                .font(.system(size: 9.5))
                .foregroundStyle(Palette.tertiary)
        }
    }

    // MARK: Week chart

    private var weekCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                SectionHeading(text: "最近 7 天")

                Spacer()

                Text("\(formattedHours(store.weekMinutes))")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Palette.text)
            }

            let peak = max(store.weekDays.map(\.minutes).max() ?? 1, 1)

            HStack(alignment: .bottom, spacing: 9) {
                ForEach(store.weekDays) { day in
                    VStack(spacing: 7) {
                        GeometryReader { geo in
                            let ratio = CGFloat(day.minutes) / CGFloat(peak)
                            let labelHeight: CGFloat = 13
                            let height = max(4, (geo.size.height - labelHeight) * ratio)

                            VStack(spacing: 3) {
                                Spacer(minLength: 0)

                                Text(day.minutes > 0 ? "\(day.minutes)" : "")
                                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                                    .foregroundStyle(day.isToday ? Palette.accent : Palette.tertiary)
                                    .monospacedDigit()
                                    .frame(height: labelHeight)

                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: day.isToday
                                                ? [Palette.accent, Palette.accent.opacity(0.55)]
                                                : [Palette.jade.opacity(0.75), Palette.jade.opacity(0.3)],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                                    .frame(height: height)
                            }
                        }
                        .frame(height: 112)

                        Text(day.isToday ? "今" : day.weekdayLabel)
                            .font(.system(size: 10, weight: day.isToday ? .bold : .medium))
                            .foregroundStyle(day.isToday ? Palette.accent : Palette.tertiary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }

            HStack(spacing: 14) {
                legendItem(color: Palette.accent, text: "今天")
                legendItem(color: Palette.jade, text: "其他日期")
                Spacer()
                Text("最高 \(peak) 分钟")
                    .font(.system(size: 9.5))
                    .foregroundStyle(Palette.tertiary)
            }
        }
        .padding(16)
        .glassSurface(cornerRadius: 26)
    }

    private func legendItem(color: Color, text: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(color)
                .frame(width: 7, height: 7)
            Text(text)
                .font(.system(size: 9.5))
                .foregroundStyle(Palette.tertiary)
        }
    }

    // MARK: Heatmap

    private var heatCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            SectionHeading(text: "阅读热力", trailing: "近 13 周")

            heatmap

            HStack(spacing: 9) {
                Text("少")
                    .font(.system(size: 9))
                    .foregroundStyle(Palette.tertiary)

                ForEach(0..<4, id: \.self) { level in
                    RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                        .fill(heatColor(level: level))
                        .frame(width: 10, height: 10)
                }

                Text("多")
                    .font(.system(size: 9))
                    .foregroundStyle(Palette.tertiary)

                Spacer()

                Text("平均 \(store.weekAverage) 分钟 / 天")
                    .font(.system(size: 9.5))
                    .foregroundStyle(Palette.tertiary)
            }
        }
        .padding(16)
        .glassSurface(cornerRadius: 26)
    }

    private var heatmap: some View {
        let days = Array(store.days.suffix(91))
        let columns = stride(from: 0, to: days.count, by: 7).map { Array(days[$0..<min($0 + 7, days.count)]) }

        return HStack(alignment: .top, spacing: 4) {
            ForEach(Array(columns.enumerated()), id: \.offset) { _, week in
                VStack(spacing: 4) {
                    ForEach(week) { day in
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(heatColor(for: day.minutes))
                            .frame(maxWidth: .infinity)
                            .frame(height: 13)
                            .overlay {
                                if day.isToday {
                                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                                        .strokeBorder(Palette.accent, lineWidth: 1.4)
                                }
                            }
                    }

                    if week.count < 7 {
                        ForEach(0..<(7 - week.count), id: \.self) { _ in
                            Color.clear.frame(height: 13)
                        }
                    }
                }
            }
        }
        .frame(height: 7 * 13 + 6 * 4)
    }

    private func heatColor(for minutes: Int) -> Color {
        switch minutes {
        case 0: Palette.faint
        case 1..<30: Palette.jade.opacity(0.22)
        case 30..<60: Palette.jade.opacity(0.42)
        case 60..<85: Palette.jade.opacity(0.66)
        default: Palette.jade.opacity(0.92)
        }
    }

    private func heatColor(level: Int) -> Color {
        switch level {
        case 0: Palette.faint
        case 1: Palette.jade.opacity(0.22)
        case 2: Palette.jade.opacity(0.55)
        default: Palette.jade.opacity(0.92)
        }
    }

    // MARK: Insight

    private var insightCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading(text: "这段时间")

            HStack(spacing: 10) {
                insightTile(
                    symbol: "calendar",
                    value: "周\(store.favoriteWeekday)",
                    caption: "读得最多"
                )
                insightTile(
                    symbol: "book.pages",
                    value: "\(store.excerpts.count)",
                    caption: "条摘录"
                )
                insightTile(
                    symbol: "flame",
                    value: "\(store.streak)",
                    caption: "天连续"
                )
            }

            Text(insightText)
                .font(.system(size: 11.5))
                .lineSpacing(4)
                .foregroundStyle(Palette.secondary)
                .padding(.top, 1)
        }
        .padding(16)
        .glassSurface(cornerRadius: 26)
    }

    private var insightText: String {
        let active = store.days.suffix(28).filter { $0.minutes > 0 }.count
        if active == 0 { return "还没有记录，翻开一本书就会开始累积。" }
        return "近四周有 \(active) 天在读书，最常在周\(store.favoriteWeekday)翻开书页。"
    }

    private func insightTile(symbol: String, value: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Palette.accent)

            Text(value)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(Palette.text)

            Text(caption)
                .font(.system(size: 9.5))
                .foregroundStyle(Palette.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(11)
        .glassSurface(cornerRadius: 17, tint: Palette.glassTint)
    }

    // MARK: Helpers

    private func formattedHours(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) 分钟" }
        let hours = Double(minutes) / 60
        return String(format: "%.1f 小时", hours)
    }
}
