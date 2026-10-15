import Foundation
import Observation
import UIKit
import UserNotifications

/// Rest timer based on timestamps (end date), not on a ticking counter: it survives screen lock,
/// backgrounding and relaunch. A local notification fires at the end; permission is requested in
/// context (the first time a timer starts), never at app launch.
@MainActor
@Observable
final class RestTimerService {
    private(set) var endDate: Date?
    private(set) var totalSeconds: Int = 0
    private let notificationId = "rest-timer"
    private static let storedEndKey = "restTimer.endDate"

    init() {
        // Restore a running timer after relaunch (UserDefaults is only used for this convenience).
        if let stored = UserDefaults.standard.object(forKey: Self.storedEndKey) as? Date, stored > Date() {
            endDate = stored
        }
    }

    func remaining(at now: Date) -> TimeInterval {
        guard let endDate else { return 0 }
        return max(0, endDate.timeIntervalSince(now))
    }

    var isRunning: Bool { endDate.map { $0 > Date() } ?? false }

    func start(seconds: Int, now: Date, notify: Bool) {
        guard seconds > 0 else { return }
        totalSeconds = seconds
        let end = now.addingTimeInterval(TimeInterval(seconds))
        endDate = end
        UserDefaults.standard.set(end, forKey: Self.storedEndKey)
        guard notify else { return }
        Task { await self.scheduleNotification(at: end) }
    }

    func add(seconds: Int, now: Date, notify: Bool) {
        let base = max(remaining(at: now), 0)
        start(seconds: Int(base) + seconds, now: now, notify: notify)
    }

    func stop() {
        endDate = nil
        UserDefaults.standard.removeObject(forKey: Self.storedEndKey)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [notificationId])
    }

    private func scheduleNotification(at date: Date) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
        }
        guard await center.notificationSettings().authorizationStatus == .authorized else { return }
        let content = UNMutableNotificationContent()
        content.title = "Descanso terminado"
        content.body = "Es momento de la próxima serie."
        content.sound = .default
        let interval = max(1, date.timeIntervalSinceNow)
        let request = UNNotificationRequest(
            identifier: notificationId,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        )
        center.removePendingNotificationRequests(withIdentifiers: [notificationId])
        try? await center.add(request)
    }
}

/// Keeps the screen on during a session when the user enabled it.
enum ScreenAwake {
    @MainActor
    static func set(_ on: Bool) {
        UIApplication.shared.isIdleTimerDisabled = on
    }
}
