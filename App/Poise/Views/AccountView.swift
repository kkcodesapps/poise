import SwiftUI
import PoiseKit

/// One account's page: what it is, how it counts, whether it counts at all — and the door to drop its institution.
struct AccountView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let accountID: String
    /// Off when the card's page already offers the statement and payment on a page of their own.
    var showsPayment = true
    @State private var confirmDisconnect = false

    private var account: Account? { model.account(id: accountID) }

    var body: some View {
        ScrollView {
            if let account {
                VStack(spacing: 0) {
                    hero(account)
                    if showsPayment, account.statementDue != nil, account.role == .credit {
                        StatementSection(account: account)
                        SectionHeader(title: "How you pay it")
                        PayChoice(account: account)
                    }
                    SectionHeader(title: "Counts as")
                    Card(padding: Theme.Spacing.s12) {
                        VStack(alignment: .leading, spacing: 10) {
                            FlowLayout(spacing: 8) {
                                ForEach(AccountRole.allCases, id: \.self) { role in
                                    Chip(label: role.title, symbol: role.symbol, on: account.role == role) { Task { await model.setRole(role, for: account) } }
                                }
                            }
                            Text(account.role.note).font(Theme.Font.caption).foregroundStyle(Theme.Text.tertiary)
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.s16)

                    SectionHeader(title: "Visibility")
                    Card {
                        ToggleRow(label: "Hide from Poise", isOn: Binding(get: { account.hidden }, set: { on in Task { await model.setHidden(on, for: account) } }))
                    }
                    .padding(.horizontal, Theme.Spacing.s16)
                    Text(account.hidden
                         ? "Hidden since \(account.hiddenAt?.formatted(.dateTime.month(.abbreviated).day()) ?? "today"). Turn this off and it counts again right away — its history was kept the whole time."
                         : "Hidden accounts count nowhere — not the verdict, the feed, Where or Leaks — and stay hidden through every refresh. Nothing is deleted; show it again any time.")
                        .font(Theme.Font.caption).foregroundStyle(Theme.Text.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, Theme.Spacing.s16).padding(.top, Theme.Spacing.s8)

                    if let institution = account.institution, let itemID = account.itemID, institution != "Apple" {
                        Button("Load two years of history") { Task { await model.relink(Repository.Item(id: itemID, institution: institution, status: "ok")) } }
                            .buttonStyle(.ghost).padding(.horizontal, Theme.Spacing.s16).padding(.top, Theme.Spacing.s16)
                        Text("Re-opens the bank's login once; Plaid then fills in up to 24 months so Leaks can see yearly renewals and Where's year view is complete.")
                            .font(Theme.Font.caption).foregroundStyle(Theme.Text.tertiary).multilineTextAlignment(.center).padding(.horizontal, Theme.Spacing.s24)
                    }
                    if let institution = account.institution, account.itemID != nil {
                        Button("Disconnect \(institution)…") { confirmDisconnect = true }
                            .buttonStyle(.ghost(Theme.Status.heads)).padding(.horizontal, Theme.Spacing.s16).padding(.top, Theme.Spacing.s24)
                        Text("Removes every \(institution) account and its history from Poise. You can link it again any time.")
                            .font(Theme.Font.caption).foregroundStyle(Theme.Text.tertiary).multilineTextAlignment(.center)
                            .padding(.horizontal, Theme.Spacing.s24)
                    }
                }
                .padding(.bottom, Theme.Spacing.s32)
            }
        }
        .background(Theme.Bg.base)
        .navigationTitle(account?.name ?? "Account")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Disconnect \(account?.institution ?? "this bank")?", isPresented: $confirmDisconnect, titleVisibility: .visible) {
            Button("Remove \(account?.institution ?? "it") and its history", role: .destructive) {
                if let itemID = account?.itemID { Task { await model.disconnect(itemID: itemID); dismiss() } }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every \(account?.institution ?? "") account leaves Poise, and the bank connection is revoked. Hiding keeps the data; this doesn't.")
        }
    }

    private func hero(_ account: Account) -> some View {
        VStack(spacing: 6) {
            IconCircle(symbol: account.symbol, size: 64)
            Text(account.name).font(Theme.Font.titleMD).foregroundStyle(Theme.Text.primary).multilineTextAlignment(.center)
            Text([account.institution, account.mask.map { "••\($0)" }, account.role.title].compactMap { $0 }.joined(separator: " · "))
                .font(Theme.Font.subhead).foregroundStyle(Theme.Text.secondary)
            if account.hidden {
                HStack(spacing: 4) {
                    Image(systemName: "eye.slash").font(.system(size: 11, weight: .semibold))
                    Text("Not counted").font(Theme.Font.captionStrong)
                }
                .foregroundStyle(Theme.Text.secondary).padding(.vertical, 3).padding(.leading, 8).padding(.trailing, 10)
                .background(Theme.Bg.subtle, in: Capsule())
            }
            Text(account.displayBalance.money2).font(Theme.Font.moneyLG).foregroundStyle(account.hidden ? Theme.Text.tertiary : Theme.Text.primary)
            Text(account.hidden ? "balance not counted" : (account.balanceAt?.freshness ?? "balance from the last sync"))
                .font(Theme.Font.caption).foregroundStyle(Theme.Text.tertiary)
        }
        .frame(maxWidth: .infinity).padding(.top, Theme.Spacing.s20).padding(.bottom, Theme.Spacing.s12).padding(.horizontal, Theme.Spacing.s16)
    }
}

/// A card's statement: when it's due, how much, and the minimum — with a note when Poise had to rebuild the figure.
struct StatementSection: View {
    let account: Account

    var body: some View {
        if let due = account.statementDue {
            VStack(spacing: 0) {
                SectionHeader(title: "Statement")
                Card {
                    HStack { Text("Due").font(Theme.Font.body).foregroundStyle(Theme.Text.primary); Spacer()
                        Text("\(due.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))\(account.statementAmount.map { " · \($0.money2)" } ?? "")").font(Theme.Font.body).foregroundStyle(Theme.Text.secondary) }
                        .padding(.horizontal, Theme.Spacing.s16).frame(minHeight: 44)
                    if let min = account.minimumDue {
                        RowDivider()
                        HStack { Text("Minimum").font(Theme.Font.body).foregroundStyle(Theme.Text.primary); Spacer(); Text(min.money2).font(Theme.Font.body).foregroundStyle(Theme.Text.secondary) }
                            .padding(.horizontal, Theme.Spacing.s16).frame(minHeight: 44)
                    }
                }
                .padding(.horizontal, Theme.Spacing.s16)
                if account.statementIsEstimate {
                    Text("Rebuilt from last month’s charges and refunds, less what’s been paid since — Wallet doesn’t share the statement balance itself.")
                        .font(Theme.Font.caption).foregroundStyle(Theme.Text.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, Theme.Spacing.s16).padding(.top, Theme.Spacing.s8)
                }
            }
        }
    }
}

/// Everything the user has taken out of the math, grouped like the main list, with a way back.
struct HiddenAccountsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                if model.hiddenAccounts.isEmpty {
                    EmptyStateView(symbol: "eye.slash", title: "Nothing hidden", body: "Open any account from the list and turn on Hide from Poise. It stays out of everything until you show it again.")
                        .padding(.top, 120)
                } else {
                    Text("These stay out of everything — balances, the feed, Where, Leaks — until you show them again.")
                        .font(Theme.Font.footnote).foregroundStyle(Theme.Text.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, Theme.Spacing.s16).padding(.top, Theme.Spacing.s12)
                    ForEach(model.grouped(model.hiddenAccounts)) { group in
                        SectionHeader(title: group.institution)
                        Card {
                            ForEach(Array(group.accounts.enumerated()), id: \.element.id) { i, a in
                                NavigationLink(value: "account:\(a.id)") {
                                    AccountRowView(account: a) {
                                        Button("Show") { Task { await model.setHidden(false, for: a) } }
                                            .font(Theme.Font.subheadStrong).foregroundStyle(Theme.Accent.default).buttonStyle(.plain)
                                    }
                                }
                                .buttonStyle(.plain)
                                if i < group.accounts.count - 1 { RowDivider() }
                            }
                        }
                        .padding(.horizontal, Theme.Spacing.s16)
                    }
                    Text("Show brings an account and its whole history straight back into the math.")
                        .font(Theme.Font.caption).foregroundStyle(Theme.Text.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, Theme.Spacing.s16).padding(.top, Theme.Spacing.s8)
                }
            }
            .padding(.bottom, Theme.Spacing.s32)
        }
        .background(Theme.Bg.base)
        .navigationTitle("Hidden accounts")
        .navigationBarTitleDisplayMode(.inline)
    }
}


/// The four ways a card gets paid, each naming the money it would cost.
///
/// The statement balance and the whole balance are different sums on any card used since the statement closed — on a
/// busy card, thousands apart — so they're separate choices rather than one word. The footer states what the forecast
/// will actually subtract and when, because that is the only thing this setting does.
struct PayChoice: View {
    @Environment(AppModel.self) private var model
    let account: Account
    @State private var editingAmount = false
    @State private var draftAmount: Decimal = 0

    private var chosen: CardPayment { account.pays ?? model.settings.newCardsPay }

    private func amount(_ option: CardPayment) -> Decimal? {
        var probe = account
        probe.pays = option
        return probe.statementPayment(default: model.settings.newCardsPay)
    }

    var body: some View {
        VStack(spacing: 0) {
            Card {
                ForEach(Array(CardPayment.allCases.enumerated()), id: \.element) { i, option in
                    Button {
                        if option == .fixed { draftAmount = account.paysFixedAmount ?? 0; editingAmount = true }
                        else { Task { await model.setPayment(option, for: account) } }
                    } label: {
                        HStack(spacing: Theme.Spacing.s12) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(option.title).font(Theme.Font.body).foregroundStyle(Theme.Text.primary)
                                Text(option.detail).font(Theme.Font.caption).foregroundStyle(Theme.Text.tertiary)
                            }
                            Spacer(minLength: 8)
                            if let value = amount(option) {
                                Text(value.money2).font(Theme.Font.moneySM)
                                    .foregroundStyle(option == chosen ? Theme.Text.primary : Theme.Text.tertiary)
                            }
                            if option == chosen {
                                Image(systemName: "checkmark").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.Accent.default)
                            }
                        }
                        .padding(.horizontal, Theme.Spacing.s16).padding(.vertical, Theme.Spacing.s12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if i < CardPayment.allCases.count - 1 { RowDivider() }
                }
            }
            .padding(.horizontal, Theme.Spacing.s16)
            Text(footer)
                .font(Theme.Font.caption).foregroundStyle(Theme.Text.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Theme.Spacing.s16).padding(.top, Theme.Spacing.s8)
        }
        .alert("How much each month?", isPresented: $editingAmount) {
            TextField("$0", value: $draftAmount, format: .number).keyboardType(.decimalPad)
            Button("Cancel", role: .cancel) {}
            Button("Set") { Task { await model.setPayment(.fixed, fixedAmount: draftAmount, for: account) } }
        } message: {
            Text("Poise will count this leaving checking on the due date.")
        }
    }

    private var footer: String {
        guard let due = account.nextDue(now: .now), let amount = account.statementPayment(default: model.settings.newCardsPay) else {
            return "Nothing is counted for this card until there's a figure to count."
        }
        let day = due.date.formatted(.dateTime.month(.abbreviated).day())
        var line = "Next counts \(amount.money2) leaving checking on \(day)."
        // The gap between the statement and the balance is the whole reason these are separate choices.
        if chosen == .statement, let statement = account.statementAmount {
            let since = (account.owed - statement).roundedToCents
            if since > 0 { line += " The \(since.money2) charged since the statement closed waits for the next one." }
        }
        if chosen == .minimum { line += " The rest keeps sitting on the card." }
        return line
    }
}
