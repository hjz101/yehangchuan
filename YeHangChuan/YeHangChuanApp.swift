import SwiftUI

@main
struct YeHangChuanApp: App {
    @State private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .tint(Theme.accent)
                .preferredColorScheme(.light)
        }
    }
}

struct RootView: View {
    @Environment(AppStore.self) private var store
    @State private var tab: AppTab = .shelf

    var body: some View {
        TabView(selection: $tab) {
            ShelfView()
                .tag(AppTab.shelf)
                .tabItem { Label("书架", systemImage: "books.vertical") }

            SourceView()
                .tag(AppTab.source)
                .tabItem { Label("书源", systemImage: "antenna.radiowaves.left.and.right") }

            SettingsView()
                .tag(AppTab.settings)
                .tabItem { Label("设置", systemImage: "slider.horizontal.3") }
        }
        .toolbarBackground(Theme.paper, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .overlay(alignment: .bottom) {
            if let toast = store.toast {
                ToastView(text: toast)
                    .padding(.bottom, 84)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.easeOut(duration: 0.2), value: store.toast)
        .onAppear {
            #if DEBUG
            let arguments = ProcessInfo.processInfo.arguments
            if arguments.contains("-openSource") {
                tab = .source
            } else if arguments.contains("-openSettings") {
                tab = .settings
            }
            if arguments.contains("-night") {
                store.settings.theme = .night
            }
            #endif
        }
    }
}

enum AppTab {
    case shelf
    case source
    case settings
}
