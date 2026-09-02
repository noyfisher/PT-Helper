---
name: ux-audit
description: Launch the app on simulator, screenshot every major screen, analyze UX issues, and output a prioritized report. Read-only — no code changes.
argument-hint: [full|dashboard|onboarding|workout|plans|settings]
---

# UX Audit

Navigate the PT Helper app on the iOS Simulator, capture screenshots and accessibility trees for each screen, and generate a prioritized UX issue report. **This skill is read-only — DO NOT edit any files, create branches, or make commits.**

## Status Protocol

Emit a single status line before and after each phase:
- Format: `[Step N/6] <phase> — starting` and `[Step N/6] <phase> — done (<metric>)`
- The 6 phases: 1=Parse Args, 2=Build & Launch, 3=Capture Screenshots, 4=Analyze Issues, 5=Generate Report, 6=Cleanup
- During Phase 3, also report per-screen: `[Step 3/6] Capture — screen N/M captured (<screen name>)`
- Example: `[Step 3/6] Capture — screen 4/12 captured (Profile)`

---

## Phase 1 — Parse Arguments

Read `$ARGUMENTS` to determine scope:

| Argument | Screens Covered |
|----------|----------------|
| `full` (default) | All 12 screens |
| `dashboard` | Dashboard, Form Check, Rehab Metrics, Profile |
| `onboarding` | Onboarding flow (requires separate launch) |
| `workout` | Rehab Plan, Guided Workout, Workout Summary |
| `plans` | Plans Tab, Rehab Plan detail |
| `settings` | Settings screen |

If no argument provided, default to `full`.

---

## Phase 2 — Build & Launch

1. Call `session_show_defaults` to check XcodeBuildMCP configuration. If not configured:
   ```
   session_set_defaults:
     projectPath: ios/PT-Helper/COIL.xcodeproj
     scheme: PT-Helper
     simulatorName: iPhone 16
   ```

2. Call `build_run_sim` to build and launch with test data. The app uses these launch arguments automatically via the scheme's test configuration. If the app doesn't land on the dashboard with data, try stopping and relaunching with explicit env:
   ```
   stop_app_sim
   launch_app_sim with args: ["--uitesting", "--skip-onboarding", "--seed-mock-data"]
   ```

3. Wait 2 seconds for the app to settle, then take an initial `screenshot` to confirm the dashboard loaded.

---

## Phase 3 — Screen Navigation & Capture

For each screen in the audit scope, follow this sequence:

1. **Navigate** to the screen (see navigation table below)
2. **Wait** 1-2 seconds for animations to complete
3. **Screenshot** — call `screenshot` (use `returnFormat: "path"` to save to disk)
4. **Snapshot UI** — call `snapshot_ui` to get the accessibility tree with coordinates
5. **Read source** — use the Read tool on the corresponding Swift file

### Full Audit Navigation Sequence (12 screens)

Execute in this order to minimize backtracking:

| Step | Screen | Navigation Action | View File |
|------|--------|------------------|-----------|
| 1 | Home | Already visible after launch (tab index 0) | `ios/PT-Helper/COIL/Views/MainTabView.swift` (HomeTab) |
| 2 | Assessment Gateway | Tap the floating "+" | `ios/PT-Helper/COIL/Views/AssessmentGatewayView.swift` |
| 3 | My Plan | Tap "My Plan" tab (tab index 1) | `ios/PT-Helper/COIL/Views/MyPlanTab.swift` |
| 4 | Progress | Tap "Progress" tab (tab index 2) | `ios/PT-Helper/COIL/Views/ProgressTab.swift` |
| 5 | Profile | Tap "Profile" tab (tab index 3) | `ios/PT-Helper/COIL/Views/MainTabView.swift` (ProfileTab) |
| 6 | Settings | From Progress, tap the settings/gear button | `ios/PT-Helper/COIL/Views/SettingsView.swift` |
| 7 | Rehab Plan | From My Plan, tap a plan card | `ios/PT-Helper/COIL/Views/RehabPlanView.swift` |
| 8 | Guided Workout | From Rehab Plan, tap "Start Workout" button | `ios/PT-Helper/COIL/Views/GuidedWorkoutView.swift` |
| 9 | Recovery Insights | From Progress, tap recovery insights card | `ios/PT-Helper/COIL/Views/RecoveryInsightsDetailView.swift` |
| 10 | Achievements | Look for achievements entry in Progress or Profile | `ios/PT-Helper/COIL/Views/AchievementsView.swift` |
| 11 | Onboarding | Stop app, relaunch with `["--uitesting"]` only (no --skip-onboarding) | `ios/PT-Helper/COIL/Views/OnboardingView.swift` |

**Navigation tips:**
- Use `snapshot_ui` to find element labels/IDs before tapping
- Prefer tapping by `label` or `id` (accessibility identifier) over coordinates
- Fall back to coordinates from `snapshot_ui` if labels are not available
- If a screen is unreachable (no navigation path with seeded data), skip it and note in the report

### Scoped Audit Navigation

For scoped audits, only execute the relevant steps from the table above:
- `dashboard`: Steps 1-4
- `onboarding`: Step 12 only
- `workout`: Steps 7-8 (navigate to a plan first, then start workout)
- `plans`: Steps 6-7
- `settings`: Steps 4-5

---

## Phase 4 — Analyze Each Screen

For each captured screen, analyze the screenshot, accessibility tree, and source code against these criteria:

### P0 — Critical (functional blockers)
- **Touch targets < 44pt**: Check `width` and `height` of interactive elements in `snapshot_ui`. Apple HIG minimum is 44x44pt.
- **Missing accessibility labels**: Interactive elements (buttons, links, inputs) in `snapshot_ui` with empty or missing `AXLabel`.
- **Overlapping tap targets**: Two interactive elements whose bounding boxes overlap.

### P1 — High (usability impact)
- **Missing empty states**: View has data-dependent sections but no fallback when data is empty. Check source for `EmptyStateView` or conditional empty display.
- **Missing error states**: View calls async ViewModel methods but doesn't display errors. Check for `errorMessage` handling.
- **Missing loading states**: View has `.task {}` or `Task {}` blocks but no `ProgressView` or `LoadingStateView`.
- **Text contrast**: Any text using colors lighter than `AppColors.mutedText` (#8A9A7E) on card/page backgrounds.
- **Navigation dead-ends**: Screens with no back button, dismiss button, or way to exit.

### P2 — Medium (design consistency)
- **Hardcoded colors**: Source uses `Color(red:`, `Color.gray`, `Color.white`, etc. instead of `AppColors` tokens.
- **Hardcoded spacing**: Source uses `.padding(20)` or similar instead of `AppSpacing` tokens.
- **Hardcoded corners**: Source uses `cornerRadius: 10` instead of `AppCorners` tokens.
- **Font inconsistencies**: Source uses `.font(.system(` instead of `AppFonts` presets.
- **Missing card styling**: Cards not using `.cardStyle()` modifier.

### P3 — Cosmetic (polish)
- **Visual clutter**: More than 6 distinct sections visible without scrolling.
- **Information density**: More than 15 interactive elements visible in one viewport.
- **Inconsistent iconography**: Mixed SF Symbol weights or sizes.
- **Alignment/spacing irregularities**: Visible in screenshot — uneven gaps, misaligned elements.

---

## Phase 5 — Generate Report

Create the report file at `docs/archive/ux-audits/ux-audit-{YYYY-MM-DD}.md`:

```markdown
# UX Audit Report — {date}

## Summary
- **Screens audited:** {N}
- **Total issues found:** {N}
- P0 Critical: {N} | P1 High: {N} | P2 Medium: {N} | P3 Cosmetic: {N}

---

## Screen: {Screen Name}
**File:** `{path/to/ViewFile.swift}`

### Issues
| # | Priority | Category | Description | Location | Suggestion |
|---|----------|----------|-------------|----------|------------|
| 1 | P0 | Touch Target | "Edit" button is 32x28pt | Line 142 | Add `.frame(minWidth: 44, minHeight: 44)` |
| 2 | P2 | Design Token | Hardcoded `Color(red: 0.9, ...)` | Line 87 | Replace with `AppColors.cardBackground` |

{repeat for each screen}

---

## Recommended Fix Order
1. **P0 items** — {grouped by screen, with effort estimate}
2. **P1 items** — {grouped by category}
3. **P2 items** — {these are good `/improve ux {screen}` candidates}
4. **P3 items** — {address during future restyle work}

---

## Next Steps
- Run `/improve ux {screen}` for the screens with the most P0/P1 issues
- Re-audit after fixes: `/ux-audit {screen-group}`
```

---

## Phase 6 — Cleanup & Verify

1. Call `stop_app_sim` to stop the simulator app
2. Run `git status --porcelain` — verify NO files were modified (except the report you just created)
3. Report to the user:
   - Path to the saved report
   - Summary counts (P0/P1/P2/P3)
   - Top 3 most impactful screens to fix first
   - Suggest specific `/improve ux {screen}` commands to run

**IMPORTANT: This skill must not modify any Swift source files. The only file created is the audit report.**
