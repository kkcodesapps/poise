import SwiftUI
import PoiseKit

struct HomeView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.s12) {
                    VerdictCard(verdict: model.verdict, linked: model.hasLinkedBank, linking: model.isLinking) {
                        Task { await model.link() }
                    }
                    if let last = model.lastSync {
                        Text("as of \(last, style: .relative) ago")
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Text.tertiary)
                    }
                    Feed(transactions: model.transactions, accounts: model.accounts)
                }
                .padding(.horizontal, Theme.Spacing.s16)
                .padding(.top, Theme.Spacing.s4)
            }
            .background(Theme.Bg.base)
            .refreshable { await model.refresh() }
            .alert("Something went wrong", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
                Button("OK") { model.errorMessage = nil }
            } message: { Text(model.errorMessage ?? "") }
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
    var linking = false
    var onLink: () -> Void = {}

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
                Button(linking ? "Opening…" : "Link a bank", action: onLink)
                    .buttonStyle(.primary)
                    .disabled(linking)
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


/// The feed: newest first, grouped by the day the user actually paid. Transfers and refunds are shown, never counted.
struct Feed: View {
    let transactions: [PoiseKit.Transaction]
    let accounts: [Account]

    private var days: [(Date, [PoiseKit.Transaction])] {
        let cal = Calendar.current
        let groups = Dictionary(grouping: transactions) { cal.startOfDay(for: $0.displayDate) }
        return groups.keys.sorted(by: >).map { ($0, groups[$0]!.sorted { $0.displayDate > $1.displayDate }) }
    }

    var body: some View {
        LazyVStack(spacing: 0) {
            ForEach(days, id: \.0) { day, rows in
                DayHeader(day: day, total: rows.filter { $0.kind == .spend || $0.kind == .untracked }.reduce(0) { $0 + $1.amount })
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { i, t in
                        TransactionRowView(transaction: t, account: accounts.first { $0.id == t.accountID })
                        if i < rows.count - 1 { Divider().overlay(Theme.Border.subtle).padding(.leading, 68) }
                    }
                }
                .background(Theme.Bg.elevated, in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous).strokeBorder(Theme.Border.subtle))
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
    let transaction: PoiseKit.Transaction
    let account: Account?

    var body: some View {
        HStack(spacing: Theme.Spacing.s12) {
            ZStack {
                Circle().fill(circleFill)
                if transaction.pending { Circle().strokeBorder(Theme.Border.strong, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3])) }
                Image(systemName: symbol).font(.system(size: 17, weight: .medium)).foregroundStyle(iconColor)
            }
            .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(transaction.merchant).font(Theme.Font.headline).foregroundStyle(titleColor).lineLimit(1)
                Text(subtitle).font(Theme.Font.footnote).foregroundStyle(subtitleColor).lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(amountText).font(Theme.Font.moneyMD).foregroundStyle(amountColor)
                Text(transaction.pending ? "PENDING" : transaction.displayDate.formatted(date: .omitted, time: .shortened))
                    .font(transaction.pending ? Theme.Font.caption2Strong : Theme.Font.caption)
                    .foregroundStyle(Theme.Text.tertiary)
            }
        }
        .padding(.vertical, Theme.Spacing.s12).padding(.horizontal, Theme.Spacing.s16)
    }

    private var subtitle: String {
        var parts: [String] = []
        switch transaction.kind {
        case .spend: parts.append(transaction.category?.title ?? "Uncategorized")
        case .income: parts.append("Income")
        case .transfer: parts.append("Transfer · not spending")
        case .ccPayment: parts.append("Card payment · not spending")
        case .refund: parts.append("Refund")
        case .untracked: return "Tap to tag what this was"
        }
        if transaction.pending, transaction.authorizedDate != nil { parts.append("authorized \(transaction.displayDate.formatted(.dateTime.weekday(.abbreviated)))") }
        else if let account { parts.append("\(account.name) ••\(account.mask ?? "")") }
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
        if transaction.pending { return .clear }
        switch transaction.kind {
        case .income, .refund: return Theme.Status.goodBg
        case .untracked: return Theme.Accent.subtle
        default: return Theme.Bg.subtle
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
        switch transaction.kind {
        case .income: return "arrow.down.left"
        case .transfer: return "arrow.left.arrow.right"
        case .ccPayment: return "creditcard"
        case .refund: return "arrow.uturn.backward"
        case .untracked: return "questionmark"
        case .spend:
            switch transaction.category {
            case .home: return "house"
            case .groceries: return "cart"
            case .dining: return "fork.knife"
            case .transport: return "car"
            case .shopping: return "bag"
            case .subscriptions: return "arrow.clockwise"
            case .health: return "heart"
            case .fun: return "ticket"
            case .other, .none: return "ellipsis"
            }
        }
    }
}

extension Decimal {
    /// "−$62.40" — cents kept, for rows.
    var money2: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.minusSign = "−"
        return formatter.string(from: self as NSDecimalNumber) ?? "\(self)"
    }
}
