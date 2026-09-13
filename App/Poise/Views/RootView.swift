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
                    case .leaks: PlaceholderView(title: "Leaks", line: "Subscriptions, price creep, renewals and fees.")
                    case .pace: PlaceholderView(title: "Pace", line: "This month against last, projected to month-end.")
                    case .next14: PlaceholderView(title: "Next 14 days", line: "Bills and income per day, and the balance after each.")
                    }
                }
            }
        }
        .tint(Theme.Accent.default)
    }
}

/// Stand-in for the three tabs that arrive after Home.
struct PlaceholderView: View {
    let title: String
    let line: String

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(line)
                    .font(Theme.Font.verdictMD)
                    .foregroundStyle(Theme.Text.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Theme.Spacing.s16)
            }
            .background(Theme.Bg.base)
            .navigationTitle(title)
        }
    }
}
