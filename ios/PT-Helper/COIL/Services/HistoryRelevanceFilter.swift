import Foundation

/// Classifies user health history items by relevance to the current pain assessment regions.
enum HistoryRelevanceFilter {

    enum Relevance: Comparable {
        case backgroundOnly
        case possiblyRelevant
        case directlyRelevant
    }

    struct ClassifiedSurgery {
        let surgery: UserProfile.Surgery
        let relevance: Relevance
    }

    struct ClassifiedInjury {
        let injury: UserProfile.Injury
        let relevance: Relevance
    }

    // MARK: - Public API

    /// Classify all surgeries relative to the assessed body regions.
    static func classify(surgeries: [UserProfile.Surgery], assessedRegions: [BodyRegion]) -> [ClassifiedSurgery] {
        let assessedKeys = Set(assessedRegions.map { normalizeZoneKey($0.zoneKey) })
        return surgeries.map { surgery in
            let relevance = classifySurgery(surgery, assessedKeys: assessedKeys)
            return ClassifiedSurgery(surgery: surgery, relevance: relevance)
        }
    }

    /// Classify all injuries relative to the assessed body regions.
    static func classify(injuries: [UserProfile.Injury], assessedRegions: [BodyRegion]) -> [ClassifiedInjury] {
        let assessedKeys = Set(assessedRegions.map { normalizeZoneKey($0.zoneKey) })
        return injuries.map { injury in
            let relevance = classifyInjury(injury, assessedKeys: assessedKeys)
            return ClassifiedInjury(injury: injury, relevance: relevance)
        }
    }

    // MARK: - Classification Logic

    private static func classifySurgery(_ surgery: UserProfile.Surgery, assessedKeys: Set<String>) -> Relevance {
        // Recovery override: still recovering or has restrictions → always relevant
        if let status = surgery.recoveryStatus,
           status == "Still recovering" || status == "Have restrictions" {
            return .directlyRelevant
        }

        let surgeryKey = bodyAreaToZoneKey(surgery.bodyArea ?? surgery.name)

        // Direct anatomical match
        if assessedKeys.contains(surgeryKey) {
            return .directlyRelevant
        }

        // Kinetic chain match
        if assessedKeys.contains(where: { isInKineticChain(surgeryKey, $0) }) {
            return temporalRelevance(year: surgery.year, isSurgical: true)
        }

        // No anatomical or chain match — temporal + surgical weight
        return temporalRelevance(year: surgery.year, isSurgical: true, baseline: .backgroundOnly)
    }

    private static func classifyInjury(_ injury: UserProfile.Injury, assessedKeys: Set<String>) -> Relevance {
        // Recovery override: still dealing with it → always relevant
        if injury.isCurrent {
            return .directlyRelevant
        }
        if let status = injury.recoveryStatus, status == "Still dealing with it" {
            return .directlyRelevant
        }

        let injuryKey = bodyAreaToZoneKey(injury.bodyArea)

        // Direct anatomical match
        if assessedKeys.contains(injuryKey) {
            return .directlyRelevant
        }

        // Kinetic chain match
        if assessedKeys.contains(where: { isInKineticChain(injuryKey, $0) }) {
            return temporalRelevance(year: injury.year, isSurgical: false)
        }

        return .backgroundOnly
    }

    // MARK: - Temporal Relevance

    /// Apply temporal rules: <1yr always relevant, 1-5yr possibly relevant, >5yr background (surgical with restrictions override handled above).
    private static func temporalRelevance(year: Int?, isSurgical: Bool, baseline: Relevance = .possiblyRelevant) -> Relevance {
        guard let year = year else {
            // Unknown year — assume possibly relevant if there's a chain match
            return baseline == .backgroundOnly ? .backgroundOnly : .possiblyRelevant
        }

        let currentYear = Calendar.current.component(.year, from: Date())
        let yearsAgo = currentYear - year

        if yearsAgo <= 1 {
            return .directlyRelevant
        } else if yearsAgo <= 5 {
            return .possiblyRelevant
        } else {
            // >5 years: surgical history normally stays possiblyRelevant while injuries
            // fade to background — surgeries keep mattering longer.
            //
            // That bump must not apply when the caller has already established there is
            // NO anatomical and NO kinetic-chain match (baseline .backgroundOnly).
            // `classifySurgery` passes exactly that, but the baseline was only consulted
            // inside the unknown-year branch above — and `Surgery.year` is a
            // non-optional Int, so for surgeries that branch is unreachable and the
            // parameter was dead. The effect: a decades-old surgery unrelated to
            // anything being assessed still ranked possiblyRelevant and was fed to the
            // AI prompt as though it might bear on the current complaint.
            if baseline == .backgroundOnly {
                return .backgroundOnly
            }
            return isSurgical ? .possiblyRelevant : .backgroundOnly
        }
    }

    // MARK: - Kinetic Chain Map

    /// Bidirectional kinetic chain relationships based on PT movement chains.
    /// Each key maps to its directly connected regions.
    private static let kineticChainMap: [String: Set<String>] = {
        // Build bidirectional map from connection pairs
        let connections: [(String, String)] = [
            // Lower extremity chain
            ("ankle_foot", "calf_shin"),
            ("calf_shin", "knee"),
            ("knee", "thigh"),
            ("knee", "hamstring"),
            ("thigh", "hip"),
            ("hamstring", "hip"),
            ("hamstring", "glute"),
            ("hip", "glute"),
            ("hip", "lower_back"),
            ("glute", "lower_back"),

            // Spine chain
            ("lower_back", "abdomen"),
            ("lower_back", "upper_back"),
            ("upper_back", "neck"),
            ("upper_back", "chest"),
            ("neck", "head"),

            // Upper extremity chain
            ("neck", "shoulder"),
            ("upper_back", "shoulder"),
            ("chest", "shoulder"),
            ("shoulder", "upper_arm"),
            ("upper_arm", "elbow"),
            ("elbow", "forearm"),
            ("forearm", "wrist_hand"),
        ]

        var map: [String: Set<String>] = [:]
        for (a, b) in connections {
            map[a, default: []].insert(b)
            map[b, default: []].insert(a)
        }
        return map
    }()

    /// Check if two normalized zone keys are in the same kinetic chain (directly connected).
    private static func isInKineticChain(_ key1: String, _ key2: String) -> Bool {
        guard let neighbors = kineticChainMap[key1] else { return false }
        return neighbors.contains(key2)
    }

    // MARK: - Zone Key Normalization

    /// Strip left/right prefix from zone keys to get the anatomical region.
    /// e.g., "left_knee" → "knee", "right_ankle_foot" → "ankle_foot", "lower_back" → "lower_back"
    static func normalizeZoneKey(_ key: String) -> String {
        let lower = key.lowercased()
        if lower.hasPrefix("left_") {
            return String(lower.dropFirst(5))
        }
        if lower.hasPrefix("right_") {
            return String(lower.dropFirst(6))
        }
        return lower
    }

    /// Convert a free-text body area string to a normalized zone key.
    /// Handles common PT terms like "Left Knee", "Right Shoulder", "Lower Back", etc.
    static func bodyAreaToZoneKey(_ bodyArea: String) -> String {
        let normalized = bodyArea.lowercased()
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: " ", with: "_")

        // Map common terms to our zone keys
        let termMap: [String: String] = [
            // Direct matches
            "knee": "knee",
            "shoulder": "shoulder",
            "hip": "hip",
            "ankle": "ankle_foot",
            "foot": "ankle_foot",
            "ankle/foot": "ankle_foot",
            "ankle_foot": "ankle_foot",
            "wrist": "wrist_hand",
            "hand": "wrist_hand",
            "wrist/hand": "wrist_hand",
            "wrist_hand": "wrist_hand",
            "elbow": "elbow",
            "neck": "neck",
            "head": "head",
            "back": "lower_back",
            "lower_back": "lower_back",
            "upper_back": "upper_back",
            "chest": "chest",
            "abdomen": "abdomen",
            "thigh": "thigh",
            "quad": "thigh",
            "quadricep": "thigh",
            "hamstring": "hamstring",
            "calf": "calf_shin",
            "shin": "calf_shin",
            "calf_shin": "calf_shin",
            "calf/shin": "calf_shin",
            "glute": "glute",
            "gluteal": "glute",
            "buttock": "glute",
            "upper_arm": "upper_arm",
            "bicep": "upper_arm",
            "tricep": "upper_arm",
            "forearm": "forearm",
            // Spine terms
            "spine": "lower_back",
            "lumbar": "lower_back",
            "thoracic": "upper_back",
            "cervical": "neck",
            // Common surgery terms
            "acl": "knee",
            "mcl": "knee",
            "meniscus": "knee",
            "rotator_cuff": "shoulder",
            "labrum": "shoulder",
            "achilles": "ankle_foot",
            "plantar_fascia": "ankle_foot",
            "carpal_tunnel": "wrist_hand",
            "hernia": "abdomen",
            "spinal_fusion": "lower_back",
            "disc": "lower_back",
            "herniated_disc": "lower_back",
        ]

        // Strip left/right prefix first
        let stripped = normalizeZoneKey(normalized)

        if let mapped = termMap[stripped] {
            return mapped
        }

        // Fuzzy match — longest matching term wins, so the zone is the same on every
        // launch. Iterating the Dictionary and taking the first containment hit was
        // order-dependent AND wrong for nested terms: "upper_back_strain" contains
        // both "back" (-> lower_back) and "upper_back" (-> upper_back), so the zone a
        // surgery was filed under could flip between runs, changing whether that
        // history was judged relevant enough to enter the AI prompt.
        if let match = TermMatching.bestMatch(for: stripped, in: termMap) {
            return match.value
        }

        // Fallback: return the stripped key as-is
        return stripped
    }
}
