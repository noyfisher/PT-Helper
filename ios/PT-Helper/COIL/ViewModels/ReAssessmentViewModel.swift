import Foundation
import FirebaseFirestore
import FirebaseAuth

/// Manages re-assessment flow: saves snapshots, computes before/after comparison.
@MainActor
class ReAssessmentViewModel: ObservableObject {
    @Published var assessments: [AssessmentSnapshot] = []
    /// A re-assessment snapshot that did not reach Firestore. This drives the
    /// before/after comparison, so a silent loss removes the evidence the feature
    /// exists to show.
    @Published var saveFailure: PersistenceFailure?
    @Published var isLoading = false

    private let db = Firestore.firestore()

    /// Whether a re-assessment should be shown for a plan at the current week
    func shouldShowReAssessment(for plan: RehabPlan) -> Bool {
        guard let week = plan.currentWeek else { return false }
        let midpoint = max(plan.totalWeeks / 2, 1)
        let isMidpoint = week == midpoint
        let isCompletion = week >= plan.totalWeeks

        // Only show if no assessment of this type exists for this plan
        let hasAssessment = assessments.contains { snapshot in
            snapshot.planId == plan.id && (
                (isMidpoint && snapshot.assessmentType == .midpoint) ||
                (isCompletion && snapshot.assessmentType == .completion)
            )
        }

        return (isMidpoint || isCompletion) && !hasAssessment
    }

    /// The assessment type to show (midpoint or completion)
    func assessmentType(for plan: RehabPlan) -> AssessmentSnapshot.AssessmentType? {
        guard let week = plan.currentWeek else { return nil }
        if week >= plan.totalWeeks { return .completion }
        if week == max(plan.totalWeeks / 2, 1) { return .midpoint }
        return nil
    }

    /// Save a new assessment snapshot
    func saveAssessment(_ snapshot: AssessmentSnapshot) async {
        assessments.append(snapshot)

        guard let uid = Auth.auth().currentUser?.uid else {
            // Signed out mid-flow: the snapshot is in the published array and the
            // UI will show the check-in as recorded, but nothing was persisted.
            // Returning silently is what made this invisible until relaunch.
            AppLogger.data.error("Cannot save assessment: no authenticated user")
            saveFailure = PersistenceFailure(
                subject: "your check-in",
                underlyingDescription: "No signed-in user"
            )
            return
        }

        let data: [String: Any] = [
            "id": snapshot.id.uuidString,
            "planId": snapshot.planId.uuidString,
            "assessmentType": snapshot.assessmentType.rawValue,
            "date": Timestamp(date: snapshot.date),
            "regionPainLevels": snapshot.regionPainLevels,
            "overallPain": snapshot.overallPain
        ]

        do {
            try await db.collection("users").document(uid)
                .collection("assessments").document(snapshot.id.uuidString)
                .setData(data)
        } catch {
            AppLogger.data.error("Error saving assessment: \(error.localizedDescription)")
            saveFailure = PersistenceFailure(
                subject: "your check-in",
                underlyingDescription: error.localizedDescription
            )
        }
    }

    /// Load all assessments from Firestore
    func loadAssessments() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        isLoading = true

        do {
            let snapshot = try await db.collection("users").document(uid)
                .collection("assessments")
                .order(by: "date", descending: false)
                .getDocuments()

            assessments = snapshot.documents.compactMap { doc -> AssessmentSnapshot? in
                let data = doc.data()
                guard let idStr = data["id"] as? String,
                      let id = UUID(uuidString: idStr),
                      let planIdStr = data["planId"] as? String,
                      let planId = UUID(uuidString: planIdStr),
                      let typeStr = data["assessmentType"] as? String,
                      let assessmentType = AssessmentSnapshot.AssessmentType(rawValue: typeStr) else {
                    return nil
                }
                return AssessmentSnapshot(
                    id: id,
                    planId: planId,
                    assessmentType: assessmentType,
                    date: (data["date"] as? Timestamp)?.dateValue() ?? Date(),
                    regionPainLevels: data["regionPainLevels"] as? [String: Double] ?? [:],
                    overallPain: data["overallPain"] as? Double ?? 0
                )
            }
            isLoading = false
        } catch {
            AppLogger.data.error("Error loading assessments: \(error.localizedDescription)")
            isLoading = false
        }
    }

    /// Get the initial assessment for a plan (if any)
    func initialAssessment(for planId: UUID) -> AssessmentSnapshot? {
        assessments.first { $0.planId == planId && $0.assessmentType == .initial }
    }

    /// Compute the before/after comparison for a plan
    func comparison(for planId: UUID) -> (initial: AssessmentSnapshot, latest: AssessmentSnapshot)? {
        let planAssessments = assessments
            .filter { $0.planId == planId }
            .sorted { $0.date < $1.date }

        guard let initial = planAssessments.first,
              planAssessments.count > 1,
              let latest = planAssessments.last else {
            return nil
        }
        return (initial, latest)
    }
}
