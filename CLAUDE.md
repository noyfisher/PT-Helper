# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Test Commands

### iOS App
```bash
# Build
xcodebuild build -project ios/PT-Helper/COIL.xcodeproj \
  -scheme COIL -destination 'platform=iOS Simulator,name=iPhone 16'

# Run all unit tests (default: UnitPlan)
xcodebuild test -project ios/PT-Helper/COIL.xcodeproj \
  -scheme COIL -destination 'platform=iOS Simulator,name=iPhone 16'

# Run smoke tests only (11 key tests, 60s timeout)
xcodebuild test -project ios/PT-Helper/COIL.xcodeproj \
  -scheme COIL -testPlan SmokePlan -destination 'platform=iOS Simulator,name=iPhone 16'

# Run full suite including collision tests (300s timeout)
xcodebuild test -project ios/PT-Helper/COIL.xcodeproj \
  -scheme COIL -testPlan FullPlan -destination 'platform=iOS Simulator,name=iPhone 16'

# Run pre-release suite: all unit + UI tests with code coverage (600s timeout)
xcodebuild test -project ios/PT-Helper/COIL.xcodeproj \
  -scheme COIL -testPlan PreReleasePlan -destination 'platform=iOS Simulator,name=iPhone 16'

# Run a single test class
xcodebuild test -project ios/PT-Helper/COIL.xcodeproj \
  -scheme COIL -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:COILTests/UserProfileTests

# Run a single test method
xcodebuild test -project ios/PT-Helper/COIL.xcodeproj \
  -scheme COIL -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:COILTests/UserProfileTests/testDefaultUserProfile
```

### Cloud Functions (Firebase)
```bash
cd functions
npm install
npm run build        # Compile TypeScript → lib/
npm run serve        # Local emulator
npm run lint         # ESLint
firebase deploy --only functions
```

## Engineering Protocol (required)

Follow these 5 rules on every code task. They minimize hallucinations and regressions in a codebase where working features must not break.

**R1 — Grep before assert.** Before citing any named symbol, file, or line, grep for it this turn. Before editing, produce a blast-radius report (callers/usages found). Always verify before editing: signature/behavior/schema changes, shared types, renames/removals, files in `Services/`, `Models/`, `ViewModels/`, `functions/src/`, `Views/Components/`, `DesignSystem.swift`, app entry/navigation files, AI prompts, infra/config (`firebase.json`, `firestore.rules`, `.entitlements`, etc.), cross-system data files (`exercise_list.json`, `exercise_image_mapping.json`, metadata JSON), production-data-mutating scripts. Skip for single-file styling/copy/log/local-var tweaks and net-new code.

**R2 — Blast-radius-gated planning.** R1's output decides plan mode. Low → proceed. Medium → 1-2 sentence plan in chat. High (5+ callers, shared type/prompt/schema change, deploy-impacting config, data mutation) → written plan, wait for approval. Escape hatch: user says "just do it" → drop to medium. **Plan audit:** whenever R2 produces a written plan, ALWAYS ask "Run plan-audit? (yes / skip)" before ExitPlanMode. Never assume — the prompt prevents forgetting. If yes → invoke `plan-audit` skill; if NEEDS REVISION, surface findings and ask revise-or-proceed.

**R3 — Build-gated "done."** No completion claim without an artifact: `xcodebuild build` + tests for Swift, simulator run with logs for UI, `npm run build` for Cloud Functions, actual script run for Python. If verification isn't possible, say "written but unverified — you need to X to confirm."

**R4 — Memory is assumed until re-read.** Anything from auto-memory is flagged "assumed." Before acting on a memory, re-read current state of the referenced file.

**R5 — Anti-momentum checkpoint.** On unexpected error, mental-model contradiction, or second failed attempt at the same approach → stop and re-read actual code. No "slightly different version of the same idea."

Full rules: `~/.claude/projects/-Users-noyfisher-IOS-Projects-PT-Helper-Agent-v1/memory/feedback_engineering_protocol.md`

## Parallel Sessions

Multiple Claude Code sessions may run against this repo concurrently. Rules:

- **One worktree per concurrent session.** Start parallel sessions with `claude -w <name>` or ask a running session to "work in a worktree". The main checkout shares one git index — concurrent sessions there can clobber each other's edits, and `git add .`/`commit -a` sweeps up another session's work-in-progress.
- **Same-checkout parallelism** only for short tasks in strictly disjoint areas (e.g. `functions/` vs `ios/`); stage files explicitly, never in bulk.
- **Simulator**: one device per session, targeted by UDID — two runs on one booted sim fight over install/launch.
- **Firebase deploys**: serialize — never `firebase deploy` from two sessions at once (single pt-helper-dev project).
- **Image pipeline** (`scripts/`): main checkout only, one owner session at a time. `scripts/output/` **is tracked in git** and does follow into worktrees — the one-owner rule is about the shared API quotas (~250 image generations/day) and the fact that `rebuild_image_mapping.py` rewrites `exercise_image_mapping.json`, which both the iOS bundle and the functions catalog build from.
- **Untracked essentials** (`functions/.env`, `scripts/archive/pilots/animation-pilot/.env`) are copied into new worktrees via `.worktreeinclude` — add new gitignored-but-required files there.
- **Merges**: small branches, rebase on `main` often, FullPlan before merge.

Full recipes (starting sessions, simulator assignment table, cross-session messaging, lead+agents pattern): `ios/PT-Helper/docs/parallel-sessions.md`.

## Architecture

### MVVM + Services Pattern
The iOS app (`ios/PT-Helper/COIL/`) uses MVVM with a singleton service layer:

- **Models/** (~22 files) — Codable structs and analyzers:
  - Core: `UserProfile`, `PainAssessment`, `RehabPlan`, `BodyRegion`, `BodyZone`, `BodyMapConstants`
  - Analysis: `InjuryAnalyzer`, `AssessmentSnapshot`
  - Wellness: `WellnessAnalyzer`, `WellnessAnalysisResult`, `WellnessAssessment`
  - Recovery: `RecoveryInsight`, `AdaptiveProgressionAnalyzer`, `ProgressionRule`
  - Workout: `WorkoutSession`, `Achievement`
  - Form: `FormAnalysis`
  - Outcome: `OutcomeFeedback`
  - Other: `Note`, `SessionEvent`, `LegalContent`
- **ViewModels/** (~14 files) — `@MainActor @ObservableObject` classes that own business logic and publish UI state
  - `InjuryAnalysisViewModel`, `RehabPlanViewModel`, `GuidedWorkoutViewModel`, `SavedPlansViewModel`, `WorkoutViewModel`
  - `WellnessAnalysisViewModel`, `WellnessPlanViewModel`, `RecoveryInsightsViewModel`
  - `FormAnalysisViewModel`, `ExerciseSwapViewModel`, `ReAssessmentViewModel`
  - `BodyMapViewModel`, `OnboardingViewModel`, `NotesViewModel`
- **Views/** (~67 files total: ~44 top-level + ~16 Components + ~6 OnboardingSteps + 1 Debug) — SwiftUI views using `@ObservedObject`/`@StateObject`. Navigation via `NavigationStack`
  - `Components/` — Reusable UI (exercise image, phase stepper, video recorder, etc.)
  - `OnboardingSteps/` — Multi-step health profile collection (basic info, injury/surgical/medical history, activity level, review)
- **Services/** (~35 files) — Singletons (`static let shared`) for API, persistence, validation, logging
  - API: `ClaudeAPIService`, `APIConfig`
  - Validation: `ResponseValidationPipeline`, `BiomechanicalRuleEngine`, `FormFeedbackValidationPipeline`, `KnowledgeGraphService`, `CrossModelVerificationService`, `DataQualityScorer`, `InputSanitizer`, `ShadowModeJSONParser`
  - Pose: `PoseDetectionService`, `PoseAnalysisEngine`
  - Data: `UserProfileService`, `ExerciseImageService`, `BodyModelCache`, `AnalysisResultStore`, `OutcomeRecorder`
  - Logging: `SessionLogger`, `AppLogger`, `AnalyticsService`
  - Safety: `SeriousWarningAcknowledgements`
  - Infra: `NetworkMonitor`, `NotificationService`, `StreakService`, `PDFExportService`, `HistoryRelevanceFilter`, `TestDataSeeder`

### AI Request Types
All AI calls go through `ClaudeAPIService` → Firebase Cloud Function proxy (`functions/src/index.ts`) → Claude API. System prompts and model config live server-side. The `AIRequestType` enum in `ClaudeAPIService.swift` has 9 cases:

| Request Type | Purpose |
|---|---|
| `analysis` | Primary injury differential diagnosis (top 5 conditions) |
| `analysis_verify` | Devil's advocate verification (refine to top 3) |
| `rehab_plan` | Structured exercise program generation |
| `exercise_substitute` | Mid-workout or plan-view exercise swap |
| `recovery_insights` | Weekly recovery digest (via Managed Agents) |
| `form_analysis` | Pose-based exercise form feedback |
| `wellness_analysis` | Wellness goal assessment (proactive health) |
| `wellness_verify` | Wellness recommendation verification |
| `wellness_plan` | Wellness exercise + habit plan generation |

Note: `nightly_report` exists server-side only as a scheduled Cloud Function — not called from iOS.

### Two-Call AI Analysis Pipeline
The core injury analysis uses a two-call pipeline in `InjuryAnalyzer.swift`:

1. **Primary call** (`analysis`) — Sends user profile + pain assessments → returns top 5 conditions
2. **Verification call** (`analysis_verify`) — Devil's advocate review → refines to top 3 conditions
3. **Graceful degradation** — If call 2 fails, falls back to call 1 results
4. **Validation** — `ResponseValidationPipeline.validateAnalysis()` runs 6 steps:
   1. Content validation (structure, required fields)
   2. Symptom red flag detection
   3. Condition red flag detection
   4. Anatomical relevance check (conditions vs. assessed body regions)
   5. Confidence calibration (capped at 85% max)
   6. Condition deduplication

The wellness analysis follows the same two-call pattern (`wellness_analysis` + `wellness_verify`) in `WellnessAnalyzer.swift`.

### Rehab Plan Validation
`ResponseValidationPipeline.validateRehabPlan()` runs 9 steps:
1. Hardcoded contraindication check (exercise vs. condition)
2. Knowledge graph validation (`KnowledgeGraphService` — deterministic verification)
3. Parameter range validation (sets, reps, rest within safe bounds)
4. Exercise count check
5. Plan duration check (1–24 weeks)
6. Age-based safety (advanced exercises flagged for age ≥ 65)
7. Medical condition safety (osteoporosis → no impact; cardiac → heart rate monitoring)
8. Medication-aware safety (blood thinners → fall risk; corticosteroids → tendon weakness; beta blockers → RPE guidance)
9. Post-surgical restriction warnings (active recovery flagged)

### History Relevance Filtering
`HistoryRelevanceFilter` classifies user's surgical/injury history before including it in AI prompts:
- **directlyRelevant** — Same body zone, or "still recovering"/"has restrictions"
- **possiblyRelevant** — Kinetic chain match (e.g., hip affecting knee) or <5 years old
- **backgroundOnly** — Old, unrelated history (included as context only)

### Wellness Goals System
`AssessmentGatewayView` (presented from the floating "+") provides a dual gateway: pain analysis or wellness goals. The wellness flow:
1. User selects wellness goals in `WellnessGoalPickerView` (posture, sleep, mobility, strength, pain management)
2. `WellnessAnalysisViewModel` runs a two-call analysis (`wellness_analysis` + `wellness_verify`)
3. `WellnessPlanViewModel` generates an exercise + habit plan (`wellness_plan`)
4. Plans include daily habits and micro-practices alongside exercises

### Recovery Insights via Managed Agents
`RecoveryInsightsViewModel` orchestrates multi-step recovery analysis:
1. Calls `agentInsights` Cloud Function → creates ephemeral Managed Agent session
2. Agent analyzes 14-day workout data using `submit_recovery_insights` tool
3. Returns `RecoveryInsightResult`: pain trends, adherence scoring, key wins, focus areas, personalized recommendations
4. Server code in `functions/src/managed-agent.ts`

### Form Analysis
Video-based exercise form feedback pipeline:
1. `VideoRecorderView` captures exercise video
2. `PoseDetectionService` (MLKit) extracts joint positions on-device
3. `PoseAnalysisEngine` computes joint angles, per-rep symmetry
4. `BiomechanicalRuleEngine` applies exercise-specific form rules (knee valgus, spinal alignment, etc.)
5. `FormFeedbackValidationPipeline` validates AI form feedback for safety
6. Results displayed in `FormAnalysisView`

### Adaptive Progressions
`AdaptiveProgressionAnalyzer` with `ProgressionRule` scales exercise difficulty based on workout performance. `AdaptiveProgressionBannerView` shows progression recommendations in the plan view.

### Exercise Substitution
Users can swap exercises mid-workout or from plan view via `ExerciseSwapSheet`. Uses `exercise_substitute` request type to get AI-suggested alternatives matching the same difficulty and rehab purpose.

### RealityKit 3D Body Map
`BodyMap3DView` uses RealityKit for interactive body region selection. Invisible proxy entities handle occluded regions (lower back, back of head, etc.). Collision tests in `BodyMapCollisionTests` (excluded from UnitPlan, included in FullPlan). First-time users see a coach mark overlay (persisted via `@AppStorage("hasSeenBodyMapCoach")`).

### Guided Workout Checkpointing
`GuidedWorkoutViewModel` saves workout state to `UserDefaults` (`GuidedWorkoutCheckpoint`) on every set completion and exercise skip. On relaunch, `GuidedWorkoutView` detects incomplete sessions and offers a "Resume Workout?" prompt. Checkpoints expire after 24 hours. The "End" button shows a confirmation dialog before ending early.

### Progressive Learning
`GuidedWorkoutViewModel` tracks exercise familiarity (new/learning/familiar/mastered). New exercises auto-expand instructions with a 3-phase stepper (`ExercisePhaseStepperView`: Start Position → Movement → Return Position). Familiar exercises show collapsed instructions.

### Rehab Plan Preferences
Before generating a rehab plan, `AnalysisResultView` shows a preferences sheet where users select equipment (none/bands/dumbbells/gym), session length (15/30/45 min), and difficulty (gentle/moderate/challenging). These are stored in `RehabPlanPreferences` on `RehabPlanViewModel` and included in the AI prompt.

### Pain Assessment Collapsible Form
`PainDetailView` splits fields into essential (always visible: pain type, intensity, duration, frequency, onset, aggravating/relieving factors) and optional (collapsed by default: description, treatment history, notes). The "Apply to All Regions & Analyze" button is shown on every region when multiple are selected.

### Cloud Functions
Firebase Cloud Functions in `functions/src/`:

| Function | Type | Purpose |
|---|---|---|
| `onBudgetAlert` | Pub/Sub | Hard billing shutoff on budget overspend |
| `claudeProxy` | HTTP | Routes AI requests to Claude API with rate limiting (20 req/min/user) |
| `crossVerify` | HTTP | Cross-model verification for rehab plans |
| `agentInsights` | HTTP | Managed Agent for recovery insights |
| `createVirtualUserToken` | HTTP | Virtual user token for testing |
| `generateExerciseImage` | HTTP | On-demand exercise image generation |
| `aggregateDailyMetrics` | Scheduled (daily 01:00 UTC) | Daily analytics aggregation |
| `sendNightlyReport` | Scheduled (07:00 Asia/Jerusalem) | Nightly product analytics digest via SendGrid |

Supporting modules:
- `managed-agent.ts` — Managed Agents API client, ephemeral session handling, `submit_recovery_insights` tool
- `scripts/setup-managed-agent.ts` — One-time agent creation (`npm run setup-agent`)
- `firestore-queries.ts` — Recovery data queries (14-day window)

### Firestore Data Structure
- `users/{uid}/profile/health` — UserProfile document
- `users/{uid}/rehabPlans` — Collection of RehabPlan documents
- `users/{uid}/workoutSessions` — Workout session logs (date, duration, pain level, exercises)
- `users/{uid}/assessments` — Pain assessment snapshots
- `users/{uid}/notes` — User observation notes
- `users/{uid}/wellnessPlans` — Wellness exercise + habit plans
- `users/{uid}/streakData/current` — Workout streak tracking
- `missingExerciseImages` — Public collection for logging missing images

### Navigation & Shared State
`MainTabView` is the primary navigation shell with 4 tabs plus a floating "+"; `TabSelection.swift` hosts the shared `TabSelection` class and `AssessmentRoute` enum:
- **Tab 0: Home** — weekly date strip, today's program + preventative tasks
- **Tab 1: My Plan** — active plan hero card + saved plans list
- **Tab 2: Progress** — charts, recovery insights, settings, session history
- **Tab 3: Profile** — profile summary + edit (`OnboardingEditView`)
- **Floating "+"** — sets `TabSelection.assessmentRequest = .gateway`, presenting `AssessmentGatewayView` in a full-screen cover (dual gateway: pain analysis or wellness goals)

`MainTabView` injects shared state via `@EnvironmentObject`:
- `TabSelection` — Cross-tab navigation + assessment routing
- `SavedPlansViewModel` — Rehab plans (real-time Firestore listener)
- `WorkoutViewModel` — Workout session tracking
- `NetworkMonitor` — Connectivity status
- `RecoveryInsightsViewModel` — Recovery insights state
- `AnalysisResultStore` — Persisted analysis results

### UI Testing Infrastructure
The app supports UI testing via launch arguments handled by `TestDataSeeder`:
- `--uitesting` — Master flag; bypasses Firebase Auth in `RootView`
- `--skip-onboarding` — Injects mock profile, skips to main app
- `--seed-mock-data` — Populates plans, sessions, analysis result, streak data
- `--simulate-offline` — Forces `NetworkMonitor.isConnected = false`
- `--clear-coach-mark` — Resets body map coach mark
- `--clear-workout-checkpoint` — Removes any saved workout checkpoint
- `--prefill-weight` — Pre-populates weight in profile
- `--show-intro` — Forces the intro carousel to display on launch

Accessibility identifiers follow `screenName.elementName` convention (e.g., `workout.completeSetButton`).

### Pre-Release Process
See `ios/PT-Helper/docs/manual-qa-checklist.md` for the full manual QA checklist.

Test plans: SmokePlan (11 tests), UnitPlan (all unit), FullPlan (all + collision + UI), PreReleasePlan (all + UI + coverage). FullPlan and PreReleasePlan run identical test targets — they intentionally aren't merged: FullPlan is the nightly gate (no coverage, 300s timeout) and PreReleasePlan is the release gate (same tests + code coverage, 600s timeout).

**What runs automatically** (`.github/workflows/`):

| Trigger | Plan | Blocking |
|---|---|---|
| push/PR to `main` | UnitPlan (all unit tests) | Yes |
| push/PR to `main` | Cloud Functions: lint, build, jest, `npm audit` | Yes |
| push/PR to `main` | Firestore rules + integration tests (emulator) | Yes |
| nightly 09:00 UTC | FullPlan on iPhone 16 Pro + iPhone SE | No — triage next morning |
| `workflow_dispatch` (before TestFlight) | PreReleasePlan + coverage artifact | Yes, gates `beta` |

SmokePlan is no longer a CI gate — it was an 11-test allow-list guarding a ~1,140-method suite, so almost nothing was actually enforced. It's kept only for fast local iteration. Don't reintroduce it as the PR gate.

## Code Conventions

### Design System
Always use tokens from `DesignSystem.swift` — never hardcode colors, spacing, or typography:
- `AppSpacing.xs/sm/md/lg/xl/xxl/xxxl` (4–40pt)
- `AppColors.accent/success/warning/danger/cardBackground`
- `AppCorners.small/medium/card/large/xl/pill`
- `AppFonts.heroTitle/sectionTitle/cardTitle/statNumber`
- `AppAnimations.springy/smooth/bouncy`

Use `CardSection` for form sections, `.cardStyle()` for card elevation, `ChipButton` for selectable tags.

### Adding Files
Xcode 16 uses `PBXFileSystemSynchronizedRootGroup` — new Swift files are auto-discovered. No manual pbxproj edits needed.

### Testing Patterns
- Test fixtures in `TestFixtures.swift` — use factory methods (`makeProfile()`, `makeAssessment()`, `makePlan()`, etc.)
- Mock API via `MockClaudeAPIService` (conforms to `ClaudeAPIServiceProtocol`)
- ViewModels require `@MainActor` in tests
- Test naming: `test<What>_<Condition>_<Expected>` (e.g., `testClassifySurgery_sameRegion_recentWithRestrictions`)

### New Request Type (AI Feature)
1. Add system prompt to `SYSTEM_PROMPTS` in `functions/src/index.ts`
2. Add model config to `MODEL_CONFIG` in the same file
3. Add `AIRequestType` case in `ClaudeAPIService.swift`
4. Add response parsing in the appropriate ViewModel

### Session Logging
Use `.trackScreen("ScreenName")` modifier on new views. `SessionLogger` auto-tracks navigation, API calls, errors, and crash recovery.

## Exercise Image Pipeline
1364 AI-generated exercise illustrations (start + end frame pairs) in `scripts/output/`. Primary generation uses **Nano Banana Pro** (`gemini-3-pro-image-preview`); QA uses Gemini 2.5 Flash vision. FLUX 2 Pro (BFL API) is legacy and only retained for the on-demand `generateExerciseImage` Cloud Function (migration to Nano Banana Pro is an open item).

To add a new exercise:
1. Add metadata to `scripts/output/all_exercises_metadata.json` (canonical; `scripts/exercise_list.json` is the legacy curated 190, still read by the FLUX-era and QA scripts)
2. Generate: `python scripts/generate_missing_images.py` (Nano Banana Pro + inline QA)
3. For failures: `python scripts/regen_with_auto_prompts.py` (Gemini observation → targeted anti-error prompt → regen)
4. End frames: `python scripts/generate_end_frames_nb.py` conditions NB Pro on the passing start image; `python scripts/qa_consistency.py` scores the pair; `python scripts/regen_end_frames_with_corrections.py` fixes what fails
5. Rebuild mapping: `python scripts/rebuild_image_mapping.py` (rebuilds the mapping JSON and copies it to iOS Resources; PNGs are uploaded to Firebase Storage with `scripts/upload_to_firebase.sh`)

Image resolution in `ExerciseImageService.swift` uses 8-layer fuzzy matching: exact name → normalized → alias → prefix → suffix → plural toggle → synonym expansion → stockpile alias fallback.
