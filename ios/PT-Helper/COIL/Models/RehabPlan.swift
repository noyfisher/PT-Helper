import Foundation

struct RehabPlan: Codable, Identifiable {

    enum PlanType: String, Codable {
        case rehab
        case wellness
    }

    let id: UUID
    var planName: String
    let conditions: [String]
    var exercises: [RehabExercise]
    var weeklySchedule: [[String]]
    let totalWeeks: Int
    var createdDate: Date
    let notes: String?
    /// When the user started following this plan (nil = not started yet)
    var startDate: Date?
    /// Timestamp of last user edit (nil = never edited)
    var lastModifiedDate: Date?
    /// Whether this is a rehab or wellness plan (defaults to .rehab for backward compatibility)
    var planType: PlanType = .rehab
    /// Wellness goal categories that generated this plan (nil for rehab plans)
    var sourceGoalCategories: [String]?
    /// PR 3: schema version for repair-on-load. Plans saved before PR 2 are version 1
    /// (may contain pre-substitution AI names that no longer resolve). The repair pass
    /// in `SavedPlansViewModel.parsePlans` rewrites them to canonical catalog names
    /// and bumps to version 2. Default 1 for legacy/no-field-set documents.
    var schemaVersion: Int = 1

    /// Current week number (1-based) based on startDate, or nil if not started
    var currentWeek: Int? {
        guard let start = startDate else { return nil }
        let days = Calendar.current.dateComponents([.day], from: start, to: Date()).day ?? 0
        return min(max(days / 7 + 1, 1), totalWeeks)
    }

    /// True once the plan's full duration has elapsed (started plans only).
    var isCompleted: Bool {
        guard let start = startDate else { return false }
        let days = Calendar.current.dateComponents([.day], from: start, to: Date()).day ?? 0
        return days >= totalWeeks * 7
    }
}

struct RehabExercise: Codable, Identifiable {
    let id: UUID
    var name: String
    var targetArea: String
    var description: String
    var sets: Int
    var reps: String
    var restSeconds: Int
    var difficulty: Difficulty
    let demonstrationIcon: String
    let tips: [String]
    let contraindications: [String]

    // Structured visual instruction fields (optional for backward compatibility)
    let startPosition: String?
    let movement: String?
    let endPosition: String?
    let exerciseCategory: String?

    // AI-generated exercise image filename (optional, nil = SF Symbol fallback)
    var imageFileName: String?

    // PR 2: AI-emitted flag indicating Claude picked an anatomically-adjacent
    // exercise from the catalog because no exact target_area match existed.
    // Treated as a hint by client-side validation (which re-runs the resolver).
    var catalogSubstitution: Bool?

    // PR 2: per-exercise notes, populated by Claude when catalogSubstitution is true.
    // Distinct from `RehabPlan.notes`, which is plan-level.
    var notes: String?

    // PR 2: preserved AI-generated name when client-side validation rewrites
    // `name`/`imageFileName` to a canonical catalog entry. Lets analytics
    // answer "what did Claude originally generate that we had to substitute?"
    var originalAIName: String?

    enum Difficulty: String, Codable, CaseIterable {
        case beginner, intermediate, advanced

        /// Parse a difficulty from AI output or a Firestore document.
        ///
        /// This mapping was duplicated across four call sites, and they had already
        /// drifted: the Firestore parse path matched on the raw string without
        /// lowercasing, so a stored "Intermediate" silently decoded as `.beginner`.
        /// Unknown values intentionally fall back to `.beginner` — the safest
        /// prescription when the model returns something unrecognised.
        static func parse(_ raw: String?) -> Difficulty {
            switch raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "intermediate": return .intermediate
            case "advanced": return .advanced
            default: return .beginner
            }
        }
    }

    init(id: UUID, name: String, targetArea: String, description: String, sets: Int, reps: String, restSeconds: Int, difficulty: Difficulty, demonstrationIcon: String, tips: [String], contraindications: [String], startPosition: String? = nil, movement: String? = nil, endPosition: String? = nil, exerciseCategory: String? = nil, imageFileName: String? = nil, catalogSubstitution: Bool? = nil, notes: String? = nil, originalAIName: String? = nil) {
        self.id = id
        self.name = name
        self.targetArea = targetArea
        self.description = description
        self.sets = sets
        self.reps = reps
        self.restSeconds = restSeconds
        self.difficulty = difficulty
        self.demonstrationIcon = demonstrationIcon
        self.tips = tips
        self.contraindications = contraindications
        self.startPosition = startPosition
        self.movement = movement
        self.endPosition = endPosition
        self.exerciseCategory = exerciseCategory
        self.imageFileName = imageFileName
        self.catalogSubstitution = catalogSubstitution
        self.notes = notes
        self.originalAIName = originalAIName
    }
}
