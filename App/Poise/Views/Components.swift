import SwiftUI
import PoiseKit

// Shared building blocks. Names mirror the design file's components.

/// Elevated card with the hairline border used for every grouped list.
struct Card<Content: View>: View {
    var padding: CGFloat = 0
    @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing: 0) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.Bg.elevated, in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous).strokeBorder(Theme.Border.subtle))
    }
}

struct SectionHeader: View {
    let title: String
    var action: String? = nil
    var onAction: () -> Void = {}
    var body: some View {
        HStack(alignment: .lastTextBaseline) {
            Text(title).font(Theme.Font.titleSM).foregroundStyle(Theme.Text.primary)
            Spacer()
            if let action { Button(action, action: onAction).font(Theme.Font.footnote.weight(.semibold)).tint(Theme.Accent.default) }
        }
        .padding(.top, Theme.Spacing.s24).padding(.bottom, Theme.Spacing.s8).padding(.horizontal, Theme.Spacing.s16)
    }
}

struct RowDivider: View {
    var body: some View { Divider().overlay(Theme.Border.subtle).padding(.leading, 68) }
}

struct IconCircle: View {
    let symbol: String
    var size: CGFloat = 40
    var fill: Color = Theme.Bg.subtle
    var color: Color = Theme.Text.primary
    var dashed = false
    var body: some View {
        ZStack {
            Circle().fill(dashed ? .clear : fill)
            if dashed { Circle().strokeBorder(Theme.Border.strong, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3])) }
            Image(systemName: symbol).font(.system(size: size * 0.42, weight: .medium)).foregroundStyle(color)
        }
        .frame(width: size, height: size)
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
    private var label: String { switch status { case .goodShape: "IN GOOD SHAPE"; case .onTrack: "ON TRACK"; case .headsUp: "HEADS UP" } }
    private var color: Color { switch status { case .goodShape: Theme.Status.good; case .onTrack: Theme.Status.track; case .headsUp: Theme.Status.heads } }
    private var background: Color { switch status { case .goodShape: Theme.Status.goodBg; case .onTrack: Theme.Status.trackBg; case .headsUp: Theme.Status.headsBg } }
}

extension Insight.Tone {
    var color: Color { switch self { case .heads: Theme.Status.heads; case .neutral: Theme.Text.primary; case .good: Theme.Status.good } }
    var background: Color { switch self { case .heads: Theme.Status.headsBg; case .neutral: Theme.Bg.subtle; case .good: Theme.Status.goodBg } }
}

extension Insight.Kind {
    var symbol: String {
        switch self {
        case .crunch: "arrow.right"
        case .duplicate: "doc.on.doc"
        case .priceUp: "chart.line.uptrend.xyaxis"
        case .fee: "receipt"
        case .paceOverrun: "fork.knife"
        case .positive: "sparkles"
        case .newStream: "arrow.clockwise"
        case .renewal: "clock"
        case .watchTriggered: "eye"
        case .refundOverdue: "arrow.uturn.backward"
        case .refundArrived: "checkmark"
        }
    }
}

struct InsightRowView: View {
    let insight: Insight
    var showChevron = true
    var body: some View {
        HStack(spacing: Theme.Spacing.s12) {
            IconCircle(symbol: insight.kind.symbol, size: 36, fill: insight.tone.background, color: insight.tone.color)
            VStack(alignment: .leading, spacing: 2) {
                Text(insight.title).font(Theme.Font.subheadStrong).foregroundStyle(Theme.Text.primary)
                Text(insight.body).font(Theme.Font.footnote).foregroundStyle(Theme.Text.secondary)
            }
            Spacer(minLength: 8)
            if showChevron { Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.Text.tertiary) }
        }
        .padding(.vertical, Theme.Spacing.s12).padding(.horizontal, Theme.Spacing.s16)
        .contentShape(Rectangle())
    }
}

struct StreamRowView: View {
    let stream: RecurringStream
    var body: some View {
        HStack(spacing: Theme.Spacing.s12) {
            ZStack {
                Circle().fill(Theme.Bg.subtle)
                Text(String(stream.displayMerchant.prefix(1)).uppercased()).font(Theme.Font.headline).foregroundStyle(Theme.Text.primary)
            }
            .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(stream.displayMerchant).font(Theme.Font.headline).foregroundStyle(Theme.Text.primary).lineLimit(1)
                Text("\(stream.cadence.label.capitalized) · next \(stream.nextExpected.formatted(.dateTime.month(.abbreviated).day()))")
                    .font(Theme.Font.footnote).foregroundStyle(Theme.Text.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(stream.amount.moneyString(cents: true)).font(Theme.Font.moneyMD).foregroundStyle(Theme.Text.primary)
                if stream.priceWentUp, let prev = stream.previousAmount {
                    Text("WAS \(prev.moneyString(cents: true))").font(Theme.Font.caption2Strong).foregroundStyle(Theme.Status.track)
                } else if stream.cadence == .annual {
                    Text("YEARLY").font(Theme.Font.caption2Strong).foregroundStyle(Theme.Accent.default)
                } else {
                    Text(stream.kind == .income ? "INCOME" : stream.cadence == .monthly ? "/mo" : "").font(Theme.Font.caption).foregroundStyle(Theme.Text.tertiary)
                }
            }
        }
        .padding(.vertical, Theme.Spacing.s12).padding(.horizontal, Theme.Spacing.s16)
    }
}

struct EmptyStateView: View {
    let symbol: String
    let title: String
    let text: String
    init(symbol: String, title: String, body: String) { self.symbol = symbol; self.title = title; self.text = body }
    var body: some View {
        VStack(spacing: Theme.Spacing.s8) {
            IconCircle(symbol: symbol, size: 56, fill: Theme.Bg.subtle, color: Theme.Text.tertiary)
            Text(title).font(Theme.Font.titleSM).foregroundStyle(Theme.Text.primary).multilineTextAlignment(.center)
            Text(text).font(Theme.Font.footnote).foregroundStyle(Theme.Text.secondary).multilineTextAlignment(.center)
        }
        .padding(.vertical, Theme.Spacing.s32).padding(.horizontal, Theme.Spacing.s24)
        .frame(maxWidth: .infinity)
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

struct SecondaryButtonStyle: ButtonStyle {
    var compact = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(compact ? Theme.Font.subheadStrong : Theme.Font.headline)
            .foregroundStyle(Theme.Text.primary)
            .padding(.horizontal, compact ? 16 : 20)
            .frame(maxWidth: compact ? nil : .infinity, minHeight: compact ? 44 : 50)
            .background(Theme.Bg.subtle.opacity(configuration.isPressed ? 0.7 : 1), in: RoundedRectangle(cornerRadius: compact ? Theme.Radius.md : Theme.Radius.lg, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: compact ? Theme.Radius.md : Theme.Radius.lg, style: .continuous).strokeBorder(Theme.Border.subtle))
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle { static var primary: PrimaryButtonStyle { PrimaryButtonStyle() } }
extension ButtonStyle where Self == SecondaryButtonStyle { static var secondary: SecondaryButtonStyle { SecondaryButtonStyle() }; static var secondaryCompact: SecondaryButtonStyle { SecondaryButtonStyle(compact: true) } }

extension Decimal {
    /// "$1,240" — whole dollars, for the verdict.
    var money: String { moneyString(cents: false) }
    /// "−$62.40" — cents kept, for rows.
    var money2: String { moneyString(cents: true) }
}

extension Double {
    var percent: String { "\(Int((self * 100).rounded()))%" }
}


extension Date {
    /// "as of just now" / "as of 2 min ago" / "as of 3 h ago"
    var freshness: String {
        let s = Int(Date.now.timeIntervalSince(self))
        if s < 60 { return "as of just now" }
        if s < 3600 { return "as of \(s / 60) min ago" }
        if s < 86_400 { return "as of \(s / 3600) h ago" }
        return "as of \(s / 86_400) d ago"
    }
}


extension PoiseKit.Transaction {
    /// Raw bank descriptors shout ("ACH ELECTRONIC CREDIT *//"); show them like a name.
    var displayMerchant: String { merchant.prettyMerchant }
}

extension RecurringStream {
    var displayMerchant: String { merchant.prettyMerchant }
}

extension String {
    var prettyMerchant: String {
        var s = self.replacingOccurrences(of: #"[*#/]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let letters = s.filter(\.isLetter)
        if letters.count > 3, letters.allSatisfy(\.isUppercase) {
            s = s.capitalized.replacingOccurrences(of: "Ach ", with: "ACH ").replacingOccurrences(of: "Atm ", with: "ATM ")
        }
        return s
    }
}
