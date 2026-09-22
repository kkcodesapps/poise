import SwiftUI
import PoiseKit

/// Where the money went: a period, the strip (the chart is the navigation), and categories ranked. No pie.
struct WhereView: View {
    @Environment(AppModel.self) private var model
    @State private var selectedSlice: Date?

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    if let b = model.breakdown {
                        PeriodSwitch(period: $model.wherePeriod).padding(.horizontal, Theme.Spacing.s16).padding(.top, Theme.Spacing.s4)
                        stepper(b)
                        headline(b)
                        lens(b)
                        strip(b)
                        if let sel = selectedSlice, let s = b.slices.first(where: { $0.id == sel }) { SliceCard(slice: s, accounts: model.accounts) { selectedSlice = nil } onSelect: { model.selectedTransaction = $0 }.padding(.horizontal, Theme.Spacing.s16).padding(.top, Theme.Spacing.s12) }
                        rows(b)
                    } else {
                        EmptyStateView(symbol: "chart.bar.doc.horizontal", title: "Where shows up here", body: "Link a bank and Poise will break spending down by category — by week, month or year.")
                    }
                }
                .padding(.bottom, Theme.Spacing.s32)
            }
            .background(Theme.Bg.base)
            .navigationTitle("Where")
            .navigationDestination(for: String.self) { id in CategoryDetailView(categoryID: id) }
            .onChange(of: model.wherePeriod) { _, _ in selectedSlice = nil }
            .onChange(of: model.whereWindow) { _, _ in selectedSlice = nil }
        }
    }

    private func stepper(_ b: Breakdown) -> some View {
        HStack {
            Button { model.stepWhere(-1) } label: { IconCircle(symbol: "chevron.left", size: 36, fill: Theme.Bg.subtle, color: Theme.Text.primary) }.buttonStyle(.plain)
            Spacer()
            VStack(spacing: 1) {
                Text(Periods.title(b.window, model.wherePeriod)).font(Theme.Font.titleSM).foregroundStyle(Theme.Text.primary)
                Text(vsLine(b)).font(Theme.Font.caption).foregroundStyle(Theme.Text.tertiary)
            }
            Spacer()
            Button { model.stepWhere(1) } label: { IconCircle(symbol: "chevron.right", size: 36, fill: Theme.Bg.subtle, color: model.whereIsCurrent ? Theme.Text.tertiary : Theme.Text.primary) }
                .buttonStyle(.plain).disabled(model.whereIsCurrent)
        }
        .padding(.horizontal, Theme.Spacing.s16).padding(.vertical, 4)
    }

    private func vsLine(_ b: Breakdown) -> String {
        let label = Periods.previousLabel(model.wherePeriod)
        guard b.previousTotal > 0 else { return model.whereIsCurrent ? "so far" : "" }
        if b.delta > 0 { return "vs \(label) · \(b.delta.money) more" }
        if b.delta < 0 { return "vs \(label) · \((-b.delta).money) less" }
        return "vs \(label) · same"
    }

    private func headline(_ b: Breakdown) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(b.total.money) spent").font(Theme.Font.titleLG).foregroundStyle(Theme.Text.primary)
            Text(summary(b)).font(Theme.Font.verdictMD).foregroundStyle(Theme.Text.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.Spacing.s16).padding(.top, 4).padding(.bottom, Theme.Spacing.s12)
    }

    private func summary(_ b: Breakdown) -> String {
        guard let top = b.rows.first else { return "Nothing spent in this period." }
        var s = "Across \(b.rows.count) categor\(b.rows.count == 1 ? "y" : "ies"). \(top.name) is \(Int((top.share * 100).rounded()))%"
        if let mover = b.rows.filter({ ($0.delta ?? 0) > 0 }).max(by: { $0.delta! < $1.delta! }), mover.delta! > 0 {
            s += mover.categoryID == top.categoryID ? " and the one that moved." : "; \(mover.name) is the one that moved."
        } else { s += "." }
        return s
    }

    private func lens(_ b: Breakdown) -> some View {
        let total = max(b.needs + b.wants, 1)
        let needs = NSDecimalNumber(decimal: b.needs / total).doubleValue
        return VStack(spacing: 8) {
            GeometryReader { geo in
                HStack(spacing: 3) {
                    RoundedRectangle(cornerRadius: 4).fill(Theme.Text.tertiary).frame(width: max(4, geo.size.width * needs))
                    RoundedRectangle(cornerRadius: 4).fill(Theme.Accent.default).frame(maxWidth: .infinity)
                }
            }
            .frame(height: 8)
            HStack {
                legend("Needs", value: needs, color: Theme.Text.tertiary); Spacer(); legend("Wants", value: 1 - needs, color: Theme.Accent.default)
            }
        }
        .padding(.horizontal, Theme.Spacing.s16).padding(.bottom, Theme.Spacing.s12)
    }

    private func legend(_ label: String, value: Double, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).font(Theme.Font.caption).foregroundStyle(Theme.Text.secondary)
            Text(value.percent).font(Theme.Font.moneyXS).foregroundStyle(Theme.Text.primary)
        }
    }

    private func strip(_ b: Breakdown) -> some View {
        let maxAmt = b.slices.map { NSDecimalNumber(decimal: max(0, $0.amount)).doubleValue }.max() ?? 1
        let selected = selectedSlice.flatMap { id in b.slices.first { $0.id == id } }
        return Card(padding: Theme.Spacing.s12) {
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(b.slices) { s in
                    let v = NSDecimalNumber(decimal: max(0, s.amount)).doubleValue
                    let on = selectedSlice == s.id
                    let future = s.slice.interval.start > .now
                    Button { withAnimation(.snappy) { selectedSlice = on ? nil : s.id } } label: {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(on ? Theme.Accent.default : future ? Theme.Bg.subtle : Theme.Border.strong)
                            .frame(maxWidth: .infinity).frame(height: max(4, 56 * v / max(maxAmt, 1)))
                            .frame(height: 56, alignment: .bottom).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).disabled(future || s.transactions.isEmpty)
                }
            }
            HStack(spacing: 6) {
                ForEach(b.slices) { s in
                    Text(s.slice.label).font(Theme.Font.caption).foregroundStyle(selectedSlice == s.id ? Theme.Accent.default : Theme.Text.tertiary)
                        .frame(maxWidth: .infinity).lineLimit(1).minimumScaleFactor(0.7)
                }
            }
            .padding(.top, 6)
            Text(selected.map { "\($0.slice.longLabel) · \($0.amount.money)" } ?? "Tap a \(model.wherePeriod == .week ? "day" : model.wherePeriod == .month ? "week" : "month") to see its charges")
                .font(Theme.Font.caption).foregroundStyle(selected == nil ? Theme.Text.tertiary : Theme.Text.primary)
                .frame(maxWidth: .infinity).padding(.top, 8)
        }
        .padding(.horizontal, Theme.Spacing.s16)
    }

    private func rows(_ b: Breakdown) -> some View {
        Card {
            if b.rows.isEmpty { EmptyStateView(symbol: "chart.bar.doc.horizontal", title: "Nothing spent", body: "No charges landed in this period.") }
            ForEach(Array(b.rows.enumerated()), id: \.element.id) { i, r in
                NavigationLink(value: r.categoryID) { CategoryRowView(row: r, previousLabel: Periods.shortPreviousLabel(b.window, model.wherePeriod)) }.buttonStyle(.plain)
                if i < b.rows.count - 1 { RowDivider() }
            }
        }
        .padding(.horizontal, Theme.Spacing.s16).padding(.top, Theme.Spacing.s12)
    }
}

struct PeriodSwitch: View {
    @Binding var period: Period
    var body: some View {
        HStack(spacing: 2) {
            ForEach(Period.allCases, id: \.self) { p in
                let on = p == period
                Button { withAnimation(.snappy) { period = p } } label: {
                    Text(p.title).font(Theme.Font.subheadStrong).foregroundStyle(on ? Theme.Text.primary : Theme.Text.secondary)
                        .frame(maxWidth: .infinity, minHeight: 30)
                        .background(on ? Theme.Bg.elevated : .clear, in: RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))
                        .shadow(color: on ? .black.opacity(0.12) : .clear, radius: 4, y: 1)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Theme.Bg.subtle, in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
    }
}

struct CategoryRowView: View {
    let row: Breakdown.Row
    let previousLabel: String
    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: Theme.Spacing.s12) {
                IconCircle(symbol: row.symbol, fill: row.lens == .wants ? Theme.Accent.subtle : Theme.Bg.subtle, color: row.lens == .wants ? Theme.Accent.default : Theme.Text.primary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.name).font(Theme.Font.headline).foregroundStyle(Theme.Text.primary)
                    Text("\(row.count) charge\(row.count == 1 ? "" : "s") · \(Int((row.share * 100).rounded()))%").font(Theme.Font.footnote).foregroundStyle(Theme.Text.secondary).lineLimit(1)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(row.amount.money).font(Theme.Font.moneyMD).foregroundStyle(Theme.Text.primary)
                    deltaText.lineLimit(1)
                }
                .fixedSize()
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.Text.tertiary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.Border.subtle)
                    Capsule().fill(row.lens == .wants ? Theme.Accent.default : Theme.Text.tertiary).frame(width: max(6, geo.size.width * row.share))
                }
            }
            .frame(height: 6)
        }
        .padding(.vertical, Theme.Spacing.s12).padding(.horizontal, Theme.Spacing.s16)
        .contentShape(Rectangle())
    }
    private var deltaText: some View {
        Group {
            if let d = row.delta {
                if d > 0 { Text("+\(d.money) vs \(previousLabel)").foregroundStyle(Theme.Status.track) }
                else if d < 0 { Text("\(d.money) vs \(previousLabel)").foregroundStyle(Theme.Status.good) }
                else { Text("same \(previousLabel)").foregroundStyle(Theme.Text.tertiary) }
            } else { Text("new").foregroundStyle(Theme.Text.tertiary) }
        }
        .font(Theme.Font.captionStrong)
    }
}

/// The selected bar's charges, right under the strip.
struct SliceCard: View {
    let slice: Breakdown.SliceTotal
    let accounts: [Account]
    var onClose: () -> Void
    var onSelect: (PoiseKit.Transaction) -> Void
    @State private var showAll = false
    var body: some View {
        let rows = showAll ? slice.transactions : Array(slice.transactions.prefix(3))
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(slice.slice.longLabel).font(Theme.Font.subheadStrong).foregroundStyle(Theme.Text.primary)
                    Text("\(slice.amount.money) spent · \(slice.transactions.count) charge\(slice.transactions.count == 1 ? "" : "s")").font(Theme.Font.footnote).foregroundStyle(Theme.Text.secondary)
                }
                Spacer()
                Button(action: onClose) { IconCircle(symbol: "xmark", size: 28, fill: Theme.Bg.subtle, color: Theme.Text.primary) }.buttonStyle(.plain)
            }
            .padding(.vertical, Theme.Spacing.s12).padding(.horizontal, Theme.Spacing.s16)
            Divider().overlay(Theme.Border.subtle)
            ForEach(Array(rows.enumerated()), id: \.element.id) { i, t in
                Button { onSelect(t) } label: { TransactionRowView(transaction: t, account: accounts.first { $0.id == t.accountID }) }.buttonStyle(.plain)
                if i < rows.count - 1 { RowDivider() }
            }
            if slice.transactions.count > 3 {
                Divider().overlay(Theme.Border.subtle)
                Button(showAll ? "Show fewer" : "See all \(slice.transactions.count) charges") { withAnimation { showAll.toggle() } }
                    .font(Theme.Font.footnote.weight(.semibold)).tint(Theme.Accent.default).frame(maxWidth: .infinity, minHeight: 44)
            }
        }
        .background(Theme.Bg.elevated, in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous).strokeBorder(Theme.Accent.default))
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}

/// One category for the same period: merchants ranked, then every charge.
struct CategoryDetailView: View {
    @Environment(AppModel.self) private var model
    let categoryID: String

    private var category: PoiseKit.Category { model.categories.resolve(categoryID) }
    private var window: DateInterval { model.whereWindow }
    private var charges: [PoiseKit.Transaction] { model.transactions.filter { window.contains($0.displayDate) && ($0.kind == .spend || $0.kind == .untracked) && model.categories.resolve($0.categoryID).id == categoryID }.sorted { $0.displayDate > $1.displayDate } }
    private var merchants: [CategoryBreakdown.Merchant] { CategoryBreakdown.merchants(in: categoryID, transactions: model.transactions, window: window, categories: model.categories) }

    var body: some View {
        let row = model.breakdown?.rows.first { $0.categoryID == categoryID }
        ScrollView {
            VStack(spacing: 0) {
                VStack(spacing: 4) {
                    IconCircle(symbol: category.symbol, size: 56, fill: category.lens == .wants ? Theme.Accent.subtle : Theme.Bg.subtle, color: category.lens == .wants ? Theme.Accent.default : Theme.Text.primary).padding(.bottom, 6)
                    Text((row?.amount ?? 0).money).font(Theme.Font.moneyXL).foregroundStyle(Theme.Text.primary)
                    Text("\(Periods.title(window, model.wherePeriod)) · \(charges.count) charge\(charges.count == 1 ? "" : "s")\(row.map { " · \(Int(($0.share * 100).rounded()))% of spending" } ?? "")").font(Theme.Font.subhead).foregroundStyle(Theme.Text.secondary)
                    if let d = row?.delta { Text((d > 0 ? "+" : "") + d.money + " vs \(Periods.previousLabel(model.wherePeriod))").font(Theme.Font.captionStrong).foregroundStyle(d > 0 ? Theme.Status.track : d < 0 ? Theme.Status.good : Theme.Text.tertiary) }
                }
                .padding(.top, 8).padding(.bottom, 12)
                SectionHeader(title: "Merchants")
                Card {
                    ForEach(Array(merchants.prefix(8).enumerated()), id: \.element.id) { i, m in
                        HStack(spacing: Theme.Spacing.s12) {
                            ZStack { Circle().fill(Theme.Bg.subtle); Text("\(i + 1)").font(Theme.Font.captionStrong).foregroundStyle(Theme.Text.secondary) }.frame(width: 28, height: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(m.name.prettyMerchant).font(Theme.Font.headline).foregroundStyle(Theme.Text.primary).lineLimit(1)
                                Text("\(m.count) charge\(m.count == 1 ? "" : "s") · avg \(m.average.money)").font(Theme.Font.footnote).foregroundStyle(Theme.Text.secondary)
                            }
                            Spacer()
                            Text(m.amount.money).font(Theme.Font.moneyMD).foregroundStyle(Theme.Text.primary)
                        }
                        .padding(.vertical, Theme.Spacing.s12).padding(.horizontal, Theme.Spacing.s16)
                        if i < min(8, merchants.count) - 1 { RowDivider() }
                    }
                }
                .padding(.horizontal, Theme.Spacing.s16)
                SectionHeader(title: "Charges")
                Card {
                    ForEach(Array(charges.enumerated()), id: \.element.id) { i, t in
                        Button { model.selectedTransaction = t } label: { TransactionRowView(transaction: t, account: model.accounts.first { $0.id == t.accountID }) }.buttonStyle(.plain)
                        if i < charges.count - 1 { RowDivider() }
                    }
                }
                .padding(.horizontal, Theme.Spacing.s16)
            }
            .padding(.bottom, Theme.Spacing.s32)
        }
        .background(Theme.Bg.base)
        .navigationTitle(category.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
