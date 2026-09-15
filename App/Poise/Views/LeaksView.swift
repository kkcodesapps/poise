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
    private var leakInsights: [Insight] { model.insights.filter { [.duplicate, .fee].contains($0.kind) } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    if !model.hasLinkedBank {
                        EmptyStateView(symbol: "drop", title: "Leaks show up here", body: "Link a bank and Poise will find subscriptions, price changes, renewals and fees.")
                    } else {
                        HStack(spacing: 8) {
                            tile("SUBSCRIPTIONS", value: monthly.money + "/mo")
                            tile("FEES THIS YEAR", value: model.fees.total.money)
                            tile("PRICE CHANGES", value: "\(priceUps.count)", color: priceUps.isEmpty ? Theme.Text.primary : Theme.Status.track)
                        }
                        .padding(.horizontal, Theme.Spacing.s16).padding(.top, Theme.Spacing.s4)
                        if !leakInsights.isEmpty {
                            SectionHeader(title: "Worth a look")
                            Card { ForEach(Array(leakInsights.enumerated()), id: \.element.id) { i, ins in
                                InsightRowView(insight: ins, showChevron: false)
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
                        SectionHeader(title: "Fees this year")
                        Card {
                            if model.fees.items.isEmpty {
                                InsightRowView(insight: Insight(id: "fees-none", kind: .positive, tone: .good, title: "No fees this year", body: "No bank, ATM, foreign-transaction or interest charges so far.", rank: 0), showChevron: false)
                            } else {
                                ForEach(Array(model.fees.items.prefix(5).enumerated()), id: \.element.id) { i, t in
                                    TransactionRowView(transaction: t, account: model.accounts.first { $0.id == t.accountID })
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
                StreamRowView(stream: s)
                if i < streams.count - 1 { RowDivider() }
            }
        }
        .padding(.horizontal, Theme.Spacing.s16)
    }

    private func monthlyEquivalent(_ s: RecurringStream) -> Decimal {
        switch s.cadence {
        case .weekly: (s.amount * 52 / 12).roundedToCents
        case .biweekly: (s.amount * 26 / 12).roundedToCents
        case .monthly: s.amount
        case .quarterly: (s.amount / 3).roundedToCents
        case .annual: (s.amount / 12).roundedToCents
        }
    }
}
