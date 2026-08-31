import * as functions from "firebase-functions/v1";
import * as admin from "firebase-admin";
import * as crypto from "crypto";
import { onSchedule } from "firebase-functions/v2/scheduler";
import sgMail from "@sendgrid/mail";
import { fetchRecoveryInsightsData, MINIMUM_SESSION_COUNT, fetchFormHistoryData, MINIMUM_FORM_HISTORY_COUNT } from "./firestore-queries";
import { runRecoveryInsightsAgent, validateInsightResult } from "./managed-agent";
import { runFormAnalysisAgent, validateFormResult } from "./form-agent";
import { handleGenerateExerciseImage } from "./image-generation";
import { deleteUserFirestoreData } from "./account-deletion";
import { RequestContext, newRequestContext, logCompleted, logError, logWarn } from "./logger";
import { validateClaudeResponse } from "./response-schemas";
import { validateNightlyReport } from "./nightly-report-validator";
import { EXERCISE_CATALOG_CSV } from "./generated/exerciseCatalog";
import { SYSTEM_PROMPTS, MODEL_CONFIG, MINOR_SAFETY_PROMPT } from "./prompts";
import {
  recordAiUsage,
  AI_DAILY_BUDGET,
  AI_BUDGET_COLLECTION,
  AI_BUDGET_DOC_ID,
  AI_USAGE_DAILY_COLLECTION,
} from "./ai-usage";
import {
  dashboardDailyCollection,
  dashboardReportsCollection,
  computeTotalsDeltas,
  resolveAiCallsToday,
  shapeAiUsageDaily,
  NightlyReportEmailStatus,
} from "./dashboard-data";

// Hard billing shutoff (Pub/Sub triggered). Exported so firebase-tools
// picks it up on deploy. See billing-shutoff.ts for arming instructions.
export { onBudgetAlert } from "./billing-shutoff";

// Monitoring dashboard (Phases 2 & 3). Exported here so firebase-tools picks
// them up on deploy; the handlers live in their own modules.
export { pullDailyAnalytics, backfillAnalytics } from "./analytics-pull";
export { dashboardData } from "./dashboard-data";

admin.initializeApp();

// ---------------------------------------------------------------------------
// Distributed rate limiter (Tier 2 PR B — Firestore-backed)
// ---------------------------------------------------------------------------
//
// Previously this was an in-memory Map that lived on each Cloud Function
// instance. With horizontal autoscale that meant a single user could burst
// past 20/min by getting routed to multiple instances. This replacement
// uses a Firestore transactional counter keyed by uid + ISO-minute bucket,
// which is atomic across all instances.
//
// Doc path: `rateLimits/{uid}/windows/{ISO-minute}`
// Fields: `count` (Int), `firstSeenAt`, `lastSeenAt` (timestamps for TTL)
//
// Contention: each minute bucket is a separate doc. A single user's 20
// req/min all hit one doc — Firestore handles this comfortably (ceiling
// ~500 writes/sec per doc).
//
// Storage cleanup: TTL policy via `lastSeenAt` field deletes stale docs
// after 2 minutes. TTL is cosmetic only — the ISO-minute key provides
// the correctness guarantee (next-minute requests hit a different doc).
//
// Latency: one extra Firestore transaction per claudeProxy request
// (~50-150ms). This is on top of the existing `checkAndIncrementQuota`
// transaction. Different docs, so no contention between them.
export const RATE_LIMIT_MAX = 20; // max requests per window
export const RATE_LIMIT_WINDOW_MS = 60_000; // 1 minute — documents purpose of the ISO-minute bucket

/** ISO-minute bucket key for a given timestamp. */
export function rateLimitWindowKey(now: Date = new Date()): string {
  // YYYY-MM-DDTHH:MM
  return now.toISOString().slice(0, 16);
}

/**
 * Atomically check-and-increment the rate-limit counter for `uid` in the
 * current ISO-minute bucket. Returns `true` if the user is currently OVER
 * the limit (request should be rejected with 429), `false` otherwise.
 *
 * Visible for testing via `__testing__.isRateLimitedWith` below.
 */
export async function isRateLimited(
  uid: string,
  now: Date = new Date(),
  db: admin.firestore.Firestore = admin.firestore(),
): Promise<boolean> {
  const windowKey = rateLimitWindowKey(now);
  const ref = db.collection("rateLimits").doc(uid)
    .collection("windows").doc(windowKey);

  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const current = (snap.exists ? (snap.data()?.count as number | undefined) : 0) ?? 0;

    if (current >= RATE_LIMIT_MAX) {
      // Do not increment — user is already over.
      return true;
    }

    tx.set(ref, {
      count: admin.firestore.FieldValue.increment(1),
      firstSeenAt: snap.exists
        ? (snap.data()?.firstSeenAt ?? admin.firestore.FieldValue.serverTimestamp())
        : admin.firestore.FieldValue.serverTimestamp(),
      lastSeenAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });

    return false;
  });
}

// ---------------------------------------------------------------------------
// Per-user quota (Firestore-backed, survives scale-out)
// Doc path: users/{uid}/quotas/current
// Fields: dayKey, dayCount, monthKey, monthCount
// ---------------------------------------------------------------------------
const DAILY_QUOTA = 100;
const MONTHLY_QUOTA = 1000;

type QuotaResult =
  | { ok: true; dayCount: number; monthCount: number }
  | { ok: false; reason: "daily" | "monthly"; limit: number };

function quotaKeys(now: Date = new Date()): { dayKey: string; monthKey: string } {
  const iso = now.toISOString();
  return {
    dayKey: iso.slice(0, 10),      // YYYY-MM-DD
    monthKey: iso.slice(0, 7),     // YYYY-MM
  };
}

async function checkAndIncrementQuota(uid: string): Promise<QuotaResult> {
  const ref = admin.firestore().doc(`users/${uid}/quotas/current`);
  const { dayKey, monthKey } = quotaKeys();

  return admin.firestore().runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const data = snap.exists ? snap.data() || {} : {};

    const dayCount = data.dayKey === dayKey ? (data.dayCount || 0) : 0;
    const monthCount = data.monthKey === monthKey ? (data.monthCount || 0) : 0;

    if (dayCount >= DAILY_QUOTA) {
      return { ok: false, reason: "daily", limit: DAILY_QUOTA } as QuotaResult;
    }
    if (monthCount >= MONTHLY_QUOTA) {
      return { ok: false, reason: "monthly", limit: MONTHLY_QUOTA } as QuotaResult;
    }

    const nextDay = dayCount + 1;
    const nextMonth = monthCount + 1;
    tx.set(ref, {
      dayKey,
      dayCount: nextDay,
      monthKey,
      monthCount: nextMonth,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });

    return { ok: true, dayCount: nextDay, monthCount: nextMonth } as QuotaResult;
  });
}

/**
 * Refunds one unit each from dayCount and monthCount if the recorded keys
 * still match (otherwise day/month already rolled — silently skip).
 *
 * Fail-safe: errors are logged but not propagated; a stuck decrement is
 * only an accounting drift, not a user-visible error. Called on upstream
 * failure paths so users aren't charged for requests that never returned
 * a useful response.
 */
async function decrementQuota(uid: string): Promise<void> {
  const ref = admin.firestore().doc(`users/${uid}/quotas/current`);
  const { dayKey, monthKey } = quotaKeys();
  try {
    await admin.firestore().runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      if (!snap.exists) return;
      const data = snap.data() || {};

      const patch: Record<string, number> = {};
      if (data.dayKey === dayKey && typeof data.dayCount === "number" && data.dayCount > 0) {
        patch.dayCount = data.dayCount - 1;
      }
      if (data.monthKey === monthKey && typeof data.monthCount === "number" && data.monthCount > 0) {
        patch.monthCount = data.monthCount - 1;
      }
      // Single update with both field deltas — avoids any ambiguity around
      // multiple writes to the same doc in one transaction.
      if (Object.keys(patch).length > 0) {
        tx.update(ref, patch);
      }
    });
  } catch (err) {
    console.error("decrementQuota failed:", err);
  }
}

// ---------------------------------------------------------------------------
// Global daily spend ceiling across ALL AI endpoints (denial-of-wallet guard).
// The per-user quotas above are keyed on uid and are bypassable by minting or
// self-registering identities; this is a single global counter that caps total
// paid AI calls per day regardless of how many identities call. Mirrors the
// image-generation DAILY_BUDGET pattern. Doc: config/aiDailyBudget.
// Increment-on-admit: over-budget calls are rejected (never admitted); admitted
// calls count — a hard ceiling, not precise per-call accounting.
// ---------------------------------------------------------------------------
// The ceiling itself (AI_DAILY_BUDGET) lives in ai-usage.ts so the enforcer
// here and the dashboard tile that reports "n / limit" read the SAME number.
// Dev value is sized to survive virtual-user batches / manual QA without
// tripping the 429 ceiling; denial-of-wallet is a prod concern and dev has no
// public account minting.

async function checkGlobalDailyBudget(): Promise<boolean> {
  const today = new Date().toISOString().slice(0, 10);
  const ref = admin.firestore().collection(AI_BUDGET_COLLECTION).doc(AI_BUDGET_DOC_ID);
  return admin.firestore().runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const data = snap.exists ? snap.data() || {} : {};
    const count = data.date === today ? (data.count || 0) : 0;
    if (count >= AI_DAILY_BUDGET) {
      return false; // ceiling reached for today
    }
    tx.set(ref, { date: today, count: count + 1 }, { merge: true });
    return true;
  });
}

// ---------------------------------------------------------------------------
// JSON output schemas — kept for future structured output support.
// Structured output (`output` field) requires anthropic-version >= 2025-xx.
// For now the system prompts instruct JSON format directly.
// ---------------------------------------------------------------------------
/* eslint-disable @typescript-eslint/no-unused-vars */
const ANALYSIS_CONDITION_SCHEMA = {
  type: "object" as const,
  properties: {
    conditionName: { type: "string" as const },
    commonName: { type: "string" as const },
    confidence: { type: "number" as const },
    explanation: { type: "string" as const },
    whatItMeans: { type: "string" as const },
    howToManage: { type: "string" as const },
    isRedFlag: { type: "boolean" as const },
    redFlagMessage: { type: "string" as const },
    nextSteps: { type: "array" as const, items: { type: "string" as const } },
  },
  required: [
    "conditionName", "commonName", "confidence", "explanation",
    "whatItMeans", "howToManage", "isRedFlag", "redFlagMessage", "nextSteps",
  ],
  additionalProperties: false,
};

const ANALYSIS_SCHEMA = {
  type: "json_schema" as const,
  json_schema: {
    name: "analysis_response",
    strict: true,
    schema: {
      type: "object" as const,
      properties: {
        conditions: {
          type: "array" as const,
          items: ANALYSIS_CONDITION_SCHEMA,
        },
        overallSummary: { type: "string" as const },
        disclaimerText: { type: "string" as const },
      },
      required: ["conditions", "overallSummary", "disclaimerText"],
      additionalProperties: false,
    },
  },
};

const REHAB_EXERCISE_SCHEMA = {
  type: "object" as const,
  properties: {
    name: { type: "string" as const },
    targetArea: { type: "string" as const },
    description: { type: "string" as const },
    sets: { type: "number" as const },
    reps: { type: "string" as const },
    restSeconds: { type: "number" as const },
    difficulty: { type: "string" as const },
    demonstrationIcon: { type: "string" as const },
    tips: { type: "array" as const, items: { type: "string" as const } },
    contraindications: { type: "array" as const, items: { type: "string" as const } },
    startPosition: { type: "string" as const },
    movement: { type: "string" as const },
    endPosition: { type: "string" as const },
    exerciseCategory: { type: "string" as const },
    imageFileName: { type: "string" as const },
  },
  required: [
    "name", "targetArea", "description", "sets", "reps", "restSeconds",
    "difficulty", "demonstrationIcon", "tips", "contraindications",
    "startPosition", "movement", "endPosition", "exerciseCategory", "imageFileName",
  ],
  additionalProperties: false,
};

const REHAB_PLAN_SCHEMA = {
  type: "json_schema" as const,
  json_schema: {
    name: "rehab_plan_response",
    strict: true,
    schema: {
      type: "object" as const,
      properties: {
        planName: { type: "string" as const },
        exercises: {
          type: "array" as const,
          items: REHAB_EXERCISE_SCHEMA,
        },
        totalWeeks: { type: "number" as const },
        notes: { type: "string" as const },
      },
      required: ["planName", "exercises", "totalWeeks", "notes"],
      additionalProperties: false,
    },
  },
};

// OUTPUT_SCHEMAS kept for future structured output support
// eslint-disable-next-line @typescript-eslint/no-unused-vars
export const _OUTPUT_SCHEMAS: Record<string, object> = {
  analysis: ANALYSIS_SCHEMA,
  analysis_verify: ANALYSIS_SCHEMA,
  rehab_plan: REHAB_PLAN_SCHEMA,
};
/* eslint-enable @typescript-eslint/no-unused-vars */

// Client-callable request types. Deny-by-default: server-only prompts
// (e.g. nightly_report, used solely by the scheduled sendNightlyReport job)
// are intentionally excluded so clients cannot relay through the paid key.
export const ALLOWED_REQUEST_TYPES = new Set<string>([
  "analysis", "analysis_verify", "rehab_plan", "exercise_substitute",
  "recovery_insights", "form_analysis", "wellness_analysis",
  "wellness_verify", "wellness_plan",
]);

// ---------------------------------------------------------------------------
// Request / response types
// ---------------------------------------------------------------------------
interface ProxyRequestBody {
  requestType: string;
  messages: { role: string; content: string }[];
}

const ageCache = new Map<string, { age: number | null; fetchedAt: number }>();
const AGE_CACHE_TTL_MS = 15 * 60_000;

export function computeAgeFromDob(dobMs: number, nowMs: number): number {
  // Calendar age: whole years since birth, decremented if this year's birthday
  // has not yet occurred. UTC throughout for determinism — avoids the ~1-day
  // drift a 365.25-day approximation accrues right at a birthday boundary.
  const dob = new Date(dobMs);
  const now = new Date(nowMs);
  let age = now.getUTCFullYear() - dob.getUTCFullYear();
  const monthDelta = now.getUTCMonth() - dob.getUTCMonth();
  if (monthDelta < 0 || (monthDelta === 0 && now.getUTCDate() < dob.getUTCDate())) {
    age -= 1;
  }
  return age;
}

// Exported for tests (injectable `db`, same seam as `isRateLimited`).
//
// Read order is a security control, not a style choice: firestore.rules makes
// `dateOfBirth` immutable ONLY on `consents/legal` (set once at terms
// acceptance, never changeable), while `profile/health` is freely
// owner-writable. Reading the profile first let any user patch their profile
// DOB to an adult date and walk through the under-13 hard block and the minor
// safeguards — the rules-level control existed and was bypassed purely by
// resolver preference. Consents first; the mutable profile is only a fallback
// for legacy accounts that predate the consents doc.
export async function getUserAge(
  uid: string,
  db: FirebaseFirestore.Firestore = admin.firestore()
): Promise<number | null> {
  const cached = ageCache.get(uid);
  if (cached && Date.now() - cached.fetchedAt < AGE_CACHE_TTL_MS) return cached.age;
  let age: number | null = null;
  try {
    let dob = (await db.doc(`users/${uid}/consents/legal`).get()).get("dateOfBirth");
    if (!dob) dob = (await db.doc(`users/${uid}/profile/health`).get()).get("dateOfBirth");
    if (dob && typeof dob.toDate === "function") {
      age = computeAgeFromDob(dob.toDate().getTime(), Date.now());
    }
  } catch {
    // DOB unreadable → null. Callers treat unknown age as a MINOR (restricted
    // path), NOT as an adult — see evaluateEligibility.
  }
  ageCache.set(uid, { age, fetchedAt: Date.now() });
  return age;
}

// ---------------------------------------------------------------------------
// Eligibility: minor safeguards + health-data consent, enforced server-side on
// every AI endpoint BEFORE any budget/quota/provider spend (P1-04).
//
// The age read here is anchored to `consents/legal.dateOfBirth`, which
// firestore.rules makes immutable once set — so the under-13/minor gates hold
// against a client that later edits its (freely writable) profile DOB. Other
// consent audit fields remain client-writable; a server-owned consent write
// path is tracked in PR-8.
// ---------------------------------------------------------------------------
export interface Eligibility {
  under13: boolean;          // hard block
  isMinor: boolean;          // extra safety system block
  consentWithdrawn: boolean; // health-data consent explicitly withdrawn
}

/**
 * Pure eligibility decision from already-resolved inputs (unit-testable).
 *
 * - Unknown age cannot prove under-13, so it is NOT hard-blocked; it is treated
 *   as a MINOR (restricted path) rather than failing open to adult.
 * - Health-data consent withdrawal is authoritative at the processing boundary:
 *   once withdrawn (revokedAt set + policyVersion cleared) even a stale client
 *   that still believes it has consent is blocked. A never-created consent doc
 *   is NOT "withdrawn" — first consent is gated client-side during onboarding.
 */
export function evaluateEligibility(
  age: number | null,
  consent: { docExists: boolean; hasPolicyVersion: boolean; wasRevoked: boolean },
): Eligibility {
  return {
    under13: age !== null && age < 13,
    isMinor: age === null || age < 18,
    consentWithdrawn: consent.docExists && consent.wasRevoked && !consent.hasPolicyVersion,
  };
}

async function checkEligibility(uid: string): Promise<Eligibility> {
  const age = await getUserAge(uid);
  let consent = { docExists: false, hasPolicyVersion: false, wasRevoked: false };
  try {
    const doc = await admin.firestore().doc(`users/${uid}/consents/healthData`).get();
    const pv = doc.get("policyVersion");
    consent = {
      docExists: doc.exists,
      hasPolicyVersion: typeof pv === "string" && pv.length > 0,
      wasRevoked: doc.get("revokedAt") != null,
    };
  } catch {
    // Consent read failed: do NOT fabricate a withdrawal (that would deny
    // legitimate users on a transient Firestore error). The age gate still
    // applies; forgery hardening is PR-8, not this read.
  }
  return evaluateEligibility(age, consent);
}

// ---------------------------------------------------------------------------
// Cloud Function: claudeProxy
// ---------------------------------------------------------------------------
export const claudeProxy = functions
  .runWith({ timeoutSeconds: 120, memory: "256MB", secrets: ["ANTHROPIC_API_KEY"] })
  .https.onRequest(async (req, res) => {
    const ctx = newRequestContext("claudeProxy");
    res.on("finish", () => logCompleted(ctx, res.statusCode));

    if (req.method !== "POST") {
      res.status(405).json({ error: "Method not allowed" });
      return;
    }

    // -----------------------------------------------------------------------
    // 1. Authenticate: verify Firebase ID token
    // -----------------------------------------------------------------------
    const authHeader = req.headers.authorization;
    if (!authHeader || !authHeader.startsWith("Bearer ")) {
      res.status(401).json({ error: "Missing or invalid Authorization header" });
      return;
    }

    const idToken = authHeader.split("Bearer ")[1];
    let uid: string;
    try {
      const decoded = await admin.auth().verifyIdToken(idToken);
      uid = decoded.uid;
      ctx.uid = uid;
    } catch {
      res.status(401).json({ error: "Invalid Firebase ID token" });
      return;
    }

    // -----------------------------------------------------------------------
    // 1b. Eligibility gate (P1-04): minor + health-data consent, enforced
    // BEFORE any budget/quota/provider spend so ineligible requests cost
    // nothing. Under-13 hard-blocks; a withdrawn consent is authoritative even
    // for a stale/patched client. `eligibility.isMinor` drives the safety block.
    // -----------------------------------------------------------------------
    const eligibility = await checkEligibility(uid);
    if (eligibility.under13) {
      res.status(403).json({ error: "age_policy" });
      return;
    }
    if (eligibility.consentWithdrawn) {
      res.status(403).json({ error: "consent_required" });
      return;
    }

    // -----------------------------------------------------------------------
    // 2. Rate limit
    // -----------------------------------------------------------------------
    if (await isRateLimited(uid)) {
      res.status(429).json({ error: "Rate limit exceeded. Please wait and try again." });
      return;
    }

    // -----------------------------------------------------------------------
    // 3. Validate request body BEFORE consuming the global budget, so malformed
    // or ineligible requests never burn the shared daily AI ceiling (P1-07).
    // -----------------------------------------------------------------------
    const body = req.body as ProxyRequestBody;

    // `messages` must be a non-empty ARRAY. A truthy non-array (a string or
    // object) previously passed this guard and consumed budget before failing
    // later at `.find` / `.reduce`.
    if (!body.requestType || !Array.isArray(body.messages) || body.messages.length === 0) {
      res.status(400).json({
        error: "Missing or invalid fields: requestType, messages",
      });
      return;
    }

    ctx.metadata.requestType = body.requestType;

    // Validate requestType is allowed (prevents misuse of API key)
    if (!ALLOWED_REQUEST_TYPES.has(body.requestType)) {
      res.status(400).json({
        error: `Invalid requestType. Allowed: ${[...ALLOWED_REQUEST_TYPES].join(", ")}`,
      });
      return;
    }

    // Validate message roles — only "user" role is allowed from clients
    const invalidRole = body.messages.find((m) => m.role !== "user");
    if (invalidRole) {
      res.status(400).json({ error: "Only 'user' role messages are allowed" });
      return;
    }

    // Validate message content length (prevent abuse)
    // form_analysis may have longer messages due to per-rep metrics data
    const maxMessageLength = body.requestType === "form_analysis" ? 20000 : 10000;
    const totalMessageLength = body.messages.reduce((sum, m) => sum + (m.content?.length || 0), 0);
    if (totalMessageLength > maxMessageLength) {
      res.status(400).json({ error: "Message content too long" });
      return;
    }

    // Global daily AI spend ceiling (denial-of-wallet guard). Per-user quotas
    // are bypassable by minting identities; this caps total paid AI calls/day.
    // Checked AFTER validation so malformed requests don't consume it (P1-07).
    if (!(await checkGlobalDailyBudget())) {
      res.status(429).json({ error: "daily_capacity_reached" });
      return;
    }

    // -----------------------------------------------------------------------
    // 4. Get Anthropic API key from environment
    // -----------------------------------------------------------------------
    const anthropicApiKey = process.env.ANTHROPIC_API_KEY;
    if (!anthropicApiKey) {
      logError(ctx, new Error("ANTHROPIC_API_KEY not configured in environment"));
      res.status(500).json({ error: "Server configuration error" });
      return;
    }

    // -----------------------------------------------------------------------
    // 4b. Per-user daily/monthly quota (cost cap, survives scale-out).
    // Placed AFTER validation + API key check so malformed / mis-configured
    // requests don't burn quota. Block is OUTSIDE the fetch try/catch so the
    // decrement paths on failure are reachable (see below).
    // -----------------------------------------------------------------------
    let quota: QuotaResult;
    try {
      quota = await checkAndIncrementQuota(uid);
    } catch (err) {
      console.error("Quota check failed:", err);
      res.status(500).json({ error: "Quota check failed" });
      return;
    }
    if (!quota.ok) {
      res.status(429).json({
        error: `${quota.reason === "daily" ? "Daily" : "Monthly"} usage limit reached (${quota.limit}). Please try again ${quota.reason === "daily" ? "tomorrow" : "next month"}.`,
        quotaReason: quota.reason,
      });
      return;
    }

    // Minor safeguards were resolved by the eligibility gate above (section 1b),
    // before any budget/quota spend. `eligibility.isMinor` drives the extra
    // safety system block appended below.

    // -----------------------------------------------------------------------
    // 5. Build request with SERVER-SIDE prompt and model config
    // -----------------------------------------------------------------------
    const systemPrompt = SYSTEM_PROMPTS[body.requestType];
    const config = MODEL_CONFIG[body.requestType];

    // For request types that need exercise-name constraint, prepend the catalog as a
    // separate cacheable block. Catalog FIRST so prompt edits don't invalidate the
    // larger catalog cache. NEVER inject per-user content into either system block —
    // user data goes in `messages`. Adding the catalog to other request types would
    // waste ~18K tokens per call for no benefit.
    const REQUEST_TYPES_WITH_CATALOG = new Set(["rehab_plan", "exercise_substitute", "wellness_plan"]);
    const systemBlocks = REQUEST_TYPES_WITH_CATALOG.has(body.requestType)
      ? [
          { type: "text", text: EXERCISE_CATALOG_CSV, cache_control: { type: "ephemeral" } },
          { type: "text", text: systemPrompt, cache_control: { type: "ephemeral" } },
        ]
      : [
          { type: "text", text: systemPrompt, cache_control: { type: "ephemeral" } },
        ];

    // Minors get an extra, cacheable safety block appended last (catalog +
    // prompt + minors = at most 3 of the 4 cache breakpoints — safe).
    if (eligibility.isMinor) {
      systemBlocks.push({ type: "text", text: MINOR_SAFETY_PROMPT, cache_control: { type: "ephemeral" } });
    }

    // AI usage telemetry (Phase 1). `providerStartedAt` doubles as the
    // "did we actually call the provider?" flag: it is set as the FIRST
    // statement inside the try, so the catch below can tell a provider
    // failure apart from a pre-provider one. Every pre-provider rejection
    // above (401 / 403 / 429 / quota / config) returns before this point and
    // is deliberately NOT recorded — no call, no cost.
    let providerStartedAt = 0;

    try {
      providerStartedAt = Date.now();
      const anthropicResponse = await fetch("https://api.anthropic.com/v1/messages", {
        method: "POST",
        headers: {
          "x-api-key": anthropicApiKey,
          "anthropic-version": "2023-06-01",
          "content-type": "application/json",
        },
        body: JSON.stringify({
          model: config.model,
          max_tokens: config.max_tokens,
          ...(config.temperature !== undefined && { temperature: config.temperature }),
          system: systemBlocks,
          messages: body.messages,
        }),
      });

      const responseData = await anthropicResponse.json() as {
        usage?: {
          input_tokens?: number;
          output_tokens?: number;
          cache_creation_input_tokens?: number;
          cache_read_input_tokens?: number;
        };
      };

      if (!anthropicResponse.ok) {
        // Refund quota — user didn't get a usable response.
        await decrementQuota(uid);
        // Error envelopes carry no usage — record zeros so the call still
        // counts toward the daily error rate.
        await recordAiUsage({
          fn: "claudeProxy",
          requestType: body.requestType,
          provider: "anthropic",
          model: config.model,
          durationMs: Date.now() - providerStartedAt,
          status: "upstream_error",
        });
        // Don't forward the raw upstream error envelope (leaks model/internal
        // details); log it server-side and return a generic error.
        logError(ctx, new Error("anthropic upstream error"),
          { stage: "anthropic_call", upstreamStatus: anthropicResponse.status });
        res.status(anthropicResponse.status).json({ error: "ai_service_error" });
        return;
      }

      // Record token usage on the context so the completion log captures it.
      if (responseData.usage) {
        ctx.metadata.tokensIn = responseData.usage.input_tokens;
        ctx.metadata.tokensOut = responseData.usage.output_tokens;
        ctx.metadata.cacheCreateTokens = responseData.usage.cache_creation_input_tokens;
        ctx.metadata.cacheReadTokens = responseData.usage.cache_read_input_tokens;
      }

      // Same numbers, shaped for the durable aiUsage record (Cloud Logging is
      // ephemeral). Used by both the success and schema-failure paths below —
      // tokens were spent either way.
      const usageTokens = {
        tokensIn: responseData.usage?.input_tokens,
        tokensOut: responseData.usage?.output_tokens,
        cacheCreateTokens: responseData.usage?.cache_creation_input_tokens,
        cacheReadTokens: responseData.usage?.cache_read_input_tokens,
      };

      // Tier 1: validate the AI response against the per-type Zod schema before
      // passing it back. If validation fails, bump a counter and return HTTP 502
      // so the iOS client surfaces a retry state rather than crashing on bad data.
      const schemaCheck = validateClaudeResponse(body.requestType, responseData);
      if (!schemaCheck.ok) {
        logWarn(ctx, "AI response rejected by schema validation", {
          requestType: body.requestType,
          reason: schemaCheck.reason,
        });
        try {
          await admin
            .firestore()
            .collection("responseValidationFailures")
            .doc(body.requestType)
            .set({
              count: admin.firestore.FieldValue.increment(1),
              lastReason: schemaCheck.reason,
              lastFailureAt: admin.firestore.FieldValue.serverTimestamp(),
            }, { merge: true });
        } catch (counterError) {
          // Counter is telemetry — never let its failure block the error response.
          logError(ctx, counterError, { stage: "response_validation_counter" });
        }
        await recordAiUsage({
          fn: "claudeProxy",
          requestType: body.requestType,
          provider: "anthropic",
          model: config.model,
          ...usageTokens,
          durationMs: Date.now() - providerStartedAt,
          status: "invalid_response",
        });
        // Quota already consumed (we did reach Anthropic) — do NOT refund. Treat
        // this as "we wasted a request" for quota purposes. 502 so the client
        // categorizes it as a server issue, matching existing invalidResponse(5xx)
        // handling in ClaudeAPIService.
        res.status(502).json({
          error: "ai_response_invalid",
          reason: schemaCheck.reason,
        });
        return;
      }

      await recordAiUsage({
        fn: "claudeProxy",
        requestType: body.requestType,
        provider: "anthropic",
        model: config.model,
        ...usageTokens,
        durationMs: Date.now() - providerStartedAt,
        status: "ok",
      });

      res.status(200).json(responseData);
    } catch (error) {
      // Fetch threw (network error, timeout, etc.) — refund quota.
      await decrementQuota(uid);
      if (providerStartedAt > 0) {
        // Only record when the provider call was actually attempted.
        await recordAiUsage({
          fn: "claudeProxy",
          requestType: body.requestType,
          provider: "anthropic",
          model: config.model,
          durationMs: Date.now() - providerStartedAt,
          status: "error",
        });
      }
      logError(ctx, error, { stage: "anthropic_call" });
      res.status(502).json({ error: "Failed to reach AI service" });
    }
  });

// ---------------------------------------------------------------------------
// Cross-Model Verification: GPT-4o-mini fact-checker for unverified exercises
// ---------------------------------------------------------------------------
interface CrossVerifyRequestBody {
  exercises: { name: string; condition: string }[];
  patientContext: string;
}

// Single source of truth for the verifier model: sent to OpenAI AND used as the
// price-table key in ai-pricing.ts, so the two can't drift apart.
const CROSS_VERIFY_MODEL = "gpt-4o-mini";

export const crossVerify = functions
  .runWith({ timeoutSeconds: 30, memory: "256MB", secrets: ["ANTHROPIC_API_KEY", "OPENAI_API_KEY"] })
  .https.onRequest(async (req, res) => {
    const ctx = newRequestContext("crossVerify");
    res.on("finish", () => logCompleted(ctx, res.statusCode));

    if (req.method !== "POST") {
      res.status(405).json({ error: "Method not allowed" });
      return;
    }

    // -----------------------------------------------------------------------
    // 1. Authenticate
    // -----------------------------------------------------------------------
    const authHeader = req.headers.authorization;
    if (!authHeader || !authHeader.startsWith("Bearer ")) {
      res.status(401).json({ error: "Missing or invalid Authorization header" });
      return;
    }

    const idToken = authHeader.split("Bearer ")[1];
    let uid: string;
    try {
      const decoded = await admin.auth().verifyIdToken(idToken);
      uid = decoded.uid;
      ctx.uid = uid;
    } catch {
      res.status(401).json({ error: "Invalid Firebase ID token" });
      return;
    }

    // Eligibility gate (P1-04): minor + health-data consent, before any
    // budget/quota/provider spend. Under-13 hard-blocks; withdrawn consent is
    // authoritative even for a stale/patched client.
    const eligibility = await checkEligibility(uid);
    if (eligibility.under13) {
      res.status(403).json({ error: "age_policy" });
      return;
    }
    if (eligibility.consentWithdrawn) {
      res.status(403).json({ error: "consent_required" });
      return;
    }

    // -----------------------------------------------------------------------
    // 2. Rate limit (shares the same limiter as claudeProxy)
    // -----------------------------------------------------------------------
    if (await isRateLimited(uid)) {
      res.status(429).json({ error: "Rate limit exceeded. Please wait and try again." });
      return;
    }

    // Global daily AI spend ceiling (denial-of-wallet guard). Shared counter.
    if (!(await checkGlobalDailyBudget())) {
      res.status(429).json({ error: "daily_capacity_reached" });
      return;
    }

    // -----------------------------------------------------------------------
    // 3. Validate request
    // -----------------------------------------------------------------------
    const body = req.body as CrossVerifyRequestBody;

    if (!body.exercises || !Array.isArray(body.exercises) || body.exercises.length === 0) {
      res.status(400).json({ error: "Missing or empty exercises array" });
      return;
    }

    if (body.exercises.length > 20) {
      res.status(400).json({ error: "Too many exercises (max 20)" });
      return;
    }

    // Bound attacker-controlled free-text that flows into the verifier prompt:
    // caps per-call token cost and limits prompt-injection surface against the
    // cross-model safety check.
    if (typeof body.patientContext === "string" && body.patientContext.length > 4000) {
      res.status(400).json({ error: "patientContext too long" });
      return;
    }

    // -----------------------------------------------------------------------
    // 4. Get OpenAI API key
    // -----------------------------------------------------------------------
    const openaiApiKey = process.env.OPENAI_API_KEY;
    if (!openaiApiKey) {
      logError(ctx, new Error("OPENAI_API_KEY not configured in environment"));
      res.status(500).json({ error: "Server configuration error" });
      return;
    }

    ctx.metadata.exerciseCount = body.exercises.length;

    // -----------------------------------------------------------------------
    // 4b. Per-user daily/monthly quota (shared cost cap across AI endpoints).
    // Placed AFTER validation + API key check so malformed / mis-configured
    // requests don't burn quota. Block is OUTSIDE the fetch try/catch so the
    // decrement paths on failure are reachable.
    // -----------------------------------------------------------------------
    let quota: QuotaResult;
    try {
      quota = await checkAndIncrementQuota(uid);
    } catch (err) {
      console.error("Quota check failed:", err);
      res.status(500).json({ error: "Quota check failed" });
      return;
    }
    if (!quota.ok) {
      res.status(429).json({
        error: `${quota.reason === "daily" ? "Daily" : "Monthly"} usage limit reached (${quota.limit}).`,
        quotaReason: quota.reason,
      });
      return;
    }

    // -----------------------------------------------------------------------
    // 5. Call GPT-4o-mini for each exercise (batched in one prompt)
    // -----------------------------------------------------------------------
    let providerStartedAt = 0;

    try {
      const clamp = (s: unknown) => String(s ?? "").slice(0, 200);
      const exerciseList = body.exercises
        .map((e, i) => `${i + 1}. Exercise: "${clamp(e.name)}" — Condition: "${clamp(e.condition)}"`)
        .join("\n");

      const userPrompt = `Evaluate whether each of the following exercises is appropriate for the given musculoskeletal condition.
Health context: ${body.patientContext || "Not provided"}

Exercises to evaluate:
${exerciseList}

For EACH exercise, respond with a JSON object in this exact format:
{
  "results": [
    {
      "safe": true/false,
      "confidence": 0.0-1.0,
      "reasoning": "brief explanation (1-2 sentences)",
      "concerns": ["list any specific concerns, empty array if none"]
    }
  ]
}

Return results in the same order as the exercises listed above.`;

      // AI usage telemetry (Phase 1): 0 means "provider not called yet", so the
      // catch below can distinguish a provider failure from a pre-provider one.
      providerStartedAt = Date.now();
      const openaiResponse = await fetch("https://api.openai.com/v1/chat/completions", {
        method: "POST",
        headers: {
          "Authorization": `Bearer ${openaiApiKey}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          model: CROSS_VERIFY_MODEL,
          temperature: 0.2,
          max_tokens: 2048,
          response_format: { type: "json_object" },
          messages: [
            {
              role: "system",
              content: "You are an exercise-safety fact-checker. You evaluate whether specific exercises are safe and appropriate for people with the musculoskeletal issues described. Be conservative — when in doubt, flag concerns. Respond only in JSON.",
            },
            {
              role: "user",
              content: userPrompt,
            },
          ],
        }),
      });

      if (!openaiResponse.ok) {
        const errorData = await openaiResponse.text();
        await decrementQuota(uid);
        await recordAiUsage({
          fn: "crossVerify",
          requestType: "cross_verify",
          provider: "openai",
          model: CROSS_VERIFY_MODEL,
          durationMs: Date.now() - providerStartedAt,
          status: "upstream_error",
        });
        logError(ctx, new Error(`OpenAI API returned ${openaiResponse.status}: ${errorData}`), { stage: "openai_call" });
        res.status(502).json({ error: "Failed to reach verification service" });
        return;
      }

      const openaiData = await openaiResponse.json() as {
        choices?: { message?: { content?: string } }[];
        usage?: { prompt_tokens?: number; completion_tokens?: number };
      };
      const content = openaiData.choices?.[0]?.message?.content;

      // OpenAI reports no prompt-cache split on this call — cache fields are 0.
      const crossVerifyUsage = {
        fn: "crossVerify" as const,
        requestType: "cross_verify" as const,
        provider: "openai" as const,
        model: CROSS_VERIFY_MODEL,
        tokensIn: openaiData.usage?.prompt_tokens,
        tokensOut: openaiData.usage?.completion_tokens,
        cacheCreateTokens: 0,
        cacheReadTokens: 0,
      };

      if (!content) {
        // Upstream delivered nothing useful — refund quota.
        await decrementQuota(uid);
        await recordAiUsage({
          ...crossVerifyUsage,
          durationMs: Date.now() - providerStartedAt,
          status: "invalid_response",
        });
        res.status(502).json({ error: "Empty response from verification service" });
        return;
      }

      // Parse the GPT response and forward to client
      const parsed = JSON.parse(content);
      await recordAiUsage({
        ...crossVerifyUsage,
        durationMs: Date.now() - providerStartedAt,
        status: "ok",
      });
      res.status(200).json(parsed);
    } catch (error) {
      // Fetch threw or JSON.parse of response threw — refund quota.
      await decrementQuota(uid);
      if (providerStartedAt > 0) {
        // Only record when the provider call was actually attempted.
        await recordAiUsage({
          fn: "crossVerify",
          requestType: "cross_verify",
          provider: "openai",
          model: CROSS_VERIFY_MODEL,
          durationMs: Date.now() - providerStartedAt,
          status: "error",
        });
      }
      logError(ctx, error, { stage: "openai_call" });
      res.status(502).json({ error: "Failed to reach verification service" });
    }
  });

// ---------------------------------------------------------------------------
// Cloud Function: deleteAccount
// Deletes ALL server-side data for the authenticated user, then the Auth user.
// Order matters: the Auth user is deleted LAST so any mid-way failure leaves
// the account able to re-authenticate and retry. Every step is idempotent.
// ---------------------------------------------------------------------------
export const deleteAccount = functions
  .runWith({ timeoutSeconds: 300, memory: "512MB" })
  .https.onRequest(async (req, res) => {
    const ctx = newRequestContext("deleteAccount");
    res.on("finish", () => logCompleted(ctx, res.statusCode));

    if (req.method !== "POST") {
      res.status(405).json({ error: "Method not allowed" });
      return;
    }
    const authHeader = req.headers.authorization;
    if (!authHeader || !authHeader.startsWith("Bearer ")) {
      res.status(401).json({ error: "Missing or invalid Authorization header" });
      return;
    }
    let uid: string;
    try {
      const decoded = await admin.auth().verifyIdToken(authHeader.split("Bearer ")[1]);
      uid = decoded.uid;
      ctx.uid = uid;
    } catch {
      res.status(401).json({ error: "Invalid Firebase ID token" });
      return;
    }

    const db = admin.firestore();
    try {
      // Firestore data: user tree + top-level sessionLogs/concernReports +
      // rate limits (extracted + emulator-tested in account-deletion.ts).
      await deleteUserFirestoreData(db, uid);

      // Storage session-log JSON blobs.
      await admin.storage().bucket().deleteFiles({ prefix: `sessionLogs/${uid}/` });

      // Auth user — LAST. A retry after a lost success response may arrive
      //    with a still-valid token for an already-deleted user; user-not-found
      //    here means the desired end state is already reached.
      try {
        await admin.auth().deleteUser(uid);
      } catch (error) {
        if ((error as { code?: string })?.code !== "auth/user-not-found") throw error;
      }

      res.status(200).json({ ok: true });
    } catch (error) {
      logError(ctx, error, { stage: "delete_account" });
      res.status(500).json({ error: "deletion_failed" });
    }
  });

// ---------------------------------------------------------------------------
// Virtual User Auth — mint Firebase Custom Tokens for virtual test users
// Only works for UIDs prefixed with "vuser-" and requires a shared secret.
// ---------------------------------------------------------------------------
export const createVirtualUserToken = functions.https.onRequest(async (req, res) => {
  // Test-only affordance. Hard-restrict to the dev project so it can never mint
  // impersonation tokens in production. `GCLOUD_PROJECT` is set by the Functions
  // runtime on deploy (same var billing-shutoff relies on); when it is defined
  // and is not the dev project we 404. If undefined (e.g. local), we fall
  // through to the secret gate, which still protects the endpoint.
  const proj = process.env.GCLOUD_PROJECT || process.env.GCP_PROJECT;
  if (proj && proj !== "pt-helper-dev") {
    res.status(404).send("Not found");
    return;
  }

  // No CORS header: this endpoint is invoked server-to-server (the virtual-user
  // harness mints via the Admin SDK directly), never from a browser origin.
  if (req.method !== "POST") {
    res.status(405).json({ error: "Method not allowed" });
    return;
  }

  const { virtualUserId, secret } = req.body || {};

  // Validate secret (constant-time, length-checked to avoid timing leaks).
  const expectedSecret = process.env.VIRTUAL_USER_SECRET;
  if (!expectedSecret) {
    console.error("VIRTUAL_USER_SECRET not configured");
    res.status(500).json({ error: "Server configuration error" });
    return;
  }

  const provided = Buffer.from(typeof secret === "string" ? secret : "");
  const expected = Buffer.from(expectedSecret);
  if (provided.length !== expected.length || !crypto.timingSafeEqual(provided, expected)) {
    res.status(403).json({ error: "Invalid secret" });
    return;
  }

  // Safety: only allow vuser- prefixed UIDs
  if (typeof virtualUserId !== "string" || !virtualUserId.startsWith("vuser-")) {
    res.status(400).json({ error: "virtualUserId must start with 'vuser-'" });
    return;
  }

  try {
    const customToken = await admin.auth().createCustomToken(virtualUserId);
    res.status(200).json({ token: customToken });
  } catch (error) {
    console.error("Error creating custom token:", error);
    res.status(500).json({ error: "Failed to create custom token" });
  }
});

// ---------------------------------------------------------------------------
// Daily analytics aggregation (runs at 01:00 UTC)
// Writes summary counts to analytics/dailyAggregates/{date}
// No health data — behavioral counts only
// ---------------------------------------------------------------------------
export const aggregateDailyMetrics = onSchedule("every day 01:00", async () => {
  const db = admin.firestore();
  const today = new Date().toISOString().split("T")[0]; // YYYY-MM-DD

  try {
    // Count users with profiles (path: users/{uid}/profile/health)
    // "profile" is the subcollection, "health" is the document ID
    const usersSnap = await db.collectionGroup("profile").count().get();
    const totalUsers = usersSnap.data().count;

    // Count total rehab plans
    const plansSnap = await db.collectionGroup("rehabPlans").count().get();
    const totalPlans = plansSnap.data().count;

    // Count total workout sessions
    const sessionsSnap = await db.collectionGroup("workoutSessions").count().get();
    const totalWorkoutSessions = sessionsSnap.data().count;

    // Count active plans (modified in last 14 days)
    const twoWeeksAgo = new Date();
    twoWeeksAgo.setDate(twoWeeksAgo.getDate() - 14);
    const activePlansSnap = await db.collectionGroup("rehabPlans")
      .where("lastModifiedDate", ">=", admin.firestore.Timestamp.fromDate(twoWeeksAgo))
      .count()
      .get();
    const activePlansCount = activePlansSnap.data().count;

    await db.collection("analytics").doc("dailyAggregates").collection("days").doc(today).set({
      date: today,
      totalUsers,
      totalPlans,
      totalWorkoutSessions,
      activePlansCount,
      generatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    console.log(`Daily metrics aggregated for ${today}: ${totalUsers} users, ${totalPlans} plans, ${totalWorkoutSessions} sessions`);
  } catch (error) {
    console.error("Error aggregating daily metrics:", error);
  }
});

// ---------------------------------------------------------------------------
// Nightly Email Report — AI-written summary of app health
// Runs at 07:00 local time, collects metrics, calls Claude for summary,
// sends via SendGrid.
// ---------------------------------------------------------------------------

/**
 * Format a day-over-day delta with an explicit sign so a negative number
 * (e.g. after a deletion) is never mistaken for a missing value. Zero is
 * printed bare — signing "+0"/"-0" would be noise. Non-finite input (should
 * never happen; defensive only) collapses to "0".
 */
export function formatDelta(delta: number): string {
  if (!Number.isFinite(delta) || delta === 0) return "0";
  return delta > 0 ? `+${delta}` : `${delta}`;
}

/**
 * Top `limit` request types from an `aiUsageDaily.byType` cost map, sorted by
 * cost descending. Ties broken alphabetically for deterministic output (the
 * report otherwise reads differently run-to-run for equal-cost days).
 */
export function topRequestTypesByCost(
  byTypeCostUSD: Record<string, number> | undefined | null,
  limit = 5,
): Array<{ type: string; costUSD: number }> {
  if (!byTypeCostUSD) return [];
  return Object.entries(byTypeCostUSD)
    .map(([type, costUSD]) => ({
      type,
      costUSD: typeof costUSD === "number" && Number.isFinite(costUSD) ? costUSD : 0,
    }))
    .sort((a, b) => b.costUSD - a.costUSD || a.type.localeCompare(b.type))
    .slice(0, Math.max(0, limit));
}

async function collectMetrics(): Promise<string> {
  const db = admin.firestore();
  const today = new Date().toISOString().split("T")[0];
  const yesterday = new Date(Date.now() - 86_400_000).toISOString().split("T")[0];
  const dayBefore = new Date(Date.now() - 2 * 86_400_000).toISOString().split("T")[0];

  const lines: string[] = [`Report date: ${today}`, ""];

  // --- Firestore daily aggregates (from aggregateDailyMetrics) + deltas ---
  try {
    const todayDoc = await db
      .collection("analytics").doc("dailyAggregates").collection("days").doc(today)
      .get();
    const yesterdayDoc = await db
      .collection("analytics").doc("dailyAggregates").collection("days").doc(yesterday)
      .get();

    if (todayDoc.exists) {
      const d = todayDoc.data()!;
      lines.push("## Firestore Aggregates (today)");
      lines.push(`- Total users: ${d.totalUsers}`);
      lines.push(`- Total rehab plans: ${d.totalPlans}`);
      lines.push(`- Total workout sessions: ${d.totalWorkoutSessions}`);
      lines.push(`- Active plans (last 14d): ${d.activePlansCount}`);
    } else {
      lines.push("## Firestore Aggregates (today): no data yet");
    }

    if (yesterdayDoc.exists) {
      const d = yesterdayDoc.data()!;
      lines.push("\n## Firestore Aggregates (yesterday)");
      lines.push(`- Total users: ${d.totalUsers}`);
      lines.push(`- Total rehab plans: ${d.totalPlans}`);
      lines.push(`- Total workout sessions: ${d.totalWorkoutSessions}`);
      lines.push(`- Active plans (last 14d): ${d.activePlansCount}`);
    }

    // Day-over-day deltas (Phase 6). Reuses the same pure helper the
    // dashboard's "totals" tile uses so the two surfaces never disagree on
    // the math. Deltas can be negative after deletions — printed as-is via
    // formatDelta, never clamped or hidden.
    const deltas = computeTotalsDeltas(
      todayDoc.exists ? (todayDoc.data() as Record<string, unknown>) : undefined,
      yesterdayDoc.exists ? (yesterdayDoc.data() as Record<string, unknown>) : undefined,
    );
    if (deltas) {
      lines.push("\n## Day-over-Day Deltas (today vs yesterday)");
      lines.push(`- New users: ${formatDelta(deltas.totalUsers)}`);
      lines.push(`- New rehab plans: ${formatDelta(deltas.totalPlans)}`);
      lines.push(`- New workout sessions: ${formatDelta(deltas.totalWorkoutSessions)}`);
      lines.push(`- Active plans (14d) change: ${formatDelta(deltas.activePlansCount)}`);
    } else {
      lines.push("\n## Day-over-Day Deltas: no data yet (need both today's and yesterday's aggregate)");
    }
  } catch (err) {
    lines.push(`Firestore aggregate error: ${err}`);
  }

  // --- Crash count (last 24h) ---
  // Was `collectionGroup("crashLogs")` — nothing ever writes that collection,
  // so this count was permanently 0. Replaced with the real crashMarker field
  // on sessionLogs, served by the same COLLECTION_GROUP composite index
  // (crashMarker ASC, uploadedAt ASC) Phase 3's dashboard crash tile uses.
  const oneDayAgo = admin.firestore.Timestamp.fromDate(new Date(Date.now() - 86_400_000));

  try {
    const crashSnap = await db
      .collectionGroup("sessionLogs")
      .where("crashMarker", "==", true)
      .where("uploadedAt", ">=", oneDayAgo)
      .count()
      .get();
    lines.push(`\n## Crash Logs (last 24h): ${crashSnap.data().count}`);
  } catch (err) {
    lines.push(`\nCrash log query error: ${err}`);
  }

  // --- Session logs (last 24h) ---
  try {
    const sessionLogSnap = await db
      .collectionGroup("sessionLogs")
      .where("uploadedAt", ">=", oneDayAgo)
      .count()
      .get();
    lines.push(`## Session Logs uploaded (last 24h): ${sessionLogSnap.data().count}`);
  } catch (err) {
    lines.push(`Session log query error: ${err}`);
  }

  // --- Missing exercise images reported ---
  try {
    const missingSnap = await db.collection("missingExerciseImages").count().get();
    lines.push(`\n## Missing Exercise Images reported: ${missingSnap.data().count}`);
  } catch (err) {
    lines.push(`Missing images query error: ${err}`);
  }

  // --- GA4 engagement & funnel (Phase 6; materialized by pullDailyAnalytics) ---
  // GA4's export lands the following morning, so "today" has no shard yet —
  // this reads yesterday (+ the day before, for a comparison line).
  try {
    const [yesterdayGa4, dayBeforeGa4] = await Promise.all([
      dashboardDailyCollection(db).doc(yesterday).get(),
      dashboardDailyCollection(db).doc(dayBefore).get(),
    ]);

    if (!yesterdayGa4.exists) {
      lines.push(
        "\n## GA4 Engagement (yesterday): no data yet (GA4 export pending or pipeline not yet run)",
      );
    } else {
      const y = yesterdayGa4.data() as Record<string, unknown>;
      const engagement = (y.engagement ?? {}) as Record<string, unknown>;
      const funnel = (y.funnel ?? {}) as Record<string, unknown>;
      const workout = (y.workout ?? {}) as Record<string, unknown>;

      lines.push("\n## GA4 Engagement (yesterday)");
      lines.push(`- DAU: ${Number(engagement.dau) || 0}`);
      lines.push(`- Sessions: ${Number(engagement.totalSessions) || 0}`);
      lines.push(`- Workouts completed: ${Number(workout.completed) || 0}`);
      lines.push(`- Sign-ins: ${Number(funnel.signIns) || 0}`);
      lines.push(`- Assessments completed: ${Number(funnel.assessmentCompleted) || 0}`);
      lines.push(`- Rehab plans generated: ${Number(funnel.rehabPlanGenerated) || 0}`);
      lines.push(`- Workouts started: ${Number(funnel.workoutStarted) || 0}`);

      if (dayBeforeGa4.exists) {
        const p = dayBeforeGa4.data() as Record<string, unknown>;
        const pEngagement = (p.engagement ?? {}) as Record<string, unknown>;
        const pWorkout = (p.workout ?? {}) as Record<string, unknown>;
        const dauDelta = (Number(engagement.dau) || 0) - (Number(pEngagement.dau) || 0);
        const sessionsDelta =
          (Number(engagement.totalSessions) || 0) - (Number(pEngagement.totalSessions) || 0);
        const completedDelta = (Number(workout.completed) || 0) - (Number(pWorkout.completed) || 0);
        lines.push(
          `- vs day before: DAU ${formatDelta(dauDelta)}, Sessions ${formatDelta(sessionsDelta)}, ` +
          `Workouts completed ${formatDelta(completedDelta)}`,
        );
      } else {
        lines.push(
          "- vs day before: no data yet (GA4 export pending or pipeline not yet run)",
        );
      }
    }
  } catch (err) {
    lines.push(`\nGA4 engagement query error: ${err}`);
  }

  // --- AI usage & cost (Phase 6; written by recordAiUsage on every attempted call) ---
  try {
    const [aiTodaySnap, aiYesterdaySnap, budgetSnap] = await Promise.all([
      db.collection(AI_USAGE_DAILY_COLLECTION).doc(today).get(),
      db.collection(AI_USAGE_DAILY_COLLECTION).doc(yesterday).get(),
      db.collection(AI_BUDGET_COLLECTION).doc(AI_BUDGET_DOC_ID).get(),
    ]);

    const todayAi = shapeAiUsageDaily(
      today,
      aiTodaySnap.exists ? (aiTodaySnap.data() as Record<string, unknown>) : undefined,
    );
    const yesterdayAi = shapeAiUsageDaily(
      yesterday,
      aiYesterdaySnap.exists ? (aiYesterdaySnap.data() as Record<string, unknown>) : undefined,
    );
    // Live budget counter resets lazily (only when the NEXT AI call's
    // transaction sees data.date !== today) — apply the same date check the
    // dashboard uses so a quiet morning doesn't show yesterday's leftover
    // count as "today".
    const callsToday = resolveAiCallsToday(
      budgetSnap.exists ? (budgetSnap.data() as Record<string, unknown>) : undefined,
      today,
    );

    lines.push("\n## AI Usage & Cost");
    lines.push(`- Budget: ${callsToday}/${AI_DAILY_BUDGET} calls used today`);
    lines.push(
      `- Today: ${todayAi.calls} calls, ${todayAi.errors} errors ` +
      `(${todayAi.errorRatePct}% error rate), $${todayAi.totalCostUSD.toFixed(4)} spent, ` +
      `${todayAi.avgLatencyMs}ms avg latency`,
    );
    lines.push(
      `- Yesterday: ${yesterdayAi.calls} calls, ${yesterdayAi.errors} errors ` +
      `(${yesterdayAi.errorRatePct}% error rate), $${yesterdayAi.totalCostUSD.toFixed(4)} spent`,
    );

    const topToday = topRequestTypesByCost(todayAi.byTypeCostUSD);
    if (topToday.length > 0) {
      lines.push("- Top request types by cost (today):");
      for (const { type, costUSD } of topToday) {
        lines.push(`  - ${type}: $${costUSD.toFixed(4)}`);
      }
    } else {
      lines.push("- Top request types by cost (today): no calls recorded yet");
    }
  } catch (err) {
    lines.push(`\nAI usage query error: ${err}`);
  }

  return lines.join("\n");
}

/**
 * Escape the four characters that can break out of HTML text or an attribute
 * value. MUST run before the markdown replaces below, which inject their own
 * trusted tags — escaping afterwards would mangle those.
 */
function escapeHtml(text: string): string {
  return text
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

/**
 * Simple markdown → HTML. The input is NOT trusted: it is either Claude's
 * generated nightly summary or, on the validation-failure path, `metricsText`
 * with raw thrown errors interpolated into it. The output is stored on the
 * report doc and assigned to `innerHTML` by the dashboard
 * (dashboard/public/js/overview.js), so unescaped input here is stored XSS
 * against whoever opens the dashboard. Escape first, then add markup.
 *
 * Exported for testing — see functions/test/markdown-to-html.test.ts.
 */
export function markdownToHtml(md: string): string {
  return escapeHtml(md)
    .replace(/^## (.+)$/gm, "<h2 style=\"color:#6B7F6B;margin:16px 0 8px;font-size:18px;\">$1</h2>")
    .replace(/^- (.+)$/gm, "<li style=\"margin:4px 0;\">$1</li>")
    .replace(/(<li[^>]*>.*<\/li>\n?)+/g, (match) => `<ul style="padding-left:20px;">${match}</ul>`)
    .replace(/\*\*(.+?)\*\*/g, "<strong>$1</strong>")
    .replace(/\n\n/g, "<br><br>")
    .replace(/\n/g, "<br>");
}

/**
 * The nightly-report recipient MUST be configured explicitly. Returns null when
 * `REPORT_RECIPIENT_EMAIL` is unset/blank so the caller skips sending — there is
 * NO personal-email fallback (P3-03): operational data must never fail open to an
 * individual mailbox that can silently survive into another environment. Use an
 * organization-controlled distribution address.
 */
export function resolveReportRecipient(env: NodeJS.ProcessEnv = process.env): string | null {
  const recipient = env.REPORT_RECIPIENT_EMAIL?.trim();
  return recipient ? recipient : null;
}

/**
 * The nightly-report SendGrid sender, configured the same way and for the same
 * reason as the recipient above. Returns null when `REPORT_SENDER_EMAIL` is
 * unset/blank so the caller skips sending — no personal-email fallback.
 *
 * A hardcoded sender is worse than a hardcoded recipient: it ships an individual's
 * address in source (this repo's default branch is public), and SendGrid rejects
 * any sender that isn't verified on the account, so a baked-in address silently
 * becomes wrong the moment the sending account changes.
 */
export function resolveReportSender(env: NodeJS.ProcessEnv = process.env): string | null {
  const sender = env.REPORT_SENDER_EMAIL?.trim();
  return sender ? sender : null;
}

// ---------------------------------------------------------------------------
// Nightly report → dashboard persistence
// ---------------------------------------------------------------------------
//
// SendGrid is not a durable channel (the account can be — and has been —
// deactivated), so the report is written to
// `analytics/dashboard/reports/{YYYY-MM-DD}` BEFORE any send is attempted and
// surfaced on the monitoring dashboard's overview page. Email became the
// secondary channel; a delivery failure now costs the notification, never the
// report itself.

/** Longest text field we will store. Guards Firestore's 1 MiB doc ceiling —
 *  a rejected write would lose the whole report, the one thing this must not
 *  do. Real reports are a few KB, so this never fires in practice. */
export const NIGHTLY_REPORT_MAX_FIELD_CHARS = 100_000;

/** Trim an arbitrary thrown value down to a short, storable message. */
export function shortErrorMessage(err: unknown, maxLength = 200): string {
  const raw = err instanceof Error ? err.message : String(err);
  const clean = raw.replace(/\s+/g, " ").trim();
  if (clean.length === 0) return "unknown error";
  return clean.length > maxLength ? `${clean.slice(0, maxLength - 1)}…` : clean;
}

function truncateField(value: string): string {
  return value.length > NIGHTLY_REPORT_MAX_FIELD_CHARS
    ? `${value.slice(0, NIGHTLY_REPORT_MAX_FIELD_CHARS)}\n…[truncated]`
    : value;
}

export interface NightlyReportEmailOutcome {
  emailStatus: NightlyReportEmailStatus;
  /** Short failure message; null on every non-"failed" status. Written (not
   *  omitted) so a same-day re-run can't leave yesterday's error behind. */
  emailError: string | null;
}

/**
 * Resolve the delivery status stored on the report doc.
 *
 * Called TWICE per run: once before the send with `attempted` unset — nothing
 * has gone out yet, so the doc lands as "skipped" — and once after the attempt
 * resolves, which merges "sent" or "failed" over it. Missing config short-
 * circuits to "skipped" because no send is possible at all.
 */
export function resolveEmailOutcome(input: {
  recipientConfigured: boolean;
  sendgridConfigured: boolean;
  attempted?: boolean;
  sendError?: unknown;
}): NightlyReportEmailOutcome {
  if (!input.recipientConfigured || !input.sendgridConfigured) {
    return { emailStatus: "skipped", emailError: null };
  }
  if (!input.attempted) return { emailStatus: "skipped", emailError: null };
  if (input.sendError !== undefined && input.sendError !== null) {
    return { emailStatus: "failed", emailError: shortErrorMessage(input.sendError) };
  }
  return { emailStatus: "sent", emailError: null };
}

export interface NightlyReportDoc {
  date: string;
  summaryMarkdown: string;
  summaryHtml: string;
  validationPassed: boolean;
  metricsText: string;
  emailStatus: NightlyReportEmailStatus;
  emailError: string | null;
}

/**
 * Assemble the Firestore document. `generatedAt` is added by the writer (it is
 * a server sentinel, not a value), which keeps this pure and unit-testable.
 */
export function buildNightlyReportDoc(input: {
  date: string;
  summaryMarkdown: string;
  summaryHtml: string;
  validationPassed: boolean;
  metricsText: string;
  outcome: NightlyReportEmailOutcome;
}): NightlyReportDoc {
  return {
    date: input.date,
    summaryMarkdown: truncateField(input.summaryMarkdown),
    summaryHtml: truncateField(input.summaryHtml),
    validationPassed: input.validationPassed,
    metricsText: truncateField(input.metricsText),
    emailStatus: input.outcome.emailStatus,
    emailError: input.outcome.emailError,
  };
}

/** Write the report. Never throws — a persistence problem must not take the
 *  email path down with it (and vice versa). */
async function persistNightlyReport(ctx: RequestContext, doc: NightlyReportDoc): Promise<void> {
  try {
    await dashboardReportsCollection(admin.firestore())
      .doc(doc.date)
      .set(
        { ...doc, generatedAt: admin.firestore.FieldValue.serverTimestamp() },
        { merge: true },
      );
  } catch (err) {
    logWarn(ctx, "nightly_report_persist_failed", {
      date: doc.date,
      errorMessage: shortErrorMessage(err),
    });
  }
}

/** Merge the post-send delivery status onto an already-persisted report. */
async function updateNightlyReportEmailStatus(
  ctx: RequestContext,
  date: string,
  outcome: NightlyReportEmailOutcome,
): Promise<void> {
  try {
    await dashboardReportsCollection(admin.firestore())
      .doc(date)
      .set(
        { emailStatus: outcome.emailStatus, emailError: outcome.emailError },
        { merge: true },
      );
  } catch (err) {
    logWarn(ctx, "nightly_report_status_update_failed", {
      date,
      errorMessage: shortErrorMessage(err),
    });
  }
}

export const sendNightlyReport = onSchedule(
  {
    schedule: "every day 07:00",
    timeZone: "Asia/Jerusalem",
    secrets: ["ANTHROPIC_API_KEY", "SENDGRID_API_KEY"],
  },
  async () => {
    // --- 1. Collect metrics ---
    const metricsText = await collectMetrics();
    console.log("Collected metrics:\n", metricsText);

    // --- 2. Call Claude for human-readable summary ---
    const anthropicApiKey = process.env.ANTHROPIC_API_KEY;
    if (!anthropicApiKey) {
      console.error("ANTHROPIC_API_KEY not configured");
      return;
    }

    const systemPrompt = SYSTEM_PROMPTS.nightly_report;
    const config = MODEL_CONFIG.nightly_report;

    let summary: string;
    const reportStartedAt = Date.now();
    try {
      const response = await fetch("https://api.anthropic.com/v1/messages", {
        method: "POST",
        headers: {
          "x-api-key": anthropicApiKey,
          "anthropic-version": "2023-06-01",
          "content-type": "application/json",
        },
        body: JSON.stringify({
          model: config.model,
          max_tokens: config.max_tokens,
          temperature: config.temperature,
          system: systemPrompt,
          messages: [{ role: "user", content: metricsText }],
        }),
      });

      const data = await response.json() as {
        content?: { type: string; text: string }[];
        usage?: {
          input_tokens?: number;
          output_tokens?: number;
          cache_creation_input_tokens?: number;
          cache_read_input_tokens?: number;
        };
      };
      // AI usage telemetry (Phase 1) — recorded between two existing statements
      // so it cannot alter the summary/fallback logic below.
      await recordAiUsage({
        fn: "sendNightlyReport",
        requestType: "nightly_report",
        provider: "anthropic",
        model: config.model,
        tokensIn: data.usage?.input_tokens,
        tokensOut: data.usage?.output_tokens,
        cacheCreateTokens: data.usage?.cache_creation_input_tokens,
        cacheReadTokens: data.usage?.cache_read_input_tokens,
        durationMs: Date.now() - reportStartedAt,
        status: response.ok ? "ok" : "upstream_error",
      });
      summary = data.content?.[0]?.text || "Failed to generate summary";
    } catch (err) {
      console.error("Claude API error:", err);
      await recordAiUsage({
        fn: "sendNightlyReport",
        requestType: "nightly_report",
        provider: "anthropic",
        model: config.model,
        durationMs: Date.now() - reportStartedAt,
        status: "error",
      });
      summary = `Error generating AI summary. Raw metrics:\n\n${metricsText}`;
    }

    // --- 2.5 Tier 3 PR B: structural validation ---
    // Catch malformed Claude output (truncated tables, empty code fences,
    // dangling headings) before it ships to the inbox. On failure we send a
    // degraded email instead so the recipient knows something went wrong but
    // the cron job still completes (vs silently failing or sending garbage).
    const reportValidation = validateNightlyReport(summary);
    if (!reportValidation.ok) {
      console.warn("Nightly report failed structural validation:", reportValidation.reasons);
      // Bump the failure counter — fire-and-forget; counter problems must
      // never block the email path.
      try {
        await admin
          .firestore()
          .collection("reportValidationFailures")
          .doc("nightly_report")
          .set(
            {
              count: admin.firestore.FieldValue.increment(1),
              lastReasons: reportValidation.reasons,
              lastFailureAt: admin.firestore.FieldValue.serverTimestamp(),
            },
            { merge: true },
          );
      } catch (counterError) {
        console.error("Failed to bump reportValidationFailures counter:", counterError);
      }
      // Replace the summary with a degraded message that still includes the
      // raw metrics so the recipient has SOMETHING actionable.
      summary = [
        "## Report generation issue",
        "",
        "Claude's nightly report failed structural validation. Reasons:",
        "",
        ...reportValidation.reasons.map((r) => `- ${r}`),
        "",
        "Raw metrics from collectMetrics() are below. The AI summary is omitted to avoid sending a malformed email.",
        "",
        "```",
        metricsText,
        "```",
      ].join("\n");
    }

    // --- 3. Persist to the dashboard BEFORE attempting the email ---
    // The dashboard is now the primary channel: whatever happens to SendGrid
    // below, the report is already readable at analytics/dashboard/reports.
    const ctx = newRequestContext("sendNightlyReport");
    const reportDate = new Date().toISOString().split("T")[0];
    const summaryHtml = markdownToHtml(summary);
    const sendgridKey = process.env.SENDGRID_API_KEY;
    const recipientEmail = resolveReportRecipient();
    const senderEmail = resolveReportSender();

    await persistNightlyReport(
      ctx,
      buildNightlyReportDoc({
        date: reportDate,
        summaryMarkdown: summary,
        summaryHtml,
        validationPassed: reportValidation.ok,
        metricsText,
        outcome: resolveEmailOutcome({
          recipientConfigured: Boolean(recipientEmail),
          sendgridConfigured: Boolean(sendgridKey),
        }),
      }),
    );

    // --- 4. Send email via SendGrid (best-effort) ---
    // No personal-email fallback (P3-03): skip the send when no org recipient is set.
    if (!recipientEmail) {
      console.warn("sendNightlyReport: REPORT_RECIPIENT_EMAIL not configured — skipping send");
      return;
    }

    if (!senderEmail) {
      console.warn("sendNightlyReport: REPORT_SENDER_EMAIL not configured — skipping send");
      return;
    }

    if (!sendgridKey) {
      console.error("SENDGRID_API_KEY not configured — logging report to console instead");
      console.log("=== NIGHTLY REPORT ===\n", summary);
      return;
    }

    sgMail.setApiKey(sendgridKey);

    const htmlBody = `
<!DOCTYPE html>
<html>
<head><meta charset="utf-8"></head>
<body style="font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;max-width:600px;margin:0 auto;padding:20px;color:#3D3D3D;background:#F5F2EC;">
  <div style="background:#FFFFFF;border-radius:12px;padding:24px;box-shadow:0 1px 3px rgba(0,0,0,0.1);">
    <h1 style="color:#6B7F6B;font-size:22px;margin:0 0 4px;">PT Helper Daily Report</h1>
    <p style="color:#9B8F80;font-size:14px;margin:0 0 20px;">${reportDate}</p>
    <hr style="border:none;border-top:1px solid #E8E3DA;margin:16px 0;">
    ${summaryHtml}
    <hr style="border:none;border-top:1px solid #E8E3DA;margin:16px 0;">
    <p style="color:#9B8F80;font-size:12px;text-align:center;margin:0;">
      Generated by PT Helper Nightly Report &bull; Powered by Claude AI
    </p>
  </div>
</body>
</html>`;

    let sendError: unknown = null;
    try {
      await sgMail.send({
        to: recipientEmail,
        from: { email: senderEmail, name: "PT Helper Reports" },
        subject: `PT Helper Daily Report — ${reportDate}`,
        html: htmlBody,
      });
      console.log(`Nightly report sent to ${recipientEmail}`);
    } catch (err) {
      sendError = err;
      console.error("SendGrid error:", err);
    }

    // --- 5. Record how the send went on the already-persisted report ---
    await updateNightlyReportEmailStatus(
      ctx,
      reportDate,
      resolveEmailOutcome({
        recipientConfigured: true,
        sendgridConfigured: true,
        attempted: true,
        sendError,
      }),
    );
  }
);

// ---------------------------------------------------------------------------
// Agent-Powered Recovery Insights
// Uses Claude Managed Agents for multi-step analysis.
// Falls back to single-call claudeProxy path on failure.
// ---------------------------------------------------------------------------
export const agentInsights = functions
  .runWith({
    timeoutSeconds: 300,
    memory: "512MB",
    secrets: ["ANTHROPIC_API_KEY", "MANAGED_AGENT_ID", "MANAGED_ENVIRONMENT_ID"],
  })
  .https.onRequest(async (req, res) => {
    const ctx = newRequestContext("agentInsights");
    res.on("finish", () => logCompleted(ctx, res.statusCode));

    if (req.method !== "POST") {
      res.status(405).json({ error: "Method not allowed" });
      return;
    }

    // 1. Authenticate
    const authHeader = req.headers.authorization;
    if (!authHeader || !authHeader.startsWith("Bearer ")) {
      res.status(401).json({ error: "Missing or invalid Authorization header" });
      return;
    }

    const idToken = authHeader.split("Bearer ")[1];
    let uid: string;
    try {
      const decoded = await admin.auth().verifyIdToken(idToken);
      uid = decoded.uid;
      ctx.uid = uid;
    } catch {
      res.status(401).json({ error: "Invalid Firebase ID token" });
      return;
    }

    // Eligibility gate (P1-04): minor + health-data consent, before any
    // budget/quota/provider spend. Under-13 hard-blocks; withdrawn consent is
    // authoritative even for a stale/patched client.
    const eligibility = await checkEligibility(uid);
    if (eligibility.under13) {
      res.status(403).json({ error: "age_policy" });
      return;
    }
    if (eligibility.consentWithdrawn) {
      res.status(403).json({ error: "consent_required" });
      return;
    }

    // 2. Rate limit
    if (await isRateLimited(uid)) {
      res.status(429).json({ error: "Rate limit exceeded. Please wait and try again." });
      return;
    }

    // Global daily AI spend ceiling (denial-of-wallet guard). Shared counter.
    if (!(await checkGlobalDailyBudget())) {
      res.status(429).json({ error: "daily_capacity_reached" });
      return;
    }

    // 3. Fetch user data from Firestore
    let data;
    try {
      data = await fetchRecoveryInsightsData(uid);
    } catch (err) {
      logError(ctx, err, { stage: "fetch_recovery_data" });
      res.status(500).json({ error: "Failed to fetch recovery data" });
      return;
    }

    ctx.metadata.sessionCount = data.sessionCount;

    if (data.sessionCount < MINIMUM_SESSION_COUNT) {
      res.status(400).json({
        error: `Need at least ${MINIMUM_SESSION_COUNT} sessions in the past 14 days`,
      });
      return;
    }

    // Per-user daily/monthly quota — charged only now that the request is
    // eligible AND has enough data to call the provider, so this agent route
    // can't draw a disproportionate share of shared AI spend and users aren't
    // charged for ineligible/insufficient requests (P1-07).
    let insightsQuota: QuotaResult;
    try {
      insightsQuota = await checkAndIncrementQuota(uid);
    } catch (err) {
      logError(ctx, err, { stage: "quota_check" });
      res.status(500).json({ error: "Quota check failed" });
      return;
    }
    if (!insightsQuota.ok) {
      res.status(429).json({
        error: `${insightsQuota.reason === "daily" ? "Daily" : "Monthly"} usage limit reached (${insightsQuota.limit}). Please try again ${insightsQuota.reason === "daily" ? "tomorrow" : "next month"}.`,
        quotaReason: insightsQuota.reason,
      });
      return;
    }

    // 4. Try managed agent
    let resultJson: string;
    const agentStartedAt = Date.now();
    try {
      const result = await runRecoveryInsightsAgent(data.userMessage);

      // Server-side validation before returning
      if (!validateInsightResult(result)) {
        throw new Error("Agent returned invalid insight structure");
      }

      resultJson = JSON.stringify(result);
      ctx.metadata.path = "agent";
    } catch (agentErr) {
      // 5. Fallback to single-call Messages API with Haiku
      logWarn(ctx, "agent_fallback", { stage: "managed_agent", fallbackReason: agentErr instanceof Error ? agentErr.message : String(agentErr) });
      ctx.metadata.path = "fallback";

      // The agent attempt happened and must be counted, even though it failed.
      // Without this record the only trace of a managed-agent call is the
      // fallback that replaced it, so the dashboard reads a 100% agent success
      // rate no matter how often the agent is actually failing. Cost stays null
      // for the same reason as the success path: agent tokens are not
      // observable from this handler.
      await recordAiUsage({
        fn: "agentInsights",
        requestType: "recovery_insights",
        provider: "anthropic",
        model: "managed_agent",
        durationMs: Date.now() - agentStartedAt,
        status: "error",
        costUSD: null,
        estimated: true,
      });

      const anthropicApiKey = process.env.ANTHROPIC_API_KEY;
      if (!anthropicApiKey) {
        res.status(500).json({ error: "Server configuration error" });
        return;
      }

      try {
        const systemPrompt = SYSTEM_PROMPTS.recovery_insights;
        const config = MODEL_CONFIG.recovery_insights;

        const fallbackStartedAt = Date.now();
        const fallbackResponse = await fetch("https://api.anthropic.com/v1/messages", {
          method: "POST",
          headers: {
            "x-api-key": anthropicApiKey,
            "anthropic-version": "2023-06-01",
            "content-type": "application/json",
          },
          body: JSON.stringify({
            model: config.model,
            max_tokens: config.max_tokens,
            temperature: config.temperature,
            system: [
              { type: "text", text: systemPrompt, cache_control: { type: "ephemeral" } },
            ],
            messages: [{ role: "user", content: data.userMessage }],
          }),
        });

        const fallbackData = await fallbackResponse.json();

        // AI usage telemetry (Phase 1). Placed between two existing statements
        // so it can't disturb control flow; one record covers both the ok and
        // upstream-error branches below. A later validation failure still counts
        // as "ok" here — the provider call itself succeeded and was billed.
        await recordAiUsage({
          fn: "agentInsights",
          requestType: "recovery_insights",
          provider: "anthropic",
          model: config.model,
          tokensIn: fallbackData?.usage?.input_tokens,
          tokensOut: fallbackData?.usage?.output_tokens,
          cacheCreateTokens: fallbackData?.usage?.cache_creation_input_tokens,
          cacheReadTokens: fallbackData?.usage?.cache_read_input_tokens,
          durationMs: Date.now() - fallbackStartedAt,
          status: fallbackResponse.ok ? "ok" : "upstream_error",
        });

        if (!fallbackResponse.ok) {
          // Don't forward the raw upstream error envelope to the client.
          logError(ctx, new Error("recovery fallback upstream error"),
            { stage: "fallback_call", upstreamStatus: fallbackResponse.status });
          res.status(502).json({ error: "ai_service_error" });
          return;
        }

        // Validate the fallback payload before returning. recovery_insights has
        // no zod schema in validateClaudeResponse (it's validated by
        // validateInsightResult), so parse the model JSON and check it here.
        try {
          const text = fallbackData?.content?.[0]?.text;
          const parsed = JSON.parse(typeof text === "string" ? text : "");
          if (!validateInsightResult(parsed)) {
            logError(ctx, new Error("fallback insight failed validation"),
              { stage: "fallback_validation" });
            res.status(502).json({ error: "Failed to generate recovery insights" });
            return;
          }
        } catch (parseErr) {
          logError(ctx, parseErr, { stage: "fallback_validation" });
          res.status(502).json({ error: "Failed to generate recovery insights" });
          return;
        }

        // Validated — return in Anthropic format for iOS compatibility.
        res.status(200).json(fallbackData);
        return;
      } catch (fallbackErr) {
        logError(ctx, fallbackErr, { stage: "fallback_call" });
        res.status(502).json({ error: "Failed to generate recovery insights" });
        return;
      }
    }

    // AI usage telemetry (Phase 1): only the managed-agent success path reaches
    // here (the fallback returns early). The agent runs server-side at Anthropic
    // and its stream events expose no token counts to this handler, so tokens
    // are 0 and cost is explicitly unknown (null) rather than a fabricated 0.
    await recordAiUsage({
      fn: "agentInsights",
      requestType: "recovery_insights",
      provider: "anthropic",
      model: "managed_agent",
      durationMs: Date.now() - agentStartedAt,
      status: "ok",
      costUSD: null,
      estimated: true,
    });

    // 6. Wrap agent result in Anthropic response format for iOS compatibility
    res.status(200).json({
      content: [{ type: "text", text: resultJson }],
      stop_reason: "end_turn",
    });
  });

// ---------------------------------------------------------------------------
// Agent-Powered Cross-Session Form Analysis
// Uses Claude Managed Agents (Sonnet) to compare the current session's pose
// metrics against the user's prior persisted sessions of the same exercise.
// Falls back to the single-call form_analysis Haiku path on any agent failure.
// ---------------------------------------------------------------------------
const FORM_EXERCISE_NAME_MAX_LENGTH = 200;
const FORM_USER_MESSAGE_MAX_LENGTH = 50_000;

export const agentFormAnalysis = functions
  .runWith({
    timeoutSeconds: 300,
    memory: "512MB",
    secrets: ["ANTHROPIC_API_KEY", "FORM_AGENT_ID", "MANAGED_ENVIRONMENT_ID"],
  })
  .https.onRequest(async (req, res) => {
    const ctx = newRequestContext("agentFormAnalysis");
    res.on("finish", () => logCompleted(ctx, res.statusCode));

    if (req.method !== "POST") {
      res.status(405).json({ error: "Method not allowed" });
      return;
    }

    // 1. Authenticate
    const authHeader = req.headers.authorization;
    if (!authHeader || !authHeader.startsWith("Bearer ")) {
      res.status(401).json({ error: "Missing or invalid Authorization header" });
      return;
    }

    const idToken = authHeader.split("Bearer ")[1];
    let uid: string;
    try {
      const decoded = await admin.auth().verifyIdToken(idToken);
      uid = decoded.uid;
      ctx.uid = uid;
    } catch {
      res.status(401).json({ error: "Invalid Firebase ID token" });
      return;
    }

    // Eligibility gate (P1-04): minor + health-data consent, before any
    // budget/quota/provider spend. Under-13 hard-blocks; withdrawn consent is
    // authoritative even for a stale/patched client.
    const eligibility = await checkEligibility(uid);
    if (eligibility.under13) {
      res.status(403).json({ error: "age_policy" });
      return;
    }
    if (eligibility.consentWithdrawn) {
      res.status(403).json({ error: "consent_required" });
      return;
    }

    // 2. Rate limit
    if (await isRateLimited(uid)) {
      res.status(429).json({ error: "Rate limit exceeded. Please wait and try again." });
      return;
    }

    // Global daily AI spend ceiling (denial-of-wallet guard). Shared counter.
    if (!(await checkGlobalDailyBudget())) {
      res.status(429).json({ error: "daily_capacity_reached" });
      return;
    }

    // 3. Validate request body — the CURRENT session's metrics travel in the
    // body (they are not in Firestore yet; iOS persists after feedback).
    const exerciseName = req.body?.exerciseName;
    const userMessage = req.body?.userMessage;
    if (typeof exerciseName !== "string" || exerciseName.length === 0 ||
        exerciseName.length > FORM_EXERCISE_NAME_MAX_LENGTH) {
      res.status(400).json({ error: "Missing or invalid exerciseName" });
      return;
    }
    if (typeof userMessage !== "string" || userMessage.length === 0 ||
        userMessage.length > FORM_USER_MESSAGE_MAX_LENGTH) {
      res.status(400).json({ error: "Missing or invalid userMessage" });
      return;
    }

    // 4. Fetch prior form sessions for this exercise
    let history;
    try {
      history = await fetchFormHistoryData(uid, exerciseName);
    } catch (err) {
      logError(ctx, err, { stage: "fetch_form_history" });
      res.status(500).json({ error: "Failed to fetch form history" });
      return;
    }

    ctx.metadata.sessionCount = history.sessionCount;

    if (history.sessionCount < MINIMUM_FORM_HISTORY_COUNT) {
      res.status(400).json({
        error: `Need at least ${MINIMUM_FORM_HISTORY_COUNT} prior sessions of this exercise`,
      });
      return;
    }

    // Per-user daily/monthly quota — charged only now that the request is
    // eligible AND has enough history to call the provider (P1-07).
    let formQuota: QuotaResult;
    try {
      formQuota = await checkAndIncrementQuota(uid);
    } catch (err) {
      logError(ctx, err, { stage: "quota_check" });
      res.status(500).json({ error: "Quota check failed" });
      return;
    }
    if (!formQuota.ok) {
      res.status(429).json({
        error: `${formQuota.reason === "daily" ? "Daily" : "Monthly"} usage limit reached (${formQuota.limit}). Please try again ${formQuota.reason === "daily" ? "tomorrow" : "next month"}.`,
        quotaReason: formQuota.reason,
      });
      return;
    }

    // 5. Try managed agent with history + current session
    const combinedMessage = `${history.userMessage}\n\nCURRENT SESSION:\n${userMessage}`;
    let resultJson: string;
    const agentStartedAt = Date.now();
    try {
      const result = await runFormAnalysisAgent(combinedMessage);

      // Server-side validation before returning
      if (!validateFormResult(result)) {
        throw new Error("Agent returned invalid form analysis structure");
      }

      resultJson = JSON.stringify(result);
      ctx.metadata.path = "agent";
    } catch (agentErr) {
      // 6. Fallback to single-call Messages API with Haiku, using the
      // CURRENT-SESSION message only (the Haiku prompt is single-session;
      // its JSON shape has no cross-session fields).
      logWarn(ctx, "agent_fallback", { stage: "form_agent", fallbackReason: agentErr instanceof Error ? agentErr.message : String(agentErr) });
      ctx.metadata.path = "fallback";

      // Count the failed agent attempt — see the matching note in agentInsights.
      await recordAiUsage({
        fn: "agentFormAnalysis",
        requestType: "form_analysis",
        provider: "anthropic",
        model: "managed_agent",
        durationMs: Date.now() - agentStartedAt,
        status: "error",
        costUSD: null,
        estimated: true,
      });

      const anthropicApiKey = process.env.ANTHROPIC_API_KEY;
      if (!anthropicApiKey) {
        res.status(500).json({ error: "Server configuration error" });
        return;
      }

      try {
        const systemPrompt = SYSTEM_PROMPTS.form_analysis;
        const config = MODEL_CONFIG.form_analysis;

        const fallbackStartedAt = Date.now();
        const fallbackResponse = await fetch("https://api.anthropic.com/v1/messages", {
          method: "POST",
          headers: {
            "x-api-key": anthropicApiKey,
            "anthropic-version": "2023-06-01",
            "content-type": "application/json",
          },
          body: JSON.stringify({
            model: config.model,
            max_tokens: config.max_tokens,
            temperature: config.temperature,
            system: [
              { type: "text", text: systemPrompt, cache_control: { type: "ephemeral" } },
            ],
            messages: [{ role: "user", content: userMessage }],
          }),
        });

        const fallbackData = await fallbackResponse.json();

        // AI usage telemetry (Phase 1). Additive between two existing statements;
        // one record covers both the ok and upstream-error branches below.
        await recordAiUsage({
          fn: "agentFormAnalysis",
          requestType: "form_analysis",
          provider: "anthropic",
          model: config.model,
          tokensIn: fallbackData?.usage?.input_tokens,
          tokensOut: fallbackData?.usage?.output_tokens,
          cacheCreateTokens: fallbackData?.usage?.cache_creation_input_tokens,
          cacheReadTokens: fallbackData?.usage?.cache_read_input_tokens,
          durationMs: Date.now() - fallbackStartedAt,
          status: fallbackResponse.ok ? "ok" : "upstream_error",
        });

        if (!fallbackResponse.ok) {
          logError(ctx, new Error("form fallback upstream error"),
            { stage: "fallback_call", upstreamStatus: fallbackResponse.status });
          res.status(502).json({ error: "ai_service_error" });
          return;
        }

        // Validate fallback against the single-call schema (unlike
        // recovery_insights, form_analysis has a zod schema).
        const check = validateClaudeResponse("form_analysis", fallbackData);
        if (!check.ok) {
          logError(ctx, new Error(check.reason), { stage: "fallback_validation" });
          res.status(502).json({ error: "ai_response_invalid" });
          return;
        }

        // Return fallback response directly (already in Anthropic format)
        res.status(200).json(fallbackData);
        return;
      } catch (fallbackErr) {
        logError(ctx, fallbackErr, { stage: "fallback_call" });
        res.status(502).json({ error: "Failed to generate form analysis" });
        return;
      }
    }

    // AI usage telemetry (Phase 1): managed-agent success path only (the
    // fallback returns early). Tokens are not observable from the agent stream,
    // so cost is explicitly unknown rather than a fabricated 0.
    await recordAiUsage({
      fn: "agentFormAnalysis",
      requestType: "form_analysis",
      provider: "anthropic",
      model: "managed_agent",
      durationMs: Date.now() - agentStartedAt,
      status: "ok",
      costUSD: null,
      estimated: true,
    });

    // 7. Wrap agent result in Anthropic response format for iOS compatibility
    res.status(200).json({
      content: [{ type: "text", text: resultJson }],
      stop_reason: "end_turn",
    });
  });

// ---------------------------------------------------------------------------
// On-demand exercise image generation
// ---------------------------------------------------------------------------
export const generateExerciseImage = functions
  .runWith({
    timeoutSeconds: 540,
    memory: "512MB",
    secrets: ["BFL_API_KEY", "GEMINI_API_KEY"],
  })
  .https.onRequest(async (req, res) => {
    const ctx = newRequestContext("generateExerciseImage");
    res.on("finish", () => logCompleted(ctx, res.statusCode));

    if (req.method !== "POST") {
      res.status(405).json({ error: "Method not allowed" });
      return;
    }

    // 1. Authenticate
    const authHeader = req.headers.authorization;
    if (!authHeader || !authHeader.startsWith("Bearer ")) {
      res.status(401).json({ error: "Missing or invalid Authorization header" });
      return;
    }

    const idToken = authHeader.split("Bearer ")[1];
    let uid: string;
    try {
      const decoded = await admin.auth().verifyIdToken(idToken);
      uid = decoded.uid;
      ctx.uid = uid;
    } catch {
      res.status(401).json({ error: "Invalid Firebase ID token" });
      return;
    }

    // Eligibility gate (P1-04): minor + health-data consent, before any
    // provider spend. Under-13 hard-blocks; withdrawn consent is authoritative
    // even for a stale/patched client.
    const eligibility = await checkEligibility(uid);
    if (eligibility.under13) {
      res.status(403).json({ error: "age_policy" });
      return;
    }
    if (eligibility.consentWithdrawn) {
      res.status(403).json({ error: "consent_required" });
      return;
    }

    // 2. Handle request
    try {
      const result = await handleGenerateExerciseImage({
        body: req.body,
        uid,
      });

      ctx.metadata.resultStatus = result.status;
      ctx.metadata.matchType = result.matchType;

      const statusCode = result.status === "rate_limited" ? 429
        : result.status === "generation_failed" || result.status === "qa_failed" ? 502
        : 200;

      res.status(statusCode).json(result);
    } catch (err) {
      logError(ctx, err, { stage: "image_generation" });
      res.status(500).json({ status: "generation_failed", message: "Internal error", retryable: true });
    }
  });
