import SwiftUI
import PoiseKit

/// One merchant, everything about it: what it costs you, since when, every charge, and the rules for it.
struct MerchantView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let merchantKey: String
    @State private var selected: PoiseKit.Transaction?
    @State private var renaming = false
    @State private var newName = ""
    @State private var filing = false
    @State private var following = false

    private var rows: [PoiseKit.Transaction] { model.rows(merchant: merchantKey) }
    private var stats: AppModel.MerchantStats? { model.stats(merchant: merchantKey) }
    private var sample: PoiseKit.Transaction? { rows.first { $0.kind == .spend || $0.kind == .untracked } ?? rows.first }
    private var watching: Bool { model.isWatched(merchantKey: merchantKey) }

    var body: some View {
        NavigationStack {
            ScrollView {
                if let s = stats, let sample {
                    VStack(spacing: 0) {
                        VStack(spacing: 4) {
                            MerchantCircle(logoURL: s.logoURL, symbol: s.symbol, size: 64)
                            Text(s.name).font(Theme.Font.titleMD).foregroundStyle(Theme.Text.primary).multilineTextAlignment(.center).padding(.top, 4)
                            Text("\(s.categoryName) · \(s.count) \(model.storeShape(merchantKey: merchantKey) != nil ? "order" : "charge")\(s.count == 1 ? "" : "s")\(s.firstSeen.map { " since \($0.formatted(.dateTime.month(.abbreviated).year()))" } ?? "")")
                                .font(Theme.Font.subhead).foregroundStyle(Theme.Text.secondary)
                        }
                        .frame(maxWidth: .infinity).padding(.top, Theme.Spacing.s12).padding(.bottom, Theme.Spacing.s12)
                        HStack(spacing: 8) {
                            tile("THIS MONTH", s.thisMonth.money)
                            // A shop is read per visit; a place you use on a rhythm, per month.
                            if model.storeShape(merchantKey: merchantKey) != nil { tile("USUALLY / ORDER", s.perCharge?.money ?? "—") }
                            else { tile("USUALLY / MO", s.usual?.money ?? "—") }
                            tile("THIS YEAR", s.thisYear.money)
                        }
                        .padding(.horizontal, Theme.Spacing.s16)

                        if let shape = model.storeShape(merchantKey: merchantKey) { storeCard(shape, sample: sample) }
                        let followed = model.itemsFollowed(at: merchantKey)
                        if !followed.isEmpty {
                            SectionHeader(title: "Followed from here · \(followed.count)")
                            Card {
                                ForEach(Array(followed.enumerated()), id: \.element.id) { i, item in
                                    Button { model.selectedPriceItem = .init(id: item.id) } label: { PriceItemRow(item: item) }.buttonStyle(.plain)
                                    if i < followed.count - 1 { RowDivider() }
                                }
                            }
                            .padding(.horizontal, Theme.Spacing.s16)
                        }
                        SectionHeader(title: "\(model.storeShape(merchantKey: merchantKey) != nil ? "Orders" : "Charges") · \(rows.count)")
                        Card {
                            ForEach(Array(rows.enumerated()), id: \.element.id) { i, t in
                                Button { selected = t } label: { TransactionRowView(transaction: t, account: model.accounts.first { $0.id == t.accountID }, showsDate: true) }.buttonStyle(.plain)
                                if i < rows.count - 1 { RowDivider() }
                            }
                        }
                        .padding(.horizontal, Theme.Spacing.s16)

                        SectionHeader(title: "Manage")
                        Card {
                            NavRow(symbol: "pencil", label: "Call it", value: s.name) { newName = sample.displayName ?? ""; renaming = true }
                            if s.categoryID != nil {
                                RowDivider()
                                NavRow(symbol: "tag", label: "File under", value: s.categoryName) { filing = true }
                            }
                            RowDivider()
                            ToggleRow(label: "Tell me if it charges again", isOn: Binding(get: { watching }, set: { on in Task { await model.setMerchantWatch(on, merchant: sample.merchant) } }))
                            RowDivider()
                            ToggleRow(label: "Ask about double charges", isOn: Binding(get: { model.flagsDuplicates(merchantKey: merchantKey) }, set: { on in Task { await model.setDuplicateFlagging(on, merchantKey: merchantKey) } }))
                        }
                        .padding(.horizontal, Theme.Spacing.s16)
                        Text("Call it and File under apply to every charge from \(sample.merchant.prettyMerchant), past and future." + (model.flagsDuplicates(merchantKey: merchantKey) ? "" : " Two identical same-day charges here won't be flagged."))
                            .font(Theme.Font.caption).foregroundStyle(Theme.Text.tertiary)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, Theme.Spacing.s16).padding(.top, Theme.Spacing.s8)
                    }
                    .padding(.bottom, Theme.Spacing.s32)
                } else {
                    EmptyStateView(symbol: "magnifyingglass", title: "Nothing here", body: "No charges from this merchant in the feed.").padding(.top, 80)
                }
            }
            .background(Theme.Bg.base)
            .navigationTitle(stats?.name ?? "Merchant")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() }.tint(Theme.Accent.default) } }
            .sheet(item: $selected) { t in TransactionDetailView(transaction: t) }
            .sheet(isPresented: $filing) { if let sample { FileUnderSheet(sample: sample) } }
            .sheet(isPresented: $following) { if let sample { FollowItemSheet(merchantKey: merchantKey, sample: sample) } }
            .alert("Call it", isPresented: $renaming) {
                TextField(sample?.merchant.prettyMerchant ?? "Name", text: $newName)
                Button("Save") { if let sample { Task { await model.rename(sample, to: newName, always: true) } } }
                Button("Cancel", role: .cancel) {}
            } message: { Text("Every charge from \(sample?.merchant.prettyMerchant ?? "this merchant") will read this way.") }
        }
    }

    /// A shop that sells everything has no price — say so, and offer the thing that does work: follow one item from here.
    private func storeCard(_ shape: AppModel.StoreShape, sample: PoiseKit.Transaction) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.Text.tertiary).padding(.top, 2)
            VStack(alignment: .leading, spacing: Theme.Spacing.s8) {
                Text("A store, not a price").font(Theme.Font.subheadStrong).foregroundStyle(Theme.Text.primary)
                Text("Every charge here is a different basket — \(shape.low.money2) to \(shape.high.money2) — so there’s nothing to chart. Name one thing you buy again and Poise follows that instead.")
                    .font(Theme.Font.footnote).foregroundStyle(Theme.Text.secondary)
                Button("Follow an item from here") { following = true }.buttonStyle(.secondaryCompact)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.s16)
        .background(Theme.Bg.subtle, in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
        .padding(.horizontal, Theme.Spacing.s16).padding(.top, Theme.Spacing.s12)
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
}

/// "File under": the category rule for a merchant, as chips.
struct FileUnderSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let sample: PoiseKit.Transaction

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.s12) {
                    Text("Every charge from \(sample.displayMerchant), past and future, files here.").font(Theme.Font.footnote).foregroundStyle(Theme.Text.secondary)
                    FlowLayout(spacing: 8) {
                        ForEach(model.categories.all) { c in
                            Chip(label: c.name, symbol: c.symbol, on: model.categories.resolve(sample.categoryID).id == c.id) {
                                Task { await model.correct(sample, kind: .spend, categoryID: c.id, always: true) }
                                dismiss()
                            }
                        }
                    }
                }
                .padding(Theme.Spacing.s16)
            }
            .background(Theme.Bg.base)
            .navigationTitle("File under")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.tint(Theme.Accent.default) } }
            .presentationDetents([.medium])
        }
    }
}


/// "Follow an item from here": pick one of this store's charges and give it a name — that name becomes the run.
struct FollowItemSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let merchantKey: String
    let sample: PoiseKit.Transaction
    @State private var name = ""
    @State private var picked: String?

    private var rows: [PoiseKit.Transaction] { model.rows(merchant: merchantKey).filter { $0.kind == .spend || $0.kind == .untracked } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.s12) {
                    Text("Give one charge a name — “Naked Whey Protein”, “Dog food”. Every charge you name the same way becomes one run with its own price history, here and at any other store.")
                        .font(Theme.Font.footnote).foregroundStyle(Theme.Text.secondary)
                    TextField("What was it?", text: $name).font(Theme.Font.body).foregroundStyle(Theme.Text.primary)
                        .padding(.horizontal, 14).frame(height: 44).background(Theme.Bg.inset, in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
                    let suggestions = model.itemNames(at: merchantKey).filter { $0 != name }
                    if !suggestions.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) { ForEach(suggestions, id: \.self) { n in Chip(label: n, symbol: "tag", on: false) { name = n } } }
                        }
                    }
                    SectionHeader(title: "Which charge?")
                    Card {
                        ForEach(Array(rows.prefix(8).enumerated()), id: \.element.id) { i, t in
                            Button { picked = picked == t.id ? nil : t.id } label: {
                                HStack(spacing: 0) {
                                    TransactionRowView(transaction: t, account: model.accounts.first { $0.id == t.accountID }, showsDate: true)
                                    if picked == t.id { Image(systemName: "checkmark").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.Accent.default).padding(.trailing, Theme.Spacing.s16) }
                                }
                            }
                            .buttonStyle(.plain)
                            if i < min(8, rows.count) - 1 { RowDivider() }
                        }
                    }
                }
                .padding(Theme.Spacing.s16)
            }
            .background(Theme.Bg.base)
            .navigationTitle("Follow an item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.tint(Theme.Accent.default) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Follow") {
                        if let id = picked, let t = rows.first(where: { $0.id == id }) { Task { await model.rename(t, to: name, always: false) } }
                        dismiss()
                    }
                    .fontWeight(.semibold).tint(Theme.Accent.default)
                    .disabled(picked == nil || name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { picked = rows.first?.id }
        }
    }
}
