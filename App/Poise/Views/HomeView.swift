import SwiftUI
import PoiseKit

struct HomeView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @State private var searchText = ""
    @State private var filterAccount: String?
    @State private var filterCategory: String?
    @State private var filterPending = false
    @State private var filterExcluded = false
    private var searching: Bool { !searchText.isEmpty || filterAccount != nil || filterCategory != nil || filterPending || filterExcluded }

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            ScrollView {
                if searching {
                    searchResults
                } else {
                VStack(spacing: Theme.Spacing.s12) {
                    ForEach(model.relinkNeeded) { item in
                        Button { Task { await model.relink(item) } } label: {
                            HStack(spacing: Theme.Spacing.s12) {
                                Image(systemName: "exclamationmark.triangle").font(.system(size: 17, weight: .medium)).foregroundStyle(Theme.Status.track)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(item.institution) needs you to sign in again").font(Theme.Font.subheadStrong).foregroundStyle(Theme.Text.primary)
                                    Text("Balances may be out of date until you do.").font(Theme.Font.footnote).foregroundStyle(Theme.Text.secondary)
                                }
                                Spacer(minLength: 8)
                                Text("Relink").font(Theme.Font.subheadStrong).foregroundStyle(Theme.Accent.default)
                            }
                            .padding(Theme.Spacing.s12).padding(.horizontal, 4)
                            .background(Theme.Status.trackBg, in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                    if model.walletAccessLost {
                        Button { openURL(URL(string: UIApplication.openSettingsURLString)!) } label: {
                            HStack(spacing: Theme.Spacing.s12) {
                                Image(systemName: "exclamationmark.triangle").font(.system(size: 17, weight: .medium)).foregroundStyle(Theme.Status.track)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Poise can't read Wallet any more").font(Theme.Font.subheadStrong).foregroundStyle(Theme.Text.primary)
                                    Text("Apple Card, Apple Cash and Savings stop here until access is back on.").font(Theme.Font.footnote).foregroundStyle(Theme.Text.secondary)
                                }
                                Spacer(minLength: 8)
                                Text("Settings").font(Theme.Font.subheadStrong).foregroundStyle(Theme.Accent.default)
                            }
                            .padding(Theme.Spacing.s12).padding(.horizontal, 4)
                            .background(Theme.Status.trackBg, in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                    VerdictCard(verdict: model.verdict, insight: model.topInsight, linked: model.looksLinked, linking: model.isLinking,
                                onLink: { model.startLink() },
                                onInsight: { insight in model.open(insight) })
                    if let last = model.lastSync {
                        Text("\((model.institutions.isEmpty ? ["Accounts"] : model.institutions).joined(separator: " · ")) · \(last.freshness)")
                            .font(Theme.Font.caption).foregroundStyle(Theme.Text.tertiary).lineLimit(1)
                    }
                    if let since = model.since {
                        Button { model.showSince = true } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "sparkles").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.Accent.default)
                                Text("Since \(since.lastLooked.sinceLabel) · \(since.summary)").font(Theme.Font.footnote).foregroundStyle(Theme.Text.primary).multilineTextAlignment(.leading)
                                Spacer(minLength: 4)
                                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.Text.tertiary)
                            }
                            .padding(.horizontal, 12).padding(.vertical, 10)
                            .background(Theme.Accent.subtle, in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                    if model.showPushAsk {
                        Card(padding: Theme.Spacing.s16) {
                            VStack(alignment: .leading, spacing: Theme.Spacing.s12) {
                                HStack(alignment: .top, spacing: Theme.Spacing.s12) {
                                    IconCircle(symbol: "bell", size: 36, fill: Theme.Accent.subtle, color: Theme.Accent.default)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Know the moment something lands").font(Theme.Font.headline).foregroundStyle(Theme.Text.primary)
                                        Text("A charge, a fee, a renewal, a refund — Poise can tell you as it happens, not when you remember to look. Never marketing.").font(Theme.Font.footnote).foregroundStyle(Theme.Text.secondary)
                                    }
                                }
                                HStack(spacing: Theme.Spacing.s8) {
                                    Button("Turn on") { Task { await model.enablePush() } }.buttonStyle(.primary).frame(maxWidth: 120)
                                    Button("Not now") { model.declinePush() }.font(Theme.Font.subheadStrong).foregroundStyle(Theme.Accent.default).buttonStyle(.plain).padding(.horizontal, 12)
                                }
                            }
                        }
                    }
                    if model.isReviewDay, !model.reviewCards.isEmpty {
                        Button { model.showReview = true } label: {
                            InsightRowView(insight: Insight(id: "review", kind: .positive, tone: .good, title: "Your week is ready", body: "Five cards, about 60 seconds.", rank: 0))
                        }
                        .buttonStyle(.plain)
                        .background(Theme.Status.goodBg, in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
                        .padding(.top, Theme.Spacing.s8)
                    }
                    if !model.openWatches.isEmpty { WatchingCard().padding(.top, Theme.Spacing.s8) }
                    if model.looksLinked {
                        Feed(transactions: model.transactions, accounts: model.accounts) { model.selectedTransaction = $0 }
                    }
                }
                .padding(.horizontal, Theme.Spacing.s16)
                .padding(.top, Theme.Spacing.s4)
                .padding(.bottom, Theme.Spacing.s24)
                }
            }
            .background(Theme.Bg.base)
            .refreshable { await model.refresh() }
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Merchant, note or amount")
            .navigationTitle("Home")
            #if DEBUG
            .onAppear { let a = ProcessInfo.processInfo.arguments; if let i = a.firstIndex(of: "-search"), i + 1 < a.count { searchText = a[i + 1] } }
            #endif
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { model.showProfile = true } label: {
                        Image(systemName: "person").font(.system(size: 15, weight: .semibold))
                            .frame(width: 32, height: 32).background(Theme.Bg.subtle, in: Circle())
                    }
                    .tint(Theme.Text.primary)
                    .accessibilityLabel("Accounts and settings")
                }
            }
            .navigationDestination(isPresented: $model.showWatching) { WatchingView() }
        }
    }

}

extension HomeView {
    /// Results replace the feed while a query or a filter is active: chips first, then the matches with their dates.
    private var searchResults: some View {
        let rows = model.search(searchText, account: filterAccount, category: filterCategory, pending: filterPending, excluded: filterExcluded)
        let spent = rows.filter { ($0.kind == .spend || $0.kind == .untracked) && !$0.excluded }.reduce(Decimal(0)) { $0 + $1.magnitude }
        return VStack(alignment: .leading, spacing: Theme.Spacing.s12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Chip(label: "Pending", symbol: "clock", on: filterPending) { filterPending.toggle() }
                    Chip(label: "Not counted", symbol: "eye.slash", on: filterExcluded) { filterExcluded.toggle() }
                    ForEach(model.accounts) { a in Chip(label: a.name, symbol: a.symbol, on: filterAccount == a.id) { filterAccount = filterAccount == a.id ? nil : a.id } }
                    ForEach(model.categories.all) { c in Chip(label: c.name, symbol: c.symbol, on: filterCategory == c.id) { filterCategory = filterCategory == c.id ? nil : c.id } }
                }
                .padding(.horizontal, Theme.Spacing.s16)
            }
            .padding(.top, Theme.Spacing.s4)
            Text(rows.isEmpty ? "Nothing matches" : "\(rows.count) row\(rows.count == 1 ? "" : "s")\(spent > 0 ? " · \(spent.money2) spent" : "")")
                .font(Theme.Font.caption).foregroundStyle(Theme.Text.tertiary).padding(.horizontal, Theme.Spacing.s16)
            if !rows.isEmpty {
                Card {
                    ForEach(Array(rows.prefix(200).enumerated()), id: \.element.id) { i, t in
                        Button { model.selectedTransaction = t } label: { TransactionRowView(transaction: t, account: model.accounts.first { $0.id == t.accountID }, showsDate: true) }
                            .buttonStyle(.plain)
                            .contextMenu { Button("All charges from \(t.displayMerchant)", systemImage: "magnifyingglass") { model.selectedMerchant = .init(key: t.merchantKey) } }
                        if i < min(200, rows.count) - 1 { RowDivider() }
                    }
                }
                .padding(.horizontal, Theme.Spacing.s16)
            }
        }
        .padding(.bottom, Theme.Spacing.s24)
    }
}

/// The hero: a status sentence, how far ahead you are, what you've kept, and the one thing to do.
struct VerdictCard: View {
    let verdict: Verdict?
    var insight: Insight? = nil
    let linked: Bool
    var linking = false
    var onLink: () -> Void = {}
    var onInsight: (Insight) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s16) {
            if let verdict { filled(verdict) } else { empty }
        }
        .padding(Theme.Spacing.s20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Bg.elevated, in: RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous).strokeBorder(Theme.Border.subtle))
    }

    private var empty: some View {
        Group {
            Text("POISE").font(Theme.Font.caption2Strong).foregroundStyle(Theme.Text.tertiary)
            Text(linked ? "Reading your accounts…" : "Link a bank to get your first verdict.")
                .font(Theme.Font.verdictLG).foregroundStyle(Theme.Text.primary)
            Text("Poise reads your accounts and tells you how you’re doing — in one sentence, with the one thing to do about it.")
                .font(Theme.Font.verdictMD).foregroundStyle(Theme.Text.secondary)
            if !linked {
                Button(linking ? "Opening…" : "Link a bank", action: onLink).buttonStyle(.primary).disabled(linking)
            }
        }
    }

    @ViewBuilder
    private func filled(_ verdict: Verdict) -> some View {
        HStack { StatusPill(status: verdict.status); Spacer() }
        Text(verdict.sentence).font(Theme.Font.verdictLG).foregroundStyle(Theme.Text.primary)
        HStack(alignment: .top, spacing: Theme.Spacing.s16) {
            stat("AHEAD", value: verdict.ahead.amount.money, color: verdict.ahead.amount < 0 ? Theme.Status.heads : Theme.Text.primary,
                 sub: verdict.ahead.crunch.map { "short on \($0.date.formatted(.dateTime.month(.abbreviated).day()))" } ?? "through \(verdict.ahead.through.formatted(.dateTime.weekday(.abbreviated))) · payday")
            stat("KEPT", value: verdict.kept.onPacePercent.percent, color: verdict.status == .goodShape ? Theme.Status.good : verdict.status == .onTrack ? Theme.Status.track : Theme.Text.primary,
                 sub: "on pace · \(verdict.kept.keptSoFar.money) so far")
        }
        Divider().overlay(Theme.Border.subtle)
        if let insight {
            Button { onInsight(insight) } label: {
                HStack(spacing: Theme.Spacing.s12) {
                    IconCircle(symbol: insight.kind.symbol, size: 32, fill: insight.tone.background, color: insight.tone.color)
                    Text(insight.title).font(Theme.Font.verdictMD).foregroundStyle(Theme.Text.primary).multilineTextAlignment(.leading)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.Text.tertiary)
                }
            }
            .buttonStyle(.plain)
        } else {
            HStack(spacing: Theme.Spacing.s12) {
                IconCircle(symbol: "checkmark", size: 32, fill: Theme.Status.goodBg, color: Theme.Status.good)
                Text("Nothing needs a look right now.").font(Theme.Font.verdictMD).foregroundStyle(Theme.Text.secondary)
                Spacer(minLength: 8)
            }
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

/// The feed: newest first, grouped by the day the user actually paid. Transfers and refunds are shown, never counted.
struct Feed: View {
    let transactions: [PoiseKit.Transaction]
    let accounts: [Account]
    var onSelect: (PoiseKit.Transaction) -> Void = { _ in }

    private var days: [(Date, [PoiseKit.Transaction])] {
        let cal = Calendar.current
        let groups = Dictionary(grouping: transactions) { cal.startOfDay(for: $0.displayDate) }
        return groups.keys.sorted(by: >).map { ($0, groups[$0]!.sorted { $0.displayDate > $1.displayDate }) }
    }

    var body: some View {
        LazyVStack(spacing: 0) {
            if transactions.isEmpty {
                EmptyStateView(symbol: "bolt", title: "Your feed starts here", body: "Every charge, the day you paid it. Transfers and refunds shown, never counted as spending.")
            }
            ForEach(days, id: \.0) { day, rows in
                DayHeader(day: day, total: rows.filter { ($0.kind == .spend || $0.kind == .untracked) && !$0.excluded }.reduce(0) { $0 + $1.amount })
                Card {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { i, t in
                        Button { onSelect(t) } label: { TransactionRowView(transaction: t, account: accounts.first { $0.id == t.accountID }) }
                            .buttonStyle(.plain)
                            .contextMenu { RowContextMenu(transaction: t) }
                        if i < rows.count - 1 { RowDivider() }
                    }
                }
            }
        }
    }
}

struct DayHeader: View {
    let day: Date
    let total: Decimal
    var body: some View {
        HStack {
            Text(label).font(Theme.Font.footnote.weight(.semibold)).foregroundStyle(Theme.Text.tertiary)
            Spacer()
            if total != 0 { Text(total.money2).font(Theme.Font.moneyXS).foregroundStyle(Theme.Text.tertiary) }
        }
        .padding(.top, Theme.Spacing.s20).padding(.bottom, Theme.Spacing.s8).padding(.horizontal, Theme.Spacing.s16)
    }
    private var label: String {
        let cal = Calendar.current
        if cal.isDateInToday(day) { return "TODAY" }
        if cal.isDateInYesterday(day) { return "YESTERDAY" }
        return day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()).uppercased()
    }
}

struct TransactionRowView: View {
    @Environment(AppModel.self) private var model
    let transaction: PoiseKit.Transaction
    let account: Account?
    /// Lists that aren't day-grouped (a subscription's charges) show the date under the amount.
    var showsDate = false

    private var watch: Watch? { model.watch(for: transaction.id) ?? (model.watches.first { $0.kind == .merchant && $0.resolvedTransactionID == transaction.id }) }

    var body: some View {
        HStack(spacing: Theme.Spacing.s12) {
            MerchantCircle(logoURL: transaction.excluded || transaction.kind == .transfer || transaction.kind == .ccPayment ? nil : transaction.logoURL, symbol: symbol, fill: circleFill, color: iconColor, dashed: transaction.pending)
                .overlay(alignment: .bottomTrailing) {
                    if watch != nil {
                        ZStack { Circle().fill(Theme.Accent.default); Image(systemName: "bookmark.fill").font(.system(size: 8, weight: .bold)).foregroundStyle(.white) }
                            .frame(width: 18, height: 18).overlay(Circle().strokeBorder(Theme.Bg.elevated, lineWidth: 2)).offset(x: 3, y: 3)
                    }
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(transaction.displayMerchant).font(Theme.Font.headline).foregroundStyle(titleColor).lineLimit(1)
                Text(subtitle).font(Theme.Font.footnote).foregroundStyle(subtitleColor).lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(amountText).font(Theme.Font.moneyMD).foregroundStyle(amountColor)
                if let w = watch, w.status == .triggered { Text("CHARGED AGAIN").font(Theme.Font.caption2Strong).foregroundStyle(Theme.Status.heads) }
                else if let w = watch, w.status == .overdue { Text("OVERDUE").font(Theme.Font.caption2Strong).foregroundStyle(Theme.Status.track) }
                else if watch != nil { Text("WATCHING").font(Theme.Font.caption2Strong).foregroundStyle(Theme.Accent.default) }
                else if transaction.excluded { Text("NOT COUNTED").font(Theme.Font.caption2Strong).foregroundStyle(Theme.Text.tertiary) }
                else if transaction.pending { Text("PENDING").font(Theme.Font.caption2Strong).foregroundStyle(Theme.Text.tertiary) }
                else if transaction.isFee { Text("FEE").font(Theme.Font.caption2Strong).foregroundStyle(Theme.Status.heads) }
                else if showsDate { Text(transaction.displayDate.formatted(.dateTime.month(.abbreviated).day()).uppercased()).font(Theme.Font.caption2Strong).foregroundStyle(Theme.Text.tertiary) }
            }
        }
        .padding(.vertical, Theme.Spacing.s12).padding(.horizontal, Theme.Spacing.s16)
        .contentShape(Rectangle())
        .opacity(transaction.excluded ? 0.55 : 1)
    }

    private var subtitle: String {
        var parts: [String] = []
        if let note = transaction.note { parts.append(note) }
        if transaction.excluded { parts.append("Left out"); if let account { parts.append(account.name) }; return parts.joined(separator: " · ") }
        switch transaction.kind {
        case .spend: parts.append(model.categories.name(transaction.categoryID))
        case .income: parts.append("Income")
        case .transfer: parts.append("Transfer · not spending")
        case .ccPayment: parts.append("Card payment · not spending")
        case .refund: parts.append(model.watches.contains { $0.resolvedTransactionID == transaction.id && $0.kind == .refund } ? "Refund · watch closed" : transaction.pairID == nil ? "Refund" : "Refund · nets against a charge")
        case .untracked: return "Tap to tag what this was"
        }
        if transaction.pending, transaction.authorizedDate != nil { parts.append("authorized \(transaction.displayDate.formatted(.dateTime.weekday(.abbreviated)))") }
        else if let account { parts.append(account.mask.map { "\(account.name) ••\($0)" } ?? account.name) }
        return parts.joined(separator: " · ")
    }
    private var amountText: String { (transaction.amount > 0 ? "+" : "") + transaction.amount.money2 }
    private var amountColor: Color {
        if transaction.pending { return Theme.Money.pending }
        switch transaction.kind {
        case .income, .refund: return Theme.Money.in
        case .transfer, .ccPayment: return Theme.Text.tertiary
        default: return Theme.Text.primary
        }
    }
    private var titleColor: Color { transaction.kind == .transfer || transaction.kind == .ccPayment ? Theme.Text.secondary : Theme.Text.primary }
    private var subtitleColor: Color { transaction.kind == .untracked ? Theme.Accent.default : Theme.Text.secondary }
    private var circleFill: Color {
        switch transaction.kind {
        case .income, .refund: Theme.Status.goodBg
        case .untracked: Theme.Accent.subtle
        default: Theme.Bg.subtle
        }
    }
    private var iconColor: Color {
        if transaction.pending { return Theme.Text.tertiary }
        switch transaction.kind {
        case .income, .refund: return Theme.Status.good
        case .transfer, .ccPayment: return Theme.Text.tertiary
        case .untracked: return Theme.Accent.default
        default: return Theme.Text.primary
        }
    }
    private var symbol: String {
        if transaction.excluded { return "eye.slash" }
        return switch transaction.kind {
        case .income: "arrow.down.left"
        case .transfer: "arrow.left.arrow.right"
        case .ccPayment: "creditcard"
        case .refund: "arrow.uturn.backward"
        case .untracked: "questionmark"
        case .spend: model.categories.symbol(transaction.categoryID)
        }
    }
}

/// Long-press on a feed row: the two watch actions first.
struct RowContextMenu: View {
    @Environment(AppModel.self) private var model
    let transaction: PoiseKit.Transaction
    var body: some View {
        if transaction.kind == .spend || transaction.kind == .untracked {
            if let w = model.watch(for: transaction.id), w.kind == .refund {
                Button("Stop waiting for a refund", systemImage: "arrow.uturn.backward") { Task { await model.removeWatch(w) } }
            } else {
                Button("Waiting for a refund", systemImage: "arrow.uturn.backward") { Task { await model.addWatch(Watch(kind: .refund, transactionID: transaction.id, merchant: transaction.merchant, expectedAmount: transaction.magnitude)) } }
            }
            if model.isWatched(merchantKey: transaction.merchantKey) {
                Button("Stop watching \(transaction.displayMerchant)", systemImage: "eye.slash") { Task { if let w = model.watches.first(where: { $0.kind == .merchant && $0.matcher == transaction.merchantKey && $0.status.isOpen }) { await model.removeWatch(w) } } }
            } else {
                Button("Tell me if they charge again", systemImage: "eye") { Task { await model.addWatch(Watch(kind: .merchant, transactionID: transaction.id, merchant: transaction.merchant)) } }
            }
            Divider()
        }
        Button("Change category", systemImage: "slider.horizontal.3") { model.selectedTransaction = transaction }
        if transaction.kind != .transfer { Button("Not spending", systemImage: "minus") { Task { await model.correct(transaction, kind: .transfer, categoryID: nil, always: false) } } }
    }
}
