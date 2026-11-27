import SwiftUI
import UniformTypeIdentifiers
import UIKit

/// 文件选择器：直接包 `UIDocumentPickerViewController`，不用 SwiftUI 的 `.fileImporter`。
///
/// 为什么要绕这一层：`.fileImporter` 装在「本身也在 sheet 里」的视图上时，
/// 系统层面的 presentation 会撞车 —— 面板不弹、或者刚弹出就自己消失，
/// SwiftUI 也不会回报错误，用户看到的就是「点了没反应」。
/// UIKit 的 picker 由我们自己 present，生命周期可控。
///
/// `asCopy: true` 还有两个额外好处：
/// - iCloud 上尚未下载到本机的文件，系统会先下好再交给我们；
/// - 拿到的 URL 是本 App 沙箱内的副本，不再受 security-scoped 授权时限约束。
struct DocumentPicker: UIViewControllerRepresentable {
    /// 允许选择的类型。`.item` 表示「什么都能选」，格式判断交给导入逻辑按扩展名做 ——
    /// cbz / cbr 这类系统未声明的格式，一旦按 UTType 过滤就会整片置灰。
    var contentTypes: [UTType] = [.item]
    var allowsMultipleSelection = false
    var onPick: ([URL]) -> Void
    var onCancel: () -> Void = {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick, onCancel: onCancel)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: contentTypes,
            asCopy: true
        )
        picker.allowsMultipleSelection = allowsMultipleSelection
        picker.shouldShowFileExtensions = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {
        context.coordinator.onPick = onPick
        context.coordinator.onCancel = onCancel
    }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        var onPick: ([URL]) -> Void
        var onCancel: () -> Void

        init(onPick: @escaping ([URL]) -> Void, onCancel: @escaping () -> Void) {
            self.onPick = onPick
            self.onCancel = onCancel
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onPick(urls)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onCancel()
        }
    }
}
