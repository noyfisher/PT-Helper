import Foundation

// MARK: - Swap Reason

/// Reason the user wants to swap an exercise.
enum SwapReason: String, CaseIterable, Identifiable {
    case tooPainful = "too_painful"
    case noEquipment = "no_equipment"
    case tooDifficult = "too_difficult"
    case other = "other"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .tooPainful: return "Too Painful"
        case .noEquipment: return "No Equipment Available"
        case .tooDifficult: return "Too Difficult"
        case .other: return "Other Reason"
        }
    }

    var icon: String {
        switch self {
        case .tooPainful: return "bolt.heart"
        case .noEquipment: return "dumbbell"
        case .tooDifficult: return "chart.bar.xaxis.ascending"
        case .other: return "ellipsis.circle"
        }
    }
}

// MARK: - AI Response Types

struct AISubstituteResponse: Decodable {
    let substitutes: [AISubstituteExercise]
}

struct AISubstituteExercise: Decodable {
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
    let whyItHelps: String?
    // PR 2: server-side flag/notes for kinetic-chain substitutions.
    let catalogSubstitution: Bool?
    let notes: String?
}

// MARK: - ViewModel

@MainActor
class ExerciseSwapViewModel: ObservableObject {

    // MARK: - Published State

    @Published var selectedReason: SwapReason?
    @Published var isLoading: Bool = false
    @Published var error: String?
    @Published var substitutes: [RehabExercise] = []
    @Published var substituteReasons: [UUID: String] = [:]  // exercise id → whyItHelps text
    @Published var verificationStatuses: [UUID: ExerciseVerificationStatus] = [:]
    /// Tier 1: set true when every candidate across `maxSaferSubstituteRetries` retries
    /// was contraindicated. UI should render a "No safe substitute available" empty state.
    @Published var noSafeSubstituteAvailable: Bool = false

    /// Max retries when the AI keeps returning contraindicated substitutes.
    nonisolated static let maxSaferSubstituteRetries = 3
    /// Per-attempt API timeout (seconds). Total ceiling = 3 × 5s = 15s.
    ///
    /// `nonisolated` because this is a compile-time constant — there's no actor state
    /// to protect, and it's accessed from `Task.sleep` inside detached task groups.
    nonisolated static let substituteFetchTimeoutSeconds: Double = 5.0

    // MARK: - Input

    let exercise: RehabExercise
    let plan: RehabPlan
    let apiService: ClaudeAPIServiceProtocol

    init(exercise: RehabExercise, plan: RehabPlan,
         apiService: ClaudeAPIServiceProtocol = ClaudeAPIService.resolved) {
        self.exercise = exercise
        self.plan = plan
        self.apiService = apiService
    }

    // MARK: - Actions

    /// Fetch substitute exercises from the AI.
    ///
    /// Tier 1: runs KG contraindication verification SYNCHRONOUSLY before assigning
    /// `substitutes`, filters out contraindicated candidates, and retries up to
    /// `maxSaferSubstituteRetries` times (5s timeout per attempt) if every candidate in
    /// a given batch was rejected. Sets `noSafeSubstituteAvailable = true` if retries
    /// are exhausted; the view should render an empty-state card pointing to PT
    /// consultation.
    func fetchSubstitutes() async {
        guard let reason = selectedReason else { return }

        // Fail fast when offline instead of making the user watch a doomed
        // spinner before a generic network error (WS8-01, extends audit #58).
        guard NetworkMonitor.shared.isConnected else {
            error = "You're offline. Connect to the internet to find substitute exercises, then try again."
            isLoading = false
            return
        }

        isLoading = true
        error = nil
        noSafeSubstituteAvailable = false

        SessionLogger.shared.log(.buttonTapped, category: .userAction,
                                  message: "Requested exercise swap",
                                  metadata: ["exercise": exercise.name,
                                              "reason": reason.rawValue])

        let graph = KnowledgeGraphService.shared
        var attemptsUsed = 0
        var lastError: Error?

        while attemptsUsed < Self.maxSaferSubstituteRetries {
            attemptsUsed += 1
            do {
                let response = try await fetchSubstituteResponseWithTimeout()
                let parsed = try parseSubstitutes(from: response)

                // Pre-display contraindication filter: drop any candidate flagged
                // `.contraindicated` by the KG against ANY condition on the plan.
                var safe: [RehabExercise] = []
                var dropped: [RehabExercise] = []
                for candidate in parsed {
                    var isContra = false
                    for condition in plan.conditions {
                        if case .contraindicated = graph.verify(exercise: candidate.name, forCondition: condition) {
                            isContra = true
                            break
                        }
                    }
                    if isContra { dropped.append(candidate) } else { safe.append(candidate) }
                }

                if !dropped.isEmpty {
                    SessionLogger.shared.log(.stateUpdated, category: .api,
                                              message: "Exercise swap dropped contraindicated candidates",
                                              metadata: [
                                                "attempt": "\(attemptsUsed)",
                                                "droppedCount": "\(dropped.count)",
                                                "droppedNames": dropped.map(\.name).joined(separator: ", ")
                                              ])
                }

                if !safe.isEmpty {
                    self.substitutes = safe
                    verifySubstitutes(safe)
                    self.isLoading = false
                    return
                }

                // All candidates contraindicated — try again (up to max retries).
                AppLogger.rehab.info("Exercise swap attempt \(attemptsUsed) returned only contraindicated substitutes; retrying")
            } catch {
                lastError = error
                // Tier 1: ai_response_invalid breadcrumb (server Zod rejection).
                if let apiError = error as? ClaudeAPIError, apiError.isResponseInvalid {
                    SessionLogger.shared.log(.errorOccurred, category: .api,
                        message: "Exercise swap rejected by server schema (ai_response_invalid)",
                        metadata: ["error_kind": "ai_response_invalid", "attempt": "\(attemptsUsed)"])
                }
                SessionLogger.shared.log(.errorOccurred, category: .error,
                                          message: "Exercise swap fetch attempt failed",
                                          metadata: [
                                            "attempt": "\(attemptsUsed)",
                                            "error": error.localizedDescription
                                          ])
                // Break on non-transient errors to avoid hammering a down endpoint.
                if !Self.isTransientError(error) {
                    break
                }
            }
        }

        // Retries exhausted.
        self.isLoading = false
        if let err = lastError {
            self.error = err.localizedDescription
        } else {
            self.noSafeSubstituteAvailable = true
            SessionLogger.shared.log(.stateUpdated, category: .api,
                                      message: "Exercise swap exhausted retries — no safe substitute",
                                      metadata: ["attempts": "\(attemptsUsed)"])
        }
    }

    /// Race `apiService.sendMessage` against a 5s timeout using `withThrowingTaskGroup`.
    /// Throws `ClaudeAPIError.networkError` on timeout, surfacing as a normal transient
    /// error so the retry loop continues.
    private func fetchSubstituteResponseWithTimeout() async throws -> String {
        let message = buildUserMessage()
        return try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask { [apiService] in
                try await apiService.sendMessage(
                    requestType: .exercise_substitute,
                    userMessage: message
                )
            }
            group.addTask {
                try await Task.sleep(for: .seconds(Self.substituteFetchTimeoutSeconds))
                throw ClaudeAPIError.networkError(
                    NSError(domain: "ExerciseSwapViewModel", code: -2,
                            userInfo: [NSLocalizedDescriptionKey: "Substitute request timed out after \(Self.substituteFetchTimeoutSeconds)s"]))
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else {
                throw ClaudeAPIError.networkError(
                    NSError(domain: "ExerciseSwapViewModel", code: -3,
                            userInfo: [NSLocalizedDescriptionKey: "Substitute fetch produced no result"]))
            }
            return first
        }
    }

    /// Network/rate-limit errors are transient and worth retrying. 4xx, decode failures,
    /// auth failures, and config errors are not.
    private static func isTransientError(_ error: Error) -> Bool {
        if let apiError = error as? ClaudeAPIError {
            switch apiError {
            case .networkError, .rateLimited:
                return true
            case .invalidResponse(let statusCode, _):
                return statusCode >= 500  // 5xx is worth retrying; 4xx is not
            case .invalidURL, .decodingError, .noContent, .authenticationRequired:
                return false
            }
        }
        return true  // unknown errors: retry conservatively
    }

    /// Replace the original exercise in the plan with the selected substitute.
    func selectSubstitute(_ substitute: RehabExercise,
                          savedPlansVM: SavedPlansViewModel) -> RehabPlan {
        var updatedPlan = plan
        if let index = updatedPlan.exercises.firstIndex(where: { $0.id == exercise.id }) {
            updatedPlan.exercises[index] = substitute
        }
        updatedPlan.lastModifiedDate = Date()
        savedPlansVM.updatePlan(updatedPlan)

        // The reason set includes "too_painful", which is a health signal about
        // this user rather than a behavioural one. Whether a reason was given is
        // the part the funnel needs; the reason itself stays in the session log,
        // which is owner-scoped and purged on account deletion.
        AnalyticsService.shared.log(.exerciseSwapped, parameters: [
            "has_reason": selectedReason != nil ? "true" : "false"
        ])
        SessionLogger.shared.log(.buttonTapped, category: .userAction,
                                  message: "Exercise swapped",
                                  metadata: [
                                      "originalExercise": exercise.name,
                                      "newExercise": substitute.name,
                                      "reason": selectedReason?.rawValue ?? "unknown",
                                      "planId": plan.id.uuidString
                                  ])

        return updatedPlan
    }

    // MARK: - Private — Message Construction

    func buildUserMessage() -> String {
        let existingNames = plan.exercises
            .filter { $0.id != exercise.id }
            .map { $0.name }
            .joined(separator: ", ")

        return """
        EXERCISE TO REPLACE:
        - Name: \(exercise.name)
        - Target Area: \(exercise.targetArea)
        - Category: \(exercise.exerciseCategory ?? "unknown")
        - Difficulty: \(exercise.difficulty.rawValue)
        - Sets: \(exercise.sets), Reps: \(exercise.reps)

        REASON FOR SWAP: \(selectedReason?.displayName ?? "Not specified")

        PLAN CONTEXT:
        - Conditions: \(plan.conditions.joined(separator: ", "))
        - Other exercises in plan: \(existingNames.isEmpty ? "None" : existingNames)
        """
    }

    // MARK: - Private — Response Parsing

    private func parseSubstitutes(from text: String) throws -> [RehabExercise] {
        // Tier 3 PR C: shadow-mode strict parsing (see ShadowModeJSONParser).
        let aiResponse = try ShadowModeJSONParser.parse(
            text,
            as: AISubstituteResponse.self,
            requestType: "exercise_substitute"
        )

        return aiResponse.substitutes.map { ai in
            let difficulty: RehabExercise.Difficulty = {
                switch ai.difficulty.lowercased() {
                case "intermediate": return .intermediate
                case "advanced": return .advanced
                default: return .beginner
                }
            }()

            let exercise = RehabExercise(
                id: UUID(),
                name: ai.name,
                targetArea: ai.targetArea,
                description: ai.description,
                sets: ai.sets,
                reps: ai.reps,
                restSeconds: ai.restSeconds,
                difficulty: difficulty,
                demonstrationIcon: ai.demonstrationIcon,
                tips: ai.tips,
                contraindications: ai.contraindications,
                startPosition: ai.startPosition,
                movement: ai.movement,
                endPosition: ai.endPosition,
                exerciseCategory: ai.exerciseCategory,
                imageFileName: ai.imageFileName,
                catalogSubstitution: ai.catalogSubstitution,
                notes: ai.notes,
                originalAIName: ai.name
            )

            // Store the whyItHelps text separately (not part of RehabExercise model)
            if let reason = ai.whyItHelps, !reason.isEmpty {
                substituteReasons[exercise.id] = reason
            }

            return exercise
        }
    }

    // MARK: - Private — Knowledge Graph Verification

    private func verifySubstitutes(_ exercises: [RehabExercise]) {
        let graph = KnowledgeGraphService.shared

        for sub in exercises {
            var worstTier: ExerciseVerificationStatus = .checking

            for condition in plan.conditions {
                let tier = graph.verify(exercise: sub.name, forCondition: condition)
                switch tier {
                case .contraindicated(let reason):
                    worstTier = .contraindicated(reason: reason)
                case .verified:
                    if case .contraindicated = worstTier { } else {
                        worstTier = .verified
                    }
                case .unverified:
                    break // keep current worstTier (.checking unless overridden)
                }
            }

            verificationStatuses[sub.id] = worstTier
        }
    }
}
