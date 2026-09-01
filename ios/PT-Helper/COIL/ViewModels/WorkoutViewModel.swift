import Foundation
import FirebaseFirestore
import FirebaseAuth

@MainActor
class WorkoutViewModel: ObservableObject {
    @Published var sessions: [WorkoutSession] = [] {
        didSet { recomputeDerivedStats() }
    }
    @Published var loadError: String?
    /// A completed session that did not reach Firestore. Surfaced rather than
    /// logged: the session is already in `sessions`, so without this the UI shows
    /// it as saved and it disappears on the next launch.
    @Published var saveFailure: PersistenceFailure?
    @Published var isLoading: Bool = false
    @Published private(set) var averagePain: Double = 0

    private let db = Firestore.firestore()
    private static let sessionFetchLimit = 180

    init() {
        if TestDataSeeder.isUITesting && TestDataSeeder.shouldSeedMockData {
            let plans = TestDataSeeder.makeMockPlans()
            self.sessions = TestDataSeeder.makeMockSessions(planId: plans.first?.id ?? UUID())
            self.isLoading = false
        } else {
            fetchSessions()
        }
    }

    private func recomputeDerivedStats() {
        averagePain = sessions.isEmpty ? 0 : sessions.reduce(0.0) { $0 + $1.painLevel } / Double(sessions.count)
    }

    func fetchSessions() {
        // See `SavedPlansViewModel.startListening()`. HomeTab calls this on every
        // appear, so without this guard a persisted auth session would overwrite the
        // seeded mock sessions as soon as the Home tab renders.
        guard !TestDataSeeder.isUITesting else { return }
        guard let uid = Auth.auth().currentUser?.uid else { return }
        isLoading = true
        db.collection("users").document(uid).collection("workoutSessions")
            .order(by: "date", descending: true)
            .limit(to: Self.sessionFetchLimit)
            .getDocuments { [weak self] snapshot, error in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    self.isLoading = false
                    if let error = error {
                        AppLogger.data.error("Error fetching workout sessions: \(error.localizedDescription)")
                        SessionLogger.shared.logError(error, context: "WorkoutSessionsFetch")
                        self.loadError = "Unable to load your workouts. Pull down to retry."
                        return
                    }
                    self.loadError = nil
                    SessionLogger.shared.log(.firestoreRead, category: .data, message: "Fetched workout sessions",
                                              metadata: ["count": "\(snapshot?.documents.count ?? 0)"])
                    self.sessions = snapshot?.documents.compactMap { document -> WorkoutSession? in
                        let data = document.data()
                        guard let idString = data["id"] as? String,
                              let id = UUID(uuidString: idString) else {
                            return nil
                        }
                        let date = (data["date"] as? Timestamp)?.dateValue() ?? Date()
                        let duration = data["duration"] as? TimeInterval ?? 0
                        let painLevel = data["painLevel"] as? Double ?? 0
                        let isCompleted = data["isCompleted"] as? Bool ?? false
                        let exercisesPerformed = data["exercisesPerformed"] as? [String] ?? []
                        let notes = data["notes"] as? String
                        let regionPainLevels = data["regionPainLevels"] as? [String: Double]
                        let planId: UUID? = (data["planId"] as? String).flatMap { UUID(uuidString: $0) }
                        return WorkoutSession(
                            id: id,
                            date: date,
                            duration: duration,
                            painLevel: painLevel,
                            isCompleted: isCompleted,
                            exercisesPerformed: exercisesPerformed,
                            notes: notes,
                            regionPainLevels: regionPainLevels,
                            planId: planId
                        )
                    } ?? []
                }
            }
    }

    /// Delete a workout session locally and from Firestore.
    func deleteSession(_ session: WorkoutSession) {
        sessions.removeAll { $0.id == session.id }

        SessionLogger.shared.log(.firestoreDelete, category: .data, message: "Workout session deleted",
                                  metadata: ["sessionId": session.id.uuidString])

        guard let uid = Auth.auth().currentUser?.uid else { return }
        db.collection("users").document(uid).collection("workoutSessions")
            .document(session.id.uuidString)
            .delete { error in
                if let error = error {
                    AppLogger.data.error("Error deleting workout session: \(error.localizedDescription)")
                }
            }
    }

    func addSession(session: WorkoutSession) {
        sessions.insert(session, at: 0) // Add to top since sorted by newest first

        SessionLogger.shared.log(.firestoreWrite, category: .data, message: "Workout session added",
                                  metadata: ["sessionId": session.id.uuidString,
                                              "exerciseCount": "\(session.exercisesPerformed.count)"])

        // Update streak and achievements
        StreakService.shared.updateStreak(after: session)
        StreakService.shared.checkAchievements(totalSessions: sessions.count)
        StreakService.shared.evaluatePainImprovement(sessions: sessions)
        // Reset the inactivity-nudge clock — the user is active today (audit #33).
        NotificationService.shared.scheduleInactivityNudge()
        Task { await NotificationService.shared.noteWorkoutCompleted() }

        // Persist to Firestore
        guard let uid = Auth.auth().currentUser?.uid else { return }
        var sessionData: [String: Any] = [
            "id": session.id.uuidString,
            "date": Timestamp(date: session.date),
            "duration": session.duration,
            "painLevel": session.painLevel,
            "isCompleted": session.isCompleted,
            "exercisesPerformed": session.exercisesPerformed
        ]
        if let notes = session.notes {
            sessionData["notes"] = notes
        }
        if let regionPainLevels = session.regionPainLevels, !regionPainLevels.isEmpty {
            sessionData["regionPainLevels"] = regionPainLevels
        }
        if let planId = session.planId {
            sessionData["planId"] = planId.uuidString
        }
        db.collection("users").document(uid).collection("workoutSessions")
            .document(session.id.uuidString)
            .setData(sessionData) { [weak self] error in
                if let error = error {
                    AppLogger.data.error("Error saving workout session: \(error.localizedDescription)")
                    Task { @MainActor in
                        self?.saveFailure = PersistenceFailure(
                            subject: "your workout",
                            underlyingDescription: error.localizedDescription
                        )
                    }
                }
            }
    }
}
