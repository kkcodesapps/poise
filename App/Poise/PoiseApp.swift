import SwiftUI
import PoiseKit

@main
struct PoiseApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    private var model: AppModel { delegate.model }
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .task { await model.start() }
                .onOpenURL { url in if url.scheme == "poise" { model.tab = .home; model.showProfile = false } }   // widgets
                .onChange(of: scenePhase) { old, new in
                    if new == .active, old == .background { Task { await model.becameActive() } }
                    if new == .background { model.markLooked() }
                }
        }
    }
}
