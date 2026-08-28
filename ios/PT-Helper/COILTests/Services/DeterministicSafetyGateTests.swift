import XCTest
@testable import COIL

/// End-to-end coverage for the two deterministic safety gates, exercised against
/// the **shipped** knowledge graph and contraindication table rather than fixtures.
///
/// Both gates had spelling/ordering defects that only show up on real data:
/// the graph's alias lookup returned the first hit while iterating an unordered
/// Dictionary, and the contraindication table matched hyphenated keywords with a
/// plain `contains`.
@MainActor
final class DeterministicSafetyGateTests: XCTestCase {

    // MARK: - Knowledge graph (real shipped data)

    /// `wrist-curls` is in lateral-epicondylitis's unsafe list while
    /// `reverse-wrist-curls` is in its safe list. A singular "Wrist Curl" is a
    /// plausible model output and matches both aliases, so before the fix the
    /// verdict depended on dictionary iteration order — the same input could be
    /// reported contraindicated on one launch and verified-safe on the next.
    func testVerify_singularWristCurl_forTennisElbow_isDeterministicallyContraindicated() {
        let service = KnowledgeGraphService.shared

        var verdicts = Set<String>()
        for _ in 0..<50 {
            switch service.verify(exercise: "Wrist Curl", forCondition: "Tennis Elbow") {
            case .contraindicated: verdicts.insert("contraindicated")
            case .verified:        verdicts.insert("verified")
            case .unverified:      verdicts.insert("unverified")
            }
        }

        XCTAssertEqual(verdicts, ["contraindicated"],
                       "A safety verdict must not depend on which alias the dictionary happened to yield first")
    }

    /// The specialised variant must still resolve to itself, not collapse onto the
    /// plain movement — it is the one that is actually unsafe for an ACL sprain.
    func testVerify_lateralStepUps_forACLSprain_isContraindicated() {
        let service = KnowledgeGraphService.shared

        if case .contraindicated = service.verify(exercise: "Lateral Step Ups", forCondition: "ACL Sprain") {
            // expected
        } else {
            XCTFail("lateral-step-ups is in acl-sprain's unsafe list and must resolve to itself")
        }
    }

    func testLookupExercise_isStableAcrossRepeatedCalls() {
        let service = KnowledgeGraphService.shared
        let names = ["Wrist Curl", "Step Ups", "Cat-Cow Stretch", "External Rotation"]

        for name in names {
            let resolved = Set((0..<25).map { _ in service.lookupExercise(name)?.id ?? "nil" })
            XCTAssertEqual(resolved.count, 1, "\(name) resolved inconsistently: \(resolved)")
        }
    }

    func testLookupCondition_isStableAcrossRepeatedCalls() {
        let service = KnowledgeGraphService.shared
        let names = ["Tennis Elbow", "Elbow Pain", "Runner's Knee", "ACL Tear"]

        for name in names {
            let resolved = Set((0..<25).map { _ in service.lookupCondition(name)?.id ?? "nil" })
            XCTAssertEqual(resolved.count, 1, "\(name) resolved inconsistently: \(resolved)")
        }
    }

    // MARK: - Contraindication table (real shipped table)

    private func contraindicationWarnings(exercise: String, conditions: [String]) -> [ValidationWarning] {
        ExerciseContraindicationChecker.validate(
            exercises: [TestFixtures.makeExercise(name: exercise, targetArea: "Core")],
            conditions: conditions
        ).filter { $0.severity >= .serious }
    }

    /// The table entry is `"sit-up"`. These are the spellings a model actually
    /// produces, and every one of them slipped through a plain `contains`. For a
    /// herniated disc this table is the only deterministic gate — the v1 graph
    /// lists no sit-up entry for that condition at all.
    func testContraindication_sitUpSpellings_areAllBlockedForHerniatedDisc() {
        for spelling in ["Sit Ups", "Situps", "Sit-Ups", "Weighted Sit Up"] {
            let warnings = contraindicationWarnings(exercise: spelling, conditions: ["Herniated Disc"])
            XCTAssertFalse(warnings.isEmpty, "\"\(spelling)\" should be flagged for a herniated disc")
        }
    }

    func testContraindication_pullUpSpellings_areBlockedForTennisElbow() {
        for spelling in ["Pull Ups", "Pullups"] {
            let warnings = contraindicationWarnings(exercise: spelling, conditions: ["Tennis Elbow"])
            XCTAssertFalse(warnings.isEmpty, "\"\(spelling)\" should be flagged for tennis elbow")
        }
    }

    func testContraindication_wordOrderVariant_isBlockedForACL() {
        let warnings = contraindicationWarnings(exercise: "Squat Jumps", conditions: ["ACL Tear"])
        XCTAssertFalse(warnings.isEmpty, "\"Squat Jumps\" is the table's \"jump squat\" in another word order")
    }

    func testContraindication_apostropheInCondition_stillMatches() {
        let warnings = contraindicationWarnings(exercise: "Wrist Curl", conditions: ["Golfer's Elbow"])
        XCTAssertFalse(warnings.isEmpty, "An apostrophe in the condition name must not defeat the gate")
    }

    /// The guard against over-widening. Loosening the match must not start flagging
    /// exercises that are appropriate for the condition.
    func testContraindication_safeExercises_stillProduceNoWarning() {
        for exercise in ["Wall Sits", "Glute Bridge", "Bird Dog", "Pelvic Tilt"] {
            let warnings = contraindicationWarnings(exercise: exercise, conditions: ["Herniated Disc"])
            XCTAssertTrue(warnings.isEmpty, "\"\(exercise)\" is appropriate here and must stay unflagged")
        }
    }

    func testContraindication_unrelatedCondition_producesNoWarning() {
        let warnings = contraindicationWarnings(exercise: "Sit Ups", conditions: ["Tennis Elbow"])
        XCTAssertTrue(warnings.isEmpty, "Sit-ups are not on the tennis-elbow list")
    }

    // MARK: - Tier aggregation across multiple conditions

    /// "Verified for condition A" must not stand in for "checked against condition
    /// B". A single `.verified` used to overwrite the tier, so an exercise the graph
    /// knows nothing about for the user's other condition was dropped from
    /// `unverifiedExercises` and never reached cross-model verification.
    func testVerifyPlan_verifiedForOneConditionButUnknownForAnother_staysUnverified() {
        let service = KnowledgeGraphService.shared

        // "Quad Sets" is known-safe for patellofemoral pain; the graph has nothing
        // to say about it for a wrist condition.
        let plan = TestFixtures.makePlan(name: "Mixed", exercises: [
            TestFixtures.makeExercise(name: "Quad Sets", targetArea: "Knee")
        ])

        let result = service.verifyPlan(plan, conditions: ["Patellofemoral Pain Syndrome", "Carpal Tunnel Syndrome"])

        XCTAssertTrue(result.unverifiedExercises.contains { $0.name == "Quad Sets" },
                      "An unknown pairing must still be routed to cross-model verification")
    }

    // MARK: - Body-zone resolution

    /// "upper_back_strain" contains both "back" (-> lower_back) and "upper_back"
    /// (-> upper_back). First-match-wins over a Dictionary could file the surgery
    /// under the wrong zone, changing whether that history reached the AI prompt.
    func testBodyAreaToZoneKey_nestedTerms_resolveToMostSpecificZone() {
        XCTAssertEqual(HistoryRelevanceFilter.bodyAreaToZoneKey("Upper Back Strain"), "upper_back")
        XCTAssertEqual(HistoryRelevanceFilter.bodyAreaToZoneKey("Lower Back Surgery"), "lower_back")
    }

    func testBodyAreaToZoneKey_isStableAcrossRepeatedCalls() {
        for area in ["Upper Back Strain", "ACL Reconstruction", "Rotator Cuff Repair", "Left Ankle"] {
            let resolved = Set((0..<25).map { _ in HistoryRelevanceFilter.bodyAreaToZoneKey(area) })
            XCTAssertEqual(resolved.count, 1, "\(area) resolved inconsistently: \(resolved)")
        }
    }
}
