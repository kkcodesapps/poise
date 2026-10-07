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

    // what was this
    @State private var name: String
    @State private var nameForAll = true
    @State private var noteText: String
    @State private var leftOut: Bool
    @State private var showMerchant = false

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
        _name = State(initialValue: transaction.displayName ?? ""); _noteText = State(initialValue: transaction.note ?? ""); _leftOut = State(initialValue: transaction.excluded)
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
                    if sameMerchantCount > 0 {
                        Button { showMerchant = true } label: {
                            HStack(spacing: 4) {
                                Text("All \(sameMerchantCount + 1) charges from \(transaction.displayMerchant)").font(Theme.Font.subheadStrong)
                                Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold))
                            }
                            .foregroundStyle(Theme.Accent.default)
                        }
                        .buttonStyle(.plain).padding(.bottom, Theme.Spacing.s8)
                    }
                    if let why = model.insightContext, why.id.hasSuffix(transaction.id) { whyCard(why) }
                    SectionHeader(title: "What was this?")
                    whatSection
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
                        RowDivider()
                        Button { leftOut.toggle() } label: {
                            HStack(spacing: Theme.Spacing.s12) {
                                Image(systemName: "eye.slash").font(.system(size: 17, weight: .medium)).foregroundStyle(Theme.Text.secondary).frame(width: 24)
                                Text("Not spending — leave it out").font(Theme.Font.body).foregroundStyle(Theme.Text.primary)
                                Spacer()
                                if leftOut { Image(systemName: "checkmark").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.Accent.default) }
                            }
                            .padding(.horizontal, Theme.Spacing.s16).frame(minHeight: 44).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, Theme.Spacing.s16)
                    Text(leftOut ? "Left out of the math. It stays in the feed, greyed, and out of Kept, Pace and Where." : "For one-offs — something you were paid back for in cash, moving costs. It stays in the feed and out of every number.")
                        .font(Theme.Font.caption).foregroundStyle(Theme.Text.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, Theme.Spacing.s16).padding(.top, Theme.Spacing.s8)
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
            .sheet(isPresented: $showMerchant) { MerchantView(merchantKey: transaction.merchantKey) }
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
        let newName = name.trimmingCharacters(in: .whitespacesAndNewlines), forAll = nameForAll
        let newNote = noteText.trimmingCharacters(in: .whitespacesAndNewlines), out = leftOut
        dismiss()
        Task {
            if newName != (t.displayName ?? "") { await model.rename(t, to: newName, always: forAll) }
            if newNote != (t.note ?? "") { await model.setNote(t, note: newNote) }
            if out != t.excluded { await model.setExcluded(t, out) }
            if changed { await model.correct(t, kind: k, categoryID: c, always: a) }
            if wantRefund, existingR == nil { await model.addWatch(Watch(kind: .refund, transactionID: t.id, merchant: t.merchant, expectedAmount: exp, nudgeDays: nd, note: nt.isEmpty ? nil : nt)) }
            else if wantRefund, var w = existingR { w.expectedAmount = exp; w.nudgeDays = nd; w.note = nt.isEmpty ? nil : nt; await model.updateWatch(w) }
            else if !wantRefund, let w = existingR { await model.removeWatch(w) }
            if wantMerchant, existingM == nil { await model.addWatch(Watch(kind: .merchant, transactionID: t.id, merchant: t.merchant)) }
            else if !wantMerchant, let w = existingM { await model.removeWatch(w) }
        }
    }

    /// A name — for this charge, or for every charge from the merchant — and a note for one-offs.
    private var whatSection: some View {
        let raw = transaction.merchant.prettyMerchant
        let sameMerchant = sameMerchantCount
        return VStack(spacing: Theme.Spacing.s8) {
            Card(padding: Theme.Spacing.s12) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        TextField(raw, text: $name).font(Theme.Font.body).foregroundStyle(Theme.Text.primary).submitLabel(.done)
                        if !name.isEmpty { Button { name = "" } label: { Image(systemName: "xmark").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.Text.tertiary) }.buttonStyle(.plain) }
                    }
                    .padding(.horizontal, 14).frame(height: 44).background(Theme.Bg.inset, in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
                    if !name.isEmpty, name != (transaction.displayName ?? ""), sameMerchant > 0 {
                        Toggle("Always call it this", isOn: $nameForAll).font(Theme.Font.body).foregroundStyle(Theme.Text.primary).tint(Theme.Accent.default)
                    }
                    TextField("Add a note — who it was for, why it matters", text: $noteText, axis: .vertical).font(Theme.Font.body).foregroundStyle(Theme.Text.primary).lineLimit(1...4)
                        .padding(.horizontal, 14).padding(.vertical, 11).background(Theme.Bg.inset, in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
                    Text(nameForAll && !name.isEmpty && sameMerchant > 0
                         ? "“Always” names the \(sameMerchant) other charge\(sameMerchant == 1 ? "" : "s") from \(raw) too, and every one after. The note stays on this charge."
                         : "The bank calls it \(raw). Your name replaces it in the feed; the note stays on this charge.")
                        .font(Theme.Font.caption).foregroundStyle(Theme.Text.tertiary)
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.s16)
    }

    /// Only when the sheet was opened from an insight: what Poise noticed, and a way to settle it.
    private func whyCard(_ why: Insight) -> some View {
        let partner = why.kind == .duplicate ? model.duplicatePartner(of: transaction) : nil
        let fees = model.fees
        return VStack(alignment: .leading, spacing: Theme.Spacing.s12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.Status.heads).padding(.top, 2)
                VStack(alignment: .leading, spacing: 4) {
                    Text(why.kind == .duplicate ? "Charged twice?" : "A fee").font(Theme.Font.subheadStrong).foregroundStyle(Theme.Text.primary)
                    Text(why.kind == .duplicate
                         ? "The same \(transaction.magnitude.money2) hit this card twice\(partner.map { " on \($0.displayDate.formatted(.dateTime.month(.abbreviated).day()))" } ?? ""). That's usually one purchase posting twice — the second often drops off on its own." + (model.duplicateStrikes(for: why) == AppModel.duplicateStrikesToMute - 1 ? " Say both are real once more and Poise stops asking about \(transaction.displayMerchant)." : "")
                         : "\(transaction.magnitude.money2) charged by the bank itself. That makes \(fees.total.money) in fees this year across \(fees.items.count) charge\(fees.items.count == 1 ? "" : "s") — Leaks keeps the running total, and banks often waive the first one you ask about.")
                        .font(Theme.Font.footnote).foregroundStyle(Theme.Text.secondary)
                }
            }
            if let partner {
                Button { model.insightContext = nil; model.selectedTransaction = partner } label: {
                    TransactionRowView(transaction: partner, account: model.accounts.first { $0.id == partner.accountID })
                        .background(Theme.Bg.elevated, in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: Theme.Spacing.s8) {
                Button(why.kind == .duplicate ? "Both are real" : "Got it") { model.acknowledge(why); model.insightContext = nil }.buttonStyle(.secondaryCompact)
                if why.kind == .duplicate {
                    Button("Watch for a refund") {
                        refundOn = true; expected = transaction.magnitude
                        Task { await model.addWatch(Watch(kind: .refund, transactionID: transaction.id, merchant: transaction.merchant, expectedAmount: transaction.magnitude)) }
                        model.acknowledge(why); model.insightContext = nil
                    }
                    .font(Theme.Font.subheadStrong).foregroundStyle(Theme.Accent.default).buttonStyle(.plain).padding(.horizontal, 12)
                }
            }
        }
        .padding(Theme.Spacing.s16)
        .background(Theme.Status.headsBg, in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
        .padding(.horizontal, Theme.Spacing.s16)
    }

    private var hero: some View {
        VStack(spacing: 6) {
            MerchantCircle(logoURL: isSpendLike ? transaction.logoURL : nil, symbol: isSpendLike ? model.categories.symbol(categoryID) : kind == .income ? "arrow.down.left" : kind == .ccPayment ? "creditcard" : "arrow.left.arrow.right",
                           size: 64, fill: Theme.Bg.subtle, color: Theme.Text.primary, dashed: transaction.pending)
                .padding(.bottom, 8)
            Text((transaction.amount > 0 ? "+" : "") + transaction.amount.money2).font(Theme.Font.moneyXL).foregroundStyle(transaction.amount > 0 ? Theme.Money.in : Theme.Text.primary)
            Text(transaction.pending ? "Pending · authorized \(transaction.displayDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))"
                 : transaction.displayDate.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                .font(Theme.Font.subhead).foregroundStyle(Theme.Text.secondary)
            if let account { Text("\(account.mask.map { "\(account.name) ••\($0)" } ?? account.name)\(transaction.pending ? " · usually posts in 1–2 days" : "")").font(Theme.Font.caption).foregroundStyle(Theme.Text.tertiary) }
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
                Chip(label: c.name, symbol: c.symbol, on: categoryID == c.id) {
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
