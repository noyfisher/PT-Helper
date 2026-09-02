import XCTest

// MARK: - Onboarding UI Tests

final class OnboardingUITests: UITestBase {

    override var skipOnboarding: Bool { false }
    override var seedMockData: Bool { false }
    override var additionalLaunchArguments: [String] { ["--prefill-weight"] }

    // `dismissHealthConsentIfPresent` now lives on `UITestBase` — the assessment journey
    // hits the same MHMDA cover, so both suites share one implementation.

    /// Wait until the step indicator reads "N/6" (the header shows a compact
    /// "\(currentStep)/6", not "Step N of 6").
    @MainActor
    @discardableResult
    private func waitForStep(_ step: Int, timeout: TimeInterval = 5) -> Bool {
        let indicator = app.descendants(matching: .any)["onboarding.stepIndicator"]
        let predicate = NSPredicate(format: "label == %@", "\(step)/6")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: indicator)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    /// Dismiss the software keyboard. BasicInfoStepView resigns the first responder
    /// on a tap of its ScrollView content, so tap the non-editable "Full Name" label
    /// (matched case-insensitively — it renders uppercased). Tapping the header step
    /// indicator does NOT resign, which would leave the keyboard covering the Sex
    /// chips, Terms checkbox, and the bottom Continue button.
    @MainActor
    private func dismissKeyboard() {
        guard app.keyboards.firstMatch.exists else { return }
        let nameLabel = app.staticTexts
            .matching(NSPredicate(format: "label ==[c] %@", "Full Name")).firstMatch
        if nameLabel.exists { nameLabel.tap() }
        // Fallback: BasicInfoStepView also uses .scrollDismissesKeyboard(.interactively).
        var attempts = 0
        while app.keyboards.firstMatch.exists && attempts < 3 {
            app.swipeDown()
            attempts += 1
        }
    }

    /// Swipe up until `element` is hittable (used to reveal fields lower in the
    /// onboarding form). Returns whether it ended up hittable.
    @MainActor
    @discardableResult
    private func scrollUpToHittable(_ element: XCUIElement, maxSwipes: Int = 6) -> Bool {
        var swipes = 0
        while !(element.exists && element.isHittable) && swipes < maxSwipes {
            app.swipeUp()
            swipes += 1
        }
        return element.exists && element.isHittable
    }

    /// Fill all required Step 1 fields so the Continue button becomes enabled.
    @MainActor
    private func fillStep1RequiredFields() {
        // First Name — tap and type
        let firstNameField = app.textFields["First Name"]
        if firstNameField.waitForExistence(timeout: 3) {
            firstNameField.tap()
            _ = app.keyboards.firstMatch.waitForExistence(timeout: 3)
            firstNameField.typeText("Test")
        }

        // Last Name (now optional) — tap directly (keyboard already up from first field)
        let lastNameField = app.textFields["Last Name (optional)"]
        if lastNameField.waitForExistence(timeout: 3) {
            lastNameField.tap()
            lastNameField.typeText("User")
        }

        // Dismiss the keyboard so the fields below it become reachable.
        dismissKeyboard()

        // Sex — tap the "Male" chip (scroll into view if needed).
        let maleButton = button("Male")
        if scrollUpToHittable(maleButton) {
            maleButton.tap()
        }

        // Height uses default 5ft 7in which passes validation.
        // Weight is pre-filled to 170 via --prefill-weight launch argument.

        // Accept Terms of Service checkbox (required for Continue) — it sits near the
        // bottom of the form, so scroll it into view first.
        let termsCheckbox = app.descendants(matching: .any)["onboarding.termsCheckbox"]
        if scrollUpToHittable(termsCheckbox) {
            termsCheckbox.tap()
        }
    }

    @MainActor
    func testFullFlow_CompletesAllSixSteps() throws {
        dismissHealthConsentIfPresent()

        // Step 1: Basic Info
        assertExists("onboarding.stepIndicator")
        XCTAssertTrue(waitForStep(1), "Should start on step 1")

        // Fill all required fields (this also dismisses the keyboard).
        fillStep1RequiredFields()

        // Continue lives in the fixed bottom nav bar — visible once the keyboard is
        // dismissed.
        let continueButton = app.descendants(matching: .any)["onboarding.continueButton"]
        XCTAssertTrue(continueButton.waitForExistence(timeout: 5))

        // Wait for button to become enabled after field validation
        let enabledPredicate = NSPredicate(format: "isEnabled == true")
        let expectation = XCTNSPredicateExpectation(predicate: enabledPredicate, object: continueButton)
        let result = XCTWaiter.wait(for: [expectation], timeout: 5)
        XCTAssertTrue(result == .completed, "Continue button should become enabled after filling required fields")

        continueButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        // Step 2: Activity Level (moved up in the 2026 reorder) — select a level
        // so Continue enables (this step is now required).
        XCTAssertTrue(waitForStep(2), "Should advance to step 2 (Activity Level)")
        let moderateButton = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Moderately'")).firstMatch
        if moderateButton.waitForExistence(timeout: 3) {
            moderateButton.tap()
        }
        if continueButton.exists, continueButton.isEnabled {
            continueButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }

        // Step 3: Medical History (optional step)
        XCTAssertTrue(waitForStep(3), "Should advance to step 3 (Medical History)")
        if continueButton.exists, continueButton.isEnabled {
            continueButton.tap()
        }

        // Step 4: Surgical History (optional step)
        XCTAssertTrue(waitForStep(4), "Should advance to step 4 (Surgical History)")
        if continueButton.exists, continueButton.isEnabled {
            continueButton.tap()
        }

        // Step 5: Injuries (optional step)
        XCTAssertTrue(waitForStep(5), "Should advance to step 5 (Injuries)")
        if continueButton.exists, continueButton.isEnabled {
            continueButton.tap()
        }

        // Step 6: Review & Submit
        XCTAssertTrue(waitForStep(6), "Should advance to step 6 (Review)")

        captureScreenshot(name: "Onboarding-Step6-Review")
    }

    @MainActor
    func testSkipButton_GoesToMainView() throws {
        dismissHealthConsentIfPresent()

        let skipButton = app.descendants(matching: .any)["onboarding.skipButton"]
        XCTAssertTrue(skipButton.waitForExistence(timeout: 3))
        skipButton.tap()

        // The live shell has no system tab bar — assert the custom FloatingTabBar's
        // Home tab (a plain accessibility button) appears after skipping.
        XCTAssertTrue(
            app.buttons["Home"].waitForExistence(timeout: 10) ||
            app.buttons["New Assessment"].waitForExistence(timeout: 3),
            "The main shell's floating tab bar should appear after skipping onboarding"
        )
    }

    @MainActor
    func testBackButton_NavigatesToPreviousStep() throws {
        dismissHealthConsentIfPresent()

        // Fill step 1 required fields and advance (fill dismisses the keyboard).
        fillStep1RequiredFields()

        let continueButton = app.descendants(matching: .any)["onboarding.continueButton"]
        XCTAssertTrue(continueButton.waitForExistence(timeout: 5))

        // Wait for button to become enabled after field validation
        let enabledPredicate = NSPredicate(format: "isEnabled == true")
        let expectation = XCTNSPredicateExpectation(predicate: enabledPredicate, object: continueButton)
        _ = XCTWaiter.wait(for: [expectation], timeout: 5)

        if continueButton.isEnabled {
            // Step 1 → 2 (Activity Level, moved up in the 2026 reorder)
            continueButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            _ = waitForStep(2)
            // Select an activity level so Continue enables, then Step 2 → 3
            let moderateButton = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Moderately'")).firstMatch
            if moderateButton.waitForExistence(timeout: 3) { moderateButton.tap() }
            if continueButton.isEnabled { continueButton.tap() }
            _ = waitForStep(3)
        }

        // Go back twice
        let backButton = app.descendants(matching: .any)["onboarding.backButton"]
        XCTAssertTrue(backButton.waitForExistence(timeout: 3))
        backButton.tap()
        XCTAssertTrue(waitForStep(2), "Back should return to step 2")
        backButton.tap()
        XCTAssertTrue(waitForStep(1), "Back should return to step 1")
    }

    @MainActor
    func testContinueDisabled_WhenRequiredFieldsMissing() throws {
        dismissHealthConsentIfPresent()

        // On step 1 with no fields filled, Continue should be disabled
        let continueButton = app.descendants(matching: .any)["onboarding.continueButton"]
        XCTAssertTrue(continueButton.waitForExistence(timeout: 3))
        XCTAssertFalse(continueButton.isEnabled, "Continue should be disabled before required fields are filled")
    }
}
