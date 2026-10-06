import SwiftUI
import PoiseKit

/// A cash-flow calendar with nothing to configure: bills and income per day, the balance after each, the crunch called out.
struct Next14View: View {
    @Environment(AppModel.self) private var model
    /// A tapped bar: its row lights up and the caption under the chart says what happens that day.
    @State private var selectedDay: Date?

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    if !model.looksLinked || model.cashflow.isEmpty {
                        EmptyStateView(symbol: "calendar", title: "The next two weeks show up here", body: "Link a bank and Poise will lay out what's due against what you have.")
                    } else {
                        // The headline comes from the same fourteen days as the chart and the list, so they never disagree.
                        if let short = model.cashflow.first(where: \.isCrunch) {
                            let day = short.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
                            let low = model.cashflow.map(\.balanceAfter).min() ?? short.balanceAfter
                            Card { InsightRowView(insight: Insight(id: "short", kind: .crunch, tone: .heads, title: "Checking runs short on \(day)",
                                                                   body: "Move \((-low).money) from savings before then and every bill clears.", rank: 1), showChevron: false) }
                                .background(Theme.Status.headsBg, in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
                                .padding(.horizontal, Theme.Spacing.s16).padding(.top, Theme.Spacing.s4)
                        } else if let statement = model.insights.first(where: { $0.kind == .statement }) {
                            // A card statement that outweighs everything else in the window gets the top spot.
                            Card { InsightRowView(insight: statement, showChevron: false) }
                                .background(statement.tone == .heads ? Theme.Status.headsBg : Theme.Accent.subtle, in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
                                .padding(.horizontal, Theme.Spacing.s16).padding(.top, Theme.Spacing.s4)
                        } else if let first = model.cashflow.first {
                            Card { InsightRowView(insight: Insight(id: "clear", kind: .positive, tone: .good, title: "Every bill clears through \(model.cashflow.last!.date.formatted(.dateTime.month(.abbreviated).day()))",
                                                                   body: "Lowest point \(model.cashflow.map(\.balanceAfter).min()!.money), starting from \(first.balanceAfter.money) today.", rank: 0), showChevron: false) }
                                .padding(.horizontal, Theme.Spacing.s16).padding(.top, Theme.Spacing.s4)
                        }
                        bars.padding(.top, Theme.Spacing.s12)
                        Card {
                            ForEach(Array(model.cashflow.enumerated()), id: \.element.id) { i, day in
                                dayRow(day).id(day.id)
                                if i < model.cashflow.count - 1 { RowDivider() }
                            }
                        }
                        .padding(.horizontal, Theme.Spacing.s16).padding(.top, Theme.Spacing.s12)
                    }
                }
                .padding(.bottom, Theme.Spacing.s32)
            }
            .onChange(of: selectedDay) { _, day in if let day { withAnimation(.snappy) { proxy.scrollTo(day, anchor: .center) } } }
            .background(Theme.Bg.base)
            .navigationTitle("Next 14 days")
            }
        }
    }

    /// The balance after each day. The bars follow the balance's movement, not its size — the lowest day in the window
    /// sits near the floor and the highest fills the card — so a $60 bill still shows against a $5,000 balance.
    /// Today is blue, a short day is a red stub, payday is green, everything else grey.
    private var bars: some View {
        let values = model.cashflow.map { NSDecimalNumber(decimal: $0.balanceAfter).doubleValue }
        let positives = values.filter { $0 >= 0 }
        let hi = positives.max() ?? 0, lo = positives.min() ?? 0
        func height(_ v: Double) -> CGFloat {
            guard v >= 0 else { return 6 }
            guard hi - lo > 0.5 else { return 40 }
            return 14 + 50 * (v - lo) / (hi - lo)
        }
        let selected = selectedDay.flatMap { d in model.cashflow.first { $0.id == d } }
        return Card(padding: Theme.Spacing.s16) {
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(model.cashflow) { day in
                    let on = selectedDay == day.id
                    Button { withAnimation(.snappy) { selectedDay = on ? nil : day.id } } label: {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(day.isCrunch ? Theme.Status.heads : day.isToday ? Theme.Accent.default : day.hasIncome ? Theme.Money.in : Theme.Border.strong)
                            .opacity(selectedDay == nil || on ? 1 : 0.45)
                            .frame(maxWidth: .infinity).frame(height: height(NSDecimalNumber(decimal: day.balanceAfter).doubleValue))
                            .frame(height: 72, alignment: .bottom).contentShape(Rectangle())   // the whole column is the tap target
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(height: 72, alignment: .bottom)
            if let selected {
                // "Thu, Oct 2 · Moda Homes −$4,110.00, Lemonade −$210.66 · after $7,915"
                let names = selected.lines.filter(\.movesCash).map { "\($0.name) \($0.amount > 0 ? "+" : "")\($0.amount.money2)" }
                let cardOnly = selected.lines.filter { !$0.movesCash }.count
                Text("\(selected.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())) · "
                     + (names.isEmpty ? (cardOnly > 0 ? "\(cardOnly) on cards, nothing from checking" : "nothing due") : names.joined(separator: ", "))
                     + " · \(selected.isCrunch ? "short by \((-selected.balanceAfter).money)" : "after \(selected.balanceAfter.money)")")
                    .font(Theme.Font.caption).foregroundStyle(selected.isCrunch ? Theme.Status.heads : Theme.Text.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.top, Theme.Spacing.s8)
            } else {
                HStack {
                    Text("Today").font(Theme.Font.caption).foregroundStyle(Theme.Text.tertiary)
                    Spacer()
                    if let c = model.cashflow.first(where: \.isCrunch) { Text("Short · \(c.date.formatted(.dateTime.month(.abbreviated).day()))").font(Theme.Font.caption).foregroundStyle(Theme.Status.heads); Spacer() }
                    if let pay = model.cashflow.first(where: \.hasIncome) { Text("Payday · \(pay.date.formatted(.dateTime.month(.abbreviated).day()))").font(Theme.Font.caption).foregroundStyle(Theme.Money.in) }
                    else { Text(model.cashflow.last!.date.formatted(.dateTime.month(.abbreviated).day())).font(Theme.Font.caption).foregroundStyle(Theme.Text.tertiary) }
                }
                .padding(.top, Theme.Spacing.s8)
            }
        }
        .padding(.horizontal, Theme.Spacing.s16)
    }

    private func dayRow(_ day: CashflowDay) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.s12) {
            VStack(spacing: 0) {
                Text(day.isToday ? "TODAY" : day.date.formatted(.dateTime.weekday(.abbreviated)).uppercased()).font(Theme.Font.caption2Strong).foregroundStyle(day.isToday ? Theme.Accent.default : Theme.Text.tertiary)
                Text(day.date.formatted(.dateTime.day())).font(Theme.Font.titleSM).foregroundStyle(day.isToday ? Theme.Accent.default : day.isCrunch ? Theme.Status.heads : Theme.Text.primary)
            }
            .frame(width: 44)
            VStack(alignment: .leading, spacing: 2) {
                if day.lines.isEmpty { Text("Nothing due").font(Theme.Font.footnote).foregroundStyle(Theme.Text.tertiary) }
                ForEach(Array(day.lines.enumerated()), id: \.offset) { _, line in
                    // A card's charge names the card and stays grey: it's the statement that leaves checking.
                    Text("\(line.name) · \(line.amount > 0 ? "+" : "")\(line.amount.money2)" + (line.viaCard.map { " · \($0)" } ?? ""))
                        .font(Theme.Font.footnote).foregroundStyle(line.viaCard != nil ? Theme.Text.tertiary : line.amount > 0 ? Theme.Money.in : Theme.Text.secondary).lineLimit(1)
                }
            }
            .padding(.top, 3)
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(day.isCrunch ? "SHORT BY" : "AFTER").font(Theme.Font.caption).foregroundStyle(day.isCrunch ? Theme.Status.heads : Theme.Text.tertiary)
                Text(day.isCrunch ? (-day.balanceAfter).money : day.balanceAfter.money).font(Theme.Font.moneySM).foregroundStyle(day.isCrunch ? Theme.Status.heads : day.hasIncome ? Theme.Money.in : Theme.Text.primary)
            }
            .padding(.top, 3)
        }
        .padding(.vertical, 10).padding(.horizontal, Theme.Spacing.s16)
        .background(selectedDay == day.id ? Theme.Accent.subtle : day.isCrunch ? Theme.Status.headsBg : .clear)
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.snappy) { selectedDay = selectedDay == day.id ? nil : day.id } }
    }
}
