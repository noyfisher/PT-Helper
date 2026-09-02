# Product Brief (COIL)

Goal: Help athletes self-assess pain via a 3D body map, answer PT-style questions, and receive AI-powered condition analysis with personalized rehab plans and guided workouts.

Users: Athletes and fitness enthusiasts (self-directed rehabilitation).

## Core Flows
1. **Intro Carousel + Onboarding** — 3-screen intro carousel precedes the 6-step health profile wizard for first-time users
2. **3D Body Map** — Tap body regions to select pain areas (RealityKit, coach marks for first-time users)
3. **Pain Assessment** — Per-region form with collapsible optional sections, "Apply to All" for multi-region
4. **AI Analysis** — Two-call verification pipeline → top 3 conditions with confidence bands, red flag alerts
5. **Wellness Goals** — Proactive health flow (posture, sleep, mobility, strength, pain management) with its own two-call analysis pipeline
6. **Rehab Plan** — AI-generated plan with user preferences (equipment, session length, difficulty), exercise verification via knowledge graph + cross-model check, adaptive progressions, exercise substitution
7. **Guided Workout** — Step-by-step execution with rest timers, exercise swaps, and crash-resilient checkpointing (24-hour expiry)
8. **Form Analysis** — On-device pose detection (MLKit) + biomechanical rule engine for video-based exercise form feedback
9. **Progress Tracking** — Pain trend charts, workout streaks, AI-powered weekly recovery insights via Managed Agents

## Safety
- Non-diagnosis disclaimer shown on first use
- Red flags trigger prominent urgent care alerts
- Confidence capped at 85% with user-facing explanation
- Exercise verification (knowledge graph + cross-model) flags contraindicated exercises
- Medication interaction checks via validation pipeline

## Technical Stack
- iOS: SwiftUI + RealityKit + Firebase (Auth, Firestore, Crashlytics)
- Backend: Firebase Cloud Functions (TypeScript) → Claude API proxy
- Images: 1364 AI-generated exercise illustrations, start + end frame pairs (Nano Banana Pro / `gemini-3-pro-image-preview`)
