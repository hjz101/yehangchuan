import Foundation
import Observation
import LegadoCore

/// 真实的网络请求记录。
///
/// 搜索、目录、正文、发现、段评、换源现在全部走 LegadoCore 的 HTTPClient，
/// 它把每一次请求写进 `DiagnosticLog`（落盘在 Application Support/Legado/Logs）。
/// 界面上的「网络日志」必须读这一份，否则用户看到的是另一套自说自话的假记录。
///
/// `DiagnosticLog` 默认不记录（`recordLog` 为 false），因为它会把 URL 写进磁盘。
/// 所以这里提供一个显式开关，让用户自己决定要不要留痕。
@MainActor
@Observable
final class NetworkDiagnostics {
    /// 是否正在记录请求。对应 LegadoCore 的 `ApplicationSettings.recordLog`。
    private(set) var isRecording: Bool

    /// 最近一次读取到的记录，新的在前。
    private(set) var entries: [DiagnosticLogEntry] = []

    /// 导出成纯文本，供「复制」用。
    var exportText: String { DiagnosticLog.shared.export() }

    init() {
        isRecording = ApplicationSettingsStore.shared.settings.recordLog
        refresh()
    }

    func setRecording(_ value: Bool) {
        var settings = ApplicationSettingsStore.shared.settings
        settings.recordLog = value
        // `save` 会做一次范围校验，这里只会失败在编码上，忽略即可保持开关可用。
        try? ApplicationSettingsStore.shared.save(settings)
        isRecording = value
        refresh()
    }

    func refresh() {
        entries = DiagnosticLog.shared.snapshot()
    }

    func clear() {
        try? DiagnosticLog.shared.clear()
        entries = []
    }
}
