import XCTest

final class GuidedWorkoutUITests: UITestBase {

    override var additionalLaunchArguments: [String] { ["--clear-workout-checkpoint"] }

    override func setUpWithError() throws {
        try super.setUpWithError()

        // Register an interruption handler for the "Resume Workout?" alert
        // that appears when a checkpoint exists from a previous session.
        addUIInterruptionMonitor(withDescription: "Resume Workout Alert") { alert in
            let startFreshButton = alert.buttons["Start Fresh"]
            if startFreshButton.exists {
                startFreshButton.tap()
                return true
            }
            return false
        }
    }

    /// Navigate to a rehab plan and start a guided workout.
    @MainActor
    private func navigateToWorkout() {
        // The live shell labels the "My Plan" tab "Plan" in the FloatingTabBar.
        tapTab("Plan")

        // The seeded data has two rehab plans (Knee + Shoulder), so MyPlanTab opens
        // on the Injury sub-tab showing a hero card per plan — hence `.firstMatch`
        // (both cards carry the same "myPlan.startWorkoutButton" identifier). There
        // is no "My Plan" nav-bar title to wait on anymore (the title is the empty
        // COIL wordmark), so wait directly on the start-workout CTA.
        let startButton = app.descendants(matching: .any)["myPlan.startWorkoutButton"].firstMatch
        XCTAssertTrue(startButton.waitForExistence(timeout: 10),
                      "Start Guided Workout button should appear on the Plan tab")

        // The CTA is a `.plain` button inside a `List` row, which XCUI reports as
        // existing but not hittable, so a plain `.tap()` throws. A coordinate tap
        // bypasses the hittability check (the same pattern the onboarding tests use
        // for buttons nested in scrolling containers).
        startButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        // Trigger the interruption monitor by interacting with the app
        // (XCUI only fires interruption monitors on next interaction).
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    @MainActor
    func testStartWorkout_ShowsFirstExercise() throws {
        navigateToWorkout()

        // Should show exercise name and set counter
        assertExists("workout.exerciseName", timeout: 10)
        assertExists("workout.completeSetButton")

        captureScreenshot(name: "Workout-FirstExercise")
    }

    @MainActor
    func testCompleteSet_ButtonExists() throws {
        navigateToWorkout()

        let completeButton = app.descendants(matching: .any)["workout.completeSetButton"]
        XCTAssertTrue(completeButton.waitForExistence(timeout: 10))

        // Tap complete set
        completeButton.tap()

        captureScreenshot(name: "Workout-AfterCompleteSet")
    }

    @MainActor
    func testSkipExercise_AdvancesToNext() throws {
        navigateToWorkout()

        let skipButton = app.descendants(matching: .any)["workout.skipButton"]
        XCTAssertTrue(skipButton.waitForExistence(timeout: 10))
        skipButton.tap()

        // Should still show exercise phase (next exercise)
        assertExists("workout.exerciseName", timeout: 5)

        captureScreenshot(name: "Workout-AfterSkip")
    }

    @MainActor
    func testPauseResume_TogglesState() throws {
        navigateToWorkout()

        let pauseButton = app.buttons["workout.pauseButton"]
        XCTAssertTrue(pauseButton.waitForExistence(timeout: 10))

        // Tap pause
        pauseButton.tap()
        captureScreenshot(name: "Workout-Paused")

        // Tap play (same button, toggled)
        let resumeButton = app.buttons["workout.pauseButton"]
        _ = resumeButton.waitForExistence(timeout: 3)
        resumeButton.tap()
        captureScreenshot(name: "Workout-Resumed")
    }

    @MainActor
    func testEndEarly_ShowsConfirmation() throws {
        navigateToWorkout()

        let endButton = app.buttons["workout.endButton"]
        XCTAssertTrue(endButton.waitForExistence(timeout: 10))
        endButton.tap()

        // Should show confirmation dialog
        XCTAssertTrue(staticText("End Workout?").waitForExistence(timeout: 3),
                      "End workout confirmation should appear")

        // Verify both options exist. The destructive role sits on "Discard"; the
        // safe action reads "Finish & Review" — renamed from "Save & Finish"
        // because it does not save. Persisting happens on the summary screen,
        // which collects the pain level and notes the session needs, so the old
        // label promised something the button could not do and a user who
        // navigated back from the summary lost the workout.
        XCTAssertTrue(button("Finish & Review").exists, "Finish & Review button should exist")
        XCTAssertTrue(button("Discard Without Saving").exists, "Discard Without Saving button should exist")

        captureScreenshot(name: "Workout-EndConfirmation")
    }

    @MainActor
    func testDiscardWorkout_DismissesWithoutSaving() throws {
        navigateToWorkout()

        let endButton = app.buttons["workout.endButton"]
        XCTAssertTrue(endButton.waitForExistence(timeout: 10))
        endButton.tap()

        // Tap Discard
        let discardButton = button("Discard Without Saving")
        XCTAssertTrue(discardButton.waitForExistence(timeout: 3))
        discardButton.tap()

        // Discarding dismisses the pushed workout, returning to the plan list —
        // the hero card's start button reappears (it's removed from the tree while
        // the workout is pushed on top).
        XCTAssertTrue(
            app.descendants(matching: .any)["myPlan.startWorkoutButton"].firstMatch.waitForExistence(timeout: 5),
            "Should return to the Plan tab after discarding"
        )

        captureScreenshot(name: "Workout-DiscardedBackToPlan")
    }

    @MainActor
    func testSwapExercise_OpensSwapSheet() throws {
        navigateToWorkout()

        let swapButton = app.descendants(matching: .any)["workout.swapButton"]
        XCTAssertTrue(swapButton.waitForExistence(timeout: 10))
        swapButton.tap()

        // Should show swap sheet with reason chips
        XCTAssertTrue(
            staticText("Why swap?").waitForExistence(timeout: 3) ||
            staticText("Swap Exercise").waitForExistence(timeout: 3),
            "Swap sheet should appear"
        )

        captureScreenshot(name: "Workout-SwapSheet")
    }
}
