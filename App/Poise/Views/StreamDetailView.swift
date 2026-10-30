import SwiftUI
import PoiseKit

/// A subscription or bill, opened from Leaks: what it costs now, what changed, the charges behind it, and the way out.
struct StreamDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let stream: RecurringStream
    @State private var selected: PoiseKit.Transaction?
    @State private var cancelling = false
    @State private var cancelDate = Date.now

    private var charges: [PoiseKit.Transaction] { model.charges(for: stream) }
    private var cancelledOn: Date? { model.isCancelled(stream) }
    private var live: RecurringStream { model.allStreams.first { $0.id == stream.id } ?? stream }   // the current shape, after re-filing
    private var dismissed: Bool { model.settings.dismissedStreams.contains(stream.id) }
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
                    if let cancelledOn { cancelledCard(cancelledOn) }
                    else if stream.isEnded { endedCard }
                    else { callout }
                    if stream.kind != .income, cancelledOn == nil { kindChooser.padding(.top, Theme.Spacing.s4) }
                    if stream.kind != .income, let usage = model.usage(for: stream), usage.thisMonth > 0 || usage.lastMonth > 0 { usageCard(usage).padding(.top, Theme.Spacing.s12) }
                    SectionHeader(title: charges.isEmpty ? "Charges" : (model.usage(for: stream) != nil ? "Plan charges · \(charges.count)" : "Charges · \(charges.count)"))
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
                        if cancelledOn != nil {
                            NavRow(symbol: "arrow.uturn.backward", label: "Not cancelled after all", value: "") { Task { await model.uncancel(stream) } }
                        } else {
                            if stream.kind != .income {
                                Menu {
                                    ForEach(model.categories.all) { c in
                                        Button { Task { await model.file(stream, under: c.id) } } label: { Label(c.name, systemImage: c.symbol) }
                                    }
                                } label: {
                                    HStack(spacing: Theme.Spacing.s12) {
                                        Image(systemName: model.categories.symbol(model.categoryID(for: live))).font(.system(size: 17, weight: .medium)).foregroundStyle(Theme.Text.secondary).frame(width: 24)
                                        Text("File under").font(Theme.Font.body).foregroundStyle(Theme.Text.primary)
                                        Spacer()
                                        Text(model.categories.name(model.categoryID(for: live))).font(Theme.Font.body).foregroundStyle(Theme.Text.secondary)
                                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.Text.tertiary)
                                    }
                                    .padding(.horizontal, Theme.Spacing.s16).frame(minHeight: 44).contentShape(Rectangle())
                                }
                                RowDivider()
                            }
                            ToggleRow(label: "Heads-up before it renews", isOn: Binding(get: { headsUp }, set: { on in Task { await model.setRenewalHeadsUp(on, for: stream) } }))
                            if stream.kind != .income {
                                RowDivider()
                                NavRow(symbol: "xmark.circle", label: stream.isEnded ? "I cancelled this" : "I cancelled this", value: "") { cancelDate = .now; cancelling = true }
                            }
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.s16)
                    Text(cancelledOn != nil ? "Undo brings it back exactly as it was."
                         : stream.kind == .income ? (headsUp ? "The next \(stream.merchant) deposit becomes a heads-up the moment it lands." : "Turn this on and the next deposit becomes a heads-up the moment it lands.")
                         : "Cancelled means it stops counting everywhere — and if \(stream.merchant.prettyMerchant) charges again, it goes to the top of Leaks with a heads-up.")
                        .font(Theme.Font.caption).foregroundStyle(Theme.Text.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, Theme.Spacing.s16).padding(.top, Theme.Spacing.s8)

                    if stream.kind != .income, cancelledOn == nil {
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
            .sheet(isPresented: $cancelling) {
                CancelSheet(stream: stream, date: $cancelDate) { Task { await model.cancel(stream, on: cancelDate) } }
                    .presentationDetents([.height(420)]).presentationDragIndicator(.visible)
            }
        }
    }

    // MARK: cancelled / ended / re-filed

    private func cancelledCard(_ on: Date) -> some View {
        calloutCard(symbol: "checkmark.shield", tint: Theme.Status.good, background: Theme.Status.goodBg,
                    title: "Cancelled \(on.formatted(.dateTime.month(.abbreviated).day())) — Poise stopped counting it",
                    body: "\(stream.amount.money)\(stream.cadence.perLabel) out of Leaks, Next 14 and the verdict. If \(stream.merchant.prettyMerchant) charges you again, it goes straight to the top of Leaks and you get a heads-up the moment it lands.")
    }

    private var endedCard: some View {
        calloutCard(symbol: "moon.zzz", tint: Theme.Text.secondary, background: Theme.Bg.subtle,
                    title: "Ended on its own · \(stream.quietLabel)",
                    body: "Last charge \(stream.lastSeen.formatted(.dateTime.month(.abbreviated).day())) and nothing since, so it stopped counting. If \(stream.merchant.prettyMerchant) charges again it comes back — with a heads-up.")
    }

    /// Subscription, bill, or just purchases that happened to line up.
    private var kindChooser: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s8) {
            Text("THIS IS A…").font(Theme.Font.caption2Strong).foregroundStyle(Theme.Text.tertiary)
            StreamKindChips(stream: stream)
            Text("Subscriptions and bills both land in Next 14; “Just purchases” takes it out of Leaks. The category is separate — this one is \(model.categories.name(model.categoryID(for: live))).")
                .font(Theme.Font.caption).foregroundStyle(Theme.Text.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, Theme.Spacing.s16)
    }

    private func usageCard(_ u: AppModel.Usage) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "bolt").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.Accent.default).padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text("Plus usage · \(u.thisMonth.money2) this month").font(Theme.Font.subheadStrong).foregroundStyle(Theme.Text.primary)
                Text("\(u.count) pay-as-you-go charge\(u.count == 1 ? "" : "s") on top of the \(stream.amount.money) plan — normal for \(stream.merchant.prettyMerchant), and not counted as the subscription. Last month: \(u.lastMonth.money2).")
                    .font(Theme.Font.footnote).foregroundStyle(Theme.Text.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.s16)
        .background(Theme.Accent.subtle, in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
        .padding(.horizontal, Theme.Spacing.s16)
    }

    private var hero: some View {
        VStack(spacing: 4) {
            MerchantCircle(logoURL: model.logoURL(for: live), symbol: model.categories.symbol(model.categoryID(for: live)), size: 64)
            Text(stream.merchant).font(Theme.Font.titleMD).foregroundStyle(Theme.Text.primary).multilineTextAlignment(.center).padding(.top, 4)
            Text((stream.isEnded || cancelledOn != nil ? "\(stream.cadence.title) · last charge \(stream.lastSeen.formatted(.dateTime.month(.abbreviated).day()))" : "\(stream.cadence.title) · \(stream.cadence == .annual ? "renews" : "next") \(stream.nextExpected.formatted(.dateTime.month(.abbreviated).day()))")
                 + (stream.kind == .income ? "" : " · \(model.categories.name(model.categoryID(for: live)))"))
                .font(Theme.Font.subhead).foregroundStyle(Theme.Text.secondary)
            Text(stream.amount.money2).font(Theme.Font.moneyLG).foregroundStyle(Theme.Text.primary).padding(.top, 2)
            if let cancelledOn {
                Tag(label: "Cancelled \(cancelledOn.formatted(.dateTime.month(.abbreviated).day()))", tone: .track).padding(.top, 4)
            } else if stream.isEnded {
                Tag(label: "Ended").padding(.top, 4)
            } else if let previous = stream.previousAmount, stream.priceWentUp {
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


/// "Cancelled Cursor?" — when, and what happens next.
struct CancelSheet: View {
    @Environment(\.dismiss) private var dismiss
    let stream: RecurringStream
    @Binding var date: Date
    let confirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s12) {
            Text("Cancelled \(stream.merchant.prettyMerchant)?").font(Theme.Font.titleMD).foregroundStyle(Theme.Text.primary).padding(.top, Theme.Spacing.s12)
            Text("Poise stops counting the \(stream.amount.money)\(stream.cadence.perLabel) from the date you cancelled and keeps an eye out: a charge after that goes to the top of Leaks with a heads-up.")
                .font(Theme.Font.body).foregroundStyle(Theme.Text.secondary)
            HStack {
                Text("When did you cancel?").font(Theme.Font.body).foregroundStyle(Theme.Text.primary)
                Spacer()
                DatePicker("", selection: $date, in: ...Date.now, displayedComponents: .date).labelsHidden().tint(Theme.Accent.default)
            }
            .padding(.horizontal, Theme.Spacing.s16).frame(minHeight: 52)
            .background(Theme.Bg.elevated, in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous).strokeBorder(Theme.Border.subtle))
            Button("Mark as cancelled") { confirm(); dismiss() }.buttonStyle(.primary).padding(.top, Theme.Spacing.s4)
            Button("Not yet") { dismiss() }.buttonStyle(.ghost)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Spacing.s16)
        .background(Theme.Bg.base)
    }
}


/// Subscription, bill, or just purchases — the one answer about how a stream charges, shown on the stream and on each
/// of its charges. Applies at once; it never touches the category.
struct StreamKindChips: View {
    @Environment(AppModel.self) private var model
    let stream: RecurringStream
    private var live: RecurringStream { model.allStreams.first { $0.id == stream.id } ?? stream }
    private var dismissed: Bool { model.settings.dismissedStreams.contains(stream.id) }

    var body: some View {
        HStack(spacing: 8) {
            Chip(label: "Subscription", symbol: "arrow.clockwise", on: !dismissed && live.kind == .subscription) { set(.subscription) }
            Chip(label: "Bill", symbol: "doc.text", on: !dismissed && live.kind == .bill) { set(.bill) }
            Chip(label: "Just purchases", symbol: "minus", on: dismissed) { set(nil) }
        }
        .sensoryFeedback(.selection, trigger: dismissed ? "none" : live.kind.rawValue)
    }

    private func set(_ kind: StreamKind?) { Task { await model.setStreamKind(stream, kind) } }
}
