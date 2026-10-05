import SwiftUI
import PoiseKit

/// One account's page: what it is, how it counts, whether it counts at all — and the door to drop its institution.
struct AccountView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let accountID: String
    @State private var confirmDisconnect = false

    private var account: Account? { model.account(id: accountID) }

    var body: some View {
        ScrollView {
            if let account {
                VStack(spacing: 0) {
                    hero(account)
                    if let due = account.statementDue, account.role == .credit {
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
                        Text((account.statementIsEstimate ? "Rebuilt from last month’s charges and refunds, less what’s been paid since — Wallet doesn’t share the statement balance itself. " : "")
                             + (model.settings.paysCardsInFull ? "Next 14 counts the full balance because “I pay credit cards in full” is on." : "Next 14 counts the minimum because “I pay credit cards in full” is off."))
                            .font(Theme.Font.caption).foregroundStyle(Theme.Text.tertiary)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, Theme.Spacing.s16).padding(.top, Theme.Spacing.s8)
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
