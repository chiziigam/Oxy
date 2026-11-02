import UIKit
import UserNotifications

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        if #available(iOS 16.1, *) {
            PendantLiveActivityManager.shared.begin()
        }
        UNUserNotificationCenter.current().delegate = self
        NotificationActions.register()
        return true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let answer = NotificationAnswer(response)
        await NotificationActions.handle(answer)
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        guard let userId = KeychainHelper.shared.read(key: "user_id"), !userId.isEmpty else { return }
        Task { @MainActor in
            await NativeIntegrationManager.shared.registerPushToken(deviceToken, userId: userId)
        }
    }
}
