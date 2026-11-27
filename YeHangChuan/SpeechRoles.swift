import AVFoundation
import Foundation

/// 一段交给朗读器的文本及其角色。voiceIdentifier 为 nil 时用系统默认中文声线。
struct SpeechSegment: Sendable {
    let text: String
    let role: String
    var voiceIdentifier: String? = nil

    init(text: String, role: String, voiceIdentifier: String? = nil) {
        self.text = text
        self.role = role
        self.voiceIdentifier = voiceIdentifier
    }
}

struct SpeechVoiceOption: Identifiable, Hashable, Sendable {
    let id: String
    let label: String
    let language: String
}

/// 从系统真实声线里取列表，而不是写死四个中文标签。
enum VoiceCatalog {
    static let narrator = "旁白"
    static let roles = [narrator, "年轻旅人", "卖布老人"]

    static var availableVoices: [SpeechVoiceOption] {
        let all = AVSpeechSynthesisVoice.speechVoices()
        let chinese = all.filter { $0.language.hasPrefix("zh") }
        let pool = chinese.isEmpty ? all : chinese
        return pool
            .map { SpeechVoiceOption(id: $0.identifier, label: $0.name, language: $0.language) }
            .sorted { $0.label < $1.label }
    }

    static func defaultMapping() -> [String: String] {
        let ids = availableVoices.map(\.id)
        var mapping: [String: String] = [:]
        for (index, role) in roles.enumerated() where index < ids.count {
            mapping[role] = ids[index]
        }
        return mapping
    }

    static func voice(identifier: String?) -> AVSpeechSynthesisVoice? {
        guard let identifier, !identifier.isEmpty else {
            return AVSpeechSynthesisVoice(language: "zh-CN")
        }
        return AVSpeechSynthesisVoice(identifier: identifier) ?? AVSpeechSynthesisVoice(language: "zh-CN")
    }
}

/// 角色→声线映射持久化。只存系统返回的 identifier，不存用户看到的中文标签。
struct SpeechRolePreferences: Codable, Sendable {
    var mapping: [String: String]

    static func load() -> SpeechRolePreferences {
        guard let data = UserDefaults.standard.data(forKey: "yehangchuan.voiceRoles.v1"),
              let decoded = try? JSONDecoder().decode(SpeechRolePreferences.self, from: data) else {
            return SpeechRolePreferences(mapping: VoiceCatalog.defaultMapping())
        }
        return decoded
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: "yehangchuan.voiceRoles.v1")
    }
}

/// 把没有标注角色的正文切成「旁白 / 对话」两类，让不同声线真的轮着念。
/// 引号内的句子按对话角色处理，其余按旁白处理；这是启发式，不是语义分析。
enum SpeechSegmenter {
    static let dialogueRole = "年轻旅人"

    static func segments(from text: String, mapping: [String: String]) -> [SpeechSegment] {
        let lines = text.components(separatedBy: .newlines)
        var result: [SpeechSegment] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            result.append(contentsOf: segments(inLine: trimmed, mapping: mapping))
        }
        return result
    }

    private static let pairs: [(Character, Character)] = [
        ("「", "」"), ("『", "』"), ("“", "”"), ("\"", "\"")
    ]

    private static func segments(inLine line: String, mapping: [String: String]) -> [SpeechSegment] {
        var result: [SpeechSegment] = []
        var plain = ""
        var closing: Character?
        var quoted = ""

        func flushPlain() {
            let value = plain.trimmingCharacters(in: .whitespaces)
            if !value.isEmpty { result.append(SpeechSegment(text: value, role: VoiceCatalog.narrator, voiceIdentifier: mapping[VoiceCatalog.narrator])) }
            plain = ""
        }
        func flushQuote() {
            let value = quoted.trimmingCharacters(in: .whitespaces)
            if !value.isEmpty { result.append(SpeechSegment(text: value, role: dialogueRole, voiceIdentifier: mapping[dialogueRole])) }
            quoted = ""
        }

        for character in line {
            if let active = closing {
                if character == active {
                    flushQuote()
                    closing = nil
                } else {
                    quoted.append(character)
                }
                continue
            }
            if let pair = pairs.first(where: { $0.0 == character }) {
                flushPlain()
                closing = pair.1
                continue
            }
            plain.append(character)
        }
        flushPlain()
        if closing != nil { flushQuote() }
        return result
    }
}
