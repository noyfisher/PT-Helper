import Foundation

// MARK: - AI Response Type

/// Decodable wrapper for the Claude form analysis JSON response.
/// Cross-session fields are optional so one decoder handles both the agent
/// payload (which includes them) and the single-call Haiku payload (which doesn't).
struct AIFormFeedbackResponse: Decodable {
    /// `Double`, not `Int`, to match the server contract: `formAnalysisSchema.overallScore`
    /// in `functions/src/response-schemas.ts` is `z.number().min(0).max(100)`, which accepts
    /// fractional values. Decoding a fractional score into `Int` threw and failed the whole
    /// analysis. Rounded to the domain model's `Int` (0–100) at the mapping site below.
    let overallScore: Double
    let verdict: String
    let corrections: [AICorrection]
    let positivePoints: [String]
    let safetyNotes: [String]
    let dataLimitations: [String]?
    let progressTrends: [AIProgressTrend]?
    let recurringIssues: [AIRecurringIssue]?
    let sessionComparison: String?

    struct AICorrection: Decodable {
        let bodyPart: String
        let issue: String
        let howToFix: String
        let severity: String
        let dataReference: String?
    }

    struct AIProgressTrend: Decodable {
        let metric: String
        let direction: String
        let description: String
    }

    struct AIRecurringIssue: Decodable {
        let issue: String
        let sessionsObserved: Int
        let description: String
    }
}

// MARK: - ViewModel

@MainActor
class FormAnalysisViewModel: ObservableObject {

    // MARK: - Published State

    @Published var state: FormAnalysisState = .idle
    @Published var processingProgress: Double = 0

    // MARK: - Dependencies

    private let apiService: ClaudeAPIServiceProtocol
    private let poseDetector: PoseDetectionService
    private let analysisEngine: PoseAnalysisEngine
    private let qualityScorer: DataQualityScorer
    private let ruleEngine: BiomechanicalRuleEngine
    private let store: FormAnalysisStoreProtocol

    /// Minimum PRIOR persisted sessions of the same exercise before the agent
    /// path is tried. Mirrors MINIMUM_FORM_HISTORY_COUNT in functions/src/firestore-queries.ts.
    static let minimumPriorSessionsForAgent = 2

    /// User's medical conditions for contraindication checking.
    var userConditions: [String] = []

    init(
        apiService: ClaudeAPIServiceProtocol = ClaudeAPIService.resolved,
        poseDetector: PoseDetectionService = .shared,
        analysisEngine: PoseAnalysisEngine = .shared,
        qualityScorer: DataQualityScorer = .shared,
        ruleEngine: BiomechanicalRuleEngine = .shared,
        store: FormAnalysisStoreProtocol = FormAnalysisStore.shared
    ) {
        self.apiService = apiService
        self.poseDetector = poseDetector
        self.analysisEngine = analysisEngine
        self.qualityScorer = qualityScorer
        self.ruleEngine = ruleEngine
        self.store = store
    }

    // MARK: - Main Pipeline

    /// Run the full form analysis pipeline: video → pose detection → metrics → AI feedback.
    func analyzeVideo(url: URL, exercise: RehabExercise) async {
        // The recorded video is only consumed on-device by pose detection below.
        // Delete it once analysis finishes so user exercise footage does not
        // accumulate in the app container indefinitely.
        defer { try? FileManager.default.removeItem(at: url) }

        // Fail fast when offline instead of making the user watch a doomed
        // spinner before a generic network error (WS8-01, extends audit #58).
        guard NetworkMonitor.shared.isConnected else {
            state = .error("You're offline. Connect to the internet to analyze your form, then try again.")
            return
        }

        state = .processing(progress: 0)
        processingProgress = 0

        SessionLogger.shared.log(.buttonTapped, category: .userAction,
                                  message: "Form analysis started",
                                  metadata: ["exercise": exercise.name])

        do {
            // Step 1: Get video metadata
            let fps = try await poseDetector.getVideoFPS(from: url)
            let duration = try await poseDetector.getVideoDuration(from: url)

            // Step 2: Detect 3D poses
            let poses = try await poseDetector.detectPoses(from: url) { [weak self] progress in
                self?.processingProgress = progress * 0.7  // 70% of progress is pose detection
                self?.state = .processing(progress: progress * 0.7)
            }

            state = .processing(progress: 0.70)
            processingProgress = 0.70

            // Step 3: Score data quality
            let totalFrames = Int(duration * fps) / 2  // subsample rate of 2
            let dataQuality = qualityScorer.score(
                poses: poses,
                totalVideoFrames: totalFrames,
                exercise: exercise,
                fps: fps
            )

            state = .processing(progress: 0.75)
            processingProgress = 0.75

            // Step 4: Analyze poses (compute metrics)
            let analysisData = analysisEngine.analyze(
                poses: poses,
                exercise: exercise,
                videoFPS: fps,
                videoDuration: duration
            )

            // Step 5: Run biomechanical rule checks
            let ruleCheckResults = ruleEngine.check(metrics: analysisData, exercise: exercise)

            state = .processing(progress: 0.85)
            processingProgress = 0.85

            // Step 6: Build message and get AI feedback (agent-first with fallback)
            state = .analyzing
            let userMessage = buildUserMessage(metrics: analysisData, exercise: exercise, dataQuality: dataQuality)

            let (response, source) = try await fetchAIFeedback(userMessage: userMessage, exercise: exercise)

            // Step 7: Parse AI response
            let feedback = try parseFormFeedback(from: response, exerciseName: exercise.name)

            // Step 8: Run validation pipeline (7 layers).
            // Cross-session text (progressInsights) intentionally bypasses the
            // 7 layers — its structure is zod-validated server-side and its
            // claims reference PRIOR sessions the pipeline has no data for.
            let (pipelineFeedback, validationResult) = FormFeedbackValidationPipeline.validate(
                feedback: feedback,
                metrics: analysisData,
                dataQuality: dataQuality,
                ruleCheckResults: ruleCheckResults,
                exercise: exercise,
                userConditions: userConditions
            )

            // Defensive re-attach: the pipeline threads progressInsights through,
            // but cross-session insight must never be lost to a pipeline rebuild.
            var validatedFeedback = pipelineFeedback
            validatedFeedback.progressInsights = feedback.progressInsights

            let result = ValidatedFormFeedback(
                feedback: validatedFeedback,
                validation: validationResult,
                dataQuality: dataQuality
            )

            // Step 9: Persist a compact record for future cross-session comparison
            // (both AI paths). Persist-after-feedback: the server history query
            // therefore only ever sees PRIOR sessions.
            let record = FormAnalysisRecord.makeRecord(
                metrics: analysisData,
                feedback: validatedFeedback,
                dataQuality: dataQuality,
                source: source
            )
            await store.save(record)

            state = .complete(result)

            // The exercise NAME is condition-revealing in a PT app (a pelvic-floor
            // or post-surgical knee exercise says what is being treated), and
            // AnalyticsService's own contract is behavioural-only. GA4 events are
            // keyed to the Firebase UID and are NOT purged by account deletion,
            // which purges Firestore, Storage and the Auth user only — so this was
            // an irreversible health-linked disclosure to a third-party processor.
            // SessionLogger already redacts the identical "exercise" key.
            // The target area is the coarse signal the funnel actually needs.
            AnalyticsService.shared.log(.formAnalysisCompleted, parameters: [
                "target_area": exercise.targetArea,
                "score": validatedFeedback.overallScore,
                "verdict": validatedFeedback.verdict.rawValue,
                "corrections_count": validatedFeedback.corrections.count,
                "reps_detected": analysisData.detectedRepCount,
                "confidence_level": validationResult.confidenceLevel.rawValue,
                "consistency_issues": validationResult.consistencyIssues.count,
                "data_quality": String(format: "%.2f", dataQuality.overallScore),
                "source": source,
            ])

            SessionLogger.shared.log(.stateUpdated, category: .lifecycle,
                                      message: "Form analysis completed",
                                      metadata: [
                                          "exercise": exercise.name,
                                          "score": "\(validatedFeedback.overallScore)",
                                          "verdict": validatedFeedback.verdict.rawValue,
                                          "repsDetected": "\(analysisData.detectedRepCount)",
                                          "confidenceLevel": validationResult.confidenceLevel.rawValue,
                                          "dataQuality": String(format: "%.2f", dataQuality.overallScore),
                                          "fixes": "\(validationResult.appliedFixes.count)",
                                      ])

        } catch {
            state = .error(error.localizedDescription)

            // Tier 1: ai_response_invalid breadcrumb (server Zod rejection).
            if let apiError = error as? ClaudeAPIError, apiError.isResponseInvalid {
                SessionLogger.shared.log(.errorOccurred, category: .api,
                    message: "Form analysis rejected by server schema (ai_response_invalid)",
                    metadata: ["error_kind": "ai_response_invalid"])
            }
            SessionLogger.shared.log(.errorOccurred, category: .error,
                                      message: "Form analysis failed",
                                      metadata: ["error": error.localizedDescription])
        }
    }

    /// Reset to idle state for a new analysis.
    func reset() {
        state = .idle
        processingProgress = 0
    }

    // MARK: - AI Routing (agent-first with fallback)

    /// Get AI feedback for the current session: try the cross-session managed
    /// agent when enough prior sessions of this exercise exist, fall back to
    /// the single-call form_analysis path on ANY failure. Mirrors
    /// RecoveryInsightsViewModel's agent-then-fallback behavior.
    ///
    /// Returns the raw response text and the path that produced it
    /// ("agent" | "single_call"). Throws only when the FALLBACK path also fails
    /// (handled by analyzeVideo's existing catch). Internal for unit testing.
    func fetchAIFeedback(userMessage: String, exercise: RehabExercise) async throws -> (response: String, source: String) {
        let priorCount = await store.priorSessionCount(exerciseName: exercise.name)

        if priorCount >= Self.minimumPriorSessionsForAgent {
            do {
                let response = try await apiService.requestAgentFormAnalysis(
                    exerciseName: exercise.name,
                    userMessage: userMessage
                )
                return (response, "agent")
            } catch {
                // Silent fallback — any agent failure (network, 4xx/5xx,
                // validation) drops to the existing single-call path.
                SessionLogger.shared.log(.errorOccurred, category: .api,
                                          message: "Form agent failed, falling back to single-call",
                                          metadata: ["error": error.localizedDescription,
                                                      "exercise": exercise.name])
            }
        }

        let response = try await apiService.sendMessage(
            requestType: .form_analysis,
            userMessage: userMessage
        )
        return (response, "single_call")
    }

    // MARK: - Message Construction

    /// Build the structured user message for Claude with exercise context + computed metrics + data quality.
    func buildUserMessage(metrics: FormAnalysisData, exercise: RehabExercise, dataQuality: DataQualityReport? = nil) -> String {
        var message = """
        EXERCISE BEING ANALYZED:
        - Name: \(exercise.name)
        - Target Area: \(exercise.targetArea)
        - Category: \(exercise.exerciseCategory ?? "unknown")
        - Difficulty: \(exercise.difficulty.rawValue)
        - Sets: \(exercise.sets), Reps: \(exercise.reps)
        """

        if let start = exercise.startPosition {
            message += "\n- Start Position: \(start)"
        }
        if let movement = exercise.movement {
            message += "\n- Movement: \(movement)"
        }
        if let end = exercise.endPosition {
            message += "\n- End Position: \(end)"
        }
        if !exercise.tips.isEmpty {
            message += "\n- Tips: \(exercise.tips.joined(separator: "; "))"
        }
        if !exercise.contraindications.isEmpty {
            message += "\n- Contraindications: \(exercise.contraindications.joined(separator: "; "))"
        }

        message += "\n\nVIDEO INFO:"
        message += "\n- Duration: \(String(format: "%.1f", metrics.videoDurationSeconds))s"
        message += "\n- FPS: \(String(format: "%.0f", metrics.videoFPS))"
        message += "\n- Frames processed: \(metrics.totalFramesProcessed)"
        if let height = metrics.bodyHeight {
            message += "\n- Estimated body height: \(String(format: "%.2f", height))m"
        }

        message += "\n\nFORM METRICS (\(metrics.detectedRepCount) reps detected):"

        if metrics.repMetrics.isEmpty {
            message += "\nNo repetitions were detected. The user may have performed a static hold, or the movement range was too small to detect."
        } else {
            for rep in metrics.repMetrics {
                message += "\nRep \(rep.repNumber) (duration: \(rep.durationSeconds)s):"
                for (angleName, range) in rep.keyAngles.sorted(by: { $0.key < $1.key }) {
                    message += "\n  \(angleName): min=\(range.minDegrees)° max=\(range.maxDegrees)° ROM=\(range.rangeOfMotion)°"
                }
            }
        }

        if let symmetry = metrics.symmetry, !symmetry.differencesDegrees.isEmpty {
            message += "\n\nSYMMETRY (global averages):"
            for (joint, diff) in symmetry.differencesDegrees.sorted(by: { $0.key < $1.key }) {
                let leftVal = symmetry.leftAvgAngles["left_\(joint)"] ?? 0
                let rightVal = symmetry.rightAvgAngles["right_\(joint)"] ?? 0
                message += "\n  \(joint): left_avg=\(leftVal)° right_avg=\(rightVal)° diff=\(diff)°"
            }
        }

        if let perRepSym = metrics.perRepSymmetry, !perRepSym.isEmpty {
            message += "\n\nSYMMETRY (per-rep phases):"
            for repSym in perRepSym {
                let allJoints = Set(Array(repSym.atMinAngle.keys) + Array(repSym.atMidAngle.keys) + Array(repSym.atMaxAngle.keys))
                for joint in allJoints.sorted() {
                    let atMin = repSym.atMinAngle[joint].map { "\($0)°" } ?? "n/a"
                    let atMid = repSym.atMidAngle[joint].map { "\($0)°" } ?? "n/a"
                    let atMax = repSym.atMaxAngle[joint].map { "\($0)°" } ?? "n/a"
                    message += "\n  Rep \(repSym.repNumber) \(joint): bottom=\(atMin) mid=\(atMid) top=\(atMax)"
                }
            }
        }

        if !metrics.alignment.isEmpty {
            message += "\n\nALIGNMENT ISSUES:"
            for issue in metrics.alignment {
                message += "\n  \(issue.description) (\(issue.affectedReps)/\(issue.totalReps) reps)"
            }
        }

        if let tempo = metrics.averageTempo {
            message += "\n\nTEMPO:"
            message += "\n  Average: \(tempo)s per rep"
            if let sd = metrics.tempoVariability {
                message += "\n  Variability (SD): \(sd)s"
            }
        }

        if let dq = dataQuality {
            message += "\n\nDATA QUALITY:"
            message += "\n  Overall quality: \(String(format: "%.2f", dq.overallScore)) / 1.00"
            message += "\n  Frame coverage: \(String(format: "%.0f", dq.frameCoverage * 100))%"
            message += "\n  Avg joints per frame: \(String(format: "%.1f", dq.averageJointCount)) / 17"
            message += "\n  Link-length consistency: \(String(format: "%.2f", dq.linkLengthConsistency))"
            message += "\n  Temporal outliers: \(dq.temporalOutlierCount)"
            message += "\n  Minimum data threshold met: \(dq.minimumDataThresholdMet ? "yes" : "NO")"
            if !dq.warnings.isEmpty {
                message += "\n  Warnings: \(dq.warnings.joined(separator: "; "))"
            }
        }

        message += "\n\nAnalyze the user's exercise form based on the metrics above. Provide specific, actionable feedback. For each correction, include a dataReference citing the specific metric."

        return message
    }

    // MARK: - Response Parsing

    /// Internal rather than private so tests can exercise the AI-response decode path.
    /// `analyzeVideo` needs a real video file and pose extraction, so this is the only
    /// reachable seam for asserting on wire-format handling. Same rationale as
    /// `buildUserMessage` above.
    func parseFormFeedback(from text: String, exerciseName: String) throws -> FormFeedback {
        // Tier 3 PR C: shadow-mode strict parsing (see ShadowModeJSONParser).
        let aiResponse = try ShadowModeJSONParser.parse(
            text,
            as: AIFormFeedbackResponse.self,
            requestType: "form_analysis"
        )

        let verdict: FormFeedback.Verdict = {
            switch aiResponse.verdict.lowercased() {
            case "excellent": return .excellent
            case "good": return .good
            case "concern": return .concern
            default: return .needsWork
            }
        }()

        let corrections = aiResponse.corrections.map { correction in
            let severity: FormFeedback.Correction.Severity = {
                switch correction.severity.lowercased() {
                case "minor": return .minor
                case "major": return .major
                default: return .moderate
                }
            }()

            return FormFeedback.Correction(
                bodyPart: correction.bodyPart,
                issue: correction.issue,
                howToFix: correction.howToFix,
                severity: severity,
                dataReference: correction.dataReference
            )
        }

        // Cross-session fields are present only on the agent path.
        var progressInsights: FormProgressInsights?
        if let comparison = aiResponse.sessionComparison, !comparison.isEmpty {
            let trends = (aiResponse.progressTrends ?? []).map { trend in
                let direction: FormProgressInsights.ProgressTrend.Direction = {
                    switch trend.direction.lowercased() {
                    case "improving": return .improving
                    case "declining": return .declining
                    default: return .stable
                    }
                }()
                return FormProgressInsights.ProgressTrend(
                    metric: trend.metric,
                    direction: direction,
                    description: trend.description
                )
            }
            let recurring = (aiResponse.recurringIssues ?? []).map {
                FormProgressInsights.RecurringIssue(
                    issue: $0.issue,
                    sessionsObserved: $0.sessionsObserved,
                    description: $0.description
                )
            }
            progressInsights = FormProgressInsights(
                progressTrends: trends,
                recurringIssues: recurring,
                sessionComparison: comparison
            )
        }

        return FormFeedback(
            exerciseName: exerciseName,
            overallScore: max(0, min(100, Int(aiResponse.overallScore.rounded()))),
            verdict: verdict,
            corrections: corrections,
            positivePoints: aiResponse.positivePoints,
            safetyNotes: aiResponse.safetyNotes,
            dataLimitations: aiResponse.dataLimitations ?? [],
            progressInsights: progressInsights
        )
    }
}
