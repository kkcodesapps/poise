import SwiftUI
import PoiseKit

/// Tap any row: change what it was for, or what it is. A correction can become a rule for that merchant.
struct TransactionDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let transaction: PoiseKit.Transaction

    @State private var kind: TransactionKind
    @State private var category: SpendCategory?
    @State private var always = false

    init(transaction: PoiseKit.Transaction) {
        self.transaction = transaction
        _kind = State(initialValue: transaction.kind)
        _category = State(initialValue: transaction.category)
    }

    private var account: Account? { model.accounts.first { $0.id == transaction.accountID } }
    private var changed: Bool { kind != transaction.kind || category != transaction.category }
    private var sameMerchantCount: Int { model.transactions.filter { $0.merchantKey == transaction.merchantKey && $0.id != transaction.id }.count }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    hero
                    if kind == .spend || kind == .untracked || kind == .refund {
                        SectionHeader(title: "Category")
                        chips
                    }
                    SectionHeader(title: "This is…")
                    Card {
                        kindRow(.spend, symbol: "bag", label: "Spending")
                        RowDivider()
                        kindRow(.transfer, symbol: "arrow.left.arrow.right", label: "A transfer between my accounts")
                        RowDivider()
                        kindRow(.refund, symbol: "arrow.uturn.backward", label: "A refund or return")
                        RowDivider()
                        kindRow(.ccPayment, symbol: "creditcard", label: "A credit-card payment")
                        if transaction.kind == .income { RowDivider(); kindRow(.income, symbol: "arrow.down.left", label: "Income") }
                    }
                    .padding(.horizontal, Theme.Spacing.s16)
                    if sameMerchantCount > 0, changed {
                        Toggle(isOn: $always) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Always treat \(transaction.merchant) this way").font(Theme.Font.body).foregroundStyle(Theme.Text.primary)
                                Text("Applies to \(sameMerchantCount) other charge\(sameMerchantCount == 1 ? "" : "s") and everything that comes after.").font(Theme.Font.footnote).foregroundStyle(Theme.Text.secondary)
                            }
                        }
                        .tint(Theme.Accent.default)
                        .padding(Theme.Spacing.s16)
                    }
                }
                .padding(.bottom, Theme.Spacing.s32)
            }
            .background(Theme.Bg.base)
            .navigationTitle(transaction.merchant)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.tint(Theme.Accent.default) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        let t = transaction, k = kind, c = category, a = always
                        dismiss()
                        if changed { Task { await model.correct(t, kind: k, category: c, always: a) } }
                    }
                    .fontWeight(.semibold).tint(Theme.Accent.default)
                }
            }
        }
        .presentationDragIndicator(.visible)
    }

    private var hero: some View {
        VStack(spacing: 6) {
            IconCircle(symbol: kind == .spend ? (category?.symbol ?? "ellipsis") : kind == .refund ? "arrow.uturn.backward" : kind == .income ? "arrow.down.left" : kind == .ccPayment ? "creditcard" : "arrow.left.arrow.right",
                       size: 64, fill: Theme.Bg.subtle, color: Theme.Text.primary, dashed: transaction.pending)
                .padding(.bottom, 8)
            Text((transaction.amount > 0 ? "+" : "") + transaction.amount.money2).font(Theme.Font.moneyXL).foregroundStyle(transaction.amount > 0 ? Theme.Money.in : Theme.Text.primary)
            Text(transaction.pending ? "Pending · authorized \(transaction.displayDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))"
                 : transaction.displayDate.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                .font(Theme.Font.subhead).foregroundStyle(Theme.Text.secondary)
            if let account {
                Text("\(account.name) ••\(account.mask ?? "")\(transaction.pending ? " · usually posts in 1–2 days" : "")").font(Theme.Font.caption).foregroundStyle(Theme.Text.tertiary)
            }
            if transaction.isFee { Text("FEE").font(Theme.Font.caption2Strong).foregroundStyle(Theme.Status.heads).padding(.top, 4) }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Theme.Spacing.s12).padding(.bottom, Theme.Spacing.s8)
    }

    private var chips: some View {
        FlowLayout(spacing: 8) {
            ForEach(SpendCategory.allCases, id: \.self) { c in
                let on = category == c
                Button {
                    category = c
                    if kind != .spend && kind != .refund { kind = .spend }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: c.symbol).font(.system(size: 12, weight: .medium))
                        Text(c.title).font(Theme.Font.footnote.weight(.semibold))
                    }
                    .foregroundStyle(on ? Theme.Accent.default : Theme.Text.secondary)
                    .padding(.horizontal, 12).frame(height: 32)
                    .background(on ? Theme.Accent.subtle : Theme.Bg.subtle, in: Capsule())
                    .overlay(Capsule().strokeBorder(on ? Theme.Accent.default : .clear))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Theme.Spacing.s16).padding(.top, 4)
    }

    private func kindRow(_ k: TransactionKind, symbol: String, label: String) -> some View {
        Button {
            kind = k
            if k != .spend && k != .refund { category = nil } else if category == nil { category = transaction.category ?? .other }
        } label: {
            HStack(spacing: Theme.Spacing.s12) {
                Image(systemName: symbol).font(.system(size: 17, weight: .medium)).foregroundStyle(Theme.Text.secondary).frame(width: 24)
                Text(label).font(Theme.Font.body).foregroundStyle(Theme.Text.primary)
                Spacer()
                if kind == k { Image(systemName: "checkmark").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.Accent.default) }
            }
            .padding(.horizontal, Theme.Spacing.s16).frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Wraps its children like text. Used for the category chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += size.width + spacing; rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing; rowHeight = max(rowHeight, size.height)
        }
    }
}
