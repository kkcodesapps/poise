import SwiftUI
import WebKit
import PoiseKit

/// Connecting Amazon, in four stages: what Poise will read, Amazon's own sign-in, the read itself, and what it found.
/// Figma §28.
struct AmazonConnectView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    /// Straight to the sign-in when the session has only lapsed — they've read the explainer once already.
    let startSignedOut: Bool
    /// Debug only: opens straight on the reading screen so the progress bar can be looked at.
    var startReading = false
    @State private var stage: Stage = .explain
    /// Bumped each time the user asks to sign in. The watcher hangs off this rather than off the sign-in view, so a
    /// stage change can't cancel it half way through a read.
    @State private var attempt = 0

    init(startSignedOut: Bool = false, startReading: Bool = false) {
        self.startSignedOut = startSignedOut
        self.startReading = startReading
    }

    private enum Stage { case explain, signIn, reading, done }

    var body: some View {
        NavigationStack {
            Group {
                switch stage {
                case .explain: explain
                case .signIn: signIn
                case .reading: reading
                case .done: done
                }
            }
            .background(Theme.Bg.base)
            .navigationTitle(stage == .signIn ? "amazon.com" : "Amazon")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if stage == .explain || stage == .signIn {
                    ToolbarItem(placement: .cancellationAction) { Button(stage == .signIn ? "Cancel" : "Close") { dismiss() }.tint(Theme.Accent.default) }
                }
                if stage == .done {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.fontWeight(.semibold).tint(Theme.Accent.default) }
                }
            }
        }
        .presentationDragIndicator(.visible)

        .onAppear {
            if startReading { stage = .reading }
            else if startSignedOut, attempt == 0 { stage = .signIn; attempt += 1 }
        }
        .task(id: attempt) { if attempt > 0 { await watchForSignIn() } }
    }

    // MARK: what Poise reads

    private var explain: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.s16) {
                Text("Connect Amazon").font(Theme.Font.titleLG).foregroundStyle(Theme.Text.primary)
                Text("Your bank only sends the amount. Amazon knows what was in it — sign in and every Amazon charge gets its order, and a link that opens the app right on it.")
                    .font(Theme.Font.verdictMD).foregroundStyle(Theme.Text.secondary)
                Card(padding: Theme.Spacing.s16) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.s16) {
                        Text("WHAT POISE READS").font(Theme.Font.caption2Strong).foregroundStyle(Theme.Text.tertiary)
                        promise("Your Amazon payments page", "Date, amount and order number — the page that lines up with your charges. Nothing else on Amazon is touched.")
                        promise("On this phone only", "The signed-in session stays in the app on your device. Poise's server only ever receives the order number.")
                        promise("Read, never act", "No browsing history, no addresses, no saved cards, and nothing can be bought.")
                    }
                }
                Button("Sign in to Amazon") { stage = .signIn; attempt += 1 }.buttonStyle(.primary)
                Text("You sign in on Amazon's own page — Poise never sees your password, and you can disconnect any time.")
                    .font(Theme.Font.caption).foregroundStyle(Theme.Text.tertiary)
            }
            .padding(.horizontal, Theme.Spacing.s16).padding(.vertical, Theme.Spacing.s8)
        }
    }

    private func promise(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(Theme.Font.headline).foregroundStyle(Theme.Text.primary)
            Text(body).font(Theme.Font.footnote).foregroundStyle(Theme.Text.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Amazon's own page

    private var signIn: some View {
        VStack(spacing: Theme.Spacing.s8) {
            HStack(spacing: 6) {
                Image(systemName: "lock.fill").font(.system(size: 11, weight: .semibold))
                Text("amazon.com · Amazon's own sign-in page").font(Theme.Font.caption)
                Spacer()
            }
            .foregroundStyle(Theme.Text.secondary)
            .padding(.horizontal, Theme.Spacing.s12).padding(.vertical, Theme.Spacing.s8)
            .background(Theme.Bg.subtle, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            AmazonWebView()
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
            Text("This is Amazon's page, loaded in the app. Poise can't read what you type into it — only the payments page you land on afterwards.")
                .font(Theme.Font.caption).foregroundStyle(Theme.Text.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, Theme.Spacing.s16).padding(.bottom, Theme.Spacing.s16)
    }

    /// Amazon's sign-in is several pages — password, sometimes a one-time code — so rather than guess at its shape we
    /// wait until it stops asking, then let the read itself decide whether we're really in.
    private func watchForSignIn() async {
        AmazonSource.shared.start()
        var settled = 0
        while !Task.isCancelled, stage != .done {
            try? await Task.sleep(for: .seconds(2))
            if await AmazonSource.shared.isAtSignIn() { settled = 0; continue }
            // Two clear readings in a row, so the pause between Amazon's email and password pages can't pass for done.
            settled += 1
            guard settled >= 2 else { continue }
            // Signed in — which was the only part needing them. The read is handed to the model and the sheet gets out
            // of the way; Home carries the progress from here.
            model.startAmazonSweep()
            dismiss()
            return
            // Amazon let us past the form but not to the page. The reader is a separate web view, so whatever they're
            // part-way through is still on screen — go back to it and keep waiting rather than tell a cheerful lie.
            stage = .signIn
            settled = 0
        }
    }

    // MARK: reading

    /// Only reachable through `-amazon reading`, kept so the progress can be looked at without a real sweep. The
    /// sheet itself never shows this any more — Home does.
    private var reading: some View {
        VStack(spacing: Theme.Spacing.s12) {
            Spacer()
            Text(readingTitle).font(Theme.Font.verdictMD).foregroundStyle(Theme.Text.primary)
            ProgressTrack(value: readingProgress).padding(.horizontal, Theme.Spacing.s32)
            Text(readingDetail).font(Theme.Font.caption).foregroundStyle(Theme.Text.tertiary)
            if model.amazonItemsTotal > 0, model.amazonOrdersRead > 0 {
                Text("Orders found · \(model.amazonOrdersRead) across \(model.amazonPagesRead) pages")
                    .font(Theme.Font.caption).foregroundStyle(Theme.Text.tertiary).padding(.top, Theme.Spacing.s16)
            }
            Spacer()
            Button("Leave it running") { dismiss() }.buttonStyle(.secondary)
            Text("It carries on while you use Poise, and picks up where it stopped if you close the app.")
                .font(Theme.Font.caption).foregroundStyle(Theme.Text.tertiary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Theme.Spacing.s16)
    }

    /// Two phases: find the orders, then read what was in them. The second is the slow one — a page load each — so it
    /// counts orders rather than borrowing the first phase's bar.
    private var readingTitle: String {
        model.amazonItemsTotal > 0 ? "Reading what was in them…" : "Reading your Amazon orders…"
    }

    private var readingProgress: Double {
        guard model.amazonItemsTotal > 0 else { return model.amazonProgress }
        return Double(model.amazonItemsDone) / Double(model.amazonItemsTotal)
    }

    private var readingDetail: String {
        if model.amazonItemsTotal > 0 { return "\(model.amazonItemsDone) of \(model.amazonItemsTotal) orders" }
        return backTo
    }

    private var backTo: String {
        guard let back = model.amazonReadingBackTo else { return "Matching them to the charges Poise already has." }
        return "Back to \(back.formatted(.dateTime.month(.abbreviated).day())) so far"
    }

    // MARK: what it matched

    private var done: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.s16) {
                IconCircle(symbol: "checkmark", size: 56, fill: Theme.Status.goodBg, color: Theme.Status.good)
                Text(headline).font(Theme.Font.titleLG).foregroundStyle(Theme.Text.primary)
                Text(subhead).font(Theme.Font.verdictMD).foregroundStyle(Theme.Text.secondary)
                if model.amazonMatched > 0 {
                    Card(padding: Theme.Spacing.s16) {
                        VStack(alignment: .leading, spacing: Theme.Spacing.s16) {
                            Text("WHAT THIS CHANGES").font(Theme.Font.caption2Strong).foregroundStyle(Theme.Text.tertiary)
                            promise("Every charge opens its order in Amazon", "One tap from the charge to the thing you bought.")
                            promise("Poise keeps up on its own", "New Amazon charges arrive with their order, without you doing anything.")
                        }
                    }
                }
                Text("Amazon signs you out every few weeks. Poise will say so and ask you to sign in again — nothing breaks in the meantime.")
                    .font(Theme.Font.caption).foregroundStyle(Theme.Text.tertiary)
                Button("Done") { dismiss() }.buttonStyle(.primary)
            }
            .padding(.horizontal, Theme.Spacing.s16).padding(.vertical, Theme.Spacing.s8)
        }
    }

    private var headline: String {
        let matched = model.amazonMatched
        guard matched > 0 else { return "Nothing to match yet" }
        return "\(model.amazonCharges) charges, \(matched) orders"
    }

    private var subhead: String {
        let matched = model.amazonMatched, charges = model.amazonCharges, read = model.amazonOrdersRead
        // "Found nothing" and "found plenty, matched nothing" are different faults and shouldn't wear the same sentence.
        if read == 0 { return "Poise reached your payments page but couldn't find any orders on it. Nothing has changed." }
        if model.amazonLapsed { return "Amazon asked you to sign in again part way through, so this read stopped early — \(read) orders. Sign in again to finish it." }
        if matched == 0 { return "Poise read \(read) orders across \(model.amazonPagesRead) pages, but none lined up with a charge." }
        if matched >= charges { return "Every Amazon charge Poise holds found its order." }
        return "Read \(read) orders across \(model.amazonPagesRead) pages. Amazon's list only goes back about three months — older charges, Whole Foods in store, Prime and anything bought with points can't be matched from it."
    }
}

/// The one web view the session lives in, shown as-is.
private struct AmazonWebView: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView { AmazonSource.shared.webView }
    func updateUIView(_ web: WKWebView, context: Context) {}
}

/// The connection itself: how fresh it is, signing in again when Amazon drops it, and disconnecting. Figma §28.
struct AmazonConnectionView: View {
    @Environment(AppModel.self) private var model
    @State private var signIn = false
    @State private var confirmDisconnect = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                if model.amazonLapsed {
                    Card(padding: Theme.Spacing.s16) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Amazon signed you out").font(Theme.Font.headline).foregroundStyle(Theme.Text.primary)
                            Text("It asks for a fresh sign-in roughly every hour, so a later check stops part way. Sign in again and the rest fills in.")
                                .font(Theme.Font.footnote).foregroundStyle(Theme.Text.secondary)
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.s16).padding(.top, Theme.Spacing.s16)
                }
                SectionHeader(title: "Connection")
                Card {
                    row("Status", model.amazonLapsed ? "Signed out" : model.amazonConnected ? "Connected" : "Not connected")
                    RowDivider()
                    row("Last checked", model.amazonCheckedAt.map(\.sinceLabel) ?? "Never")
                    RowDivider()
                    row("Charges with an order", "\(model.amazonMatched) of \(model.amazonCharges)")
                    RowDivider()
                    row("Orders seen", model.amazonOrdersRead == 0 ? "None yet" : "\(model.amazonOrdersRead) across \(model.amazonPagesRead) pages")
                    if model.amazonItemsWanted > 0 {
                        RowDivider()
                        // The two phases fail for different reasons, so each reports its own result.
                        row("Contents read", "\(model.amazonItemsRead) of \(model.amazonItemsWanted)")
                        if let why = model.amazonItemsFailure {
                            Text(why).font(Theme.Font.caption).foregroundStyle(Theme.Text.tertiary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, Theme.Spacing.s16).padding(.bottom, Theme.Spacing.s8)
                        }
                    }
                    if let back = model.amazonReachedBack {
                        RowDivider()
                        row("Reached back to", back.formatted(.dateTime.month(.abbreviated).day().year()))
                    }
                }
                .padding(.horizontal, Theme.Spacing.s16)
                VStack(spacing: Theme.Spacing.s12) {
                    if model.amazonConnected, !model.amazonLapsed {
                        // Always a catch-up read: it walks back to the oldest charge still missing an order, so a
                        // connection that fell behind is one tap from whole.
                        Button(model.amazonReading ? "Checking…" : "Check now") { Task { await model.syncAmazon(deep: true) } }
                            .buttonStyle(.secondary).disabled(model.amazonReading)
                        if model.amazonReading {
                            ProgressTrack(value: model.amazonItemsTotal > 0
                                          ? Double(model.amazonItemsDone) / Double(model.amazonItemsTotal)
                                          : model.amazonProgress)
                            Text(model.amazonItemsTotal > 0
                                 ? "Reading what was in them · \(model.amazonItemsDone) of \(model.amazonItemsTotal)"
                                 : backTo)
                                .font(Theme.Font.caption).foregroundStyle(Theme.Text.tertiary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    } else {
                        Button(model.amazonLapsed ? "Sign in to Amazon again" : "Connect Amazon") { signIn = true }.buttonStyle(.primary)
                    }
                    if model.amazonConnected {
                        Button("Disconnect Amazon") { confirmDisconnect = true }.buttonStyle(.ghost(Theme.Status.heads))
                    }
                }
                .padding(.horizontal, Theme.Spacing.s16).padding(.top, Theme.Spacing.s16)
                Text("Poise reads one page — the amount, date and order number of your Amazon charges. Disconnecting forgets the session and every order number with it. Your charges stay exactly as they are.")
                    .font(Theme.Font.caption).foregroundStyle(Theme.Text.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Theme.Spacing.s16).padding(.top, Theme.Spacing.s8)
            }
            .padding(.bottom, Theme.Spacing.s32)
        }
        .background(Theme.Bg.base)
        .navigationTitle("Amazon")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $signIn) { AmazonConnectView(startSignedOut: model.amazonLapsed) }
        .confirmationDialog("Disconnect Amazon?", isPresented: $confirmDisconnect, titleVisibility: .visible) {
            Button("Disconnect", role: .destructive) { Task { await model.disconnectAmazon() } }
        } message: {
            Text("Poise forgets the sign-in and the \(model.amazonMatched) order numbers it found.")
        }
    }

    private var backTo: String {
        guard let back = model.amazonReadingBackTo else { return "Reading your Amazon orders…" }
        return "Back to \(back.formatted(.dateTime.month(.abbreviated).day())) so far"
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(Theme.Font.body).foregroundStyle(Theme.Text.primary)
            Spacer()
            Text(value).font(Theme.Font.body).foregroundStyle(Theme.Text.secondary)
        }
        .padding(.horizontal, Theme.Spacing.s16).frame(minHeight: 44)
    }
}
