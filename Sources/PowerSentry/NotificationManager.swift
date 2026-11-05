import Foundation
import UserNotifications

enum NotificationManager {
    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func notify(_ incident: Incident) {
        let content = UNMutableNotificationContent()
        content.title = incident.title
        content.body = incident.detail
        content.sound = .default
        let request = UNNotificationRequest(identifier: incident.id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
