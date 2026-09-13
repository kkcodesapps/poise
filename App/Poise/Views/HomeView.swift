import SwiftUI
import PoiseKit

struct HomeView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.s12) {
                    VerdictCard(verdict: model.verdict, linked: model.hasLinkedBank)
                    if let last = model.lastSync {
                        Text("as of \(last, style: .relative) ago")
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Text.tertiary)
                    }
                }
                .padding(.horizontal, Theme.Spacing.s16)
                .padding(.top, Theme.Spacing.s4)
            }
            .background(Theme.Bg.base)
            .navigationTitle("Home")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { } label: {
                        Image(systemName: "person")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(width: 32, height: 32)
                            .background(Theme.Bg.subtle, in: Circle())
                    }
                    .tint(Theme.Text.primary)
                    .accessibilityLabel("Accounts and settings")
                }
            }
        }
    }
}

/// The hero: a status sentence, how far ahead you are, what you've kept, and the one thing to do.
struct VerdictCard: View {
    let verdict: Verdict?
    let linked: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s16) {
            if let verdict {
                filled(verdict)
            } else {
                empty
            }
        }
        .padding(Theme.Spacing.s20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Bg.elevated, in: RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous).strokeBorder(Theme.Border.subtle))
    }

    private var empty: some View {
        Group {
            Text("POISE")
                .font(Theme.Font.caption2Strong)
                .foregroundStyle(Theme.Text.tertiary)
            Text(linked ? "Reading your accounts…" : "Link a bank to get your first verdict.")
                .font(Theme.Font.verdictLG)
                .foregroundStyle(Theme.Text.primary)
            Text("Poise reads your accounts and tells you how you’re doing — in one sentence, with the one thing to do about it.")
                .font(Theme.Font.verdictMD)
                .foregroundStyle(Theme.Text.secondary)
            if !linked {
                Button("Link a bank") { }
                    .buttonStyle(.primary)
            }
        }
    }

    @ViewBuilder
    private func filled(_ verdict: Verdict) -> some View {
        HStack {
            StatusPill(status: verdict.status)
            Spacer()
        }
        Text(verdict.sentence)
            .font(Theme.Font.verdictLG)
            .foregroundStyle(Theme.Text.primary)
        HStack(alignment: .top, spacing: Theme.Spacing.s16) {
            stat("AHEAD", value: verdict.ahead.amount.money, color: verdict.ahead.amount < 0 ? Theme.Status.heads : Theme.Text.primary,
                 sub: verdict.ahead.crunch.map { "short on \($0.date.formatted(.dateTime.month(.abbreviated).day()))" } ?? "through \(verdict.ahead.through.formatted(.dateTime.weekday(.abbreviated))) · payday")
            stat("KEPT", value: verdict.kept.onPacePercent.percent, color: verdict.status == .goodShape ? Theme.Status.good : Theme.Text.primary,
                 sub: "on pace · \(verdict.kept.keptSoFar.money) so far")
        }
    }

    private func stat(_ label: String, value: String, color: Color, sub: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(Theme.Font.captionStrong).foregroundStyle(Theme.Text.tertiary)
            Text(value).font(Theme.Font.moneyLG).foregroundStyle(color)
            Text(sub).font(Theme.Font.footnote).foregroundStyle(Theme.Text.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct StatusPill: View {
    let status: VerdictStatus

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).font(Theme.Font.caption2Strong).foregroundStyle(color)
        }
        .padding(.vertical, 4).padding(.leading, 8).padding(.trailing, 12)
        .background(background, in: Capsule())
    }

    private var label: String {
        switch status {
        case .goodShape: "IN GOOD SHAPE"
        case .onTrack: "ON TRACK"
        case .headsUp: "HEADS UP"
        }
    }
    private var color: Color {
        switch status {
        case .goodShape: Theme.Status.good
        case .onTrack: Theme.Status.track
        case .headsUp: Theme.Status.heads
        }
    }
    private var background: Color {
        switch status {
        case .goodShape: Theme.Status.goodBg
        case .onTrack: Theme.Status.trackBg
        case .headsUp: Theme.Status.headsBg
        }
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Font.headline)
            .foregroundStyle(Theme.Text.onAccent)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(Theme.Accent.default.opacity(configuration.isPressed ? 0.85 : 1), in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

extension Decimal {
    /// "$1,240" / "−$150" — whole dollars for the verdict, cents elsewhere.
    var money: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 0
        formatter.minusSign = "−"
        return formatter.string(from: self as NSDecimalNumber) ?? "\(self)"
    }
}

extension Double {
    var percent: String { "\(Int((self * 100).rounded()))%" }
}

#Preview("Empty") {
    VerdictCard(verdict: nil, linked: false).padding().background(Theme.Bg.base)
}
