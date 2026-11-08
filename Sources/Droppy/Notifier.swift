import Foundation
@preconcurrency import UserNotifications

@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    private nonisolated static let viewKey = "view"
    var onActivate: ((UUID) -> Void)?

    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    func post(title: String, body: String, from viewID: UUID) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = [Self.viewKey: viewID.uuidString]
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error { log.error("notification authorization failed: \(String(describing: error), privacy: .public)") }
            guard granted else { return }
            center.add(request) { error in
                if let error { log.error("notification failed: \(String(describing: error), privacy: .public)") }
            }
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let identifier = (response.notification.request.content.userInfo[Self.viewKey] as? String).flatMap(UUID.init)
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                if let identifier { self.onActivate?(identifier) }
            }
        }
        completionHandler()
    }
}
