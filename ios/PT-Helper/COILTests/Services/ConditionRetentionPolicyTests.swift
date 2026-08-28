import XCTest
@testable import COIL

/// Unit coverage for the retention rule that replaced two drifting `prefix(3)`
/// calls (`InjuryAnalyzer.synthesize` and `validateAnalysis`). Both previously
/// ranked red flags against the benign differential, so a low-confidence red flag
/// was always truncated out — including one the safety step had just re-added.
final class ConditionRetentionPolicyTests: XCTestCase {

    private func condition(_ name: String, _ confidence: Double, redFlag: Bool = false) -> ConditionResult {
        TestFixtures.makeCondition(name: name, commonName: name, confidence: confidence, isRedFlag: redFlag)
    }

    // MARK: - Ranked head

    func testRetain_keepsRankedHeadVerbatim() {
        let ordered = [condition("A", 80), condition("B", 60), condition("C", 40), condition("D", 20)]

        let retention = ConditionRetentionPolicy.retain(ordered)

        XCTAssertEqual(retention.conditions.map(\.conditionName), ["A", "B", "C"])
        XCTAssertEqual(retention.rescuedRedFlagCount, 0)
    }

    func testRetain_shorterThanHead_returnsAll() {
        let ordered = [condition("A", 80), condition("B", 60)]
        XCTAssertEqual(ConditionRetentionPolicy.retain(ordered).conditions.count, 2)
    }

    func testRetain_empty_returnsEmpty() {
        XCTAssertTrue(ConditionRetentionPolicy.retain([]).conditions.isEmpty)
    }

    // MARK: - Red-flag rescue (the P0)

    func testRetain_redFlagBeyondHead_isRescued() {
        let ordered = [
            condition("Benign A", 80), condition("Benign B", 60), condition("Benign C", 40),
            condition("DVT", 15, redFlag: true),
        ]

        let retention = ConditionRetentionPolicy.retain(ordered)

        XCTAssertEqual(retention.conditions.count, 4)
        XCTAssertEqual(retention.rescuedRedFlagCount, 1)
        XCTAssertEqual(retention.droppedRedFlagCount, 0)
        XCTAssertEqual(retention.conditions.last?.conditionName, "DVT",
                       "Rescued flags append after the head so `conditions.first` is unchanged")
    }

    func testRetain_redFlagInsideHead_isNotDuplicated() {
        let ordered = [
            condition("Fracture", 80, redFlag: true), condition("Benign B", 60), condition("Benign C", 40),
        ]

        let retention = ConditionRetentionPolicy.retain(ordered)

        XCTAssertEqual(retention.conditions.count, 3)
        XCTAssertEqual(retention.rescuedRedFlagCount, 0)
        XCTAssertEqual(retention.conditions.filter { $0.conditionName == "Fracture" }.count, 1)
    }

    func testRetain_nonRedFlagBeyondHead_isStillDropped() {
        let ordered = [
            condition("A", 80), condition("B", 60), condition("C", 40), condition("D", 20),
        ]
        XCTAssertFalse(ConditionRetentionPolicy.retain(ordered).conditions.contains { $0.conditionName == "D" })
    }

    func testRetain_overRescueCap_reportsDropped() {
        var ordered = [condition("A", 80), condition("B", 60), condition("C", 40)]
        for index in 0..<(ConditionRetentionPolicy.maxRescuedRedFlags + 2) {
            ordered.append(condition("Flag \(index)", 10, redFlag: true))
        }

        let retention = ConditionRetentionPolicy.retain(ordered)

        XCTAssertEqual(retention.rescuedRedFlagCount, ConditionRetentionPolicy.maxRescuedRedFlags)
        XCTAssertEqual(retention.droppedRedFlagCount, 2,
                       "Over-cap drops are reported rather than silently swallowed")
    }
}
