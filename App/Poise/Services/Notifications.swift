import BackgroundTasks
import UIKit
import UserNotifications
import OSLog
import PoiseKit

private let log = Logger(subsystem: "com.koliokolev.poise", category: "push")

/// Registers the phone for pushes, hands the token to the server, and routes taps back into the app.
@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    var model: AppModel?

    /// Banks reach the server by webhook and Wallet by its own extension, so both arrive with the app closed. Amazon
    /// can't: its session lives in this app's web view, so iOS has to wake us to read it.
    static let amazonRefresh = "com.koliokolev.poise.amazon-refresh"

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        // On the main queue deliberately: the handler touches the model and the web view, both main-actor bound. Passing
        // nil here hands the launch handler a background queue, and assuming main-actor isolation on it traps — which
        // crashed the app every time iOS ran the background refresh.
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.amazonRefresh, using: .main) { task in
            MainActor.assumeIsolated { AppDelegate.handleAmazonRefresh(task) }
        }
        Self.scheduleAmazonRefresh()
        return true
    }

    /// Asks iOS for another wake in about four hours. It decides the real timing from how the app is used, so this is
    /// a floor rather than a schedule — in practice a few times a day.
    static func scheduleAmazonRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: amazonRefresh)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 4 * 3600)
        try? BGTaskScheduler.shared.submit(request)
    }

    /// One page of Amazon, which is a fortnight of orders — enough to catch what's new in the few seconds iOS allows.
    @MainActor
    private static func handleAmazonRefresh(_ task: BGTask) {
        scheduleAmazonRefresh()                                   // queue the next one first, whatever happens here
        guard let model = (UIApplication.shared.delegate as? AppDelegate)?.model else {
            return task.setTaskCompleted(success: false)
        }
        let work = Task { @MainActor in
            await model.syncAmazonIfDue(notBefore: 3 * 3600, maxPages: 1)
            task.setTaskCompleted(success: true)
        }
        task.expirationHandler = { work.cancel() }
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task { await model?.registerDevice(token: token) }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        log.error("push registration failed: \(error.localizedDescription, privacy: .public)")
    }

    /// In the foreground a new charge is already on screen, so only heads-ups and the review show as banners.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        let kind = notification.request.content.userInfo["kind"] as? String
        await MainActor.run { model?.pushArrived() }
        return kind == "spend" ? [] : [.banner, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        let hints = Dictionary(uniqueKeysWithValues: info.compactMap { k, v in (k as? String).flatMap { key in (v as? String).map { (key, $0) } } })
        await MainActor.run { model?.handlePush(hints) }
    }
}

/// The heads-ups the phone can schedule itself: a renewal you asked about, a crunch ahead, the Sunday review.
enum LocalNotifications {
    static func schedule(streams: [RecurringStream], watched: Set<String>, crunch: (date: Date, shortfall: Decimal)?, weeklyReview: Bool, headsUp: Bool) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        let pending = await center.pendingNotificationRequests().map(\.identifier)
        center.removePendingNotificationRequests(withIdentifiers: pending.filter { $0.hasPrefix("renewal-") || $0 == "crunch" || $0 == "weekly-review" })
        let cal = Calendar.current
        guard headsUp || weeklyReview else { return }
        if headsUp {
            for s in streams where s.kind != .income && watched.contains(PoiseKit.Transaction.merchantKey(s.merchant)) {
                guard let dayBefore = cal.date(byAdding: .day, value: -1, to: s.nextExpected) else { continue }
                var comps = cal.dateComponents([.year, .month, .day], from: dayBefore); comps.hour = 9
                guard let fire = cal.date(from: comps), fire > .now else { continue }
                let content = UNMutableNotificationContent()
                content.title = "\(s.merchant.prettyMerchant) \(s.cadence == .annual ? "renews" : "charges") tomorrow · \(s.amount.money2)"
                content.body = "You asked for a heads-up before it \(s.cadence == .annual ? "renews" : "lands")."
                content.sound = .default; content.threadIdentifier = "heads"; content.userInfo = ["kind": "heads", "stream": s.id]
                try? await center.add(UNNotificationRequest(identifier: "renewal-\(s.id)", content: content, trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)))
            }
            if let crunch, let dayBefore = cal.date(byAdding: .day, value: -1, to: crunch.date) {
                var comps = cal.dateComponents([.year, .month, .day], from: dayBefore); comps.hour = 9
                if let fire = cal.date(from: comps), fire > .now {
                    let content = UNMutableNotificationContent()
                    content.title = "Checking runs short \(crunch.date.formatted(.dateTime.weekday(.wide)))"
                    content.body = "Move \(crunch.shortfall.money) across before then and every bill clears."
                    content.sound = .default; content.threadIdentifier = "heads"; content.userInfo = ["kind": "heads", "tab": "next14"]
                    try? await center.add(UNNotificationRequest(identifier: "crunch", content: content, trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)))
                }
            }
        }
        if weeklyReview {
            var comps = DateComponents(); comps.weekday = 1; comps.hour = 18
            let content = UNMutableNotificationContent()
            content.title = "Your week is ready"; content.body = "Five cards, about 60 seconds."
            content.sound = .default; content.threadIdentifier = "review"; content.userInfo = ["kind": "review", "review": "1"]
            try? await center.add(UNNotificationRequest(identifier: "weekly-review", content: content, trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)))
        }
    }
}
