import SwiftUI

import Foundation
import FirebaseFirestore
import FirebaseAuth

@MainActor
class SavedPlansViewModel: ObservableObject {
    /// Cap on plans fetched by the real-time listener. Prevents unbounded reads
    /// (and unbounded snapshot payloads on every write) if a user accumulates
    /// many plans. Newest-first ordering means older plans fall off the window
    /// once the cap is hit; add pagination here if users ever actually hit it.
    private static let rehabPlansFetchLimit = 50

    @Published var rehabPlans: [RehabPlan] = []
    @Published var isLoading: Bool = false
    @Published var loadError: String?

    private let db = Firestore.firestore()
    /// `nonisolated(unsafe)` so deinit (which is nonisolated) can remove the listener.
    nonisolated(unsafe) private var listenerRegistration: ListenerRegistration?

    /// PR 3: tracks plan IDs that have been repaired this app session, so the
    /// snapshot listener doesn't re-trigger repair on its own write-back.
    /// Cleared on cold start (initial value `[]`).
    private var repairedThisSession: Set<UUID> = []
    /// Hard cap to bound Firestore quota for users with many saved plans.
    /// Once we hit the cap, remaining plans wait for the next cold start.
    private static let maxRepairsPerSession = 5

    init() {
        if TestDataSeeder.isUITesting && TestDataSeeder.shouldSeedMockData {
            self.rehabPlans = TestDataSeeder.makeMockPlans()
            self.isLoading = false
        } else {
            startListening()
        }
    }

    deinit {
        listenerRegistration?.remove()
        listenerRegistration = nil
    }

    /// One-time migration: move any docs from the legacy `wellnessPlans` collection
    /// into `rehabPlans` so they appear in the My Plan tab.
    private func migrateWellnessPlansIfNeeded(uid: String) {
        let key = "wellnessPlansMigrated_\(uid)"
        guard !UserDefaults.standard.bool(forKey: key) else { return }

        Task {
            do {
                let snapshot = try await db.collection("users").document(uid)
                    .collection("wellnessPlans").getDocuments()

                guard !snapshot.documents.isEmpty else {
                    UserDefaults.standard.set(true, forKey: key)
                    return
                }

                AppLogger.data.info("Migrating \(snapshot.documents.count) wellness plan(s) to rehabPlans")

                for doc in snapshot.documents {
                    let data = doc.data()
                    try await db.collection("users").document(uid)
                        .collection("rehabPlans").document(doc.documentID)
                        .setData(data)
                    try await doc.reference.delete()
                }

                UserDefaults.standard.set(true, forKey: key)
                SessionLogger.shared.log(.firestoreWrite, category: .data,
                                          message: "Migrated \(snapshot.documents.count) wellness plan(s) to rehabPlans")
            } catch {
                AppLogger.data.error("Wellness plan migration failed: \(error.localizedDescription)")
                SessionLogger.shared.logError(error, context: "WellnessPlanMigration")
            }
        }
    }

    /// Start real-time Firestore listener for rehab plans.
    /// Idempotent — if a listener is already active, this is a no-op.
    func startListening() {
        // UI tests must never reach the real Firestore. `--uitesting` bypasses auth in
        // RootView but does not sign the user out, so a persisted session would stream
        // live plans in here — making both the seeded fixtures and the empty state
        // unreachable, and letting the repair pass write back to real data. Seeded
        // plans are injected in `init`; without `--seed-mock-data` the tab stays empty.
        guard !TestDataSeeder.isUITesting else { return }
        guard listenerRegistration == nil else { return }
        guard let uid = Auth.auth().currentUser?.uid else { return }
        isLoading = true

        migrateWellnessPlansIfNeeded(uid: uid)

        listenerRegistration = db.collection("users").document(uid).collection("rehabPlans")
            .order(by: "createdDate", descending: true)
            .limit(to: Self.rehabPlansFetchLimit)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    self.isLoading = false
                    if let error = error {
                        AppLogger.data.error("Error listening to rehab plans: \(error.localizedDescription)")
                        SessionLogger.shared.logError(error, context: "RehabPlansListener")
                        self.loadError = "Unable to load your rehab plans. Please pull down to retry."
                        return
                    }
                    self.loadError = nil
                    SessionLogger.shared.log(.firestoreRead, category: .data, message: "Rehab plans updated",
                                              metadata: ["count": "\(snapshot?.documents.count ?? 0)"])
                    let parsed = self.parsePlans(from: snapshot)
                    self.rehabPlans = parsed
                    // PR 3: repair-on-load. Walk plans needing repair, rewrite
                    // pre-substitution names to canonical catalog entries, and
                    // batch-persist. Subsequent listener fires see schemaVersion=2
                    // and skip; the in-session set guards against listener loops.
                    await self.runRepairPass(on: parsed)
                    await NotificationService.shared.syncPlanReminders(plans: parsed)
                }
            }
    }

    /// Stop the real-time listener (called on deinit).
    func stopListening() {
        listenerRegistration?.remove()
        listenerRegistration = nil
    }

    /// Restart the listener (useful for pull-to-refresh or auth changes).
    func fetchRehabPlans() {
        stopListening()
        startListening()
    }

    // MARK: - Parsing

    private func parsePlans(from snapshot: QuerySnapshot?) -> [RehabPlan] {
        snapshot?.documents.compactMap { Self.parsePlan(from: $0.data()) } ?? []
    }

    /// Decode a single `rehabPlans` document. Split out of `parsePlans` so the
    /// document round trip (`planDocumentData` -> `parsePlan`) is unit-testable
    /// without constructing a Firestore `QuerySnapshot`.
    static func parsePlan(from data: [String: Any]) -> RehabPlan? {
            guard let idString = data["id"] as? String,
                  let id = UUID(uuidString: idString),
                  let planName = data["planName"] as? String else {
                return nil
            }

            let exercises: [RehabExercise] = (data["exercises"] as? [[String: Any]] ?? []).compactMap { e in
                guard let eidStr = e["id"] as? String,
                      let eid = UUID(uuidString: eidStr),
                      let name = e["name"] as? String else { return nil }
                let diffStr = e["difficulty"] as? String ?? "beginner"
                let difficulty: RehabExercise.Difficulty
                switch diffStr {
                case "intermediate": difficulty = .intermediate
                case "advanced": difficulty = .advanced
                default: difficulty = .beginner
                }
                return RehabExercise(
                    id: eid,
                    name: name,
                    targetArea: e["targetArea"] as? String ?? "",
                    description: e["description"] as? String ?? "",
                    sets: e["sets"] as? Int ?? 3,
                    reps: e["reps"] as? String ?? "10",
                    restSeconds: e["restSeconds"] as? Int ?? 30,
                    difficulty: difficulty,
                    demonstrationIcon: e["demonstrationIcon"] as? String ?? "figure.flexibility",
                    tips: e["tips"] as? [String] ?? [],
                    contraindications: e["contraindications"] as? [String] ?? [],
                    startPosition: e["startPosition"] as? String,
                    movement: e["movement"] as? String,
                    endPosition: e["endPosition"] as? String,
                    exerciseCategory: e["exerciseCategory"] as? String,
                    imageFileName: e["imageFileName"] as? String,
                    catalogSubstitution: e["catalogSubstitution"] as? Bool,
                    notes: e["notes"] as? String,
                    originalAIName: e["originalAIName"] as? String
                )
            }

            // Decode weeklySchedule: supports both dictionary format (new) and nested array format (legacy)
            let weeklySchedule: [[String]]
            if let scheduleDict = data["weeklySchedule"] as? [String: [String]] {
                // New format: dictionary keyed by day index
                var schedule: [[String]] = Array(repeating: [], count: 7)
                for (key, exercises) in scheduleDict {
                    if let dayIndex = Int(key), dayIndex >= 0, dayIndex < 7 {
                        schedule[dayIndex] = exercises
                    }
                }
                weeklySchedule = schedule
            } else if let scheduleArray = data["weeklySchedule"] as? [[String]] {
                // Legacy format: nested array
                weeklySchedule = scheduleArray
            } else {
                weeklySchedule = []
            }

            var plan = RehabPlan(
                id: id,
                planName: planName,
                conditions: data["conditions"] as? [String] ?? [],
                exercises: exercises,
                weeklySchedule: weeklySchedule,
                totalWeeks: data["totalWeeks"] as? Int ?? 4,
                createdDate: (data["createdDate"] as? Timestamp)?.dateValue() ?? Date(),
                notes: data["notes"] as? String,
                startDate: (data["startDate"] as? Timestamp)?.dateValue(),
                lastModifiedDate: (data["lastModifiedDate"] as? Timestamp)?.dateValue()
            )
            plan.schemaVersion = data["schemaVersion"] as? Int ?? 1
            // Wellness plans are stored in this same collection and are only
            // distinguishable by these two fields. Missing/unrecognized values keep
            // the model default (.rehab), which is correct for legacy rehab plans.
            if let rawPlanType = data["planType"] as? String,
               let parsedPlanType = RehabPlan.PlanType(rawValue: rawPlanType) {
                plan.planType = parsedPlanType
            }
            plan.sourceGoalCategories = data["sourceGoalCategories"] as? [String]
            return plan
    }

    // MARK: - Repair-on-load (PR 3)

    /// Walk plans that haven't been migrated to schemaVersion 2 yet, rewrite any
    /// exercises whose names no longer resolve to a catalog image, and persist.
    /// The repair pass uses the same `ImageAvailabilityValidator` as PR 2's
    /// validateRehabPlan step so substitution choices are consistent.
    private func runRepairPass(on plans: [RehabPlan]) async {
        var repairsThisCall = 0
        for original in plans {
            guard original.schemaVersion < 2 else { continue }
            guard !repairedThisSession.contains(original.id) else { continue }
            guard repairsThisCall < Self.maxRepairsPerSession else {
                AppLogger.data.info("[parsePlans] repair cap (\(Self.maxRepairsPerSession)) reached; deferring remaining plans to next cold start")
                break
            }

            // Mark BEFORE the write so a fast listener fire (which can re-enter
            // parsePlans before our updatePlan completes) doesn't re-trigger.
            repairedThisSession.insert(original.id)

            // Run the same validation helper PR 2 uses for new plans. We don't
            // have user conditions here (this runs at app cold start, before
            // any analysis context is loaded), so pass empty arrays — the
            // safety guards in `ImageAvailabilityValidator` will conservatively
            // refuse to substitute exercises with safety-flagged keywords
            // regardless of conditions.
            let result = await Task.detached(priority: .userInitiated) {
                ImageAvailabilityValidator.validate(
                    exercises: original.exercises,
                    userConditions: [],
                    userPainRegions: []
                )
            }.value

            if result.substitutionCount == 0 {
                // Nothing to rewrite, but still bump schemaVersion so we don't
                // re-attempt every cold start. Unrepairable cases also count as
                // "we did the best we can" — no point retrying.
                var bumped = original
                bumped.schemaVersion = 2
                updatePlan(bumped)
                repairsThisCall += 1
                AppLogger.data.info("[parsePlans] plan '\(original.planName)' marked v2 (no substitutions needed)")
                continue
            }

            var repaired = original
            repaired.exercises = result.rewritten
            repaired.schemaVersion = 2
            updatePlan(repaired)
            repairsThisCall += 1
            AppLogger.data.info("[parsePlans] plan '\(original.planName)' repaired: \(result.substitutionCount) substitutions, \(result.unrepairableCount) unrepairable → v2")
        }
        if repairsThisCall > 0 {
            SessionLogger.shared.log(.firestoreWrite, category: .data,
                                      message: "Repair-on-load: \(repairsThisCall) plan(s) migrated to schemaVersion 2")
        }
    }

    /// Update an existing plan in Firestore (for edits, startDate changes, etc.)
    func updatePlan(_ plan: RehabPlan) {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        // Update locally first
        if let index = rehabPlans.firstIndex(where: { $0.id == plan.id }) {
            rehabPlans[index] = plan
        }
        Task { await NotificationService.shared.syncPlanReminders(plans: rehabPlans) }

        db.collection("users").document(uid).collection("rehabPlans")
            .document(plan.id.uuidString)
            .setData(Self.planDocumentData(for: plan)) { error in
                if let error = error {
                    AppLogger.data.error("Error updating plan: \(error.localizedDescription)")
                }
            }
    }

    /// The canonical `rehabPlans` document shape.
    ///
    /// Single source of truth on purpose: this dictionary used to be rebuilt
    /// independently here and in two save paths, and the copy here silently omitted
    /// `planType`/`sourceGoalCategories`. Because the write is a full-document
    /// `setData` (not a merge), that omission *deleted* those fields — and the
    /// repair-on-load pass calls `updatePlan` for every schemaVersion<2 plan, so
    /// every wellness plan was converted to a rehab plan shortly after being saved.
    /// Round-trips with `parsePlan(from:)`; keep the two in step.
    static func planDocumentData(for plan: RehabPlan) -> [String: Any] {
        let exercisesData: [[String: Any]] = plan.exercises.map { e in
            var dict: [String: Any] = [
                "id": e.id.uuidString,
                "name": e.name,
                "targetArea": e.targetArea,
                "description": e.description,
                "sets": e.sets,
                "reps": e.reps,
                "restSeconds": e.restSeconds,
                "difficulty": e.difficulty.rawValue,
                "demonstrationIcon": e.demonstrationIcon,
                "tips": e.tips,
                "contraindications": e.contraindications
            ]
            if let sp = e.startPosition { dict["startPosition"] = sp }
            if let mv = e.movement { dict["movement"] = mv }
            if let ep = e.endPosition { dict["endPosition"] = ep }
            if let ec = e.exerciseCategory { dict["exerciseCategory"] = ec }
            if let img = e.imageFileName { dict["imageFileName"] = img }
            if let cs = e.catalogSubstitution { dict["catalogSubstitution"] = cs }
            if let n = e.notes { dict["notes"] = n }
            if let orig = e.originalAIName { dict["originalAIName"] = orig }
            return dict
        }

        // Serialize weeklySchedule as dictionary format
        var scheduleDict: [String: [String]] = [:]
        for (index, day) in plan.weeklySchedule.enumerated() {
            if !day.isEmpty {
                scheduleDict["\(index)"] = day
            }
        }

        var planData: [String: Any] = [
            "id": plan.id.uuidString,
            "planName": plan.planName,
            "conditions": plan.conditions,
            "exercises": exercisesData,
            "weeklySchedule": scheduleDict,
            "totalWeeks": plan.totalWeeks,
            "createdDate": Timestamp(date: plan.createdDate),
            "schemaVersion": plan.schemaVersion,
            "planType": plan.planType.rawValue
        ]
        if let goalCategories = plan.sourceGoalCategories {
            planData["sourceGoalCategories"] = goalCategories
        }
        if let notes = plan.notes { planData["notes"] = notes }
        if let startDate = plan.startDate { planData["startDate"] = Timestamp(date: startDate) }
        if let lastMod = plan.lastModifiedDate { planData["lastModifiedDate"] = Timestamp(date: lastMod) }
        return planData
    }

    func deletePlan(_ plan: RehabPlan) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let planId = plan.id.uuidString

        SessionLogger.shared.log(.firestoreDelete, category: .data, message: "Rehab plan deleted",
                                  metadata: ["planId": planId])

        // Remove locally first for instant UI feedback
        rehabPlans.removeAll { $0.id == plan.id }
        Task { await NotificationService.shared.syncPlanReminders(plans: rehabPlans) }

        // Remove from Firestore
        db.collection("users").document(uid).collection("rehabPlans")
            .document(planId)
            .delete { [weak self] error in
                if let error = error {
                    AppLogger.data.error("Error deleting plan: \(error.localizedDescription)")
                    // Re-fetch to restore consistent state.
                    // Firestore's completion handler is nonisolated, so hop to the main
                    // actor to call `fetchRehabPlans()` which is @MainActor-bound.
                    Task { @MainActor [weak self] in
                        self?.fetchRehabPlans()
                    }
                }
            }
    }
}
