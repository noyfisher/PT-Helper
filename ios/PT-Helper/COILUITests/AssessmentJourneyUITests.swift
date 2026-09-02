import XCTest

/// End-to-end coverage of the app's primary value path: body region → pain wizard →
/// AI analysis → results → rehab plan generation.
///
/// This journey previously had **zero** E2E coverage, and not by oversight: `ClaudeAPIService`
/// had no `--uitesting` branch, so any test walking this far would have hit the live Cloud
/// Function and the real Claude API. `--stub-ai` (see `COIL/Testing/AIStubbing.swift`)
/// serves canned responses in-process, which makes the journey deterministic and offline.
///
/// Scenarios are selected per test *class* via `additionalLaunchArguments` rather than by
/// relaunching inside a test method. Re-launching mid-test reliably lost the connection to
/// the app on the RealityKit body-map screen, and one launch per test is what `UITestBase`
/// is built for anyway.
class AssessmentJourneyTestCase: UITestBase {

    override var seedMockData: Bool { true }

    /// Overridden per scenario subclass.
    var aiScenario: String { "default" }

    override var additionalLaunchArguments: [String] {
        ["--stub-ai", "--ai-scenario", aiScenario]
    }

    // MARK: - Navigation helpers

    /// Floating "+" → gateway → "Something Hurts" → body map.
    @MainActor
    func openBodyMap() {
        let newAssessment = app.buttons["New Assessment"]
        XCTAssertTrue(newAssessment.waitForExistence(timeout: 10), "Floating assessment button should exist")
        newAssessment.tap()

        let somethingHurts = app.descendants(matching: .any)["gateway.somethingHurtsButton"]
        XCTAssertTrue(somethingHurts.waitForExistence(timeout: 5), "Assessment gateway should present")
        somethingHurts.tap()
    }

    /// Selects a region through the accessible list rather than the RealityKit model —
    /// the 3D model's hit-testing isn't reliably drivable from XCUITest.
    @MainActor
    func selectRegionFromList(_ regionName: String) {
        // 30s, not 15: the RealityKit model load is the slowest step in the suite and
        // this exact wait was the most common failure point across repeated FullPlan
        // runs — it took ~59s in isolation on a loaded machine, so 15s was marginal
        // under full-suite contention and failed a healthy app.
        let chooseFromList = app.descendants(matching: .any)["bodyMap.chooseFromListButton"]
        XCTAssertTrue(chooseFromList.waitForExistence(timeout: 30), "Body map should offer the list fallback")
        chooseFromList.tap()

        let region = app.buttons[regionName]
        XCTAssertTrue(region.waitForExistence(timeout: 5), "\(regionName) should be listed")
        region.tap()

        // Dismiss the sheet, then confirm it actually went away before looking for the
        // button underneath — tapping Done occasionally doesn't register first time, and
        // the resulting failure otherwise looks like a body-map bug rather than a
        // still-open sheet.
        let done = app.buttons["Done"]
        var dismissAttempts = 0
        while done.exists && dismissAttempts < 3 {
            done.tap()
            _ = done.waitForNonExistence(timeout: 3)
            dismissAttempts += 1
        }
        XCTAssertFalse(done.exists, "The region list sheet should have been dismissed")

        let cont = app.descendants(matching: .any)["bodyMap3D.continueButton"]
        XCTAssertTrue(cont.waitForExistence(timeout: 20), "Continue should appear once a region is selected")

        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"), object: cont)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 10), .completed,
                       "Continue should enable once a region is selected")
        cont.tap()
    }

    /// Walks the pain wizard. Each step builds its choices through `optionCard`, which tags
    /// them `painDetail.option.<label>`, so a required step is satisfied by taking the first
    /// offered answer. Stops as soon as the Analyze button appears.
    @MainActor
    @discardableResult
    func completePainWizard(maxSteps: Int = 12) -> Bool {
        let analyze = app.descendants(matching: .any)["painDetail.analyzeButton"]
        let cont = app.descendants(matching: .any)["painDetail.continueButton"]

        XCTAssertTrue(cont.waitForExistence(timeout: 30) || analyze.waitForExistence(timeout: 3),
                      "The pain wizard should present after choosing a region")

        for step in 0..<maxSteps {
            if analyze.exists && analyze.isHittable { return true }

            if cont.exists && !cont.isEnabled {
                let options = app.descendants(matching: .any)
                    .matching(NSPredicate(format: "identifier BEGINSWITH %@", "painDetail.option."))
                guard options.element(boundBy: 0).waitForExistence(timeout: 3) else {
                    XCTFail("Step \(step + 1): Continue is disabled and no option was tappable")
                    return false
                }

                // Try options in order until Continue enables, rather than assuming index
                // 0 always satisfies the step. Some steps are multi-select ("select all
                // that apply"), where re-tapping an already-chosen option toggles it back
                // OFF and leaves Continue disabled; others gate on a particular answer.
                //
                // The wait after each tap matters on its own: SwiftUI re-evaluates
                // `canContinue` asynchronously, so reading `isEnabled` immediately can see
                // the pre-tap state and fail a perfectly healthy app. Same wait
                // `selectRegionFromList` uses above.
                let candidateCount = min(options.count, 8)
                for index in 0..<max(candidateCount, 1) {
                    let option = options.element(boundBy: index)
                    guard option.exists, option.isHittable else { continue }
                    option.tap()

                    let enabled = XCTNSPredicateExpectation(
                        predicate: NSPredicate(format: "isEnabled == true"), object: cont
                    )
                    // 10s, not 3. Measured over three full FullPlan runs, the dominant
                    // first-attempt failure was "Continue never became enabled" on the
                    // onset and relieving steps — this exact wait timing out while
                    // SwiftUI re-evaluated `canContinue` on a loaded machine. The 15s
                    // body-map waits were NOT the ones failing; this 3s one was.
                    if XCTWaiter.wait(for: [enabled], timeout: 10) == .completed { break }
                }
            }

            guard cont.exists, cont.isEnabled else {
                if analyze.exists { return true }
                XCTFail("Step \(step + 1): could not advance — Continue never became enabled")
                return false
            }
            cont.tap()
        }

        return analyze.exists
    }

    /// Full run from the tab shell to tapping Analyze.
    @MainActor
    @discardableResult
    func runAssessment(region: String = "Lower Back") -> Bool {
        openBodyMap()
        dismissHealthConsentIfPresent()
        dismissDisclaimerIfPresent()
        selectRegionFromList(region)
        dismissHealthConsentIfPresent()
        dismissDisclaimerIfPresent()

        guard completePainWizard() else { return false }

        app.descendants(matching: .any)["painDetail.analyzeButton"].tap()
        return true
    }
}

// MARK: - Happy path

final class AssessmentJourneyUITests: AssessmentJourneyTestCase {

    /// The core journey. Reaching the results screen proves the whole pipeline ran: prompt
    /// construction, the two-call analysis, response parsing, and the validation pipeline.
    @MainActor
    func testPainAssessment_producesAnalysisResult() throws {
        XCTAssertTrue(runAssessment(), "Should reach the Analyze step")

        let buildPlan = app.descendants(matching: .any)["analysisResult.buildRehabPlanButton"]
        XCTAssertTrue(buildPlan.waitForExistence(timeout: 30),
                      "Analysis should complete and offer to build a rehab plan")

        XCTAssertTrue(staticText("Runner's Knee").waitForExistence(timeout: 5),
                      "The stubbed condition should render, proving the response was parsed and displayed")

        captureScreenshot(name: "Assessment-AnalysisResult")
    }

    /// Extends the happy path through plan generation — a separate AI call (`rehab_plan`)
    /// handled by a separate ViewModel.
    @MainActor
    func testAnalysisResult_generatesRehabPlan() throws {
        XCTAssertTrue(runAssessment(), "Should reach the Analyze step")

        let buildPlan = app.descendants(matching: .any)["analysisResult.buildRehabPlanButton"]
        XCTAssertTrue(buildPlan.waitForExistence(timeout: 30))
        buildPlan.tap()

        // A preferences sheet gates generation; accept its defaults if it appears.
        let generate = app.buttons["Generate Plan"]
        if generate.waitForExistence(timeout: 5) { generate.tap() }

        XCTAssertTrue(staticText("Quad Sets").waitForExistence(timeout: 30),
                      "The generated plan should render the stubbed exercises")

        captureScreenshot(name: "Assessment-RehabPlan")
    }
}

// MARK: - Emergency routing

/// DOCUMENTS CURRENT BEHAVIOUR — this asserts what the app does today, which is *not*
/// what the scenario name might suggest.
///
/// An AI response carrying `isRedFlag: true` does **not** trigger the emergency takeover.
/// `EmergencyRedirectView` is reached only when `viewModel.redFlagAlerts` contains an
/// `.emergency` warning, and those come exclusively from
/// `MedicalRedFlagDetector.check(assessments:)` — a client-side scan of the symptoms the
/// *user* entered. The response-side path, `checkConditions`, only ever emits `.urgent`,
/// and only when `isRedFlag` is false (it exists to catch conditions the AI failed to
/// flag, not to act on ones it did).
///
/// That may well be deliberate — letting the model declare a medical emergency is a
/// meaningful thing not to do — but it means a red flag the AI identifies and the user did
/// not describe reaches the user as an ordinary result. Flagged as a product question
/// rather than changed here.
final class AssessmentEmergencyJourneyUITests: AssessmentJourneyTestCase {

    override var aiScenario: String { "emergency_red_flag" }

    @MainActor
    func testAIDeclaredRedFlag_doesNotTriggerEmergencyTakeover_currentBehaviour() throws {
        XCTAssertTrue(runAssessment(), "Should reach the Analyze step")

        XCTAssertTrue(app.descendants(matching: .any)["analysisResult.buildRehabPlanButton"]
                        .waitForExistence(timeout: 30),
                      "Today an AI-flagged response still lands on the normal results screen")

        XCTAssertFalse(app.descendants(matching: .any)["emergencyRedirect.callCta"].exists, """
            The emergency takeover now fires for an AI-declared red flag. If that change was \
            intended, invert this test; the emergency route previously depended only on \
            user-entered symptoms.
            """)

        captureScreenshot(name: "Assessment-AIRedFlagResult")
    }
}

// MARK: - Graceful degradation

/// The verification call fails, so `InjuryAnalyzer` must fall back to the primary result
/// rather than surfacing an error. Pure client logic, but only reachable end to end now
/// that the AI layer can be driven deterministically.
final class AssessmentVerifyFailureJourneyUITests: AssessmentJourneyTestCase {

    override var aiScenario: String { "verify_failure" }

    @MainActor
    func testVerificationFailure_degradesToPrimaryResult() throws {
        XCTAssertTrue(runAssessment(), "Should reach the Analyze step")

        XCTAssertTrue(app.descendants(matching: .any)["analysisResult.buildRehabPlanButton"]
                        .waitForExistence(timeout: 30),
                      "A failed verification must degrade to the primary result, not an error state")
        XCTAssertTrue(staticText("Primary Call Result").waitForExistence(timeout: 5),
                      "The displayed result should be the primary call's, since verification failed")
    }
}
