# PT Helper

An iOS app that uses AI to deliver personalized physical therapy guidance — from injury analysis through guided rehab workouts.

Users tap where it hurts on a 3D body model, answer targeted questions, and receive a PT-style analysis with a structured exercise plan they can follow with built-in workout guidance.

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
- **Exercise Images** — 1,364 AI-generated exercise illustrations (start + end frames) via Nano Banana Pro (`gemini-3-pro-image-preview`) with automated Gemini QA, served on demand from Firebase Storage
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

## Project Structure

```
├── ios/PT-Helper/
│   └── PT-Helper/
│       ├── Models/            # Data models (22 files)
│       ├── Services/          # API, validation, logging (33 files)
│       ├── ViewModels/        # Business logic (14 files)
│       ├── Views/             # SwiftUI views (71 files)
│       │   ├── Components/    # Reusable UI components
│       │   ├── Dashboard/     # Dashboard widgets and charts
│       │   └── OnboardingSteps/  # Onboarding flow steps
│       ├── Resources/         # exercise_image_mapping.json (images live in Firebase Storage)
│       └── DesignSystem.swift # Colors, spacing, typography
│   └── COILTests/        # Unit + UI tests
├── functions/src/             # Firebase Cloud Functions
│   ├── index.ts               # Rate limiting, system prompts, AI proxy endpoints
│   ├── managed-agent.ts       # Managed Agents API client (recovery insights)
│   ├── form-agent.ts          # Cross-session form analysis agent
│   ├── image-generation.ts    # On-demand exercise image generation
│   ├── billing-shutoff.ts     # Daily AI budget enforcement
│   ├── firestore-queries.ts   # Recovery data queries
│   └── nightly-report-validator.ts
├── scripts/                   # Exercise image pipeline (Nano Banana Pro)
│   ├── generate_missing_images.py
│   ├── regen_with_auto_prompts.py  # Auto-prompt correction loop
│   ├── qa_exercise_images.py
│   ├── upload_to_firebase.sh
│   ├── exercise_list.json          # Curated exercise metadata (legacy 190)
│   └── output/                     # 1364 generated start+end frames + QA reports
├── docs/                      # Brief, UX flows, safety, API, data models, privacy/terms
├── firebase.json              # Firebase deployment config
└── firestore.rules            # Security rules
```

## Getting Started

### Prerequisites

- Xcode 16+
- iOS 18.2+ deployment target
- Node.js 22 (for Cloud Functions)
- Firebase CLI (`npm install -g firebase-tools`)
- A Firebase project with Firestore and Authentication enabled

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
   npm install
   firebase deploy --only functions
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
4. Request goes to Cloud Function → Claude API with structured system prompt
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
# Run all tests from Xcode or command line
xcodebuild test -project ios/PT-Helper/COIL.xcodeproj \
  -scheme COIL -destination 'platform=iOS Simulator,name=iPhone 16'
```

Test plans: SmokePlan (11 key tests), UnitPlan (all unit), FullPlan (all + collision + UI), PreReleasePlan (all + UI + coverage).

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

## Exercise Image Pipeline

1,364 canonical exercises with start + end frame pairs, generated with AI and uploaded to Firebase Storage.

> **Primary pipeline (current):** Nano Banana Pro (`gemini-3-pro-image-preview`) via
> `scripts/generate_missing_images.py` and the auto-prompt correction loop in
> `scripts/regen_with_auto_prompts.py`.
>
> **Legacy pipeline:** FLUX 2 Pro via BFL API (`scripts/generate_exercise_images.py`) is
> deprecated for new image work. Note: the on-demand `generateExerciseImage` Cloud
> Function may still call FLUX — migration to Nano Banana Pro is an open item.

```bash
# Generate missing images with Nano Banana Pro (Gemini API key)
cd scripts
python generate_missing_images.py --api-key YOUR_GEMINI_KEY

# Auto-prompt correction loop (regenerate failures with targeted prompts)
python regen_with_auto_prompts.py --api-key YOUR_GEMINI_KEY

# Run automated QA (Gemini 2.5 Flash)
python qa_exercise_images.py --api-key YOUR_GEMINI_KEY

# Upload PNGs + mapping to Firebase Storage (needs `gcloud auth login`)
./upload_to_firebase.sh

# Legacy: FLUX 2 Pro generation (requires BFL API key)
python generate_exercise_images.py --api-key YOUR_BFL_KEY
```

- **Generator**: Nano Banana Pro (`gemini-3-pro-image-preview`) with structured pose descriptions — far better prompt adherence than the legacy FLUX pipeline
- **QA**: Gemini 2.5 Flash vision model (9 checks + 1–5 pose-accuracy score)
- **Auto-prompt correction**: feed Gemini its own QA failure → it writes a targeted regen prompt with anti-cues → near-100% success
- **Style**: Clean white background, anatomical mannequin figure
- **Delivery**: images served on demand from Firebase Storage; the iOS bundle ships only `exercise_image_mapping.json`
- **Image resolution**: 7-layer fuzzy matching in `ExerciseImageService`

> The original FLUX 2 Pro pipeline (`generate_exercise_images.py`, BFL API) is retained for the on-demand image Cloud Function but is no longer used for batch generation.

## Key Files

| File | Purpose |
|------|---------|
| `Models/InjuryAnalyzer.swift` | Builds AI prompts with relevance-sorted history |
| `Models/WellnessAnalyzer.swift` | Builds wellness analysis prompts |
| `Services/ResponseValidationPipeline.swift` | Analysis (6-step) and rehab plan (9-step) validation |
| `Services/BiomechanicalRuleEngine.swift` | Exercise-specific form validation rules |
| `Services/HistoryRelevanceFilter.swift` | Kinetic chain health history classification |
| `Services/ExerciseImageService.swift` | 7-layer fuzzy image matching and caching |
| `ViewModels/InjuryAnalysisViewModel.swift` | Analysis flow orchestration |
| `ViewModels/RecoveryInsightsViewModel.swift` | Managed Agent recovery insights |
| `ViewModels/GuidedWorkoutViewModel.swift` | Workout state machine with checkpointing |
| `Views/MainTabView.swift` | 4-tab navigation shell + floating "+" |
| `Views/BodyMap3DView.swift` | RealityKit 3D body model |
| `Services/ClaudeAPIService.swift` | Claude API client (9 request types) |
| `functions/src/index.ts` | Cloud Functions with system prompts |
| `functions/src/managed-agent.ts` | Managed Agents API client |
| `DesignSystem.swift` | App-wide colors, spacing, typography |
