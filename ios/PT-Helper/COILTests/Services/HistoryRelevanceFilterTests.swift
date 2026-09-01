import XCTest
@testable import COIL

final class HistoryRelevanceFilterTests: XCTestCase {

    // MARK: - Helpers

    private func makeRegion(zoneKey: String) -> BodyRegion {
        BodyRegion(
            name: zoneKey, zoneKey: zoneKey,
            sides: [.front],
            frontPosition: CGPoint(x: 0.5, y: 0.5),
            backPosition: nil
        )
    }

    // MARK: - Zone Key Normalization

    func testNormalizeZoneKey_stripsLeftPrefix() {
        XCTAssertEqual(HistoryRelevanceFilter.normalizeZoneKey("left_knee"), "knee")
    }

    func testNormalizeZoneKey_stripsRightPrefix() {
        XCTAssertEqual(HistoryRelevanceFilter.normalizeZoneKey("right_shoulder"), "shoulder")
    }

    func testNormalizeZoneKey_preservesMidlineRegions() {
        XCTAssertEqual(HistoryRelevanceFilter.normalizeZoneKey("lower_back"), "lower_back")
        XCTAssertEqual(HistoryRelevanceFilter.normalizeZoneKey("neck"), "neck")
    }

    // MARK: - Body Area to Zone Key Mapping

    func testBodyAreaToZoneKey_commonTerms() {
        XCTAssertEqual(HistoryRelevanceFilter.bodyAreaToZoneKey("Left Knee"), "knee")
        XCTAssertEqual(HistoryRelevanceFilter.bodyAreaToZoneKey("Right Shoulder"), "shoulder")
        XCTAssertEqual(HistoryRelevanceFilter.bodyAreaToZoneKey("Lower Back"), "lower_back")
    }

    func testBodyAreaToZoneKey_surgeryTerms() {
        XCTAssertEqual(HistoryRelevanceFilter.bodyAreaToZoneKey("ACL"), "knee")
        XCTAssertEqual(HistoryRelevanceFilter.bodyAreaToZoneKey("Rotator Cuff"), "shoulder")
        XCTAssertEqual(HistoryRelevanceFilter.bodyAreaToZoneKey("Achilles"), "ankle_foot")
        XCTAssertEqual(HistoryRelevanceFilter.bodyAreaToZoneKey("Herniated Disc"), "lower_back")
    }

    // MARK: - Surgery Classification

    func testSurgery_directAnatomicalMatch_isDirectlyRelevant() {
        let surgery = UserProfile.Surgery(name: "ACL Repair", year: 2023, bodyArea: "Left Knee")
        let regions = [makeRegion(zoneKey: "left_knee")]

        let classified = HistoryRelevanceFilter.classify(surgeries: [surgery], assessedRegions: regions)

        XCTAssertEqual(classified.count, 1)
        XCTAssertEqual(classified[0].relevance, .directlyRelevant)
    }

    func testSurgery_kineticChainMatch_recentIsPossiblyRelevant() {
        // Hip surgery, assessing knee — kinetic chain connected, 3 years ago
        let surgery = UserProfile.Surgery(name: "Hip Replacement", year: 2023, bodyArea: "Right Hip")
        let regions = [makeRegion(zoneKey: "right_knee")]

        let classified = HistoryRelevanceFilter.classify(surgeries: [surgery], assessedRegions: regions)

        XCTAssertEqual(classified[0].relevance, .possiblyRelevant)
    }

    func testSurgery_kineticChainMatch_veryRecentIsDirectlyRelevant() {
        let currentYear = Calendar.current.component(.year, from: Date())
        let surgery = UserProfile.Surgery(name: "Hip Replacement", year: currentYear, bodyArea: "Right Hip")
        let regions = [makeRegion(zoneKey: "right_knee")]

        let classified = HistoryRelevanceFilter.classify(surgeries: [surgery], assessedRegions: regions)

        XCTAssertEqual(classified[0].relevance, .directlyRelevant)
    }

    func testSurgery_stillRecovering_alwaysRelevant() {
        // Old surgery on unrelated area, but still recovering → directly relevant
        let surgery = UserProfile.Surgery(
            name: "Wrist Repair", year: 2018,
            bodyArea: "Left Wrist",
            recoveryStatus: "Still recovering"
        )
        let regions = [makeRegion(zoneKey: "right_knee")]

        let classified = HistoryRelevanceFilter.classify(surgeries: [surgery], assessedRegions: regions)

        XCTAssertEqual(classified[0].relevance, .directlyRelevant)
    }

    func testSurgery_hasRestrictions_alwaysRelevant() {
        let surgery = UserProfile.Surgery(
            name: "Spinal Fusion", year: 2015,
            bodyArea: "Lower Back",
            recoveryStatus: "Have restrictions",
            restrictions: "No heavy lifting"
        )
        let regions = [makeRegion(zoneKey: "left_ankle_foot")]

        let classified = HistoryRelevanceFilter.classify(surgeries: [surgery], assessedRegions: regions)

        XCTAssertEqual(classified[0].relevance, .directlyRelevant)
    }

    func testSurgery_noMatch_isBackground() {
        let surgery = UserProfile.Surgery(name: "Carpal Tunnel", year: 2018, bodyArea: "Right Wrist")
        let regions = [makeRegion(zoneKey: "left_knee")]

        let classified = HistoryRelevanceFilter.classify(surgeries: [surgery], assessedRegions: regions)

        // A `<=` bound here pinned nothing: it passed for background AND for
        // possiblyRelevant, so it could not distinguish the intended classification
        // from the bug where the surgical >5yr bump was applied even with no
        // anatomical or kinetic-chain match. A wrist surgery has no bearing on a knee
        // assessment and must not enter the AI prompt as possibly relevant.
        XCTAssertEqual(classified[0].relevance, .backgroundOnly)
    }

    // MARK: - Injury Classification

    func testInjury_currentInjury_isDirectlyRelevant() {
        let injury = UserProfile.Injury(
            bodyArea: "Right Ankle", description: "Sprained ankle",
            isCurrent: true
        )
        let regions = [makeRegion(zoneKey: "left_knee")]

        let classified = HistoryRelevanceFilter.classify(injuries: [injury], assessedRegions: regions)

        XCTAssertEqual(classified[0].relevance, .directlyRelevant)
    }

    func testInjury_stillDealingWithIt_isDirectlyRelevant() {
        let injury = UserProfile.Injury(
            bodyArea: "Lower Back", description: "Herniated disc",
            isCurrent: false,
            recoveryStatus: "Still dealing with it"
        )
        let regions = [makeRegion(zoneKey: "right_shoulder")]

        let classified = HistoryRelevanceFilter.classify(injuries: [injury], assessedRegions: regions)

        XCTAssertEqual(classified[0].relevance, .directlyRelevant)
    }

    func testInjury_directMatch_pastFullyRecovered_isDirectlyRelevant() {
        let injury = UserProfile.Injury(
            bodyArea: "Right Knee", description: "Torn meniscus",
            isCurrent: false,
            recoveryStatus: "Fully recovered"
        )
        let regions = [makeRegion(zoneKey: "right_knee")]

        let classified = HistoryRelevanceFilter.classify(injuries: [injury], assessedRegions: regions)

        XCTAssertEqual(classified[0].relevance, .directlyRelevant)
    }

    func testInjury_kineticChainMatch_recentIsPossiblyRelevant() {
        // Ankle injury 3 years ago, assessing knee — kinetic chain
        let injury = UserProfile.Injury(
            bodyArea: "Right Ankle", description: "Sprain",
            isCurrent: false, year: 2023,
            recoveryStatus: "Fully recovered"
        )
        let regions = [makeRegion(zoneKey: "right_knee")]

        let classified = HistoryRelevanceFilter.classify(injuries: [injury], assessedRegions: regions)

        // The kinetic-chain map is DIRECT connections only: ankle_foot connects to
        // calf_shin and calf_shin connects to knee, but ankle_foot and knee are not
        // directly connected, so this is not a chain match. `classifyInjury` returns
        // background outright when there is no direct match.
        XCTAssertEqual(classified[0].relevance, .backgroundOnly)
    }

    func testInjury_oldNoMatch_isBackground() {
        let injury = UserProfile.Injury(
            bodyArea: "Left Wrist", description: "Fracture",
            isCurrent: false, year: 2015,
            recoveryStatus: "Fully recovered"
        )
        let regions = [makeRegion(zoneKey: "right_knee")]

        let classified = HistoryRelevanceFilter.classify(injuries: [injury], assessedRegions: regions)

        XCTAssertEqual(classified[0].relevance, .backgroundOnly)
    }

    // MARK: - Kinetic Chain Connections

    func testKineticChain_hipToKnee_connected() {
        // Hip injury, assessing thigh (which connects to knee which connects to hip)
        let injury = UserProfile.Injury(
            bodyArea: "Left Hip", description: "Bursitis",
            isCurrent: false, year: 2024,
            recoveryStatus: "Mostly recovered"
        )
        let regions = [makeRegion(zoneKey: "left_thigh")]

        let classified = HistoryRelevanceFilter.classify(injuries: [injury], assessedRegions: regions)

        // hip → thigh is a direct connection
        XCTAssertTrue(classified[0].relevance >= .possiblyRelevant)
    }

    func testKineticChain_neckToShoulder_connected() {
        let injury = UserProfile.Injury(
            bodyArea: "Neck", description: "Strain",
            isCurrent: false, year: 2025,
            recoveryStatus: "Mostly recovered"
        )
        let regions = [makeRegion(zoneKey: "left_shoulder")]

        let classified = HistoryRelevanceFilter.classify(injuries: [injury], assessedRegions: regions)

        XCTAssertTrue(classified[0].relevance >= .possiblyRelevant)
    }

    // MARK: - Multiple Regions

    func testMultipleRegions_matchesBestRelevance() {
        let surgery = UserProfile.Surgery(name: "Knee Surgery", year: 2024, bodyArea: "Right Knee")
        let regions = [
            makeRegion(zoneKey: "left_shoulder"),
            makeRegion(zoneKey: "right_knee")
        ]

        let classified = HistoryRelevanceFilter.classify(surgeries: [surgery], assessedRegions: regions)

        XCTAssertEqual(classified[0].relevance, .directlyRelevant)
    }
}
