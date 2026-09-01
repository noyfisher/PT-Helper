/**
 * On-demand exercise image generation Cloud Function.
 *
 * Flow:
 * 1. Mapping intelligence check (alias/fuzzy match before generating)
 * 2. BFL FLUX 2 Pro image generation
 * 3. Gemini 2.5 Flash QA gate
 * 4. Upload to Firebase Storage + update mapping
 */

import * as admin from "firebase-admin";
import { EXERCISE_CATALOG_CSV } from "./generated/exerciseCatalog";
import { recordAiUsage } from "./ai-usage";
import { FLAT_COST_USD } from "./ai-pricing";

// Model identifiers for usage telemetry. BFL and Gemini bill per operation, so
// these carry FLAT_COST_USD estimates rather than token math.
const BFL_IMAGE_MODEL = "flux-2-pro";
const GEMINI_QA_MODEL = "gemini-2.5-flash";

// Lazy-initialized to avoid "no default app" error at import time
// (admin.initializeApp() is called in index.ts before these are used)
function getDb() { return admin.firestore(); }
function getStorage() { return admin.storage(); }

/**
 * Tier 1: increment the `imageQAUnavailable/{exerciseKey}` counter when the Gemini
 * QA API is down (HTTP error, empty response, or thrown exception). Fire-and-
 * forget — counter failure must never block the generation response.
 */
async function bumpQaUnavailableCounter(exerciseKey: string, reason: string): Promise<void> {
  try {
    await getDb()
      .collection("imageQAUnavailable")
      .doc(exerciseKey)
      .set({
        count: admin.firestore.FieldValue.increment(1),
        lastReason: reason,
        lastAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
  } catch (err) {
    console.error("Failed to bump imageQAUnavailable counter:", err);
  }
}

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

interface GenerateRequest {
  exerciseName: string;
  exerciseCategory?: string;
  targetArea?: string;
  bodyPosition?: string;
  poseDescription?: string;
}

interface GenerateResponse {
  status: "success" | "already_exists" | "alias_added" | "generation_failed" | "qa_failed" | "rate_limited" | "locked";
  key?: string;
  imageUrl?: string;
  matchType?: string;
  retryable?: boolean;
  message?: string;
  qaSkipped?: boolean;
}

// ---------------------------------------------------------------------------
// Name normalization (matches ExerciseImageService.normalizeName() in Swift)
// ---------------------------------------------------------------------------

export function normalizeName(name: string): string {
  return name
    .toLowerCase()
    .replace(/['ʼ']/g, "") // straight + curly apostrophes
    .split(/[^a-z0-9-]+/)
    .filter((s) => s.length > 0)
    .join("-");
}

// ---------------------------------------------------------------------------
// Synonyms and viewing angle heuristics
// ---------------------------------------------------------------------------

const SYNONYMS: Record<string, string> = {
  quadriceps: "quad",
  quadricep: "quad",
  hamstrings: "hamstring",
  calves: "calf",
  abdominals: "abdominal",
};

const SIDE_KEYWORDS = [
  "squat", "lunge", "deadlift", "plank", "push-up", "pushup",
  "bird dog", "cat-cow", "bridge", "superman", "step-up",
  "heel slide", "leg raise", "hamstring curl", "calf raise",
  "wall sit", "prone", "quadruped", "child", "cobra", "pike",
];
const THREE_QUARTER_KEYWORDS = [
  "row", "press", "curl", "extension", "rotation",
  "fly", "raise", "pull", "swing", "chop", "kickback",
];
const FRONT_KEYWORDS = [
  "stretch", "standing", "balance", "abduction", "adduction",
  "clamshell", "fire hydrant", "monster walk", "band walk",
  "shoulder shrug", "neck", "wrist", "hand", "finger",
];

function getViewingAngle(name: string): string {
  const lower = name.toLowerCase();
  if (SIDE_KEYWORDS.some((kw) => lower.includes(kw))) return "side profile";
  if (THREE_QUARTER_KEYWORDS.some((kw) => lower.includes(kw)))
    return "three-quarter (45-degree)";
  if (FRONT_KEYWORDS.some((kw) => lower.includes(kw))) return "front-facing";
  return "three-quarter (45-degree)";
}

const BODY_POSITION_DESCRIPTIONS: Record<string, string> = {
  supine: "lying flat on his back on the ground, face up",
  prone: "lying flat on his stomach, face down, chest and belly on the floor",
  side_lying: "lying on his side on the ground",
  quadruped: "on all fours with both hands and knees on the floor in a tabletop position",
  standing: "standing upright",
  seated: "seated, sitting down",
  kneeling: "kneeling on the ground",
  foam_roller: "on the ground with a cylindrical foam roller",
  wall_sit: "in a wall sit with back against a wall, knees bent at 90 degrees",
};

// ---------------------------------------------------------------------------
// Fuzzy matching (7-layer, matches Swift ExerciseImageService)
// ---------------------------------------------------------------------------

function longestPrefixMatch(name: string, keys: Set<string>): string | null {
  let best: string | null = null;
  for (const k of keys) {
    if (name.startsWith(k + "-") && (!best || k.length > best.length)) {
      best = k;
    }
  }
  return best;
}

function suffixMatch(name: string, keys: Set<string>): string | null {
  let best: string | null = null;
  for (const k of keys) {
    if (k.endsWith("-" + name) && (!best || k.length < best.length)) {
      best = k;
    }
  }
  return best;
}

function applySynonyms(name: string): string {
  const tokens = name.split("-");
  let changed = false;
  for (let i = 0; i < tokens.length; i++) {
    const syn = SYNONYMS[tokens[i]];
    if (syn) {
      tokens[i] = syn;
      changed = true;
    }
  }
  return changed ? tokens.join("-") : name;
}

interface MatchResult {
  key: string;
  matchType: string;
}

function fuzzyMatch(
  normalized: string,
  mappingKeys: Set<string>,
  _aliasMap: Record<string, string>,
): MatchResult | null {
  // Layer 1-3: exact matches handled by caller

  // Layer 4: Longest prefix
  let match = longestPrefixMatch(normalized, mappingKeys);
  if (match) return { key: match, matchType: "prefixFuzzy" };

  // Layer 5: Suffix
  match = suffixMatch(normalized, mappingKeys);
  if (match) return { key: match, matchType: "suffixFuzzy" };

  // Layer 6: Plural/singular toggle
  const toggled = normalized.endsWith("s")
    ? normalized.slice(0, -1)
    : normalized + "s";
  if (mappingKeys.has(toggled)) return { key: toggled, matchType: "pluralToggle" };
  match = longestPrefixMatch(toggled, mappingKeys);
  if (match) return { key: match, matchType: "pluralToggle" };
  match = suffixMatch(toggled, mappingKeys);
  if (match) return { key: match, matchType: "pluralToggle" };

  // Layer 7: Synonym expansion
  const expanded = applySynonyms(normalized);
  if (expanded !== normalized) {
    if (mappingKeys.has(expanded))
      return { key: expanded, matchType: "synonymExpansion" };
    match = longestPrefixMatch(expanded, mappingKeys);
    if (match) return { key: match, matchType: "synonymExpansion" };
    match = suffixMatch(expanded, mappingKeys);
    if (match) return { key: match, matchType: "synonymExpansion" };
    const expandedToggled = expanded.endsWith("s")
      ? expanded.slice(0, -1)
      : expanded + "s";
    if (mappingKeys.has(expandedToggled))
      return { key: expandedToggled, matchType: "synonymExpansion" };
    match = longestPrefixMatch(expandedToggled, mappingKeys);
    if (match) return { key: match, matchType: "synonymExpansion" };
    match = suffixMatch(expandedToggled, mappingKeys);
    if (match) return { key: match, matchType: "synonymExpansion" };
  }

  return null;
}

// ---------------------------------------------------------------------------
// Mapping cache (in-memory, 5-min TTL)
// ---------------------------------------------------------------------------

let mappingCache: Record<string, { name: string; filename: string; category: string; target_area: string }> | null = null;
let mappingCacheTime = 0;
const MAPPING_CACHE_TTL = 5 * 60 * 1000; // 5 minutes

async function loadMapping(): Promise<Record<string, { name: string; filename: string; category: string; target_area: string }>> {
  const now = Date.now();
  if (mappingCache && now - mappingCacheTime < MAPPING_CACHE_TTL) {
    return mappingCache;
  }

  try {
    const bucket = getStorage().bucket();
    const file = bucket.file("exercise-images/exercise_image_mapping.json");
    const [contents] = await file.download();
    mappingCache = JSON.parse(contents.toString());
    mappingCacheTime = now;
    return mappingCache!;
  } catch {
    // Fall back to empty mapping if file doesn't exist yet
    if (!mappingCache) mappingCache = {};
    return mappingCache;
  }
}

// Alias cache (from Firestore, 5-min TTL)
let aliasCache: Record<string, string> | null = null;
let aliasCacheTime = 0;

async function loadAliases(): Promise<Record<string, string>> {
  const now = Date.now();
  if (aliasCache && now - aliasCacheTime < MAPPING_CACHE_TTL) {
    return aliasCache;
  }

  try {
    const doc = await getDb().collection("config").doc("exerciseImageAliases").get();
    if (doc.exists) {
      aliasCache = (doc.data()?.aliases as Record<string, string>) || {};
    } else {
      aliasCache = {};
    }
    aliasCacheTime = now;
    return aliasCache;
  } catch {
    if (!aliasCache) aliasCache = {};
    return aliasCache;
  }
}

// ---------------------------------------------------------------------------
// Mapping intelligence: resolve or auto-alias
// ---------------------------------------------------------------------------

async function resolveOrAlias(
  exerciseName: string,
  imageFileName?: string,
): Promise<{ found: true; key: string; matchType: string } | { found: false }> {
  const mapping = await loadMapping();
  const aliases = await loadAliases();
  const mappingKeys = new Set(Object.keys(mapping));

  // Layer 1: Explicit imageFileName
  if (imageFileName && mappingKeys.has(imageFileName)) {
    return { found: true, key: imageFileName, matchType: "exact" };
  }

  // Layer 2: Normalized name
  const normalized = normalizeName(exerciseName);
  if (mappingKeys.has(normalized)) {
    return { found: true, key: normalized, matchType: "exact" };
  }

  // Layer 3: Alias map
  const aliasTarget = aliases[normalized];
  if (aliasTarget && mappingKeys.has(aliasTarget)) {
    return { found: true, key: aliasTarget, matchType: "exact" };
  }

  // Layers 4-7: Fuzzy
  const fuzzyResult = fuzzyMatch(normalized, mappingKeys, aliases);
  if (fuzzyResult) {
    // Auto-add alias so future lookups are instant
    try {
      await getDb().collection("config").doc("exerciseImageAliases").set(
        { aliases: { [normalized]: fuzzyResult.key }, updatedAt: admin.firestore.FieldValue.serverTimestamp() },
        { merge: true },
      );
      // Invalidate alias cache
      aliasCacheTime = 0;
    } catch (err) {
      console.warn("Failed to auto-add alias:", err);
    }
    return { found: true, key: fuzzyResult.key, matchType: fuzzyResult.matchType };
  }

  return { found: false };
}

// ---------------------------------------------------------------------------
// BFL FLUX 2 Pro API
// ---------------------------------------------------------------------------

function buildFlux2Prompt(
  exerciseName: string,
  bodyPosition: string,
  poseDescription: string,
  category?: string,
  targetArea?: string,
): string {
  const positionDesc = BODY_POSITION_DESCRIPTIONS[bodyPosition] || "standing upright";
  const angle = getViewingAngle(exerciseName);

  const pose = poseDescription || (
    `Performing a ${category || "general"} exercise targeting the ${targetArea || "General"} with proper form and controlled positioning.`
  );

  const prompt = {
    scene: "Clean fitness studio with plain white background, no furniture, no equipment except what is described",
    subjects: [{
      type: "athletic young man",
      description: (
        `Short dark hair, lean fit build, wearing fitted light gray ` +
        `athletic t-shirt, dark navy compression shorts, white ankle ` +
        `socks, and gray athletic sneakers. ` +
        `Body position: ${positionDesc}. ` +
        `Exercise: ${exerciseName}. ${pose}`
      ),
      position: "centered, full body visible from head to toe",
    }],
    style: "Clean professional fitness illustration, digital art, soft even lighting",
    lighting: "Soft, even studio lighting, no harsh shadows",
    camera: { angle, lens: "50mm", "f-number": "f/5.6" },
    composition: "Single figure centered, full body visible, no text, no labels, no watermarks, no arrows, no annotations",
  };

  return JSON.stringify(prompt);
}

async function callBflApi(
  prompt: string,
  apiKey: string,
  seed?: number,
): Promise<Buffer | null> {
  const submitUrl = "https://api.bfl.ai/v1/flux-2-pro";
  const startedAt = Date.now();

  // Submit generation request
  const submitBody: Record<string, unknown> = {
    prompt,
    width: 1024,
    height: 1024,
    prompt_upsampling: false,
    output_format: "png",
  };
  if (seed !== undefined) submitBody.seed = seed;

  const submitResp = await fetch(submitUrl, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "X-Key": apiKey,
    },
    body: JSON.stringify(submitBody),
  });

  if (!submitResp.ok) {
    const errText = await submitResp.text();
    console.error(`BFL submit failed (${submitResp.status}): ${errText}`);
    return null;
  }

  const { id: taskId } = (await submitResp.json()) as { id: string };

  // Poll for completion (max 3 minutes)
  const pollUrl = `https://api.bfl.ai/v1/get_result?id=${taskId}`;
  const maxAttempts = 120;
  const pollInterval = 1500;

  for (let i = 0; i < maxAttempts; i++) {
    await new Promise((r) => setTimeout(r, pollInterval));

    const pollResp = await fetch(pollUrl);
    if (!pollResp.ok) continue;

    const result = (await pollResp.json()) as { status: string; result?: { sample: string } };

    if (result.status === "Ready" && result.result?.sample) {
      // AI usage telemetry (Phase 1): BFL has produced (and billed for) an
      // image at this point, whether or not the download below succeeds.
      // recordAiUsage never throws, so this cannot change the return value.
      await recordAiUsage({
        fn: "generateExerciseImage",
        requestType: "exercise_image",
        provider: "bfl",
        model: BFL_IMAGE_MODEL,
        durationMs: Date.now() - startedAt,
        status: "ok",
        costUSD: FLAT_COST_USD.bfl_flux_image,
        estimated: true,
      });

      // Download the image
      const imgResp = await fetch(result.result.sample);
      if (imgResp.ok) {
        const arrayBuf = await imgResp.arrayBuffer();
        return Buffer.from(arrayBuf);
      }
      return null;
    }

    if (result.status === "Error" || result.status === "Request Moderated") {
      console.error(`BFL generation failed: ${result.status}`);
      return null;
    }
  }

  console.error("BFL polling timed out");
  return null;
}

// ---------------------------------------------------------------------------
// Gemini QA
// ---------------------------------------------------------------------------

async function runGeminiQA(
  imageBuffer: Buffer,
  exerciseName: string,
  bodyPosition: string,
  poseDescription: string,
  geminiApiKey: string,
): Promise<{ passed: boolean; failures: string[]; unavailable?: boolean }> {
  const positionDesc = BODY_POSITION_DESCRIPTIONS[bodyPosition] || "standing upright";
  const base64Image = imageBuffer.toString("base64");

  const prompt = `You are a quality assurance inspector for physical therapy exercise illustrations.

Analyze this image against the following specifications.

## Expected Exercise
- Exercise Name: ${exerciseName}
- Expected Body Position: ${bodyPosition} (${positionDesc})
- Expected Pose: ${poseDescription || "Standard form for this exercise"}

## Checks
For each check, respond with "pass" or "fail":

1. ANATOMY: Figure has exactly 2 arms and 2 legs
2. SUBJECT: Single human male figure
3. FULL_BODY: Full body visible head to toe
4. CLOTHING: Wearing t-shirt and shorts
5. BACKGROUND: Clean, plain, light background
6. NO_TEXT: No text, labels, or watermarks (small clothing logos OK)
7. ART_STYLE: Photo-realistic or clean digital illustration
8. BODY_ORIENTATION: Body position matches "${bodyPosition}"
9. POSE_ACCURACY: Recognizable as the expected exercise (score 1-5, pass if >= 2)

Return ONLY a JSON object with this exact format:
{"anatomy":"pass","subject":"pass","full_body":"pass","clothing":"pass","background":"pass","no_text":"pass","art_style":"pass","body_orientation":"pass","pose_score":3,"overall_pass":true,"failures":[]}

Set overall_pass to true only if ALL checks pass AND pose_score >= 2. List failed check names in "failures".`;

  const url = `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_QA_MODEL}:generateContent?key=${geminiApiKey}`;
  const startedAt = Date.now();

  try {
    const resp = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        contents: [{
          parts: [
            { text: prompt },
            { inlineData: { mimeType: "image/png", data: base64Image } },
          ],
        }],
        generationConfig: {
          responseMimeType: "application/json",
        },
      }),
    });

    // AI usage telemetry (Phase 1): one record per QA call, placed between two
    // existing statements. Gemini reports no usable token accounting here, so
    // the flat per-call estimate stands in; a failed call is not billed.
    await recordAiUsage({
      fn: "generateExerciseImage",
      requestType: "image_qa",
      provider: "google",
      model: GEMINI_QA_MODEL,
      durationMs: Date.now() - startedAt,
      status: resp.ok ? "ok" : "upstream_error",
      costUSD: resp.ok ? FLAT_COST_USD.gemini_flash_qa : 0,
      estimated: true,
    });

    if (!resp.ok) {
      console.error(`Gemini QA failed (${resp.status}): ${await resp.text()}`);
      // Tier 1 fix: QA unavailable is NOT a pass. Returning `passed: true` here
      // silently shipped bad images when Gemini was down. Treat as an unknown
      // state — the caller will not upload and will surface `qa_failed`.
      return { passed: false, failures: ["qa_unavailable"], unavailable: true };
    }

    const data = (await resp.json()) as {
      candidates?: Array<{ content?: { parts?: Array<{ text?: string }> } }>;
    };

    const text = data.candidates?.[0]?.content?.parts?.[0]?.text;
    if (!text) {
      console.warn("Gemini returned empty response");
      return { passed: false, failures: ["qa_empty_response"], unavailable: true };
    }

    const result = JSON.parse(text) as {
      overall_pass?: boolean;
      failures?: string[];
    };

    // Fail CLOSED: require an explicit `true`. `overall_pass !== false` treated a
    // missing, renamed or stringified field as a pass, so a QA response the model
    // shaped slightly differently published an unvetted image to shared Storage and
    // into the mapping every user reads — the opposite of this file's stated
    // fail-closed design, and reachable without the model ever saying "pass".
    if (result.overall_pass !== true) {
      return {
        passed: false,
        failures: result.failures?.length ? result.failures : ["qa_no_explicit_pass"],
      };
    }

    return { passed: true, failures: result.failures || [] };
  } catch (err) {
    console.error("Gemini QA error:", err);
    // Same fix as the HTTP-error branch — don't silently ship on thrown exceptions.
    return { passed: false, failures: ["qa_error"], unavailable: true };
  }
}

// ---------------------------------------------------------------------------
// Upload to Firebase Storage + update mapping
// ---------------------------------------------------------------------------

async function uploadAndUpdateMapping(
  imageBuffer: Buffer,
  normalizedKey: string,
  exerciseName: string,
  category: string,
  targetArea: string,
): Promise<string> {
  const bucket = getStorage().bucket();
  const filename = `${normalizedKey}.png`;
  const filePath = `exercise-images/${filename}`;

  // Upload image. Do NOT call makePublic() — clients authenticate via the
  // Firebase Storage SDK and the storage.rules gate (`allow read: if
  // request.auth != null`). Making the object public would bypass the rule
  // and allow unauthenticated DoS against the GCS bucket.
  const file = bucket.file(filePath);
  await file.save(imageBuffer, {
    metadata: { contentType: "image/png" },
  });

  const imageUrl = `gs://${bucket.name}/${filePath}`;

  // Update mapping in Storage
  const mapping = await loadMapping();
  mapping[normalizedKey] = {
    name: exerciseName,
    filename,
    category: category || "general",
    target_area: targetArea || "General",
  };

  const mappingFile = bucket.file("exercise-images/exercise_image_mapping.json");
  await mappingFile.save(JSON.stringify(mapping, null, 2), {
    metadata: { contentType: "application/json" },
  });

  // Invalidate mapping cache
  mappingCacheTime = 0;

  return imageUrl;
}

// ---------------------------------------------------------------------------
// Rate limiting (stricter than claudeProxy: 3 per hour for image gen)
// ---------------------------------------------------------------------------

const imageGenRateMap = new Map<string, number[]>();
const IMAGE_GEN_RATE_LIMIT = 3;
const IMAGE_GEN_RATE_WINDOW = 60 * 60 * 1000; // 1 hour

function isImageGenRateLimited(uid: string): boolean {
  const now = Date.now();
  const timestamps = imageGenRateMap.get(uid) || [];
  const recent = timestamps.filter((t) => now - t < IMAGE_GEN_RATE_WINDOW);

  if (recent.length >= IMAGE_GEN_RATE_LIMIT) {
    imageGenRateMap.set(uid, recent);
    return true;
  }

  recent.push(now);
  imageGenRateMap.set(uid, recent);
  return false;
}

// ---------------------------------------------------------------------------
// Per-user daily quota (separate from the global DAILY_BUDGET below).
// Prevents one user from draining the global 50/day pool; Firestore-backed
// so it survives Cloud Function scale-out.
// ---------------------------------------------------------------------------
const DAILY_USER_IMAGE_QUOTA = 5;

type UserImageQuotaResult =
  | { ok: true; remaining: number }
  | { ok: false; limit: number };

async function checkAndIncrementUserImageQuota(uid: string): Promise<UserImageQuotaResult> {
  const ref = getDb().doc(`users/${uid}/quotas/images`);
  const dayKey = new Date().toISOString().slice(0, 10);

  return getDb().runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const data = snap.exists ? snap.data() || {} : {};
    const count = data.dayKey === dayKey ? (data.dayCount || 0) : 0;

    if (count >= DAILY_USER_IMAGE_QUOTA) {
      return { ok: false, limit: DAILY_USER_IMAGE_QUOTA } as UserImageQuotaResult;
    }

    tx.set(ref, {
      dayKey,
      dayCount: count + 1,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });

    return { ok: true, remaining: DAILY_USER_IMAGE_QUOTA - count - 1 } as UserImageQuotaResult;
  });
}

// Daily global budget
const DAILY_BUDGET = 50;

async function checkDailyBudget(): Promise<boolean> {
  const today = new Date().toISOString().slice(0, 10);
  const counterRef = getDb().collection("config").doc("imageGenBudget");
  // Atomic read-check-increment (P2-07): the previous read-then-write let
  // concurrent instances both observe an under-budget count and both proceed.
  return getDb().runTransaction(async (tx) => {
    const doc = await tx.get(counterRef);
    const data = doc.data();
    if (data?.date === today) {
      if ((data.count ?? 0) >= DAILY_BUDGET) {
        return false; // Budget exhausted
      }
      tx.update(counterRef, { count: admin.firestore.FieldValue.increment(1) });
    } else {
      tx.set(counterRef, { date: today, count: 1 });
    }
    return true;
  });
}

// ---------------------------------------------------------------------------
// Generation lock (Firestore-based, 10-min TTL)
// ---------------------------------------------------------------------------

const LOCK_TTL_MS = 10 * 60 * 1000; // 10 minutes

async function acquireGenerationLock(normalizedKey: string): Promise<boolean> {
  const docRef = getDb().collection("missingExerciseImages").doc(normalizedKey);
  // Atomic acquire (P2-07): the previous read-then-write let two instances both
  // see "not generating" and both take the lock, duplicating a paid generation.
  return getDb().runTransaction(async (tx) => {
    const doc = await tx.get(docRef);
    const data = doc.data();
    if (data?.status === "generating") {
      const startedAt = data.generatingStartedAt?.toMillis?.() || 0;
      if (Date.now() - startedAt < LOCK_TTL_MS) {
        return false; // Another instance holds a live lock
      }
      // Lock expired — take it over.
    }
    tx.set(docRef, {
      status: "generating",
      generatingStartedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
    return true;
  });
}

/**
 * Release a lock taken by `acquireGenerationLock` without marking the exercise
 * generated.
 *
 * Only the full-success path used to clear the lock, so every failure after it
 * was taken — missing API key, generation failure, QA unavailable, upload
 * failure — left the document in `status: "generating"` for the whole 10-minute
 * TTL. Several of those paths return `retryable: true`, so the client was
 * explicitly told to try again into a wall it could not pass, and each attempt
 * still consumed the caller's daily image quota.
 */
async function releaseGenerationLock(normalizedKey: string): Promise<void> {
  try {
    await getDb().collection("missingExerciseImages").doc(normalizedKey).set(
      {
        status: "pending",
        generatingStartedAt: admin.firestore.FieldValue.delete(),
      },
      { merge: true },
    );
  } catch (err) {
    // Best-effort: the TTL is the backstop, and a failed release must never
    // replace the real error the caller is about to return.
    console.error("Failed to release generation lock:", err);
  }
}

async function markGenerated(normalizedKey: string): Promise<void> {
  await getDb().collection("missingExerciseImages").doc(normalizedKey).set(
    { status: "generated", generatedAt: admin.firestore.FieldValue.serverTimestamp() },
    { merge: true },
  );
}

// ---------------------------------------------------------------------------
// Request validation + canonical-catalog gate (P1-08)
// ---------------------------------------------------------------------------

const MAX_EXERCISE_NAME_LEN = 100;
const MAX_METADATA_FIELD_LEN = 200;

/**
 * Strict schema/length check on the generation request. Returns an error
 * message, or null when the request is well-formed. Length caps bound prompt
 * size (cost) and abuse.
 */
export function validateGenerateRequest(body: GenerateRequest): string | null {
  const { exerciseName, exerciseCategory, targetArea, bodyPosition, poseDescription } = body;
  if (typeof exerciseName !== "string" || exerciseName.trim().length === 0) {
    return "exerciseName is required";
  }
  if (exerciseName.length > MAX_EXERCISE_NAME_LEN) {
    return "exerciseName is too long";
  }
  for (const [field, value] of Object.entries({ exerciseCategory, targetArea, bodyPosition, poseDescription })) {
    if (value !== undefined && (typeof value !== "string" || value.length > MAX_METADATA_FIELD_LEN)) {
      return `${field} is invalid`;
    }
  }
  return null;
}

// Canonical catalog keys (normalized names + slugs), parsed once from the
// server-side exercise catalog CSV whose lines are `name|slug|category|...`.
let _canonicalKeys: Set<string> | null = null;
function canonicalKeys(): Set<string> {
  if (_canonicalKeys) return _canonicalKeys;
  const set = new Set<string>();
  for (const line of EXERCISE_CATALOG_CSV.split("\n")) {
    if (!line.trim()) continue;
    const [name, slug] = line.split("|");
    if (name) set.add(normalizeName(name));
    if (slug && slug.trim()) set.add(slug.trim().toLowerCase());
  }
  _canonicalKeys = set;
  return set;
}

/**
 * True when the requested exercise is one the server catalogues. Generation is
 * restricted to catalogued exercises so arbitrary / AI-hallucinated names can't
 * create cost, poison the shared alias mapping, or promote an unvetted asset
 * into shared application state (P1-08). Non-catalogued names fall back to the
 * client's missing-image placeholder.
 */
export function isCanonicalExercise(name: string): boolean {
  const keys = canonicalKeys();
  return keys.has(normalizeName(name)) || keys.has(name.trim().toLowerCase());
}

// ---------------------------------------------------------------------------
// Main handler
// ---------------------------------------------------------------------------

export async function handleGenerateExerciseImage(
  req: { body: GenerateRequest; uid: string },
): Promise<GenerateResponse> {
  const { exerciseName, exerciseCategory, targetArea, bodyPosition, poseDescription } = req.body;

  // Strict schema + length validation (P1-08): reject malformed / oversized input.
  const validationError = validateGenerateRequest(req.body);
  if (validationError) {
    return { status: "generation_failed", message: validationError, retryable: false };
  }

  // Rate limit
  if (isImageGenRateLimited(req.uid)) {
    return { status: "rate_limited", message: "Max 3 image generation requests per hour" };
  }

  // Step 1: Mapping intelligence — check if image already exists
  // (No quota cost: cache hits don't trigger generation.)
  const resolution = await resolveOrAlias(exerciseName);
  if (resolution.found) {
    return {
      status: resolution.matchType === "exact" ? "already_exists" : "alias_added",
      key: resolution.key,
      matchType: resolution.matchType,
    };
  }

  // Restrict GENERATION to the server's canonical catalog. Existing images still
  // resolve above; only creating a NEW asset for an off-catalog name is blocked,
  // so arbitrary / AI-hallucinated names can't create cost, poison the shared
  // mapping, or promote an unvetted illustration into shared state (P1-08). The
  // client shows its missing-image placeholder for non-catalogued exercises.
  if (!isCanonicalExercise(exerciseName)) {
    return {
      status: "generation_failed",
      message: "Exercise is not in the catalog",
      retryable: false,
    };
  }

  // Step 2a: Per-user daily quota (caps cost per user; prevents a single
  // user from draining the global DAILY_BUDGET pool).
  const userQuota = await checkAndIncrementUserImageQuota(req.uid);
  if (!userQuota.ok) {
    return {
      status: "rate_limited",
      message: `Daily image generation limit reached (${userQuota.limit} per user). Please try again tomorrow.`,
      retryable: false,
    };
  }

  // Step 2b: Check global daily budget
  const budgetOk = await checkDailyBudget();
  if (!budgetOk) {
    return { status: "generation_failed", message: "Daily generation budget exhausted", retryable: false };
  }

  // Step 3: Acquire generation lock
  const normalizedKey = normalizeName(exerciseName);
  const locked = await acquireGenerationLock(normalizedKey);
  if (!locked) {
    return { status: "locked", message: "Image generation already in progress for this exercise" };
  }

  // Step 4: Generate image via FLUX 2 Pro
  const bflApiKey = process.env.BFL_API_KEY;
  const geminiApiKey = process.env.GEMINI_API_KEY;

  if (!bflApiKey) {
    await releaseGenerationLock(normalizedKey);
    return { status: "generation_failed", message: "BFL_API_KEY not configured", retryable: false };
  }

  const resolvedBodyPosition = bodyPosition || "standing";
  const resolvedPoseDescription = poseDescription || "";

  const prompt = buildFlux2Prompt(
    exerciseName,
    resolvedBodyPosition,
    resolvedPoseDescription,
    exerciseCategory,
    targetArea,
  );

  let imageBuffer = await callBflApi(prompt, bflApiKey);

  if (!imageBuffer) {
    await releaseGenerationLock(normalizedKey);
    return { status: "generation_failed", message: "Image generation failed", retryable: true };
  }

  // Step 5: QA gate — REQUIRED. An unvetted image must never be published, so a
  // missing QA key fails CLOSED (quarantine + telemetry) rather than open (P1-08):
  // previously the whole QA block was skipped and the image was published with
  // qaSkipped:true.
  if (!geminiApiKey) {
    await bumpQaUnavailableCounter(normalizedKey, "gemini_key_unconfigured");
    await releaseGenerationLock(normalizedKey);
    return {
      status: "qa_failed",
      message: "Image quality check is unavailable. Image was not published.",
      retryable: true,
    };
  }

  // geminiApiKey is guaranteed present past the guard above.
  if (geminiApiKey) {
    const qa = await runGeminiQA(
      imageBuffer,
      exerciseName,
      resolvedBodyPosition,
      resolvedPoseDescription,
      geminiApiKey,
    );

    // Tier 1: if QA is unavailable (API error, empty response, exception), DO NOT
    // silently accept the image. Bump a telemetry counter and return qa_failed so
    // the client can retry later when Gemini is reachable. Retrying with a different
    // seed wouldn't help — QA would still be unavailable.
    if (qa.unavailable) {
      await bumpQaUnavailableCounter(normalizedKey, qa.failures.join(", "));
      await releaseGenerationLock(normalizedKey);
      return {
        status: "qa_failed",
        message: "Image quality check is temporarily unavailable. Please try again in a minute.",
        retryable: true,
      };
    }

    if (!qa.passed) {
      // Retry once with different seed
      console.log(`QA failed for ${exerciseName} (failures: ${qa.failures.join(", ")}), retrying with different seed`);
      imageBuffer = await callBflApi(prompt, bflApiKey, 42);

      if (!imageBuffer) {
        await releaseGenerationLock(normalizedKey);
        return { status: "generation_failed", message: "Retry generation failed", retryable: true };
      }

      const retryQa = await runGeminiQA(
        imageBuffer,
        exerciseName,
        resolvedBodyPosition,
        resolvedPoseDescription,
        geminiApiKey,
      );

      if (retryQa.unavailable) {
        await bumpQaUnavailableCounter(normalizedKey, retryQa.failures.join(", "));
        await releaseGenerationLock(normalizedKey);
        return {
          status: "qa_failed",
          message: "Image quality check is temporarily unavailable. Please try again in a minute.",
          retryable: true,
        };
      }

      if (!retryQa.passed) {
        await releaseGenerationLock(normalizedKey);
        return {
          status: "qa_failed",
          message: `Image quality check failed: ${retryQa.failures.join(", ")}`,
          retryable: true,
        };
      }
    }
  }

  // Step 6: Upload and update mapping
  try {
    const imageUrl = await uploadAndUpdateMapping(
      imageBuffer,
      normalizedKey,
      exerciseName,
      exerciseCategory || "general",
      targetArea || "General",
    );

    await markGenerated(normalizedKey);

    return {
      status: "success",
      key: normalizedKey,
      imageUrl,
    };
  } catch (err) {
    console.error("Upload/mapping update failed:", err);
    await releaseGenerationLock(normalizedKey);
    return { status: "generation_failed", message: "Failed to upload image", retryable: true };
  }
}
