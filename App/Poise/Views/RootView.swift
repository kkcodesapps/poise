import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.tab) {
            ForEach(AppModel.Tab.allCases) { tab in
                Tab(tab.rawValue, systemImage: tab.symbol, value: tab) {
                    switch tab {
                    case .home: HomeView()
                    case .leaks: LeaksView()
                    case .pace: PaceView()
                    case .next14: Next14View()
                    }
                }
            }
        }
        .tint(Theme.Accent.default)
        .alert("Something went wrong", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
    }
}
