import SwiftUI
import PoiseKit

/// What changed since the app was last in front: new charges, what posted, cards paid, refunds in. Nothing here is new data.
struct SinceView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    if let s = model.since {
                        let charges = s.new.filter { $0.kind != .ccPayment && $0.kind != .refund }
                        group("New charges", charges)
                        group("Posted", s.posted)
                        group("Refunds", s.refunds)
                        group("Payments", s.payments)
                        Text("Everything here is already in the feed — this is just what changed since you last opened Poise.")
                            .font(Theme.Font.caption).foregroundStyle(Theme.Text.tertiary)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, Theme.Spacing.s16).padding(.top, Theme.Spacing.s16)
                    } else {
                        EmptyStateView(symbol: "sparkles", title: "Nothing new", body: "You’ve seen everything that landed since you last looked.").padding(.top, 80)
                    }
                }
                .padding(.bottom, Theme.Spacing.s32)
            }
            .background(Theme.Bg.base)
            .navigationTitle("Since \(model.since?.lastLooked.sinceLabel ?? "you last looked")")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() }.tint(Theme.Accent.default) } }
        }
    }

    @ViewBuilder private func group(_ title: String, _ rows: [PoiseKit.Transaction]) -> some View {
        if !rows.isEmpty {
            SectionHeader(title: rows.count > 1 ? "\(title) · \(rows.count)" : title)
            Card {
                ForEach(Array(rows.enumerated()), id: \.element.id) { i, t in
                    Button { dismiss(); model.selectedTransaction = t } label: { TransactionRowView(transaction: t, account: model.accounts.first { $0.id == t.accountID }, showsDate: true) }.buttonStyle(.plain)
                    if i < rows.count - 1 { RowDivider() }
                }
            }
            .padding(.horizontal, Theme.Spacing.s16)
        }
    }
}
