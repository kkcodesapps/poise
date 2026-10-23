import SwiftUI
import PoiseKit

/// One list for everything watched: refunds (waiting / overdue), merchant alerts, then resolved history.
struct WatchingView: View {
    @Environment(AppModel.self) private var model

    private var refunds: [Watch] { model.watches.filter { $0.kind == .refund && $0.status.isOpen } }
    private var merchants: [Watch] { model.watches.filter { $0.kind == .merchant && $0.status.isOpen } }
    private var resolved: [Watch] { model.watches.filter { !$0.status.isOpen && $0.kind != .price }.sorted { ($0.resolvedAt ?? .distantPast) > ($1.resolvedAt ?? .distantPast) } }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                if model.watches.allSatisfy({ $0.kind == .price }) {
                    EmptyStateView(symbol: "bookmark", title: "Nothing watched yet", body: "Long-press any charge, or open it and use Watch: wait for a refund, or be told if a merchant charges you again.")
                } else {
                    if !refunds.isEmpty {
                        SectionHeader(title: "Waiting on refunds · \(model.owedBack.money2)")
                        list(refunds)
                    }
                    if !merchants.isEmpty {
                        SectionHeader(title: "Merchant alerts")
                        list(merchants)
                    }
                    if !resolved.isEmpty {
                        SectionHeader(title: "Resolved", action: "Clear") { Task { for w in resolved { await model.removeWatch(w) } } }
                        list(resolved)
                    }
                    Text("Overdue nudges after each watch's own window. A merchant alert stays on until you turn it off.").font(Theme.Font.caption).foregroundStyle(Theme.Text.tertiary).multilineTextAlignment(.center).padding(Theme.Spacing.s16)
                }
            }
            .padding(.bottom, Theme.Spacing.s32)
        }
        .background(Theme.Bg.base)
        .navigationTitle("Watching")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func list(_ ws: [Watch]) -> some View {
        // A refund you're owed deserves the whole story — what it was, what was charged, how long it's been. Merchant
        // and price watches are a single fact each and stay compact.
        VStack(spacing: Theme.Spacing.s12) {
            ForEach(ws) { w in
                if w.kind == .refund, w.status.isOpen {
                    RefundWatchCard(watch: w)
                        .contextMenu {
                            Button("Stop watching", systemImage: "eye.slash") { Task { await model.closeWatch(w) } }
                            Button("Remove", systemImage: "trash", role: .destructive) { Task { await model.removeWatch(w) } }
                        }
                } else {
                    Card { WatchRowView(watch: w) }
                        .contextMenu {
                            if w.status.isOpen { Button("Stop watching", systemImage: "eye.slash") { Task { await model.closeWatch(w) } } }
                            Button("Remove", systemImage: "trash", role: .destructive) { Task { await model.removeWatch(w) } }
                        }
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.s16)
    }
}

struct WatchRowView: View {
    @Environment(AppModel.self) private var model
    let watch: Watch

    private var since: Date { watch.transactionID.flatMap { id in model.transactions.first { $0.id == id }?.displayDate } ?? watch.createdAt }
    private var days: Int { Calendar.current.dateComponents([.day], from: since, to: watch.resolvedAt ?? .now).day ?? 0 }
    private var style: (symbol: String, bg: Color, fg: Color, pill: String) {
        switch watch.status {
        case .waiting: ("arrow.uturn.backward", Theme.Accent.subtle, Theme.Accent.default, "WAITING")
        case .overdue: ("arrow.uturn.backward", Theme.Status.trackBg, Theme.Status.track, "OVERDUE")
        case .arrived: ("checkmark", Theme.Status.goodBg, Theme.Status.good, "ARRIVED")
        case .watching: ("eye", Theme.Bg.subtle, Theme.Text.primary, "WATCHING")
        case .triggered: ("eye", Theme.Status.headsBg, Theme.Status.heads, "CHARGED AGAIN")
        case .closed: ("xmark", Theme.Bg.subtle, Theme.Text.tertiary, "CLOSED")
        }
    }
    private var sub: String {
        let d = { (x: Date) in x.formatted(.dateTime.month(.abbreviated).day()) }
        switch (watch.kind, watch.status) {
        case (.refund, .arrived): return "Refund arrived \(d(watch.resolvedAt ?? .now)) · \((watch.expectedAmount ?? 0).money2)"
        case (.refund, _): return "Waiting for a refund · \((watch.expectedAmount ?? 0).money2) · since \(d(since))"
        case (.merchant, .triggered): return "Charged again \(d(watch.resolvedAt ?? .now))"
        case (.merchant, _): return "Tell me if they charge again · since \(d(watch.createdAt))"
        case (.price, _): return "Tell me when the price moves · since \(d(watch.createdAt))"
        }
    }
    private var right: String {
        switch watch.status {
        case .triggered: return model.transactions.first { $0.id == watch.resolvedTransactionID }?.magnitude.money2 ?? ""
        case .watching: return watch.kind == .price ? (model.priceItem(id: watch.matcher).map { "usually \($0.usual.money2)" } ?? "") : "no charges"
        case .closed: return ""
        default: return "\(days) day\(days == 1 ? "" : "s")"
        }
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.s12) {
            IconCircle(symbol: style.symbol, fill: style.bg, color: style.fg)
            VStack(alignment: .leading, spacing: 2) {
                Text(watch.merchant.prettyMerchant).font(Theme.Font.headline).foregroundStyle(Theme.Text.primary).lineLimit(1)
                Text(sub).font(Theme.Font.footnote).foregroundStyle(Theme.Text.secondary).lineLimit(1)
                if let n = watch.note, !n.isEmpty { Text(n).font(Theme.Font.caption).foregroundStyle(Theme.Text.tertiary).lineLimit(1) }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                Text(style.pill).font(Theme.Font.caption2Strong).foregroundStyle(style.fg).padding(.horizontal, 8).padding(.vertical, 3).background(style.bg, in: Capsule())
                Text(right).font(Theme.Font.caption).foregroundStyle(Theme.Text.tertiary)
            }
        }
        .padding(.vertical, Theme.Spacing.s12).padding(.horizontal, Theme.Spacing.s16)
        .contentShape(Rectangle())
    }
}

/// A refund you're owed, with everything needed to decide whether to chase it.
struct RefundWatchCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    let watch: Watch

    private var charge: PoiseKit.Transaction? { watch.transactionID.flatMap { id in model.transactions.first { $0.id == id } } }
    private var since: Date { charge?.displayDate ?? watch.createdAt }
    private var days: Int { Calendar.current.dateComponents([.day], from: since, to: .now).day ?? 0 }
    private var progress: (status: String, note: String?)? { model.returnProgress(for: watch) }
    /// The merchant says it's in hand, so it isn't late however long it's been.
    private var late: Bool { watch.status == .overdue && !model.returnUnderWay(watch) }

    var body: some View {
        Card(padding: Theme.Spacing.s16) {
            VStack(alignment: .leading, spacing: Theme.Spacing.s12) {
                HStack(spacing: Theme.Spacing.s12) {
                    IconCircle(symbol: "arrow.uturn.backward", size: 36,
                               fill: late ? Theme.Status.trackBg : Theme.Accent.subtle,
                               color: late ? Theme.Status.track : Theme.Accent.default)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(watch.merchant.prettyMerchant).font(Theme.Font.headline).foregroundStyle(Theme.Text.primary).lineLimit(1)
                        Text(what).font(Theme.Font.footnote).foregroundStyle(Theme.Text.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Tag(label: late ? "Overdue" : "Waiting", tone: late ? .track : .accent)
                }
                Divider().overlay(Theme.Border.subtle)
                fact("Charged", chargeLine, tone: Theme.Text.secondary)
                fact("Waiting", waitLine, tone: late ? Theme.Status.track : Theme.Text.secondary)
                if let progress {
                    // Amazon's own words, so a refund in hand doesn't read like one gone quiet.
                    VStack(alignment: .leading, spacing: 2) {
                        Text(progress.status).font(Theme.Font.captionStrong).foregroundStyle(Theme.Status.good)
                        if let note = progress.note {
                            Text(note).font(Theme.Font.caption).foregroundStyle(Theme.Text.tertiary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack(spacing: Theme.Spacing.s8) {
                    Button("It arrived") { Task { await model.markWatchArrived(watch) } }.buttonStyle(.secondaryCompact)
                    if let ref = charge?.orderRef {
                        Button("See the order") { openURL(AmazonOrders.url(for: ref)) }.buttonStyle(.ghost)
                    }
                }
            }
        }
    }

    private func fact(_ label: String, _ value: String, tone: Color) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(Theme.Font.caption).foregroundStyle(Theme.Text.tertiary)
            Spacer(minLength: 8)
            Text(value).font(Theme.Font.captionStrong).foregroundStyle(tone).multilineTextAlignment(.trailing)
        }
    }

    /// What the money was for: the thing itself when Poise knows it, the category when it doesn't.
    private var what: String {
        guard let charge else { return watch.note ?? "Waiting for a refund" }
        return model.contents(of: charge) ?? model.categories.name(charge.categoryID)
    }

    private var chargeLine: String {
        guard let charge else { return (watch.expectedAmount ?? 0).money2 }
        let account = model.accounts.first { $0.id == charge.accountID }
        let card = account.map { a in a.mask.map { "\(a.name) ···\($0)" } ?? a.name } ?? ""
        return "\(charge.magnitude.money2) · \(charge.displayDate.formatted(.dateTime.month(.abbreviated).day()))\(card.isEmpty ? "" : " · \(card)")"
    }

    private var waitLine: String {
        let age = days == 0 ? "Since today" : "\(days) day\(days == 1 ? "" : "s")"
        return "\(age) · expected within \(watch.nudgeDays)"
    }
}

/// Compact card on Home — only when something is being watched.
struct WatchingCard: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        let open = model.openWatches.filter { $0.kind != .price }
        Button { model.showWatching = true } label: {
            VStack(spacing: 0) {
                HStack {
                    HStack(spacing: 8) {
                        Image(systemName: "bookmark").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.Accent.default)
                        Text("WATCHING · \(open.count)").font(Theme.Font.captionStrong).foregroundStyle(Theme.Text.tertiary)
                    }
                    Spacer()
                    if model.owedBack > 0 { Text("\(model.owedBack.money) owed back").font(Theme.Font.captionStrong).foregroundStyle(Theme.Accent.default) }
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.Text.tertiary)
                }
                .padding(.top, 12).padding(.bottom, 6).padding(.horizontal, Theme.Spacing.s16)
                ForEach(Array(open.prefix(3).enumerated()), id: \.element.id) { i, w in
                    HStack(spacing: 12) {
                        HStack(spacing: 6) {
                            Text(w.merchant.prettyMerchant).font(Theme.Font.subheadStrong).foregroundStyle(Theme.Text.primary).lineLimit(1)
                            Text("· " + line(w)).font(Theme.Font.subhead).foregroundStyle(w.status == .overdue ? Theme.Status.track : Theme.Text.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        Text(w.kind == .refund ? (w.expectedAmount ?? 0).money2 : "no charges").font(Theme.Font.moneySM).foregroundStyle(w.status == .overdue ? Theme.Status.track : w.kind == .refund ? Theme.Text.primary : Theme.Text.tertiary)
                    }
                    .padding(.horizontal, Theme.Spacing.s16).padding(.top, 8).padding(.bottom, i == min(2, open.count - 1) ? 14 : 8)
                }
            }
            .background(Theme.Bg.elevated, in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous).strokeBorder(Theme.Border.subtle))
        }
        .buttonStyle(.plain)
    }
    private func line(_ w: Watch) -> String {
        let since = w.transactionID.flatMap { id in model.transactions.first { $0.id == id }?.displayDate } ?? w.createdAt
        let days = Calendar.current.dateComponents([.day], from: since, to: .now).day ?? 0
        switch w.status {
        case .waiting: return "refund · \(days) day\(days == 1 ? "" : "s")"
        case .overdue: return "refund · \(days) days · overdue"
        default: return "tell me if they charge again"
        }
    }
}
