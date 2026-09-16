import SwiftUI
import PoiseKit

/// A cash-flow calendar with nothing to configure: bills and income per day, the balance after each, the crunch called out.
struct Next14View: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    if !model.hasLinkedBank || model.cashflow.isEmpty {
                        EmptyStateView(symbol: "calendar", title: "The next two weeks show up here", body: "Link a bank and Poise will lay out what's due against what you have.")
                    } else {
                        if let crunch = model.insights.first(where: { $0.kind == .crunch }) {
                            Card { InsightRowView(insight: crunch, showChevron: false) }
                                .background(Theme.Status.headsBg, in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
                                .padding(.horizontal, Theme.Spacing.s16).padding(.top, Theme.Spacing.s4)
                        } else if let first = model.cashflow.first {
                            Card { InsightRowView(insight: Insight(id: "clear", kind: .positive, tone: .good, title: "Every bill clears through \(model.cashflow.last!.date.formatted(.dateTime.month(.abbreviated).day()))",
                                                                   body: "Lowest point \(model.cashflow.map(\.balanceAfter).min()!.money), starting from \(first.balanceAfter.money) today.", rank: 0), showChevron: false) }
                                .padding(.horizontal, Theme.Spacing.s16).padding(.top, Theme.Spacing.s4)
                        }
                        bars.padding(.top, Theme.Spacing.s12)
                        Card {
                            ForEach(Array(model.cashflow.enumerated()), id: \.element.id) { i, day in
                                dayRow(day)
                                if i < model.cashflow.count - 1 { RowDivider() }
                            }
                        }
                        .padding(.horizontal, Theme.Spacing.s16).padding(.top, Theme.Spacing.s12)
                    }
                }
                .padding(.bottom, Theme.Spacing.s32)
            }
            .background(Theme.Bg.base)
            .navigationTitle("Next 14 days")
        }
    }

    private var bars: some View {
        let maxAbs = model.cashflow.map { abs(NSDecimalNumber(decimal: $0.balanceAfter).doubleValue) }.max() ?? 1
        return Card(padding: Theme.Spacing.s16) {
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(model.cashflow) { day in
                    let v = NSDecimalNumber(decimal: day.balanceAfter).doubleValue
                    RoundedRectangle(cornerRadius: 3)
                        .fill(day.isCrunch ? Theme.Status.heads : day.isToday ? Theme.Accent.default : Theme.Border.strong)
                        .frame(maxWidth: .infinity).frame(height: max(6, 64 * abs(v) / max(maxAbs, 1)))
                }
            }
            .frame(height: 72, alignment: .bottom)
            HStack {
                Text("Today").font(Theme.Font.caption).foregroundStyle(Theme.Text.tertiary)
                Spacer()
                if let c = model.cashflow.first(where: \.isCrunch) { Text(c.date.formatted(.dateTime.month(.abbreviated).day())).font(Theme.Font.caption).foregroundStyle(Theme.Status.heads); Spacer() }
                if let pay = model.cashflow.first(where: \.hasIncome) { Text("Payday · \(pay.date.formatted(.dateTime.month(.abbreviated).day()))").font(Theme.Font.caption).foregroundStyle(Theme.Text.tertiary) }
                else { Text(model.cashflow.last!.date.formatted(.dateTime.month(.abbreviated).day())).font(Theme.Font.caption).foregroundStyle(Theme.Text.tertiary) }
            }
            .padding(.top, Theme.Spacing.s8)
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
                    Text("\(line.name) · \(line.amount > 0 ? "+" : "")\(line.amount.money2)").font(Theme.Font.footnote).foregroundStyle(line.amount > 0 ? Theme.Money.in : Theme.Text.secondary).lineLimit(1)
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
        .background(day.isCrunch ? Theme.Status.headsBg : .clear)
    }
}
