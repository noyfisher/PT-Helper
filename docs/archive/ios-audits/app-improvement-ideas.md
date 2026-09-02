# PT Helper — App Improvement Ideas

_Read-only audit. 105 ideas, each verified against the actual code. Nothing changed in the project._

**Impact** = how much users/business feel it · **Effort** = rough build cost (small / medium / large)

## ⭐ Quick wins (biggest payoff, smallest build)
- Wellness path is unreachable for new users
- 'Start Assessment' / 'Re-Assess' buttons route to a dead-end tab
- Skip discards everything and re-traps the user on next launch
- Onboarding ends in a cold tab instead of a personalized 'aha' moment
- Emergency 'Call' button can silently do nothing on iPad / non-cellular devices
- Form Check is buried in the legacy dashboard — invisible in the main 3-tab app
- 'Inactivity Nudges' and 'Re-Assessment Prompts' toggles do nothing
- No first-workout / activation nudge during the make-or-break first week
- 3D body map has no non-visual way to select a region
- Custom fonts ignore Dynamic Type app-wide
- Earned achievements unlock completely silently — celebration is wired up but never shown
- Workout completion screen ignores the streak and achievements it just earned
- 'End Workout' confirmation gives the destructive Discard option safe styling

## 🏗️ Bigger bets (high impact, larger build)
- Custom fonts ignore Dynamic Type app-wide
- Split-brain typography: whole screens never got the rebrand
- No way to review the recorded clip alongside the feedback

---

## First-run & onboarding momentum
_The signup funnel front-loads heavy medical questions, breaks the Skip option, and ends with no payoff — losing people before they reach the AI that is the actual product._

### 1. Onboarding ends in a cold tab instead of a personalized 'aha' moment
`high impact` · `medium effort` · `engagement` · `ios/PT-Helper/PT-Helper/Views/OnboardingSteps/ProfileReviewStepView.swift:99-117; ios/PT-Helper/PT-Helper/RootView.swift:133-134`

**Pitch:** Right now, the moment a new user finishes their full health profile, the app just drops them on a generic home screen with no reward or direction. We'd turn that finish line into a personalized hand-off straight into their first injury assessment, so the effort immediately pays off and far more people reach the AI analysis that is the actual product.

- **Today:** After 6 steps of medical data entry, Submit shows a 'Profile Saved!' overlay for 1.5s and drops the user onto a generic home tab. None of the info they entered visibly does anything — no first plan, no nudge into the body-map assessment, no payoff.
- **Proposal:** On completion, route directly into the first pain/body-map assessment with a one-line personalized hook referencing what they entered ('Ready to map that knee, Sarah?'). At minimum land on an Assess screen with a prominent 'Start your first assessment' CTA.

### 2. Skip discards everything and re-traps the user on next launch
`high impact` · `small effort` · `flow` · `ios/PT-Helper/PT-Helper/RootView.swift:135-137; ios/PT-Helper/PT-Helper/Views/OnboardingView.swift:18-29`

**Pitch:** If a new user taps 'Skip' on profile setup, the app forgets that choice and dumps them right back into the same questionnaire every time they reopen it. We'd make Skip actually stick, so people who aren't ready to fill out their profile can get into the app and stay there instead of hitting the same wall on every launch.

- **Today:** The Skip button only sets profileCompleted = true in memory and never saves a profile. On next launch, checkProfileExists() returns false and the user is forced back into the full onboarding and intro carousel again.
- **Proposal:** Make Skip create a minimal valid profile (or a 'skippedOnboarding' flag that checkProfileExists honors) so the choice survives a relaunch. Alternatively remove the top-bar Skip and rely on per-step optionality.

### 3. Friction is front-loaded: medical history asked before easy questions
`medium impact` · `small effort` · `flow` · `ios/PT-Helper/PT-Helper/Views/OnboardingView.swift:67-74, 126-148`

**Pitch:** Right after signing up, new users get hit with the heaviest, most personal questions first — medications, past surgeries, injuries — before the quick, fun 'how active are you?' tap. We'd flip that so the easy, identity-affirming choice comes early and carries people through the harder questions, meaning more of them finish setup instead of bailing partway.

- **Today:** Step order is Basic Info, Medical History, Past Surgeries, Injuries, Activity Level, Review. The three heaviest, most sensitive steps (conditions grid + meds, surgery cards, injury cards) sit at positions 2-4, while the light single-tap Activity Level step is buried at position 5.
- **Proposal:** Move Activity Level to step 2 (a single tap that builds momentum and is non-threatening), and cluster the optional medical/surgical/injury steps later so difficulty ramps up rather than peaking right after the required step.

### 4. Two full names plus DOB required up front with no 'why'
`medium impact` · `small effort` · `flow` · `ios/PT-Helper/PT-Helper/ViewModels/OnboardingViewModel.swift:214-221; ios/PT-Helper/PT-Helper/Views/OnboardingSteps/BasicInfoStepView.swift:16-27`

**Pitch:** The first onboarding screen forces new users to type both a first and last name even though the app never shows a surname anywhere. We can drop that requirement and add a one-line note explaining why we ask for height and weight. Fewer required fields and a bit of reassurance means more people finish signup instead of bouncing.

- **Today:** Step 1 hard-blocks Continue until first AND last name, sex, height, weight and Terms are all filled. Last name is required even though nothing user-facing uses a surname, and there's no explanation of why any of it is collected.
- **Proposal:** Drop the last-name requirement and add an inline reassurance under the name field. Keep sex/height/weight (they feed clinical safety) but add a one-line note that they tailor exercise dosing.

### 5. No time/effort expectation set before the 6-step form
`medium impact` · `small effort` · `copy` · `ios/PT-Helper/PT-Helper/Views/IntroCarouselView.swift:354-363; ios/PT-Helper/PT-Helper/Views/OnboardingView.swift:35-63`

**Pitch:** When new users hit 'LET'S GO,' they land in a 6-step health questionnaire with no idea how long it takes or whether they can skip parts — which makes people bail. One reassuring line up front makes the intake feel quick and low-stakes instead of a daunting medical form, helping more people finish.

- **Today:** Tapping 'LET'S GO' drops the user straight into step 1 of 6 with only a thin progress bar. Nothing tells them how long it takes, that most steps are optional, or that progress auto-saves (the draft-save feature exists but is invisible).
- **Proposal:** Add a brief framing line on the carousel's final page or step 1 header: 'Takes about 2 minutes — and you can skip anything that doesn't apply, your progress is saved.'

### 6. Injury/surgery entry is free-text only despite the app having a body map
`medium impact` · `medium effort` · `feature` · `ios/PT-Helper/PT-Helper/Views/OnboardingSteps/InjuryHistoryStepView.swift:51-54; ios/PT-Helper/PT-Helper/Views/OnboardingSteps/SurgicalHistoryStepView.swift:40-42`

**Pitch:** Today, new users type past injuries and surgeries into a blank box — easy to fumble on a phone and easy to phrase three different ways. We'd swap that for a tap-to-pick list of body regions, so setup is faster, the AI gets clean data, and people preview our signature body map from minute one.

- **Today:** To log an injury or surgery, users free-type the body area ('Left Knee') into a plain text field. The signature 3D body map isn't leveraged, and free text produces inconsistent strings ('l knee' vs 'Left Knee') that history-relevance filtering and AI prompts must contend with.
- **Proposal:** Replace the free-text body-area field with a tap-to-select chip list of common regions (or a lightweight body-map picker) with a 'Custom' fallback, giving structured data and a preview of the body-map feature.

### 7. Carousel sells 'elite performance' while the form asks about surgeries and blood thinners
`medium impact` · `small effort` · `copy` · `ios/PT-Helper/PT-Helper/Views/IntroCarouselView.swift:158-170, 249-263, 328-338; ios/PT-Helper/PT-Helper/Views/OnboardingSteps/MedicalHistoryStepView.swift:8-33`

**Pitch:** Right after a flashy 'peak performance' intro, the app asks for sensitive medical history with no explanation of why — which feels like a bait-and-switch and scares people off. One reassuring line on those screens explains the 'why' and builds trust at the most fragile moment of onboarding.

- **Today:** The intro carousel is framed entirely as athletic performance ('PRECISION RECOVERY', 'FAST TRACK TO PERFORMANCE'), then the next screens ask for diabetes, heart disease, blood thinners, corticosteroids, and past surgeries with no bridge explaining why a 'performance' app needs medical data.
- **Proposal:** Add one value-bridge line atop the medical/surgical/injury steps ('We use this to keep every exercise safe for your body — never to diagnose you'), and optionally soften the carousel to speak to recovery/pain users too.


## Dead-end navigation & broken entry points
_The wellness path has no door, key CTAs route to a stranded tab, and several screens send users to placeholders — leaving people unable to reach features that are already fully built._

### 8. Wellness path is unreachable for new users
`high impact` · `small effort` · `flow` · `ios/PT-Helper/PT-Helper/Views/ThreeTabView.swift:61-99; WellnessGoalPickerView only entered from AssessTab.swift:93 and AnalysisDashboardView.swift:164`

**Pitch:** The app's entire proactive-wellness side — plans for posture, sleep, mobility, strength — is fully built but has no door into it from the main screen; the big '+' only starts the injured-body flow. Adding a simple 'Something hurts / Improve my life' choice instantly unlocks the app for people who aren't injured, doubling who can get value from a feature we already shipped.

- **Today:** In the live 3-tab UI, the floating + button opens BodyMap3DView (pain only). The wellness goal picker is reachable only from disabled UIs (AssessTab is never instantiated; AnalysisDashboardView is behind useDashboardUI=false). A new user with no wellness plan has no way to start the wellness flow, and the MyPlanTab 'Set Wellness Goals' CTA just routes to a tab with no wellness entry.
- **Proposal:** Make the + button (or a visible Home/Plan entry) present the dual gateway — either present AssessTab as the + destination, or add a 'Something hurts / Improve my life' chooser before the body map. At minimum, wire the wellness empty-state CTAs to WellnessGoalPickerView.

### 9. 'Start Assessment' / 'Re-Assess' buttons route to a dead-end tab
`high impact` · `small effort` · `flow` · `ios/PT-Helper/PT-Helper/Views/HomeTab.swift:313, MyPlanTab.swift:250, ProgressTab.swift:524`

**Pitch:** When someone has no plan yet or gets nudged to re-check progress, the big 'Start Assessment' / 'Re-Assess Now' buttons don't open the assessment — they just switch to the Home calendar and strand the user. Wiring those buttons to launch the assessment directly sends the most eager taps straight to the body map, lifting how many people complete an assessment.

- **Today:** Three prominent CTAs — Home's 'Start Assessment', MyPlan's empty-state buttons, and Progress's 'Re-Assess Now' — all set tabSelection.selectedTab = 0. But tab 0 is HomeTab (the calendar), not an assessment screen. HomeTab has no assessment launcher, so the user is dropped on a screen with no next step and must discover the floating + button themselves.
- **Proposal:** Point these CTAs at the actual assessment launcher — trigger the same showAssessment fullScreenCover the + button uses, or present the gateway directly so the label and destination match.

### 10. Deep-link / notification router points 'analyze' at the wrong screen and ignores wellness
`medium impact` · `small effort` · `flow` · `ios/PT-Helper/PT-Helper/Views/ThreeTabView.swift:104-128`

**Pitch:** When someone taps a 'time to reassess' reminder, the app should open the assessment — but today it dumps them on the home calendar to hunt for the right button. Fixing the routing (and adding a wellness reminder path) means our re-engagement nudges actually deliver people to the screen the notification is about, so more taps become completed assessments.

- **Today:** The deep-link router maps 'home' and 'analyze' both to tab 0, but tab 0 is HomeTab — so an 'analyze' push (meant to start an assessment) lands on the Home calendar. There is no deep-link case for the wellness flow at all.
- **Proposal:** Make the 'analyze' deep link present the assessment (trigger showAssessment), and add a 'wellness' deep-link case that opens the wellness goal picker, keeping the routing table aligned with real tab contents.

### 11. Edit Profile opens a placeholder stub
`medium impact` · `small effort` · `structure` · `ios/PT-Helper/PT-Helper/Views/ThreeTabView.swift:168-172`

**Pitch:** Tapping 'Edit Profile' from the Profile tab currently hits a blank dead-end screen, even though the exact same button works from the Progress tab. This fix makes Edit Profile open the real editor everywhere, so people can reliably update health details — which directly drives the safety and accuracy of the AI's recommendations.

- **Today:** ProfileTab's edit-profile sheet renders literally Text('Edit Profile').padding() — a placeholder. The working editor (OnboardingEditView) is wired correctly in ProgressTab, so the same action behaves completely differently depending on which tab you reach it from.
- **Proposal:** Replace the placeholder with OnboardingEditView (or QuickHealthUpdateView), matching the ProgressTab path. If ProfileTab duplicates Progress's settings, consider removing the duplicate entry point.

### 12. Three scattered entry points to the same Log Workout / Notes screens
`low impact` · `medium effort` · `structure` · `ios/PT-Helper/PT-Helper/Views/AssessTab.swift:135-156, ProgressTab.swift:108-124, :119-123`

**Pitch:** 'Log Workout' and 'Recovery Notes' show up in several different spots across the Assess and Progress tabs, so there's no obvious place to find them. Giving each task one predictable home makes the app feel simpler and stops users wondering whether the three 'Log Workout' buttons do different things.

- **Today:** Log Workout (WorkoutSessionView) and Recovery Notes (NotesView) are surfaced as standalone rows in multiple places — AssessTab's Quick Actions, ProgressTab's body (two rows), and a 'See All' link. There's no single canonical home, so placement feels scattered and the Progress tab mixes charts, a log-workout card, a re-assess nudge, and a notes link in one scroll.
- **Proposal:** Consolidate utility actions into one predictable place (a Quick Actions group or the Profile/Progress tab) rather than repeating them per screen, and decide whether Log Workout needs both a card and a row on Progress.

### 13. Floating + button has no text label and an ambiguous meaning
`low impact` · `small effort` · `minor-design` · `ios/PT-Helper/PT-Helper/Views/ThreeTabView.swift:242-257`

**Pitch:** The big '+' at the centre of the tab bar is how people start a pain assessment — the first step of the whole app — but it's just a plus sign with no word next to it. A short label like 'Assess' lets new users instantly know that's where they go to get checked out, instead of guessing on the most important action in the app.

- **Today:** The centre action is a bare '+' circle with only an accessibility label ('New Assessment') — no visible caption, while the four flanking tabs all have text labels. A generic '+' reads as 'add an item', not 'start a pain assessment', yet it's the single most important action in the app and the least self-explanatory control.
- **Proposal:** Add a short visible caption under the + (e.g. 'Assess') or swap the glyph for something assessment-specific (body/stethoscope icon) so its purpose is legible without VoiceOver.

### 14. Tab labels/order don't match the documented information architecture
`low impact` · `small effort` · `structure` · `ios/PT-Helper/PT-Helper/Views/ThreeTabView.swift:205-212, :3 doc comment, :75 tabNames`

**Pitch:** Internal naming for the app's bottom tabs is out of sync with what users actually see, which has quietly caused buttons to jump to the wrong screen. Cleaning it up so code matches reality makes future navigation changes safer and less bug-prone — invisible to users, but it stops a recurring class of routing bugs.

- **Today:** The file header and CLAUDE.md describe a 3-tab Assess / My Plan / Progress IA, but the shipped bar is FOUR tabs (Home, Plan, Progress, Profile) plus a floating + — and tab 0 is HomeTab, not Assess. The struct is even named ThreeTabView. The stale conceptual model is why the selectedTab=0 CTAs misfire.
- **Proposal:** Reconcile the model: either rename/realign so tab 0 truly is the assessment gateway, or update the doc comments, struct name, and tabNames array to reflect Home/Plan/Progress/Profile. Pick one source of truth.


## Assessment & body-map friction
_The pain assessment — the funnel's most important step — forces extra taps, repeats an 8-step wizard per region, hides shortcuts, and ships dead legacy components._

### 15. Multi-region assessment repeats an 8-step wizard with the shortcut hidden at the end
`medium impact` · `small effort` · `flow` · `ios/PT-Helper/PT-Helper/Views/PainDetailView.swift:120; ios/PT-Helper/PT-Helper/Views/PainWizardSteps.swift:194-208`

**Pitch:** If you pick two symmetrical areas — both knees, both shoulders — the app makes you fill out the same 8-question pain form twice, and the 'copy my answers to all areas' shortcut is hidden at the very end of the first one. Surfacing that choice up front cuts a common drop-off point right before users get their AI analysis.

- **Today:** PainDetailView is a fixed 8-step wizard, repeated per region, so 3 regions = up to 24 screens. The one shortcut, 'Apply to All N Regions & Analyze,' is buried at the bottom of region one's step-7 summary, so users only discover it after completing 8 full steps.
- **Proposal:** Offer the 'apply the same answers to all regions' choice up front (a toggle on the first step or right after region selection: 'Is the pain similar in all areas?') so symmetrical multi-region users answer once.

### 16. Every region selection costs a forced two-tap zoom — no direct pick
`medium impact` · `medium effort` · `flow` · `ios/PT-Helper/PT-Helper/Views/BodyMap3DView.swift:937-945`

**Pitch:** Pointing at where you hurt on the 3D body map always takes two taps — one to zoom, another to pick the spot — even for obvious complaints like lower back. Letting you tap once in the common case makes logging your pain faster and the map feel snappy instead of fussy, exactly when people most want to just get help.

- **Today:** handleEntityTap() always drills into a zone first; selection is only reachable after drilling in. Even for an unambiguous complaint like 'Lower Back,' the user must tap once to zoom, then tap the sub-region to select. There's no single-tap select from the overview.
- **Proposal:** For zones with a single (or clearly dominant) selectable region, let the first tap select directly and skip the drill-down, or add a long-press-to-select shortcut in overview mode. At minimum auto-select the obvious sub-region.

### 17. No way to add, remove, or skip a region once the wizard starts
`medium impact` · `medium effort` · `flow` · `ios/PT-Helper/PT-Helper/Views/PainDetailView.swift:143-196`

**Pitch:** When someone taps several body areas then realizes one is actually fine, today they're stuck answering every question for it or starting over. Letting them skip or drop a region mid-flow means a single misclick on the body map no longer turns into a frustrating dead end.

- **Today:** The wizard nav bar only offers Continue/Next-Region/Back. There's no 'skip this region', and canContinue hard-requires a selection on most steps — so you can't advance a region you no longer care about without backing all the way out to the 3D map. There's also no confirmation when abandoning a half-finished assessment.
- **Proposal:** Add a 'Skip this region' affordance for multi-region sessions, let users drop a region from the 'Region 2 of 3' header, and add an 'are you sure?' confirm when backing out of a partially completed assessment.

### 18. Body-map gesture hints live only in a one-time coach mark
`medium impact` · `small effort` · `engagement` · `ios/PT-Helper/PT-Helper/Views/BodyMap3DView.swift:55-56, 340-407`

**Pitch:** The only hint that you can spin the 3D model to reach your back, glutes, or hamstrings shows up once, the first time. A returning user with back pain can easily think the app doesn't cover the back. A small always-visible 'rotate' cue means people can always find common pain areas, so the assessment never feels like a dead end.

- **Today:** The 'Tap / Drag / Pinch' instructions appear only once, gated by @AppStorage('hasSeenBodyMapCoach'). After 'Got it' they never return. Nothing lasting tells a returning user the model rotates — which is where lower back, glutes, hamstrings, and upper back live.
- **Proposal:** Keep a lightweight always-available rotate cue (or front/back chips), and add a way to replay the coach mark (a small '?' in the header).

### 19. Region pain picker uses zone keys that don't match the body map
`medium impact` · `small effort` · `structure` · `ios/PT-Helper/PT-Helper/Views/Components/RegionPainInputView.swift:12-26`

**Pitch:** The app uses two different sets of body-part names in two places: the body map you tap to start an assessment, and the 'rate your pain by region' form after a workout. They've drifted apart, so pain you log after a workout can be filed under a name the rest of the app doesn't recognize — leaving gaps in your progress charts. Pointing both at one shared list keeps your pain history connected end to end.

- **Today:** RegionPainInputView.allRegions hard-codes keys like 'core', 'left_upper_thigh', 'left_lower_leg' — but the body map uses 'abdomen', 'left_thigh', 'left_calf_shin'. The two lists have drifted, so pain logged here may never line up with what the body map / analysis uses, leaving gaps in charts and recovery insights.
- **Proposal:** Source RegionPainInputView's list from the same canonical BodyRegion definitions the 3D map uses (or a shared constant), so labels and keys stay in lockstep.

### 20. Body map opens cold with no way to reuse last assessment's regions
`low impact` · `medium effort` · `engagement` · `ios/PT-Helper/PT-Helper/Views/BodyMap3DView.swift:67, 192-234`

**Pitch:** When someone with a recurring problem area comes back to assess again, the body map opens completely blank and they re-tap the same spot every time. A one-tap 'same areas as last time' shortcut lets returning users jump straight in, making the app feel like it remembers them and respecting the repeat nature of rehab.

- **Today:** Every time the body map opens, it shows 'No areas selected' from a blank slate. There's no 're-assess the same area' shortcut inside the map, so a chronic sufferer re-selects and re-answers everything from zero on each visit.
- **Proposal:** Pre-seed or one-tap-restore the most recently assessed region(s) (a 'Same areas as last time' chip in the pills strip) so returning users with recurring pain jump straight to the wizard.

### 21. Disabled Continue button gives no reason or nudge
`low impact` · `small effort` · `copy` · `ios/PT-Helper/PT-Helper/Views/BodyMap3DView.swift:685-713`

**Pitch:** On the 'Where does it hurt?' map, the Continue button stays greyed out until you pick an area, but nothing tells you that — you can be left tapping a dead button. Making the button say exactly what to do removes a moment of confusion at the very first step of using the app.

- **Today:** When no region is selected, Continue is greyed out and the bottom row just reads '0 area(s) selected.' Nothing tells the user how to enable it; a first-timer who doesn't realize the first tap only zooms can stare at a dead button.
- **Proposal:** Replace the disabled state with a self-explaining prompt ('Select where it hurts to continue') and fix the grammar of '0 area(s) selected' to 'No areas selected yet.'

### 22. Two unused legacy body-map components still ship
`low impact` · `small effort` · `structure` · `ios/PT-Helper/PT-Helper/Views/BodyMapView.swift:3, ios/PT-Helper/PT-Helper/Views/ZoneSelectionPanel.swift:5`

**Pitch:** Two leftover screens from the body-map feature are built into the app but never shown to anyone. Removing them ships the app a little leaner and stops the team wasting time maintaining or accidentally 'fixing' screens nobody can reach.

- **Today:** BodyMapView.swift (the 2D map) is never presented; all entry points use BodyMap3DView. ZoneSelectionPanel.swift is also dead — BodyMap3DView uses an inline zoneRegionStrip, and the only reference to ZoneSelectionPanel is a stale comment. Both compile and ship but render nothing.
- **Proposal:** Delete BodyMapView.swift and ZoneSelectionPanel.swift (or wire BodyMapView in as a 2D fallback behind a capability check) and remove the stale comment at BodyMap3DView.swift:986.


## Trust & clarity of AI results
_The analysis screens overpromise, lead with disclaimers, hide the safety work the app actually does, and show raw confidence numbers the rest of the app deliberately suppresses — undermining trust right where it matters most._

### 23. Onboarding promises 'real-time' analysis and 'professional-grade PT' the app doesn't deliver
`medium impact` · `small effort` · `trust-safety` · `ios/PT-Helper/PT-Helper/Views/IntroCarouselView.swift:170, 263 vs. DisclaimerView.swift:31-39 and FormAnalysisView.swift:72,154-157`

**Pitch:** Onboarding tells users the app gives 'real-time' form analysis and 'professional-grade physical therapy,' but the app actually records a video then reviews it, and our own disclaimer says it's an educational tool, not a medical device. Rewording two screens keeps the messaging compelling while reducing the regulatory and trust risk of overpromising medical capability in a health app.

- **Today:** The carousel claims 'Our AI analyzes your form in real-time… Professional-grade physical therapy in the palm of your hand.' But form analysis is record-then-process, not real-time, and the very next screen's Disclaimer states this is an 'Educational Tool Only… not a medical device.' The marketing and the legal text contradict each other and the product.
- **Proposal:** Align onboarding copy with the product and disclaimer: drop 'real-time' (say 'AI reviews your recorded form') and soften 'professional-grade physical therapy' to defensible language like 'rehab guidance built on clinical protocols.'

### 24. Build Rehab Plan CTA can sit directly under an urgent red-flag warning
`medium impact` · `small effort` · `trust-safety` · `ios/PT-Helper/PT-Helper/Views/AnalysisResultView.swift:28-44, 354-364`

**Pitch:** When our analysis flags a symptom that could need urgent care, the app shows a red warning and then offers a big 'Build Rehab Plan' button right below it — so a user with a potentially serious issue can start a self-guided program in the same moment we tell them to see a doctor. Making the app act consistently with its own warnings meaningfully reduces a real safety and liability concern.

- **Today:** When a red flag is present, the screen shows a danger banner ('Seek immediate medical attention') and then still presents a prominent primary 'Build Rehab Plan' button at the bottom with no acknowledgement of the warning. The plan CTA is unconditional regardless of red-flag severity.
- **Proposal:** When an AI or app red flag is present, soften or gate the rehab-plan CTA — demote it to secondary styling, add a 'We recommend seeing a clinician first' note, or require an acknowledgement tap before generating a self-rehab program.

### 25. Results screen leads with disclaimers/warnings before showing any answer
`medium impact` · `small effort` · `flow` · `ios/PT-Helper/PT-Helper/Views/AnalysisResultView.swift:26-46`

**Pitch:** After waiting for the analysis, users should see their actual result first, not scroll past a legal disclaimer to reach it. Genuine safety alerts still stay pinned at the top, but the everyday experience leads with the answer people came for, so the result feels like the payoff rather than fine print.

- **Today:** The result scroll renders red-flag alerts, the info disclaimer banner, and a validation-caution banner BEFORE the 'What We Found' summary and condition cards. In the common no-red-flag case, the first thing a user sees after waiting is a disclaimer banner, not their result.
- **Proposal:** Keep emergency/red-flag alerts pinned at top, but for the normal path move the standing info disclaimer below the summary/condition cards (or collapse it to one line) so the user's actual answer is the first thing they read.

### 26. Dashboard shows raw confidence percentages the rest of the app deliberately hides
`medium impact` · `small effort` · `trust-safety` · `ios/PT-Helper/PT-Helper/Views/Dashboard/DashConfidenceChart.swift:25, DashDifferentialsTable.swift:57, AnalysisDashboardView.swift:122`

**Pitch:** Everywhere it matters, the app intentionally never shows a '72% confident' diagnosis — it softens the AI's guess into 'Strong / Possible / Less Likely' and reminds people to see a clinician. But the analytics dashboard slipped through and still shows the raw numbers, which makes the app look like it's diagnosing. Making the dashboard speak the same careful language keeps our medical-safety promise consistent on every screen.

- **Today:** The main results screen translates AI confidence into qualitative capped 'Match Strength' labels and explains numbers are hidden because AI should be verified by a professional. But the Dashboard shows the same conditions as raw percentages — a 'Confidence Breakdown' bar chart with '72%' annotations and a '72%' stat — making the app look like it's diagnosing.
- **Proposal:** Make the Dashboard speak the same language: replace raw % with the Match Strength label, or at minimum re-title 'Confidence' to 'Match Strength' and apply the same 85%-cap caveat and info affordance.

### 27. Invisible verification rigor — no trust badge for the two-call + 6-step pipeline
`medium impact` · `small effort` · `trust-safety` · `ios/PT-Helper/PT-Helper/Views/AnalysisResultView.swift:62-66, 176-184`

**Pitch:** Our injury results quietly run a second AI pass that argues against its own first answer, plus a 6-step safety screen — but users see none of it, so the screen looks like one quick AI guess. A small 'Reviewed by a second AI pass + safety checks' badge lets people actually see why our results are more trustworthy than a single chatbot answer, at almost no engineering cost.

- **Today:** The only explanation of confidence is a tappable info alert ('capped at 85% because AI should be verified'). Nothing on screen shows that the app ran a two-call devil's-advocate verification pipeline and 6-step validation — all that rigor is invisible, so results look like one quick AI guess.
- **Proposal:** Surface the verification work as a lightweight trust badge ('Reviewed by a second AI pass + safety checks') linking to a short explainer, reusing work the app already performs and the visual pattern already used on rehab plans.

### 28. Loading screen step labels don't match what the AI actually does
`medium impact` · `small effort` · `copy` · `ios/PT-Helper/PT-Helper/Views/AnalyzingView.swift:211-243`

**Pitch:** During the wait, the app secretly runs a multi-step safety check on the AI's answer — but the progress label calls that step 'Generating recommendations,' hiding the one thing that builds trust. Relabeling it 'Running safety checks' lets users see the app double-checking the AI, and softening the hardcoded '10-20 seconds' means a slow response doesn't make the app feel broken.

- **Today:** The third backend stage is .validating but its row reads 'Generating recommendations' even though the system is running the 6-step safety/validation pipeline. The header also hardcodes 'this usually takes 10-20 seconds.'
- **Proposal:** Rename the third step to 'Running safety checks' / 'Checking for red flags' (a real trust signal), and soften the hardcoded time estimate unless telemetry supports it.

### 29. AI-generated self-care guidance is collected but never shown
`low impact` · `small effort` · `feature` · `ios/PT-Helper/PT-Helper/Models/PainAssessment.swift:87; AnalysisResultView.swift:210-255`

**Pitch:** When the app shows possible explanations for your pain, it already generates a quick 'here's what to do about it' tip for each — but that tip is hidden and never reaches you. Surfacing it right in the results gives an immediate, actionable answer to 'so what do I do now?' instead of waiting until you build a full plan.

- **Today:** Every condition the AI returns includes a populated howToManage field (the server prompt requires it) that is decoded and stored, but the expanded condition card only renders explanation, whatItMeans, and nextSteps. howToManage is rendered nowhere.
- **Proposal:** Add a 'How to manage this' section to the expanded condition card, mirroring the existing styling used for 'What's happening', surfacing the howToManage text.

### 30. Clinical jargon shown as a permanent subtitle with no explanation
`low impact` · `small effort` · `copy` · `ios/PT-Helper/PT-Helper/Views/AnalysisResultView.swift:156-162`

**Pitch:** When the app shows what might be going on, it now leads with plain English instead of an intimidating medical term sitting right under it. Worried users see a name they understand first, with the clinical label clearly marked as the 'medical term' rather than reading like a scary diagnosis — keeping the experience calm exactly when people are most anxious.

- **Today:** Each condition card shows the friendly commonName as the title and the raw clinical conditionName ('Subacromial impingement syndrome') directly underneath as an unlabeled grey subtitle — an intimidating medical term with no context.
- **Proposal:** Prefix it for context ('Medical term: …') or de-emphasize it into the expanded detail rather than always-visible, and/or pair it with the plain-language definition.


## Motivation, habit-building & retention
_The app already tracks streaks, achievements and reminders behind the scenes — but never celebrates wins, two notification toggles do nothing, and there's no nudge during the make-or-break first week, so the habit loop never closes._

### 31. Earned achievements unlock completely silently — celebration is wired up but never shown
`medium impact` · `small effort` · `engagement` · `ios/PT-Helper/PT-Helper/Services/StreakService.swift:12,79,144 (newlyEarned/clearNewlyEarned); no consumer in any View`

**Pitch:** When someone hits a 7-day streak or their 50th session, the app quietly records it and the user never finds out unless they dig two screens deep. We'd pop a celebratory card with the badge name, a little animation, and a satisfying buzz the instant it's earned — turning an invisible reward into the 'You just earned Week Warrior!' moment that makes people proud, keeps them coming back, and is worth sharing. Most of the code already exists.

- **Today:** StreakService publishes newlyEarned and exposes clearNewlyEarned() commented 'call after displaying celebration' — but no view anywhere observes it (only unit tests reference it). Achievements are silently marked earned in Firestore; the user only sees a lock flip to a checkmark if they navigate two taps deep into AchievementsView.
- **Proposal:** Add an app-level celebratory overlay/toast (the existing CelebrationOverlay scale+opacity, achievement icon + title, success haptic) on newlyEarned != nil, ideally on the workout summary and/or app foreground, then call clearNewlyEarned(). The wiring is ~90% built.

### 32. Workout completion screen ignores the streak and achievements it just earned
`medium impact` · `small effort` · `engagement` · `ios/PT-Helper/PT-Helper/Views/GuidedWorkoutSummaryView.swift:140-163, 216-237; ViewModels/WorkoutViewModel.swift:95-97`

**Pitch:** When you finish a workout, the app quietly bumps your streak and can unlock a badge — but the celebration screen never tells you, and looks identical on day 1 and day 30. Showing 'You're on a 5-day streak — don't break the chain!' and popping any badge at the exact moment users feel proudest gives them a concrete reason to come back tomorrow. The data already exists; we just surface it at peak motivation.

- **Today:** saveSession() runs updateStreak + checkAchievements — so the streak just incremented and a badge may have unlocked — but the summary only shows a generic trophy, plan name, and a Duration/Completed/Skipped grid. The streak count and any newly-earned achievement are updated silently. The user sees the same screen on day 1 and day 30.
- **Proposal:** On the summary, read StreakService.shared.streakData.currentStreak and newlyEarned and surface them inline — a streak chip in the celebration header ('5 days in a row!') and a badge/toast for new achievements, scaling the celebration with the milestone. Reset newlyEarned after showing.

### 33. 'Inactivity Nudges' and 'Re-Assessment Prompts' toggles do nothing
`high impact` · `medium effort` · `engagement` · `ios/PT-Helper/PT-Helper/Views/SettingsView.swift:142-184; ios/PT-Helper/PT-Helper/Services/NotificationService.swift`

**Pitch:** Settings offers users 'Inactivity Nudges' and 'Re-Assessment Prompts' switches, but flipping them does nothing — no reminder ever gets sent. Making them real means people who haven't exercised in a few days get a friendly nudge back, and get reminded to re-check their pain. For a rehab app where people quietly drop off once pain eases, this is the most direct way to win lapsed users back.

- **Today:** Settings presents three notification toggles, but NotificationService only ever schedules weekly plan workout reminders. There's zero code to schedule an inactivity 'come back' notification or a re-assessment reminder — two of the three toggles are decorative, flipping a UserDefaults key nothing reads.
- **Proposal:** Implement an inactivity nudge (reschedule a local notification N days out on background/save, cancelled whenever the user works out) gated behind inactivityNudgesEnabled, and the same pattern for re-assessment at plan midpoint/completion.

### 34. No first-workout / activation nudge during the make-or-break first week
`high impact` · `medium effort` · `engagement` · `ios/PT-Helper/PT-Helper/Services/NotificationService.swift:82-117`

**Pitch:** The app only reminds users to exercise after they've built a full plan — so the people most likely to drop off (just signed up, got their analysis, haven't started) hear nothing during the make-or-break first days. A 'your recovery plan is ready' nudge plus a gentle day-2/3 follow-up brings brand-new users back during the exact window when most of them quit.

- **Today:** All reminder scheduling is keyed to an existing RehabPlan's weeklySchedule. A user who finishes onboarding and gets an analysis but hasn't started a plan receives zero reminders — the crucial first-week activation window has no notification touchpoints at all.
- **Proposal:** Add a lightweight activation nudge for users with an analysis but no started plan ('Your recovery plan is ready — start your first session') plus a day-2/3 follow-up if they haven't worked out, independent of plan scheduling.

### 35. Plan reminder notifications are generic and ignore the streak
`medium impact` · `small effort` · `copy` · `ios/PT-Helper/PT-Helper/Services/NotificationService.swift:96-100`

**Pitch:** Every workout reminder says the exact same thing no matter whether you're on day 1 or day 30. Making it speak to what you'd lose by skipping ('Keep your 6-day streak alive — about 12 minutes today') and rotating the wording makes reminders far more likely to get tapped instead of swiped away — a small copy change on a channel we already own.

- **Today:** Every scheduled reminder uses identical static copy — 'Time for your exercises!' and '<Plan> — N exercise(s) scheduled today' — never referencing streak, progress, or personal stake. Same words whether you're on a 1-day or 30-day streak.
- **Proposal:** Personalize and rotate the copy with streak stakes ('Keep your 6-day streak alive — today's session takes ~12 min', 'You're 1 day from Week Warrior'), varying the message so it doesn't read as a robotic alarm.

### 36. Recovery digest evaporates on every app restart and never auto-surfaces
`medium impact` · `medium effort` · `engagement` · `ios/PT-Helper/PT-Helper/ViewModels/RecoveryInsightsViewModel.swift:34-35, 68-71, 80-84; ios/PT-Helper/PT-Helper/Views/RecoveryInsightsCardView.swift:13-24, 30-57, 167-175`

**Pitch:** The AI recovery digest your app spends a real API call to generate vanishes the moment someone reopens the app, and it only runs at all if they scroll down and tap a button. We'd save it and bring it back instantly, and generate it automatically once someone has logged enough workouts — so users open the app to find fresh, personalized coaching waiting. That turns a feature most people never discover into a recurring weekly reason to come back.

- **Today:** The generated recovery insight lives only in @Published var insight ('In-memory only — resets on app restart'). It's also gated behind a manual 'Generate Weekly Digest' tap with no proactive generation. So on every launch the digest is gone and re-gated behind a tap, and the costly AI result is one most users see only once.
- **Proposal:** Persist the last RecoveryInsight (UserDefaults or Firestore) with its date and rehydrate on launch; auto-generate (respecting the 1-hour throttle) once eligibility is met, and add a 'New digest ready' indicator when a week has passed.

### 37. 'pain_improved' achievement can never be earned
`low impact` · `medium effort` · `engagement` · `ios/PT-Helper/PT-Helper/Models/Achievement.swift:22 vs Services/StreakService.swift:60-75`

**Pitch:** We added a 'Progress!' badge that celebrates the thing patients actually care about — pain going down over two weeks — but the code that hands out badges was never taught how to award it, so it sits locked forever. Wiring it up turns the app's most meaningful reward from a dead padlock into a real moment of encouragement that shows the program is working.

- **Today:** The catalog ships a 7th achievement, 'Progress! — Average pain decreased over 2 weeks,' but checkAchievements has no 'pain_improved' case, so it hits default: break and is impossible to unlock — permanently a locked padlock.
- **Proposal:** Implement the evaluation (compare 2-week rolling average pain from sessions and award it) — preferable since it's the most therapeutically meaningful badge — or remove it from the catalog.

### 38. Streak and personal-best are hidden in a tiny toolbar badge
`medium impact` · `small effort` · `engagement` · `ios/PT-Helper/PT-Helper/Views/ProgressTab.swift:450-481, 556-578; Models/Achievement.swift:28-29`

**Pitch:** The Progress screen leads with 'Total Minutes' — a number nobody opens the app to see — while the day-streak they're actually building is buried as a tiny flame in the corner. Moving the streak front-and-center and adding a 'personal best' moment turns the Progress tab into a reason to come back tomorrow instead of just a logbook.

- **Today:** The Progress tab's prominent 3-up stats are Sessions, Avg Pain, Total Min. The streak only appears as a small flame badge in the nav toolbar, and longestStreak (personal best) is never shown. There's no celebration when a streak grows or pain improves.
- **Proposal:** Promote the current streak into the summary stat row (replacing the least motivating 'Total Min'), surface longestStreak as a 'personal best' callout when the current streak nears or beats it, and add a brief celebratory state when pain drops week-over-week.


## Wellness flow gaps
_The wellness path promises habits it never delivers, re-asks data it already has, forces full forms per goal, and ends without a path into the plan it just built — making a fully-built feature feel like a fragile afterthought._

### 39. Wellness plan promises 'habits' but delivers only exercises
`medium impact` · `medium effort` · `feature` · `ios/PT-Helper/PT-Helper/ViewModels/WellnessPlanViewModel.swift:8-13, 272; ios/PT-Helper/PT-Helper/Views/WellnessPlanView.swift:48,70`

**Pitch:** The wellness flow tells users 'Creating personalized exercises and habits' but only hands them an exercise list — any habit advice gets buried in a notes paragraph or disappears. A real 'Daily Habits' section (a screen curfew for sleep, hourly posture check-ins) makes the wellness path deliver the behavior-change coaching it promises, instead of feeling like a re-skinned injury workout. This is what makes our proactive-health positioning ring true.

- **Today:** The generating screen says 'Creating personalized exercises and habits…' and the prompt asks for an 'exercise and habit plan,' but the response model only decodes planName, exercises, totalWeeks, and notes — no habits field. The rendered plan shows only exercise cards; promised daily habits / micro-practices never appear (at best buried in the notes blob).
- **Proposal:** Add a structured dailyHabits field to AIWellnessPlanResponse and render a dedicated 'Daily Habits' card section, or if habits are out of scope, change the copy and prompt to stop promising them. Structured habits is what makes wellness feel distinct from a rehab plan.

### 40. Multi-goal wellness intake forces a full 9-section form per goal
`medium impact` · `medium effort` · `flow` · `ios/PT-Helper/PT-Helper/Views/WellnessDetailView.swift:37-47, 377-419`

**Pitch:** If someone picks three wellness goals to get a thorough plan, the app makes them fill out the same long nine-question form three times — including person-level questions like 'how motivated are you' that don't change between goals. Letting shared answers carry over means picking more goals no longer means triple the typing, so the people most invested in getting better stop getting punished with the longest forms.

- **Today:** Selecting multiple goals walks the user through the same nine sections once per goal. Several answers (motivation, commitment, prior attempts, daily context) are person-level, not goal-level, yet must be re-entered for each goal. There's no 'apply to all' affordance like the pain flow.
- **Proposal:** Split the form into person-level questions asked once and goal-specific questions asked per goal, or add an 'Apply my answers to remaining goals' button mirroring the pain flow's pattern.

### 41. Saving a wellness plan dead-ends — no path into the workout it just built
`medium impact` · `small effort` · `engagement` · `ios/PT-Helper/PT-Helper/Views/WellnessPlanView.swift:24-28, 230-246`

**Pitch:** When someone finishes building a wellness plan, the app just says 'saved — find it in the My Plan tab' and stops, forcing them to hunt for the plan they just made. A one-tap 'Start My First Workout' button at that exact moment captures users at their most motivated point and makes them far more likely to complete session one — the strongest signal they'll stick with the app.

- **Today:** After 'Save Wellness Plan', the only feedback is an alert: 'Your wellness plan has been saved. You can find it in the My Plan tab.' with one 'OK'. There's no 'Start First Workout' or jump-to-plan action — the user must dismiss, back out of the nav stack, switch tabs, find the plan, and start it. The momentum from assess→analyze→build is dropped at the finish line.
- **Proposal:** Add a primary 'Start My First Workout' (or 'Go to My Plan') action to the save-success alert or as a button after save, deep-linking into the saved plan / guided workout, with 'Done' as secondary.

### 42. Wellness has no persistent re-entry card, unlike pain's 'Last Analysis'
`medium impact` · `medium effort` · `structure` · `ios/PT-Helper/PT-Helper/Views/AssessTab.swift:103-121`

**Pitch:** If you start the wellness check-in and get interrupted — or finish it but don't immediately build a plan — your answers vanish and you start over. The pain side already remembers your last analysis; giving wellness the same 'Resume' card makes it feel like a real, first-class feature you can return to, not a fragile quiz that punishes you for closing the app.

- **Today:** A completed pain analysis persists as a 'Your Last Analysis' card so users can re-enter results across relaunches. There's no equivalent for an in-progress or completed wellness assessment — if a user starts the multi-goal intake and leaves, or finishes analysis but doesn't build a plan, there's no re-entry point. Wellness is treated as a one-shot.
- **Proposal:** Add a parallel 'Your Wellness Goals' / 'Resume Wellness Assessment' card (and/or persist the last WellnessAnalysisResult the way AnalysisResultStore persists pain results) so wellness has the same recoverability as pain.

### 43. Wellness analysis failures have no offline-aware messaging
`medium impact` · `small effort` · `trust-safety` · `ios/PT-Helper/PT-Helper/Views/WellnessAnalyzingView.swift:113-150; ios/PT-Helper/PT-Helper/ViewModels/WellnessAnalysisViewModel.swift:143-160`

**Pitch:** If the wellness plan fails to generate — even just because the phone briefly lost signal — users see a confusing technical error with no hint of what went wrong. Detecting offline state and showing a clear 'you appear to be offline, reconnect and try again' message tells people it's their connection, not a broken app, so they simply retry.

- **Today:** On any failure the screen shows 'Analysis Failed' with the raw error.localizedDescription. There's no network-aware messaging — a dropped connection surfaces the same opaque technical string as a server schema rejection, and the error view never hints it might be connectivity.
- **Proposal:** Check NetworkMonitor.isConnected in the failure path and show a tailored 'You appear to be offline — reconnect and try again' vs a generic 'Something went wrong on our end' for server errors, instead of echoing localizedDescription.

### 44. Wellness intake re-asks the time commitment it already collected
`low impact` · `small effort` · `flow` · `ios/PT-Helper/PT-Helper/Views/WellnessDetailView.swift:217-229; ios/PT-Helper/PT-Helper/Views/WellnessResultView.swift:266-276`

**Pitch:** When setting up a wellness plan, we ask 'how much time can you give per day?' early, then ask basically the same question again before building — and throw away the first answer. Carrying it forward so the second screen comes pre-filled means one less tap and a setup that feels like the app remembers what you told it.

- **Today:** The per-goal detail form asks 'How much time can you dedicate daily?' (5/10/15/20/30+ min), then after analysis the 'Build My Wellness Plan' sheet asks 'Session Length' again (15/30/45 min) on a different scale. The user answers the same question twice and the two are never reconciled.
- **Proposal:** Pre-select the Session Length chip from the daily CommitmentLevel already given (map 5-10→15, 15-20→30, 30+→45), or drop one of the two questions. At minimum default the sheet selection.

### 45. Goal cards lack descriptions and the button says 'Continue with 0 Goals'
`low impact` · `small effort` · `minor-design` · `ios/PT-Helper/PT-Helper/Views/WellnessGoalPickerView.swift:80-134, 165-179`

**Pitch:** On the wellness goal picker, a short plain-English line under each goal lets people choose with confidence instead of guessing from a two-word label, and the button gently says 'Select a goal to continue' instead of the confusing 'Continue with 0 Goals' — a friendlier first step that helps people start on the plan that fits them.

- **Today:** Each goal card shows only an icon and a short title ('Work with Equipment', 'Core & Balance') with no description, so titles are ambiguous about what the plan does. The continue button reads 'Continue with 0 Goals' when nothing is selected (disabled), which is awkward copy to render at all.
- **Proposal:** Add a single-line subtitle under each goal title, and when zero goals are selected swap the button label to 'Select a goal to continue.'

### 46. Dead placeholder ViewModel constructed in the goal picker
`low impact` · `small effort` · `performance` · `ios/PT-Helper/PT-Helper/Views/WellnessGoalPickerView.swift:8-15, 183-188`

**Pitch:** A leftover, never-used object is created every time someone opens the wellness goal picker, doing no work. Removing it makes the screen a touch leaner and eliminates a confusing 'placeholder' that could trick a future developer into wiring the screen to an empty user profile by mistake. Pure cleanup — no behavior change.

- **Today:** WellnessGoalPickerView declares a @StateObject viewModel initialized with an empty placeholder UserProfile ('will be replaced when navigating'). It's never read — the real ViewModel is built on demand in createViewModel(). The placeholder allocates a WellnessAnalysisViewModel and its API dependency on every appearance for nothing.
- **Proposal:** Delete the unused @StateObject placeholder and rely solely on createViewModel(), removing a misleading dead object and the wasted allocation.


## Guided workout & rehab plan experience
_The workout flow has timer bugs, missing hold timers, forced full-screen rests, inverted destructive buttons, and a plan-generation wait far weaker than the analysis screen — friction on the app's most-repeated actions._

### 47. 'End Workout' confirmation gives the destructive Discard option safe styling
`medium impact` · `small effort` · `trust-safety` · `ios/PT-Helper/PT-Helper/Views/GuidedWorkoutView.swift:88-99`

**Pitch:** When you tap End mid-workout, the button that saves your progress is colored red (the universal 'danger' color), while the button that throws your workout away looks perfectly safe. Swapping the colors means no more accidentally losing a workout you just finished — the effort that feeds your progress charts and streak stays intact.

- **Today:** The End-Workout alert gives 'End & Save' the destructive (red) role while 'Discard Workout' — the genuinely irreversible action — has no role and renders as a normal blue button. The danger cue is on the safe action and absent from the destructive one.
- **Proposal:** Swap the roles so 'Discard Workout' carries the destructive red styling and 'End & Save' is a normal action, or relabel to 'Save & Finish' / 'Discard Without Saving' for clarity.

### 48. Rehab plan generation — the slowest AI call — has the weakest loading screen
`medium impact` · `small effort` · `engagement` · `ios/PT-Helper/PT-Helper/Views/RehabPlanView.swift:343-377`

**Pitch:** When the app builds your personalized rehab plan — its longest wait, which can include validation retries — you just stare at a spinner with no sense of progress, right when you're most eager for results. Giving it the same friendly treatment the symptom-analysis screen already has (a 'usually takes about X seconds' countdown plus simple progress steps) reduces the chance people give up or force-quit seconds before their plan appears.

- **Today:** generatingView is just a pulsing dumbbell, 'Building Your Plan', a one-line subtitle, and a bare spinner — no elapsed-time counter, no 'usually takes X seconds' reassurance, no step indicators. AnalyzingView (a shorter call) has all of that. Plan generation can run validation retries and is one of the longest waits in the app.
- **Proposal:** Bring generatingView up to AnalyzingView's standard: add the elapsed-time hint and step rows ('Selecting exercises', 'Checking contraindications', 'Personalizing for your level'), reusing the AnalysisStepRow pattern.

### 49. Rehab plan reveal snaps in with no haptic or 'done' moment
`medium impact` · `small effort` · `engagement` · `ios/PT-Helper/PT-Helper/Views/RehabPlanView.swift:50-148; ViewModels/RehabPlanViewModel.swift vs AnalyzingView.swift:104-117`

**Pitch:** When the app finishes building your rehab plan, the reward should match the diagnosis screen: a gentle success buzz, a brief 'Your Plan Is Ready!' celebration, and a smooth fade-in instead of the plan abruptly popping on. It makes the most valuable moment in the whole flow feel earned, and removes a jarring inconsistency where the lower-stakes diagnosis screen felt more polished than the payoff.

- **Today:** When the AI finishes a plan, isGenerating flips false and the full plan ScrollView simply appears — no transition, no success haptic, no completion flash. The parallel AnalyzingView fires a .success haptic and shows an 'Analysis Complete!' overlay. The plan path has none of it.
- **Proposal:** Mirror AnalyzingView: on completion fire a .success notification haptic and briefly show a 'Your Plan Is Ready!' CelebrationOverlay, and wrap the plan content in a fade+move transition so it eases in.

### 50. No in-set timer for timed-hold exercises
`medium impact` · `medium effort` · `feature` · `ios/PT-Helper/PT-Helper/Views/GuidedWorkoutView.swift:257-308, 199-204; Models/RehabPlan.swift:46`

**Pitch:** For exercises you hold instead of count — planks, wall sits, stretches — the app now runs the clock for you with an on-screen countdown and a buzz when time's up, instead of making you count seconds in your head while holding a tough position. It turns the guided workout into a real coach for timed holds and helps people hold each rep for the full prescribed duration.

- **Today:** RehabExercise.reps is free-text that can be rep-based ('10 reps') or hold-based ('30 seconds'). During a guided workout the bottom bar always shows 'Complete Set N' and a static reps badge — there's no countdown for timed holds. Rest gets a 220pt ring, but a 30-second plank gives nothing to time against. ExerciseDetailView even has a timerView for 'seconds' reps that the guided workout lacks.
- **Proposal:** Detect hold/timed exercises (reps contains 'second'/'hold', the heuristic already in ExerciseDetailView) and show a start/countdown timer inline with a haptic at completion, instead of a passive 'Complete Set' tap.

### 51. Rest timer drifts and can't finish in the background
`medium impact` · `medium effort` · `performance` · `ios/PT-Helper/PT-Helper/ViewModels/GuidedWorkoutViewModel.swift:368-405, 414-421`

**Pitch:** During a workout, if you glance at a text or lock your phone while resting, the rest timer freezes and you never get the 'rest's over' buzz — you come back to a stuck clock. Fixing the timer so it keeps counting accurately with the screen off and still alerts you means you can put your phone down between sets and trust the app to tell you when to go again.

- **Today:** Both rest countdown and elapsed clock are driven by Timer.publish(every:1) with no scenePhase/background handling. When the app is backgrounded or the phone locks during rest, the timer stops firing — the countdown freezes and the completion haptic at 0 never fires. Meanwhile elapsed time is recomputed from Date() on resume, so the two clocks disagree.
- **Proposal:** Anchor the rest countdown to an absolute end-Date (derived from Date() like elapsed time already is), and on scenePhase .active recompute remaining / fire the end transition if it elapsed while backgrounded. Optionally schedule a local notification for rest-end with the screen off.

### 52. Inter-set rest is forced as a full-screen interrupt even for short pauses
`medium impact` · `medium effort` · `flow` · `ios/PT-Helper/PT-Helper/ViewModels/GuidedWorkoutViewModel.swift:154-160; GuidedWorkoutView.swift:363-442`

**Pitch:** Finishing a set always throws you to a full-screen rest timer, even for gentle exercises where you don't need a break — so you tap 'Skip Rest' over and over just to keep going. Keeping short between-set pauses lightweight and saving the big rest screen for real breaks between exercises makes easy workouts feel smooth instead of naggy.

- **Today:** Completing any non-final set always routes through the full-screen rest view with a 220pt ring. For light mobility exercises the user is bounced to the rest screen and must tap 'Skip Rest' every set. The rest phase is the same heavyweight full-screen ring whether it's a 10s inter-set pause or a 90s inter-exercise rest.
- **Proposal:** For inter-set rests, keep the user on the exercise screen with a small inline countdown chip (or auto-advance when very short), reserving the full-screen ring for inter-exercise transitions.

### 53. Completion screen trophy bounces once and has no success haptic
`medium impact` · `small effort` · `engagement` · `ios/PT-Helper/PT-Helper/Views/GuidedWorkoutSummaryView.swift:140-163, 225-226`

**Pitch:** Finishing a guided workout is the whole point of the app, but it lands on a silent screen with a trophy that freezes after a single twitch. Greeting users with a celebratory buzz and a livelier animation the instant the summary appears makes finishing feel rewarding right away, which makes coming back tomorrow more tempting.

- **Today:** The summary header shows a static trophy with symbolEffect(.bounce, value: true) — because value is a constant, it bounces once on first render and never again. There's no success haptic when the summary appears; the only .success haptic fires later on Save. So finishing the workout lands with no buzz and a quickly-settling trophy.
- **Proposal:** Fire a .success notification haptic in .onAppear of the summary, drive the bounce off a state flag toggled on appear, and consider a brief confetti burst over the header for the workout-complete peak.

### 54. Swap is the only secondary action with no explanation of what it does
`medium impact` · `small effort` · `flow` · `ios/PT-Helper/PT-Helper/Views/GuidedWorkoutView.swift:312-339; ExerciseSwapSheet.swift:44-112`

**Pitch:** During a workout, the Swap button gives no clue that it's our AI feature for trading a painful exercise for a safe alternative targeting the same body part. A one-line label like 'Trade for a safe alternative' and making the destructive Skip less prominent means people discover and use a genuinely helpful AI feature instead of just skipping exercises and falling off their plan.

- **Today:** 'Swap' sits between 'Form' and 'Skip' as a small circular icon with only the label 'Swap', jumping straight into a reason picker. There's no hint it means 'get an AI-suggested safe alternative for the same body part.' Skip (which permanently drops the exercise) sits right next to it with equal weight and no confirmation.
- **Proposal:** Add a one-line subtitle or first-use tooltip clarifying Swap ('Trade this for a safe alternative'), and de-emphasize the destructive Skip relative to Swap, or add a lightweight confirm/undo for Skip.

### 55. Exercise detail always renders empty 'Form Tips' and 'Contraindications' cards
`medium impact` · `small effort` · `minor-design` · `ios/PT-Helper/PT-Helper/Views/ExerciseDetailView.swift:65-87`

**Pitch:** When an exercise has no listed form tips or safety warnings, the detail screen still shows empty 'Form Tips' and 'Contraindications' boxes with just a header. Making those sections disappear when there's nothing to show looks cleaner and never leaves a blank 'Contraindications' card that could be misread as 'this exercise has no safety concerns.'

- **Today:** formTips and contraindications CardSections render unconditionally. If exercise.tips or contraindications is empty (common for AI-generated/swapped exercises), the card still shows its header and icon with no content — an empty labeled box. Other sections like positionGuide are correctly gated behind content checks.
- **Proposal:** Wrap formTips and contraindications in if !isEmpty guards, matching the existing pattern, so empty sections simply don't appear.

### 56. Post-workout pain prompt lacks reassurance that honesty is safe
`medium impact` · `small effort` · `copy` · `ios/PT-Helper/PT-Helper/Views/GuidedWorkoutSummaryView.swift:41-62`

**Pitch:** Right after a workout we ask 'How do you feel?' on a pain slider but never say why or that a higher number isn't failing — so some users round their pain down to feel like they aced it. One supportive line turns the slider from a graded test into a collaborative check-in, giving us truthful pain data and an app that feels like a coach in your corner.

- **Today:** Immediately after a workout, the summary asks 'How do you feel?' with a 0-10 slider labeled only 'No pain' / 'Severe.' There's no microcopy explaining why it's asked or reassuring that reporting higher pain isn't 'failing' — it looks like a graded test.
- **Proposal:** Add a one-line subtitle: 'Be honest — this helps us adjust your next sessions. Some soreness is normal,' reframing the slider as collaborative tuning rather than self-judgment.

### 57. Set-completion dot fill isn't animated and final set has no distinct flourish
`low impact` · `small effort` · `minor-design` · `ios/PT-Helper/PT-Helper/Views/GuidedWorkoutView.swift:259-285`

**Pitch:** Completing a set will feel smoother and more satisfying: the progress dot fades in with color instead of snapping on, and finishing the final set gets its own celebratory pulse and distinct 'you did it' buzz. Since logging sets is the single most repeated action in a workout, making that moment feel rewarding rep after rep helps people keep coming back.

- **Today:** When a set completes, the dot scales 1.4x and back (nice) with a haptic, but its fill flips from clear to accent instantly with no transition, and the bounce is driven by a manual DispatchQueue.asyncAfter reset that can desync on fast taps. There's no distinct 'final set / exercise complete' beat — the last set looks like any other.
- **Proposal:** Animate the dot fill via withAnimation, and when the final set completes add a stronger beat (all dots pulse + a .success haptic) to mark finishing the exercise versus just a set.


## Empty, loading, error & offline states
_Several screens dead-end with no next step, fetch failures masquerade as 'no data', error UI is inconsistent and scary, and the app never blocks doomed AI calls when it already knows you're offline._

### 58. Offline state is known but never blocks AI actions
`medium impact` · `small effort` · `flow` · `ios/PT-Helper/PT-Helper/Services/NetworkMonitor.swift:11; ViewModels/InjuryAnalysisViewModel.swift:128-189; ViewModels/RehabPlanViewModel.swift:143-179`

**Pitch:** If you're offline and tap Analyze or Generate Plan, the app already knows it can't reach the internet but still makes you stare at a 15-30 second spinner before showing a generic error. Checking connection up front and instantly showing a friendly 'You're offline' message with retry means you never waste time waiting on a request that was doomed from the start.

- **Today:** NetworkMonitor.isConnected is accurate but consumed only by the offline banner in three tab containers. No AI flow checks connectivity before firing. Offline, a user can tap Analyze or Generate Plan, watch a polished 15-30s spinner with 'usually takes 10-20 seconds', and only then hit a generic network error.
- **Proposal:** Before starting any AI call, check NetworkMonitor.shared.isConnected. If offline, skip the spinner and immediately show a friendly 'You're offline — connect to run your assessment' state with a retry.

### 59. Offline banner disappears during the entire assessment + analysis flow
`medium impact` · `small effort` · `flow` · `ios/PT-Helper/PT-Helper/Views/ThreeTabView.swift:17-29, 80-99`

**Pitch:** If your connection drops while you're tapping out where it hurts and filling in symptoms, the app stays silent until the AI request fails at the very end — after you've done all the work. Keeping the 'you're offline' warning visible during the assessment lets you fix your connection before wasting the effort.

- **Today:** The offline banner lives in the tab container's VStack, but the core assessment opens as a fullScreenCover (BodyMap3DView in its own NavigationStack) that covers the tab container. So during body-map selection, pain entry, and the AI analysis — exactly the moments needing a live network — the banner isn't visible.
- **Proposal:** Surface the offline indicator inside the assessment fullScreenCover too (or hoist the banner above the cover) so the warning shows during the one flow most dependent on connectivity.

### 60. Progress 'No Data Yet' empty state is a dead end with no CTA
`medium impact` · `small effort` · `engagement` · `ios/PT-Helper/PT-Helper/Views/ProgressTab.swift:66-73; DesignSystem.swift:396-432`

**Pitch:** New users who open Progress before logging anything hit a flat 'No Data Yet' message with no next step. Adding a clear button like 'Log Your First Workout' turns a dead end into a one-tap on-ramp to their first session — a tiny change that removes a common drop-off point.

- **Today:** When sessions is empty, ProgressTab shows EmptyStateView with 'No Data Yet' but passes no actionTitle/action, even though the component natively supports a button. The only way forward (a 'Log Workout' nav link) renders far below, requiring the user to scroll past a dead-end message.
- **Proposal:** Add an actionTitle/action (e.g. 'Log Your First Workout' to WorkoutSessionView, or 'Start an Assessment'). The component already supports it — a one-argument change.

### 61. Form Check empty state offers no way out
`medium impact` · `small effort` · `flow` · `ios/PT-Helper/PT-Helper/Views/FormCheckTab.swift:104-128`

**Pitch:** When someone opens Form Check before they have a plan, the screen tells them to 'create a rehab plan first' but gives no way to do it — a dead end they must navigate out of themselves. A button right there takes them straight to the assessment, matching how the rest of the app's empty screens work and helping users discover form check instead of bouncing off it.

- **Today:** When the user has no plans, FormCheckTab shows a hand-rolled 'No Exercises Available' state with 'Create a rehab plan first…' — purely informational, no button. The user is told to create a plan but given no tap target to do so.
- **Proposal:** Add a primary button ('Start an Assessment' / 'Create a Plan') routing to the assessment flow via TabSelection like MyPlanTab's empty state does.

### 62. Session-fetch failures masquerade as 'No Data Yet'
`medium impact` · `small effort` · `trust-safety` · `ios/PT-Helper/PT-Helper/Views/ProgressTab.swift:66-73; ViewModels/WorkoutViewModel.swift:35`

**Pitch:** If loading a user's workout history hits a network or server hiccup, the Progress screen falsely says 'No Data Yet' — the exact message a brand-new user sees — making a longtime user fear weeks of logged workouts vanished. Detecting the failure and showing 'couldn't load, pull to retry' reassures people their data is safe and the problem is just temporary.

- **Today:** WorkoutViewModel sets loadError on a failed Firestore fetch, but ProgressTab never reads it. When a fetch fails, sessions stays empty, so a longtime user sees the identical 'No Data Yet' empty state shown to a brand-new account — making them fear their data vanished.
- **Proposal:** In ProgressTab, branch on workoutViewModel.loadError before the isEmpty check and show an error state with retry (the message already says 'pull down to retry', but there's no refreshable on the ScrollView).

### 63. Inconsistent error UI: raw error strings, no retry, scary wifi icon
`medium impact` · `medium effort` · `trust-safety` · `ios/PT-Helper/PT-Helper/Views/MyPlanTab.swift:259-275; ios/PT-Helper/PT-Helper/Views/RecoveryInsightsCardView.swift:37-46`

**Pitch:** When loading plans or recovery insights fails, the app shows a scary wifi icon and confusing technical text with no obvious 'Try Again' — and every error screen looks different. Making them all show a clear, friendly message with one consistent retry button means a momentary hiccup doesn't make the app feel broken or leave people guessing whether it's their connection.

- **Today:** MyPlanTab.errorState always shows a 'wifi.exclamationmark' icon and dumps the raw loadError regardless of cause (a Firestore permission error reads as a wifi problem). RecoveryInsightsCardView shows the error as a tiny caption with no retry. Meanwhile AnalyzingView/RehabPlanView/FormAnalysisView use a consistent triangle + 'Try Again' pattern. Error treatment is fragmented.
- **Proposal:** Standardize a single ErrorStateView (title, message, Retry button) used everywhere, stop hard-coding the wifi icon when the failure may not be connectivity, and always give recovery-insight errors a visible Retry.


## Accessibility & inclusive design
_Custom fonts ignore Dynamic Type, the 3D body map and charts are unreachable by VoiceOver, exercise images and chips lack labels, and color-only cues exclude colorblind users — real ADA gaps for an app whose core demographic skews older._

### 64. 3D body map has no non-visual way to select a region
`high impact` · `medium effort` · `accessibility` · `ios/PT-Helper/PT-Helper/Views/BodyMap3DView.swift:240, 192-228`

**Pitch:** A blind or low-vision user literally cannot get past the very first screen of pain analysis — picking where it hurts requires tapping a 3D model VoiceOver can't read, so the entire app is closed to them. Adding an accessible 'choose from a list' way to select body areas unlocks the whole product for these users and closes a real ADA compliance gap.

- **Today:** Region selection happens entirely by tapping 3D meshes inside a RealityView. There's no accessibility representation of the model, no list/menu fallback; only the reset/clear/continue buttons have accessibility identifiers. A VoiceOver user cannot select 'lower back' or 'left knee' at all — the entire assessment funnel dead-ends at step one.
- **Proposal:** Offer an accessible alternative: a VoiceOver-reachable list of body zones/regions (the same BodyZone/BodyRegion data drives the model) that toggles selection, or expose proxy entities as accessibility elements. At minimum, surface a 'Choose from a list' affordance.

### 65. Custom fonts ignore Dynamic Type app-wide
`high impact` · `medium effort` · `accessibility` · `ios/PT-Helper/PT-Helper/DesignSystem.swift:145-171 plus ~153 .font(.system(size:)) call sites`

**Pitch:** The app shows the same fixed text size no matter how large a user sets their phone's text, so anyone who relies on Larger Text — common among older rehab patients and people with low vision — is stuck squinting. Making every font grow with the system text-size setting removes a real barrier to use and a credibility gap against App Store accessibility standards.

- **Today:** Every AppFonts token is Font.custom(...) with NO relativeTo: parameter, and ~153 view sites use .font(.system(size:)) with hardcoded points. Both produce fonts that do NOT respond to the iOS 'Larger Text' setting. A user who bumps text size in Settings sees the exact same tiny type throughout.
- **Proposal:** Add a relative text style to every AppFonts token (Font.custom('Inter-Regular', size:14, relativeTo:.body)), replace the worst .font(.system(size:)) offenders with semantic styles, and cap with .dynamicTypeSize where layouts would break.

### 66. Dashboard charts are invisible to VoiceOver
`medium impact` · `small effort` · `accessibility` · `ios/PT-Helper/PT-Helper/Views/Dashboard/DashPainTrendChart.swift:25-78, DashConfidenceChart.swift:11-53`

**Pitch:** Blind and low-vision users with VoiceOver hear nothing when they reach the Pain Trend and Confidence charts — the screen reader skips silently past the most motivating part of the app. Adding spoken summaries ('Pain dropped from 6 to 2 over the last 14 days') lets everyone hear their progress, opening a core retention moment to users currently locked out of it.

- **Today:** The Pain Trend and Confidence Breakdown charts carry no accessibilityLabel/Value or chart descriptor. A VoiceOver user hears nothing — the pain-over-time story and confidence percentages are conveyed only by pixels.
- **Proposal:** Add per-mark accessibilityLabel/Value inside the Chart closures and/or an accessibilityChartDescriptor, or a hidden element reading 'Pain dropped from 6 to 2 over the last 14 days.'

### 67. Exercise demonstration images have no description
`medium impact` · `small effort` · `accessibility` · `ios/PT-Helper/PT-Helper/Views/Components/ExerciseImageView.swift:86,100,107`

**Pitch:** Blind and low-vision users hear nothing meaningful at the exercise illustration — the picture showing how to position their body during a rehab workout. A spoken description ('Start position for Glute Bridge') lets VoiceOver users follow the movement instead of guessing, making the core workout usable for screen-reader users in an app where doing an exercise wrong can mean re-injury.

- **Today:** ExerciseImageView renders start/end pose illustrations via Image(uiImage:) with zero accessibility — the dominant image component across 6 screens including the guided workout. The sibling ExerciseImagePagerView DOES add a label + hint, so the pattern exists but wasn't applied to the main component.
- **Proposal:** Mirror the pager: add accessibilityLabel ('Start position for <exercise>' / 'End position') to the images, and mark the decorative compact thumbnail as accessibilityHidden where the name is announced nearby.

### 68. Selectable chips don't tell VoiceOver they're selected
`medium impact` · `small effort` · `accessibility` · `ios/PT-Helper/PT-Helper/DesignSystem.swift:554-574 (ChipButton)`

**Pitch:** VoiceOver users can't hear which goal or filter chips they've tapped — selection shows only as a color change, silent to screen readers and invisible to colorblind users. Adding a spoken 'selected' cue in one shared component lets everyone confirm their picks before generating a plan.

- **Today:** ChipButton (goal pickers, region filters) changes only background and border color when selected, with no .isSelected trait and no state in its label. VoiceOver reads 'Posture, button' identically whether on or off — selection is conveyed by color alone.
- **Proposal:** Apply .accessibilityAddTraits(isSelected ? [.isSelected] : []) (or append ', selected') in ChipButton — a one-place fix that propagates to every chip.

### 69. Pain-level history badge relies on color plus an unlabeled number
`medium impact` · `small effort` · `accessibility` · `ios/PT-Helper/PT-Helper/Views/ProgressTab.swift:259-310`

**Pitch:** In the session-history list, a VoiceOver user just hears a floating '4' with no hint it's a pain rating, and colorblind users can't tell green from red. A single combined spoken label like 'June 12, pain 4 of 10 (moderate), 30 minutes, 5 exercises' makes the recovery log readable and reassuring for everyone.

- **Today:** Each session row shows a green/amber/red circle with the pain number inside, but no combined accessibility element — so VoiceOver reads the pieces separately ('4'… 'June 12'… '30 min') with no statement that 4 is a pain level or what the color band means. The traffic-light severity is color-only.
- **Proposal:** Wrap the row in .accessibilityElement(children: .combine) with a label like 'June 12, pain 4 of 10 (moderate), 30 minutes, 5 exercises', so the number is contextualized and the color meaning is spoken.


## Visual consistency, polish & branding
_The rebrand is half-applied: whole screens still use stock iOS fonts and colors, the shared card/icon/spacing tokens are widely ignored, big numbers render in off-brand fonts, and navigation lacks tactile feedback — making the app feel like two products stitched together._

### 70. Split-brain typography: whole screens never got the rebrand
`medium impact` · `large effort` · `minor-design` · `ios/PT-Helper/PT-Helper/Views/ExerciseSwapSheet.swift, FormAnalysisView.swift, SettingsView.swift; ~344 raw .font + 153 .font(.system(size:)) across Views`

**Pitch:** The app's screens are inconsistent under the hood: some use the new MVVC brand fonts and others — exercise swap, form analysis, settings — still use generic Apple text. Once custom fonts are turned on, that becomes visible and the app looks like two different products stitched together. Sweeping these screens onto shared font tokens makes the whole app feel like one polished, branded experience.

- **Today:** Roughly 500 text elements bypass AppFonts and use raw system fonts. Some screens are fully rebranded (AssessTab, HomeTab); others (ExerciseSwapSheet has zero AppFonts, FormAnalysisView, SettingsView) are 100% system font. Once custom fonts are registered, the app visually splits into 'rebranded' and 'stock iOS' zones.
- **Proposal:** Sweep the un-rebranded screens (ExerciseSwapSheet, FormAnalysisView, SettingsView, WorkoutSessionView, BodyMap3DView, AnalysisResultView) and replace raw fonts with the matching AppFonts token.

### 71. The reusable card style is used in only 3 places out of ~56
`medium impact` · `medium effort` · `structure` · `ios/PT-Helper/PT-Helper/DesignSystem.swift:224 (.cardStyle); only 3 call sites vs 56 hand-rolled cards`

**Pitch:** Cards are the most common building block in the app, but each screen draws its own with slightly different rounding, borders, and shadows, so the UI looks subtly inconsistent screen to screen. Routing them all through one shared card style makes every card match and future tweaks a one-line change — a more polished feel for users, faster restyling for the team.

- **Today:** DesignSystem ships a .cardStyle(elevation:) modifier with 4 calibrated elevations, called only 3 times. 56 places hand-build the card surface with their own background+cornerRadius+stroke+shadow, and the shadow values drift (radius 8/y2 vs opacity 0.14 radius 16/y4 vs the token's 0.06 radius 8/y2).
- **Proposal:** Adopt .cardStyle() on the hand-rolled cards and add a dark-surface variant for the dark gateway/hero cards, standardizing radius, border, and shadow in one place.

### 72. Big stat/timer numbers render in off-brand SF Rounded
`low impact` · `small effort` · `minor-design` · `ios/PT-Helper/PT-Helper/Views/GuidedWorkoutView.swift:382; TimerView.swift:28; WorkoutSessionView.swift:28,71; GuidedWorkoutSummaryView.swift:45,200; RehabPlanView.swift:272; SettingsView.swift:35 — 23 sites`

**Pitch:** The big numbers people stare at most — the rest-timer countdown, summary stats, streak count — show in a generic Apple rounded font instead of our brand typeface. Swapping them to the MVVC display font makes the app feel consistently branded exactly when users pay closest attention. Low-risk polish since the tokens already exist.

- **Today:** 23 places display hero/stat numbers in SF Rounded — the rest-timer countdown, summary stats, Settings avatar initials, re-assessment scores — even though AppFonts.display (Industry-Bold) and AppFonts.statNumber exist precisely for these. In GuidedWorkoutView the 52pt rounded timer sits next to AppFonts.body text.
- **Proposal:** Replace the .rounded stat fonts with AppFonts.display / statNumber (or a new larger Industry-Bold token where 52pt is needed), keeping monospaced only where digit-width stability matters.

### 73. Inline Font.custom calls invent untokenized heading sizes
`low impact` · `small effort` · `structure` · `ios/PT-Helper/PT-Helper/Views/AssessTab.swift:192,236; HomeTab.swift:84,176,221; MyPlanTab.swift:165,191; ProgressTab.swift:468,512; IntroCarouselView.swift:250,329; PainWizardSteps.swift:136,371 — 32 sites`

**Pitch:** Headings are sized with hand-typed numbers that wander a few points from screen to screen, so the same kind of card title is 14pt one place, 16pt another, 18pt elsewhere. Moving to named font sizes makes the type hierarchy consistent and gives designers one place to tune all headings — and a future font swap becomes one edit instead of 32.

- **Today:** Rebranded screens call Font.custom('Industry-Bold', size: N) inline with ad-hoc sizes (13,16,18,20,26,32,38,52). AppFonts only tokenizes 10/11/14/20/24/28/36, so the same conceptual 'card heading' is 14 on one screen and 16 or 18 on others. The font-name string is duplicated 32 times.
- **Proposal:** Add the missing scale steps to AppFonts (headingSm 16, headingMd 18, displayLg 52) and replace the 32 inline calls with tokens, with no literal font-name strings outside DesignSystem.swift.

### 74. Icon-chip corner radius drifts between 6, 7 and 8
`low impact` · `medium effort` · `minor-design` · `ios/PT-Helper/PT-Helper/Views/AdaptiveProgressionBannerView.swift:19 vs :39; NotesView.swift:109, GuidedWorkoutView.swift:596, Dashboard/DashProfileView.swift:123, ProfileReviewStepView.swift:176; ExerciseIllustration.swift:242`

**Pitch:** Those little colored icon tiles next to settings rows, notes, and review steps are rounded by slightly different amounts depending on the screen. One reusable badge component makes every one match exactly, giving a cleaner, more deliberate look — users won't notice any single tile, but the whole interface feels more professionally finished.

- **Today:** The small tinted icon-badge pattern is built with at least three corner radii: hardcoded 7 in five views, 6 in ExerciseIllustration, and the token AppCorners.small (8) elsewhere. AdaptiveProgressionBannerView uses cornerRadius(7) and AppCorners.small two lines apart. No token exists for 6 or 7.
- **Proposal:** Extract a shared IconChip/IconBadge component (icon + tinted background + token radius) used everywhere, settling on AppCorners.small and removing literal 6/7 values.

### 75. Raw dark-surface hex re-typed in IntroCarousel instead of AppColors.darkSurface
`low impact` · `small effort` · `minor-design` · `ios/PT-Helper/PT-Helper/Views/IntroCarouselView.swift:105,120,224,292; DesignSystem.swift:40`

**Pitch:** The very first screens a new user sees use hand-typed color values instead of the shared brand palette. If we ever fine-tune the near-black or red, this welcome screen would silently keep the old shade and look off-brand. Wiring these back to the central palette guarantees the first impression always matches the live brand.

- **Today:** IntroCarouselView re-types Color(red:0.067,green:0.067,blue:0.067) four times as a background — that exact value is already AppColors.darkSurface. It also hardcodes maroon gradient stops not in the palette. This is the first screen new users see.
- **Proposal:** Replace the four dark-surface literals with AppColors.darkSurface, and either add the maroon gradient stops to AppColors or reuse the existing gradients. No bare Color(red:) literals in Views.

### 76. Magic padding numbers scattered through onboarding and key flows
`low impact` · `medium effort` · `minor-design` · `ios/PT-Helper/PT-Helper/Views/IntroCarouselView.swift; SettingsView.swift:88,117; PainWizardSteps.swift; BodyMapView.swift — 65 literal .padding sites`

**Pitch:** Onboarding and a few key flows use a grab-bag of hand-typed spacing numbers instead of the shared scale, so gaps between elements feel subtly uneven screen to screen. Switching to standard tokens makes the layout rhythm consistent and lets us tune the app's density in one place — a touch more polished and intentional.

- **Today:** 65 padding calls use bare CGFloat literals instead of AppSpacing tokens. SettingsView aligns dividers with .padding(.leading, 52) (a magic inset), and IntroCarouselView has 14 literal paddings. AppSpacing defines a full scale these largely don't reference.
- **Proposal:** Replace literal paddings with the nearest AppSpacing token; for derived insets, compute from tokens or add a named constant. Reserve raw numbers for true one-offs.

### 77. Tab bar switches are instant — no haptic, no animation, no feedback on the '+' CTA
`low impact` · `small effort` · `minor-design` · `ios/PT-Helper/PT-Helper/Views/ThreeTabView.swift:242-279`

**Pitch:** Tapping the bottom tabs and the big red '+' will now give a subtle buzz and a small tap animation instead of switching silently — the kind of tiny tactile feedback that makes the app feel more responsive and polished every time you navigate.

- **Today:** The custom FloatingTabBar swaps foregroundColor instantly with no animation or haptic, and the large central red '+' button (the app's primary entry to a new assessment) has only a static shadow — no press scale, no haptic. No feedback generator anywhere.
- **Proposal:** Add a light selection haptic on tab tap and a medium impact on '+'; animate the active-color change with AppAnimations.smooth; give '+' a scaleEffect press animation matching PrimaryButtonStyle.

### 78. AI diagnosis results appear all at once instead of revealing one at a time
`low impact` · `small effort` · `minor-design` · `ios/PT-Helper/PT-Helper/Views/AnalysisResultView.swift:41-43`

**Pitch:** When the app finishes figuring out what might be causing your pain, all the explanations slap onto the screen at the same instant. Revealing them one after another with a smooth fade-in, and having each confidence bar fill up, makes the results feel carefully considered rather than dumped on you — building trust exactly when users are anxiously reading 'what's wrong with me.'

- **Today:** The top-3 condition cards — the headline output of the analysis — render in a plain ForEach with no entrance transition or stagger. After the 'Analysis Complete!' flash, all three cards and their match-strength bars pop in simultaneously and statically.
- **Proposal:** Give each card a staggered fade-and-slide-in (incremental animation delay per index) and animate the match-strength bars filling from 0 to their value, giving the diagnosis a sense of considered arrival.

### 79. AssessmentGrowthBackground is a dead stub that ignores its own input
`low impact` · `small effort` · `engagement` · `ios/PT-Helper/PT-Helper/Views/AssessmentGrowthBackground.swift:3-9`

**Pitch:** Filling out a multi-region pain assessment is a wall of forms. Making the background quietly come to life as you move through each step signals 'you're making progress,' so a chore feels like momentum. The hook is already half-built and wired to the step counter; we only need to finish the visual.

- **Today:** AssessmentGrowthBackground takes a step: Int parameter (callers pass assessment progress) but its entire body is a flat AppColors.pageBackground fill. The step value is never read — it's named and shaped to render a progressive 'growth' visual but does nothing.
- **Proposal:** Either deliver the intended effect — a subtle background that visibly evolves as step increases (growing plant, rising fill, accumulating dots) to reward progress — or delete the parameter and rename to a plain Background to remove misleading dead code.


## Settings, account, legal & safety
_The reminder picker silently corrupts saved times, there's no data export despite the privacy policy promising it, legal docs are 15 months stale, and the emergency Call button can silently fail in a crisis._

### 80. Emergency 'Call' button can silently do nothing on iPad / non-cellular devices
`high impact` · `small effort` · `trust-safety` · `ios/PT-Helper/PT-Helper/Views/Components/EmergencyRedirectView.swift:87-94`

**Pitch:** On the emergency screen that appears when someone may be having a heart attack or stroke, the 'Call Emergency Services' button does nothing on iPads and other devices that can't make calls — and the number is never shown. Always displaying the number as large readable text with clear guidance means the user is never left staring at a dead button in a crisis. A small change that closes a real safety gap on the highest-stakes screen in the app.

- **Today:** callEmergencyServices() opens tel://911 only if canOpenURL succeeds. On an iPad or any non-dialer device it returns false and the tap does nothing — no dialer, no error, no fallback, no displayed number. A user just told they may have a cardiac/stroke/cauda-equina red flag taps the big red 'Call Emergency Services' button and gets zero feedback. 911 is also hardcoded US-only.
- **Proposal:** When canOpenURL is false, fall back to showing the emergency number(s) as large selectable text with guidance ('Call 911 from a phone / dial your local emergency number'). Always render the number so it's available even when dialing fails.

### 81. Reminder time picker always shows current time, not the saved time
`medium impact` · `small effort` · `flow` · `ios/PT-Helper/PT-Helper/Views/SettingsView.swift:17,103-112`

**Pitch:** When you set a daily reminder time and come back to Settings, the picker now correctly shows the time you actually picked instead of resetting to the current clock time. This stops an accidental tap from silently changing your reminder to the wrong time, keeping the daily nudges that drive exercise adherence reliable and trustworthy.

- **Today:** The 'Reminder Time' DatePicker is bound to @State reminderDate = Date() (current clock time) with no .onAppear seeding it from the persisted reminderHour/reminderMinute. A user who set 8:00 AM sees the picker showing the current time, and any touch overwrites their real 8:00 AM with whatever the picker showed.
- **Proposal:** Add an .onAppear that sets reminderDate from the saved hour/minute, so the picker always reflects the user's actual reminder time and a glance or accidental tap can't silently change it.

### 82. No 'Export My Data' control despite privacy policy granting portability rights
`medium impact` · `medium effort` · `trust-safety` · `ios/PT-Helper/PT-Helper/Views/SettingsView.swift:235-256; Models/LegalContent.swift:85-91`

**Pitch:** The privacy policy promises users they can access and request their data, but there's no button to actually download it. An 'Export My Data' option that packages your health profile, assessments, plans, and notes into one shareable file is a real trust signal for a health app where people hand medical history to an AI — 'your data is yours, take it anytime.'

- **Today:** The Privacy Policy lists rights to 'Access your data' and make 'data requests,' but Settings offers no data-export action — only 'Export Debug Log' (session events, not health data), Delete Account, and per-plan PDF export buried in the plan view. There's no consolidated way to see or export the health profile, assessments, and AI analyses.
- **Proposal:** Add an 'Export My Data' row in Legal/Account that bundles profile, assessments, plans, and notes into a shareable file (JSON or PDF), reusing the Firestore reads already in deleteAccount().

### 83. Legal documents are 15 months stale and omit new data flows
`medium impact` · `small effort` · `trust-safety` · `ios/PT-Helper/PT-Helper/Models/LegalContent.swift:14,116`

**Pitch:** The in-app Privacy Policy and Terms have a 'Last Updated' date over a year old and don't mention newer features that touch user data — form analysis (on-device motion/pose data), the AI recovery agent, and wellness plans. Refreshing them with accurate, current disclosure builds trust and keeps us aligned for App Store and privacy-regulation review.

- **Today:** Both Privacy Policy and Terms are stamped 'Last Updated: March 2025' (today is June 2026). Since then the app shipped Managed-Agent recovery insights, a cross-session form-analysis agent storing video-derived pose data in a new formAnalyses collection, and wellness plans — none reflected in 'Data We Collect' or 'Third-Party Services.' The pose/biometric data is never mentioned.
- **Proposal:** Refresh both documents with a current date and disclose pose/form-analysis data, the managed-agent processing path, and wellness data. Add a 'last reviewed' line kept current even when content doesn't change.

### 84. Settings has no support / contact / 'rate the app' affordance
`medium impact` · `small effort` · `engagement` · `ios/PT-Helper/PT-Helper/Views/SettingsView.swift:195-256`

**Pitch:** There's no way for a user to reach a human or rate the app from Settings — the only contact email is buried in legal fine print, so frustrated users vent in App Store reviews instead. A 'Help & Support' section with one-tap 'Contact Support' (pre-filled with the app version for faster debugging) and a 'Rate' button means fewer angry 1-star reviews, more direct feedback, and better ranking from ratings we actually asked for.

- **Today:** Settings sections are Profile, Notifications, Debug & Feedback (only 'Export Debug Log' + a session count), Legal, Actions, Danger Zone. There's no Contact Support, Send Feedback, Help/FAQ, or Rate row — the only way to reach a human is a Gmail address buried in the Privacy Policy text.
- **Proposal:** Add a 'Help & Support' section with a 'Contact Support' row (prefilled email including app version, already computed in appVersionText) and a 'Rate PT Helper' row via SKStoreReviewController.

### 85. Pre-analysis disclaimer has a redundant 'Cancel' that silently aborts the flow
`medium impact` · `small effort` · `flow` · `ios/PT-Helper/PT-Helper/Views/DisclaimerView.swift:59-87; BodyMap3DView.swift:686-693`

**Pitch:** Right before someone gets their first AI injury analysis, a one-time disclaimer has both 'Continue' and 'Cancel'. Tapping Cancel just dumps them back to the body map with no explanation — it feels broken at the exact moment they're most excited for results. Removing or re-labeling that confusing exit means fewer people abandon the flow right before the app's standout feature.

- **Today:** The one-time pre-analysis disclaimer shows a primary 'I Understand, Continue' AND a toolbar 'Cancel'. Cancel just calls dismiss() with no onAccept — so the user is silently bounced back to the body map having selected pain regions, with no indication why analysis didn't proceed. The disclaimer is required before analysis, yet offers an equally-weighted silent exit.
- **Proposal:** Remove the Cancel button (the content is read-only and one-time, so a single 'I Understand' CTA is cleaner), or make its consequence explicit ('You'll need to accept this to get an analysis') instead of a silent dismiss.

### 86. Legacy Profile screen has a dead 'Reminders' row and a mislabeled 'Debug Log'
`low impact` · `small effort` · `minor-design` · `ios/PT-Helper/PT-Helper/Views/Dashboard/DashProfileView.swift:23-32`

**Pitch:** On the older app layout, the Profile screen had a 'Reminders' button that did nothing and a 'Debug Log' button that actually opened Settings. Fixing both so every button does what its label says removes two small but confidence-eroding rough edges.

- **Today:** In DashProfileView (legacy --use-legacy-ui), the 'Reminders' row has an empty action body ('// Future: notification settings') — tapping it does nothing. A row labeled 'Debug Log' actually opens the full SettingsView, not a debug log. One row is a no-op and another is misnamed.
- **Proposal:** Wire 'Reminders' to open SettingsView (where the real reminder toggles live) or remove it; rename the 'Debug Log' row to 'Settings' since that's what it opens.


## Form analysis & pose feedback
_The most differentiated feature is buried, gives users no framing guide or actionable error fixes, hides the rep count and methodology behind a bare score, and throws away the video before they can learn from it._

### 87. Form Check is buried in the legacy dashboard — invisible in the main 3-tab app
`high impact` · `small effort` · `structure` · `ios/PT-Helper/PT-Helper/Views/FormCheckTab.swift:5; Views/Dashboard/DashboardMainTabView.swift:38`

**Pitch:** The AI video form-check feature — your phone watching you exercise and coaching your technique — is effectively hidden: the only way a real user reaches it is tapping a tiny 'Form' icon mid-workout. A clear 'Check My Form' entry on the main plan screen lets users record any exercise anytime, putting one of the app's most impressive, differentiated capabilities front and center instead of letting most people never find it.

- **Today:** FormCheckTab (the standalone form-analysis entry) is only mounted inside the legacy DashboardMainTabView. The live ThreeTabView/MyPlanTab/ProgressTab contain zero references. The only way a regular user reaches AI form analysis is the small 'Form' icon in the secondary actions row mid-workout.
- **Proposal:** Surface form analysis as a first-class entry point in the live 3-tab UI — a 'Check My Form' card on My Plan or a per-exercise affordance — so users can record a form check without first being inside a running guided workout.

### 88. Specific, actionable data-quality warnings are computed then discarded
`medium impact` · `small effort` · `feature` · `ios/PT-Helper/PT-Helper/Views/FormAnalysisView.swift:221-234; Services/DataQualityScorer.swift:49-95`

**Pitch:** When a form-check video comes back weak, the app already knows the exact reason — too short, poor lighting, a key joint out of frame — but only says a vague 'results may be less accurate.' Surfacing the specific, fixable advice it already computed turns a dead-end into a clear 'do this and record again,' so users get usable results faster and are far less likely to give up on the feature.

- **Today:** DataQualityScorer produces precise fixable warnings ('Video is too short, record at least 3 seconds', 'Try better lighting', 'Key joints were not visible in X% of frames') that flow into dataQuality.warnings. But the result view only reads confidenceLevel and shows one generic line, never rendering the warnings.
- **Proposal:** When confidence is low/insufficient, render the actual dataQuality.warnings with their concrete fixes (a 'How to get a better result' tip block tied to a 'Record Again' button).

### 89. Bare camera with no framing guide during recording
`medium impact` · `medium effort` · `flow` · `ios/PT-Helper/PT-Helper/Views/Components/VideoRecorderView.swift:10-20`

**Pitch:** When you record yourself for AI form feedback, the camera shows nothing to help you frame the shot — so you can record 30 seconds, wait for processing, and only then get told 'no body pose detected' because you were out of frame. An on-screen body outline and a 'stand back so your whole body fits' guide (plus an optional 3-2-1 countdown) means people get a usable take on the first try.

- **Today:** VideoRecorderView is a plain UIImagePickerController with no overlay — no body-outline silhouette, no 'step back so your full body fits' prompt, no countdown, no live in-frame check. Guidance lives only as static text on the prior screen. 'No body pose detected' failures are only discovered after recording and processing.
- **Proposal:** Add a camera overlay with a body-position silhouette/frame guide and a brief 'stand back, full body in frame' instruction, plus optionally a 3-2-1 countdown so users can get into position.

### 90. Detected rep count is hidden, so feedback feels disconnected from what the user did
`medium impact` · `small effort` · `trust-safety` · `ios/PT-Helper/PT-Helper/Views/FormAnalysisView.swift:461-508; FormAnalysisViewModel.swift:189,303`

**Pitch:** The form-feedback screen gives a score out of 100 but never says how many reps the app actually saw — so if it caught only a blurry frame or zero reps, you'd never know the score might be guesswork. Showing 'Analyzed N reps' (and saying so plainly when it detects none) makes people trust the score more, because they can see the app actually watched their workout.

- **Today:** The pipeline detects a rep count and even sends 'FORM METRICS (N reps detected)' to the AI, but the result screen never tells the user how many reps it saw. If detection found 0 reps (a special case in the prompt), the user still gets a score with no signal that the system essentially saw a static frame.
- **Proposal:** Show 'Analyzed N reps' near the score header, and when 0 reps are detected, replace/annotate the score with an explicit note ('We couldn't detect distinct reps — try a fuller range of motion or a side-on angle').

### 91. Score has no meaning, methodology, or safety framing — feels like a black box
`medium impact` · `small effort` · `trust-safety` · `ios/PT-Helper/PT-Helper/Views/FormAnalysisView.swift:461-508, 194-326`

**Pitch:** The form-check result drops a big 0-100 score and a verdict like 'Form Concern' with zero explanation of what it means — alarming and overly authoritative for a health app. A short honest line near the score, plus surfacing the limitations the AI already returns but we throw away, gives users feedback they can trust and won't over-read a number as a diagnosis.

- **Today:** The result leads with a big colored 0-100 number and a verdict ('Form Concern') with no explanation of what the score represents, how it was computed, or any 'AI estimate / not medical advice' framing. The parsed dataLimitations field is stored on FormFeedback but never rendered.
- **Proposal:** Add a brief, dismissible explainer near the score ('This score estimates technique from on-device pose tracking — a coaching aid, not a medical assessment') and render the existing dataLimitations entries.

### 92. Error screen gives the failure but not the fix
`medium impact` · `small effort` · `copy` · `ios/PT-Helper/PT-Helper/Views/FormAnalysisView.swift:416-457; Services/PoseDetectionService.swift:336-337`

**Pitch:** When form analysis fails, users see cryptic developer messages like 'Failed to configure video reader' with no idea how to fix it — so many give up. Turning each failure into plain English plus a short checklist (good lighting, full body in frame, stable connection) means more users successfully complete a form check instead of abandoning the feature after one confusing error.

- **Today:** On failure the view shows a generic 'Analysis Failed' plus error.localizedDescription and 'Try Again.' Pose failures have decent copy, but other errors surface raw technical strings ('Failed to configure video reader', 'Video reading failed'). There's no differentiation by cause and no checklist of what to change.
- **Proposal:** Map error categories (no pose, too short, decode/reader failure, network) to friendly titles and a short 'Before you try again' bulleted list (lighting, distance, full body, stable network). Reserve raw detail for logs.

### 93. No way to review the recorded clip alongside the feedback
`medium impact` · `large effort` · `feature` · `ios/PT-Helper/PT-Helper/ViewModels/FormAnalysisViewModel.swift:86-89; FormAnalysisView.swift:194-326`

**Pitch:** After you record yourself doing an exercise, the app gives a score and tips but throws away your video — so when it says your knee caved on rep 3, you just take its word for it. Letting you watch your own clip next to the feedback turns a one-line verdict into something you can actually see and learn from, while still deleting the video when you leave the screen to keep the privacy promise.

- **Today:** The recorded video is deleted in a defer block as soon as analysis finishes, and the results screen is entirely text/score based — no thumbnail, no playback, no visual marking of the moments a correction refers to. Corrections reference body parts ('Based on: knee angle…') the user can never see.
- **Proposal:** Retain the clip for the duration of the result screen and let users replay it (ideally scrub to the rep/moment a correction references), tying the privacy-minded deletion to leaving the results screen rather than analysis completion.


## Microcopy & UX writing
_Small wording issues — programmer-style pluralization and an inconsistent voice swinging between cheery exclamations, robotic 'OK', and blunt error headings — make the app feel unfinished in the moments users touch most._

### 94. Inconsistent alert voice: cheery 'Plan Saved!' next to robotic 'OK' and blunt 'X Failed'
`low impact` · `small effort` · `copy` · `ios/PT-Helper/PT-Helper/Views/WellnessPlanView.swift:24-25; AnalysisResultView.swift:62-63; SettingsView.swift:360-361,375-376`

**Pitch:** The app's popups speak in three different voices within a few taps — a cheery 'Plan Saved!', a robotic 'OK', and a blunt 'Sign Out Failed'. Giving every confirmation and error a single warm, human voice ('Got it', 'Couldn't sign you out — try again') is small polish, but it's what makes the app feel like a finished, cared-for product instead of a stack of default system dialogs.

- **Today:** Confirmation and dismissal microcopy is inconsistent: a friendly 'Plan Saved!' resolves with a flat 'OK'; the 'About Match Strength' info alert also dismisses with 'OK'; sign-out and delete failures use 'Sign Out Failed' / 'Delete Failed' + 'OK'. The voice swings between warm exclamation, neutral 'OK', and curt 'X Failed' within a few taps.
- **Proposal:** Standardize a light, consistent voice: success/info alerts dismiss with 'Got it' (already used on the body-map coach mark); failure headings drop 'X Failed' for 'Couldn't sign you out' / 'Couldn't delete your account' with a 'Try Again' affordance where possible.

### 95. Programmer-style '(s)' pluralization leaks into user-facing copy
`low impact` · `small effort` · `copy` · `ios/PT-Helper/PT-Helper/Views/WorkoutSessionView.swift:143; GuidedWorkoutView.swift:85`

**Pitch:** Two spots in the workout flow show counts like '1 exercise(s) selected' with that clunky '(s)' you only see in unfinished software. Making them read naturally ('1 exercise' or '3 exercises') makes the app feel polished and human in the moments users touch most.

- **Today:** Counts are shown with literal '(s)' suffixes — 'N exercise(s) selected' on the log-workout screen and 'with N exercise(s) completed' in the Resume Workout dialog — a developer shortcut surfacing in the UI even when the count makes the plural unambiguous.
- **Proposal:** Use proper pluralization (Swift AttributedString inflection or a simple ternary, '1 exercise' / 'N exercises'). The codebase already does this elsewhere (WellnessGoalPickerView uses a Goal/Goals ternary).
