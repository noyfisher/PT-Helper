# UX Flows

## Navigation Structure
4-tab shell via `MainTabView` plus a floating "+":
- **Home** (Tab 0) — weekly date strip, today's program + preventative tasks
- **My Plan** (Tab 1) — Active plan hero card + saved plans list, with Injury / Wellness sub-tabs filtering saved plans by `RehabPlan.PlanType`
- **Progress** (Tab 2) — Charts, recovery insights, settings, session history
- **Profile** (Tab 3) — profile summary + edit
- **Floating "+"** — Dual gateway: pain analysis or wellness goals (`AssessmentGatewayView`)

## Core Flow: Analysis → Plan → Workout

### 1. Body Map Selection (`BodyMap3DView`)
- RealityKit 3D body model with 19 bilateral zones (~32 with L/R)
- Tap to select/deselect (haptic + red highlight + toast)
- Drag to rotate, pinch to zoom, double-tap zoom toggle
- First-time coach mark overlay with gesture hints
- Continue button requires >= 1 region selected
- First-use disclaimer sheet before proceeding

### 2. Pain Assessment (`PainDetailView`)
- One form per selected region, navigated with Next/Back
- **Essential fields** (always visible): pain type chips, intensity slider (1-10), duration, frequency, onset, aggravating factors, relieving factors
- **Optional fields** (collapsed behind "Add More Details"): pain description, treatment history, additional notes
- "Apply to All Regions & Analyze" button shown on every region for multi-region selections
- Form completion progress bar with encouraging micro-copy

### 3. AI Analysis (`AnalyzingView` → `AnalysisResultView`)
- Two-call pipeline: primary analysis → verification (15-30s)
- Loading screen with 4-step progress indicator and elapsed timer
- Results: top 3 conditions with expand/collapse cards
- Match strength indicator (Strong/Moderate/Weak) with info button explaining 85% cap
- Red flag alerts as prominent banners
- "Build Rehab Plan" opens preferences sheet before generation

### 4. Rehab Plan Preferences (`AnalysisResultView` sheet)
- Equipment: None / Resistance bands / Dumbbells / Full gym
- Session length: 15 / 30 / 45 min
- Difficulty: Gentle / Moderate / Challenging
- "Skip" option uses defaults; "Generate Plan" passes preferences to AI

### 5. Rehab Plan (`RehabPlanView`)
- Plan header with conditions, duration, start date
- Weekly calendar with exercise-day indicators
- Exercise cards with images, sets/reps, difficulty, verification badges
- Visible swap button on each exercise card (saved plans only)
- Context menu also available for swap
- "Start Guided Workout" button
- Share plan as PDF, edit plan via sheet
- Adaptive progression banner when performance data warrants changes

### 6. Guided Workout (`GuidedWorkoutView`)
- **Sticky bottom action bar** with primary action ("Complete Set" / "Skip Rest" / "Next Exercise")
- **Exercise phase**: image, 3-phase instruction stepper (Start Position → Movement → Return Position), tips
- **Progressive learning**: exercise familiarity tracking (new/learning/familiar/mastered); new exercises auto-expand instructions, familiar exercises collapse them
- **Rest phase**: circular countdown timer, next exercise preview, skip rest button
- Pause/resume, skip exercise, swap exercise mid-workout
- "End" button shows confirmation dialog ("End & Save" / "Cancel")
- **Checkpointing**: state saved to UserDefaults on every set completion/skip
- **Resume**: on relaunch, detects incomplete session and offers resume prompt
- Checkpoints expire after 24 hours

### 7. Workout Summary (`GuidedWorkoutSummaryView`)
- Trophy celebration animation
- Stats: duration, completed, skipped
- Pain input: overall slider + per-region sliders
- Session notes
- "Save & Done" saves session; button changes to "Done" for explicit dismiss
- No auto-dismiss — user controls when to leave

## Wellness Flow

### 1. Wellness Goal Picker (`WellnessGoalPickerView`)
- Accessed from Assess tab dual gateway ("I want to improve my wellness")
- User selects wellness goals: posture, sleep, mobility, strength, pain management
- Additional context/questionnaire fields

### 2. Wellness Analysis (`WellnessAnalyzingView` → `WellnessResultView`)
- Two-call pipeline: `wellness_analysis` → `wellness_verify`
- Loading screen similar to injury analysis
- Results: personalized wellness assessment with recommendations

### 3. Wellness Plan (`WellnessPlanView`)
- AI-generated plan combining exercises and daily habits/micro-practices
- Exercises structured same as rehab plans (sets, reps, phases)
- Habits include: stretches, breathing exercises, positioning cues
- Can start guided workout from plan

## Form Analysis Flow

### 1. Video Capture (`VideoRecorderView`)
- Record exercise form during workout
- Minimum 720p video quality required for pose detection

### 2. Analysis (`FormAnalysisView`)
- MLKit pose detection extracts joint positions on-device
- `PoseAnalysisEngine` computes joint angles, per-rep symmetry
- `BiomechanicalRuleEngine` applies exercise-specific form rules
- AI-generated form feedback with safety validation
- Results: form score, specific corrections, what you're doing well

## Exercise Swap Flow

### From Plan View
- Swap button visible on each exercise card (saved plans only)
- Opens `ExerciseSwapSheet` with AI-suggested alternatives
- Alternatives match same difficulty and rehab purpose

### Mid-Workout
- Swap option available during guided workout
- Uses `exercise_substitute` request type
- Seamlessly continues workout with new exercise

## Recovery Insights Flow

### Recovery Digest (`RecoveryInsightsCardView` → `RecoveryInsightsDetailView`)
- Available on Progress tab and Home/Assess tab as quick action
- Requires 3+ workout sessions in past 14 days
- Multi-step AI analysis via Managed Agent:
  - Pain trend detection (improving/stable/worsening) per region
  - Adherence scoring (sessions completed vs. expected)
  - Key wins and focus areas
  - Personalized recommendations with SF Symbol icons
- Teaser with progress dots shown when < 3 sessions

## Re-Assessment Flow

### Re-Assessment Prompt (`ReAssessmentPromptView`)
- Prompted periodically to re-assess pain levels
- Comparison view (`ReAssessmentComparisonView`) shows current vs. previous
- Tracks progress over time

## Secondary Flows

### Assess Tab
- Dual gateway: "I'm in pain" (→ body map) or "I want to improve" (→ wellness goals)
- Health check prompt when returning after 3+ months of inactivity

### My Plan Tab
- Active plan hero card (most recent plan)
- Injury / Wellness sub-tabs filter saved plans by `RehabPlan.PlanType`
- Saved plans list with tap to open
- Recent workout sessions (last 10) with swipe-to-delete

### Onboarding (preceded by 3-screen intro carousel)
Before the wizard, first-time users see a 3-screen intro carousel that introduces the app's value proposition.

Then the 6-step wizard:
1. Basic info (name, DOB, sex, height/weight) — required
2. Medical history — optional, subtitle explains AI accuracy impact
3. Surgical history — optional, subtitle explains safety value
4. Injury history — optional, subtitle explains personalization value
5. Activity level — required
6. Review & submit

### Health Check Prompt
- Shown when user returns after 3+ months of inactivity
- Options: "Update My Profile" or "Continue to Analysis"

### Settings
- Reminders (toggle + time picker)
- Debug log export
- Sign out, delete account (two-step confirmation)

### Progress Tab
- Pain trend line chart filtered by region
- Summary stats: total sessions, avg pain, total minutes
- Recovery insights card (AI-generated weekly digest, requires 3+ sessions in 14 days)
- Session history list
