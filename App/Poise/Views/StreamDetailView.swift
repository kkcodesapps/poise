import SwiftUI
import PoiseKit

/// A subscription or bill, opened from Leaks: what it costs now, what changed, the charges behind it, and the way out.
struct StreamDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let stream: RecurringStream
    @State private var selected: PoiseKit.Transaction?

    private var charges: [PoiseKit.Transaction] { model.charges(for: stream) }
    private var headsUp: Bool { model.isWatched(merchantKey: PoiseKit.Transaction.merchantKey(stream.merchant)) }
    private var daysToNext: Int { Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: .now), to: stream.nextExpected).day ?? 0 }
    private var yearlyDelta: Decimal? {
        guard let previous = stream.previousAmount, stream.amount != previous else { return nil }
        return ((stream.amount - previous) * stream.cadence.perYear).roundedToCents
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    hero
                    callout
                    SectionHeader(title: charges.isEmpty ? "Charges" : "Charges · \(charges.count)")
                    Card {
                        if charges.isEmpty {
                            EmptyStateView(symbol: "arrow.clockwise", title: "No charges in the last year", body: "The stream is older than the feed Poise keeps on the phone.")
                        } else {
                            ForEach(Array(charges.enumerated()), id: \.element.id) { i, t in
                                Button { selected = t } label: { TransactionRowView(transaction: t, account: model.accounts.first { $0.id == t.accountID }, showsDate: true) }.buttonStyle(.plain)
                                if i < charges.count - 1 { RowDivider() }
                            }
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.s16)

                    SectionHeader(title: "Manage")
                    Card {
                        ToggleRow(label: "Heads-up before it renews", isOn: Binding(get: { headsUp }, set: { on in Task { await model.setRenewalHeadsUp(on, for: stream) } }))
                        RowDivider()
                        NavRow(symbol: "xmark.circle", label: "Not a subscription", value: "") { Task { await model.dismiss(stream) } }
                    }
                    .padding(.horizontal, Theme.Spacing.s16)
                    Text(headsUp ? "The next \(stream.merchant) charge becomes a heads-up the moment it lands." : "Turn this on and the next charge becomes a heads-up the moment it lands.")
                        .font(Theme.Font.caption).foregroundStyle(Theme.Text.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, Theme.Spacing.s16).padding(.top, Theme.Spacing.s8)

                    if stream.kind != .income {
                        Button("How to cancel \(stream.merchant)") {
                            let q = "cancel \(stream.merchant) subscription".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                            if let url = URL(string: "https://www.google.com/search?q=\(q)") { openURL(url) }
                        }
                        .buttonStyle(.ghost).padding(.horizontal, Theme.Spacing.s16).padding(.top, Theme.Spacing.s16)
                        Text("Opens a web search — Poise can’t cancel it for you.").font(Theme.Font.caption).foregroundStyle(Theme.Text.tertiary).multilineTextAlignment(.center)
                    }
                }
                .padding(.bottom, Theme.Spacing.s32)
            }
            .background(Theme.Bg.base)
            .navigationTitle(stream.merchant)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() }.tint(Theme.Accent.default) } }
            .sheet(item: $selected) { t in TransactionDetailView(transaction: t) }
        }
    }

    private var hero: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle().fill(Theme.Bg.subtle)
                Text(String(stream.merchant.prefix(1)).uppercased()).font(Theme.Font.titleMD).foregroundStyle(Theme.Text.primary)
            }
            .frame(width: 64, height: 64)
            Text(stream.merchant).font(Theme.Font.titleMD).foregroundStyle(Theme.Text.primary).multilineTextAlignment(.center).padding(.top, 4)
            Text("\(stream.cadence.title) · \(stream.cadence == .annual ? "renews" : "next") \(stream.nextExpected.formatted(.dateTime.month(.abbreviated).day()))")
                .font(Theme.Font.subhead).foregroundStyle(Theme.Text.secondary)
            Text(stream.amount.money2).font(Theme.Font.moneyLG).foregroundStyle(Theme.Text.primary).padding(.top, 2)
            if let previous = stream.previousAmount, stream.priceWentUp {
                Text("WAS \(previous.money2)").font(Theme.Font.caption2Strong).foregroundStyle(Theme.Status.track)
            }
        }
        .frame(maxWidth: .infinity).padding(.top, Theme.Spacing.s12).padding(.bottom, Theme.Spacing.s16).padding(.horizontal, Theme.Spacing.s16)
    }

    /// Price creep or a renewal inside 30 days gets a card; a quiet stream gets nothing.
    @ViewBuilder private var callout: some View {
        if stream.priceWentUp, let previous = stream.previousAmount {
            calloutCard(symbol: "exclamationmark.triangle", tint: Theme.Status.track, background: Theme.Status.trackBg,
                        title: "Went up \((stream.amount - previous).money2) in \(stream.lastSeen.formatted(.dateTime.month(.wide)))",
                        body: "\(previous.money2) → \(stream.amount.money2)." + (yearlyDelta.map { " That’s \($0.money) more a year for the same thing." } ?? ""))
        } else if daysToNext <= 30 {
            calloutCard(symbol: "calendar", tint: Theme.Accent.default, background: Theme.Accent.subtle,
                        title: daysToNext <= 0 ? "Due today" : "\(stream.cadence == .annual ? "Renews" : "Due") in \(daysToNext) day\(daysToNext == 1 ? "" : "s")",
                        body: "\(stream.amount.money2) on \(stream.nextExpected.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())). Decide before it lands, not after.")
        }
    }

    private func calloutCard(symbol: String, tint: Color, background: Color, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(tint).padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(Theme.Font.subheadStrong).foregroundStyle(Theme.Text.primary)
                Text(body).font(Theme.Font.footnote).foregroundStyle(Theme.Text.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.s16)
        .background(background, in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
        .padding(.horizontal, Theme.Spacing.s16)
    }
}

extension Cadence {
    var title: String {
        switch self { case .weekly: "Weekly"; case .biweekly: "Every 2 weeks"; case .semimonthly: "Twice a month"; case .monthly: "Monthly"; case .quarterly: "Quarterly"; case .annual: "Yearly" }
    }
    var perYear: Decimal {
        switch self { case .weekly: 52; case .biweekly: 26; case .semimonthly: 24; case .monthly: 12; case .quarterly: 4; case .annual: 1 }
    }
}
