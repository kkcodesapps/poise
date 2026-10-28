import SwiftUI
import CoreMotion
import PoiseKit

/// The look of a card. Neither Plaid nor Wallet hands over the issuer's artwork, so Poise draws each card in one of
/// its own finishes: the well-known cards something close to what's in your wallet, the rest a steady pick of the
/// others, and any of them whatever the user chooses instead.
enum CardFinish: String, CaseIterable, Identifiable, Sendable {
    // In the order the picker shows them, four families of four: metals, blues, greens, warm.
    case titanium, gold, rose, copper
    case sky, sapphire, midnight, graphite
    case lagoon, ocean, sage, forest
    case violet, plum, ruby, sunset

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    /// Lit corner first: the gradient runs from top-left to bottom-right.
    var colors: (Color, Color) {
        switch self {
        case .ocean: (Color(hex: 0x16707A), Color(hex: 0x0B2740))
        case .sapphire: (Color(hex: 0x2F4FA8), Color(hex: 0x0B1A44))
        case .sky: (Color(hex: 0x3D8BD9), Color(hex: 0x123E7A))
        case .forest: (Color(hex: 0x2F7D5B), Color(hex: 0x0D3326))
        case .plum: (Color(hex: 0x9A4577), Color(hex: 0x3A1532))
        case .graphite: (Color(hex: 0x2C2C30), Color(hex: 0x0E0E10))
        case .gold: (Color(hex: 0xE9CF8E), Color(hex: 0xA47A33))
        case .titanium: (Color(hex: 0xF6F6F8), Color(hex: 0xC4C7D0))
        case .rose: (Color(hex: 0xF2CDBF), Color(hex: 0xB5796A))
        case .copper: (Color(hex: 0xB86A3C), Color(hex: 0x4E2412))
        case .midnight: (Color(hex: 0x232A4D), Color(hex: 0x07080F))
        case .lagoon: (Color(hex: 0x22948A), Color(hex: 0x0C4048))
        case .sage: (Color(hex: 0x6E8A72), Color(hex: 0x2C3D31))
        case .violet: (Color(hex: 0x6B4FD1), Color(hex: 0x241356))
        case .ruby: (Color(hex: 0xB3263E), Color(hex: 0x4A0A18))
        case .sunset: (Color(hex: 0xD9603F), Color(hex: 0x7A1F3D))
        }
    }
    /// The pale metals take dark type; everything else white.
    var isLight: Bool { self == .gold || self == .titanium || self == .rose }
    var ink: Color {
        switch self {
        case .gold: Color(hex: 0x2B1F0A)
        case .titanium: Color(hex: 0x1C1C1E)
        case .rose: Color(hex: 0x3A1F17)
        default: .white
        }
    }
    /// The chip a finish comes with: silver on titanium, gold on everything else.
    var chip: CardChipMetal { self == .titanium ? .silver : .gold }
    /// What the shadow is tinted with: the deeper of the two colours on a pale card, the lit one on a dark card.
    var glow: Color { isLight ? colors.1 : colors.0 }
    var gradient: LinearGradient { LinearGradient(colors: [colors.0, colors.1], startPoint: .topLeading, endPoint: .bottomTrailing) }

    /// The issuer's own look, for the cards anyone would recognise.
    static func issuer(_ account: Account) -> CardFinish? {
        let n = "\(account.bankName ?? account.name) \(account.institution ?? "")".lowercased()
        if n.contains("apple") { return .titanium }
        if n.contains("prime") || n.contains("amazon") { return .ocean }
        if n.contains("sapphire") { return .sapphire }
        if n.contains("freedom") || n.contains("barclays") { return .sky }
        if n.contains("robinhood") || n.contains("gold") { return .gold }
        if n.contains("platinum") || n.contains("american express") || n.contains("amex") { return .titanium }
        return nil
    }

    /// Poise's pick for every card. Cards it can't place get one of the deeper finishes, stable across launches, and
    /// two cards the bank calls the same thing never get the same one — three "Ultimate Rewards" have to be told apart.
    static func defaults(for accounts: [Account]) -> [String: CardFinish] {
        let rest: [CardFinish] = [.sapphire, .graphite, .forest, .plum]
        var out: [String: CardFinish] = [:], taken: [String: Set<CardFinish>] = [:]
        for a in accounts.sorted(by: { $0.id < $1.id }) {
            let key = (a.bankName ?? a.name).lowercased()
            var f = issuer(a)
            if f == nil || taken[key, default: []].contains(f!) {
                let seed = a.id.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
                let order = (0..<rest.count).map { rest[(abs(seed) + $0) % rest.count] }
                f = order.first { !taken[key, default: []].contains($0) } ?? order[0]
            }
            out[a.id] = f; taken[key, default: []].insert(f!)
        }
        return out
    }
}

/// The chip's metal, which the user can pick apart from the finish.
enum CardChipMetal: String, CaseIterable, Identifiable, Sendable {
    case gold, silver, rose, black

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    /// Lit corner first, like the finishes.
    var colors: [Color] {
        switch self {
        case .gold: [Color(hex: 0xEAD7A4), Color(hex: 0xB48E4E)]
        case .silver: [Color(hex: 0xECECEF), Color(hex: 0xA7AAB4)]
        case .rose: [Color(hex: 0xF0C7B6), Color(hex: 0xB07A66)]
        case .black: [Color(hex: 0x4A4A50), Color(hex: 0x1A1A1E)]
        }
    }
    /// The contact lines: dark on the bright metals, light on black so they don't vanish.
    var line: Color {
        switch self {
        case .gold: Color(hex: 0x402E0D).opacity(0.28)
        case .silver: Color(hex: 0x2A2C33).opacity(0.28)
        case .rose: Color(hex: 0x3A1F17).opacity(0.28)
        case .black: Color.white.opacity(0.16)
        }
    }
}

extension AppModel {
    /// The finish a card is drawn in: the user's choice, else Poise's pick.
    func finish(for account: Account) -> CardFinish {
        account.finish.flatMap(CardFinish.init(rawValue:)) ?? CardFinish.defaults(for: cards)[account.id] ?? CardFinish.issuer(account) ?? .graphite
    }
    /// The card's chip: the user's choice, else the one its finish comes with.
    func chip(for account: Account) -> CardChipMetal {
        account.chip.flatMap(CardChipMetal.init(rawValue:)) ?? finish(for: account).chip
    }
}

/// How the phone is tilted, for the light on the cards. One motion stream however many cards are on screen, running
/// only while one is.
@MainActor @Observable final class Tilt {
    static let shared = Tilt()
    private(set) var x: Double = 0
    private(set) var y: Double = 0
    @ObservationIgnored private let motion = CMMotionManager()
    @ObservationIgnored private var users = 0

    func begin() {
        users += 1
        guard users == 1, motion.isDeviceMotionAvailable else { return }
        motion.deviceMotionUpdateInterval = 1.0 / 30
        motion.startDeviceMotionUpdates(to: .main) { [weak self] m, _ in
            guard let m else { return }
            // Held in the hand the phone leans back about 40°; that's the rest position.
            let roll = max(-1, min(1, m.attitude.roll / 0.6)), pitch = max(-1, min(1, (m.attitude.pitch - 0.7) / 0.6))
            MainActor.assumeIsolated {
                guard let self else { return }
                self.x = self.x * 0.8 + roll * 0.2
                self.y = self.y * 0.8 + pitch * 0.2
            }
        }
    }

    func end() {
        users = max(0, users - 1)
        if users == 0 { motion.stopDeviceMotionUpdates() }
    }
}

/// A fine tile of grain, made once. It's what keeps a gradient from looking like a gradient.
@MainActor private let grain: UIImage = {
    let size = 96
    var seed: UInt64 = 0x9E3779B97F4A7C15     // fixed, so the grain is the same every launch
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size), format: { let f = UIGraphicsImageRendererFormat(); f.scale = 1; return f }())
    return renderer.image { ctx in
        for y in 0..<size {
            for x in 0..<size {
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                let v = CGFloat((seed >> 33) & 0xFF) / 255
                ctx.cgContext.setFillColor(gray: v, alpha: 1)
                ctx.cgContext.fill(CGRect(x: x, y: y, width: 1, height: 1))
            }
        }
    }
}()

/// The light across a card: one soft diagonal band that slides as the phone tilts.
private struct Sheen: View {
    let finish: CardFinish
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        let t = Tilt.shared, dx = reduceMotion ? 0 : t.x * 0.35, dy = reduceMotion ? 0 : t.y * 0.25
        let peak = finish.isLight ? 0.55 : 0.16, tail = finish.isLight ? 0.25 : 0.05
        LinearGradient(stops: [.init(color: .white.opacity(0), location: 0.2), .init(color: .white.opacity(peak), location: 0.46),
                               .init(color: .white.opacity(tail), location: 0.54), .init(color: .white.opacity(0), location: 0.8)],
                       startPoint: UnitPoint(x: -0.1 + dx, y: dy), endPoint: UnitPoint(x: 1.1 + dx, y: 1 + dy))
    }
}

/// The card itself: its finish, grain, the light across it, a lit top edge and a shadow in its own colour.
struct CardFace<Content: View>: View {
    let finish: CardFinish
    var radius: CGFloat = 18
    var large = true
    @ViewBuilder var content: Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background {
                ZStack {
                    finish.gradient
                    Image(uiImage: grain).resizable(resizingMode: .tile).interpolation(.none)
                        .blendMode(finish.isLight ? .multiply : .screen).opacity(finish.isLight ? 0.05 : 0.07)
                    Sheen(finish: finish)
                }
            }
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(LinearGradient(stops: [.init(color: .white.opacity(finish.isLight ? 0.9 : 0.42), location: 0),
                                                          .init(color: .white.opacity(0.08), location: 0.5),
                                                          .init(color: .black.opacity(finish.isLight ? 0.1 : 0.25), location: 1)],
                                                  startPoint: .top, endPoint: .bottom), lineWidth: 1)
            }
            .foregroundStyle(finish.ink)
            .shadow(color: .black.opacity(0.22), radius: 1, y: 1)
            .shadow(color: finish.glow.opacity(0.26), radius: large ? 15 : 8, y: large ? 14 : 8)
            .onAppear { if !reduceMotion { Tilt.shared.begin() } }
            .onDisappear { if !reduceMotion { Tilt.shared.end() } }
    }
}

/// The chip, drawn: a small metal plate with its contact lines.
struct CardChip: View {
    let metal: CardChipMetal
    var body: some View {
        let line = metal.line
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(LinearGradient(colors: metal.colors, startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay {
                GeometryReader { g in
                    let w = g.size.width, h = g.size.height
                    Path { p in
                        p.move(to: .init(x: w * 0.34, y: 0)); p.addLine(to: .init(x: w * 0.34, y: h))
                        p.move(to: .init(x: w * 0.66, y: 0)); p.addLine(to: .init(x: w * 0.66, y: h))
                        p.move(to: .init(x: 0, y: h / 2)); p.addLine(to: .init(x: w * 0.34, y: h / 2))
                        p.move(to: .init(x: w * 0.66, y: h / 2)); p.addLine(to: .init(x: w, y: h / 2))
                    }
                    .stroke(line, lineWidth: 0.75)
                    RoundedRectangle(cornerRadius: 2).stroke(line, lineWidth: 0.75)
                        .frame(width: w * 0.32, height: h * 0.42).position(x: w / 2, y: h / 2)
                }
            }
            .overlay { RoundedRectangle(cornerRadius: 5, style: .continuous).stroke(.black.opacity(0.18), lineWidth: 0.5) }
            .frame(width: 32, height: 24)
            .accessibilityHidden(true)
    }
}

/// The big card: name and bank, chip, what's owed, what's due and the last four. On the card's page and in Look & name.
struct CardHero: View {
    @Environment(AppModel.self) private var model
    let card: Account
    var name: String? = nil
    var finish: CardFinish? = nil
    var chip: CardChipMetal? = nil

    var body: some View {
        let f = finish ?? model.finish(for: card)
        CardFace(finish: f) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text(name ?? card.name).font(.system(size: 16, weight: .semibold)).lineLimit(1)
                    Spacer(minLength: 8)
                    if let institution = card.institution { Text(institution).font(.system(size: 11, weight: .medium)).opacity(0.62).lineLimit(1) }
                }
                CardChip(metal: chip ?? (finish == nil ? model.chip(for: card) : f.chip)).padding(.top, 14)
                Spacer(minLength: 0)
                Text(card.hidden ? "Not counted" : "Owed").font(Theme.Font.captionStrong).opacity(0.66)
                Text(card.owed.money2).font(Theme.Font.moneyLG).minimumScaleFactor(0.7).lineLimit(1)
                Spacer(minLength: 0)
                HStack {
                    if let due = dueLine {
                        Text(due).font(Theme.Font.captionStrong).opacity(0.92).lineLimit(1)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(f.isLight ? Color.black.opacity(0.07) : Color.white.opacity(0.15), in: Capsule())
                    }
                    Spacer(minLength: 8)
                    if let mask = card.mask { Text("••••  \(mask)").font(.system(size: 13, weight: .medium).monospacedDigit()).tracking(1).opacity(0.82) }
                }
            }
            .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 16)
        }
        .aspectRatio(329.0 / 207.0, contentMode: .fit)
        .accessibilityElement(children: .combine)
    }

    /// "$4,020.25 due Thu, Oct 22" — what the forecast will take, and when, in the card's own words.
    private var dueLine: String? {
        guard let due = card.nextDue(now: .now) else { return nil }
        let day = due.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        guard let amount = card.statementPayment(default: model.settings.newCardsPay) else { return "Due \(day)" }
        return "\(amount.money2) due \(day)"
    }
}

// MARK: - Home

/// Home's row of cards: each in its finish, with this month against last. Tap opens it; press and hold for Look & name.
struct CardStrip: View {
    @Environment(AppModel.self) private var model
    let onOpen: (String) -> Void

    var body: some View {
        let cards = model.cards
        let spent = Dictionary(uniqueKeysWithValues: cards.map { ($0.id, model.monthSpend(account: $0.id)) })
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Your cards").font(Theme.Font.headline).foregroundStyle(Theme.Text.primary)
                Spacer()
                Text("\(spent.values.reduce(0, +).money) this month").font(Theme.Font.footnote).foregroundStyle(Theme.Text.secondary)
            }
            .padding(.horizontal, 4)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(cards) { card in
                        CardTile(card: card, spent: spent[card.id] ?? 0, last: model.lastMonthSpend(account: card.id)) { onOpen(card.id) }
                    }
                }
                .padding(.top, 6).padding(.bottom, 14)
            }
            .contentMargins(.horizontal, Theme.Spacing.s16, for: .scrollContent)
            .padding(.horizontal, -Theme.Spacing.s16)
            .scrollClipDisabled()
        }
        .padding(.top, Theme.Spacing.s8)
    }
}

/// One small card on Home. A thin bar shows how far into last month's total this month has got; past it, the bar
/// runs full with a mark where last month ended.
private struct CardTile: View {
    @Environment(AppModel.self) private var model
    let card: Account
    let spent: Decimal
    let last: Decimal
    let onOpen: () -> Void
    @State private var pressed = false
    @State private var held = 0

    var body: some View {
        let f = model.finish(for: card)
        CardFace(finish: f, radius: 13, large: false) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(card.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    Spacer(minLength: 4)
                    if let mask = card.mask { Text("••\(mask)").font(.system(size: 10, weight: .medium).monospacedDigit()).opacity(0.66) }
                }
                Text(spent.money).font(.system(size: 20, weight: .semibold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.7).padding(.top, 6)
                HStack {
                    Text("this month")
                    Spacer(minLength: 4)
                    Text("\(lastMonthName) \(last.money)")
                }
                .font(.system(size: 10)).opacity(0.66).lineLimit(1).padding(.top, 1)
                Spacer(minLength: 0)
                bar(f)
            }
            .padding(.horizontal, 12).padding(.top, 11).padding(.bottom, 15)
        }
        .frame(width: 150, height: 96)
        .scaleEffect(pressed ? 0.97 : 1)
        .animation(.snappy(duration: 0.15), value: pressed)
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .onLongPressGesture(minimumDuration: 0.4) { held += 1; model.lookCard = card.id } onPressingChanged: { pressed = $0 }
        .sensoryFeedback(.impact(weight: .medium), trigger: held)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(card.name), \(spent.money) this month, \(last.money) in \(lastMonthName)")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Look & name") { model.lookCard = card.id }
    }

    private var lastMonthName: String {
        let start = Periods.shift(Periods.window(.month, containing: .now), .month, by: -1).start
        return start.formatted(.dateTime.month(.abbreviated))
    }

    private func bar(_ f: CardFinish) -> some View {
        let share = last > 0 ? Double(truncating: (spent / last) as NSDecimalNumber) : 0
        return GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(f.isLight ? Color.black.opacity(0.12) : Color.white.opacity(0.2))
                if share > 0 { Capsule().fill(f.ink.opacity(0.9)).frame(width: max(4, g.size.width * min(1, share))) }
            }
            .frame(height: 3)
            // The tick is an overlay so it can stand above and below the bar without making the bar itself taller.
            .overlay(alignment: .leading) {
                if share > 1 {
                    Capsule().fill(f.ink.opacity(0.9)).frame(width: 1.5, height: 8).offset(x: g.size.width / share - 0.75)
                }
            }
        }
        .frame(height: 3)
    }
}

/// Look & name: what the card is called, the finish it's drawn in and its chip, with a live preview.
struct CardLookSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let accountID: String
    @State private var name = ""
    @State private var finish: CardFinish = .graphite
    @State private var chip: CardChipMetal = .gold
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            ScrollView {
                if let card = model.account(id: accountID) {
                    let fallback = CardFinish.defaults(for: model.cards)[card.id] ?? .graphite
                    let bank = card.bankName ?? card.name
                    VStack(alignment: .leading, spacing: 24) {
                        CardHero(card: card, name: name.isEmpty ? bank : name, finish: finish, chip: chip).padding(.horizontal, Theme.Spacing.s16)
                        VStack(alignment: .leading, spacing: 8) {
                            label("NAME")
                            HStack {
                                TextField(bank, text: $name).font(Theme.Font.body).foregroundStyle(Theme.Text.primary)
                                    .textInputAutocapitalization(.words).submitLabel(.done)
                                if let mask = card.mask { Text("\(bank) ••\(mask)").font(Theme.Font.footnote).foregroundStyle(Theme.Text.tertiary).lineLimit(1) }
                            }
                            .padding(.horizontal, 14).padding(.vertical, 13)
                            .background(Theme.Bg.subtle, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            Text("Shown on Home, this page and every charge from this card.").font(Theme.Font.caption).foregroundStyle(Theme.Text.tertiary)
                        }
                        .padding(.horizontal, Theme.Spacing.s16)
                        VStack(alignment: .leading, spacing: 10) {
                            label("FINISH")
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: 4), spacing: 14) {
                                ForEach(CardFinish.allCases) { f in swatch(f) }
                            }
                        }
                        .padding(.horizontal, Theme.Spacing.s16)
                        VStack(alignment: .leading, spacing: 10) {
                            label("CHIP")
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: 4), spacing: 14) {
                                ForEach(CardChipMetal.allCases) { m in chipSwatch(m) }
                            }
                        }
                        .padding(.horizontal, Theme.Spacing.s16)
                        if finish != fallback || chip != fallback.chip || !(name.isEmpty || name == bank) {
                            Button { finish = fallback; chip = fallback.chip; name = "" } label: {
                                HStack {
                                    Text("Back to \(card.institution ?? "the bank")'s look").font(Theme.Font.body).foregroundStyle(Theme.Accent.default)
                                    Spacer(minLength: 8)
                                    Text("\(fallback.title), \(fallback.chip.rawValue) chip").font(Theme.Font.footnote).foregroundStyle(Theme.Text.tertiary).lineLimit(1)
                                }
                                .padding(.horizontal, 14).padding(.vertical, 13)
                                .background(Theme.Bg.subtle, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .buttonStyle(.plain).padding(.horizontal, Theme.Spacing.s16)
                        }
                        Text("Also: press and hold a card on Home.").font(Theme.Font.caption).foregroundStyle(Theme.Text.tertiary).padding(.horizontal, Theme.Spacing.s16)
                    }
                    .padding(.top, Theme.Spacing.s12).padding(.bottom, Theme.Spacing.s32)
                    .onAppear {
                        guard !loaded else { return }
                        loaded = true; name = card.nickname ?? ""; finish = model.finish(for: card); chip = model.chip(for: card)
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.Bg.elevated)
            .navigationTitle("Look & name")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        if let card = model.account(id: accountID) { Task { await model.setLook(nickname: name, finish: finish, chip: chip, for: card) } }
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .sensoryFeedback(.selection, trigger: finish)
            .sensoryFeedback(.selection, trigger: chip)
            // A chip left as the finish came with follows the finish; one picked on purpose stays put.
            .onChange(of: finish) { old, new in if chip == old.chip { chip = new.chip } }
        }
        .presentationDragIndicator(.visible)
    }

    private func label(_ s: String) -> some View { Text(s).font(Theme.Font.captionStrong).foregroundStyle(Theme.Text.tertiary) }

    /// A chip on a scrap of the card's current finish, so it's picked against what it'll sit on.
    private func chipSwatch(_ m: CardChipMetal) -> some View {
        let on = m == chip
        return Button { chip = m } label: {
            VStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(finish.gradient)
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(LinearGradient(colors: [.white.opacity(0.45), .black.opacity(0.2)], startPoint: .top, endPoint: .bottom), lineWidth: 1)
                    }
                    .overlay { CardChip(metal: m) }
                    .aspectRatio(74.0 / 47.0, contentMode: .fit)
                    .padding(3)
                    .overlay { if on { RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Theme.Accent.default, lineWidth: 2) } }
                Text(m.title).font(on ? Theme.Font.captionStrong : Theme.Font.caption).foregroundStyle(on ? Theme.Text.primary : Theme.Text.secondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(m.title) chip")
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func swatch(_ f: CardFinish) -> some View {
        let on = f == finish
        return Button { finish = f } label: {
            VStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(f.gradient)
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(LinearGradient(colors: [.white.opacity(0.45), .black.opacity(0.2)], startPoint: .top, endPoint: .bottom), lineWidth: 1)
                    }
                    .aspectRatio(74.0 / 47.0, contentMode: .fit)
                    .padding(3)
                    .overlay { if on { RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Theme.Accent.default, lineWidth: 2) } }
                Text(f.title).font(on ? Theme.Font.captionStrong : Theme.Font.caption).foregroundStyle(on ? Theme.Text.primary : Theme.Text.secondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(f.title)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

// MARK: - The card's page

/// Everything Poise shows for spending, for one card: where it went, where it was spent, and every charge. The card
/// sits at the top in its colours and the rest of your cards are a swipe away; its settings wait at the bottom.
struct CardPage: View {
    @Environment(AppModel.self) private var model
    @State private var current: String?
    @State private var allMerchants = false
    @State private var showLook = false

    init(accountID: String) { _current = State(initialValue: accountID) }

    /// The swipeable set. A card opened from somewhere else that isn't among them (hidden, say) still gets its page.
    private var cards: [Account] {
        let list = model.cards
        if let current, !list.contains(where: { $0.id == current }), let a = model.account(id: current) { return [a] + list }
        return list
    }
    private var account: Account? { current.flatMap { model.account(id: $0) } }

    var body: some View {
        @Bindable var model = model
        ScrollView {
            VStack(spacing: 0) {
                carousel
                if cards.count > 1 { dots }
                if let account {
                    let b = model.breakdown(account: account.id)
                    PeriodSwitch(period: $model.wherePeriod).padding(.horizontal, Theme.Spacing.s16).padding(.top, Theme.Spacing.s8)
                    stepper(b)
                    headline(b)
                    whereItWent(b, card: account)
                    merchants(card: account)
                    charges(b, card: account)
                    settings(account)
                }
            }
            .padding(.bottom, Theme.Spacing.s32)
        }
        .background(Theme.Bg.base)
        .navigationTitle(account?.name ?? "Card")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: current) { _, _ in allMerchants = false }
        .sheet(isPresented: $showLook) { if let current { CardLookSheet(accountID: current) } }
    }

    // MARK: Card

    private var carousel: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.s12) {
                ForEach(cards) { card in
                    face(card)
                        .containerRelativeFrame(.horizontal) { width, _ in width - (cards.count > 1 ? 64 : 32) }
                        .id(card.id)
                }
            }
            .scrollTargetLayout()
            .padding(.top, Theme.Spacing.s12).padding(.bottom, Theme.Spacing.s24)
        }
        .contentMargins(.horizontal, Theme.Spacing.s16, for: .scrollContent)
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $current)
        .scrollClipDisabled()
        .sensoryFeedback(.selection, trigger: current)
        .padding(.top, Theme.Spacing.s4)
    }

    private func face(_ card: Account) -> some View { CardHero(card: card) }

    private var dots: some View {
        HStack(spacing: 6) {
            ForEach(cards) { card in
                Circle().fill(card.id == current ? Theme.Text.primary : Theme.Text.tertiary.opacity(0.45)).frame(width: 6, height: 6)
            }
        }
        .animation(.snappy, value: current)
        .padding(.bottom, Theme.Spacing.s8)
    }

    // MARK: Spending

    private func stepper(_ b: Breakdown) -> some View {
        HStack {
            Button { model.stepWhere(-1) } label: { IconCircle(symbol: "chevron.left", size: 36, fill: Theme.Bg.subtle, color: Theme.Text.primary) }.buttonStyle(.plain)
            Spacer()
            VStack(spacing: 1) {
                Text(Periods.title(b.window, model.wherePeriod)).font(Theme.Font.titleSM).foregroundStyle(Theme.Text.primary)
                if model.whereIsCurrent { Text(soFar(b.window)).font(Theme.Font.caption).foregroundStyle(Theme.Text.tertiary) }
            }
            Spacer()
            Button { model.stepWhere(1) } label: { IconCircle(symbol: "chevron.right", size: 36, fill: Theme.Bg.subtle, color: model.whereIsCurrent ? Theme.Text.tertiary : Theme.Text.primary) }
                .buttonStyle(.plain).disabled(model.whereIsCurrent)
        }
        .padding(.horizontal, Theme.Spacing.s16).padding(.top, Theme.Spacing.s8).padding(.bottom, 4)
    }

    /// "Oct 1 – 22 · so far": the period isn't over, and this is how much of it there's been.
    private func soFar(_ window: DateInterval) -> String {
        guard model.wherePeriod != .year else { return "so far" }
        let start = window.start.formatted(.dateTime.month(.abbreviated).day())
        let today = Calendar.current.isDate(window.start, equalTo: .now, toGranularity: .month)
            ? Date.now.formatted(.dateTime.day()) : Date.now.formatted(.dateTime.month(.abbreviated).day())
        return "\(start) – \(today) · so far"
    }

    private func headline(_ b: Breakdown) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(b.total.money).font(Theme.Font.moneyXL).foregroundStyle(Theme.Text.primary).contentTransition(.numericText())
            HStack(spacing: 8) {
                Text("spent on this card").font(Theme.Font.subhead).foregroundStyle(Theme.Text.secondary)
                if b.previousTotal > 0, b.delta != 0 {
                    let less = b.delta < 0
                    Text("\((less ? -b.delta : b.delta).money) \(less ? "less" : "more") than \(previousName(b.window))")
                        .font(Theme.Font.captionStrong).foregroundStyle(less ? Theme.Status.good : Theme.Status.track).lineLimit(1)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(less ? Theme.Status.goodBg : Theme.Status.trackBg, in: Capsule())
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.Spacing.s16).padding(.horizontal, 4).padding(.top, Theme.Spacing.s8)
        .animation(.snappy, value: b.total)
    }

    /// The period before, by name where it has one: "September", "2025", "last week".
    private func previousName(_ window: DateInterval) -> String {
        let prev = Periods.shift(window, model.wherePeriod, by: -1)
        switch model.wherePeriod {
        case .week: return "last week"
        case .month: return prev.start.formatted(.dateTime.month(.wide))
        case .year: return prev.start.formatted(.dateTime.year())
        }
    }

    private struct Slice: Identifiable { let id: String; let name: String; let count: Int; let amount: Decimal; let share: Double; let color: Color; let categoryID: String? }

    /// The three biggest categories, and the rest together: four colours are as many as a bar can carry and still be read.
    private func slices(_ b: Breakdown) -> [Slice] {
        let colors = [Theme.Accent.default, Theme.Status.heads, Theme.Status.good]
        var out = b.rows.prefix(3).enumerated().map { i, r in Slice(id: r.categoryID, name: r.name, count: r.count, amount: r.amount, share: r.share, color: colors[i], categoryID: r.categoryID) }
        let rest = b.rows.dropFirst(3)
        if !rest.isEmpty {
            out.append(Slice(id: "rest", name: rest.count == 1 ? rest.first!.name : "Everything else", count: rest.reduce(0) { $0 + $1.count },
                             amount: rest.reduce(0) { $0 + $1.amount }, share: rest.reduce(0) { $0 + $1.share }, color: Theme.Text.tertiary,
                             categoryID: rest.count == 1 ? rest.first!.categoryID : nil))
        }
        return out
    }

    @ViewBuilder private func whereItWent(_ b: Breakdown, card: Account) -> some View {
        let parts = slices(b)
        SectionHeader(title: "Where it went")
        Card {
            if parts.isEmpty {
                Text("Nothing spent on \(card.name) in this \(model.wherePeriod == .week ? "week" : model.wherePeriod == .month ? "month" : "year").")
                    .font(Theme.Font.subhead).foregroundStyle(Theme.Text.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(Theme.Spacing.s16)
            } else {
                GeometryReader { geo in
                    let gaps = CGFloat(parts.count - 1) * 3
                    HStack(spacing: 3) {
                        ForEach(parts) { p in Rectangle().fill(p.color).frame(width: max(3, (geo.size.width - gaps) * p.share)) }
                    }
                }
                .frame(height: 12).clipShape(Capsule())
                .padding(.horizontal, Theme.Spacing.s16).padding(.top, Theme.Spacing.s16).padding(.bottom, Theme.Spacing.s8)
                ForEach(Array(parts.enumerated()), id: \.element.id) { i, p in
                    if let id = p.categoryID {
                        NavigationLink { CategoryDetailView(categoryID: id, accountID: card.id) } label: { sliceRow(p, chevron: true) }.buttonStyle(.plain)
                    } else {
                        sliceRow(p, chevron: false)
                    }
                    if i < parts.count - 1 { Divider().overlay(Theme.Border.subtle).padding(.leading, 38) }
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.s16)
        .animation(.snappy, value: b.total)
    }

    private func sliceRow(_ p: Slice, chevron: Bool) -> some View {
        HStack(spacing: Theme.Spacing.s12) {
            Circle().fill(p.color).frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 1) {
                Text(p.name).font(Theme.Font.body.weight(.medium)).foregroundStyle(Theme.Text.primary).lineLimit(1)
                Text("\(p.count) charge\(p.count == 1 ? "" : "s") · \(p.share.percent)").font(Theme.Font.footnote).foregroundStyle(Theme.Text.secondary)
            }
            Spacer(minLength: 8)
            Text(p.amount.money).font(Theme.Font.moneySM).foregroundStyle(Theme.Text.primary)
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.Text.tertiary).opacity(chevron ? 1 : 0)
        }
        .padding(.horizontal, Theme.Spacing.s16).padding(.vertical, Theme.Spacing.s12)
        .contentShape(Rectangle())
    }

    @ViewBuilder private func merchants(card: Account) -> some View {
        let all = CategoryBreakdown.merchants(transactions: model.transactions(on: card.id), window: model.whereWindow, categories: model.categories)
        if !all.isEmpty {
            let shown = Array(all.prefix(allMerchants ? 12 : 3))
            SectionHeader(title: "Merchants", action: all.count > 3 ? (allMerchants ? "Show fewer" : "See all \(all.count)") : nil) {
                withAnimation(.snappy) { allMerchants.toggle() }
            }
            Card {
                ForEach(Array(shown.enumerated()), id: \.element.id) { i, m in
                    Button { model.selectedMerchant = .init(key: PoiseKit.Transaction.merchantKey(m.name)) } label: {
                        HStack(spacing: Theme.Spacing.s12) {
                            ZStack { Circle().fill(Theme.Bg.subtle); Text("\(i + 1)").font(Theme.Font.captionStrong).foregroundStyle(Theme.Text.secondary) }.frame(width: 28, height: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(m.name.prettyMerchant).font(Theme.Font.headline).foregroundStyle(Theme.Text.primary).lineLimit(1)
                                Text("\(m.count) charge\(m.count == 1 ? "" : "s")\(m.count > 1 ? " · avg \(m.average.money)" : "")").font(Theme.Font.footnote).foregroundStyle(Theme.Text.secondary)
                            }
                            Spacer()
                            Text(m.amount.money).font(Theme.Font.moneyMD).foregroundStyle(Theme.Text.primary)
                        }
                        .padding(.vertical, Theme.Spacing.s12).padding(.horizontal, Theme.Spacing.s16).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if i < shown.count - 1 { RowDivider() }
                }
            }
            .padding(.horizontal, Theme.Spacing.s16)
        }
    }

    @ViewBuilder private func charges(_ b: Breakdown, card: Account) -> some View {
        // The feed's rows, so a card payment reads once and Amazon rows still say what was in the order. No card name
        // on them: it's this card, every one.
        let rows = model.feed.filter { $0.accountID == card.id && b.window.holds($0.displayDate) }
        if !rows.isEmpty {
            SectionHeader(title: "Charges · \(b.count)")
            Feed(transactions: rows, accounts: [], today: model.today) { model.selectedTransaction = $0 }
                .padding(.horizontal, Theme.Spacing.s16)
        }
    }

    @ViewBuilder private func settings(_ card: Account) -> some View {
        SectionHeader(title: "This card")
        Card {
            Button { showLook = true } label: { navRow("Look & name", value: model.finish(for: card).title) }.buttonStyle(.plain)
            RowDivider().padding(.leading, -52)
            if card.statementDue != nil {
                NavigationLink { CardPaymentView(accountID: card.id) } label: { navRow("How you pay it", value: (card.pays ?? model.settings.newCardsPay).shortTitle) }.buttonStyle(.plain)
                RowDivider().padding(.leading, -52)
            }
            NavigationLink { AccountView(accountID: card.id, showsPayment: false) } label: { navRow("Counts as, visibility & disconnect", value: nil) }.buttonStyle(.plain)
        }
        .padding(.horizontal, Theme.Spacing.s16)
    }

    private func navRow(_ label: String, value: String?) -> some View {
        HStack {
            Text(label).font(Theme.Font.body).foregroundStyle(Theme.Text.primary)
            Spacer(minLength: 8)
            if let value { Text(value).font(Theme.Font.body).foregroundStyle(Theme.Text.secondary) }
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.Text.tertiary)
        }
        .padding(.horizontal, Theme.Spacing.s16).frame(minHeight: 44).contentShape(Rectangle())
    }
}

/// The statement, and the choice of how it gets paid — the half of a card's settings that changes the forecast.
struct CardPaymentView: View {
    @Environment(AppModel.self) private var model
    let accountID: String

    var body: some View {
        ScrollView {
            if let account = model.account(id: accountID) {
                VStack(spacing: 0) {
                    StatementSection(account: account)
                    SectionHeader(title: "How you pay it")
                    PayChoice(account: account)
                }
                .padding(.bottom, Theme.Spacing.s32)
            }
        }
        .background(Theme.Bg.base)
        .navigationTitle("How you pay it")
        .navigationBarTitleDisplayMode(.inline)
    }
}
