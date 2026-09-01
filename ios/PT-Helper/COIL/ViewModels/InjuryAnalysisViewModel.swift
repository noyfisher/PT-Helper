import Foundation
import SwiftUI

@MainActor
class InjuryAnalysisViewModel: ObservableObject {
    @Published var assessments: [PainAssessment?]
    @Published var currentRegionIndex: Int = 0
    @Published var analysisResult: AnalysisResult?
    @Published var validationWarnings: [ValidationWarning] = []
    @Published var redFlagAlerts: [ValidationWarning] = []
    @Published var isAnalyzing: Bool = false
    @Published var analysisError: String? = nil
    @Published var showAnalyzingScreen: Bool = false
    @Published var currentStage: InjuryAnalyzer.Stage? = nil

    let userProfile: UserProfile
    let selectedRegions: [BodyRegion]
    private let apiService: ClaudeAPIServiceProtocol
    private(set) var analysisTask: Task<Void, Never>?

    init(userProfile: UserProfile, selectedRegions: [BodyRegion], apiService: ClaudeAPIServiceProtocol = ClaudeAPIService.resolved) {
        self.userProfile = userProfile
        self.selectedRegions = selectedRegions
        self.apiService = apiService
        // Pre-allocate one slot per region (nil = not yet filled)
        self.assessments = Array(repeating: nil, count: selectedRegions.count)
    }

    /// Save (or overwrite) the assessment for the current region.
    func saveCurrentAssessment(_ assessment: PainAssessment) {
        guard currentRegionIndex < selectedRegions.count else { return }
        assessments[currentRegionIndex] = assessment
    }

    /// Save and advance to the next region.
    func saveAndAdvance(_ assessment: PainAssessment) {
        saveCurrentAssessment(assessment)
        if currentRegionIndex < selectedRegions.count - 1 {
            currentRegionIndex += 1
        }
    }

    /// Save current and go back.
    func saveAndGoBack(_ assessment: PainAssessment) {
        saveCurrentAssessment(assessment)
        if currentRegionIndex > 0 {
            currentRegionIndex -= 1
        }
    }

    /// Save the last region and trigger async AI analysis.
    func saveAndAnalyze(_ assessment: PainAssessment) {
        saveCurrentAssessment(assessment)
        startAnalysis()
    }

    /// Apply the given assessment's pain data to all regions, then trigger analysis.
    func applyToAllRegionsAndAnalyze(_ template: PainAssessment) {
        for (index, region) in selectedRegions.enumerated() {
            assessments[index] = PainAssessment(
                id: UUID(),
                selectedRegion: region,
                painTypes: template.painTypes,
                customPainDescription: template.customPainDescription,
                painIntensity: template.painIntensity,
                painDurations: template.painDurations,
                painFrequencies: template.painFrequencies,
                painOnsets: template.painOnsets,
                aggravatingFactors: template.aggravatingFactors,
                relievingFactors: template.relievingFactors,
                additionalNotes: template.additionalNotes,
                currentTreatment: template.currentTreatment
            )
        }
        startAnalysis()
    }

    /// Retry analysis after an error.
    func retryAnalysis() {
        startAnalysis()
    }

    /// Cancel an in-flight analysis and go back to the assessment.
    func cancelAnalysis() {
        analysisTask?.cancel()
        analysisTask = nil
        isAnalyzing = false
        analysisError = nil
        showAnalyzingScreen = false
        currentStage = nil
        redFlagAlerts = []
        validationWarnings = []
    }

    /// Reset all analysis state (used when navigating back to body map).
    func resetAnalysisState() {
        analysisTask?.cancel()
        analysisTask = nil
        isAnalyzing = false
        analysisError = nil
        analysisResult = nil
        showAnalyzingScreen = false
        currentStage = nil
        // AnalyzingView routes to the emergency takeover when it finds red-flag
        // alerts with no in-flight analysis and no result. Leaving these set meant a
        // flag from a PREVIOUS assessment could hijack the next one the moment its
        // analyzing screen appeared. The wellness twin already clears its
        // equivalents — this is the same contract.
        redFlagAlerts = []
        validationWarnings = []
    }

    private func startAnalysis() {
        guard !isAnalyzing else { return }
        let completed = assessments.compactMap { $0 }
        guard !completed.isEmpty else {
            AppLogger.rehab.error("startAnalysis called with no completed assessments")
            SessionLogger.shared.logError(
                NSError(domain: "InjuryAnalysis", code: -1, userInfo: [NSLocalizedDescriptionKey: "No completed assessments"]),
                context: "InjuryAnalysis.startAnalysis"
            )
            return
        }

        // Emergency pre-screen: never send 911-pattern data to the API.
        let preScreen = MedicalRedFlagDetector.check(assessments: completed)
        let emergencyAlerts = preScreen.alerts.filter { $0.severity == .emergency }
        if !emergencyAlerts.isEmpty {
            redFlagAlerts = emergencyAlerts
            analysisResult = nil
            analysisError = nil
            isAnalyzing = false
            showAnalyzingScreen = true
            SessionLogger.shared.log(.stateUpdated, category: .stateChange,
                message: "Emergency pre-screen triggered — analysis blocked",
                metadata: ["alertCount": "\(emergencyAlerts.count)"])
            return
        }

        // Fail fast when offline instead of making the user watch a doomed
        // 15–30s spinner before a generic network error (audit #58).
        guard NetworkMonitor.shared.isConnected else {
            analysisError = "You're offline. Connect to the internet to run your assessment, then tap Try Again."
            isAnalyzing = false
            showAnalyzingScreen = true
            return
        }

        // Pre-flight validation logging
        let regionNames = completed.map { $0.selectedRegion.name }
        let missingFields = completed.enumerated().compactMap { (i, a) -> String? in
            var missing: [String] = []
            if a.painTypes.isEmpty { missing.append("painTypes") }
            if a.painDurations.isEmpty { missing.append("painDurations") }
            if a.painFrequencies.isEmpty { missing.append("painFrequencies") }
            if a.painOnsets.isEmpty { missing.append("painOnsets") }
            return missing.isEmpty ? nil : "region[\(i)](\(a.selectedRegion.name)): \(missing.joined(separator: ","))"
        }

        isAnalyzing = true
        analysisError = nil
        showAnalyzingScreen = true
        currentStage = nil

        AnalyticsService.shared.log(.assessmentCompleted, parameters: ["region_count": completed.count])
        AppLogger.rehab.info("Starting analysis: \(completed.count) region(s) — \(regionNames.joined(separator: ", "))")
        SessionLogger.shared.log(.loadingStarted, category: .stateChange, message: "Analysis started",
                                  metadata: [
                                    "regionCount": "\(completed.count)",
                                    "missingFields": missingFields.isEmpty ? "none" : missingFields.joined(separator: "; ")
                                  ])

        // Snapshot values needed by the detached task before crossing the actor
        // boundary. This avoids capturing `self` implicitly (Swift 6 forbids it
        // inside Sendable closures) and removes a captured-var race between the
        // outer Task's `[weak self]` and the inner Sendable `stageHandler`.
        let profileSnapshot = userProfile
        let apiServiceSnapshot = apiService

        analysisTask = Task { [weak self] in
            let stageHandler: @Sendable (InjuryAnalyzer.Stage) -> Void = { [weak self] stage in
                Task { @MainActor [weak self] in
                    self?.currentStage = stage
                }
            }

            do {
                let validated = try await InjuryAnalyzer.analyze(
                    assessments: completed,
                    profile: profileSnapshot,
                    apiService: apiServiceSnapshot,
                    onStage: stageHandler
                )
                guard !Task.isCancelled else {
                    AppLogger.rehab.info("Analysis task was cancelled after completion")
                    return
                }
                guard let self = self else { return }
                self.analysisResult = validated.result
                self.validationWarnings = validated.validation.warnings
                self.redFlagAlerts = validated.redFlagAlerts
                self.isAnalyzing = false
                self.currentStage = nil

                AnalyticsService.shared.log(.analysisCompleted, parameters: [
                    "condition_count": validated.result.conditions.count,
                    "has_red_flags": !validated.redFlagAlerts.isEmpty
                ])
                AppLogger.rehab.info("Analysis completed: \(validated.result.conditions.count) conditions")
                SessionLogger.shared.log(.loadingFinished, category: .stateChange, message: "Analysis completed",
                                          metadata: [
                                            "conditionCount": "\(validated.result.conditions.count)",
                                            "hasRedFlags": "\(!validated.redFlagAlerts.isEmpty)",
                                            "warningCount": "\(validated.validation.warnings.count)",
                                            "appliedFixes": validated.validation.appliedFixes.joined(separator: "; ")
                                          ])
            } catch is CancellationError {
                AppLogger.rehab.info("Analysis task cancelled by user")
                SessionLogger.shared.log(.stateUpdated, category: .stateChange, message: "Analysis cancelled by user")
            } catch {
                guard !Task.isCancelled else {
                    AppLogger.rehab.info("Analysis task cancelled (error after cancel: \(error.localizedDescription))")
                    return
                }
                guard let self = self else { return }
                self.analysisError = error.localizedDescription
                self.isAnalyzing = false
                self.currentStage = nil

                // Tier 1: dedicated breadcrumb when the server rejected Claude's output
                // via Zod response-schema validation (ai_response_invalid → HTTP 502).
                // Helps distinguish schema failures from network/quota errors in telemetry.
                if let apiError = error as? ClaudeAPIError, apiError.isResponseInvalid {
                    SessionLogger.shared.log(.errorOccurred, category: .api,
                        message: "Injury analysis rejected by server schema (ai_response_invalid)",
                        metadata: ["error_kind": "ai_response_invalid"])
                }
                AnalyticsService.shared.log(.analysisFailed, parameters: ["error_type": String(describing: type(of: error))])
                AppLogger.rehab.error("Analysis failed: \(error.localizedDescription)")
                SessionLogger.shared.logError(error, context: "InjuryAnalysis.startAnalysis")
            }
        }
    }

    /// The assessment saved for the current region (if any), used to restore form state.
    var currentAssessment: PainAssessment? {
        guard currentRegionIndex < assessments.count else { return nil }
        return assessments[currentRegionIndex]
    }

    var currentRegion: BodyRegion? {
        guard currentRegionIndex < selectedRegions.count else { return nil }
        return selectedRegions[currentRegionIndex]
    }

    var isLastRegion: Bool {
        return currentRegionIndex == selectedRegions.count - 1
    }

    var isFirstRegion: Bool {
        return currentRegionIndex == 0
    }

    var hasMultipleRegions: Bool {
        return selectedRegions.count > 1
    }

    var totalRegions: Int {
        return selectedRegions.count
    }

    var selectedRegionNames: [String] {
        return selectedRegions.map { $0.name }
    }
}
