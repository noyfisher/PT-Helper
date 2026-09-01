import Foundation
import os
import UIKit
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage

/// Loads, caches, and serves AI-generated exercise illustration images.
/// Falls back gracefully when no image is available (the view layer shows an SF Symbol instead).
/// Not @MainActor — disk I/O runs off the main thread.
final class ExerciseImageService: @unchecked Sendable {
    static let shared = ExerciseImageService()

    // MARK: - Mapping

    /// Mapping from normalized filename key to image metadata.
    /// Loaded once from the bundled exercise_image_mapping.json.
    private var mapping: [String: ImageEntry] = [:]

    struct ImageEntry: Decodable {
        let name: String
        let filename: String
        let category: String
        let target_area: String
        let end_filename: String?
        let body_position: String?
        let aliases: [String]?
    }

    /// Bundled-alias lookup: alias-key → canonical-key. Built once from `mapping`
    /// after `loadMapping()`. Source of truth is the bundled JSON's per-entry
    /// `aliases` array (populated via `scripts/seed_aliases_from_swift.py` +
    /// `scripts/rebuild_image_mapping.py`). PR 3 deleted the legacy hardcoded
    /// Swift `aliasMap` — aliases now live entirely in reviewable JSON.
    private var bundledAliases: [String: String] = [:]

    // MARK: - Image Match Metadata

    /// Describes how an exercise name was resolved to an image key.
    enum MatchType: String {
        case exact              // Layers 1-3: imageFileName, normalized name, or alias
        case prefixFuzzy        // Layer 4: longestPrefixMatch
        case suffixFuzzy        // Layer 5: suffixMatch
        case pluralToggle       // Layer 6: plural/singular toggle
        case synonymExpansion   // Layer 7: body-part synonym expansion
        case stripped           // Layer 8: parentheticals + qualifier tokens removed, then retry
    }

    /// Result of resolving an exercise to an image key, including how it was matched.
    struct ImageMatch {
        let key: String
        let matchType: MatchType
    }

    // MARK: - Caches

    /// In-memory image cache (evicted when the app is backgrounded / under memory pressure).
    private let memoryCache = NSCache<NSString, UIImage>()

    /// Disk cache directory: Library/Caches/exercise-images/
    private let diskCacheURL: URL = {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return caches.appendingPathComponent("exercise-images", isDirectory: true)
    }()

    /// Firebase Storage download-URL cache so we only resolve each path once per session.
    private var downloadURLCache: [String: URL] = [:]

    /// Track in-flight downloads to avoid duplicate network requests.
    private var activeDownloads: [String: Task<UIImage?, Never>] = [:]

    /// Track in-flight on-demand generation requests (dedup).
    private var activeGenerations: [String: Task<UIImage?, Never>] = [:]

    /// Normalized keys already logged to Firestore this session (dedup).
    private var loggedThisSession: Set<String> = []

    /// Firestore aliases merged with hardcoded aliasMap (fetched once per session).
    private var firestoreAliases: [String: String]?
    private var firestoreAliasesLastFetch: Date?

    /// Lock protecting mutable dictionaries from concurrent access.
    private let lock = NSLock()

    // MARK: - Firebase Storage

    private let storageRef: StorageReference = {
        let storage = Storage.storage()
        return storage.reference().child("exercise-images")
    }()

    // MARK: - Init

    private init() {
        // Create disk cache directory
        try? FileManager.default.createDirectory(at: diskCacheURL, withIntermediateDirectories: true)

        // Set memory cache limits (e.g. ~50 images)
        memoryCache.countLimit = 60

        // Load bundled mapping
        loadMapping()
    }

    // MARK: - Public API

    /// Whether an image is available for this exercise (in the mapping).
    func hasImage(for exercise: RehabExercise) -> Bool {
        imageKey(for: exercise) != nil
    }

    /// Load the exercise image asynchronously.
    /// Returns nil if no image is available (caller should show SF Symbol fallback).
    func loadImage(for exercise: RehabExercise) async -> UIImage? {
        guard let key = imageKey(for: exercise) else { return nil }
        return await loadImage(forKey: key)
    }

    /// Preload all images for a rehab plan in the background.
    func preloadImages(for exercises: [RehabExercise]) {
        for exercise in exercises {
            guard let key = imageKey(for: exercise) else { continue }
            // Only preload if not already cached
            if memoryCache.object(forKey: key as NSString) == nil {
                Task {
                    _ = await loadImage(forKey: key)
                }
            }
        }
    }

    /// Returns exercises that do NOT have a matching image in the mapping.
    /// Useful for logging which exercises still need images generated.
    func exercisesWithoutImages(in exercises: [RehabExercise]) -> [RehabExercise] {
        exercises.filter { imageKey(for: $0) == nil }
    }

    /// Load animated image data (GIF/APNG) from cache or Firebase Storage.
    /// Returns raw Data so the caller can create an animated UIImageView.
    func loadAnimatedImageData(named filename: String) async -> Data? {
        // Check disk cache
        let diskPath = diskCacheURL.appendingPathComponent(filename)
        if let data = try? Data(contentsOf: diskPath) {
            return data
        }

        // Try Firebase Storage
        let animRef = storageRef.child(filename)
        let maxSize: Int64 = 5 * 1024 * 1024 // 5 MB for animations

        do {
            let data = try await animRef.data(maxSize: maxSize)
            // Cache to disk
            try? data.write(to: diskPath, options: .atomic)
            return data
        } catch {
            // No animated version available — that's fine
            return nil
        }
    }

    // MARK: - End Image Support

    /// Whether a start+end image pair is available for this exercise.
    func hasImagePair(for exercise: RehabExercise) -> Bool {
        guard let key = imageKey(for: exercise),
              let entry = mapping[key] else { return false }
        return entry.end_filename != nil
    }

    /// Load the end-position image for an exercise.
    /// Returns nil if no end image exists.
    func loadEndImage(for exercise: RehabExercise) async -> UIImage? {
        guard let key = imageKey(for: exercise),
              let entry = mapping[key],
              let endFilename = entry.end_filename else { return nil }

        let endKey = endFilename.replacingOccurrences(of: ".png", with: "")
        return await loadImageByFilename(endFilename, cacheKey: endKey)
    }

    /// Cache + Firebase-Storage fetch keyed by an explicit filename. Used for end-frame
    /// images, which don't have their own mapping entry (the start entry carries the
    /// `end_filename` field, so a forKey: lookup would miss).
    private func loadImageByFilename(_ filename: String, cacheKey: String) async -> UIImage? {
        if let cached = memoryCache.object(forKey: cacheKey as NSString) {
            return cached
        }
        if let diskImage = loadFromDisk(key: cacheKey) {
            memoryCache.setObject(diskImage, forKey: cacheKey as NSString)
            return diskImage
        }
        let task: Task<UIImage?, Never> = lock.withLock {
            if let existing = activeDownloads[cacheKey] { return existing }
            let new = Task<UIImage?, Never> {
                let image = await self.downloadFromStorageByFilename(filename, cacheKey: cacheKey)
                _ = self.lock.withLock { self.activeDownloads.removeValue(forKey: cacheKey) }
                return image
            }
            activeDownloads[cacheKey] = new
            return new
        }
        return await task.value
    }

    private func downloadFromStorageByFilename(_ filename: String, cacheKey: String) async -> UIImage? {
        let imageRef = storageRef.child(filename)
        let maxSize: Int64 = 2 * 1024 * 1024
        do {
            let data = try await imageRef.data(maxSize: maxSize)
            guard let image = UIImage(data: data) else { return nil }
            memoryCache.setObject(image, forKey: cacheKey as NSString)
            saveToDisk(key: cacheKey, data: data)
            return image
        } catch {
            AppLogger.images.error("Download failed for \(filename): \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - On-Demand Image Generation

    /// Request on-demand image generation via Cloud Function.
    /// Returns the generated image, or nil if generation failed.
    /// Deduplicates concurrent requests for the same exercise.
    func requestImageGeneration(for exercise: RehabExercise) async -> UIImage? {
        guard let user = Auth.auth().currentUser else { return nil }
        let normalized = normalizeName(exercise.name)

        // Dedup: reuse in-flight generation task
        let task: Task<UIImage?, Never> = lock.withLock {
            if let existing = activeGenerations[normalized] {
                return existing
            }

            let newTask = Task<UIImage?, Never> {
                defer {
                    _ = self.lock.withLock { self.activeGenerations.removeValue(forKey: normalized) }
                }
                return await self.performImageGeneration(for: exercise, user: user, normalized: normalized)
            }

            activeGenerations[normalized] = newTask
            return newTask
        }

        return await task.value
    }

    private func performImageGeneration(for exercise: RehabExercise, user: User, normalized: String) async -> UIImage? {
        guard let idToken = try? await user.getIDToken() else { return nil }
        guard let url = URL(string: APIConfig.generateImageURL) else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 300 // 5 min for generation + QA

        let body: [String: Any] = [
            "exerciseName": exercise.name,
            "exerciseCategory": exercise.exerciseCategory ?? "general",
            "targetArea": exercise.targetArea,
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else { return nil }

            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let status = json?["status"] as? String

            if httpResponse.statusCode == 200 {
                if let key = json?["key"] as? String {
                    // Image was found or generated — reload from Firebase Storage
                    // Update in-memory mapping if it's a new image
                    if status == "success", let imageUrl = json?["imageUrl"] as? String {
                        AppLogger.images.info("On-demand image generated for \(exercise.name) at \(imageUrl)")
                    }
                    return await loadImage(forKey: key)
                }
            }

            AppLogger.images.warning("Image generation returned status=\(status ?? "unknown") for \(exercise.name)")
            return nil
        } catch {
            AppLogger.images.error("Image generation request failed for \(exercise.name): \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Firestore Aliases

    /// Fetch remote aliases from Firestore and merge with hardcoded aliasMap.
    func fetchRemoteAliases() async {
        // Only fetch once per hour. The freshness check reads
        // `firestoreAliasesLastFetch` under the SAME lock that guards its write —
        // it was previously read unsynchronised, a data race with the write below
        // (every exercise card calls this on appear, so concurrent entry is the
        // normal case, not an edge one).
        let isFresh = lock.withLock {
            guard let lastFetch = firestoreAliasesLastFetch else { return false }
            return Date().timeIntervalSince(lastFetch) < 3600
        }
        if isFresh { return }

        do {
            let doc = try await Firestore.firestore().collection("config").document("exerciseImageAliases").getDocument()
            if let aliases = doc.data()?["aliases"] as? [String: String] {
                lock.withLock {
                    firestoreAliases = aliases
                    firestoreAliasesLastFetch = Date()
                }
                AppLogger.images.info("Fetched \(aliases.count) remote aliases from Firestore")
            }
        } catch {
            AppLogger.images.warning("Failed to fetch remote aliases: \(error.localizedDescription)")
        }
    }

    // MARK: - Key Resolution


    /// Body-part synonyms for token-level replacement.
    private static let synonyms: [String: String] = [
        "quadriceps": "quad",
        "quadricep": "quad",
        "hamstrings": "hamstring",
        "calves": "calf",
        "abdominals": "abdominal",
    ]

    /// Resolve the mapping key for an exercise.
    /// Priority: imageFileName → normalized name → alias → fuzzy match → nil.
    func imageKey(for exercise: RehabExercise) -> String? {
        resolveImageMatch(for: exercise)?.key
    }

    /// Resolve the mapping key for an exercise, including how it was matched.
    /// Returns nil when no match is found at any layer.
    func resolveImageMatch(for exercise: RehabExercise) -> ImageMatch? {
        // 1. Explicit imageFileName from AI / Firestore
        if let fileName = exercise.imageFileName, mapping[fileName] != nil {
            return ImageMatch(key: fileName, matchType: .exact)
        }

        // 2. Normalize the exercise name and look up
        let normalized = normalizeName(exercise.name)
        if mapping[normalized] != nil {
            return ImageMatch(key: normalized, matchType: .exact)
        }

        // 3. Check bundled aliases (per-entry `aliases` array in exercise_image_mapping.json).
        // Source of truth as of PR 1. The legacy hardcoded Swift `aliasMap` was
        // deleted in PR 3 — bundled aliases are functionally equivalent (seeded
        // from the same source via `scripts/seed_aliases_from_swift.py`) and live
        // in reviewable JSON instead of a 200-line Swift dictionary.
        if let canonical = bundledAliases[normalized], mapping[canonical] != nil {
            return ImageMatch(key: canonical, matchType: .exact)
        }

        // 4. Firestore remote aliases (hot-fix lever for production-discovered names).
        if let remoteAlias = lock.withLock({ firestoreAliases?[normalized] }), mapping[remoteAlias] != nil {
            return ImageMatch(key: remoteAlias, matchType: .exact)
        }

        // 4-8. Fuzzy matching + stripped fallback (cached under original `normalized` key)
        return lock.withLock {
            if let cached = fuzzyMatchCache[normalized] {
                return cached
            }
            // Layers 4-7: existing fuzzy matcher on the original normalized form
            var result = fuzzyMatch(normalized)

            // Layer 4b: Retry fuzzy matching against the AI-provided imageFileName.
            // The AI often produces a high-quality kebab-case `imageFileName` that's a
            // single transformation off canonical (plural toggle, prefix modifier, suffix
            // qualifier). The original Layer 1 only does exact-match on imageFileName,
            // so a near-correct guess was thrown away. Feed it back into Layers 4-7 as
            // a secondary candidate before falling through to qualifier stripping.
            if result == nil, let fileName = exercise.imageFileName, !fileName.isEmpty,
               fileName != normalized {
                result = fuzzyMatch(fileName)
            }

            // Layer 8: strip qualifiers (parentheticals, em-dashes, qualifier tokens) and retry
            // alias + fuzzy lookup against the stripped form. Calls helpers directly (NOT
            // resolveImageMatch) to avoid polluting fuzzyMatchCache with stripped-key entries.
            if result == nil {
                let stripped = strippedKey(for: exercise.name)
                if !stripped.isEmpty && stripped != normalized {
                    if mapping[stripped] != nil {
                        result = ImageMatch(key: stripped, matchType: .stripped)
                    } else if let canonical = bundledAliases[stripped], mapping[canonical] != nil {
                        result = ImageMatch(key: canonical, matchType: .stripped)
                    } else if let fuzzy = fuzzyMatch(stripped) {
                        // Re-tag as .stripped so callers know how the match was derived.
                        result = ImageMatch(key: fuzzy.key, matchType: .stripped)
                    }
                }
            }
            fuzzyMatchCache[normalized] = result
            return result
        }
    }

    // MARK: - Qualifier Stripping (Layer 8)

    /// Tokens that carry no anatomical or movement information — safe to drop before re-matching.
    /// Kept conservative: never strips body parts, positions (supine/prone/standing), or movements.
    private static let qualifierTokens: Set<String> = [
        "free",         // "Band-Free"
        "modified",
        "bodyweight",
        "bilateral",
        "progressive",
        "progression",
        "eccentric",
        "isometric",
        "controlled",
        "gentle",
        "emphasis",
        "focus",
        "advanced",
        "beginner",
        "intermediate",
        "weeks",        // "Weeks 3-6"
        "week",
    ]

    /// Strip parentheticals, em/en-dashes, and qualifier tokens from a raw exercise name,
    /// then return the normalized hyphen-delimited key.
    /// e.g. "Standing Band-Free Shoulder ER (Isometric)" → "standing-shoulder-er"
    /// e.g. "Right Shoulder – Sleeper Stretch (Lying)" → "right-shoulder-sleeper-stretch-lying"
    private func strippedKey(for rawName: String) -> String {
        // 1. Remove anything between parentheses (including the parens themselves).
        var s = rawName
        while let openIdx = s.firstIndex(of: "(") {
            if let closeIdx = s[openIdx...].firstIndex(of: ")") {
                s.removeSubrange(openIdx...closeIdx)
            } else {
                // Unmatched "(" — bail out and use what we have.
                s.removeSubrange(openIdx...)
                break
            }
        }
        // 2. Em/en-dashes act as separators, not hyphens — replace with spaces so they
        // don't get folded into adjacent tokens by normalizeName.
        s = s.replacingOccurrences(of: "–", with: " ")
              .replacingOccurrences(of: "—", with: " ")
        // 3. Standard normalization to hyphen-delimited lowercase.
        let normalized = normalizeName(s)
        // 4. Drop qualifier tokens. Single-character tokens (artifacts of compound forms
        // like "I-Y-T") are also dropped — multi-letter abbreviations are preserved.
        let tokens = normalized.split(separator: "-").map(String.init)
        let filtered = tokens.filter { tok in
            !Self.qualifierTokens.contains(tok) && tok.count > 1
        }
        return filtered.joined(separator: "-")
    }

    // MARK: - Fuzzy Matching

    /// Cache for fuzzy-matched results to avoid redundant computation.
    /// Stores full ImageMatch (key + matchType) so callers know how the match was found.
    private var fuzzyMatchCache: [String: ImageMatch?] = [:]

    /// Layers 4-7: progressively looser matching strategies.
    private func fuzzyMatch(_ normalized: String) -> ImageMatch? {
        let toggled = normalized.hasSuffix("s") ? String(normalized.dropLast()) : normalized + "s"

        // Layer 3b: whole-string plural/singular toggle against an EXACT key.
        //
        // This has to run before the prefix/suffix layers, not after them. Those
        // layers happily match a longer, more specialised key, so a singular name
        // whose exact plural exists was hijacked before the toggle ever ran:
        // "Hamstring Curl" resolved to `hamstring-curl-band` (adds a resistance
        // band) rather than `hamstring-curls`, "Deadlift" to `dumbbell-deadlift`
        // (adds load), and "Dumbbell Lateral Raise" to the single-leg balance
        // variant. 62 singular forms in the shipped mapping resolved this way.
        //
        // An exact key differing only in plurality is a better answer than any
        // fuzzy match, and in a PT app the difference is not cosmetic: the
        // illustration is what the user copies, so a banded or single-leg variant
        // shown for an unloaded prescription is a wrong instruction.
        if mapping[toggled] != nil { return ImageMatch(key: toggled, matchType: .pluralToggle) }

        // Layer 4: Longest prefix match
        // e.g. "cat-cow-stretch-modified-for-lower-back-relief" starts with "cat-cow-stretch-"
        if let match = longestPrefixMatch(normalized) { return ImageMatch(key: match, matchType: .prefixFuzzy) }

        // Layer 5: Suffix match — AI omits position prefix
        // e.g. "calf-raises" is a suffix of "standing-calf-raises"
        if let match = suffixMatch(normalized) { return ImageMatch(key: match, matchType: .suffixFuzzy) }

        // Layer 6: fuzzy retries on the toggled form.
        if let match = longestPrefixMatch(toggled) { return ImageMatch(key: match, matchType: .pluralToggle) }
        if let match = suffixMatch(toggled) { return ImageMatch(key: match, matchType: .pluralToggle) }

        // Layer 7: Synonym expansion, then retry layers 2+4+5
        let expanded = applySynonyms(normalized)
        if expanded != normalized {
            if mapping[expanded] != nil { return ImageMatch(key: expanded, matchType: .synonymExpansion) }
            if let match = longestPrefixMatch(expanded) { return ImageMatch(key: match, matchType: .synonymExpansion) }
            if let match = suffixMatch(expanded) { return ImageMatch(key: match, matchType: .synonymExpansion) }
            // Also try plural toggle on expanded form
            let expandedToggled = expanded.hasSuffix("s") ? String(expanded.dropLast()) : expanded + "s"
            if mapping[expandedToggled] != nil { return ImageMatch(key: expandedToggled, matchType: .synonymExpansion) }
            if let match = longestPrefixMatch(expandedToggled) { return ImageMatch(key: match, matchType: .synonymExpansion) }
            if let match = suffixMatch(expandedToggled) { return ImageMatch(key: match, matchType: .synonymExpansion) }
        }

        return nil
    }

    /// Find a mapping key with a prefix-relationship to `name` at a hyphen boundary.
    /// Bidirectional: matches both `key` ⊂ `name` (e.g. "cat-cow-stretch" prefix of
    /// "cat-cow-stretch-modified") AND `name` ⊂ `key` (e.g. "wall-pushups" is a prefix
    /// of "wall-pushups-modified"). When `name` is the prefix, prefers the shortest
    /// (least specialized) key. When `key` is the prefix, prefers the longest (most
    /// specific) — preserves prior behavior for the common "AI tacked qualifiers
    /// onto a known canonical name" case.
    private func longestPrefixMatch(_ name: String) -> String? {
        // Forward: existing key⊂name behavior — prefer longest (most specific).
        if let m = mapping.keys
            .filter({ name.hasPrefix($0 + "-") })
            .max(by: { $0.count < $1.count }) {
            return m
        }
        // Reverse: name⊂key — prefer shortest (least specialized variant).
        return mapping.keys
            .filter { $0.hasPrefix(name + "-") }
            .min(by: { $0.count < $1.count })
    }

    /// Find a mapping key with a suffix-relationship to `name` at a hyphen boundary.
    /// Bidirectional: matches both `key` ⊂ `name` (e.g. "calf-raises" is a suffix of
    /// "standing-calf-raises") AND `name` ⊂ `key` (e.g. "neck-rolls" is a suffix of
    /// "seated-neck-rolls"). Prefers the shortest (least specialized) key in both cases.
    private func suffixMatch(_ name: String) -> String? {
        // Forward: existing key⊂name behavior.
        if let m = mapping.keys
            .filter({ $0.hasSuffix("-" + name) })
            .min(by: { $0.count < $1.count }) {
            return m
        }
        // Reverse: name⊂key.
        return mapping.keys
            .filter { name.hasSuffix("-" + $0) }
            .min(by: { $0.count < $1.count })
    }

    /// Replace body-part synonym tokens in a hyphen-delimited name.
    private func applySynonyms(_ name: String) -> String {
        var tokens = name.split(separator: "-").map(String.init)
        var changed = false
        for i in tokens.indices {
            if let replacement = Self.synonyms[tokens[i]] {
                tokens[i] = replacement
                changed = true
            }
        }
        return changed ? tokens.joined(separator: "-") : name
    }

    // MARK: - Image Loading Pipeline

    private func loadImage(forKey key: String) async -> UIImage? {
        // 1. Memory cache
        if let cached = memoryCache.object(forKey: key as NSString) {
            return cached
        }

        // 2. Disk cache
        if let diskImage = loadFromDisk(key: key) {
            memoryCache.setObject(diskImage, forKey: key as NSString)
            return diskImage
        }

        // 3. Download from Firebase Storage (deduplicate in-flight requests)
        let task: Task<UIImage?, Never> = lock.withLock {
            if let existingTask = activeDownloads[key] {
                return existingTask
            }

            let newTask = Task<UIImage?, Never> {
                let image = await self.downloadFromStorage(key: key)
                _ = self.lock.withLock { self.activeDownloads.removeValue(forKey: key) }
                return image
            }

            activeDownloads[key] = newTask
            return newTask
        }

        return await task.value
    }

    // MARK: - Disk Cache

    private func diskCachePath(for key: String) -> URL {
        diskCacheURL.appendingPathComponent("\(key).png")
    }

    private func loadFromDisk(key: String) -> UIImage? {
        let path = diskCachePath(for: key)
        guard FileManager.default.fileExists(atPath: path.path) else { return nil }
        guard let data = try? Data(contentsOf: path) else { return nil }
        return UIImage(data: data)
    }

    private func saveToDisk(key: String, data: Data) {
        let path = diskCachePath(for: key)
        try? data.write(to: path, options: .atomic)
    }

    // MARK: - Firebase Storage Download

    private func downloadFromStorage(key: String) async -> UIImage? {
        guard let entry = mapping[key] else { return nil }
        let filename = entry.filename
        let imageRef = storageRef.child(filename)

        // Download up to 2 MB
        let maxSize: Int64 = 2 * 1024 * 1024

        do {
            let data = try await imageRef.data(maxSize: maxSize)
            guard let image = UIImage(data: data) else { return nil }

            // Cache
            memoryCache.setObject(image, forKey: key as NSString)
            saveToDisk(key: key, data: data)

            return image
        } catch {
            AppLogger.images.error("Download failed for \(filename): \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Mapping Loader

    private func loadMapping() {
        guard let url = Bundle.main.url(forResource: "exercise_image_mapping", withExtension: "json") else {
            AppLogger.images.warning("No bundled exercise_image_mapping.json found — images disabled")
            return
        }

        do {
            let data = try Data(contentsOf: url)
            mapping = try JSONDecoder().decode([String: ImageEntry].self, from: data)
            // Invert the per-entry `aliases` arrays into a flat alias-key → canonical-key index
            // so resolveImageMatch can look up in O(1). Done once at load time.
            var index: [String: String] = [:]
            for (canonical, entry) in mapping {
                for alias in entry.aliases ?? [] {
                    index[alias] = canonical
                }
            }
            bundledAliases = index
            AppLogger.images.info("Loaded mapping with \(self.mapping.count) exercises, \(self.bundledAliases.count) bundled aliases")
        } catch {
            AppLogger.images.error("Failed to decode mapping: \(error.localizedDescription)")
        }
    }

    // MARK: - Missing Image Logging

    /// Log exercise to Firestore `missingExerciseImages` if it doesn't have an exact image match.
    /// Deduplicates within the session — safe to call on every exercise display.
    /// `substitutedTo`: PR 2 — set when the validation pipeline rewrote this exercise's
    /// name/imageFileName to a canonical catalog entry. Distinguishes "shown SF Symbol
    /// fallback" from "shown a substituted image" in the missing-images backlog.
    func logMissingImageIfNeeded(for exercise: RehabExercise, substitutedTo: String? = nil) {
        let match = resolveImageMatch(for: exercise)

        // Any layer that resolves to a real image is "good enough" — the user sees the
        // picture. Only `pluralToggle`, `synonymExpansion`, and unmatched (nil) get logged,
        // so we still capture the strong signal of completely-novel AI names.
        // Exception: validation-side substitutions ALWAYS log (the source field is
        // `validation`, not `display`), even if the original name happened to fuzzy-match.
        if substitutedTo == nil {
            switch match?.matchType {
            case .exact, .prefixFuzzy, .suffixFuzzy, .stripped:
                return
            case .pluralToggle, .synonymExpansion, .none:
                break
            }
        }

        let normalized = normalizeName(exercise.name)

        // Deduplicate within this session — keyed on (normalizedKey, source) so a
        // validation-time substitution and a later display-time log both get recorded.
        let dedupKey = "\(normalized)|\(substitutedTo == nil ? "display" : "validation")"
        let alreadyLogged = lock.withLock {
            if loggedThisSession.contains(dedupKey) { return true }
            loggedThisSession.insert(dedupKey)
            return false
        }
        guard !alreadyLogged else { return }

        // Must be authenticated to write to Firestore
        guard Auth.auth().currentUser != nil else { return }

        let matchTypeValue = match?.matchType.rawValue ?? "none"
        let matchedTo = match?.key

        Task {
            let db = Firestore.firestore()
            let docRef = db.collection("missingExerciseImages").document(normalized)

            var data: [String: Any] = [
                "exerciseName": exercise.name,
                "normalizedKey": normalized,
                "matchType": matchTypeValue,
                "exerciseCategory": exercise.exerciseCategory ?? "unknown",
                "targetArea": exercise.targetArea,
                "source": substitutedTo == nil ? "display" : "validation",
                "count": FieldValue.increment(Int64(1)),
                "lastSeen": FieldValue.serverTimestamp(),
            ]

            if let matchedTo {
                data["matchedTo"] = matchedTo
            }
            if let substitutedTo {
                data["substitutedTo"] = substitutedTo
            }

            do {
                let snapshot = try? await docRef.getDocument()
                if snapshot?.exists != true {
                    data["firstSeen"] = FieldValue.serverTimestamp()
                }
                try await docRef.setData(data, merge: true)
            } catch {
                AppLogger.images.error("Failed to log missing image for \(exercise.name): \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Name Normalization

    /// Convert exercise name to a normalized filename key.
    /// e.g. "Quad Sets" → "quad-sets", "Cat-Cow Stretch" → "cat-cow-stretch"
    func normalizeName(_ name: String) -> String {
        name
            .lowercased()
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "'", with: "")
            .components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-")).inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
    }

    /// Tokenize a target_area string into a Set of comparable terms.
    /// Splits on `,`, `&`, `/`, and parentheses; lowercases; trims whitespace
    /// so "Core (Transverse Abdominis)" → `{"core", "transverse abdominis"}`.
    /// Used by the validation pipeline (PR 2) for substitution scoring + anatomical-relevance.
    static func normalizedTargetArea(_ raw: String) -> Set<String> {
        let separators = CharacterSet(charactersIn: ",&/()")
        return Set(
            raw.lowercased()
                .components(separatedBy: separators)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        )
    }
}
