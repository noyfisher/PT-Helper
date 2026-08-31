import XCTest
@testable import COIL

// MARK: - OnboardingViewModel Tests (non-Firebase parts)

@MainActor
final class OnboardingViewModelTests: XCTestCase {

    /// Helper to fill in valid step 1 data so nextStep() can proceed
    private func fillValidBasicInfo(_ vm: OnboardingViewModel) {
        vm.userProfile.firstName = "Test"
        vm.userProfile.lastName = "User"
        vm.userProfile.sex = "Male"
        vm.userProfile.heightFeet = 5
        vm.userProfile.heightInches = 10
        vm.userProfile.weight = 175
        vm.hasAcceptedTerms = true
    }

    /// Helper to fill valid activity-level data (step 2 after the 2026 reorder)
    private func fillValidActivityLevel(_ vm: OnboardingViewModel) {
        vm.userProfile.activityLevel = "Active"
    }

    func testInitialStep() {
        let vm = OnboardingViewModel()
        XCTAssertEqual(vm.currentStep, 1)
    }

    func testNextStep_BlockedWithoutValidation() {
        let vm = OnboardingViewModel()
        XCTAssertEqual(vm.currentStep, 1)

        // Try to advance without filling in required fields
        vm.nextStep()
        XCTAssertEqual(vm.currentStep, 1, "Should not advance without valid basic info")
    }

    func testNextStep_AdvancesWithValidData() {
        let vm = OnboardingViewModel()
        fillValidBasicInfo(vm)
        fillValidActivityLevel(vm) // step 2 (activity) now requires a selection

        vm.nextStep()
        XCTAssertEqual(vm.currentStep, 2)

        vm.nextStep()
        XCTAssertEqual(vm.currentStep, 3)
    }

    func testNextStep_DoesNotExceedMax() {
        let vm = OnboardingViewModel()
        fillValidBasicInfo(vm)
        fillValidActivityLevel(vm)

        // Advance to step 6 (max)
        for _ in 1..<6 {
            vm.nextStep()
        }
        XCTAssertEqual(vm.currentStep, 6)

        // Try to go past max
        vm.nextStep()
        XCTAssertEqual(vm.currentStep, 6, "Should not exceed step 6")
    }

    func testPreviousStep_DecreasesStep() {
        let vm = OnboardingViewModel()
        fillValidBasicInfo(vm)
        fillValidActivityLevel(vm) // step 2 (activity) now requires a selection
        vm.nextStep()
        vm.nextStep()
        XCTAssertEqual(vm.currentStep, 3)

        vm.previousStep()
        XCTAssertEqual(vm.currentStep, 2)
    }

    func testPreviousStep_DoesNotGoBelowOne() {
        let vm = OnboardingViewModel()
        XCTAssertEqual(vm.currentStep, 1)

        vm.previousStep()
        XCTAssertEqual(vm.currentStep, 1, "Should not go below step 1")
    }

    func testFullStepNavigation() {
        let vm = OnboardingViewModel()
        fillValidBasicInfo(vm)
        fillValidActivityLevel(vm)

        // Walk through all steps forward
        for expectedStep in 2...6 {
            vm.nextStep()
            XCTAssertEqual(vm.currentStep, expectedStep)
        }

        // Walk back to step 1
        for expectedStep in stride(from: 5, through: 1, by: -1) {
            vm.previousStep()
            XCTAssertEqual(vm.currentStep, expectedStep)
        }
    }

    func testCanProceedFromStep1_requiresCoreFields_lastNameOptional() {
        let vm = OnboardingViewModel()
        XCTAssertFalse(vm.canProceedFromCurrentStep, "Empty profile should not pass validation")

        vm.userProfile.firstName = "Test"
        XCTAssertFalse(vm.canProceedFromCurrentStep, "Still missing sex, weight, terms")

        // Last name is intentionally NOT set — it is optional (2026 change).
        vm.userProfile.sex = "Male"
        vm.userProfile.heightFeet = 5
        vm.userProfile.weight = 175
        vm.hasAcceptedTerms = true
        XCTAssertTrue(vm.canProceedFromCurrentStep, "Core fields filled; last name is optional")
    }

    func testUserProfileModification() {
        let vm = OnboardingViewModel()

        vm.userProfile.firstName = "Jane"
        vm.userProfile.lastName = "Smith"
        vm.userProfile.sex = "Female"
        vm.userProfile.heightFeet = 5
        vm.userProfile.heightInches = 6
        vm.userProfile.weight = 135
        vm.userProfile.activityLevel = "Very Active"
        vm.userProfile.primarySport = "Running"
        vm.userProfile.medicalConditions = ["Asthma"]

        XCTAssertEqual(vm.userProfile.firstName, "Jane")
        XCTAssertEqual(vm.userProfile.lastName, "Smith")
        XCTAssertEqual(vm.userProfile.sex, "Female")
        XCTAssertEqual(vm.userProfile.heightFeet, 5)
        XCTAssertEqual(vm.userProfile.heightInches, 6)
        XCTAssertEqual(vm.userProfile.weight, 135)
        XCTAssertEqual(vm.userProfile.activityLevel, "Very Active")
        XCTAssertEqual(vm.userProfile.primarySport, "Running")
        XCTAssertEqual(vm.userProfile.medicalConditions, ["Asthma"])
    }

    func testUserProfileSurgeriesAndInjuries() {
        let vm = OnboardingViewModel()

        vm.userProfile.surgeries = [
            UserProfile.Surgery(name: "ACL Repair", year: 2020),
            UserProfile.Surgery(name: "Meniscus Repair", year: 2022)
        ]
        vm.userProfile.injuries = [
            UserProfile.Injury(bodyArea: "Right Knee", description: "ACL tear", isCurrent: false),
            UserProfile.Injury(bodyArea: "Lower Back", description: "Disc herniation", isCurrent: true)
        ]

        XCTAssertEqual(vm.userProfile.surgeries.count, 2)
        XCTAssertEqual(vm.userProfile.injuries.count, 2)

        let currentInjuries = vm.userProfile.injuries.filter { $0.isCurrent }
        XCTAssertEqual(currentInjuries.count, 1)
        XCTAssertEqual(currentInjuries.first?.bodyArea, "Lower Back")
    }

    // MARK: - Validation Edge Cases

    func testCanProceed_step1_weightBelowMinimum_returnsFalse() {
        let vm = OnboardingViewModel()
        fillValidBasicInfo(vm)
        vm.userProfile.weight = 40 // below 50 minimum
        XCTAssertFalse(vm.canProceedFromCurrentStep)
    }

    func testCanProceed_step1_weightAboveMaximum_returnsFalse() {
        let vm = OnboardingViewModel()
        fillValidBasicInfo(vm)
        vm.userProfile.weight = 600 // above 500 maximum
        XCTAssertFalse(vm.canProceedFromCurrentStep)
    }

    func testCanProceed_step1_heightTooShort_returnsFalse() {
        let vm = OnboardingViewModel()
        fillValidBasicInfo(vm)
        vm.userProfile.heightFeet = 2 // below 3 minimum
        XCTAssertFalse(vm.canProceedFromCurrentStep)
    }

    func testCanProceed_step1_missingTermsAcceptance_returnsFalse() {
        let vm = OnboardingViewModel()
        fillValidBasicInfo(vm)
        vm.hasAcceptedTerms = false
        XCTAssertFalse(vm.canProceedFromCurrentStep)
    }

    func testCanProceedStep1_UnderThirteenDOB_False() {
        let vm = OnboardingViewModel()
        fillValidBasicInfo(vm)
        // Ten years old — under the 13+ minimum.
        vm.userProfile.dateOfBirth = Calendar.current.date(byAdding: .year, value: -10, to: Date())!
        XCTAssertFalse(vm.canProceedFromCurrentStep, "Under-13 DOB must block step 1")
    }

    func testCanProceedStep1_ExactlyThirteenDOB_True() {
        let vm = OnboardingViewModel()
        fillValidBasicInfo(vm)
        // Exactly 13 years old today — the boundary is allowed.
        vm.userProfile.dateOfBirth = Calendar.current.date(byAdding: .year, value: -13, to: Date())!
        XCTAssertTrue(vm.canProceedFromCurrentStep, "Exactly-13 DOB must pass step 1")
    }

    func testCanProceed_step2_emptyActivityLevel_returnsFalse() {
        let vm = OnboardingViewModel()
        fillValidBasicInfo(vm)
        vm.nextStep() // → step 2 (activity level, moved up in the 2026 reorder)
        XCTAssertEqual(vm.currentStep, 2)

        vm.userProfile.activityLevel = ""
        XCTAssertFalse(vm.canProceedFromCurrentStep)
    }

    func testCanProceed_steps3Through5_alwaysTrue() {
        let vm = OnboardingViewModel()
        fillValidBasicInfo(vm)
        fillValidActivityLevel(vm)
        vm.nextStep() // → step 2 (activity)
        vm.nextStep() // → step 3 (medical — optional)
        XCTAssertTrue(vm.canProceedFromCurrentStep, "Step 3 (medical) should always allow proceed")
        vm.nextStep() // → step 4 (surgical — optional)
        XCTAssertTrue(vm.canProceedFromCurrentStep, "Step 4 (surgical) should always allow proceed")
        vm.nextStep() // → step 5 (injury — optional)
        XCTAssertTrue(vm.canProceedFromCurrentStep, "Step 5 (injury) should always allow proceed")
    }

    func testNextStep_failedValidation_showsValidationErrors() {
        let vm = OnboardingViewModel()
        // Don't fill required fields
        vm.nextStep()
        XCTAssertTrue(vm.showValidationErrors, "Failed validation should set showValidationErrors")
        XCTAssertEqual(vm.currentStep, 1, "Should remain on step 1")
    }

    // MARK: - Draft Persistence

    override func tearDown() {
        OnboardingViewModel.clearDraft()
        super.tearDown()
    }

    func testSaveDraft_thenLoadDraft_restoresProfile() {
        let vm = OnboardingViewModel()
        fillValidBasicInfo(vm)
        vm.hasAcceptedTerms = true
        vm.nextStep() // advances to step 2, which calls saveDraft()

        let vm2 = OnboardingViewModel()
        let loaded = vm2.loadDraft()
        XCTAssertTrue(loaded, "Should successfully load draft")
        XCTAssertEqual(vm2.userProfile.firstName, "Test")
        XCTAssertEqual(vm2.currentStep, 2)
    }

    func testLoadDraft_staleDraft_discarded() {
        let vm = OnboardingViewModel()
        fillValidBasicInfo(vm)
        vm.saveDraft()

        // Set savedAt to 8 days ago (stale)
        let staleSavedAt = Date().timeIntervalSince1970 - (8 * 24 * 60 * 60)
        UserDefaults.standard.set(staleSavedAt, forKey: "onboarding_draft_saved_at")

        let vm2 = OnboardingViewModel()
        let loaded = vm2.loadDraft()
        XCTAssertFalse(loaded, "Stale draft should be discarded")
    }

    func testLoadDraft_corruptData_returnsFalse() {
        UserDefaults.standard.set(Data([0xFF, 0xFE]), forKey: "onboarding_draft_profile")
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "onboarding_draft_saved_at")

        let vm = OnboardingViewModel()
        let loaded = vm.loadDraft()
        XCTAssertFalse(loaded, "Corrupt data should return false")
    }

    func testClearDraft_removesAllKeys() {
        let vm = OnboardingViewModel()
        fillValidBasicInfo(vm)
        vm.saveDraft()

        OnboardingViewModel.clearDraft()

        XCTAssertNil(UserDefaults.standard.data(forKey: "onboarding_draft_profile"))
        XCTAssertNil(UserDefaults.standard.object(forKey: "onboarding_draft_saved_at"))
    }

    // MARK: - Medication History

    func testUpdateMedicationHistory_newMedAdded_recordsStartedAction() {
        let vm = OnboardingViewModel()
        vm.userProfile.medications = ["Ibuprofen", "Aspirin"]

        vm.updateMedicationHistory(previousMedications: ["Ibuprofen"])

        let history = vm.userProfile.medicationHistory ?? []
        let started = history.filter { $0.action == "started" }
        XCTAssertEqual(started.count, 1)
        XCTAssertEqual(started.first?.medication, "Aspirin")
    }
}

// MARK: - Step-identity validation (C: age gate + consent)

extension OnboardingViewModelTests {

    private func makeUnderageProfile(_ vm: OnboardingViewModel) {
        fillValidBasicInfo(vm)
        fillValidActivityLevel(vm)
        // 10 years old — under the 13 minimum.
        vm.userProfile.dateOfBirth = Calendar.current.date(byAdding: .year, value: -10, to: Date())!
    }

    /// Validation must follow step IDENTITY, not index — the edit flow orders
    /// steps differently, and an index-keyed switch validated the wrong screen.
    func testCanProceed_isKeyedOnStepIdentityAcrossBothOrderings() {
        let vm = OnboardingViewModel()
        fillValidBasicInfo(vm)
        // Activity intentionally left blank, so the Activity rule is the one that
        // can distinguish "validated Activity" from "validated something else".

        // Onboarding order: Activity is position 2.
        vm.stepOrder = OnboardingViewModel.Step.onboardingOrder
        vm.currentStep = 2
        XCTAssertFalse(vm.canProceedFromCurrentStep, "Onboarding step 2 is Activity — blank must block")
        vm.currentStep = 3
        XCTAssertTrue(vm.canProceedFromCurrentStep, "Onboarding step 3 is Medical — optional, passes")

        // Edit order: Medical is position 2, Activity is position 5.
        vm.stepOrder = OnboardingViewModel.Step.editOrder
        vm.currentStep = 2
        XCTAssertTrue(vm.canProceedFromCurrentStep, "Edit step 2 is Medical — must NOT be judged by the Activity rule")
        vm.currentStep = 5
        XCTAssertFalse(vm.canProceedFromCurrentStep, "Edit step 5 is Activity — blank must block")
    }

    func testCanProceed_basicInfo_blocksUnder13() {
        let vm = OnboardingViewModel()
        fillValidBasicInfo(vm)
        vm.userProfile.dateOfBirth = Calendar.current.date(byAdding: .year, value: -10, to: Date())!
        XCTAssertFalse(vm.canProceed(from: .basicInfo), "Under-13 DOB must fail the Basic Info gate")
    }

    /// The defense-in-depth guard: even if the UI is bypassed (the page TabView
    /// was swipeable), saveProfile must refuse an invalid profile and must NOT
    /// record legal acceptance for it.
    func testIsProfileSubmittable_falseWhenAnyGatingStepFails() {
        let vm = OnboardingViewModel()

        // Under-13 with everything else valid → not submittable.
        makeUnderageProfile(vm)
        XCTAssertFalse(vm.isProfileSubmittable, "An under-13 profile must never be submittable")

        // Missing terms → not submittable.
        fillValidBasicInfo(vm)
        fillValidActivityLevel(vm)
        vm.userProfile.dateOfBirth = Calendar.current.date(byAdding: .year, value: -30, to: Date())!
        vm.hasAcceptedTerms = false
        XCTAssertFalse(vm.isProfileSubmittable, "Missing Terms acceptance must block submission")

        // Missing activity level → not submittable (order-independent).
        vm.hasAcceptedTerms = true
        vm.userProfile.activityLevel = ""
        XCTAssertFalse(vm.isProfileSubmittable, "A blank required step blocks submission regardless of position")

        // All gates satisfied → submittable.
        fillValidActivityLevel(vm)
        XCTAssertTrue(vm.isProfileSubmittable, "A complete, adult, consented profile is submittable")
    }

    func testSaveProfile_refusesUnder13_withoutRecordingAcceptance() {
        let vm = OnboardingViewModel()
        makeUnderageProfile(vm)

        let expectation = expectation(description: "saveProfile completes")
        var reportedSuccess = true
        vm.saveProfile { success in
            reportedSuccess = success
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2.0)

        XCTAssertFalse(reportedSuccess, "saveProfile must fail closed for an under-13 profile")
        XCTAssertTrue(vm.showValidationErrors, "The refusal should surface validation errors to the UI")
    }
}
