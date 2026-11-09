import SwiftUI
import PoiseKit

/// Money leaving silently: price creep, renewals coming up, every subscription, fees this year.
struct LeaksView: View {
    @Environment(AppModel.self) private var model
    @State private var undo: PendingUndo?

    struct PendingUndo { let id = UUID(); let message: String; let revert: @MainActor () async -> Void }

    private var subscriptions: [RecurringStream] { model.streams.filter { $0.kind == .subscription } }
    private var monthly: Decimal { subscriptions.reduce(0) { $0 + monthlyEquivalent($1) } }
    private var bills: [RecurringStream] { model.streams.filter { $0.kind == .bill } }
    private var billsMonthly: Decimal { bills.reduce(0) { $0 + monthlyEquivalent($1) } }
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
                        Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                            GridRow {
                                tile("SUBSCRIPTIONS", value: monthly.money + "/mo")
                                tile("BILLS", value: billsMonthly.money + "/mo")
                            }
                            GridRow {
                                tile("FEES THIS YEAR", value: model.fees.total.money)
                                let moved = priceUps.count + model.pricesMovedLately.filter { $0.direction == .up }.count
                                Button { model.showPricesList(filter: "up") } label: { tile("PRICE CHANGES", value: "\(moved)", color: moved == 0 ? Theme.Text.primary : Theme.Status.track) }.buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, Theme.Spacing.s16).padding(.top, Theme.Spacing.s4)
                        if !leakInsights.isEmpty {
                            SectionHeader(title: "Worth a look")
                            // Each one answered where it sits: "it's fine" clears it, the other opens it. A swipe used to be
                            // the only way to clear one, and it never worked — these rows aren't in a List.
                            Card { ForEach(Array(leakInsights.enumerated()), id: \.element.id) { i, ins in
                                VStack(alignment: .leading, spacing: 0) {
                                    Button { model.open(ins) } label: { InsightRowView(insight: ins, showChevron: false) }.buttonStyle(.plain)
                                    HStack(spacing: 8) {
                                        Button { answer(ins) } label: {
                                            HStack(spacing: 5) { Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)); Text(answers(ins).yes) }
                                        }
                                        .buttonStyle(.answerPrimary)
                                        Button(answers(ins).look) { model.open(ins) }.buttonStyle(.answer)
                                    }
                                    .padding(.leading, Theme.Spacing.s16 + 36 + Theme.Spacing.s12).padding(.top, -4).padding(.bottom, Theme.Spacing.s12)
                                }
                                if i < leakInsights.count - 1 { RowDivider() }
                            } }
                            .animation(.snappy, value: leakInsights.map(\.id))
                            .padding(.horizontal, Theme.Spacing.s16)
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
                        if !bills.isEmpty {
                            SectionHeader(title: "Bills · \(billsMonthly.money)/mo")
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
            .overlay(alignment: .bottom) {
                if let undo {
                    UndoToast(message: undo.message) {
                        let revert = undo.revert
                        withAnimation(.snappy) { self.undo = nil }
                        Task { await revert() }
                    }
                    .padding(.bottom, Theme.Spacing.s12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task(id: undo.id) {
                        try? await Task.sleep(for: .seconds(5))
                        if self.undo?.id == undo.id { withAnimation(.snappy) { self.undo = nil } }
                    }
                }
            }
            .sensoryFeedback(.success, trigger: undo?.id) { _, new in new != nil }
            .navigationTitle("Leaks")
        }
    }

    /// The two answers a row offers, and what the toast says after the first.
    private func answers(_ i: Insight) -> (yes: String, look: String, done: String) {
        switch i.kind {
        case .duplicate: ("Both are real", "Look into it", "Marked both charges as real")
        case .cancelledCharge: ("I signed back up", "Look into it", "Counting it again")
        case .fee: ("Got it", "See the charge", "Fee noted")
        case .priceMoved: ("Expected", "See it", "Price change marked expected")
        default: ("Expected", "Look into it", "Marked as expected")
        }
    }

    private func answer(_ ins: Insight) {
        let message = answers(ins).done
        Task {
            let revert = await model.settle(ins)
            withAnimation(.snappy) { undo = PendingUndo(message: message, revert: revert) }
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
    @Environment(AppModel.self) private var model
    let stream: RecurringStream
    let cancelledOn: Date?
    var body: some View {
        HStack(spacing: Theme.Spacing.s12) {
            MerchantCircle(logoURL: model.logoURL(for: stream), symbol: model.categories.symbol(model.categoryID(for: stream)), color: Theme.Text.tertiary).opacity(0.6)
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
