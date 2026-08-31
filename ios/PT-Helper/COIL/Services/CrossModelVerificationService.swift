import Foundation
import FirebaseAuth
import os

// MARK: - Cross-Model Verification Result

struct CrossModelResult {
    let exerciseName: String
    let conditionName: String
    let isSafe: Bool
    let confidence: Double
    let reasoning: String
    let concerns: [String]
}

/// The final verification status for an exercise after all verification tiers have been attempted.
enum ExerciseVerificationStatus: Equatable {
    case verified                                    // Knowledge graph confirms safe
    case contraindicated(reason: String)             // Knowledge graph confirms unsafe
    case crossModelVerified                          // GPT-4o-mini confirms safe
    case crossModelFlagged(concerns: [String])       // GPT-4o-mini has concerns
    case crossModelFailed                            // Cross-model check failed (network, etc.)
    case checking                                    // Cross-model check in progress

    static func == (lhs: ExerciseVerificationStatus, rhs: ExerciseVerificationStatus) -> Bool {
        switch (lhs, rhs) {
        case (.verified, .verified): return true
        case (.contraindicated(let a), .contraindicated(let b)): return a == b
        case (.crossModelVerified, .crossModelVerified): return true
        case (.crossModelFlagged(let a), .crossModelFlagged(let b)): return a == b
        case (.crossModelFailed, .crossModelFailed): return true
        case (.checking, .checking): return true
        default: return false
        }
    }
}

// MARK: - HTTP Session Abstraction (Tier 2 PR D)

/// Minimal protocol that captures the single `URLSession` method the service
/// uses. Makes `CrossModelVerificationService` testable by allowing tests to
/// inject a mock session that controls failures, status codes, and latency.
protocol HTTPSession: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: HTTPSession {}

// MARK: - Cross-Model Verification Service

/// The one behaviour callers depend on. Extracted so UI tests can substitute an
/// in-process implementation — this service is reached via `.shared` rather than
/// constructor injection, so there was previously no seam at all.
protocol CrossModelVerifying {
    func verify(
        exercises: [(name: String, condition: String)],
        patientContext: String
    ) async throws -> [CrossModelResult]
}

class CrossModelVerificationService: CrossModelVerifying {
    static let shared = CrossModelVerificationService()

    /// Mirrors `ClaudeAPIService.resolved`: the stub under `--uitesting --stub-ai`, the
    /// real singleton otherwise. Stripped to `shared` in release.
    static var resolved: CrossModelVerifying {
        #if DEBUG
        if TestDataSeeder.isUITesting && TestDataSeeder.shouldStubAI {
            return StubCrossModelVerificationService.shared
        }
        #endif
        return shared
    }

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.pthelper", category: "crossModel")
    private let crossVerifyURL = "https://us-central1-pt-helper-dev.cloudfunctions.net/crossVerify"

    /// Injectable HTTP session. Defaults to `URLSession.shared` in production;
    /// tests supply a mock implementation.
    private let session: HTTPSession

    /// Delay between retry attempts. Production uses exponential backoff
    /// 1 s / 2 s / 4 s; tests inject zero delays so they don't drag.
    private let retryDelays: [Duration]

    /// Default production retry schedule — 3 total attempts.
    /// Index i is the delay BEFORE attempt (i+1), so attempt 1 has no pre-delay.
    static let defaultRetryDelays: [Duration] = [.seconds(1), .seconds(2), .seconds(4)]

    /// Production initializer — uses `URLSession.shared` and default retry delays.
    private init() {
        self.session = URLSession.shared
        self.retryDelays = Self.defaultRetryDelays
    }

    /// Testable initializer. Internal visibility so `@testable import`
    /// can reach it without exposing to app code.
    internal init(session: HTTPSession, retryDelays: [Duration]) {
        self.session = session
        self.retryDelays = retryDelays
    }

    /// Maximum exercises per request (server enforces max 20).
    private let maxBatchSize = 20

    /// Verify unverified exercises against a second AI model (GPT-4o-mini).
    /// Automatically batches into chunks of 20 if needed.
    func verify(
        exercises: [(name: String, condition: String)],
        patientContext: String
    ) async throws -> [CrossModelResult] {
        guard !exercises.isEmpty else { return [] }

        logger.info("Cross-model verification requested for \(exercises.count) exercise(s)")

        // Split into batches of maxBatchSize to stay within server limit
        var allResults: [CrossModelResult] = []
        let batches = stride(from: 0, to: exercises.count, by: maxBatchSize).map {
            Array(exercises[$0..<min($0 + maxBatchSize, exercises.count)])
        }

        logger.info("Splitting into \(batches.count) batch(es)")
        for (index, batch) in batches.enumerated() {
            logger.debug("Sending batch \(index + 1)/\(batches.count) with \(batch.count) exercise(s)")
            // Tier 2 PR D: each batch goes through the retry wrapper, not raw
            // sendBatch. A transient network blip on batch 2/3 won't now lose
            // the whole verification for all exercises.
            let batchResults = try await sendBatchWithRetry(exercises: batch, patientContext: patientContext)
            allResults.append(contentsOf: batchResults)
        }

        logger.info("Cross-model verification complete: \(allResults.filter { $0.isSafe }.count) safe, \(allResults.filter { !$0.isSafe }.count) flagged")
        return allResults
    }

    // MARK: - Retry wrapper (Tier 2 PR D)

    /// Wraps `sendBatch` with exponential-backoff retry on transient errors.
    ///
    /// Retry policy:
    /// - Attempts: up to `retryDelays.count` (default 3).
    /// - Back-off: pre-delay from `retryDelays[attemptIndex]` before each
    ///   attempt EXCEPT the first.
    /// - Retried: `networkError` + `serverError(5xx)`.
    /// - NOT retried: `authenticationRequired`, `invalidURL`, 4xx server
    ///   errors, `decodingError`, `invalidResponse` — these won't succeed
    ///   on retry and would just waste the user's time.
    ///
    /// On exhausting all attempts, rethrows the last error. The caller
    /// (`RehabPlanViewModel.performCrossModelVerification`) catches and marks
    /// every exercise in `unverified` as `.crossModelFailed`, which Tier 2
    /// PR D routes through `SeriousWarningModal` via `.serious` severity.
    private func sendBatchWithRetry(
        exercises: [(name: String, condition: String)],
        patientContext: String
    ) async throws -> [CrossModelResult] {
        try await Self.withRetry(delays: retryDelays, logger: logger) {
            try await self.sendBatch(exercises: exercises, patientContext: patientContext)
        }
    }

    /// Pure retry helper. Extracted from `sendBatchWithRetry` so tests can
    /// verify retry/backoff/error-classification behavior without needing
    /// Firebase auth or live network.
    ///
    /// - Parameters:
    ///   - delays: one entry per attempt. `delays[0]` is ignored (first attempt
    ///     has no pre-delay); `delays[i>0]` is the pause before attempt (i+1).
    ///     The COUNT of `delays` is the total attempt ceiling.
    ///   - logger: optional OSLog logger for attempt-level breadcrumbs.
    ///   - operation: the throwing async closure to run.
    /// - Returns: the successful operation result.
    /// - Throws: the last retryable error if all attempts failed, OR
    ///   immediately rethrows any non-retryable error (per `isRetryable(_:)`).
    static func withRetry<T>(
        delays: [Duration],
        logger: Logger? = nil,
        operation: () async throws -> T
    ) async throws -> T {
        precondition(!delays.isEmpty, "withRetry requires at least one attempt")

        var lastError: Error = CrossModelError.networkError(
            NSError(domain: "CrossModel", code: -999,
                    userInfo: [NSLocalizedDescriptionKey: "No attempt was made"])
        )

        for attemptIndex in 0..<delays.count {
            if attemptIndex > 0 {
                let delay = delays[attemptIndex]
                logger?.debug("Retry attempt \(attemptIndex + 1)/\(delays.count) after \(String(describing: delay))")
                try? await Task.sleep(for: delay)
            }

            do {
                return try await operation()
            } catch let error as CrossModelError where Self.isRetryable(error) {
                lastError = error
                logger?.warning("Cross-model attempt \(attemptIndex + 1)/\(delays.count) failed with retryable error: \(error.localizedDescription)")
                continue
            } catch {
                // Non-retryable — rethrow immediately, don't consume attempts.
                logger?.error("Cross-model non-retryable error: \(error.localizedDescription)")
                throw error
            }
        }

        logger?.error("Cross-model exhausted \(delays.count) retry attempts; final error: \(lastError.localizedDescription)")
        throw lastError
    }

    /// Which errors are worth retrying. Transient network and 5xx: yes.
    /// Everything else: no — subsequent attempts would fail the same way.
    static func isRetryable(_ error: CrossModelError) -> Bool {
        switch error {
        case .networkError:
            return true
        case .serverError(let code):
            return code >= 500
        case .invalidURL, .authenticationRequired, .invalidResponse, .decodingError:
            return false
        }
    }

    /// Send a single batch (max 20) to the crossVerify endpoint.
    ///
    /// Internal (not private) so `CrossModelVerificationRetryTests` can
    /// exercise the retry wrapper via `verify()` end-to-end; kept at the
    /// smallest possible scope otherwise.
    private func sendBatch(
        exercises: [(name: String, condition: String)],
        patientContext: String
    ) async throws -> [CrossModelResult] {
        guard let url = URL(string: crossVerifyURL) else {
            logger.error("Invalid crossVerify URL")
            throw CrossModelError.invalidURL
        }

        // Get Firebase Auth token
        guard let currentUser = Auth.auth().currentUser else {
            throw CrossModelError.authenticationRequired
        }

        let idToken: String
        do {
            idToken = try await currentUser.getIDToken()
        } catch {
            throw CrossModelError.authenticationRequired
        }

        // Build request
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let exercisesPayload = exercises.map { exercise in
            ["name": exercise.name, "condition": exercise.condition]
        }

        let body: [String: Any] = [
            "exercises": exercisesPayload,
            "patientContext": patientContext
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        // Make request. Uses the injected HTTPSession so tests can stub
        // network responses without hitting the real endpoint.
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            logger.error("Cross-model network error: \(error.localizedDescription)")
            throw CrossModelError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw CrossModelError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            logger.error("Cross-model error (\(httpResponse.statusCode)): \(errorBody)")
            throw CrossModelError.serverError(httpResponse.statusCode)
        }

        // Parse response
        return try parseCrossModelResponse(data, exercises: exercises)
    }

    // MARK: - Response Parsing

    /// Internal rather than private so the response-mapping logic is testable. `verify` and
    /// `sendBatch` require a signed-in Firebase user before any network call, so they throw
    /// `.authenticationRequired` in a unit-test process — this is the only reachable seam
    /// for asserting on how the two response shapes are decoded.
    func parseCrossModelResponse(_ data: Data, exercises: [(name: String, condition: String)]) throws -> [CrossModelResult] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CrossModelError.decodingError
        }

        // Handle single exercise response. Gated on a single requested exercise:
        // a bare top-level object carries no identity, so accepting it for a
        // multi-exercise batch would attribute one verdict to the first exercise
        // and silently drop the rest.
        if let safe = json["safe"] as? Bool {
            guard exercises.count == 1, let firstExercise = exercises.first else {
                logger.error("Cross-model returned a single-object response for \(exercises.count) exercises — rejecting")
                throw CrossModelError.decodingError
            }
            return [CrossModelResult(
                exerciseName: firstExercise.name,
                conditionName: firstExercise.condition,
                isSafe: safe,
                confidence: json["confidence"] as? Double ?? 0.5,
                reasoning: json["reasoning"] as? String ?? "",
                concerns: json["concerns"] as? [String] ?? []
            )]
        }

        // Handle batched response
        guard let results = json["results"] as? [[String: Any]] else {
            throw CrossModelError.decodingError
        }

        // Verdicts are paired to exercises POSITIONALLY, so a response that
        // drops, adds or reorders an entry silently attributes a safety verdict
        // to the wrong exercise — `zip` would truncate to the shorter side and
        // shift everything after the omission. The server now validates and
        // re-orders by an echoed 1-based `index`; these guards are the client's
        // own fail-closed check, because a wrong verdict is worse than none.
        guard results.count == exercises.count else {
            logger.error("Cross-model result count \(results.count) != \(exercises.count) requested — rejecting")
            throw CrossModelError.decodingError
        }

        // Honour the echoed index when present (accepting a stringified number,
        // which some models emit), and fail closed on anything malformed rather
        // than defaulting — a silently defaulted index would reintroduce exactly
        // the misattribution these guards exist to prevent.
        var ordered = results
        if results.contains(where: { $0["index"] != nil }) {
            var byIndex = [Int: [String: Any]]()
            for result in results {
                let parsedIndex: Int?
                if let value = result["index"] as? Int {
                    parsedIndex = value
                } else if let text = result["index"] as? String, let value = Int(text) {
                    parsedIndex = value
                } else {
                    parsedIndex = nil
                }
                guard let index = parsedIndex, (1...exercises.count).contains(index), byIndex[index] == nil else {
                    logger.error("Cross-model response carried a missing/duplicate/out-of-range index — rejecting")
                    throw CrossModelError.decodingError
                }
                byIndex[index] = result
            }
            ordered = (1...exercises.count).compactMap { byIndex[$0] }
            guard ordered.count == exercises.count else {
                throw CrossModelError.decodingError
            }
        }

        return zip(ordered, exercises).map { (result, exercise) in
            CrossModelResult(
                exerciseName: exercise.name,
                conditionName: exercise.condition,
                isSafe: result["safe"] as? Bool ?? false,
                confidence: result["confidence"] as? Double ?? 0.5,
                reasoning: result["reasoning"] as? String ?? "",
                concerns: result["concerns"] as? [String] ?? []
            )
        }
    }
}

// MARK: - Cross-Model Errors

enum CrossModelError: LocalizedError {
    case invalidURL
    case authenticationRequired
    case networkError(Error)
    case invalidResponse
    case serverError(Int)
    case decodingError

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid verification service URL."
        case .authenticationRequired: return "Authentication required for verification."
        case .networkError(let error): return "Network error during verification: \(error.localizedDescription)"
        case .invalidResponse: return "Invalid response from verification service."
        case .serverError(let code): return "Verification service error (status \(code))."
        case .decodingError: return "Failed to parse verification response."
        }
    }
}
