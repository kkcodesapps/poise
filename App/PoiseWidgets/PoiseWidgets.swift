import WidgetKit
import SwiftUI

@main
struct PoiseWidgetBundle: WidgetBundle {
    var body: some Widget { VerdictWidget() }
}

struct VerdictEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

/// One entry per refresh: whatever the app last wrote. The app reloads timelines after every sync, so the
/// 30-minute policy is only a floor for when the app hasn't run.
struct VerdictProvider: TimelineProvider {
    func placeholder(in context: Context) -> VerdictEntry {
        VerdictEntry(date: .now, snapshot: WidgetSnapshot(status: .good, statusLabel: "IN GOOD SHAPE", ahead: "$1,240", aheadSub: "ahead through Fri", kept: "31%", keptGood: true,
                                                         latest: [.init(id: "1", name: "Costco", amount: "−$62.40", pending: true), .init(id: "2", name: "Shell", amount: "−$48.10", pending: false), .init(id: "3", name: "Spotify", amount: "−$11.99", pending: false)], updatedAt: .now))
    }
    func getSnapshot(in context: Context, completion: @escaping (VerdictEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : VerdictEntry(date: .now, snapshot: WidgetSnapshot.load() ?? .empty))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<VerdictEntry>) -> Void) {
        let entry = VerdictEntry(date: .now, snapshot: WidgetSnapshot.load() ?? .empty)
        completion(Timeline(entries: [entry], policy: .after(Date.now.addingTimeInterval(30 * 60))))
    }
}

struct VerdictWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: VerdictEntry
    var body: some View {
        Group {
            switch family {
            case .systemMedium: VerdictWithLatest(snapshot: entry.snapshot)
            case .accessoryRectangular: VerdictLockRectangle(snapshot: entry.snapshot)
            case .accessoryInline: Text("\(entry.snapshot.ahead) ahead · kept \(entry.snapshot.kept)")
            case .accessoryCircular:
                VStack(spacing: 0) {
                    Text(entry.snapshot.ahead.replacingOccurrences(of: ",", with: "")).font(.system(size: 13, weight: .semibold, design: .rounded)).minimumScaleFactor(0.6).lineLimit(1)
                    Text("ahead").font(.system(size: 9))
                }
            default: VerdictGlance(snapshot: entry.snapshot)
            }
        }
        .widgetURL(URL(string: "poise://home"))
        .containerBackground(for: .widget) { Theme.Bg.elevated }
    }
}

struct VerdictWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.koliokolev.poise.verdict", provider: VerdictProvider()) { entry in VerdictWidgetView(entry: entry) }
            .configurationDisplayName("Verdict")
            .description("How you're doing, at a glance — and the latest charges on the medium size.")
            .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline, .accessoryCircular])
    }
}
