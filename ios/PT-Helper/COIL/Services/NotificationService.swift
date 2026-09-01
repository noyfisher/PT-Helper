import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseMessaging
import UserNotifications

/// Seam for unit-testing scheduling without the real notification center.
protocol NotificationScheduling: AnyObject {
    // The completion handler must be @Sendable to match UNUserNotificationCenter's
    // own signature under the iOS 26 SDK — without it the conformance below is a
    // Swift 6 sendability mismatch (and an error here, since warnings are errors).
    func add(_ request: UNNotificationRequest, withCompletionHandler completionHandler: (@Sendable (Error?) -> Void)?)
    func removePendingNotificationRequests(withIdentifiers identifiers: [String])
    func removeAllPendingNotificationRequests()
    func pendingNotificationRequests() async -> [UNNotificationRequest]
}
extension UNUserNotificationCenter: NotificationScheduling {}

/// Manages local + remote push notification reminders for rehab plan schedules.
@MainActor
class NotificationService: ObservableObject {
    static let shared = NotificationService()

    private let center: NotificationScheduling
    private let defaults: UserDefaults

    @Published var isAuthorized: Bool = false
    @Published var reminderHour: Int {
        didSet { defaults.set(reminderHour, forKey: "notif_reminder_hour") }
    }
    @Published var reminderMinute: Int {
        didSet { defaults.set(reminderMinute, forKey: "notif_reminder_minute") }
    }
    @Published var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: "notif_enabled") }
    }

    // MARK: - FCM Token

    @Published var fcmToken: String?

    // MARK: - Notification Type Preferences

    @Published var workoutRemindersEnabled: Bool {
        didSet { defaults.set(workoutRemindersEnabled, forKey: "notif_workout_reminders") }
    }
    @Published var reassessmentRemindersEnabled: Bool {
        didSet { defaults.set(reassessmentRemindersEnabled, forKey: "notif_reassessment_reminders") }
    }
    @Published var inactivityNudgesEnabled: Bool {
        didSet { defaults.set(inactivityNudgesEnabled, forKey: "notif_inactivity_nudges") }
    }

    // MARK: - Deep Link Queue (for cold-launch)

    /// Stores the target tab from a notification tap, consumed by ThreeTabView on appear.
    @Published var pendingDeepLink: String?

    init(center: NotificationScheduling = UNUserNotificationCenter.current(), defaults: UserDefaults = .standard, skipAuthCheck: Bool = false) {
        self.center = center
        self.defaults = defaults
        self.reminderHour = defaults.object(forKey: "notif_reminder_hour") as? Int ?? 9
        self.reminderMinute = defaults.object(forKey: "notif_reminder_minute") as? Int ?? 0
        self.isEnabled = defaults.object(forKey: "notif_enabled") as? Bool ?? false
        self.workoutRemindersEnabled = defaults.object(forKey: "notif_workout_reminders") as? Bool ?? true
        self.reassessmentRemindersEnabled = defaults.object(forKey: "notif_reassessment_reminders") as? Bool ?? true
        self.inactivityNudgesEnabled = defaults.object(forKey: "notif_inactivity_nudges") as? Bool ?? true
        if !skipAuthCheck { checkAuthorizationStatus() }
    }

    // MARK: - Permission

    func requestPermission() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .badge, .sound])
            await MainActor.run {
                self.isAuthorized = granted
                if granted { self.isEnabled = true }
            }
            return granted
        } catch {
            AppLogger.data.error("Notification permission error: \(error.localizedDescription)")
            return false
        }
    }

    func checkAuthorizationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            Task { @MainActor in
                self.isAuthorized = settings.authorizationStatus == .authorized
            }
        }
    }

    // MARK: - Scheduling

    /// Schedule weekly reminders based on a plan's weeklySchedule
    func scheduleReminders(for plan: RehabPlan) {
        guard isEnabled, isAuthorized, workoutRemindersEnabled else { return }

        // Cancel existing reminders for this plan first
        cancelReminders(for: plan.id)

        for (dayIndex, exercises) in plan.weeklySchedule.enumerated() {
            guard !exercises.isEmpty else { continue }

            // Map dayIndex (0=Sun) to calendar weekday (1=Sun)
            let weekday = dayIndex + 1

            let content = UNMutableNotificationContent()
            let streak = StreakService.shared.streakData.currentStreak
            let exerciseText = exercises.count == 1 ? "1 exercise" : "\(exercises.count) exercises"
            // Personalize with streak stakes so reminders read as a personal nudge,
            // not a robotic alarm (audit #35 — also fixes the "(s)" pluralization).
            if streak >= 2 {
                content.title = "Keep your \(streak)-day streak alive 🔥"
                content.body = "\(plan.planName) — \(exerciseText) today keeps the chain going."
            } else {
                content.title = "Time for your exercises!"
                content.body = "\(plan.planName) — \(exerciseText) scheduled today."
            }
            content.sound = .default
            content.badge = 1
            content.userInfo = ["tab": "plans"]

            var dateComponents = DateComponents()
            dateComponents.weekday = weekday
            dateComponents.hour = reminderHour
            dateComponents.minute = reminderMinute

            let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
            let identifier = notificationId(planId: plan.id, dayIndex: dayIndex)
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

            center.add(request) { error in
                if let error = error {
                    AppLogger.data.error("Failed to schedule notification: \(error.localizedDescription)")
                }
            }
        }
    }

    /// Cancel all reminders for a specific plan
    func cancelReminders(for planId: UUID) {
        let identifiers = (0..<7).map { notificationId(planId: planId, dayIndex: $0) }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    /// Cancel all app reminders
    /// Cancel every scheduled reminder, keeping the cached plan list.
    ///
    /// Used by the Settings toggle, which must be able to turn reminders back on.
    /// This previously also cleared `lastKnownPlans`, and `resyncReminders` schedules
    /// exclusively from that cache — so toggling reminders off and on again
    /// scheduled nothing at all, silently, until the plans listener happened to
    /// fire again.
    func cancelAllReminders() {
        center.removeAllPendingNotificationRequests()
        UNUserNotificationCenter.current().setBadgeCount(0)
    }

    /// Cancel every reminder AND forget the plans they were built from.
    ///
    /// Sign-out only. The cache must be dropped there or a toggle flipped before
    /// the next user's plans listener fires would resync reminders from the
    /// previous account's plan names.
    func cancelAllRemindersAndForgetPlans() {
        cancelAllReminders()
        lastKnownPlans = []
    }

    // MARK: - Plan-lifecycle reconciliation (WS2)

    /// Last plans list handed over by SavedPlansViewModel's listener; lets
    /// Settings toggles resync without view-layer plumbing (SettingsView is
    /// presented from three contexts, one of them dead code — no @EnvironmentObject).
    private(set) var lastKnownPlans: [RehabPlan] = []

    /// Identifier prefixes owned by the reconciler; every pass removes all
    /// pending requests with these prefixes, then re-schedules from scratch.
    static let reconciledPrefixes = ["plan-", "reassess-", "activation-"]

    /// The one plan that gets weekly workout reminders: most recently started,
    /// not yet completed. Single plan only — two overlapping schedules would
    /// fire duplicate same-minute alerts (spam) and burn the 64-pending cap.
    static func reminderEligiblePlan(from plans: [RehabPlan]) -> RehabPlan? {
        plans.filter { $0.startDate != nil && !$0.isCompleted }
            .max { ($0.startDate ?? .distantPast) < ($1.startDate ?? .distantPast) }
    }

    /// Store the latest plans and reconcile all plan-derived notifications.
    func syncPlanReminders(plans: [RehabPlan]) async {
        lastKnownPlans = plans
        await reconcile()
    }

    /// Re-run reconciliation with the last known plans (Settings toggles / time picker).
    func resyncReminders() async {
        await reconcile()
    }

    private func reconcile() async {
        let pending = await center.pendingNotificationRequests()
        let stale = pending.map(\.identifier)
            .filter { id in Self.reconciledPrefixes.contains { id.hasPrefix($0) } }
        center.removePendingNotificationRequests(withIdentifiers: stale)

        guard isEnabled, isAuthorized else { return }
        if workoutRemindersEnabled, let active = Self.reminderEligiblePlan(from: lastKnownPlans) {
            scheduleReminders(for: active)
        }
        if reassessmentRemindersEnabled {
            for plan in lastKnownPlans where plan.startDate != nil && !plan.isCompleted {
                scheduleReassessmentReminders(for: plan)
            }
        }
        if inactivityNudgesEnabled, let active = Self.reminderEligiblePlan(from: lastKnownPlans),
           let start = active.startDate {
            let lastWorkout = defaults.object(forKey: lastWorkoutAtKey) as? Date
            if lastWorkout == nil || lastWorkout! < start {
                scheduleActivationNudge(for: active)
            }
        }
    }

    // MARK: - Re-assessment reminders (audit #33)

    /// Midpoint + completion one-shot reminders mirroring the in-app prompt
    /// (ReAssessmentViewModel.shouldShowReAssessment). Fires on the FIRST DAY of
    /// the milestone week at the user's reminder time; past dates are skipped.
    func scheduleReassessmentReminders(for plan: RehabPlan) {
        guard isEnabled, isAuthorized, reassessmentRemindersEnabled,
              let start = plan.startDate else { return }

        let midpointWeek = max(plan.totalWeeks / 2, 1)
        var milestones: [(suffix: String, week: Int, title: String, body: String)] = []
        if midpointWeek < plan.totalWeeks {
            milestones.append(("midpoint", midpointWeek,
                "Halfway there — quick check-in",
                "\(plan.planName): compare today's pain to week 1 with a 2-minute re-assessment."))
        }
        milestones.append(("completion", plan.totalWeeks,
            "Final week — see your progress",
            "\(plan.planName): run your final re-assessment to see how far you've come."))

        for milestone in milestones {
            guard let fireDay = Calendar.current.date(byAdding: .day,
                                                      value: (milestone.week - 1) * 7,
                                                      to: start) else { continue }
            var comps = Calendar.current.dateComponents([.year, .month, .day], from: fireDay)
            comps.hour = reminderHour
            comps.minute = reminderMinute
            guard let fireDate = Calendar.current.date(from: comps), fireDate > Date() else { continue }
            let content = UNMutableNotificationContent()
            content.title = milestone.title
            content.body = milestone.body
            content.sound = .default
            content.userInfo = ["tab": "plans"]
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            let request = UNNotificationRequest(
                identifier: "reassess-\(plan.id.uuidString)-\(milestone.suffix)",
                content: content, trigger: trigger)
            center.add(request) { error in
                if let error {
                    AppLogger.data.error("Failed to schedule re-assessment reminder: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Inactivity Nudge (audit #33)

    private let inactivityNudgeId = "inactivity-nudge"
    /// Days of no workout before the "come back" nudge fires.
    private let inactivityNudgeDays = 3

    /// (Re)schedules a "come back" nudge `inactivityNudgeDays` out, gated by the
    /// `inactivityNudgesEnabled` toggle (which previously did nothing). Call after
    /// each workout so the clock resets to the last active day; if the user keeps
    /// working out it never fires, and it lands only after a real lapse.
    func scheduleInactivityNudge() {
        cancelInactivityNudge()
        guard isEnabled, isAuthorized, inactivityNudgesEnabled else { return }

        let content = UNMutableNotificationContent()
        content.title = "Your recovery misses you"
        content.body = "It's been a few days — a short session keeps your progress moving."
        content.sound = .default

        let seconds = TimeInterval(inactivityNudgeDays * 24 * 60 * 60)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
        let request = UNNotificationRequest(identifier: inactivityNudgeId, content: content, trigger: trigger)
        center.add(request) { error in
            if let error = error {
                AppLogger.data.error("Failed to schedule inactivity nudge: \(error.localizedDescription)")
            }
        }
    }

    func cancelInactivityNudge() {
        center.removePendingNotificationRequests(withIdentifiers: [inactivityNudgeId])
    }

    // MARK: - First-workout activation nudge (audit #34)

    private let lastWorkoutAtKey = "notif_last_workout_at"

    /// Called by WorkoutViewModel on session save: records activity, then
    /// reconciles — the guard below sees the fresh timestamp and drops any
    /// pending activation nudge.
    func noteWorkoutCompleted() async {
        defaults.set(Date(), forKey: lastWorkoutAtKey)
        await resyncReminders()
    }

    /// One-shot "do your first session" nudge, 2 days after plan start at the
    /// user's reminder time. Gated by inactivityNudgesEnabled (same "you haven't
    /// trained" family as the 3-day nudge). Past fire dates are skipped.
    private func scheduleActivationNudge(for plan: RehabPlan) {
        guard let start = plan.startDate,
              let fireDay = Calendar.current.date(byAdding: .day, value: 2, to: start) else { return }
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: fireDay)
        comps.hour = reminderHour
        comps.minute = reminderMinute
        guard let fireDate = Calendar.current.date(from: comps), fireDate > Date() else { return }
        let content = UNMutableNotificationContent()
        content.title = "Your plan is ready when you are"
        content.body = "\(plan.planName) — a first session today starts your streak."
        content.sound = .default
        content.userInfo = ["tab": "plans"]
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let request = UNNotificationRequest(identifier: "activation-\(plan.id.uuidString)",
                                            content: content, trigger: trigger)
        center.add(request) { error in
            if let error {
                AppLogger.data.error("Failed to schedule activation nudge: \(error.localizedDescription)")
            }
        }
    }

    /// Update reminder time and reschedule everything the reconciler owns.
    func updateReminderTime(hour: Int, minute: Int) {
        reminderHour = hour
        reminderMinute = minute
        Task { await resyncReminders() }
    }

    // MARK: - FCM Token Management

    /// Called by AppDelegate when FCM registration token is received or refreshed.
    func updateFCMToken(_ token: String) {
        fcmToken = token
        AppLogger.data.info("FCM token updated: \(token.prefix(20))...")
        uploadTokenToFirestore()
    }

    /// Uploads the current FCM token to the user's Firestore document.
    private func uploadTokenToFirestore() {
        guard let token = fcmToken,
              let uid = Auth.auth().currentUser?.uid else { return }

        let db = Firestore.firestore()
        db.collection("users").document(uid).setData([
            "fcmToken": token,
            "fcmTokenUpdatedAt": FieldValue.serverTimestamp()
        ], merge: true) { error in
            if let error {
                AppLogger.data.error("Failed to upload FCM token: \(error.localizedDescription)")
            }
        }
    }

    /// Clears the FCM token from Firestore. MUST be called while the user is
    /// still authenticated — i.e. at the sign-out action, BEFORE `Auth.signOut()`
    /// so the delete is authorized. After sign-out the client can't write
    /// Firestore, so the token would linger under the former account and keep
    /// receiving that account's notifications on a shared device (P2-01).
    ///
    /// The write is time-bounded: the app enables Firestore offline persistence,
    /// so a write's completion never resolves while offline. A plain `await`
    /// here would then suspend forever and `Auth.signOut()` would never run —
    /// silently leaving the user signed in on a shared device (the exact leak
    /// this path closes). We wait up to `fcmClearTimeoutSeconds` for the delete
    /// to reach the backend, then let sign-out proceed regardless: offline the
    /// server token can't be cleared anyway, and it is rebound on next sign-in.
    func clearFCMToken() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        fcmToken = nil
        await Self.awaitWithTimeout(seconds: Self.fcmClearTimeoutSeconds) {
            do {
                try await Firestore.firestore().collection("users").document(uid).updateData([
                    "fcmToken": FieldValue.delete(),
                    "fcmTokenUpdatedAt": FieldValue.delete()
                ])
            } catch {
                AppLogger.data.error("Failed to clear FCM token: \(error.localizedDescription)")
            }
        }
    }

    /// Upper bound (seconds) on how long sign-out waits for the FCM-token delete
    /// to acknowledge before proceeding anyway.
    nonisolated static let fcmClearTimeoutSeconds: Double = 3

    /// Runs `operation`, returning when it finishes or after `seconds`,
    /// whichever comes first. Past the deadline `operation` keeps running
    /// detached — we simply stop waiting on it — so a caller never blocks on a
    /// non-cancellable async call (e.g. a Firestore write that can't ack under
    /// offline persistence). Returns as soon as `operation` completes when the
    /// backend is reachable, so the online sign-out path is not slowed.
    nonisolated static func awaitWithTimeout(
        seconds: Double,
        _ operation: @escaping @Sendable () async -> Void
    ) async {
        let gate = OneShotGate()
        let work = Task.detached { await operation(); await gate.open() }
        let timer = Task.detached {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            await gate.open()
        }
        await gate.wait()
        work.cancel()
        timer.cancel()
    }

    // MARK: - Helpers

    private func notificationId(planId: UUID, dayIndex: Int) -> String {
        "plan-\(planId.uuidString)-day-\(dayIndex)"
    }
}

/// One-shot gate used to implement `awaitWithTimeout`. The first `open()`
/// releases a single pending `wait()`; a `wait()` that arrives after `open()`
/// returns immediately, and additional `open()` calls are no-ops. Actor
/// isolation serializes `wait`/`open`, so the single continuation is resumed
/// exactly once.
fileprivate actor OneShotGate {
    private var isOpen = false
    private var waiter: CheckedContinuation<Void, Never>?

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiter = $0 }
    }

    func open() {
        guard !isOpen else { return }
        isOpen = true
        waiter?.resume()
        waiter = nil
    }
}
