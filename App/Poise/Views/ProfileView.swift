import SwiftUI
import PoiseKit

/// Behind the profile button: accounts, settings, the weekly review, and the door to link another bank.
struct ProfileView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    SectionHeader(title: "Accounts")
                    if model.accounts.isEmpty {
                        Card { EmptyStateView(symbol: "building.columns", title: "No bank linked yet", body: "Link the account you spend from first. Savings and cards can come after.") }.padding(.horizontal, Theme.Spacing.s16)
                    } else {
                        Card {
                            let rows = model.accounts.sorted { ($0.role.order, $0.name) < ($1.role.order, $1.name) }
                            ForEach(Array(rows.enumerated()), id: \.element.id) { i, a in
                                AccountRowView(account: a) { role in Task { await model.setRole(role, for: a) } }
                                if i < rows.count - 1 { RowDivider() }
                            }
                        }
                        .padding(.horizontal, Theme.Spacing.s16)
                    }
                    Button(model.isLinking ? "Opening…" : model.accounts.isEmpty ? "Link a bank" : "Link another bank") { Task { await model.link() } }
                        .buttonStyle(.secondary).disabled(model.isLinking).padding(.horizontal, Theme.Spacing.s16).padding(.top, Theme.Spacing.s16)
                    Text("Read-only, always. Poise can see balances and transactions; it can never move money.").font(Theme.Font.caption).foregroundStyle(Theme.Text.tertiary)
                        .multilineTextAlignment(.center).padding(.horizontal, Theme.Spacing.s24).padding(.top, Theme.Spacing.s8)

                    SectionHeader(title: "Money")
                    SettingsSection()
                    SectionHeader(title: "Review")
                    Card {
                        NavRow(symbol: "sparkles", label: "This week's review", value: model.reviewCards.isEmpty ? "After the first sync" : "5 cards") {
                            dismiss(); model.showReview = true
                        }
                        .disabled(model.reviewCards.isEmpty)
                    }
                    .padding(.horizontal, Theme.Spacing.s16)
                    SectionHeader(title: "Data")
                    Card {
                        NavRow(symbol: "arrow.clockwise", label: "Refresh balances now", value: model.lastSync.map { $0.freshness } ?? "") { Task { await model.refresh(trigger: "foreground") } }
                    }
                    .padding(.horizontal, Theme.Spacing.s16)
                    Text("Poise 0.1.0 · sandbox").font(Theme.Font.caption).foregroundStyle(Theme.Text.tertiary).padding(.top, Theme.Spacing.s24)
                }
                .padding(.bottom, Theme.Spacing.s32)
            }
            .background(Theme.Bg.base)
            .navigationTitle("You")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.fontWeight(.semibold).tint(Theme.Accent.default) } }
        }
    }
}

struct AccountRowView: View {
    let account: Account
    var onRole: (AccountRole) -> Void = { _ in }
    var body: some View {
        HStack(spacing: Theme.Spacing.s12) {
            IconCircle(symbol: account.role == .credit ? "creditcard" : "building.columns")
            VStack(alignment: .leading, spacing: 2) {
                Text(account.name).font(Theme.Font.headline).foregroundStyle(Theme.Text.primary).lineLimit(1)
                Text("••\(account.mask ?? "") · \(account.role.title)").font(Theme.Font.footnote).foregroundStyle(Theme.Text.secondary)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text((account.role == .credit && account.current > 0 ? -account.current : account.balance).money2).font(Theme.Font.moneyMD).foregroundStyle(Theme.Text.primary)
                Menu {
                    ForEach(AccountRole.allCases, id: \.self) { r in Button(r.title) { onRole(r) } }
                } label: {
                    Text("CHANGE ROLE").font(Theme.Font.caption2Strong).foregroundStyle(Theme.Accent.default)
                }
            }
        }
        .padding(.vertical, Theme.Spacing.s12).padding(.horizontal, Theme.Spacing.s16)
    }
}

extension AccountRole {
    var title: String { switch self { case .spending: "Spending"; case .savings: "Savings"; case .credit: "Credit"; case .other: "Other" } }
    var order: Int { switch self { case .spending: 0; case .savings: 1; case .credit: 2; case .other: 3 } }
}

struct NavRow: View {
    let symbol: String
    let label: String
    var value: String = ""
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.s12) {
                Image(systemName: symbol).font(.system(size: 17, weight: .medium)).foregroundStyle(Theme.Text.secondary).frame(width: 24)
                Text(label).font(Theme.Font.body).foregroundStyle(Theme.Text.primary)
                Spacer()
                Text(value).font(Theme.Font.body).foregroundStyle(Theme.Text.secondary).lineLimit(1)
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.Text.tertiary)
            }
            .padding(.horizontal, Theme.Spacing.s16).frame(minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Payday, credit cards, kept target, committed savings, notification preferences.
struct SettingsSection: View {
    @Environment(AppModel.self) private var model
    @State private var draft = Repository.Settings()
    @State private var loaded = false

    var body: some View {
        Card {
            DatePickerRow(label: "Payday", detected: model.streams.first { $0.kind == .income }?.nextExpected, date: $draft.paydayOverride)
            RowDivider()
            ToggleRow(label: "I pay credit cards in full", isOn: $draft.paysCardsInFull)
            RowDivider()
            HStack {
                Text("Kept target").font(Theme.Font.body).foregroundStyle(Theme.Text.primary)
                Spacer()
                Picker("Kept target", selection: Binding(get: { draft.keptTarget.map { Int($0 * 100) } ?? -1 }, set: { draft.keptTarget = $0 < 0 ? nil : Double($0) / 100 })) {
                    Text("Beat last month").tag(-1)
                    ForEach([10, 20, 30, 40, 50], id: \.self) { Text("\($0)%").tag($0) }
                }
                .tint(Theme.Text.secondary)
            }
            .padding(.horizontal, Theme.Spacing.s16).frame(minHeight: 44)
            RowDivider()
            HStack {
                Text("Committed savings").font(Theme.Font.body).foregroundStyle(Theme.Text.primary)
                Spacer()
                TextField("$0", value: $draft.committedSavings, format: .currency(code: "USD").precision(.fractionLength(0)))
                    .keyboardType(.numberPad).multilineTextAlignment(.trailing).font(Theme.Font.body).foregroundStyle(Theme.Text.secondary).frame(width: 120)
            }
            .padding(.horizontal, Theme.Spacing.s16).frame(minHeight: 44)
            RowDivider()
            ToggleRow(label: "Notify on new spend", isOn: $draft.notifySpend)
            RowDivider()
            ToggleRow(label: "Notify on heads-ups", isOn: $draft.notifyHeadsUp)
            RowDivider()
            ToggleRow(label: "Weekly review · Sun 6 PM", isOn: $draft.notifyWeekly)
        }
        .padding(.horizontal, Theme.Spacing.s16)
        .onAppear { if !loaded { draft = model.settings; loaded = true } }
        .onChange(of: draft) { _, new in if loaded, new != model.settings { Task { await model.save(new) } } }
    }
}

struct ToggleRow: View {
    let label: String
    @Binding var isOn: Bool
    var body: some View {
        Toggle(label, isOn: $isOn).font(Theme.Font.body).foregroundStyle(Theme.Text.primary).tint(Theme.Accent.default)
            .padding(.horizontal, Theme.Spacing.s16).frame(minHeight: 44)
    }
}

struct DatePickerRow: View {
    let label: String
    let detected: Date?
    @Binding var date: Date?
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(Theme.Font.body).foregroundStyle(Theme.Text.primary)
                if date == nil { Text(detected.map { "Detected: \($0.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))" } ?? "Not detected yet — set it here").font(Theme.Font.caption).foregroundStyle(Theme.Text.tertiary) }
            }
            Spacer()
            if let d = date {
                DatePicker("", selection: Binding(get: { d }, set: { date = $0 }), displayedComponents: .date).labelsHidden().tint(Theme.Accent.default)
                Button { date = nil } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.Text.tertiary) }.buttonStyle(.plain)
            } else {
                Button("Set") { date = detected ?? Calendar.current.date(byAdding: .day, value: 14, to: .now) }.font(Theme.Font.subheadStrong).tint(Theme.Accent.default)
            }
        }
        .padding(.horizontal, Theme.Spacing.s16).frame(minHeight: 44)
    }
}
