import Foundation
import Combine

/// 全部设置都存在 UserDefaults 里；Key 单独放 Keychain 会更安全，这里先简单存本地。
@MainActor
final class AppSettings: ObservableObject {
    @Published var baseURL: String {
        didSet { store.set(baseURL, forKey: "llm.baseURL") }
    }
    @Published var apiKey: String {
        didSet { store.set(apiKey, forKey: "llm.apiKey") }
    }
    @Published var model: String {
        didSet { store.set(model, forKey: "llm.model") }
    }
    @Published var visionModel: String {
        didSet { store.set(visionModel, forKey: "llm.visionModel") }
    }
    @Published var asrModel: String {
        didSet { store.set(asrModel, forKey: "llm.asrModel") }
    }
    @Published var ttsEnabled: Bool {
        didSet { store.set(ttsEnabled, forKey: "voice.tts") }
    }
    @Published var speakRate: Double {
        didSet { store.set(speakRate, forKey: "voice.rate") }
    }
    @Published var persona: String {
        didSet { store.set(persona, forKey: "persona.text") }
    }
    @Published var pcAddress: String {
        didSet { store.set(pcAddress, forKey: "pc.address") }
    }
    @Published var usePC: Bool {
        didSet { store.set(usePC, forKey: "pc.enabled") }
    }
    @Published var coyoteMax: Int {
        didSet { store.set(coyoteMax, forKey: "coyote.max") }
    }

    private let store = UserDefaults.standard

    init() {
        baseURL = store.string(forKey: "llm.baseURL") ?? "https://api.deepseek.com/v1"
        apiKey = store.string(forKey: "llm.apiKey") ?? ""
        model = store.string(forKey: "llm.model") ?? "deepseek-chat"
        visionModel = store.string(forKey: "llm.visionModel") ?? ""
        asrModel = store.string(forKey: "llm.asrModel") ?? "whisper-1"
        ttsEnabled = store.object(forKey: "voice.tts") as? Bool ?? true
        speakRate = store.object(forKey: "voice.rate") as? Double ?? 1.0
        persona = store.string(forKey: "persona.text") ?? AppSettings.defaultPersona
        pcAddress = store.string(forKey: "pc.address") ?? "192.168.0.103:8080"
        usePC = store.object(forKey: "pc.enabled") as? Bool ?? true
        coyoteMax = store.object(forKey: "coyote.max") as? Int ?? 40
    }

    var hasKey: Bool { !apiKey.trimmingCharacters(in: .whitespaces).isEmpty }

    /// 识图模型：留空就用对话模型
    var effectiveVisionModel: String {
        let value = visionModel.trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? model : value
    }

    var chatURL: URL? { URL(string: baseURL.trimmingCharacters(in: .whitespaces) + "/chat/completions") }
    var transcribeURL: URL? { URL(string: baseURL.trimmingCharacters(in: .whitespaces) + "/audio/transcriptions") }

    static let defaultPersona = """
    你是「林序」，27 岁，独立书店店主。话短，少用感叹号，偶尔用比喻。
    你在和一个成年人相处，语气自然、有边界感，不主动说教。
    用户说的话要先理解，再回应；需要动手时调用工具，不要只描述。
    """
}
