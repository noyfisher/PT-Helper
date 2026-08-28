import XCTest
import FirebaseFirestore
@testable import COIL

/// Firestore document round trip for `rehabPlans`.
///
/// These exist because `planType` was written by the wellness save path but never
/// read back by the parser, and then actively *deleted* by `updatePlan` (a
/// full-document `setData` that omitted the field). The repair-on-load pass calls
/// `updatePlan` for every schemaVersion<2 plan, so every wellness plan silently
/// became a rehab plan shortly after it was saved, with no recovery signal left.
///
/// The save -> parse -> update -> parse cycle below is the shape that catches it:
/// a one-hop test passes even when the second hop erases the field.
@MainActor
final class SavedPlansRoundTripTests: XCTestCase {

    // MARK: - Helpers

    /// One full persistence cycle: serialize, read back, serialize the read-back
    /// value, read that back. Mirrors save -> listener -> repair pass -> listener.
    private func roundTrip(_ plan: RehabPlan) throws -> (firstHop: RehabPlan, secondHop: RehabPlan) {
        let firstDoc = SavedPlansViewModel.planDocumentData(for: plan)
        let firstHop = try XCTUnwrap(SavedPlansViewModel.parsePlan(from: firstDoc),
                                     "First hop failed to parse")
        let secondDoc = SavedPlansViewModel.planDocumentData(for: firstHop)
        let secondHop = try XCTUnwrap(SavedPlansViewModel.parsePlan(from: secondDoc),
                                      "Second hop failed to parse")
        return (firstHop, secondHop)
    }

    private func makeWellnessPlan() -> RehabPlan {
        var plan = TestFixtures.makePlan(name: "Posture Reset")
        plan.planType = .wellness
        plan.sourceGoalCategories = ["improve_posture", "reduce_stiffness"]
        return plan
    }

    // MARK: - planType survival (the P1)

    func testRoundTrip_wellnessPlan_planTypeSurvivesBothHops() throws {
        let (firstHop, secondHop) = try roundTrip(makeWellnessPlan())

        XCTAssertEqual(firstHop.planType, .wellness,
                       "planType must be read back — parsePlan previously ignored the field")
        XCTAssertEqual(secondHop.planType, .wellness,
                       "planType must survive a re-save — updatePlan previously erased it")
    }

    func testRoundTrip_wellnessPlan_sourceGoalCategoriesSurviveBothHops() throws {
        let (firstHop, secondHop) = try roundTrip(makeWellnessPlan())

        XCTAssertEqual(firstHop.sourceGoalCategories, ["improve_posture", "reduce_stiffness"])
        XCTAssertEqual(secondHop.sourceGoalCategories, ["improve_posture", "reduce_stiffness"],
                       "sourceGoalCategories must survive a re-save")
    }

    /// The exact production sequence that destroyed the data: a wellness plan is
    /// saved at schemaVersion 1, the repair pass bumps it to 2 and calls updatePlan.
    func testRepairPassSimulation_wellnessPlan_isNotConvertedToRehab() throws {
        var plan = makeWellnessPlan()
        plan.schemaVersion = 1

        let saved = try XCTUnwrap(SavedPlansViewModel.parsePlan(
            from: SavedPlansViewModel.planDocumentData(for: plan)))
        XCTAssertEqual(saved.schemaVersion, 1)

        // Repair pass: bump the version and write the whole document back.
        var repaired = saved
        repaired.schemaVersion = 2
        let afterRepair = try XCTUnwrap(SavedPlansViewModel.parsePlan(
            from: SavedPlansViewModel.planDocumentData(for: repaired)))

        XCTAssertEqual(afterRepair.planType, .wellness,
                       "The repair pass must not convert a wellness plan into a rehab plan")
        XCTAssertEqual(afterRepair.schemaVersion, 2)
    }

    // MARK: - Rehab plans keep working

    func testRoundTrip_rehabPlan_staysRehab() throws {
        let (_, secondHop) = try roundTrip(TestFixtures.makePlan(name: "Knee Rehab"))
        XCTAssertEqual(secondHop.planType, .rehab)
        XCTAssertNil(secondHop.sourceGoalCategories)
    }

    /// Documents written before `planType` existed have no such field; they must
    /// keep defaulting to .rehab rather than failing to parse.
    func testParse_legacyDocumentWithoutPlanType_defaultsToRehab() throws {
        var legacyDoc = SavedPlansViewModel.planDocumentData(for: TestFixtures.makePlan(name: "Legacy"))
        legacyDoc.removeValue(forKey: "planType")
        legacyDoc.removeValue(forKey: "sourceGoalCategories")

        let parsed = try XCTUnwrap(SavedPlansViewModel.parsePlan(from: legacyDoc))
        XCTAssertEqual(parsed.planType, .rehab)
        XCTAssertNil(parsed.sourceGoalCategories)
    }

    func testParse_unrecognizedPlanType_fallsBackToRehab() throws {
        var doc = SavedPlansViewModel.planDocumentData(for: TestFixtures.makePlan(name: "Odd"))
        doc["planType"] = "not_a_real_plan_type"

        let parsed = try XCTUnwrap(SavedPlansViewModel.parsePlan(from: doc))
        XCTAssertEqual(parsed.planType, .rehab, "An unknown planType must not crash or mis-classify")
    }

    // MARK: - The rest of the document still round-trips

    func testRoundTrip_preservesCoreFields() throws {
        var plan = TestFixtures.makePlan(name: "Full Fidelity")
        plan.startDate = Date(timeIntervalSince1970: 1_700_000_000)
        plan.schemaVersion = 2

        let (_, secondHop) = try roundTrip(plan)

        XCTAssertEqual(secondHop.id, plan.id)
        XCTAssertEqual(secondHop.planName, plan.planName)
        XCTAssertEqual(secondHop.conditions, plan.conditions)
        XCTAssertEqual(secondHop.totalWeeks, plan.totalWeeks)
        XCTAssertEqual(secondHop.exercises.count, plan.exercises.count)
        XCTAssertEqual(secondHop.exercises.first?.name, plan.exercises.first?.name)
        XCTAssertEqual(secondHop.schemaVersion, 2)
        XCTAssertEqual(secondHop.startDate?.timeIntervalSince1970,
                       plan.startDate?.timeIntervalSince1970)
    }

    /// `startDate` is what drives currentWeek/isCompleted, and the plan-header
    /// DatePicker now edits it. A dropped startDate would silently reset progress.
    func testRoundTrip_startDateNil_staysNil() throws {
        var plan = TestFixtures.makePlan(name: "Not Started")
        plan.startDate = nil

        let (_, secondHop) = try roundTrip(plan)
        XCTAssertNil(secondHop.startDate)
    }
}
