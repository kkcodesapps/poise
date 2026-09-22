import SwiftUI
import PoiseKit

/// Tap any row: change what it was for, what it is, or ask Poise to watch it. A correction can become a rule for that merchant.
struct TransactionDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let transaction: PoiseKit.Transaction

    @State private var kind: TransactionKind
    @State private var categoryID: String?
    @State private var always = false
    @State private var newCategory = false

    // watch drafts
    @State private var refundOn: Bool
    @State private var expected: Decimal
    @State private var nudgeDays: Int
    @State private var note: String
    @State private var merchantOn: Bool

    init(transaction: PoiseKit.Transaction) {
        self.transaction = transaction
        _kind = State(initialValue: transaction.kind)
        _categoryID = State(initialValue: transaction.categoryID)
        _refundOn = State(initialValue: false); _expected = State(initialValue: transaction.magnitude); _nudgeDays = State(initialValue: 14); _note = State(initialValue: ""); _merchantOn = State(initialValue: false)
    }

    private var account: Account? { model.accounts.first { $0.id == transaction.accountID } }
    private var changed: Bool { kind != transaction.kind || categoryID != transaction.categoryID }
    private var sameMerchantCount: Int { model.transactions.filter { $0.merchantKey == transaction.merchantKey && $0.id != transaction.id }.count }
    private var existingRefundWatch: Watch? { model.watches.first { $0.kind == .refund && $0.transactionID == transaction.id && $0.status.isOpen } }
    private var existingMerchantWatch: Watch? { model.watches.first { $0.kind == .merchant && $0.matcher == transaction.merchantKey && $0.status.isOpen } }
    private var isSpendLike: Bool { kind == .spend || kind == .untracked || kind == .refund }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    hero
                    if transaction.kind == .spend || transaction.kind == .untracked {
                        SectionHeader(title: "Watch")
                        watchSection
                    }
                    if isSpendLike {
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
                                Text("Always treat \(transaction.displayMerchant) this way").font(Theme.Font.body).foregroundStyle(Theme.Text.primary)
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
            .navigationTitle(transaction.displayMerchant)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.tint(Theme.Accent.default) }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { commit() }.fontWeight(.semibold).tint(Theme.Accent.default) }
            }
            .sheet(isPresented: $newCategory) { CategoryEditView(startWith: transaction.merchant) { created in categoryID = created.id; if kind != .spend && kind != .refund { kind = .spend } } }
            .onAppear {
                if let w = existingRefundWatch { refundOn = true; expected = w.expectedAmount ?? transaction.magnitude; nudgeDays = w.nudgeDays; note = w.note ?? "" }
                merchantOn = existingMerchantWatch != nil
            }
        }
        .presentationDragIndicator(.visible)
    }

    private func commit() {
        let t = transaction, k = kind, c = categoryID, a = always
        let wantRefund = refundOn, exp = expected, nd = nudgeDays, nt = note, wantMerchant = merchantOn
        let existingR = existingRefundWatch, existingM = existingMerchantWatch
        dismiss()
        Task {
            if changed { await model.correct(t, kind: k, categoryID: c, always: a) }
            if wantRefund, existingR == nil { await model.addWatch(Watch(kind: .refund, transactionID: t.id, merchant: t.merchant, expectedAmount: exp, nudgeDays: nd, note: nt.isEmpty ? nil : nt)) }
            else if wantRefund, var w = existingR { w.expectedAmount = exp; w.nudgeDays = nd; w.note = nt.isEmpty ? nil : nt; await model.updateWatch(w) }
            else if !wantRefund, let w = existingR { await model.removeWatch(w) }
            if wantMerchant, existingM == nil { await model.addWatch(Watch(kind: .merchant, transactionID: t.id, merchant: t.merchant)) }
            else if !wantMerchant, let w = existingM { await model.removeWatch(w) }
        }
    }

    private var hero: some View {
        VStack(spacing: 6) {
            IconCircle(symbol: isSpendLike ? model.categories.symbol(categoryID) : kind == .income ? "arrow.down.left" : kind == .ccPayment ? "creditcard" : "arrow.left.arrow.right",
                       size: 64, fill: Theme.Bg.subtle, color: Theme.Text.primary, dashed: transaction.pending)
                .padding(.bottom, 8)
            Text((transaction.amount > 0 ? "+" : "") + transaction.amount.money2).font(Theme.Font.moneyXL).foregroundStyle(transaction.amount > 0 ? Theme.Money.in : Theme.Text.primary)
            Text(transaction.pending ? "Pending · authorized \(transaction.displayDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))"
                 : transaction.displayDate.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                .font(Theme.Font.subhead).foregroundStyle(Theme.Text.secondary)
            if let account { Text("\(account.name) ••\(account.mask ?? "")\(transaction.pending ? " · usually posts in 1–2 days" : "")").font(Theme.Font.caption).foregroundStyle(Theme.Text.tertiary) }
            if transaction.isFee { Text("FEE").font(Theme.Font.caption2Strong).foregroundStyle(Theme.Status.heads).padding(.top, 4) }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Theme.Spacing.s12).padding(.bottom, Theme.Spacing.s8)
    }

    private var watchSection: some View {
        Card {
            Toggle(isOn: $refundOn.animation(.snappy)) {
                HStack(spacing: Theme.Spacing.s12) {
                    Image(systemName: "arrow.uturn.backward").font(.system(size: 17, weight: .medium)).foregroundStyle(refundOn ? Theme.Accent.default : Theme.Text.secondary).frame(width: 24)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Waiting for a refund").font(Theme.Font.body).foregroundStyle(Theme.Text.primary)
                        Text("Resolves itself when the money comes back").font(Theme.Font.caption).foregroundStyle(Theme.Text.tertiary)
                    }
                }
            }
            .tint(Theme.Accent.default).padding(.vertical, 10).padding(.horizontal, Theme.Spacing.s16)
            if refundOn {
                VStack(spacing: 0) {
                    HStack {
                        Text("Expecting back").font(Theme.Font.subhead).foregroundStyle(Theme.Text.primary); Spacer()
                        TextField("$0", value: $expected, format: .currency(code: "USD")).keyboardType(.decimalPad).multilineTextAlignment(.trailing).font(Theme.Font.subhead).foregroundStyle(Theme.Text.secondary).frame(width: 120)
                    }
                    .frame(minHeight: 44).padding(.leading, 52).padding(.trailing, Theme.Spacing.s16)
                    Divider().overlay(Theme.Border.subtle).padding(.leading, 52)
                    HStack {
                        Text("Nudge me after").font(Theme.Font.subhead).foregroundStyle(Theme.Text.primary); Spacer()
                        Picker("Nudge", selection: $nudgeDays) { ForEach([7, 14, 30, 60], id: \.self) { Text("\($0) days").tag($0) } }.tint(Theme.Text.secondary)
                    }
                    .frame(minHeight: 44).padding(.leading, 52).padding(.trailing, Theme.Spacing.s16)
                    Divider().overlay(Theme.Border.subtle).padding(.leading, 52)
                    HStack {
                        Text("Note").font(Theme.Font.subhead).foregroundStyle(Theme.Text.primary); Spacer()
                        TextField("Optional", text: $note).multilineTextAlignment(.trailing).font(Theme.Font.subhead).foregroundStyle(Theme.Text.secondary)
                    }
                    .frame(minHeight: 44).padding(.leading, 52).padding(.trailing, Theme.Spacing.s16)
                }
                .background(Theme.Bg.subtle)
            }
            RowDivider()
            Toggle(isOn: $merchantOn) {
                HStack(spacing: Theme.Spacing.s12) {
                    Image(systemName: "eye").font(.system(size: 17, weight: .medium)).foregroundStyle(merchantOn ? Theme.Accent.default : Theme.Text.secondary).frame(width: 24)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Tell me if \(transaction.displayMerchant) charges again").font(Theme.Font.body).foregroundStyle(Theme.Text.primary)
                        Text("Any future charge becomes a heads-up").font(Theme.Font.caption).foregroundStyle(Theme.Text.tertiary)
                    }
                }
            }
            .tint(Theme.Accent.default).padding(.vertical, 10).padding(.horizontal, Theme.Spacing.s16)
        }
        .padding(.horizontal, Theme.Spacing.s16)
    }

    private var chips: some View {
        FlowLayout(spacing: 8) {
            ForEach(model.categories.all) { c in
                chip(label: c.name, symbol: c.symbol, on: categoryID == c.id) {
                    categoryID = c.id
                    if kind != .spend && kind != .refund { kind = .spend }
                }
            }
            Button { newCategory = true } label: {
                HStack(spacing: 6) { Image(systemName: "plus").font(.system(size: 12, weight: .semibold)); Text("New…").font(Theme.Font.footnote.weight(.semibold)) }
                    .foregroundStyle(Theme.Accent.default).padding(.horizontal, 12).frame(height: 32)
                    .overlay(Capsule().strokeBorder(Theme.Border.strong, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Theme.Spacing.s16).padding(.top, 4)
    }

    private func chip(label: String, symbol: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 12, weight: .medium))
                Text(label).font(Theme.Font.footnote.weight(.semibold))
            }
            .foregroundStyle(on ? Theme.Accent.default : Theme.Text.secondary)
            .padding(.horizontal, 12).frame(height: 32)
            .background(on ? Theme.Accent.subtle : Theme.Bg.subtle, in: Capsule())
            .overlay(Capsule().strokeBorder(on ? Theme.Accent.default : .clear))
        }
        .buttonStyle(.plain)
    }

    private func kindRow(_ k: TransactionKind, symbol: String, label: String) -> some View {
        Button {
            kind = k
            if k != .spend && k != .refund { categoryID = nil } else if categoryID == nil { categoryID = transaction.categoryID ?? SpendCategory.other.rawValue }
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
