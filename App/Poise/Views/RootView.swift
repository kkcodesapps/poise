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
        // Sheets hang off the root so a row on any tab can open them.
        .sheet(item: $model.selectedTransaction, onDismiss: { model.insightContext = nil }) { t in TransactionDetailView(transaction: t) }
        .sheet(item: $model.selectedStream) { s in StreamDetailView(stream: s) }
        .sheet(isPresented: $model.showSince, onDismiss: { model.dismissSince() }) { SinceView() }
        .sheet(item: $model.selectedMerchant) { m in MerchantView(merchantKey: m.key) }
        #if DEBUG
        .sheet(isPresented: $model.showWidgetPreview) { WidgetPreviewSheet() }
        #endif
        .sheet(isPresented: $model.showProfile) { ProfileView() }
        .fullScreenCover(isPresented: $model.showReview) { WeeklyReviewView() }
        .overlay { if model.onboarding != nil { OnboardingView().transition(.opacity) } }
        .overlay { if model.isLocked { LockScreen() } }
        .overlay { if model.launch != .ready { LaunchView().transition(.opacity) } }
        .animation(.easeInOut(duration: 0.3), value: model.launch)
        .animation(.easeInOut(duration: 0.3), value: model.onboarding == nil)
        .alert("Something went wrong", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
        .confirmationDialog("What are you adding?", isPresented: $model.showLinkOptions, titleVisibility: .visible) {
            Button("Apple Card, Apple Cash & Savings") { Task { await model.linkWallet() } }
            Button("A bank or credit card") { Task { await model.link() } }
        } message: {
            Text("Apple accounts are read from Wallet on this iPhone. Banks and other cards connect through Plaid.")
        }
    }
}


/// Face ID gate. Shown over everything until the device owner authenticates.
struct LockScreen: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        VStack(spacing: Theme.Spacing.s16) {
            Spacer()
            PoiseMark()
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
