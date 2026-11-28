import SwiftUI
import UniformTypeIdentifiers

// MARK: - 主题编辑器子视图（P3-04/05/06 + P3-02）
//
// 所有子视图通过 Binding<Theme> 改 draft，不直接写 ThemeStore。
// 文件拆分：避免 ThemeEditor.swift 膨胀成下一个 3192 行单文件（技术评审 B）。

/// Color → UInt32 hex：通过 UIColor/NSColor 取 RGB 分量，编辑器的色选择器共用。
private func editorHexValue(_ color: Color) -> UInt32 {
    #if canImport(UIKit)
    let ui = UIColor(color)
    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
    ui.getRed(&r, green: &g, blue: &b, alpha: nil)
    return (UInt32(r * 255) << 16) | (UInt32(g * 255) << 8) | UInt32(b * 255)
    #else
    return 0x111A24
    #endif
}

// MARK: 色彩（P3-04）

struct ColorEditorView: View {
    @Binding var theme: Theme
    @Environment(\.theme) private var activeTheme

    private struct Role: Identifiable {
        let id = UUID()
        let name: String
        let get: (ThemeColor) -> ThemeColor
        let set: (inout ThemeColor, ThemeColor) -> Void
    }

    var body: some View {
        Form {
            Section("主色与文字") {
                ColorRow(title: "主色 accent", color: binding(\.accent))
                ColorRow(title: "强调实色 accentSolid", color: binding(\.accentSolid))
                ColorRow(title: "主色前景 onAccent", color: binding(\.onAccent))
                ColorRow(title: "正文 text", color: binding(\.text))
                ColorRow(title: "次级 secondary", color: binding(\.secondary))
                ColorRow(title: "三级 tertiary", color: binding(\.tertiary))
            }
            Section("辅助色") {
                ColorRow(title: "青 jade", color: binding(\.jade))
                ColorRow(title: "金 gold", color: binding(\.gold))
                ColorRow(title: "船木 sand", color: binding(\.sand))
                ColorRow(title: "暮蓝 blue", color: binding(\.blue))
                ColorRow(title: "分隔线 hairline", color: binding(\.hairline))
                ColorRow(title: "极淡 faint", color: binding(\.faint))
                ColorRow(title: "玻璃底色 glassTint", color: binding(\.glassTint))
            }
            Section("护栏") {
                if contrastIssues.isEmpty {
                    Text("accent ↔ onAccent 自动保持高对比；正文对比度不足时黄标提示，可用「一键修正」。")
                        .font(.caption)
                        .foregroundStyle(activeTheme.secondary)
                } else {
                    ForEach(contrastIssues, id: \.self) { warning in
                        Text(warning)
                            .font(.caption)
                            .foregroundStyle(.yellow)
                    }
                    Button("一键修正正文对比度") { fixTextContrast() }
                }
            }
        }
    }

    /// 背景浅档：systemMesh/渐变/图片等无单一 hex 的配置统一用夜色水面的浅档兜底。
    private var backgroundLight: UInt32 {
        switch theme.backdrop {
        case let .solid(spec):
            switch spec {
            case let .adaptive(light, _, _, _): return light
            case let .fixed(hex, _): return hex
            case .system: return 0xF7F9FD
            }
        default: return 0xF7F9FD
        }
    }

    /// 背景深档：供 text.dark 同步修正，纯色取 dark，其余走深色兜底。
    private var backgroundDark: UInt32 {
        switch theme.backdrop {
        case let .solid(spec):
            switch spec {
            case let .adaptive(_, dark, _, _): return dark
            case let .fixed(hex, _): return hex
            case .system: return 0x0A0E14
            }
        default: return 0x0A0E14
        }
    }

    /// 关键色对实时校验：正文/背景、强调色按钮、次级文字。
    private var contrastIssues: [String] {
        ThemeEngine.warnings(pairs: [
            (name: "正文/背景", fg: theme.colors.text.light, bg: backgroundLight, min: 4.5),
            (name: "强调色按钮", fg: theme.colors.onAccent.light, bg: theme.colors.accentSolid.light, min: 4.5),
            (name: "次级文字", fg: theme.colors.secondary.light, bg: backgroundLight, min: 3.0)
        ])
    }

    /// 只修正文双档（不擅自改次级/强调色），修完黄标自然消失。
    private func fixTextContrast() {
        theme.colors.text.light = ThemeEngine.suggestedTextColor(background: backgroundLight)
        theme.colors.text.dark = ThemeEngine.suggestedTextColor(background: backgroundDark)
    }

    /// 每个色角色用浅/深双色选择器编辑（UInt32 hex）。
    private func binding(_ key: WritableKeyPath<ColorRoles, ThemeColor>) -> Binding<ThemeColor> {
        Binding(
            get: { theme.colors[keyPath: key] },
            set: { theme.colors[keyPath: key] = $0 }
        )
    }
}

private struct ColorRow: View {
    let title: String
    @Binding var color: ThemeColor

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline)
            HStack {
                ColorPicker("浅色", selection: Binding(
                    get: { Color(hex: color.light) },
                    set: { color.light = editorHexValue($0) }
                ))
                ColorPicker("深色", selection: Binding(
                    get: { Color(hex: color.dark) },
                    set: { color.dark = editorHexValue($0) }
                ))
            }
        }
    }
}

// MARK: 字体（P3-02 导入 + G4 字族选择面板）

struct FontGroupView: View {
    @Binding var theme: Theme
    @Environment(\.theme) private var activeTheme

    var body: some View {
        Form {
            Section("字族") {
                Picker("界面字体", selection: Binding(
                    get: { theme.typography.uiFamily },
                    set: { theme.typography.uiFamily = $0 }
                )) {
                    Text("系统默认").tag(FontFamilySpec.system(design: .default))
                    Text("衬线").tag(FontFamilySpec.system(design: .serif))
                    Text("圆体").tag(FontFamilySpec.system(design: .rounded))
                    Text("等宽").tag(FontFamilySpec.system(design: .monospaced))
                }
                Picker("标题字体", selection: Binding(
                    get: { theme.typography.titleFamily },
                    set: { theme.typography.titleFamily = $0 }
                )) {
                    Text("系统默认").tag(FontFamilySpec.system(design: .default))
                    Text("衬线").tag(FontFamilySpec.system(design: .serif))
                    Text("圆体").tag(FontFamilySpec.system(design: .rounded))
                }
            }
            Section("导入字体") {
                Text("从文件 App 导入 ttf/otf。导入前需确认拥有合法使用授权。")
                    .font(.caption)
                    .foregroundStyle(activeTheme.secondary)
                // P3-02：字体导入入口在 ThemeEditor sheet 内，必须复用 DocumentPicker。
                FontImportButton(theme: $theme)
            }
        }
    }
}

/// 字体导入按钮：复用 DocumentPicker（禁 .fileImporter），版权钩子挂 onPick 内。
private struct FontImportButton: View {
    @Binding var theme: Theme
    @State private var showPicker = false
    @State private var showCopyright = false
    @State private var pendingURL: URL?

    var body: some View {
        Button("导入字体文件") { showPicker = true }
            .sheet(isPresented: $showPicker) {
                DocumentPicker(contentTypes: [.item]) { urls in
                    // 合规 B3：拿到 URL 后、落盘/注册之前先确认版权。
                    if let url = urls.first {
                        pendingURL = url
                        showCopyright = true
                    }
                }
                .presentationDetents([.medium])
            }
            .alert("字体版权确认", isPresented: $showCopyright) {
                Button("取消", role: .cancel) { pendingURL = nil }
                Button("确认导入") {
                    if let url = pendingURL { importFont(url) }
                    pendingURL = nil
                }
            } message: {
                Text("请确认你拥有该字体的合法使用授权。App 不内置任何字体，仅导入你自有的字体文件。")
            }
    }

    private func importFont(_ url: URL) {
        guard let data = try? Data(contentsOf: url) else { return }
        let ext = url.pathExtension.lowercased()
        guard ["ttf", "otf"].contains(ext) else { return }
        // magic bytes 校验：ttf 0x00010000 / true，otf OTTO。
        let head = Array(data.prefix(4))
        let valid = head == [0x00, 0x01, 0x00, 0x00] || head == Array("true".utf8) || head == Array("OTTO".utf8)
        guard valid else { return }
        if let ref = try? ThemeAssetStore.shared.importAsset(data: data, ext: ext) {
            let name = FontRegistry.postScriptName(for: url) ?? ""
            theme.typography.uiFamily = .imported(assetID: ref.id, postScriptName: name)
        }
    }
}

// MARK: 背景（P3-05 Mesh 锚点 + P3-06 背景类型）

struct BackdropEditorView: View {
    @Binding var theme: Theme
    @Environment(\.theme) private var activeTheme

    var body: some View {
        Form {
            Section("背景类型") {
                Picker("类型", selection: Binding(
                    get: { theme.backdrop },
                    set: { theme.backdrop = $0 }
                )) {
                    Text("夜色水面（内置）").tag(BackgroundSpec.systemMesh)
                    Text("纯色").tag(BackgroundSpec.solid(.system))
                    Text("线性渐变").tag(BackgroundSpec.linear(
                        colors: [.system, .system],
                        start: ThemePoint(x: 0, y: 0), end: ThemePoint(x: 1, y: 1)
                    ))
                }
            }
            Section("光斑（≤3、静态）") {
                Text("光斑数量 \(theme.glows.count)/3。均为静态，无动画字段。")
                    .font(.caption)
                    .foregroundStyle(activeTheme.secondary)
                Stepper("数量", value: Binding(
                    get: { theme.glows.count },
                    set: { count in
                        if count < theme.glows.count { theme.glows.removeLast() }
                        else if count > theme.glows.count && theme.glows.count < 3 {
                            theme.glows.append(GlowSpec())
                        }
                    }
                ), in: 0...3)
            }
            Section("MeshGradient 锚点") {
                Text("3×3~5×5 锚点拖拽与逐点取色（P3-05）。结构禁止任何时间/动画字段。")
                    .font(.caption)
                    .foregroundStyle(activeTheme.secondary)
                MeshAnchorEditor(theme: $theme)
            }
        }
    }
}

/// Mesh 锚点编辑：内部点可拖、边缘点吸附边界（静态，无动画）。
private struct MeshAnchorEditor: View {
    @Binding var theme: Theme
    /// 选中/正在拖动的锚点用 row*cols+col 线性下标表示，避免可选元组。
    @State private var selectedIndex: Int?
    @State private var draggingIndex: Int?

    var body: some View {
        Group {
            if case let .mesh(points, colors) = theme.backdrop {
                let rows = points.count
                let cols = points.first?.count ?? 0
                VStack(alignment: .leading, spacing: 8) {
                    Text("当前 \(rows)×\(cols) 网格，\(colors.count) 个配色点")
                        .font(.caption)
                    Picker("网格规模", selection: Binding(
                        get: { rows },
                        set: { newRows in
                            selectedIndex = nil
                            draggingIndex = nil
                            theme.backdrop = Self.resized(rows: newRows, cols: newRows)
                        }
                    )) {
                        Text("3×3").tag(3)
                        Text("4×4").tag(4)
                        Text("5×5").tag(5)
                    }
                    .pickerStyle(.segmented)

                    GeometryReader { geo in
                        ZStack {
                            // 静态网格线：只从当前点集连线，无任何时间/动画字段。
                            Path { path in
                                for r in 0..<rows {
                                    for c in 0..<cols {
                                        guard points.indices.contains(r),
                                              points[r].indices.contains(c),
                                              points[r][c].count >= 2 else { continue }
                                        let p = CGPoint(
                                            x: CGFloat(points[r][c][0]) * geo.size.width,
                                            y: CGFloat(points[r][c][1]) * geo.size.height
                                        )
                                        if c + 1 < cols, points[r].indices.contains(c + 1),
                                           points[r][c + 1].count >= 2 {
                                            let next = CGPoint(
                                                x: CGFloat(points[r][c + 1][0]) * geo.size.width,
                                                y: CGFloat(points[r][c + 1][1]) * geo.size.height
                                            )
                                            path.move(to: p)
                                            path.addLine(to: next)
                                        }
                                        if r + 1 < rows, points.indices.contains(r + 1),
                                           points[r + 1].indices.contains(c),
                                           points[r + 1][c].count >= 2 {
                                            let next = CGPoint(
                                                x: CGFloat(points[r + 1][c][0]) * geo.size.width,
                                                y: CGFloat(points[r + 1][c][1]) * geo.size.height
                                            )
                                            path.move(to: p)
                                            path.addLine(to: next)
                                        }
                                    }
                                }
                            }
                            .stroke(Color.secondary.opacity(0.35), lineWidth: 1)

                            ForEach(0..<rows, id: \.self) { r in
                                ForEach(0..<cols, id: \.self) { c in
                                    if points.indices.contains(r), points[r].indices.contains(c),
                                       points[r][c].count >= 2 {
                                        let index = r * cols + c
                                        let spec = colors.indices.contains(index)
                                            ? colors[index] : ColorSpec.system
                                        Circle()
                                            .fill(Color(hex: spec.editorLightHex))
                                            .overlay {
                                                Circle()
                                                    .stroke(
                                                        selectedIndex == index ? Color.primary : Color.clear,
                                                        lineWidth: 2
                                                    )
                                            }
                                            .frame(width: 14, height: 14)
                                            .position(
                                                x: CGFloat(points[r][c][0]) * geo.size.width,
                                                y: CGFloat(points[r][c][1]) * geo.size.height
                                            )
                                    }
                                }
                            }

                            // 整块画布统一接管拖拽：按起点就近抓取锚点，location 是容器坐标，
                            // 避免逐个 Circle 挂手势时的坐标系与复用闭包问题。
                            Color.clear
                                .contentShape(Rectangle())
                                .gesture(DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        moveAnchor(
                                            location: value.location,
                                            start: value.startLocation,
                                            size: geo.size
                                        )
                                    }
                                    .onEnded { _ in draggingIndex = nil })
                        }
                    }
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                    }

                    if let index = selectedIndex, colors.indices.contains(index), cols > 0 {
                        let r = index / cols
                        let c = index % cols
                        ColorPicker("锚点颜色（第 \(r + 1) 行 第 \(c + 1) 列）", selection: Binding(
                            get: { Color(hex: colors[index].editorLightHex) },
                            set: { updateColor(at: index, from: colors[index], hex: editorHexValue($0)) }
                        ))
                    }
                    Text("点选锚点后可取色；内部点可自由拖动，边界点只沿所在边滑动。")
                        .font(.caption)
                        .foregroundStyle(Color.secondary)
                }
            } else {
                Button("从夜色水面创建 3×3 网格") {
                    selectedIndex = nil
                    draggingIndex = nil
                    theme.backdrop = Self.resized(rows: 3, cols: 3)
                }
            }
        }
    }

    /// 拖拽锚点：边界点固定一维（上/下固定 y、左/右固定 x），可动维度 clamp 到 0.02...0.98。
    private func moveAnchor(location: CGPoint, start: CGPoint, size: CGSize) {
        guard case let .mesh(originalPoints, colors) = theme.backdrop,
              !originalPoints.isEmpty, let cols = originalPoints.first?.count, cols > 0 else { return }
        var points = originalPoints
        let rows = points.count
        let index: Int
        if let draggingIndex {
            index = draggingIndex
        } else {
            // 首次触碰：按起点归一化距离抓取最近锚点。
            let sx = start.x / max(size.width, 1)
            let sy = start.y / max(size.height, 1)
            var best = 0
            var bestDistance = Double.greatestFiniteMagnitude
            for r in 0..<rows {
                for c in 0..<cols {
                    guard points.indices.contains(r), points[r].indices.contains(c),
                          points[r][c].count >= 2 else { continue }
                    let dx = points[r][c][0] - sx
                    let dy = points[r][c][1] - sy
                    let distance = dx * dx + dy * dy
                    if distance < bestDistance {
                        bestDistance = distance
                        best = r * cols + c
                    }
                }
            }
            index = best
            draggingIndex = best
            selectedIndex = best
        }
        let r = index / cols
        let c = index % cols
        guard points.indices.contains(r), points[r].indices.contains(c),
              points[r][c].count >= 2 else { return }
        let x = min(max(location.x / max(size.width, 1), 0.02), 0.98)
        let y = min(max(location.y / max(size.height, 1), 0.02), 0.98)
        let atTop = r == 0
        let atBottom = r == rows - 1
        let atLeft = c == 0
        let atRight = c == cols - 1
        if !atLeft && !atRight { points[r][c][0] = x }
        if !atTop && !atBottom { points[r][c][1] = y }
        theme.backdrop = .mesh(points: points, colors: colors)
    }

    /// 逐点取色：保留原深色档/透明度，只替换浅档 hex（ColorSpec 是 mesh 的实际配色类型）。
    private func updateColor(at index: Int, from spec: ColorSpec, hex: UInt32) {
        guard case let .mesh(points, var colors) = theme.backdrop,
              colors.indices.contains(index) else { return }
        colors[index] = spec.editorReplacingLight(hex)
        theme.backdrop = .mesh(points: points, colors: colors)
    }

    private static func resized(rows: Int, cols: Int) -> BackgroundSpec {
        let points = (0..<rows).map { r in
            (0..<cols).map { c -> [Double] in
                [Double(c) / Double(max(1, cols - 1)), Double(r) / Double(max(1, rows - 1))]
            }
        }
        return .mesh(points: points, colors: Array(repeating: .system, count: rows * cols))
    }
}

/// mesh 配色点以 ColorSpec 持久化；这里只暴露浅档 hex 给 ColorPicker，深档/透明度原样保留。
private extension ColorSpec {
    var editorLightHex: UInt32 {
        switch self {
        case .system: return 0x111A24
        case let .adaptive(light, _, _, _): return light
        case let .fixed(hex, _): return hex
        }
    }

    func editorReplacingLight(_ hex: UInt32) -> ColorSpec {
        switch self {
        case .system:
            return .adaptive(light: hex, dark: 0xF4F0E8)
        case let .adaptive(_, dark, lightOpacity, darkOpacity):
            return .adaptive(
                light: hex, dark: dark,
                lightOpacity: lightOpacity, darkOpacity: darkOpacity
            )
        case let .fixed(_, opacity):
            return .fixed(hex, opacity: opacity)
        }
    }
}

// MARK: 玻璃与组件（P3-06）

struct ComponentStyleView: View {
    @Binding var theme: Theme

    var body: some View {
        Form {
            Section("玻璃") {
                Picker("强度", selection: Binding(
                    get: { theme.shape.glassStrength },
                    set: { theme.shape.glassStrength = $0 }
                )) {
                    ForEach(1...5, id: \.self) { Text("\($0) 档").tag($0) }
                }
                Slider(value: Binding(
                    get: { theme.shape.cornerRadiusScale },
                    set: { theme.shape.cornerRadiusScale = $0 }
                ), in: 0.6...1.6, label: { Text("圆角缩放") })
            }
            Section("按压反馈") {
                Slider(value: Binding(
                    get: { theme.shape.pressScale },
                    set: { theme.shape.pressScale = $0 }
                ), in: 0.8...1.0, label: { Text("按压缩放") })
            }
        }
    }
}

// MARK: 阅读排版（P3-06 + D20）

struct ReaderTypographyView: View {
    @Binding var theme: Theme
    @Environment(\.theme) private var activeTheme

    var body: some View {
        Form {
            Section("字符与段落") {
                Slider(value: Binding(
                    get: { theme.typography.tracking },
                    set: { theme.typography.tracking = $0 }
                ), in: 0...2, label: { Text("字符间距 \(theme.typography.tracking, specifier: "%.1f")pt") })
                Slider(value: Binding(
                    get: { theme.typography.paragraphSpacing },
                    set: { theme.typography.paragraphSpacing = $0 }
                ), in: 0...8, label: { Text("段距 \(theme.typography.paragraphSpacing, specifier: "%.1f")pt") })
            }
            Section("说明") {
                Text("字号/字重/行距/版心的唯一真相在阅读设置里；此处仅编辑界面级字符与段落间距。")
                    .font(.caption)
                    .foregroundStyle(activeTheme.secondary)
            }
        }
    }
}

// MARK: 加载与状态（P3-06）

struct LoadingEditorView: View {
    @Binding var theme: Theme

    var body: some View {
        Form {
            Picker("加载样式", selection: Binding(
                get: { theme.loading.style },
                set: { theme.loading.style = $0 }
            )) {
                Text("转圈").tag(LoadingStyle.spinner)
                Text("品牌标记").tag(LoadingStyle.brandMark)
                Text("图片").tag(LoadingStyle.artwork)
                Text("骨架屏").tag(LoadingStyle.skeleton)
            }
            Picker("转场", selection: Binding(
                get: { theme.loading.transition },
                set: { theme.loading.transition = $0 }
            )) {
                Text("灵动").tag(TransitionSpec.lively)
                Text("克制").tag(TransitionSpec.restrained)
                Text("关闭").tag(TransitionSpec.off)
            }
        }
    }
}

// MARK: 主题库 CRUD（P3-03）

struct ThemeLibraryView: View {
    @Binding var draft: Theme
    let original: Theme
    /// 点内置预设即刻换肤（由 ThemeEditor 调 onApply + dismiss）。
    let onPreset: (Theme) -> Void
    let onDelete: (Theme) -> Void
    let onRestore: () -> Void

    @Environment(\.theme) private var activeTheme

    var body: some View {
        Form {
            Section("内置预设") {
                ForEach(BuiltinThemes.all) { preset in
                    Button {
                        // 已是当前预设时只高亮，不重复应用。
                        guard preset.id != draft.id else { return }
                        onPreset(preset)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(preset.name)
                                Text("内置主题")
                                    .font(.caption2)
                                    .foregroundStyle(activeTheme.secondary)
                            }
                            Spacer()
                            if preset.id == draft.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(activeTheme.accent)
                                    .accessibilityLabel("当前主题")
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(preset.id == draft.id)
                }
            }
            Section("当前主题") {
                TextField("名称", text: Binding(
                    get: { draft.name },
                    set: { draft.name = $0 }
                ))
                Button("复制为新主题") {
                    draft = Theme(
                        name: original.name + " 副本",
                        colors: draft.colors,
                        backdrop: draft.backdrop,
                        glows: draft.glows,
                        reading: draft.reading,
                        typography: draft.typography,
                        loading: draft.loading,
                        shape: draft.shape
                    )
                }
            }
            Section("危险操作") {
                Button("删除当前主题", role: .destructive) {
                    guard !original.builtin else { return }
                    onDelete(original)
                    onRestore()
                }
                .disabled(original.builtin)
                if original.builtin {
                    Text("内置主题不可删除")
                        .font(.caption)
                        .foregroundStyle(activeTheme.secondary)
                }
            }
        }
    }
}
