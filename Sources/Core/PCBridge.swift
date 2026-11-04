import Foundation
import Combine

/// 电脑端连接（只用于 OSR 动作和急停；聊天已经不走电脑了）
@MainActor
final class PCBridge: ObservableObject {
    @Published var address: String {
        didSet { UserDefaults.standard.set(address, forKey: "pc.address") }
    }
    @Published private(set) var connected = false
    @Published private(set) var estop = false
    @Published private(set) var mode = "simulation"
    @Published var errorText = ""

    private var pollTask: Task<Void, Never>?

    init() {
        address = UserDefaults.standard.string(forKey: "pc.address") ?? "192.168.0.103:8080"
    }

    var baseURL: URL? {
        let trimmed = address.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let withScheme = trimmed.hasPrefix("http") ? trimmed : "http://\(trimmed)"
        return URL(string: withScheme)
    }

    func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func refresh() async {
        guard let base = baseURL else { return }
        do {
            let (data, _) = try await URLSession.shared.data(
                from: base.appendingPathComponent("api/state"))
            guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return
            }
            connected = obj["connected"] as? Bool ?? false
            estop = obj["estop"] as? Bool ?? false
            mode = obj["mode"] as? String ?? "simulation"
            errorText = ""
        } catch {
            connected = false
            errorText = "电脑没连上"
        }
    }

    // MARK: - 指令

    func toggleEstop() async {
        guard let base = baseURL else { return }
        let path = estop ? "api/estop/clear" : "api/estop"
        _ = await post(base.appendingPathComponent(path), [:])
        await refresh()
    }

    func motion(pattern: String, intensity: Int, tempo: Int, seconds: Int) async -> String {
        guard let base = baseURL else { return "没配置电脑地址" }
        return await post(base.appendingPathComponent("api/motion"), [
            "pattern": pattern,
            "intensity": intensity,
            "tempo": tempo,
            "duration_sec": seconds,
        ])
    }

    func stopMotion() async -> String {
        guard let base = baseURL else { return "没配置电脑地址" }
        return await post(base.appendingPathComponent("api/stop"), [:])
    }

    @discardableResult
    private func post(_ url: URL, _ body: [String: Any]) async -> String {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 20
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            if let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                return obj["note"] as? String ?? ""
            }
        } catch {
            return "电脑没响应：\(error.localizedDescription)"
        }
        return ""
    }
}
