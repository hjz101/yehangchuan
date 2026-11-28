import LegadoCore
import SwiftUI
import WebKit

/// 书源登录弹窗。
///
/// 真正的登录内容在 `SourceLoginContent` / `SourceLoginModel` 里，沙箱直接复用
/// 同一套页面渲染，避免「登录页能打开、沙箱里却看不到」的分叉。
struct SourceLoginSheet: View {
    @Environment(\.dismiss) private var dismiss

    let source: BookSource
    let engineSource: LegadoCore.BookSource?
    var onFinished: (SourceLoginState) -> Void = { _ in }

    @State private var model: SourceLoginModel?

    var body: some View {
        NavigationStack {
            Group {
                if let model {
                    SourceLoginContent(model: model)
                } else {
                    ProgressView("正在准备登录页…")
                }
            }
            .navigationTitle("书源登录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        model?.finish()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .task(id: source.id) {
            let next = SourceLoginModel(
                source: source,
                engineSource: engineSource,
                onFinished: { state in onFinished(state) }
            )
            model = next
            await next.prepare()
        }
    }
}

/// 书源登录页的状态与动作。UI 只负责渲染，沙箱和弹窗共享同一份状态机。
@MainActor
final class SourceLoginModel: ObservableObject {
    enum Mode {
        case web(URL)
        case script
        case html
    }

    let source: BookSource
    let engineSource: LegadoCore.BookSource?
    let onFinished: (SourceLoginState) -> Void

    @Published var fields: [LoginField] = []
    @Published var values: [String: String] = [:]
    @Published var status = "正在准备登录页…"
    @Published var htmlReady = false
    @Published var webView: WKWebView?

    init(
        source: BookSource,
        engineSource: LegadoCore.BookSource?,
        onFinished: @escaping (SourceLoginState) -> Void
    ) {
        self.source = source
        self.engineSource = engineSource
        self.onFinished = onFinished
    }

    var mode: Mode? {
        guard let engineSource else { return nil }
        if HTMLSourceRegistry.shared.contains(engineSource.bookSourceUrl) { return .html }
        if let raw = engineSource.loginUrl?.trimmingCharacters(in: .whitespacesAndNewlines),
           !raw.isEmpty,
           let url = URL(string: raw),
           ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
            return .web(url)
        }
        if !(engineSource.loginUi ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .script
        }
        return nil
    }

    func prepare() async {
        guard let engineSource else { return }
        switch mode {
        case .script:
            if let raw = engineSource.loginUi,
               let data = raw.data(using: .utf8),
               let decoded = try? JSONDecoder().decode([LoginField].self, from: data) {
                fields = decoded
            }
            let saved = BookSourceRuntimeStore.shared.get(sourceID: engineSource.id, key: "loginInfo")
            if let data = saved.data(using: .utf8),
               let map = try? JSONDecoder().decode([String: String].self, from: data) {
                values = map
            }
            status = "填写后点「♥登录书源」，或直接用密钥登录。"
        case .html:
            do {
                let url = try await WebJavaScriptRuleEvaluator.shared.prepareHTMLSource(engineSource)
                status = url.isEmpty ? "登录页生成失败，请重试。" : "设置会自动写入本地缓存，完成后点右上角「完成」。"
                htmlReady = !url.isEmpty
            } catch {
                status = "登录页生成失败：\(error.localizedDescription)"
            }
        case .web, nil:
            status = "在页面内完成站点登录，然后点右上角「完成」保存会话。"
        }
    }

    func run(action: String) {
        guard let engineSource, !action.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if let data = try? JSONEncoder().encode(values), let text = String(data: data, encoding: .utf8) {
            BookSourceRuntimeStore.shared.put(sourceID: engineSource.id, key: "loginInfo", value: text)
        }
        status = "正在执行：\(action)"
        let evaluator = JavaScriptRuleEvaluator()
        Task { @MainActor in
            do {
                _ = try await evaluator.evaluateAsync(
                    script: "(0, eval)(String(source.loginUrl)); \(action)",
                    result: .null,
                    executionContext: .init(source: engineSource)
                )
                status = "登录脚本已执行，请看站点提示。"
            } catch {
                status = "登录失败：\(error.localizedDescription)"
            }
        }
    }

    func finish() {
        guard let engineSource else {
            onFinished(.signedOut)
            return
        }
        switch mode {
        case .web:
            webView?.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
                let host = URL(string: engineSource.bookSourceUrl)?.host ?? ""
                let pairs = cookies
                    .filter { host.isEmpty || $0.domain.hasSuffix(host) || host.hasSuffix($0.domain) }
                    .map { "\($0.name)=\($0.value)" }
                let header = pairs.joined(separator: "; ")
                if !header.isEmpty {
                    LegadoCookieStore.shared.setCookie(header, for: engineSource.bookSourceUrl)
                    if let data = try? JSONSerialization.data(withJSONObject: ["Cookie": header]),
                       let text = String(data: data, encoding: .utf8) {
                        BookSourceRuntimeStore.shared.put(
                            sourceID: engineSource.id, key: "loginHeader", value: text
                        )
                    }
                }
                DispatchQueue.main.async {
                    self?.onFinished(header.isEmpty ? .signedOut : .signedIn)
                }
            }
        case .script:
            onFinished(.signedIn)
        case .html:
            Task { @MainActor in
                do {
                    try await WebJavaScriptRuleEvaluator.shared.commitHTMLSourceLogin(engineSource)
                    onFinished(.signedIn)
                } catch {
                    status = "保存失败：\(error.localizedDescription)"
                }
            }
        case nil:
            onFinished(.signedOut)
        }
    }
}

/// 登录内容本体。`embedded = true` 时不再自己套 ScrollView，交给外层页面滚动，
/// 这样沙箱把它放进卡片时不会出现嵌套滚动抢手势。
struct SourceLoginContent: View {
    @Environment(\.theme) private var theme
    @ObservedObject var model: SourceLoginModel
    var embedded = false

    var body: some View {
        Group {
            if embedded {
                contentStack
            } else {
                ScrollView(.vertical) {
                    contentStack
                }
                .scrollContentBackground(.hidden)
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .legadoToast)) { notification in
            if let message = notification.userInfo?["message"] as? String, !message.isEmpty {
                model.status = message
            }
        }
    }

    private var contentStack: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Different source · 不同书源的登录方式不同。这里只保存你主动提交的会话，账号密码不会写回书源。")
                .font(.system(size: 11))
                .foregroundStyle(theme.secondary)

            switch model.mode {
            case .some(.web(let url)):
                SourceLoginWebView(url: url, webView: $model.webView)
                    .frame(minHeight: 420)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            case .some(.script):
                scriptForm
            case .some(.html):
                htmlPage
            case nil:
                Text("这条书源没有声明登录入口。")
                    .foregroundStyle(theme.secondary)
            }

            Text(model.status)
                .font(.system(size: 11))
                .foregroundStyle(theme.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(embedded ? 0 : 18)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var scriptForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(model.fields) { field in
                if field.isButton {
                    Button(field.name) { model.run(action: field.action ?? "") }
                        .buttonStyle(PressableStyle())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .glassCapsule(tint: theme.jade.opacity(0.12), interactive: true)
                } else if field.isPassword {
                    SecureField(field.name, text: binding(for: field.name))
                        .textFieldStyle(.roundedBorder)
                } else {
                    TextField(field.name, text: binding(for: field.name))
                        .textFieldStyle(.roundedBorder)
                }
            }
        }
    }

    @ViewBuilder
    private var htmlPage: some View {
        if model.htmlReady {
            WebViewContainer(view: WebJavaScriptRuleEvaluator.shared.hostedView())
                .frame(minHeight: 360)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        } else {
            ProgressView("正在生成登录设置页…")
        }
    }

    private func binding(for key: String) -> Binding<String> {
        Binding(
            get: { model.values[key] ?? "" },
            set: { model.values[key] = $0 }
        )
    }
}

struct LoginField: Codable, Identifiable {
    var name: String
    var type: String
    var action: String?

    var id: String { name + (action ?? "") }
    var isButton: Bool { type.lowercased() == "button" }
    var isPassword: Bool { type.lowercased() == "password" }
}

private struct WebViewContainer: UIViewRepresentable {
    let view: UIView

    func makeUIView(context: Context) -> UIView { view }
    func updateUIView(_ uiView: UIView, context: Context) {}
}

private struct SourceLoginWebView: UIViewRepresentable {
    let url: URL
    @Binding var webView: WKWebView?

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        let web = WKWebView(frame: .zero, configuration: configuration)
        context.coordinator.webView = web
        web.load(URLRequest(url: url))
        DispatchQueue.main.async { webView = web }
        return web
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject {
        var webView: WKWebView?
    }
}
