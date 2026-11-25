import AVFoundation
import Observation

/// Real spoken playback for the demo: system voice reads the current chapter,
/// while progress is driven by the synthesiser's spoken range.
@MainActor
@Observable
final class SpeechPlayer: NSObject, AVSpeechSynthesizerDelegate {
    var isPlaying = false
    var isPaused = false
    var progress: Double = 0
    var speed: Double = 1
    var title = ""
    var chapterTitle = ""
    var text = ""
    var elapsedLabel = "00:00"
    var remainingLabel = "00:00"

    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()
    @ObservationIgnored private var offset = 0
    @ObservationIgnored private var utteranceStart = 0
    @ObservationIgnored private var totalCharacters = 1
    @ObservationIgnored private var startedAt: Date?
    @ObservationIgnored private var accumulated: TimeInterval = 0
    @ObservationIgnored private var ticker: Task<Void, Never>?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    var hasChapter: Bool { !text.isEmpty }

    func load(book: Book, chapterTitle: String, text: String) {
        stop()
        title = book.title
        self.chapterTitle = chapterTitle
        self.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        totalCharacters = max(self.text.count, 1)
        offset = 0
        progress = 0
        accumulated = 0
        startedAt = nil
        updateLabels()
    }

    func toggle() {
        guard hasChapter else { return }
        if isPlaying {
            pause()
        } else if isPaused {
            resume()
        } else {
            speak(from: offset)
        }
    }

    func pause() {
        guard isPlaying else { return }
        synthesizer.pauseSpeaking(at: .immediate)
        isPlaying = false
        isPaused = true
        accumulated += startedAt.map { Date().timeIntervalSince($0) } ?? 0
        startedAt = nil
        ticker?.cancel()
    }

    func resume() {
        guard isPaused else { return }
        activateSession()
        synthesizer.continueSpeaking()
        isPlaying = true
        isPaused = false
        startedAt = Date()
        startTicker()
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        isPlaying = false
        isPaused = false
        ticker?.cancel()
        startedAt = nil
        deactivateSession()
    }

    func restart() {
        stop()
        offset = 0
        progress = 0
        accumulated = 0
        updateLabels()
    }

    func skip(_ characters: Int) {
        guard hasChapter else { return }
        // 先记下状态：stop() 会把 isPlaying / isPaused 一起清掉，
        // 否则「暂停中跳过」会被当成「停住」，剩余进度也就不再继续念。
        let wasPlaying = isPlaying
        let wasPaused = isPaused
        stop()
        offset = min(max(offset + characters, 0), totalCharacters - 1)
        progress = Double(offset) / Double(totalCharacters)
        accumulated = 0
        updateLabels()
        if wasPlaying {
            speak(from: offset)
        } else if wasPaused {
            // 保持暂停：把发音位置挪过去后再停住，用户按播放会从这里继续。
            isPaused = true
        }
    }

    func seek(to fraction: Double) {
        guard hasChapter else { return }
        let wasPlaying = isPlaying
        let wasPaused = isPaused
        stop()
        offset = Int(Double(totalCharacters - 1) * min(max(fraction, 0), 1))
        progress = Double(offset) / Double(totalCharacters)
        accumulated = 0
        updateLabels()
        if wasPlaying {
            speak(from: offset)
        } else if wasPaused {
            isPaused = true
        }
    }

    func setSpeed(_ value: Double) {
        speed = min(max(value, 0.5), 2)
        if isPlaying {
            stop()
            speak(from: offset)
        }
    }

    private func speak(from start: Int) {
        let start = min(max(start, 0), max(text.count - 1, 0))
        offset = start
        utteranceStart = start
        let remaining = String(text.dropFirst(start))
        guard !remaining.isEmpty else { return }

        activateSession()
        let utterance = AVSpeechUtterance(string: remaining)
        utterance.voice = AVSpeechSynthesisVoice(language: "zh-CN")
        utterance.rate = Float(min(max(0.5 * speed, 0.28), 0.92))
        utterance.pitchMultiplier = 0.96
        utterance.postUtteranceDelay = 0.08
        isPlaying = true
        isPaused = false
        startedAt = Date()
        synthesizer.speak(utterance)
        startTicker()
    }

    private func activateSession() {
        let session = AVAudioSession.sharedInstance()
        // 听书是主内容，不该被自己压低；用 .duckOthers 会让音乐之类在朗读时
        // 依旧以低音量播放，反而更吵。改为独占播放。
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.interruptSpokenAudioAndMixWithOthers])
        try? session.setActive(true)
    }

    /// 念完 / 停止后交还音频会话，避免一直占着系统音频焦点。
    private func deactivateSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setActive(false, options: [.notifyOthersOnDeactivation])
    }

    private func startTicker() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard let self, self.isPlaying else { return }
                self.updateLabels()
            }
        }
    }

    private func updateLabels() {
        let secondsPerCharacter = 0.22 / speed
        let elapsed = accumulated + (startedAt.map { Date().timeIntervalSince($0) } ?? 0)
        let spoken = Double(offset) + min(elapsed / secondsPerCharacter, Double(totalCharacters))
        let duration = Double(totalCharacters) * secondsPerCharacter
        let clampedElapsed = min(max(spoken * secondsPerCharacter, 0), duration)
        elapsedLabel = Self.label(clampedElapsed)
        remainingLabel = "-" + Self.label(max(duration - clampedElapsed, 0))
        if isPlaying {
            progress = min(max(spoken / Double(totalCharacters), 0), 0.999)
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        willSpeakRangeOfSpeechString characterRange: NSRange,
        utterance: AVSpeechUtterance
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let absolute = self.utteranceStart + characterRange.location
            self.progress = min(max(Double(absolute) / Double(self.totalCharacters), 0), 0.999)
            self.offset = absolute
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            // 念完后把计时与位置一起归零：否则 accumulated 会把上一轮时长
            // 带进下一轮，进度条和时间标签一开播就顶到结尾。
            // 界面停在「已念完」，用户再按播放即从头重听。
            let duration = Double(self.totalCharacters) * 0.22 / self.speed
            self.isPlaying = false
            self.isPaused = false
            self.progress = 1
            self.offset = 0
            self.accumulated = 0
            self.startedAt = nil
            self.ticker?.cancel()
            self.ticker = nil
            self.elapsedLabel = Self.label(duration)
            self.remainingLabel = "-" + Self.label(0)
            self.deactivateSession()
        }
    }

    static func label(_ value: TimeInterval) -> String {
        let total = Int(value.rounded())
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
