import XCTest
@testable import COIL

/// Covers the shared matcher that replaced two ad-hoc implementations in the
/// deterministic safety layer: the knowledge-graph alias lookup (which returned the
/// first hit while iterating an unordered Dictionary) and the contraindication table
/// (which matched hyphenated keywords with a plain `contains`).
final class TermMatchingTests: XCTestCase {

    // MARK: - Normalisation

    func testNormalize_foldsSeparatorsAndCase() {
        XCTAssertEqual(TermMatching.normalize("Sit-Ups"), "sit ups")
        XCTAssertEqual(TermMatching.normalize("  Deep   Squat  "), "deep squat")
        XCTAssertEqual(TermMatching.normalize("Golfer's Elbow"), "golfer s elbow")
    }

    // MARK: - containsTerm: the spellings the model actually emits

    func testContainsTerm_hyphenatedKeywordMatchesSpacedAndRunTogether() {
        // The exact miss that let sit-ups through for a herniated disc.
        XCTAssertTrue(TermMatching.containsTerm("sit-up", in: "Sit Ups"))
        XCTAssertTrue(TermMatching.containsTerm("sit-up", in: "Situps"))
        XCTAssertTrue(TermMatching.containsTerm("sit-up", in: "Weighted Sit-Up"))
        XCTAssertTrue(TermMatching.containsTerm("pull-up", in: "Pull Ups"))
        XCTAssertTrue(TermMatching.containsTerm("chin-up", in: "Chin Ups"))
    }

    func testContainsTerm_toleratesWordOrder() {
        XCTAssertTrue(TermMatching.containsTerm("jump squat", in: "Squat Jumps"))
        XCTAssertTrue(TermMatching.containsTerm("box jump", in: "Box Jumps"))
    }

    /// Documents a deliberate limit: plurals fold, gerunds do not. Stemming
    /// "jumping" to "jump" would widen every term in the table (and "running" to
    /// "run"), which is not a change to make in a safety gate without evidence that
    /// the model emits those forms. The single-token entry "jumping" already covers
    /// this exercise, which is why the gap is acceptable.
    func testContainsTerm_doesNotStemGerunds() {
        XCTAssertFalse(TermMatching.containsTerm("box jump", in: "Jumping Box Step"))
        XCTAssertTrue(TermMatching.containsTerm("jumping", in: "Jumping Box Step"))
    }

    func testContainsTerm_toleratesApostrophes() {
        XCTAssertTrue(TermMatching.containsTerm("golfers elbow", in: "Golfer's Elbow"))
    }

    func testContainsTerm_singleTokenKeepsSubstringSemantics() {
        // Deliberately broad terms must keep behaving exactly as before.
        XCTAssertTrue(TermMatching.containsTerm("extension", in: "Terminal Knee Extension"))
        XCTAssertTrue(TermMatching.containsTerm("jumping", in: "Jumping Jacks"))
    }

    func testContainsTerm_doesNotOverMatch() {
        // The guard against widening: unrelated exercises must stay unflagged.
        XCTAssertFalse(TermMatching.containsTerm("sit-up", in: "Wall Sits"))
        XCTAssertFalse(TermMatching.containsTerm("box jump", in: "Squat Jumps"))
        XCTAssertFalse(TermMatching.containsTerm("deadlift", in: "Glute Bridge"))
        XCTAssertFalse(TermMatching.containsTerm("overhead press", in: "Leg Press"))
    }

    // MARK: - bestMatch: determinism

    func testBestMatch_isStableAcrossManyLookups() {
        let aliases = [
            "wrist curls": "wrist-curls",
            "reverse wrist curls": "reverse-wrist-curls",
            "step ups": "step-ups",
            "lateral step ups": "lateral-step-ups",
        ]

        // A single run of the old implementation could not reveal the bug — the
        // hash seed is fixed per process — so this pins the *rule* instead: the
        // resolved id must be a specific value, not merely a repeatable one.
        let resolved = Set((0..<200).compactMap { _ in
            TermMatching.bestMatch(for: "Wrist Curl", in: aliases)?.value
        })
        XCTAssertEqual(resolved, ["wrist-curls"])
    }

    /// The safety-critical direction. "Wrist Curl" is contained in both
    /// `wrist curls` and `reverse wrist curls`, which carry OPPOSITE verdicts for
    /// tennis elbow in the shipped graph. Resolving to the specialised variant
    /// would hand back the safe verdict for a movement the user did not describe.
    func testBestMatch_underspecifiedInput_prefersLeastSpecialisedAlias() {
        let aliases = [
            "wrist curls": "wrist-curls",
            "reverse wrist curls": "reverse-wrist-curls",
        ]
        XCTAssertEqual(TermMatching.bestMatch(for: "Wrist Curl", in: aliases)?.value, "wrist-curls")
    }

    func testBestMatch_specificInput_prefersMostSpecificAlias() {
        let aliases = [
            "step ups": "step-ups",
            "lateral step ups": "lateral-step-ups",
        ]
        XCTAssertEqual(TermMatching.bestMatch(for: "Lateral Step Ups", in: aliases)?.value, "lateral-step-ups")
    }

    func testBestMatch_knownTermInsideLongerName_prefersLongestAlias() {
        let aliases = [
            "stretch": "generic-stretch",
            "cat cow stretch": "cat-cow-stretch",
        ]
        let match = TermMatching.bestMatch(for: "Modified Cat-Cow Stretch for Lower Back Relief", in: aliases)
        XCTAssertEqual(match?.value, "cat-cow-stretch")
    }

    func testBestMatch_exactWinsOverContainment() {
        let aliases = [
            "squats": "squats",
            "bodyweight squats": "bodyweight-squats",
        ]
        XCTAssertEqual(TermMatching.bestMatch(for: "Squats", in: aliases)?.value, "squats")
    }

    func testBestMatch_singleTokenDoesNotSubstringMatch() {
        // "row" must not resolve via "narrow".
        XCTAssertNil(TermMatching.bestMatch(for: "row", in: ["narrow": "narrow-stance"]))
    }

    func testBestMatch_noMatch_returnsNil() {
        XCTAssertNil(TermMatching.bestMatch(for: "Underwater Basket Weaving", in: ["squats": "squats"]))
    }

    func testBestMatch_emptyInput_returnsNil() {
        XCTAssertNil(TermMatching.bestMatch(for: "   ", in: ["squats": "squats"]))
    }
}
