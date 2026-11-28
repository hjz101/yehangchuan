import AVFoundation
import MediaPlayer
import Observation
import UIKit

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
    /// 睡眠定时（分钟），0 表示关闭。到点后暂停朗读。
    var sleepMinutes = 0

    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()
    @ObservationIgnored private var offset = 0
    @ObservationIgnored private var utteranceStart = 0
    @ObservationIgnored private var totalCharacters = 1
    @ObservationIgnored private var startedAt: Date?
    @ObservationIgnored private var accumulated: TimeInterval = 0
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private var sleepTask: Task<Void, Never>?
    @ObservationIgnored private lazy var artwork: MPMediaItemArtwork? = Self.makeArtwork()

    private struct SpokenSegment {
        let text: String
        let voice: AVSpeechSynthesisVoice?
        /// 在整章文本里的起始字符位置，用于跨段累计进度。
        let start: Int
    }
    @ObservationIgnored private var spokenSegments: [SpokenSegment] = []
    @ObservationIgnored private var currentSegment = 0
    /// 自然念完一段后是否继续下一段；stop() 会清掉它。
    @ObservationIgnored private var continueAfterFinish = false

    override init() {
        super.init()
        synthesizer.delegate = self
        setupRemoteCommands()
    }

    var hasChapter: Bool { !text.isEmpty }

    func load(book: Book, chapterTitle: String, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        load(book: book, chapterTitle: chapterTitle, segments: [
            SpeechSegment(text: trimmed, role: VoiceCatalog.narrator)
        ])
    }

    /// 多角色朗读：每段可指定系统声线，段与段之间连续播，进度按整章字符数累计。
    func load(book: Book, chapterTitle: String, segments: [SpeechSegment]) {
        stop()
        title = book.title
        self.chapterTitle = chapterTitle
        let cleaned = segments
            .map { SpeechSegment(text: $0.text.trimmingCharacters(in: .whitespacesAndNewlines),
                                  role: $0.role, voiceIdentifier: $0.voiceIdentifier) }
            .filter { !$0.text.isEmpty }
        self.text = cleaned.map(\.text).joined(separator: "\n")
        var cursor = 0
        spokenSegments = cleaned.map { segment in
            let item = SpokenSegment(
                text: segment.text,
                voice: VoiceCatalog.voice(identifier: segment.voiceIdentifier),
                start: cursor
            )
            cursor += segment.text.count + 1 // 与 joined("\n") 的字符数对齐
            return item
        }
        totalCharacters = max(cursor - 1, 1)
        currentSegment = 0
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
        updateNowPlaying()
    }

    func resume() {
        guard isPaused else { return }
        activateSession()
        // 暂停后如果又跳转/拖动过，发音队列已经被 stop() 清空，
        // continueSpeaking() 没有可继续的语句；此时必须从当前 offset 重新开口，
        // 否则会出现「进度在走但没有声音」。
        if synthesizer.isPaused {
            synthesizer.continueSpeaking()
        } else {
            speak(from: offset)
        }
        isPlaying = true
        isPaused = false
        startedAt = Date()
        startTicker()
        updateNowPlaying()
    }

    func stop() {
        continueAfterFinish = false
        synthesizer.stopSpeaking(at: .immediate)
        isPlaying = false
        isPaused = false
        ticker?.cancel()
        cancelSleepTimer()
        startedAt = nil
        deactivateSession()
        updateNowPlaying()
    }

    /// 睡眠定时：只作用于系统语音朗读，到点暂停，不影响有声书播放器。
    func setSleepTimer(_ minutes: Int) {
        sleepTask?.cancel()
        sleepTask = nil
        sleepMinutes = max(minutes, 0)
        guard sleepMinutes > 0 else { return }
        sleepTask = Task { [weak self] in
            for _ in 0..<minutes {
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled else { return }
            }
            await MainActor.run { [weak self] in
                self?.pause()
                self?.sleepMinutes = 0
                self?.sleepTask = nil
            }
        }
    }

    private func cancelSleepTimer() {
        sleepTask?.cancel()
        sleepTask = nil
        sleepMinutes = 0
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
        updateNowPlaying()
    }

    private func speak(from start: Int) {
        let start = min(max(start, 0), max(totalCharacters - 1, 0))
        guard let index = spokenSegments.firstIndex(where: {
                $0.start <= start && start < $0.start + $0.text.count
              }) ?? spokenSegments.lastIndex(where: { $0.start <= start }) else {
            finishAll()
            return
        }
        let segment = spokenSegments[index]
        let localStart = min(max(start - segment.start, 0), segment.text.count - 1)
        let remaining = String(segment.text.dropFirst(localStart))
        guard !remaining.isEmpty else {
            if index + 1 < spokenSegments.count {
                speak(from: spokenSegments[index + 1].start)
            } else {
                finishAll()
            }
            return
        }
        offset = start
        utteranceStart = segment.start
        currentSegment = index
        continueAfterFinish = true
        activateSession()
        let utterance = AVSpeechUtterance(string: remaining)
        utterance.voice = segment.voice ?? AVSpeechSynthesisVoice(language: "zh-CN")
        utterance.rate = Float(min(max(0.5 * speed, 0.28), 0.92))
        utterance.pitchMultiplier = 0.96
        utterance.postUtteranceDelay = 0.08
        isPlaying = true
        isPaused = false
        startedAt = Date()
        synthesizer.speak(utterance)
        startTicker()
        updateNowPlaying()
    }

    private func finishAll() {
        continueAfterFinish = false
        let duration = Double(totalCharacters) * 0.22 / speed
        isPlaying = false
        isPaused = false
        progress = 1
        offset = 0
        accumulated = 0
        startedAt = nil
        ticker?.cancel()
        ticker = nil
        elapsedLabel = Self.label(duration)
        remainingLabel = "-" + Self.label(0)
        deactivateSession()
        updateNowPlaying()
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
        updateNowPlaying()
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
            self.updateNowPlaying()
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            // 自然念完一段就接着念下一段（用各自的角色声线）；手动 stop 时
            // continueAfterFinish 已被清掉，直接从最后一段收尾。
            guard self.continueAfterFinish,
                  self.spokenSegments.indices.contains(self.currentSegment + 1) else {
                self.finishAll()
                return
            }
            self.speak(from: self.spokenSegments[self.currentSegment + 1].start)
        }
    }

    // MARK: - Lock screen & remote control

    /// 系统语音是真实发声的，锁屏与车机理应能控制它。命令回调不在主actor上，
    /// 统一派回主actor再改播放状态，避免和 AVSpeechSynthesizer 的 delegate 抢状态。
    private func setupRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.resume() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pause() }
            return .success
        }
        center.stopCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.stop() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.toggle() }
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.skip(400) }
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.skip(-400) }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { @MainActor in
                guard let self else { return }
                let duration = Double(self.totalCharacters) * 0.22 / self.speed
                guard duration > 0 else { return }
                self.seek(to: event.positionTime / duration)
            }
            return .success
        }
    }

    private func updateNowPlaying() {
        let center = MPNowPlayingInfoCenter.default()
        guard hasChapter else {
            center.nowPlayingInfo = nil
            return
        }
        let duration = Double(totalCharacters) * 0.22 / speed
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: chapterTitle.isEmpty ? title : chapterTitle,
            MPMediaItemPropertyArtist: title,
            MPMediaItemPropertyMediaType: MPMediaType.audioBook.rawValue,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: min(max(progress * duration, 0), duration),
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? Double(speed) : 0
        ]
        if let artwork { info[MPMediaItemPropertyArtwork] = artwork }
        center.nowPlayingInfo = info
    }

    private static func makeArtwork() -> MPMediaItemArtwork? {
        let size = CGSize(width: 300, height: 300)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            UIColor(red: 0.07, green: 0.12, blue: 0.19, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor(red: 0.95, green: 0.74, blue: 0.42, alpha: 1).setFill()
            UIBezierPath(
                arcCenter: CGPoint(x: 150, y: 128), radius: 52,
                startAngle: 0, endAngle: .pi * 2, clockwise: true
            ).fill()
            UIColor(red: 0.07, green: 0.12, blue: 0.19, alpha: 1).setFill()
            UIBezierPath(
                arcCenter: CGPoint(x: 178, y: 112), radius: 48,
                startAngle: 0, endAngle: .pi * 2, clockwise: true
            ).fill()
        }
        return MPMediaItemArtwork(boundsSize: size) { _ in image }
    }

    static func label(_ value: TimeInterval) -> String {
        let total = Int(value.rounded())
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
