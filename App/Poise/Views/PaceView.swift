import SwiftUI
import Charts
import PoiseKit

/// Not a pie chart. One line: this month against last, projected to month-end. Then what moved it.
struct PaceView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    if let pace = model.pace, model.hasLinkedBank {
                        headline(pace)
                        chartCard(pace)
                        SectionHeader(title: "What moved")
                        movers(pace)
                        SectionHeader(title: "Needs · wants · kept")
                        lens(pace)
                    } else {
                        EmptyStateView(symbol: "chart.line.uptrend.xyaxis", title: "Pace shows up here", body: "Link a bank and Poise will project this month against last.")
                    }
                }
                .padding(.bottom, Theme.Spacing.s32)
            }
            .background(Theme.Bg.base)
            .navigationTitle("Pace")
        }
    }

    private func headline(_ p: Pace) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(Date.now.formatted(.dateTime.month(.wide)).uppercased()) · DAY \(p.dayOfMonth) OF \(p.daysInMonth)").font(Theme.Font.captionStrong).foregroundStyle(Theme.Text.tertiary)
            Text("On pace for \(p.projected.money)").font(Theme.Font.titleLG).foregroundStyle(Theme.Text.primary)
            Text(summary(p)).font(Theme.Font.verdictMD).foregroundStyle(Theme.Text.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.Spacing.s16).padding(.top, Theme.Spacing.s4).padding(.bottom, Theme.Spacing.s16)
    }

    private func summary(_ p: Pace) -> String {
        let last = Calendar.current.date(byAdding: .month, value: -1, to: .now)!.formatted(.dateTime.month(.wide))
        guard p.lastMonthTotal > 0 else { return "First full month on Poise — next month you'll see this against \(last)." }
        let diff = p.overLastMonth
        if diff > 0 { return "\(diff.money) over \(last)\(p.topMover.map { ", mostly \($0.category.title)" } ?? "")." }
        if diff < 0 { return "\((-diff).money) under \(last). Keep the rhythm." }
        return "Right on \(last)'s pace."
    }

    private func chartCard(_ p: Pace) -> some View {
        Card(padding: Theme.Spacing.s16) {
            Chart {
                ForEach(p.cumulative, id: \.day) { pt in
                    if let l = pt.lastMonth {
                        LineMark(x: .value("Day", pt.day), y: .value("Last month", max(0, NSDecimalNumber(decimal: l).doubleValue)), series: .value("Series", "Last month"))
                            .foregroundStyle(Theme.Text.tertiary).lineStyle(StrokeStyle(lineWidth: 2)).interpolationMethod(.monotone)
                    }
                    if let t = pt.thisMonth {
                        LineMark(x: .value("Day", pt.day), y: .value("This month", max(0, NSDecimalNumber(decimal: t).doubleValue)), series: .value("Series", "This month"))
                            .foregroundStyle(Theme.Accent.default).lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round)).interpolationMethod(.monotone)
                    }
                }
                let projected = NSDecimalNumber(decimal: p.projected).doubleValue
                let today = max(0, NSDecimalNumber(decimal: p.spendSoFar).doubleValue)
                LineMark(x: .value("Day", p.dayOfMonth), y: .value("Projected", today), series: .value("Series", "Projected")).foregroundStyle(Theme.Accent.default).lineStyle(StrokeStyle(lineWidth: 2, dash: [4, 5]))
                LineMark(x: .value("Day", p.daysInMonth), y: .value("Projected", projected), series: .value("Series", "Projected")).foregroundStyle(Theme.Accent.default).lineStyle(StrokeStyle(lineWidth: 2, dash: [4, 5]))
                PointMark(x: .value("Day", p.dayOfMonth), y: .value("Today", today)).foregroundStyle(Theme.Accent.default).symbolSize(60)
                    .annotation(position: .top, alignment: .center) { Text("today").font(Theme.Font.caption2Strong).foregroundStyle(Theme.Accent.default) }
            }
            .chartXScale(domain: 1...p.daysInMonth)
            .chartYScale(domain: 0...max(NSDecimalNumber(decimal: max(p.projected, p.lastMonthTotal)).doubleValue * 1.1, 100))
            .chartXAxis { AxisMarks(values: [1, 8, 15, 22, p.daysInMonth]) { v in AxisValueLabel { if let d = v.as(Int.self) { Text("\(d)").font(Theme.Font.caption).foregroundStyle(Theme.Text.tertiary) } } } }
            .chartYAxis { AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { v in
                AxisGridLine().foregroundStyle(Theme.Border.subtle)
                AxisValueLabel { if let d = v.as(Double.self) { Text(Decimal(d).money).font(Theme.Font.caption).foregroundStyle(Theme.Text.tertiary) } }
            } }
            .frame(height: 170)
            HStack(spacing: 16) {
                legend("This month", color: Theme.Accent.default)
                legend("Projected", color: Theme.Accent.default, dashed: true)
                legend("Last month", color: Theme.Text.tertiary)
            }
            .padding(.top, Theme.Spacing.s12)
        }
        .padding(.horizontal, Theme.Spacing.s16)
    }

    private func legend(_ label: String, color: Color, dashed: Bool = false) -> some View {
        HStack(spacing: 6) {
            if dashed { Line().stroke(color, style: StrokeStyle(lineWidth: 2, dash: [3, 3])).frame(width: 16, height: 2) }
            else { RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 16, height: 3) }
            Text(label).font(Theme.Font.caption).foregroundStyle(Theme.Text.secondary)
        }
    }

    private func movers(_ p: Pace) -> some View {
        Card {
            let rows = Array(p.movers.prefix(5))
            ForEach(Array(rows.enumerated()), id: \.element.id) { i, m in
                HStack(spacing: Theme.Spacing.s12) {
                    IconCircle(symbol: m.category.symbol, size: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(m.category.title).font(Theme.Font.headline).foregroundStyle(Theme.Text.primary)
                        Text("\(m.thisMonth.money) this month").font(Theme.Font.footnote).foregroundStyle(Theme.Text.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text((m.delta > 0 ? "+" : "") + m.delta.money).font(Theme.Font.moneySM).foregroundStyle(m.delta > 0 ? Theme.Status.track : m.delta < 0 ? Theme.Status.good : Theme.Text.secondary)
                        Text("vs last month").font(Theme.Font.caption).foregroundStyle(Theme.Text.tertiary)
                    }
                }
                .padding(.vertical, Theme.Spacing.s12).padding(.horizontal, Theme.Spacing.s16)
                if i < rows.count - 1 { RowDivider() }
            }
        }
        .padding(.horizontal, Theme.Spacing.s16)
    }

    private func lens(_ p: Pace) -> some View {
        let income = model.verdict?.kept.expectedIncome ?? 0
        let kept = max(0, income - p.needs - p.wants)
        let total = max(p.needs + p.wants + kept, 1)
        func pct(_ d: Decimal) -> Double { NSDecimalNumber(decimal: d / total).doubleValue }
        return Card(padding: Theme.Spacing.s16) {
            GeometryReader { geo in
                HStack(spacing: 3) {
                    RoundedRectangle(cornerRadius: 5).fill(Theme.Text.tertiary).frame(width: max(4, geo.size.width * pct(p.needs)))
                    RoundedRectangle(cornerRadius: 5).fill(Theme.Accent.default).frame(width: max(4, geo.size.width * pct(p.wants)))
                    RoundedRectangle(cornerRadius: 5).fill(Theme.Status.good).frame(maxWidth: .infinity)
                }
            }
            .frame(height: 10)
            HStack {
                legendDot("Needs", value: pct(p.needs), color: Theme.Text.tertiary)
                Spacer()
                legendDot("Wants", value: pct(p.wants), color: Theme.Accent.default)
                Spacer()
                legendDot("Kept", value: pct(kept), color: Theme.Status.good)
            }
            .padding(.top, Theme.Spacing.s12)
            if income == 0 {
                Text("Needs / wants split of this month's spending. Kept fills in once Poise sees a paycheck.").font(Theme.Font.caption).foregroundStyle(Theme.Text.tertiary).padding(.top, Theme.Spacing.s8)
            }
        }
        .padding(.horizontal, Theme.Spacing.s16)
    }

    private func legendDot(_ label: String, value: Double, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).font(Theme.Font.caption).foregroundStyle(Theme.Text.secondary)
            Text(value.percent).font(Theme.Font.moneyXS).foregroundStyle(Theme.Text.primary)
        }
    }
}

private struct Line: Shape {
    func path(in rect: CGRect) -> Path { var p = Path(); p.move(to: CGPoint(x: 0, y: rect.midY)); p.addLine(to: CGPoint(x: rect.width, y: rect.midY)); return p }
}
