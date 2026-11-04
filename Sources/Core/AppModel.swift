import Foundation
import SwiftUI

/// 把各个单例收在一起，方便注入环境
@MainActor
final class AppModel: ObservableObject {
    let settings = AppSettings()
    let coyote = CoyoteBLE()
    let game = GameStore()
    let speech = Speech()
    let pc = PCBridge()
    let recorder = Recorder()
    let engine: ChatEngine

    init() {
        engine = ChatEngine(settings: settings, coyote: coyote, game: game,
                            speech: speech, pc: pc)
        pc.startPolling()
    }
}
