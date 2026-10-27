import Foundation
import UserNotifications

@MainActor
protocol RestAlertScheduling: AnyObject {
    func requestPermission() async throws -> Bool
    func update(deadline: Date?, enabled: Bool)
}

@MainActor
final class LocalRestAlerts: NSObject, RestAlertScheduling, UNUserNotificationCenterDelegate {
    static let identifier = "togetherstrong.rest.complete"
    private let center: UNUserNotificationCenter
    private var generation = 0
    private var queued: Task<Void, Never>?

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center; super.init(); center.delegate = self
    }
    func requestPermission() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .sound])
    }
    static func request(deadline: Date) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = "Rest complete"
        content.body = "Ready for your next set when you are."
        content.sound = .default
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let rounded = Date(timeIntervalSince1970: ceil(deadline.timeIntervalSince1970))
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: rounded)
        components.calendar = calendar; components.timeZone = calendar.timeZone
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        return UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
    }
    func update(deadline: Date?, enabled: Bool) {
        generation += 1
        let version = generation
        let prior = queued
        center.removePendingNotificationRequests(withIdentifiers: [Self.identifier])
        center.removeDeliveredNotifications(withIdentifiers: [Self.identifier])
        queued = Task { [weak self] in
            await prior?.value
            guard let self, version == self.generation else { return }
            self.center.removePendingNotificationRequests(withIdentifiers: [Self.identifier])
            guard enabled, let deadline, deadline > Date() else { return }
            let settings = await self.center.notificationSettings()
            guard version == self.generation, deadline > Date(),
                  [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus) else { return }
            do {
                try await self.center.add(Self.request(deadline: deadline))
                if version != self.generation {
                    self.center.removePendingNotificationRequests(withIdentifiers: [Self.identifier])
                }
            } catch {
                // OS alert delivery is optional; the persisted deadline remains authoritative.
            }
        }
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
        willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
