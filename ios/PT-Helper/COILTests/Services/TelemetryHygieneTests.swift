import XCTest
@testable import COIL

/// Guards the two telemetry paths that fail silently: uploads that stop without
/// anyone noticing, and health text reaching a sink that only redacted half its
/// payload.
@MainActor
final class TelemetryHygieneTests: XCTestCase {

    /// The upload dedup compared the event ARRAY LENGTH, which `trimEventsIfNeeded`
    /// pins at the 500-event cap. Once a long session hit that and uploaded once,
    /// the comparison was permanently equal and uploads stopped for the rest of the
    /// session — including the forced upload on backgrounding, the one that matters
    /// for crash recovery. This pins the monotonic counter that replaced it.
    func testEventCountSaturatesAtTheCap_soDedupCannotUseIt() {
        let logger = SessionLogger.shared
        logger.startSession(userId: "test-telemetry-user")

        for index in 0..<520 {
            logger.log(.stateUpdated, category: .stateChange, message: "event \(index)")
        }

        XCTAssertLessThanOrEqual(logger.eventCount, 500,
                                 "The retained array is capped — which is exactly why dedup must not key on it")
    }

    /// `message` reaches Firebase alongside metadata, and only metadata was
    /// redacted. No current call site puts health data there, but nothing stopped
    /// one, and the tests only covered metadata.
    func testLogMessages_areRedactedLikeMetadata() {
        let raw = "Contact me at patient@example.com about my token abc123def456ghi789jkl"
        let redacted = SessionLogger.redactedErrorSummary(raw)

        XCTAssertFalse(redacted.contains("patient@example.com"),
                       "An email in a log message must be redacted, as it already is in metadata")
    }

    func testRedaction_boundsMessageLength() {
        let long = String(repeating: "x", count: 5000)
        XCTAssertLessThanOrEqual(SessionLogger.redactedErrorSummary(long).count, 400,
                                 "Unbounded messages inflate every uploaded session log")
    }
}
