import SwiftUI
import AuthenticationServices
import PoiseKit

/// The first run (Figma §01): sign in → link the first account → we read it → confirm the payday we spotted. No forms.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @State private var pickingPayday = false

    var body: some View {
        ZStack {
            Theme.Bg.base.ignoresSafeArea()
            switch model.onboarding {
            case .welcome: welcome.transition(.opacity)
            case .link: link.transition(.asymmetric(insertion: .move(edge: .trailing), removal: .opacity))
            case .reading: reading.transition(.opacity)
            case .payday: payday.transition(.asymmetric(insertion: .move(edge: .trailing), removal: .opacity))
            case nil: EmptyView()
            }
        }
        .animation(.easeInOut(duration: 0.3), value: model.onboarding)
        .sheet(isPresented: $pickingPayday) { PaydaySheet() }
    }

    // MARK: Welcome

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer().frame(height: 96)
            PoiseMark()
            Text("How you’re doing,\nin one sentence.").font(Theme.Font.displayLG).foregroundStyle(Theme.Text.primary).padding(.top, Theme.Spacing.s24)
            Text("Poise links your accounts, shows every charge the day you actually paid, and tells you the one thing worth doing about it.")
                .font(Theme.Font.body).foregroundStyle(Theme.Text.secondary).padding(.top, Theme.Spacing.s24)
            Spacer()
            AppleSignInButton(height: 50) { model.onboardingSignedIn() }
            Text("No passwords. Read-only access to your banks — Poise can never move money.")
                .font(Theme.Font.caption).foregroundStyle(Theme.Text.tertiary).multilineTextAlignment(.center).frame(maxWidth: .infinity).padding(.top, Theme.Spacing.s12)
            Button("Look around without an account") { model.advanceOnboarding(to: .link) }.buttonStyle(.ghost).padding(.top, Theme.Spacing.s4)
        }
        .padding(.horizontal, Theme.Spacing.s24).padding(.bottom, Theme.Spacing.s8)
    }

    // MARK: Link

    private var link: some View {
        VStack(alignment: .leading, spacing: 0) {
            bar(back: model.isAnonymous ? { model.advanceOnboarding(to: .welcome) } : nil)
            Text("Link your first account").font(Theme.Font.titleLG).foregroundStyle(Theme.Text.primary).padding(.top, Theme.Spacing.s24)
            Text("Start with the account you spend from. You can add savings and cards after.")
                .font(Theme.Font.body).foregroundStyle(Theme.Text.secondary).padding(.top, Theme.Spacing.s12)
            VStack(spacing: 0) {
                promise("lock", "Read-only, always", "Poise sees transactions and balances. It can’t move a cent.")
                promise("bolt", "Charges in hours, not days", "Pending shows up with the day you paid — not the day the bank posts it.")
                promise("checkmark.shield", "Your login never touches your phone", "The bank connection is handled by Plaid; Poise only ever receives data.")
            }
            .padding(.top, Theme.Spacing.s24)
            Spacer()
            Button(model.walletAvailable ? "Link an account" : "Continue with Plaid") { model.startLink() }
                .buttonStyle(.primary).disabled(model.isLinking).opacity(model.isLinking ? 0.6 : 1)
            Button("I’ll do this later") { model.finishOnboarding() }.buttonStyle(.ghost).padding(.top, Theme.Spacing.s8)
        }
        .padding(.horizontal, Theme.Spacing.s24).padding(.bottom, Theme.Spacing.s8)
    }

    private func promise(_ symbol: String, _ title: String, _ body: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            IconCircle(symbol: symbol, size: 40, fill: Theme.Accent.subtle, color: Theme.Accent.default)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.Font.headline).foregroundStyle(Theme.Text.primary)
                Text(body).font(Theme.Font.footnote).foregroundStyle(Theme.Text.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, Theme.Spacing.s8)
    }

    // MARK: Reading

    private var reading: some View {
        VStack(alignment: .leading, spacing: 0) {
            bar(back: nil).padding(.horizontal, Theme.Spacing.s8)
            Card(padding: Theme.Spacing.s20) {
                HStack {
                    Text("POISE").font(Theme.Font.caption2Strong).foregroundStyle(Theme.Text.tertiary)
                    Spacer()
                    HStack(spacing: 6) {
                        Circle().fill(model.isLoading ? Theme.Accent.default : Theme.Status.good).frame(width: 6, height: 6)
                        Text(model.isLoading ? "checking…" : "up to date").font(Theme.Font.caption).foregroundStyle(Theme.Text.tertiary)
                    }
                }
                Text("Reading your accounts…").font(Theme.Font.verdictLG).foregroundStyle(Theme.Text.primary).padding(.top, Theme.Spacing.s16)
                Text("Most banks take a minute. Pending charges show up with the day you actually paid.")
                    .font(Theme.Font.body).foregroundStyle(Theme.Text.secondary).padding(.top, Theme.Spacing.s8)
                HStack(spacing: Theme.Spacing.s16) { bone; bone }.padding(.top, Theme.Spacing.s16)
            }
            .padding(.top, Theme.Spacing.s16)
            VStack(spacing: 0) {
                ForEach(Array(model.allAccounts.enumerated()), id: \.element.id) { i, a in
                    HStack(spacing: Theme.Spacing.s12) {
                        IconCircle(symbol: a.role == .credit ? "creditcard" : "building.columns", size: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(a.name + (a.mask.map { " ••\($0)" } ?? "")).font(Theme.Font.headline).foregroundStyle(Theme.Text.primary).lineLimit(1)
                            Text(rowsLine(for: a)).font(Theme.Font.footnote).foregroundStyle(Theme.Text.secondary)
                        }
                        Spacer()
                        if model.isLoading {
                            Text("checking…").font(Theme.Font.caption).foregroundStyle(Theme.Text.tertiary)
                        } else {
                            IconCircle(symbol: "checkmark", size: 24, fill: Theme.Status.goodBg, color: Theme.Status.good)
                        }
                    }
                    .padding(.vertical, Theme.Spacing.s12).padding(.horizontal, Theme.Spacing.s16)
                    if i < model.allAccounts.count - 1 { Divider().overlay(Theme.Border.subtle).padding(.leading, 68) }
                }
            }
            .padding(.top, Theme.Spacing.s24)
            Text("Most banks take about a minute. You can close this — we’ll notify you when the first verdict is ready.")
                .font(Theme.Font.footnote).foregroundStyle(Theme.Text.tertiary).multilineTextAlignment(.center).frame(maxWidth: .infinity)
                .padding(.top, Theme.Spacing.s24).padding(.horizontal, Theme.Spacing.s16)
            Spacer()
        }
        .padding(.horizontal, Theme.Spacing.s16)
    }

    private var bone: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s8) {
            RoundedRectangle(cornerRadius: 4).fill(Theme.Bg.subtle).frame(width: 48, height: 10)
            RoundedRectangle(cornerRadius: 6).fill(Theme.Bg.subtle).frame(width: 96, height: 26)
            RoundedRectangle(cornerRadius: 4).fill(Theme.Bg.subtle).frame(width: 120, height: 10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func rowsLine(for a: Account) -> String {
        let rows = model.transactions.filter { $0.accountID == a.id }
        let pending = rows.filter { $0.pending }.count
        if rows.isEmpty { return model.isLoading ? "checking…" : "No charges yet" }
        return "\(rows.count) transaction\(rows.count == 1 ? "" : "s")" + (pending > 0 ? " · \(pending) pending" : "")
    }

    // MARK: Payday

    private var payday: some View {
        let income = model.streams.first { $0.kind == .income }
        return VStack(alignment: .leading, spacing: 0) {
            bar(back: nil)
            if let income {
                Text("Looks like you get paid \(income.cadence.spoken), on \(income.nextExpected.formatted(.dateTime.weekday(.wide)))s")
                    .font(Theme.Font.titleLG).foregroundStyle(Theme.Text.primary).padding(.top, Theme.Spacing.s24)
                Text("Poise uses payday to work out how far ahead you are. Next one: \(income.nextExpected.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())).")
                    .font(Theme.Font.body).foregroundStyle(Theme.Text.secondary).padding(.top, Theme.Spacing.s12)
                let rows = Array(model.charges(for: income).prefix(3))
                if !rows.isEmpty {
                    Card {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { i, t in
                            TransactionRowView(transaction: t, account: model.accounts.first { $0.id == t.accountID }, showsDate: true)
                            if i < rows.count - 1 { RowDivider() }
                        }
                    }
                    .padding(.top, Theme.Spacing.s20)
                }
            } else {
                Text("Poise will spot your payday as deposits come in").font(Theme.Font.titleLG).foregroundStyle(Theme.Text.primary).padding(.top, Theme.Spacing.s24)
                Text("Payday is how Poise works out how far ahead you are. Set it now if you know it, or let Poise find it.")
                    .font(Theme.Font.body).foregroundStyle(Theme.Text.secondary).padding(.top, Theme.Spacing.s12)
            }
            Spacer()
            if income != nil {
                Button("That’s right") { model.finishOnboarding() }.buttonStyle(.primary)
                Button("Change payday") { pickingPayday = true }.buttonStyle(.ghost).padding(.top, Theme.Spacing.s8)
            } else {
                Button("Set payday") { pickingPayday = true }.buttonStyle(.primary)
                Button("Skip for now") { model.finishOnboarding() }.buttonStyle(.ghost).padding(.top, Theme.Spacing.s8)
            }
        }
        .padding(.horizontal, Theme.Spacing.s24).padding(.bottom, Theme.Spacing.s8)
    }

    // MARK: Bits

    /// The nav strip: a Back chevron when there's somewhere to go, else just the height.
    private func bar(back: (() -> Void)?) -> some View {
        HStack {
            if let back {
                Button(action: back) {
                    HStack(spacing: 2) { Image(systemName: "chevron.left").font(.system(size: 17, weight: .semibold)); Text("Back").font(Theme.Font.body) }
                }
                .tint(Theme.Accent.default)
            }
            Spacer()
        }
        .frame(height: 44)
    }
}

/// The payday override, as a calendar: pick the next one and Poise counts from there.
private struct PaydaySheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var date = Calendar.current.date(byAdding: .day, value: 14, to: .now) ?? .now

    var body: some View {
        NavigationStack {
            VStack(spacing: Theme.Spacing.s16) {
                Text("When is your next payday?").font(Theme.Font.titleMD).foregroundStyle(Theme.Text.primary).frame(maxWidth: .infinity, alignment: .leading)
                DatePicker("Next payday", selection: $date, in: Date.now..., displayedComponents: .date)
                    .datePickerStyle(.graphical).tint(Theme.Accent.default)
                Spacer()
                Button("Use \(date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))") {
                    var s = model.settings; s.paydayOverride = date
                    Task { await model.save(s); model.finishOnboarding() }
                    dismiss()
                }
                .buttonStyle(.primary)
            }
            .padding(Theme.Spacing.s16)
            .background(Theme.Bg.base)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.tint(Theme.Accent.default) } }
        }
        .onAppear { if let s = model.streams.first(where: { $0.kind == .income }) { date = max(s.nextExpected, .now) } }
    }
}

/// The "P" mark, as on the launch screen and the lock screen.
struct PoiseMark: View {
    var size: CGFloat = 72
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size / 4, style: .continuous).fill(Theme.Accent.default)
                .shadow(color: Theme.Accent.default.opacity(0.35), radius: 16, y: 6)
            Text("P").font(.system(size: size * 0.58, weight: .bold, design: .rounded)).foregroundStyle(.white)
        }
        .frame(width: size, height: size)
    }
}

/// Sign in with Apple, wired to the model. Black on light, white on dark — Apple's own rule.
struct AppleSignInButton: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme
    var height: CGFloat = 50
    var onSignedIn: () -> Void = {}
    @State private var nonce = Auth.makeNonce()

    var body: some View {
        SignInWithAppleButton(.signIn) { request in
            request.requestedScopes = [.fullName]
            request.nonce = Auth.sha256(nonce)
        } onCompletion: { result in
            switch result {
            case .success(let auth):
                if let credential = auth.credential as? ASAuthorizationAppleIDCredential {
                    let n = nonce
                    Task { if await model.signInWithApple(credential, nonce: n) { onSignedIn() } }
                    nonce = Auth.makeNonce()
                }
            case .failure(let error):
                if (error as? ASAuthorizationError)?.code != .canceled { model.errorMessage = error.localizedDescription }
            }
        }
        .signInWithAppleButtonStyle(scheme == .dark ? .white : .black)
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
    }
}

extension Cadence {
    /// "every two weeks", for a sentence.
    var spoken: String {
        switch self { case .weekly: "every week"; case .biweekly: "every two weeks"; case .semimonthly: "twice a month"; case .monthly: "once a month"; case .quarterly: "every quarter"; case .annual: "once a year" }
    }
}
