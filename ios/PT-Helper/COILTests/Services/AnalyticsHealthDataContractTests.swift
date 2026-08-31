import XCTest
@testable import COIL

/// Enforces AnalyticsService's stated contract — "NEVER log health data (pain
/// levels, conditions, body regions, medical history). Use counts and durations
/// instead" — by scanning the actual call sites in the app target.
///
/// This is a source-level test rather than a behavioural one on purpose. GA4 is
/// a third-party processor outside the Firebase project, events are keyed to the
/// Firebase UID, and account deletion cannot reach data already exported: a leak
/// here is irreversible the moment it ships, so it needs to fail at desk-check
/// time. The form-analysis event sent the exercise NAME — condition-revealing in
/// a PT app — while SessionLogger redacted that identical key from its own
/// uploads.
final class AnalyticsHealthDataContractTests: XCTestCase {

    /// Parameter keys that would carry health information about the user.
    /// `target_area` is deliberately allowed: a coarse body area on a behavioural
    /// funnel event is the signal the funnel needs, and is not a diagnosis.
    private let forbiddenKeys: Set<String> = [
        "exercise", "exercise_name", "condition", "condition_name",
        "pain_level", "pain", "region", "regions", "body_region",
        "diagnosis", "medication", "medications", "swap_reason",
        "activity_level", "notes", "description",
    ]

    private func appSourceFiles() throws -> [URL] {
        // .../COILTests/Services/<this file> -> up 3 -> ios/PT-Helper
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Services
            .deletingLastPathComponent()   // COILTests
            .deletingLastPathComponent()   // PT-Helper
            .appendingPathComponent("COIL")

        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else {
            return []
        }
        return walker.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }

    func testNoAnalyticsCallSitePassesAHealthDataParameter() throws {
        let files = try appSourceFiles()
        XCTAssertFalse(files.isEmpty, "Could not locate the app sources to scan")

        var violations: [String] = []

        for file in files {
            guard let text = try? String(contentsOf: file, encoding: .utf8),
                  text.contains("AnalyticsService.shared.log(") else { continue }

            let lines = text.components(separatedBy: .newlines)
            for (index, line) in lines.enumerated() where line.contains("AnalyticsService.shared.log(") {
                // Scan the call's parameter dictionary (until the closing bracket).
                let window = lines[index..<min(index + 25, lines.count)]
                var depth = 0
                for callLine in window {
                    depth += callLine.filter { $0 == "(" }.count
                    depth -= callLine.filter { $0 == ")" }.count

                    for key in forbiddenKeys where callLine.contains("\"\(key)\":") {
                        violations.append("\(file.lastPathComponent):\(index + 1) passes \"\(key)\"")
                    }
                    if depth <= 0 { break }
                }
            }
        }

        XCTAssertTrue(
            violations.isEmpty,
            "Health data must never reach GA4 — it is UID-keyed and survives account deletion:\n"
                + violations.joined(separator: "\n")
        )
    }

    /// `setUserProperties` sets DURABLE attributes on the UID, so a health
    /// attribute there is worse than on a single event. It must not accept one.
    func testSetUserProperties_doesNotAcceptAHealthAttribute() throws {
        let files = try appSourceFiles()
        let analyticsService = files.first { $0.lastPathComponent == "AnalyticsService.swift" }
        let text = try XCTUnwrap(analyticsService.flatMap { try? String(contentsOf: $0, encoding: .utf8) })

        XCTAssertFalse(text.contains("forName: \"activity_level\""),
                       "activityLevel is a health-profile attribute and must not be a GA4 user property")
    }

    /// Account deletion cannot reach GA4 server-side, so the client must at least
    /// clear the local identifiers.
    func testAccountDeletionResetsAnalyticsIdentity() throws {
        let files = try appSourceFiles()
        let settings = files.first { $0.lastPathComponent == "SettingsView.swift" }
        let text = try XCTUnwrap(settings.flatMap { try? String(contentsOf: $0, encoding: .utf8) })

        XCTAssertTrue(text.contains("AnalyticsService.shared.resetForAccountDeletion()"),
                      "Local deletion cleanup must reset the analytics identity")
    }
}
