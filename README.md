# COIL

An iOS app that uses AI to deliver personalized physical therapy guidance — from injury analysis through guided rehab workouts.

Users tap where it hurts on a 3D body model, answer targeted questions, and receive a PT-style analysis with a structured exercise plan they can follow with built-in workout guidance.

> The app was formerly called **PT Helper**. The old name survives in two places that are expensive to change: the `ios/PT-Helper/` directory path and the `pt-helper-dev` Firebase project id. Everything else is COIL.

## Start here

Read in this order:

| Doc | What it's for |
|---|---|
| `README.md` | This overview — what the app does and how the pieces fit together |
| `CLAUDE.md` | Engineering rules and the architecture reference (the deepest single doc) |
| `CONTRIBUTING.md` | Setup, build and test commands, conventions, git workflow |
| `ios/LAYOUT.md` | The iOS file map — every model, view model, view, service and test |
| `functions/README.md` | The Cloud Functions backend: deployed functions, source map, deploy |
| `scripts/README.md` | The exercise-image pipeline |
| `docs/` | Product brief, UX flows, data models, API, safety, and the legal texts |
| `docs/archive/` | Historical, point-in-time records — not maintained, not a source of truth |
| `ios/PT-Helper/docs/tester-welcome-note.md` | What TestFlight testers are told |

## Features

- **3D Body Map** — Interactive RealityKit body model with tap-to-select pain regions and invisible proxy entities for occluded areas
- **AI Injury Analysis** — Claude-powered assessment that considers pain characteristics, medical history, and kinetic chain relationships
- **Wellness Goals** — Proactive wellness pathway for posture, sleep, mobility, strength, and pain management with AI-generated exercise + habit plans
- **Smart Health History** — Relevance-filtered surgical/injury/medication history using anatomical proximity and temporal rules
- **Rehab Plans** — Structured exercise programs with phases, progressions, and weekly schedules
- **Guided Workouts** — Step-by-step exercise sessions with sticky action bar, 3-phase instruction stepper, progressive learning, timers, and rep counters
- **Exercise Form Analysis** — Video-based form feedback using MLKit pose detection, biomechanical rules, and AI analysis
- **Exercise Substitution** — AI-powered exercise swap from plan view or mid-workout
- **Recovery Insights** — Weekly AI-generated recovery digest via Claude Managed Agents with pain trends, adherence scoring, and recommendations
- **Adaptive Progressions** — Rules-based difficulty scaling based on workout performance
- **Exercise Images** — ~1,360 AI-generated exercise illustrations (start + end frames) served on demand from Firebase Storage
- **Progress Tracking** — Workout streaks, achievements, re-assessment comparisons, and progress charts
- **Session Logging** — Detailed logging of analysis and workout sessions for debugging and analytics
- **Safety Pipeline** — Analysis validation (6 steps) and rehab plan validation (9 steps) including medication-aware checks and red-flag detection
- **PDF Export** — Export rehab plans as formatted PDFs

## Architecture

```
┌─────────────────────┐
│   iOS App (SwiftUI)  │
│                      │
│  Views → ViewModels  │
│  Models → Services   │
└──────────┬───────────┘
           │ HTTPS
┌──────────▼───────────┐
│  Firebase Cloud Fns   │
│  (Node.js 22)        │
│  • Rate limiting      │
│  • System prompts     │
│  • Prompt assembly    │
│  • Managed Agents     │
└──────────┬───────────┘
           │
┌──────────▼───────────┐     ┌──────────────────┐
│   Claude API          │     │  Firestore        │
│   (Anthropic)         │     │  • User profiles  │
│   • Analysis (9 types)│     │  • Assessments    │
│   • Managed Agents    │     │  • Rehab plans    │
└───────────────────────┘     │  • Workouts       │
                              │  • Wellness plans  │
                              └──────────────────┘
```

The iOS client never talks to a model provider directly and never holds a provider API key — every AI call goes through the Cloud Functions proxy, which owns the system prompts, rate limiting, spend ceilings, and response-schema validation.

## Project Structure

```
├── ios/
│   ├── LAYOUT.md                   # Full iOS file map
│   └── PT-Helper/
│       ├── COIL/                   # The app target
│       │   ├── COILApp.swift       # @main entry point (Firebase init, scene phase)
│       │   ├── RootView.swift      # Auth / legal / onboarding gate
│       │   ├── DesignSystem.swift  # Colors, spacing, typography tokens
│       │   ├── Models/             # Codable models + analyzers
│       │   ├── ViewModels/         # @MainActor ObservableObjects
│       │   ├── Views/
│       │   │   ├── MainTabView.swift   # 4-tab shell + floating "+"
│       │   │   ├── TabSelection.swift  # Shared TabSelection + AssessmentRoute
│       │   │   ├── Components/         # Reusable UI
│       │   │   └── OnboardingSteps/    # Profile wizard steps
│       │   ├── Services/           # API, validation, pose, logging, persistence
│       │   └── Resources/          # exercise_image_mapping.json, knowledge graphs,
│       │                           #   3D body model, fonts — no exercise images
│       ├── COILTests/              # Unit tests
│       ├── COILUITests/            # XCUI tests
│       ├── docs/                   # Living iOS docs (QA checklist, parallel sessions,
│       │                           #   security review, tester note)
│       └── *.xctestplan            # UnitPlan / SmokePlan / FullPlan / PreReleasePlan
├── functions/                      # Firebase Cloud Functions (TypeScript, Node 22)
│   ├── README.md
│   ├── src/
│   │   ├── index.ts                # HTTP + scheduled handlers, rate limit, quota, spend cap
│   │   ├── prompts.ts              # SYSTEM_PROMPTS + MODEL_CONFIG (server-side prompts)
│   │   ├── response-schemas.ts     # Zod schema per AI request type
│   │   ├── managed-agent.ts        # Managed Agents client (recovery insights)
│   │   ├── form-agent.ts           # Managed Agents client (cross-session form analysis)
│   │   ├── image-generation.ts     # On-demand exercise image generation
│   │   └── billing-shutoff.ts      # Budget-alert billing shutoff
│   └── scripts/                    # One-off ts-node scripts (never deployed)
├── contracts/                      # Cross-stack response-schema contracts
├── scripts/                        # Exercise image pipeline (Python)
│   ├── README.md
│   ├── archive/                    # Retired and one-off scripts
│   └── output/                     # Master illustrations + mapping — tracked in git
├── docs/                           # Brief, UX flows, safety, API, data models, legal texts
│   └── archive/                    # Historical records (see docs/archive/README.md)
├── firebase.json                   # Firebase deployment config
└── firestore.rules                 # Security rules
```

## Getting Started

### Prerequisites

- Xcode 16+
- iOS 18.2 deployment target
- Node.js 22 (for Cloud Functions)
- Firebase CLI (`npm install -g firebase-tools`)
- A Firebase project with Firestore and Authentication enabled

Full setup, conventions, and the git workflow are in `CONTRIBUTING.md`.

### Setup

1. **Clone and open in Xcode**
   ```bash
   git clone <repo-url>
   open ios/PT-Helper/COIL.xcodeproj
   ```

2. **Firebase configuration**
   - Create a Firebase project at [console.firebase.google.com](https://console.firebase.google.com)
   - Enable Firestore and Authentication (Apple Sign-In, Google Sign-In)
   - Download `GoogleService-Info.plist` and add it to `ios/PT-Helper/COIL/`

3. **Deploy Cloud Functions**
   ```bash
   cd functions
   npm ci
   npm run deploy
   ```

4. **Configure API endpoint**
   - Update `ios/PT-Helper/COIL/Services/APIConfig.swift` with your Cloud Functions URL

5. **Deploy Firestore rules**
   ```bash
   firebase deploy --only firestore:rules
   ```

## Data Flow

### Injury Analysis Flow

1. User taps pain region on 3D body map
2. `PainDetailView` collects: pain level, type, duration, triggers, treatment history
3. `InjuryAnalysisViewModel` builds the assessment with `HistoryRelevanceFilter` sorting medical history by anatomical proximity
4. Request goes to Cloud Function → Claude API with the server-side system prompt
5. `ResponseValidationPipeline` validates the response (6-step analysis validation)
6. Results displayed in `AnalysisResultView`

### Wellness Flow

1. User selects wellness goals (posture, sleep, mobility, strength, pain management)
2. Two-call analysis pipeline (`wellness_analysis` + `wellness_verify`)
3. Wellness plan generated with exercises + daily habits/micro-practices

### Health History Relevance

The `HistoryRelevanceFilter` classifies surgeries and injuries as:
- **Directly relevant** — Same body region or active recovery/restrictions
- **Possibly relevant** — Connected via kinetic chain (e.g., hip issue when assessing knee)
- **Background only** — Unrelated or old and fully recovered

This produces focused AI prompts with detailed relevant history and condensed background context.

## Testing

```bash
# All unit tests (UnitPlan — the PR gate)
xcodebuild test -project ios/PT-Helper/COIL.xcodeproj \
  -scheme COIL -destination 'platform=iOS Simulator,name=iPhone 16'
```

> If `name=iPhone 16` resolves to the wrong runtime on your machine, append `,OS=18.2` to the destination (or target the simulator by UDID).

Test plans: `UnitPlan` (all unit tests — the PR gate), `FullPlan` (unit + collision + UI — nightly), `PreReleasePlan` (FullPlan targets + coverage — the release gate), `SmokePlan` (11-test local quick check, not a CI gate).

## Safety

The app includes multiple safety layers:

1. **Red-flag detection** — Flags symptoms requiring emergency care (numbness, bowel/bladder changes, etc.)
2. **Input sanitization** — Strips prompt injection attempts from user text
3. **Analysis validation** — 6-step pipeline: content validation, symptom/condition red flags, anatomical relevance, confidence calibration (85% cap), deduplication
4. **Rehab plan validation** — 9-step pipeline: image-availability + auto-substitution, contraindications, knowledge graph verification, parameter ranges, exercise count, duration, age safety, medical conditions, medication-aware + post-surgical checks
5. **Form feedback validation** — `FormFeedbackValidationPipeline` + `BiomechanicalRuleEngine` for exercise form analysis safety
6. **Rate limiting** — 20 requests/minute per user (server-side)
7. **Firestore rules** — Users can only read/write their own data
8. **Disclaimer** — App presents wellness guidance disclaimer, not medical diagnosis

## Exercise Images

Roughly 1,360 canonical exercises, each with a start and an end frame, generated with **Nano Banana Pro** (`gemini-3-pro-image-preview`) and quality-scored with **Gemini 2.5 Flash** vision.

**How the app gets them:** `ExerciseImageService` resolves an exercise name to a filename through 8 layers of fuzzy matching (exact → normalized → alias → prefix → suffix → plural toggle → synonym expansion → qualifier stripping), then downloads the PNG from **Firebase Storage** and caches it in memory and on disk. If nothing resolves, it asks the `generateExerciseImage` Cloud Function to produce one on demand. **No exercise images ship in the app bundle** — only `Resources/exercise_image_mapping.json` does.

The masters and the mapping live in `scripts/output/` and are tracked in git; `scripts/upload_to_firebase.sh` is what puts them in Storage. The pipeline itself — generation, the auto-prompt correction loop, QA, end frames, and mapping rebuild — is documented in `scripts/README.md`.

## Key Files

| File | Purpose |
|------|---------|
| `Models/InjuryAnalyzer.swift` | Builds AI prompts with relevance-sorted history |
| `Models/WellnessAnalyzer.swift` | Builds wellness analysis prompts |
| `Services/ResponseValidationPipeline.swift` | Analysis (6-step) and rehab plan (9-step) validation |
| `Services/BiomechanicalRuleEngine.swift` | Exercise-specific form validation rules |
| `Services/HistoryRelevanceFilter.swift` | Kinetic chain health history classification |
| `Services/ExerciseImageService.swift` | 8-layer fuzzy image matching, Storage fetch, caching |
| `Services/ClaudeAPIService.swift` | Claude API client (9 request types) |
| `ViewModels/InjuryAnalysisViewModel.swift` | Analysis flow orchestration |
| `ViewModels/RecoveryInsightsViewModel.swift` | Managed Agent recovery insights |
| `ViewModels/GuidedWorkoutViewModel.swift` | Workout state machine with checkpointing |
| `Views/MainTabView.swift` | 4-tab navigation shell + floating "+" |
| `Views/TabSelection.swift` | Shared tab state + assessment routing |
| `Views/BodyMap3DView.swift` | RealityKit 3D body model |
| `DesignSystem.swift` | App-wide colors, spacing, typography |
| `functions/src/prompts.ts` | `SYSTEM_PROMPTS` + `MODEL_CONFIG` — the server-side prompts |
| `functions/src/index.ts` | Cloud Function handlers, rate limiting, quotas |
| `functions/src/managed-agent.ts` | Managed Agents API client |
