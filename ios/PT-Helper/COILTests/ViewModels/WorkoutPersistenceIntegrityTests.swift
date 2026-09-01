import XCTest
@testable import COIL

/// Covers the workout-state defects that shared one shape: state failing to
/// reach persistence, or overwriting persistence it should not have, while the
/// UI reported success either way.
@MainActor
final class WorkoutPersistenceIntegrityTests: XCTestCase {

    private func makeExercise(name: String = "Wall Sits", sets: Int = 3) -> RehabExercise {
        RehabExercise(
            id: UUID(), name: name, targetArea: "Knee",
            description: "Test exercise", sets: sets, reps: "10",
            restSeconds: 30, difficulty: .beginner,
            demonstrationIcon: "figure.cooldown",
            tips: [], contraindications: []
        )
    }

    private func makePlan(sets: Int = 3) -> RehabPlan {
        RehabPlan(
            id: UUID(), planName: "Checkpoint Plan",
            conditions: ["Knee Pain"],
            exercises: [
                makeExercise(name: "Ex1", sets: sets),
                makeExercise(name: "Ex2", sets: sets)
            ],
            weeklySchedule: Array(repeating: [], count: 7),
            totalWeeks: 6, createdDate: Date(), notes: nil
        )
    }

    override func tearDown() {
        GuidedWorkoutViewModel.clearAllLocalWorkoutState()
        super.tearDown()
    }

    // MARK: - Failed writes are surfaced, not just logged

    func testPersistenceFailure_messageNamesWhatFailedAndSaysWhereItIs() {
        let failure = PersistenceFailure(subject: "your workout", underlyingDescription: "network down")

        XCTAssertEqual(failure.title, "Couldn't save your workout")
        XCTAssertTrue(failure.message.contains("saved on this device"),
                      "The copy must say the data still exists locally rather than implying total loss")
        XCTAssertFalse(failure.message.contains("network down"),
                       "Raw error text belongs in the log, not in front of the user")
    }

    func testPersistenceFailure_equatesOnSubjectAndCause() {
        let a = PersistenceFailure(subject: "your workout", underlyingDescription: "offline")
        let b = PersistenceFailure(subject: "your workout", underlyingDescription: "offline")
        let c = PersistenceFailure(subject: "your check-in", underlyingDescription: "offline")
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    // MARK: - Checkpoint integrity

    /// `handleAppBackgrounded` is live from the moment the workout view appears, so
    /// backgrounding while the Resume prompt was still up wrote a checkpoint for the
    /// freshly-initialised ViewModel — exercise 0, set 1, nothing completed — over
    /// the real record of the interrupted workout.
    func testBackgrounding_whileAwaitingResumeDecision_doesNotOverwriteTheCheckpoint() {
        let plan = makePlan()
        let first = GuidedWorkoutViewModel(plan: plan)
        first.completeSet()   // real progress: currentSet advances and checkpoints

        guard let before = GuidedWorkoutViewModel.savedCheckpoint(forPlanId: plan.id.uuidString) else {
            return XCTFail("Expected a checkpoint after completeSet")
        }
        XCTAssertEqual(before.currentSet, 2)

        // Relaunch: a fresh ViewModel sits at set 1 while the prompt is pending.
        let relaunched = GuidedWorkoutViewModel(plan: plan)
        relaunched.isAwaitingCheckpointDecision = true
        relaunched.handleAppBackgrounded()

        let after = GuidedWorkoutViewModel.savedCheckpoint(forPlanId: plan.id.uuidString)
        XCTAssertEqual(after?.currentSet, before.currentSet,
                       "The pending checkpoint is the only record of the interrupted workout")
    }

    func testBackgrounding_whenNotAwaitingDecision_stillCheckpoints() {
        let plan = makePlan()
        let vm = GuidedWorkoutViewModel(plan: plan)
        vm.completeSet()
        vm.handleAppBackgrounded()

        XCTAssertNotNil(GuidedWorkoutViewModel.savedCheckpoint(forPlanId: plan.id.uuidString),
                        "Normal backgrounding must still persist progress")
    }

    /// Swaps reset `currentSet` in memory but did not checkpoint, so a crash after a
    /// mid-set swap restored the substitute at the pre-swap set counter.
    func testSwappingAnExercise_persistsTheResetSetCounter() {
        let plan = makePlan(sets: 3)
        let vm = GuidedWorkoutViewModel(plan: plan)
        vm.completeSet()
        vm.completeSet()   // now partway through the exercise

        let substitute = makeExercise(name: "Substitute Move", sets: 3)
        var updated = plan
        updated.exercises[0] = substitute
        vm.swapCurrentExercise(with: substitute, updatedPlan: updated)

        let checkpoint = GuidedWorkoutViewModel.savedCheckpoint(forPlanId: plan.id.uuidString)
        XCTAssertEqual(checkpoint?.currentSet, 1,
                       "A swap resets the set counter — the checkpoint must record that, not the pre-swap value")
    }

    /// A checkpoint can outlive the plan shape it described.
    func testRestore_clampsTheSetCounterToTheExercisesActualSetCount() {
        let plan = makePlan(sets: 3)
        let vm = GuidedWorkoutViewModel(plan: plan)

        let stale = GuidedWorkoutViewModel.WorkoutCheckpoint(
            planId: plan.id.uuidString,
            currentExerciseIndex: 0,
            currentSet: 9,
            completedExercises: [],
            skippedExercises: [],
            substitutedExercises: [:],
            accumulatedTime: 0,
            savedAt: Date()
        )
        vm.restoreFromCheckpoint(stale)

        XCTAssertLessThanOrEqual(vm.currentSet, 3, "A restored set counter must not exceed the exercise's sets")
        XCTAssertGreaterThanOrEqual(vm.currentSet, 1)
    }
}
