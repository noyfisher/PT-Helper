import SwiftUI
import Foundation
import FirebaseFirestore
import FirebaseAuth

@MainActor
class OnboardingViewModel: ObservableObject {

    /// Step identity, independent of position. Validation is keyed on THIS, not on
    /// the step index: onboarding presents Basic→Activity→Medical→Surgical→Injury→
    /// Review while the edit flow presents Basic→Medical→Surgical→Injury→Activity→
    /// Review, and an index-keyed switch validated edit-step 2 (Medical) against
    /// the Activity rule while never validating Activity at all.
    enum Step: CaseIterable {
        case basicInfo
        case activityLevel
        case medicalHistory
        case surgicalHistory
        case injuryHistory
        case review

        /// Order used by OnboardingView.
        static let onboardingOrder: [Step] = [.basicInfo, .activityLevel, .medicalHistory, .surgicalHistory, .injuryHistory, .review]
        /// Order used by OnboardingEditView (Update Health Info).
        static let editOrder: [Step] = [.basicInfo, .medicalHistory, .surgicalHistory, .injuryHistory, .activityLevel, .review]
    }

    /// The presentation order of steps for the hosting flow. Views that lay out
    /// their TabView in a different order MUST set this to match, or validation
    /// applies the wrong rule to the wrong screen.
    var stepOrder: [Step] = Step.onboardingOrder

    @Published var currentStep: Int = 1
    @Published var hasAcceptedTerms: Bool = false
    @Published var userProfile = UserProfile(userId: Auth.auth().currentUser?.uid ?? "",
                                             firstName: "",
                                             lastName: "",
                                             dateOfBirth: Calendar.current.date(byAdding: .year, value: -30, to: Date()) ?? Date(),
                                             sex: "",
                                             heightFeet: 5,
                                             heightInches: 7,
                                             weight: TestDataSeeder.shouldPrefillWeight ? 170.0 : 0.0,
                                             medicalConditions: [],
                                             otherMedicalConditions: nil,
                                             surgeries: [],
                                             injuries: [],
                                             activityLevel: "",
                                             primarySport: nil)

    private let db = Firestore.firestore()

    func saveProfile(completion: @escaping (Bool) -> Void) {
        // Defense-in-depth: the step UIs gate Continue, but nothing here may rely
        // on the UI having done so (the page TabView was swipeable past every
        // check, including the 13+ age gate). An invalid profile must not reach
        // Firestore, and recordLegalAcceptance below must never fire for a
        // profile whose terms/age requirements aren't actually met.
        guard isProfileSubmittable else {
            AppLogger.auth.error("saveProfile refused: profile fails required-step validation")
            showValidationErrors = true
            completion(false)
            return
        }
        guard let uid = Auth.auth().currentUser?.uid else {
            AppLogger.auth.error("Error saving profile: no authenticated user")
            completion(false)
            return
        }
        userProfile.userId = uid

        // Build dictionary manually to avoid Codable encoding issues
        var profileData: [String: Any] = [
            "userId": uid,
            "firstName": userProfile.firstName,
            "lastName": userProfile.lastName,
            "dateOfBirth": Timestamp(date: userProfile.dateOfBirth),
            "sex": userProfile.sex,
            "heightFeet": userProfile.heightFeet,
            "heightInches": userProfile.heightInches,
            "weight": userProfile.weight,
            "medicalConditions": userProfile.medicalConditions,
            "surgeries": userProfile.surgeries.map { surgery -> [String: Any] in
                var dict: [String: Any] = [
                    "id": surgery.id.uuidString,
                    "name": surgery.name,
                    "year": surgery.year
                ]
                if let bodyArea = surgery.bodyArea { dict["bodyArea"] = bodyArea }
                if let status = surgery.recoveryStatus { dict["recoveryStatus"] = status }
                if let restrictions = surgery.restrictions { dict["restrictions"] = restrictions }
                if let surgeryType = surgery.surgeryType { dict["surgeryType"] = surgeryType }
                if let causingInjury = surgery.causingInjury { dict["causingInjury"] = causingInjury }
                if let hasHardware = surgery.hasHardware { dict["hasHardware"] = hasHardware }
                if let hardwareDetails = surgery.hardwareDetails { dict["hardwareDetails"] = hardwareDetails }
                return dict
            },
            "injuries": userProfile.injuries.map { injury -> [String: Any] in
                var dict: [String: Any] = [
                    "id": injury.id.uuidString,
                    "bodyArea": injury.bodyArea,
                    "description": injury.description,
                    "isCurrent": injury.isCurrent
                ]
                if let year = injury.year { dict["year"] = year }
                if let saw = injury.sawDoctor { dict["sawDoctor"] = saw }
                if let pt = injury.hadPhysicalTherapy { dict["hadPhysicalTherapy"] = pt }
                if let status = injury.recoveryStatus { dict["recoveryStatus"] = status }
                return dict
            },
            "activityLevel": userProfile.activityLevel
        ]
        if let other = userProfile.otherMedicalConditions {
            profileData["otherMedicalConditions"] = other
        }
        if let sport = userProfile.primarySport {
            profileData["primarySport"] = sport
        }
        if let meds = userProfile.medications, !meds.isEmpty {
            profileData["medications"] = meds
        }
        if let side = userProfile.dominantSide {
            profileData["dominantSide"] = side
        }

        // Medication history: merge existing history with any new changes
        let isoFormatter = ISO8601DateFormatter()
        if let history = userProfile.medicationHistory, !history.isEmpty {
            profileData["medicationHistory"] = history.map { change -> [String: Any] in
                [
                    "medication": change.medication,
                    "action": change.action,
                    "date": isoFormatter.string(from: change.date)
                ]
            }
        }

        db.collection("users").document(uid).collection("profile").document("health")
            .setData(profileData) { error in
                DispatchQueue.main.async {
                    if let error = error {
                        AppLogger.data.error("Error saving profile: \(error.localizedDescription)")
                        completion(false)
                    } else {
                        AnalyticsService.shared.log(.onboardingCompleted)
                        Task { @MainActor in
                            ConsentService.shared.recordLegalAcceptance(source: "onboarding", dateOfBirth: self.userProfile.dateOfBirth)
                        }
                        OnboardingViewModel.clearDraft()
                        completion(true)
                    }
                }
            }
    }

    func loadProfile(completion: @escaping (Bool) -> Void) {
        guard let uid = Auth.auth().currentUser?.uid else {
            completion(false)
            return
        }
        db.collection("users").document(uid).collection("profile").document("health").getDocument { snapshot, error in
            DispatchQueue.main.async {
                if let error = error {
                    AppLogger.data.error("Error loading profile: \(error.localizedDescription)")
                    completion(false)
                } else if let snapshot = snapshot, snapshot.exists, let data = snapshot.data() {
                    // Parse manually to match our manual save format
                    var profile = UserProfile(
                        userId: data["userId"] as? String ?? uid,
                        firstName: data["firstName"] as? String ?? "",
                        lastName: data["lastName"] as? String ?? "",
                        dateOfBirth: UserProfile.parseDateOfBirth(data["dateOfBirth"], context: "OnboardingViewModel.loadProfile"),
                        sex: data["sex"] as? String ?? "",
                        heightFeet: data["heightFeet"] as? Int ?? 0,
                        heightInches: data["heightInches"] as? Int ?? 0,
                        weight: data["weight"] as? Double ?? 0.0,
                        medicalConditions: data["medicalConditions"] as? [String] ?? [],
                        otherMedicalConditions: data["otherMedicalConditions"] as? String,
                        surgeries: [],
                        injuries: [],
                        activityLevel: data["activityLevel"] as? String ?? "",
                        primarySport: data["primarySport"] as? String
                    )

                    profile.medications = data["medications"] as? [String]
                    profile.dominantSide = data["dominantSide"] as? String

                    // Parse medication history
                    if let historyData = data["medicationHistory"] as? [[String: Any]] {
                        let isoFormatter = ISO8601DateFormatter()
                        profile.medicationHistory = historyData.compactMap { entry in
                            guard let medication = entry["medication"] as? String,
                                  let action = entry["action"] as? String else { return nil }
                            let date: Date
                            if let dateString = entry["date"] as? String,
                               let parsed = isoFormatter.date(from: dateString) {
                                date = parsed
                            } else if let timestamp = entry["date"] as? Timestamp {
                                date = timestamp.dateValue()
                            } else {
                                date = Date()
                            }
                            return UserProfile.MedicationChange(medication: medication, action: action, date: date)
                        }
                    }

                    // Parse surgeries
                    if let surgeriesData = data["surgeries"] as? [[String: Any]] {
                        profile.surgeries = surgeriesData.map { s in
                            UserProfile.Surgery(
                                id: UUID(uuidString: s["id"] as? String ?? "") ?? UUID(),
                                name: s["name"] as? String ?? "",
                                year: s["year"] as? Int ?? 2024,
                                bodyArea: s["bodyArea"] as? String,
                                recoveryStatus: s["recoveryStatus"] as? String,
                                restrictions: s["restrictions"] as? String,
                                surgeryType: s["surgeryType"] as? String,
                                causingInjury: s["causingInjury"] as? String,
                                hasHardware: s["hasHardware"] as? Bool,
                                hardwareDetails: s["hardwareDetails"] as? String
                            )
                        }
                    }

                    // Parse injuries
                    if let injuriesData = data["injuries"] as? [[String: Any]] {
                        profile.injuries = injuriesData.map { i in
                            UserProfile.Injury(
                                id: UUID(uuidString: i["id"] as? String ?? "") ?? UUID(),
                                bodyArea: i["bodyArea"] as? String ?? "",
                                description: i["description"] as? String ?? "",
                                isCurrent: i["isCurrent"] as? Bool ?? false,
                                year: i["year"] as? Int,
                                sawDoctor: i["sawDoctor"] as? Bool,
                                hadPhysicalTherapy: i["hadPhysicalTherapy"] as? Bool,
                                recoveryStatus: i["recoveryStatus"] as? String
                            )
                        }
                    }

                    self.userProfile = profile
                    // An existing profile can only have been written through
                    // saveProfile, which records legal acceptance — so seed the
                    // flag. Without this, step-identity validation correctly
                    // requires terms on Basic Info and the edit flow's Continue
                    // is dead until the user re-accepts terms they already
                    // accepted (re-acceptance after a legal-version bump is
                    // RootView's legal gate, not this flow).
                    self.hasAcceptedTerms = true
                    completion(true)
                } else {
                    completion(false)
                }
            }
        }
    }

    /// Whether the current step has all required fields filled in.
    ///
    /// Step order (2026 reorder): 1 Basic · 2 Activity · 3 Medical · 4 Surgical
    /// · 5 Injury · 6 Review. Activity moved up to step 2 so a single, momentum-
    /// building tap comes before the heavier optional medical/surgical/injury steps.
    /// The step identity at a 1-based position in the current flow's order.
    func step(at position: Int) -> Step {
        let index = position - 1
        guard stepOrder.indices.contains(index) else { return .review }
        return stepOrder[index]
    }

    func canProceed(from step: Step) -> Bool {
        switch step {
        case .basicInfo:
            // Basic info: need first name, sex, reasonable height/weight, terms.
            // Last name is optional — nothing user-facing ever shows a surname.
            let hasName = !userProfile.firstName.trimmingCharacters(in: .whitespaces).isEmpty
            let hasSex = !userProfile.sex.isEmpty
            let hasHeight = userProfile.heightFeet >= 3 && userProfile.heightFeet <= 7
            let hasWeight = userProfile.weight >= 50 && userProfile.weight <= 500
            let isOldEnough = !AgePolicy.isBlocked(dateOfBirth: userProfile.dateOfBirth)
            return hasName && hasSex && hasHeight && hasWeight && hasAcceptedTerms && isOldEnough
        case .activityLevel:
            // Activity level must be selected
            return !userProfile.activityLevel.isEmpty
        case .medicalHistory, .surgicalHistory, .injuryHistory, .review:
            // History steps are optional; review is the submit step
            return true
        }
    }

    var canProceedFromCurrentStep: Bool {
        canProceed(from: step(at: currentStep))
    }

    /// Every gating step's rule holds, regardless of which flow or screen the
    /// data came from. `saveProfile` checks this as defense-in-depth: the
    /// page-style TabViews are swipeable unless explicitly disabled, and a
    /// regression there (or any future entry point) must not be able to submit
    /// an invalid profile or record legal acceptance the user never gave.
    var isProfileSubmittable: Bool {
        Step.allCases.allSatisfy { canProceed(from: $0) }
    }

    /// Set to true when the user attempts to proceed but validation fails.
    /// Views observe this to show inline error messages.
    @Published var showValidationErrors = false

    func nextStep() {
        if currentStep < 6 && canProceedFromCurrentStep {
            showValidationErrors = false
            currentStep += 1
            saveDraft()
            AnalyticsService.shared.log(.onboardingStepCompleted, parameters: ["step_number": currentStep - 1])
        } else {
            showValidationErrors = true
        }
    }

    func previousStep() {
        if currentStep > 1 {
            currentStep -= 1
            saveDraft()
        }
    }

    // MARK: - Draft Persistence

    private enum DraftKeys {
        static let profile = "onboarding_draft_profile"
        static let step = "onboarding_draft_step"
        static let acceptedTerms = "onboarding_draft_accepted_terms"
        static let savedAt = "onboarding_draft_saved_at"
    }

    /// Maximum draft age before it's considered stale and discarded (7 days).
    private static let maxDraftAgeSeconds: TimeInterval = 7 * 24 * 60 * 60

    /// File-protected location for the PHI-bearing draft profile blob. The draft
    /// holds medical conditions, surgeries, and injuries, so it is stored as a
    /// file with `.completeFileProtection` (encrypted at rest while the device is
    /// locked, excluded from unencrypted backups) rather than in UserDefaults.
    /// The non-PHI scalars (step / accepted-terms / savedAt) remain in UserDefaults.
    private static var draftProfileFileURL: URL {
        let dir = (try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true)) ?? FileManager.default.temporaryDirectory
        return dir.appendingPathComponent("onboarding_draft_profile.json")
    }

    private static func writeDraftProfile(_ data: Data) {
        let url = draftProfileFileURL
        try? data.write(to: url, options: [.atomic, .completeFileProtection])
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableURL = url
        try? mutableURL.setResourceValues(values)
    }

    /// Reads the draft profile blob, migrating once from the legacy UserDefaults key.
    private static func readDraftProfile() -> Data? {
        if let data = try? Data(contentsOf: draftProfileFileURL) {
            return data
        }
        if let legacy = UserDefaults.standard.data(forKey: DraftKeys.profile) {
            writeDraftProfile(legacy)
            UserDefaults.standard.removeObject(forKey: DraftKeys.profile)
            return legacy
        }
        return nil
    }

    /// Saves the current onboarding state for crash/interruption recovery.
    func saveDraft() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(userProfile) {
            Self.writeDraftProfile(data)
        }
        UserDefaults.standard.set(currentStep, forKey: DraftKeys.step)
        UserDefaults.standard.set(hasAcceptedTerms, forKey: DraftKeys.acceptedTerms)
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: DraftKeys.savedAt)
    }

    /// Loads a previously saved draft. Returns true if a valid draft was restored.
    func loadDraft() -> Bool {
        // Don't load drafts during UI testing (DEBUG-only flag).
        #if DEBUG
        guard !ProcessInfo.processInfo.arguments.contains("--uitesting") else { return false }
        #endif

        // Check draft age — discard if stale
        let savedAt = UserDefaults.standard.double(forKey: DraftKeys.savedAt)
        if savedAt > 0 {
            let age = Date().timeIntervalSince1970 - savedAt
            if age > Self.maxDraftAgeSeconds {
                Self.clearDraft()
                return false
            }
        }

        guard let data = Self.readDraftProfile() else {
            return false
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let draft = try? decoder.decode(UserProfile.self, from: data) else {
            Self.clearDraft()
            return false
        }
        userProfile = draft
        currentStep = max(1, min(6, UserDefaults.standard.integer(forKey: DraftKeys.step)))
        hasAcceptedTerms = UserDefaults.standard.bool(forKey: DraftKeys.acceptedTerms)
        return true
    }

    /// Removes any saved draft (file-protected profile blob + UserDefaults scalars).
    static func clearDraft() {
        try? FileManager.default.removeItem(at: draftProfileFileURL)
        UserDefaults.standard.removeObject(forKey: DraftKeys.profile) // clear any legacy remnant
        UserDefaults.standard.removeObject(forKey: DraftKeys.step)
        UserDefaults.standard.removeObject(forKey: DraftKeys.acceptedTerms)
        UserDefaults.standard.removeObject(forKey: DraftKeys.savedAt)
    }

    // MARK: - Medication Diff Tracking

    /// Computes medication changes between previous and current medications,
    /// appends them to the existing medication history.
    func updateMedicationHistory(previousMedications: [String]?) {
        let oldMeds = Set(previousMedications ?? [])
        let newMeds = Set(userProfile.medications ?? [])

        let now = Date()
        var changes: [UserProfile.MedicationChange] = userProfile.medicationHistory ?? []

        // Newly added medications
        for med in newMeds.subtracting(oldMeds) {
            changes.append(UserProfile.MedicationChange(medication: med, action: "started", date: now))
        }

        // Removed medications
        for med in oldMeds.subtracting(newMeds) {
            changes.append(UserProfile.MedicationChange(medication: med, action: "stopped", date: now))
        }

        userProfile.medicationHistory = changes
    }
}
