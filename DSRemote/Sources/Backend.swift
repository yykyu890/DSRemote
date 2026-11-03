import Foundation
import Combine

/// 一条聊天消息
struct Message: Identifiable, Equatable {
    enum Who: String { case me, her, sys }
    let id = UUID()
    let who: Who
    var text: String
}

/// 后端状态（和电脑上 /api/state 对应）
struct ServerState: Decodable {
    let mode: String
    let connected: Bool
    let estop: Bool
}

/// 和电脑上的 mobile 服务对话：SSE 收事件，POST 发指令
@MainActor
final class Backend: ObservableObject {
    @Published var messages: [Message] = []
    @Published var state = ServerState(mode: "simulation", connected: false, estop: false)
    @Published var address: String {
        didSet { UserDefaults.standard.set(address, forKey: "address") }
    }
    @Published var connecting = false
    @Published var errorText = ""

    private var streamTask: Task<Void, Never>?
    private var stateTask: Task<Void, Never>?
    private var streamingID: UUID?

    init() {
        address = UserDefaults.standard.string(forKey: "address") ?? "192.168.0.103:8080"
    }

    var baseURL: URL? {
        let trimmed = address.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let withScheme = trimmed.hasPrefix("http") ? trimmed : "http://\(trimmed)"
        return URL(string: withScheme)
    }

    // MARK: - 连接

    func connect() {
        guard let base = baseURL else {
            errorText = "地址不对"
            return
        }
        streamTask?.cancel()
        stateTask?.cancel()
        connecting = true
        errorText = ""

        stateTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshState(base: base)
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
        streamTask = Task { [weak self] in
            await self?.listenEvents(base: base)
        }
    }

    func disconnect() {
        streamTask?.cancel()
        stateTask?.cancel()
        streamTask = nil
        stateTask = nil
        connecting = false
    }

    // MARK: - 事件流（SSE）

    private func listenEvents(base: URL) async {
        var request = URLRequest(url: base.appendingPathComponent("api/events"))
        request.timeoutInterval = .infinity
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

        while !Task.isCancelled {
            do {
                let (bytes, _) = try await URLSession.shared.bytes(for: request)
                connecting = false
                errorText = ""
                for try await line in bytes.lines {
                    guard line.hasPrefix("data: ") else { continue }
                    handleEvent(String(line.dropFirst(6)))
                }
            } catch {
                if Task.isCancelled { return }
                connecting = false
                errorText = "连接断开，3 秒后重试"
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
    }

    private func handleEvent(_ json: String) {
        guard let data = json.data(using: .utf8),
              let raw = try? JSONSerialization.jsonObject(with: data),
              let obj = raw as? [String: Any],
              let type = obj["type"] as? String else { return }
        let text = obj["text"] as? String ?? ""

        switch type {
        case "text":
            appendStreaming(text)
        case "done":
            streamingID = nil
        case "warning", "error":
            messages.append(Message(who: .sys, text: "⚠ " + text))
        case "stop", "motion":
            if !text.isEmpty {
                messages.append(Message(who: .sys, text: text))
            }
        default:
            break
        }
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

    // MARK: - 状态

    private func refreshState(base: URL) async {
        do {
            let (data, _) = try await URLSession.shared.data(
                from: base.appendingPathComponent("api/state"))
            if let decoded = try? JSONDecoder().decode(ServerState.self, from: data) {
                state = decoded
            }
        } catch {
            // 连不上就保持旧状态，避免刷屏
        }
    }

    // MARK: - 指令

    func send(_ text: String) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        messages.append(Message(who: .me, text: value))
        post("api/chat", ["text": value])
    }

    func estop() {
        if state.estop {
            post("api/estop/clear", [:])
            messages.append(Message(who: .sys, text: "已解除急停"))
        } else {
            post("api/estop", [:])
            messages.append(Message(who: .sys, text: "⛔ 急停"))
        }
    }

    func motion(pattern: String, intensity: Int, tempo: Int, seconds: Int) {
        post("api/motion", [
            "pattern": pattern,
            "intensity": intensity,
            "tempo": tempo,
            "duration_sec": seconds,
        ])
    }

    func stopMotion() {
        post("api/stop", [:])
    }

    private func post(_ path: String, _ body: [String: Any]) {
        guard let base = baseURL else { return }
        var request = URLRequest(url: base.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 20

        URLSession.shared.dataTask(with: request) { data, _, error in
            if let error = error {
                Task { @MainActor in self.errorText = error.localizedDescription }
                return
            }
            guard let data = data,
                  let raw = try? JSONSerialization.jsonObject(with: data),
                  let obj = raw as? [String: Any] else { return }
            let ok = obj["ok"] as? Bool ?? false
            let note = obj["note"] as? String ?? ""
            Task { @MainActor in
                if !note.isEmpty {
                    self.messages.append(Message(who: .sys, text: note))
                }
                if !ok {
                    self.errorText = note
                }
            }
        }.resume()
    }
}
