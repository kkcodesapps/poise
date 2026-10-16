import SwiftUI
import PoiseKit

/// What you pay for the things you buy again — the Where tab's second mode. Tracked first, then what moved lately,
/// then everything A–Z. A row opens the item.
struct PricesList: View {
    @Environment(AppModel.self) private var model
    @State private var filter = "all"
    @State private var query = ""
    @State private var selected: AppModel.PriceItemRef?

    private var tracked: [PriceItem] { model.priceItems.filter { $0.tracked && passes($0) }.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending } }
    private var moved: [PriceItem] { model.pricesMovedLately.filter { !$0.tracked && passes($0) } }
    private var rest: [PriceItem] { model.pricesRest.filter { !$0.tracked && passes($0) } }
    private func passes(_ i: PriceItem) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces)
        if !q.isEmpty, !i.displayName.localizedCaseInsensitiveContains(q), !i.merchant.prettyMerchant.localizedCaseInsensitiveContains(q) { return false }
        switch filter {
        case "tracked": return i.tracked
        case "up": return i.direction == .up
        case "down": return i.direction == .down
        case "plans": return i.source == .plan
        default: return true
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.Text.tertiary)
                TextField("Anything you buy again", text: $query).font(Theme.Font.body).foregroundStyle(Theme.Text.primary).autocorrectionDisabled()
                if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.Text.tertiary) }.buttonStyle(.plain) }
            }
            .padding(.horizontal, 12).frame(height: 40).background(Theme.Bg.inset, in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
            .padding(.horizontal, Theme.Spacing.s16).padding(.top, Theme.Spacing.s12)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach([("all", "All · \(model.priceItems.count)"), ("tracked", "Tracked · \(model.priceItems.filter(\.tracked).count)"), ("up", "Up"), ("down", "Down"), ("plans", "Plans")], id: \.0) { key, label in
                        Chip(label: label, symbol: key == "up" ? "arrow.up.right" : key == "down" ? "arrow.down.right" : key == "tracked" ? "eye" : key == "plans" ? "arrow.clockwise" : "line.3.horizontal.decrease", on: filter == key) { withAnimation(.snappy) { filter = key } }
                    }
                }
                .padding(.horizontal, Theme.Spacing.s16)
            }
            .padding(.top, Theme.Spacing.s12)
            if tracked.isEmpty, moved.isEmpty, rest.isEmpty {
                Card { EmptyStateView(symbol: "chart.line.uptrend.xyaxis", title: filter == "all" && query.isEmpty ? "Nothing to compare yet" : "Nothing here", body: filter == "all" && query.isEmpty ? "Poise needs two purchases of the same thing. Name a charge to follow one item from a store that sells everything." : "Try another filter or search.") }
                    .padding(.horizontal, Theme.Spacing.s16).padding(.top, Theme.Spacing.s16)
            }
            if !tracked.isEmpty {
                SectionHeader(title: "Tracked · \(tracked.count)")
                list(tracked)
            }
            if !moved.isEmpty {
                SectionHeader(title: "Moved lately")
                list(moved)
            }
            if !rest.isEmpty {
                SectionHeader(title: "Everything · \(rest.count)")
                list(rest)
            }
            Text("Everything you’ve bought twice or more. Things that cost about the same get a usual price and a heads-up when it moves; things that vary — groceries, gas, usage — show their range. Name a charge to follow one thing from a store that sells everything.")
                .font(Theme.Font.caption).foregroundStyle(Theme.Text.tertiary).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, Theme.Spacing.s16).padding(.top, Theme.Spacing.s12)
        }
        .sheet(item: $selected) { ref in PriceItemView(itemID: ref.id) }
        .onAppear { if model.pricesFilter != "all" { filter = model.pricesFilter; model.pricesFilter = "all" } }
        .onChange(of: model.pricesFilter) { _, f in if f != "all" { filter = f; model.pricesFilter = "all" } }
    }

    private func list(_ items: [PriceItem]) -> some View {
        Card {
            ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                Button { selected = .init(id: item.id) } label: { PriceItemRow(item: item) }.buttonStyle(.plain)
                if i < items.count - 1 { RowDivider() }
            }
        }
        .padding(.horizontal, Theme.Spacing.s16)
    }
}

/// One item in the list: what it is, how often, the usual price, a sparkline, and the last price with its move.
struct PriceItemRow: View {
    @Environment(AppModel.self) private var model
    let item: PriceItem

    var body: some View {
        HStack(spacing: 10) {
            MerchantCircle(logoURL: item.logoURL, symbol: model.categories.symbol(item.categoryID), size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName).font(Theme.Font.headline).foregroundStyle(Theme.Text.primary).lineLimit(1)
                Text(item.subtitle).font(Theme.Font.footnote).foregroundStyle(Theme.Text.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            Sparkline(values: item.purchases.suffix(8).map { NSDecimalNumber(decimal: $0.price).doubleValue }, color: item.tone).frame(width: 28, height: 12)
            VStack(alignment: .trailing, spacing: 2) {
                Text(item.last.money2).font(Theme.Font.moneyMD).foregroundStyle(Theme.Text.primary)
                Text(item.deltaLabel).font(Theme.Font.captionStrong).foregroundStyle(item.tone)
            }
        }
        .padding(.vertical, Theme.Spacing.s12).padding(.horizontal, Theme.Spacing.s16).contentShape(Rectangle())
    }
}

extension PriceItem {
    var displayName: String { (source == .named ? name : name.prettyMerchant) + (planSuffix.map { " · \($0)" } ?? "") }
    var tone: Color { direction == .up ? Theme.Status.track : direction == .down ? Theme.Status.good : Theme.Text.tertiary }
    /// "▲ $5.00 · 17%", "▼ $6.30 · 12%", "steady", or "varies" for a run with no usual price.
    var deltaLabel: String {
        switch direction {
        case .steady: return steady ? "steady" : "varies"
        case .up: return "▲ \(delta.money2) · \(Int((deltaPercent * 100).rounded()))%"
        case .down: return "▼ \((-delta).money2) · \(Int((-deltaPercent * 100).rounded()))%"
        }
    }
    /// "Amazon · 7× · usually $29.99", "Monthly · usually $200.00", "14× · $92 – $392 per visit", "9× · $63 – $100 · pay-as-you-go".
    var subtitle: String {
        let lead = source == .named ? "\(merchant.prettyMerchant) · " : ""
        if source == .plan { return "\(lead)Plan · usually \(usual.money2)" }
        if steady { return "\(lead)\(count)× · usually \(usual.money2)" }
        return "\(lead)\(count)× · \(lowest.money) – \(highest.money)\(planSuffix == "usage" ? " · pay-as-you-go" : " per visit")"
    }
}

/// A tiny line of the last few prices.
struct Sparkline: View {
    let values: [Double]
    var color: Color = Theme.Text.tertiary
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let lo = values.min() ?? 0, hi = values.max() ?? 1
            Path { p in
                for (i, v) in values.enumerated() {
                    let x = values.count > 1 ? w * CGFloat(i) / CGFloat(values.count - 1) : w / 2
                    let y = hi > lo ? h - h * CGFloat((v - lo) / (hi - lo)) : h / 2
                    if i == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
                }
            }
            .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
    }
}

/// One item: last / usual / lowest, the run of prices, what changed, every purchase, and the switches.
struct PriceItemView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let itemID: String
    @State private var selected: PoiseKit.Transaction?
    @State private var renaming = false
    @State private var newName = ""
    @State private var filing = false

    private var item: PriceItem? { model.priceItem(id: itemID) }
    private var sample: PoiseKit.Transaction? { item?.purchases.last.flatMap { p in model.transactions.first { $0.id == p.id } } }

    var body: some View {
        NavigationStack {
            ScrollView {
                if let item, let sample {
                    VStack(spacing: 0) {
                        VStack(spacing: 4) {
                            MerchantCircle(logoURL: item.logoURL, symbol: model.categories.symbol(item.categoryID), size: 64)
                            Text(item.displayName).font(Theme.Font.titleMD).foregroundStyle(Theme.Text.primary).multilineTextAlignment(.center).padding(.top, 4)
                            Text("\(model.categories.resolve(item.categoryID).name)\(item.source == .named ? " · \(item.merchant.prettyMerchant)" : "") · \(item.count) purchase\(item.count == 1 ? "" : "s") since \(item.firstSeen.formatted(.dateTime.month(.abbreviated).year()))")
                                .font(Theme.Font.subhead).foregroundStyle(Theme.Text.secondary).multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity).padding(.top, Theme.Spacing.s12).padding(.bottom, Theme.Spacing.s12).padding(.horizontal, Theme.Spacing.s16)
                        HStack(spacing: 8) {
                            tile("LAST", item.last.money2)
                            tile(item.steady ? "USUALLY" : "RANGE", item.steady ? item.usual.money2 : "\(item.lowest.money) – \(item.highest.money)")
                            tile(item.steady ? "LOWEST" : "AVERAGE", item.steady ? item.lowest.money2 : item.average.money2)
                        }
                        .padding(.horizontal, Theme.Spacing.s16)
                        PriceChart(item: item).padding(.horizontal, Theme.Spacing.s16).padding(.top, Theme.Spacing.s12)
                        if item.direction != .steady { callout(item).padding(.top, Theme.Spacing.s12) }

                        SectionHeader(title: "Purchases · \(item.count)")
                        Card {
                            let rows = item.purchases.reversed().compactMap { p in model.transactions.first { $0.id == p.id } }
                            ForEach(Array(rows.enumerated()), id: \.element.id) { i, t in
                                Button { selected = t } label: { TransactionRowView(transaction: t, account: model.accounts.first { $0.id == t.accountID }, showsDate: true) }.buttonStyle(.plain)
                                if i < rows.count - 1 { RowDivider() }
                            }
                        }
                        .padding(.horizontal, Theme.Spacing.s16)

                        SectionHeader(title: "Manage")
                        Card {
                            NavRow(symbol: "pencil", label: "Call it", value: item.displayName) { newName = item.source == .named ? item.name : (sample.displayName ?? ""); renaming = true }
                            RowDivider()
                            NavRow(symbol: "tag", label: "File under", value: model.categories.resolve(item.categoryID).name) { filing = true }
                            RowDivider()
                            ToggleRow(label: "Tell me when the price moves", isOn: Binding(get: { item.tracked }, set: { on in Task { await model.setPriceTracking(on, item: item) } }))
                        }
                        .padding(.horizontal, Theme.Spacing.s16)
                        Text(item.tracked ? "The next purchase at a different price becomes a heads-up the moment it lands."
                             : item.source == .named ? "Poise groups every charge you’ve named “\(item.name)”. Name the next one the same way and it joins the run."
                             : item.source == .plan ? "The plan’s own charges — what \(item.merchant.prettyMerchant) bills on schedule. Anything else from them is usage."
                             : item.steady ? "Every charge from \(item.merchant.prettyMerchant) counts as one thing because they cost about the same."
                             : "What you paid \(item.merchant.prettyMerchant) each time. Prices vary, so there’s no usual — the range and the average are the story.")
                            .font(Theme.Font.caption).foregroundStyle(Theme.Text.tertiary)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, Theme.Spacing.s16).padding(.top, Theme.Spacing.s8)
                    }
                    .padding(.bottom, Theme.Spacing.s32)
                } else {
                    EmptyStateView(symbol: "chart.line.uptrend.xyaxis", title: "Nothing here", body: "This item has no purchases in the feed any more.").padding(.top, 80)
                }
            }
            .background(Theme.Bg.base)
            .navigationTitle(item?.displayName ?? "Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() }.tint(Theme.Accent.default) } }
            .sheet(item: $selected) { t in TransactionDetailView(transaction: t) }
            .sheet(isPresented: $filing) { if let sample { FileUnderSheet(sample: sample) } }
            .alert("Call it", isPresented: $renaming) {
                TextField(item?.displayName ?? "Name", text: $newName)
                Button("Save") { if let item { Task { await model.renameItem(item, to: newName) } } }
                Button("Cancel", role: .cancel) {}
            } message: { Text(item?.source == .named ? "Every purchase in this run takes the new name." : "Every charge from \(item?.merchant.prettyMerchant ?? "this merchant") will read this way.") }
        }
    }

    private func tile(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(Theme.Font.caption2Strong).foregroundStyle(Theme.Text.tertiary)
            Text(value).font(Theme.Font.moneyMD).foregroundStyle(Theme.Text.primary)
        }
        .padding(Theme.Spacing.s12).frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Bg.elevated, in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous).strokeBorder(Theme.Border.subtle))
    }

    /// "Up $5.00 since July" — what changed, in one breath, and what to do about it.
    private func callout(_ item: PriceItem) -> some View {
        let up = item.direction == .up
        let since = item.changedAt.map { " since \($0.formatted(.dateTime.month(.wide)))" } ?? ""
        let pct = Int((abs(item.deltaPercent) * 100).rounded())
        let held = item.purchases.reversed().prefix { $0.price == item.last }.count
        let body = "\(item.usual.money2) → \(item.last.money2)" + (held > 1 ? ", and it’s stayed there \(held == 2 ? "twice" : "\(held) times")." : ".")
            + (up ? " That’s \(pct)% more for the same thing — worth a look at other sellers before the next one." : " That’s \(pct)% less than usual — a good time to stock up.")
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: up ? "arrow.up.right" : "arrow.down.right").font(.system(size: 15, weight: .semibold)).foregroundStyle(up ? Theme.Status.track : Theme.Status.good).padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text("\(up ? "Up" : "Down") \(abs(item.delta).money2)\(since)").font(Theme.Font.subheadStrong).foregroundStyle(Theme.Text.primary)
                Text(body).font(Theme.Font.footnote).foregroundStyle(Theme.Text.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.s16)
        .background(up ? Theme.Status.trackBg : Theme.Status.goodBg, in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
        .padding(.horizontal, Theme.Spacing.s16)
    }
}

/// The run of prices over time: gridlines with the $ scale on the left, an area under the line, a dot per purchase,
/// the lowest one in green with its price, the latest ringed with its price, months along the bottom.
struct PriceChart: View {
    let item: PriceItem

    var body: some View {
        let points = item.purchases
        let prices = points.map { NSDecimalNumber(decimal: $0.price).doubleValue }
        let lo = (prices.min() ?? 0), hi = (prices.max() ?? 1)
        let pad = max(1, (hi - lo) * 0.35)
        let yMin = max(0, floor(lo - pad)), yMax = ceil(hi + pad)
        let start = points.first?.date ?? .now, end = points.last?.date ?? .now
        let span = max(end.timeIntervalSince(start), 86_400 * 30)
        return VStack(alignment: .leading, spacing: Theme.Spacing.s12) {
            HStack {
                Text("PRICE PAID").font(Theme.Font.caption2Strong).foregroundStyle(Theme.Text.tertiary)
                Spacer()
                Text("\(start.formatted(.dateTime.month(.abbreviated)))\(Calendar.current.isDate(start, equalTo: end, toGranularity: .month) ? "" : " – \(end.formatted(.dateTime.month(.abbreviated)))") · \(item.count) purchase\(item.count == 1 ? "" : "s")").font(Theme.Font.caption).foregroundStyle(Theme.Text.tertiary)
            }
            GeometryReader { geo in
                let labelW: CGFloat = 34, top: CGFloat = 14, bottom = geo.size.height - 20
                let plotW = geo.size.width - labelW
                let x: (Date) -> CGFloat = { d in labelW + 8 + CGFloat(d.timeIntervalSince(start) / span) * (plotW - 16) }
                let y: (Double) -> CGFloat = { p in top + CGFloat((yMax - p) / max(yMax - yMin, 1)) * (bottom - top) }
                let ticks = [yMax, (yMax + yMin) / 2, yMin]
                ZStack(alignment: .topLeading) {
                    ForEach(ticks, id: \.self) { t in
                        Path { p in p.move(to: CGPoint(x: labelW, y: y(t))); p.addLine(to: CGPoint(x: geo.size.width, y: y(t))) }.stroke(Theme.Border.subtle, lineWidth: 1)
                        Text(Decimal(t).money).font(Theme.Font.caption2).foregroundStyle(Theme.Text.tertiary).position(x: 14, y: y(t))
                    }
                    if points.count > 1 {
                        Path { p in
                            p.move(to: CGPoint(x: x(points[0].date), y: bottom))
                            for pt in points { p.addLine(to: CGPoint(x: x(pt.date), y: y(NSDecimalNumber(decimal: pt.price).doubleValue))) }
                            p.addLine(to: CGPoint(x: x(points.last!.date), y: bottom)); p.closeSubpath()
                        }
                        .fill(Theme.Accent.subtle)
                        Path { p in
                            for (i, pt) in points.enumerated() { let c = CGPoint(x: x(pt.date), y: y(NSDecimalNumber(decimal: pt.price).doubleValue)); if i == 0 { p.move(to: c) } else { p.addLine(to: c) } }
                        }
                        .stroke(Theme.Accent.default, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    }
                    let lowIndex = points.firstIndex { $0.price == item.lowest }
                    ForEach(Array(points.enumerated()), id: \.element.id) { i, pt in
                        let last = i == points.count - 1, low = i == lowIndex && !last
                        let c = CGPoint(x: x(pt.date), y: y(NSDecimalNumber(decimal: pt.price).doubleValue))
                        Circle().fill(low ? Theme.Status.good : Theme.Accent.default)
                            .overlay(Circle().strokeBorder(Theme.Bg.elevated, lineWidth: last ? 2 : 0))
                            .frame(width: last ? 10 : 6, height: last ? 10 : 6).position(c)
                        if last { Text(pt.price.money2).font(Theme.Font.captionStrong).foregroundStyle(Theme.Text.primary).position(x: min(c.x, geo.size.width - 22), y: c.y - 14) }
                        else if low { Text(pt.price.money2).font(Theme.Font.captionStrong).foregroundStyle(Theme.Status.good).position(x: c.x, y: c.y + 14) }
                    }
                    let months = monthMarks(from: start, to: end)
                    ForEach(months, id: \.self) { m in
                        Text(m.formatted(.dateTime.month(.abbreviated))).font(Theme.Font.caption2).foregroundStyle(Theme.Text.tertiary).position(x: x(m), y: geo.size.height - 6)
                    }
                }
            }
            .frame(height: 140)
        }
        .padding(Theme.Spacing.s16)
        .background(Theme.Bg.elevated, in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous).strokeBorder(Theme.Border.subtle))
    }

    /// The first of each month across the run, thinned so labels don't collide (at most eight).
    private func monthMarks(from: Date, to: Date) -> [Date] {
        let cal = Calendar.current
        var out: [Date] = []
        var d = cal.date(from: cal.dateComponents([.year, .month], from: from)) ?? from
        if d < from {
            // The run starts mid-month: label that month at the first purchase unless the next mark is right on top of it.
            let next = cal.date(byAdding: .month, value: 1, to: d) ?? d
            if (cal.dateComponents([.day], from: from, to: next).day ?? 0) >= 20 { out.append(from) }
            d = next
        }
        while d <= to { out.append(d); d = cal.date(byAdding: .month, value: 1, to: d) ?? to.addingTimeInterval(1) }
        let step = max(1, Int(ceil(Double(out.count) / 8)))
        return out.enumerated().filter { $0.offset % step == 0 }.map(\.element)
    }
}
