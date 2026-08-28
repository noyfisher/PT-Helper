import Foundation
import SwiftUI
import os

// MARK: - Tier 2 PR C-1: feature flag + v2 loader

/// `@AppStorage` flag gating the v2 knowledge-graph file. Defaults OFF —
/// enables the merge-with-fallback loader to silently include v2 entries
/// alongside the existing v1 graph when present.
///
/// Flip to `true` only AFTER:
/// 1. `scripts/expand_knowledge_graph.py` produced a complete v2 draft.
/// 2. `scripts/review_kg_candidates.py` walked through every
///    `contraindicated` verdict + 10% sample of `safe`.
/// 3. The reviewed JSON was merged into
///    `Resources/medical_knowledge_graph_v2.json`.
///
/// While OFF, the production graph is unchanged — only v1 contributes.
enum KnowledgeGraphFeatureFlag {
    static let key = "knowledgeGraphV2Enabled"
    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: key)
    }
}

// MARK: - Knowledge Graph Models

struct KnowledgeGraph: Decodable {
    let version: String
    let conditions: [String: KnownCondition]
    /// Optional — if absent, exercise aliases are derived from condition safe/unsafe lists.
    let exercises: [String: KnownExercise]?
}

struct KnownCondition: Decodable {
    let names: [String]
    let icd10: String
    let bodyRegions: [String]
    let safeExercises: [String]
    let unsafeExercises: [String]
    let redFlags: [String]
    let referIfPresent: [String]
}

struct KnownExercise: Decodable {
    let names: [String]
    let targetRegions: [String]
    let category: String
    let safeForConditions: [String]
    let unsafeForConditions: [String]
}

// MARK: - Verification Types

enum VerificationTier: Equatable {
    case verified                       // In graph, confirmed safe
    case contraindicated(reason: String) // In graph, confirmed unsafe
    case unverified                     // Not in graph — needs cross-model check

    static func == (lhs: VerificationTier, rhs: VerificationTier) -> Bool {
        switch (lhs, rhs) {
        case (.verified, .verified): return true
        case (.unverified, .unverified): return true
        case (.contraindicated(let a), .contraindicated(let b)): return a == b
        default: return false
        }
    }
}

struct PlanVerificationResult {
    let exerciseResults: [(exercise: RehabExercise, tier: VerificationTier)]
    let conditionResults: [(condition: String, isKnown: Bool)]
    let unverifiedExercises: [RehabExercise]
    let contraindicatedExercises: [(exercise: RehabExercise, reason: String)]
}

// MARK: - Knowledge Graph Service

class KnowledgeGraphService {
    static let shared = KnowledgeGraphService()

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.pthelper", category: "knowledgeGraph")
    private var graph: KnowledgeGraph?
    private var isLoaded = false

    /// Pre-built lookup tables for fast fuzzy matching
    private var conditionAliasMap: [String: String] = [:]   // lowercased alias → condition ID
    private var exerciseAliasMap: [String: String] = [:]     // lowercased alias → exercise ID

    init() {
        loadGraph(from: Bundle.main)
    }

    /// Allow injection of a custom bundle for testing
    init(bundle: Bundle) {
        loadGraph(from: bundle)
    }

    /// Allow injection of a custom graph for testing
    init(graph: KnowledgeGraph) {
        self.graph = graph
        self.isLoaded = true
        buildLookupTables()
    }

    // MARK: - Loading

    private func loadGraph(from bundle: Bundle) {
        guard let url = bundle.url(forResource: "medical_knowledge_graph", withExtension: "json") else {
            logger.error("medical_knowledge_graph.json not found in bundle")
            return
        }

        do {
            let data = try Data(contentsOf: url)
            let v1 = try JSONDecoder().decode(KnowledgeGraph.self, from: data)

            // Tier 2 PR C-1: opt-in merge with v2 file when present + flag on.
            // The merger UNIONS condition entries (more aliases / more
            // safe/unsafe exercises in either source = available in the
            // result). v2 cannot SHRINK v1 — at worst an empty v2 is a no-op.
            // While the feature flag is OFF, v2 is ignored entirely so the
            // production graph is byte-identical to before this PR.
            let v2: KnowledgeGraph? = KnowledgeGraphFeatureFlag.isEnabled
                ? Self.loadV2(from: bundle)
                : nil

            self.graph = v2.map { Self.merge(v1: v1, v2: $0) } ?? v1
            isLoaded = true
            buildLookupTables()

            let condCount = self.graph?.conditions.count ?? 0
            let exCount = self.graph?.exercises?.count ?? 0
            let aliasCount = self.exerciseAliasMap.count
            let condAliasCount = self.conditionAliasMap.count
            let v2Note = v2 != nil ? " (v1 + v2 merged)" : ""
            logger.info("✅ Knowledge graph loaded\(v2Note): \(condCount) conditions, \(exCount) explicit exercises, \(aliasCount) exercise aliases, \(condAliasCount) condition aliases")
            // Log a sample of exercise aliases for debugging
            let sampleAliases = Array(self.exerciseAliasMap.keys.prefix(10))
            logger.debug("📋 Sample exercise aliases: \(sampleAliases.joined(separator: ", "))")
            let sampleCondAliases = Array(self.conditionAliasMap.keys.prefix(10))
            logger.debug("📋 Sample condition aliases: \(sampleCondAliases.joined(separator: ", "))")
        } catch {
            logger.error("Failed to load knowledge graph: \(error.localizedDescription)")
        }
    }

    /// Best-effort load of the v2 file from the bundle. Returns nil if absent
    /// or malformed — v1 alone is the safe fallback.
    static func loadV2(from bundle: Bundle) -> KnowledgeGraph? {
        guard let url = bundle.url(forResource: "medical_knowledge_graph_v2", withExtension: "json") else {
            return nil
        }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(KnowledgeGraph.self, from: data)
        } catch {
            // Don't fail the whole app on a malformed v2 file — log and skip.
            // v1 alone keeps the existing safety semantics.
            return nil
        }
    }

    /// Union v1 and v2 into a single graph.
    /// - For overlapping condition IDs: v2's `safeExercises` and
    ///   `unsafeExercises` are unioned with v1's, names are unioned, and
    ///   `redFlags` / `referIfPresent` are unioned. ICD-10 + bodyRegions
    ///   prefer v1 (the curated source of truth for those fields).
    /// - Conditions only in v2 are added as-is.
    /// - Exercise dict is unioned (v1 wins on overlap).
    static func merge(v1: KnowledgeGraph, v2: KnowledgeGraph) -> KnowledgeGraph {
        var mergedConditions = v1.conditions
        for (key, v2Cond) in v2.conditions {
            if let v1Cond = mergedConditions[key] {
                mergedConditions[key] = KnownCondition(
                    names: Array(Set(v1Cond.names + v2Cond.names)).sorted(),
                    icd10: v1Cond.icd10.isEmpty ? v2Cond.icd10 : v1Cond.icd10,
                    bodyRegions: Array(Set(v1Cond.bodyRegions + v2Cond.bodyRegions)).sorted(),
                    safeExercises: Array(Set(v1Cond.safeExercises + v2Cond.safeExercises)).sorted(),
                    unsafeExercises: Array(Set(v1Cond.unsafeExercises + v2Cond.unsafeExercises)).sorted(),
                    redFlags: Array(Set(v1Cond.redFlags + v2Cond.redFlags)).sorted(),
                    referIfPresent: Array(Set(v1Cond.referIfPresent + v2Cond.referIfPresent)).sorted()
                )
            } else {
                mergedConditions[key] = v2Cond
            }
        }

        // Union the exercise dicts. v1 entry wins on collision.
        var mergedExercises = v1.exercises ?? [:]
        if let v2Exercises = v2.exercises {
            for (key, ex) in v2Exercises where mergedExercises[key] == nil {
                mergedExercises[key] = ex
            }
        }

        return KnowledgeGraph(
            version: "merged(v1=\(v1.version), v2=\(v2.version))",
            conditions: mergedConditions,
            exercises: mergedExercises.isEmpty ? nil : mergedExercises
        )
    }

    private func buildLookupTables() {
        guard let graph = graph else { return }

        // Build condition alias map
        for (conditionID, condition) in graph.conditions {
            // Map each alias to the condition ID
            for name in condition.names {
                conditionAliasMap[name.lowercased()] = conditionID
            }
            // Also map the ID itself (kebab-case → condition ID)
            conditionAliasMap[conditionID.lowercased()] = conditionID
            // Map the ID with spaces instead of hyphens
            conditionAliasMap[conditionID.replacingOccurrences(of: "-", with: " ").lowercased()] = conditionID
        }

        // Build exercise alias map from explicit exercises dict if available
        if let exercises = graph.exercises {
            for (exerciseID, exercise) in exercises {
                for name in exercise.names {
                    exerciseAliasMap[name.lowercased()] = exerciseID
                }
                exerciseAliasMap[exerciseID.lowercased()] = exerciseID
                exerciseAliasMap[exerciseID.replacingOccurrences(of: "-", with: " ").lowercased()] = exerciseID
            }
        }

        // Also derive exercise IDs from condition safe/unsafe lists
        // This ensures every exercise referenced in the graph is discoverable,
        // even when the top-level "exercises" dict is absent.
        for condition in graph.conditions.values {
            for exerciseID in condition.safeExercises + condition.unsafeExercises {
                let idLower = exerciseID.lowercased()
                if exerciseAliasMap[idLower] == nil {
                    exerciseAliasMap[idLower] = exerciseID
                }
                // Also map with spaces instead of hyphens (e.g. "quad sets" → "quad-sets")
                let withSpaces = idLower.replacingOccurrences(of: "-", with: " ")
                if exerciseAliasMap[withSpaces] == nil {
                    exerciseAliasMap[withSpaces] = exerciseID
                }
            }
        }

        logger.debug("Lookup tables built: \(self.conditionAliasMap.count) condition aliases, \(self.exerciseAliasMap.count) exercise aliases")
    }

    // MARK: - Lookup

    /// Look up a condition by name (fuzzy match against all known aliases).
    func lookupCondition(_ name: String) -> (id: String, condition: KnownCondition)? {
        guard let graph = graph else { return nil }

        let nameLower = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        // Normalize: replace hyphens with spaces so "cat-cow" matches "cat cow"
        let nameNorm = nameLower.replacingOccurrences(of: "-", with: " ")

        // 1. Exact match against alias map (try both raw and normalized)
        if let conditionID = conditionAliasMap[nameLower],
           let condition = graph.conditions[conditionID] {
            return (conditionID, condition)
        }
        if nameNorm != nameLower, let conditionID = conditionAliasMap[nameNorm],
           let condition = graph.conditions[conditionID] {
            return (conditionID, condition)
        }

        // 2. Fuzzy match — longest matching alias wins.
        //
        // This previously iterated the alias Dictionary and returned the FIRST
        // substring hit. Swift randomizes dictionary order per process, so when
        // several aliases matched, the winner changed between launches. That is
        // unacceptable in a layer whose whole purpose is a deterministic verdict:
        // "runner's knee" is a substring of the "runner's knee lateral" alias, and
        // those two resolve to different conditions with different unsafe lists.
        if let match = TermMatching.bestMatch(for: name, in: conditionAliasMap),
           let condition = graph.conditions[match.value] {
            return (match.value, condition)
        }

        // 3. Retry against stop-word-stripped aliases ("syndrome", "chronic", ...),
        // still longest-wins so the outcome stays order-independent.
        let strippedAliases = Dictionary(
            conditionAliasMap.map { (normalizeConditionName($0.key.replacingOccurrences(of: "-", with: " ")), $0.value) },
            uniquingKeysWith: { first, second in min(first, second) }
        )
        if let match = TermMatching.bestMatch(for: normalizeConditionName(nameNorm), in: strippedAliases),
           let condition = graph.conditions[match.value] {
            return (match.value, condition)
        }

        return nil
    }

    /// Look up an exercise by name (fuzzy match against known aliases).
    /// Returns the exercise ID and (optionally) the full KnownExercise metadata.
    /// When the graph has no explicit exercises dict, the ID is still resolved
    /// from condition safe/unsafe lists so verification works.
    func lookupExercise(_ name: String) -> (id: String, exercise: KnownExercise)? {
        guard let graph = graph else { return nil }

        let nameLower = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        // Normalize: replace hyphens with spaces so "cat-cow" matches "cat cow"
        let nameNorm = nameLower.replacingOccurrences(of: "-", with: " ")
        let exercises = graph.exercises ?? [:]

        // Helper to return exercise or synthetic
        func resolve(_ exerciseID: String) -> (String, KnownExercise) {
            if let exercise = exercises[exerciseID] {
                return (exerciseID, exercise)
            }
            return (exerciseID, syntheticExercise(id: exerciseID))
        }

        // 1. Exact match against alias map (try both raw and normalized)
        if let exerciseID = exerciseAliasMap[nameLower] {
            return resolve(exerciseID)
        }
        if nameNorm != nameLower, let exerciseID = exerciseAliasMap[nameNorm] {
            return resolve(exerciseID)
        }

        // 2. Fuzzy match — longest matching alias wins, so the result is the same on
        // every launch. First-match-wins over a Dictionary meant "Wrist Curl" could
        // resolve to `wrist-curls` (unsafe for tennis elbow) or `reverse-wrist-curls`
        // (safe for it) depending on the process hash seed. Preferring the longest
        // alias also picks the more specific exercise, which is the safer answer:
        // `lateral-step-ups` over `step-ups` for "Lateral Step Ups".
        if let match = TermMatching.bestMatch(for: name, in: exerciseAliasMap) {
            return resolve(match.value)
        }

        // 3. Normalized filename match (kebab-case comparison)
        let kebabName = nameLower
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "\u{2019}", with: "")
        if let exerciseID = exerciseAliasMap[kebabName] {
            return resolve(exerciseID)
        }
        if let exercise = exercises[kebabName] {
            return (kebabName, exercise)
        }

        return nil
    }

    /// Create a minimal KnownExercise from condition cross-references
    /// when the graph doesn't have an explicit exercises dictionary.
    private func syntheticExercise(id: String) -> KnownExercise {
        guard let graph = graph else {
            return KnownExercise(names: [id], targetRegions: [], category: "unknown", safeForConditions: [], unsafeForConditions: [])
        }
        var safeFor: [String] = []
        var unsafeFor: [String] = []
        for (conditionID, condition) in graph.conditions {
            if condition.safeExercises.contains(id) { safeFor.append(conditionID) }
            if condition.unsafeExercises.contains(id) { unsafeFor.append(conditionID) }
        }
        let displayName = id.replacingOccurrences(of: "-", with: " ").capitalized
        return KnownExercise(names: [displayName, id], targetRegions: [], category: "unknown", safeForConditions: safeFor, unsafeForConditions: unsafeFor)
    }

    // MARK: - Verification

    /// Verify a specific exercise-condition pair.
    /// Returns .verified if the graph confirms it's safe, .contraindicated if unsafe,
    /// or .unverified if we don't have data (unknown ≠ wrong).
    func verify(exercise exerciseName: String, forCondition conditionName: String) -> VerificationTier {
        guard graph != nil else {
            logger.warning("⚠️ verify() called but graph is nil")
            return .unverified
        }

        let conditionLookup = lookupCondition(conditionName)
        let exerciseLookup = lookupExercise(exerciseName)

        logger.debug("🔍 verify(\"\(exerciseName)\", for: \"\(conditionName)\") → condition: \(conditionLookup?.id ?? "NOT FOUND"), exercise: \(exerciseLookup?.id ?? "NOT FOUND")")

        // If we don't know either the condition or the exercise, it's unverified
        guard let (_, condition) = conditionLookup else { return .unverified }
        guard let (exerciseID, _) = exerciseLookup else { return .unverified }

        // Check if the exercise is in the condition's unsafe list
        if condition.unsafeExercises.contains(exerciseID) {
            return .contraindicated(
                reason: "\"\(exerciseName)\" is not recommended for \(conditionName). This exercise may aggravate the condition."
            )
        }

        // Check if the exercise is in the condition's safe list
        if condition.safeExercises.contains(exerciseID) {
            return .verified
        }

        // Exercise and condition are both known, but this specific pair isn't mapped
        // This is still unverified — we don't assume it's safe or unsafe
        return .unverified
    }

    /// Verify an entire rehab plan against diagnosed conditions.
    func verifyPlan(_ plan: RehabPlan, conditions: [String]) -> PlanVerificationResult {
        var exerciseResults: [(exercise: RehabExercise, tier: VerificationTier)] = []
        var unverifiedExercises: [RehabExercise] = []
        var contraindicatedExercises: [(exercise: RehabExercise, reason: String)] = []

        // Check each exercise against all conditions
        for exercise in plan.exercises {
            var worstTier: VerificationTier = .unverified
            var contraindicationReason: String?
            // "Verified for condition A" must not stand in for "checked against
            // condition B". Previously a single .verified overwrote the tier, so an
            // exercise the graph knows nothing about for the user's OTHER condition
            // was excluded from `unverifiedExercises` and therefore never reached
            // cross-model verification. An unknown pairing is not a safe pairing.
            var hasUnknownCondition = false
            var hasVerifiedCondition = false

            for condition in conditions {
                let tier = verify(exercise: exercise.name, forCondition: condition)

                switch tier {
                case .contraindicated(let reason):
                    // Contraindicated takes highest priority and is terminal.
                    worstTier = tier
                    contraindicationReason = reason
                case .verified:
                    hasVerifiedCondition = true
                case .unverified:
                    hasUnknownCondition = true
                }
            }

            if case .contraindicated = worstTier {
                // Keep the contraindication.
            } else if hasUnknownCondition {
                worstTier = .unverified
            } else if hasVerifiedCondition {
                worstTier = .verified
            }

            exerciseResults.append((exercise, worstTier))

            switch worstTier {
            case .unverified:
                unverifiedExercises.append(exercise)
            case .contraindicated(let reason):
                contraindicatedExercises.append((exercise, contraindicationReason ?? reason))
            case .verified:
                break
            }
        }

        // Check which conditions are known
        let conditionResults = conditions.map { condition in
            (condition: condition, isKnown: lookupCondition(condition) != nil)
        }

        logger.info("Plan verification: \(exerciseResults.filter { $0.tier == .verified }.count) verified, \(contraindicatedExercises.count) contraindicated, \(unverifiedExercises.count) unverified out of \(plan.exercises.count) exercises")

        return PlanVerificationResult(
            exerciseResults: exerciseResults,
            conditionResults: conditionResults,
            unverifiedExercises: unverifiedExercises,
            contraindicatedExercises: contraindicatedExercises
        )
    }

    // MARK: - Red Flags

    /// Get red flags for a condition from the knowledge graph.
    func redFlags(forCondition conditionName: String) -> [String]? {
        guard let (_, condition) = lookupCondition(conditionName) else { return nil }
        return condition.redFlags.isEmpty ? nil : condition.redFlags
    }

    /// Get referral criteria for a condition from the knowledge graph.
    func referralCriteria(forCondition conditionName: String) -> [String]? {
        guard let (_, condition) = lookupCondition(conditionName) else { return nil }
        return condition.referIfPresent.isEmpty ? nil : condition.referIfPresent
    }

    // MARK: - Helpers

    private func normalizeConditionName(_ name: String) -> String {
        var normalized = name.lowercased()
        // Remove common medical suffixes/prefixes that might vary
        let stripWords = ["syndrome", "disease", "disorder", "injury", "bilateral", "unilateral", "left", "right", "acute", "chronic"]
        for word in stripWords {
            normalized = normalized.replacingOccurrences(of: word, with: "")
        }
        // Collapse whitespace
        normalized = normalized.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return normalized
    }
}
