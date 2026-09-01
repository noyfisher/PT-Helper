import XCTest
@testable import COIL

/// Tier 3 PR E — minimum-viable regression harness.
///
/// Walks `GroundTruth/cases.json`, seeds `MockClaudeAPIService` with each
/// case's golden response, runs the full validation pipeline, and asserts
/// the pipeline output matches the case's `expectedOutcomes`.
///
/// What this catches: PIPELINE drift. If we change a validator and a
/// previously-passing case starts failing, the change is either correct
/// (and the case needs updating) or a regression (and the change needs
/// reverting). Either way the failure surfaces.
///
/// What this does NOT catch:
///   - Real model behavior changes. Goldens are pinned via
///     `cases.json.modelVersion`; if it drifts from `APIConfig.currentModel`,
///     `test_modelVersionMatchesAPIConfig` fails LOUDLY rather than letting
///     the suite run against stale fixtures.
///   - Clinical accuracy. Goldens are dev-authored, not PT-reviewed. See
///     the cases.json `_NOTE` and Tier 3B.
///
/// Runs as part of `xcodebuild test -testPlan PreReleasePlan` (CI surface
/// is broader than SmokePlan but narrower than FullPlan, matching the
/// regression-harness purpose).
@MainActor
final class ValidationRegressionRunner: XCTestCase {

    // MARK: - Case loading

    private struct CasesFile: Decodable {
        let version: String
        let modelVersion: String
        let cases: [Case]
    }

    private struct Case: Decodable {
        let id: String
        let description: String
        let patient: Patient
        let goldenAnalysisResponse: AIAnalysisResponseFixture?
        let goldenVerifyResponse: AIAnalysisResponseFixture?
        let rawGoldenResponse: String?
        let expectedOutcomes: ExpectedOutcomes
    }

    private struct Patient: Decodable {
        let age: Int
        let sex: String
        let primaryRegion: String
        let painIntensity: Int
        let painOnset: String
        let aggravatingFactors: [String]
        let relievingFactors: [String]
        let medicalConditions: [String]
        let medications: [String]
    }

    /// Mirror of `AIAnalysisResponse` shape — kept independent so a future
    /// rename of the production type doesn't silently break fixture loading.
    /// `Codable` (not just `Decodable`) so we can encode the fixture back to
    /// JSON when seeding the mock service.
    private struct AIAnalysisResponseFixture: Codable {
        struct Condition: Codable {
            let conditionName: String
            let commonName: String
            let confidence: Double
            let explanation: String
            let whatItMeans: String
            let howToManage: String
            let isRedFlag: Bool
            let redFlagMessage: String
            let nextSteps: [String]
        }
        let conditions: [Condition]
        let overallSummary: String
        let disclaimerText: String
    }

    private struct ExpectedOutcomes: Decodable {
        let minConditionCount: Int?
        let maxConditionCount: Int?
        let expectedConditionKeywords: [String]?
        let shouldHaveRedFlags: Bool?
        let validationShouldBeValid: Bool?
        let shouldTriggerSymptomRedFlag: Bool?
        let expectedRedFlagSeverity: String?
        let expectedRedFlagKeywords: [String]?
        let shouldTriggerNoSelfManage: Bool?
        let expectedShadowFallbackUsed: Bool?
    }

    private static func loadCases() throws -> CasesFile {
        let bundle = Bundle(for: ValidationRegressionRunner.self)
        guard let url = bundle.url(forResource: "cases", withExtension: "json") else {
            throw NSError(
                domain: "ValidationRegressionRunner",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "cases.json not in test bundle. Add it via Target Membership → COILTests."]
            )
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(CasesFile.self, from: data)
    }

    // MARK: - Model-version guard

    /// Loud failure when the cases file's pinned model differs from
    /// production. Per the Tier 3 plan, golden responses are model-specific
    /// — running the suite against stale goldens after a model rotation
    /// would silently pass-or-fail meaninglessly. Make the regression run
    /// REFUSE rather than silently mislead.
    func test_00_modelVersionMatchesAPIConfig() throws {
        let cases = try Self.loadCases()
        XCTAssertEqual(
            cases.modelVersion,
            APIConfig.currentModel,
            """
            cases.json's pinned model (\(cases.modelVersion)) does not match
            APIConfig.currentModel (\(APIConfig.currentModel)).

            The committed golden responses were captured against a different
            model. Re-capture them, then update cases.json's modelVersion.
            DO NOT just sync the strings — that defeats the purpose of the pin.
            """
        )
    }

    // MARK: - Per-case execution

    func test_01_pfpsClean() async throws {
        try await runCase(id: "01-pfps-clean")
    }

    func test_02_cardiacEmergency() async throws {
        try await runCase(id: "02-cardiac-emergency")
    }

    func test_03_osteoporosisBalanceComorbidity() async throws {
        try await runCase(id: "03-osteoporosis-balance-comorbidity")
    }

    func test_04_malformedWithPreamble() async throws {
        try await runCase(id: "04-malformed-with-preamble")
    }

    func test_05_noselfManageKeyword() async throws {
        try await runCase(id: "05-noselfmanage-keyword")
    }

    func test_06_rotatorCuffStrain() async throws { try await runCase(id: "06-rotator-cuff-strain") }
    func test_07_frozenShoulder() async throws { try await runCase(id: "07-frozen-shoulder") }
    func test_08_meniscusTear() async throws { try await runCase(id: "08-meniscus-tear") }
    func test_09_ankleSprain() async throws { try await runCase(id: "09-ankle-sprain") }
    func test_10_tennisElbow() async throws { try await runCase(id: "10-tennis-elbow") }
    func test_11_plantarFasciitis() async throws { try await runCase(id: "11-plantar-fasciitis") }
    func test_12_cervicalRadiculopathy() async throws { try await runCase(id: "12-cervical-radiculopathy") }
    func test_13_elderlyKneeOA() async throws { try await runCase(id: "13-elderly-knee-oa") }
    func test_14_postpartumBack() async throws { try await runCase(id: "14-postpartum-back") }
    func test_15_youngAthleteAclRecovery() async throws { try await runCase(id: "15-young-athlete-acl-recovery") }
    func test_16_diabetesPvdFoot() async throws { try await runCase(id: "16-diabetes-pvd-foot") }
    func test_17_cardiacHtnBack() async throws { try await runCase(id: "17-cardiac-htn-back") }
    func test_18_bloodthinnerBalanceBack() async throws { try await runCase(id: "18-bloodthinner-balance-back") }
    func test_19_postsurgicalCardiacShoulder() async throws { try await runCase(id: "19-postsurgical-cardiac-shoulder") }
    func test_20_caudaEquinaSaddle() async throws { try await runCase(id: "20-cauda-equina-saddle") }
    func test_21_strokeOnset() async throws { try await runCase(id: "21-stroke-onset") }
    func test_22_fractureDeformity() async throws { try await runCase(id: "22-fracture-deformity") }
    func test_23_recentAclSurgeryHistory() async throws { try await runCase(id: "23-recent-acl-surgery-history") }
    func test_24_osteoporosisOnMedsKnee() async throws { try await runCase(id: "24-osteoporosis-on-meds-knee") }
    func test_25_bloodthinnerFallHistory() async throws { try await runCase(id: "25-bloodthinner-fall-history") }

    // MARK: - Runner core

    private func runCase(id caseId: String) async throws {
        let cases = try Self.loadCases()
        guard let testCase = cases.cases.first(where: { $0.id == caseId }) else {
            XCTFail("Case '\(caseId)' missing from cases.json")
            return
        }

        // Build mock service seeded with the golden response.
        let mock = MockClaudeAPIService()
        let goldenText = try goldenAsText(for: testCase)

        if let expectedFallback = testCase.expectedOutcomes.expectedShadowFallbackUsed {
            assertShadowFallback(expectedFallback, rawResponse: goldenText, caseId: caseId)
        }
        if let verify = testCase.goldenVerifyResponse {
            // Two-call pipeline: queue analysis + verify responses in order.
            let verifyText = try encodeFixture(verify)
            mock.responsesQueue = [goldenText, verifyText]
        } else {
            // Single-call (or analysis-only) — seed both queue and fallback.
            mock.responsesQueue = [goldenText, goldenText]
            mock.responseToReturn = goldenText
        }

        // Build the patient/profile/assessment objects from the case.
        let profile = makeProfile(from: testCase.patient)
        let assessments = [makeAssessment(from: testCase.patient)]

        // Run the full pipeline. Some cases may legitimately throw when
        // the AI emits malformed content the parser can't recover from;
        // we don't expect that for our v1 fixtures.
        let validated: InjuryAnalyzer.ValidatedAnalysis
        do {
            validated = try await InjuryAnalyzer.analyze(
                assessments: assessments,
                profile: profile,
                apiService: mock
            )
        } catch {
            XCTFail("Case '\(caseId)' threw unexpectedly: \(error)")
            return
        }

        // Assert against expected outcomes.
        try assertOutcomes(testCase.expectedOutcomes, validated: validated, caseId: caseId)
    }

    // MARK: - Outcome assertions

    private func assertOutcomes(
        _ expected: ExpectedOutcomes,
        validated: InjuryAnalyzer.ValidatedAnalysis,
        caseId: String
    ) throws {
        let conditions = validated.result.conditions
        let conditionNames = conditions.map { $0.commonName.lowercased() + " " + $0.conditionName.lowercased() }
        let allConditionText = conditionNames.joined(separator: " ")

        if let minCount = expected.minConditionCount {
            XCTAssertGreaterThanOrEqual(
                conditions.count, minCount,
                "[\(caseId)] expected ≥\(minCount) conditions, got \(conditions.count)"
            )
        }
        if let maxCount = expected.maxConditionCount {
            XCTAssertLessThanOrEqual(
                conditions.count, maxCount,
                "[\(caseId)] expected ≤\(maxCount) conditions, got \(conditions.count)"
            )
        }
        if let keywords = expected.expectedConditionKeywords {
            for keyword in keywords {
                XCTAssertTrue(
                    allConditionText.contains(keyword.lowercased()),
                    "[\(caseId)] expected condition matching '\(keyword)', got: \(conditionNames)"
                )
            }
        }
        if expected.shouldHaveRedFlags == true {
            XCTAssertFalse(
                validated.redFlagAlerts.isEmpty,
                "[\(caseId)] expected red flag alerts, got none"
            )
        }
        if expected.shouldHaveRedFlags == false {
            XCTAssertTrue(
                validated.redFlagAlerts.isEmpty,
                "[\(caseId)] expected no red flag alerts, got \(validated.redFlagAlerts.count)"
            )
        }
        if expected.validationShouldBeValid == true {
            XCTAssertTrue(
                validated.validation.isValid,
                "[\(caseId)] expected validation.isValid, got false. Warnings: \(validated.validation.warnings.map(\.message))"
            )
        }
        if expected.shouldTriggerSymptomRedFlag == true {
            XCTAssertFalse(
                validated.redFlagAlerts.isEmpty,
                "[\(caseId)] expected MedicalRedFlagDetector to fire, got no alerts"
            )
        }
        if let severityRaw = expected.expectedRedFlagSeverity {
            let expectedSeverity: ValidationSeverity
            switch severityRaw {
            case "info":      expectedSeverity = .info
            case "caution":   expectedSeverity = .caution
            case "serious":   expectedSeverity = .serious
            case "urgent":    expectedSeverity = .urgent
            case "emergency": expectedSeverity = .emergency
            default:
                XCTFail("[\(caseId)] unknown expectedRedFlagSeverity '\(severityRaw)'")
                return
            }
            let allSeverities = (validated.redFlagAlerts + validated.validation.warnings).map(\.severity)
            XCTAssertTrue(
                allSeverities.contains(expectedSeverity),
                "[\(caseId)] expected severity \(severityRaw), got \(allSeverities)"
            )
        }
        if let keywords = expected.expectedRedFlagKeywords {
            let allText = (validated.redFlagAlerts + validated.validation.warnings)
                .map { $0.message.lowercased() }
                .joined(separator: " ")
            for keyword in keywords {
                XCTAssertTrue(
                    allText.contains(keyword.lowercased()),
                    "[\(caseId)] expected red-flag text matching '\(keyword)' in: \(allText)"
                )
            }
        }
        if expected.shouldTriggerNoSelfManage == true {
            // The pipeline's checkConditions adds the noSelfManage warning to
            // `redFlagAlerts`, not to `validation.warnings`. The message
            // contains "professional medical treatment".
            let alertText = validated.redFlagAlerts.map { $0.message.lowercased() }
            XCTAssertTrue(
                alertText.contains(where: { $0.contains("professional medical treatment") }),
                "[\(caseId)] expected noSelfManage red-flag alert, got: \(alertText)"
            )
        }
    }

    /// Assert `expectedShadowFallbackUsed`, which was decoded from `cases.json` and
    /// then never checked — leaving case `04-malformed-with-preamble` declaring an
    /// expectation nothing enforced.
    ///
    /// `ShadowModeJSONParser.parse` returns the decoded value whether or not the
    /// permissive path saved it, so there is no return-value signal to assert on.
    /// Rather than widen the production API for a test, this reconstructs the same
    /// condition from the same input: the fallback is used exactly when a strict
    /// decode fails but brace-extraction then succeeds.
    private func assertShadowFallback(_ expected: Bool, rawResponse: String, caseId: String) {
        let decoder = JSONDecoder()
        let strictSucceeded = (try? decoder.decode(AIAnalysisResponseFixture.self,
                                                   from: Data(rawResponse.utf8))) != nil

        var permissiveSucceeded = false
        if let start = rawResponse.firstIndex(of: "{"),
           let end = rawResponse.lastIndex(of: "}"),
           start <= end {
            let extracted = String(rawResponse[start...end])
            permissiveSucceeded = (try? decoder.decode(AIAnalysisResponseFixture.self,
                                                       from: Data(extracted.utf8))) != nil
        }

        let fallbackUsed = !strictSucceeded && permissiveSucceeded
        XCTAssertEqual(
            fallbackUsed, expected,
            "[\(caseId)] expectedShadowFallbackUsed=\(expected) but strict=\(strictSucceeded), permissive=\(permissiveSucceeded)"
        )
    }

    // MARK: - Fixture → object adapters

    private func goldenAsText(for testCase: Case) throws -> String {
        if let raw = testCase.rawGoldenResponse {
            // Pre-formatted (used for shadow-mode/preamble cases).
            return raw
        }
        guard let golden = testCase.goldenAnalysisResponse else {
            throw NSError(
                domain: "ValidationRegressionRunner", code: -2,
                userInfo: [NSLocalizedDescriptionKey: "Case '\(testCase.id)' has neither goldenAnalysisResponse nor rawGoldenResponse"]
            )
        }
        return try encodeFixture(golden)
    }

    private func encodeFixture(_ fixture: AIAnalysisResponseFixture) throws -> String {
        let data = try JSONEncoder().encode(fixture)
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func makeProfile(from patient: Patient) -> UserProfile {
        TestFixtures.makeProfile(
            age: patient.age,
            sex: patient.sex,
            medicalConditions: patient.medicalConditions,
            medications: patient.medications
        )
    }

    private func makeAssessment(from patient: Patient) -> PainAssessment {
        // Build a BodyRegion whose `zoneKey` matches the case's
        // `primaryRegion`. The MedicalRedFlagDetector's region-bound
        // patterns (cardiac → "chest", cauda equina → "lower_back")
        // match on `assessment.selectedRegion.zoneKey.contains(...)`,
        // so the zoneKey value is the part that actually matters.
        let region = BodyRegion(
            name: patient.primaryRegion.replacingOccurrences(of: "_", with: " ").capitalized,
            zoneKey: patient.primaryRegion,
            sides: [.front],
            frontPosition: nil,
            backPosition: nil
        )
        return TestFixtures.makeAssessment(
            region: region,
            painIntensity: patient.painIntensity,
            painOnsets: [patient.painOnset],
            aggravatingFactors: patient.aggravatingFactors,
            relievingFactors: patient.relievingFactors
        )
    }
}
