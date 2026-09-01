import Foundation
import Combine
import UIKit

/// Manages the state for a guided workout flow: exercise-by-exercise
/// with set tracking, rest timers, and completion summary.
@MainActor
class GuidedWorkoutViewModel: ObservableObject {

    // MARK: - Checkpoint Keys

    private static let checkpointKey = "GuidedWorkoutCheckpoint"

    /// Protected on-disk location for the checkpoint. The checkpoint reveals
    /// plan/exercise names + progress (health/fitness treatment), so it lives in
    /// a file-protected store like the app's other PHI — not plain UserDefaults,
    /// which lacks `.completeFileProtection` and can end up in device backups (P2-08).
    private static var checkpointURL: URL? {
        let fm = FileManager.default
        guard let dir = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("guided_workout_checkpoint.json")
    }

    /// Reads the checkpoint bytes from the protected file, migrating a legacy
    /// UserDefaults checkpoint into the file on the first read after upgrade so an
    /// in-progress workout survives the move (then removing the legacy copy).
    private static func loadCheckpointData() -> Data? {
        if let url = checkpointURL, let data = try? Data(contentsOf: url) {
            return data
        }
        if let legacy = UserDefaults.standard.data(forKey: checkpointKey) {
            if let url = checkpointURL {
                try? legacy.write(to: url, options: [.atomic, .completeFileProtection])
            }
            UserDefaults.standard.removeObject(forKey: checkpointKey)
            return legacy
        }
        return nil
    }

    struct WorkoutCheckpoint: Codable {
        let planId: String
        let currentExerciseIndex: Int
        let currentSet: Int
        let completedExercises: [String]
        let skippedExercises: [String]
        let substitutedExercises: [String: String]
        let accumulatedTime: TimeInterval
        let savedAt: Date
    }

    // MARK: - Published State

    @Published var plan: RehabPlan
    /// True between finding a saved checkpoint and the user answering the Resume
    /// prompt. While set, nothing may overwrite that checkpoint — it is the only
    /// remaining record of the interrupted workout.
    @Published var isAwaitingCheckpointDecision = false
    @Published var currentExerciseIndex: Int = 0
    @Published var currentSet: Int = 1
    @Published var phase: WorkoutPhase = .exercise
    @Published var isTimerRunning: Bool = false
    @Published var timeRemaining: Int = 0
    @Published var totalElapsedTime: TimeInterval = 0
    @Published var completedExercises: [String] = []
    @Published var skippedExercises: [String] = []
    @Published var isPaused: Bool = false
    @Published var substitutedExercises: [String: String] = [:] // original name → new name

    enum WorkoutPhase: Equatable {
        case exercise
        case rest
        case complete
    }

    /// What the current rest phase leads into. Inter-set rest returns to the
    /// same exercise; inter-exercise rest advances to the next exercise.
    enum RestKind: Equatable {
        case interSet
        case interExercise
    }

    @Published private(set) var restKind: RestKind = .interExercise
    /// Total duration of the current rest, used for progress ring rendering.
    @Published private(set) var restDuration: Int = 0

    // MARK: - Exercise Familiarity

    enum ExerciseFamiliarity: Int, Comparable {
        case new = 0, learning = 1, familiar = 2, mastered = 3

        init(completions: Int) {
            switch completions {
            case 0: self = .new
            case 1...3: self = .learning
            case 4...9: self = .familiar
            default: self = .mastered
            }
        }

        static func < (lhs: Self, rhs: Self) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    static func completionCount(for exerciseName: String) -> Int {
        UserDefaults.standard.integer(forKey: "exerciseCompletions_\(exerciseName)")
    }

    static func incrementCompletionCount(for exerciseName: String) {
        let key = "exerciseCompletions_\(exerciseName)"
        let current = UserDefaults.standard.integer(forKey: key)
        UserDefaults.standard.set(current + 1, forKey: key)
    }

    /// Clears the workout checkpoint and all per-exercise completion counters
    /// (account deletion).
    static func clearAllLocalWorkoutState() {
        if let url = checkpointURL { try? FileManager.default.removeItem(at: url) }
        UserDefaults.standard.removeObject(forKey: checkpointKey) // legacy copy
        for key in UserDefaults.standard.dictionaryRepresentation().keys
        where key.hasPrefix("exerciseCompletions_") {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    // MARK: - Timer

    private var timerSubscription: AnyCancellable?
    private var elapsedSubscription: AnyCancellable?
    /// Accumulated elapsed time from completed (pre-pause) segments.
    private var accumulatedTime: TimeInterval = 0
    /// Reference point for the current active segment (reset on each resume).
    private var lastResumeTime = Date()
    /// Wall-clock end of the current rest. Source of truth for timeRemaining.
    private var restEndDate: Date?
    /// Injectable clock for the rest-timer paths (test seam). Production: real Date.
    var now: () -> Date = { Date() }

    // MARK: - Computed Properties

    var currentExercise: RehabExercise? {
        guard plan.exercises.indices.contains(currentExerciseIndex) else { return nil }
        return plan.exercises[currentExerciseIndex]
    }

    var totalExercises: Int { plan.exercises.count }

    var progress: Double {
        guard totalExercises > 0 else { return 0 }
        return Double(currentExerciseIndex) / Double(totalExercises)
    }

    var exerciseProgress: String {
        "\(currentExerciseIndex + 1) of \(totalExercises)"
    }

    var formattedElapsedTime: String {
        let minutes = Int(totalElapsedTime) / 60
        let seconds = Int(totalElapsedTime) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    var formattedTimeRemaining: String {
        let minutes = timeRemaining / 60
        let seconds = timeRemaining % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    // MARK: - Init

    init(plan: RehabPlan) {
        self.plan = plan
        startElapsedTimer()
    }

    // MARK: - Actions

    /// Mark the current set as complete. If all sets done, start rest or move to next exercise.
    func completeSet() {
        guard let exercise = currentExercise else { return }

        SessionLogger.shared.logUserAction(.buttonTapped, action: "completeSet",
                                            metadata: ["exercise": exercise.name,
                                                        "set": "\(currentSet)/\(exercise.sets)"])

        if currentSet >= exercise.sets {
            // All sets done for this exercise
            completedExercises.append(exercise.name)
            Self.incrementCompletionCount(for: exercise.name)

            if currentExerciseIndex < totalExercises - 1 {
                // Start rest before next exercise. Save the ADVANCED position:
                // the live index still points at the just-completed exercise
                // (invariant — see saveCheckpoint doc comment).
                saveCheckpoint(forNextExercise: true)
                startRestTimer(seconds: exercise.restSeconds, kind: .interExercise)
            } else {
                // Last exercise — workout complete
                finishWorkout()   // clears the checkpoint — no save needed
            }
        } else {
            // More sets to do — brief inter-set rest
            currentSet += 1
            saveCheckpoint()
            let interSetRest = min(exercise.restSeconds, 60)
            startRestTimer(seconds: interSetRest, kind: .interSet)
        }
    }

    /// Skip the current exercise entirely
    func skipExercise() {
        guard let exercise = currentExercise else { return }
        AnalyticsService.shared.log(.exerciseSkipped)
        SessionLogger.shared.logUserAction(.buttonTapped, action: "skipExercise",
                                            metadata: ["exercise": exercise.name])
        skippedExercises.append(exercise.name)
        moveToNextExercise()
    }

    /// Skip the remaining rest time and continue (next set or next exercise,
    /// depending on the kind of rest in progress).
    func skipRest() {
        stopTimer()
        if phase == .rest {
            endRest()
        }
    }

    /// Adjust rest timer by a number of seconds (positive or negative)
    func adjustRestTime(by seconds: Int) {
        timeRemaining = max(5, timeRemaining + seconds)
        restDuration = max(restDuration, timeRemaining)
        restEndDate = now().addingTimeInterval(TimeInterval(timeRemaining))
    }

    /// Toggle pause state
    func togglePause() {
        isPaused.toggle()
        AnalyticsService.shared.log(.workoutPauseToggled, parameters: ["paused": isPaused ? "true" : "false"])
        SessionLogger.shared.logUserAction(.toggleChanged, action: "workoutPause",
                                            metadata: ["paused": "\(isPaused)"])
        if isPaused {
            // Save elapsed time from the current active segment before pausing
            accumulatedTime += Date().timeIntervalSince(lastResumeTime)
            timerSubscription?.cancel()
            timerSubscription = nil
            elapsedSubscription?.cancel()
            elapsedSubscription = nil
        } else {
            // Reset reference point so the next segment starts fresh
            lastResumeTime = Date()
            if phase == .rest && timeRemaining > 0 {
                restEndDate = now().addingTimeInterval(TimeInterval(timeRemaining))
                isTimerRunning = true
                startRestTicker()
            }
            startElapsedTimer()
        }
    }

    /// Build the final WorkoutSession from the guided workout data
    func buildSession(painLevel: Double, regionPainLevels: [String: Double]?, notes: String?) -> WorkoutSession {
        WorkoutSession(
            id: UUID(),
            date: Date(),
            duration: totalElapsedTime,
            painLevel: painLevel,
            isCompleted: true,
            exercisesPerformed: completedExercises,
            notes: notes?.trimmingCharacters(in: .whitespaces).isEmpty == true ? nil : notes,
            regionPainLevels: regionPainLevels?.isEmpty == true ? nil : regionPainLevels,
            planId: plan.id
        )
    }

    /// Discard the workout entirely without saving any session data.
    /// Used when a user accidentally starts a workout.
    func discardWorkout() {
        stopTimer()
        elapsedSubscription?.cancel()
        elapsedSubscription = nil
        clearCheckpoint()
        AnalyticsService.shared.log(.workoutDiscarded, parameters: [
            "completed_count": completedExercises.count,
            "duration_seconds": Int(totalElapsedTime)
        ])
        SessionLogger.shared.logUserAction(.buttonTapped, action: "discardWorkout",
                                            metadata: ["completed": "\(completedExercises.count)"])
    }

    /// End the workout early, marking remaining exercises as skipped.
    func endWorkoutEarly() {
        // Mark all remaining exercises (including current) as skipped
        for i in currentExerciseIndex..<totalExercises {
            let name = plan.exercises[i].name
            if !completedExercises.contains(name) && !skippedExercises.contains(name) {
                skippedExercises.append(name)
            }
        }
        AnalyticsService.shared.log(.workoutEndedEarly, parameters: [
            "completed_count": completedExercises.count,
            "skipped_count": skippedExercises.count
        ])
        SessionLogger.shared.logUserAction(.buttonTapped, action: "endWorkoutEarly",
                                            metadata: ["completed": "\(completedExercises.count)",
                                                        "skipped": "\(skippedExercises.count)"])
        finishWorkout()
    }

    /// Replace the current exercise with a substitute, updating the plan in-place.
    func swapCurrentExercise(with substitute: RehabExercise, updatedPlan: RehabPlan) {
        let originalName = currentExercise?.name ?? "Unknown"
        self.plan = updatedPlan
        substitutedExercises[originalName] = substitute.name
        // Reset set counter since this is a new exercise
        currentSet = 1
        // Checkpoints are written on set completion, skip and backgrounding — but
        // not here, so a crash after a mid-set swap restored the substitute at the
        // PRE-swap set counter (e.g. set 3 of a 3-set exercise the user hasn't
        // started). Persist the reset immediately.
        saveCheckpoint()
    }

    // MARK: - Checkpointing

    /// Save current workout state so it can be resumed after a crash or interruption.
    ///
    /// Invariant: a checkpoint always records the next actionable exercise/set —
    /// never state the user has already completed. Pass `forNextExercise: true`
    /// when saving at the moment an exercise is completed but the index has not
    /// yet advanced (inter-exercise rest window).
    func saveCheckpoint(forNextExercise: Bool = false) {
        let checkpoint = WorkoutCheckpoint(
            planId: plan.id.uuidString,
            currentExerciseIndex: forNextExercise ? currentExerciseIndex + 1 : currentExerciseIndex,
            currentSet: forNextExercise ? 1 : currentSet,
            completedExercises: completedExercises,
            skippedExercises: skippedExercises,
            substitutedExercises: substitutedExercises,
            accumulatedTime: isPaused ? accumulatedTime : accumulatedTime + Date().timeIntervalSince(lastResumeTime),
            savedAt: Date()
        )
        if let data = try? JSONEncoder().encode(checkpoint), let url = Self.checkpointURL {
            try? data.write(to: url, options: [.atomic, .completeFileProtection])
        }
    }

    /// Clear saved checkpoint (called on workout completion or discard).
    func clearCheckpoint() {
        if let url = Self.checkpointURL { try? FileManager.default.removeItem(at: url) }
        UserDefaults.standard.removeObject(forKey: Self.checkpointKey) // drop any legacy copy
    }

    /// Check if a saved checkpoint exists for the given plan.
    static func savedCheckpoint(forPlanId planId: String) -> WorkoutCheckpoint? {
        guard let data = loadCheckpointData(),
              let checkpoint = try? JSONDecoder().decode(WorkoutCheckpoint.self, from: data),
              checkpoint.planId == planId,
              // Discard checkpoints older than 24 hours
              Date().timeIntervalSince(checkpoint.savedAt) < 86400 else {
            return nil
        }
        return checkpoint
    }

    /// Restore state from a checkpoint.
    func restoreFromCheckpoint(_ checkpoint: WorkoutCheckpoint) {
        currentExerciseIndex = min(checkpoint.currentExerciseIndex, totalExercises - 1)
        // Clamp: a checkpoint can outlive the shape of the plan it described (an
        // exercise swapped for one with fewer sets, or a plan edited between runs),
        // and an out-of-range set counter puts the workout past its own end.
        let setsForCurrentExercise = max(1, currentExercise?.sets ?? 1)
        currentSet = min(max(checkpoint.currentSet, 1), setsForCurrentExercise)
        completedExercises = checkpoint.completedExercises
        skippedExercises = checkpoint.skippedExercises
        substitutedExercises = checkpoint.substitutedExercises
        accumulatedTime = checkpoint.accumulatedTime
        totalElapsedTime = accumulatedTime
        lastResumeTime = Date()
        phase = .exercise
    }

    // MARK: - Scene Phase

    /// Persist an accurate checkpoint when the app is backgrounded mid-workout.
    /// During an inter-exercise rest the live index still points at the exercise
    /// just completed, so save the advanced position (same rule as completeSet's
    /// final-set branch) — a live-state save here would resurrect the WS5-01 bug.
    func handleAppBackgrounded() {
        guard phase != .complete else { return }
        // A saved checkpoint the user hasn't answered the Resume prompt for yet is
        // still the authoritative record of their progress. This handler is live
        // from the moment the view appears, so backgrounding while that alert is up
        // (a call, an app switch) wrote a checkpoint for the freshly-initialised
        // ViewModel — exercise 0, set 1, nothing completed — over the real one.
        guard !isAwaitingCheckpointDecision else { return }
        if phase == .rest && restKind == .interExercise {
            saveCheckpoint(forNextExercise: true)
        } else {
            saveCheckpoint()
        }
    }

    /// Snap timers to the wall clock immediately on return to foreground
    /// (instead of waiting up to 1s for the next ticker tick).
    func handleAppForegrounded() {
        guard !isPaused, phase != .complete else { return }
        if phase == .rest {
            reconcileRestFromWallClock()
        }
        totalElapsedTime = accumulatedTime + now().timeIntervalSince(lastResumeTime)
    }

    // MARK: - Private

    private func moveToNextExercise() {
        stopTimer()
        if currentExerciseIndex < totalExercises - 1 {
            currentExerciseIndex += 1
            currentSet = 1
            phase = .exercise
            saveCheckpoint()
        } else {
            finishWorkout()
        }
    }

    /// End the current rest phase, routing to the next set or next exercise
    /// based on the kind of rest that was running.
    private func endRest() {
        stopTimer()
        switch restKind {
        case .interSet:
            // Stay on the same exercise; currentSet was already advanced in completeSet()
            phase = .exercise
        case .interExercise:
            moveToNextExercise()
        }
    }

    private func finishWorkout() {
        // Capture final elapsed time before stopping timers
        if !isPaused {
            accumulatedTime += Date().timeIntervalSince(lastResumeTime)
        }
        totalElapsedTime = accumulatedTime
        stopTimer()
        elapsedSubscription?.cancel()
        elapsedSubscription = nil
        clearCheckpoint()
        phase = .complete

        AnalyticsService.shared.log(.workoutCompleted, parameters: [
            "duration_seconds": Int(totalElapsedTime),
            "exercises_completed": completedExercises.count,
            "exercises_skipped": skippedExercises.count
        ])
        SessionLogger.shared.log(.stateUpdated, category: .stateChange, message: "Guided workout completed",
                                  metadata: ["completed": "\(completedExercises.count)",
                                              "skipped": "\(skippedExercises.count)",
                                              "elapsed": formattedElapsedTime])
    }

    private func startRestTimer(seconds: Int, kind: RestKind) {
        phase = .rest
        restKind = kind
        timeRemaining = max(seconds, 5)
        restDuration = timeRemaining
        restEndDate = now().addingTimeInterval(TimeInterval(timeRemaining))
        isTimerRunning = true
        startRestTicker()
    }

    private func startRestTicker() {
        timerSubscription = Foundation.Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.reconcileRestFromWallClock()
            }
    }

    /// Derive timeRemaining from the wall-clock end date. Called every ticker
    /// tick and on foreground return; self-heals after any suspension.
    func reconcileRestFromWallClock() {
        guard !isPaused, phase == .rest, let end = restEndDate else { return }
        let remaining = max(0, Int(end.timeIntervalSince(now()).rounded(.up)))
        if timeRemaining > 5 && remaining <= 5 && remaining > 0 {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        timeRemaining = remaining
        if remaining == 0 {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            endRest()
        }
    }

    private func stopTimer() {
        timerSubscription?.cancel()
        timerSubscription = nil
        isTimerRunning = false
        timeRemaining = 0
        restEndDate = nil
    }

    private func startElapsedTimer() {
        elapsedSubscription = Foundation.Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self, !self.isPaused else { return }
                self.totalElapsedTime = self.accumulatedTime + Date().timeIntervalSince(self.lastResumeTime)
            }
    }
}
