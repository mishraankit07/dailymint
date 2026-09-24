import Foundation
import UserNotifications

enum AutomaticImportNotification {
    static let enabledKey = "automaticImportNotificationsEnabledV1"

    static func sendTransactionAdded() async {
        guard UserDefaults.standard.bool(forKey: enabledKey) else { return }

        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        let allowed = settings.authorizationStatus == .authorized ||
            settings.authorizationStatus == .provisional ||
            settings.authorizationStatus == .ephemeral
        guard allowed else { return }

        let content = UNMutableNotificationContent()
        content.title = "DailyMint"
        content.body = "DailyMint added a transaction automatically."
        content.sound = .default
        content.threadIdentifier = "automatic-bank-imports"

        let request = UNNotificationRequest(
            identifier: "automatic-bank-import-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        try? await center.add(request)
    }
}
