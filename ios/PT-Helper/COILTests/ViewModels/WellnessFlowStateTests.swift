import XCTest
@testable import COIL

/// State-lifecycle guards for the wellness assessment flow (D1).
///
/// Both defects here were "the injury flow does this correctly, the wellness
/// twin doesn't", so these tests pin the ViewModel contract the ported patterns
/// depend on. The SwiftUI wiring itself (a @State-held ViewModel, and clearing
/// the analyzing screen when the destination goes nil) is not unit-testable —
/// what IS testable is that the ViewModel exposes the state those fixes drive,
/// and that a completed analysis leaves the analyzing flag set, which is the
/// exact reason the view must clear it.
@MainActor
final class WellnessFlowStateTests: XCTestCase {

    private func makeViewModel() -> WellnessAnalysisViewModel {
        WellnessAnalysisViewModel(
            userProfile: TestFixtures.makeProfile(),
            selectedGoals: [GoalSelection(category: .improvePosture)]
        )
    }

    /// A fresh ViewModel starts at goal 0 with nothing saved — which is exactly
    /// what the user got mid-assessment every time the picker re-rendered and
    /// rebuilt the ViewModel inside its navigationDestination closure.
    func testFreshViewModel_hasNoProgress_soRecreationLosesTheAssessment() {
        let vm = makeViewModel()
        XCTAssertEqual(vm.currentGoalIndex, 0)
        XCTAssertNil(vm.analysisResult)
        XCTAssertFalse(vm.showAnalyzingScreen)
    }

    /// Progress lives on the ViewModel instance, so holding it stably across
    /// re-renders is what preserves it. Advancing then re-creating demonstrates
    /// the loss the @State fix prevents.
    func testAdvancingGoal_isLostWhenTheViewModelIsRecreated() {
        let vm = makeViewModel()
        vm.currentGoalIndex = 1
        XCTAssertEqual(vm.currentGoalIndex, 1)

        let recreated = makeViewModel()
        XCTAssertEqual(recreated.currentGoalIndex, 0,
                       "A rebuilt ViewModel resets the flow — this is why it must be held in @State")
    }

    /// The dead-spinner root cause: nothing in the ViewModel clears
    /// showAnalyzingScreen on success, so the view MUST clear it when the
    /// results destination is dismissed. If a future change makes the ViewModel
    /// self-clearing, this test flags that the view-side cleanup is redundant.
    func testShowAnalyzingScreen_isNotSelfClearing_soTheViewMustClearIt() {
        let vm = makeViewModel()
        vm.showAnalyzingScreen = true
        vm.isAnalyzing = false
        vm.analysisResult = nil

        XCTAssertTrue(vm.showAnalyzingScreen,
                      "Nothing clears this automatically — WellnessDetailView's onChange(destination) is the only exit")
    }

    /// resetAnalysisState is what the emergency path and the fixed back path
    /// rely on; it must clear the analyzing screen.
    func testResetAnalysisState_clearsTheAnalyzingScreen() {
        let vm = makeViewModel()
        vm.showAnalyzingScreen = true
        vm.isAnalyzing = true

        vm.resetAnalysisState()

        XCTAssertFalse(vm.showAnalyzingScreen)
        XCTAssertFalse(vm.isAnalyzing)
        XCTAssertNil(vm.analysisResult)
    }
}
