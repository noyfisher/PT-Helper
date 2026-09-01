import SwiftUI
import Foundation
import FirebaseFirestore
import FirebaseAuth

// MARK: - Intermediate Decodable Types for AI Wellness Plan Response

struct AIWellnessPlanResponse: Decodable {
    let planName: String
    let exercises: [AIWellnessExercise]
    let totalWeeks: Int
    let notes: String?
}

struct AIWellnessExercise: Decodable {
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
    // PR 2: server-side flag/notes for kinetic-chain substitutions.
    let catalogSubstitution: Bool?
    let notes: String?
}

@MainActor
class WellnessPlanViewModel: ObservableObject {
    @Published var wellnessPlan: RehabPlan?
    @Published var rehabPlanWarnings: [ValidationWarning] = []
    @Published var isSaving = false
    @Published var showSaveSuccess = false
    @Published var saveError: String? = nil
    @Published var isGenerating: Bool = false
    @Published var generationError: String? = nil
    @Published var preferences = RehabPlanPreferences()

    // MARK: - Exercise Verification State
    @Published var exerciseVerifications: [String: ExerciseVerificationStatus] = [:]
    @Published var isVerifyingUnknowns: Bool = false
    @Published var verificationComplete: Bool = false
    var verifiedCount: Int { exerciseVerifications.values.filter { $0 == .verified || $0 == .crossModelVerified }.count }
    var flaggedCount: Int { exerciseVerifications.values.filter { if case .crossModelFlagged = $0 { return true }; return false }.count }
    var totalExerciseCount: Int { wellnessPlan?.exercises.count ?? 0 }

    let apiService: ClaudeAPIServiceProtocol
    private let db = Firestore.firestore()

    init(apiService: ClaudeAPIServiceProtocol = ClaudeAPIService.resolved) {
        self.apiService = apiService
    }

    // Fallback wellness exercise database
    private let wellnessFallbackExercises: [RehabExercise] = [
        RehabExercise(id: UUID(), name: "Cat-Cow Stretch", targetArea: "Spine", description: "On hands and knees, alternate between arching your back up (cat) and letting it sag down (cow). Move slowly with your breath.", sets: 2, reps: "10", restSeconds: 20, difficulty: .beginner, demonstrationIcon: "figure.flexibility", tips: ["Inhale on cow, exhale on cat.", "Move through each position slowly.", "Keep your core lightly engaged."], contraindications: ["Avoid if back pain significantly worsens."], startPosition: "Get on your hands and knees with wrists under shoulders and knees under hips", movement: "Exhale and round your back up toward the ceiling (cat). Then inhale and let your belly drop toward the floor, lifting your head (cow)", endPosition: "Return to a flat-back neutral position", exerciseCategory: "stretch", imageFileName: "cat-cow-stretch"),
        RehabExercise(id: UUID(), name: "Seated Shoulder Rolls", targetArea: "Shoulders/Neck", description: "Sit upright and slowly roll your shoulders forward in circles, then backward. This releases tension in the upper body.", sets: 2, reps: "10 each direction", restSeconds: 15, difficulty: .beginner, demonstrationIcon: "figure.seated.side", tips: ["Keep movements slow and controlled.", "Breathe naturally.", "Make the circles as large as comfortable."], contraindications: ["Avoid if sharp shoulder pain occurs."], startPosition: "Sit upright in a chair with feet flat on the floor, arms relaxed at your sides", movement: "Slowly roll both shoulders forward in large circles, then reverse direction and roll backward", endPosition: "Return shoulders to a relaxed neutral position", exerciseCategory: "mobility", imageFileName: "seated-shoulder-rolls"),
        RehabExercise(id: UUID(), name: "Standing Hip Circles", targetArea: "Hips", description: "Stand on one foot and make large circles with your other knee. This improves hip mobility and balance.", sets: 2, reps: "10 each direction per leg", restSeconds: 20, difficulty: .beginner, demonstrationIcon: "figure.flexibility", tips: ["Hold onto something for balance.", "Make circles as large as comfortable.", "Keep your standing leg slightly bent."], contraindications: ["Avoid if hip pain is present."], startPosition: "Stand next to a wall or chair for support, feet hip-width apart", movement: "Lift one knee to hip height and make large circles with your knee, rotating from the hip", endPosition: "Place your foot back on the ground and switch legs", exerciseCategory: "mobility", imageFileName: "standing-hip-circles"),
        RehabExercise(id: UUID(), name: "Deep Breathing Exercise", targetArea: "Core/Relaxation", description: "Sit or lie comfortably. Breathe in slowly through your nose for 4 counts, hold for 4, exhale through mouth for 6. This activates your relaxation response.", sets: 1, reps: "5-10 breaths", restSeconds: 0, difficulty: .beginner, demonstrationIcon: "figure.yoga", tips: ["Place one hand on your chest and one on your belly.", "Focus on belly rising, not chest.", "Exhale longer than you inhale."], contraindications: ["None — safe for everyone."], startPosition: "Sit comfortably or lie on your back with one hand on your chest and one on your belly", movement: "Breathe in slowly through your nose for 4 counts, feeling your belly rise. Hold for 4 counts. Exhale slowly through your mouth for 6 counts", endPosition: "Return to natural breathing and notice how you feel", exerciseCategory: "yoga", imageFileName: "deep-breathing-exercise")
    ]

    /// Generate a wellness plan using AI, with fallback to basic exercises
    func generateWellnessPlan(from wellnessResult: WellnessAnalysisResult) {
        guard !isGenerating else { return }

        let goalCategories = wellnessResult.recommendations.map { $0.goalCategory }

        // Offline: skip the doomed API call and go straight to the same local
        // fallback plan the catch block below builds on a network failure —
        // this VM has a genuine network-free fallback, unlike the other
        // WS8-01 offline guards, so failing fast here would take away a
        // feature that already worked offline (WS8-01, extends audit #58).
        guard NetworkMonitor.shared.isConnected else {
            Task { await applyFallbackPlan(for: wellnessResult, goalCategories: goalCategories, reason: "offline") }
            return
        }

        isGenerating = true
        generationError = nil

        AppLogger.rehab.info("Starting wellness plan generation for \(goalCategories.count) goal(s)")
        SessionLogger.shared.log(.loadingStarted, category: .stateChange, message: "Wellness plan generation started",
                                  metadata: [
                                    "goalCount": "\(goalCategories.count)",
                                    "goals": goalCategories.joined(separator: ", ")
                                  ])

        Task {
            do {
                AppLogger.rehab.info("Calling AI for wellness plan...")
                let plan = try await generateAIWellnessPlan(from: wellnessResult)
                AppLogger.rehab.info("AI returned wellness plan '\(plan.planName)' with \(plan.exercises.count) exercises")

                // Validate the plan — two stages:
                //   (a) validateRehabPlan runs the standard rehab-plan checks (age, meds,
                //       post-surgical, parameter range). Conditions are goal categories so
                //       contraindication lookups target goal names (mostly a no-op).
                //   (b) WellnessPlanValidator re-runs KG contraindication against the user's
                //       *actual* medical conditions, which is the safety-critical check.
                //       Warnings from both stages are merged.
                let conditions = goalCategories
                let (validatedPlan, baseWarnings, graphVerification) = await Task.detached(priority: .userInitiated) {
                    ResponseValidationPipeline.validateRehabPlan(
                        plan,
                        conditions: conditions,
                        userProfile: wellnessResult.userProfileSnapshot
                    )
                }.value
                let planValidatorWarnings = WellnessPlanValidator.validate(
                    exercises: validatedPlan.exercises,
                    conditions: wellnessResult.userProfileSnapshot.medicalConditions
                )
                let warnings = baseWarnings + planValidatorWarnings
                self.wellnessPlan = validatedPlan
                self.rehabPlanWarnings = warnings
                self.isGenerating = false

                // Set initial verification statuses from knowledge graph
                if let graphResult = graphVerification {
                    for (exercise, tier) in graphResult.exerciseResults {
                        switch tier {
                        case .verified:
                            exerciseVerifications[exercise.name] = .verified
                        case .contraindicated(let reason):
                            exerciseVerifications[exercise.name] = .contraindicated(reason: reason)
                        case .unverified:
                            break // Will be handled by cross-model if needed
                        }
                    }
                }

                SessionLogger.shared.log(.loadingFinished, category: .stateChange, message: "Wellness plan generated (AI)",
                                          metadata: [
                                            "exerciseCount": "\(plan.exercises.count)",
                                            "source": "ai"
                                          ])

                verificationComplete = true

                // Preload exercise images
                ExerciseImageService.shared.preloadImages(for: plan.exercises)
            } catch {
                // Tier 1: ai_response_invalid breadcrumb (server Zod rejection).
                if let apiError = error as? ClaudeAPIError, apiError.isResponseInvalid {
                    SessionLogger.shared.log(.errorOccurred, category: .api,
                        message: "Wellness plan rejected by server schema (ai_response_invalid)",
                        metadata: ["error_kind": "ai_response_invalid"])
                }
                await applyFallbackPlan(for: wellnessResult, goalCategories: goalCategories, reason: error.localizedDescription)
            }
        }
    }

    /// Builds and applies the local, network-free fallback wellness plan —
    /// used both when offline (no API call attempted) and when the AI call
    /// fails (`reason` is the caught error's description in that case).
    private func applyFallbackPlan(for wellnessResult: WellnessAnalysisResult, goalCategories: [String], reason: String) async {
        AppLogger.rehab.warning("Using fallback wellness plan: \(reason)")

        let weeklySchedule = createWeeklySchedule(
            for: wellnessFallbackExercises,
            activityLevel: wellnessResult.userProfileSnapshot.activityLevel
        )

        let fallbackPlan = RehabPlan(
            id: UUID(),
            planName: "Wellness Improvement Plan",
            conditions: goalCategories,
            exercises: wellnessFallbackExercises,
            weeklySchedule: weeklySchedule,
            totalWeeks: 4,
            createdDate: Date(),
            notes: nil,
            planType: .wellness,
            sourceGoalCategories: goalCategories
        )

        let (validatedFallback, baseWarnings, _) = await Task.detached(priority: .userInitiated) {
            ResponseValidationPipeline.validateRehabPlan(
                fallbackPlan,
                conditions: goalCategories,
                userProfile: wellnessResult.userProfileSnapshot
            )
        }.value
        let planValidatorWarnings = WellnessPlanValidator.validate(
            exercises: validatedFallback.exercises,
            conditions: wellnessResult.userProfileSnapshot.medicalConditions
        )
        let warnings = baseWarnings + planValidatorWarnings
        self.wellnessPlan = validatedFallback
        self.rehabPlanWarnings = warnings
        self.isGenerating = false
        self.generationError = nil
        for exercise in validatedFallback.exercises {
            exerciseVerifications[exercise.name] = .verified
        }
        verificationComplete = true

        SessionLogger.shared.log(.loadingFinished, category: .stateChange, message: "Wellness plan generated (fallback)",
                                  metadata: ["source": "fallback", "reason": reason])
    }

    // MARK: - AI Wellness Plan Generation

    private func generateAIWellnessPlan(from wellnessResult: WellnessAnalysisResult) async throws -> RehabPlan {
        let userMessage = buildWellnessPlanUserMessage(from: wellnessResult)

        let responseText = try await apiService.sendMessage(
            requestType: .wellness_plan,
            userMessage: userMessage
        )

        return try parseWellnessPlanResponse(
            responseText,
            goalCategories: wellnessResult.recommendations.map { $0.goalCategory },
            activityLevel: wellnessResult.userProfileSnapshot.activityLevel
        )
    }

    func buildWellnessPlanUserMessage(from wellnessResult: WellnessAnalysisResult) -> String {
        let profile = wellnessResult.userProfileSnapshot

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

        if let meds = profile.medications, !meds.isEmpty {
            message += "\n- Current Medications: \(meds.joined(separator: ", "))"
        }

        // Include all surgical history for safety context
        if !profile.surgeries.isEmpty {
            message += "\n\nSURGICAL HISTORY:"
            for s in profile.surgeries {
                var line = "\n- \(s.name) (\(s.year))"
                if let status = s.recoveryStatus { line += " — \(status)" }
                if let restrictions = s.restrictions, !restrictions.isEmpty { line += " [Restrictions: \(restrictions)]" }
                message += line
            }

            let withRestrictions = profile.surgeries.filter { $0.restrictions != nil && !($0.restrictions?.isEmpty ?? true) }
            if !withRestrictions.isEmpty {
                message += "\n\nACTIVE POST-SURGICAL RESTRICTIONS:"
                for s in withRestrictions {
                    message += "\n- \(s.name): \(s.restrictions!)"
                }
            }
        }

        // Include current injuries
        let currentInjuries = profile.injuries.filter { $0.isCurrent }
        if !currentInjuries.isEmpty {
            message += "\n\nCURRENT INJURIES:"
            for i in currentInjuries {
                var line = "\n- \(i.bodyArea): \(i.description)"
                if let recovery = i.recoveryStatus { line += " — \(recovery)" }
                message += line
            }
        }

        message += "\n\nWELLNESS RECOMMENDATIONS:\n"
        for rec in wellnessResult.recommendations {
            message += "\n- \(rec.title) (Priority: \(rec.priorityLevel))"
            message += "\n  Assessment: \(rec.currentStateAssessment)"
            message += "\n  Key Insight: \(rec.keyInsight)"
        }

        message += "\n\nUSER PREFERENCES:"
        message += "\n- Available Equipment: \(preferences.equipment.rawValue)"
        message += "\n- Preferred Session Length: \(preferences.sessionLength.rawValue)"
        message += "\n- Difficulty Preference: \(preferences.difficulty.rawValue)"

        message += "\n\nPlease create a personalized wellness exercise and habit plan based on these recommendations, taking into account their equipment availability, preferred session length, and difficulty preference."

        return message
    }

    private func parseWellnessPlanResponse(_ text: String, goalCategories: [String], activityLevel: String) throws -> RehabPlan {
        // Tier 3 PR C: shadow-mode strict parsing (see ShadowModeJSONParser).
        let aiResponse = try ShadowModeJSONParser.parse(
            text,
            as: AIWellnessPlanResponse.self,
            requestType: "wellness_plan"
        )

        let exercises = aiResponse.exercises.map { aiExercise in
            let difficulty = RehabExercise.Difficulty.parse(aiExercise.difficulty)

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
                originalAIName: aiExercise.name
            )
        }

        let weeklySchedule = createWeeklySchedule(for: exercises, activityLevel: activityLevel)

        return RehabPlan(
            id: UUID(),
            planName: aiResponse.planName,
            conditions: goalCategories,
            exercises: exercises,
            weeklySchedule: weeklySchedule,
            totalWeeks: aiResponse.totalWeeks,
            createdDate: Date(),
            notes: aiResponse.notes,
            planType: .wellness,
            sourceGoalCategories: goalCategories
        )
    }

    // MARK: - Schedule

    private func createWeeklySchedule(for exercises: [RehabExercise], activityLevel: String) -> [[String]] {
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

        let dayIndices: [Int]
        switch exerciseDays {
        case 3: dayIndices = [1, 3, 5]
        case 4: dayIndices = [1, 2, 4, 5]
        case 5: dayIndices = [1, 2, 3, 4, 5]
        default: dayIndices = [1, 3, 5]
        }

        for dayIndex in dayIndices {
            schedule[dayIndex] = exerciseIds
        }

        return schedule
    }

    // MARK: - Firestore

    func savePlanToFirestore() {
        guard let userId = Auth.auth().currentUser?.uid else {
            saveError = "Not signed in"
            return
        }
        guard let plan = wellnessPlan else {
            saveError = "No plan to save"
            return
        }

        isSaving = true
        saveError = nil

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
            "planType": RehabPlan.PlanType.wellness.rawValue,
            // Store the version explicitly rather than relying on the read-side
            // default. Wellness plans skip ImageAvailabilityValidator, so they are
            // legitimately version 1 and the repair-on-load pass should run once —
            // which is now safe because updatePlan preserves planType.
            "schemaVersion": plan.schemaVersion
        ]
        if let notes = plan.notes {
            planData["notes"] = notes
        }
        if let goalCategories = plan.sourceGoalCategories {
            planData["sourceGoalCategories"] = goalCategories
        }

        Task {
            do {
                try await db.collection("users").document(userId).collection("rehabPlans")
                    .document(plan.id.uuidString)
                    .setData(planData)
                self.isSaving = false
                self.showSaveSuccess = true
                AnalyticsService.shared.log(.rehabPlanGenerated, parameters: [
                    "exercise_count": plan.exercises.count,
                    "type": "wellness"
                ])
                SessionLogger.shared.log(.firestoreWrite, category: .data, message: "Wellness plan saved",
                                          metadata: ["planId": plan.id.uuidString])
            } catch {
                self.isSaving = false
                self.saveError = error.localizedDescription
                SessionLogger.shared.logError(error, context: "WellnessPlanSave")
            }
        }
    }
}
