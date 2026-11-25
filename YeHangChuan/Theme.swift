import SwiftUI

enum Theme {
    static let paper = Color(hex: 0xF3EEE4)
    static let paperDeep = Color(hex: 0xE7DCC8)
    static let ink = Color(hex: 0x121820)
    static let text = Color(hex: 0xF1ECE2)
    static let secondary = Color(hex: 0xA69E8F)
    static let hairline = Color(hex: 0x3A424D)
    static let accent = Color(hex: 0xD56A4B)
    static let jade = Color(hex: 0x6FA795)

    private static let covers: [(Color, Color)] = [
        (Color(hex: 0x33404F), Color(hex: 0x1E2833)),
        (Color(hex: 0x6E4B38), Color(hex: 0x4A3125)),
        (Color(hex: 0x2E5B53), Color(hex: 0x1C3B36)),
        (Color(hex: 0x7B3C2C), Color(hex: 0x53251B)),
        (Color(hex: 0x45465F), Color(hex: 0x2B2C40)),
        (Color(hex: 0x5B5736), Color(hex: 0x3B3822))
    ]

    static func cover(_ style: Int) -> (Color, Color) {
        covers[abs(style) % covers.count]
    }
}

struct AppBackground: View {
    var body: some View {
        LinearGradient(
            stops: [
                .init(color: Color(hex: 0x0D141C), location: 0),
                .init(color: Color(hex: 0x121B25), location: 0.44),
                .init(color: Color(hex: 0x1B2026), location: 0.76),
                .init(color: Color(hex: 0x2A2119), location: 1)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}

private struct GlassSurfaceModifier: ViewModifier {
    let cornerRadius: CGFloat
    let tint: Color?
    let interactive: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            if let tint {
                content.glassEffect(
                    .regular.tint(tint).interactive(interactive),
                    in: .rect(cornerRadius: cornerRadius)
                )
            } else {
                content.glassEffect(
                    .regular.interactive(interactive),
                    in: .rect(cornerRadius: cornerRadius)
                )
            }
        } else {
            content
                .background(
                    .ultraThinMaterial,
                    in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(.white.opacity(0.35), lineWidth: 1)
                }
        }
    }
}

extension View {
    func glassSurface(
        cornerRadius: CGFloat = 20,
        tint: Color? = nil,
        interactive: Bool = false
    ) -> some View {
        modifier(GlassSurfaceModifier(cornerRadius: cornerRadius, tint: tint, interactive: interactive))
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

struct BookCover: View {
    let book: Book
    var compact = false

    var body: some View {
        let colors = Theme.cover(book.coverStyle)

        ZStack(alignment: .topLeading) {
            LinearGradient(colors: [colors.0, colors.1], startPoint: .topLeading, endPoint: .bottomTrailing)

            Rectangle()
                .fill(.black.opacity(0.16))
                .frame(width: compact ? 1 : 2)
                .padding(.leading, compact ? 4 : 7)

            VStack(alignment: .leading, spacing: 6) {
                Text(book.title)
                    .font(.system(size: compact ? 8 : 15, weight: .semibold, design: .serif))
                    .foregroundStyle(.white)
                    .lineLimit(compact ? 2 : 3)
                    .minimumScaleFactor(compact ? 0.7 : 0.8)

                Spacer(minLength: 4)

                Text(book.author)
                    .font(.system(size: compact ? 5.5 : 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.66))
                    .lineLimit(1)
            }
            .padding(compact ? 5 : 10)
            .padding(.leading, compact ? 2 : 4)

            if book.kind != .novel {
                Image(systemName: book.kind.symbol)
                    .font(.system(size: compact ? 5 : 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(compact ? 3 : 5)
                    .background(.black.opacity(0.2), in: Circle())
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(compact ? 3 : 6)
            }
        }
        .aspectRatio(0.72, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .overlay {
            RoundedRectangle(cornerRadius: 5)
                .stroke(.black.opacity(0.08))
        }
        .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
    }
}

struct ProgressBar: View {
    let value: Double
    var tint: Color = .white
    var track: Color = .white.opacity(0.2)

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule()
                    .fill(tint)
                    .frame(width: max(2, geometry.size.width * min(max(value, 0), 1)))
            }
        }
        .frame(height: 3)
    }
}

struct SectionHeading: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .tracking(1.5)
            .foregroundStyle(Theme.secondary)
    }
}

struct ToastView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .glassSurface(cornerRadius: 22)
            .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
            .allowsHitTesting(false)
    }
}

struct SettingsRow: View {
    let title: String
    var value: String?
    var systemImage: String?
    var showsChevron = true

    var body: some View {
        HStack(spacing: 12) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 22)
            }

            Text(title)
                .font(.system(size: 15))
                .foregroundStyle(Theme.text)

            Spacer()

            if let value {
                Text(value)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.secondary)
            }

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.secondary.opacity(0.45))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }
}

struct ToastModifier: ViewModifier {
    let text: String

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            ToastView(text: text)
                .padding(.bottom, 24)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
        .animation(.easeOut(duration: 0.2), value: text)
    }
}
