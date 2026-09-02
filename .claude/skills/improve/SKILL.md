---
name: improve
description: Run an autonomous improvement cycle — creates a branch, makes focused improvements, runs tests, and opens a PR for review.
argument-hint: [tests|accessibility|code-quality|error-handling|performance|ux {screen}|auto]
---

# Autonomous Improvement Cycle

Make focused, small improvements to the PT Helper iOS app in an isolated branch. Build, test, and open a PR for human review.

## Status Protocol

Emit a single status line before starting each phase and after completing it:
- Format: `[Step N/8] <phase> — starting` and `[Step N/8] <phase> — done (<key metric>)`
- The 8 phases: 1=Parse Args, 2=Check PR Limit, 3=Record State & Branch, 4=Analyze & Improve, 5=Build, 6=Test, 7=Commit & PR, 8=Cleanup
- Example: `[Step 5/8] Build — starting` → `[Step 5/8] Build — done (succeeded)`
- On failure: `[Step 6/8] Test — failed (2 tests failed, aborting)`

## Safety Rules — READ FIRST

1. **Never modify `main` branch** — always work in a new `agent/improve-*` branch
2. **Never force-push** — if push fails, stop and report
3. **Never modify existing passing tests** — only ADD new tests or new assertions
4. **Never change these files**: `DesignSystem.swift`, `ClaudeAPIService.swift`, `functions/src/index.ts`, `CLAUDE.md`
5. **Max 3 files changed** per cycle — keeps PRs small and reviewable
6. **Always run SmokePlan** before creating a PR
7. **Revert everything on test failure** — do not create PRs with failing tests
8. **Never use `git add .` or `git add -A`** — stage specific files only

---

## Phase 1 — Parse Arguments

Read `$ARGUMENTS` to determine the category:

| Argument | Category |
|----------|----------|
| `tests` | Add missing unit tests |
| `accessibility` | Add accessibility identifiers to views |
| `code-quality` | Replace hardcoded values with design tokens, reduce duplication |
| `error-handling` | Add error/empty states to views |
| `performance` | Optimize rendering and data loading |
| `ux {screen}` | Fix UX issues on a specific screen (requires screen name) |
| `auto` or empty | Auto-select (see Auto Mode below — excludes `ux`) |

**Special handling for `ux`**: The argument is two parts — `ux dashboard`, `ux settings`, etc. If `ux` is provided without a screen name, STOP and show the user the valid screen names (see the screen mapping table in the `ux` category section below).

---

## Phase 2 — Check PR Limit

Before doing any work, check how many improvement PRs are already open:

```bash
gh pr list --label agent-improvement --state open --json number --jq 'length'
```

- If the count is **5 or more**: STOP. Tell the user: "There are already N open improvement PRs. Please review and merge/close some before running another cycle."
- If the label doesn't exist yet, that's fine — it means 0 open PRs.

---

## Phase 3 — Record Starting State & Create Branch

1. Record the current branch name so you can return to it later:
   ```bash
   ORIGINAL_BRANCH=$(git branch --show-current)
   ```

2. Make sure working tree is clean (no uncommitted changes):
   ```bash
   git status --porcelain
   ```
   If there are uncommitted changes, STOP and tell the user to commit or stash first.

3. Create a new branch:
   ```bash
   git checkout -b agent/improve-{category}-$(date +%Y%m%d-%H%M)
   ```

---

## Phase 4 — Analyze & Improve

### Category: `tests`

**Goal**: Add unit tests for untested or under-tested ViewModels.

**Priority targets** (check in order — skip if already tested):
1. `ios/PT-Helper/COIL/ViewModels/WellnessAnalysisViewModel.swift` — no test file exists
2. `ios/PT-Helper/COIL/ViewModels/WellnessPlanViewModel.swift` — no test file exists
3. Any ViewModel where the test file exists but has fewer than 3 test methods

**Reference pattern**: Read `ios/PT-Helper/COILTests/ViewModels/RecoveryInsightsViewModelTests.swift` and follow this structure exactly:
- `@MainActor final class {Name}Tests: XCTestCase`
- `private var mockAPI: MockClaudeAPIService!` + `private var vm: {ViewModel}!` in setUp
- Use `TestFixtures` factory methods from `ios/PT-Helper/COILTests/TestFixtures.swift`
- Test naming: `test<What>_<Condition>_<Expected>`
- Minimum 3 test methods per new file

**Also read**: `ios/PT-Helper/COILTests/Mocks/MockClaudeAPIService.swift` to understand available mock capabilities.

**New test files go in**: `ios/PT-Helper/COILTests/ViewModels/`

**Scope**: 1 new test file OR add tests to 1 existing test file per cycle.

---

### Category: `accessibility`

**Goal**: Add `.accessibilityIdentifier()` modifiers to interactive elements in views.

**Naming convention**: `screenName.elementName` (e.g., `dashboard.streakBadge`, `settings.logoutButton`)

**Priority targets** (lowest coverage first):
1. Views in `ios/PT-Helper/COIL/Views/Dashboard/` — check each file for missing identifiers
2. Views in `ios/PT-Helper/COIL/Views/Components/` — reusable components often lack identifiers
3. Any View file with buttons, text fields, or toggles that lack identifiers

**Reference pattern**: Read `ios/PT-Helper/COIL/Views/GuidedWorkoutView.swift` to see how identifiers are applied consistently.

**What to add identifiers to**:
- Buttons and navigation links
- Text fields and toggles
- Cards/cells that could be tapped in UI tests
- Status indicators (loading, error, empty states)

**What NOT to add identifiers to**:
- Decorative text or images
- Static layout containers

**Scope**: Up to 3 view files per cycle.

---

### Category: `code-quality`

**Goal**: Replace hardcoded values with design system tokens.

**Step 1 — Find violations**: Search for raw color/spacing values:
```
# Find hardcoded colors
grep -rn "Color(red:" ios/PT-Helper/COIL/Views/ --include="*.swift" | head -20

# Find hardcoded corner radii
grep -rn "cornerRadius:" ios/PT-Helper/COIL/Views/ --include="*.swift" | grep -v "AppCorners" | head -20

# Find hardcoded padding values
grep -rn "\.padding(" ios/PT-Helper/COIL/Views/ --include="*.swift" | grep -E "\.[0-9]+" | head -20
```

**Step 2 — Read design tokens**: Read `ios/PT-Helper/COIL/DesignSystem.swift` to find the correct replacement tokens:
- `AppColors.accent`, `.success`, `.warning`, `.danger`, `.cardBackground`, etc.
- `AppSpacing.xs` (4), `.sm` (8), `.md` (12), `.lg` (16), `.xl` (24), `.xxl` (32), `.xxxl` (40)
- `AppCorners.small` (8), `.medium` (12), `.card` (16), `.large` (20), `.xl` (24), `.pill` (100)

**Step 3 — Replace**: Swap hardcoded values with the nearest token. When in doubt, pick the closest match — do not create new tokens.

**Scope**: Up to 3 files per cycle. Pick the files with the most violations first.

---

### Category: `error-handling`

**Goal**: Add missing error and empty states to views that call async ViewModel methods.

**How to find targets**:
1. Grep for `.task {` or `Task {` in View files
2. Check if the corresponding ViewModel has an `errorMessage` or `error` published property
3. Check if the View actually displays error/empty states

**Reference patterns**:
- Empty state: Read `ios/PT-Helper/COIL/Views/MyPlanTab.swift` — shows how to display a message when no data exists
- Error display: Read `ios/PT-Helper/COIL/Views/GuidedWorkoutView.swift` — shows error banner pattern

**What to add**:
- `if let errorMessage = vm.errorMessage { ... }` blocks showing the error
- Empty state views when collections are empty after loading completes
- Loading indicators during async operations (if missing)

**What NOT to do**:
- Don't change ViewModel logic — only add display code in Views
- Don't add try/catch — ViewModels should already handle errors
- Don't change the happy path behavior

**Scope**: 1-2 view files per cycle.

---

### Category: `performance`

**Goal**: Make targeted optimizations to rendering or data loading.

**Checklist (pick ONE per cycle)**:
1. `VStack` → `LazyVStack` in scrollable lists with many items
2. Add `EquatableView` or manual `Equatable` to avoid unnecessary redraws
3. Move expensive computations out of `body` into computed properties or `.task`
4. Add `.id()` to ForEach loops that use index-based identity

**How to find targets**:
```
# Find non-lazy stacks inside ScrollViews
grep -rn "ScrollView" ios/PT-Helper/COIL/Views/ --include="*.swift" -A 5 | grep "VStack\|HStack" | grep -v "Lazy"
```

**Reference**: Read the target file thoroughly before making any changes. Understand the data flow.

**Scope**: 1 file, 1 optimization per cycle. Performance changes have the highest risk — keep it minimal.

---

### Category: `ux {screen}`

**Goal**: Identify and fix 1-3 concrete UX issues on a specific screen, verified visually on the simulator.

**Step 1 — Resolve screen name to file**

Use this mapping to find the view file. If the screen name is not listed, STOP and show the user this table:

| Screen Name | View File |
|-------------|-----------|
| `form-check` | `ios/PT-Helper/COIL/Views/FormCheckTab.swift` |
| `profile` | `ios/PT-Helper/COIL/Views/MainTabView.swift` (ProfileTab) |
| `settings` | `ios/PT-Helper/COIL/Views/SettingsView.swift` |
| `onboarding` | `ios/PT-Helper/COIL/Views/OnboardingView.swift` |
| `plans` | `ios/PT-Helper/COIL/Views/MyPlanTab.swift` |
| `rehab-plan` | `ios/PT-Helper/COIL/Views/RehabPlanView.swift` |
| `workout` | `ios/PT-Helper/COIL/Views/GuidedWorkoutView.swift` |
| `workout-summary` | `ios/PT-Helper/COIL/Views/GuidedWorkoutSummaryView.swift` |
| `progress` | `ios/PT-Helper/COIL/Views/ProgressTab.swift` |
| `recovery` | `ios/PT-Helper/COIL/Views/RecoveryInsightsDetailView.swift` |
| `wellness` | `ios/PT-Helper/COIL/Views/WellnessGoalPickerView.swift` |
| `timer` | `ios/PT-Helper/COIL/ViewModels/GuidedWorkoutViewModel.swift` (rest timer; there is no standalone TimerView) |
| `notes` | `ios/PT-Helper/COIL/Views/NotesView.swift` |
| `achievements` | `ios/PT-Helper/COIL/Views/AchievementsView.swift` |
| `home` | `ios/PT-Helper/COIL/Views/MainTabView.swift` (HomeTab) |

**Step 2 — Build and launch app**

1. Call `session_show_defaults` to verify XcodeBuildMCP configuration. If not set:
   ```
   session_set_defaults:
     projectPath: ios/PT-Helper/COIL.xcodeproj
     scheme: PT-Helper
     simulatorName: iPhone 16
   ```

2. Call `build_run_sim` to build and launch. The app uses `["--uitesting", "--skip-onboarding", "--seed-mock-data"]` via the test scheme. If needed, stop and relaunch with explicit args.

**Step 3 — Navigate to target screen**

| Screen | How to reach it |
|--------|----------------|
| `dashboard` | Already visible (tab 0) |
| `form-check` | Tap "Form Check" tab |
| `rehab-metrics` | Tap "Rehab" tab |
| `profile` | Tap "Profile" tab |
| `settings` | Go to Profile tab → tap settings/gear button |
| `plans` | Tap "Rehab" tab → plans are listed |
| `rehab-plan` | Tap "Rehab" tab → tap a plan card |
| `workout` | Navigate to rehab-plan → tap "Start Workout" |
| `workout-summary` | Navigate to workout → complete one set → tap "End" → confirm |
| `progress` | From dashboard, find progress/chart entry |
| `recovery` | From dashboard, tap recovery insights card |
| `achievements` | From profile, find achievements entry |
| `wellness` | From dashboard, find wellness entry or navigate via Analyze |
| `timer` | From workout, timer is embedded |
| `notes` | From dashboard or home, tap notes entry |
| `onboarding` | Stop app → relaunch with `["--uitesting"]` only (no --skip-onboarding) |
| `home` | Stop app → relaunch with `["--uitesting", "--skip-onboarding", "--seed-mock-data"]` |

Use `snapshot_ui` to find element labels/IDs before tapping. Prefer tap by `label` or `id` over coordinates. Wait 1-2 seconds after navigation for animations to settle.

**Step 4 — Capture baseline**

1. Call `screenshot` — this is the "before" reference
2. Call `snapshot_ui` — get the accessibility tree with coordinates
3. Read the target view file with the Read tool
4. Read `ios/PT-Helper/COIL/DesignSystem.swift` for design token reference

**Step 5 — Identify 1-3 improvements**

Analyze the screenshot, accessibility tree, and source code. Pick improvements using this priority (highest first):

1. **Touch targets < 44pt** — Check element sizes in snapshot_ui. Add `.frame(minWidth: 44, minHeight: 44)` or increase padding
2. **Missing accessibility labels** — Interactive elements without `AXLabel`. Add `.accessibilityLabel()` and `.accessibilityIdentifier()`
3. **Hardcoded colors/spacing/corners** — Replace with `AppColors`, `AppSpacing`, `AppCorners` tokens
4. **Missing empty/error/loading states** — Add using `EmptyStateView`, `LoadingStateView` from DesignSystem
5. **Typography inconsistencies** — Replace `.font(.system(` with `AppFonts` tokens
6. **Spacing irregularities** — Adjust to nearest `AppSpacing` token

Document each planned change BEFORE editing: what, why, and which line(s).

**Step 6 — Make changes**

Edit the view file (and up to 2 related files, respecting the 3-file max). Use existing components from `DesignSystem.swift`.

**Step 7 — Verify visually**

1. Call `build_sim` to recompile
2. If build passes, launch app again with same arguments
3. Navigate to the same screen
4. Call `screenshot` — this is the "after" reference
5. Call `snapshot_ui` — verify fixes are reflected (e.g., larger touch targets, new labels)
6. Note before/after differences for the PR description

**Step 8 — Continue to standard improve cycle**

Proceed to Phase 5 (Build), Phase 6 (Test SmokePlan), Phase 7 (Commit & PR), Phase 8 (Cleanup).

Commit message format:
```
improve(ux): fix {N} UX issues on {screen} screen

- {fix 1 description}
- {fix 2 description}

Co-Authored-By: Claude <noreply@anthropic.com>
```

The PR body should include descriptions of the before/after state and what specifically improved.

**Scope**: Max 3 files, 1-3 improvements per cycle.

---

## Auto Mode

**Note: The `ux` category is excluded from auto mode** — it requires a screen name and involves simulator interaction that is slower and less deterministic. Use `/improve ux {screen}` explicitly.

When `$ARGUMENTS` is empty or `auto`, pick a category automatically using this priority:

1. **tests** — Check if untested ViewModels still exist:
   ```bash
   # If either file exists without a corresponding test, pick tests
   ls ios/PT-Helper/COILTests/ViewModels/WellnessAnalysisViewModelTests.swift 2>/dev/null
   ls ios/PT-Helper/COILTests/ViewModels/WellnessPlanViewModelTests.swift 2>/dev/null
   ```

2. **accessibility** — Check for views missing identifiers:
   ```bash
   # If many views lack identifiers, pick accessibility
   grep -rL "accessibilityIdentifier" ios/PT-Helper/COIL/Views/Dashboard/ --include="*.swift" | head -5
   ```

3. **code-quality** — Check for hardcoded colors:
   ```bash
   grep -c "Color(red:" ios/PT-Helper/COIL/Views/**/*.swift 2>/dev/null | grep -v ":0$" | head -5
   ```

4. **error-handling** — Check for views missing error display
5. **performance** — Always last (highest risk)

Pick the **first category that has remaining work**.

---

## Phase 5 — Build

After making changes, build to verify compilation:

**Prefer XcodeBuildMCP**: Call `session_show_defaults` to check configuration, then `build_sim`.

**Fallback**:
```bash
xcodebuild build \
  -project ios/PT-Helper/COIL.xcodeproj \
  -scheme COIL \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -quiet
```

If the build fails:
1. Read the error messages carefully
2. Fix compilation errors (you have 1 attempt)
3. Build again
4. If still failing → go to **Abort Procedure**

---

## Phase 6 — Test

Run SmokePlan to verify no regressions:

**Prefer XcodeBuildMCP**: `test_sim` with `extraArgs: ["-testPlan", "SmokePlan"]`

**Fallback**:
```bash
xcodebuild test \
  -project ios/PT-Helper/COIL.xcodeproj \
  -scheme COIL \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -testPlan SmokePlan
```

If tests fail:
1. Read the failure messages
2. Fix the issue (1 attempt)
3. Re-run SmokePlan
4. If still failing → go to **Abort Procedure**

---

## Phase 7 — Commit & PR

1. **Stage only changed files** (list them explicitly):
   ```bash
   git add ios/PT-Helper/COILTests/ViewModels/NewTestFile.swift
   git add ios/PT-Helper/COIL/Views/SomeView.swift
   ```

2. **Commit** with a descriptive message:
   ```bash
   git commit -m "improve(tests): add unit tests for WellnessAnalysisViewModel

   Co-Authored-By: Claude <noreply@anthropic.com>"
   ```

3. **Push** the branch:
   ```bash
   git push -u origin HEAD
   ```

4. **Create the label** (if it doesn't exist — safe to run every time):
   ```bash
   gh label create agent-improvement --description "Automated improvement by /improve skill" --color "1d76db" 2>/dev/null || true
   ```

5. **Create the PR**:
   ```bash
   gh pr create \
     --title "improve({category}): {short summary}" \
     --label agent-improvement \
     --body "$(cat <<'EOF'
   ## What
   {Description of what was changed and why}

   ## Category
   `{category}`

   ## Files Changed
   - `path/to/file1.swift` — {what changed}
   - `path/to/file2.swift` — {what changed}

   ## Verification
   - SmokePlan: **PASS** ({N} tests passed)
   - Build: **PASS**

   ## Review Notes
   {Any specific things the reviewer should check}

   ---
   Generated by `/improve` skill
   EOF
   )"
   ```

---

## Phase 8 — Cleanup & Report

1. Switch back to the original branch:
   ```bash
   git checkout $ORIGINAL_BRANCH
   ```

2. Report to the user:
   - PR URL (clickable)
   - Category and what was improved
   - Files changed
   - Test results (pass count)
   - Any notes or observations

---

## Abort Procedure

If build or tests fail after retries:

1. Revert all changes:
   ```bash
   git checkout -- .
   git clean -fd
   ```

2. Switch back to original branch:
   ```bash
   git checkout $ORIGINAL_BRANCH
   ```

3. Delete the failed branch:
   ```bash
   git branch -D agent/improve-{category}-{timestamp}
   ```

4. Report to the user:
   - What was attempted
   - Why it failed (build error? test failure?)
   - The error messages
   - Suggestion for what to try differently
