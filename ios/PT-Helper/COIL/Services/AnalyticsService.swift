import Foundation
import FirebaseAnalytics

/// Wraps Firebase Analytics with typed events to enforce behavioral-only tracking.
/// NEVER log health data (pain levels, conditions, body regions, medical history).
/// Use counts and durations instead (e.g., region_count: 3, not regions: ["knee"]).
final class AnalyticsService {
    static let shared = AnalyticsService()
    private init() {}

    // MARK: - Funnel Events (core conversion pipeline)

    enum FunnelEvent: String {
        case appOpened = "app_opened"
        case signInCompleted = "sign_in_completed"
        case onboardingStarted = "onboarding_started"
        case onboardingStepCompleted = "onboarding_step_completed"
        case onboardingCompleted = "onboarding_completed"
        case onboardingSkipped = "onboarding_skipped"
        case bodyMapOpened = "body_map_opened"
        case regionsSelected = "regions_selected"
        case assessmentStarted = "assessment_started"
        case assessmentCompleted = "assessment_completed"
        case analysisCompleted = "analysis_completed"
        case analysisFailed = "analysis_failed"
        case rehabPlanGenerated = "rehab_plan_generated"
        case workoutStarted = "workout_started"
        case workoutCompleted = "workout_completed"
        case workoutEndedEarly = "workout_ended_early"
        case workoutDiscarded = "workout_discarded"
        case assessmentGatewayChosen = "assessment_gateway_chosen"
        case accountDeleteAttempted = "account_delete_attempted"
        case accountDeleted = "account_deleted"
        case accountDeleteFailed = "account_delete_failed"
        case signedOut = "signed_out"
        case planDeleted = "plan_deleted"
        case workoutCheckpointDiscarded = "workout_checkpoint_discarded"
    }

    // MARK: - Engagement Events (feature adoption & depth)

    enum EngagementEvent: String {
        case exerciseSwapped = "exercise_swapped"
        case exerciseSkipped = "exercise_skipped"
        case planViewed = "plan_viewed"
        case recoveryInsightsViewed = "recovery_insights_viewed"
        case achievementEarned = "achievement_earned"
        case reassessmentStarted = "reassessment_started"
        case pdfExported = "pdf_exported"
        case tabSwitched = "tab_switched"
        case workoutResumed = "workout_resumed"
        case formAnalysisCompleted = "form_analysis_completed"
        case workoutPauseToggled = "workout_pause_toggled"
        case exerciseSwapOpened = "exercise_swap_opened"
        case formAnalysisStarted = "form_analysis_started"
        case settingChanged = "setting_changed"
        case errorShown = "error_shown"
    }

    // MARK: - Logging

    func log(_ event: FunnelEvent, parameters: [String: Any] = [:]) {
        Analytics.logEvent(event.rawValue, parameters: parameters.isEmpty ? nil : parameters)
    }

    func log(_ event: EngagementEvent, parameters: [String: Any] = [:]) {
        Analytics.logEvent(event.rawValue, parameters: parameters.isEmpty ? nil : parameters)
    }

    func logScreenView(_ screenName: String) {
        Analytics.logEvent(AnalyticsEventScreenView, parameters: [
            AnalyticsParameterScreenName: screenName
        ])
    }

    // MARK: - User Properties (for cohort analysis)

    /// `activityLevel` is deliberately NOT forwarded: a GA4 *user property* is a
    /// durable attribute attached to the UID, and it comes straight off the
    /// health profile. `hasProfile` carries the funnel signal (did onboarding
    /// complete) without the health attribute itself.
    func setUserProperties(hasProfile: Bool) {
        Analytics.setUserProperty(hasProfile ? "true" : "false", forName: "has_profile")
        if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            Analytics.setUserProperty(version, forName: "app_version")
        }
    }

    func setUserId(_ userId: String?) {
        Analytics.setUserID(userId)
    }

    /// Clear the on-device analytics identifiers and stop further collection for
    /// this install's current identity.
    ///
    /// Account deletion purges Firestore, Storage and the Auth user, but GA4 is
    /// a separate processor that it cannot reach, so without this the deleted
    /// user's events stayed associated with a live client id. This does NOT
    /// retroactively delete events already exported to GA4/BigQuery — that
    /// requires a user-deletion request on the property itself.
    func resetForAccountDeletion() {
        Analytics.setUserID(nil)
        Analytics.setUserProperty(nil, forName: "has_profile")
        Analytics.resetAnalyticsData()
    }
}
