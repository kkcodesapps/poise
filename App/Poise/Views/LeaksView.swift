import SwiftUI
import PoiseKit

/// Money leaving silently: price creep, renewals coming up, every subscription, fees this year.
struct LeaksView: View {
    @Environment(AppModel.self) private var model

    private var subscriptions: [RecurringStream] { model.streams.filter { $0.kind == .subscription } }
    private var monthly: Decimal { subscriptions.reduce(0) { $0 + monthlyEquivalent($1) } }
    private var priceUps: [RecurringStream] { model.streams.filter { $0.priceWentUp && $0.kind != .income } }
    private var renewals: [RecurringStream] {
        model.streams.filter { $0.cadence == .annual && (Calendar.current.dateComponents([.day], from: .now, to: $0.nextExpected).day ?? 99) <= 30 }
    }
    private var leakInsights: [Insight] { model.insights.filter { [.cancelledCharge, .streamReturned, .duplicate, .fee, .priceMoved].contains($0.kind) } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    if !model.looksLinked {
                        EmptyStateView(symbol: "drop", title: "Leaks show up here", body: "Link a bank and Poise will find subscriptions, price changes, renewals and fees.")
                    } else {
                        HStack(spacing: 8) {
                            tile("SUBSCRIPTIONS", value: monthly.money + "/mo")
                            tile("FEES THIS YEAR", value: model.fees.total.money)
                            let moved = priceUps.count + model.pricesMovedLately.filter { $0.direction == .up }.count
                            Button { model.showPricesList(filter: "up") } label: { tile("PRICE CHANGES", value: "\(moved)", color: moved == 0 ? Theme.Text.primary : Theme.Status.track) }.buttonStyle(.plain)
                        }
                        .padding(.horizontal, Theme.Spacing.s16).padding(.top, Theme.Spacing.s4)
                        if !leakInsights.isEmpty {
                            SectionHeader(title: "Worth a look")
                            Card { ForEach(Array(leakInsights.enumerated()), id: \.element.id) { i, ins in
                                Button { model.open(ins) } label: { InsightRowView(insight: ins) }.buttonStyle(.plain)
                                    .swipeActions { Button("Got it") { model.acknowledge(ins) }.tint(Theme.Accent.default) }
                                if i < leakInsights.count - 1 { RowDivider() }
                            } }.padding(.horizontal, Theme.Spacing.s16)
                        }
                        if !priceUps.isEmpty {
                            SectionHeader(title: "Price went up")
                            list(priceUps)
                        }
                        if !renewals.isEmpty {
                            SectionHeader(title: "Coming up")
                            list(renewals)
                        }
                        SectionHeader(title: subscriptions.isEmpty ? "Subscriptions" : "Subscriptions · \(monthly.money)/mo")
                        if subscriptions.isEmpty {
                            Card { EmptyStateView(symbol: "arrow.clockwise", title: "No subscriptions found yet", body: "Poise needs at least two charges from the same place to call something recurring.") }.padding(.horizontal, Theme.Spacing.s16)
                        } else {
                            list(subscriptions.sorted { $0.amount > $1.amount })
                        }
                        let bills = model.streams.filter { $0.kind == .bill }
                        if !bills.isEmpty {
                            SectionHeader(title: "Bills")
                            list(bills)
                        }
                        if !model.endedStreams.isEmpty {
                            SectionHeader(title: "Cancelled & ended · \(model.endedStreams.count)")
                            Card {
                                ForEach(Array(model.endedStreams.enumerated()), id: \.element.id) { i, s in
                                    Button { model.selectedStream = s } label: { EndedStreamRow(stream: s, cancelledOn: model.isCancelled(s)) }.buttonStyle(.plain)
                                    if i < model.endedStreams.count - 1 { RowDivider() }
                                }
                            }
                            .padding(.horizontal, Theme.Spacing.s16)
                            Text("Cancelled ones you told Poise about; ended ones went quiet for two billing periods on their own. Both stop counting everywhere. If any of them charges again it goes to the top of this screen with a heads-up.")
                                .font(Theme.Font.caption).foregroundStyle(Theme.Text.tertiary).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, Theme.Spacing.s16).padding(.top, Theme.Spacing.s8)
                        }
                        SectionHeader(title: "Fees this year")
                        Card {
                            if model.fees.items.isEmpty {
                                InsightRowView(insight: Insight(id: "fees-none", kind: .positive, tone: .good, title: "No fees this year", body: "No bank, ATM, foreign-transaction or interest charges so far.", rank: 0), showChevron: false)
                            } else {
                                ForEach(Array(model.fees.items.prefix(5).enumerated()), id: \.element.id) { i, t in
                                    Button { model.selectedTransaction = t } label: { TransactionRowView(transaction: t, account: model.accounts.first { $0.id == t.accountID }) }.buttonStyle(.plain)
                                    if i < min(5, model.fees.items.count) - 1 { RowDivider() }
                                }
                            }
                        }
                        .padding(.horizontal, Theme.Spacing.s16)
                    }
                }
                .padding(.bottom, Theme.Spacing.s32)
            }
            .background(Theme.Bg.base)
            .navigationTitle("Leaks")
        }
    }

    private func tile(_ label: String, value: String, color: Color = Theme.Text.primary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(Theme.Font.caption2Strong).foregroundStyle(Theme.Text.tertiary)
            Text(value).font(Theme.Font.moneyMD).foregroundStyle(color)
        }
        .padding(Theme.Spacing.s12).frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Bg.elevated, in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous).strokeBorder(Theme.Border.subtle))
    }

    private func list(_ streams: [RecurringStream]) -> some View {
        Card {
            ForEach(Array(streams.enumerated()), id: \.element.id) { i, s in
                Button { model.selectedStream = s } label: { StreamRowView(stream: s) }.buttonStyle(.plain)
                if i < streams.count - 1 { RowDivider() }
            }
        }
        .padding(.horizontal, Theme.Spacing.s16)
    }

    private func monthlyEquivalent(_ s: RecurringStream) -> Decimal {
        switch s.cadence {
        case .weekly: (s.amount * 52 / 12).roundedToCents
        case .biweekly: (s.amount * 26 / 12).roundedToCents
        case .semimonthly: s.amount * 2
        case .monthly: s.amount
        case .quarterly: (s.amount / 3).roundedToCents
        case .annual: (s.amount / 12).roundedToCents
        }
    }
}


/// A subscription that stopped — by your hand or on its own — muted, with what it used to cost.
struct EndedStreamRow: View {
    let stream: RecurringStream
    let cancelledOn: Date?
    var body: some View {
        HStack(spacing: Theme.Spacing.s12) {
            ZStack {
                Circle().fill(Theme.Bg.subtle)
                Text(String(stream.displayMerchant.prefix(1)).uppercased()).font(Theme.Font.headline).foregroundStyle(Theme.Text.tertiary)
            }
            .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(stream.displayMerchant).font(Theme.Font.headline).foregroundStyle(Theme.Text.secondary).lineLimit(1)
                Text(cancelledOn.map { "Cancelled \($0.formatted(.dateTime.month(.abbreviated).day())) · watching for a charge" }
                     ?? "Ended · last charge \(stream.lastSeen.formatted(.dateTime.month(.abbreviated).day())) · \(stream.quietLabel)")
                    .font(Theme.Font.footnote).foregroundStyle(Theme.Text.tertiary).lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(stream.amount.moneyString(cents: true)).font(Theme.Font.moneyMD).foregroundStyle(Theme.Text.tertiary)
                Text("WAS \(stream.cadence.perLabel)").font(Theme.Font.caption2Strong).foregroundStyle(Theme.Text.tertiary)
            }
        }
        .padding(.vertical, Theme.Spacing.s12).padding(.horizontal, Theme.Spacing.s16)
    }
}

extension RecurringStream {
    /// "two months quiet", "three weeks quiet".
    var quietLabel: String {
        let days = Calendar.current.dateComponents([.day], from: lastSeen, to: .now).day ?? 0
        let months = days / 30, weeks = days / 7
        let n = months >= 1 ? months : weeks
        let unit = months >= 1 ? "month" : "week"
        let words = ["", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven", "twelve"]
        return "\(n < words.count ? words[n] : "\(n)") \(unit)\(n == 1 ? "" : "s") quiet"
    }
}

extension Cadence {
    /// "/mo", "/wk", "/yr" — what the amount is per.
    var perLabel: String {
        switch self { case .weekly: "/wk"; case .biweekly: "/2wk"; case .semimonthly: "×2/mo"; case .monthly: "/mo"; case .quarterly: "/qtr"; case .annual: "/yr" }
    }
}
