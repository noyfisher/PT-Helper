import XCTest
@testable import COIL

/// `WellnessPlanValidator` is the wellness flow's ONLY per-exercise
/// contraindication gate — `WellnessAnalyzer` defers to it explicitly — and it
/// had zero test references while the rehab-side analogue was covered. Any
/// regression that dropped these `.serious` warnings would have shipped green,
/// letting a knowledge-graph-contraindicated exercise reach a user with a
/// declared medical condition with no acknowledgement gate.
///
/// These run against the SHIPPED knowledge graph rather than an injected one, so
/// they also pin that the real data still contains the pairs being relied on.
@MainActor
final class WellnessPlanValidatorTests: XCTestCase {

    private func exercise(_ name: String) -> RehabExercise {
        RehabExercise(
            id: UUID(), name: name, targetArea: "Elbow",
            description: "Test", sets: 3, reps: "10",
            restSeconds: 45, difficulty: .beginner,
            demonstrationIcon: "figure.cooldown",
            tips: [], contraindications: []
        )
    }

    // MARK: - The gate fires

    /// `wrist-curls` is in lateral-epicondylitis's unsafe list in the shipped graph.
    func testContraindicatedExercise_forDeclaredCondition_raisesSeriousWarning() {
        let warnings = WellnessPlanValidator.validate(
            exercises: [exercise("Wrist Curls")],
            conditions: ["Tennis Elbow"]
        )

        XCTAssertEqual(warnings.count, 1)
        XCTAssertEqual(warnings.first?.severity, .serious,
                       "Contraindications must be .serious — that is what gates the acknowledgement sheet")
    }

    /// Spelling tolerance matters here too: the model emits singular and
    /// differently-punctuated names.
    func testContraindication_isFoundForASingularExerciseName() {
        let warnings = WellnessPlanValidator.validate(
            exercises: [exercise("Wrist Curl")],
            conditions: ["Tennis Elbow"]
        )
        XCTAssertFalse(warnings.isEmpty, "A singular name must not slip past the gate")
    }

    func testOnlyTheOffendingExercise_isFlagged() {
        let warnings = WellnessPlanValidator.validate(
            exercises: [exercise("Wrist Curls"), exercise("Wall Sits")],
            conditions: ["Tennis Elbow"]
        )
        XCTAssertEqual(warnings.count, 1, "A safe exercise alongside an unsafe one must not be flagged")
    }

    /// One warning per exercise even when several declared conditions contraindicate
    /// it — the loop breaks on the first hit.
    func testMultipleConditions_produceOneWarningPerExercise() {
        let warnings = WellnessPlanValidator.validate(
            exercises: [exercise("Wrist Curls")],
            conditions: ["Tennis Elbow", "Lateral Epicondylitis"]
        )
        XCTAssertEqual(warnings.count, 1)
    }

    // MARK: - The gate stays quiet when it should

    /// The common wellness case: no declared conditions, so nothing to check.
    func testNoConditions_producesNoWarnings() {
        let warnings = WellnessPlanValidator.validate(
            exercises: [exercise("Wrist Curls")],
            conditions: []
        )
        XCTAssertTrue(warnings.isEmpty)
    }

    func testSafeExercise_forDeclaredCondition_producesNoWarnings() {
        let warnings = WellnessPlanValidator.validate(
            exercises: [exercise("Reverse Wrist Curls")],
            conditions: ["Tennis Elbow"]
        )
        XCTAssertTrue(warnings.isEmpty,
                      "reverse-wrist-curls is in the condition's SAFE list — flagging it would train users to dismiss warnings")
    }

    func testUnknownExercise_producesNoWarning() {
        let warnings = WellnessPlanValidator.validate(
            exercises: [exercise("Underwater Basket Weaving")],
            conditions: ["Tennis Elbow"]
        )
        XCTAssertTrue(warnings.isEmpty, "Unverified is not the same as contraindicated")
    }

    func testEmptyExerciseList_producesNoWarnings() {
        XCTAssertTrue(WellnessPlanValidator.validate(exercises: [], conditions: ["Tennis Elbow"]).isEmpty)
    }
}
