import SwiftUI

@main
struct DSRemoteApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model.settings)
                .environmentObject(model.coyote)
                .environmentObject(model.game)
                .environmentObject(model.speech)
                .environmentObject(model.pc)
                .environmentObject(model.recorder)
                .environmentObject(model.engine)
                .preferredColorScheme(.dark)
        }
    }
}
