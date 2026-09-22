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
                    case .whereTab: WhereView()
                    }
                }
            }
        }
        .tint(Theme.Accent.default)
        .overlay { if model.isLocked { LockScreen() } }
        .alert("Something went wrong", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
    }
}


/// Face ID gate. Shown over everything until the device owner authenticates.
struct LockScreen: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        VStack(spacing: Theme.Spacing.s16) {
            Spacer()
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.Accent.default).frame(width: 72, height: 72)
                Text("P").font(.system(size: 42, weight: .bold, design: .rounded)).foregroundStyle(.white)
            }
            Text("Poise is locked").font(Theme.Font.titleMD).foregroundStyle(Theme.Text.primary)
            Text("Face ID keeps your finances private.").font(Theme.Font.verdictMD).foregroundStyle(Theme.Text.secondary)
            Spacer()
            Button("Unlock") { Task { await model.unlock() } }.buttonStyle(.primary).padding(.horizontal, Theme.Spacing.s24).padding(.bottom, Theme.Spacing.s32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Bg.base)
        .ignoresSafeArea()
    }
}
