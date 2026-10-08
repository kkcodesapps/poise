import SwiftUI

// The widget faces, shared with the app so they can be previewed in-app. No WidgetKit here — the extension
// wraps these in its container background; the app draws them on a card.

private extension WidgetSnapshot.Status {
    var color: Color { switch self { case .good: Theme.Status.good; case .track: Theme.Status.track; case .heads: Theme.Status.heads; case .empty: Theme.Text.tertiary } }
}

/// The verdict at a glance: status, how far ahead, what's kept.
struct VerdictGlance: View {
    let snapshot: WidgetSnapshot
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(snapshot.statusLabel).font(.system(size: 11, weight: .semibold)).foregroundStyle(snapshot.status.color).lineLimit(1)
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 0) {
                Text(snapshot.ahead).font(.system(size: 28, weight: .semibold, design: .rounded)).foregroundStyle(Theme.Text.primary).lineLimit(1).minimumScaleFactor(0.7)
                Text(snapshot.aheadSub).font(.system(size: 13)).foregroundStyle(Theme.Text.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                Text("Kept").font(.system(size: 12)).foregroundStyle(Theme.Text.tertiary)
                Text(snapshot.kept).font(.system(size: 13, weight: .medium, design: .rounded)).foregroundStyle(snapshot.keptGood ? Theme.Status.good : Theme.Status.track)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

/// Medium: the glance plus the three latest charges.
struct VerdictWithLatest: View {
    let snapshot: WidgetSnapshot
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VerdictGlance(snapshot: snapshot)
            VStack(spacing: 8) {
                Spacer(minLength: 0)
                if snapshot.latest.isEmpty {
                    Text("No charges yet").font(.system(size: 13)).foregroundStyle(Theme.Text.tertiary).frame(maxWidth: .infinity, alignment: .leading)
                }
                ForEach(snapshot.latest.prefix(3)) { row in
                    HStack {
                        Text(row.name).font(.system(size: 13)).foregroundStyle(Theme.Text.primary).lineLimit(1)
                        Spacer(minLength: 8)
                        Text(row.amount).font(.system(size: 13, weight: .medium, design: .rounded)).foregroundStyle(row.pending ? Theme.Money.pending : Theme.Text.primary).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// Lock Screen rectangle: three short lines.
struct VerdictLockRectangle: View {
    let snapshot: WidgetSnapshot
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("AHEAD · \(snapshot.statusLabel.replacingOccurrences(of: "IN ", with: ""))").font(.system(size: 11, weight: .semibold)).lineLimit(1)
            Text(snapshot.ahead).font(.system(size: 17, weight: .semibold, design: .rounded)).lineLimit(1)
            Text("\(snapshot.aheadSub.replacingOccurrences(of: "ahead ", with: "")) · kept \(snapshot.kept)").font(.system(size: 12)).opacity(0.75).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
