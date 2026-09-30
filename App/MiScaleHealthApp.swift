import SwiftUI

@main
struct MiScaleHealthApp: App {
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            // watchOS only lets us scan while the app is in the foreground.
            if phase == .active { model.activate() } else { model.deactivate() }
        }
    }
}
