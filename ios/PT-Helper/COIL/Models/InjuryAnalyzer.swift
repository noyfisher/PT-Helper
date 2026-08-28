import Foundation
import os

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "COIL", category: "InjuryAnalyzer")

// MARK: - Intermediate Decodable Types for AI Response

struct AIAnalysisResponse: Decodable {
    let conditions: [AIConditionResult]
    let overallSummary: String
    let disclaimerText: String
}

struct AIConditionResult: Decodable {
    let conditionName: String
    let commonName: String
    let confidence: Double
    let explanation: String
    let whatItMeans: String
    let howToManage: String
    let isRedFlag: Bool
    let redFlagMessage: String?
    let nextSteps: [String]
}

// MARK: - AI-Powered Injury Analyzer

class InjuryAnalyzer {

    /// Backend stages reported to progress callbacks so the UI can reflect real work.
    enum Stage {
        case primaryAnalysis
        case verifyingResults
        case validating
    }

    /// Result of a validated analysis including any safety warnings.
    struct ValidatedAnalysis {
        let result: AnalysisResult
        let validation: ValidationResult
        let redFlagAlerts: [ValidationWarning]
    }

    /// Analyze pain assessments using a two-call AI pipeline, then validate the response.
    ///
    /// Call 1 (Primary Analysis): Structured clinical reasoning with top 5 conditions.
    /// Call 2 (Verification): Devil's advocate review that challenges and refines to top 3.
    /// If Call 2 fails, gracefully falls back to Call 1's result.
    ///
    /// - Parameter onStage: Optional callback invoked when the pipeline enters a new stage.
    ///   Called from a background task; handlers that touch UI state should hop to the main actor.
    static func analyze(
        assessments: [PainAssessment],
        profile: UserProfile,
        apiService: ClaudeAPIServiceProtocol = ClaudeAPIService.resolved,
        onStage: (@Sendable (Stage) -> Void)? = nil
    ) async throws -> ValidatedAnalysis {

        // --- Call 1: Primary Analysis ---
        logger.info("Building primary analysis prompt for \(assessments.count) region(s)")
        let userMessage = buildUserMessage(assessments: assessments, profile: profile)
        logger.debug("Prompt length: \(userMessage.count) characters")

        onStage?(.primaryAnalysis)
        logger.info("Sending primary analysis request to Claude API...")
        let primaryResponseText = try await apiService.sendMessage(
            requestType: .analysis,
            userMessage: userMessage
        )
        logger.info("Primary response: \(primaryResponseText.count) characters")

        logger.info("Parsing primary analysis response...")
        let primaryResult = try parseAnalysisResponse(primaryResponseText, assessments: assessments, profile: profile)
        logger.info("Primary analysis: \(primaryResult.conditions.count) conditions")

        // --- Call 2: Verification (graceful degradation on failure) ---
        let synthesizedResult: AnalysisResult
        do {
            let verificationMessage = buildVerificationMessage(
                originalUserMessage: userMessage,
                primaryResponseJSON: primaryResponseText
            )
            logger.debug("Verification message length: \(verificationMessage.count) characters")

            onStage?(.verifyingResults)
            logger.info("Sending verification request to Claude API...")
            let verifyResponseText = try await apiService.sendMessage(
                requestType: .analysis_verify,
                userMessage: verificationMessage
            )
            logger.info("Verification response: \(verifyResponseText.count) characters")

            logger.info("Parsing verification response...")
            let verifyResult = try parseAnalysisResponse(verifyResponseText, assessments: assessments, profile: profile)
            logger.info("Verification analysis: \(verifyResult.conditions.count) conditions")

            // Synthesize the two results
            synthesizedResult = synthesize(primary: primaryResult, verification: verifyResult, assessments: assessments, profile: profile)
            logger.info("Synthesis complete: \(synthesizedResult.conditions.count) conditions")
        } catch {
            // Graceful degradation: if verification fails, use primary result
            logger.warning("Verification call failed: \(error.localizedDescription). Falling back to primary analysis.")
            Task { @MainActor in
                SessionLogger.shared.log(.stateUpdated, category: .api, message: "Verification fallback to primary",
                                          metadata: ["error": error.localizedDescription])
            }
            synthesizedResult = primaryResult
        }

        // Run validation pipeline (same as before)
        onStage?(.validating)
        logger.info("Running validation pipeline...")
        let (validatedResult, validation, redFlags) = ResponseValidationPipeline.validateAnalysis(
            synthesizedResult,
            assessments: assessments
        )
        logger.info("Validation complete — fixes: \(validation.appliedFixes.count), warnings: \(validation.warnings.count), redFlags: \(redFlags.count)")

        return ValidatedAnalysis(
            result: validatedResult,
            validation: validation,
            redFlagAlerts: redFlags
        )
    }

    // MARK: - User Message Construction

    static func buildUserMessage(assessments: [PainAssessment], profile: UserProfile) -> String {
        let assessedRegions = assessments.map { $0.selectedRegion }

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
            message += "\n- Medical Conditions: \(profile.medicalConditions.map { InputSanitizer.sanitize($0) }.joined(separator: ", "))"
        }

        if let other = profile.otherMedicalConditions, !other.isEmpty {
            message += "\n- Other Medical Conditions: \(InputSanitizer.sanitize(other))"
        }

        if let side = profile.dominantSide {
            message += "\n- Dominant Side: \(side)"
        }

        if let meds = profile.medications, !meds.isEmpty {
            // Custom medications are free text (MedicalHistoryStepView) — sanitize
            // before interpolating into the prompt, like the neighboring fields (P2-06).
            message += "\n- Current Medications: \(meds.map { InputSanitizer.sanitize($0) }.joined(separator: ", "))"
        }

        // Medication change history
        if let history = profile.medicationHistory, !history.isEmpty {
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .medium
            let recentChanges = history.suffix(10)  // Last 10 changes
            message += "\n\nMEDICATION HISTORY:"
            for change in recentChanges {
                message += "\n- \(change.action.capitalized) \(InputSanitizer.sanitize(change.medication)) on \(dateFormatter.string(from: change.date))"
            }
        }

        // Relevance-sorted surgical history
        if !profile.surgeries.isEmpty {
            let classified = HistoryRelevanceFilter.classify(surgeries: profile.surgeries, assessedRegions: assessedRegions)
            let relevant = classified.filter { $0.relevance >= .possiblyRelevant }
            let background = classified.filter { $0.relevance == .backgroundOnly }

            if !relevant.isEmpty {
                message += "\n\nRELEVANT SURGICAL HISTORY (same or related body region):"
                for item in relevant {
                    let s = item.surgery
                    var line = "\n- \(InputSanitizer.sanitize(s.name)) (\(s.year))"
                    if let area = s.bodyArea, !area.isEmpty { line += ", \(area)" }
                    if let surgeryType = s.surgeryType, !surgeryType.isEmpty { line += " [Type: \(InputSanitizer.sanitize(surgeryType))]" }
                    if let causingInjury = s.causingInjury, !causingInjury.isEmpty { line += " [Caused by: \(InputSanitizer.sanitize(causingInjury))]" }
                    if let status = s.recoveryStatus { line += " — \(status)" }
                    if let restrictions = s.restrictions, !restrictions.isEmpty { line += " [Restrictions: \(InputSanitizer.sanitize(restrictions))]" }
                    if let hasHardware = s.hasHardware {
                        if hasHardware {
                            let details = s.hardwareDetails.flatMap { !$0.isEmpty && $0 != "__not_sure__" ? InputSanitizer.sanitize($0) : nil } ?? "details unknown"
                            line += " [Hardware present: \(details)]"
                        } else {
                            line += " [No hardware]"
                        }
                    }
                    message += line
                }
            }

            if !background.isEmpty {
                let condensed = background.map { "\(InputSanitizer.sanitize($0.surgery.name)) (\($0.surgery.year))" }.joined(separator: ", ")
                message += "\n\nOTHER SURGICAL HISTORY: \(condensed)"
            }
        }

        // Relevance-sorted injury history
        if !profile.injuries.isEmpty {
            let classified = HistoryRelevanceFilter.classify(injuries: profile.injuries, assessedRegions: assessedRegions)
            let relevant = classified.filter { $0.relevance >= .possiblyRelevant }
            let background = classified.filter { $0.relevance == .backgroundOnly }

            if !relevant.isEmpty {
                message += "\n\nRELEVANT INJURY HISTORY:"
                for item in relevant {
                    let i = item.injury
                    let status = i.isCurrent ? "current" : "past"
                    var line = "\n- \(InputSanitizer.sanitize(i.bodyArea)): \(InputSanitizer.sanitize(i.description)) (\(status))"
                    if let year = i.year { line += ", \(year)" }
                    if let recovery = i.recoveryStatus { line += " — \(recovery)" }
                    if let saw = i.sawDoctor { line += saw ? ", saw doctor" : ", did not see doctor" }
                    if let pt = i.hadPhysicalTherapy { line += pt ? ", had PT" : ", no PT" }
                    message += line
                }
            }

            if !background.isEmpty {
                let condensed = background.map { "\(InputSanitizer.sanitize($0.injury.bodyArea)): \(InputSanitizer.sanitize($0.injury.description))" }.joined(separator: "; ")
                message += "\n\nOTHER INJURY HISTORY: \(condensed)"
            }
        }

        message += "\n\nPAIN ASSESSMENTS:\n"

        for (index, assessment) in assessments.enumerated() {
            message += """

            --- Region \(index + 1): \(assessment.selectedRegion.name) ---
            - Pain Types: \(assessment.painTypes.joined(separator: ", "))
            """

            if let customDesc = assessment.customPainDescription, !customDesc.isEmpty {
                message += "\n- Patient's Description: \(InputSanitizer.sanitize(customDesc))"
            }

            message += """

            - Pain Intensity: \(assessment.painIntensity)/10
            - Duration: \(assessment.painDurations.joined(separator: ", "))
            - Frequency: \(assessment.painFrequencies.joined(separator: ", "))
            - Onset: \(assessment.painOnsets.joined(separator: ", "))
            """

            if !assessment.aggravatingFactors.isEmpty {
                message += "\n- Aggravating Factors: \(assessment.aggravatingFactors.joined(separator: ", "))"
            }

            if !assessment.relievingFactors.isEmpty {
                message += "\n- Relieving Factors: \(assessment.relievingFactors.joined(separator: ", "))"
            }

            // Treatment context
            if let treatment = assessment.currentTreatment {
                if treatment.hasSeenDoctor {
                    var treatLine = "\n- Has seen doctor"
                    if !treatment.imagingDone.isEmpty {
                        treatLine += "; Imaging: \(treatment.imagingDone.joined(separator: ", "))"
                    }
                    if treatment.hasDiagnosis, let dx = treatment.diagnosisText, !dx.isEmpty {
                        treatLine += "; Diagnosis: \(InputSanitizer.sanitize(dx))"
                    }
                    message += treatLine
                }
                if treatment.currentlyReceivingTreatment {
                    var treatLine = "\n- Currently receiving treatment"
                    if let details = treatment.treatmentDetails, !details.isEmpty {
                        treatLine += ": \(InputSanitizer.sanitize(details))"
                    }
                    message += treatLine
                }
            }

            if let notes = assessment.additionalNotes, !notes.isEmpty {
                message += "\n- Additional Notes: \(InputSanitizer.sanitize(notes))"
            }
        }

        message += "\n\nPlease analyze these symptoms and provide your assessment."

        return message
    }

    // MARK: - Verification Message Construction

    /// Build the user message for the verification call, combining original patient data
    /// with the primary analysis JSON for the verifier to review.
    static func buildVerificationMessage(originalUserMessage: String, primaryResponseJSON: String) -> String {
        return """
        ORIGINAL USER DATA:
        \(originalUserMessage)

        PRIMARY ANALYSIS (from initial review):
        \(primaryResponseJSON)

        Please review the above primary analysis against the patient data. Challenge any anchoring bias, check for missed red flags, validate anatomical consistency, and return your refined top 3 conditions.
        """
    }

    // MARK: - Synthesis

    /// Merge the primary and verification analysis results into a final result.
    ///
    /// - Uses verification's conditions as the base (it had more context).
    /// - Applies agreement bonus (+10 confidence) for conditions present in both.
    /// - Preserves red flags from primary that the verification may have dropped.
    /// - Returns top 3 conditions sorted by confidence.
    static func synthesize(
        primary: AnalysisResult,
        verification: AnalysisResult,
        assessments: [PainAssessment],
        profile: UserProfile
    ) -> AnalysisResult {
        // Build lookup of primary condition names (case-insensitive)
        let primaryNames = Set(primary.conditions.map { $0.conditionName.lowercased() })

        // Build lookup of verification condition names (case-insensitive)
        let verifyNames = Set(verification.conditions.map { $0.conditionName.lowercased() })

        // Start with verification's conditions, apply agreement bonus
        var synthesized: [ConditionResult] = verification.conditions.map { condition in
            let nameKey = condition.conditionName.lowercased()
            if primaryNames.contains(nameKey) {
                // Agreement bonus: both calls identified this condition
                return ConditionResult(
                    id: condition.id,
                    conditionName: condition.conditionName,
                    commonName: condition.commonName,
                    confidence: min(condition.confidence + 10, 100),
                    explanation: condition.explanation,
                    whatItMeans: condition.whatItMeans,
                    howToManage: condition.howToManage,
                    isRedFlag: condition.isRedFlag,
                    redFlagMessage: condition.redFlagMessage,
                    nextSteps: condition.nextSteps
                )
            }
            return condition
        }

        // Safety preservation: re-add red flags from primary that verification dropped
        for primaryCondition in primary.conditions where primaryCondition.isRedFlag {
            let nameKey = primaryCondition.conditionName.lowercased()
            if !verifyNames.contains(nameKey) {
                logger.warning("Re-adding dropped red flag from primary: \(primaryCondition.conditionName)")
                synthesized.append(primaryCondition)
            }
        }

        // Rank by confidence, then keep the ranked head PLUS any red flag that would
        // otherwise fall off the end. A re-added red flag deliberately receives no
        // agreement bonus and no confidence floor — the bonus encodes "both passes
        // agreed", and a rescued flag is by definition one the verifier disagreed
        // with. See ConditionRetentionPolicy.
        let ranked = synthesized.sorted { $0.confidence > $1.confidence }
        let retention = ConditionRetentionPolicy.retain(ranked)
        if retention.rescuedRedFlagCount > 0 {
            logger.warning("Preserved \(retention.rescuedRedFlagCount) red flag(s) beyond the ranked top \(ConditionRetentionPolicy.maxRankedConditions)")
        }
        if retention.droppedRedFlagCount > 0 {
            logger.error("Dropped \(retention.droppedRedFlagCount) red flag(s) over the rescue cap")
        }
        let topConditions = retention.conditions

        // Use verification's summary and disclaimer (it had the most context)
        return AnalysisResult(
            id: UUID(),
            assessments: assessments,
            conditions: topConditions,
            overallSummary: verification.overallSummary,
            disclaimerText: verification.disclaimerText,
            generatedDate: Date(),
            userProfileSnapshot: profile
        )
    }

    // MARK: - Response Parsing

    static func parseAnalysisResponse(_ text: String, assessments: [PainAssessment], profile: UserProfile) throws -> AnalysisResult {
        // Tier 3 PR C: shadow-mode strict parsing. In shadow mode (default),
        // behavior is unchanged from before this PR — strict tried first,
        // permissive fallback on failure, telemetry counter when fallback
        // saves us. Behind `strictJsonParsingV1Enabled`, strict failure
        // throws immediately.
        let aiResponse = try ShadowModeJSONParser.parse(
            text,
            as: AIAnalysisResponse.self,
            requestType: "analysis"
        )

        // Map AI response to our model types
        let conditions = aiResponse.conditions.map { aiCondition in
            ConditionResult(
                id: UUID(),
                conditionName: aiCondition.conditionName,
                commonName: aiCondition.commonName,
                confidence: aiCondition.confidence,
                explanation: aiCondition.explanation,
                whatItMeans: aiCondition.whatItMeans,
                howToManage: aiCondition.howToManage,
                isRedFlag: aiCondition.isRedFlag,
                redFlagMessage: aiCondition.redFlagMessage,
                nextSteps: aiCondition.nextSteps
            )
        }

        return AnalysisResult(
            id: UUID(),
            assessments: assessments,
            conditions: conditions,
            overallSummary: aiResponse.overallSummary,
            disclaimerText: aiResponse.disclaimerText,
            generatedDate: Date(),
            userProfileSnapshot: profile
        )
    }
}
