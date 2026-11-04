import Foundation
import Combine

/// 聊天总控：直接连 LLM，工具在本地执行（郊狼/游戏），OSR 动作转发给电脑。
@MainActor
final class ChatEngine: ObservableObject {
    @Published var messages: [Message] = []
    @Published var busy = false
    @Published var errorText = ""

    let settings: AppSettings
    let coyote: CoyoteBLE
    let game: GameStore
    let speech: Speech
    let pc: PCBridge

    private var history: [[String: Any]] = []
    private var streamingID: UUID?

    init(settings: AppSettings, coyote: CoyoteBLE, game: GameStore,
         speech: Speech, pc: PCBridge) {
        self.settings = settings
        self.coyote = coyote
        self.game = game
        self.speech = speech
        self.pc = pc
    }

    // MARK: - 发送

    func send(_ text: String) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !busy else { return }
        guard settings.hasKey else {
            errorText = "还没填 API Key（右上角 ⚙）"
            return
        }
        messages.append(Message(who: .me, text: value))
        history.append(["role": "user", "content": value])
        streamingID = nil
        Task { await runTurn() }
    }

    private func runTurn() async {
        busy = true
        errorText = ""
        defer { busy = false }

        let client = LLMClient(baseURL: settings.baseURL, apiKey: settings.apiKey)
        var rounds = 0

        while rounds < 4 {
            rounds += 1
            var spokenText = ""
            var calls: [ToolCall] = []

            do {
                try await client.stream(
                    messages: buildMessages(),
                    tools: toolSchemas(),
                    model: settings.model
                ) { event in
                    switch event.kind {
                    case .text(let piece):
                        spokenText += piece
                        self.appendStreaming(piece)
                    case .tools(let list):
                        calls = list
                    case .done:
                        break
                    }
                }
            } catch {
                self.errorText = (error as? LocalizedError)?.errorDescription
                    ?? error.localizedDescription
                if !spokenText.isEmpty {
                    self.history.append(["role": "assistant", "content": spokenText])
                }
                return
            }

            // 没有工具调用：这一轮就是最终回复
            if calls.isEmpty {
                if !spokenText.isEmpty {
                    history.append(["role": "assistant", "content": spokenText])
                    if settings.ttsEnabled {
                        speech.speak(spokenText, rate: Float(settings.speakRate))
                    }
                }
                streamingID = nil
                if game.playing {
                    game.nextRound()
                    await applyEffect("round")
                }
                return
            }

            // 有工具调用：记录 assistant 的 tool_calls，再逐个执行
            var assistant: [String: Any] = ["role": "assistant", "content": spokenText]
            assistant["tool_calls"] = calls.map { call in
                [
                    "id": call.id,
                    "type": "function",
                    "function": [
                        "name": call.name,
                        "arguments": (try? JSONSerialization.data(withJSONObject: call.arguments))
                            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}",
                    ],
                ]
            }
            history.append(assistant)

            for call in calls {
                let result = await execute(call)
                history.append([
                    "role": "tool",
                    "tool_call_id": call.id,
                    "content": result,
                ])
            }
        }
    }

    private func buildMessages() -> [[String: Any]] {
        var system = settings.persona + toolRules
        let block = game.promptBlock()
        if !block.isEmpty {
            system += block
        }
        var result: [[String: Any]] = [["role": "system", "content": system]]
        result.append(contentsOf: history.suffix(24))
        return result
    }

    private var toolRules: String {
        """


        你可以调用工具：郊狼（coyote_*）、游戏（game_*）、OSR 动作（motion_*，需要电脑连着）。
        用户说要、或者情境到了才调用；不要解释工具，也不要念参数。
        强度不超过 \(settings.coyoteMax)。
        """
    }

    private func appendStreaming(_ piece: String) {
        if let id = streamingID, let index = messages.firstIndex(where: { $0.id == id }) {
            messages[index].text += piece
            return
        }
        let message = Message(who: .her, text: piece)
        streamingID = message.id
        messages.append(message)
    }

    // MARK: - 工具

    private func toolSchemas() -> [[String: Any]] {
        var tools: [[String: Any]] = [
            [
                "type": "function",
                "function": [
                    "name": "coyote_strength",
                    "description": "调郊狼强度（0-200，实际受上限限制）",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "channel": ["type": "string", "enum": ["A", "B"]],
                            "mode": ["type": "string", "enum": ["set", "inc", "dec"]],
                            "value": ["type": "integer", "minimum": 0, "maximum": 200],
                        ],
                        "required": ["channel", "mode", "value"],
                    ],
                ],
            ],
            [
                "type": "function",
                "function": [
                    "name": "coyote_wave",
                    "description": "播放一段郊狼波形",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "channel": ["type": "string", "enum": ["A", "B"]],
                            "waveform": ["type": "string",
                                         "enum": Waveform.presets.map { $0.label }],
                            "duration_sec": ["type": "integer", "minimum": 1, "maximum": 50],
                        ],
                        "required": ["channel", "duration_sec"],
                    ],
                ],
            ],
            [
                "type": "function",
                "function": [
                    "name": "coyote_stop",
                    "description": "立刻停郊狼输出",
                    "parameters": ["type": "object",
                                   "properties": [String: Any](),
                                   "required": [String]()],
                ],
            ],
            [
                "type": "function",
                "function": [
                    "name": "game_start",
                    "description": "开始之前定好的游戏",
                    "parameters": [
                        "type": "object",
                        "properties": ["rounds": ["type": "integer", "minimum": 1, "maximum": 50]],
                        "required": [String](),
                    ],
                ],
            ],
            [
                "type": "function",
                "function": [
                    "name": "game_end",
                    "description": "结束当前游戏",
                    "parameters": [
                        "type": "object",
                        "properties": ["reason": ["type": "string"]],
                        "required": [String](),
                    ],
                ],
            ],
        ]

        if settings.usePC {
            tools.append([
                "type": "function",
                "function": [
                    "name": "motion_play",
                    "description": "让 OSR 设备动起来（需要电脑连着）",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "pattern": ["type": "string",
                                        "enum": ["stroke", "surge", "sway", "twist", "roll", "pitch"]],
                            "intensity": ["type": "integer", "minimum": 1, "maximum": 100],
                            "tempo": ["type": "integer", "minimum": 10, "maximum": 100],
                            "duration_sec": ["type": "integer", "minimum": 1, "maximum": 600],
                        ],
                        "required": ["pattern", "intensity", "tempo", "duration_sec"],
                    ],
                ],
            ])
            tools.append([
                "type": "function",
                "function": [
                    "name": "motion_stop",
                    "description": "缓停 OSR 动作",
                    "parameters": ["type": "object",
                                   "properties": [String: Any](),
                                   "required": [String]()],
                ],
            ])
        }
        return tools
    }

    private func execute(_ call: ToolCall) async -> String {
        let args = call.arguments
        switch call.name {
        case "coyote_strength":
            guard coyote.state.connected else { return "郊狼没连上" }
            let channel = args["channel"] as? String ?? "A"
            let mode = args["mode"] as? String ?? "set"
            let value = args["value"] as? Int ?? 0
            coyote.setStrength(channel, value: min(value, settings.coyoteMax), mode: mode)
            return "已设置 \(channel) 通道强度"

        case "coyote_wave":
            guard coyote.state.connected else { return "郊狼没连上" }
            let channel = args["channel"] as? String ?? "A"
            let name = args["waveform"] as? String ?? "轻点"
            let seconds = Double(args["duration_sec"] as? Int ?? 5)
            guard let wave = Waveform.named(name) else { return "没有这个波形：\(name)" }
            coyote.play(channel, waveform: wave, seconds: seconds)
            return "\(channel) 通道播放「\(wave.label)」\(Int(seconds)) 秒"

        case "coyote_stop":
            coyote.stopMotor()
            return "已停"

        case "game_start":
            guard let rules = game.rules else {
                return "还没有游戏规则：先在「游戏」里加一张图或手写规则。"
            }
            if let rounds = args["rounds"] as? Int {
                game.save(GameRules(title: rules.title, kind: rules.kind, goal: rules.goal,
                                    rounds: max(1, min(50, rounds)), steps: rules.steps,
                                    lose: rules.lose, flavor: rules.flavor,
                                    effects: rules.effects))
            }
            game.start()
            await applyEffect("start")
            messages.append(Message(who: .sys, text: "游戏开始：\(rules.summary)"))
            return "游戏已开始：\(rules.title)，共 \(game.rules?.rounds ?? 5) 回合"

        case "game_end":
            game.stop()
            await applyEffect("end")
            messages.append(Message(who: .sys, text: "游戏结束"))
            return "游戏结束"

        case "motion_play":
            let note = await pc.motion(
                pattern: args["pattern"] as? String ?? "stroke",
                intensity: args["intensity"] as? Int ?? 40,
                tempo: args["tempo"] as? Int ?? 50,
                seconds: args["duration_sec"] as? Int ?? 20)
            return note.isEmpty ? "已开始" : note

        case "motion_stop":
            let note = await pc.stopMotion()
            return note.isEmpty ? "已缓停" : note

        default:
            return "未知工具"
        }
    }

    /// 游戏联动：规则里写的动作，回合推进/开局/收尾时执行
    private func applyEffect(_ slot: String) async {
        guard let rules = game.rules,
              let command = rules.effects[slot], !command.isEmpty else { return }
        let parts = command.split(separator: ":").map(String.init)
        guard let head = parts.first?.lowercased() else { return }

        switch head {
        case "stop":
            _ = await pc.stopMotion()
        case "motion":
            let pattern = parts.count > 1 ? parts[1] : "stroke"
            let intensity = Int(parts.count > 2 ? parts[2] : "40") ?? 40
            let seconds = Int(parts.count > 3 ? parts[3] : "20") ?? 20
            _ = await pc.motion(pattern: pattern, intensity: intensity,
                                tempo: 50, seconds: seconds)
        case "coyote":
            let channel = parts.count > 1 ? parts[1].uppercased() : "A"
            let name = parts.count > 2 ? parts[2] : "轻点"
            let seconds = Double(Int(parts.count > 3 ? parts[3] : "3") ?? 3)
            if let wave = Waveform.named(name) {
                coyote.play(channel, waveform: wave, seconds: seconds)
            }
        default:
            break
        }
        messages.append(Message(who: .sys, text: "联动：\(command)"))
    }

    // MARK: - 图片 → 游戏规则

    func importGame(from data: Data, mime: String) async throws -> GameRules {
        let client = LLMClient(baseURL: settings.baseURL, apiKey: settings.apiKey)
        let answer = try await client.describeImage(data, mime: mime,
                                                    model: settings.effectiveVisionModel)
        let rules = parseRules(answer)
        game.save(rules)
        return rules
    }

    private func parseRules(_ text: String) -> GameRules {
        var rules = GameRules()
        let json = extractJSON(text)
        if let json {
            rules.title = json["title"] as? String ?? ""
            rules.kind = json["kind"] as? String ?? "其他"
            rules.goal = json["goal"] as? String ?? ""
            rules.lose = json["lose"] as? String ?? ""
            rules.flavor = json["flavor"] as? String ?? ""
            rules.rounds = max(1, min(50, json["rounds"] as? Int ?? 5))
            rules.steps = (json["steps"] as? [String]) ?? []
            rules.effects = (json["effects"] as? [String: String]) ?? [:]
        }
        if rules.title.isEmpty {
            rules.title = text.split(separator: "\n").first.map(String.init) ?? "自定义玩法"
        }
        return rules
    }

    private func extractJSON(_ text: String) -> [String: Any]? {
        if let start = text.firstIndex(of: "{"),
           let end = text.lastIndex(of: "}"), start < end {
            let slice = String(text[start...end])
            if let data = slice.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                return obj
            }
        }
        return nil
    }

    func reset() {
        messages.removeAll()
        history.removeAll()
        streamingID = nil
    }
}
