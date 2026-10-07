#if DEBUG
import SwiftUI

/// `-widgets`: the widget faces at their real sizes, drawn from the same snapshot the extension reads.
struct WidgetPreviewSheet: View {
    var body: some View {
        let snap = WidgetSnapshot.load() ?? .empty
        ScrollView {
            VStack(spacing: 24) {
                VerdictGlance(snapshot: snap).padding(16).frame(width: 158, height: 158).background(Theme.Bg.elevated, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                VerdictWithLatest(snapshot: snap).padding(16).frame(width: 338, height: 158).background(Theme.Bg.elevated, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                VerdictLockRectangle(snapshot: snap).padding(.horizontal, 12).frame(width: 157, height: 72).background(Theme.Bg.subtle, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                Text("updated \(snap.updatedAt.formatted(.dateTime.hour().minute()))").font(Theme.Font.caption).foregroundStyle(Theme.Text.tertiary)
            }
            .padding(32)
        }
        .background(Theme.Bg.base)
    }
}
#endif
