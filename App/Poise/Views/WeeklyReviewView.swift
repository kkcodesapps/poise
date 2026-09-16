import SwiftUI
import PoiseKit

/// Sunday's five cards, sixty seconds. Swipe through; Next advances; Skip closes.
struct WeeklyReviewView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var page = 0

    private var range: String {
        let end = Date.now, start = Calendar.current.date(byAdding: .day, value: -7, to: end)!
        return "\(start.formatted(.dateTime.month(.abbreviated).day())) – \(end.formatted(.dateTime.month(.abbreviated).day()))"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Your week").font(Theme.Font.titleMD).foregroundStyle(Theme.Text.primary)
                    Text("\(range) · 60 seconds").font(Theme.Font.footnote).foregroundStyle(Theme.Text.secondary)
                }
                Spacer()
                Button { dismiss() } label: { IconCircle(symbol: "xmark", size: 32, fill: Theme.Bg.subtle, color: Theme.Text.primary) }.buttonStyle(.plain)
            }
            .padding(.horizontal, Theme.Spacing.s24).padding(.top, Theme.Spacing.s16)
            TabView(selection: $page) {
                ForEach(Array(model.reviewCards.enumerated()), id: \.element.id) { i, card in
                    ReviewCardView(card: card).padding(.horizontal, Theme.Spacing.s24).tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            HStack(spacing: 6) {
                ForEach(0..<max(model.reviewCards.count, 1), id: \.self) { i in
                    Capsule().fill(i == page ? Theme.Text.primary : Theme.Border.strong).frame(width: i == page ? 18 : 6, height: 6)
                }
            }
            .padding(.bottom, Theme.Spacing.s24)
            VStack(spacing: Theme.Spacing.s8) {
                Button(page < model.reviewCards.count - 1 ? "Next" : "Done") {
                    if page < model.reviewCards.count - 1 { withAnimation { page += 1 } } else { dismiss() }
                }
                .buttonStyle(.primary)
                Button("Skip this week") { dismiss() }.font(Theme.Font.headline).tint(Theme.Accent.default).frame(minHeight: 44)
            }
            .padding(.horizontal, Theme.Spacing.s24).padding(.bottom, Theme.Spacing.s12)
        }
        .background(Theme.Bg.base)
    }
}

struct ReviewCardView: View {
    let card: ReviewCard
    private var color: Color { switch card.tone { case .neutral: Theme.Text.primary; case .good: Theme.Status.good; case .heads: Theme.Status.heads } }
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s8) {
            Text(card.eyebrow).font(Theme.Font.captionStrong).foregroundStyle(Theme.Text.tertiary)
            Text(card.value).font(Theme.Font.moneyXL).foregroundStyle(color).padding(.top, 8).minimumScaleFactor(0.6).lineLimit(1)
            Text(card.title).font(Theme.Font.titleMD).foregroundStyle(Theme.Text.primary)
            Text(card.body).font(Theme.Font.verdictMD).foregroundStyle(Theme.Text.secondary)
            Spacer(minLength: 0)
        }
        .padding(Theme.Spacing.s24)
        .frame(maxWidth: .infinity, maxHeight: 420, alignment: .topLeading)
        .background(Theme.Bg.elevated, in: RoundedRectangle(cornerRadius: Theme.Radius.xxl, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.xxl, style: .continuous).strokeBorder(Theme.Border.subtle))
    }
}
