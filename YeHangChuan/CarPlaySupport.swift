import SwiftUI
#if canImport(CarPlay)
import CarPlay
import UIKit

/// CarPlay 场景只读取 AppStore 的公开状态，不另起一份数据副本。
@MainActor
enum CarPlaySupport {
    static weak var store: AppStore?

    static var enabled: Bool {
        get { UserDefaults.standard.object(forKey: "yehangchuan.carplay") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "yehangchuan.carplay") }
    }
}

@MainActor
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        guard CarPlaySupport.enabled else {
            interfaceController.setRootTemplate(CPNowPlayingTemplate.shared, animated: false)
            return
        }
        let chapters: [Chapter] = {
            guard let store = CarPlaySupport.store else { return [] }
            return store.player.chapters
        }()
        let items = chapters.prefix(30).enumerated().map { index, chapter -> CPListItem in
            let item = CPListItem(text: chapter.title, detailText: "第 \(index + 1) 节", image: nil)
            item.handler = { _, completion in
                Task { @MainActor in
                    CarPlaySupport.store?.player.chapterIndex = index
                    completion()
                }
            }
            return item
        }
        let list = CPListTemplate(
            title: "夜航船 · 在听",
            sections: items.isEmpty ? [] : [CPListSection(items: Array(items))]
        )
        interfaceController.setRootTemplate(
            CPTabBarTemplate(templates: [list, CPNowPlayingTemplate.shared]),
            animated: false
        )
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnect interfaceController: CPInterfaceController
    ) {
        // 播放状态由 MPNowPlayingInfoCenter 托管，断开场景不需要额外清理。
    }
}
#endif
