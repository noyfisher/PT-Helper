import Foundation
import os
import FirebaseAuth
import FirebaseFirestore

// MARK: - Validation Severity (top-level, Comparable)

/// Severity of a validation finding. Ordered: info < caution < serious < urgent < emergency.
///
/// Tier 1 meaning:
/// - `.info`     — purely informational (e.g. "very high AI confidence, interpret with caution").
/// - `.caution`  — advisory; shown inline. Examples: age ≥ 65 + advanced exercise, unverified-by-KG.
/// - `.serious`  — contraindication requiring explicit user acknowledgement before plan display.
///                 Examples: osteoporosis + impact, blood-thinners + balance, KG-contraindicated substitute.
/// - `.urgent`   — condition-level red flag (AI-flagged red-flag condition without a message, etc.).
/// - `.emergency`— symptom-level red flag requiring immediate medical referral.
///                 Examples: cardiac pattern, cauda equina, stroke signs, DVT signs.
///
/// UI treatment (`AnalyzingView` / `RehabPlanView`):
/// - `.emergency` → redirect to `EmergencyRedirectView` (no normal result shown).
/// - `.serious`   → `SeriousWarningModal` acknowledgement gate (gated behind feature flag).
/// - `.urgent`    → inline warning banner (existing behavior).
/// - `.caution`   → inline badge.
/// - `.info`      → inline badge.
enum ValidationSeverity: Int, Comparable {
    case info = 0
    case caution = 1
    case serious = 2
    case urgent = 3
    case emergency = 4

    static func < (lhs: ValidationSeverity, rhs: ValidationSeverity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - Validation Result

struct ValidationResult {
    let isValid: Bool
    let warnings: [ValidationWarning]
    let appliedFixes: [String]

    var hasWarnings: Bool { !warnings.isEmpty }

    /// Highest severity across all warnings, or `.info` if no warnings.
    /// Used to drive navigation routing (emergency redirect vs. serious modal vs. inline display).
    var worstSeverity: ValidationSeverity {
        warnings.map(\.severity).max() ?? .info
    }
}

struct ValidationWarning {
    /// Source-compat alias so existing `ValidationWarning.Severity` references keep working.
    typealias Severity = ValidationSeverity

    let severity: ValidationSeverity
    let message: String
}

// MARK: - Confidence Calibration

enum MatchStrength: String {
    case strong = "Strong Match"
    case moderate = "Possible Match"
    case weak = "Less Likely"

    var color: String {
        switch self {
        case .strong: return "green"
        case .moderate: return "orange"
        case .weak: return "gray"
        }
    }
}

struct ConfidenceCalibrator {
    /// Maximum confidence we display — even expert doctors are ~70-80% accurate.
    static let maxDisplayConfidence: Double = 85.0

    /// Clamp and calibrate a raw AI confidence score.
    static func calibrate(_ rawConfidence: Double) -> Double {
        min(max(rawConfidence, 0), maxDisplayConfidence)
    }

    /// Convert numeric confidence to a human-friendly strength label.
    static func matchStrength(for confidence: Double) -> MatchStrength {
        let calibrated = calibrate(confidence)
        switch calibrated {
        case 65...: return .strong
        case 35...: return .moderate
        default:    return .weak
        }
    }
}

// MARK: - Condition Retention Policy

/// Decides which conditions survive to the user.
///
/// This rule used to live as two independent `prefix(3)` calls — one in
/// `InjuryAnalyzer.synthesize()` and one in `validateAnalysis` step 5 — and both
/// ranked red flags *against* the benign differential on a confidence scale where
/// red flags structurally lose (a possible DVT scores 15-35; benign conditions
/// score 60-85). So `synthesize()`'s "safety preservation" step would re-add a red
/// flag the verification pass had dropped, log that it had done so, and then
/// discard it again on the very next line. The drift between the two copies is the
/// bug, so the rule lives here once and both sites call it.
///
/// Red flags ride *alongside* the ranked head rather than competing for a slot:
/// displacing a real differential buys nothing (every red-flag UI surface scans the
/// full array), and flooring a red flag's confidence to make it rank would render
/// "Strong match" in green next to a suspected blood clot.
struct ConditionRetentionPolicy {
    /// How many conditions form the ranked differential shown as cards.
    static let maxRankedConditions = 3
    /// Ceiling on rescued red flags, so a pathological response can't balloon the
    /// list. Not expected to bite (responses carry 0-1); over-cap drops are logged.
    static let maxRescuedRedFlags = 3

    struct Retention {
        let conditions: [ConditionResult]
        let rescuedRedFlagCount: Int
        let droppedRedFlagCount: Int
    }

    /// Keep the first `maxRankedConditions` of an **already-ordered** list, then
    /// append any red flag from the tail that would otherwise be truncated.
    ///
    /// Deliberately does not re-sort. The head is preserved verbatim so
    /// `conditions.first` (the Progress tab's "last analysis" headline) and the card
    /// order are byte-identical for every result that isn't currently losing a red
    /// flag — that minimum-diff property is what makes this safe to ship as a P0.
    static func retain(_ ordered: [ConditionResult]) -> Retention {
        let head = Array(ordered.prefix(maxRankedConditions))
        let rescuable = ordered.dropFirst(maxRankedConditions).filter { $0.isRedFlag }
        let rescued = Array(rescuable.prefix(maxRescuedRedFlags))
        return Retention(
            conditions: head + rescued,
            rescuedRedFlagCount: rescued.count,
            droppedRedFlagCount: rescuable.count - rescued.count
        )
    }
}

// MARK: - Analysis Content Validator

struct AnalysisContentValidator {

    static func validate(_ result: AnalysisResult) -> ValidationResult {
        var warnings: [ValidationWarning] = []
        var fixes: [String] = []

        // 1. Condition count: should be 1-3
        if result.conditions.isEmpty {
            warnings.append(ValidationWarning(severity: .caution, message: "No possible explanations were identified. Consider consulting a healthcare provider for an in-person assessment."))
        }
        // Report the trim the retention policy will actually perform. A flat
        // "trimmed to 3" would be a lie once a red flag is preserved past the head.
        let retainedCount = ConditionRetentionPolicy.retain(result.conditions).conditions.count
        if retainedCount < result.conditions.count {
            fixes.append("Trimmed conditions from \(result.conditions.count) to \(retainedCount)")
        }

        // 2. Confidence score validation
        for condition in result.conditions {
            if condition.confidence < 0 || condition.confidence > 100 {
                fixes.append("Clamped out-of-range confidence for \(condition.commonName)")
            }
            if condition.confidence >= 95 {
                warnings.append(ValidationWarning(severity: .info, message: "Very high match scores should be interpreted with caution. Even healthcare professionals may not reach this level of certainty without imaging or lab tests."))
            }
        }

        // 3. Red flag consistency: if isRedFlag, must have a message
        for condition in result.conditions {
            if condition.isRedFlag && (condition.redFlagMessage == nil || condition.redFlagMessage?.isEmpty == true) {
                warnings.append(ValidationWarning(severity: .urgent, message: "\(condition.commonName) was flagged as potentially serious. Please consult a healthcare provider promptly."))
            }
        }

        // 4. Duplicate detection
        let names = result.conditions.map { $0.conditionName.lowercased() }
        if Set(names).count < names.count {
            fixes.append("Duplicate conditions detected and would be removed")
        }

        // 5. Summary present and non-empty
        if result.overallSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            warnings.append(ValidationWarning(severity: .caution, message: "The analysis summary was empty."))
        }

        let isValid = warnings.filter({ $0.severity >= .serious }).isEmpty
        return ValidationResult(isValid: isValid, warnings: warnings, appliedFixes: fixes)
    }
}

// MARK: - Medical Red Flag Detector

struct MedicalRedFlagDetector {

    struct RedFlagResult {
        let triggered: Bool
        let alerts: [ValidationWarning]
    }

    /// Symptom combination patterns that ALWAYS require urgent care referral,
    /// regardless of what the AI returns.
    ///
    /// Severity classification (Tier 1):
    /// - `.emergency` — 911-level: cardiac, stroke, meningitis, cauda equina, DVT. These trigger
    ///                  `EmergencyRedirectView` and the normal analysis result is NOT shown.
    /// - `.urgent`    — ER/provider visit but not 911-level: suspected fracture. Shown as a banner.
    private static let symptomPatterns: [(keywords: [String], region: String?, severity: ValidationSeverity, message: String)] = [
        // Cardiac — 911
        (["chest pain", "shortness of breath"],
         "chest",
         .emergency,
         "Chest pain with difficulty breathing may indicate a cardiac emergency. Please call 911 or go to the ER immediately."),

        // Stroke — 911
        (["sudden weakness", "numbness", "one side"],
         nil,
         .emergency,
         "Sudden weakness or numbness on one side could be signs of a stroke. Please call 911 immediately."),

        // Meningitis — ER
        (["severe headache", "stiff neck", "fever"],
         nil,
         .emergency,
         "A severe headache with neck stiffness and fever could indicate meningitis. Seek emergency medical care."),

        // Cauda Equina Syndrome — ER
        (["loss of bladder", "back pain", "leg weakness"],
         "lower_back",
         .emergency,
         "Loss of bladder or bowel control with back pain and leg weakness may indicate cauda equina syndrome. This is a medical emergency — go to the ER immediately."),

        (["saddle numbness", "back pain"],
         "lower_back",
         .emergency,
         "Numbness in the saddle area with back pain may indicate cauda equina syndrome. This is a medical emergency."),

        // DVT — ER (blood clot risk)
        (["calf pain", "swelling", "redness"],
         nil,
         .emergency,
         "Calf pain with swelling and redness could indicate a blood clot (DVT). Please seek immediate medical attention."),

        // Fracture indicators — urgent provider visit, not 911
        (["deformity", "unable to bear weight"],
         nil,
         .urgent,
         "Visible deformity or inability to bear weight may indicate a fracture. Please seek medical evaluation."),
    ]

    /// Conditions that should NEVER be self-managed with home exercises alone.
    ///
    /// Sources: APTA red-flag screening checklists, Goodman & Snyder
    /// (Differential Diagnosis for Physical Therapists, 6th ed.),
    /// standard clinical red-flag screens.
    ///
    /// Tier 2 expansion (from 13 → 26 keywords). Additions target conditions
    /// that should route the user to a clinician rather than self-managed
    /// exercise, but were missing from the previous list.
    static let noSelfManageKeywords: Set<String> = [
        // Structural injury (original set)
        "fracture",
        "dislocation",
        "cauda equina",          // spinal-cord compression emergency
        "spinal cord",           // any spinal-cord involvement
        "compartment syndrome",  // vascular compromise
        "avascular necrosis",    // bone infarction

        // Infection (original set + additions)
        "infection",
        "septic",                // covers "septic joint" via substring match
        "osteomyelitis",         // bone infection

        // Oncologic (original)
        "tumor",
        "cancer",

        // Vascular (original)
        "dvt",                   // deep vein thrombosis
        "embolism",

        // Neurologic (Tier 2 additions — APTA red-flag screen)
        "neuropathy",            // peripheral neuropathy: sensory/motor deficit
        "radiculopathy",         // nerve-root compression symptoms
        "myelopathy",            // spinal-cord dysfunction

        // Structural instability (Tier 2 additions)
        "subluxation",           // partial dislocation
        "ligament rupture",      // complete ligament tear
        "tendon rupture",        // complete tendon tear
        "complete labral tear",  // labral disruption requiring imaging/surgical eval

        // Pain syndromes that need medical workup (Tier 2 additions)
        "fibromyalgia",                     // requires medical management
        "crps",                             // complex regional pain syndrome
        "complex regional pain syndrome",
        "reflex sympathetic dystrophy",     // older name for CRPS type I

        // Inflammatory flares requiring meds (Tier 2 additions)
        "rheumatoid flare",                 // RA exacerbation
        "gout flare",                       // acute gout attack
    ]

    /// Check assessments for hardcoded red flag patterns.
    static func check(assessments: [PainAssessment]) -> RedFlagResult {
        var alerts: [ValidationWarning] = []

        // High pain intensity check
        for assessment in assessments {
            if assessment.painIntensity >= 9 && assessment.painOnsets.contains("Sudden") {
                alerts.append(ValidationWarning(
                    severity: .urgent,
                    message: "You reported very severe (\(assessment.painIntensity)/10) pain in your \(assessment.selectedRegion.name) with sudden onset. With pain this severe, we strongly recommend seeing a healthcare provider before starting any exercise program."
                ))
            } else if assessment.painIntensity >= 9 {
                alerts.append(ValidationWarning(
                    severity: .caution,
                    message: "You reported very severe pain (\(assessment.painIntensity)/10) in your \(assessment.selectedRegion.name). Please consult a healthcare provider if this pain does not improve."
                ))
            }
        }

        // Symptom pattern matching from aggravating factors, notes, and custom descriptions
        let allText = assessments.flatMap { assessment in
            var texts = assessment.aggravatingFactors + assessment.relievingFactors
            if let notes = assessment.additionalNotes { texts.append(notes) }
            if let custom = assessment.customPainDescription { texts.append(custom) }
            return texts
        }.joined(separator: " ").lowercased()

        let regionKeys = assessments.map { $0.selectedRegion.zoneKey }

        for pattern in symptomPatterns {
            let allKeywordsMatch = pattern.keywords.allSatisfy { allText.contains($0) }
            let regionMatches: Bool
            if let region = pattern.region {
                regionMatches = regionKeys.contains(where: { $0.contains(region) })
            } else {
                regionMatches = true
            }

            if allKeywordsMatch && regionMatches {
                alerts.append(ValidationWarning(severity: pattern.severity, message: pattern.message))
            }
        }

        // Night pain + weight loss — suspicious for tumor/infection workup. Urgent provider visit
        // (not 911-level emergency).
        if allText.contains("night pain") && allText.contains("weight loss") {
            alerts.append(ValidationWarning(
                severity: .urgent,
                message: "Persistent night pain combined with unexplained weight loss needs medical evaluation to rule out serious conditions. Please see a doctor."
            ))
        }

        return RedFlagResult(triggered: !alerts.isEmpty, alerts: alerts)
    }

    /// Overload for the wellness flow: run the same 7-pattern symptom match on free-form
    /// strings (user goal descriptions, stated concerns, custom fields). The injury flow
    /// extracts these from `PainAssessment.aggravatingFactors` / `.relievingFactors` /
    /// `.additionalNotes`; the wellness flow has no such structure, so we accept the
    /// strings directly.
    ///
    /// Note: region-scoped patterns (e.g. cauda equina requires `"lower_back"` region)
    /// cannot fire from this entry point because wellness has no region data. That's the
    /// intended behavior — if a user types symptoms that match a region-bound pattern,
    /// they should be in the injury flow, not the wellness flow.
    static func check(symptomStrings: [String]) -> RedFlagResult {
        var alerts: [ValidationWarning] = []
        let allText = symptomStrings.joined(separator: " ").lowercased()

        for pattern in symptomPatterns where pattern.region == nil {
            let allKeywordsMatch = pattern.keywords.allSatisfy { allText.contains($0) }
            if allKeywordsMatch {
                alerts.append(ValidationWarning(severity: pattern.severity, message: pattern.message))
            }
        }

        if allText.contains("night pain") && allText.contains("weight loss") {
            alerts.append(ValidationWarning(
                severity: .urgent,
                message: "Persistent night pain combined with unexplained weight loss needs medical evaluation to rule out serious conditions. Please see a doctor."
            ))
        }

        return RedFlagResult(triggered: !alerts.isEmpty, alerts: alerts)
    }

    /// Check AI-returned conditions for dangerous self-management scenarios.
    static func checkConditions(_ conditions: [ConditionResult]) -> [ValidationWarning] {
        var alerts: [ValidationWarning] = []

        for condition in conditions {
            let nameLower = condition.conditionName.lowercased()
            let commonLower = condition.commonName.lowercased()

            for keyword in noSelfManageKeywords {
                if nameLower.contains(keyword) || commonLower.contains(keyword) {
                    // Ensure this is flagged as a red flag even if AI didn't do so
                    if !condition.isRedFlag {
                        alerts.append(ValidationWarning(
                            severity: .urgent,
                            message: "\(condition.commonName) is a condition that requires professional medical treatment. Please do not attempt to self-manage this with exercises alone."
                        ))
                    }
                    break
                }
            }
        }

        return alerts
    }

    /// Surface conditions the model itself marked as red flags as first-class alerts.
    ///
    /// Distinct from `checkConditions`, which is keyword-driven and deliberately
    /// emits nothing for an already-flagged condition (so the two don't double up on
    /// the same wording). That silence meant an AI-flagged condition never reached
    /// `redFlagAlerts`, which gates session-log upload, the has_red_flags analytic,
    /// and the persisted risk acknowledgement.
    ///
    /// Always `.urgent`, never `.emergency`: only `check(assessments:)` may emit
    /// `.emergency`, because `AnalyzingView` routes to the full-screen emergency
    /// takeover on that severity alone, and a condition-level flag must not seize
    /// the screen. `testValidateAnalysis_redFlaggedCondition_neverEmitsEmergency`
    /// pins this.
    static func alerts(forFlagged conditions: [ConditionResult]) -> [ValidationWarning] {
        conditions.filter { $0.isRedFlag }.map { condition in
            let message: String
            if let redFlagMessage = condition.redFlagMessage, !redFlagMessage.isEmpty {
                message = redFlagMessage
            } else {
                message = "\(condition.commonName) may be serious. Please see a healthcare provider before starting any exercise program."
            }
            return ValidationWarning(severity: .urgent, message: message)
        }
    }
}

// MARK: - Comorbidity Interaction Map (Tier 3 PR A)

/// Order-independent pair of condition IDs. Sorts on init so `(a,b)` and
/// `(b,a)` collide as the same key — interactions are symmetric.
struct OrderedPair: Hashable {
    let a: String
    let b: String

    init(_ x: String, _ y: String) {
        if x <= y {
            self.a = x
            self.b = y
        } else {
            self.a = y
            self.b = x
        }
    }
}

/// Loads `Resources/comorbidity_interactions.json` once at startup. Provides:
///   - `canonicalize(_:)` — maps free-text user condition strings to canonical
///     IDs (e.g., "PVD" → "peripheral_vascular_disease").
///   - `interactionExercises(for:)` — for a pair of canonicalized condition
///     IDs, returns the set of exercise-name keywords that should escalate to
///     `.serious` severity when both conditions are present.
///
/// Bundle-membership note: the Xcode project uses
/// `PBXFileSystemSynchronizedRootGroup` so the JSON file under `Resources/`
/// auto-discovers. If the resource is missing at runtime (CI bundle issue,
/// stripped artifact), the loader fails open — comorbidity checks become a
/// no-op rather than crashing. A DEBUG `assertionFailure` surfaces the
/// regression during development.
enum ComorbidityInteractionMap {

    fileprivate struct InteractionEntry: Decodable {
        let condition_a: String
        let condition_b: String
        let exercises: [String]
        let severity: String          // "serious" in v1; reserved for future tiers
        let source: String?
        let note: String?
    }

    fileprivate struct ComorbidityFile: Decodable {
        let version: String
        let aliases: [String: String]
        let interactions: [InteractionEntry]
    }

    private static let _logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.pthelper",
        category: "comorbidity"
    )

    private static let _state: (aliases: [String: String], interactions: [OrderedPair: Set<String>]) = load()

    private static var aliasMap: [String: String] { _state.aliases }
    private static var interactionLookup: [OrderedPair: Set<String>] { _state.interactions }

    private static func load() -> ([String: String], [OrderedPair: Set<String>]) {
        guard let url = Bundle.main.url(forResource: "comorbidity_interactions", withExtension: "json") else {
            _logger.error("comorbidity_interactions.json not in bundle — comorbidity checks will be a no-op")
            assertionFailure("comorbidity_interactions.json missing from bundle")
            return ([:], [:])
        }
        do {
            let data = try Data(contentsOf: url)
            let file = try JSONDecoder().decode(ComorbidityFile.self, from: data)
            // Filter out the "_NOTE" key from aliases (documentation-only).
            let aliases = file.aliases.filter { !$0.key.hasPrefix("_") }
            var lookup: [OrderedPair: Set<String>] = [:]
            for entry in file.interactions {
                let pair = OrderedPair(entry.condition_a, entry.condition_b)
                let normalized = Set(entry.exercises.map { $0.lowercased() })
                lookup[pair, default: []].formUnion(normalized)
            }
            _logger.info("Loaded comorbidity map (v\(file.version)): \(aliases.count) aliases, \(lookup.count) interaction pairs")
            return (aliases, lookup)
        } catch {
            _logger.error("Failed to parse comorbidity_interactions.json: \(error.localizedDescription)")
            assertionFailure("comorbidity_interactions.json parse error: \(error)")
            return ([:], [:])
        }
    }

    /// Map a free-text user condition string to a canonical ID.
    ///
    /// Matching strategy:
    ///   1. Normalize input — lowercase, trim, collapse whitespace.
    ///   2. Exact key lookup against the alias map.
    ///   3. Multi-word aliases (contain whitespace): substring containment
    ///      against the input. Safe because they're distinctive.
    ///   4. Single-word aliases: match only as a WHOLE TOKEN of the input.
    ///      Without this, short aliases like "ra" (rheumatoid arthritis) or
    ///      "pad" (peripheral artery disease) would incorrectly substring-
    ///      match unrelated inputs like "zebrafish" or "padding".
    ///   5. Longest matching alias wins (more specific = better).
    ///   6. Return nil on no match — caller logs to alias-miss telemetry.
    static func canonicalize(_ userCondition: String) -> String? {
        let normalized = userCondition
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard !normalized.isEmpty else { return nil }

        // 1. Exact match
        if let canonical = aliasMap[normalized] {
            return canonical
        }

        // 2 + 3. Token-level + multi-word substring match.
        let inputTokens = Set(
            normalized
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }
        )

        var bestMatch: (alias: String, canonical: String)? = nil
        for (alias, canonical) in aliasMap {
            // "Compound" = contains any non-alphanumeric (space, hyphen, etc.).
            // These aliases are inherently distinctive ("post-op", "history of mi")
            // and safe to substring-match.
            let aliasIsCompound = alias.contains { !$0.isLetter && !$0.isNumber }
            let matched: Bool
            if aliasIsCompound {
                matched = normalized.contains(alias) || alias.contains(normalized)
            } else {
                // Single-token alias: must appear as a whole token of the input.
                // Without this, "ra" would falsely match "zebrafish" via substring.
                matched = inputTokens.contains(alias)
            }
            if matched {
                if bestMatch == nil || alias.count > bestMatch!.alias.count {
                    bestMatch = (alias, canonical)
                }
            }
        }
        return bestMatch?.canonical
    }

    /// Exercise-name keywords that should fire a `.serious` warning when
    /// both conditions in `pair` are present. Empty set if the pair has no
    /// known interaction (the common case).
    static func interactionExercises(for pair: OrderedPair) -> Set<String> {
        interactionLookup[pair] ?? []
    }
}

/// Fire-and-forget Firestore counter for canonicalize() misses. Lets us
/// review monthly which user-entered condition strings aren't in the
/// alias map and decide whether to expand it. Auth-safe: no-op if no
/// authenticated user (cold start before sign-in).
enum ComorbidityAliasMissTelemetry {

    /// Doc ids already recorded in this process.
    ///
    /// `recordMiss` is reached from `ExerciseContraindicationChecker.validate`,
    /// which the image-substitution step calls once per *candidate* — potentially
    /// hundreds of catalog entries for a single exercise. Every candidate
    /// re-canonicalized the same user conditions, so one unmapped condition
    /// spawned a detached Firestore write per probe: a write flood on a hot loop,
    /// and a counter measuring how many candidates happened to be tried rather
    /// than how often the alias map actually missed.
    ///
    /// Deduping per process makes the metric the one that was intended — distinct
    /// unmapped conditions seen — and collapses the flood to one write each.
    private static var recorded = Set<String>()
    private static let recordedLock = NSLock()

    /// Returns true the first time this process sees `docId`.
    private static func claim(_ docId: String) -> Bool {
        recordedLock.lock()
        defer { recordedLock.unlock() }
        return recorded.insert(docId).inserted
    }

    static func recordMiss(condition: String) {
        let slug = condition
            .lowercased()
            .unicodeScalars
            .map { scalar -> String in
                if ("a"..."z").contains(String(scalar)) || ("0"..."9").contains(String(scalar)) {
                    return String(scalar)
                }
                return "-"
            }
            .joined()
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let docId = slug.isEmpty ? "_empty" : String(slug.prefix(100))

        guard claim(docId) else { return }

        Task.detached {
            await _record(docId: docId, original: condition)
        }
    }

    private static func _record(docId: String, original: String) async {
        guard Auth.auth().currentUser != nil else { return }
        do {
            try await Firestore.firestore()
                .collection("comorbidityAliasMisses")
                .document(docId)
                .setData([
                    "count": FieldValue.increment(Int64(1)),
                    "lastOriginal": String(original.prefix(200)),
                    "lastAt": FieldValue.serverTimestamp(),
                ], merge: true)
        } catch {
            // Swallow — telemetry must never block validation.
        }
    }
}

// MARK: - Exercise Contraindication Checker

struct ExerciseContraindicationChecker {

    /// Exercises that should NEVER be recommended for certain conditions.
    /// Key: lowercased keyword in condition name. Value: lowercased keywords in exercise name.
    private static let contraindicatedExercises: [String: Set<String>] = [
        "herniated disc": ["deadlift", "sit-up", "crunch", "good morning", "toe touch", "leg press"],
        "disc": ["deadlift", "sit-up", "crunch", "good morning"],
        "acl": ["deep squat", "plyometric", "cutting", "pivot", "jump squat", "box jump"],
        "rotator cuff": ["overhead press", "behind neck", "upright row", "behind-the-neck", "military press"],
        "impingement": ["overhead press", "behind neck", "upright row", "lateral raise above shoulder"],
        "frozen shoulder": ["forced stretch", "aggressive", "overhead press"],
        "fracture": ["impact", "jumping", "running", "plyometric", "heavy"],
        "osteoporosis": ["high impact", "jumping", "plyometric", "heavy deadlift", "twisting under load"],
        "spinal stenosis": ["extension", "back bend", "cobra", "overhead"],
        "sciatica": ["sit-up", "crunch", "toe touch", "seated forward fold"],
        "plantar fasciitis": ["jumping", "plyometric", "box jump", "running"],
        "carpal tunnel": ["wrist curl", "heavy grip"],
        "tennis elbow": ["wrist curl", "heavy grip", "pull-up"],
        "golfers elbow": ["wrist curl", "heavy grip", "chin-up"],
    ]

    /// Validate that no exercises are contraindicated for the diagnosed conditions.
    ///
    /// Tier 3 PR A: in addition to the existing single-condition check, this
    /// also runs a comorbidity interaction check. When the user has BOTH
    /// conditions in a known interaction pair (e.g. osteoporosis + balance
    /// disorder, blood-thinner + balance disorder), exercises matching the
    /// pair's blocked-keyword set get a `.serious` warning EVEN IF neither
    /// condition alone would block them. This is the core gap Tier 3 closes:
    /// real patients have comorbidities, and risks compound.
    static func validate(exercises: [RehabExercise], conditions: [String]) -> [ValidationWarning] {
        var warnings: [ValidationWarning] = []

        let conditionsLower = conditions.map { $0.lowercased() }

        // ---- Single-condition checks (existing behavior) ----
        for exercise in exercises {
            let exerciseLower = exercise.name.lowercased()

            for (conditionKeyword, blockedExercises) in contraindicatedExercises {
                // Spelling-tolerant on both sides. Plain `contains` meant the
                // hyphenated table entries silently missed the spellings the model
                // actually emits — "Sit Ups" and "Situps" both slipped past
                // `"sit-up"`, and for a herniated disc this table is the only
                // deterministic gate (the v1 knowledge graph lists no sit-up entry
                // for it at all). Word order is tolerated too, so `"jump squat"`
                // catches "Squat Jumps". Single-token entries such as `"extension"`
                // keep plain substring semantics, so nothing widens accidentally.
                let conditionMatches = conditionsLower.contains(where: {
                    TermMatching.containsTerm(conditionKeyword, in: $0)
                })
                guard conditionMatches else { continue }

                let exerciseBlocked = TermMatching.containsAnyTerm(blockedExercises, in: exerciseLower)
                if exerciseBlocked {
                    // Tier 1 severity: contraindicated exercises against a user's condition are
                    // `.serious` — the user must acknowledge the risk before the plan is shown,
                    // OR request a safer plan. Previously this was `.caution` and silently passed
                    // through as an inline note.
                    warnings.append(ValidationWarning(
                        severity: .serious,
                        message: "\"\(exercise.name)\" may not be appropriate given your condition. Please consult a physical therapist before attempting this exercise."
                    ))
                }
            }
        }

        // ---- Tier 3 PR A: comorbidity interaction check ----
        warnings.append(contentsOf: comorbidityWarnings(exercises: exercises, conditions: conditions))

        return warnings
    }

    /// Comorbidity-pair check. Canonicalizes user conditions, then for every
    /// unordered pair of canonicalized conditions, looks up the interaction
    /// map and emits a `.serious` warning per matching exercise.
    ///
    /// Internal so `ComorbidityInteractionTests` can drive it directly.
    static func comorbidityWarnings(
        exercises: [RehabExercise],
        conditions: [String]
    ) -> [ValidationWarning] {
        // Canonicalize everything once. Misses go to telemetry — they're not
        // errors, just opportunities to expand the alias map.
        var canonical: [String] = []
        for original in conditions {
            if let canon = ComorbidityInteractionMap.canonicalize(original) {
                canonical.append(canon)
            } else {
                ComorbidityAliasMissTelemetry.recordMiss(condition: original)
            }
        }
        // Dedupe — same user can list the same condition twice in different
        // wording (e.g. "PVD" + "peripheral vascular disease" → both map to
        // peripheral_vascular_disease).
        let unique = Array(Set(canonical))
        guard unique.count >= 2 else { return [] }

        var warnings: [ValidationWarning] = []
        // Track (exercise.id, pair-key) so we don't double-warn on the same
        // exercise when multiple pairs match.
        var emittedKeys: Set<String> = []

        for i in 0..<unique.count {
            for j in (i + 1)..<unique.count {
                let pair = OrderedPair(unique[i], unique[j])
                let blocked = ComorbidityInteractionMap.interactionExercises(for: pair)
                guard !blocked.isEmpty else { continue }

                for exercise in exercises {
                    let exerciseLower = exercise.name.lowercased()
                    let matched = blocked.contains(where: { exerciseLower.contains($0) })
                    guard matched else { continue }

                    let key = "\(exercise.id.uuidString)|\(pair.a)|\(pair.b)"
                    if emittedKeys.contains(key) { continue }
                    emittedKeys.insert(key)

                    warnings.append(ValidationWarning(
                        severity: .serious,
                        message: "\"\(exercise.name)\" may not be appropriate given your combination of \(humanize(pair.a)) and \(humanize(pair.b)). The combined risk is higher than either condition alone — please consult your physical therapist before attempting this exercise."
                    ))
                }
            }
        }

        return warnings
    }

    /// Convert a canonical ID like "peripheral_vascular_disease" to the
    /// human form "peripheral vascular disease" for warning messages.
    private static func humanize(_ canonicalID: String) -> String {
        canonicalID.replacingOccurrences(of: "_", with: " ")
    }

    /// Validate exercise parameter ranges are reasonable.
    ///
    /// Tier 2: also parses and range-checks `reps`. `reps` is a `String` on
    /// `RehabExercise` because the AI emits varied formats — "10", "10-15",
    /// "Hold 30s", "As needed", etc. Each shape is parsed separately:
    /// - numeric reps → clamp 1–30 warning
    /// - rep range "N-M" → flag if BOTH endpoints are out of 1–30 (the
    ///   "30-40" case is legitimate — low end is fine)
    /// - duration in seconds → clamp 5–120 warning
    /// - unrecognized spec → silent telemetry, NOT a user-visible caution
    ///   (wellness plans commonly use "As needed"/"Daily"/"As tolerated").
    /// Safe therapeutic bands. Values outside these are corrected, not just noted.
    static let setsRange = 1...10
    static let restSecondsRange = 0...300

    /// Validates exercise parameters and CLAMPS the numeric ones into their safe
    /// band, returning the corrected exercises alongside a description of every
    /// correction applied.
    ///
    /// This previously only appended advisory strings and returned nothing: the
    /// pipeline reported "has unusual sets count: 15" as an `.info` badge while
    /// shipping the 15 sets to the user unchanged. A range check that names the
    /// problem and then prescribes it anyway is not a safety control. The server
    /// schema is no backstop either — it bounds only nonsense (see
    /// response-schemas.ts), because a rejection there loses the whole plan.
    ///
    /// `reps` is deliberately NOT clamped: it is a free-form spec string
    /// ("8-12", "30 seconds", "As tolerated"), and rewriting it risks changing
    /// the meaning of a prescription rather than bounding it. Out-of-band rep
    /// specs stay advisory.
    static func validateParameters(_ exercises: [RehabExercise]) -> (exercises: [RehabExercise], fixes: [String]) {
        var fixes: [String] = []
        var corrected = exercises

        for index in corrected.indices {
            let exercise = corrected[index]

            if !setsRange.contains(exercise.sets) {
                let clamped = min(max(exercise.sets, setsRange.lowerBound), setsRange.upperBound)
                fixes.append("Adjusted \"\(exercise.name)\" from \(exercise.sets) sets to \(clamped) — outside the safe range.")
                corrected[index].sets = clamped
            }
            if !restSecondsRange.contains(exercise.restSeconds) {
                let clamped = min(max(exercise.restSeconds, restSecondsRange.lowerBound), restSecondsRange.upperBound)
                fixes.append("Adjusted rest for \"\(exercise.name)\" from \(exercise.restSeconds)s to \(clamped)s — outside the safe range.")
                corrected[index].restSeconds = clamped
            }

            switch RepSpecParser.parse(exercise.reps) {
            case .reps(let n):
                if n < 1 || n > 30 {
                    fixes.append("Exercise \"\(exercise.name)\" has unusual rep count: \(n)")
                }
            case .repsRange(let low, let high):
                // Only flag when BOTH endpoints fall outside the reasonable band.
                // A spec like "30-40" has a legitimate low end — don't false-clamp.
                if (low < 1 && high < 1) || (low > 30 && high > 30) {
                    fixes.append("Exercise \"\(exercise.name)\" has unusual rep range: \(low)-\(high)")
                }
            case .duration(let seconds):
                if seconds < 5 || seconds > 120 {
                    fixes.append("Exercise \"\(exercise.name)\" has unusual hold duration: \(seconds)s")
                }
            case .unknown:
                // Telemetry-only — don't flood the UI with warnings on
                // "As needed" / "Daily" / "As tolerated" wellness specs.
                RepSpecTelemetry.recordUnknown(exerciseName: exercise.name, rawSpec: exercise.reps)
            }
        }

        return (corrected, fixes)
    }
}

// MARK: - Rep Spec Parsing (Tier 2)

/// Result of parsing a `RehabExercise.reps` string. The AI returns this field
/// in multiple shapes depending on exercise type, so we classify it.
enum RepSpecResult: Equatable {
    /// A single numeric rep count, e.g. "10".
    case reps(Int)
    /// A rep range, e.g. "10-15" or "10 to 15" or "10–15".
    case repsRange(low: Int, high: Int)
    /// A time-held duration, e.g. "Hold 30s", "30 seconds", "Hold 3 minutes".
    /// Normalized to seconds.
    case duration(seconds: Int)
    /// Non-numeric spec, e.g. "As needed", "Daily", "As tolerated".
    case unknown
}

/// Pure parser for AI-emitted rep specs. Ordering matters — duration match
/// runs first because strings like "Hold 30s" contain a leading digit that
/// would otherwise parse as a rep count.
enum RepSpecParser {
    static func parse(_ raw: String) -> RepSpecResult {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .unknown }

        // 1. Duration form: "(N) (s|sec|second|seconds|min|minute|minutes|m)"
        //    — NOT required to be at start of string ("Hold 30 seconds" works).
        let durationRegex = try? NSRegularExpression(
            pattern: #"(\d+)\s*(m\b|mins?|minutes?|s\b|secs?|seconds?)"#,
            options: [.caseInsensitive]
        )
        if let regex = durationRegex,
           let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
           match.numberOfRanges == 3,
           let numRange = Range(match.range(at: 1), in: trimmed),
           let unitRange = Range(match.range(at: 2), in: trimmed),
           let num = Int(trimmed[numRange]) {
            let unit = trimmed[unitRange].lowercased()
            let seconds = unit.hasPrefix("m") ? num * 60 : num
            return .duration(seconds: seconds)
        }

        // 2. Rep range form: "N-M", "N to M", "N–M" (en dash), "N — M" (em dash)
        let rangeRegex = try? NSRegularExpression(
            pattern: #"^\s*(\d+)\s*(?:-|–|—|to)\s*(\d+)\s*$"#,
            options: [.caseInsensitive]
        )
        if let regex = rangeRegex,
           let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
           match.numberOfRanges == 3,
           let lowRange = Range(match.range(at: 1), in: trimmed),
           let highRange = Range(match.range(at: 2), in: trimmed),
           let low = Int(trimmed[lowRange]),
           let high = Int(trimmed[highRange]) {
            return .repsRange(low: low, high: high)
        }

        // 3. Bare numeric form: "10" (with optional surrounding whitespace).
        let intRegex = try? NSRegularExpression(pattern: #"^\s*(\d+)\s*$"#)
        if let regex = intRegex,
           let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
           match.numberOfRanges == 2,
           let numRange = Range(match.range(at: 1), in: trimmed),
           let num = Int(trimmed[numRange]) {
            return .reps(num)
        }

        return .unknown
    }
}

/// Fire-and-forget Firestore counter for unknown rep-spec shapes. The plan
/// intentionally does NOT surface these as user-visible warnings — wellness
/// plans routinely use "As needed" / "Daily" / "As tolerated". Instead we
/// count them centrally so we can decide later whether to expand the parser
/// or tighten the server prompt.
///
/// Runs from a detached `Task` so it never blocks validation. Auth-safe: if
/// `Auth.auth().currentUser` is nil (cold-start before sign-in completes),
/// the write is skipped to avoid a permission-denied error.
enum RepSpecTelemetry {
    static func recordUnknown(exerciseName: String, rawSpec: String) {
        // Slugify to a safe Firestore doc-id: lowercased, letters/digits/hyphen only.
        let slug = exerciseName
            .lowercased()
            .unicodeScalars
            .map { scalar -> String in
                if ("a"..."z").contains(String(scalar)) || ("0"..."9").contains(String(scalar)) {
                    return String(scalar)
                }
                return "-"
            }
            .joined()
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let docId = slug.isEmpty ? "_empty" : String(slug.prefix(100))

        Task.detached {
            await _recordUnknown(docId: docId, rawSpec: rawSpec)
        }
    }

    /// Extracted so the Firestore call site has a single entry point for tests
    /// to stub or swap in future work.
    private static func _recordUnknown(docId: String, rawSpec: String) async {
        // Auth-gate: Firestore writes need an authenticated user in this project.
        guard Auth.auth().currentUser != nil else { return }
        do {
            try await Firestore.firestore()
                .collection("unknownRepSpecs")
                .document(docId)
                .setData([
                    "count": FieldValue.increment(Int64(1)),
                    "lastRawSpec": String(rawSpec.prefix(200)),
                    "lastAt": FieldValue.serverTimestamp(),
                ], merge: true)
        } catch {
            // Telemetry must never throw into validation. Swallow silently.
        }
    }
}

// MARK: - Anatomical Relevance Checker

struct AnatomicalRelevanceChecker {

    /// Maps body region zone keys to conditions that could reasonably occur there.
    private static let regionConditions: [String: Set<String>] = [
        // ── Head & Neck (separate regions) ───────────────────────
        "head": ["headache", "migraine", "tension", "concussion", "tmj", "jaw", "temporal", "occipital"],
        "neck": ["cervical", "neck", "whiplash", "cervicogenic", "radiculopathy", "stinger", "torticollis", "disc"],

        // ── Torso (front) ────────────────────────────────────────
        "chest": ["costochondritis", "chest wall", "rib", "thoracic", "pectoral", "intercostal", "sternum"],
        "abdomen": ["abdominal", "core", "hernia", "oblique", "rectus", "diastasis"],

        // ── Torso (back) ─────────────────────────────────────────
        "upper_back": ["thoracic", "upper back", "scapular", "trapezius", "rhomboid", "postural", "kyphosis", "latissimus"],
        "lower_back": ["lumbar", "lower back", "disc", "sciatica", "stenosis", "spondyl", "sacroiliac", "si joint", "piriformis", "erector"],

        // ── Shoulders ────────────────────────────────────────────
        "left_shoulder": ["shoulder", "rotator cuff", "impingement", "frozen", "labral", "ac joint", "bicep tendon", "deltoid"],
        "right_shoulder": ["shoulder", "rotator cuff", "impingement", "frozen", "labral", "ac joint", "bicep tendon", "deltoid"],

        // ── Upper Arms ───────────────────────────────────────────
        "left_upper_arm": ["bicep", "tricep", "upper arm", "humerus", "brachial"],
        "right_upper_arm": ["bicep", "tricep", "upper arm", "humerus", "brachial"],

        // ── Elbows ───────────────────────────────────────────────
        "left_elbow": ["elbow", "tennis", "golfer", "epicondylitis", "ulnar", "olecranon", "bursitis"],
        "right_elbow": ["elbow", "tennis", "golfer", "epicondylitis", "ulnar", "olecranon", "bursitis"],

        // ── Forearms ─────────────────────────────────────────────
        "left_forearm": ["forearm", "radial", "ulnar", "pronator", "supinator", "compartment"],
        "right_forearm": ["forearm", "radial", "ulnar", "pronator", "supinator", "compartment"],

        // ── Wrists & Hands ───────────────────────────────────────
        "left_wrist_hand": ["wrist", "carpal tunnel", "de quervain", "ganglion", "hand", "finger", "trigger", "scaphoid"],
        "right_wrist_hand": ["wrist", "carpal tunnel", "de quervain", "ganglion", "hand", "finger", "trigger", "scaphoid"],

        // ── Glutes ───────────────────────────────────────────────
        "left_glute": ["glute", "gluteal", "piriformis", "sciatica", "buttock", "deep gluteal"],
        "right_glute": ["glute", "gluteal", "piriformis", "sciatica", "buttock", "deep gluteal"],

        // ── Hips ─────────────────────────────────────────────────
        "left_hip": ["hip", "labral", "bursitis", "groin", "flexor", "impingement", "snapping hip"],
        "right_hip": ["hip", "labral", "bursitis", "groin", "flexor", "impingement", "snapping hip"],

        // ── Thighs ───────────────────────────────────────────────
        "left_thigh": ["quad", "thigh", "adductor", "it band", "femoral", "vastus", "sartorius", "groin"],
        "right_thigh": ["quad", "thigh", "adductor", "it band", "femoral", "vastus", "sartorius", "groin"],

        // ── Hamstrings ───────────────────────────────────────────
        "left_hamstring": ["hamstring", "posterior thigh", "biceps femoris", "strain", "pull", "tear"],
        "right_hamstring": ["hamstring", "posterior thigh", "biceps femoris", "strain", "pull", "tear"],

        // ── Knees ────────────────────────────────────────────────
        "left_knee": ["knee", "patellofemoral", "meniscus", "acl", "pcl", "mcl", "lcl", "patellar", "baker", "chondromalacia"],
        "right_knee": ["knee", "patellofemoral", "meniscus", "acl", "pcl", "mcl", "lcl", "patellar", "baker", "chondromalacia"],

        // ── Calves & Shins ───────────────────────────────────────
        "left_calf_shin": ["calf", "shin", "achilles", "gastrocnemius", "soleus", "tibial", "compartment", "shin splint", "fibular"],
        "right_calf_shin": ["calf", "shin", "achilles", "gastrocnemius", "soleus", "tibial", "compartment", "shin splint", "fibular"],

        // ── Ankles & Feet ────────────────────────────────────────
        "left_ankle_foot": ["ankle", "foot", "plantar", "sprain", "peroneal", "metatarsal", "bunion", "tarsal"],
        "right_ankle_foot": ["ankle", "foot", "plantar", "sprain", "peroneal", "metatarsal", "bunion", "tarsal"],
    ]

    /// Check whether the AI-returned conditions are anatomically relevant to the assessed body regions.
    static func validate(conditions: [ConditionResult], assessedRegions: [BodyRegion]) -> [ValidationWarning] {
        var warnings: [ValidationWarning] = []

        let regionKeys = assessedRegions.map { $0.zoneKey }
        let allowedKeywords: Set<String> = Set(regionKeys.flatMap { regionConditions[$0] ?? [] })

        // If we have no mapping for the regions, skip this check
        guard !allowedKeywords.isEmpty else { return [] }

        for condition in conditions {
            let condNameLower = condition.conditionName.lowercased()
            let commonNameLower = condition.commonName.lowercased()

            let isRelevant = allowedKeywords.contains(where: { keyword in
                condNameLower.contains(keyword) || commonNameLower.contains(keyword)
            })

            if !isRelevant {
                warnings.append(ValidationWarning(
                    severity: .info,
                    message: "\"\(condition.commonName)\" may not be directly related to the body areas you reported pain in. This could be a referred pain pattern, or you may want to discuss this with a healthcare provider."
                ))
            }
        }

        return warnings
    }
}

// MARK: - Image Availability Validator (PR 2)

/// Validates every exercise resolves to a real catalog image, and substitutes
/// the closest catalog match when it doesn't (or when the resolved image is
/// for a wrong body region). Runs FIRST in `validateRehabPlan` so all
/// downstream steps (KG, cross-model verification, contraindication) operate
/// on canonical post-substitution names.
struct ImageAvailabilityValidator {
    private static let log = AppLogger.images

    struct Result {
        let rewritten: [RehabExercise]
        let substitutionWarnings: [ValidationWarning]
        let substitutionCount: Int
        let unrepairableCount: Int
    }

    /// Lightweight catalog entry for substitution scoring. Decoded from the
    /// bundled exercise_image_mapping.json once per call.
    private struct CatalogEntry {
        let key: String
        let name: String
        let category: String
        let targetAreaTokens: Set<String>
        let bodyPosition: String?
    }

    /// Loaded once per call; ~1225 entries, decode is <10ms on simulator.
    private static func loadCatalog() -> [CatalogEntry] {
        guard let url = Bundle.main.url(forResource: "exercise_image_mapping", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let raw = try? JSONDecoder().decode([String: ExerciseImageService.ImageEntry].self, from: data)
        else {
            return []
        }
        return raw.map { (key, entry) in
            CatalogEntry(
                key: key,
                name: entry.name,
                category: entry.category,
                targetAreaTokens: ExerciseImageService.normalizedTargetArea(entry.target_area),
                bodyPosition: entry.body_position
            )
        }
    }

    static func validate(
        exercises: [RehabExercise],
        userConditions: [String],
        userPainRegions: [String]
    ) -> Result {
        let catalog = loadCatalog()
        let service = ExerciseImageService.shared
        var rewritten: [RehabExercise] = []
        var warnings: [ValidationWarning] = []
        var substitutions = 0
        var unrepairable = 0

        for original in exercises {
            let originalAreaTokens = ExerciseImageService.normalizedTargetArea(original.targetArea)

            // Step 1: try the resolver.
            let match = service.resolveImageMatch(for: original)
            var needsSubstitution = false
            if let m = match,
               let entry = catalog.first(where: { $0.key == m.key }) {
                // Step 2: anatomical-relevance check on successfully-resolved match.
                // If the resolved image's target_area has no overlap with the
                // exercise's targetArea, the resolver picked an anatomically
                // wrong image — treat as needing substitution.
                if entry.targetAreaTokens.isDisjoint(with: originalAreaTokens) && !originalAreaTokens.isEmpty {
                    needsSubstitution = true
                }
            } else {
                needsSubstitution = true
            }

            if !needsSubstitution {
                rewritten.append(original)
                continue
            }

            // Safety guard: if the ORIGINAL exercise would trigger any
            // contraindication for the user's conditions, do NOT substitute.
            // Substitution would silently mask the warning at downstream
            // step 2/9 (e.g. "Jump Squat" → "Wall Sits" hides the osteoporosis
            // jumping warning). Pass through unchanged so the safety pipeline
            // fires on the original name; user falls back to SF Symbol if
            // they acknowledge and proceed anyway.
            let originalContraindications = ExerciseContraindicationChecker.validate(
                exercises: [original], conditions: userConditions
            )
            if !originalContraindications.isEmpty {
                rewritten.append(original)
                continue
            }
            // Same guard for the medical-condition safety keyword set used by
            // downstream steps 8/9 (osteoporosis+impact, blood-thinners+fall-risk).
            // These checks operate on `userProfile.medicalConditions`/`.medications`
            // which we don't have here, so we conservatively block substitution
            // whenever the name contains any flagged keyword. Worst case: a
            // healthy user with no flagged conditions sees an SF Symbol fallback
            // for a jump exercise. Best case: a flagged user sees the safety
            // warning we'd otherwise have hidden.
            if hasSafetyFlaggedKeyword(original.name) {
                rewritten.append(original)
                continue
            }

            // Step 3-7: pick a substitute.
            if let substitute = pickSubstitute(
                for: original,
                originalAreaTokens: originalAreaTokens,
                catalog: catalog,
                userConditions: userConditions
            ) {
                substitutions += 1
                var rewrittenExercise = original
                // Capture the AI's original name BEFORE rewriting (idempotent — only
                // sets if not already set, in case validation runs more than once).
                if rewrittenExercise.originalAIName == nil {
                    rewrittenExercise.originalAIName = original.name
                }
                rewrittenExercise.name = substitute.name
                rewrittenExercise.imageFileName = substitute.key
                rewritten.append(rewrittenExercise)
                // The warning must describe what ACTUALLY changed. It previously read
                // "Showing illustration for similar exercise", implying the swap was
                // display-only — but the exercise NAME is rewritten too while the
                // description, tips, phase instructions and sets/reps/rest all remain
                // the originally prescribed ones. A user reading a renamed card was
                // given no signal that the instructions belong to a different movement.
                //
                // DESIGN GAP (not fixable here): the catalog behind this substitution
                // is the image mapping — key, name, category, target-area tokens — so
                // it carries no instructional content to swap in alongside the name.
                // Closing the mismatch properly means either sourcing instructions for
                // the substitute, or not renaming and treating this as illustration-only.
                // Both are product decisions beyond a copy fix; this at least stops the
                // message asserting something untrue.
                warnings.append(ValidationWarning(
                    severity: .info,
                    message: "\"\(original.name)\" wasn't in our exercise library, so it's shown as \"\(substitute.name)\". Follow the written steps on the card — they describe the exercise your plan prescribed."
                ))
                log.info("Image substitution: '\(original.name)' → '\(substitute.name)' (key: \(substitute.key))")

                // Telemetry: record the substitution in `missingExerciseImages` so
                // the debug surface (PR 2.3) can surface it as a backlog item.
                service.logMissingImageIfNeeded(for: original, substitutedTo: substitute.key)
            } else {
                // No catalog candidate survived the contraindication + KG filters.
                // Keep the original; it'll fall through to SF Symbol fallback at
                // display time. PR 3 will re-attempt this on saved-plan load.
                unrepairable += 1
                rewritten.append(original)
                log.warning("Image substitution failed for '\(original.name)' — no safe candidate")
            }
        }

        return Result(
            rewritten: rewritten,
            substitutionWarnings: warnings,
            substitutionCount: substitutions,
            unrepairableCount: unrepairable
        )
    }

    /// Mirror of the safety-keyword sets used in `validateRehabPlan` steps 8/9.
    /// Substitution refuses to rewrite names containing these keywords because
    /// downstream checks fire on the name itself — silent rewrite would hide
    /// safety warnings.
    private static let safetyKeywords: Set<String> = [
        "jump", "plyometric", "impact", "running", "balance", "single-leg"
    ]

    private static func hasSafetyFlaggedKeyword(_ name: String) -> Bool {
        let lower = name.lowercased()
        return safetyKeywords.contains(where: { lower.contains($0) })
    }

    /// Pick the best catalog substitute for an exercise that has no image.
    /// Returns nil if no candidate survives the contraindication + KG filters.
    private static func pickSubstitute(
        for exercise: RehabExercise,
        originalAreaTokens: Set<String>,
        catalog: [CatalogEntry],
        userConditions: [String]
    ) -> CatalogEntry? {
        let originalCategory = exercise.exerciseCategory?.lowercased()
        let originalNameTokens = Set(
            ExerciseImageService.shared.normalizeName(exercise.name).split(separator: "-").map(String.init)
        )

        // Candidates: any catalog entry that shares at least one target_area token.
        let candidates = catalog.filter { candidate in
            !candidate.targetAreaTokens.isDisjoint(with: originalAreaTokens)
        }
        if candidates.isEmpty { return nil }

        // Filter out anything the hardcoded contraindication checker would reject
        // for this user's conditions. Substitution must NEVER produce an exercise
        // that triggers a `.serious` warning at downstream step 2/9.
        let safeCandidates = candidates.filter { candidate in
            let probe = RehabExercise(
                id: UUID(),
                name: candidate.name,
                targetArea: exercise.targetArea,
                description: "",
                sets: 1, reps: "1", restSeconds: 0,
                difficulty: .beginner,
                demonstrationIcon: "figure.flexibility",
                tips: [], contraindications: []
            )
            let warnings = ExerciseContraindicationChecker.validate(
                exercises: [probe], conditions: userConditions
            )
            // Drop any candidate that produces ANY warning — substitutes must be clean.
            return warnings.isEmpty
        }
        if safeCandidates.isEmpty { return nil }

        // Score each surviving candidate.
        let scored: [(CatalogEntry, Int)] = safeCandidates.map { candidate in
            var score = 0
            // target_area token overlap (3 per shared token, max 10)
            let overlap = candidate.targetAreaTokens.intersection(originalAreaTokens).count
            score += min(overlap * 3, 10)
            // category exact match (5)
            if let cat = originalCategory, candidate.category.lowercased() == cat {
                score += 5
            }
            // name token overlap with original (1 per shared token, max 5)
            let candidateNameTokens = Set(candidate.key.split(separator: "-").map(String.init))
            let nameOverlap = candidateNameTokens.intersection(originalNameTokens).count
            score += min(nameOverlap, 5)
            return (candidate, score)
        }

        // Highest score wins; tiebreak alphabetically by canonical key (deterministic).
        return scored.max(by: { lhs, rhs in
            if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
            return lhs.0.key > rhs.0.key
        })?.0
    }
}

// MARK: - Knowledge Graph Validator

struct KnowledgeGraphValidator {

    /// Validate exercises against the medical knowledge graph.
    /// Returns warnings for contraindicated exercises and the full verification result.
    static func validate(
        exercises: [RehabExercise],
        conditions: [String],
        knowledgeGraph: KnowledgeGraphService = .shared
    ) -> (warnings: [ValidationWarning], verification: PlanVerificationResult) {
        let plan = RehabPlan(
            id: UUID(),
            planName: "",
            conditions: conditions,
            exercises: exercises,
            weeklySchedule: [],
            totalWeeks: 0,
            createdDate: Date(),
            notes: nil
        )

        let verification = knowledgeGraph.verifyPlan(plan, conditions: conditions)
        var warnings: [ValidationWarning] = []

        // Add warnings for contraindicated exercises.
        // Tier 1 severity: knowledge-graph-contraindicated → `.serious` (modal gate required).
        // The `exercise` variable is intentionally unused: the `reason` string already names
        // the exercise and condition.
        for (_, reason) in verification.contraindicatedExercises {
            warnings.append(ValidationWarning(
                severity: .serious,
                message: reason
            ))
        }

        // Add warnings for conditions with red flags from the knowledge graph
        for condition in conditions {
            if let redFlags = knowledgeGraph.redFlags(forCondition: condition) {
                for flag in redFlags {
                    warnings.append(ValidationWarning(
                        severity: .info,
                        message: "Knowledge base note for your condition: \(flag)"
                    ))
                }
            }
        }

        return (warnings, verification)
    }
}

// MARK: - Wellness Validators

/// Validates a wellness analysis result (the "what's going on" recommendations stage —
/// before any exercise plan is generated).
///
/// Scope: bounds + red-flag scan of user-supplied strings + confidence cap. The
/// `WellnessRecommendation` model carries no exercises, so per-exercise contraindication
/// checks happen later in `WellnessPlanValidator`.
struct WellnessAnalysisValidator {

    /// Collect free-text strings from a wellness assessment to feed into the red-flag
    /// detector. Covers: custom goal text, specific context, additional notes.
    private static func symptomStrings(from assessments: [WellnessAssessment]) -> [String] {
        var out: [String] = []
        for a in assessments {
            if let s = a.customGoalText, !s.isEmpty { out.append(s) }
            if let s = a.specificContext, !s.isEmpty { out.append(s) }
            if let s = a.additionalNotes, !s.isEmpty { out.append(s) }
        }
        return out
    }

    /// Run the full wellness analysis validation pipeline.
    /// Returns the bounded result + a `ValidationResult` carrying any warnings.
    static func validate(
        _ result: WellnessAnalysisResult,
        assessments: [WellnessAssessment]
    ) -> (result: WellnessAnalysisResult, validation: ValidationResult) {

        var warnings: [ValidationWarning] = []
        var fixes: [String] = []

        // 1. Content bounds: recommendations 1–5, each non-empty title + assessment.
        if result.recommendations.isEmpty {
            warnings.append(ValidationWarning(severity: .caution, message: "No wellness recommendations were generated."))
        }
        // Enforce the 1–5 bound for real. This previously appended the "Trimmed…" fix
        // message and then returned the untouched result, so an over-long AI response
        // reached the user in full while the pipeline reported a correction it had not
        // performed. Mirrors `validateAnalysis`'s `conditions.prefix(3)` on the injury side.
        var boundedRecommendations = result.recommendations
        if boundedRecommendations.count > 5 {
            fixes.append("Trimmed wellness recommendations from \(boundedRecommendations.count) to 5")
            boundedRecommendations = Array(boundedRecommendations.prefix(5))
        }
        for rec in boundedRecommendations {
            if rec.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                warnings.append(ValidationWarning(severity: .info, message: "A wellness recommendation was missing a title."))
            }
            if rec.currentStateAssessment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                warnings.append(ValidationWarning(severity: .info, message: "A wellness recommendation was missing a state assessment."))
            }
        }

        // 2. Summary must be non-empty.
        if result.overallSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            warnings.append(ValidationWarning(severity: .caution, message: "The wellness summary was empty."))
        }

        // 3. Red-flag scan over user-supplied strings. Emergency hits surface via
        //    `redFlags` return (parallel to the injury flow) so the caller can route
        //    to `EmergencyRedirectView`.
        let redFlags = MedicalRedFlagDetector.check(symptomStrings: symptomStrings(from: assessments))
        warnings.append(contentsOf: redFlags.alerts)

        let isValid = warnings.filter({ $0.severity >= .serious }).isEmpty
        let validation = ValidationResult(isValid: isValid, warnings: warnings, appliedFixes: fixes)

        let boundedResult = WellnessAnalysisResult(
            id: result.id,
            assessments: result.assessments,
            recommendations: boundedRecommendations,
            overallSummary: result.overallSummary,
            disclaimerText: result.disclaimerText,
            generatedDate: result.generatedDate,
            userProfileSnapshot: result.userProfileSnapshot
        )
        return (boundedResult, validation)
    }
}

/// Validates a generated wellness plan — the stage after recommendations, once concrete
/// exercises exist. Runs KG-based contraindication check against the user's medical
/// conditions (same pattern as `ExerciseSwapViewModel.verifySubstitutes`).
struct WellnessPlanValidator {

    /// Run KG-based contraindication check on each exercise against every condition.
    /// Worst tier wins. `.contraindicated` → `.serious` severity.
    static func validate(
        exercises: [RehabExercise],
        conditions: [String],
        knowledgeGraph: KnowledgeGraphService = .shared
    ) -> [ValidationWarning] {

        // Empty conditions array = nothing to check against. Return cleanly — this is
        // the common case for wellness users (they haven't declared medical conditions).
        guard !conditions.isEmpty else { return [] }

        var warnings: [ValidationWarning] = []

        for exercise in exercises {
            for condition in conditions {
                let tier = knowledgeGraph.verify(exercise: exercise.name, forCondition: condition)
                if case .contraindicated(let reason) = tier {
                    warnings.append(ValidationWarning(severity: .serious, message: reason))
                    break  // first hit per exercise is enough
                }
            }
        }

        return warnings
    }
}

// MARK: - Full Validation Pipeline

struct ResponseValidationPipeline {

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.pthelper", category: "validation")

    /// Run the full validation pipeline on an analysis result.
    /// Returns the (potentially modified) result along with validation info.
    static func validateAnalysis(
        _ result: AnalysisResult,
        assessments: [PainAssessment]
    ) -> (result: AnalysisResult, validation: ValidationResult, redFlags: [ValidationWarning]) {

        var allWarnings: [ValidationWarning] = []
        var allFixes: [String] = []

        logger.info("Starting analysis validation pipeline for \(result.conditions.count) condition(s), \(assessments.count) assessment(s)")

        // 1. Content validation
        logger.debug("[1/6] Running content validation...")
        let contentValidation = AnalysisContentValidator.validate(result)
        allWarnings.append(contentsOf: contentValidation.warnings)
        allFixes.append(contentsOf: contentValidation.appliedFixes)
        logger.debug("[1/6] Content validation: \(contentValidation.warnings.count) warnings, \(contentValidation.appliedFixes.count) fixes")

        // 2. Red flag detection from symptoms
        logger.debug("[2/6] Checking symptom red flags...")
        let symptomRedFlags = MedicalRedFlagDetector.check(assessments: assessments)
        var redFlagAlerts = symptomRedFlags.alerts
        logger.debug("[2/6] Symptom red flags: \(symptomRedFlags.alerts.count)")

        // 3. Red flag detection from conditions
        logger.debug("[3/6] Checking condition red flags...")
        let conditionRedFlags = MedicalRedFlagDetector.checkConditions(result.conditions)
        redFlagAlerts.append(contentsOf: conditionRedFlags)
        // AI-flagged conditions additionally surface as first-class alerts.
        // `redFlagAlerts` is load-bearing beyond the on-screen banner: it decides
        // whether the session log is uploaded, sets the has_red_flags analytic, and
        // supplies the messages persisted by RiskAcknowledgementRecorder. Without
        // this, a condition the model itself marked serious contributed to none of
        // those — checkConditions is keyword-driven and stays deliberately silent
        // for conditions already flagged (see testCheckConditions_fracture_
        // alreadyRedFlagged_notDoubled, which pins that behavior).
        let flaggedConditionAlerts = MedicalRedFlagDetector.alerts(forFlagged: result.conditions)
        redFlagAlerts.append(contentsOf: flaggedConditionAlerts)
        logger.debug("[3/6] Condition red flags: \(conditionRedFlags.count), AI-flagged: \(flaggedConditionAlerts.count)")

        // 4. Anatomical relevance check
        logger.debug("[4/6] Checking anatomical relevance...")
        let regions = assessments.map { $0.selectedRegion }
        let anatomicalWarnings = AnatomicalRelevanceChecker.validate(conditions: result.conditions, assessedRegions: regions)
        allWarnings.append(contentsOf: anatomicalWarnings)
        logger.debug("[4/6] Anatomical warnings: \(anatomicalWarnings.count)")

        // 5. Deduplicate conditions.
        // Runs BEFORE retention so a duplicate can't consume one of the three ranked
        // slots — `[A, A, B, C]` previously truncated to `[A, A, B]` and then deduped
        // to two conditions, silently losing C. A red-flagged copy also wins a name
        // collision, since dropping it is the defect this pass exists to prevent.
        logger.debug("[5/6] Deduplicating conditions...")
        var seenIndex: [String: Int] = [:]
        var dedupedConditions: [ConditionResult] = []
        for condition in result.conditions {
            let key = condition.conditionName.lowercased()
            if let existing = seenIndex[key] {
                allFixes.append("Removed duplicate condition: \(condition.commonName)")
                if condition.isRedFlag && !dedupedConditions[existing].isRedFlag {
                    dedupedConditions[existing] = condition
                }
                continue
            }
            seenIndex[key] = dedupedConditions.count
            dedupedConditions.append(condition)
        }

        // 6. Apply the retention policy, then calibrate confidence.
        // The retention policy — not a bare prefix(3) — decides what survives, so a
        // low-confidence red flag reaches the user instead of being ranked out.
        logger.debug("[6/6] Applying retention policy and calibrating confidence...")
        let retention = ConditionRetentionPolicy.retain(dedupedConditions)
        if retention.rescuedRedFlagCount > 0 {
            logger.warning("Retained \(retention.rescuedRedFlagCount) red flag(s) past the ranked top \(ConditionRetentionPolicy.maxRankedConditions)")
            allFixes.append("Preserved \(retention.rescuedRedFlagCount) potentially serious finding(s) beyond the top \(ConditionRetentionPolicy.maxRankedConditions)")
        }
        if retention.droppedRedFlagCount > 0 {
            logger.error("Dropped \(retention.droppedRedFlagCount) red flag(s) over the rescue cap")
            redFlagAlerts.append(ValidationWarning(
                severity: .urgent,
                message: "Additional potentially serious findings were identified. Please see a healthcare provider before starting any exercise program."
            ))
        }
        let uniqueConditions = retention.conditions.map { condition in
            ConditionResult(
                id: condition.id,
                conditionName: condition.conditionName,
                commonName: condition.commonName,
                confidence: ConfidenceCalibrator.calibrate(condition.confidence),
                explanation: condition.explanation,
                whatItMeans: condition.whatItMeans,
                howToManage: condition.howToManage,
                isRedFlag: condition.isRedFlag,
                redFlagMessage: condition.redFlagMessage,
                nextSteps: condition.nextSteps
            )
        }

        // Build validated result
        let validatedResult = AnalysisResult(
            id: result.id,
            assessments: result.assessments,
            conditions: Array(uniqueConditions),
            overallSummary: result.overallSummary,
            disclaimerText: result.disclaimerText,
            generatedDate: result.generatedDate,
            userProfileSnapshot: result.userProfileSnapshot
        )

        // Log validation
        logger.info("Validation complete: \(allWarnings.count) warnings, \(allFixes.count) fixes, \(redFlagAlerts.count) red flags")
        Task { @MainActor in
            SessionLogger.shared.log(.stateUpdated, category: .stateChange, message: "Validation pipeline completed",
                                      metadata: ["warnings": "\(allWarnings.count)",
                                                  "fixes": "\(allFixes.count)",
                                                  "redFlags": "\(redFlagAlerts.count)"])
            if !redFlagAlerts.isEmpty {
                // Auto-upload on red flags — this is a high-value flow to capture
                await SessionLogger.shared.uploadToFirestore()
            }
        }
        for fix in allFixes {
            logger.debug("Fix applied: \(fix)")
        }

        let validation = ValidationResult(
            isValid: allWarnings.filter({ $0.severity >= .serious }).isEmpty,
            warnings: allWarnings,
            appliedFixes: allFixes
        )

        return (validatedResult, validation, redFlagAlerts)
    }

    /// Run validation on a rehab plan.
    /// Returns the plan, warnings, and an optional knowledge graph verification result.
    static func validateRehabPlan(
        _ plan: RehabPlan,
        conditions: [String],
        userProfile: UserProfile,
        userPainRegions: [String] = []
    ) -> (plan: RehabPlan, warnings: [ValidationWarning], graphVerification: PlanVerificationResult?) {

        var warnings: [ValidationWarning] = []
        var graphVerification: PlanVerificationResult?
        var workingPlan = plan

        logger.info("Starting rehab plan validation: \(plan.exercises.count) exercises, \(conditions.count) conditions")

        // 1.0/9. Image-availability + auto-substitute (runs FIRST so KG validation
        // and cross-model verification operate on canonical post-substitution names).
        logger.debug("[Rehab 1.0/9] Validating image availability + substituting where needed...")
        let imageResult = ImageAvailabilityValidator.validate(
            exercises: plan.exercises,
            userConditions: conditions,
            userPainRegions: userPainRegions
        )
        workingPlan.exercises = imageResult.rewritten
        warnings.append(contentsOf: imageResult.substitutionWarnings)
        logger.debug("[Rehab 1.0/9] Substitutions: \(imageResult.substitutionCount), unrepairable: \(imageResult.unrepairableCount)")

        // 2/9. Exercise contraindication check (hardcoded rules — safety net).
        // Note: image-substitution candidates were already filtered by
        // ExerciseContraindicationChecker before scoring (see
        // ImageAvailabilityValidator), so substituted exercises will be clean.
        // Original-AI exercises that survived (no substitution) still get checked
        // here. The duplication is intentional — keep the existing safety net.
        let contraindicationWarnings = ExerciseContraindicationChecker.validate(
            exercises: workingPlan.exercises,
            conditions: conditions
        )
        warnings.append(contentsOf: contraindicationWarnings)
        logger.debug("[Rehab 2/9] Contraindication warnings: \(contraindicationWarnings.count)")

        // 3/9. Knowledge graph validation (comprehensive, deterministic).
        // Now sees CANONICAL post-substitution names — `crossVerify` payload
        // downstream uses these same names.
        logger.debug("[Rehab 3/9] Running knowledge graph validation...")
        let graphResult = KnowledgeGraphValidator.validate(
            exercises: workingPlan.exercises,
            conditions: conditions
        )
        warnings.append(contentsOf: graphResult.warnings)
        graphVerification = graphResult.verification
        let verified = graphResult.verification.exerciseResults.filter { $0.tier == .verified }.count
        let unverified = graphResult.verification.unverifiedExercises.count
        let contraindicated = graphResult.verification.contraindicatedExercises.count
        logger.debug("[Rehab 3/9] Knowledge graph: \(verified) verified, \(contraindicated) contraindicated, \(unverified) unverified")

        // 4/9. Parameter range validation — corrections are APPLIED, not just noted.
        let (boundedExercises, paramFixes) = ExerciseContraindicationChecker.validateParameters(workingPlan.exercises)
        workingPlan.exercises = boundedExercises
        for fix in paramFixes {
            warnings.append(ValidationWarning(severity: .info, message: fix))
        }

        // 5/9. Exercise count check
        if workingPlan.exercises.isEmpty {
            warnings.append(ValidationWarning(severity: .caution, message: "No exercises were generated. The fallback exercise database will be used."))
        }

        // 6/9. Plan duration check
        if workingPlan.totalWeeks < 1 || workingPlan.totalWeeks > 24 {
            warnings.append(ValidationWarning(severity: .info, message: "Plan duration of \(workingPlan.totalWeeks) weeks is unusual. Typical plans are 4-12 weeks."))
        }

        // 7/9. Age-based safety checks
        if userProfile.age >= 65 {
            let hasHighIntensity = workingPlan.exercises.contains(where: { $0.difficulty == .advanced })
            if hasHighIntensity {
                warnings.append(ValidationWarning(
                    severity: .caution,
                    message: "Some exercises are marked as advanced. Given your age, please start slowly and consult a healthcare provider before attempting advanced exercises."
                ))
            }
        }

        // 8/9. Medical condition safety checks
        let medConditionsLower = userProfile.medicalConditions.map { $0.lowercased() }

        if medConditionsLower.contains(where: { $0.contains("osteoporosis") }) {
            let hasImpact = workingPlan.exercises.contains(where: {
                let nameLower = $0.name.lowercased()
                return nameLower.contains("jump") || nameLower.contains("plyometric") || nameLower.contains("impact") || nameLower.contains("running")
            })
            if hasImpact {
                // Tier 1 severity: osteoporosis + impact is a well-documented contraindication
                // (fracture risk). Route through `SeriousWarningModal` — user acknowledges or
                // requests a safer plan.
                warnings.append(ValidationWarning(
                    severity: .serious,
                    message: "High-impact exercises are not recommended with osteoporosis. Please consult your doctor before performing any impact-based exercises."
                ))
            }
        }

        if medConditionsLower.contains(where: { $0.contains("heart") || $0.contains("cardiac") }) {
            warnings.append(ValidationWarning(
                severity: .caution,
                message: "With your cardiac history, please monitor your heart rate during exercises and stop if you experience chest pain, dizziness, or shortness of breath."
            ))
        }

        // 9/9. Medication + post-surgical safety checks
        let meds = userProfile.medications ?? []
        // Exact set membership only ever matched the onboarding chip strings
        // verbatim, so a free-text entry ("Blood thinner", "blood-thinners",
        // "Warfarin (blood thinner)") silently skipped these gates — and the
        // medical-history step accepts custom medications. Term matching folds the
        // separator/plural variants the way the condition checks above already do.
        let takesMedication: (String) -> Bool = { term in
            meds.contains { TermMatching.containsTerm(term, in: $0) }
        }

        if takesMedication("blood thinners") || takesMedication("blood thinner") {
            let hasImpactOrFall = workingPlan.exercises.contains(where: {
                let n = $0.name.lowercased()
                return n.contains("jump") || n.contains("plyometric") || n.contains("balance") || n.contains("single-leg")
            })
            if hasImpactOrFall {
                // Tier 1 severity: blood-thinners + fall-risk exercises → `.serious`
                // (bleeding risk from any fall). Acknowledgement required.
                warnings.append(ValidationWarning(
                    severity: .serious,
                    message: "You take blood thinners. Be extra cautious with balance and impact exercises to avoid falls or bruising. Consider performing these near a wall or support."
                ))
            }
        }

        if takesMedication("corticosteroids") {
            warnings.append(ValidationWarning(
                severity: .info,
                message: "Long-term corticosteroid use can weaken tendons. Start with lower resistance and increase gradually."
            ))
        }

        if takesMedication("beta blockers") {
            warnings.append(ValidationWarning(
                severity: .info,
                message: "Beta blockers affect heart rate response. Use how you feel (perceived exertion) rather than heart rate to gauge exercise intensity."
            ))
        }

        let activeSurgeries = userProfile.surgeries.filter {
            $0.recoveryStatus == "Still recovering" || $0.recoveryStatus == "Have restrictions"
        }
        if !activeSurgeries.isEmpty {
            let surgeryNames = activeSurgeries.map { $0.name }.joined(separator: ", ")
            warnings.append(ValidationWarning(
                severity: .caution,
                message: "You have active surgical recovery (\(surgeryNames)). Follow your surgeon's guidelines and avoid exercises that conflict with your restrictions."
            ))
        }

        // PR 3: tag plans that survived the full pipeline as schemaVersion 2 so
        // SavedPlansViewModel's repair-on-load skips them on subsequent fetches.
        workingPlan.schemaVersion = 2

        logger.info("Rehab plan validation: \(warnings.count) warnings for \(workingPlan.exercises.count) exercises")

        return (workingPlan, warnings, graphVerification)
    }

    // MARK: - Cross-model verification helpers (Tier 2 PR D)

    /// Emit a `.serious` warning for an exercise whose cross-model safety check
    /// failed after all retries exhausted. Compile-time references
    /// `ValidationSeverity.serious` — if Tier 1 hasn't shipped the `.serious`
    /// case, this file won't compile, which is the intended hard gate.
    ///
    /// Called from `RehabPlanViewModel.performCrossModelVerification` when an
    /// exercise gets status `.crossModelFailed`. The view appends the warning
    /// to `rehabPlanWarnings`, which Tier 1's `RehabPlanView.evaluateSeriousWarning`
    /// picks up and routes through `SeriousWarningModal`.
    ///
    /// Rationale for `.serious` (not `.urgent`, not removal):
    /// - We can't verify this exercise is safe, but also can't confirm it's
    ///   unsafe — an acknowledgement modal ("unverified; talk to your PT") is
    ///   the honest middle path.
    /// - Removing the exercise from the rendered plan would require rewiring
    ///   `RehabPlanView` and risks the plan shrinking silently on transient
    ///   outages; explicitly out of scope for PR D.
    static func crossModelFailureWarning(exerciseName: String) -> ValidationWarning {
        ValidationWarning(
            severity: ValidationSeverity.serious,
            message: "\"\(exerciseName)\" couldn't be verified against our safety database right now. It may still be appropriate — but please confirm with your physical therapist before starting."
        )
    }
}
