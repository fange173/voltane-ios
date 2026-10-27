import SwiftUI

@main
struct VoltaneApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .preferredColorScheme(model.colorScheme)
                .tint(Color.vBrand)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.sceneBecameActive() } }
        }
    }
}
