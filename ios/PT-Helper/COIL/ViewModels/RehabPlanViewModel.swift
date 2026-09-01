import SwiftUI
import Foundation
import FirebaseFirestore
import FirebaseAuth

// MARK: - Intermediate Decodable Types for AI Rehab Response

struct AIRehabResponse: Decodable {
    let planName: String
    let exercises: [AIRehabExercise]
    let totalWeeks: Int
    let notes: String?
}

struct AIRehabExercise: Decodable {
    let name: String
    let targetArea: String
    let description: String
    let sets: Int
    let reps: String
    let restSeconds: Int
    let difficulty: String
    let demonstrationIcon: String
    let tips: [String]
    let contraindications: [String]
    let startPosition: String?
    let movement: String?
    let endPosition: String?
    let exerciseCategory: String?
    let imageFileName: String?
    // PR 2: server-side flag/notes for kinetic-chain substitutions. Both optional
    // so omission decodes cleanly. `originalAIName` is intentionally NOT here —
    // it's a client-side-only field set during validation.
    let catalogSubstitution: Bool?
    let notes: String?
}

// MARK: - Rehab Plan Preferences

struct RehabPlanPreferences {
    enum Equipment: String, CaseIterable {
        case none = "No equipment"
        case bands = "Resistance bands"
        case dumbbells = "Dumbbells"
        case fullGym = "Full gym"
    }

    enum SessionLength: String, CaseIterable {
        case short = "15 min"
        case medium = "30 min"
        case long = "45 min"
    }

    enum DifficultyPreference: String, CaseIterable {
        case gentle = "Gentle"
        case moderate = "Moderate"
        case challenging = "Challenging"
    }

    var equipment: Equipment = .none
    var sessionLength: SessionLength = .medium
    var difficulty: DifficultyPreference = .moderate
}

@MainActor
class RehabPlanViewModel: ObservableObject {
    @Published var rehabPlan: RehabPlan?
    @Published var rehabPlanWarnings: [ValidationWarning] = []
    @Published var isSaving = false
    @Published var showSaveSuccess = false
    @Published var saveError: String? = nil
    @Published var isGenerating: Bool = false
    @Published var generationError: String? = nil
    @Published var preferences = RehabPlanPreferences()

    // MARK: - Safer-plan retry (Tier 1)
    /// Count of safer-plan retries already attempted for the current analysis.
    /// Max 2 — after that, surface "Contact your PT".
    @Published var saferPlanRetryCount: Int = 0
    /// Cached analysis result + original warnings so a retry can rebuild the prompt with
    /// a "do not recommend these exercises" constraint appended.
    private var originalAnalysisResult: AnalysisResult?
    private var originalFlaggedExerciseNames: [String] = []
    /// Max retries before giving up and recommending PT consultation.
    static let maxSaferPlanRetries = 2

    // MARK: - Exercise Verification State
    /// Verification status for each exercise (keyed by exercise name)
    @Published var exerciseVerifications: [String: ExerciseVerificationStatus] = [:]
    /// Whether cross-model verification is in progress
    @Published var isVerifyingUnknowns: Bool = false
    /// Whether all verification (graph + cross-model) is complete
    @Published var verificationComplete: Bool = false
    /// Summary counts for UI display
    var verifiedCount: Int { exerciseVerifications.values.filter { $0 == .verified || $0 == .crossModelVerified }.count }
    var flaggedCount: Int { exerciseVerifications.values.filter { if case .crossModelFlagged = $0 { return true }; return false }.count }
    var totalExerciseCount: Int { rehabPlan?.exercises.count ?? 0 }

    let apiService: ClaudeAPIServiceProtocol
    /// Tier-2 safety check. Injected rather than reached via `.shared` so UI tests can
    /// drive the cross-model failure path (which surfaces `SeriousWarningModal`).
    private let crossModelService: CrossModelVerifying
    private let db = Firestore.firestore()

    init(
        apiService: ClaudeAPIServiceProtocol = ClaudeAPIService.resolved,
        crossModelService: CrossModelVerifying = CrossModelVerificationService.resolved
    ) {
        self.apiService = apiService
        self.crossModelService = crossModelService
    }

    // Fallback exercise database organized by condition name
    private let exerciseDatabase: [String: [RehabExercise]] = [
        "Patellofemoral Pain Syndrome": [
            RehabExercise(id: UUID(), name: "Quad Sets", targetArea: "Knee", description: "Sit with your leg straight. Tighten the muscle on top of your thigh by pressing the back of your knee into the floor. Hold for 5 seconds, then relax.", sets: 3, reps: "10-15", restSeconds: 30, difficulty: .beginner, demonstrationIcon: "figure.flexibility", tips: ["Keep your leg straight.", "Press knee firmly into the floor.", "You should see your kneecap move upward."], contraindications: ["Avoid if acute knee swelling is present."], startPosition: "Sit on the floor or bed with your affected leg straight out in front of you", movement: "Tighten the muscle on top of your thigh by pressing the back of your knee firmly into the floor. Hold for 5 seconds", endPosition: "Release the tension and let your leg rest flat. Repeat.", exerciseCategory: "strength", imageFileName: "quad-sets"),
            RehabExercise(id: UUID(), name: "Straight Leg Raises", targetArea: "Knee", description: "Lie on your back with one knee bent. Keeping the other leg straight, tighten the quad and lift the leg to 45 degrees. Hold 2 seconds, lower slowly.", sets: 3, reps: "10-12", restSeconds: 30, difficulty: .beginner, demonstrationIcon: "figure.strengthtraining.traditional", tips: ["Keep your core engaged.", "Lift slowly and with control.", "Don't arch your back."], contraindications: ["Avoid if hip pain worsens."], startPosition: "Lie on your back with one knee bent and foot flat on the floor. Keep the other leg straight", movement: "Tighten your quad, then slowly lift the straight leg to about 45 degrees. Hold for 2 seconds", endPosition: "Lower the leg slowly back to the floor with control", exerciseCategory: "strength", imageFileName: "straight-leg-raises"),
            RehabExercise(id: UUID(), name: "Wall Sits", targetArea: "Knee", description: "Stand with your back against a wall. Slide down until your knees are bent to about 45 degrees. Hold the position.", sets: 3, reps: "30 seconds", restSeconds: 45, difficulty: .intermediate, demonstrationIcon: "figure.cooldown", tips: ["Keep knees behind toes.", "Press your back flat against the wall.", "Start with a shallow bend and go deeper as you get stronger."], contraindications: ["Avoid deep bending if knee pain increases."], startPosition: "Stand with your back flat against a wall, feet shoulder-width apart and about 2 feet from the wall", movement: "Slowly slide your back down the wall until your knees are bent to about 45 degrees. Hold this position", endPosition: "Slide back up the wall to standing", exerciseCategory: "strength", imageFileName: "wall-sits"),
            RehabExercise(id: UUID(), name: "Clamshells", targetArea: "Hip/Knee", description: "Lie on your side with knees bent to 45 degrees. Keeping your feet together, raise your top knee as high as you can without rotating your pelvis. Lower slowly.", sets: 3, reps: "12-15", restSeconds: 30, difficulty: .beginner, demonstrationIcon: "figure.flexibility", tips: ["Keep your feet together throughout.", "Don't roll your hips backward.", "Focus on squeezing the glute."], contraindications: ["Avoid if hip pain is present."], startPosition: "Lie on your side with knees bent to 45 degrees, feet together, head resting on your arm", movement: "Keeping your feet together, raise your top knee as high as you can without rotating your pelvis", endPosition: "Lower your knee slowly back to the starting position", exerciseCategory: "strength", imageFileName: "clamshells")
        ],
        "Meniscus Tear": [
            RehabExercise(id: UUID(), name: "Heel Slides", targetArea: "Knee", description: "Lie on your back. Slowly slide your heel toward your buttock, bending your knee. Slide back to the starting position.", sets: 3, reps: "10-12", restSeconds: 30, difficulty: .beginner, demonstrationIcon: "figure.flexibility", tips: ["Move slowly and smoothly.", "Only go as far as comfortable.", "Use a towel under your heel to reduce friction."], contraindications: ["Stop if you feel locking or catching."], startPosition: "Lie on your back with both legs straight on the floor", movement: "Slowly slide your heel along the floor toward your buttock, bending your knee as far as comfortable", endPosition: "Slide your heel back to the straight position", exerciseCategory: "mobility", imageFileName: "heel-slides"),
            RehabExercise(id: UUID(), name: "Step-Ups", targetArea: "Knee", description: "Step up onto a low step with your affected leg. Straighten your knee fully, then step back down slowly.", sets: 3, reps: "10", restSeconds: 45, difficulty: .intermediate, demonstrationIcon: "figure.stairs", tips: ["Use a handrail for balance.", "Keep your knee aligned over your toes.", "Control the descent."], contraindications: ["Avoid if knee gives way or locks."], startPosition: "Stand in front of a low step (6-8 inches) with feet hip-width apart", movement: "Step up with your affected leg, pressing through your heel to straighten your knee fully on top", endPosition: "Step back down slowly with control, leading with the unaffected leg", exerciseCategory: "stair", imageFileName: "step-ups")
        ],
        "Rotator Cuff Strain": [
            RehabExercise(id: UUID(), name: "Pendulum Swings", targetArea: "Shoulder", description: "Lean forward with your unaffected hand on a table. Let your affected arm hang down and swing in small circles, then back and forth.", sets: 2, reps: "30 seconds each direction", restSeconds: 30, difficulty: .beginner, demonstrationIcon: "figure.cooldown", tips: ["Keep your arm relaxed.", "Let gravity do the work.", "Gradually increase the circle size."], contraindications: ["Avoid if severe shoulder pain is present."], startPosition: "Lean forward at the waist, supporting yourself with your unaffected hand on a table. Let your affected arm hang straight down", movement: "Gently swing your arm in small circles clockwise, then counterclockwise, then forward and back", endPosition: "Let your arm come to rest hanging straight down", exerciseCategory: "mobility", imageFileName: "pendulum-swings"),
            RehabExercise(id: UUID(), name: "External Rotation", targetArea: "Shoulder", description: "Stand with your elbow bent 90 degrees at your side. Rotate your forearm outward away from your body, keeping elbow tucked.", sets: 3, reps: "12-15", restSeconds: 30, difficulty: .beginner, demonstrationIcon: "figure.strengthtraining.traditional", tips: ["Keep your elbow at your side.", "Move slowly with control.", "Use a light resistance band if available."], contraindications: ["Stop if sharp pain occurs."], startPosition: "Stand with your elbow bent 90 degrees and tucked against your side, forearm pointing forward", movement: "Rotate your forearm outward away from your body while keeping your elbow firmly against your side", endPosition: "Slowly rotate back to the starting position with your forearm pointing forward", exerciseCategory: "strength", imageFileName: "external-rotation"),
            RehabExercise(id: UUID(), name: "Scapular Squeezes", targetArea: "Upper Back/Shoulder", description: "Sit or stand with arms at your sides. Squeeze your shoulder blades together as if pinching a pencil between them. Hold 5 seconds.", sets: 3, reps: "10-12", restSeconds: 30, difficulty: .beginner, demonstrationIcon: "figure.cooldown", tips: ["Keep shoulders down, away from ears.", "Don't shrug.", "Breathe normally while holding."], contraindications: ["Avoid if thoracic spine pain increases."], startPosition: "Sit or stand upright with arms relaxed at your sides, shoulders down", movement: "Squeeze your shoulder blades together as if pinching a pencil between them. Hold for 5 seconds", endPosition: "Slowly release and let your shoulders return to a relaxed position", exerciseCategory: "strength", imageFileName: "scapular-squeezes"),
            RehabExercise(id: UUID(), name: "Wall Slides", targetArea: "Shoulder", description: "Stand with your back against a wall, arms in a goalpost position. Slowly slide arms up the wall overhead, then back down.", sets: 3, reps: "10", restSeconds: 30, difficulty: .intermediate, demonstrationIcon: "figure.flexibility", tips: ["Keep your back flat against the wall.", "Only go as high as comfortable.", "Focus on smooth movement."], contraindications: ["Avoid if impingement symptoms worsen."], startPosition: "Stand with your back against a wall, arms in a goalpost position (elbows bent 90 degrees at shoulder height)", movement: "Slowly slide your arms up the wall overhead, keeping your back and arms in contact with the wall", endPosition: "Slide arms back down to the goalpost position", exerciseCategory: "mobility", imageFileName: "wall-slides")
        ],
        "Muscle Strain": [
            RehabExercise(id: UUID(), name: "Cat-Cow Stretch", targetArea: "Back", description: "On hands and knees, alternate between arching your back up (cat) and letting it sag down (cow). Move slowly with your breath.", sets: 2, reps: "10", restSeconds: 20, difficulty: .beginner, demonstrationIcon: "figure.flexibility", tips: ["Inhale on cow, exhale on cat.", "Move through each position slowly.", "Keep your core lightly engaged."], contraindications: ["Avoid if back pain significantly worsens."], startPosition: "Get on your hands and knees with wrists under shoulders and knees under hips", movement: "Exhale and round your back up toward the ceiling (cat). Then inhale and let your belly drop toward the floor, lifting your head (cow)", endPosition: "Return to a flat-back neutral position on hands and knees", exerciseCategory: "stretch", imageFileName: "cat-cow-stretch"),
            RehabExercise(id: UUID(), name: "Glute Bridges", targetArea: "Back/Glutes", description: "Lie on your back with knees bent. Squeeze your glutes and lift your hips toward the ceiling. Hold 2 seconds at the top.", sets: 3, reps: "12-15", restSeconds: 30, difficulty: .beginner, demonstrationIcon: "figure.strengthtraining.traditional", tips: ["Don't arch your lower back excessively.", "Squeeze glutes at the top.", "Keep your core engaged."], contraindications: ["Avoid if acute back spasm is present."], startPosition: "Lie on your back with knees bent, feet flat on the floor hip-width apart, arms at your sides", movement: "Squeeze your glutes and press through your heels to lift your hips toward the ceiling until your body forms a straight line from shoulders to knees. Hold for 2 seconds", endPosition: "Lower your hips slowly back to the floor", exerciseCategory: "strength", imageFileName: "glute-bridges"),
            RehabExercise(id: UUID(), name: "Bird Dog", targetArea: "Core/Back", description: "On hands and knees, extend one arm forward and the opposite leg backward. Hold for 3 seconds, return, and switch sides.", sets: 3, reps: "8 each side", restSeconds: 30, difficulty: .intermediate, demonstrationIcon: "figure.yoga", tips: ["Keep your back flat like a table.", "Don't rotate your hips.", "Engage your core throughout."], contraindications: ["Modify if shoulder or hip pain occurs."], startPosition: "Get on your hands and knees with a flat back, wrists under shoulders and knees under hips", movement: "Extend your right arm straight forward and your left leg straight back at the same time. Hold for 3 seconds", endPosition: "Return your arm and leg to the floor. Repeat on the opposite side", exerciseCategory: "core", imageFileName: "bird-dog")
        ],
        "Herniated Disc": [
            RehabExercise(id: UUID(), name: "Pelvic Tilts", targetArea: "Lower Back", description: "Lie on your back with knees bent. Flatten your lower back against the floor by tilting your pelvis. Hold 5 seconds.", sets: 3, reps: "10-12", restSeconds: 20, difficulty: .beginner, demonstrationIcon: "figure.flexibility", tips: ["Think of pulling your belly button to your spine.", "Breathe normally.", "The movement is subtle."], contraindications: ["Stop if radiating leg pain worsens."], startPosition: "Lie on your back with knees bent, feet flat on the floor, arms at your sides", movement: "Gently flatten your lower back against the floor by tilting your pelvis upward. Hold for 5 seconds", endPosition: "Relax and let your back return to its natural position", exerciseCategory: "core", imageFileName: "pelvic-tilts"),
            RehabExercise(id: UUID(), name: "Child's Pose", targetArea: "Lower Back", description: "Kneel on the floor, sit back on your heels, and stretch your arms forward on the floor. Hold the position and breathe deeply.", sets: 2, reps: "30 seconds", restSeconds: 20, difficulty: .beginner, demonstrationIcon: "figure.yoga", tips: ["Relax into the stretch.", "Breathe deeply.", "Widen your knees if needed."], contraindications: ["Avoid if knee pain prevents kneeling."], startPosition: "Kneel on the floor with your knees together or slightly apart", movement: "Sit your hips back onto your heels and stretch your arms forward along the floor. Rest your forehead on the ground", endPosition: "Slowly walk your hands back and sit upright", exerciseCategory: "stretch", imageFileName: "childs-pose")
        ],
        "Impingement Syndrome": [
            RehabExercise(id: UUID(), name: "Doorway Stretch", targetArea: "Chest/Shoulder", description: "Stand in a doorway with arms on the frame at 90 degrees. Step forward to stretch the front of your shoulders and chest.", sets: 3, reps: "30 seconds", restSeconds: 20, difficulty: .beginner, demonstrationIcon: "figure.flexibility", tips: ["Keep your core tight.", "Don't lean too far forward.", "You should feel the stretch across your chest."], contraindications: ["Avoid if shoulder pops or clicks."], startPosition: "Stand in a doorway with both arms on the door frame, elbows bent at 90 degrees at shoulder height", movement: "Step one foot forward through the doorway until you feel a gentle stretch across your chest and the front of your shoulders. Hold", endPosition: "Step back to the starting position and relax your arms", exerciseCategory: "stretch", imageFileName: "doorway-stretch")
        ],
        "ACL Sprain": [
            RehabExercise(id: UUID(), name: "Hamstring Curls", targetArea: "Knee/Hamstring", description: "Stand holding a chair for balance. Slowly bend your knee to bring your heel toward your buttock. Lower slowly.", sets: 3, reps: "12-15", restSeconds: 30, difficulty: .beginner, demonstrationIcon: "figure.strengthtraining.traditional", tips: ["Keep your thighs parallel.", "Control the movement.", "Use ankle weights for progression."], contraindications: ["Avoid if knee instability is severe."], startPosition: "Stand upright holding the back of a chair for balance, feet hip-width apart", movement: "Slowly bend your affected knee to bring your heel toward your buttock as far as comfortable", endPosition: "Lower your foot slowly back to the floor with control", exerciseCategory: "strength", imageFileName: "hamstring-curls")
        ]
    ]

    /// Generate a rehab plan using AI, with fallback to hardcoded database
    func generateRehabPlan(from analysisResult: AnalysisResult) {
        guard !isGenerating else { return }

        // Fail fast when offline instead of showing the plan-building spinner for a
        // request that can't succeed (audit #58).
        guard NetworkMonitor.shared.isConnected else {
            generationError = "You're offline. Connect to the internet to build your plan, then try again."
            isGenerating = false
            return
        }

        let conditions = analysisResult.conditions.map { $0.conditionName }

        // Cache original result for potential safer-plan retries.
        self.originalAnalysisResult = analysisResult
        self.saferPlanRetryCount = 0
        self.originalFlaggedExerciseNames = []

        isGenerating = true
        generationError = nil
        // Verification state is keyed by exercise NAME and is only ever written for
        // exercises present in the CURRENT plan, so anything left from a previous
        // plan survives and is rendered against the new one. Clear it up front.
        exerciseVerifications = [:]
        verificationComplete = false

        AppLogger.rehab.info("Starting rehab plan generation for \(conditions.count) condition(s): \(conditions.joined(separator: ", "))")
        // Session logs upload to Firebase; per the privacy policy they must not
        // carry condition names (P1-05). Log the count, not the names.
        SessionLogger.shared.log(.loadingStarted, category: .stateChange, message: "Rehab plan generation started",
                                  metadata: [
                                    "conditionCount": "\(conditions.count)",
                                    "activityLevel": analysisResult.userProfileSnapshot.activityLevel
                                  ])

        Task {
            do {
                AppLogger.rehab.info("Calling AI for rehab plan...")
                let plan = try await generateAIRehabPlan(from: analysisResult)
                AppLogger.rehab.info("AI returned plan '\(plan.planName)' with \(plan.exercises.count) exercises, \(plan.totalWeeks) weeks")

                // Validate the plan (includes knowledge graph check)
                AppLogger.rehab.info("Validating AI rehab plan...")
                let painRegions = analysisResult.assessments.map { $0.selectedRegion.name }
                let (validatedPlan, warnings, graphVerification) = await Task.detached(priority: .userInitiated) {
                    ResponseValidationPipeline.validateRehabPlan(
                        plan,
                        conditions: conditions,
                        userProfile: analysisResult.userProfileSnapshot,
                        userPainRegions: painRegions
                    )
                }.value
                self.rehabPlan = validatedPlan
                self.rehabPlanWarnings = warnings
                self.isGenerating = false

                // Set initial verification statuses from knowledge graph
                if let graphResult = graphVerification {
                    applyGraphVerification(graphResult)
                }

                let exerciseNames = plan.exercises.map { $0.name }
                AppLogger.rehab.info("Rehab plan finalized: \(exerciseNames.joined(separator: ", "))")
                // A rehab plan's exercise prescription reveals health/treatment;
                // keep names out of the uploaded session log (P1-05) — count only.
                SessionLogger.shared.log(.loadingFinished, category: .stateChange, message: "Rehab plan generated (AI)",
                                          metadata: [
                                            "exerciseCount": "\(plan.exercises.count)",
                                            "totalWeeks": "\(plan.totalWeeks)",
                                            "warningCount": "\(warnings.count)",
                                            "source": "ai"
                                          ])

                // Trigger cross-model verification for unverified exercises (async, background)
                if let graphResult = graphVerification, !graphResult.unverifiedExercises.isEmpty {
                    await performCrossModelVerification(
                        unverified: graphResult.unverifiedExercises,
                        conditions: conditions,
                        profile: analysisResult.userProfileSnapshot
                    )
                } else {
                    verificationComplete = true
                }

                // Preload exercise images in background
                ExerciseImageService.shared.preloadImages(for: plan.exercises)
                // Log exercises that don't have images yet
                logMissingImages(exercises: plan.exercises, source: "ai")
            } catch {
                // Fallback to hardcoded database
                AppLogger.rehab.warning("AI rehab generation failed, using fallback: \(error.localizedDescription)")
                // Tier 1 breadcrumb: distinguish schema failures (ai_response_invalid)
                // from network/quota errors in telemetry.
                if let apiError = error as? ClaudeAPIError, apiError.isResponseInvalid {
                    SessionLogger.shared.log(.errorOccurred, category: .api,
                        message: "Rehab plan rejected by server schema (ai_response_invalid)",
                        metadata: ["error_kind": "ai_response_invalid"])
                }
                SessionLogger.shared.log(.stateUpdated, category: .stateChange, message: "Rehab plan using fallback",
                                          metadata: ["source": "fallback", "reason": error.localizedDescription])

                let exercises = conditions.flatMap { exerciseDatabase[$0] ?? [] }
                let matchedConditions = conditions.filter { exerciseDatabase[$0] != nil }
                let unmatchedConditions = conditions.filter { exerciseDatabase[$0] == nil }

                if !unmatchedConditions.isEmpty {
                    AppLogger.rehab.info("No fallback exercises for: \(unmatchedConditions.joined(separator: ", "))")
                }

                let finalExercises: [RehabExercise]
                if exercises.isEmpty {
                    AppLogger.rehab.info("No condition-specific exercises found, using region-aware fallback")
                    finalExercises = getRegionAwareExercises(conditions: conditions)
                } else {
                    finalExercises = exercises
                }

                AppLogger.rehab.info("Fallback plan: \(finalExercises.count) exercises from \(matchedConditions.count) matched condition(s)")

                let weeklySchedule = createWeeklySchedule(
                    for: finalExercises,
                    activityLevel: analysisResult.userProfileSnapshot.activityLevel
                )

                let fallbackPlan = RehabPlan(
                    id: UUID(),
                    planName: "Personalized Rehab Plan",
                    conditions: conditions,
                    exercises: finalExercises,
                    weeklySchedule: weeklySchedule,
                    totalWeeks: 4,
                    createdDate: Date(),
                    notes: nil
                )
                // Validate fallback plan too
                let (validatedFallback, warnings, _) = await Task.detached(priority: .userInitiated) {
                    ResponseValidationPipeline.validateRehabPlan(
                        fallbackPlan,
                        conditions: conditions,
                        userProfile: analysisResult.userProfileSnapshot,
                        userPainRegions: analysisResult.assessments.map { $0.selectedRegion.name }
                    )
                }.value
                self.rehabPlan = validatedFallback
                self.rehabPlanWarnings = warnings
                self.isGenerating = false
                // Fallback exercises are curated — mark all as verified, skip cross-model
                for exercise in validatedFallback.exercises {
                    exerciseVerifications[exercise.name] = .verified
                }
                verificationComplete = true

                // Condition names stay out of the uploaded session log (P1-05) —
                // matched/unmatched counts are enough to diagnose fallback coverage.
                SessionLogger.shared.log(.loadingFinished, category: .stateChange, message: "Rehab plan generated (fallback)",
                                          metadata: [
                                            "exerciseCount": "\(finalExercises.count)",
                                            "source": "fallback",
                                            "matchedConditionCount": "\(matchedConditions.count)",
                                            "unmatchedConditionCount": "\(unmatchedConditions.count)"
                                          ])

                // Preload exercise images in background
                ExerciseImageService.shared.preloadImages(for: finalExercises)
                // Log exercises that don't have images yet
                logMissingImages(exercises: finalExercises, source: "fallback")
            }
        }
    }

    // MARK: - Knowledge Graph & Cross-Model Verification

    /// Apply knowledge graph verification results to the exerciseVerifications dictionary.
    private func applyGraphVerification(_ result: PlanVerificationResult) {
        for (exercise, tier) in result.exerciseResults {
            switch tier {
            case .verified:
                exerciseVerifications[exercise.name] = .verified
            case .contraindicated(let reason):
                exerciseVerifications[exercise.name] = .contraindicated(reason: reason)
            case .unverified:
                exerciseVerifications[exercise.name] = .checking
            }
        }
    }

    /// Perform cross-model verification for exercises the knowledge graph doesn't cover.
    private func performCrossModelVerification(
        unverified: [RehabExercise],
        conditions: [String],
        profile: UserProfile
    ) async {
        isVerifyingUnknowns = true
        AppLogger.rehab.info("Starting cross-model verification for \(unverified.count) unverified exercise(s)")

        let exercisePairs = unverified.flatMap { exercise in
            conditions.map { condition in
                (name: exercise.name, condition: condition)
            }
        }

        let patientContext = "\(profile.age)-year-old \(profile.sex.lowercased()), \(profile.activityLevel.lowercased()) activity level"

        do {
            let results = try await crossModelService.verify(
                exercises: exercisePairs,
                patientContext: patientContext
            )

            // Group results by exercise name and determine overall safety
            var exerciseSafety: [String: (safe: Bool, concerns: [String])] = [:]
            for result in results {
                let current = exerciseSafety[result.exerciseName]
                if let existing = current {
                    // If any condition flags it unsafe, it's unsafe overall
                    exerciseSafety[result.exerciseName] = (
                        safe: existing.safe && result.isSafe,
                        concerns: existing.concerns + result.concerns
                    )
                } else {
                    exerciseSafety[result.exerciseName] = (safe: result.isSafe, concerns: result.concerns)
                }
            }

            // Update verification statuses
            for (exerciseName, safety) in exerciseSafety {
                if safety.safe {
                    exerciseVerifications[exerciseName] = .crossModelVerified
                } else {
                    exerciseVerifications[exerciseName] = .crossModelFlagged(concerns: safety.concerns)
                }
            }

            // Any unverified exercises not in results get marked as failed.
            // Tier 2 PR D: append a `.serious` warning so the acknowledgement
            // modal surfaces via `rehabPlanWarnings`.
            for exercise in unverified {
                if exerciseSafety[exercise.name] == nil {
                    exerciseVerifications[exercise.name] = .crossModelFailed
                    appendCrossModelFailureWarning(exerciseName: exercise.name)
                }
            }

            AppLogger.rehab.info("Cross-model verification complete: \(exerciseSafety.filter { $0.value.safe }.count) safe, \(exerciseSafety.filter { !$0.value.safe }.count) flagged")
        } catch {
            AppLogger.rehab.warning("Cross-model verification failed: \(error.localizedDescription)")
            // All retries exhausted → mark every unverified exercise failed.
            // Tier 2 PR D: each failure now emits a `.serious` warning, which
            // Tier 1's SeriousWarningModal picks up via `rehabPlanWarnings`.
            for exercise in unverified {
                exerciseVerifications[exercise.name] = .crossModelFailed
                appendCrossModelFailureWarning(exerciseName: exercise.name)
            }
        }

        isVerifyingUnknowns = false
        verificationComplete = true
    }

    /// Append a `.serious` warning for a cross-model verification failure, if
    /// one isn't already present for this exercise. Deduplicates so repeated
    /// cross-model runs don't pile up.
    private func appendCrossModelFailureWarning(exerciseName: String) {
        let warning = ResponseValidationPipeline.crossModelFailureWarning(exerciseName: exerciseName)
        // Dedupe by exact message — the helper includes the exercise name in
        // quotes, so message equality implies same exercise.
        if !rehabPlanWarnings.contains(where: { $0.message == warning.message }) {
            rehabPlanWarnings.append(warning)
        }
    }

    // MARK: - AI Rehab Plan Generation

    private func generateAIRehabPlan(from analysisResult: AnalysisResult) async throws -> RehabPlan {
        let userMessage = buildRehabUserMessage(from: analysisResult)

        let responseText = try await apiService.sendMessage(
            requestType: .rehab_plan,
            userMessage: userMessage
        )

        return try parseRehabPlanResponse(
            responseText,
            conditions: analysisResult.conditions.map { $0.conditionName },
            activityLevel: analysisResult.userProfileSnapshot.activityLevel
        )
    }

    func buildRehabUserMessage(from analysisResult: AnalysisResult) -> String {
        let profile = analysisResult.userProfileSnapshot
        let assessedRegions = analysisResult.assessments.map { $0.selectedRegion }

        var message = """
        USER PROFILE:
        - Age: \(profile.age) years old
        - Sex: \(profile.sex)
        - Height: \(profile.heightFeet)'\(profile.heightInches)"
        - Weight: \(Int(profile.weight)) lbs
        - Activity Level: \(profile.activityLevel)
        """

        if let sport = profile.primarySport, !sport.isEmpty {
            message += "\n- Primary Sport/Activity: \(sport)"
        }

        if !profile.medicalConditions.isEmpty {
            message += "\n- Medical Conditions: \(profile.medicalConditions.joined(separator: ", "))"
        }

        if let side = profile.dominantSide {
            message += "\n- Dominant Side: \(side)"
        }

        if let meds = profile.medications, !meds.isEmpty {
            message += "\n- Current Medications: \(meds.joined(separator: ", "))"
        }

        // Medication change history
        if let history = profile.medicationHistory, !history.isEmpty {
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .medium
            let recentChanges = history.suffix(10)
            message += "\n\nMEDICATION HISTORY:"
            for change in recentChanges {
                message += "\n- \(change.action.capitalized) \(change.medication) on \(dateFormatter.string(from: change.date))"
            }
        }

        // Relevance-sorted surgical history
        if !profile.surgeries.isEmpty {
            let classified = HistoryRelevanceFilter.classify(surgeries: profile.surgeries, assessedRegions: assessedRegions)
            let relevant = classified.filter { $0.relevance >= .possiblyRelevant }
            let background = classified.filter { $0.relevance == .backgroundOnly }

            if !relevant.isEmpty {
                message += "\n\nRELEVANT SURGICAL HISTORY:"
                for item in relevant {
                    let s = item.surgery
                    var line = "\n- \(s.name) (\(s.year))"
                    if let area = s.bodyArea, !area.isEmpty { line += ", \(area)" }
                    if let surgeryType = s.surgeryType, !surgeryType.isEmpty { line += " [Type: \(surgeryType)]" }
                    if let causingInjury = s.causingInjury, !causingInjury.isEmpty { line += " [Caused by: \(causingInjury)]" }
                    if let status = s.recoveryStatus { line += " — \(status)" }
                    if let restrictions = s.restrictions, !restrictions.isEmpty { line += " [Restrictions: \(restrictions)]" }
                    if let hasHardware = s.hasHardware {
                        if hasHardware {
                            let details = s.hardwareDetails.flatMap { !$0.isEmpty && $0 != "__not_sure__" ? $0 : nil } ?? "details unknown"
                            line += " [Hardware present: \(details)]"
                        } else {
                            line += " [No hardware]"
                        }
                    }
                    message += line
                }
            }

            // Active restrictions get their own section for rehab
            let withRestrictions = profile.surgeries.filter { $0.restrictions != nil && !($0.restrictions?.isEmpty ?? true) }
            if !withRestrictions.isEmpty {
                message += "\n\nACTIVE POST-SURGICAL RESTRICTIONS:"
                for s in withRestrictions {
                    message += "\n- \(s.name): \(s.restrictions!)"
                }
            }

            if !background.isEmpty {
                let condensed = background.map { "\($0.surgery.name) (\($0.surgery.year))" }.joined(separator: ", ")
                message += "\n\nOTHER SURGICAL HISTORY: \(condensed)"
            }
        }

        // Relevance-sorted injury history
        if !profile.injuries.isEmpty {
            let classified = HistoryRelevanceFilter.classify(injuries: profile.injuries, assessedRegions: assessedRegions)
            let relevant = classified.filter { $0.relevance >= .possiblyRelevant }

            if !relevant.isEmpty {
                message += "\n\nRELEVANT INJURY HISTORY:"
                for item in relevant {
                    let i = item.injury
                    let status = i.isCurrent ? "current" : "past"
                    var line = "\n- \(i.bodyArea): \(i.description) (\(status))"
                    if let recovery = i.recoveryStatus { line += " — \(recovery)" }
                    message += line
                }
            }
        }

        // Red-flag conditions are split into their own block. They must still reach
        // the model (and the downstream contraindication checker keys on condition
        // names, so they stay in `conditions` elsewhere), but they are not things to
        // build a rehab programme around — the correct response to a suspected clot
        // or fracture is evaluation, not exercise selection.
        let differentialConditions = analysisResult.conditions.filter { !$0.isRedFlag }
        let flaggedConditions = analysisResult.conditions.filter { $0.isRedFlag }

        message += "\n\nIDENTIFIED CONDITIONS:\n"

        for condition in differentialConditions {
            message += "- \(condition.conditionName) (Confidence: \(Int(condition.confidence))%)\n"
            message += "  Explanation: \(condition.explanation)\n"
        }

        if !flaggedConditions.isEmpty {
            message += "\n\nSERIOUS FINDINGS — DO NOT PROGRAM FOR THESE:\n"
            for condition in flaggedConditions {
                message += "- \(condition.conditionName): flagged as potentially serious and pending clinical evaluation. "
                message += "Do NOT design exercises to treat or rehabilitate this. Choose conservative, low-load options "
                message += "for the primary complaint and avoid any exercise that loads, stretches, or stresses the affected area.\n"
            }
        }

        // User preferences
        message += "\n\nUSER PREFERENCES (STRICT CONSTRAINTS — must be honoured):"
        message += "\n- Available Equipment: \(preferences.equipment.rawValue) — select ONLY exercises that require this equipment level or less"
        message += "\n- Preferred Session Length: \(preferences.sessionLength.rawValue)"
        message += "\n- Difficulty Preference: \(preferences.difficulty.rawValue)"

        // Safer-plan retry constraint (Tier 1): appended when the user rejected a previous
        // plan that contained contraindicated exercises. We list the flagged names by hand,
        // but the real safety net is the downstream KG + contraindication validation — the
        // AI isn't perfectly reliable at following name-based avoid-lists, so the validator
        // re-runs on the retry output.
        if !originalFlaggedExerciseNames.isEmpty {
            let list = originalFlaggedExerciseNames.joined(separator: ", ")
            message += "\n\nIMPORTANT SAFETY CONSTRAINT: The prior plan included exercises incompatible with this patient's condition(s) or medications. Do NOT return these exercises, their variants, or movements in the same pattern: \(list). Use only safer alternatives that work the same movement category but at safe loading, impact, or stability levels."
        }

        message += "\nPlease create a personalized rehabilitation exercise plan for this patient, taking into account their equipment availability, preferred session length, and difficulty preference."

        return message
    }

    // MARK: - Safer-plan retry (Tier 1)

    /// Regenerate the current plan with a safety constraint instructing Claude to avoid the
    /// specific exercises flagged as `.serious` in the prior plan. Preserves the user's
    /// `preferences` (equipment, session length, difficulty) on the retry.
    ///
    /// Max `maxSaferPlanRetries` attempts; after that, surface a "Contact your PT" state via
    /// `generationError`.
    func regenerateSaferPlan() {
        guard let analysisResult = originalAnalysisResult else {
            AppLogger.rehab.warning("regenerateSaferPlan called with no cached analysis result")
            return
        }
        guard saferPlanRetryCount < Self.maxSaferPlanRetries else {
            generationError = "We weren't able to build a safer plan after multiple attempts. Please contact your physical therapist for a tailored program."
            return
        }

        // Collect exercise names flagged as .serious from the current warnings. The
        // `ExerciseContraindicationChecker` and KG-contraindicated messages embed the
        // exercise name in quotes — parse them out for the avoid-list.
        let flaggedNames = rehabPlanWarnings
            .filter { $0.severity >= .serious }
            .compactMap { extractExerciseName(from: $0.message) }
        // Merge with any prior-round flags so the avoid-list grows monotonically.
        originalFlaggedExerciseNames = Array(Set(originalFlaggedExerciseNames + flaggedNames)).sorted()
        saferPlanRetryCount += 1

        AppLogger.rehab.info("Safer-plan retry \(self.saferPlanRetryCount)/\(Self.maxSaferPlanRetries) — avoiding: \(self.originalFlaggedExerciseNames.joined(separator: ", "))")
        // The avoid-list is exercise names (health-revealing); log the count only.
        SessionLogger.shared.log(.stateUpdated, category: .stateChange, message: "Safer-plan retry requested",
                                  metadata: [
                                    "retryCount": "\(saferPlanRetryCount)",
                                    "avoidedCount": "\(originalFlaggedExerciseNames.count)"
                                  ])

        // Clear current plan state and regenerate via the same entry point — the avoid-list
        // is consumed by `buildRehabUserMessage` via `originalFlaggedExerciseNames`.
        rehabPlan = nil
        rehabPlanWarnings = []
        generationError = nil
        isGenerating = false  // reset so the guard in generateRehabPlan allows entry

        // Preserve retry state across the generateRehabPlan reset by snapshotting.
        let savedRetryCount = saferPlanRetryCount
        let savedAvoidList = originalFlaggedExerciseNames

        generateRehabPlan(from: analysisResult)

        // Restore — generateRehabPlan resets these fields on entry.
        saferPlanRetryCount = savedRetryCount
        originalFlaggedExerciseNames = savedAvoidList
    }

    /// Parse an exercise name out of a warning message. Warning messages from
    /// `ExerciseContraindicationChecker` and `KnowledgeGraphValidator` include the name
    /// in quotes (e.g., `"\"Deep Squat\" may not be appropriate..."`). Returns nil if no
    /// quoted name is present.
    private func extractExerciseName(from message: String) -> String? {
        guard let firstQuote = message.firstIndex(of: "\""),
              let lastQuote = message[message.index(after: firstQuote)...].firstIndex(of: "\"")
        else { return nil }
        let name = message[message.index(after: firstQuote)..<lastQuote]
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : String(trimmed)
    }

    private func parseRehabPlanResponse(_ text: String, conditions: [String], activityLevel: String) throws -> RehabPlan {
        AppLogger.rehab.info("Parsing rehab plan response: \(text.count) characters")
        // Tier 3 PR C: shadow-mode strict parsing (see ShadowModeJSONParser).
        let aiResponse = try ShadowModeJSONParser.parse(
            text,
            as: AIRehabResponse.self,
            requestType: "rehab_plan"
        )

        // Map AI exercises to our model
        let exercises = aiResponse.exercises.map { aiExercise in
            let difficulty: RehabExercise.Difficulty
            switch aiExercise.difficulty.lowercased() {
            case "intermediate": difficulty = .intermediate
            case "advanced": difficulty = .advanced
            default: difficulty = .beginner
            }

            return RehabExercise(
                id: UUID(),
                name: aiExercise.name,
                targetArea: aiExercise.targetArea,
                description: aiExercise.description,
                sets: aiExercise.sets,
                reps: aiExercise.reps,
                restSeconds: aiExercise.restSeconds,
                difficulty: difficulty,
                demonstrationIcon: aiExercise.demonstrationIcon,
                tips: aiExercise.tips,
                contraindications: aiExercise.contraindications,
                startPosition: aiExercise.startPosition,
                movement: aiExercise.movement,
                endPosition: aiExercise.endPosition,
                exerciseCategory: aiExercise.exerciseCategory,
                imageFileName: aiExercise.imageFileName,
                catalogSubstitution: aiExercise.catalogSubstitution,
                notes: aiExercise.notes,
                // Capture the original AI-generated name BEFORE any substitution
                // rewrites happen in `validateRehabPlan`. Preserves the analytics
                // signal "what did Claude generate that we had to substitute?"
                originalAIName: aiExercise.name
            )
        }

        let weeklySchedule = createWeeklySchedule(for: exercises, activityLevel: activityLevel)

        return RehabPlan(
            id: UUID(),
            planName: aiResponse.planName,
            conditions: conditions,
            exercises: exercises,
            weeklySchedule: weeklySchedule,
            totalWeeks: aiResponse.totalWeeks,
            createdDate: Date(),
            notes: aiResponse.notes
        )
    }

    // MARK: - Schedule & Fallback

    func createWeeklySchedule(for exercises: [RehabExercise], activityLevel: String) -> [[String]] {
        let exerciseDays: Int
        switch activityLevel.lowercased() {
        case "sedentary", "lightly active":
            exerciseDays = 3
        case "moderately active":
            exerciseDays = 4
        case "very active", "athlete":
            exerciseDays = 5
        default:
            exerciseDays = 3
        }

        let exerciseIds = exercises.map { $0.id.uuidString }
        var schedule: [[String]] = Array(repeating: [], count: 7)

        // Distribute exercises across the week with rest days
        let dayIndices: [Int]
        switch exerciseDays {
        case 3: dayIndices = [1, 3, 5] // Mon, Wed, Fri
        case 4: dayIndices = [1, 2, 4, 5] // Mon, Tue, Thu, Fri
        case 5: dayIndices = [1, 2, 3, 4, 5] // Mon-Fri
        default: dayIndices = [1, 3, 5]
        }

        for dayIndex in dayIndices {
            schedule[dayIndex] = exerciseIds
        }

        return schedule
    }

    /// Produce fallback exercises targeted to the affected body regions.
    /// Falls back to general exercises when no region can be inferred.
    private func getRegionAwareExercises(conditions: [String]) -> [RehabExercise] {
        var exercises: [RehabExercise] = []
        let joined = conditions.joined(separator: " ").lowercased()

        // Determine the affected region from condition names
        let isLowerBody = ["knee", "ankle", "foot", "hip", "leg", "hamstring", "quad", "calf", "shin", "thigh", "groin", "acl", "mcl", "meniscus", "patella"].contains(where: { joined.contains($0) })
        let isUpperBody = ["shoulder", "elbow", "wrist", "hand", "arm", "rotator", "bicep", "tricep", "forearm"].contains(where: { joined.contains($0) })
        let isBack = ["back", "spine", "disc", "lumbar", "thoracic", "cervical", "sciatica"].contains(where: { joined.contains($0) })
        let isNeck = ["neck", "cervical"].contains(where: { joined.contains($0) })

        if isLowerBody {
            exercises.append(contentsOf: [
                RehabExercise(id: UUID(), name: "Gentle Leg Stretching", targetArea: "Lower Body", description: "Gently stretch your quadriceps, hamstrings, and calves. Hold each stretch for 15-30 seconds.", sets: 2, reps: "5 each side", restSeconds: 15, difficulty: .beginner, demonstrationIcon: "figure.flexibility", tips: ["Never bounce.", "Stretch to mild tension, not pain.", "Breathe deeply throughout."], contraindications: ["Stop if sharp pain occurs."], startPosition: "Stand upright holding a wall or chair for balance", movement: "Gently stretch each major muscle group of the lower body: pull heel to glute for quads, reach for toes for hamstrings, press heel down on a step for calves. Hold each 15-30 seconds", endPosition: "Return to standing and gently shake out each leg", exerciseCategory: "stretch", imageFileName: "gentle-stretching"),
                RehabExercise(id: UUID(), name: "Straight Leg Raises", targetArea: "Lower Body", description: "Lie on your back with one knee bent. Keeping the other leg straight, tighten the quad and lift the leg to 45 degrees. Hold 2 seconds, lower slowly.", sets: 3, reps: "10-12", restSeconds: 30, difficulty: .beginner, demonstrationIcon: "figure.strengthtraining.traditional", tips: ["Keep your core engaged.", "Lift slowly and with control.", "Don't arch your back."], contraindications: ["Avoid if hip pain worsens."], startPosition: "Lie on your back with one knee bent and foot flat on the floor. Keep the other leg straight", movement: "Tighten your quad, then slowly lift the straight leg to about 45 degrees. Hold for 2 seconds", endPosition: "Lower the leg slowly back to the floor with control", exerciseCategory: "strength", imageFileName: "straight-leg-raises"),
                RehabExercise(id: UUID(), name: "Ankle Circles", targetArea: "Lower Body", description: "Sit with one leg extended or elevated. Slowly rotate your ankle in circles, then reverse direction.", sets: 2, reps: "10 each direction", restSeconds: 15, difficulty: .beginner, demonstrationIcon: "figure.flexibility", tips: ["Move slowly and deliberately.", "Make the circles as large as comfortable.", "Keep the rest of your leg still."], contraindications: ["Stop if you feel grinding or sharp pain."], startPosition: "Sit in a chair with one foot slightly off the floor", movement: "Slowly rotate your ankle clockwise for 10 circles, then counterclockwise for 10 circles", endPosition: "Place your foot back on the floor and switch to the other side", exerciseCategory: "mobility", imageFileName: "ankle-circles"),
                RehabExercise(id: UUID(), name: "Glute Bridges", targetArea: "Lower Body", description: "Lie on your back with knees bent. Squeeze your glutes and lift your hips toward the ceiling. Hold 2 seconds at the top.", sets: 3, reps: "12-15", restSeconds: 30, difficulty: .beginner, demonstrationIcon: "figure.strengthtraining.traditional", tips: ["Don't arch your lower back excessively.", "Squeeze glutes at the top.", "Keep your core engaged."], contraindications: ["Avoid if acute back spasm is present."], startPosition: "Lie on your back with knees bent, feet flat on the floor hip-width apart, arms at your sides", movement: "Squeeze your glutes and press through your heels to lift your hips toward the ceiling until your body forms a straight line from shoulders to knees. Hold for 2 seconds", endPosition: "Lower your hips slowly back to the floor", exerciseCategory: "strength", imageFileName: "glute-bridges")
            ])
        }

        if isUpperBody {
            exercises.append(contentsOf: [
                RehabExercise(id: UUID(), name: "Pendulum Swings", targetArea: "Upper Body", description: "Lean forward with your unaffected hand on a table. Let your affected arm hang down and swing in small circles.", sets: 2, reps: "30 seconds each direction", restSeconds: 30, difficulty: .beginner, demonstrationIcon: "figure.cooldown", tips: ["Keep your arm relaxed.", "Let gravity do the work.", "Gradually increase the circle size."], contraindications: ["Avoid if severe pain is present."], startPosition: "Lean forward at the waist, supporting yourself with your unaffected hand on a table. Let your affected arm hang straight down", movement: "Gently swing your arm in small circles clockwise, then counterclockwise, then forward and back", endPosition: "Let your arm come to rest hanging straight down", exerciseCategory: "mobility", imageFileName: "pendulum-swings"),
                RehabExercise(id: UUID(), name: "Wrist Flexion & Extension", targetArea: "Upper Body", description: "Rest your forearm on a table with your hand over the edge. Slowly bend your wrist up and down through a comfortable range.", sets: 2, reps: "10-12", restSeconds: 20, difficulty: .beginner, demonstrationIcon: "figure.flexibility", tips: ["Move slowly.", "Keep your forearm flat on the surface.", "Only go through pain-free range."], contraindications: ["Stop if numbness or tingling occurs."], startPosition: "Sit with your forearm resting on a table, hand hanging over the edge", movement: "Slowly bend your wrist upward as far as comfortable, hold briefly, then slowly bend it downward", endPosition: "Return to neutral wrist position", exerciseCategory: "mobility", imageFileName: "wrist-flexion"),
                RehabExercise(id: UUID(), name: "Scapular Squeezes", targetArea: "Upper Body", description: "Sit or stand with arms at your sides. Squeeze your shoulder blades together as if pinching a pencil between them. Hold 5 seconds.", sets: 3, reps: "10-12", restSeconds: 30, difficulty: .beginner, demonstrationIcon: "figure.cooldown", tips: ["Keep shoulders down, away from ears.", "Don't shrug.", "Breathe normally while holding."], contraindications: ["Avoid if thoracic spine pain increases."], startPosition: "Sit or stand upright with arms relaxed at your sides, shoulders down", movement: "Squeeze your shoulder blades together as if pinching a pencil between them. Hold for 5 seconds", endPosition: "Slowly release and let your shoulders return to a relaxed position", exerciseCategory: "strength", imageFileName: "scapular-squeezes")
            ])
        }

        if isBack {
            exercises.append(contentsOf: [
                RehabExercise(id: UUID(), name: "Cat-Cow Stretch", targetArea: "Back", description: "On hands and knees, alternate between arching your back up (cat) and letting it sag down (cow). Move slowly with your breath.", sets: 2, reps: "10", restSeconds: 20, difficulty: .beginner, demonstrationIcon: "figure.flexibility", tips: ["Inhale on cow, exhale on cat.", "Move through each position slowly.", "Keep your core lightly engaged."], contraindications: ["Avoid if back pain significantly worsens."], startPosition: "Get on your hands and knees with wrists under shoulders and knees under hips", movement: "Exhale and round your back up toward the ceiling (cat). Then inhale and let your belly drop toward the floor, lifting your head (cow)", endPosition: "Return to a flat-back neutral position on hands and knees", exerciseCategory: "stretch", imageFileName: "cat-cow-stretch"),
                RehabExercise(id: UUID(), name: "Pelvic Tilts", targetArea: "Back", description: "Lie on your back with knees bent. Flatten your lower back against the floor by tilting your pelvis. Hold 5 seconds.", sets: 3, reps: "10-12", restSeconds: 20, difficulty: .beginner, demonstrationIcon: "figure.flexibility", tips: ["Think of pulling your belly button to your spine.", "Breathe normally.", "The movement is subtle."], contraindications: ["Stop if radiating leg pain worsens."], startPosition: "Lie on your back with knees bent, feet flat on the floor, arms at your sides", movement: "Gently flatten your lower back against the floor by tilting your pelvis upward. Hold for 5 seconds", endPosition: "Relax and let your back return to its natural position", exerciseCategory: "core", imageFileName: "pelvic-tilts"),
                RehabExercise(id: UUID(), name: "Bird Dog", targetArea: "Back", description: "On hands and knees, extend one arm forward and the opposite leg backward. Hold for 3 seconds, return, and switch sides.", sets: 3, reps: "8 each side", restSeconds: 30, difficulty: .intermediate, demonstrationIcon: "figure.yoga", tips: ["Keep your back flat like a table.", "Don't rotate your hips.", "Engage your core throughout."], contraindications: ["Modify if shoulder or hip pain occurs."], startPosition: "Get on your hands and knees with a flat back, wrists under shoulders and knees under hips", movement: "Extend your right arm straight forward and your left leg straight back at the same time. Hold for 3 seconds", endPosition: "Return your arm and leg to the floor. Repeat on the opposite side", exerciseCategory: "core", imageFileName: "bird-dog")
            ])
        }

        if isNeck {
            exercises.append(contentsOf: [
                RehabExercise(id: UUID(), name: "Neck Tilts", targetArea: "Neck", description: "Slowly tilt your head to one side, bringing your ear toward your shoulder. Hold 15 seconds, then switch sides.", sets: 2, reps: "5 each side", restSeconds: 10, difficulty: .beginner, demonstrationIcon: "figure.flexibility", tips: ["Move slowly and gently.", "Don't force the stretch.", "Keep your shoulders relaxed and down."], contraindications: ["Stop if dizziness or numbness occurs."], startPosition: "Sit or stand upright with your head in a neutral position, looking straight ahead", movement: "Slowly tilt your head to one side, bringing your ear toward your shoulder. Hold for 15 seconds", endPosition: "Slowly return your head to the neutral position. Repeat on the other side", exerciseCategory: "stretch", imageFileName: "neck-tilts"),
                RehabExercise(id: UUID(), name: "Chin Tucks", targetArea: "Neck", description: "Gently pull your chin straight back, creating a 'double chin.' Hold for 5 seconds. This strengthens deep neck flexors.", sets: 3, reps: "10", restSeconds: 15, difficulty: .beginner, demonstrationIcon: "figure.cooldown", tips: ["Keep your eyes level, don't tilt your head.", "Think of sliding your head straight back.", "You should feel a stretch at the base of your skull."], contraindications: ["Stop if pain radiates down your arms."], startPosition: "Sit or stand upright with your head in a neutral position", movement: "Gently draw your chin straight back as if making a double chin, keeping your eyes level. Hold for 5 seconds", endPosition: "Relax and let your head return to its natural position", exerciseCategory: "strength", imageFileName: "chin-tucks")
            ])
        }

        // If no region matched or exercises is still empty, add universal exercises
        if exercises.isEmpty {
            exercises.append(contentsOf: [
                RehabExercise(id: UUID(), name: "Gentle Stretching", targetArea: "Full Body", description: "Perform gentle full-body stretches, holding each for 15-30 seconds. Focus on areas of tightness.", sets: 1, reps: "5-10 minutes", restSeconds: 0, difficulty: .beginner, demonstrationIcon: "figure.flexibility", tips: ["Never bounce while stretching.", "Breathe deeply.", "Stop if you feel sharp pain."], contraindications: ["Avoid stretching acutely injured areas."], startPosition: "Stand upright with feet shoulder-width apart, arms relaxed at your sides", movement: "Slowly reach overhead, then gently bend to each side. Reach for your toes. Hold each stretch for 15-30 seconds", endPosition: "Return to standing upright and shake out your arms and legs", exerciseCategory: "stretch", imageFileName: "gentle-stretching"),
                RehabExercise(id: UUID(), name: "Glute Bridges", targetArea: "Core/Glutes", description: "Lie on your back with knees bent. Squeeze your glutes and lift your hips toward the ceiling. Hold 2 seconds at the top.", sets: 3, reps: "12-15", restSeconds: 30, difficulty: .beginner, demonstrationIcon: "figure.strengthtraining.traditional", tips: ["Don't arch your lower back excessively.", "Squeeze glutes at the top.", "Keep your core engaged."], contraindications: ["Avoid if acute back spasm is present."], startPosition: "Lie on your back with knees bent, feet flat on the floor hip-width apart, arms at your sides", movement: "Squeeze your glutes and press through your heels to lift your hips toward the ceiling until your body forms a straight line from shoulders to knees. Hold for 2 seconds", endPosition: "Lower your hips slowly back to the floor", exerciseCategory: "strength", imageFileName: "glute-bridges"),
                RehabExercise(id: UUID(), name: "Cat-Cow Stretch", targetArea: "Back", description: "On hands and knees, alternate between arching your back up (cat) and letting it sag down (cow). Move slowly with your breath.", sets: 2, reps: "10", restSeconds: 20, difficulty: .beginner, demonstrationIcon: "figure.flexibility", tips: ["Inhale on cow, exhale on cat.", "Move through each position slowly.", "Keep your core lightly engaged."], contraindications: ["Avoid if back pain significantly worsens."], startPosition: "Get on your hands and knees with wrists under shoulders and knees under hips", movement: "Exhale and round your back up toward the ceiling (cat). Then inhale and let your belly drop toward the floor, lifting your head (cow)", endPosition: "Return to a flat-back neutral position on hands and knees", exerciseCategory: "stretch", imageFileName: "cat-cow-stretch")
            ])
        }

        // Always include walking as a baseline exercise
        exercises.append(
            RehabExercise(id: UUID(), name: "Walking", targetArea: "General", description: "Walk at a comfortable pace. Start with 10 minutes and gradually increase duration.", sets: 1, reps: "10-20 minutes", restSeconds: 0, difficulty: .beginner, demonstrationIcon: "figure.walk", tips: ["Wear supportive shoes.", "Walk on flat surfaces.", "Maintain good posture."], contraindications: ["Avoid if weight-bearing causes significant pain."], startPosition: "Stand upright with good posture, shoulders back, wearing supportive shoes", movement: "Walk at a comfortable pace on a flat surface. Swing your arms naturally and breathe evenly", endPosition: "Gradually slow your pace and come to a gentle stop", exerciseCategory: "walking", imageFileName: "walking")
        )

        return exercises
    }

    // MARK: - Missing Image Logging

    /// Logs exercises without exact image matches to Firestore so we know which to generate next.
    /// Includes match metadata (matchType, matchedTo) for fuzzy-matched exercises.
    /// Fire-and-forget — non-blocking, errors are printed to console.
    private func logMissingImages(exercises: [RehabExercise], source: String) {
        let imageService = ExerciseImageService.shared
        let needsLogging = exercises.filter { exercise in
            let match = imageService.resolveImageMatch(for: exercise)
            return match == nil || match?.matchType != .exact
        }
        guard !needsLogging.isEmpty else { return }

        let trulyMissing = needsLogging.filter { imageService.resolveImageMatch(for: $0) == nil }
        let fuzzyMatched = needsLogging.count - trulyMissing.count

        AppLogger.images.info("\(trulyMissing.count) exercise(s) missing images, \(fuzzyMatched) fuzzy-matched: \(needsLogging.map { $0.name }.joined(separator: ", "))")

        Task {
            for exercise in needsLogging {
                let normalizedKey = imageService.normalizeName(exercise.name)
                let match = imageService.resolveImageMatch(for: exercise)

                var data: [String: Any] = [
                    "exerciseName": exercise.name,
                    "normalizedKey": normalizedKey,
                    "matchType": match?.matchType.rawValue ?? "none",
                    "exerciseCategory": exercise.exerciseCategory ?? "unknown",
                    "targetArea": exercise.targetArea,
                    "source": source,
                    "count": FieldValue.increment(Int64(1)),
                    "lastSeen": FieldValue.serverTimestamp()
                ]

                if let matchedTo = match?.key {
                    data["matchedTo"] = matchedTo
                }

                if let imageFile = exercise.imageFileName {
                    data["imageFileName"] = imageFile
                }

                do {
                    let docRef = db.collection("missingExerciseImages").document(normalizedKey)
                    let snapshot = try? await docRef.getDocument()
                    if snapshot?.exists != true {
                        data["firstSeen"] = FieldValue.serverTimestamp()
                    }
                    try await docRef.setData(data, merge: true)
                } catch {
                    AppLogger.images.error("Failed to log missing image for \(exercise.name): \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Firestore

    func savePlanToFirestore() {
        guard let userId = Auth.auth().currentUser?.uid else {
            saveError = "Not signed in"
            AppLogger.rehab.error("Cannot save plan: user not signed in")
            SessionLogger.shared.logError(
                NSError(domain: "RehabPlan", code: -2, userInfo: [NSLocalizedDescriptionKey: "User not signed in"]),
                context: "RehabPlan.savePlanToFirestore"
            )
            return
        }
        guard let plan = rehabPlan else {
            saveError = "No plan to save"
            AppLogger.rehab.error("Cannot save plan: rehabPlan is nil")
            return
        }

        AppLogger.rehab.info("Saving rehab plan '\(plan.planName)' to Firestore (\(plan.exercises.count) exercises)")
        isSaving = true
        saveError = nil

        // Build exercise dictionaries safely
        var exerciseDicts: [[String: Any]] = []
        for exercise in plan.exercises {
            var dict: [String: Any] = [
                "id": exercise.id.uuidString,
                "name": exercise.name,
                "targetArea": exercise.targetArea,
                "description": exercise.description,
                "sets": exercise.sets,
                "reps": exercise.reps,
                "restSeconds": exercise.restSeconds,
                "difficulty": exercise.difficulty.rawValue,
                "demonstrationIcon": exercise.demonstrationIcon,
                "tips": exercise.tips,
                "contraindications": exercise.contraindications
            ]
            if let start = exercise.startPosition { dict["startPosition"] = start }
            if let move = exercise.movement { dict["movement"] = move }
            if let end = exercise.endPosition { dict["endPosition"] = end }
            if let category = exercise.exerciseCategory { dict["exerciseCategory"] = category }
            if let imageFile = exercise.imageFileName { dict["imageFileName"] = imageFile }
            exerciseDicts.append(dict)
        }

        // Flatten weeklySchedule to avoid nested array issues with Firestore
        // Store as a dictionary keyed by day index
        var scheduleDicts: [String: [String]] = [:]
        for (index, dayExercises) in plan.weeklySchedule.enumerated() {
            if !dayExercises.isEmpty {
                scheduleDicts["\(index)"] = dayExercises
            }
        }

        var planData: [String: Any] = [
            "id": plan.id.uuidString,
            "planName": plan.planName,
            "conditions": plan.conditions,
            "exercises": exerciseDicts,
            "weeklySchedule": scheduleDicts,
            "totalWeeks": plan.totalWeeks,
            "createdDate": Timestamp(date: plan.createdDate),
            "planType": plan.planType.rawValue,
            // Persist the version we actually built so the repair-on-load pass
            // doesn't rewrite every freshly saved plan on the next cold start.
            "schemaVersion": plan.schemaVersion
        ]
        if let notes = plan.notes {
            planData["notes"] = notes
        }

        Task {
            do {
                try await db.collection("users").document(userId).collection("rehabPlans")
                    .document(plan.id.uuidString)
                    .setData(planData)
                self.isSaving = false
                self.showSaveSuccess = true
                AnalyticsService.shared.log(.rehabPlanGenerated, parameters: [
                    "exercise_count": plan.exercises.count
                ])
                SessionLogger.shared.log(.firestoreWrite, category: .data, message: "Rehab plan saved",
                                          metadata: ["planId": plan.id.uuidString])
            } catch {
                self.isSaving = false
                self.saveError = error.localizedDescription
                SessionLogger.shared.logError(error, context: "RehabPlanSave")
            }
        }
    }
}
