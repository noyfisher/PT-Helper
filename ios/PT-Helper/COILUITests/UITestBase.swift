import XCTest

/// Base class for all COIL UI tests.
/// Configures the app with test mode launch arguments and provides common helpers.
class UITestBase: XCTestCase {
    var app: XCUIApplication!

    /// Override in subclasses to customize launch arguments.
    var additionalLaunchArguments: [String] { [] }

    /// Whether to skip onboarding (default: true for most tests).
    var skipOnboarding: Bool { true }

    /// Whether to seed mock data (default: true).
    var seedMockData: Bool { true }

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()

        var args = ["--uitesting"]
        if skipOnboarding { args.append("--skip-onboarding") }
        if seedMockData { args.append("--seed-mock-data") }
        args.append(contentsOf: additionalLaunchArguments)

        app.launchArguments = args

        // Workaround for a simulator/XCTest launch crash: the app's custom UIAppFonts
        // (Industry-Bold / Inter) emit an os_log fault during font registration that
        // XCTAutomationSupport's runtime-issue handler mishandles, segfaulting the app
        // on launch (EXC_BAD_ACCESS in libGSFont `AddFontsFromURLOrPath`). Disabling
        // os_activity in the launched process suppresses the fault so the app launches
        // cleanly under UI automation. Pre-existing; unrelated to app logic.
        app.launchEnvironment["OS_ACTIVITY_MODE"] = "disable"

        app.launch()
    }

    // MARK: - Helpers

    /// Wait for an element to exist within the given timeout.
    @discardableResult
    func waitForElement(_ element: XCUIElement, timeout: TimeInterval = 5) -> Bool {
        element.waitForExistence(timeout: timeout)
    }

    /// Assert an element with the given accessibility identifier exists.
    func assertExists(_ identifier: String, timeout: TimeInterval = 5, file: StaticString = #file, line: UInt = #line) {
        let element = app.descendants(matching: .any)[identifier]
        XCTAssertTrue(element.waitForExistence(timeout: timeout),
                      "Expected element '\(identifier)' to exist", file: file, line: line)
    }

    /// Assert an element does NOT exist.
    func assertNotExists(_ identifier: String, file: StaticString = #file, line: UInt = #line) {
        let element = app.descendants(matching: .any)[identifier]
        XCTAssertFalse(element.exists, "Expected element '\(identifier)' to not exist", file: file, line: line)
    }

    /// Tap a tab bar item by label text.
    /// The app's live shell uses a custom SwiftUI `FloatingTabBar` (whose items are plain
    /// accessibility buttons via `accessibilityLabel`), not a system `UITabBar`, so query
    /// `app.buttons` first and fall back to `tabBars.buttons` for any legacy system bar.
    func tapTab(_ label: String) {
        let floatingItem = app.buttons[label]
        if floatingItem.waitForExistence(timeout: 5) {
            floatingItem.tap()
        } else {
            app.tabBars.buttons[label].tap()
        }
    }

    /// Capture a screenshot with a descriptive name.
    func captureScreenshot(name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    /// Find a button by its text label.
    func button(_ label: String) -> XCUIElement {
        app.buttons[label]
    }

    /// Find a static text element.
    func staticText(_ text: String) -> XCUIElement {
        app.staticTexts[text]
    }

    // MARK: - One-time gates

    /// Clears the MHMDA health-data consent cover if it is showing. It appears the first
    /// time health data is collected, so whether a test sees it depends on the simulator's
    /// persisted state — always call this before driving an assessment rather than
    /// assuming either outcome.
    /// `timeout` is how long to wait for the cover to *appear*. It defaults high enough to
    /// cover a slow sheet animation on a loaded runner: if this returns before the sheet
    /// arrives, the sheet then covers whatever the test does next, and the failure surfaces
    /// much later as "the next screen never appeared" rather than "the gate was missed".
    @MainActor
    func dismissHealthConsentIfPresent(timeout: TimeInterval = 5) {
        let collection = app.buttons["healthConsent.collectionCheckbox"]
        guard collection.waitForExistence(timeout: timeout) else { return }
        collection.tap()
        app.buttons["healthConsent.sharingCheckbox"].tap()
        let cont = app.buttons["healthConsent.continueButton"]
        if cont.waitForExistence(timeout: 5) { cont.tap() }
        _ = collection.waitForNonExistence(timeout: 5)
    }

    /// Clears the "Before You Begin" medical disclaimer, which gates the pain wizard on
    /// first run. Same persisted-state caveat as the consent cover above.
    @MainActor
    func dismissDisclaimerIfPresent(timeout: TimeInterval = 5) {
        let cta = app.buttons["I Understand, Continue"]
        guard cta.waitForExistence(timeout: timeout) else { return }

        // On a fresh simulator this sheet is chained from the consent sheet's
        // onDismiss, so it exists while it is still animating in, and a tap
        // synthesised at that moment lands where the button was, not where it
        // ends up. Measured on an erased simulator: the first tap missed,
        // `markAccepted()` never ran, and the pain wizard never presented — the
        // same failure the nightly runner reports on every run. Wait for the
        // button to be hittable, then re-tap while the sheet is still up.
        var attempts = 0
        repeat {
            let hittable = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "isHittable == true"), object: cta)
            _ = XCTWaiter.wait(for: [hittable], timeout: 3)
            cta.tap()
            attempts += 1
        } while !cta.waitForNonExistence(timeout: 3) && attempts < 3
        XCTAssertFalse(cta.exists, "The medical disclaimer should dismiss after accepting it")
    }
}
