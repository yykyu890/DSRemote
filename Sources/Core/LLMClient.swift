import Foundation

/// 直接和 LLM 说话：流式聊天、看图片、转写
struct LLMClient {
    let baseURL: String
    let apiKey: String

    private var chatURL: URL? {
        URL(string: baseURL.trimmingCharacters(in: .whitespaces) + "/chat/completions")
    }
    private var audioURL: URL? {
        URL(string: baseURL.trimmingCharacters(in: .whitespaces) + "/audio/transcriptions")
    }

    private var headers: [String: String] {
        var value = ["Content-Type": "application/json"]
        if !apiKey.isEmpty {
            value["Authorization"] = "Bearer \(apiKey)"
        }
        return value
    }

    // MARK: - 流式对话（带工具）

    struct StreamEvent {
        enum Kind { case text(String), tools([ToolCall]), done }
        let kind: Kind
    }

    /// 流式请求；每拿到一段文本或一轮工具调用就回调一次。
    @MainActor
    func stream(messages: [[String: Any]],
                tools: [[String: Any]],
                model: String,
                onEvent: @escaping (StreamEvent) -> Void) async throws {
        guard let url = chatURL else { throw LLMError.badURL }
        var body: [String: Any] = [
            "model": model,
            "messages": messages,
            "stream": true,
            "temperature": 0.8,
        ]
        if !tools.isEmpty {
            body["tools"] = tools
            body["tool_choice"] = "auto"
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            var detail = ""
            for try await line in bytes.lines {
                detail += line
                if detail.count > 300 { break }
            }
            throw LLMError.http(http.statusCode, detail)
        }

        var pendingText = ""
        var toolBuffer: [Int: [String: String]] = [:]

        for try await line in bytes.lines {
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            if payload == "[DONE]" { break }
            guard let data = payload.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data),
                  let root = obj as? [String: Any],
                  let choices = root["choices"] as? [[String: Any]],
                  let delta = choices.first?["delta"] as? [String: Any] else { continue }

            if let content = delta["content"] as? String, !content.isEmpty {
                pendingText += content
                onEvent(StreamEvent(kind: .text(content)))
            }

            if let calls = delta["tool_calls"] as? [[String: Any]] {
                for call in calls {
                    let index = call["index"] as? Int ?? 0
                    var slot = toolBuffer[index] ?? [:]
                    if let id = call["id"] as? String { slot["id"] = id }
                    if let function = call["function"] as? [String: Any] {
                        if let name = function["name"] as? String, !name.isEmpty {
                            slot["name"] = name
                        }
                        if let args = function["arguments"] as? String {
                            slot["arguments"] = (slot["arguments"] ?? "") + args
                        }
                    }
                    toolBuffer[index] = slot
                }
            }
        }

        if !toolBuffer.isEmpty {
            var calls: [ToolCall] = []
            for key in toolBuffer.keys.sorted() {
                guard let slot = toolBuffer[key],
                      let name = slot["name"] else { continue }
                let raw = slot["arguments"] ?? "{}"
                let args = (try? JSONSerialization.jsonObject(with: Data(raw.utf8))) as? [String: Any]
                calls.append(ToolCall(id: slot["id"] ?? UUID().uuidString,
                                      name: name,
                                      arguments: args ?? [:]))
            }
            if !calls.isEmpty {
                onEvent(StreamEvent(kind: .tools(calls)))
            }
        }
        onEvent(StreamEvent(kind: .done))
    }

    // MARK: - 看图生成游戏规则

    static let rulesPrompt = """
    看着这张图，把里面的玩法整理成可以照着执行的游戏规则。
    要求：判断图是什么；提炼目标、回合流程、输赢条件；图里没有明确游戏就基于画面设计一个两人小游戏。
    只输出 JSON，不要解释：
    {"title":"游戏名","kind":"棋类/卡牌/骰子/文字/其他","goal":"一句话目标","rounds":5,
     "steps":["第一步","第二步"],"lose":"失败条件","flavor":"氛围提示",
     "effects":{"round":"motion:stroke:40:20"}}
    effects 可留空，写法只有四种：motion:动作:幅度:秒数 / coyote:A:波形:秒数 / servo:角度 / stop
    """

    func describeImage(_ data: Data, mime: String, model: String) async throws -> String {
        guard let url = chatURL else { throw LLMError.badURL }
        let encoded = data.base64EncodedString()
        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": "你把图片翻译成可执行的游戏规则。"],
                ["role": "user", "content": [
                    ["type": "text", "text": LLMClient.rulesPrompt],
                    ["type": "image_url", "image_url": ["url": "data:\(mime);base64,\(encoded)"]],
                ]],
            ],
            "temperature": 0.4,
        ]
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data2, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            let detail = String(data: data2.prefix(200), encoding: .utf8) ?? ""
            throw LLMError.http(http.statusCode, detail + "（当前模型可能不支持看图）")
        }
        guard let root = try? JSONSerialization.jsonObject(with: data2) as? [String: Any],
              let choices = root["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw LLMError.empty
        }
        return content
    }

    // MARK: - 语音转写

    func transcribe(wav: Data, model: String, language: String = "zh") async throws -> String {
        guard let url = audioURL else { throw LLMError.badURL }
        let boundary = "----ds\(UUID().uuidString)"
        var body = Data()

        func addField(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append(value.data(using: .utf8)!)
            body.append("\r\n".data(using: .utf8)!)
        }

        addField("model", model)
        addField("language", language)
        addField("response_format", "json")

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"speech.wav\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(wav)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            let detail = String(data: data.prefix(200), encoding: .utf8) ?? ""
            throw LLMError.http(http.statusCode, detail + "（这个接口可能不支持转写）")
        }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = root["text"] as? String else {
            throw LLMError.empty
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum LLMError: LocalizedError {
    case badURL
    case empty
    case http(Int, String)

    var errorDescription: String? {
        switch self {
        case .badURL: return "接口地址不对"
        case .empty: return "模型没有返回内容"
        case .http(let code, let detail): return "HTTP \(code)：\(detail)"
        }
    }
}
