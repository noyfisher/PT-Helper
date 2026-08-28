import Foundation

/// Deterministic, spelling-tolerant matching for clinical terms.
///
/// Two safety layers independently grew their own ad-hoc matching and both got it
/// wrong in the same two ways:
///
/// 1. **Non-determinism.** `KnowledgeGraphService` resolved a name by iterating an
///    alias `Dictionary` and returning the *first* substring hit. Swift randomizes
///    dictionary order per process, so when several aliases matched, the winner
///    changed between launches — and for the shipped graph those aliases can carry
///    opposite verdicts (`step-ups` is safe for an ACL sprain, `lateral-step-ups`
///    is not). A deterministic layer must not decide safety by hash seed.
///
/// 2. **Spelling brittleness.** `ExerciseContraindicationChecker` matched blocked
///    keywords with a plain `contains`, so the hyphenated table entry `"sit-up"`
///    missed the "Sit Ups" and "Situps" spellings the model actually emits — and
///    for a herniated disc that table is the only deterministic gate.
///
/// `ComorbidityInteractionMap.canonicalize` already had the right idea (longest
/// alias wins; compound aliases substring-match while single-token aliases must
/// match a whole token). This generalises it so both layers share one reviewed
/// implementation instead of three divergent ones.
enum TermMatching {

    // MARK: - Normalisation

    /// Lowercase, collapse every run of non-alphanumerics to a single space, trim.
    ///
    /// Folds the spelling variants that matter clinically: `"Sit-Ups"`,
    /// `"Sit Ups"` and `"sit ups"` all become `"sit ups"`, and `"Golfer's Elbow"`
    /// becomes `"golfer s elbow"`.
    static func normalize(_ raw: String) -> String {
        let scalars = raw.lowercased().map { character -> Character in
            character.isLetter || character.isNumber ? character : " "
        }
        return String(scalars)
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
    }

    /// Normalised form with all separators removed: `"sit-up"` -> `"situp"`.
    /// Lets a term match a run-together spelling such as `"Situps"`.
    private static func squashed(_ raw: String) -> String {
        normalize(raw).replacingOccurrences(of: " ", with: "")
    }

    /// Whitespace-separated tokens of the normalised form.
    static func tokens(_ raw: String) -> [String] {
        normalize(raw).split(separator: " ").map(String.init)
    }

    /// Crude singular form so `"jumps"` and `"jump"` compare equal. Deliberately
    /// naive — it only strips a trailing "s" from tokens long enough for that to be
    /// meaningful, which covers the exercise-name plurals without touching words
    /// like "press" or "hips".
    private static func singularized(_ token: String) -> String {
        guard token.count > 3, token.hasSuffix("s"), !token.hasSuffix("ss") else { return token }
        return String(token.dropLast())
    }

    private static func singularTokenSet(_ raw: String) -> Set<String> {
        Set(tokens(raw).map(singularized))
    }

    /// True when `term` contains a separator (space, hyphen, apostrophe...).
    /// Compound terms are inherently distinctive and safe to match loosely;
    /// single-token terms are not — matching `"ra"` loosely would hit "zebrafish".
    private static func isCompound(_ term: String) -> Bool {
        tokens(term).count > 1
    }

    // MARK: - Containment

    /// Does `text` contain `term`, tolerating hyphen/space/apostrophe and word-order
    /// differences?
    ///
    /// Single-token terms keep plain substring semantics, exactly as before, so
    /// existing behaviour (and the deliberate breadth of terms like `"extension"`)
    /// is unchanged. Only compound terms gain the extra tolerance, which is where
    /// the misses were.
    static func containsTerm(_ term: String, in text: String) -> Bool {
        let normalizedTerm = normalize(term)
        guard !normalizedTerm.isEmpty else { return false }
        let normalizedText = normalize(text)

        // Plain substring on the normalised forms. Covers the single-token case and
        // the common compound case ("deep squat" in "deep squat hold").
        if normalizedText.contains(normalizedTerm) { return true }

        guard isCompound(normalizedTerm) else { return false }

        // "sit-up" -> "situp" inside "Situps" -> "situps".
        if squashed(text).contains(squashed(term)) { return true }

        // Word order: "jump squat" should match "Squat Jumps".
        let termTokens = singularTokenSet(normalizedTerm)
        let textTokens = singularTokenSet(normalizedText)
        return !termTokens.isEmpty && termTokens.isSubset(of: textTokens)
    }

    /// True when any of `terms` is contained in `text`.
    static func containsAnyTerm(_ terms: some Sequence<String>, in text: String) -> Bool {
        terms.contains { containsTerm($0, in: text) }
    }

    // MARK: - Deterministic alias lookup

    /// Resolve `input` against an alias map deterministically.
    ///
    /// The preference order matters for safety, and mirrors the rule
    /// `ExerciseImageService` already uses for image keys:
    ///
    /// 1. **Exact** normalised equality.
    /// 2. **Alias inside the input** — a known term found within a longer name.
    ///    Prefer the *longest* such alias: for "Modified Cat-Cow Stretch for Lower
    ///    Back Relief", `cat cow stretch` is a better answer than `stretch`.
    /// 3. **Input inside the alias** — the input is underspecified and several
    ///    specialisations match. Prefer the *shortest* alias, i.e. the least
    ///    specialised reading. This is the safety-critical direction: "Wrist Curl"
    ///    matches both `wrist curls` and `reverse wrist curls`, and those carry
    ///    opposite verdicts for tennis elbow. Taking the shortest resolves to the
    ///    plain movement the user most likely meant rather than silently assuming a
    ///    specialised variant that happens to be the safe one.
    ///
    /// Rank 2 beats rank 3: a known term present in the input is stronger evidence
    /// than guessing which specialisation an underspecified input refers to. Ties
    /// break lexicographically so the result never depends on dictionary order.
    static func bestMatch<Value>(for input: String, in aliasMap: [String: Value]) -> (alias: String, value: Value)? {
        let normalizedInput = normalize(input)
        guard !normalizedInput.isEmpty else { return nil }

        // Rank 1: exact.
        var exact: (alias: String, value: Value)?
        // Rank 2: alias ⊂ input, longest wins.
        var aliasInInput: (alias: String, value: Value)?
        // Rank 3: input ⊂ alias, shortest wins.
        var inputInAlias: (alias: String, value: Value)?

        for (alias, value) in aliasMap {
            let normalizedAlias = normalize(alias)
            guard !normalizedAlias.isEmpty else { continue }

            if normalizedAlias == normalizedInput || squashed(alias) == squashed(input) {
                if exact == nil || alias < exact!.alias { exact = (alias, value) }
                continue
            }

            // Single-token terms on both sides must match as whole tokens, never as
            // substrings, so "row" cannot match "narrow".
            let bothSingleToken = !isCompound(normalizedAlias) && !isCompound(normalizedInput)
            guard !bothSingleToken else { continue }

            if normalizedInput.contains(normalizedAlias) {
                let currentLength = aliasInInput.map { normalize($0.alias).count } ?? -1
                if normalizedAlias.count > currentLength
                    || (normalizedAlias.count == currentLength && alias < aliasInInput!.alias) {
                    aliasInInput = (alias, value)
                }
            } else if normalizedAlias.contains(normalizedInput) {
                let currentLength = inputInAlias.map { normalize($0.alias).count } ?? Int.max
                if normalizedAlias.count < currentLength
                    || (normalizedAlias.count == currentLength && alias < inputInAlias!.alias) {
                    inputInAlias = (alias, value)
                }
            }
        }

        return exact ?? aliasInInput ?? inputInAlias
    }
}
