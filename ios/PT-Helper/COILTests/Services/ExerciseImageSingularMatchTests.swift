import XCTest
@testable import COIL

/// Replays the singular exercise names that the fuzzy matcher used to hijack,
/// against the SHIPPED mapping.
///
/// The prefix and suffix layers ran before the whole-string plural toggle, so a
/// singular name whose exact plural key existed was captured first by a longer,
/// more specialised key — "Hamstring Curl" resolving to `hamstring-curl-band`,
/// "Deadlift" to `dumbbell-deadlift`, "Dumbbell Lateral Raise" to the single-leg
/// balance variant. In a PT app the illustration is what the user copies, so a
/// banded, loaded or single-leg variant shown for an unloaded prescription is a
/// wrong instruction rather than a cosmetic mismatch.
@MainActor
final class ExerciseImageSingularMatchTests: XCTestCase {

    private let service = ExerciseImageService.shared

    /// (input name, expected mapping key). Every pair is a real hijack from the
    /// shipped `exercise_image_mapping.json`, derived by finding singular forms
    /// whose exact plural exists while a longer specialised key would match first.
    private let knownHijacks: [(name: String, expected: String)] = [
        ("Band Row", "band-rows"),
        ("Bicep Curl", "bicep-curls"),
        ("Calf Raise", "calf-raises"),
        ("Clam Shell", "clam-shells"),
        ("Deadlift", "deadlifts"),
        ("Dumbbell Lateral Raise", "dumbbell-lateral-raises"),
        ("Dumbbell Step Up", "dumbbell-step-ups"),
        ("Glute Squeeze", "glute-squeezes"),
        ("Hamstring Curl", "hamstring-curls"),
        ("Hip Bridge", "hip-bridges"),
        ("Hip Circle", "hip-circles"),
    ]

    func testSingularNames_resolveToTheirExactPluralKey_notASpecialisedVariant() {
        var failures: [String] = []

        for (name, expected) in knownHijacks {
            let exercise = RehabExercise(
                id: UUID(), name: name, targetArea: "Knee",
                description: "", sets: 3, reps: "10", restSeconds: 30,
                difficulty: .beginner, demonstrationIcon: "figure.cooldown",
                tips: [], contraindications: []
            )
            let resolved = service.imageKey(for: exercise)
            if resolved != expected {
                failures.append("\(name): expected \(expected), got \(resolved ?? "nil")")
            }
        }

        XCTAssertTrue(failures.isEmpty,
                      "Singular names must prefer the exact plural key:\n" + failures.joined(separator: "\n"))
    }

    /// The hoist must not break the case the prefix layer exists for: a decorated
    /// name with no exact key still needs its fuzzy match.
    func testDecoratedName_withNoExactKey_stillMatchesViaPrefix() {
        let exercise = RehabExercise(
            id: UUID(), name: "Cat-Cow Stretch Modified For Lower Back Relief",
            targetArea: "Lower Back",
            description: "", sets: 3, reps: "10", restSeconds: 30,
            difficulty: .beginner, demonstrationIcon: "figure.cooldown",
            tips: [], contraindications: []
        )
        XCTAssertNotNil(service.imageKey(for: exercise),
                        "Hoisting the plural toggle must not disable prefix matching")
    }
}
