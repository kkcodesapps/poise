import SwiftUI

/// The launch screen, continued: the same mark the static launch image shows, in the same place, held until the
/// first load settles. Quiet until a second passes; a way back in if the connection fails.
struct LaunchView: View {
    @Environment(AppModel.self) private var model
    @State private var reading = false

    var body: some View {
        ZStack {
            Theme.Bg.base
            Image("LaunchMark")
                .overlay(alignment: .top) { status.offset(y: 146 + 28) }   // the image is 96 × 146 pt
        }
        .ignoresSafeArea()
        .task {
            try? await Task.sleep(for: .seconds(1))
            withAnimation(.easeInOut(duration: 0.3)) { reading = true }
        }
    }

    @ViewBuilder private var status: some View {
        switch model.launch {
        case .failed:
            VStack(spacing: Theme.Spacing.s16) {
                Text("Can’t reach Poise right now.").font(Theme.Font.headline).foregroundStyle(Theme.Text.primary)
                Text("Your banks stay linked and nothing has changed — this is just the connection.")
                    .font(Theme.Font.footnote).foregroundStyle(Theme.Text.secondary).multilineTextAlignment(.center)
                Button("Try again") { Task { await model.start() } }.buttonStyle(.secondaryCompact)
            }
            .frame(width: 345)
            .transition(.opacity)
        case .loading where reading:
            VStack(spacing: Theme.Spacing.s12) {
                SlidingBar()
                Text("Reading your accounts…").font(Theme.Font.footnote).foregroundStyle(Theme.Text.tertiary)
            }
            .fixedSize()
            .transition(.opacity)
        default:
            EmptyView()
        }
    }
}

/// A short accent bar that slides along a track. It shows waiting, not progress — there is no real progress to show.
private struct SlidingBar: View {
    @State private var toRight = false
    var body: some View {
        ZStack(alignment: .leading) {
            Capsule().fill(Theme.Bg.subtle).frame(width: 120, height: 4)
            Capsule().fill(Theme.Accent.default).frame(width: 48, height: 4).offset(x: toRight ? 72 : 0)
        }
        .onAppear { withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { toRight = true } }
    }
}
