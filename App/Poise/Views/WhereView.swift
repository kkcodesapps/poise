import SwiftUI
import PoiseKit

/// Where the money went: a period, the strip (the chart is the navigation), and categories ranked. No pie.
struct WhereView: View {
    @Environment(AppModel.self) private var model
    @State private var selectedSlice: Date?

    var body: some View {
        @Bindable var model = model
        return NavigationStack(path: $model.wherePath) {
            ScrollView {
                VStack(spacing: 0) {
                    modeSwitch.padding(.horizontal, Theme.Spacing.s16).padding(.top, Theme.Spacing.s4)
                    if model.whereMode == .prices {
                        PricesList()
                    } else if let b = model.breakdown {
                        PeriodSwitch(period: $model.wherePeriod).padding(.horizontal, Theme.Spacing.s16).padding(.top, Theme.Spacing.s12)
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
        // Always the whole period before: part of a month reading lower than all of last month is the plain, useful
        // comparison — "so far" says the period isn't over.
        let label = Periods.previousLabel(model.wherePeriod), so = model.whereIsCurrent ? "so far · " : ""
        guard b.previousTotal > 0 else { return model.whereIsCurrent ? "so far" : "" }
        if b.delta > 0 { return "\(so)\(b.delta.money) more than \(label)" }
        if b.delta < 0 { return "\(so)\((-b.delta).money) less than \(label)" }
        return "\(so)same as \(label)"
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

    /// Spending or Prices — the tab's two faces.
    private var modeSwitch: some View {
        @Bindable var model = model
        return HStack(spacing: 0) {
            ForEach(AppModel.WhereMode.allCases, id: \.self) { mode in
                let on = model.whereMode == mode
                Button { withAnimation(.snappy) { model.whereMode = mode } } label: {
                    Text(mode.rawValue).font(on ? Theme.Font.subheadStrong : Theme.Font.subhead).foregroundStyle(on ? Theme.Text.primary : Theme.Text.secondary)
                        .frame(maxWidth: .infinity).padding(.vertical, 7)
                        .background(on ? Theme.Bg.elevated : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Theme.Bg.subtle, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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

    /// Six months of a category, for the row's trend line.
    private func trend(_ categoryID: String) -> [Double] {
        guard let h = model.history(categoryID: categoryID) else { return [] }
        return h.months.suffix(6).map { NSDecimalNumber(decimal: $0.total).doubleValue }
    }

    private func rows(_ b: Breakdown) -> some View {
        Card {
            if b.rows.isEmpty { EmptyStateView(symbol: "chart.bar.doc.horizontal", title: "Nothing spent", body: "No charges landed in this period.") }
            ForEach(Array(b.rows.enumerated()), id: \.element.id) { i, r in
                let h = model.history(categoryID: r.categoryID)
                NavigationLink(value: r.categoryID) {
                    CategoryRowView(row: r, previousLabel: Periods.shortPreviousLabel(b.window, model.wherePeriod),
                                    trend: h.map { $0.months.suffix(6).map { NSDecimalNumber(decimal: $0.total).doubleValue } } ?? [],
                                    usual: h?.usual)
                }
                .buttonStyle(.plain)
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
    /// Six months of this category, so the row says where it's heading before you open it.
    var trend: [Double] = []
    var usual: Decimal?
    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: Theme.Spacing.s12) {
                IconCircle(symbol: row.symbol, fill: row.lens == .wants ? Theme.Accent.subtle : Theme.Bg.subtle, color: row.lens == .wants ? Theme.Accent.default : Theme.Text.primary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.name).font(Theme.Font.headline).foregroundStyle(Theme.Text.primary).lineLimit(1).minimumScaleFactor(0.9)
                    Text("\(row.count)× · \(usual.map { "usually \($0.money)" } ?? "\(Int((row.share * 100).rounded()))%")").font(Theme.Font.footnote).foregroundStyle(Theme.Text.secondary).lineLimit(1)
                }
                Spacer(minLength: 8)
                if trend.count > 1 {
                    Sparkline(values: trend, color: trend.last! > trend[trend.count - 2] ? Theme.Status.track : Theme.Status.good).frame(width: 34, height: 14)
                }
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
    /// Just the change. What it's measured against is stated once, in the headline above the list — repeating
    /// "vs Aug 1–24" on every row costs the name and the "usually" line their space.
    private var deltaText: some View {
        Group {
            if let d = row.delta {
                if d > 0 { Text("+\(d.money)").foregroundStyle(Theme.Status.track) }
                else if d < 0 { Text(d.money).foregroundStyle(Theme.Status.good) }
                else { Text("same").foregroundStyle(Theme.Text.tertiary) }
            } else { Text("new").foregroundStyle(Theme.Text.tertiary) }
        }
        .font(Theme.Font.captionStrong)
        .accessibilityLabel(row.delta.map { d in "\(d > 0 ? "up" : d < 0 ? "down" : "same") \(abs(d).money) \(previousLabel)" } ?? "new this period")
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
    @State private var range: CategoryHistory.Range = .year
    /// A month picked from the history chart; nil is the month in progress.
    @State private var pickedMonth: Date?

    private var category: PoiseKit.Category { model.categories.resolve(categoryID) }
    /// The window the page describes: the picked month, else whatever Where has selected.
    private var window: DateInterval {
        guard let m = pickedMonth, let i = Calendar.current.dateInterval(of: .month, for: m) else { return model.whereWindow }
        return i
    }
    private var charges: [PoiseKit.Transaction] { model.transactions.filter { window.holds($0.displayDate) && ($0.kind == .spend || $0.kind == .untracked) && model.categories.resolve($0.categoryID).id == categoryID }.sorted { $0.displayDate > $1.displayDate } }
    private var merchants: [CategoryBreakdown.Merchant] { CategoryBreakdown.merchants(in: categoryID, transactions: model.transactions, window: window, categories: model.categories) }

    var body: some View {
        let row = model.breakdown?.rows.first { $0.categoryID == categoryID }
        let history = model.history(categoryID: categoryID)
        // The month the page is describing: one picked from the chart, else the window Where has selected.
        let picked = pickedMonth.flatMap { m in history?.months.first { Calendar.current.isDate($0.start, equalTo: m, toGranularity: .month) } }
        let total = picked?.total ?? row?.amount ?? 0
        ScrollView {
            VStack(spacing: 0) {
                VStack(spacing: 4) {
                    IconCircle(symbol: category.symbol, size: 56, fill: category.lens == .wants ? Theme.Accent.subtle : Theme.Bg.subtle, color: category.lens == .wants ? Theme.Accent.default : Theme.Text.primary).padding(.bottom, 6)
                    Text(total.money).font(Theme.Font.moneyXL).foregroundStyle(Theme.Text.primary)
                    Text("\(picked.map { $0.start.formatted(.dateTime.month(.wide).year()) } ?? Periods.title(window, model.wherePeriod)) · \(charges.count) charge\(charges.count == 1 ? "" : "s")\(picked == nil ? (row.map { " · \(Int(($0.share * 100).rounded()))% of spending" } ?? "") : "")").font(Theme.Font.subhead).foregroundStyle(Theme.Text.secondary)
                    if let picked, let h = history {
                        // A month that's over is measured against the usual one.
                        let d = (picked.total - h.usual).roundedToCents
                        Text((d > 0 ? "+" : "") + d.money + " vs the usual month")
                            .font(Theme.Font.captionStrong).foregroundStyle(d > 0 ? Theme.Status.track : d < 0 ? Theme.Status.good : Theme.Text.tertiary)
                    } else if let h = history, model.wherePeriod == .month, Calendar.current.isDate(model.whereWindow.start, equalTo: .now, toGranularity: .month) {
                        let d = h.delta
                        Text((d > 0 ? "+" : "") + d.money + (h.comparedToLastYear ? " vs \(h.current.start.formatted(.dateTime.month(.abbreviated))) last year" : " vs the usual month"))
                            .font(Theme.Font.captionStrong).foregroundStyle(d > 0 ? Theme.Status.track : d < 0 ? Theme.Status.good : Theme.Text.tertiary)
                    } else if let d = row?.delta {
                        Text((d > 0 ? "+" : "") + d.money + " vs \(Periods.previousLabel(model.wherePeriod))").font(Theme.Font.captionStrong).foregroundStyle(d > 0 ? Theme.Status.track : d < 0 ? Theme.Status.good : Theme.Text.tertiary)
                    }
                }
                .padding(.top, 8).padding(.bottom, 12)
                if let h = history {
                    CategoryHistoryCard(name: category.name, history: h, range: $range, selected: $pickedMonth).padding(.horizontal, Theme.Spacing.s16)
                    if !h.moves.isEmpty, pickedMonth == nil {
                        SectionHeader(title: "What moved\(h.comparedToLastYear ? " vs \(h.current.start.formatted(.dateTime.month(.abbreviated))) last year" : "") · \(h.moves.count)")
                        Card {
                            ForEach(Array(h.moves.enumerated()), id: \.element.id) { i, m in
                                Button { model.selectedMerchant = .init(key: m.merchantKey) } label: { MoveRow(move: m, symbol: category.symbol, comparedToLastYear: h.comparedToLastYear) }.buttonStyle(.plain)
                                if i < h.moves.count - 1 { RowDivider() }
                            }
                        }
                        .padding(.horizontal, Theme.Spacing.s16)
                    }
                }
                SectionHeader(title: pickedMonth == nil ? "Merchants" : "Merchants in \(window.start.formatted(.dateTime.month(.abbreviated)))")
                Card {
                    ForEach(Array(merchants.prefix(8).enumerated()), id: \.element.id) { i, m in
                        Button { model.selectedMerchant = .init(key: PoiseKit.Transaction.merchantKey(m.name)) } label: {
                        HStack(spacing: Theme.Spacing.s12) {
                            ZStack { Circle().fill(Theme.Bg.subtle); Text("\(i + 1)").font(Theme.Font.captionStrong).foregroundStyle(Theme.Text.secondary) }.frame(width: 28, height: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(m.name.prettyMerchant).font(Theme.Font.headline).foregroundStyle(Theme.Text.primary).lineLimit(1)
                                Text("\(m.count) charge\(m.count == 1 ? "" : "s") · avg \(m.average.money)").font(Theme.Font.footnote).foregroundStyle(Theme.Text.secondary)
                            }
                            Spacer()
                            Text(m.amount.money).font(Theme.Font.moneyMD).foregroundStyle(Theme.Text.primary)
                            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.Text.tertiary)
                        }
                        .padding(.vertical, Theme.Spacing.s12).padding(.horizontal, Theme.Spacing.s16).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if i < min(8, merchants.count) - 1 { RowDivider() }
                    }
                }
                .padding(.horizontal, Theme.Spacing.s16)
                SectionHeader(title: pickedMonth == nil ? "Charges · \(charges.count)" : "Charges in \(window.start.formatted(.dateTime.month(.abbreviated))) · \(charges.count)")
                Card {
                    ForEach(Array(charges.enumerated()), id: \.element.id) { i, t in
                        Button { model.selectedTransaction = t } label: { TransactionRowView(transaction: t, account: model.accounts.first { $0.id == t.accountID }) }.buttonStyle(.plain)
                        if i < charges.count - 1 { RowDivider() }
                    }
                }
                .padding(.horizontal, Theme.Spacing.s16)
                if history != nil {
                    SectionHeader(title: "Manage")
                    Card {
                        ToggleRow(label: "Tell me when \(category.name) costs more than usual",
                                  isOn: Binding(get: { model.watchesCategory(categoryID) }, set: { on in Task { await model.setCategoryWatch(on, categoryID: categoryID) } }))
                    }
                    .padding(.horizontal, Theme.Spacing.s16)
                    Text("A heads-up when a month runs a quarter over what \(category.name) usually costs — the same rule Prices uses for a thing you buy.")
                        .font(Theme.Font.caption).foregroundStyle(Theme.Text.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, Theme.Spacing.s16).padding(.top, Theme.Spacing.s8)
                }
            }
            .padding(.bottom, Theme.Spacing.s32)
        }
        .background(Theme.Bg.base)
        .navigationTitle(category.name)
        .navigationBarTitleDisplayMode(.inline)
        #if DEBUG
        // `-range 2y|all` opens the history on that span; `-pick-month N` opens it N months back (screenshots, checks).
        .onAppear {
            let a = ProcessInfo.processInfo.arguments
            if let i = a.firstIndex(of: "-range"), i + 1 < a.count {
                range = a[i + 1] == "all" ? .all : a[i + 1] == "2y" ? .twoYears : .year
            }
            if let i = a.firstIndex(of: "-pick-month"), i + 1 < a.count, let back = Int(a[i + 1]),
               let h = model.history(categoryID: categoryID), h.months.count > back {
                pickedMonth = h.months[h.months.count - 1 - back].start
            }
        }
        #endif
    }
}


/// A category's run of months: a bar each, the usual line across them, and what the shape means in words.
struct CategoryHistoryCard: View {
    let name: String
    let history: CategoryHistory
    @Binding var range: CategoryHistory.Range
    /// Which month the page is showing. Nil means the one in progress, which is what the card opens on.
    @Binding var selected: Date?

    private var months: [CategoryHistory.Month] { history.months(in: range) }
    private var shownMonth: CategoryHistory.Month? {
        selected.flatMap { d in months.first { Calendar.current.isDate($0.start, equalTo: d, toGranularity: .month) } } ?? months.last
    }

    var body: some View {
        let shown = months
        let peak = shown.map(\.total).max() ?? 1
        let cal = Calendar.current
        return VStack(alignment: .leading, spacing: Theme.Spacing.s12) {
            HStack(alignment: .firstTextBaseline) {
                Text(title.uppercased()).font(Theme.Font.caption2Strong).foregroundStyle(Theme.Text.tertiary)
                Spacer(minLength: 8)
                Text("usually \(history.usual.money) a month").font(Theme.Font.caption).foregroundStyle(Theme.Text.tertiary)
            }
            if history.ranges.count > 1 {
                HStack(spacing: 6) {
                    ForEach(history.ranges, id: \.self) { r in
                        Button { withAnimation(.snappy) { range = r } } label: {
                            Text(label(for: r)).font(Theme.Font.captionStrong).foregroundStyle(range == r ? Theme.Accent.default : Theme.Text.secondary)
                                .padding(.horizontal, 10).padding(.vertical, 4)
                                .background(range == r ? Theme.Accent.subtle : Theme.Bg.subtle, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            GeometryReader { geo in
                let labelW: CGFloat = 34, top: CGFloat = 8, base = geo.size.height - 22
                let plotW = geo.size.width - labelW
                let gap: CGFloat = shown.count > 18 ? 2 : shown.count > 12 ? 3 : 6
                let bw = max(2, (plotW - gap * CGFloat(shown.count - 1)) / CGFloat(shown.count))
                let usualY = base - (base - top) * CGFloat(truncating: (peak > 0 ? history.usual / peak : 0) as NSDecimalNumber)
                ZStack(alignment: .topLeading) {
                    // the usual line, and the years behind the bars when there's more than one
                    Path { p in p.move(to: CGPoint(x: labelW, y: usualY)); p.addLine(to: CGPoint(x: geo.size.width, y: usualY)) }
                        .stroke(style: StrokeStyle(lineWidth: 1, dash: [3, 3])).foregroundStyle(Theme.Border.default)
                    Text("usual").font(Theme.Font.caption2).foregroundStyle(Theme.Text.tertiary).position(x: 14, y: usualY)
                    ForEach(Array(shown.enumerated()), id: \.element.id) { i, m in
                        let h = max(2, (base - top) * CGFloat(truncating: (peak > 0 ? m.total / peak : 0) as NSDecimalNumber))
                        let current = i == shown.count - 1
                        let picked = cal.isDate(m.start, equalTo: shownMonth?.start ?? .distantPast, toGranularity: .month)
                        let x = labelW + CGFloat(i) * (bw + gap) + bw / 2
                        RoundedRectangle(cornerRadius: min(3, bw / 2))
                            .fill(picked ? Theme.Accent.default : current ? Theme.Accent.default.opacity(0.45) : cal.isDate(m.start, equalTo: history.lastYear?.start ?? .distantPast, toGranularity: .month) ? Theme.Status.track : Theme.Border.strong)
                            .frame(width: bw, height: h)
                            .position(x: x, y: base - h / 2)
                    }
                    ForEach(marks(shown, width: bw, gap: gap, labelW: labelW), id: \.0) { x, text in
                        Text(text).font(Theme.Font.caption2).foregroundStyle(Theme.Text.tertiary).position(x: x, y: base + 12)
                    }
                }
                // One gesture over the whole chart, picking the nearest month: a 2pt bar is nobody's idea of a target.
                .contentShape(Rectangle())
                .onTapGesture { point in
                    let i = Int(((point.x - labelW) / max(bw + gap, 1)).rounded(.down))
                    guard shown.indices.contains(min(max(i, 0), shown.count - 1)) else { return }
                    let month = shown[min(max(i, 0), shown.count - 1)]
                    withAnimation(.snappy) {
                        let already = cal.isDate(month.start, equalTo: shownMonth?.start ?? .distantPast, toGranularity: .month)
                        selected = already && selected != nil ? nil : month.start
                    }
                }
            }
            .frame(height: 124)
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s8) {
                Text(read).font(Theme.Font.footnote).foregroundStyle(Theme.Text.secondary)
                Spacer(minLength: 0)
                if selected != nil {
                    Button("This month") { withAnimation(.snappy) { selected = nil } }
                        .font(Theme.Font.captionStrong).foregroundStyle(Theme.Accent.default).fixedSize()
                }
            }
        }
        .padding(Theme.Spacing.s16)
        .background(Theme.Bg.elevated, in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous).strokeBorder(Theme.Border.subtle))
    }

    /// Names the span actually drawn, so the card never says "a month" over twelve bars.
    private var title: String {
        let n = months.count
        if n > 24 { return "\(spelled((n + 11) / 12)) years of \(name)" }
        if n > 12 { return "Two years of \(name)" }
        if n > 1 { return "\(spelled(n)) months of \(name)" }
        return "A month of \(name)"
    }
    private func spelled(_ n: Int) -> String {
        ["", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven", "twelve"].indices.contains(n) ? ["", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven", "twelve"][n] : "\(n)"
    }
    private func label(for r: CategoryHistory.Range) -> String {
        switch r {
        case .year: "12m"
        case .twoYears: "2y"
        case .all: history.years >= 2 ? "All · \(history.years + 1)y" : "All"
        }
    }
    /// Month names when the run is short, year names when it's long.
    private func marks(_ shown: [CategoryHistory.Month], width: CGFloat, gap: CGFloat, labelW: CGFloat) -> [(CGFloat, String)] {
        let cal = Calendar.current
        let x = { (i: Int) in labelW + CGFloat(i) * (width + gap) + width / 2 }
        if shown.count <= 13 {
            let step = shown.count > 9 ? 2 : 1
            return shown.enumerated().filter { $0.offset % step == 0 }.map { (x($0.offset), $0.element.start.formatted(.dateTime.month(.narrow))) }
        }
        var out: [(CGFloat, String)] = []
        var year: Int?
        for (i, m) in shown.enumerated() {
            let y = cal.component(.year, from: m.start)
            guard y != year else { continue }
            year = y
            let at = x(i) + width
            // A year that starts a couple of bars in would print on top of the one before it.
            if let last = out.last, at - last.0 < 34 { continue }
            out.append((at, String(y)))
        }
        return out
    }
    /// The shape in a sentence: how the month on show sits against the thing worth comparing it to.
    private var read: String {
        guard let month = shownMonth else { return "" }
        let isCurrent = Calendar.current.isDate(month.start, equalTo: history.current.start, toGranularity: .month)
        if !isCurrent {
            let benchmark = history.usual
            let when = month.start.formatted(.dateTime.month(.wide).year())
            guard month.count > 0 else { return "Nothing in \(when)." }
            let diff = (month.total - benchmark).roundedToCents
            let how = abs(Double(truncating: (benchmark > 0 ? diff / benchmark : 0) as NSDecimalNumber)) < 0.15 ? "about usual"
                : diff > 0 ? "\(diff.money) more than usual" : "\((-diff).money) less than usual"
            return "\(when) · \(month.total.money) across \(month.count) charge\(month.count == 1 ? "" : "s") — \(how)."
        }
        let current = history.current.total, benchmark = history.lastYear?.total ?? history.usual
        guard benchmark > 0 else { return "\(current.money) so far — the first month Poise has seen for \(name)." }
        let ratio = Double(truncating: (current / benchmark) as NSDecimalNumber)
        let against = history.comparedToLastYear ? "than the same month last year" : "than a usual month"
        if ratio >= 1.8 { return "\(String(format: "%.0f", ratio))× a usual month — \(current.money) against \(benchmark.money) \(history.comparedToLastYear ? "last year" : "usually")." }
        if ratio >= 1.25 { return "\(((current - benchmark)).money) more \(against) — \(current.money) against \(benchmark.money)." }
        if ratio <= 0.75 { return "\(((benchmark - current)).money) less \(against) — \(current.money) against \(benchmark.money)." }
        return "About usual for \(name) — \(current.money) against \(benchmark.money) \(history.comparedToLastYear ? "last year" : "in a usual month")."
    }
}

/// One merchant that moved, with what it was before.
struct MoveRow: View {
    let move: CategoryHistory.Move
    let symbol: String
    let comparedToLastYear: Bool
    var body: some View {
        HStack(spacing: Theme.Spacing.s12) {
            IconCircle(symbol: symbol, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(move.name.prettyMerchant).font(Theme.Font.headline).foregroundStyle(Theme.Text.primary).lineLimit(1)
                Text(sub).font(Theme.Font.footnote).foregroundStyle(Theme.Text.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(move.amount.money).font(Theme.Font.moneyMD).foregroundStyle(Theme.Text.primary)
                Text("\(move.delta > 0 ? "▲" : "▼") \(abs(move.delta).money)").font(Theme.Font.captionStrong).foregroundStyle(move.delta > 0 ? Theme.Status.track : Theme.Status.good)
            }
        }
        .padding(.vertical, Theme.Spacing.s12).padding(.horizontal, Theme.Spacing.s16).contentShape(Rectangle())
    }
    private var sub: String {
        if move.amount == 0 { return "nothing this month · was \((move.was ?? 0).money)" }
        let charges = "\(move.count) charge\(move.count == 1 ? "" : "s")"
        if move.isNew { return "\(charges) · new \(comparedToLastYear ? "since last year" : "this month")" }
        guard let wasCount = move.wasCount else { return charges }
        return "\(charges) · \(wasCount) \(comparedToLastYear ? "last year" : "in a usual month")"
    }
}

private func abs(_ d: Decimal) -> Decimal { d < 0 ? -d : d }
