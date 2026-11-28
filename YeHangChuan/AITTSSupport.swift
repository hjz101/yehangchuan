import AVFoundation
import Foundation
import Observation
import LegadoCore

enum AITTSPlaybackState: Equatable {
    case idle
    case loading
    case playing
    case paused
    case failed(String)

    var label: String {
        switch self {
        case .idle: "未播放"
        case .loading: "正在生成音频"
        case .playing: "AI TTS 播放中"
        case .paused: "AI TTS 已暂停"
        case .failed(let message): message
        }
    }
}

@MainActor
@Observable
final class AITTSPlayer {
    private(set) var engines: [HttpTTS] = []
    var selectedEngineID: Int64?
    private(set) var state: AITTSPlaybackState = .idle

    @ObservationIgnored private var player: AVPlayer?
    @ObservationIgnored private var endObserver: NSObjectProtocol?
    @ObservationIgnored private var audioURL: URL?
    @ObservationIgnored private var requestTask: Task<Void, Never>?

    var selectedEngine: HttpTTS? {
        guard let selectedEngineID else { return engines.first }
        return engines.first { $0.id == selectedEngineID }
    }

    var hasEngine: Bool { selectedEngine != nil }
    var isBusy: Bool { state == .loading }
    var isPlaying: Bool { state == .playing }

    deinit {
        requestTask?.cancel()
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
    }

    func loadEngines() async {
        do {
            let database = try LegadoDatabase(url: LegadoDatabase.defaultURL())
            let repository = SQLiteConfigurationRepository(database: database)
            let loaded = try await repository.loadHttpTTS()
            engines = loaded.filter {
                !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                !$0.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            if let selectedEngineID, engines.contains(where: { $0.id == selectedEngineID }) {
                return
            }
            selectedEngineID = engines.first?.id
        } catch {
            engines = []
            selectedEngineID = nil
            state = .failed("读取 HTTP TTS 配置失败：\(error.localizedDescription)")
        }
    }

    func start(text: String) {
        requestTask?.cancel()
        requestTask = Task { [weak self] in
            await self?.speak(text: text)
        }
    }

    private func speak(text: String) async {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            state = .failed("请先生成摘要，再开始 AI 朗读")
            return
        }
        guard let engine = selectedEngine else {
            state = .failed("没有可用的 HTTP TTS 配置，请先导入或配置一个引擎")
            return
        }

        stopPlayback()
        state = .loading

        do {
            let audio = try await HttpTTSService().audio(engine: engine, text: text, speechRate: 5)
            try Task.checkCancellation()
            let url = try writeAudio(audio)
            play(url: url)
        } catch is CancellationError {
            state = .idle
        } catch {
            state = .failed("AI TTS 请求失败：\(error.localizedDescription)")
        }
    }

    func togglePlayback() {
        guard let player else { return }
        switch state {
        case .playing:
            player.pause()
            state = .paused
        case .paused:
            player.play()
            state = .playing
        default:
            break
        }
    }

    func stop() {
        requestTask?.cancel()
        requestTask = nil
        stopPlayback()
        state = .idle
    }

    private func stopPlayback() {
        player?.pause()
        player = nil
        removeAudioFile()
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
    }

    private func writeAudio(_ audio: HttpTTSAudio) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "YeHangChuan-AITTS",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(audio.suggestedFileExtension)
        try audio.data.write(to: url, options: .atomic)
        audioURL = url
        return url
    }

    private func play(url: URL) {
        let player = AVPlayer(url: url)
        self.player = player
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.state = .idle
                self.player = nil
                self.removeAudioFile()
            }
        }
        player.play()
        state = .playing
    }

    private func removeAudioFile() {
        if let audioURL {
            try? FileManager.default.removeItem(at: audioURL)
            self.audioURL = nil
        }
    }
}
