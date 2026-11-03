import SwiftUI

@main
struct DSRemoteApp: App {
    @StateObject private var backend = Backend()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(backend)
                .preferredColorScheme(.dark)
        }
    }
}
