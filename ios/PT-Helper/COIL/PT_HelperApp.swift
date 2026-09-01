import SwiftUI
import UIKit
import FirebaseCore
import FirebaseCrashlytics
import FirebaseFirestore
import GoogleSignIn
import FirebaseMessaging
import UserNotifications

@main
struct PainPointApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate

    init() {
        FirebaseApp.configure()   // uses GoogleService-Info.plist in this target
        Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(true)

        // Enable explicit Firestore offline persistence (100 MB cache)
        let db = Firestore.firestore()
        let settings = FirestoreSettings()
        settings.cacheSettings = PersistentCacheSettings(sizeBytes: NSNumber(value: 100 * 1024 * 1024))
        db.settings = settings
    }

    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(AppAppearance.storageKey) private var appearanceRaw = AppAppearance.system.rawValue

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme((AppAppearance(rawValue: appearanceRaw) ?? .system).colorScheme)
                .onOpenURL { url in
                    GIDSignIn.sharedInstance.handle(url)
                }
                .onChange(of: scenePhase) { _, newPhase in
                    switch newPhase {
                    case .active:
                        SessionLogger.shared.resumeSession()
                        AnalyticsService.shared.log(.appOpened)
                    case .background:
                        // End the session and force-upload the trail now —
                        // for sessions without an AI analysis this is the only
                        // upload trigger. The background task keeps iOS from
                        // suspending us before the upload finishes.
                        SessionLogger.shared.endSession()
                        // The expiration handler is required, not optional: without
                        // one, a background task that outlives its window is
                        // terminated by the watchdog and the app is killed. The
                        // upload does a Storage putData (default retry window ~600s)
                        // plus a Firestore write, so an offline or stalled
                        // background launch could sit well past the ~30s iOS grants.
                        var taskId: UIBackgroundTaskIdentifier = .invalid
                        taskId = UIApplication.shared.beginBackgroundTask(withName: "SessionLogUpload") {
                            // Last word before the system reclaims us — end the task
                            // ourselves so it is a clean stop rather than a kill. The
                            // log is already persisted to disk, so crash recovery
                            // picks it up on the next launch.
                            if taskId != .invalid {
                                UIApplication.shared.endBackgroundTask(taskId)
                                taskId = .invalid
                            }
                        }
                        Task {
                            await SessionLogger.shared.uploadToFirestore(force: true)
                            if taskId != .invalid {
                                UIApplication.shared.endBackgroundTask(taskId)
                                taskId = .invalid
                            }
                        }
                    default:
                        break
                    }
                }
                .task {
                    TestDataSeeder.seedIfNeeded()
                }
        }
    }
}

/// AppDelegate for handling foreground notification presentation
class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate, MessagingDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        application.registerForRemoteNotifications()
        Messaging.messaging().delegate = self
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
    }

    // MARK: - MessagingDelegate

    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        Task { @MainActor in
            NotificationService.shared.updateFCMToken(fcmToken ?? "")
        }
    }

    /// Show notifications even when app is in foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .badge])
    }

    /// Handle notification tap
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        // Clear badge on tap
        UNUserNotificationCenter.current().setBadgeCount(0)

        // Parse deep link from notification payload
        let userInfo = response.notification.request.content.userInfo
        if let tab = userInfo["tab"] as? String {
            NotificationService.shared.pendingDeepLink = tab
            NotificationCenter.default.post(name: .deepLink, object: nil)
        }

        completionHandler()
    }
}
