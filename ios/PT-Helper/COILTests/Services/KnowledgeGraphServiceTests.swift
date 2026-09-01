import XCTest
@testable import COIL

final class KnowledgeGraphServiceTests: XCTestCase {

    private var service: KnowledgeGraphService!

    /// A comprehensive test graph mirroring the real data structure for the conditions we test.
    private static let testGraph = KnowledgeGraph(
        version: "test-1.0",
        conditions: [
            "patellofemoral-pain-syndrome": KnownCondition(
                names: ["patellofemoral pain syndrome", "runner's knee", "pfps", "kneecap pain", "anterior knee pain"],
                icd10: "M22.2X9",
                bodyRegions: ["knee"],
                safeExercises: ["quad-sets", "straight-leg-raises", "wall-sits", "clamshells", "heel-slides", "step-ups", "hamstring-curls", "glute-bridges"],
                unsafeExercises: ["bulgarian-split-squat", "single-leg-deadlift"],
                redFlags: ["knee locking", "inability to bear weight", "acute swelling within 2 hours"],
                referIfPresent: ["symptoms > 8 weeks without improvement", "mechanical locking"]
            ),
            "meniscus-tear": KnownCondition(
                names: ["meniscus tear", "meniscal tear", "torn meniscus"],
                icd10: "S83.200A",
                bodyRegions: ["knee"],
                safeExercises: ["quad-sets", "straight-leg-raises", "heel-slides"],
                unsafeExercises: ["bulgarian-split-squat"],
                redFlags: ["locked knee unable to straighten"],
                referIfPresent: ["mechanical locking episodes"]
            ),
            "herniated-disc": KnownCondition(
                names: ["herniated disc", "disc herniation", "bulging disc", "slipped disc"],
                icd10: "M51.16",
                bodyRegions: ["lower_back"],
                safeExercises: ["pelvic-tilts", "cat-cow-stretch", "bird-dog", "glute-bridges"],
                unsafeExercises: ["deadlift", "sit-ups"],
                redFlags: ["progressive leg weakness", "bladder or bowel changes"],
                referIfPresent: ["progressive neurological deficit"]
            ),
            "plantar-fasciitis": KnownCondition(
                names: ["plantar fasciitis", "heel pain", "plantar heel pain"],
                icd10: "M72.2",
                bodyRegions: ["ankle_foot"],
                safeExercises: ["calf-stretch", "plantar-fascia-stretch", "towel-curls"],
                unsafeExercises: [],
                redFlags: ["pain at rest not improving"],
                referIfPresent: ["symptoms > 6 months"]
            ),
            "sciatica": KnownCondition(
                names: ["sciatica", "sciatic nerve pain", "lumbar radiculopathy"],
                icd10: "M54.30",
                bodyRegions: ["lower_back", "hip"],
                safeExercises: ["pelvic-tilts", "cat-cow-stretch", "glute-bridges"],
                unsafeExercises: ["sit-ups", "deadlift"],
                redFlags: ["bilateral leg symptoms", "bladder changes"],
                referIfPresent: ["progressive weakness"]
            )
        ],
        exercises: [
            "quad-sets": KnownExercise(
                names: ["quad sets", "quadricep sets", "quad isometrics", "quadricep isometrics"],
                targetRegions: ["knee"],
                category: "strength",
                safeForConditions: ["patellofemoral-pain-syndrome", "meniscus-tear"],
                unsafeForConditions: []
            ),
            "straight-leg-raises": KnownExercise(
                names: ["straight leg raises", "slr", "straight leg raise"],
                targetRegions: ["knee"],
                category: "strength",
                safeForConditions: ["patellofemoral-pain-syndrome", "meniscus-tear"],
                unsafeForConditions: []
            ),
            "clamshells": KnownExercise(
                names: ["clamshells", "clam shells", "clamshell exercise"],
                targetRegions: ["hip", "knee"],
                category: "strength",
                safeForConditions: ["patellofemoral-pain-syndrome"],
                unsafeForConditions: []
            ),
            "glute-bridges": KnownExercise(
                names: ["glute bridges", "glute bridge", "hip bridges"],
                targetRegions: ["hip", "lower_back"],
                category: "strength",
                safeForConditions: ["patellofemoral-pain-syndrome", "herniated-disc", "sciatica"],
                unsafeForConditions: []
            ),
            "bulgarian-split-squat": KnownExercise(
                names: ["bulgarian split squat", "rear foot elevated split squat"],
                targetRegions: ["knee", "hip"],
                category: "strength",
                safeForConditions: [],
                unsafeForConditions: ["patellofemoral-pain-syndrome", "meniscus-tear"]
            ),
            "single-leg-deadlift": KnownExercise(
                names: ["single leg deadlift", "single-leg deadlift"],
                targetRegions: ["hip", "knee"],
                category: "strength",
                safeForConditions: [],
                unsafeForConditions: ["patellofemoral-pain-syndrome"]
            ),
            "deadlift": KnownExercise(
                names: ["deadlift", "conventional deadlift"],
                targetRegions: ["lower_back", "hip"],
                category: "strength",
                safeForConditions: [],
                unsafeForConditions: ["herniated-disc", "sciatica"]
            ),
            "pelvic-tilts": KnownExercise(
                names: ["pelvic tilts", "pelvic tilt"],
                targetRegions: ["lower_back"],
                category: "core",
                safeForConditions: ["herniated-disc", "sciatica"],
                unsafeForConditions: []
            )
        ]
    )

    override func setUp() {
        super.setUp()
        // All tests use an injected graph for deterministic, self-contained behavior.
        // This avoids bundle loading issues in the simulator test environment.
        service = KnowledgeGraphService(graph: Self.testGraph)
    }

    // MARK: - Condition Lookup

    func testLookupCondition_exactMatch() {
        let result = service.lookupCondition("patellofemoral pain syndrome")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.id, "patellofemoral-pain-syndrome")
    }

    func testLookupCondition_aliasMatch() {
        let result = service.lookupCondition("runner's knee")
        XCTAssertNotNil(result, "Should match 'runner's knee' alias for PFPS")
        XCTAssertEqual(result?.id, "patellofemoral-pain-syndrome")
    }

    func testLookupCondition_caseInsensitive() {
        let result = service.lookupCondition("PATELLOFEMORAL PAIN SYNDROME")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.id, "patellofemoral-pain-syndrome")
    }

    func testLookupCondition_kebabCaseInput() {
        let result = service.lookupCondition("patellofemoral-pain-syndrome")
        XCTAssertNotNil(result)
    }

    func testLookupCondition_unknown() {
        let result = service.lookupCondition("rare exotic tropical bone disease")
        XCTAssertNil(result, "Unknown condition should return nil, not crash")
    }

    func testLookupCondition_herniatedDisc() {
        let result = service.lookupCondition("Herniated Disc")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.id, "herniated-disc")
    }

    func testLookupCondition_sciaticaAlias() {
        let result = service.lookupCondition("sciatic nerve pain")
        XCTAssertNotNil(result, "Should match sciatica alias")
        XCTAssertEqual(result?.id, "sciatica")
    }

    // MARK: - Exercise Lookup

    func testLookupExercise_byNormalizedFilename() {
        let result = service.lookupExercise("quad-sets")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.id, "quad-sets")
    }

    func testLookupExercise_byAlias() {
        let result = service.lookupExercise("quad sets")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.id, "quad-sets")
    }

    func testLookupExercise_fuzzyMatch() {
        // "quadricep sets" should match via alias
        let result = service.lookupExercise("quadricep sets")
        XCTAssertNotNil(result, "Should fuzzy-match 'quadricep sets' to quad-sets")
    }

    func testLookupExercise_unknown() {
        let result = service.lookupExercise("underwater backflip tuck")
        XCTAssertNil(result, "Unknown exercise should return nil")
    }

    func testLookupExercise_caseInsensitive() {
        let result = service.lookupExercise("STRAIGHT LEG RAISES")
        XCTAssertNotNil(result)
    }

    func testLookupExercise_kebabToSpaceConversion() {
        // Exercise name with spaces should match kebab-case ID
        let result = service.lookupExercise("pelvic tilts")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.id, "pelvic-tilts")
    }

    // MARK: - Single Pair Verification

    func testVerify_knownSafePair() {
        let tier = service.verify(exercise: "Quad Sets", forCondition: "Patellofemoral Pain Syndrome")
        XCTAssertEqual(tier, .verified, "Quad sets should be verified safe for PFPS")
    }

    func testVerify_knownUnsafePair() {
        let tier = service.verify(exercise: "Bulgarian Split Squat", forCondition: "Patellofemoral Pain Syndrome")
        if case .contraindicated = tier {
            // Expected
        } else {
            XCTFail("Bulgarian split squat should be contraindicated for PFPS, got \(tier)")
        }
    }

    func testVerify_unknownExercise_unverified() {
        let tier = service.verify(exercise: "Prone Y Raises With Band", forCondition: "Patellofemoral Pain Syndrome")
        XCTAssertEqual(tier, .unverified, "Unknown exercise should be unverified, not blocked")
    }

    func testVerify_unknownCondition_unverified() {
        let tier = service.verify(exercise: "Quad Sets", forCondition: "Extremely Rare Condition XYZ")
        XCTAssertEqual(tier, .unverified, "Unknown condition should be unverified, not blocked")
    }

    func testVerify_bothUnknown_unverified() {
        let tier = service.verify(exercise: "Space Walk Exercise", forCondition: "Moon Knee Syndrome")
        XCTAssertEqual(tier, .unverified)
    }

    func testVerify_knownPairButNotMapped_unverified() {
        // Quad sets exists, plantar fasciitis exists, but quad-sets is not in plantar-fasciitis's safe/unsafe list
        let tier = service.verify(exercise: "Quad Sets", forCondition: "Plantar Fasciitis")
        XCTAssertEqual(tier, .unverified, "Known exercise/condition pair without explicit mapping should be unverified")
    }

    func testVerify_contraindicationReasonContainsExerciseName() {
        let tier = service.verify(exercise: "Deadlift", forCondition: "Herniated Disc")
        if case .contraindicated(let reason) = tier {
            XCTAssertTrue(reason.contains("Deadlift"), "Reason should mention the exercise name")
        } else {
            XCTFail("Deadlift should be contraindicated for herniated disc")
        }
    }

    // MARK: - Plan Verification

    func testVerifyPlan_mixedResults() {
        let exercises = [
            TestFixtures.makeExercise(name: "Quad Sets", targetArea: "Knee"),
            TestFixtures.makeExercise(name: "Bulgarian Split Squat", targetArea: "Knee"),
            TestFixtures.makeExercise(name: "Prone Y Raises", targetArea: "Shoulder")
        ]
        let plan = TestFixtures.makePlan(
            conditions: ["Patellofemoral Pain Syndrome"],
            exercises: exercises
        )

        let result = service.verifyPlan(plan, conditions: ["Patellofemoral Pain Syndrome"])

        XCTAssertEqual(result.exerciseResults.count, 3)
        XCTAssertEqual(result.unverifiedExercises.count, 1, "Prone Y Raises should be unverified")
        XCTAssertEqual(result.contraindicatedExercises.count, 1, "Bulgarian Split Squat should be contraindicated")

        // Check verified count
        let verifiedCount = result.exerciseResults.filter { $0.tier == .verified }.count
        XCTAssertEqual(verifiedCount, 1, "Quad Sets should be verified")
    }

    func testVerifyPlan_allVerified() {
        let exercises = [
            TestFixtures.makeExercise(name: "Quad Sets", targetArea: "Knee"),
            TestFixtures.makeExercise(name: "Straight Leg Raises", targetArea: "Knee"),
            TestFixtures.makeExercise(name: "Clamshells", targetArea: "Hip/Knee")
        ]
        let plan = TestFixtures.makePlan(
            conditions: ["Patellofemoral Pain Syndrome"],
            exercises: exercises
        )

        let result = service.verifyPlan(plan, conditions: ["Patellofemoral Pain Syndrome"])

        XCTAssertEqual(result.unverifiedExercises.count, 0, "All exercises should be verified for PFPS")
        XCTAssertEqual(result.contraindicatedExercises.count, 0)
    }

    func testVerifyPlan_noneVerified_unknownDoesNotBlock() {
        let exercises = [
            TestFixtures.makeExercise(name: "Mystery Exercise 1"),
            TestFixtures.makeExercise(name: "Mystery Exercise 2")
        ]
        let plan = TestFixtures.makePlan(
            conditions: ["Mystery Condition"],
            exercises: exercises
        )

        let result = service.verifyPlan(plan, conditions: ["Mystery Condition"])

        // KEY PRINCIPLE: Unknown ≠ wrong. All should be unverified, NOT blocked.
        XCTAssertEqual(result.unverifiedExercises.count, 2, "Unknown exercises for unknown condition should be unverified, not blocked")
        XCTAssertEqual(result.contraindicatedExercises.count, 0, "Unknown exercises must NOT be contraindicated")
    }

    func testVerifyPlan_conditionResults() {
        let exercises = [TestFixtures.makeExercise(name: "Quad Sets")]
        let plan = TestFixtures.makePlan(
            conditions: ["Patellofemoral Pain Syndrome", "Mystery Condition"],
            exercises: exercises
        )

        let result = service.verifyPlan(plan, conditions: ["Patellofemoral Pain Syndrome", "Mystery Condition"])

        let known = result.conditionResults.filter { $0.isKnown }
        let unknown = result.conditionResults.filter { !$0.isKnown }

        XCTAssertEqual(known.count, 1, "PFPS should be a known condition")
        XCTAssertEqual(unknown.count, 1, "Mystery Condition should be unknown")
    }

    func testVerifyPlan_multipleConditions_contraindicationWins() {
        // Glute bridges are safe for herniated disc, but what about a condition where they're unsafe?
        // Here: an exercise safe for one condition but contraindicated for another
        let exercises = [TestFixtures.makeExercise(name: "Deadlift")]
        let plan = TestFixtures.makePlan(
            conditions: ["Herniated Disc", "Patellofemoral Pain Syndrome"],
            exercises: exercises
        )

        let result = service.verifyPlan(plan, conditions: ["Herniated Disc", "Patellofemoral Pain Syndrome"])

        // Deadlift is contraindicated for herniated disc — that should win
        XCTAssertEqual(result.contraindicatedExercises.count, 1)
    }

    // MARK: - Red Flags

    func testRedFlags_knownCondition() {
        let flags = service.redFlags(forCondition: "Patellofemoral Pain Syndrome")
        XCTAssertNotNil(flags)
        XCTAssertFalse(flags!.isEmpty, "PFPS should have red flags defined")
        XCTAssertTrue(flags!.contains("knee locking"))
    }

    func testRedFlags_unknownCondition() {
        let flags = service.redFlags(forCondition: "Unknown Condition")
        XCTAssertNil(flags, "Unknown condition should return nil for red flags")
    }

    func testReferralCriteria_knownCondition() {
        let criteria = service.referralCriteria(forCondition: "Meniscus Tear")
        XCTAssertNotNil(criteria)
        XCTAssertFalse(criteria!.isEmpty)
    }

    // MARK: - VerificationTier Equatable

    func testVerificationTier_equatable() {
        XCTAssertEqual(VerificationTier.verified, VerificationTier.verified)
        XCTAssertEqual(VerificationTier.unverified, VerificationTier.unverified)
        XCTAssertEqual(
            VerificationTier.contraindicated(reason: "test"),
            VerificationTier.contraindicated(reason: "test")
        )
        XCTAssertNotEqual(VerificationTier.verified, VerificationTier.unverified)
        XCTAssertNotEqual(
            VerificationTier.contraindicated(reason: "a"),
            VerificationTier.contraindicated(reason: "b")
        )
    }

    // MARK: - ExerciseVerificationStatus Equatable

    func testExerciseVerificationStatus_equatable() {
        XCTAssertEqual(ExerciseVerificationStatus.verified, ExerciseVerificationStatus.verified)
        XCTAssertEqual(ExerciseVerificationStatus.checking, ExerciseVerificationStatus.checking)
        XCTAssertEqual(ExerciseVerificationStatus.crossModelVerified, ExerciseVerificationStatus.crossModelVerified)
        XCTAssertEqual(ExerciseVerificationStatus.crossModelFailed, ExerciseVerificationStatus.crossModelFailed)
        XCTAssertNotEqual(ExerciseVerificationStatus.verified, ExerciseVerificationStatus.checking)
        XCTAssertEqual(
            ExerciseVerificationStatus.crossModelFlagged(concerns: ["a"]),
            ExerciseVerificationStatus.crossModelFlagged(concerns: ["a"])
        )
        XCTAssertNotEqual(
            ExerciseVerificationStatus.crossModelFlagged(concerns: ["a"]),
            ExerciseVerificationStatus.crossModelFlagged(concerns: ["b"])
        )
    }

    // MARK: - Injection Test (validates the DI mechanism)

    func testCustomGraph_injectedForTesting() {
        let miniGraph = KnowledgeGraph(
            version: "mini",
            conditions: [
                "test-cond": KnownCondition(
                    names: ["test condition"],
                    icd10: "T00.0",
                    bodyRegions: ["test"],
                    safeExercises: ["safe-ex"],
                    unsafeExercises: ["unsafe-ex"],
                    redFlags: [],
                    referIfPresent: []
                )
            ],
            exercises: [
                "safe-ex": KnownExercise(names: ["safe exercise"], targetRegions: ["test"], category: "strength", safeForConditions: ["test-cond"], unsafeForConditions: []),
                "unsafe-ex": KnownExercise(names: ["unsafe exercise"], targetRegions: ["test"], category: "strength", safeForConditions: [], unsafeForConditions: ["test-cond"])
            ]
        )

        let miniService = KnowledgeGraphService(graph: miniGraph)

        XCTAssertEqual(miniService.verify(exercise: "safe exercise", forCondition: "test condition"), .verified)

        if case .contraindicated = miniService.verify(exercise: "unsafe exercise", forCondition: "test condition") {
            // Expected
        } else {
            XCTFail("unsafe exercise should be contraindicated")
        }

        XCTAssertEqual(miniService.verify(exercise: "unknown", forCondition: "test condition"), .unverified)
    }

    // MARK: - KnowledgeGraphValidator Integration

    func testKnowledgeGraphValidator_producesWarningsForContraindicated() {
        let exercises = [
            TestFixtures.makeExercise(name: "Bulgarian Split Squat", targetArea: "Knee")
        ]
        let (warnings, verification) = KnowledgeGraphValidator.validate(
            exercises: exercises,
            conditions: ["Patellofemoral Pain Syndrome"],
            knowledgeGraph: service
        )

        XCTAssertFalse(warnings.isEmpty, "Should produce warnings for contraindicated exercise")
        XCTAssertEqual(verification.contraindicatedExercises.count, 1)
    }

    func testKnowledgeGraphValidator_noContraindicationWarningsForVerified() {
        let exercises = [
            TestFixtures.makeExercise(name: "Quad Sets", targetArea: "Knee")
        ]
        let (warnings, _) = KnowledgeGraphValidator.validate(
            exercises: exercises,
            conditions: ["Patellofemoral Pain Syndrome"],
            knowledgeGraph: service
        )

        // Filter to contraindication warnings. KnowledgeGraphValidator emits these at
        // `.serious` (Tier 1) — filtering on .caution/.urgent excluded the exact
        // severity this test exists to check, so it passed no matter what production
        // did. Anything at or above .serious counts.
        let contraindicationWarnings = warnings.filter { $0.severity >= .serious }
        XCTAssertTrue(contraindicationWarnings.isEmpty, "Should not produce contraindication warnings for verified exercises")
    }

    // MARK: - Edge Cases

    func testEmptyGraph_allUnverified() {
        let emptyGraph = KnowledgeGraph(version: "empty", conditions: [:], exercises: [:])
        let emptyService = KnowledgeGraphService(graph: emptyGraph)

        let tier = emptyService.verify(exercise: "Anything", forCondition: "Anything")
        XCTAssertEqual(tier, .unverified, "Empty graph should return unverified for everything")
    }

    func testConditionWithNoUnsafe_neverContraindicates() {
        // Plantar fasciitis has no unsafe exercises in our test graph
        let tier = service.verify(exercise: "Quad Sets", forCondition: "Plantar Fasciitis")
        if case .contraindicated = tier {
            XCTFail("Should never contraindicate when condition has no unsafe exercises mapped for this exercise")
        }
    }
}
