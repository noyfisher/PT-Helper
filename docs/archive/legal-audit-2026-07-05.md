> **Historical.** Audit of branch `mvvc-rebrand-improvements` (no longer exists). Finding A6 (legal-doc dates) has since been fixed; see `ios/PT-Helper/docs/security-review-2026-06-10.md` for current compliance status.

# PT-Helper Legal & Compliance Audit

**Date:** 2026-07-05 · **Branch audited:** `mvvc-rebrand-improvements` (clean tree) · **Live exposure:** ~25–30 TestFlight beta testers

> **This is a structural and technical audit, not legal advice.** It compares what actually exists in the code and shipped flows against current law, Anthropic policy, and Apple policy (all re-verified against live sources on 2026-07-05). Items that cannot be resolved by engineering are listed in §3 (Attorney-Required Flags). Facts not determinable from code are in §4 (Open Questions).

**Method:** Six parallel research passes — three over the codebase (legal docs/consent flow, AI prompt & scope-of-practice language, data flows/privacy), three over live external sources (Anthropic Usage Policy & Commercial Terms, Apple App Store Review Guidelines & App Store Connect requirements, federal/state health-data & AI law). All load-bearing file:line claims were independently re-verified in the working tree.

---

## 1. Inventory Table

Status: ✅ present · 🟡 partial · ❌ absent. Risk reflects severity × current live exposure (real users today).

### A. Baseline legal documents

| # | Compliance element | Status | Evidence | Risk |
|---|---|---|---|---|
| A1 | Privacy Policy exists & is shown in-app | ✅ | `Models/LegalContent.swift:10–110` (in-app, "July 2026"); shown in onboarding (`Views/OnboardingSteps/BasicInfoStepView.swift:162–202`) and Settings (`Views/SettingsView.swift:270–281`) | — |
| A2 | Terms of Service exists & is shown in-app | ✅ | `Models/LegalContent.swift:114–203`; same surfacing as A1 | — |
| A3 | Separate liability waiver / assumption-of-risk document | ❌ | No standalone document anywhere in repo. Partial substitutes: ToS liability clause (`LegalContent.swift:180–190`) and per-plan risk-acknowledgement modal (`Views/Components/SeriousWarningModal.swift:44–96`, "I've read this & accept the risk") | **High** |
| A4 | ToS acceptance is a blocking gate | 🟡 | Checkbox required to continue onboarding (`ViewModels/OnboardingViewModel.swift:225`) — **but the onboarding "Skip" button bypasses it entirely**: `Views/OnboardingView.swift:18–28` → `RootView.swift:145–147` drops the user into the full app with no ToS/Privacy acceptance | **High** |
| A5 | Acceptance recorded, timestamped, versioned, provable | 🟡 | Local UserDefaults only (`OnboardingViewModel.swift:108–109`); `tosAcceptedDate` is written once and never read (write-only dead code); nothing in Firestore; no version string; no re-acceptance on ToS change | **High** |
| A6 | Repo legal docs match shipped legal text | ❌ | `docs/PRIVACY_POLICY.md` / `docs/TERMS_OF_SERVICE.md` say "March 2025"; shipped `LegalContent.swift` says "July 2026" and adds pose-data/AI-agent disclosures the docs lack | Med |
| A7 | Privacy policy matches actual data practices | ❌ | Three inaccuracies: (1) "Not stored by Anthropic beyond the API request" (`LegalContent.swift:64`) — only true under a ZDR agreement, which is not evidenced anywhere; (2) Firebase/Google Analytics undisclosed despite `Analytics.setUserID(uid)` (`RootView.swift:54`, `Services/AnalyticsService.swift:86–88`); (3) "Delete your account and all data" (`LegalContent.swift:92`) — deletion is incomplete (D6). SendGrid (aggregates only) and health-bearing session-log uploads also undisclosed | **High** |
| A8 | Pre-analysis informed-consent screen | 🟡 | `Views/DisclaimerView.swift:5–93` — strong, blocking, `interactiveDismissDisabled()` — **but gates only the pain-analysis path** (`Views/BodyMap3DView.swift:762–769`); the wellness AI flow has no disclaimer gate at all | Med |
| A9 | Per-result medical disclaimers | ✅ | Server-forced disclaimer text in every AI response (`functions/src/index.ts:292, 322, 483`); rendered at `Views/AnalysisResultView.swift:97–108`, `Views/WellnessResultView.swift:64`, `Views/RecoveryInsightsDetailView.swift:265`, `Views/FormAnalysisView.swift:202`; PDF export footer (`Services/PDFExportService.swift:193`) | — |

### B. Scope-of-practice risk (highest-severity category)

| # | Compliance element | Status | Evidence | Risk |
|---|---|---|---|---|
| B1 | System prompts avoid framing the product as a substitute for medical care | ❌ | `functions/src/index.ts:270`: *"YOUR AUDIENCE: Regular people who **may not be able to see a doctor right away**."* Directly undercuts every "not a substitute" disclaimer in the app | **High** |
| B2 | AI does not claim/imply licensed-professional identity | ❌ | "You are a **PT rehabilitation specialist**" (`index.ts:328, 362`), "**PT wellness specialist**" (`:522`), "expert **physiotherapy** form analysis specialist" (`:407`, `setup-form-agent.ts:14`), "expert **physical therapy** recovery analyst" (`setup-managed-agent.ts:13`); "never **prescribe**" / "NEVER **prescribe**" (`index.ts:331, 345, 525`). Directly implicated by CA AB 489 (effective 2026-01-01): AI may not use terms/letters implying licensed healing-arts care; each use a separate violation | **High** |
| B3 | App name avoids protected professional title | ❌ | `CFBundleDisplayName = "PT Helper"` (`project.pbxproj:469`). "P.T." is statutorily title-protected (e.g., CA BPC §2633). MVVC rebrand is incomplete — Settings, legal docs, PDF footer still say "PT Helper" | **High** (attorney) |
| B4 | Diagnostic framing in prompts | 🟡 | Two-call differential-diagnosis pipeline: "generate candidate conditions… Rank by how well each fits the full clinical picture" (`index.ts:268`), clinical decision rules (Ottawa Knee, Canadian C-Spine, cauda equina screens) in `CLINICAL_KNOWLEDGE_BASE` (`index.ts:212–258`); user called "the patient" throughout. Counterweights: "educational only, not a diagnosis" in every prompt; mandatory disclaimer text; confidence humility instruction (`index.ts:304`) | **High** (attorney) |
| B5 | Emergency red-flag hard-block (injury flow) | ✅ | `.emergency` → `EmergencyRedirectView` replaces results, ungated, 911 CTA (`Views/AnalyzingView.swift:160–169`, `Views/Components/EmergencyRedirectView.swift`) | — |
| B6 | Emergency red-flag routing (wellness flow) | ❌ | **Dead safety path.** `WellnessAnalysisViewModel.worstSeverity` is computed and documented for routing (`ViewModels/WellnessAnalysisViewModel.swift:14–18`) but **no view reads it** — a wellness user reporting "chest pain and shortness of breath" gets a wellness plan, never the emergency screen | **High** |
| B7 | Urgent red flags block plan generation | ❌ | After an `.urgent` flag (possible fracture, no-self-manage condition), **"Build Rehab Plan Anyway"** remains one tap away (`Views/AnalysisResultView.swift:437–444`) | Med-High |
| B8 | Pre-submission red-flag screening | ❌ | Red-flag detection runs only *after* two AI round-trips (`Models/InjuryAnalyzer.swift:52–124`); emergency-pattern data is sent to Claude before the user is redirected | Med |
| B9 | Referral logic ("see a doctor") | ✅ | Layered: symptom/condition red-flag detectors (`Services/ResponseValidationPipeline.swift:162–367`), server prompt requires MD-evaluation nudges (`index.ts:276, 400`), 26-keyword no-self-manage condition list | — |
| B10 | Human-in-the-loop / professional oversight | ❌ | None. Pipeline is fully automated (user → Claude ×2 → machine validation → plan). All "verification" layers are machine (second AI pass, GPT-4o-mini cross-check, knowledge graph). Copy repeatedly refers users to "your PT" the app never verifies exists | **High** (see C1) |
| B11 | AI disclosure to users | ✅ | Prominent and repeated at every AI touchpoint: intro carousel "AI ENGINE ACTIVE" (`Views/IntroCarouselView.swift:144`), analyzing screens, results trust badge (`AnalysisResultView.swift:153`), "AI-powered" badges in wellness/form flows; Anthropic named in privacy policy (`LegalContent.swift:85`) | — |
| B12 | Calibrated confidence presentation | 🟡 | Main flow: qualitative match strength, no percentages, honest 85%-cap explainer (`AnalysisResultView.swift:63–94`). **But** Dashboard leaks raw numeric confidence under the clinical header **"Differential Analysis"** (`Views/Dashboard/DashDifferentialsTable.swift:9, 57`; `DashConfidenceChart.swift:9, 25`) with none of the explainer copy | Med |
| B13 | Unsubstantiated accuracy claims | 🟡 | "rehab guidance built on **clinical protocols**" / "clinically-informed protocols" (`Views/IntroCarouselView.swift:170, 263`) — evidence-quality claims with no substantiation mechanism (relevant to Apple 1.4.1 "must support accuracy claims"). No "clinically validated"/"trusted by" claims found | Med |

### C. Anthropic Usage Policy & Commercial Terms (contractual — enforced by Anthropic)

| # | Compliance element | Status | Evidence | Risk |
|---|---|---|---|---|
| C1 | High-Risk Use Case safeguards (healthcare) | ❌/🟡 | AUP (eff. 2025-09-15) requires, for consumer-facing "healthcare decisions, medical diagnosis, patient care… or other medical guidance": (1) qualified-professional review **before dissemination** — absent (B10); (2) AI disclosure — present (B11). The injury differential pipeline reads squarely as "medical diagnosis"; the wellness flow plausibly fits the express carve-out ("Wellness advice (e.g., advice on sleep, stress, nutrition, exercise…) does not fall under this category"). Classification of the rehab-plan flow is a gray zone | **High** (attorney + Anthropic) |
| C2 | Anthropic minors policy (if any user <18) | ❌ | Policy (updated 2026-03-16) requires age verification, content moderation, monitoring/reporting, minor-specific educational resources, AI disclosure, COPPA compliance. App has **no age gate** despite collecting full DOB (D2); ToS says 13+ but nothing enforces it (`LegalContent.swift:160`; no DOB check anywhere). Founder coaches high-school athletes — tester ages unknown (§4) | **High** |
| C3 | Data retention posture with Anthropic | 🟡 | All 10 request types use `claude-haiku-4-5-20251001`; agents use `claude-sonnet-4-6` (`functions/src/index.ts:585–594`, `setup-managed-agent.ts:148`, `setup-form-agent.ts:187`) — not Covered Models, so ZDR is *available* but no ZDR agreement is evidenced; the privacy policy's "not stored by Anthropic" claim is therefore unsupported (A7). Managed Agents sessions (recovery insights, form agent) are **never ZDR-eligible** and have no automatic deletion | Med |
| C4 | Output responsibility / indemnity awareness | 🟡 | Commercial Terms: outputs "as is," customer indemnifies Anthropic for claims arising from inputs or policy-violating use. If the high-risk safeguards are missing, indemnity exposure runs toward the developer | Med (attorney) |

### D. Data privacy

| # | Compliance element | Status | Evidence | Risk |
|---|---|---|---|---|
| D1 | HIPAA applicability correctly scoped | ✅ | No covered-entity/BA relationship → HIPAA inapplicable. Only repo mention is accurate: `STARTUP-PLAN.md:67` ("You are not HIPAA-covered"). No HIPAA claims in app or policies | — |
| D2 | Data inventory awareness | ✅ (for the record) | Full health profile collected: name, **full DOB**, sex, height/weight, medical conditions, medications + history, surgeries incl. restrictions/hardware, injuries, pain assessments with free text, prior diagnosis/treatment text, wellness assessments, per-region pain logs, pose-derived biometrics (`Models/UserProfile.swift:7–31`, `Models/PainAssessment.swift:57–78`, `Models/FormAnalysis.swift`) | — |
| D3 | FTC Health Breach Notification Rule readiness | ❌ | App very likely a "vendor of personal health records" under the 2024-amended rule (covers symptom/fitness trackers; "breach" includes voluntary unauthorized disclosure — the GoodRx theory). No breach-response plan; exposure compounds with A7 policy inaccuracies (§5 deception) | **High** |
| D4 | Washington MHMDA compliance (if any WA user) | ❌ | No separate consumer-health-data privacy policy/link, no opt-in collection consent, no separate sharing consent, no 45-day deletion pipeline. No small-business exemption; one WA tester triggers it; private right of action is live (first class actions filed 2025) | **High** (if WA users — §4) |
| D5 | California exposure | 🟡 | CCPA/CPRA thresholds not met (~30 users, no $26.6M revenue). CalOPPA satisfied by existing policy. **CMIA §56.06** may deem the app a "provider of health care" (no size threshold) — attorney flag. AB 489 covered at B2 | Med (attorney) |
| D6 | Complete account/data deletion | ❌ | `Views/SettingsView.swift:448–503` deletes only `["profile", "rehabPlans", "workoutSessions", "notes", "wellnessPlans"]` (`:458`). **Orphaned after deletion:** Firestore `assessments` (pain snapshots), `formAnalyses` (biometrics), `streakData`, `analysisOutcomes`, `quotas`; Firestore + Storage `sessionLogs` (which contain condition/region names); local `AnalysisResultStore` file, on-disk session log, workout checkpoint. Contradicts dialog copy (`:406`), privacy policy (A7), and Apple 5.1.1(v) full-deletion requirement | **High** |
| D7 | Health data in telemetry | 🟡 | GA4 is behavioral-only by design (`AnalyticsService.swift:4–6`) with two edge cases (exercise name/score in `formAnalysisCompleted`, `worst_severity` in wellness events). **SessionLogger uploads condition names + confidences, body regions, wellness goals** to Firebase Storage/Firestore (`Services/SessionLogger.swift:249–272`; `ViewModels/InjuryAnalysisViewModel.swift:143–189`) — undisclosed in the policy | Med |
| D8 | Encryption in transit / at rest | ✅ | HTTPS-only endpoints (`Services/APIConfig.swift:5–15`), no ATS exceptions, no `http://` URLs; Firestore/Storage encrypted at rest by default; PHI local caches use `.completeFileProtection` + backup exclusion (`Services/AnalysisResultStore.swift:3–9`); no Anthropic key in the bundle; identity minimization to Anthropic (age computed, name/DOB/uid never sent — `Models/InjuryAnalyzer.swift:131–138`) | — |
| D9 | Access control | ✅/🟡 | Owner-only Firestore rules for user data (`firestore.rules:21–23`); proxy has token auth, 20 req/min rate limit, daily/monthly quotas. Gaps: no Firebase App Check; `missingExerciseImages` readable by any authenticated user (no PII by design, `firestore.rules:61–66`) | Low-Med |
| D10 | Data export / portability | 🟡 | Per-plan PDF only (`Services/PDFExportService.swift`); no full-account export | Low |
| D11 | Video / pose data handling | ✅ | Form-check video never leaves the device (Apple Vision on-device, `Services/PoseDetectionService.swift:7–8`), deleted after analysis (`ViewModels/FormAnalysisViewModel.swift:87–89`); only derived joint metrics are sent | — |

### E. App Store submission (verified against live Apple sources, 2026-07-05)

| # | Compliance element | Status | Evidence | Risk |
|---|---|---|---|---|
| E1 | Guideline 1.4.1 — consult-a-doctor + accuracy claims | 🟡 | Doctor-consultation reminders are pervasive (A8, A9, B9). Accuracy-claim exposure limited to "clinical protocols" copy (B13). No sensor-measurement or dosage features (1.4.2 n/a) | Med |
| E2 | Regulated-medical-device declaration (eff. 2026-03-26) | ❌ (pending) | Required at submission for apps in Health & Fitness/Medical categories **or** with "frequent" Medical/Treatment age-rating answers (AI output explicitly counts toward frequency). Declaring "No" is permitted if accurate. Cannot be audited from repo — App Store Connect item | Med (blocking at submission) |
| E3 | Age rating consistency | ❌ (pending) | "Frequent" Medical or Treatment Information → 16+ rating; ToS says 13+ (`LegalContent.swift:160`); no in-app age gate (C2). These three must be reconciled | Med |
| E4 | 5.1.1(v) in-app account deletion | 🟡 | Exists (Settings → Delete Account) but must delete *all* records — currently incomplete (D6) | **High** (must-fix) |
| E5 | 5.1.1(ix) legal-entity submission | ❌ (open) | "Apps that provide services in highly regulated fields (such as… healthcare)… **should** be submitted by a legal entity… not by an individual developer." Account type unknown (§4) | Med (attorney/business) |
| E6 | PrivacyInfo.xcprivacy privacy manifest | ❌ | No `.xcprivacy` file anywhere in repo (verified), despite UserDefaults (required-reasons API) and health-data collection | **High** (blocking at submission) |
| E7 | App Privacy Details accuracy | ❌ (pending) | Not in repo. Apple's "Health" data type explicitly includes "any other user provided health or medical data" — pain/injury inputs count without HealthKit. Inaccurate labels = 2.3.1 metadata violation (removal / account termination for egregious cases) | **High** (at submission) |
| E8 | 5.1.3 health-data rules | ✅ | No health data in iCloud (Firestore used); no advertising/data-mining use of health data found; no HealthKit | — |
| E9 | TestFlight compliance now | 🟡 | Guidelines formally apply to external-tester builds ("should comply"; first build passes Beta App Review). Current gaps above are technically in scope today, enforced leniently | Low-Med |

### F. Content licensing & IP

| # | Compliance element | Status | Evidence | Risk |
|---|---|---|---|---|
| F1 | Third-party exercise content licensed correctly | ✅ (n/a) | Zero hits for Kemtai/WorkoutLabs/Physiopedia; all images AI-generated in-house (`scripts/` pipeline); exercise instruction text generated by Claude at runtime, not bundled from third parties | — |
| F2 | Trademark clearance for app name | ❌ (open) | No evidence of any check for "PT Helper" or "MVVC" (rebrand in progress). Interacts with B3 title-protection issue | Med (attorney) |

### G. Business structure & insurance

| # | Compliance element | Status | Evidence | Risk |
|---|---|---|---|---|
| G1 | Legal entity (LLC or similar) | ❓ | Not determinable from code; `STARTUP-PLAN.md:67` shows it was planned ("form an LLC…"). Interacts with E5 | **High** (open) |
| G2 | General liability / E&O insurance | ❓ | Not determinable from code | **High** (open) |

---

## 2. Priority Action Plan

Ranked by (risk severity × exposure to the 25–30 live users today). Items 1–6 affect people using the app *this week*; items 7–12 are pre-scale gates; items 13+ are App Store-submission gates.

### Tier 1 — Live safety & active misrepresentation (do first)

**1. Wire up the wellness emergency red-flag path (dead safety code).**
`WellnessAnalysisViewModel.worstSeverity` (`ViewModels/WellnessAnalysisViewModel.swift:18`) is computed but consumed by no view. Route `.emergency` to `EmergencyRedirectView` from the wellness analyzing flow, mirroring `Views/AnalyzingView.swift:160–169`, and render `.urgent` warnings in `WellnessResultView`. This is a small, contained change with the highest safety value in the audit.

**2. Strip licensed-title language from all server prompts and redeploy functions.**
In `functions/src/index.ts` (and `setup-form-agent.ts`, `setup-managed-agent.ts`): replace "PT rehabilitation specialist" / "PT wellness specialist" / "physiotherapy … specialist" / "physical therapy recovery analyst" with unlicensed framings ("exercise and movement guide", "strength & conditioning coach", "movement-form reviewer"); replace every "prescribe" with "include"/"select"; add a standing line to every prompt: "You are an AI assistant, not a licensed physical therapist or medical professional; never imply otherwise." Directly addresses CA AB 489 (effective now) and the broader 30-bill trend. Note: `setup-*` agent prompts require re-running agent setup, not just `firebase deploy` (see memory: create-new gotcha).

**3. Fix the `analysis` prompt audience statement.**
`functions/src/index.ts:270` — delete/replace "Regular people who may not be able to see a doctor right away" with e.g. "Regular people who want to understand their body better while they decide whether to see a professional." As written it frames the product as a substitute for unavailable medical care — the single most damaging sentence in the codebase for both liability and Anthropic-policy purposes.

**4. Make account deletion actually delete everything.**
Extend `Views/SettingsView.swift:458` to include `assessments`, `formAnalyses`, `streakData`, `analysisOutcomes`, `quotas`; delete Firestore `sessionLogs` index docs + Storage `sessionLogs/{uid}/*`; clear local `AnalysisResultStore`, on-disk session logs, and the workout checkpoint. Better: implement a `deleteAccount` Cloud Function (Admin SDK `recursiveDelete`) so client-side listing can't drift again, and call it from Settings. Until fixed, the app is making a false deletion promise to live users (FTC §5 exposure) and fails Apple 5.1.1(v).

**5. Correct the privacy policy to match reality (both copies).**
In `Models/LegalContent.swift` and `docs/PRIVACY_POLICY.md`: (a) fix the Anthropic retention claim — unless a ZDR agreement is actually in place, say data is processed by Anthropic subject to its API data-retention practices and never used for model training; note that recovery-insights agent sessions persist until deleted; (b) add Firebase/Google Analytics (behavioral events, pseudonymous user ID) and SendGrid (aggregate metrics only) to Third-Party Services; (c) disclose that diagnostic session logs (body regions, condition names) are uploaded for debugging, or stop uploading condition names (preferable: log condition *counts* in `InjuryAnalysisViewModel.swift:143–189`, mirroring the GA4 discipline); (d) re-sync `docs/` with `LegalContent.swift` and make one of them canonical.

**6. Close the ToS skip bypass and record acceptance server-side.**
Either remove `onSkip` from first-run onboarding (`Views/OnboardingView.swift:18–28`, `RootView.swift:145–147`) or interpose a minimal blocking accept-terms screen on skip. Write `{tosVersion, acceptedAt}` to `users/{uid}` (e.g. into the profile save at `OnboardingViewModel.swift:39–100`) so acceptance is provable and versioned; add a re-acceptance check when `tosVersion` changes.

### Tier 2 — Policy/regulatory gates before scaling past beta

**7. Decide and enforce a minimum age.**
The app already collects DOB (`BasicInfoStepView.swift:29`) and never checks it. Options: (a) **18+**: add a DOB gate + App Store 18+ restriction → exits Anthropic's minors policy entirely (recommended for simplicity unless serving teen athletes is a goal); (b) **13–17 allowed**: implement Anthropic's minors requirements (age verification, moderation, monitoring, minor-facing educational resources) and get COPPA/parental-consent counsel. Either way, enforce the ToS's own "13+" line at onboarding today (one `Calendar.dateComponents` check + blocking screen). Also ask every current tester's age (§4) — if any minor is testing now, this jumps to Tier 1.

**8. Resolve the Anthropic High-Risk classification (with counsel, and possibly Anthropic).**
The injury differential pipeline plausibly is "medical diagnosis… or other medical guidance" → requires qualified-professional review before dissemination, which the product does not have. Engineering options to bring the product toward the wellness carve-out: reframe outputs away from named-condition differentials toward educational "possible explanations + when to see someone" content; or add an actual human-review tier (e.g., a licensed PT reviews plans async before activation). Which path is viable is a product + legal decision; flag prominently, don't guess. Interim mitigations already in place (AI disclosure everywhere, disclaimers, red-flag routing) should be preserved and the AUP's session-start disclosure kept in mind (one fetch of the AUP showed "disclosure… at a minimum at the beginning of each session" — unverified; check the live page).

**9. Add friction after urgent red flags.**
`Views/AnalysisResultView.swift:437–444`: replace one-tap "Build Rehab Plan Anyway" with a typed/checked acknowledgement modal (reuse `SeriousWarningModal` pattern) stating the specific detected risk, and log the acknowledgement server-side with timestamp.

**10. Gate the wellness flow behind the disclaimer screen.**
Reuse `DisclaimerManager` (`Views/BodyMap3DView.swift:762–769` pattern) before the first wellness analysis in `WellnessGoalPickerView`/wellness submission path.

**11. Pre-submission red-flag screening.**
Run `MedicalRedFlagDetector` client-side on assessment inputs *before* the first API call in `InjuryAnalyzer.analyze()` (`Models/InjuryAnalyzer.swift:52`) and route `.emergency` straight to `EmergencyRedirectView` — the user gets the safety screen faster and their emergency-pattern data never leaves the device.

**12. Washington MHMDA posture.**
First ask testers' states (§4). If any WA resident (or before public launch, since you can't geo-limit an App Store release practically): create a separate "Consumer Health Data Privacy Policy," link it separately wherever the privacy policy appears; add an opt-in consent screen for health-data collection (distinct from ToS acceptance — the current checkbox bundles everything); add a separate consent for any "sharing"; make deletion complete (item 4) and honor 45-day timelines including backups. A single combined "I agree" does not satisfy MHMDA's opt-in structure.

**13. Fix the Dashboard's clinical presentation.**
`Views/Dashboard/DashDifferentialsTable.swift:9` — rename "Differential Analysis" (e.g., "Possible Explanations") and replace raw percentages (`:57`, and `DashConfidenceChart.swift:25`) with the main flow's qualitative match-strength labels + the 85%-cap explainer.

**14. Soften or substantiate "clinical protocols" marketing copy.**
`Views/IntroCarouselView.swift:170, 263` — either maintain a citable evidence file mapping plan logic to published guidelines (the repo's knowledge graph + APTA-sourced red-flag lists are a start) or reword to "evidence-informed exercise guidance." Relevant to Apple 1.4.1's accuracy-claims "must."

### Tier 3 — App Store submission gates (before leaving TestFlight)

**15. Add `PrivacyInfo.xcprivacy`** declaring collected data types (Health, identifiers, usage data), purposes, no tracking, and required-reasons API usage (UserDefaults). Blocking at submission; trivial to add now.

**16. App Store Connect package (not in repo — do at submission):** complete the age-rating questionnaire honestly (AI-generated medical/treatment content counts toward frequency → likely "frequent" → 16+); declare regulated-medical-device status (likely "No," if accurate after items 2–3 keep the product non-diagnostic — confirm with counsel); fill App Privacy Details matching the corrected privacy policy (pain/injury data = "Health" even without HealthKit); reconcile the ToS 13+ line with the final age-rating and age-gate decision (item 7).

**17. Entity + account migration:** form the LLC (G1, already planned in `STARTUP-PLAN.md`), get a free D-U-N-S number, and migrate the Apple Developer account individual → organization (same $99/yr; Apple verifies entity; takes weeks — start early). Addresses 5.1.1(ix) "should be submitted by a legal entity" for healthcare.

**18. Security hardening carried over from the 2026-06-10 security review** (open items that also matter legally): Firebase App Check on all endpoints, GCP API-key restrictions.

---

## 3. Attorney-Required Flags

These cannot be resolved by engineering. Recommend one consultation covering all of them (health-tech / digital-health counsel, not generic startup counsel):

1. **Unauthorized practice of physical therapy + title protection.** Whether the app's function (AI differential analysis + condition-keyed exercise plans) falls within any state's statutory definition of PT practice, and whether the name "PT Helper" violates title-protection statutes (e.g., CA BPC §2630/§2633 — misdemeanor; NY Educ. Law §6512 — class E felony). No app precedent found either way; boards act on complaints. The rename decision (MVVC?) should be made *with* this analysis.
2. **CA AB 489 exposure** (AI implying licensed healing-arts care; effective 2026-01-01, per-use violations, PT Board enforcement) — review prompts/UI copy after the Tier-1 fixes, and the app name.
3. **Waiver/assumption-of-risk enforceability.** Whether a standalone waiver should exist, whether the ToS liability cap + indemnification clause (`LegalContent.swift:180–190`) holds up for personal-injury claims under California law (many states void personal-injury liability waivers in consumer adhesion contracts), and whether the `SeriousWarningModal` acknowledgement has evidentiary value as implemented (local-only, untimestamped).
4. **Anthropic AUP classification** of the injury-analysis feature (high-risk "medical guidance" vs. "wellness advice") and what a compliant product posture looks like — possibly a direct conversation with Anthropic; account-level enforcement risk lands on the developer.
5. **Minors strategy**: COPPA (under-13), Anthropic minors policy (under-18), parental consent, and whether coaching relationships with teen athletes change the analysis.
6. **California CMIA §56.06** — whether the app is a deemed "provider of health care" (no size threshold) and what confidentiality/breach duties follow.
7. **Washington MHMDA applicability** and the compliant consent architecture (item 12) if any WA users exist or public launch proceeds.
8. **Trademark clearance** for "PT Helper" and "MVVC" before the rebrand ships.
9. **Entity formation & insurance** (LLC structure, general liability + E&O/tech E&O for an AI health product).

---

## 4. Open Questions for Noy

Facts the audit could not determine from the repo — answers change the priority ordering above:

1. **Tester ages.** Are any of the ~25–30 beta testers under 18 — specifically, are any of your private training clients or the high-school athletes you coach on the beta? (If yes: item 7 becomes Tier 1, and the Anthropic minors policy applies *today*.)
2. **Tester locations.** Any Washington residents? California residents? (WA → item 12 activates now; CA → AB 489/CMIA analysis is live rather than prospective.)
3. **Business entity.** Has the LLC from `STARTUP-PLAN.md` been formed? Is the app (and the Apple/Firebase/Anthropic accounts) held personally or by the entity?
4. **Insurance.** Any general liability or E&O/tech E&O policy in place?
5. **Apple Developer account type.** Individual or Organization? (Determines the E5/17 migration timeline.)
6. **Anthropic account arrangements.** Is there a ZDR agreement or any special data arrangement with Anthropic? (Determines whether the privacy policy's retention claim is fixable by wording or by contract.)
7. **App Store Connect current state.** Chosen category, age-rating answers, and privacy-label entries (not in repo) — needed to verify E2/E3/E7.
8. **Launch intent.** Target date for public App Store release, and regions (EEA/UK add the medical-device declaration regardless; EU users would add GDPR, which this audit did not scope).
9. **Name decision.** Is "MVVC" the final shipping name, and has anyone run even a knockout trademark search on it?
10. **Professional-relationship overlay.** Are you personally giving training/rehab guidance to any testers alongside the app? (Blends product liability with personal professional liability — worth raising with counsel.)

---

## Appendix: Source verification notes

- External sources verified live on 2026-07-05: Anthropic Usage Policy (eff. 2025-09-15), Consumer Terms (eff. 2025-10-08), Commercial Terms (eff. 2025-06-17), minors guidelines (upd. 2026-03-16); Apple App Review Guidelines, regulated-medical-device requirement (eff. 2026-03-26; existing apps have until early 2027), age-rating system (Jan 31, 2026 deadline), account-deletion requirement; RCW 19.373 (WA MHMDA); FTC HBNR final rule (eff. 2024-07-29); CA AB 489 (eff. 2026-01-01), AB 3030 (inapplicable — facilities only), SB 1223, CMIA §56.06; IL WOPR (mental health only), NV AB 406 (mental health only), UT HB 452/SB 226/332, TX HB 149 (no general impersonation ban), CO AI Act (delayed to 2027-01-01 and narrowed), NY GBL Art. 47 (companion AI).
- **Unverified items** (re-check before relying): the AUP sentence "disclosure… at the beginning of each session" (appeared in one of three fetches); exact 2026 FTC per-violation penalty figure; final status of NH SB 640 / NJ A5603; any merits ruling in the first MHMDA class actions.
- Codebase claims: all High-risk file:line citations in this document were independently re-verified in the working tree on 2026-07-05.
