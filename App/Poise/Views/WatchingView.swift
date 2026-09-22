import SwiftUI
import PoiseKit

/// One list for everything watched: refunds (waiting / overdue), merchant alerts, then resolved history.
struct WatchingView: View {
    @Environment(AppModel.self) private var model

    private var refunds: [Watch] { model.watches.filter { $0.kind == .refund && $0.status.isOpen } }
    private var merchants: [Watch] { model.watches.filter { $0.kind == .merchant && $0.status.isOpen } }
    private var resolved: [Watch] { model.watches.filter { !$0.status.isOpen }.sorted { ($0.resolvedAt ?? .distantPast) > ($1.resolvedAt ?? .distantPast) } }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                if model.watches.isEmpty {
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
        Card {
            ForEach(Array(ws.enumerated()), id: \.element.id) { i, w in
                WatchRowView(watch: w)
                    .contextMenu {
                        if w.status.isOpen { Button("Stop watching", systemImage: "eye.slash") { Task { await model.closeWatch(w) } } }
                        Button("Remove", systemImage: "trash", role: .destructive) { Task { await model.removeWatch(w) } }
                    }
                if i < ws.count - 1 { RowDivider() }
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
        }
    }
    private var right: String {
        switch watch.status {
        case .triggered: return model.transactions.first { $0.id == watch.resolvedTransactionID }?.magnitude.money2 ?? ""
        case .watching: return "no charges"
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

/// Compact card on Home — only when something is being watched.
struct WatchingCard: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        let open = model.openWatches
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
