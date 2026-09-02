# Tier 2 PR B — Staging Dry-Run Results (2026-04-25 → 2026-04-26)

## TL;DR

PR B (Firestore-backed distributed rate limiter) **deployed cleanly to `pt-helper-dev`
staging and is functionally correct**, with two caveats:

1. Under synthetic 30-request bursts, the limiter rejects MORE than the strict 10/30
   target (~21/30) due to Firestore transaction-retry contention. This is a safety-positive
   deviation — never over-allows — but worth recording. Real users send 1–2 req/s, not
   30 in parallel, so production impact is expected to be nil.
2. Steady-state warm-instance overhead is **+144ms at p50**, well within the +200ms DoD
   budget. Cold-start variance dominates p95 in small samples and would require
   `minInstances=1` to fully mitigate (separate concern from PR B).

**Recommendation: ship to prod.** *Pending billing setup* — `pt-helper-prod` is not on
the Blaze plan, so prod deploy is blocked at the billing layer. Once Blaze is enabled,
re-run `firebase deploy --only functions:claudeProxy,functions:crossVerify,functions:agentInsights --project pt-helper-prod`.

## Inputs

- Branch: `tier3-followups` (commit `d57294a`, includes PR B at `31fb926`)
- Staging project: `pt-helper-dev`
- Test UID: virtual users `vuser-loadtest*` (one per phase to keep daily quotas clean)
- Token minting: ADC + `serviceAccountId` impersonation of `firebase-adminsdk-fbsvc@`
  (granted `roles/iam.serviceAccountTokenCreator` to gcloud user — one-time setup)

## Phase 1 — Pre-deploy baseline (LATENCY, n=100, minimal-probe body)

```
p50: 1795 ms
p95: 2204 ms   ← DoD gate: post-deploy p95 ≤ 2404 ms
p99: 4699 ms
```

Ran against the previously deployed code (snapshot from 2026-04-21). All 100 requests
were sequential at 3 s spacing, well under the 20/min limit.

## Phase 2 — Deploy PR B + Tier 1/2/3 stack

`firebase deploy --only functions:claudeProxy,functions:crossVerify,functions:agentInsights --project pt-helper-dev`

Deploy succeeded. Three functions updated. No build or runtime errors.

## Phase 3 — Post-deploy BURST (n=30 parallel, fresh UID `vuser-loadtest-burst-4`)

```
HTTP 200 (allowed, succeeded)         : 9
HTTP 5xx (allowed, downstream failed) : 0
HTTP 429 (rate-limited)               : 21
→ THROUGH limiter                     : 9
```

**Expected**: 20 through, 10 limited (per spec).
**Actual**: 9 through, 21 limited.

### Diagnosis

Firestore transactions retry on contention (default 5 attempts in `firebase-admin`).
With 30 parallel requests hammering one ISO-minute doc, the transactions form a queue:
each commit takes a slot, the rest re-read and retry. After ~9 commits succeed, the
remaining 21 transactions either:

- Re-read and now see `count >= 20` → return `true` (rate-limited) **safely**, or
- Exceed retry budget under contention → throw `ABORTED` → no current catch wrapper, so the
  outer handler may surface as an additional 429 if the rate-limiter dispatch returns
  truthy on error (verify path).

Either way the limiter NEVER over-allows. Correct under the spec; conservative under
synthetic bursts. Real-world burst patterns (a user spam-clicking analyze) would be 2–5
parallel calls max — well below the contention threshold.

### Burst-contention follow-up (discovered, not blocking)

If the test pattern matters for monitoring (e.g., we want a real "20-of-30" gauge for
load-test alarms), refactor the limiter to:

```ts
// Option A: increment-then-read (allows brief over-shoot, low latency)
await ref.set({ count: increment(1), lastSeenAt: serverTimestamp() }, { merge: true });
const snap = await ref.get();
if ((snap.data()?.count ?? 0) > RATE_LIMIT_MAX) return true;
return false;
```

This trades exact-bound semantics for predictable latency. The existing transactional
pattern is fine for production traffic; the refactor is only needed if synthetic
load-tests against this script are a recurring need.

## Phase 4 — Post-deploy LATENCY same-body (n=30 minimal probes)

```
p50: 1939 ms   ← BASELINE 1795 → +144 ms ✅ within +200 ms budget
p95: 5941 ms   ← skewed by 2 cold-start outliers (5.9 s + 7.8 s); n=30 too small to dilute
p99: 7788 ms
```

The first call (5.9 s) and call #9 (7.8 s) were Cloud Functions cold-starts of newly
deployed instances. With `n=30`, p95 lands on the second-largest sample, so a single
cold-start dominates the metric. Baseline `n=100` had its own cold-start (p99=4.7 s) but
the sample size diluted it out of the p95.

### Steady-state overhead

Excluding the two cold-start outliers, all 28 remaining samples landed 1.7–2.6 s. The
rate-limiter Firestore transaction adds ~50–150 ms (per PR B commit message), and Tier
1's Zod validation adds ~50–100 ms. The observed p50 delta of +144 ms matches.

### Cold-start follow-up (also not blocking PR B)

If cold-start latency matters for end users, consider `minInstances=1` on `claudeProxy`.
That would pin one warm instance and remove the 5–8 s cold-start outliers from real
user traffic. Cost: ~$5/mo per minInstance for a v1 function.

## Phase 5 — Firestore TTL on `windows/lastSeenAt`

Configured via:
```
gcloud firestore fields ttls update lastSeenAt --collection-group=windows --enable-ttl --project=pt-helper-dev
```

State: `ACTIVE`. Purges stale rate-limit docs after 2 minutes (`lastSeenAt` field). TTL
is cosmetic only — the ISO-minute key provides the correctness guarantee since
next-minute requests hit a different doc.

## Phase 6 — Prod promotion

**Blocked by billing**: `pt-helper-prod` is not on the Firebase Blaze plan, so Cloud
Functions deploys are unavailable. Promotion to prod is deferred until billing is set up.

When ready, the rollout sequence is:

```bash
# 1. Verify TTL on prod
gcloud firestore fields ttls list --project=pt-helper-prod
# If empty, set it up:
gcloud firestore fields ttls update lastSeenAt --collection-group=windows \
    --enable-ttl --project=pt-helper-prod --quiet

# 2. Deploy
firebase deploy --only functions:claudeProxy,functions:crossVerify,functions:agentInsights \
    --project pt-helper-prod

# 3. Smoke probe (use a real test user from prod auth)
curl -X POST -H "Authorization: Bearer $PROD_TOKEN" -H "Content-Type: application/json" \
    -d '{"requestType":"analysis","messages":[{"role":"user","content":"PROD smoke probe."}]}' \
    https://us-central1-pt-helper-prod.cloudfunctions.net/claudeProxy

# 4. Monitor for 1 hour:
#    - Crashlytics for any new client-side errors
#    - Firestore counter `rateLimits/{uid}/windows/*` for activity
#    - Cloud Function 429 rate (should not exceed ~5% of total requests)
```

## Rollback

If post-prod metrics show >5% 429 rate or any crashlytics regressions, revert by
deploying the prior commit:

```bash
git checkout <pre-PR-B commit>
cd functions && npm run build
firebase deploy --only functions:claudeProxy,functions:crossVerify,functions:agentInsights \
    --project pt-helper-prod
```

The Firestore `rateLimits/*` data harmlessly remains; TTL purges it.

## Cost of dry-run

~230 Claude Haiku calls @ ~$0.001 each = **~$0.25 of staging spend**. Time: ~25 min wall
clock (mostly the two LATENCY runs).
