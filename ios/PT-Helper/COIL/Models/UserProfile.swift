import Foundation
import FirebaseFirestore
import FirebaseAuth

struct UserProfile: Codable, Identifiable {
    var id: String { userId }
    var userId: String
    var firstName: String
    var lastName: String
    var dateOfBirth: Date
    var sex: String
    var heightFeet: Int
    var heightInches: Int
    var weight: Double
    var medicalConditions: [String]
    var otherMedicalConditions: String?
    var surgeries: [Surgery]
    var injuries: [Injury]
    var activityLevel: String
    var primarySport: String?

    var age: Int {
        let calendar = Calendar.current
        let ageComponents = calendar.dateComponents([.year], from: dateOfBirth, to: Date())
        return ageComponents.year ?? 0
    }

    var medications: [String]?
    var dominantSide: String?           // "Left" | "Right" | "Ambidextrous"
    var medicationHistory: [MedicationChange]?
    var wellnessGoals: [WellnessGoal] = []

    struct Surgery: Codable, Identifiable {
        var id: UUID = UUID()
        var name: String
        var year: Int
        var bodyArea: String?
        var recoveryStatus: String?     // "Fully recovered" | "Still recovering" | "Have restrictions"
        var restrictions: String?
        var surgeryType: String?        // Exact name or description of the surgery
        var causingInjury: String?      // What injury led to this surgery
        var hasHardware: Bool?          // Whether pins/screws/plates remain
        var hardwareDetails: String?    // Description of remaining hardware
    }

    struct MedicationChange: Codable, Equatable {
        let medication: String
        let action: String              // "started" or "stopped"
        let date: Date
    }

    struct Injury: Codable, Identifiable {
        var id: UUID = UUID()
        var bodyArea: String
        var description: String
        var isCurrent: Bool
        var year: Int?
        var sawDoctor: Bool?
        var hadPhysicalTherapy: Bool?
        var recoveryStatus: String?     // "Fully recovered" | "Mostly recovered" | "Still dealing with it"
    }

    struct WellnessGoal: Codable, Identifiable {
        var id: UUID = UUID()
        var category: GoalCategory
        var customDescription: String?
        var startDate: Date
        var isActive: Bool
    }

    // MARK: - Firestore Parsing

    /// Neutral fallback DOB (age ~30) for a profile document whose `dateOfBirth`
    /// is missing or unparseable.
    ///
    /// The old fallback was `Date()` — age 0 — which silently changed safety
    /// behavior in both directions: the age-≥65 advanced-exercise check in
    /// `validateRehabPlan` failed OPEN, and the under-13 hard block fired for a
    /// legitimate adult whose field got lost. A ~30-year-old prior triggers
    /// neither the senior nor the minor path, and the legally binding age gate
    /// does not rest on this value anyway: the server reads the rules-immutable
    /// `consents/legal` DOB first (`getUserAge`), which is written at terms
    /// acceptance and cannot go missing the way a re-saved profile field can.
    static func fallbackDateOfBirth(now: Date = Date()) -> Date {
        Calendar.current.date(byAdding: .year, value: -30, to: now) ?? now
    }

    /// Parse a Firestore `dateOfBirth` value, logging when the fallback engages
    /// so a data problem is visible instead of silently reshaping safety checks.
    static func parseDateOfBirth(_ raw: Any?, context: String) -> Date {
        if let date = (raw as? Timestamp)?.dateValue() {
            return date
        }
        AppLogger.data.error("\(context): dateOfBirth missing/unparseable — using neutral ~30y fallback")
        return fallbackDateOfBirth()
    }

    /// Create a UserProfile from a Firestore data dictionary.
    static func from(firestoreData data: [String: Any]) -> UserProfile {
        let uid = data["userId"] as? String ?? Auth.auth().currentUser?.uid ?? ""

        var profile = UserProfile(
            userId: uid,
            firstName: data["firstName"] as? String ?? data["name"] as? String ?? "",
            lastName: data["lastName"] as? String ?? "",
            dateOfBirth: parseDateOfBirth(data["dateOfBirth"], context: "UserProfile.from"),
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
                return MedicationChange(medication: medication, action: action, date: date)
            }
        }

        if let surgeriesData = data["surgeries"] as? [[String: Any]] {
            profile.surgeries = surgeriesData.map { s in
                Surgery(
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

        if let injuriesData = data["injuries"] as? [[String: Any]] {
            profile.injuries = injuriesData.map { i in
                Injury(
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

        if let goalsData = data["wellnessGoals"] as? [[String: Any]] {
            profile.wellnessGoals = goalsData.compactMap { g in
                guard let categoryRaw = g["category"] as? String,
                      let category = GoalCategory(rawValue: categoryRaw) else { return nil }
                let startDate: Date
                if let ts = g["startDate"] as? Timestamp {
                    startDate = ts.dateValue()
                } else {
                    startDate = Date()
                }
                return WellnessGoal(
                    id: UUID(uuidString: g["id"] as? String ?? "") ?? UUID(),
                    category: category,
                    customDescription: g["customDescription"] as? String,
                    startDate: startDate,
                    isActive: g["isActive"] as? Bool ?? true
                )
            }
        }

        return profile
    }

    /// Computed property for full name
    var name: String {
        let full = "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
        return full.isEmpty ? firstName : full
    }
}
