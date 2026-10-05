import SwiftUI
import PoiseKit

/// Profile → Categories: yours first, then the nine built-ins. Built-ins can be re-lensed, never deleted.
struct CategoriesView: View {
    @Environment(AppModel.self) private var model
    @State private var editing: PoiseKit.Category?
    @State private var creating = false

    private func meta(_ c: PoiseKit.Category) -> String {
        let year = Calendar.current.dateInterval(of: .year, for: .now)!
        let rows = model.transactions.filter { year.holds($0.displayDate) && ($0.kind == .spend || $0.kind == .untracked) && model.categories.resolve($0.categoryID).id == c.id }
        let top = Dictionary(grouping: rows) { $0.merchantKey }.values.sorted { $0.count > $1.count }.prefix(3).map { $0[0].displayMerchant }
        return "\(rows.count) charge\(rows.count == 1 ? "" : "s") this year" + (top.isEmpty ? "" : " · " + top.joined(separator: ", "))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                SectionHeader(title: "Yours")
                if model.categories.custom.isEmpty {
                    Card { EmptyStateView(symbol: "tag", title: "No categories of your own yet", body: "Add one for anything the nine built-ins don't capture — Kids, Pets, Business.") }.padding(.horizontal, Theme.Spacing.s16)
                } else {
                    list(model.categories.custom)
                }
                Button { creating = true } label: {
                    HStack(spacing: 10) { Image(systemName: "plus").font(.system(size: 15, weight: .semibold)); Text("New category").font(Theme.Font.headline) }
                        .foregroundStyle(Theme.Accent.default).frame(maxWidth: .infinity, minHeight: 50)
                        .background(Theme.Bg.subtle, in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous).strokeBorder(Theme.Border.subtle))
                }
                .buttonStyle(.plain).padding(.horizontal, Theme.Spacing.s16).padding(.top, Theme.Spacing.s12)
                SectionHeader(title: "Built in")
                list(model.categories.builtIns)
                Text("Every charge is filed into a built-in automatically from the bank's category. Yours fill through rules and your own corrections.")
                    .font(Theme.Font.caption).foregroundStyle(Theme.Text.tertiary).multilineTextAlignment(.center).padding(Theme.Spacing.s16)
            }
            .padding(.bottom, Theme.Spacing.s32)
        }
        .background(Theme.Bg.base)
        .navigationTitle("Categories")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { c in CategoryEditView(category: c) { _ in } }
        .sheet(isPresented: $creating) { CategoryEditView { _ in } }
        .onAppear { if model.newCategoryOnLaunch { model.newCategoryOnLaunch = false; creating = true } }
    }

    private func list(_ cats: [PoiseKit.Category]) -> some View {
        Card {
            ForEach(Array(cats.enumerated()), id: \.element.id) { i, c in
                Button { editing = c } label: {
                    HStack(spacing: Theme.Spacing.s12) {
                        IconCircle(symbol: c.symbol, fill: c.lens == .wants ? Theme.Accent.subtle : c.lens == .kept ? Theme.Status.goodBg : Theme.Bg.subtle, color: c.lens == .wants ? Theme.Accent.default : c.lens == .kept ? Theme.Status.good : Theme.Text.primary)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 8) {
                                Text(c.name).font(Theme.Font.headline).foregroundStyle(Theme.Text.primary)
                                if !c.builtIn { Text("YOURS").font(Theme.Font.caption2Strong).foregroundStyle(Theme.Accent.default).padding(.horizontal, 6).padding(.vertical, 2).background(Theme.Accent.subtle, in: Capsule()) }
                            }
                            Text(meta(c)).font(Theme.Font.footnote).foregroundStyle(Theme.Text.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        Text(c.lens.rawValue.uppercased()).font(Theme.Font.caption2Strong).foregroundStyle(c.lens == .wants ? Theme.Accent.default : c.lens == .kept ? Theme.Status.good : Theme.Text.tertiary)
                        Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.Text.tertiary)
                    }
                    .padding(.vertical, Theme.Spacing.s12).padding(.horizontal, Theme.Spacing.s16).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if i < cats.count - 1 { RowDivider() }
            }
        }
        .padding(.horizontal, Theme.Spacing.s16)
    }
}

/// New or existing category: name, icon, lens, and (for new ones) merchants to start with.
struct CategoryEditView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var category: PoiseKit.Category? = nil
    var startWith: String? = nil
    var onSave: (PoiseKit.Category) -> Void

    @State private var name = ""
    @State private var symbol = "tag"
    @State private var lens: Lens = .wants
    @State private var picked: Set<String> = []
    @State private var confirmDelete = false

    /// Grouped so a name suggests a glyph. Filtered at runtime to what this iOS actually ships, so nothing renders blank.
    static let iconGroups: [(title: String, symbols: [String])] = [
        ("Money", ["tag", "banknote", "creditcard", "dollarsign.circle", "percent", "chart.pie", "chart.bar", "chart.line.uptrend.xyaxis", "building.columns", "wallet.pass", "receipt", "giftcard", "gift", "shield", "hourglass", "calendar", "clock"]),
        ("Home", ["house", "house.lodge", "bed.double", "sofa", "lamp.desk", "washer", "refrigerator", "lightbulb", "bolt", "flame", "drop", "wrench.and.screwdriver", "hammer", "paintbrush", "leaf", "tree", "key", "lock", "door.left.hand.closed", "building.2", "building", "trash", "spigot"]),
        ("Food & drink", ["fork.knife", "cup.and.saucer", "mug", "wineglass", "takeoutbag.and.cup.and.straw", "birthday.cake", "carrot", "fish", "frying.pan", "cart", "basket", "bag"]),
        ("Getting around", ["car", "car.2", "bus", "tram", "bicycle", "scooter", "fuelpump", "ev.charger", "parkingsign", "steeringwheel", "road.lanes", "airplane", "ferry", "sailboat", "figure.walk", "map", "location"]),
        ("Health", ["heart", "cross.case", "pills", "stethoscope", "bandage", "syringe", "eyeglasses", "ear", "lungs", "brain.head.profile", "figure.run", "dumbbell", "figure.yoga", "figure.mind.and.body", "bathtub", "shower", "comb"]),
        ("Fun", ["gamecontroller", "tv", "music.note", "headphones", "film", "ticket", "theatermasks", "sportscourt", "soccerball", "basketball", "football", "figure.tennis", "book", "books.vertical", "newspaper", "paintpalette", "camera", "photo", "guitars", "mic", "party.popper", "balloon", "popcorn", "beach.umbrella", "tent", "mountain.2", "globe.americas", "suitcase", "dice", "puzzlepiece"]),
        ("People & pets", ["person", "person.2", "figure.2.and.child.holdinghands", "figure.and.child.holdinghands", "stroller", "teddybear", "pawprint", "dog", "cat", "bird", "graduationcap", "backpack", "pencil", "book.closed", "hands.sparkles"]),
        ("Work & tech", ["briefcase", "laptopcomputer", "desktopcomputer", "iphone", "keyboard", "printer", "wifi", "antenna.radiowaves.left.and.right", "cloud", "server.rack", "cpu", "sparkles", "wand.and.stars", "network", "envelope", "phone", "doc.text", "folder", "paperclip", "signature", "megaphone"]),
        ("Everything else", ["star", "crown", "trophy", "medal", "diamond", "scissors", "tshirt", "shoe", "umbrella", "sun.max", "snowflake", "moon", "flag", "bell", "hand.thumbsup", "arrow.3.trianglepath", "recycle", "leaf.arrow.triangle.circlepath", "questionmark", "ellipsis"]),
    ]
    static let symbols: [String] = iconGroups.flatMap(\.symbols)
    /// The groups with only the symbols this iOS knows.
    static var availableGroups: [(title: String, symbols: [String])] {
        iconGroups.compactMap { g in let ok = g.symbols.filter { UIImage(systemName: $0) != nil }; return ok.isEmpty ? nil : (g.title, ok) }
    }

    private var isNew: Bool { category == nil }
    private var recentMerchants: [String] {
        let since = Calendar.current.date(byAdding: .day, value: -90, to: .now)!
        let rows = model.transactions.filter { $0.displayDate >= since && ($0.kind == .spend || $0.kind == .untracked) }
        return Dictionary(grouping: rows) { $0.merchantKey }.values.sorted { $0.count > $1.count }.prefix(12).map { $0[0].merchant }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    IconCircle(symbol: symbol, size: 64, fill: lens == .wants ? Theme.Accent.subtle : lens == .kept ? Theme.Status.goodBg : Theme.Bg.subtle, color: lens == .wants ? Theme.Accent.default : lens == .kept ? Theme.Status.good : Theme.Text.primary).padding(.top, 8)
                    SectionHeader(title: "Name")
                    TextField("Kids, Pets, Business…", text: $name).font(Theme.Font.body).foregroundStyle(Theme.Text.primary).padding(.horizontal, Theme.Spacing.s16).frame(height: 50)
                        .background(Theme.Bg.elevated, in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous).strokeBorder(Theme.Accent.default)).padding(.horizontal, Theme.Spacing.s16)
                        .disabled(category?.builtIn == true)
                    if category?.builtIn != true {
                        SectionHeader(title: "Icon")
                        VStack(alignment: .leading, spacing: Theme.Spacing.s12) {
                            ForEach(Self.availableGroups, id: \.title) { group in
                                Text(group.title.uppercased()).font(Theme.Font.caption2Strong).foregroundStyle(Theme.Text.tertiary).padding(.top, 4)
                                FlowLayout(spacing: 10) {
                                    ForEach(group.symbols, id: \.self) { s in
                                        Button { symbol = s } label: { IconCircle(symbol: s, size: 42, fill: symbol == s ? Theme.Accent.subtle : Theme.Bg.elevated, color: symbol == s ? Theme.Accent.default : Theme.Text.secondary).overlay(Circle().strokeBorder(symbol == s ? Theme.Accent.default : Theme.Border.subtle)) }.buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, Theme.Spacing.s16)
                    }
                    SectionHeader(title: "Counts as")
                    HStack(spacing: 2) {
                        ForEach(Lens.allCases, id: \.self) { l in
                            let on = lens == l
                            Button { withAnimation(.snappy) { lens = l } } label: {
                                Text(l.rawValue.capitalized).font(Theme.Font.subheadStrong).foregroundStyle(on ? Theme.Text.primary : Theme.Text.secondary).frame(maxWidth: .infinity, minHeight: 30)
                                    .background(on ? Theme.Bg.elevated : .clear, in: RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(3).background(Theme.Bg.subtle, in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)).padding(.horizontal, Theme.Spacing.s16)
                    Text("Needs and wants feed Pace and Where. “Kept” is for money you set aside — it counts like savings.").font(Theme.Font.caption).foregroundStyle(Theme.Text.tertiary).padding(.horizontal, Theme.Spacing.s16).padding(.top, 8).frame(maxWidth: .infinity, alignment: .leading)
                    if isNew, !recentMerchants.isEmpty {
                        SectionHeader(title: "Start with")
                        Card {
                            ForEach(Array(recentMerchants.enumerated()), id: \.element) { i, m in
                                let on = picked.contains(m)
                                Button { if on { picked.remove(m) } else { picked.insert(m) } } label: {
                                    HStack(spacing: Theme.Spacing.s12) {
                                        ZStack { Circle().fill(on ? Theme.Accent.default : Theme.Bg.subtle); if on { Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(.white) } else { Circle().strokeBorder(Theme.Border.strong, lineWidth: 1.5) } }.frame(width: 24, height: 24)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(m.prettyMerchant).font(Theme.Font.body).foregroundStyle(Theme.Text.primary)
                                            Text("\(model.transactions.filter { $0.merchantKey == PoiseKit.Transaction.merchantKey(m) }.count) charges · \(model.categories.name(model.transactions.first { $0.merchantKey == PoiseKit.Transaction.merchantKey(m) }?.categoryID)) today").font(Theme.Font.caption).foregroundStyle(Theme.Text.tertiary)
                                        }
                                        Spacer()
                                    }
                                    .padding(.vertical, Theme.Spacing.s12).padding(.horizontal, Theme.Spacing.s16).contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                if i < recentMerchants.count - 1 { RowDivider() }
                            }
                        }
                        .padding(.horizontal, Theme.Spacing.s16)
                        Text("Picked merchants move here now and become rules for everything after.").font(Theme.Font.caption).foregroundStyle(Theme.Text.tertiary).padding(Theme.Spacing.s16)
                    }
                    if let c = category, !c.builtIn {
                        Button(role: .destructive) { confirmDelete = true } label: { Text("Delete category").font(Theme.Font.headline).foregroundStyle(Theme.Status.heads).frame(maxWidth: .infinity, minHeight: 50) }
                            .padding(.top, Theme.Spacing.s24)
                            .confirmationDialog("Delete \(c.name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
                                Button("Delete", role: .destructive) { dismiss(); Task { await model.deleteCategory(c) } }
                                Button("Cancel", role: .cancel) {}
                            } message: { Text("Its charges go back to the bank's suggested category. Rules pointing here are cleared.") }
                    }
                }
                .padding(.bottom, Theme.Spacing.s32)
            }
            .background(Theme.Bg.base)
            .navigationTitle(isNew ? "New category" : category!.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.tint(Theme.Accent.default) }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.fontWeight(.semibold).tint(Theme.Accent.default).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty) }
            }
            .onAppear {
                if let c = category { name = c.name; symbol = c.symbol; lens = c.lens }
                if let s = startWith { picked = [s] }
            }
        }
        .presentationDragIndicator(.visible)
    }

    private func save() {
        let n = name.trimmingCharacters(in: .whitespaces), s = symbol, l = lens, p = Array(picked)
        if var c = category { c.name = n; c.symbol = s; c.lens = l; let done = c; dismiss(); Task { await model.updateCategory(done); onSave(done) } }
        else { dismiss(); Task { if let c = await model.createCategory(name: n, symbol: s, lens: l, startWith: p) { onSave(c) } } }
    }
}
