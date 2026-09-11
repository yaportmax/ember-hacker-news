import SwiftUI

@main
struct EmberApp: App {
    @State private var app = AppContainer()
    @AppStorage("appearance") private var appearance = "system"
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .environment(app.reading)
                .tint(Color.accentColor)
                .preferredColorScheme(appearance == "dark" ? .dark : appearance == "light" ? .light : nil)
                .onChange(of: phase) { _, newValue in
                    if newValue != .active { Task { await app.reading.flush() } }
                }
        }
    }
}
