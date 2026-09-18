import SwiftUI
import PoiseKit

@main
struct PoiseApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .task { await model.start() }
                .onChange(of: scenePhase) { old, new in
                    if new == .active, old == .background { Task { await model.becameActive() } }
                }
        }
    }
}
