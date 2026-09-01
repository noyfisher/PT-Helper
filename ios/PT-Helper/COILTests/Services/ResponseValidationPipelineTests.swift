import XCTest
@testable import COIL

// MARK: - ResponseValidationPipeline Tests

final class ResponseValidationPipelineTests: XCTestCase {

    // MARK: - Test Helpers

    private func makeRegion(name: String = "Right Knee", zoneKey: String = "right_knee") -> BodyRegion {
        BodyRegion(
            name: name, zoneKey: zoneKey,
            sides: [.front],
            frontPosition: CGPoint(x: 0.5, y: 0.7),
            backPosition: nil
        )
    }

    private func makeCondition(
        name: String = "Patellofemoral Pain Syndrome",
        commonName: String = "Runner's Knee",
        confidence: Double = 72,
        isRedFlag: Bool = false,
        redFlagMessage: String? = nil
    ) -> ConditionResult {
        ConditionResult(
            id: UUID(), conditionName: name, commonName: commonName,
            confidence: confidence, explanation: "Test explanation",
            whatItMeans: "Test meaning", howToManage: "Test management",
            isRedFlag: isRedFlag, redFlagMessage: redFlagMessage,
            nextSteps: ["See a doctor"]
        )
    }

    private func makeAssessment(
        region: BodyRegion? = nil,
        painIntensity: Int = 5,
        painOnsets: [String] = ["Gradual"],
        aggravatingFactors: [String] = [],
        relievingFactors: [String] = [],
        additionalNotes: String? = nil,
        customPainDescription: String? = nil
    ) -> PainAssessment {
        PainAssessment(
            id: UUID(),
            selectedRegion: region ?? makeRegion(),
            painTypes: ["Aching"],
            customPainDescription: customPainDescription,
            painIntensity: painIntensity,
            painDurations: ["Over a Month"],
            painFrequencies: ["Intermittent"],
            painOnsets: painOnsets,
            aggravatingFactors: aggravatingFactors,
            relievingFactors: relievingFactors,
            additionalNotes: additionalNotes,
            currentTreatment: nil
        )
    }

    private func makeExercise(
        name: String = "Wall Sits",
        sets: Int = 3,
        restSeconds: Int = 45,
        reps: String = "10",
        difficulty: RehabExercise.Difficulty = .beginner
    ) -> RehabExercise {
        RehabExercise(
            id: UUID(), name: name, targetArea: "Knee",
            description: "Test", sets: sets, reps: reps,
            restSeconds: restSeconds, difficulty: difficulty,
            demonstrationIcon: "figure.cooldown",
            tips: [], contraindications: []
        )
    }

    private func makePlan(exercises: [RehabExercise] = [], totalWeeks: Int = 6) -> RehabPlan {
        RehabPlan(
            id: UUID(), planName: "Test Plan",
            conditions: ["Test"], exercises: exercises,
            weeklySchedule: Array(repeating: [], count: 7),
            totalWeeks: totalWeeks, createdDate: Date(), notes: nil
        )
    }

    private func makeProfile(
        age: Int = 30,
        medicalConditions: [String] = [],
        medications: [String]? = nil,
        surgeries: [UserProfile.Surgery] = []
    ) -> UserProfile {
        let calendar = Calendar.current
        let dob = calendar.date(byAdding: .year, value: -age, to: Date())!
        var profile = UserProfile(
            userId: "test", firstName: "Test", lastName: "User",
            dateOfBirth: dob, sex: "Male",
            heightFeet: 5, heightInches: 10, weight: 170,
            medicalConditions: medicalConditions,
            surgeries: surgeries, injuries: [],
            activityLevel: "Moderate"
        )
        profile.medications = medications
        return profile
    }

    private func makeAnalysisResult(
        conditions: [ConditionResult] = [],
        summary: String = "Test summary"
    ) -> AnalysisResult {
        AnalysisResult(
            id: UUID(), assessments: [],
            conditions: conditions,
            overallSummary: summary,
            disclaimerText: "Not medical advice",
            generatedDate: Date(),
            userProfileSnapshot: makeProfile()
        )
    }

    // MARK: - ConfidenceCalibrator Tests

    func testCalibrate_clampsBelowZero() {
        XCTAssertEqual(ConfidenceCalibrator.calibrate(-10), 0)
    }

    func testCalibrate_clampsAboveMax() {
        XCTAssertEqual(ConfidenceCalibrator.calibrate(99), 85)
        XCTAssertEqual(ConfidenceCalibrator.calibrate(100), 85)
    }

    func testCalibrate_preservesWithinRange() {
        XCTAssertEqual(ConfidenceCalibrator.calibrate(50), 50)
        XCTAssertEqual(ConfidenceCalibrator.calibrate(85), 85)
        XCTAssertEqual(ConfidenceCalibrator.calibrate(0), 0)
    }

    func testMatchStrength_strong() {
        XCTAssertEqual(ConfidenceCalibrator.matchStrength(for: 80), .strong)
        XCTAssertEqual(ConfidenceCalibrator.matchStrength(for: 65), .strong)
    }

    func testMatchStrength_moderate() {
        XCTAssertEqual(ConfidenceCalibrator.matchStrength(for: 50), .moderate)
        XCTAssertEqual(ConfidenceCalibrator.matchStrength(for: 35), .moderate)
    }

    func testMatchStrength_weak() {
        XCTAssertEqual(ConfidenceCalibrator.matchStrength(for: 20), .weak)
        XCTAssertEqual(ConfidenceCalibrator.matchStrength(for: 0), .weak)
    }

    func testMatchStrength_highConfidenceGetsCapped() {
        // 95 → calibrated to 85 → strong
        XCTAssertEqual(ConfidenceCalibrator.matchStrength(for: 95), .strong)
    }

    // MARK: - AnalysisContentValidator Tests

    func testContentValidator_emptyConditions_warnsButValid() {
        let result = makeAnalysisResult(conditions: [])
        let validation = AnalysisContentValidator.validate(result)

        XCTAssertTrue(validation.isValid)
        XCTAssertTrue(validation.warnings.contains(where: { $0.message.contains("No possible explanations") }))
    }

    func testContentValidator_moreThanThreeConditions_fixApplied() {
        let conditions = (1...5).map { makeCondition(name: "Condition \($0)", commonName: "Name \($0)") }
        let result = makeAnalysisResult(conditions: conditions)
        let validation = AnalysisContentValidator.validate(result)

        XCTAssertTrue(validation.appliedFixes.contains(where: { $0.contains("Trimmed conditions") }))
    }

    func testContentValidator_outOfRangeConfidence_fixApplied() {
        let condition = makeCondition(confidence: 150)
        let result = makeAnalysisResult(conditions: [condition])
        let validation = AnalysisContentValidator.validate(result)

        XCTAssertTrue(validation.appliedFixes.contains(where: { $0.contains("Clamped") }))
    }

    func testContentValidator_veryHighConfidence_warnsInfo() {
        let condition = makeCondition(confidence: 95)
        let result = makeAnalysisResult(conditions: [condition])
        let validation = AnalysisContentValidator.validate(result)

        XCTAssertTrue(validation.warnings.contains(where: { $0.severity == .info && $0.message.contains("high match scores") }))
    }

    func testContentValidator_redFlagWithoutMessage_warnsUrgent() {
        let condition = makeCondition(isRedFlag: true, redFlagMessage: nil)
        let result = makeAnalysisResult(conditions: [condition])
        let validation = AnalysisContentValidator.validate(result)

        XCTAssertFalse(validation.isValid, "Should be invalid when urgent warnings exist")
        XCTAssertTrue(validation.warnings.contains(where: { $0.severity == .urgent }))
    }

    func testContentValidator_redFlagWithMessage_noUrgentWarning() {
        let condition = makeCondition(isRedFlag: true, redFlagMessage: "See a doctor immediately")
        let result = makeAnalysisResult(conditions: [condition])
        let validation = AnalysisContentValidator.validate(result)

        // Should NOT have the "flagged as potentially serious" urgent warning
        XCTAssertFalse(validation.warnings.contains(where: { $0.severity == .urgent && $0.message.contains("flagged as potentially serious") }))
    }

    func testContentValidator_duplicateConditions_fixApplied() {
        let conditions = [
            makeCondition(name: "Tennis Elbow", commonName: "Tennis Elbow"),
            makeCondition(name: "tennis elbow", commonName: "Tennis Elbow Duplicate")
        ]
        let result = makeAnalysisResult(conditions: conditions)
        let validation = AnalysisContentValidator.validate(result)

        XCTAssertTrue(validation.appliedFixes.contains(where: { $0.contains("Duplicate") }))
    }

    func testContentValidator_emptySummary_warnsCaution() {
        let result = makeAnalysisResult(summary: "   ")
        let validation = AnalysisContentValidator.validate(result)

        XCTAssertTrue(validation.warnings.contains(where: { $0.message.contains("summary was empty") }))
    }

    func testContentValidator_validResult_noWarnings() {
        let condition = makeCondition(confidence: 70)
        let result = makeAnalysisResult(conditions: [condition], summary: "A valid summary")
        let validation = AnalysisContentValidator.validate(result)

        XCTAssertTrue(validation.isValid)
        XCTAssertTrue(validation.warnings.isEmpty)
        XCTAssertTrue(validation.appliedFixes.isEmpty)
    }

    // MARK: - MedicalRedFlagDetector Tests

    func testRedFlag_highPainSuddenOnset_urgent() {
        let assessment = makeAssessment(painIntensity: 9, painOnsets: ["Sudden"])
        let result = MedicalRedFlagDetector.check(assessments: [assessment])

        XCTAssertTrue(result.triggered)
        XCTAssertTrue(result.alerts.contains(where: { $0.severity == .urgent && $0.message.contains("very severe") && $0.message.contains("sudden onset") }))
    }

    func testRedFlag_highPainGradualOnset_cautionNotUrgent() {
        let assessment = makeAssessment(painIntensity: 9, painOnsets: ["Gradual"])
        let result = MedicalRedFlagDetector.check(assessments: [assessment])

        XCTAssertTrue(result.triggered)
        XCTAssertTrue(result.alerts.contains(where: { $0.severity == .caution }))
        XCTAssertFalse(result.alerts.contains(where: { $0.severity == .urgent }))
    }

    func testRedFlag_moderatePain_noAlerts() {
        let assessment = makeAssessment(painIntensity: 5)
        let result = MedicalRedFlagDetector.check(assessments: [assessment])

        XCTAssertFalse(result.triggered)
        XCTAssertTrue(result.alerts.isEmpty)
    }

    func testRedFlag_chestPainWithBreathing_urgent() {
        let assessment = makeAssessment(
            region: makeRegion(name: "Chest", zoneKey: "chest"),
            aggravatingFactors: ["chest pain", "shortness of breath"]
        )
        let result = MedicalRedFlagDetector.check(assessments: [assessment])

        XCTAssertTrue(result.triggered)
        XCTAssertTrue(result.alerts.contains(where: { $0.message.contains("cardiac emergency") }))
    }

    func testRedFlag_caudaEquina_fromNotes() {
        let region = makeRegion(name: "Lower Back", zoneKey: "lower_back")
        let assessment = makeAssessment(
            region: region,
            additionalNotes: "I have loss of bladder control, back pain, and leg weakness"
        )
        let result = MedicalRedFlagDetector.check(assessments: [assessment])

        XCTAssertTrue(result.triggered)
        XCTAssertTrue(result.alerts.contains(where: { $0.message.contains("cauda equina") }))
    }

    func testRedFlag_dvtPattern() {
        let assessment = makeAssessment(
            aggravatingFactors: ["calf pain with swelling and redness"]
        )
        let result = MedicalRedFlagDetector.check(assessments: [assessment])

        XCTAssertTrue(result.triggered)
        XCTAssertTrue(result.alerts.contains(where: { $0.message.contains("blood clot") }))
    }

    func testRedFlag_nightPainAndWeightLoss() {
        let assessment = makeAssessment(
            additionalNotes: "I have night pain and unexplained weight loss"
        )
        let result = MedicalRedFlagDetector.check(assessments: [assessment])

        XCTAssertTrue(result.triggered)
        XCTAssertTrue(result.alerts.contains(where: { $0.message.contains("night pain") }))
    }

    func testRedFlag_patternRequiresAllKeywords() {
        // Only one keyword from the DVT pattern — should NOT trigger
        let assessment = makeAssessment(
            aggravatingFactors: ["calf pain"]
        )
        let result = MedicalRedFlagDetector.check(assessments: [assessment])

        XCTAssertFalse(result.alerts.contains(where: { $0.message.contains("blood clot") }))
    }

    func testRedFlag_regionSpecificPattern_wrongRegion() {
        // Cauda equina requires lower_back region
        let assessment = makeAssessment(
            region: makeRegion(name: "Right Shoulder", zoneKey: "right_shoulder"),
            additionalNotes: "loss of bladder control, back pain, leg weakness"
        )
        let result = MedicalRedFlagDetector.check(assessments: [assessment])

        // Should NOT trigger cauda equina because region doesn't match
        XCTAssertFalse(result.alerts.contains(where: { $0.message.contains("cauda equina") }))
    }

    // MARK: - MedicalRedFlagDetector.checkConditions Tests

    func testCheckConditions_fracture_flagged() {
        let condition = makeCondition(name: "Stress Fracture", commonName: "Stress Fracture", isRedFlag: false)
        let alerts = MedicalRedFlagDetector.checkConditions([condition])

        XCTAssertEqual(alerts.count, 1)
        XCTAssertTrue(alerts[0].message.contains("requires professional medical treatment"))
    }

    func testCheckConditions_fracture_alreadyRedFlagged_notDoubled() {
        let condition = makeCondition(name: "Stress Fracture", commonName: "Stress Fracture", isRedFlag: true)
        let alerts = MedicalRedFlagDetector.checkConditions([condition])

        XCTAssertTrue(alerts.isEmpty, "Should not add duplicate alert when AI already flagged it")
    }

    func testCheckConditions_dvt_flagged() {
        let condition = makeCondition(name: "Deep Vein Thrombosis", commonName: "DVT", isRedFlag: false)
        let alerts = MedicalRedFlagDetector.checkConditions([condition])

        XCTAssertFalse(alerts.isEmpty)
    }

    func testCheckConditions_normalCondition_noAlert() {
        let condition = makeCondition(name: "Patellofemoral Pain Syndrome", commonName: "Runner's Knee")
        let alerts = MedicalRedFlagDetector.checkConditions([condition])

        XCTAssertTrue(alerts.isEmpty)
    }

    // MARK: - ExerciseContraindicationChecker Tests

    func testContraindication_herniatedDiscWithDeadlift() {
        let exercises = [makeExercise(name: "Deadlift")]
        let warnings = ExerciseContraindicationChecker.validate(
            exercises: exercises, conditions: ["Herniated Disc L4-L5"]
        )

        // Matches both "herniated disc" and "disc" patterns
        XCTAssertGreaterThanOrEqual(warnings.count, 1)
        XCTAssertTrue(warnings.allSatisfy { $0.message.contains("Deadlift") })
    }

    func testContraindication_aclWithDeepSquat() {
        let exercises = [makeExercise(name: "Deep Squat")]
        let warnings = ExerciseContraindicationChecker.validate(
            exercises: exercises, conditions: ["ACL Tear"]
        )

        XCTAssertFalse(warnings.isEmpty)
    }

    func testContraindication_rotatorCuffWithOverheadPress() {
        let exercises = [makeExercise(name: "Overhead Press")]
        let warnings = ExerciseContraindicationChecker.validate(
            exercises: exercises, conditions: ["Rotator Cuff Tear"]
        )

        XCTAssertFalse(warnings.isEmpty)
    }

    func testContraindication_safeExercise_noWarning() {
        let exercises = [makeExercise(name: "Wall Sits")]
        let warnings = ExerciseContraindicationChecker.validate(
            exercises: exercises, conditions: ["Herniated Disc"]
        )

        XCTAssertTrue(warnings.isEmpty)
    }

    func testContraindication_multipleConditions() {
        let exercises = [
            makeExercise(name: "Deadlift"),
            makeExercise(name: "Deep Squat"),
            makeExercise(name: "Wall Sits")
        ]
        let warnings = ExerciseContraindicationChecker.validate(
            exercises: exercises, conditions: ["Herniated Disc", "ACL Reconstruction"]
        )

        // Deadlift blocked by herniated disc, Deep Squat blocked by ACL
        XCTAssertTrue(warnings.count >= 2)
    }

    // These previously asserted only that a MESSAGE was produced, which is why the
    // defect survived: the pipeline reported "has unusual sets count: 15" as an
    // `.info` badge and then shipped the 15 sets to the user unchanged. Each test
    // now asserts the corrected VALUE as well as the report.

    func testValidateParameters_normalRange_leavesExercisesUntouched() {
        let exercises = [makeExercise(sets: 3, restSeconds: 45)]
        let result = ExerciseContraindicationChecker.validateParameters(exercises)

        XCTAssertTrue(result.fixes.isEmpty)
        XCTAssertEqual(result.exercises[0].sets, 3)
        XCTAssertEqual(result.exercises[0].restSeconds, 45)
    }

    func testValidateParameters_setsAboveRange_areClampedNotJustReported() {
        let exercises = [makeExercise(name: "Bad Sets", sets: 15)]
        let result = ExerciseContraindicationChecker.validateParameters(exercises)

        XCTAssertEqual(result.exercises[0].sets, 10, "15 sets must not reach the user")
        XCTAssertTrue(result.fixes.contains(where: { $0.contains("Bad Sets") && $0.contains("10") }))
    }

    func testValidateParameters_restAboveRange_isClamped() {
        let exercises = [makeExercise(name: "Bad Rest", restSeconds: 400)]
        let result = ExerciseContraindicationChecker.validateParameters(exercises)

        XCTAssertEqual(result.exercises[0].restSeconds, 300)
        XCTAssertTrue(result.fixes.contains(where: { $0.contains("Bad Rest") }))
    }

    func testValidateParameters_zeroSets_isRaisedToTheMinimum() {
        let exercises = [makeExercise(name: "Zero Sets", sets: 0)]
        let result = ExerciseContraindicationChecker.validateParameters(exercises)

        XCTAssertEqual(result.exercises[0].sets, 1, "A zero-set exercise is not performable")
        XCTAssertFalse(result.fixes.isEmpty)
    }

    func testValidateParameters_negativeRest_isRaisedToZero() {
        let exercises = [makeExercise(name: "Neg Rest", restSeconds: -10)]
        let result = ExerciseContraindicationChecker.validateParameters(exercises)

        XCTAssertEqual(result.exercises[0].restSeconds, 0)
        XCTAssertFalse(result.fixes.isEmpty)
    }

    /// `reps` is a free-form spec string, so it stays advisory — rewriting it could
    /// change the meaning of a prescription rather than bound it.
    func testValidateParameters_outOfRangeReps_areReportedButNotRewritten() {
        let exercises = [makeExercise(name: "Many Reps", reps: "60")]
        let result = ExerciseContraindicationChecker.validateParameters(exercises)

        XCTAssertEqual(result.exercises[0].reps, "60")
        XCTAssertTrue(result.fixes.contains(where: { $0.contains("Many Reps") }))
    }

    // MARK: - AnatomicalRelevanceChecker Tests

    func testAnatomicalRelevance_kneeConditionForKneeRegion_noWarning() {
        let condition = makeCondition(name: "Patellofemoral Pain Syndrome", commonName: "Runner's Knee")
        let regions = [makeRegion(zoneKey: "right_knee")]
        let warnings = AnatomicalRelevanceChecker.validate(conditions: [condition], assessedRegions: regions)

        XCTAssertTrue(warnings.isEmpty)
    }

    func testAnatomicalRelevance_shoulderConditionForKneeRegion_warns() {
        let condition = makeCondition(name: "Rotator Cuff Tendinopathy", commonName: "Rotator Cuff Issue")
        let regions = [makeRegion(zoneKey: "right_knee")]
        let warnings = AnatomicalRelevanceChecker.validate(conditions: [condition], assessedRegions: regions)

        XCTAssertEqual(warnings.count, 1)
        XCTAssertTrue(warnings[0].message.contains("not be directly related"))
    }

    func testAnatomicalRelevance_multipleRegions_expandsAllowed() {
        let condition = makeCondition(name: "Sciatica", commonName: "Sciatica")
        let regions = [
            makeRegion(name: "Right Knee", zoneKey: "right_knee"),
            makeRegion(name: "Lower Back", zoneKey: "lower_back")
        ]
        let warnings = AnatomicalRelevanceChecker.validate(conditions: [condition], assessedRegions: regions)

        // Sciatica should match lower_back region
        XCTAssertTrue(warnings.isEmpty)
    }

    func testAnatomicalRelevance_unknownRegion_skipsCheck() {
        let condition = makeCondition()
        let regions = [makeRegion(zoneKey: "unknown_zone")]
        let warnings = AnatomicalRelevanceChecker.validate(conditions: [condition], assessedRegions: regions)

        XCTAssertTrue(warnings.isEmpty, "Should skip check when no mapping exists")
    }

    // MARK: - Full Pipeline: validateAnalysis Tests

    func testValidateAnalysis_capsConfidenceAt85() {
        let condition = makeCondition(confidence: 95)
        let result = makeAnalysisResult(conditions: [condition])
        let assessment = makeAssessment()

        let (validated, _, _) = ResponseValidationPipeline.validateAnalysis(result, assessments: [assessment])

        XCTAssertEqual(validated.conditions.first?.confidence, 85)
    }

    func testValidateAnalysis_trimsToThreeConditions() {
        let conditions = (1...5).map { makeCondition(name: "C\($0)", commonName: "C\($0)", confidence: Double(70 - $0 * 10)) }
        let result = makeAnalysisResult(conditions: conditions)
        let assessment = makeAssessment()

        let (validated, _, _) = ResponseValidationPipeline.validateAnalysis(result, assessments: [assessment])

        XCTAssertLessThanOrEqual(validated.conditions.count, 3)
    }

    func testValidateAnalysis_deduplicatesConditions() {
        let conditions = [
            makeCondition(name: "Tennis Elbow", commonName: "TE1"),
            makeCondition(name: "tennis elbow", commonName: "TE2"),
            makeCondition(name: "Knee Sprain", commonName: "KS")
        ]
        let result = makeAnalysisResult(conditions: conditions)
        let assessment = makeAssessment()

        let (validated, validation, _) = ResponseValidationPipeline.validateAnalysis(result, assessments: [assessment])

        XCTAssertEqual(validated.conditions.count, 2)
        XCTAssertTrue(validation.appliedFixes.contains(where: { $0.contains("Removed duplicate") }))
    }

    func testValidateAnalysis_redFlagsFromSymptoms() {
        let assessment = makeAssessment(painIntensity: 10, painOnsets: ["Sudden"])

        let result = makeAnalysisResult(conditions: [makeCondition()])
        let (_, _, redFlags) = ResponseValidationPipeline.validateAnalysis(result, assessments: [assessment])

        XCTAssertFalse(redFlags.isEmpty)
    }

    func testValidateAnalysis_redFlagsFromConditions() {
        let condition = makeCondition(name: "Spinal Cord Compression", commonName: "Spinal Cord Issue", isRedFlag: false)
        let result = makeAnalysisResult(conditions: [condition])
        let assessment = makeAssessment()

        let (_, _, redFlags) = ResponseValidationPipeline.validateAnalysis(result, assessments: [assessment])

        XCTAssertFalse(redFlags.isEmpty)
    }

    // MARK: - Full Pipeline: validateRehabPlan Tests

    func testValidateRehabPlan_contraindicationDetected() {
        let exercises = [makeExercise(name: "Deadlift")]
        let plan = makePlan(exercises: exercises)
        let profile = makeProfile()

        let (_, warnings, _) = ResponseValidationPipeline.validateRehabPlan(
            plan, conditions: ["Herniated Disc"], userProfile: profile
        )

        XCTAssertTrue(warnings.contains(where: { $0.message.contains("Deadlift") }))
    }

    func testValidateRehabPlan_emptyExercises_warns() {
        let plan = makePlan(exercises: [])
        let profile = makeProfile()

        let (_, warnings, _) = ResponseValidationPipeline.validateRehabPlan(
            plan, conditions: ["Knee Pain"], userProfile: profile
        )

        XCTAssertTrue(warnings.contains(where: { $0.message.contains("No exercises") }))
    }

    func testValidateRehabPlan_unusualDuration_warns() {
        let plan = makePlan(totalWeeks: 30)
        let profile = makeProfile()

        let (_, warnings, _) = ResponseValidationPipeline.validateRehabPlan(
            plan, conditions: ["Test"], userProfile: profile
        )

        XCTAssertTrue(warnings.contains(where: { $0.message.contains("unusual") }))
    }

    func testValidateRehabPlan_elderlyWithAdvanced_warns() {
        let exercises = [makeExercise(difficulty: .advanced)]
        let plan = makePlan(exercises: exercises)
        let profile = makeProfile(age: 70)

        let (_, warnings, _) = ResponseValidationPipeline.validateRehabPlan(
            plan, conditions: ["Knee Pain"], userProfile: profile
        )

        XCTAssertTrue(warnings.contains(where: { $0.message.contains("advanced") && $0.message.contains("age") }))
    }

    func testValidateRehabPlan_elderlyWithBeginner_noAgeWarning() {
        let exercises = [makeExercise(difficulty: .beginner)]
        let plan = makePlan(exercises: exercises)
        let profile = makeProfile(age: 70)

        let (_, warnings, _) = ResponseValidationPipeline.validateRehabPlan(
            plan, conditions: ["Knee Pain"], userProfile: profile
        )

        XCTAssertFalse(warnings.contains(where: { $0.message.contains("advanced") }))
    }

    func testValidateRehabPlan_osteoporosisWithJumping_serious() {
        // Tier 1 reclassified this pairing from `.urgent` → `.serious` — it's a
        // plan-level contraindication (fracture risk) that now routes through
        // the acknowledgement modal rather than just flashing a red banner.
        let exercises = [makeExercise(name: "Jump Squat")]
        let plan = makePlan(exercises: exercises)
        let profile = makeProfile(medicalConditions: ["Osteoporosis"])

        let (_, warnings, _) = ResponseValidationPipeline.validateRehabPlan(
            plan, conditions: ["Knee Pain"], userProfile: profile
        )

        XCTAssertTrue(warnings.contains(where: { $0.severity == .serious && $0.message.contains("osteoporosis") }))
    }

    func testValidateRehabPlan_cardiacHistory_warns() {
        let exercises = [makeExercise()]
        let plan = makePlan(exercises: exercises)
        let profile = makeProfile(medicalConditions: ["Heart Disease"])

        let (_, warnings, _) = ResponseValidationPipeline.validateRehabPlan(
            plan, conditions: ["Back Pain"], userProfile: profile
        )

        XCTAssertTrue(warnings.contains(where: { $0.message.contains("cardiac") }))
    }

    func testValidateRehabPlan_bloodThinners_balanceWarning() {
        let exercises = [makeExercise(name: "Single-Leg Balance")]
        let plan = makePlan(exercises: exercises)
        let profile = makeProfile(medications: ["Blood Thinners"])

        let (_, warnings, _) = ResponseValidationPipeline.validateRehabPlan(
            plan, conditions: ["Ankle Sprain"], userProfile: profile
        )

        XCTAssertTrue(warnings.contains(where: { $0.message.contains("blood thinners") }))
    }

    func testValidateRehabPlan_corticosteroids_info() {
        let exercises = [makeExercise()]
        let plan = makePlan(exercises: exercises)
        let profile = makeProfile(medications: ["Corticosteroids"])

        let (_, warnings, _) = ResponseValidationPipeline.validateRehabPlan(
            plan, conditions: ["Test"], userProfile: profile
        )

        XCTAssertTrue(warnings.contains(where: { $0.message.contains("corticosteroid") }))
    }

    func testValidateRehabPlan_betaBlockers_info() {
        let exercises = [makeExercise()]
        let plan = makePlan(exercises: exercises)
        let profile = makeProfile(medications: ["Beta Blockers"])

        let (_, warnings, _) = ResponseValidationPipeline.validateRehabPlan(
            plan, conditions: ["Test"], userProfile: profile
        )

        XCTAssertTrue(warnings.contains(where: { $0.message.contains("Beta blockers") }))
    }

    func testValidateRehabPlan_activeSurgery_warns() {
        let surgery = UserProfile.Surgery(
            name: "ACL Reconstruction", year: 2025,
            recoveryStatus: "Still recovering"
        )
        let exercises = [makeExercise()]
        let plan = makePlan(exercises: exercises)
        let profile = makeProfile(surgeries: [surgery])

        let (_, warnings, _) = ResponseValidationPipeline.validateRehabPlan(
            plan, conditions: ["Knee Pain"], userProfile: profile
        )

        XCTAssertTrue(warnings.contains(where: { $0.message.contains("ACL Reconstruction") }))
    }

    func testValidateRehabPlan_surgeryWithRestrictions_warns() {
        let surgery = UserProfile.Surgery(
            name: "Spinal Fusion", year: 2020,
            recoveryStatus: "Have restrictions",
            restrictions: "No heavy lifting"
        )
        let exercises = [makeExercise()]
        let plan = makePlan(exercises: exercises)
        let profile = makeProfile(surgeries: [surgery])

        let (_, warnings, _) = ResponseValidationPipeline.validateRehabPlan(
            plan, conditions: ["Back Pain"], userProfile: profile
        )

        XCTAssertTrue(warnings.contains(where: { $0.message.contains("Spinal Fusion") }))
    }

    func testValidateRehabPlan_fullyRecoveredSurgery_noSurgeryWarning() {
        let surgery = UserProfile.Surgery(
            name: "Appendectomy", year: 2015,
            recoveryStatus: "Fully recovered"
        )
        let exercises = [makeExercise()]
        let plan = makePlan(exercises: exercises)
        let profile = makeProfile(surgeries: [surgery])

        let (_, warnings, _) = ResponseValidationPipeline.validateRehabPlan(
            plan, conditions: ["Knee Pain"], userProfile: profile
        )

        XCTAssertFalse(warnings.contains(where: { $0.message.contains("Appendectomy") }))
    }

    func testValidateRehabPlan_noMedications_noMedWarnings() {
        let exercises = [makeExercise()]
        let plan = makePlan(exercises: exercises)
        let profile = makeProfile(medications: nil)

        let (_, warnings, _) = ResponseValidationPipeline.validateRehabPlan(
            plan, conditions: ["Test"], userProfile: profile
        )

        XCTAssertFalse(warnings.contains(where: { $0.message.contains("blood thinners") || $0.message.contains("corticosteroid") || $0.message.contains("Beta blockers") }))
    }

    // MARK: - ValidationResult Tests

    func testValidationResult_hasWarnings() {
        let result = ValidationResult(isValid: true, warnings: [
            ValidationWarning(severity: .info, message: "Test")
        ], appliedFixes: [])

        XCTAssertTrue(result.hasWarnings)
    }

    func testValidationResult_noWarnings() {
        let result = ValidationResult(isValid: true, warnings: [], appliedFixes: [])

        XCTAssertFalse(result.hasWarnings)
    }

    // MARK: - MatchStrength Properties

    func testMatchStrength_colors() {
        XCTAssertEqual(MatchStrength.strong.color, "green")
        XCTAssertEqual(MatchStrength.moderate.color, "orange")
        XCTAssertEqual(MatchStrength.weak.color, "gray")
    }

    func testMatchStrength_rawValues() {
        XCTAssertEqual(MatchStrength.strong.rawValue, "Strong Match")
        XCTAssertEqual(MatchStrength.moderate.rawValue, "Possible Match")
        XCTAssertEqual(MatchStrength.weak.rawValue, "Less Likely")
    }
}
