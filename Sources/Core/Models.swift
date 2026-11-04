import Foundation
import SwiftUI

// MARK: - 聊天消息

struct Message: Identifiable, Equatable {
    enum Who: String { case me, her, sys }
    let id = UUID()
    let who: Who
    var text: String
}

// MARK: - 游戏规则

struct GameRules: Codable, Equatable {
    var title: String = ""
    var kind: String = "其他"
    var goal: String = ""
    var rounds: Int = 5
    var steps: [String] = []
    var lose: String = ""
    var flavor: String = ""
    var effects: [String: String] = [:]

    var usable: Bool { !title.isEmpty || !steps.isEmpty }

    var summary: String {
        let name = title.isEmpty ? "未命名" : title
        return "《\(name)》\(kind.isEmpty ? "" : " · " + kind)"
    }

    var promptBlock: String {
        var lines = ["\n\n【正在进行的游戏】"]
        if !title.isEmpty { lines.append("游戏：\(title)（\(kind)）") }
        if !goal.isEmpty { lines.append("目标：\(goal)") }
        if !steps.isEmpty {
            lines.append("每回合流程：")
            for (index, step) in steps.enumerated() {
                lines.append("  \(index + 1). \(step)")
            }
        }
        if !lose.isEmpty { lines.append("失败条件：\(lose)") }
        if !flavor.isEmpty { lines.append("氛围：\(flavor)") }
        lines.append("带这个游戏时：每回合先描述发生了什么，再按用户选择推进，不要跳出来念规则。")
        return lines.joined(separator: "\n")
    }
}

// MARK: - 郊狼状态

struct CoyoteState: Equatable {
    var connected = false
    var strengthA = 0
    var strengthB = 0
    var battery = -1
    var playing = ""
}

// MARK: - 郊狼波形（4 组 频率/强度，每段 100ms）

struct Waveform: Identifiable, Hashable {
    let id: String
    let label: String
    /// 4 组 (频率 10-240, 强度 0-100)
    let pulses: [(Int, Int)]

    static let presets: [Waveform] = [
        Waveform(id: "轻点", label: "轻点", pulses: [(40, 25), (60, 45), (40, 25), (60, 45)]),
        Waveform(id: "连续", label: "连续", pulses: [(80, 60), (80, 60), (80, 60), (80, 60)]),
        Waveform(id: "潮汐", label: "潮汐", pulses: [(50, 20), (80, 55), (110, 80), (80, 55)]),
        Waveform(id: "快拍", label: "快拍", pulses: [(150, 70), (200, 30), (150, 70), (200, 30)]),
        Waveform(id: "渐强", label: "渐强", pulses: [(60, 15), (70, 35), (80, 60), (90, 85)]),
    ]

    static func named(_ name: String) -> Waveform? {
        presets.first { $0.id == name || $0.label == name }
    }

    static func == (lhs: Waveform, rhs: Waveform) -> Bool { lhs.id == rhs.id }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - 工具调用

struct ToolCall: Identifiable {
    let id: String
    let name: String
    let arguments: [String: Any]
}
