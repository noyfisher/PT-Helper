# Changelog

All notable changes to PT Helper are documented here.

## [Unreleased]

### Added
- **Documentation Overhaul** — Updated all documentation to reflect current app state

## [1.3.0] — 2025-04-12

### Added
- **Workout UX Overhaul** — Sticky bottom action bar, 3-phase exercise stepper (Start Position → Movement → Return Position), progressive learning with exercise familiarity tracking (new/learning/familiar/mastered)
- **Exercise Image QA Fix Agent** — Claude-powered agent that analyzes QA failures, regenerates images via FLUX 2 Pro, and re-runs Gemini QA automatically
- **Recent Workouts Section** — Last 10 workout sessions on dashboard with swipe-to-delete
- **Background Task Support** — API calls continue when app is backgrounded

### Fixed
- Pre-beta UX — Touch targets, accessibility IDs, build number bump
- Pre-beta test failures — Proxy collisions, agent mock setup, timer flake
- Swipe-to-delete, discard workout confirmation, UI test updates

## [1.2.0] — 2025-03-28

### Added
- **Pose Analysis Enhancement** — Per-rep symmetry analysis, expanded biomechanical rules for exercise form validation
- **Claude Managed Agents** — Multi-step recovery insights via ephemeral Managed Agent sessions with `submit_recovery_insights` tool
- **3-Tab Navigation Redesign** — New Assess / My Plan / Progress tabs replacing the old 4-tab layout
- **Nightly Email Report** — SendGrid-powered daily product analytics digest

### Changed
- Wellness plan migration to new data model

## [1.1.0] — 2025-03-15

### Added
- **Sage & Stone Restyle** — Complete visual overhaul of all screens with new design tokens
- **Form Check Tab** — Exercise form analysis via video capture + MLKit pose detection
- **Wellness Pathway** — Dual-gateway in Assess tab: pain analysis or wellness goals with goal picker, questionnaire, AI analysis (two-call pipeline), and habit-based plans
- **Exercise Form Analysis** — 3D pose detection with 7-layer form feedback validation pipeline (`BiomechanicalRuleEngine`, `PoseAnalysisEngine`, `FormFeedbackValidationPipeline`)
- **Dashboard Redesign** — Pain trend charts, confidence charts, differentials table, exercise performance table, session history list, profile widget
- **Exercise Substitution** — AI-powered swap from plan view or mid-workout
- **Recovery Insights** — AI-generated weekly recovery digest with pain trends, adherence scoring, recommendations
- **Adaptive Progressions** — Rules-based difficulty scaling with progression banner
- **Body Map Zones** — Extended zone system with `BodyZone` model
- **Exercise Image Coverage** — Expanded to ~190 illustrations

### Changed
- Removed legacy OpenAI agent infrastructure
- DesignSystem.swift overhauled with Sage & Stone tokens

## [1.0.0] — 2025-03-08

### Added
- **Pre-Release Beta Sprint** — Firebase Crashlytics, legal docs (privacy policy, terms of service), Google Sign-In, FCM push notifications, accessibility improvements
- **Release Automation Pipeline** — GitHub Actions for CI/CD
- **Medical Knowledge Graph** — `KnowledgeGraphService` for deterministic exercise-condition verification
- **Cross-Model Verification** — `CrossModelVerificationService` for rehab plan validation
- **Enhanced Health Profile** — Expanded medical conditions and medications tracking
- **Two-Call Verify Pipeline** — Secondary AI review for analysis results

## [0.9.0] — 2025-03-08

### Added
- **Firebase Crashlytics** — Automatic dSYM upload for crash reporting
- **Apply to All Regions** — Button to copy pain details across multiple selected body regions
- **Session Logging** — Detailed event logging for analysis and workout sessions with Firestore upload

### Fixed
- Analysis and rehab plan navigation crashes resolved
- Firebase warning suppression in test suite

## [0.8.0] — 2025-02-28

### Added
- **3D Body Map Proxy Entities** — Invisible collision entities for occluded body regions (back, glutes)
- **Comprehensive Collision Tests** — BodyMapCollisionTests for proxy entity validation
- **Test Reorganization** — 22 focused test files with Xcode Test Plans

## [0.7.0] — 2025-02-20

### Added
- **AI Response Validation Pipeline** — Multi-step safety validation for analysis and rehab plan responses
- **Exercise Contraindication Checker** — Cross-references exercises against diagnosed conditions
- **Medical Red Flag Detector** — Symptom pattern matching for emergency conditions
- **Anatomical Relevance Checker** — Validates AI conditions match assessed body regions
- **Confidence Calibration** — Caps AI confidence at 85%, maps to human-friendly labels
- **Exercise Images** — 178 AI-generated exercise illustrations (FLUX 2 Pro)

## [0.6.0] — 2025-02-10

### Added
- **Tester Feedback Round** — Onboarding UX improvements, analysis flow refinements, workout logging enhancements
- **TestFlight Configuration** — Bundle ID update, provisioning for TestFlight distribution

## [0.5.0] — 2025-01-30

### Added
- **Firebase Cloud Functions Proxy** — Server-side API key management, rate limiting, system prompts
- **Exercise Image Logging** — Missing image detection and Firestore reporting
- **Pre-TestFlight Polish** — UI refinements and stability improvements

## [0.4.0] — 2025-01-20

### Added
- **Injury Analysis** — AI-powered pain assessment with condition identification
- **Rehab Plans** — Personalized exercise programs with weekly schedules
- **Guided Workouts** — Step-by-step workout sessions with timers and counters
- **Plan Management** — Save, edit, and track rehab plans
- **Onboarding Flow** — Multi-step health profile collection

## [0.3.0] — 2025-01-10

### Added
- **3D Body Map** — Interactive RealityKit body model with tap-to-select regions
- **Pain Detail Collection** — Multi-factor pain assessment (type, intensity, duration, triggers)
- **Progress Tracking** — Workout streaks, achievements, progress charts

## [0.2.0] — 2024-12-15

### Added
- Initial app structure with SwiftUI navigation
- Firebase Authentication (Apple Sign-In, Google Sign-In)
- Basic user profile management
- Notes system for tracking observations
