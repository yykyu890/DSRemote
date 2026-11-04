import Foundation
import Combine

/// 游戏存档：存在 UserDefaults 里，最多一个
@MainActor
final class GameStore: ObservableObject {
    @Published private(set) var rules: GameRules?
    @Published private(set) var playing = false
    @Published private(set) var round = 0

    private let key = "game.current"

    init() { load() }

    func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let saved = try? JSONDecoder().decode(GameRules.self, from: data) else {
            rules = nil
            return
        }
        rules = saved
    }

    func save(_ rules: GameRules) {
        self.rules = rules
        round = 0
        if let data = try? JSONEncoder().encode(rules) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    func start() {
        playing = true
        round = 0
    }

    func stop() {
        playing = false
    }

    func nextRound() {
        guard let rules else { return }
        round = min(max(0, rules.rounds - 1), round + 1)
    }

    /// 拼进系统提示；没规则返回空串
    func promptBlock() -> String {
        guard let rules, rules.usable else { return "" }
        if !playing {
            return "\n\n【有一局游戏准备好，还没开始】\(rules.summary) 共 \(rules.rounds) 回合。"
                + "用户说想玩时调用 game_start 开局；不想玩就照常聊，不要硬拉着玩。"
        }
        return rules.promptBlock + "\n进度：第 \(round + 1)/\(max(1, rules.rounds)) 回合"
    }
}
