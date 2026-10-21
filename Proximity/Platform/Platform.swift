import UIKit
import UserNotifications

enum Platform {
    /// CloudKit needs the iCloud entitlement, which needs a paid developer account.
    /// Builds without the CLOUDKIT flag run fully offline.
    static func makeBackend() -> (any CloudBackend)? {
        #if CLOUDKIT
        return CloudKitBackend()
        #else
        return nil
        #endif
    }

    /// Asks once for permission to show "INCOMING TRANSMISSION" alerts.
    static func requestNotifications() async {
        #if CLOUDKIT
        let center = UNUserNotificationCenter.current()
        guard await center.notificationSettings().authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        #endif
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        #if CLOUDKIT
        // CloudKit delivers mailbox notifications through APNs.
        application.registerForRemoteNotifications()
        #endif
        return true
    }
}
