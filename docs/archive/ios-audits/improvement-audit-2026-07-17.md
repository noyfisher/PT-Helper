# COIL App Improvement Audit — Implementation Spec

**Commit:** `5fd0abb` &nbsp;·&nbsp; **Branch:** `coil-rebrand` &nbsp;·&nbsp; **Date:** 2026-07-17

**Provenance:** Multi-agent audit — adversarial verification wave (5 parallel refute-first verifiers) + a serial simulator visual pass (37 screenshots, light/dark/Dynamic-Type) + git archaeology + synthesis with a reviewer cycle. Every file:line claim in this document was re-grepped against the working tree at `5fd0abb` before inclusion; refuted findings were dropped, reframed findings carry their tightened claim.

This single file is the complete, execution-ready spec: hand it to Claude Sonnet 5 and it can execute WS1 without asking a question. Read "How to use this document" first, then work the Status Ledger top-to-bottom.

---

## 1. Status Ledger

Sonnet's cross-session memory. Update the **Status** and **PR#** columns as you land each item. `todo` = ready to start (all its dependencies are already merged or it has none). `BLOCKED: <reason>` = do not start until the named predecessor lands; when it does, flip the row to `todo`. Effort: S ≈ <½ day, M ≈ ½–1½ days, L ≈ multi-PR.

| Item ID | Title | WS | Priority | Effort | Status | PR# |
|---|---|---|---|---|---|---|
| WS1-01 | Collapse MainTabView to a ThreeTabView passthrough and delete the legacy 4-tab shell wiring (+ LegacyUITests, --use-legacy-ui) | WS1 | P1 | M | done | #43 |
| WS1-02 | Delete the --showcase screenshot harness (ShowcaseHostView + PT_HelperApp entry) | WS1 | P1 | S | done | #43 |
| WS1-03 | Delete Views/Dashboard/* (10 files, 1,341 LOC) and the last dashboard TabSelection ids | WS1 | P1 | S | done | #43 |
| WS1-04 | Split ContentView.swift: extract live OnboardingEditView, delete LegacyHomeTab, delete the file | WS1 | P1 | S | done | #43 |
| WS1-05 | Delete legacy-orphaned view files: PlansTab, ProgressChartView, HealthCheckPromptView | WS1 | P1 | S | done | #43 |
| WS1-06 | Delete AssessTab.swift and QuickHealthUpdateView.swift | WS1 | P2 | S | done | #43 |
| WS1-07 | Remove dead ProgressTabContent.totalMinutes (ProgressTab.swift:584-586) | WS1 | P3 | S | done | #43 |
| WS1-08 | Commit the cosmetic pbxproj diff (unquoted CFBundleDisplayName) | WS1 | P3 | S | done | #43 |
| WS1-09 | Fix stale navigation docs and purge references to deleted files (CLAUDE.md, ux_flows, PT-Helper-Documentation, LAYOUT.md, improve skill) | WS1 | P2 | S | done | #43 |
| WS2-01 | Build the reminder reconciliation engine and wire it into the plan lifecycle | WS2 | P1 | M | done | #44 |
| WS2-02 | Make the Settings toggles, time picker, and sign-out honor notification state | WS2 | P1 | S | done | #44 |
| WS2-03 | Schedule re-assessment reminders at plan midpoint and completion (audit #33) | WS2 | P2 | S | done | #44 |
| WS2-04 | First-workout activation nudge for freshly started plans (audit #34) | WS2 | P2 | S | done | #44 |
| WS3-01 | Close the grandfathered-user consent bypass with a launch-time health-consent gate | WS3 | P1 | M | done | #45 |
| WS3-02 | Add the policy-promised consent-withdraw control in Settings with defined downstream effects | WS3 | P1 | M | done | #45 |
| WS3-03 | Make server state authoritative in ConsentService.load() and surface record-write failures; add ConsentService tests | WS3 | P1 | M | done | #45 |
| WS3-04 | Delete the write-only legacy ToS UserDefaults keys | WS3 | P2 | S | done | #45 |
| WS3-05 | Centralize duplicated UserDefaults key literals and clear the stale minor-safety flag on account deletion | WS3 | P2 | S | done | #45 |
| WS3-06 | Update the Consumer Health Data Policy withdrawal-mechanism text | WS3 | P2 | S | BLOCKED: legal review (BLOCKED-on-legal per D-2) | |
| WS4-01 | Re-skin IntroCarouselView hero to COIL tokens and fix the light-mode status-bar strip | WS4 | P1 | S | done | #46 |
| WS4-02 | Add branded launch screen and dark/tinted app-icon variants | WS4 | P2 | M | done | #46 |
| WS4-03 | Rename "PT Helper" to "COIL" in LegalContent (verbatim spec) | WS4 | P2 | S | BLOCKED: Legal sign-off (D-2) — bumps tosVersion, re-triggers acceptance gate for all users | |
| WS4-04 | Replace systemBlue with fixed COIL teal in PDFExportService | WS4 | P2 | S | done | #46 |
| WS4-05 | Sweep stale red/Barlow comments and residual PT Helper brand strings in live files | WS4 | P3 | S | done | #46 |
| WS4-06 | Remove dead Inter-Bold font (unregistered payload) | WS4 | P3 | S | done | #46 |
| WS5-01 | Fix checkpoint double-count at the exercise boundary (save-point semantics) | WS5 | P1 | M | done | #47 |
| WS5-02 | Convert rest countdown to wall-clock end-Date reconciliation | WS5 | P1 | M | done | #47 |
| WS5-03 | Add scenePhase background-save and foreground wall-clock reconcile to GuidedWorkout | WS5 | P2 | S | done | #47 |
| WS5-04 | Delete the dead TimerViewModel/TimerView/ExerciseTimer trio | WS5 | P2 | S | done | #47 |
| WS6-01 | Add read-only "Your Last Analysis" card to the Progress tab | WS6 | P1 | S | done | #48 |
| WS6-02 | Clear AnalysisResultStore on sign-out (cross-account PHI guard) | WS6 | P1 | S | done | #48 |
| WS7-01 | Sweep accent-as-text to a new adaptive accentText token (35 sites) | WS7 | P1 | M | done | #49 |
| WS7-02 | Fix Progress pain-trend chart axis labels (1.61:1 worst audit failure) | WS7 | P1 | S | done | #49 |
| WS7-03 | Darken chip/badge selected fills so white text passes AA (CoilBadge + ChipButton) | WS7 | P2 | S | done | #49 |
| WS7-04 | Add accessibilityLabels to 9 icon-only buttons | WS7 | P2 | S | done | #49 |
| WS7-05 | Add VoiceOver summary to ReAssessment comparison chart | WS7 | P2 | S | done | #49 |
| WS8-01 | Add offline fail-fast guards to the 5 ungated AI ViewModels | WS8 | P1 | M | done | #50 |
| WS8-02 | Extract shared performProxyRequest helper in ClaudeAPIService | WS8 | P1 | M | done | #50 |
| WS8-03 | Add service-level retry: 1 retry, 2s delay, transport/5xx only, never 429 | WS8 | P2 | S | done | #50 |
| WS9-01 | Tokenize text fonts in the 7 worst-offender screens (+ own the master mapping table) | WS9 | P2 | M | done | #51 |
| WS9-02 | Tokenize text fonts across the remaining live screens (long tail; split 2a components/onboarding + 2b screens) | WS9 | P2 | L | done | #51 |
| WS9-03 | Tokenize numeric padding + corner-radius literals to AppSpacing/AppCorners | WS9 | P3 | M | done | #51 |
| WS9-04 | Fold hand-rolled card stacks into .cardStyle() (33 quadruples) | WS9 | P3 | S | done | #51 |
| WS10-01 | Replace the cosmetic 21-day date strip with an honest completion-dot week strip | WS10 | P2 | M | done | #52 |
| WS10-02 | Gate the Preventative section on an active plan (hide it when there is no plan) | WS10 | P2 | S | done | #52 |
| WS10-03 | Clear preventiveTasks_* UserDefaults keys on account deletion | WS10 | P3 | S | done | #52 |
| WS11-01 | Move rehab/wellness image validation off the main thread | WS11 | P1 | M | done | #53 |
| WS11-02 | Stop recomputing ProgressTab chart/stat data every render | WS11 | P1 | S | done | #53 |
| WS11-03 | Configure body-model collision shapes + proxies once on a cached template | WS11 | P2 | M | done | #53 |
| WS11-04 | Bound the workout-session Firestore fetch | WS11 | P3 | S | done | #53 |
| WS12-01 | Remove nightly_report from the client-callable request allow-list | WS12 | P1 | S | done | #54 |
| WS12-02 | Restore a working, project-owned ESLint (config + devDependency + bounded fixes) | WS12 | P2 | M | done | #54 |
| WS12-03 | Extract system prompts + model config into a side-effect-free src/prompts.ts module | WS12 | P2 | M | done | #54 |
| WS13-01 | Convert the 12 Task.sleep VM waits (+ Timer fixed-delay) to deterministic await/expectation patterns | WS13 | P2 | M | PARTIAL: Timer left on Task.sleep (see PR notes — ExerciseTimer is a class, @Published won't observe in-place mutation, prod file out of scope) | #55 |
| WS13-02 | Extract a NotificationLifecycleScheduling seam and test WS2's newly-wired notification behavior | WS13 | P2 | M | todo (unblocked — WS2 merged via #44) | |
| WS13-03 | Test ConsentService's newly-added withdraw path + policy/mirror contract (no production seam) | WS13 | P2 | S | todo (unblocked — WS3 merged via #45) | |
| WS13-04 | Post-WS1 SmokePlan integrity gate | WS13 | P3 | S | todo (unblocked — WS1 merged via #43) | |
| WS13-05 | Document FullPlan vs PreReleasePlan intent | WS13 | P3 | S | done | #55 |

**58 items · 13 workstreams · 22 P1 · 26 P2 · 10 P3.**

---

## 2. How to use this document (read first)

You are Claude Sonnet 5, executing this spec. Operate as follows:

1. **One workstream per branch/PR.** Work workstreams in ledger order (WS1 → WS13) unless the **Depends on / Blocks** line at the foot of an item says otherwise. Within a workstream, follow the item's stated execution order.
2. **Follow the repo engineering protocol** at `/Users/noyfisher/IOS-Projects/PT-Helper-Agent-v1/CLAUDE.md` on every item — especially **R1 grep-before-assert** (re-grep every file:line before you edit it) and **R3 build-gated "done"** (no completion claim without the item's Verify block passing: `xcodebuild build` + the named test plan; any item touching `functions/src/` additionally needs `cd functions && npm run build && npm run lint`).
3. **BLOCKED protocol.** Every item's Evidence lines were verified at `5fd0abb`. If a grep does not reproduce the stated evidence (line moved, symbol renamed, file gone), **STOP — do not improvise a fix.** Re-grep to locate the true state, and if it materially diverges from the spec, mark the item **BLOCKED** in the ledger with a one-line reason and move on. Never guess at a changed insertion point.
4. **Update the Status Ledger** as you go: flip a landed item to its PR number, and flip any item it unblocks from `BLOCKED` to `todo`.
5. **Visual verification (WS4, WS7, WS9, WS10).** Build, install, and launch with the seed harness, then screenshot and compare against the baselines in `ios/PT-Helper/docs/audit-assets-2026-07-17/`:
   ```bash
   xcrun simctl launch booted com.noyfisher.pthelper --uitesting --skip-onboarding --seed-mock-data
   xcrun simctl io booted screenshot /tmp/after.png
   ```
   (Launch args must go through `simctl`, not the MCP launcher.) The only pixels that may differ are the ones the item intends to change.
6. **Simulator quirk (project memory):** if `-destination 'platform=iOS Simulator,name=iPhone 16'` fails to resolve an OS, append `,OS=18.2` — the commands in each item are otherwise copy-paste runnable verbatim.

---

## 3. Executive Summary

**Headline.** 58 execution-ready items across 13 workstreams: **22 P1, 26 P2, 10 P3**. The work splits into three arcs — (a) *truth & correctness* (dead-code deletion, workout-engine state machine, notification wiring, offline handling, performance), (b) *compliance & PHI* (MHMDA consent completion, cross-account data hygiene, last-analysis resurfacing), and (c) *brand & accessibility polish* (COIL re-skin completion, WCAG contrast, typography tokenization). WS1 lands first because deleting ~3,300 LOC of unreachable UI shrinks every later sweep.

**Top 5 by user impact.**
1. **WS6 — completed AI analysis is unreachable (P1 net-new regression).** The FloatingTabBar migration orphaned the "Your Last Analysis" re-entry card, re-introducing virtual-user bug F2: once a user leaves the result screen, a seeded/persisted analysis can never be viewed again. Restoring the card on the Progress tab (with a mandatory sign-out PHI clear) is the single highest-impact fix.
2. **WS3 — MHMDA consent gaps.** Grandfathered/post-version-bump users can run ungated health-data collection, and the policy-promised consent-withdraw control does not exist. A launch-time gate + Settings withdraw path + server-authoritative reconciliation close a real regulatory exposure.
3. **WS7 — light-mode contrast failures.** The COIL teal accent used as text is 2.54:1 on white (chart axis labels 1.61:1, the audit's worst measurement); primary CTAs and status text are unreadable in bright light. An adaptive `accentText` token + a 35-site sweep fixes it.
4. **WS2 — notifications are a no-op facade.** Every reminder toggle in Settings is a placebo (`scheduleReminders` has zero callers). Wiring a single idempotent reconciler to the plan lifecycle turns on a retention lever that has never fired for any user.
5. **WS5 — workout-engine correctness.** A checkpoint double-count at the exercise boundary corrupts completion counts on resume, and the rest countdown freezes whenever the app is backgrounded (the exact moment rests happen). Both are state-machine fixes with full regression tests.

**Audit method.** Plan-mode exploration surfaced ~45 seed findings; execution ran a read-only multi-agent workflow. A verification wave re-grepped every seed with bare-symbol patterns (the check that caught the original false "orphaned consent view"), assigning each a `CONFIRMED / REFUTED / REFRAMED` verdict — refuted seeds were dropped, reframed seeds carry their tightened claim. A simulator pass captured 16 of 17 matrix screens in light/dark plus Dynamic-Type spot checks, pixel-sampling every flagged teal-text contrast ratio. A git-archaeology + gap-hunt pass dispositioned ~15 deferred prior-audit items and answered the open questions from repo evidence. Only VERIFIED findings became spec items; everything else is appendix-flagged.

---

## 4. Decision Log (settled — do not re-litigate)

These decisions are final for this audit. Treat them as fixed constraints; do not reopen them mid-execution.

- **D-1 — Delete ALL dead trees.** The Dashboard tree, AssessTab, the legacy 4-tab shell, LegacyUITests, and the `--showcase` harness are deleted outright (WS1). Reference-graph proof per file is embedded in each WS1 item; HealthDataConsentView has 3 live production call sites and is NOT dead.
- **D-2 — LegalContent renames are spec'd verbatim but BLOCKED-on-legal in the ledger.** Non-legal brand strings (comments, logger fallbacks, PDF accent) rename now (WS4-04/05); the in-document "PT Helper" → "COIL" rename (WS4-03) and the Consumer Health Data Policy withdrawal-text update (WS3-06) ship only after counsel sign-off, because they bump `tosVersion` and force app-wide re-acceptance.
- **D-3 — Feature bets are Appendix-A briefs only.** HealthKit, Live Activity, widgets/App Intents, clip playback, localization, richer export, per-day programming, structured wellness habits: one-paragraph briefs, explicitly NOT specced. Fixes/polish/correctness get full specs.
- **D-4 — IntroCarousel is a re-SKIN to COIL tokens, not a redesign.** Swap the red hero literals for teal tokens and fix the light-mode status-bar strip (WS4-01). Page-indicator placement and layout are out of scope.
- **D-5 — The typography sweep excludes icon-size fonts.** A raw `.font(...)` sizing an `Image(systemName:)` is skipped; only text-attached fonts are tokenized (WS9; classifier command published in-section).
- **D-6 — The last-analysis card returns on the Progress tab** (WS6), built fresh from ProgressTab, not salvaged from the Dash* dead tree.
- **D-7 — The Home date strip becomes an honest today-strip** with real completion dots (WS10). True per-day *exercise* programming is a speculative Appendix-A bet, not a near-term commitment.
- **D-8 — Notification toggles get WIRED** (WS2), not removed. Git archaeology confirmed the wiring was never connected (a documented deferral in commit 9e9d223, not an intentional kill), so the default path is to wire it. Removal would only have applied had archaeology proved an intentional kill.

---

## 5. Sequencing Table

Recommended workstream order, with size, risk, required test plan, dependencies, and whether the workstream needs a simulator visual compare.

| Order | WS | Name | Size | Risk | Required test plan | Depends on | Visual check |
|---|---|---|---|---|---|---|---|
| 1 | WS1 | Dead-code deletion + repo hygiene | M | LOW (deletions with reference-graph proof; test-plan refs must be updated) | FullPlan (unit + UI) | — | no |
| 2 | WS2 | Notification system wiring | M | MEDIUM (new scheduling behavior; permission prompts; must not spam) | UnitPlan + new NotificationService tests | — | no |
| 3 | WS3 | MHMDA consent completion + consent-state consolidation | M | HIGH (consent gating regressions lock users out or leak ungated collection; fragile dismissal-ordering) | UnitPlan + new ConsentService tests + manual gate-flow check | — | no |
| 4 | WS4 | Rebrand completion | M | LOW-MEDIUM (visual-only; IntroCarousel is every new user's first screen) | SmokePlan + visual compare vs audit screenshots | — | **yes** |
| 5 | WS5 | Workout engine correctness | M | MEDIUM-HIGH (checkpoint/timer state machine; regressions corrupt workout data) | UnitPlan (GuidedWorkoutViewModelTests extended) | — | no |
| 6 | WS6 | Last-analysis resurfacing | S | LOW | UnitPlan + SmokePlan | — | no |
| 7 | WS7 | Contrast + accessibility | M | LOW (color token swaps + additive labels) | SmokePlan + visual compare | — | **yes** |
| 8 | WS8 | Offline fail-fast + API resilience | M | MEDIUM (touches all AI entry points) | UnitPlan (VM tests for offline paths) | — | no |
| 9 | WS9 | Typography + token sweep | L (split into 3-4 PRs by file group) | LOW (mechanical; visual regression risk mitigated by per-screen screenshots) | SmokePlan per PR + visual compare | — | **yes** |
| 10 | WS10 | Home-screen truth | S-M | LOW-MEDIUM | UnitPlan + SmokePlan | — | **yes** |
| 11 | WS11 | Performance | M | MEDIUM (concurrency changes) | UnitPlan + manual instrument note | — | no |
| 12 | WS12 | Backend/functions hygiene | M | LOW-MEDIUM (server deploy required; note deploy step explicitly) | `cd functions && npm run build && npm run lint && npx jest` | — | no |
| 13 | WS13 | Test health + testability seams | M | LOW | UnitPlan + FullPlan | WS1, WS2, WS3 (per-item) | no |

---

## 6. Workstream Sections

The 13 workstream specs follow verbatim. Each item carries: ID · priority · effort · risk · Problem · Evidence (re-verified at `5fd0abb`) · Change spec · Do NOT · Files to touch · Acceptance criteria · Verify block · Depends on / Blocks.

## WS1: Dead-code deletion + repo hygiene

**Scope (3 lines):** Delete every confirmed-dead UI tree — the legacy 4-tab shell (LegacyHomeTab/PlansTab/ProgressChartView/HealthCheckPromptView + `--use-legacy-ui` + LegacyUITests), the disabled Dashboard UI (Views/Dashboard/*, 10 files), AssessTab + QuickHealthUpdateView, and the `--showcase` harness — each with its reference-graph proof embedded below. Split ContentView.swift so the live OnboardingEditView survives, collapse MainTabView to a ThreeTabView passthrough, remove the dead `totalMinutes`, commit the cosmetic pbxproj diff, and fix stale navigation docs. Net effect: ~3,300 LOC of unreachable code removed with zero behavior change to the shipped app; required test plan for the workstream is **FullPlan**.

**Shared context:** All evidence line numbers were grep-verified at commit `5fd0abb` on branch `coil-rebrand`. App root = `ios/PT-Helper/PT-Helper/` (paths below are relative to repo root `/Users/noyfisher/IOS-Projects/PT-Helper-Agent-v1` unless absolute). The dead-code graph is one connected component anchored on `Views/MainTabView.swift` (263 LOC): `useThreeTabUI` (MainTabView.swift:6-11) is hard-`true` in release because `TestDataSeeder.isUITesting` and `TestDataSeeder.shouldUseLegacyUI` are `#if DEBUG`-gated to `false` (Services/TestDataSeeder.swift:13-19, :53-59), and `useDashboardUI` (:15-21) ends in an unconditional `return false` (:20). So `MainTabView.body` (:145-152) always returns `ThreeTabView()`; the `DashboardMainTabView()` call (:149) and `existingTabView` (:155-262) are unreachable. Xcode 16 `PBXFileSystemSynchronizedRootGroup` means file deletions/additions need **no pbxproj edits**. Execution order that compiles at every step: **WS1-08 → WS1-02 → WS1-01 → WS1-03 → WS1-04 → WS1-05 → WS1-06 → WS1-07 → WS1-09**, one commit per item, single FullPlan run at the end (per-item `xcodebuild build` in between is sufficient). Known project quirk (from project memory, re-verify if hit): if `-destination 'platform=iOS Simulator,name=iPhone 16'` fails to resolve, append `,OS=18.2`. No `.xctestplan` edits are needed anywhere in this workstream: FullPlan/PreReleasePlan include the whole `PT-HelperUITests` target with no `selectedTests`/`skippedTests` arrays (FullPlan.xctestplan:27, PreReleasePlan.xctestplan:28), and SmokePlan/UnitPlan don't include the UITests target at all — verified verbatim at 5fd0abb.

---

### [WS1-01] Collapse MainTabView to a ThreeTabView passthrough and delete the legacy 4-tab shell wiring
`P1` · `effort: M` · `risk: LOW — deleting branches that are provably unreachable in release; LegacyUITests (their only exerciser) deleted in the same commit so FullPlan stays green.

**Problem** — MainTabView carries two dead UI shells (legacy 4-tab TabView and the disabled Dashboard branch) behind flags that can never be true in production. Every future navigation change pays a triple-maintenance tax, and LegacyUITests burns CI time exercising a UI no user can reach.

**Evidence**
- `ios/PT-Helper/PT-Helper/Views/MainTabView.swift:6-11` — `useThreeTabUI` returns `false` only when `TestDataSeeder.isUITesting && TestDataSeeder.shouldUseLegacyUI`.
- `ios/PT-Helper/PT-Helper/Services/TestDataSeeder.swift:13-19, :53-59` — both flags are `#if DEBUG`-gated; hard `false` in release → `useThreeTabUI` is always `true` in production.
- `ios/PT-Helper/PT-Helper/Views/MainTabView.swift:15-21` — `useDashboardUI` ends in unconditional `return false // Dashboard UI disabled in favor of 3-tab layout` (:20).
- `ios/PT-Helper/PT-Helper/Views/MainTabView.swift:145-152` — body: `if useThreeTabUI { ThreeTabView() } else if useDashboardUI { DashboardMainTabView() } else { existingTabView }`.
- `ios/PT-Helper/PT-Helper/Views/MainTabView.swift:155-262` — `existingTabView`: the whole legacy 4-tab TabView (LegacyHomeTab :173, HealthCheckPromptView :181, QuickHealthUpdateView :191, PlansTab :208, ProgressChartView :215, legacy deep-link/analytics handlers :225-262).
- `ios/PT-Helper/PT-Helper/Views/MainTabView.swift:123-143` — MainTabView's `@StateObject`s and health-check `@State` are used only inside `existingTabView` (the ThreeTabView path at :147 injects nothing — ThreeTabView owns its own `@StateObject`s at ThreeTabView.swift:7-12).
- `ios/PT-Helper/PT-HelperUITests/LegacyUITests.swift:3,:5` — sole exerciser of the path: 2 tests (`testFourTabs_Exist`, `testProgressTab_ShowsChart`) launched with `--use-legacy-ui`. Repo-wide grep for `LegacyUITests` = 1 hit (the file itself); no scheme/plan/script references it.
- `grep -rn "useThreeTabUI\|useDashboardUI\|shouldUseLegacyUI\|use-legacy-ui" --include="*.swift" ios/` → hits ONLY in MainTabView.swift, TestDataSeeder.swift:53-55, LegacyUITests.swift:5. Complete blast radius.
- `ios/PT-Helper/PT-Helper/RootView.swift:118,:149` — the two `MainTabView()` call sites; both remain valid with the passthrough (rationale for keeping the struct instead of deleting the file: RootView untouched, and MainTabView.swift also hosts the live `AssessmentRoute` enum :24-29 and `TabSelection` class :32).
- `analyzeNavigationId` external refs = 0 (only MainTabView :42, :80, :113, :200 — all dying here). `homeNavigationId`/`plansNavigationId`/`dashboardNavigationId`/`rehabNavigationId` still have refs in files deleted by WS1-03/04/05 — they are removed THERE, not here, so every intermediate commit compiles.

**Change spec**
1. In `Views/MainTabView.swift`, delete the `useThreeTabUI` computed var **including its doc comment** (lines 3-11) and the `useDashboardUI` var including its doc comment (lines 13-21).
2. In `TabSelection`, delete the `analyzeNavigationId` property (line 42). KEEP — temporarily — `homeNavigationId` (:41), `plansNavigationId` (:43), `dashboardNavigationId` (:47), `rehabNavigationId` (:48): they are still referenced by ContentView.swift:173, PlansTab.swift:46, and DashboardMainTabView.swift:36/:49, which WS1-04/05/03 delete along with the properties. KEEP `progressNavigationId`, `profileNavigationId`, `assessNavigationId`, `myPlanNavigationId` (live via ThreeTabView.swift:47,:52,:57,:62).
3. Replace `func popToRootAndGoHome()` (lines 55-91) in full with:
   ```swift
   func popToRootAndGoHome() {
       if selectedTab == 0 {
           assessNavigationId = UUID()
           return
       }
       switch selectedTab {
       case 1: myPlanNavigationId = UUID()
       case 2: progressNavigationId = UUID()
       case 3: profileNavigationId = UUID()
       default: break
       }
       selectedTab = 0
   }
   ```
   (Preserves the existing comment-documented invariant: never reset the destination tab's nav id and switch tabs in the same pass.)
4. Replace `func popToRootCurrentTab()` (lines 94-120) in full with the `useThreeTabUI` branch's switch only:
   ```swift
   func popToRootCurrentTab() {
       switch selectedTab {
       case 0: assessNavigationId = UUID()
       case 1: myPlanNavigationId = UUID()
       case 2: progressNavigationId = UUID()
       case 3: profileNavigationId = UUID()
       default: break
       }
   }
   ```
5. Replace the whole `struct MainTabView` (lines 122-263, i.e., through end of file) with:
   ```swift
   struct MainTabView: View {
       var body: some View {
           ThreeTabView()
       }
   }
   ```
   This deletes the 5 `@StateObject`s (:123-128), the health-check `@State`s + `needsHealthCheck` (:131-143, note `showHealthCheck` :132 was unused even by the legacy branch), and `existingTabView` (:155-262).
6. In `Services/TestDataSeeder.swift`, delete the `shouldUseLegacyUI` static var (lines 53-59).
7. Delete file `ios/PT-Helper/PT-HelperUITests/LegacyUITests.swift` (34 LOC, 2 tests). No test-plan edit needed (see shared context).

**Do NOT** — do not delete PlansTab/ProgressChartView/HealthCheckPromptView/ContentView/Dashboard files here (WS1-03/04/05 own them, and their temporary TabSelection id refs are why step 2 keeps four ids); do not rename `ThreeTabView` or `assessNavigationId` (naming cleanup is not in scope); do not touch RootView.swift.

**Files to touch**
- `ios/PT-Helper/PT-Helper/Views/MainTabView.swift`
- `ios/PT-Helper/PT-Helper/Services/TestDataSeeder.swift`
- `ios/PT-Helper/PT-HelperUITests/LegacyUITests.swift` (delete)

**Acceptance criteria**
- [ ] `grep -rn "useThreeTabUI\|useDashboardUI\|shouldUseLegacyUI\|use-legacy-ui\|existingTabView\|analyzeNavigationId" --include="*.swift" ios/` returns 0 hits.
- [ ] `test -f ios/PT-Helper/PT-HelperUITests/LegacyUITests.swift` exits 1.
- [ ] `grep -c "DashboardMainTabView()\|LegacyHomeTab()\|PlansTab()\|ProgressChartView()\|HealthCheckPromptView(\|QuickHealthUpdateView" ios/PT-Helper/PT-Helper/Views/MainTabView.swift` returns 0.
- [ ] Build succeeds; FullPlan green (run once at end of workstream).
- [ ] Simulator smoke: app launches to the 4-tab FloatingTabBar shell (Home/My Plan/Progress/Profile + center "+"), identical to `ios/PT-Helper/docs/audit-assets-2026-07-17` baseline screenshots.

**Verify**
```bash
xcodebuild build -project ios/PT-Helper/PT-Helper.xcodeproj \
  -scheme PT-Helper -destination 'platform=iOS Simulator,name=iPhone 16'

xcodebuild test -project ios/PT-Helper/PT-Helper.xcodeproj \
  -scheme PT-Helper -testPlan FullPlan -destination 'platform=iOS Simulator,name=iPhone 16'
```

**Depends on / Blocks** — Depends on nothing. Blocks WS1-03, WS1-04, WS1-05, WS1-06, WS1-09.

---

### [WS1-02] Delete the --showcase screenshot harness (ShowcaseHostView + PT_HelperApp entry)
`P1` · `effort: S` · `risk: LOW — self-described throwaway harness; every view it renders has verified live production call sites.

**Problem** — A screenshot harness whose own header says it was never meant to be merged landed on `coil-rebrand` (commit 04fa28f, not on main). It adds a launch-argument-activated alternate app entry point in the release binary's source and is the second-to-last reference keeping the dead Dashboard tree compiling.

**Evidence**
- `ios/PT-Helper/PT-Helper/ShowcaseHostView.swift:3-5` — header: "SHOWCASE-ONLY HARNESS — lives on the throwaway `compliance/integration-showcase` branch … Never merged into a real branch."
- `ios/PT-Helper/PT-Helper/ShowcaseHostView.swift` — 117 LOC: `ShowcaseHostView` (:6), file-private `ShowcaseSheetBackdrop` (:63), `ShowcaseDashboardWrap` (:78, builds mock `ConditionResult`s :79-98), `ShowcaseIndex` (:109).
- `ios/PT-Helper/PT-Helper/ShowcaseHostView.swift:102` — instantiates `DashDifferentialsTable` → the only reference to Views/Dashboard/ from outside MainTabView + the Dashboard folder itself; this item must land before WS1-03.
- `ios/PT-Helper/PT-Helper/PT_HelperApp.swift:30-36` — `Group { if ProcessInfo.processInfo.arguments.contains("--showcase") { ShowcaseHostView() } else { RootView() } }`; modifier chain `.preferredColorScheme … .task { TestDataSeeder.seedIfNeeded() }` (:37-65) hangs off the Group.
- `grep -rn "showcase" --include="*" .` (excluding .git and audit-assets) → hits only in ShowcaseHostView.swift and PT_HelperApp.swift — no script, doc, or CI reference.
- Liveness of everything the harness renders (so nothing else dies with it): `HealthDataConsentView` → BodyMap3DView.swift:127; `LegalAcceptanceGateView` → RootView.swift:151; `MinorSafetyResourcesView` → RootView.swift:154; all other compliance views have live call sites (verified this session, trailing-closure-aware).

**Change spec**
1. Delete file `ios/PT-Helper/PT-Helper/ShowcaseHostView.swift`.
2. In `PT_HelperApp.swift`, remove the `Group { … }` wrapper and the `--showcase` conditional (lines 30-36), leaving `RootView()` as the WindowGroup's direct child with the entire existing modifier chain (currently :37-65) reattached to it unchanged. (Chosen shape: plain `RootView()` + chain, no Group — the Group existed only for the conditional.)
3. Session-owner note (NOT a Sonnet repo change): auto-memory file `reference_screenshot_showcase.md` (outside the repo) documents this harness and should be updated by the orchestrating session after this lands.

**Do NOT** — do not touch any of the compliance views the harness renders (LegalAcceptanceGateView, HealthDataConsentView, DisclaimerView, etc. — all live); do not delete Views/Dashboard files here (WS1-03).

**Files to touch**
- `ios/PT-Helper/PT-Helper/ShowcaseHostView.swift` (delete)
- `ios/PT-Helper/PT-Helper/PT_HelperApp.swift`

**Acceptance criteria**
- [ ] `grep -rni "showcase" --include="*.swift" ios/` returns 0 hits.
- [ ] `grep -n "RootView()" ios/PT-Helper/PT-Helper/PT_HelperApp.swift` returns exactly 1 hit, and `grep -c "Group {" ios/PT-Helper/PT-Helper/PT_HelperApp.swift` returns 0.
- [ ] Build succeeds; app launches normally on simulator (RootView path unchanged).

**Verify**
```bash
xcodebuild build -project ios/PT-Helper/PT-Helper.xcodeproj \
  -scheme PT-Helper -destination 'platform=iOS Simulator,name=iPhone 16'
```

**Depends on / Blocks** — Depends on nothing. Blocks WS1-03.

---

### [WS1-03] Delete Views/Dashboard/* (10 files, 1,341 LOC) and the last dashboard TabSelection ids
`P1` · `effort: S` · `risk: LOW — pure file deletion; both external references removed by WS1-01/WS1-02 before this lands.

**Problem** — The entire experimental "Manus Concept 2" dashboard UI ships in the binary but is unreachable: its only entry point sat behind `useDashboardUI`, which unconditionally returns false. 1,341 LOC of unmaintained UI silently rots and pollutes every repo-wide sweep (fonts, colors, a11y).

**Evidence**
- Exhaustive file list (LOC, verified by `wc -l`): AnalysisDashboardView.swift 309; DashboardComponents.swift 200; RehabMetricsView.swift 150; DashProfileView.swift 139; DashActivePlansList.swift 102; DashboardMainTabView.swift 102; DashSessionHistoryList.swift 96; DashDifferentialsTable.swift 86; DashPainTrendChart.swift 83; DashExercisePerformanceTable.swift 74. Total 1,341.
- Per-symbol external reference graph (grep of each of the 10 type names repo-wide, all targets incl. tests): every hit is inside Views/Dashboard/ itself EXCEPT `DashboardMainTabView` → MainTabView.swift:149 (removed by WS1-01), `DashDifferentialsTable` → ShowcaseHostView.swift:102 (removed by WS1-02), and `DashboardMainTabView` in a doc comment at Services/NotificationService.swift:41. Zero references from PT-HelperTests or PT-HelperUITests (ShellNavigationUITests.swift:5 mentions "retired Dashboard tests" in a comment only — historical, accurate, leave).
- `ios/PT-Helper/PT-Helper/Views/Dashboard/DashboardMainTabView.swift:36,:49` — the last references to `TabSelection.dashboardNavigationId` / `rehabNavigationId` (WS1-01 deliberately left those two properties in place for this item). `profileNavigationId` (also used at :56) stays — live via ThreeTabView.swift:62.
- `ios/PT-Helper/PT-Helper/Views/Dashboard/DashProfileView.swift:60` — calls the LIVE `OnboardingEditView`; that is a dependency OF the dead code, not a liveness signal (OnboardingEditView's live callers: ThreeTabView.swift:213, ProgressTab.swift:37).

**Change spec**
1. Delete the directory `ios/PT-Helper/PT-Helper/Views/Dashboard/` (all 10 files above; confirm the folder contains exactly those 10 before deleting — anything else = STOP, mark BLOCKED).
2. In `Views/MainTabView.swift`, delete the now-unreferenced `TabSelection` properties `dashboardNavigationId` and `rehabNavigationId` and their `/// Navigation IDs for the 3-tab dashboard layout.` doc comment (post-WS1-01 positions; at 5fd0abb these are :46-48).
3. In `Services/NotificationService.swift:41`, change the doc comment `…consumed by MainTabView/DashboardMainTabView on appear.` → `…consumed by ThreeTabView on appear.`

**Do NOT** — do not port any dashboard widget anywhere: the "last-analysis card on Progress tab" (settled decision D-6) is a separate workstream's item, built fresh from ProgressTab, not salvaged from Dash* code.

**Files to touch**
- `ios/PT-Helper/PT-Helper/Views/Dashboard/` (delete directory, 10 files)
- `ios/PT-Helper/PT-Helper/Views/MainTabView.swift`
- `ios/PT-Helper/PT-Helper/Services/NotificationService.swift`

**Acceptance criteria**
- [ ] `test -d ios/PT-Helper/PT-Helper/Views/Dashboard` exits 1.
- [ ] `grep -rn "DashboardMainTabView\|AnalysisDashboardView\|RehabMetricsView\|DashProfileView\|DashActivePlansList\|DashSessionHistoryList\|DashDifferentialsTable\|DashPainTrendChart\|DashExercisePerformanceTable\|dashboardNavigationId\|rehabNavigationId" --include="*.swift" -r ios/` returns 0 hits.
- [ ] Build succeeds; FullPlan green at end of workstream.

**Verify**
```bash
xcodebuild build -project ios/PT-Helper/PT-Helper.xcodeproj \
  -scheme PT-Helper -destination 'platform=iOS Simulator,name=iPhone 16'
```

**Depends on / Blocks** — Depends on WS1-01, WS1-02. Blocks WS1-09.

---

### [WS1-04] Split ContentView.swift: extract live OnboardingEditView, delete LegacyHomeTab, delete the file
`P1` · `effort: S` · `risk: LOW — mechanical extract-then-delete; OnboardingEditView body moves byte-identical.

**Problem** — ContentView.swift (486 LOC) contains no `ContentView` type at all: it is dead `LegacyHomeTab` (330 LOC) fused to the very-live `OnboardingEditView` (profile editing for the whole app). The dead majority hides the live minority and drags a vestigial FirebaseAuth import.

**Evidence**
- `ios/PT-Helper/PT-Helper/ContentView.swift:4-330` — `struct LegacyHomeTab`; sole instantiation MainTabView.swift:173 (removed by WS1-01). Includes its file-private helpers (heroGreeting/statsRow/recentPlansPreview etc.) and the `.id(tabSelection.homeNavigationId)` ref at :173 — the LAST reference to `TabSelection.homeNavigationId`.
- `ios/PT-Helper/PT-Helper/ContentView.swift:2` — `import FirebaseAuth` is vestigial: `grep -n "Auth" ContentView.swift` → only line 2 itself.
- `ios/PT-Helper/PT-Helper/ContentView.swift:332-486` — `// MARK: - Onboarding Edit Wrapper` (:332) + `struct OnboardingEditView` (:333) through end of file (:486).
- `ios/PT-Helper/PT-Helper/ContentView.swift:438` — uses `UIApplication`/`UIResponder`; compiles today only via transitive imports, so the new file needs explicit `import UIKit`.
- Live callers of `OnboardingEditView`: ThreeTabView.swift:213 (ProfileTab edit sheet — ProfileTab is defined in ThreeTabView.swift:201), ProgressTab.swift:37. Dead callers (ContentView.swift:164 inside LegacyHomeTab; DashProfileView.swift:60) are deleted by this item and WS1-03.
- New-file discovery: Xcode 16 `PBXFileSystemSynchronizedRootGroup` — no pbxproj edit.

**Change spec**
1. Create `ios/PT-Helper/PT-Helper/Views/OnboardingEditView.swift` containing, in order: `import SwiftUI`, `import UIKit`, one blank line, then lines 332-486 of ContentView.swift **verbatim** (the MARK comment + the whole `OnboardingEditView` struct). No other edits to the moved code — restyling is another workstream's scope.
2. Delete `ios/PT-Helper/PT-Helper/ContentView.swift` entirely (lines 1-331 are the vestigial imports + LegacyHomeTab; 332-486 just moved).
3. In `Views/MainTabView.swift`, delete the now-unreferenced `TabSelection.homeNavigationId` property (at 5fd0abb :41).

**Do NOT** — do not restyle, re-token, or otherwise modify OnboardingEditView's body (the COIL re-skin sweeps own styling); do not touch OnboardingViewModel or the step views it hosts.

**Files to touch**
- `ios/PT-Helper/PT-Helper/Views/OnboardingEditView.swift` (create)
- `ios/PT-Helper/PT-Helper/ContentView.swift` (delete)
- `ios/PT-Helper/PT-Helper/Views/MainTabView.swift`

**Acceptance criteria**
- [ ] `test -f ios/PT-Helper/PT-Helper/ContentView.swift` exits 1; `test -f ios/PT-Helper/PT-Helper/Views/OnboardingEditView.swift` exits 0.
- [ ] `grep -rn "LegacyHomeTab\|homeNavigationId" --include="*.swift" ios/` returns 0 hits.
- [ ] `grep -rn "import FirebaseAuth" ios/PT-Helper/PT-Helper/Views/OnboardingEditView.swift` returns 0 hits; `grep -c "import UIKit" ios/PT-Helper/PT-Helper/Views/OnboardingEditView.swift` returns 1.
- [ ] Diff check: the extracted struct is byte-identical to ContentView.swift:332-486 at 5fd0abb (`git show 5fd0abb:ios/PT-Helper/PT-Helper/ContentView.swift | sed -n '332,486p' | diff - <(tail -n +4 ios/PT-Helper/PT-Helper/Views/OnboardingEditView.swift)` → empty).
- [ ] Simulator smoke: Profile tab → Edit opens the profile editor; Progress tab profile edit path also opens it.

**Verify**
```bash
xcodebuild build -project ios/PT-Helper/PT-Helper.xcodeproj \
  -scheme PT-Helper -destination 'platform=iOS Simulator,name=iPhone 16'
```

**Depends on / Blocks** — Depends on WS1-01. Blocks WS1-09.

---

### [WS1-05] Delete legacy-orphaned view files: PlansTab, ProgressChartView, HealthCheckPromptView
`P1` · `effort: S` · `risk: LOW — each file has exactly one caller, inside the branch WS1-01 removed.

**Problem** — Three complete screens survive only as transitive dependencies of the deleted legacy shell. ProgressChartView is additionally a stale near-duplicate of ProgressTab's chart (copy-pasted LineMark/AreaMark/PointMark body, ProgressChartView.swift:99-130 vs ProgressTab.swift:422-453), so keeping it would force every future font/color/a11y sweep to touch an unreachable file.

**Evidence**
- `ios/PT-Helper/PT-Helper/Views/PlansTab.swift` (156 LOC, defines only `struct PlansTab` :3) — sole instantiation MainTabView.swift:208 (deleted in WS1-01). Its `.id(tabSelection.plansNavigationId)` (:46) is the LAST reference to `TabSelection.plansNavigationId`. Remaining repo-wide `PlansTab` hit after deletion: the historical comment at PT-HelperUITests/MyPlanTabUITests.swift:4 ("Replaces the retired legacy PlansTab tests") — accurate history, keep.
- `ios/PT-Helper/PT-Helper/Views/ProgressChartView.swift` (238 LOC, defines only `struct ProgressChartView` :4) — sole instantiation MainTabView.swift:215 (deleted in WS1-01). Its internal `totalMinutes` (:235-237, used at :189) dies with the file — distinct from WS1-07's dead property.
- `ios/PT-Helper/PT-Helper/Views/HealthCheckPromptView.swift` (71 LOC, defines only `struct HealthCheckPromptView` :5) — sole instantiation MainTabView.swift:181 (deleted in WS1-01).
- `ios/PT-Helper/PT-Helper/Views/RecoveryInsightsCardView.swift:4` — doc comment "Used in ProgressChartView and HomeTab." is doubly stale: actual call sites are ProgressTab.swift:98 (live) and ProgressChartView.swift:29 (dying here). RecoveryInsightsCardView itself STAYS (live via ProgressTab).
- Zero references to any of the three types from PT-HelperTests or PT-HelperUITests (grep verified).

**Change spec**
1. Delete `ios/PT-Helper/PT-Helper/Views/PlansTab.swift`.
2. Delete `ios/PT-Helper/PT-Helper/Views/ProgressChartView.swift`.
3. Delete `ios/PT-Helper/PT-Helper/Views/HealthCheckPromptView.swift`.
4. In `Views/MainTabView.swift`, delete the now-unreferenced `TabSelection.plansNavigationId` property (at 5fd0abb :43).
5. In `Views/RecoveryInsightsCardView.swift:4`, change the doc comment to `/// Used in ProgressTab.`

**Do NOT** — do not touch ProgressTab.swift's live chart or RecoveryInsightsCardView's body; do not delete QuickHealthUpdateView here (WS1-06 owns it — it still has a caller in dead-but-compiling AssessTab).

**Files to touch**
- `ios/PT-Helper/PT-Helper/Views/PlansTab.swift` (delete)
- `ios/PT-Helper/PT-Helper/Views/ProgressChartView.swift` (delete)
- `ios/PT-Helper/PT-Helper/Views/HealthCheckPromptView.swift` (delete)
- `ios/PT-Helper/PT-Helper/Views/MainTabView.swift`
- `ios/PT-Helper/PT-Helper/Views/RecoveryInsightsCardView.swift`

**Acceptance criteria**
- [ ] `grep -rn "ProgressChartView\|HealthCheckPromptView\|plansNavigationId" --include="*.swift" ios/` returns 0 hits.
- [ ] `grep -rn "PlansTab" --include="*.swift" ios/` returns exactly 1 hit: the MyPlanTabUITests.swift:4 comment.
- [ ] Build succeeds; FullPlan green at end of workstream.

**Verify**
```bash
xcodebuild build -project ios/PT-Helper/PT-Helper.xcodeproj \
  -scheme PT-Helper -destination 'platform=iOS Simulator,name=iPhone 16'
```

**Depends on / Blocks** — Depends on WS1-01. Blocks WS1-09.

---

### [WS1-06] Delete AssessTab.swift and QuickHealthUpdateView.swift
`P2` · `effort: S` · `risk: LOW — AssessTab has zero callers today; QuickHealthUpdateView's two callers are both in the dead set.

**Problem** — AssessTab (384 LOC) is the abandoned tab-0 gateway from the pre-FloatingTabBar IA; the live gateway is AssessmentGatewayView presented from ThreeTabView's full-screen cover. It in turn is the last thing keeping QuickHealthUpdateView (399 LOC) alive. 783 LOC of ghost assessment UI that confuses every "where does assessment start?" question.

**Evidence**
- `grep -rn "AssessTab" --include="*.swift" ios/` (app + unit tests + UI tests) → exactly 2 hits, both inside its own file: `struct AssessTab` (Views/AssessTab.swift:5) and `.trackScreen("AssessTab")` (:173). Also 0 hits in pbxproj/xctestplan/plist. Zero callers.
- Live gateway: `ThreeTabView.swift:141` — `AssessmentGatewayView()` inside `assessmentDestination(for:)` (:138), presented via the `fullScreenCover(item: $tabSelection.assessmentRequest)` (:93) set by the floating "+" (:75).
- `grep -rn "QuickHealthUpdateView" --include="*.swift" ios/` → definition (Views/QuickHealthUpdateView.swift:8, sole top-level type in the file, 399 LOC) + 2 callers: MainTabView.swift:191 (legacy branch, deleted in WS1-01) and AssessTab.swift:168 (deleted here). After both, zero callers.
- AssessTab's other dependencies (WellnessGoalPickerView, BodyMap3DView, etc.) all have live call sites elsewhere — nothing else dies with it.

**Change spec**
1. Delete `ios/PT-Helper/PT-Helper/Views/AssessTab.swift`.
2. Delete `ios/PT-Helper/PT-Helper/Views/QuickHealthUpdateView.swift`.

**Do NOT** — do not touch AssessmentGatewayView, WellnessGoalPickerView, or BodyMap3DView (live assessment flow); do not remove the `AssessmentRoute` enum or `assessmentRequest` plumbing in MainTabView.swift/ThreeTabView.swift (live).

**Files to touch**
- `ios/PT-Helper/PT-Helper/Views/AssessTab.swift` (delete)
- `ios/PT-Helper/PT-Helper/Views/QuickHealthUpdateView.swift` (delete)

**Acceptance criteria**
- [ ] `grep -rn "AssessTab\|QuickHealthUpdateView" --include="*.swift" ios/` returns 0 hits.
- [ ] Simulator smoke: floating "+" still opens the assessment gateway (pain / wellness dual choice), matching the audit baseline screenshots.
- [ ] Build succeeds; FullPlan green at end of workstream.

**Verify**
```bash
xcodebuild build -project ios/PT-Helper/PT-Helper.xcodeproj \
  -scheme PT-Helper -destination 'platform=iOS Simulator,name=iPhone 16'
```

**Depends on / Blocks** — Depends on WS1-01 (removes the MainTabView:191 caller). Blocks WS1-09.

---

### [WS1-07] Remove dead ProgressTabContent.totalMinutes
`P3` · `effort: S` · `risk: NONE — private computed property with zero references, even in its own file.

**Problem** — A leftover private computed property survives because Swift emits no unused-private-property warning for computed vars. Trivial, but it is the workstream's canary that reference-graph hygiene extends below file granularity.

**Evidence**
- `ios/PT-Helper/PT-Helper/Views/ProgressTab.swift:584-586` — `private var totalMinutes: Int { … }` inside `struct ProgressTabContent` (:45). `grep -n "totalMinutes" ProgressTab.swift` → exactly 1 hit: the definition. Zero uses.
- Not to be confused with `ProgressChartView.totalMinutes` (:235-237, used at :189) — a different property on a different type, deleted whole-file by WS1-05. These are the only 2 `totalMinutes` definitions repo-wide.

**Change spec**
1. In `Views/ProgressTab.swift`, delete lines 584-586 (the `totalMinutes` computed var) plus its preceding blank line.

**Do NOT** — do not touch ProgressTab's session-stat computations that ARE used, and do not "fix" ProgressChartView (WS1-05 deletes it).

**Files to touch**
- `ios/PT-Helper/PT-Helper/Views/ProgressTab.swift`

**Acceptance criteria**
- [ ] `grep -n "totalMinutes" ios/PT-Helper/PT-Helper/Views/ProgressTab.swift` returns 0 hits (and after WS1-05, `grep -rn "totalMinutes" --include="*.swift" ios/` returns 0 repo-wide).
- [ ] Build succeeds.

**Verify**
```bash
xcodebuild build -project ios/PT-Helper/PT-Helper.xcodeproj \
  -scheme PT-Helper -destination 'platform=iOS Simulator,name=iPhone 16'
```

**Depends on / Blocks** — nothing.

---

### [WS1-08] Commit the cosmetic pbxproj diff (unquoted CFBundleDisplayName)
`P3` · `effort: S` · `risk: NONE — semantically identical serialization; verified 2-line diff.

**Problem** — An uncommitted 2-line pbxproj diff has been sitting in the working tree, polluting `git status` for every session and risking accidental inclusion in an unrelated commit.

**Evidence**
- `git diff ios/PT-Helper/PT-Helper.xcodeproj/project.pbxproj` at 5fd0abb → exactly 2 hunks: `INFOPLIST_KEY_CFBundleDisplayName = "COIL";` → `= COIL;` in the app target's Debug (~:469) and Release (~:500) build configurations. Nothing else.
- Old-style-plist pbxproj format permits unquoted tokens for plain alphanumeric strings; dropping the quotes is Xcode's own canonical re-serialization (quotes were only needed pre-rebrand when the display name contained spaces). Display name value unchanged: COIL.

**Change spec**
1. Run this as the FIRST commit of the workstream (clean checkpoint before deletions, per project convention):
   ```bash
   cd /Users/noyfisher/IOS-Projects/PT-Helper-Agent-v1
   git add ios/PT-Helper/PT-Helper.xcodeproj/project.pbxproj
   git commit -m "chore(xcodeproj): accept Xcode's canonical unquoted CFBundleDisplayName serialization"
   ```
2. Stage ONLY that file. The untracked `ios/PT-Helper/docs/audit-assets-2026-07-17/` directory belongs to the audit session — leave it untracked.

**Do NOT** — do not commit audit-assets or any other working-tree change; do not hand-edit the pbxproj.

**Files to touch**
- `ios/PT-Helper/PT-Helper.xcodeproj/project.pbxproj` (commit as-is)

**Acceptance criteria**
- [ ] `git status --porcelain ios/PT-Helper/PT-Helper.xcodeproj` returns empty.
- [ ] `git show --stat HEAD` for that commit lists exactly 1 file changed, 2 insertions, 2 deletions.
- [ ] Build succeeds (display name still COIL on the simulator home screen).

**Verify**
```bash
xcodebuild build -project ios/PT-Helper/PT-Helper.xcodeproj \
  -scheme PT-Helper -destination 'platform=iOS Simulator,name=iPhone 16'
```

**Depends on / Blocks** — nothing (but run FIRST so later commits start from a clean tree).

---

### [WS1-09] Fix stale navigation docs and purge references to deleted files
`P2` · `effort: S` · `risk: NONE — docs only; must land AFTER all code deletions so it documents the real end state.

**Problem** — CLAUDE.md and three other docs describe a 3-tab Assess/My Plan/Progress shell that no longer exists (the shipped shell is 4 tabs + floating "+"), and several docs/skills reference files this workstream deletes. Every future agent session inherits a wrong navigation model from these files.

**Evidence** (all verified at 5fd0abb; the shipped reality: ThreeTabView.swift:44-64 = HomeTab(0)/MyPlanTab(1)/ProgressTab(2)/ProfileTab(3); :75 floating "+" sets `assessmentRequest = .gateway`; :93+:141 full-screen cover presents AssessmentGatewayView; :88 analytics tabNames `["Home", "My Plan", "Progress", "Profile"]`; ThreeTabView.swift:3-5 header already documents the 4-tab reality and historical name)
- `CLAUDE.md:219-222` — "primary navigation container with 3 tabs: Tab 0 Assess / Tab 1 My Plan / Tab 2 Progress" — wrong shell AND wrong tab-0 content.
- `CLAUDE.md:232` — legacy-wrapper note: accurate TODAY, stale after WS1-01.
- `CLAUDE.md:241` — `--use-legacy-ui` launch-arg row: flag deleted in WS1-01.
- `CLAUDE.md:86` — Views listing bullet for `Dashboard/` widgets: deleted in WS1-03.
- `CLAUDE.md:148` — "`AssessTab` provides a dual gateway": AssessTab deleted in WS1-06; the dual gateway is AssessmentGatewayView.
- `docs/ux_flows.md:4-9` — "3-tab layout via ThreeTabView" + legacy-4-tab note.
- `PT-Helper-Documentation.md:248` — "MainTabView injects shared state" (ThreeTabView does); `:296-300` — presents the legacy 4-tab MainTabView as primary navigation; `:398` — "ContentView.swift # HomeTab + OnboardingEditView" (file deleted in WS1-04); `:421` — "MainTabView.swift # 4-tab navigation + shared state injection"; `:429` — "ProgressChartView.swift" row (file deleted in WS1-05).
- `ios/LAYOUT.md:50-52` — ThreeTabView "3-tab" description, MainTabView "Legacy 4-tab wrapper (--use-legacy-ui)", AssessTab row; `:89-94` — QuickHealthUpdateView/HealthCheckPromptView/ProgressChartView/PlansTab rows; `:114` — "Dashboard/ (11 files)"; `:175` — "PlansTabUITests.swift" (file does not exist even at 5fd0abb — UITests dir listing verified).
- `.claude/skills/improve/SKILL.md:272` — `home` profile relaunches with `--use-legacy-ui`; after WS1-01 the flag is a silent no-op and the profile description is wrong.

**Change spec**
1. `CLAUDE.md`: replace the `### Navigation & Shared State` block (:217-232) with the real shell — use exactly this content (adjust surrounding blank lines only):
   ```markdown
   ### Navigation & Shared State
   `MainTabView` is a thin passthrough to `ThreeTabView`; `MainTabView.swift` also hosts the shared `TabSelection` class and `AssessmentRoute` enum. `ThreeTabView` (named for a historical 3-tab IA) is the primary navigation shell with 4 tabs plus a floating "+":
   - **Tab 0: Home** — weekly date strip, today's program + preventative tasks
   - **Tab 1: My Plan** — active plan hero card + saved plans list
   - **Tab 2: Progress** — charts, recovery insights, settings, session history
   - **Tab 3: Profile** — profile summary + edit (`OnboardingEditView`)
   - **Floating "+"** — sets `TabSelection.assessmentRequest = .gateway`, presenting `AssessmentGatewayView` in a full-screen cover (dual gateway: pain analysis or wellness goals)

   `ThreeTabView` injects shared state via `@EnvironmentObject`:
   - `TabSelection` — Cross-tab navigation + assessment routing
   - `SavedPlansViewModel` — Rehab plans (real-time Firestore listener)
   - `WorkoutViewModel` — Workout session tracking
   - `NetworkMonitor` — Connectivity status
   - `RecoveryInsightsViewModel` — Recovery insights state
   - `AnalysisResultStore` — Persisted analysis results
   ```
2. `CLAUDE.md:241`: delete the `--use-legacy-ui` bullet from the launch-args list.
3. `CLAUDE.md:86`: delete the `Dashboard/` bullet from the Views listing.
4. `CLAUDE.md:148`: change "`AssessTab` provides a dual gateway: pain analysis or wellness goals." to "`AssessmentGatewayView` (presented from the floating "+") provides a dual gateway: pain analysis or wellness goals." (rest of the wellness-flow numbered list stays).
5. `docs/ux_flows.md:3-9`: replace the Navigation Structure section with the same 4-tab + floating-"+" description as step 1 (condensed to the doc's list style); delete the legacy-layout note at :9.
6. `PT-Helper-Documentation.md`: :248 change "MainTabView" → "ThreeTabView"; :296-300 replace the 4-tab MainTabView section with the current shell (same content as step 1); :398 change to `OnboardingEditView.swift   # Profile edit wrapper (Views/)` and relocate/remove the ContentView row; :421 change MainTabView row comment to "Thin passthrough to ThreeTabView + TabSelection/AssessmentRoute"; :429 delete the ProgressChartView row.
7. `ios/LAYOUT.md`: :50 update ThreeTabView comment to "4-tab shell (Home / My Plan / Progress / Profile) + floating '+'"; :51 update MainTabView comment to "Thin passthrough + TabSelection"; delete rows for deleted files (:52 AssessTab, :89 QuickHealthUpdateView, :90 HealthCheckPromptView, :92 ProgressChartView, :94 PlansTab, :114 Dashboard/ subtree, :175 PlansTabUITests) and add a row for `OnboardingEditView.swift`; adjust the "(69 files)"-style counts to match `ls | wc -l` reality after WS1-01..06.
8. `.claude/skills/improve/SKILL.md:272`: change the `home` profile launch args to `["--uitesting", "--skip-onboarding", "--seed-mock-data"]` (drop `--use-legacy-ui`).
9. Final sweep gate: `grep -rn "AssessTab\|LegacyHomeTab\|QuickHealthUpdateView\|HealthCheckPromptView\|ProgressChartView\|DashboardMainTabView\|use-legacy-ui\|--showcase" --include="*.md" CLAUDE.md docs/ ios/LAYOUT.md PT-Helper-Documentation.md .claude/skills/` must return 0 hits. (Historical artifacts `virtual-users/results/**` and `ios/PT-Helper/docs/app-improvement-ideas.md` are dated reports — explicitly excluded, do not edit.)

**Do NOT** — do not rewrite doc sections beyond navigation/deleted-file references (broader doc refresh is not in scope); do not touch `virtual-users/results/**`, `ios/PT-Helper/docs/app-improvement-ideas.md`, or anything under `~/.claude` memory (session owner handles memory).

**Files to touch**
- `CLAUDE.md`
- `docs/ux_flows.md`
- `PT-Helper-Documentation.md`
- `ios/LAYOUT.md`
- `.claude/skills/improve/SKILL.md`

**Acceptance criteria**
- [ ] Step 9's grep returns 0 hits.
- [ ] `grep -n "3 tabs\|3-tab" CLAUDE.md docs/ux_flows.md ios/LAYOUT.md` returns 0 hits describing the current shell (historical-name explanation "(named for a historical 3-tab IA)" is the single allowed occurrence).
- [ ] `grep -c "use-legacy-ui" CLAUDE.md .claude/skills/improve/SKILL.md docs/ux_flows.md` returns 0 for each file.

**Verify**
```bash
grep -rn "AssessTab\|LegacyHomeTab\|QuickHealthUpdateView\|HealthCheckPromptView\|ProgressChartView\|DashboardMainTabView\|use-legacy-ui\|--showcase" \
  --include="*.md" CLAUDE.md docs/ ios/LAYOUT.md PT-Helper-Documentation.md .claude/skills/ ; echo "exit=$? (want 1 = no matches)"
```

**Depends on / Blocks** — Depends on WS1-01, WS1-02, WS1-03, WS1-04, WS1-05, WS1-06. Blocks nothing.

---

**Workstream-final verification (run once after WS1-09):**
```bash
xcodebuild build -project ios/PT-Helper/PT-Helper.xcodeproj \
  -scheme PT-Helper -destination 'platform=iOS Simulator,name=iPhone 16'

xcodebuild test -project ios/PT-Helper/PT-Helper.xcodeproj \
  -scheme PT-Helper -testPlan FullPlan -destination 'platform=iOS Simulator,name=iPhone 16'
```
Plus simulator visual compare of the 4-tab shell + floating-"+" gateway against `ios/PT-Helper/docs/audit-assets-2026-07-17/`.

**Skipped (P3, low value):** none — all scope bullets are covered by WS1-01..09. (Session-owner follow-up outside the repo, not a Sonnet item: update auto-memory `reference_screenshot_showcase.md` after WS1-02 lands.)

## WS2: Notification system wiring

Make the Settings reminder toggles real: plan-lifecycle scheduling for `scheduleReminders(for:)`, a working reminder-time picker, re-assessment milestone reminders, a first-workout activation nudge, and schedule/cancel on every toggle change. S14 archaeology verdict is **NEVER WIRED** (born unreachable in 606debe; no caller ever existed on any branch), so this is a **fresh wiring design**, not a restore — per D-8, wiring proceeds (9e9d223's commit message explicitly lists #33/#34 as "Deferred", i.e. a documented to-do, not an intentional kill).

**Shared context (read once, applies to all items).** `NotificationService` (`ios/PT-Helper/PT-Helper/Services/NotificationService.swift`) is a `@MainActor` singleton whose `scheduleReminders(for:)` (:82) and `updateReminderTime(hour:minute:plans:)` (:173-181) are transitively dead; the only working local-notification path is the inactivity nudge (`scheduleInactivityNudge` :150-167, called from `ViewModels/WorkoutViewModel.swift:100`) — use it as the wiring pattern. Plan lifecycle events all flow through `SavedPlansViewModel` (`ViewModels/SavedPlansViewModel.swift`): a real-time Firestore listener (:90-115) fires on every save/edit/delete (including latency-compensated local writes), plan *activation* is "Start This Plan" in `Views/RehabPlanView.swift:912-934` setting `startDate` then calling `savedPlansVM.updatePlan(plan)` (:917), and deletion is `deletePlan` (:333-353). The chosen architecture is a single idempotent **reconciler** inside `NotificationService`: every call wipes all reconciler-owned pending requests (by identifier prefix) and re-schedules from the current plans list — so save/start/edit/delete/complete/toggle/time-change all route through one function and can never double-schedule (risk: must not spam). Settings toggles live in `Views/SettingsView.swift` (:114-124 master, :145-164 time picker, :181-187 workout, :204-210 re-assessment, :227-233 inactivity) and today only log analytics. The permission model stays **opt-in via Settings only** (`isEnabled` defaults `false` at NotificationService.swift:47; the only `requestPermission()` site remains the master toggle) — no new permission-prompt sites anywhere. All items run tests via UnitPlan; the new `NotificationServiceTests` file grows across items. NOTE (from project memory, assumed until it bites): if the destination `name=iPhone 16` errors with "OS:latest ≠ 18.2", append `,OS=18.2` to the `-destination` string.

---

### [WS2-01] Build the reminder reconciliation engine and wire it into the plan lifecycle
`P1` · `effort: M` · `risk: new scheduling behavior on every Firestore listener fire; reconciler must be idempotent or reminders duplicate`

**Problem** — The Settings "Workout Reminders" toggle promises weekly exercise reminders, but `scheduleReminders(for:)` has zero reachable callers, so no plan reminder has ever been registered for any user. Users who start a plan and enable reminders get silence — a broken product promise and a retention lever left on the floor.

**Evidence** —
- `ios/PT-Helper/PT-Helper/Services/NotificationService.swift:82` — `scheduleReminders(for:)` definition; only call site is :179 inside `updateReminderTime`, itself uncalled (S7 CONFIRMED).
- `ios/PT-Helper/PT-Helper/Services/NotificationService.swift:83` — guard checks only `isEnabled, isAuthorized`; ignores `workoutRemindersEnabled`, so even wired it would defy the toggle.
- `ios/PT-Helper/PT-Helper/ViewModels/SavedPlansViewModel.swift:90-115` — Firestore listener; :108 `self.rehabPlans = parsed` is the single point where every plan change (save/start/edit/delete) lands.
- `ios/PT-Helper/PT-Helper/Views/RehabPlanView.swift:915-917` — "Start This Plan" sets `startDate` and routes through `savedPlansVM.updatePlan`.
- `ios/PT-Helper/PT-Helper/Services/StreakService.swift:16` — `init(skipFirebaseLoad: Bool = false)` is the established testable-singleton-init precedent to mirror.
- `ios/PT-Helper/PT-HelperTests/TestFixtures.swift:180` — `makePlan` lacks `startDate`/`weeklySchedule` params needed by the new tests.

**Change spec** —
1. In `NotificationService.swift`, below the imports, add the test seam (non-isolated protocol; `UNUserNotificationCenter`'s existing signatures satisfy it as-is):
   ```swift
   /// Seam for unit-testing scheduling without the real notification center.
   protocol NotificationScheduling: AnyObject {
       func add(_ request: UNNotificationRequest, withCompletionHandler completionHandler: ((Error?) -> Void)?)
       func removePendingNotificationRequests(withIdentifiers identifiers: [String])
       func removeAllPendingNotificationRequests()
       func pendingNotificationRequests() async -> [UNNotificationRequest]
   }
   extension UNUserNotificationCenter: NotificationScheduling {}
   ```
2. Replace `private init()` (:44) with `init(center: NotificationScheduling = UNUserNotificationCenter.current(), defaults: UserDefaults = .standard, skipAuthCheck: Bool = false)` (mirrors `StreakService(skipFirebaseLoad:)`). Store `private let center: NotificationScheduling` and `private let defaults: UserDefaults`; end init with `if !skipAuthCheck { checkAuthorizationStatus() }`. `static let shared = NotificationService()` stays unchanged.
3. Replace every `UserDefaults.standard` in this file (12 refs: :14, :17, :20, :30, :33, :36, :45-:50) with `defaults`. Replace `UNUserNotificationCenter.current()` with `center` at :88 (scheduleReminders), :131 (cancelReminders), :136 (removeAll inside cancelAllReminders — keep the `setBadgeCount(0)` at :137 on `UNUserNotificationCenter.current()`; badge is not in the protocol), :162 (nudge add), :170 (nudge cancel). Leave :58 (`requestAuthorization`) and :72 (`getNotificationSettings`) on the real center — auth is not under test.
4. In `Models/RehabPlan.swift`, directly below `currentWeek` (:37), add:
   ```swift
   /// True once the plan's full duration has elapsed (started plans only).
   var isCompleted: Bool {
       guard let start = startDate else { return false }
       let days = Calendar.current.dateComponents([.day], from: start, to: Date()).day ?? 0
       return days >= totalWeeks * 7
   }
   ```
5. In `NotificationService.swift`, tighten the `scheduleReminders` guard (:83) to `guard isEnabled, isAuthorized, workoutRemindersEnabled else { return }`, and after `content.badge = 1` (:109) add `content.userInfo = ["tab": "plans"]` — taps then route to My Plan via the existing deep-link chain (`PT_HelperApp.swift:102-106` → `ThreeTabView.swift` `handleDeepLink`, case `"plans"` → tab 1).
6. Add the reconciler after `cancelAllReminders()` (:138):
   ```swift
   // MARK: - Plan-lifecycle reconciliation (WS2)

   /// Last plans list handed over by SavedPlansViewModel's listener; lets
   /// Settings toggles resync without view-layer plumbing (SettingsView is
   /// presented from three contexts, one of them dead code — no @EnvironmentObject).
   private(set) var lastKnownPlans: [RehabPlan] = []

   /// Identifier prefixes owned by the reconciler; every pass removes all
   /// pending requests with these prefixes, then re-schedules from scratch.
   static let reconciledPrefixes = ["plan-", "reassess-", "activation-"]

   /// The one plan that gets weekly workout reminders: most recently started,
   /// not yet completed. Single plan only — two overlapping schedules would
   /// fire duplicate same-minute alerts (spam) and burn the 64-pending cap.
   static func reminderEligiblePlan(from plans: [RehabPlan]) -> RehabPlan? {
       plans.filter { $0.startDate != nil && !$0.isCompleted }
           .max { ($0.startDate ?? .distantPast) < ($1.startDate ?? .distantPast) }
   }

   /// Store the latest plans and reconcile all plan-derived notifications.
   func syncPlanReminders(plans: [RehabPlan]) async {
       lastKnownPlans = plans
       await reconcile()
   }

   /// Re-run reconciliation with the last known plans (Settings toggles / time picker).
   func resyncReminders() async {
       await reconcile()
   }

   private func reconcile() async {
       let pending = await center.pendingNotificationRequests()
       let stale = pending.map(\.identifier)
           .filter { id in Self.reconciledPrefixes.contains { id.hasPrefix($0) } }
       center.removePendingNotificationRequests(withIdentifiers: stale)

       guard isEnabled, isAuthorized else { return }
       if workoutRemindersEnabled, let active = Self.reminderEligiblePlan(from: lastKnownPlans) {
           scheduleReminders(for: active)
       }
       // WS2-03 appends re-assessment scheduling here; WS2-04 the activation nudge.
   }
   ```
7. Wire `SavedPlansViewModel` (3 call sites, all it needs): (a) in the listener callback after `self.runRepairPass(on: parsed)` (:113) add `await NotificationService.shared.syncPlanReminders(plans: parsed)` (the enclosing closure is already `Task { @MainActor in … }`); (b) in `updatePlan` after the local array mutation block (:272-274) add `Task { await NotificationService.shared.syncPlanReminders(plans: rehabPlans) }`; (c) in `deletePlan` after `rehabPlans.removeAll { … }` (:341) add the same `Task { … }` line. Do NOT add a sync call in the UI-testing seeded branch of `init` (:32-34) — `isEnabled` defaults false and UI tests must stay prompt-free.
8. Extend `TestFixtures.makePlan` (:180) with two additive defaulted params: `startDate: Date? = nil` and `weeklySchedule: [[String]]? = nil`; pass `weeklySchedule: weeklySchedule ?? Array(repeating: [], count: 7)` and `startDate: startDate` into the `RehabPlan` init (memberwise init already accepts `startDate`; existing callers unaffected).
9. New file `ios/PT-Helper/PT-HelperTests/Mocks/MockNotificationCenter.swift`: `final class MockNotificationCenter: NotificationScheduling` recording `addedRequests: [UNNotificationRequest]`, `removedIdentifiers: [String]`, `removeAllCallCount: Int`, with a settable `pendingStub: [UNNotificationRequest]`; `add` appends + calls completion with nil; `pendingNotificationRequests()` returns `pendingStub + addedRequests`. (If the build trips a Sendable diagnostic, mark it `@unchecked Sendable`.)
10. New file `ios/PT-Helper/PT-HelperTests/Services/NotificationServiceTests.swift` (`@MainActor final class NotificationServiceTests: XCTestCase`). `setUp` creates the mock and `UserDefaults(suiteName: "NotificationServiceTests")` with `removePersistentDomain` reset; `makeSUT(enabled: Bool = true, authorized: Bool = true)` builds `NotificationService(center:defaults:skipAuthCheck: true)` then sets `isEnabled`/`isAuthorized`. Tests (project naming convention `test<What>_<Condition>_<Expected>`):
    - `testReminderEligiblePlan_twoStartedPlans_picksMostRecentlyStarted`
    - `testReminderEligiblePlan_unstartedAndCompletedPlans_returnsNil`
    - `testIsCompleted_startedPastDuration_true`, `testIsCompleted_withinDuration_false`, `testIsCompleted_unstarted_false`
    - `testSync_startedPlanWithThreeScheduledDays_addsThreeRequestsWithPlanPrefix`
    - `testSync_unstartedPlan_schedulesNothing`
    - `testSync_masterDisabled_removesStalePlanRequestsAndAddsNone` (seed `pendingStub` with a `plan-`-prefixed request)
    - `testSync_workoutToggleOff_schedulesNoWorkoutReminders`
    - `testSync_twoStartedPlans_schedulesOnlyMostRecent`
    - `testScheduleReminders_userInfo_routesToPlansTab`

**Do NOT** — touch the inactivity-nudge logic (:150-171) beyond the mechanical `center`/`defaults` substitution, add any new `requestPermission()` call site, or build per-day exercise programming (D-7: that is an Appendix-A bet; WS10 owns the date strip).

**Files to touch** —
- `ios/PT-Helper/PT-Helper/Services/NotificationService.swift`
- `ios/PT-Helper/PT-Helper/Models/RehabPlan.swift`
- `ios/PT-Helper/PT-Helper/ViewModels/SavedPlansViewModel.swift`
- `ios/PT-Helper/PT-HelperTests/TestFixtures.swift`
- `ios/PT-Helper/PT-HelperTests/Mocks/MockNotificationCenter.swift` (new)
- `ios/PT-Helper/PT-HelperTests/Services/NotificationServiceTests.swift` (new)

**Acceptance criteria** —
- [ ] `grep -c "UserDefaults.standard" ios/PT-Helper/PT-Helper/Services/NotificationService.swift` → `0`
- [ ] `grep -c "syncPlanReminders" ios/PT-Helper/PT-Helper/ViewModels/SavedPlansViewModel.swift` → `3`
- [ ] `grep -c "guard isEnabled, isAuthorized, workoutRemindersEnabled" ios/PT-Helper/PT-Helper/Services/NotificationService.swift` → `1`
- [ ] `grep -c "var isCompleted" ios/PT-Helper/PT-Helper/Models/RehabPlan.swift` → `1`
- [ ] All 9+ new `NotificationServiceTests` methods pass (single-class command below)
- [ ] Full UnitPlan green (no regressions in `WeeklyScheduleTests`, `StreakServiceTests`, plan-parsing suites)

**Verify** — run from `/Users/noyfisher/IOS-Projects/PT-Helper-Agent-v1`:
```bash
xcodebuild build -project ios/PT-Helper/PT-Helper.xcodeproj \
  -scheme PT-Helper -destination 'platform=iOS Simulator,name=iPhone 16'

xcodebuild test -project ios/PT-Helper/PT-Helper.xcodeproj \
  -scheme PT-Helper -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:PT-HelperTests/NotificationServiceTests

xcodebuild test -project ios/PT-Helper/PT-Helper.xcodeproj \
  -scheme PT-Helper -destination 'platform=iOS Simulator,name=iPhone 16'
```

**Depends on / Blocks** — depends on nothing; blocks WS2-02, WS2-03, WS2-04.

---

### [WS2-02] Make the Settings toggles, time picker, and sign-out honor notification state
`P1` · `effort: S` · `risk: toggle-off must actually cancel pending requests or users get "disabled" reminders — the worst spam failure`

**Problem** — Every reminder control in Settings is a placebo: the master toggle only requests permission, the time picker writes hours nobody reads back for scheduling, the workout/inactivity toggles only log analytics, and disabling anything cancels nothing. Sign-out clears the FCM token but leaves local reminders pending for whoever holds the device next.

**Evidence** —
- `ios/PT-Helper/PT-Helper/Views/SettingsView.swift:147-154` — DatePicker onChange writes `reminderHour`/`reminderMinute` directly (:149-150), bypassing any reschedule (S9 CONFIRMED: `updateReminderTime` has zero callers).
- `ios/PT-Helper/PT-Helper/Views/SettingsView.swift:117-124` — master toggle onChange: analytics + permission request on enable; nothing on disable.
- `ios/PT-Helper/PT-Helper/Views/SettingsView.swift:183-187, :229-233` — workout / inactivity toggle onChange: analytics only; toggling inactivity OFF leaves a pending nudge live.
- `ios/PT-Helper/PT-Helper/Services/NotificationService.swift:173-181` — `updateReminderTime(hour:minute:plans:)` takes a `plans:` param no caller can supply post-WS2-01 (the service now caches `lastKnownPlans`).
- `ios/PT-Helper/PT-Helper/RootView.swift:76` — sign-out branch calls `clearFCMToken()` but never cancels local pending reminders.

**Change spec** —
1. In `NotificationService.swift`, replace `updateReminderTime(hour:minute:plans:)` (:173-181) wholesale with:
   ```swift
   /// Update reminder time and reschedule everything the reconciler owns.
   func updateReminderTime(hour: Int, minute: Int) {
       reminderHour = hour
       reminderMinute = minute
       Task { await resyncReminders() }
   }
   ```
   (Zero external callers exist, so the signature change is safe by construction.)
2. `SettingsView.swift` DatePicker onChange (:147-154): keep the analytics lines; replace the two direct writes (:149-150) with `notificationService.updateReminderTime(hour: components.hour ?? 9, minute: components.minute ?? 0)`. Leave the onAppear seed-read (:155-164, audit #81) untouched.
3. `SettingsView.swift` master toggle onChange (:117-124): keep analytics, replace the permission block with:
   ```swift
   if enabled {
       Task {
           if !notificationService.isAuthorized {
               _ = await notificationService.requestPermission()
           }
           await notificationService.resyncReminders()
       }
   } else {
       notificationService.cancelAllReminders()
   }
   ```
   (Denied permission → `reconcile()`'s `isAuthorized` guard no-ops; nothing schedules. No other permission-prompt site is added.)
4. `SettingsView.swift` workout toggle onChange (:183-187): append `Task { await notificationService.resyncReminders() }` after the analytics call (covers both directions: off → reconcile wipes `plan-` requests and re-adds none; on → schedules).
5. `SettingsView.swift` inactivity toggle onChange (:229-233): append `if !enabled { notificationService.cancelInactivityNudge() }`. (On-enable schedules nothing until the next workout — matches the nudge's reset-on-workout semantics at `WorkoutViewModel.swift:100`.)
6. `RootView.swift` sign-out branch: immediately after `NotificationService.shared.clearFCMToken()` (:76) add `NotificationService.shared.cancelAllReminders()`.
7. Append to `NotificationServiceTests.swift`:
   - `testUpdateReminderTime_persistsHourAndMinute` (assert `reminderHour`/`reminderMinute` and the `defaults` keys `notif_reminder_hour`/`notif_reminder_minute`)
   - `testResync_afterTimeChange_reschedulesActivePlanAtNewTime` (set time, `await sut.resyncReminders()`, assert the added requests' `UNCalendarNotificationTrigger.dateComponents.hour/minute` match)
   - `testCancelAllReminders_callsRemoveAllOnCenter` (mock `removeAllCallCount == 1`)

**Do NOT** — restyle Settings rows, add an authorization-denied warning UI (skipped P3 below), or touch FCM token upload/clear logic beyond the one added line in RootView.

**Files to touch** —
- `ios/PT-Helper/PT-Helper/Services/NotificationService.swift`
- `ios/PT-Helper/PT-Helper/Views/SettingsView.swift`
- `ios/PT-Helper/PT-Helper/RootView.swift`
- `ios/PT-Helper/PT-HelperTests/Services/NotificationServiceTests.swift`

**Acceptance criteria** —
- [ ] `grep -c "notificationService.reminderHour = " ios/PT-Helper/PT-Helper/Views/SettingsView.swift` → `0` (direct writes gone)
- [ ] `grep -c "updateReminderTime" ios/PT-Helper/PT-Helper/Views/SettingsView.swift` → `1`
- [ ] `grep -c "resyncReminders" ios/PT-Helper/PT-Helper/Views/SettingsView.swift` → `2` (master + workout; becomes 3 after WS2-03)
- [ ] `grep -c "cancelInactivityNudge" ios/PT-Helper/PT-Helper/Views/SettingsView.swift` → `1`
- [ ] `grep -c "cancelAllReminders" ios/PT-Helper/PT-Helper/RootView.swift` → `1`
- [ ] `grep -c "func updateReminderTime(hour: Int, minute: Int)" ios/PT-Helper/PT-Helper/Services/NotificationService.swift` → `1` (old `plans:` signature gone)
- [ ] New tests pass; full UnitPlan green

**Verify** — run from `/Users/noyfisher/IOS-Projects/PT-Helper-Agent-v1`:
```bash
xcodebuild build -project ios/PT-Helper/PT-Helper.xcodeproj \
  -scheme PT-Helper -destination 'platform=iOS Simulator,name=iPhone 16'

xcodebuild test -project ios/PT-Helper/PT-Helper.xcodeproj \
  -scheme PT-Helper -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:PT-HelperTests/NotificationServiceTests

xcodebuild test -project ios/PT-Helper/PT-Helper.xcodeproj \
  -scheme PT-Helper -destination 'platform=iOS Simulator,name=iPhone 16'
```

**Depends on / Blocks** — depends on WS2-01; blocks nothing.

---

### [WS2-03] Schedule re-assessment reminders at plan midpoint and completion (audit #33)
`P2` · `effort: S` · `risk: milestone math must mirror ReAssessmentViewModel's week logic or the notification lands when no in-app prompt is showing`

**Problem** — The "Re-Assessment Prompts" toggle gates nothing: `reassessmentRemindersEnabled` has zero functional readers, and the in-app re-assessment prompt only appears if the user happens to open their plan during the right week. Users who drift away mid-plan — exactly the ones re-assessment is for — never get pulled back.

**Evidence** —
- `ios/PT-Helper/PT-Helper/Services/NotificationService.swift:32-34, :49` — `reassessmentRemindersEnabled` declared/persisted, default true; zero scheduling readers (S8 CONFIRMED).
- `ios/PT-Helper/PT-Helper/Views/SettingsView.swift:204-210` — toggle onChange logs analytics only.
- `ios/PT-Helper/PT-Helper/ViewModels/ReAssessmentViewModel.swift:14-29` — in-app prompt logic: midpoint `= max(totalWeeks / 2, 1)`, completion at `week >= totalWeeks`; `currentWeek = days/7 + 1` means week W begins on day `(W-1)*7`. The notification fire dates below reproduce exactly this.
- `git log -1 9e9d223` — "#33 reassessment reminders" explicitly deferred for "cross-cutting plan-lifecycle wiring" — which WS2-01 now provides.

**Change spec** —
1. In `NotificationService.swift`, add below `scheduleReminders(for:)`:
   ```swift
   // MARK: - Re-assessment reminders (audit #33)

   /// Midpoint + completion one-shot reminders mirroring the in-app prompt
   /// (ReAssessmentViewModel.shouldShowReAssessment). Fires on the FIRST DAY of
   /// the milestone week at the user's reminder time; past dates are skipped.
   func scheduleReassessmentReminders(for plan: RehabPlan) {
       guard isEnabled, isAuthorized, reassessmentRemindersEnabled,
             let start = plan.startDate else { return }

       let midpointWeek = max(plan.totalWeeks / 2, 1)
       var milestones: [(suffix: String, week: Int, title: String, body: String)] = []
       if midpointWeek < plan.totalWeeks {
           milestones.append(("midpoint", midpointWeek,
               "Halfway there — quick check-in",
               "\(plan.planName): compare today's pain to week 1 with a 2-minute re-assessment."))
       }
       milestones.append(("completion", plan.totalWeeks,
           "Final week — see your progress",
           "\(plan.planName): run your final re-assessment to see how far you've come."))

       for milestone in milestones {
           guard let fireDay = Calendar.current.date(byAdding: .day,
                                                     value: (milestone.week - 1) * 7,
                                                     to: start) else { continue }
           var comps = Calendar.current.dateComponents([.year, .month, .day], from: fireDay)
           comps.hour = reminderHour
           comps.minute = reminderMinute
           guard let fireDate = Calendar.current.date(from: comps), fireDate > Date() else { continue }
           let content = UNMutableNotificationContent()
           content.title = milestone.title
           content.body = milestone.body
           content.sound = .default
           content.userInfo = ["tab": "plans"]
           let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
           let request = UNNotificationRequest(
               identifier: "reassess-\(plan.id.uuidString)-\(milestone.suffix)",
               content: content, trigger: trigger)
           center.add(request) { error in
               if let error {
                   AppLogger.data.error("Failed to schedule re-assessment reminder: \(error.localizedDescription)")
               }
           }
       }
   }
   ```
   Known, accepted limitation: the service does not read `AssessmentSnapshot`s, so a user who already re-assessed early still gets the notification; the tap lands on My Plan where the in-app gate (`shouldShowReAssessment`) simply shows nothing. One stray tap beats coupling NotificationService to Firestore assessments.
2. In `reconcile()` (added by WS2-01), after the workout-reminder block insert:
   ```swift
   if reassessmentRemindersEnabled {
       for plan in lastKnownPlans where plan.startDate != nil && !plan.isCompleted {
           scheduleReassessmentReminders(for: plan)
       }
   }
   ```
   (All started, non-completed plans — not just the active one: these are rare one-shots, max 2 per plan, plan-specific dates. The `reassess-` prefix is already in `reconciledPrefixes`, so completion/deletion cancels them automatically.)
3. `SettingsView.swift` re-assessment toggle onChange (:206-210): append `Task { await notificationService.resyncReminders() }` after the analytics call.
4. Append to `NotificationServiceTests.swift` (use `TestFixtures.makePlan(startDate:)`; set `sut.reminderHour = 23; sut.reminderMinute = 59` where "today" fire dates must stay in the future):
   - `testReassessment_fourWeekPlanStartedToday_schedulesMidpointAndCompletion` (2 requests, ids `reassess-<id>-midpoint` / `-completion`, trigger day components == start+7d and start+21d)
   - `testReassessment_oneWeekPlan_schedulesOnlyCompletion`
   - `testReassessment_startedThreeWeeksAgo_skipsPastMidpoint` (totalWeeks 4 → only completion scheduled)
   - `testReassessment_toggleOff_schedulesNone`
   - `testSync_completedPlan_schedulesNoReassessmentReminders`

**Do NOT** — modify `ReAssessmentViewModel` or the in-app prompt at `RehabPlanView.swift:89`; do not attempt assessment-aware dedupe (limitation accepted above).

**Files to touch** —
- `ios/PT-Helper/PT-Helper/Services/NotificationService.swift`
- `ios/PT-Helper/PT-Helper/Views/SettingsView.swift`
- `ios/PT-Helper/PT-HelperTests/Services/NotificationServiceTests.swift`

**Acceptance criteria** —
- [ ] `grep -c "scheduleReassessmentReminders" ios/PT-Helper/PT-Helper/Services/NotificationService.swift` → `2` (definition + reconcile call)
- [ ] `grep -c "reassess-" ios/PT-Helper/PT-Helper/Services/NotificationService.swift` → `2` (prefix list + identifier)
- [ ] `grep -c "resyncReminders" ios/PT-Helper/PT-Helper/Views/SettingsView.swift` → `3`
- [ ] The 5 new tests pass; full UnitPlan green

**Verify** — run from `/Users/noyfisher/IOS-Projects/PT-Helper-Agent-v1`:
```bash
xcodebuild build -project ios/PT-Helper/PT-Helper.xcodeproj \
  -scheme PT-Helper -destination 'platform=iOS Simulator,name=iPhone 16'

xcodebuild test -project ios/PT-Helper/PT-Helper.xcodeproj \
  -scheme PT-Helper -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:PT-HelperTests/NotificationServiceTests

xcodebuild test -project ios/PT-Helper/PT-Helper.xcodeproj \
  -scheme PT-Helper -destination 'platform=iOS Simulator,name=iPhone 16'
```

**Depends on / Blocks** — depends on WS2-01 (reconciler); independent of WS2-02.

---

### [WS2-04] First-workout activation nudge for freshly started plans (audit #34)
`P2` · `effort: S` · `risk: must self-cancel on first workout or it fires at users who already trained — reconcile guard is the safety`

**Problem** — A user who starts a plan but never does a first workout falls through every notification net: weekly reminders assume engagement, and the 3-day inactivity nudge only ever gets scheduled *after* a workout (`scheduleInactivityNudge` is called on session save). The highest-risk churn moment — plan started, zero sessions — has no touchpoint.

**Evidence** —
- `git log -1 9e9d223` — "#34 first-workout activation nudge" explicitly deferred pending plan-lifecycle wiring (gap-hunt: CONFIRMED unresolved, deliberately deferred).
- `ios/PT-Helper/PT-Helper/Services/NotificationService.swift:150-167` — inactivity nudge is reset-on-workout only; nothing covers the never-worked-out case.
- `ios/PT-Helper/PT-Helper/ViewModels/WorkoutViewModel.swift:100` — the single session-save hook where "user is active" is known; the activation nudge must die here.
- `ios/PT-Helper/PT-Helper/Views/RehabPlanView.swift:915-917` — plan start sets `startDate` → flows into the WS2-01 reconciler, giving the scheduling trigger for free.

**Change spec** —
1. In `NotificationService.swift`, add below the inactivity-nudge section:
   ```swift
   // MARK: - First-workout activation nudge (audit #34)

   private let lastWorkoutAtKey = "notif_last_workout_at"

   /// Called by WorkoutViewModel on session save: records activity, then
   /// reconciles — the guard below sees the fresh timestamp and drops any
   /// pending activation nudge.
   func noteWorkoutCompleted() async {
       defaults.set(Date(), forKey: lastWorkoutAtKey)
       await resyncReminders()
   }

   /// One-shot "do your first session" nudge, 2 days after plan start at the
   /// user's reminder time. Gated by inactivityNudgesEnabled (same "you haven't
   /// trained" family as the 3-day nudge). Past fire dates are skipped.
   private func scheduleActivationNudge(for plan: RehabPlan) {
       guard let start = plan.startDate,
             let fireDay = Calendar.current.date(byAdding: .day, value: 2, to: start) else { return }
       var comps = Calendar.current.dateComponents([.year, .month, .day], from: fireDay)
       comps.hour = reminderHour
       comps.minute = reminderMinute
       guard let fireDate = Calendar.current.date(from: comps), fireDate > Date() else { return }
       let content = UNMutableNotificationContent()
       content.title = "Your plan is ready when you are"
       content.body = "\(plan.planName) — a first session today starts your streak."
       content.sound = .default
       content.userInfo = ["tab": "plans"]
       let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
       let request = UNNotificationRequest(identifier: "activation-\(plan.id.uuidString)",
                                           content: content, trigger: trigger)
       center.add(request) { error in
           if let error {
               AppLogger.data.error("Failed to schedule activation nudge: \(error.localizedDescription)")
           }
       }
   }
   ```
2. In `reconcile()`, after the re-assessment block (or the workout block if WS2-03 hasn't landed), insert:
   ```swift
   if inactivityNudgesEnabled, let active = Self.reminderEligiblePlan(from: lastKnownPlans),
      let start = active.startDate {
       let lastWorkout = defaults.object(forKey: lastWorkoutAtKey) as? Date
       if lastWorkout == nil || lastWorkout! < start {
           scheduleActivationNudge(for: active)
       }
   }
   ```
   (The `activation-` prefix is already in `reconciledPrefixes` from WS2-01, so every pass wipes-then-conditionally-re-adds — idempotent, and a completed workout can never resurrect it.)
3. In `WorkoutViewModel.swift`, directly after `NotificationService.shared.scheduleInactivityNudge()` (:100), add `Task { await NotificationService.shared.noteWorkoutCompleted() }`.
4. Append to `NotificationServiceTests.swift`:
   - `testActivation_freshlyStartedPlanNoWorkouts_schedulesNudgeTwoDaysOut` (start today, `reminderHour = 23`; assert one `activation-`-prefixed request, trigger day == start+2d)
   - `testActivation_workoutLoggedAfterStart_notScheduled` (seed `notif_last_workout_at` after startDate → no `activation-` request)
   - `testActivation_startedThreeDaysAgo_pastFireDateSkipped`
   - `testActivation_inactivityToggleOff_notScheduled`
   - `testNoteWorkoutCompleted_removesPendingActivationNudge` (sync once → nudge added; `await sut.noteWorkoutCompleted()` → its id appears in `removedIdentifiers` and no new `activation-` request added)

**Do NOT** — change `StreakService` calls or the session-save flow beyond the single added line; do not touch `scheduleInactivityNudge` semantics (its reset-on-workout behavior is the WS2 wiring pattern, verified working).

**Files to touch** —
- `ios/PT-Helper/PT-Helper/Services/NotificationService.swift`
- `ios/PT-Helper/PT-Helper/ViewModels/WorkoutViewModel.swift`
- `ios/PT-Helper/PT-HelperTests/Services/NotificationServiceTests.swift`

**Acceptance criteria** —
- [ ] `grep -c "noteWorkoutCompleted" ios/PT-Helper/PT-Helper/ViewModels/WorkoutViewModel.swift` → `1`
- [ ] `grep -c "activation-" ios/PT-Helper/PT-Helper/Services/NotificationService.swift` → `2` (prefix list + identifier)
- [ ] `grep -c "scheduleActivationNudge" ios/PT-Helper/PT-Helper/Services/NotificationService.swift` → `2` (definition + reconcile call)
- [ ] The 5 new tests pass; full UnitPlan green

**Verify** — run from `/Users/noyfisher/IOS-Projects/PT-Helper-Agent-v1`:
```bash
xcodebuild build -project ios/PT-Helper/PT-Helper.xcodeproj \
  -scheme PT-Helper -destination 'platform=iOS Simulator,name=iPhone 16'

xcodebuild test -project ios/PT-Helper/PT-Helper.xcodeproj \
  -scheme PT-Helper -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:PT-HelperTests/NotificationServiceTests

xcodebuild test -project ios/PT-Helper/PT-Helper.xcodeproj \
  -scheme PT-Helper -destination 'platform=iOS Simulator,name=iPhone 16'
```

**Depends on / Blocks** — depends on WS2-01 (reconciler + prefixes); independent of WS2-02/WS2-03.

---

**Skipped (P3, low value):**
- Deep-link `userInfo` on the existing inactivity nudge (tap already opens the app; adding `["tab": "plans"]` is a 1-line nicety with no test surface worth the churn).
- Authorization-denied inline warning row in Settings (master toggle on + permission denied currently fails silent; real but pure-UI polish, and the reconcile guards make it harmless).
- Badge-count hygiene consolidation (badge set at NotificationService.swift:109, cleared in `cancelAllReminders` :137 and on tap in PT_HelperApp.swift:99 — works today; unifying it is refactor-for-taste).

## WS3: MHMDA consent completion + consent-state consolidation

**Scope (3 lines):** Close the grandfathered-user bypass so no health-data flow runs without MHMDA consent; add the policy-promised in-app consent-withdraw path with fully defined downstream effects; make `ConsentService` the single authoritative consent/ToS store (server-absent records clear local mirrors, write failures surfaced, dead/duplicated UserDefaults keys eliminated). Existing 3-site point-of-use gating is verified and preserved as an invariant, not redesigned. Required verification everywhere: UnitPlan + new ConsentService tests + the manual gate-flow check in WS3-01/WS3-02.

**Shared context (read once, applies to every item).** All consent state lives in `ios/PT-Helper/PT-Helper/Services/ConsentService.swift` (`@MainActor` singleton): Firestore docs `users/{uid}/consents/legal` and `users/{uid}/consents/healthData`, mirrored to UserDefaults keys `consent.tosVersion` / `consent.healthDataPolicyVersion` (`MirrorKeys`, ConsentService.swift:22-25). `hasHealthDataConsent` (ConsentService.swift:40-43) is an exact-string compare of the mirror against `LegalContent.healthDataPolicyVersion` (`"2026.07"`, LegalContent.swift:14). Pure decision logic lives in `ios/PT-Helper/PT-Helper/Models/ConsentPolicy.swift` (`enum ConsentPolicy`, line 3) with tests in `ios/PT-Helper/PT-HelperTests/Models/ConsentPolicyTests.swift`. The live shell is `RootView` → `MainTabView`/`ThreeTabView`; assessment flows are presented via `ThreeTabView.assessmentDestination(for:)` (ThreeTabView.swift:138-149 → `BodyMap3DView` at :143, `WellnessGoalPickerView` at :146). The three live just-in-time consent gates all present `HealthDataConsentView` (blocking, `interactiveDismissDisabled`, parent-driven dismissal — "Gotcha #1/#2" comments): OnboardingView.swift:129-135, WellnessGoalPickerView.swift:50-60 + :182-190, BodyMap3DView.swift:120-128 + :772-783. Sign-out clears mirrors (RootView.swift:84); account deletion clears them via `clearAllLocalUserData()` (SettingsView.swift:558-570). Recommended execution order: **WS3-03 → WS3-01 → WS3-02 → WS3-04 → WS3-05 → WS3-06** (01/02/03 touch overlapping files; 03 lands the reconciliation primitives the others build on).

---

### [WS3-01] Close the grandfathered-user consent bypass with a launch-time health-consent gate
`P1` · `effort: M` · `risk: HIGH — a wrong gate predicate locks consented users out of the whole app, or fullScreenCover contention (legal gate / minor-safety / health gate) deadlocks launch`

**Problem** — The three just-in-time gates cover only the assessment *entry* points. Every user whose `hasHealthDataConsent` is false but who already has a profile — everyone onboarded before the gate shipped (fd4d3e7, 2026-07-05), plus everyone after any future `healthDataPolicyVersion` bump — can edit their health profile, write health notes, log pain-level workout sessions, run AI form analysis and exercise swaps, save re-assessment snapshots, and trigger the recovery-insights agent without ever consenting. That is active ungated collection under MHMDA, and it also makes any withdrawal path (WS3-02) meaningless mid-stream.

**Evidence** (all verified at 5fd0abb)
- `Services/ConsentService.swift:40-43` — `hasHealthDataConsent` is an exact-string mirror compare; any version bump flips the whole install base to unconsented.
- `Views/OnboardingView.swift:129-135` — gate 1: undismissable fullScreenCover at onboarding start (new users are watertight).
- `Views/WellnessGoalPickerView.swift:182-190` + `:50-60` — gate 2: Continue-button gate chain + onDismiss chain ("Gotcha #2" ordering comment).
- `Views/BodyMap3DView.swift:772-783` + `:120-128` — gate 3: Continue gate + onDismiss chain ("Gotcha #2" comment).
- Ungated health-data flows (the bypass): `Views/ThreeTabView.swift:213` and `Views/ProgressTab.swift:37` (→ `OnboardingEditView`, defined at `ContentView.swift:333` — full profile edit+save); `Views/ProgressTab.swift:132` (→ `NotesView`, free-text health notes to Firestore); `ViewModels/WorkoutViewModel.swift:102-121` (workout sessions incl. `painLevel` to Firestore); `Views/GuidedWorkoutView.swift:122-135` (exercise swap AI call) and `:136-140` (form-analysis AI call); `Views/RehabPlanView.swift:242-248` (swap) and `:15` (re-assessment flow); `Views/ProgressTab.swift:98` (recovery-insights agent — 14 days of workout+pain data to the AI backend).
- `RootView.swift:150-164` — the existing launch-time legal re-acceptance gate; the pattern this item copies.
- `RootView.swift:153-158` + `:21` — the minor-safety fullScreenCover competes for the same presentation slot; ordering must be explicit.

**Current-behavior map (VERIFY portion)** — coverage matrix of the live shell:

| Flow | Entry point | Gated? |
|---|---|---|
| New-user onboarding health profile | OnboardingView.swift:129-135 | YES (blocking, no decline) |
| Pain assessment | BodyMap3DView.swift:772 Continue (only live entry to PainDetailView) | YES |
| Wellness assessment | WellnessGoalPickerView.swift:184 Continue (only live entry to WellnessDetailView) | YES |
| Profile edit + save | ThreeTabView.swift:213, ProgressTab.swift:37 | NO |
| Health notes | ProgressTab.swift:132 → NotesView | NO |
| Workout logging (painLevel) | WorkoutViewModel.swift:102-121 | NO |
| Form analysis (AI) | GuidedWorkoutView.swift:136-140 | NO |
| Exercise swap (AI) | GuidedWorkoutView.swift:122-135, RehabPlanView.swift:242-248 | NO |
| Re-assessment snapshots | RehabPlanView.swift:15 + ReAssessmentPromptView | NO |
| Recovery insights agent | ProgressTab.swift:98 | NO |

**Invariant to preserve** — the three existing gates keep firing exactly as today (do not touch their Continue-gate logic or onDismiss chains); new-user onboarding, skip-onboarding, legal re-acceptance, and minor-safety flows are behaviorally unchanged for users who HAVE current health consent; `--uitesting` runs (which use `uiTestingContent`, RootView.swift:113-126) are untouched.

**Consolidation target** — one launch-time gate in `RootView` (pattern-copy of `showLegalGate`) closes all ten downstream flows at once, instead of gating 7+ heterogeneous sites individually.

**Change spec**
1. In `Models/ConsentPolicy.swift`, add to `enum ConsentPolicy` a pure decision function (chosen over per-flow gating: single choke point, unit-testable truth table):
   ```swift
   /// Launch-time MHMDA gate: fires only for users with a real health profile
   /// (health data already on file) who lack consent for the CURRENT policy
   /// version, and never while a higher-priority cover (legal gate,
   /// minor-safety interstitial) is showing or pending.
   static func shouldShowHealthConsentGate(
       consentLoaded: Bool,
       needsLegalReacceptance: Bool,
       legalGateShowing: Bool,
       minorSafetyPending: Bool,
       hasHealthProfile: Bool,
       hasHealthDataConsent: Bool
   ) -> Bool {
       consentLoaded
           && !needsLegalReacceptance
           && !legalGateShowing
           && !minorSafetyPending
           && hasHealthProfile
           && !hasHealthDataConsent
   }
   ```
   Rationale for `hasHealthProfile` (pass `profileService.profile != nil`): skip-onboarding users have no health data yet — the three point-of-use gates cover their first assessment; gating them at launch would be premature.
2. In `Views/HealthDataConsentView.swift`, add a second, defaulted closure parameter after `let onConsented` (HealthDataConsentView.swift:8): `var onDeclineSignOut: (() -> Void)? = nil`. When non-nil, render below the Continue button block (insert after line 96, inside the VStack): a plain-text `Button("Sign out instead") { onDeclineSignOut() }` styled `.font(AppFonts.bodyMedium)`, `.foregroundColor(AppColors.secondaryText)`, `.accessibilityIdentifier("healthConsent.signOutButton")`, plus a `Text` caption in `AppFonts.caption`/`AppColors.secondaryText`: `"If you don't consent, COIL can't provide assessments or plans. You can also email noyfisher2003@gmail.com to request deletion of your data."` The default `nil` keeps all three existing trailing-closure call sites source-compatible (unlabeled trailing closure binds to `onConsented`) — verify they still compile unchanged.
3. In `RootView.swift`: add `@State private var showHealthGate = false` next to `showLegalGate` (line 15). Add a private helper:
   ```swift
   private func reevaluateHealthGate() {
       showHealthGate = ConsentPolicy.shouldShowHealthConsentGate(
           consentLoaded: consentService.isLoaded,
           needsLegalReacceptance: consentService.needsLegalReacceptance,
           legalGateShowing: showLegalGate,
           minorSafetyPending: pendingMinorSafetyScreen,
           hasHealthProfile: profileService.profile != nil,
           hasHealthDataConsent: consentService.hasHealthDataConsent)
   }
   ```
4. Attach a third fullScreenCover on the `MainTabView()` branch, AFTER the minor-safety cover (i.e., after RootView.swift:158):
   ```swift
   .fullScreenCover(isPresented: $showHealthGate) {
       HealthDataConsentView(
           onConsented: { showHealthGate = false },
           onDeclineSignOut: {
               showHealthGate = false
               try? Auth.auth().signOut()   // RootView auth listener (lines 72-85) resets state + clears mirrors
           })
   }
   ```
5. Wire re-evaluation so the covers present strictly sequentially (legal > minor-safety > health): append `reevaluateHealthGate()` inside the existing `.onChange(of: consentService.isLoaded)` closure (RootView.swift:159-161) and the existing `.onAppear` (RootView.swift:162-164); add three new modifiers on the same branch: `.onChange(of: showLegalGate) { _, _ in reevaluateHealthGate() }`, `.onChange(of: pendingMinorSafetyScreen) { _, _ in reevaluateHealthGate() }`, `.onChange(of: isCheckingProfile) { _, _ in reevaluateHealthGate() }` (profile loads async after consent — the gate must re-check when the profile arrives).
6. Accepted, documented limitation (do not "fix"): if consent is revoked mid-session (WS3-02) the ungated downstream flows stay open until next launch; immediate coverage is provided by the three point-of-use gates. Add this as a code comment above `reevaluateHealthGate()`.
7. Add gate truth-table tests to `PT-HelperTests/Models/ConsentPolicyTests.swift` (8 cases): all-true-preconditions → true; each of the six parameters individually flipped to its blocking value → false; `hasHealthDataConsent: true` → false. Naming per convention, e.g. `testShouldShowHealthConsentGate_profiledUserWithoutConsent_fires`, `testShouldShowHealthConsentGate_legalGateShowing_defers`.
8. Virtual-user caution: vusers (`--virtual-user-token`) use the production branch. After building, check one vuser account for a `users/{uid}/consents/healthData` doc; if absent, the vuser harness will land in the gate — record that in the ledger as a note for the harness owner. Do NOT modify the harness or `functions/` here.

**Do NOT** — touch the three point-of-use gates' internal logic or their onDismiss chains (Gotcha #2 ordering), add per-flow gating to Notes/Workout/Swap/FormAnalysis/Insights, gate skip-onboarding users at launch, or alter `uiTestingContent`. Withdraw UI is WS3-02; mirror reconciliation is WS3-03.

**Files to touch**
- `ios/PT-Helper/PT-Helper/RootView.swift`
- `ios/PT-Helper/PT-Helper/Models/ConsentPolicy.swift`
- `ios/PT-Helper/PT-Helper/Views/HealthDataConsentView.swift`
- `ios/PT-Helper/PT-HelperTests/Models/ConsentPolicyTests.swift`

**Acceptance criteria**
- [ ] `grep -c "shouldShowHealthConsentGate" ios/PT-Helper/PT-Helper/Models/ConsentPolicy.swift` returns ≥ 1 and `grep -c "reevaluateHealthGate" ios/PT-Helper/PT-Helper/RootView.swift` returns ≥ 6 (1 definition + 5 call sites).
- [ ] `grep -rn "HealthDataConsentView {" --include="*.swift" ios/PT-Helper/PT-Helper/Views/OnboardingView.swift ios/PT-Helper/PT-Helper/Views/WellnessGoalPickerView.swift ios/PT-Helper/PT-Helper/Views/BodyMap3DView.swift` still returns exactly 3 hits (existing gates untouched).
- [ ] All 8 new `testShouldShowHealthConsentGate_*` tests pass in UnitPlan.
- [ ] **Prove-no-regression:** full UnitPlan green; manual: fresh sign-in with an account that HAS `consents/healthData` → no gate, app usable end-to-end.
- [ ] **Manual gate-flow check:** for a signed-in account with a profile, delete `users/{uid}/consents/healthData` in the pt-helper-dev Firestore console → relaunch → gate appears over the main UI, Continue disabled until both checkboxes ticked; consenting dismisses it and re-creates the Firestore doc; "Sign out instead" lands on LoginView.
- [ ] Manual ordering check: with the same account also missing `consents/legal` → legal gate presents first; health gate presents only after legal acceptance (no stuck blank cover).

**Verify**
```bash
xcodebuild build -project ios/PT-Helper/PT-Helper.xcodeproj \
  -scheme PT-Helper -destination 'platform=iOS Simulator,name=iPhone 16'

xcodebuild test -project ios/PT-Helper/PT-Helper.xcodeproj \
  -scheme PT-Helper -destination 'platform=iOS Simulator,name=iPhone 16'
```
(Known env quirk, memory-flagged: if the destination errors with "OS:latest" mismatch, append `,OS=18.2` to the destination string.)
Visual compare (gate screen) vs `ios/PT-Helper/docs/audit-assets-2026-07-17/healthconsent-light.png` and `healthconsent-dark.png` — identical except the added "Sign out instead" row in gate mode.

**Depends on / Blocks** — Depends on: WS3-03 (land reconciliation first so gate decisions track server truth; not a compile-time dependency). Blocks: WS3-02.

---

### [WS3-02] Add the policy-promised consent-withdraw control in Settings with defined downstream effects
`P1` · `effort: M` · `risk: HIGH — withdrawal that doesn't actually stop collection breaks a legal promise; a wrong re-gate condition can trap the user in a consent loop with no exit`

**Problem** — The Consumer Health Data Policy and the consent screen itself promise withdrawal, but today "withdraw" is only achievable by destroying the account or emailing the developer; `ConsentService` has record methods but no revoke method and Settings has no control. Under MHMDA, conditioning withdrawal on account termination is a weak compliance posture.

**Evidence**
- `Models/LegalContent.swift:263` — canonical policy text: right to "Withdraw consent"; `:266` — exercise mechanism named as Settings → Delete Account or email.
- `docs/CONSUMER_HEALTH_DATA_POLICY.md:37,40` — generated mirror of the same (header line 1: canonical text lives in LegalContent.swift).
- `Views/HealthDataConsentView.swift:74` — consent-screen caption promises withdrawal "by deleting your account in Settings, or by emailing…".
- `Services/ConsentService.swift:109-126` — `recordHealthDataConsent()` exists; grep for `withdraw`/`revoke` in ConsentService.swift and SettingsView.swift → zero hits.
- `Views/SettingsView.swift:338-341` — Legal card's "Consumer Health Data Policy" row: the insertion point.
- `Views/SettingsView.swift:558-570` — `clearAllLocalUserData()` (deletion path) already clears mirrors; withdrawal must not require it.

**Change spec**
1. In `Services/ConsentService.swift`, add below `recordHealthDataConsent()` (after line 126):
   ```swift
   /// MHMDA withdrawal: removes the consent assertion server-side while keeping
   /// an audit trail (revokedAt + prior timestamps survive; policyVersion is
   /// field-deleted so `load()` reconciliation treats it as unconsented on every
   /// device). Mirror cleared immediately so point-of-use gates re-fire this session.
   func revokeHealthDataConsent() {
       guard let uid = Auth.auth().currentUser?.uid else {
           AppLogger.data.error("revokeHealthDataConsent: no signed-in user")
           return
       }
       db.collection("users").document(uid)
           .collection("consents").document("healthData")
           .setData([
               "policyVersion": FieldValue.delete(),
               "revokedAt": FieldValue.serverTimestamp(),
               "appVersion": appVersion
           ], merge: true) { error in
               if let error {
                   AppLogger.data.error("Failed to record consent withdrawal: \(error.localizedDescription)")
               }
           }
       UserDefaults.standard.removeObject(forKey: MirrorKeys.healthDataPolicyVersion)
       objectWillChange.send()
   }
   ```
   Chosen approach: field-delete + `revokedAt` over document deletion — preserves the audit trail and is exactly the shape WS3-03's reconciliation maps to "unconsented". Same Firestore path/auth as the existing record write, so no rules change.
2. In `Views/SettingsView.swift`: add `@StateObject private var consentService = ConsentService.shared` alongside the existing `@StateObject` (line 10), and `@State private var showWithdrawConsentConfirmation = false` + `@State private var showWithdrawDone = false` with the other `@State` vars (lines 11-25).
3. In the Legal card, insert after `.accessibilityIdentifier("settings.consumerHealthDataPolicyButton")` (line 341), inside the same `VStack`:
   ```swift
   if consentService.hasHealthDataConsent {
       Divider().padding(.leading, 52)
       settingsRow(icon: "heart.slash", color: AppColors.danger, title: "Withdraw Health Data Consent") {
           showWithdrawConsentConfirmation = true
       }
       .accessibilityIdentifier("settings.withdrawHealthConsentButton")
   }
   ```
   (Conditional row: after withdrawal it disappears — re-consent happens through the gates, not through Settings.)
4. Add, next to the existing Delete Account `confirmationDialog` (SettingsView.swift:460):
   ```swift
   .confirmationDialog("Withdraw Health Data Consent", isPresented: $showWithdrawConsentConfirmation, titleVisibility: .visible) {
       Button("Withdraw Consent", role: .destructive) {
           ConsentService.shared.revokeHealthDataConsent()
           showWithdrawDone = true
       }
       Button("Cancel", role: .cancel) {}
   } message: {
       Text("COIL will stop collecting and using your health data. You'll need to consent again before starting new assessments or using health features. Your existing data is kept until you delete your account.")
   }
   .alert("Consent Withdrawn", isPresented: $showWithdrawDone) {
       Button("OK", role: .cancel) {}
   } message: {
       Text("New health-data features are paused until you consent again. To erase your data entirely, use Delete Account.")
   }
   ```
5. Update the consent-screen caption (UI copy, not the legal document — ships now) at `Views/HealthDataConsentView.swift:74` to exactly: `"You can withdraw consent at any time in Settings, by deleting your account, or by emailing noyfisher2003@gmail.com."`
6. Defined downstream effects (this IS the spec of "withdraw", document in a comment on `revokeHealthDataConsent()`): (a) immediately — `hasHealthDataConsent` flips false, the three point-of-use gates re-fire on the next assessment attempt, the Settings row disappears; (b) next launch — the WS3-01 gate blocks all health-data flows until re-consent or sign-out; (c) other devices — WS3-03 `load()` reconciliation clears their mirrors on next launch; (d) existing stored data is untouched (deletion remains a separate right via Delete Account). No mid-session hard-block of already-open flows (accepted limitation per WS3-01 step 6). Deliberately NO immediate fullScreenCover on revoke: RootView's gate re-evaluates only at launch-time hooks, avoiding cover-vs-sheet presentation contention while Settings is on screen.

**Do NOT** — edit the LegalContent policy-document text or docs mirror (WS3-06, blocked-on-legal); add new AnalyticsEvent cases (shared-type blast radius, not needed — `revokedAt` is the audit record); build a data-deletion path (Delete Account already owns that); touch the launch gate predicate (WS3-01).

**Files to touch**
- `ios/PT-Helper/PT-Helper/Services/ConsentService.swift`
- `ios/PT-Helper/PT-Helper/Views/SettingsView.swift`
- `ios/PT-Helper/PT-Helper/Views/HealthDataConsentView.swift`

**Acceptance criteria**
- [ ] `grep -c "revokeHealthDataConsent" ios/PT-Helper/PT-Helper/Services/ConsentService.swift` ≥ 1 and `grep -c "settings.withdrawHealthConsentButton" ios/PT-Helper/PT-Helper/Views/SettingsView.swift` = 1.
- [ ] `grep -n "deleting your account in Settings" ios/PT-Helper/PT-Helper/Views/HealthDataConsentView.swift` returns 0 hits (caption updated to the Settings-first wording).
- [ ] UnitPlan green (incl. WS3-03's `ConsentServiceTests` — revoke path covered there via mirror-key assertions).
- [ ] **Manual gate-flow check:** consented account → Settings shows the Withdraw row → confirm withdrawal → row disappears; start a pain assessment → BodyMap3DView Continue presents `HealthDataConsentView`; relaunch → WS3-01 launch gate presents; Firestore doc shows `revokedAt` set and `policyVersion` absent; re-consent restores normal use and the Settings row.

**Verify**
```bash
xcodebuild build -project ios/PT-Helper/PT-Helper.xcodeproj \
  -scheme PT-Helper -destination 'platform=iOS Simulator,name=iPhone 16'

xcodebuild test -project ios/PT-Helper/PT-Helper.xcodeproj \
  -scheme PT-Helper -destination 'platform=iOS Simulator,name=iPhone 16'
```
Visual compare vs `ios/PT-Helper/docs/audit-assets-2026-07-17/settings-light.png` and `settings-dark.png` — identical except the new row in the Legal card; and vs `healthconsent-light.png`/`healthconsent-dark.png` for the caption change.

**Depends on / Blocks** — Depends on: WS3-01, WS3-03. Blocks: WS3-06.

---

### [WS3-03] Make server state authoritative in ConsentService.load() and surface record-write failures; add ConsentService tests
`P1` · `effort: M` · `risk: HIGH — over-eager mirror clearing re-fires blocking gates for legitimately consented users (e.g., on a misread of doc-absent vs network error)`

**Problem** — `load()` only overwrites a mirror key when the Firestore doc exists with the field; it never clears a mirror when the server record is absent. So an email-honored withdrawal, manual remediation, or partial deletion leaves the device asserting consent forever — the mirror, not Firestore, is effectively canonical, and the promised email-withdrawal path is silently ineffective. Separately, both record methods write Firestore fire-and-forget and silently no-op when signed out, so "mirror says consented, server has no record" can arise with no trace.

**Evidence**
- `Services/ConsentService.swift:59-75` — `load()`: mirror updated only inside `if let data … if let version` branches; no else-clear on either doc.
- `Services/ConsentService.swift:84-104` — `recordLegalAcceptance`: `guard uid else { return }` (silent no-op, mirror included) and `setData` with no completion handler.
- `Services/ConsentService.swift:109-126` — `recordHealthDataConsent`: same fire-and-forget shape.
- `RootView.swift:70` — `load()` runs on every sign-in state change (the reconciliation point).
- `RootView.swift:150-164` — clearing `consent.tosVersion` when the server doc is absent will (intentionally) re-fire the legal gate: expected self-healing, flag in the PR description.

**Current-behavior map / invariant (VERIFY portion)** — Today: mirror-first hydration, server values overlay only when present, errors fall back to mirror, `isLoaded` always set (ConsentService.swift:50-77). Invariant to preserve: offline/network-error launches MUST keep trusting the mirror (no gate storm on airplane mode); the mirror-first synchronous reads used by the gate chains (`hasHealthDataConsent` in onDismiss closures — Gotcha #2) stay synchronous; `isLoaded` is still always set.

**Change spec**
1. In `Models/ConsentPolicy.swift`, add the pure reconciliation function (pure fn chosen so the doc-absent vs read-failed distinction is unit-testable without Firestore):
   ```swift
   /// Post-read mirror value for one consent doc.
   /// Read failed (offline) → keep mirror. Doc absent or field missing
   /// (server authoritatively says "no consent") → nil (clear mirror).
   /// Field present → server wins.
   static func reconciledConsentVersion(
       readFailed: Bool,
       docExists: Bool,
       serverVersion: String?,
       mirrorVersion: String?
   ) -> String? {
       if readFailed { return mirrorVersion }
       guard docExists, let serverVersion else { return nil }
       return serverVersion
   }
   ```
2. Rewrite the `do` block of `load()` (ConsentService.swift:59-75) to use it for BOTH docs: capture `snapshot.exists`, compute `reconciledConsentVersion(readFailed: false, docExists: snapshot.exists, serverVersion: snapshot.data()?["tosVersion"] as? String, mirrorVersion: recordedTosVersion)`; assign the result to `recordedTosVersion` and write-or-remove the mirror via a new private helper `setMirror(_ value: String?, forKey key: String)` (set when non-nil, `removeObject` when nil). Same for `healthData` with `"policyVersion"` and `MirrorKeys.healthDataPolicyVersion`; end the block with `objectWillChange.send()` (so `hasHealthDataConsent` observers refresh). The `catch` path is unchanged (mirror kept — that is the `readFailed` branch by construction).
3. Add failure logging to both record methods: give each `setData` call a completion closure logging via `AppLogger.data.error("Failed to record legal acceptance: …")` / `("Failed to record health data consent: …")`, and add `AppLogger.data.error(…: no signed-in user)` lines to both nil-uid guards. Keep the optimistic synchronous mirror writes exactly as-is (rationale: the gate dismissal chains read the mirror synchronously in `onDismiss`; a write-failure self-heals at next launch via step 2's reconciliation).
4. Change `private enum MirrorKeys` (ConsentService.swift:22) to `enum MirrorKeys` (internal) so tests can reference the key strings without duplicating literals.
5. Create `ios/PT-Helper/PT-HelperTests/Services/ConsentServiceTests.swift` (`@MainActor final class ConsentServiceTests: XCTestCase`, Firestore-free — pure fn + UserDefaults only; tearDown removes both mirror keys). Tests:
   - `testReconciledConsentVersion_readFailed_keepsMirror`
   - `testReconciledConsentVersion_docMissing_clearsMirror`
   - `testReconciledConsentVersion_fieldMissing_clearsMirror`
   - `testReconciledConsentVersion_serverValue_wins`
   - `testReconciledConsentVersion_docMissingAndNoMirror_staysNil`
   - `testHasHealthDataConsent_matchingMirror_isTrue` (set `ConsentService.MirrorKeys.healthDataPolicyVersion` to `LegalContent.healthDataPolicyVersion`)
   - `testHasHealthDataConsent_staleVersionMirror_isFalse` (set to `"2025.01"`)
   - `testHasHealthDataConsent_missingMirror_isFalse`
   - `testClearLocalMirrors_removesBothKeys`

**Do NOT** — make the record methods async/blocking or reorder any gate dismissal chain (Gotcha #2); add retry queues or offline persistence machinery; touch the gate predicates (WS3-01) or add revocation (WS3-02).

**Files to touch**
- `ios/PT-Helper/PT-Helper/Services/ConsentService.swift`
- `ios/PT-Helper/PT-Helper/Models/ConsentPolicy.swift`
- `ios/PT-Helper/PT-HelperTests/Services/ConsentServiceTests.swift` (new)

**Acceptance criteria**
- [ ] `grep -c "reconciledConsentVersion" ios/PT-Helper/PT-Helper/Models/ConsentPolicy.swift` ≥ 1; `grep -c "reconciledConsentVersion" ios/PT-Helper/PT-Helper/Services/ConsentService.swift` = 2 (one per doc).
- [ ] `grep -c "private enum MirrorKeys" ios/PT-Helper/PT-Helper/Services/ConsentService.swift` = 0 (now internal).
- [ ] All 9 new tests pass: `-only-testing:PT-HelperTests/ConsentServiceTests` green.
- [ ] **Prove-no-regression:** full UnitPlan green (incl. existing `ConsentPolicyTests`); manual: airplane-mode relaunch of a consented account shows NO legal gate and NO health gate (mirror fallback intact).

**Verify**
```bash
xcodebuild build -project ios/PT-Helper/PT-Helper.xcodeproj \
  -scheme PT-Helper -destination 'platform=iOS Simulator,name=iPhone 16'

xcodebuild test -project ios/PT-Helper/PT-Helper.xcodeproj \
  -scheme PT-Helper -destination 'platform=iOS Simulator,name=iPhone 16'

xcodebuild test -project ios/PT-Helper/PT-Helper.xcodeproj \
  -scheme PT-Helper -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:PT-HelperTests/ConsentServiceTests
```

**Depends on / Blocks** — Depends on: nothing. Blocks: WS3-01, WS3-02 (soft — execution-order, not compile-time).

---

### [WS3-04] Delete the write-only legacy ToS UserDefaults keys
`P2` · `effort: S` · `risk: LOW — keys have zero readers; only risk is grep-verified wrong-line removal`

**Problem** — `hasAcceptedTermsOfService`/`tosAcceptedDate` are written at onboarding and cleared at account deletion but read nowhere — pure dead state that misleadingly suggests a second consent source of truth next to `ConsentService` (which line 111 already uses for the same acceptance).

**Evidence**
- `ViewModels/OnboardingViewModel.swift:108-109` — the only writes; line 110-112 records the same acceptance via `ConsentService.recordLegalAcceptance`.
- `Views/SettingsView.swift:566-567` — the only other references (removeObject in `clearAllLocalUserData`).
- Repo-wide grep for either key at 5fd0abb → exactly these 4 lines; zero readers.

**Change spec**
1. Delete OnboardingViewModel.swift lines 108-109 (the two `UserDefaults.standard.set` calls). Leave lines 107 and 110-113 untouched.
2. Delete SettingsView.swift lines 566-567 (the two `removeObject` calls). Stale values in existing installs are inert — nothing reads them — so no migration/cleanup pass is warranted.

**Do NOT** — touch the `ConsentService.recordLegalAcceptance` call or its detached-Task shape (OnboardingViewModel.swift:110-112 — the kill-window there is a skipped P3, self-healing via the re-acceptance gate); touch any other line of `clearAllLocalUserData`.

**Files to touch**
- `ios/PT-Helper/PT-Helper/ViewModels/OnboardingViewModel.swift`
- `ios/PT-Helper/PT-Helper/Views/SettingsView.swift`

**Acceptance criteria**
- [ ] `grep -rn "hasAcceptedTermsOfService\|tosAcceptedDate" --include="*.swift" ios/` returns 0 lines.
- [ ] UnitPlan green.

**Verify**
```bash
xcodebuild build -project ios/PT-Helper/PT-Helper.xcodeproj \
  -scheme PT-Helper -destination 'platform=iOS Simulator,name=iPhone 16'

xcodebuild test -project ios/PT-Helper/PT-Helper.xcodeproj \
  -scheme PT-Helper -destination 'platform=iOS Simulator,name=iPhone 16'
```

**Depends on / Blocks** — nothing (coordinate merge order with WS3-02, which edits neighboring SettingsView lines).

---

### [WS3-05] Centralize duplicated UserDefaults key literals and clear the stale minor-safety flag on account deletion
`P2` · `effort: S` · `risk: LOW-MED — a typo'd key value silently orphans stored state (the exact fragility being fixed); mitigated by verbatim-value acceptance greps`

**Problem** — `"hasSeenMinorSafetyScreen"` and `"hasSeenBodyMapCoach"` each exist as an `@AppStorage` declaration in one file and a bare string literal in another; renaming either `@AppStorage` key would silently orphan the raw-string site (for the minor-safety key, account deletion would stop resetting a safety-relevant flag; for the coach key, `--clear-coach-mark` would break). Additionally `pendingMinorSafetyScreen` is not cleared on account deletion at all, so a stale pending flag re-shows the minor interstitial to the next account on the device.

**Evidence**
- `RootView.swift:23` — `@AppStorage("hasSeenMinorSafetyScreen")`; set at `:156`, read at `:207`.
- `Views/SettingsView.swift:569` — same key as bare literal; its own comment flags it: "plain string key — compiles fine before PR-5".
- `Views/BodyMap3DView.swift:59` — `@AppStorage("hasSeenBodyMapCoach")` (property `hasSeenCoach`).
- `Services/TestDataSeeder.swift:108` — same coach key as bare literal (`--clear-coach-mark` handler, line 107-109).
- `RootView.swift:21` — `@AppStorage("pendingMinorSafetyScreen")`; absent from `clearAllLocalUserData` (SettingsView.swift:558-570).
- Verified character-by-character at 5fd0abb: both pairs currently match — no live bug, fragility only.

**Change spec**
1. Create `ios/PT-Helper/PT-Helper/Services/AppStorageKeys.swift` (new file; auto-discovered per Xcode 16 synchronized groups — no pbxproj edit):
   ```swift
   /// Single source of truth for UserDefaults/@AppStorage keys that are
   /// referenced from more than one file ("PR-5" from the SettingsView comment).
   /// Values are frozen — changing one orphans users' stored state.
   enum AppStorageKeys {
       static let hasSeenMinorSafetyScreen = "hasSeenMinorSafetyScreen"
       static let pendingMinorSafetyScreen = "pendingMinorSafetyScreen"
       static let hasSeenBodyMapCoach = "hasSeenBodyMapCoach"
   }
   ```
2. Replace the literals at the five sites, preserving values exactly: RootView.swift:21 → `@AppStorage(AppStorageKeys.pendingMinorSafetyScreen)`; RootView.swift:23 → `@AppStorage(AppStorageKeys.hasSeenMinorSafetyScreen)`; BodyMap3DView.swift:59 → `@AppStorage(AppStorageKeys.hasSeenBodyMapCoach)`; TestDataSeeder.swift:108 → `forKey: AppStorageKeys.hasSeenBodyMapCoach`; SettingsView.swift:569 → `forKey: AppStorageKeys.hasSeenMinorSafetyScreen` and delete the stale "plain string key" comment.
3. In `clearAllLocalUserData()` add directly after the line edited in step 2: `UserDefaults.standard.removeObject(forKey: AppStorageKeys.pendingMinorSafetyScreen)`.

**Do NOT** — sweep other `@AppStorage` keys (`hasSeenIntroCarousel`, `skippedOnboarding`, `pendingFirstAssessment`, checkpoint keys) into the enum, move `ConsentService.MirrorKeys` (single-file scope, owned by WS3-03), or change sign-out semantics of the minor-safety flags.

**Files to touch**
- `ios/PT-Helper/PT-Helper/Services/AppStorageKeys.swift` (new)
- `ios/PT-Helper/PT-Helper/RootView.swift`
- `ios/PT-Helper/PT-Helper/Views/SettingsView.swift`
- `ios/PT-Helper/PT-Helper/Views/BodyMap3DView.swift`
- `ios/PT-Helper/PT-Helper/Services/TestDataSeeder.swift`

**Acceptance criteria**
- [ ] `grep -rn '"hasSeenMinorSafetyScreen"\|"pendingMinorSafetyScreen"\|"hasSeenBodyMapCoach"' --include="*.swift" ios/PT-Helper/PT-Helper | grep -v AppStorageKeys.swift` returns 0 lines (literals exist only in the enum).
- [ ] `grep -c 'removeObject(forKey: AppStorageKeys.pendingMinorSafetyScreen)' ios/PT-Helper/PT-Helper/Views/SettingsView.swift` = 1.
- [ ] Key VALUES unchanged: `grep -c '= "hasSeenMinorSafetyScreen"' ios/PT-Helper/PT-Helper/Services/AppStorageKeys.swift` = 1 (likewise for the other two).
- [ ] UnitPlan green; SmokePlan green (coach-mark UI tests exercise `--clear-coach-mark`).

**Verify**
```bash
xcodebuild build -project ios/PT-Helper/PT-Helper.xcodeproj \
  -scheme PT-Helper -destination 'platform=iOS Simulator,name=iPhone 16'

xcodebuild test -project ios/PT-Helper/PT-Helper.xcodeproj \
  -scheme PT-Helper -destination 'platform=iOS Simulator,name=iPhone 16'

xcodebuild test -project ios/PT-Helper/PT-Helper.xcodeproj \
  -scheme PT-Helper -testPlan SmokePlan -destination 'platform=iOS Simulator,name=iPhone 16'
```

**Depends on / Blocks** — nothing (coordinate merge order with WS3-01/WS3-02/WS3-04, which edit neighboring RootView/SettingsView lines).

---

### [WS3-06] Update the Consumer Health Data Policy withdrawal-mechanism text (BLOCKED-on-legal)
`P2` · `effort: S` · `risk: LOW — text-only; risk is drift between canonical LegalContent and the generated docs mirror`

**Problem** — Once WS3-02 ships, the policy's "exercise your rights" paragraph should name the in-app withdraw control, not only Delete-Account-or-email. Per settled decision D-2, legal-document text changes are spec'd verbatim here but land only after legal review.

**Evidence**
- `Models/LegalContent.swift:266` — current mechanism sentence (canonical).
- `docs/CONSUMER_HEALTH_DATA_POLICY.md:1` — "GENERATED MIRROR — canonical text lives in LegalContent.swift. Edit there, then re-sync"; `:40` — mirrored sentence.

**Change spec**
1. In `Models/LegalContent.swift` line 266, replace the sentence beginning `To exercise any right: use Settings → Delete Account` so the full line reads verbatim:
   `To exercise any right: use Settings → Withdraw Health Data Consent (stops collection and use), Settings → Delete Account (removes all data immediately), or email noyfisher2003@gmail.com. We will respond within 45 days. If we deny a request, you may appeal by replying to our response; if the appeal is denied, you may contact the Washington State Attorney General at www.atg.wa.gov/file-complaint.`
2. Re-sync `docs/CONSUMER_HEALTH_DATA_POLICY.md` by hand (no sync script exists — verified): copy the updated markdown body from `LegalContent.consumerHealthDataPolicy`, keeping the line-1 GENERATED MIRROR header.
3. Do NOT bump `LegalContent.healthDataPolicyVersion` (line 14): the change is an additive rights-mechanism clarification, not a change to collection/sharing scope; a bump would force app-wide re-consent (WS3-01 gate + all three point-of-use gates) for every user. Flag this no-bump decision to legal alongside the text.

**Do NOT** — touch any other LegalContent document, the "Last Updated" date, or any brand-rename strings (those are D-2's separate verbatim spec).

**Files to touch**
- `ios/PT-Helper/PT-Helper/Models/LegalContent.swift`
- `docs/CONSUMER_HEALTH_DATA_POLICY.md`

**Acceptance criteria**
- [ ] `grep -c "Withdraw Health Data Consent" ios/PT-Helper/PT-Helper/Models/LegalContent.swift` ≥ 1 and same grep on `docs/CONSUMER_HEALTH_DATA_POLICY.md` ≥ 1 (mirror in sync).
- [ ] `grep -n 'healthDataPolicyVersion = "2026.07"' ios/PT-Helper/PT-Helper/Models/LegalContent.swift` still returns 1 hit (no version bump).
- [ ] UnitPlan green (LegalContent is compiled source).
- [ ] Ledger shows legal sign-off recorded before merge.

**Verify**
```bash
xcodebuild build -project ios/PT-Helper/PT-Helper.xcodeproj \
  -scheme PT-Helper -destination 'platform=iOS Simulator,name=iPhone 16'

xcodebuild test -project ios/PT-Helper/PT-Helper.xcodeproj \
  -scheme PT-Helper -destination 'platform=iOS Simulator,name=iPhone 16'
```

**Depends on / Blocks** — Depends on: WS3-02 (text must not promise a control that isn't shipped) + legal review (BLOCKED). Blocks: nothing.

---

**Skipped (P3, low value):**
- OnboardingViewModel.swift:110-112 detached-Task kill-window between profile save and legal-acceptance recording — self-healing via the LegalAcceptanceGateView re-acceptance gate (RootView.swift:150-164); not worth new plumbing.
- Renaming/moving `ConsentService.MirrorKeys` into `AppStorageKeys` — keys are single-file scoped after WS3-03; consolidation would add churn with no fragility win.
- Sign-out (vs deletion) semantics of `hasSeenMinorSafetyScreen`/`hasSeenBodyMapCoach` on shared devices — cosmetic re-show/no-show of one-time overlays; no health-data exposure.

## WS4: Rebrand completion

Scope: finish the MVVC→COIL rebrand in the shipping app — re-skin the IntroCarousel red hero (D-4: re-skin, not redesign), branded launch screen + dark/tinted app-icon variants, PDF export teal accent, LegalContent rename spec (D-2: verbatim but ledger-BLOCKED on legal sign-off), non-legal brand-string/comment sweep, and Inter-Bold dead-font removal.
Size M · Risk LOW-MEDIUM (visual-only, but IntroCarousel is every new user's first screen) · Required test plan: SmokePlan + visual compare vs `/Users/noyfisher/IOS-Projects/PT-Helper-Agent-v1/ios/PT-Helper/docs/audit-assets-2026-07-17/`.
All file:line citations verified at 5fd0abb.

**Shared context.** All paths below are relative to `/Users/noyfisher/IOS-Projects/PT-Helper-Agent-v1/ios/PT-Helper/PT-Helper/` unless prefixed. The COIL token system is two-tier: `CoilPalette` (DesignSystem.swift:19-64, raw UIColor hues — the ONLY place RGB lives) and `AppColors` (DesignSystem.swift:66+, semantic SwiftUI tokens). Key values used in this section: `CoilPalette.accent` = light #0FB5B0 / dark #2CC7C2 (:32), `accentDeep` = #0B7A78 / #17A6A2 (:33), `accentDeeper` = #075E5C / #0B7A78 (:35), `ink` = fixed #0E1C22 (:39), `inkElevated` = fixed #16303A (:40), `page` = #F3F5F4 / #0E1518 (:44); semantic wrappers `AppColors.accentDark` = Color(accentDeeper) (:103), `AppColors.darkSurface` = Color(ink) (:88), `AppColors.darkSurfaceElevated` = Color(inkElevated) (:89). The COIL mark is `CoilGlyph` (DesignSystem.swift:182, 4 overlapping spring rings) and the current `AppIcon.png` is 1024×1024 with exactly two dominant flat colors: background (15,181,176)=#0FB5B0 and rings (14,28,34)=#0E1C22 (pixel-verified). The app's product/target/bundle name (`PT-Helper`) is NOT in this workstream — only user-visible strings, art, and assets. Run all `xcodebuild` commands from `/Users/noyfisher/IOS-Projects/PT-Helper-Agent-v1`. Known quirk (memory `project_build_simulator_destination.md`): if `name=iPhone 16` fails destination resolution, append `,OS=18.2` to the destination string.

---

### [WS4-01] Re-skin IntroCarouselView hero to COIL tokens and fix the light-mode status-bar strip
`P1` · `effort: S` · `risk: first screen every new user sees; token swap only, no layout change (D-4)`

**Problem** — The intro carousel still ships the old MVVC deep-RED hero: a red radial glow and dark-red silhouette behind the teal skeleton lines, so the very first screen a new user sees is half old-brand, half new-brand. Additionally, in light appearance all three pages show a white status-bar strip above the dark hero (audit screenshots), because the paging TabView is laid out inside the safe area and nothing paints behind it.

**Evidence** —
- `Views/IntroCarouselView.swift:112` — comment `// Deep red radial background filling the hero zone`.
- `Views/IntroCarouselView.swift:115-116` — `Color(red: 0.35, green: 0.02, blue: 0.02)` and `Color(red: 0.13, green: 0.02, blue: 0.02)` radial-gradient stops (third stop :117 is already `AppColors.darkSurface`).
- `Views/IntroCarouselView.swift:407` — silhouette fill `Color(red: 0.15, green: 0.04, blue: 0.04).opacity(0.9)` on the `figure.stand` image (:404-407).
- `grep -n 'Color(red' Views/IntroCarouselView.swift` → exactly 3 hits (115, 116, 407) — the only raw color literals in the file; the rest is already tokenized (`AppColors.accent` at :139/:162/:250/:256/:329/:358/:374/:398/:412/:418, `AppColors.darkSurface` at :102/:221/:289) with exactly 20 `.white`/`Color.white` sites tuned to the dark background.
- `RootView.swift:24` (`@AppStorage("hasSeenIntroCarousel")`) and `:165-168` — the carousel gates every new user before onboarding.
- `Views/IntroCarouselView.swift:9-24` — container `TabView` deliberately has NO `.ignoresSafeArea()` (F6 regression comment :18-22); page backgrounds ignore safe area themselves but the paging TabView clips them, leaving the strip.
- Audit screenshots: white strip visible in `intro1-light.png`/`intro2-light.png`; `intro1-dark.png` is seamless. `LoginView.swift:130` and `Views/OnboardingView.swift:142` solve the same problem with `.preferredColorScheme(.dark) // hero screen is intentionally dark in both app modes`.

**Change spec** —
1. `Views/IntroCarouselView.swift:112` — change comment to `// Deep teal radial background filling the hero zone`.
2. `:115` — replace `Color(red: 0.35, green: 0.02, blue: 0.02),` with `AppColors.accentDark,` (deep teal #075E5C/#0B7A78 — nearest-luminance teal to the old bright-red glow stop; keeps the center-out luminance ramp).
3. `:116` — replace `Color(red: 0.13, green: 0.02, blue: 0.02),` with `AppColors.darkSurfaceElevated,` (teal-tinted ink #16303A as the mid stop; edge stop :117 stays `AppColors.darkSurface`).
4. `:407` — replace `.foregroundColor(Color(red: 0.15, green: 0.04, blue: 0.04).opacity(0.9))` with `.foregroundColor(AppColors.darkSurfaceElevated.opacity(0.9))` (silhouette slightly lighter than the ink background, same relationship as the old red pair; the teal `SkeletonLines` stroke at :410-413 stays).
5. In `IntroCarouselView.body` (:9-24): wrap the existing `TabView` (with its `.tabViewStyle` and `.trackScreen` modifiers unchanged) in a `ZStack` whose first layer is `AppColors.darkSurface.ignoresSafeArea()`. Do NOT add `.ignoresSafeArea()` to the TabView itself — preserve the F6 comment block (:18-22) verbatim; the backdrop paints the strip without touching page safe-area insets.
6. Add `.preferredColorScheme(.dark) // hero screen is intentionally dark in both app modes` on the new ZStack — same convention and comment as LoginView.swift:130 / OnboardingView.swift:142; this keeps status-bar glyphs light over the dark backdrop.
7. The 20 `.white` sites stay as-is — the background remains dark ink, so they remain valid (D-4).

**Do NOT** — Do not redesign layout, copy, page-indicator placement (p2 missing indicator / p3 centered indicator are D-4-excluded redesign), or touch `RootView`'s gating logic; the `--skip-onboarding` UITest path is out of scope.

**Files to touch** —
- `ios/PT-Helper/PT-Helper/Views/IntroCarouselView.swift`

**Acceptance criteria** —
- [ ] `grep -c 'Color(red' ios/PT-Helper/PT-Helper/Views/IntroCarouselView.swift` returns 0.
- [ ] `grep -c 'preferredColorScheme' ios/PT-Helper/PT-Helper/Views/IntroCarouselView.swift` returns 1.
- [ ] `grep -cE 'accentDark|darkSurfaceElevated' ios/PT-Helper/PT-Helper/Views/IntroCarouselView.swift` returns ≥ 3.
- [ ] Build + SmokePlan pass (commands below).
- [ ] Fresh-install simulator run in LIGHT appearance (delete the app first so `hasSeenIntroCarousel` resets): screenshot of page 1 saved as `intro1-light-after.png` shows (a) no white strip above the nav bar, (b) teal — not red — hero glow. Mechanical check: `python3 -c "from PIL import Image; im=Image.open('intro1-light-after.png').convert('RGB'); r,g,b=im.getpixel((im.width//2,8)); assert max(r,g,b)<70, f'status strip not dark: {(r,g,b)}'; r2,g2,b2=im.getpixel((im.width//2,int(im.height*0.32))); assert g2>=r2, f'hero glow still red: {(r2,g2,b2)}'; print('OK')"`
- [ ] Side-by-side compare vs before-screenshots `/Users/noyfisher/IOS-Projects/PT-Helper-Agent-v1/ios/PT-Helper/docs/audit-assets-2026-07-17/intro1-light.png`, `intro2-light.png`, `intro3-light.png`, `intro1-dark.png`: layout/copy identical, only colors changed.

**Verify** —
```bash
cd /Users/noyfisher/IOS-Projects/PT-Helper-Agent-v1
xcodebuild build -project ios/PT-Helper/PT-Helper.xcodeproj \
  -scheme PT-Helper -destination 'platform=iOS Simulator,name=iPhone 16'
xcodebuild test -project ios/PT-Helper/PT-Helper.xcodeproj \
  -scheme PT-Helper -testPlan SmokePlan -destination 'platform=iOS Simulator,name=iPhone 16'
```
Visual compare vs `/Users/noyfisher/IOS-Projects/PT-Helper-Agent-v1/ios/PT-Helper/docs/audit-assets-2026-07-17/intro1-light.png` (+ intro2-light, intro3-light, intro1-dark).

**Depends on / Blocks** — Depends on nothing. Blocks nothing (WS4-05's sweep-grep excludes this file because item 1 above fixes its stale comment).

---

### [WS4-02] Add branded launch screen and dark/tinted app-icon variants
`P2` · `effort: M` · `risk: asset + plist + pbxproj edits; pbxproj already has uncommitted local modifications — touch only the 2 named lines`

**Problem** — Cold launch shows a bare white/black system flash (Xcode auto-generated blank launch screen), and the iOS 18 dark/tinted Home Screen appearances reuse the single full-color icon PNG, so the icon renders as a flat teal square in dark mode and fails the grayscale requirement in tinted mode. Decision (settled here): static branded launch screen = adaptive page-colored background + centered COIL rings mark; icon variants generated programmatically from the existing flat-color AppIcon.png.

**Evidence** —
- `ios/PT-Helper/PT-Helper.xcodeproj/project.pbxproj:472,503` — `INFOPLIST_KEY_UILaunchScreen_Generation = YES;` in both Debug and Release (blank auto-generated launch screen; no storyboard or launch asset exists anywhere in the repo or its history — archaeology confirmed).
- `ios/PT-Helper/Info.plist` — no `UILaunchScreen` dict (only URL types, camera/mic strings, `UIAppFonts`); merged via `INFOPLIST_FILE = Info.plist` + `GENERATE_INFOPLIST_FILE = YES` (pbxproj:467-468, 498-499).
- `Assets.xcassets/AppIcon.appiconset/Contents.json` — declares `universal`, `dark`, and `tinted` appearance slots but all three point to the same `AppIcon.png`.
- `AppIcon.png` pixel audit: 1024×1024, two flat colors — bg (15,181,176)=#0FB5B0, rings (14,28,34)=#0E1C22 — so a chroma-key recolor is deterministic.
- `Assets.xcassets/` currently contains only `AccentColor.colorset` + `AppIcon.appiconset`; the names `LaunchBackground`/`LaunchLogo` are unused (grep = 0 hits).
- Pillow is installed for `python3` on this machine (verified this session).

**Change spec** —
1. Create `/Users/noyfisher/IOS-Projects/PT-Helper-Agent-v1/scripts/generate_brand_launch_assets.py` with exactly this algorithm (Pillow; pure-PIL loop is fine at 1024²):
   - `SRC = ios/PT-Helper/PT-Helper/Assets.xcassets/AppIcon.appiconset/AppIcon.png`; constants `BG=(15,181,176)`, `RING=(14,28,34)`.
   - Per pixel `p`: `t = clamp(dist(p,BG)/dist(BG,RING), 0, 1)`; ring alpha mask `A = round(255*t)` (handles anti-aliased edges).
   - Emit into `ios/PT-Helper/PT-Helper/Assets.xcassets/AppIcon.appiconset/`:
     - `AppIcon-dark.png` — 1024×1024 RGBA, all pixels color `(44,199,194)` (#2CC7C2, dark-mode accent), alpha=A (transparent bg; system supplies the dark backdrop).
     - `AppIcon-tinted.png` — 1024×1024 RGBA, color `(230,230,230)` (grayscale, per Apple tinted-icon requirement), alpha=A.
   - Emit into `ios/PT-Helper/PT-Helper/Assets.xcassets/LaunchLogo.imageset/` (create dir): mask downscaled to 512×512 with LANCZOS, then
     - `LaunchLogo.png` — color `(11,122,120)` (#0B7A78 accentDeep-light, passes on the light launch bg).
     - `LaunchLogo-dark.png` — color `(44,199,194)` (#2CC7C2).
2. Run the script.
3. Edit `Assets.xcassets/AppIcon.appiconset/Contents.json`: dark-appearance entry `"filename" : "AppIcon-dark.png"`, tinted-appearance entry `"filename" : "AppIcon-tinted.png"`; universal entry keeps `AppIcon.png`.
4. Create `Assets.xcassets/LaunchBackground.colorset/Contents.json` — adaptive color matching `CoilPalette.page` (rationale: launch should match the surface most launches land on, and its dark value is near-ink so the dark hero screens don't clash): universal/any = sRGB `0xF3`,`0xF5`,`0xF4`; dark appearance = `0x0E`,`0x15`,`0x18`. Standard colorset JSON with `"color-space" : "srgb"` and hex `"components"`.
5. Create `Assets.xcassets/LaunchLogo.imageset/Contents.json`: single universal scale-1x entry `LaunchLogo.png` plus a `luminosity: dark` appearance entry `LaunchLogo-dark.png`.
6. Edit `ios/PT-Helper/Info.plist` — add at dict top level:
   ```xml
   <key>UILaunchScreen</key>
   <dict>
       <key>UIColorName</key>
       <string>LaunchBackground</string>
       <key>UIImageName</key>
       <string>LaunchLogo</string>
       <key>UIImageRespectsSafeAreaInsets</key>
       <true/>
   </dict>
   ```
7. Edit `ios/PT-Helper/PT-Helper.xcodeproj/project.pbxproj` — delete BOTH lines `INFOPLIST_KEY_UILaunchScreen_Generation = YES;` (:472 Debug, :503 Release) so the generated empty `UILaunchScreen` key cannot conflict with the manual dict. Touch nothing else in pbxproj (it has unrelated uncommitted modifications).

**Do NOT** — Do not rename the target/product/bundle-id, redraw the CoilGlyph mark itself (V5 art is final per 4a85bee), or touch `AccentColor.colorset`.

**Files to touch** —
- `/Users/noyfisher/IOS-Projects/PT-Helper-Agent-v1/scripts/generate_brand_launch_assets.py` (new)
- `ios/PT-Helper/PT-Helper/Assets.xcassets/AppIcon.appiconset/AppIcon-dark.png` (new), `AppIcon-tinted.png` (new), `Contents.json`
- `ios/PT-Helper/PT-Helper/Assets.xcassets/LaunchBackground.colorset/Contents.json` (new)
- `ios/PT-Helper/PT-Helper/Assets.xcassets/LaunchLogo.imageset/Contents.json` (new), `LaunchLogo.png` (new), `LaunchLogo-dark.png` (new)
- `ios/PT-Helper/Info.plist`
- `ios/PT-Helper/PT-Helper.xcodeproj/project.pbxproj` (ONLY the two `UILaunchScreen_Generation` lines)

**Acceptance criteria** —
- [ ] `grep -c 'UILaunchScreen_Generation' ios/PT-Helper/PT-Helper.xcodeproj/project.pbxproj` returns 0.
- [ ] `plutil -lint ios/PT-Helper/Info.plist` prints OK, and `grep -c 'UILaunchScreen' ios/PT-Helper/Info.plist` returns 1.
- [ ] `python3 -c "import json;d=json.load(open('ios/PT-Helper/PT-Helper/Assets.xcassets/AppIcon.appiconset/Contents.json'));fs=[i['filename'] for i in d['images']];assert fs==['AppIcon.png','AppIcon-dark.png','AppIcon-tinted.png'],fs;print('OK')"` prints OK.
- [ ] `python3 -c "from PIL import Image; a=Image.open('ios/PT-Helper/PT-Helper/Assets.xcassets/AppIcon.appiconset/AppIcon-dark.png'); assert a.mode=='RGBA' and a.size==(1024,1024) and a.getpixel((5,5))[3]==0; print('OK')"` prints OK (transparent background).
- [ ] Build + SmokePlan pass.
- [ ] Simulator cold launch (terminate app, relaunch from Home Screen): screenshot during launch shows rings mark on the page-colored background, not a blank flash.

**Verify** —
```bash
cd /Users/noyfisher/IOS-Projects/PT-Helper-Agent-v1
python3 scripts/generate_brand_launch_assets.py
xcodebuild build -project ios/PT-Helper/PT-Helper.xcodeproj \
  -scheme PT-Helper -destination 'platform=iOS Simulator,name=iPhone 16'
xcodebuild test -project ios/PT-Helper/PT-Helper.xcodeproj \
  -scheme PT-Helper -testPlan SmokePlan -destination 'platform=iOS Simulator,name=iPhone 16'
```
Visual compare: launch-screen screenshot vs the blank flash implied by `/Users/noyfisher/IOS-Projects/PT-Helper-Agent-v1/ios/PT-Helper/docs/audit-assets-2026-07-17/home-light.png` chrome (no "before" launch capture exists; the check is the after-state described above).

**Depends on / Blocks** — Depends on nothing. Blocks nothing.

---

### [WS4-03] Rename "PT Helper" → "COIL" in LegalContent (spec'd verbatim; BLOCKED on legal sign-off, D-2)
`P2` · `effort: S` · `risk: bumping tosVersion re-triggers the legal-acceptance gate for ALL existing users — intended, but must ship WITH the sign-off`

**Problem** — The in-app Privacy Policy and Terms of Service still name the product "PT Helper" eight times, visible from Settings on the rebranded COIL build (audit screenshots). Per D-2 the replacement text is specified verbatim here but execution is ledger-BLOCKED until legal sign-off, because a legal-document change requires a Last-Updated bump and forced re-acceptance.

**Evidence** —
- `Models/LegalContent.swift` — exactly 8 `PT Helper` hits: :21, :26, :119 (Privacy Policy) and :135, :140, :144, :152, :210 (ToS). Verified: zero hits elsewhere in the file (incl. `consumerHealthDataPolicy`, :227+).
- `Models/LegalContent.swift:12-14` — `tosVersion` / `privacyPolicyVersion` / `healthDataPolicyVersion` all `"2026.07"`; `:22` and `:136` — `**Last Updated: July 2026**`.
- `Services/ConsentService.swift:32-33` → `Models/ConsentPolicy.swift:5-9` — `needsLegalReacceptance` is `recordedVersion != LegalContent.tosVersion`; `RootView.swift:160,163` re-presents the legal gate when true. So bumping `tosVersion` automatically forces re-acceptance — the desired behavior for a legal-text change.
- App shell already renamed: `INFOPLIST_KEY_CFBundleDisplayName = COIL` (pbxproj:469,500).

**Change spec** (execute only after legal sign-off is recorded in the ledger) —
1. In `Models/LegalContent.swift`, replace the literal `PT Helper` with `COIL` at all 8 sites. Verbatim before-text for each (replace only the brand token, rest of sentence unchanged):
   - :21 `**PT Helper**` → `**COIL**`
   - :26 `PT Helper ("the App") is a wellness guidance application …` → `COIL ("the App") is a wellness guidance application …`
   - :119 `PT Helper provides **wellness guidance only, not medical diagnosis**…` → `COIL provides …`
   - :135 `**PT Helper**` → `**COIL**`
   - :140 `By downloading, installing, or using PT Helper ("the App"), …` → `… using COIL ("the App"), …`
   - :144 `PT Helper is a wellness guidance application that uses artificial intelligence to:` → `COIL is a wellness guidance application …`
   - :152 `**PT Helper is NOT a medical device and does NOT provide medical diagnosis, treatment, or advice.**` → `**COIL is NOT a medical device …**`
   - :210 `You agree to indemnify and hold harmless PT Helper, its developers, and affiliates …` → `… hold harmless COIL, its developers, and affiliates …`
2. `:22` and `:136` — set `**Last Updated: <Month Year of sign-off>**` (e.g. `August 2026`).
3. `:12-14` — set all three version constants to the sign-off month in the existing `YYYY.MM` format (e.g. `"2026.08"`). This intentionally flips `needsLegalReacceptance` for every existing user; no other code change is needed (gate wiring at RootView:160,163 already handles it).
4. Ledger entry: mark this item BLOCKED-legal; unblocking evidence = user confirmation of counsel sign-off in chat.

**Do NOT** — Do not fix LegalDocumentView's raw-markdown rendering (content workstream), the personal-Gmail withdraw-consent contact in HealthDataConsentView (compliance workstream), or the dead-tree `PT Helper` strings in ContentView.swift:141 / Views/Dashboard/DashProfileView.swift:35 (WS1 deletes those files).

**Files to touch** —
- `ios/PT-Helper/PT-Helper/Models/LegalContent.swift`

**Acceptance criteria** —
- [ ] `grep -c 'PT Helper' ios/PT-Helper/PT-Helper/Models/LegalContent.swift` returns 0.
- [ ] `grep -c '"2026.07"' ios/PT-Helper/PT-Helper/Models/LegalContent.swift` returns 0 (all three versions bumped).
- [ ] Build + SmokePlan pass.
- [ ] Manual gate check on simulator with an existing signed-in user: legal re-acceptance sheet appears once on next launch, accepting dismisses it permanently.
- [ ] Screenshot of Settings → Privacy Policy shows "COIL" title (compare against before-state `/Users/noyfisher/IOS-Projects/PT-Helper-Agent-v1/ios/PT-Helper/docs/audit-assets-2026-07-17/legalprivacy-light.png`).

**Verify** —
```bash
cd /Users/noyfisher/IOS-Projects/PT-Helper-Agent-v1
xcodebuild build -project ios/PT-Helper/PT-Helper.xcodeproj \
  -scheme PT-Helper -destination 'platform=iOS Simulator,name=iPhone 16'
xcodebuild test -project ios/PT-Helper/PT-Helper.xcodeproj \
  -scheme PT-Helper -testPlan SmokePlan -destination 'platform=iOS Simulator,name=iPhone 16'
```
Visual compare vs `/Users/noyfisher/IOS-Projects/PT-Helper-Agent-v1/ios/PT-Helper/docs/audit-assets-2026-07-17/legalprivacy-light.png` and `legalprivacy-dark.png`.

**Depends on / Blocks** — BLOCKED on legal sign-off (ledger item, D-2). Depends on no other WS4 item. Blocks nothing.

---

### [WS4-04] Replace systemBlue with fixed COIL teal in PDFExportService
`P2` · `effort: S` · `risk: none beyond PDF appearance; PDFs are user-shared externally so off-brand blue is visible outside the app`

**Problem** — Exported rehab-plan PDFs draw the "COIL" brand header and the weekly-calendar exercise counts in `UIColor.systemBlue` — the only remaining old-accent color in the export, on a document users hand to clinicians.

**Evidence** —
- `Services/PDFExportService.swift:48` — `.foregroundColor: UIColor.systemBlue` in `brandAttrs`; the literal `"COIL".draw(...)` at :50 confirms the name is already rebranded, only the color is stale.
- `Services/PDFExportService.swift:124` — `.foregroundColor: UIColor.systemBlue` in `countAttrs` (weekly-calendar exercise-count text).
- These are the only 2 `systemBlue` sites in the file; :176 `UIColor.systemOrange` is a semantic precaution-warning color — keep.
- `PDFExportService` is a static-only `enum` (:4) with layout constants at :6-9 — natural insertion point for a shared constant.
- `CoilPalette.hex(_:)` (DesignSystem.swift:25-30) returns a fixed opaque UIColor and is internal — callable from the service.

**Change spec** —
1. `Services/PDFExportService.swift` — after `:9` (`private static let contentWidth…`), insert:
   `private static let brandAccent = CoilPalette.hex(0x0B7A78) // fixed print-safe COIL teal (accentDeep-light). PDFs render with no trait environment — never use dynamic AppColors/CoilPalette.accent here; #0FB5B0 also fails contrast on white paper.`
2. `:48` (now shifted +2) — replace `UIColor.systemBlue` with `brandAccent`.
3. `:124` (shifted) — replace `UIColor.systemBlue` with `brandAccent`.
4. Leave `UIColor.systemOrange` (:176) and all neutral grays untouched.

**Do NOT** — Do not restyle the PDF layout, fonts, or the orange precaution color; do not introduce dynamic colors.

**Files to touch** —
- `ios/PT-Helper/PT-Helper/Services/PDFExportService.swift`

**Acceptance criteria** —
- [ ] `grep -c 'systemBlue' ios/PT-Helper/PT-Helper/Services/PDFExportService.swift` returns 0.
- [ ] `grep -c 'brandAccent' ios/PT-Helper/PT-Helper/Services/PDFExportService.swift` returns 3 (1 definition + 2 uses).
- [ ] Build + SmokePlan pass.
- [ ] Manual: export a plan PDF from the plan detail screen on simulator; header "COIL" and calendar counts render deep teal (#0B7A78), warnings still orange.

**Verify** —
```bash
cd /Users/noyfisher/IOS-Projects/PT-Helper-Agent-v1
xcodebuild build -project ios/PT-Helper/PT-Helper.xcodeproj \
  -scheme PT-Helper -destination 'platform=iOS Simulator,name=iPhone 16'
xcodebuild test -project ios/PT-Helper/PT-Helper.xcodeproj \
  -scheme PT-Helper -testPlan SmokePlan -destination 'platform=iOS Simulator,name=iPhone 16'
```

**Depends on / Blocks** — nothing.

---

### [WS4-05] SWEEP: purge stale red/Barlow comments and residual "PT Helper" brand strings in live files
`P3` · `effort: S` · `risk: comments and never-hit fallback strings only; zero behavior change`

**Problem** — Doc comments still describe the COIL components in old-brand terms ("Red gradient", "Barlow Condensed", "red pill", "red accent") and two `os.log` subsystem fallbacks plus one UITest doc comment still say "PT-Helper"/"PT Helper". Pure rot; misleads future contributors.

**Sweep table (current → 0)** —

| File:line | Current text (verbatim) | Replacement |
|---|---|---|
| `DesignSystem.swift:428` | `/// Red gradient rule with uppercase Barlow Condensed title — use for all content section breaks.` | `/// Teal gradient rule with uppercase Industry-Bold title — use for all content section breaks.` |
| `DesignSystem.swift:449` | `/// Small red pill badge — "ACTIVE", "ON FIRE", count indicators, etc.` | `/// Small teal pill badge — "ACTIVE", "ON FIRE", count indicators, etc.` |
| `LoginView.swift:19` | `// Diagonal red accent — top-right` | `// Diagonal teal accent — top-right` |
| `Models/InjuryAnalyzer.swift:4` | `… bundleIdentifier ?? "PT-Helper", category: "InjuryAnalyzer")` | fallback string → `"COIL"` |
| `Models/WellnessAnalyzer.swift:4` | `… bundleIdentifier ?? "PT-Helper", category: "WellnessAnalyzer")` | fallback string → `"COIL"` |
| `../PT-HelperUITests/UITestBase.swift:3` | `/// Base class for all PT Helper UI tests.` | `/// Base class for all COIL UI tests.` |

(Verified complete: `grep -rniE 'barlow|red gradient|red pill|red accent'` over live Swift finds exactly the 3 comment sites; `grep -rn '"PT-Helper"'` finds exactly the 2 logger fallbacks; the underlying code at all 3 comment sites is already teal/Industry-Bold.)

**Explicit exclusions** — `Models/LegalContent.swift` (WS4-03, legal-gated); `ContentView.swift:141` and `Views/Dashboard/DashProfileView.swift:35` (dead trees, deleted by WS1); `Views/IntroCarouselView.swift:112` "Deep red radial" comment (fixed by WS4-01); target/product name `PT-Helper` in pbxproj/bundle-id (out of scope for this audit).

**Do NOT** — Do not rename files, targets, schemes, the `PT-Helper` bundle identifier, or any user-facing legal text.

**Files to touch** —
- `ios/PT-Helper/PT-Helper/DesignSystem.swift`
- `ios/PT-Helper/PT-Helper/LoginView.swift`
- `ios/PT-Helper/PT-Helper/Models/InjuryAnalyzer.swift`
- `ios/PT-Helper/PT-Helper/Models/WellnessAnalyzer.swift`
- `ios/PT-Helper/PT-HelperUITests/UITestBase.swift`

**Acceptance criteria** —
- [ ] Done-grep: `grep -rniE 'barlow|red gradient|red pill|red accent' /Users/noyfisher/IOS-Projects/PT-Helper-Agent-v1/ios/PT-Helper/PT-Helper --include='*.swift'` returns 0 hits.
- [ ] `grep -rn '"PT-Helper"' /Users/noyfisher/IOS-Projects/PT-Helper-Agent-v1/ios/PT-Helper/PT-Helper --include='*.swift'` returns 0 hits.
- [ ] `grep -rn 'PT Helper' /Users/noyfisher/IOS-Projects/PT-Helper-Agent-v1/ios/PT-Helper/PT-Helper/PT-HelperUITests 2>/dev/null; grep -rn 'PT Helper' /Users/noyfisher/IOS-Projects/PT-Helper-Agent-v1/ios/PT-Helper/PT-Helper --include='*.swift' | grep -v 'LegalContent\|ContentView.swift\|DashProfileView'` returns 0 hits.
- [ ] Build + SmokePlan pass.

**Verify** —
```bash
cd /Users/noyfisher/IOS-Projects/PT-Helper-Agent-v1
xcodebuild build -project ios/PT-Helper/PT-Helper.xcodeproj \
  -scheme PT-Helper -destination 'platform=iOS Simulator,name=iPhone 16'
xcodebuild test -project ios/PT-Helper/PT-Helper.xcodeproj \
  -scheme PT-Helper -testPlan SmokePlan -destination 'platform=iOS Simulator,name=iPhone 16'
```

**Depends on / Blocks** — Independent of WS4-01 (patterns don't overlap), but if WS1's dead-tree deletion has landed, the third acceptance grep can drop its `ContentView.swift|DashProfileView` exclusions. Blocks nothing.

---

### [WS4-06] Remove dead Inter-Bold font (unregistered payload)
`P3` · `effort: S` · `risk: none — zero code references; 420 KB dead binary in every install`

**Problem** — `Inter-Bold.ttf` is registered and bundled but referenced by zero Swift code: the AppFonts Inter ladder stops at SemiBold and all bold/heading weights use Industry-Bold. Decision (settled, per verified finding S42): REMOVE rather than tokenize — Industry-Bold owns emphasis and no sweep introduces a bold-Inter need.

**Evidence** —
- `ios/PT-Helper/Info.plist:28` — `<string>Fonts/Inter-Bold.ttf</string>` inside the `UIAppFonts` array (:22-29).
- `ios/PT-Helper/PT-Helper/Resources/Fonts/Inter-Bold.ttf` — present on disk (420 KB).
- `grep -rn 'Inter-Bold' ios --include='*.swift'` → 0 hits; `grep -n 'Inter-Bold' ios/PT-Helper/PT-Helper.xcodeproj/project.pbxproj` → 0 hits (folder is a `PBXFileSystemSynchronizedRootGroup`, so file deletion needs no pbxproj edit).
- `DesignSystem.swift:276-293` region — AppFonts defines only Inter-Regular/Medium/SemiBold body tokens; headings use Industry-Bold.

**Change spec** —
1. Delete `ios/PT-Helper/PT-Helper/Resources/Fonts/Inter-Bold.ttf` (`git rm`).
2. Remove the line `<string>Fonts/Inter-Bold.ttf</string>` from the `UIAppFonts` array in `ios/PT-Helper/Info.plist` (leave Industry-Bold.otf and the other three Inter entries).

**Do NOT** — Do not touch Industry-Bold or the Inter Regular/Medium/SemiBold entries, and do not add a bodyBold token (rejected fork).

**Files to touch** —
- `ios/PT-Helper/PT-Helper/Resources/Fonts/Inter-Bold.ttf` (delete)
- `ios/PT-Helper/Info.plist`

**Acceptance criteria** —
- [ ] `grep -rn 'Inter-Bold' /Users/noyfisher/IOS-Projects/PT-Helper-Agent-v1/ios` returns 0 hits.
- [ ] `test ! -f /Users/noyfisher/IOS-Projects/PT-Helper-Agent-v1/ios/PT-Helper/PT-Helper/Resources/Fonts/Inter-Bold.ttf && echo GONE` prints GONE.
- [ ] `plutil -lint ios/PT-Helper/Info.plist` prints OK.
- [ ] Build + SmokePlan pass (no missing-font console warnings on launch).

**Verify** —
```bash
cd /Users/noyfisher/IOS-Projects/PT-Helper-Agent-v1
xcodebuild build -project ios/PT-Helper/PT-Helper.xcodeproj \
  -scheme PT-Helper -destination 'platform=iOS Simulator,name=iPhone 16'
xcodebuild test -project ios/PT-Helper/PT-Helper.xcodeproj \
  -scheme PT-Helper -testPlan SmokePlan -destination 'platform=iOS Simulator,name=iPhone 16'
```

**Depends on / Blocks** — nothing.

---

**Skipped (P3, low value):**
- Intro p2 missing page indicator / p3 centered-indicator inconsistency (audit `intro2-light.png`, `intro3-light.png`) — layout redesign, excluded by D-4 (re-skin only).
- Logger subsystem fallbacks fire only when `Bundle.main.bundleIdentifier` is nil (never in a real install) — included in WS4-05 only because the sweep is already touching neighbors; would not justify its own item.

## WS5: Workout engine correctness

**Scope:** Fix the checkpoint double-count at the exercise boundary (S1), convert the rest countdown to wall-clock end-Date reconciliation (S2 / deferred #51), add scenePhase-driven background-save + foreground-reconcile (S4 reframed), and delete the dead TimerViewModel/TimerView/ExerciseTimer trio (S3 reframed — deletion supersedes the originally-planned `@MainActor` annotation).
**Size:** M · **Risk:** MEDIUM-HIGH (checkpoint/timer state machine; regressions corrupt workout data) · **Required test plan:** UnitPlan (GuidedWorkoutViewModelTests extended).
**Execute in item order:** WS5-01 → WS5-02 → WS5-03 (all three touch `GuidedWorkoutViewModel.swift`); WS5-04 is independent.

**Shared context.** All workout-engine state lives in `ios/PT-Helper/PT-Helper/ViewModels/GuidedWorkoutViewModel.swift` (`@MainActor`, verified at 5fd0abb) with a single production consumer, `ios/PT-Helper/PT-Helper/Views/GuidedWorkoutView.swift` (`vm.completeSet()` has exactly one call site, GuidedWorkoutView.swift:297). Checkpoints persist to `UserDefaults` key `"GuidedWorkoutCheckpoint"` (VM :12), restore via the "Resume Workout?" alert (GuidedWorkoutView.swift:63–88), and `restoreFromCheckpoint` always forces `phase = .exercise` (VM :326). The governing invariant this workstream establishes: **a persisted checkpoint always records the next actionable (exerciseIndex, currentSet) the user should perform on resume — never state the user has already completed.** The mid-set save path (VM :164–170: `currentSet += 1` at :166 *then* `saveCheckpoint()` at :167) already satisfies this invariant and is the template; the final-set and skip paths violate it. The elapsed timer (VM :424–431, `accumulatedTime + Date().timeIntervalSince(lastResumeTime)` at :429) is the wall-clock template for WS5-02. The `RestKind` enum and its routing were verified good this session and are on the Do-NOT-touch list in every item. Tests: `ios/PT-Helper/PT-HelperTests/ViewModels/GuidedWorkoutViewModelTests.swift` (`@MainActor final class`, helpers `makeExercise(name:sets:restSeconds:)` :17–29 and `makePlan(exercises:)` :31–44; no test waits on real timer ticks — rests are always ended via `skipRest()`, so wall-clock refactoring breaks no existing test). Known simulator quirk (assumed, from memory): if `name=iPhone 16` destination errors with an OS mismatch, pin the destination to `OS=18.2` — do not change the commands in this doc otherwise.

**DO NOT TOUCH (verified-good RestKind logic — applies to every item below):**
- `enum RestKind` declaration, VM :47–50
- `@Published private(set) var restKind` :52 and the `restKind = kind` assignment inside `startRestTimer` :380
- `endRest()`'s `switch restKind` routing (`.interSet` → stay on exercise / `.interExercise` → `moveToNextExercise()`), VM :344–353 (adding a `saveCheckpoint()` inside `moveToNextExercise` per WS5-01 is allowed; the switch itself is not)
- The inter-set rest clamp `min(exercise.restSeconds, 60)` at VM :168
- The rest-phase "up next" branching on `vm.restKind` in GuidedWorkoutView.swift:441–446
- Existing RestKind tests: `testCompleteSet_interSetRest_skipRest_staysOnSameExercise`, `testThreeSetExercise_fullProgression_appendsToCompleted`, `testRestKind_afterFinalSet_isInterExercise` (GuidedWorkoutViewModelTests.swift :287–362) — these must pass unmodified.

---

### [WS5-01] Fix checkpoint double-count at the exercise boundary (save-point semantics)
`P1` · `effort: M` · `risk: touches the checkpoint write path; a wrong save-point silently corrupts resumed-workout data`

**Problem** — Killing the app anywhere between the final-set tap of exercise N and the first checkpoint-writing action on exercise N+1 resumes the workout on the *already-completed* exercise with the "Complete Exercise" button armed. Tapping it appends a duplicate name to `completedExercises` (no dedupe) and double-increments the persistent familiarity counter, inflating `WorkoutSession.exercisesPerformed`, the "Completed N exercises" summary, and Progress-tab stats. The skip path has the same defect class: a kill-and-resume re-presents the skipped exercise; completing it then puts the same name in BOTH `completedExercises` and `skippedExercises`.

**Evidence** (all verified at 5fd0abb)
- `ios/PT-Helper/PT-Helper/ViewModels/GuidedWorkoutViewModel.swift:151-163` — final-set branch: `completedExercises.append` :153, `Self.incrementCompletionCount` :154, `saveCheckpoint()` :155 with `currentExerciseIndex` still pointing at the completed exercise and `currentSet == exercise.sets`, then `startRestTimer(..., kind: .interExercise)` :159.
- `GuidedWorkoutViewModel.swift:283-297` — `saveCheckpoint()` snapshots live (un-advanced) `currentExerciseIndex`/`currentSet`.
- `GuidedWorkoutViewModel.swift:317-327` — `restoreFromCheckpoint` forces `phase = .exercise` :326, re-arming the completed exercise.
- `GuidedWorkoutViewModel.swift:331-340` and `:344-353` — neither `moveToNextExercise()` nor `endRest()` writes a checkpoint after the index advances, so the stale checkpoint survives the whole rest AND the post-rest window until the next `completeSet`/skip.
- `GuidedWorkoutViewModel.swift:174-182` — `skipExercise()` saves :180 BEFORE `moveToNextExercise()` :181 (same stale-index class).
- `GuidedWorkoutViewModel.swift:164-170` — mid-set branch advances `currentSet` :166 *before* saving :167 — the already-correct template.
- `ios/PT-Helper/PT-Helper/Views/GuidedWorkoutView.swift:63-88` — resume prompt; `:297` — sole `completeSet()` call site.
- Repro (V1, written step-by-step): plan [A(2 sets), B, C] → complete both sets of A → checkpoint {idx:0, set:2, completed:["A"]} → kill during inter-exercise rest (or after rest, before acting on B) → relaunch, Resume → back on A, "Complete Exercise" armed → tap → `completedExercises == ["A","A"]`, `exerciseCompletions_A == 2`.

**Change spec** (approach chosen: parameterized save + save-after-advance; NO checkpoint schema change, NO restore-side inference — smallest diff that satisfies the invariant, and old in-flight checkpoints stay decodable)
1. In `GuidedWorkoutViewModel.swift`, change the `saveCheckpoint` declaration (:283) to `func saveCheckpoint(forNextExercise: Bool = false)`. Inside, build the `WorkoutCheckpoint` with:
   `currentExerciseIndex: forNextExercise ? currentExerciseIndex + 1 : currentExerciseIndex` and `currentSet: forNextExercise ? 1 : currentSet`. All other fields unchanged. Add a doc comment stating the invariant: "A checkpoint always records the next actionable exercise/set; pass `forNextExercise: true` when saving at the moment an exercise is completed but the index has not yet advanced (inter-exercise rest window)."
2. Rewrite the final-set branch of `completeSet()` (:151–163) so the save moves inside the not-last-exercise arm and records the advanced position:
   ```swift
   if currentSet >= exercise.sets {
       completedExercises.append(exercise.name)
       Self.incrementCompletionCount(for: exercise.name)
       if currentExerciseIndex < totalExercises - 1 {
           saveCheckpoint(forNextExercise: true)
           startRestTimer(seconds: exercise.restSeconds, kind: .interExercise)
       } else {
           finishWorkout()   // clears the checkpoint (:364) — no save needed
       }
   }
   ```
   (The unconditional `saveCheckpoint()` formerly at :155 is deleted.) Rationale: the checkpoint written at the boundary now points at exercise N+1 / set 1, so a kill during the inter-exercise rest resumes directly on the next exercise (rest is intentionally not resumed — `restoreFromCheckpoint` already forces `.exercise`, preserved behavior).
3. In `skipExercise()` (:174–182), delete the `saveCheckpoint()` call at :180. The save moves into `moveToNextExercise()` (step 4), which runs one line later with the advanced index.
4. In `moveToNextExercise()` (:331–340), add `saveCheckpoint()` immediately after `phase = .exercise` in the advancing branch (after :336). This covers the skip path AND refreshes the boundary checkpoint when an inter-exercise rest ends normally (idempotent with step 2's save — both record idx+1/set 1). The `else` branch (`finishWorkout()`) is unchanged — it already clears the checkpoint.
5. Leave `restoreFromCheckpoint` (:317–327) untouched, including the `min(checkpoint.currentExerciseIndex, totalExercises - 1)` clamp at :318 and `phase = .exercise` at :326.
6. In `GuidedWorkoutViewModelTests.swift`, replace the `tearDown` body (:9–13) with `GuidedWorkoutViewModel.clearAllLocalWorkoutState()` (clears the checkpoint key AND all `exerciseCompletions_` counters — the new tests assert on `completionCount`, and existing tests already pollute those keys).
7. Add these tests to `GuidedWorkoutViewModelTests` (use existing `makeExercise`/`makePlan` helpers; all synchronous — no timer waits):
   - `testCheckpoint_afterFinalSetOfExercise_pointsToNextExercise` — plan [Ex1(1 set), Ex2(1 set)]; `vm.completeSet()`; `savedCheckpoint(forPlanId:)` must have `currentExerciseIndex == 1`, `currentSet == 1`, `completedExercises == ["Ex1"]`.
   - `testCheckpoint_resumeAfterFinalSet_doesNotDoubleCount` — the V1 repro: after the state above, build a second `GuidedWorkoutViewModel` from the same plan, `restoreFromCheckpoint`; assert `currentExercise?.name == "Ex2"`, `completedExercises == ["Ex1"]`, `GuidedWorkoutViewModel.completionCount(for: "Ex1") == 1`; then `completeSet()` on Ex2 and assert `completedExercises == ["Ex1", "Ex2"]` (no duplicate).
   - `testCheckpoint_afterInterExerciseRestEnds_pointsToNextExercise` — `completeSet()` then `skipRest()`; checkpoint must read idx 1 / set 1 (proves the `moveToNextExercise` save).
   - `testCheckpoint_afterSkip_pointsToNextExercise` — `skipExercise()` on a 3-exercise plan; checkpoint must read idx 1 / set 1 with `skippedExercises == ["Wall Sits"]`; restore into a fresh VM and assert `currentExercise?.name == "Quad Sets"` (skipped exercise is NOT re-presented).
   - `testCheckpoint_lastExercise_clearedOnCompletion` — single-exercise plan, `completeSet()` through all sets; `savedCheckpoint(forPlanId:)` must be `nil`.

**Do NOT** — add name-dedupe guards to `completedExercises`/`skippedExercises` (masks bugs, breaks duplicate-name plans); touch `swapCurrentExercise` checkpointing (no verified finding); touch the rest-timer internals (:378–431 — WS5-02 owns them); touch `RestKind` routing (see shared Do-NOT list).

**Files to touch**
- `ios/PT-Helper/PT-Helper/ViewModels/GuidedWorkoutViewModel.swift`
- `ios/PT-Helper/PT-HelperTests/ViewModels/GuidedWorkoutViewModelTests.swift`

**Acceptance criteria**
- [ ] `grep -c "saveCheckpoint()" ios/PT-Helper/PT-Helper/ViewModels/GuidedWorkoutViewModel.swift` returns exactly `2` (mid-set branch + `moveToNextExercise`) — becomes `3` only after WS5-03 lands.
- [ ] `grep -c "saveCheckpoint(forNextExercise: true)" ios/PT-Helper/PT-Helper/ViewModels/GuidedWorkoutViewModel.swift` returns exactly `1` (completeSet final-set branch) — becomes `2` only after WS5-03 lands.
- [ ] `grep -n "saveCheckpoint" ios/PT-Helper/PT-Helper/ViewModels/GuidedWorkoutViewModel.swift` shows NO call inside `skipExercise()`.
- [ ] All 5 new tests pass; pre-existing `testCheckpoint_duringInterSetRest_restoresToSameExerciseAndSet` and `testFullWorkout_twoExercises` pass UNMODIFIED (mid-set invariant preserved).
- [ ] Full UnitPlan green.

**Verify**
```bash
xcodebuild build -project ios/PT-Helper/PT-Helper.xcodeproj \
  -scheme PT-Helper -destination 'platform=iOS Simulator,name=iPhone 16'

xcodebuild test -project ios/PT-Helper/PT-Helper.xcodeproj \
  -scheme PT-Helper -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:PT-HelperTests/GuidedWorkoutViewModelTests

xcodebuild test -project ios/PT-Helper/PT-Helper.xcodeproj \
  -scheme PT-Helper -destination 'platform=iOS Simulator,name=iPhone 16'
```

**Depends on / Blocks** — Depends on nothing. Blocks WS5-03 (uses `saveCheckpoint(forNextExercise:)`).

---

### [WS5-02] Convert rest countdown to wall-clock end-Date reconciliation
`P1` · `effort: M` · `risk: rewrites the rest-timer core; a wrong derivation breaks every rest in every workout`

**Problem** — The rest countdown is tick-based: both timer sinks do `timeRemaining -= 1` per Combine tick on the main run loop, and the run loop suspends with the process, delivering no catch-up ticks. A 60-second rest with 55 seconds spent backgrounded resumes with essentially the same `timeRemaining` — the rest effectively freezes whenever the user leaves the app, which is exactly when rests happen (checking messages between sets). This is deferred prior-audit item #51.

**Evidence** (all verified at 5fd0abb)
- `ios/PT-Helper/PT-Helper/ViewModels/GuidedWorkoutViewModel.swift:385-399` — `startRestTimer` sink: decrement at :390, light-impact haptic at `== 5` :391–392, success haptic at `== 0` :393–394, `endRest()` on the tick after zero :397.
- `GuidedWorkoutViewModel.swift:402-415` — `resumeRestTimer` sink: near-duplicate of the above minus haptics (decrement at :410) — collapses to one code path under this refactor.
- `GuidedWorkoutViewModel.swift:424-431` — elapsed timer is Date-based (`accumulatedTime + Date().timeIntervalSince(lastResumeTime)` :429) and self-heals across backgrounding — the fix template; supporting state at :100–102.
- `GuidedWorkoutViewModel.swift:194-197` — `adjustRestTime` mutates `timeRemaining`/`restDuration` directly; `:205-219` — `togglePause` cancels/recreates the subscription (both interact cleanly with an end-Date design).

**Change spec** (approach chosen: stored `restEndDate` + derived remaining + injectable clock; single ticker replaces both sinks)
1. In `GuidedWorkoutViewModel.swift`, add two members in the `// MARK: - Timer` block (after :102):
   ```swift
   /// Wall-clock end of the current rest. Source of truth for timeRemaining.
   private var restEndDate: Date?
   /// Injectable clock for the rest-timer paths (test seam). Production: real Date.
   var now: () -> Date = { Date() }
   ```
2. Rewrite `startRestTimer(seconds:kind:)` (:378–400):
   ```swift
   private func startRestTimer(seconds: Int, kind: RestKind) {
       phase = .rest
       restKind = kind
       timeRemaining = max(seconds, 5)
       restDuration = timeRemaining
       restEndDate = now().addingTimeInterval(TimeInterval(timeRemaining))
       isTimerRunning = true
       startRestTicker()
   }

   private func startRestTicker() {
       timerSubscription = Foundation.Timer.publish(every: 1, on: .main, in: .common)
           .autoconnect()
           .sink { [weak self] _ in
               self?.reconcileRestFromWallClock()
           }
   }
   ```
3. Add the reconciliation function — deliberately **internal** (WS5-03 and the tests call it):
   ```swift
   /// Derive timeRemaining from the wall-clock end date. Called every ticker
   /// tick and on foreground return; self-heals after any suspension.
   func reconcileRestFromWallClock() {
       guard !isPaused, phase == .rest, let end = restEndDate else { return }
       let remaining = max(0, Int(end.timeIntervalSince(now()).rounded(.up)))
       if timeRemaining > 5 && remaining <= 5 && remaining > 0 {
           UIImpactFeedbackGenerator(style: .light).impactOccurred()
       }
       timeRemaining = remaining
       if remaining == 0 {
           UINotificationFeedbackGenerator().notificationOccurred(.success)
           endRest()
       }
   }
   ```
   Haptics are edge-triggered (`>5 → ≤5` crossing) so a wall-clock jump fires each at most once. Behavior delta accepted: rest now ends in the same tick that reaches 0 instead of one tick later (rest is exactly `seconds` long, previously `seconds + 1`).
4. Delete `resumeRestTimer()` (:402–415) entirely. In `togglePause()`'s resume branch, replace the `resumeRestTimer()` call (:216) with:
   ```swift
   if phase == .rest && timeRemaining > 0 {
       restEndDate = now().addingTimeInterval(TimeInterval(timeRemaining))
       isTimerRunning = true
       startRestTicker()
   }
   ```
   Rationale: `timeRemaining` frozen at pause is authoritative; resume re-anchors the end date from it, so paused time never counts against the rest.
5. Rewrite `adjustRestTime(by:)` (:194–197) to re-anchor the end date, preserving the 5-second floor and the ring-duration rule:
   ```swift
   func adjustRestTime(by seconds: Int) {
       timeRemaining = max(5, timeRemaining + seconds)
       restDuration = max(restDuration, timeRemaining)
       restEndDate = now().addingTimeInterval(TimeInterval(timeRemaining))
   }
   ```
6. In `stopTimer()` (:417–422), add `restEndDate = nil` after `timeRemaining = 0`.
7. Add tests to `GuidedWorkoutViewModelTests` (drive time via the `now` seam + direct `reconcileRestFromWallClock()` calls — zero real waiting):
   - `testRestTimer_reconcile_afterTimeJump_derivesFromWallClock` — plan with `makeExercise(sets: 2, restSeconds: 60)`; freeze a `base = Date()` via `vm.now = { base }` BEFORE `completeSet()`; `completeSet()` (inter-set rest, 60s); set `vm.now = { base.addingTimeInterval(40) }`; `vm.reconcileRestFromWallClock()`; assert `vm.timeRemaining == 20`.
   - `testRestTimer_reconcile_pastExpiry_endsRest` — same setup; jump `+61`; reconcile; assert `vm.phase == .exercise` and `vm.currentSet == 2` (inter-set rest returned to the same exercise — RestKind routing preserved).
   - `testAdjustRestTime_reAnchorsEndDate` — during the 60s rest with frozen clock, `vm.adjustRestTime(by: 15)`; assert `timeRemaining == 75`; reconcile with clock unchanged; assert still `75`. Also `vm.adjustRestTime(by: -1000)` → `timeRemaining == 5` (floor preserved).
   - `testPauseDuringRest_resumePreservesRemaining` — frozen clock, start rest (60); `togglePause()`; jump clock `+30`; `togglePause()` again; `reconcileRestFromWallClock()`; assert `timeRemaining == 60` (paused time doesn't burn rest).

**Do NOT** — touch `RestKind` routing or the inter-set clamp (shared Do-NOT list); convert the elapsed timer or `saveCheckpoint`'s `Date()` reads to the `now` seam (out of scope — elapsed timer is already wall-clock-correct); add scenePhase observers (WS5-03 owns that); redesign the rest UI (`restPhaseView`, deferred #52 is a settled DROP).

**Files to touch**
- `ios/PT-Helper/PT-Helper/ViewModels/GuidedWorkoutViewModel.swift`
- `ios/PT-Helper/PT-HelperTests/ViewModels/GuidedWorkoutViewModelTests.swift`

**Acceptance criteria**
- [ ] `grep -c "timeRemaining -= 1" ios/PT-Helper/PT-Helper/ViewModels/GuidedWorkoutViewModel.swift` returns `0`.
- [ ] `grep -c "resumeRestTimer" ios/PT-Helper/PT-Helper/ViewModels/GuidedWorkoutViewModel.swift` returns `0`.
- [ ] `grep -c "restEndDate" ios/PT-Helper/PT-Helper/ViewModels/GuidedWorkoutViewModel.swift` returns ≥ `5` (declaration + start/resume/adjust/stop/reconcile sites).
- [ ] All 4 new tests pass; the 3 protected RestKind tests (shared Do-NOT list) pass UNMODIFIED.
- [ ] Full UnitPlan green.
- [ ] Manual sim check: start a workout, complete a set, background the app 20s mid-rest, foreground — countdown shows ~20s less (not frozen). No screenshot compare needed (no visual layout change).

**Verify**
```bash
xcodebuild build -project ios/PT-Helper/PT-Helper.xcodeproj \
  -scheme PT-Helper -destination 'platform=iOS Simulator,name=iPhone 16'

xcodebuild test -project ios/PT-Helper/PT-Helper.xcodeproj \
  -scheme PT-Helper -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:PT-HelperTests/GuidedWorkoutViewModelTests

xcodebuild test -project ios/PT-Helper/PT-Helper.xcodeproj \
  -scheme PT-Helper -destination 'platform=iOS Simulator,name=iPhone 16'
```

**Depends on / Blocks** — Depends on nothing (same-file coordination with WS5-01: execute after it). Blocks WS5-03 (uses `reconcileRestFromWallClock()` and the `now` seam).

---

### [WS5-03] Add scenePhase background-save and foreground wall-clock reconcile to GuidedWorkout
`P2` · `effort: S` · `risk: a naive background-save during inter-exercise rest would REINTRODUCE the WS5-01 double-count — the restKind guard in step 3 is load-bearing`

**Problem** — GuidedWorkout has no scenePhase handling at all, so (a) backgrounding mid-set never persists a checkpoint — a background kill loses all elapsed time and progress since the last set boundary, and (b) on foreground return the rest ring shows a stale value for up to one tick. Note the original "timers keep firing while backgrounded" framing was REFUTED this session: all three timers ride the main run loop, which suspends with the process (that suspension IS the S2 freeze); this item is the reconcile/persist complement to WS5-02, not a battery fix.

**Evidence** (all verified at 5fd0abb)
- App-wide grep for `scenePhase`: only `ios/PT-Helper/PT-Helper/PT_HelperApp.swift:25,41` (SessionLogger/analytics) and `ios/PT-Helper/PT-Helper/Views/OnboardingView.swift:7,136` — nothing in GuidedWorkoutView/ViewModel.
- `PT_HelperApp.swift:41` — the project's `.onChange(of: scenePhase) { _, newPhase in ... }` signature pattern to copy.
- `GuidedWorkoutViewModel.swift:385,405,425` — all three timers are `Timer.publish(every: 1, on: .main, in: .common)` (suspend with the process).
- `PT_HelperApp.swift:52` — app-level `beginBackgroundTask("SessionLogUpload")` keeps the process alive ~30s post-background; timers tick during that window, then suspend (no user-visible defect by itself).
- `GuidedWorkoutViewModel.swift:283-297` — checkpoints are written only at set/skip boundaries today; backgrounding mid-set persists nothing.

**Change spec**
1. In `GuidedWorkoutView.swift`, add `@Environment(\.scenePhase) private var scenePhase` to the view's property block (alongside the existing `@State` properties at the top of `struct GuidedWorkoutView`).
2. Add this modifier immediately after the existing `.onChange(of: vm.currentExerciseIndex)` modifier (GuidedWorkoutView.swift:110), copying the two-parameter signature from PT_HelperApp.swift:41:
   ```swift
   .onChange(of: scenePhase) { _, newPhase in
       switch newPhase {
       case .background: vm.handleAppBackgrounded()
       case .active: vm.handleAppForegrounded()
       default: break
       }
   }
   ```
3. In `GuidedWorkoutViewModel.swift`, add a `// MARK: - Scene Phase` section with:
   ```swift
   /// Persist an accurate checkpoint when the app is backgrounded mid-workout.
   /// During an inter-exercise rest the live index still points at the exercise
   /// just completed, so save the advanced position (same rule as completeSet's
   /// final-set branch) — a live-state save here would resurrect the WS5-01 bug.
   func handleAppBackgrounded() {
       guard phase != .complete else { return }
       if phase == .rest && restKind == .interExercise {
           saveCheckpoint(forNextExercise: true)
       } else {
           saveCheckpoint()
       }
   }

   /// Snap timers to the wall clock immediately on return to foreground
   /// (instead of waiting up to 1s for the next ticker tick).
   func handleAppForegrounded() {
       guard !isPaused, phase != .complete else { return }
       if phase == .rest {
           reconcileRestFromWallClock()
       }
       totalElapsedTime = accumulatedTime + now().timeIntervalSince(lastResumeTime)
   }
   ```
   (Elapsed time intentionally includes backgrounded time — that matches the existing self-healing behavior of the Date-based elapsed timer at :429.)
4. Add tests to `GuidedWorkoutViewModelTests`:
   - `testHandleAppBackgrounded_duringInterExerciseRest_savesAdvancedCheckpoint` — plan [Ex1(1 set), Ex2]; `completeSet()` (now in inter-exercise rest); `handleAppBackgrounded()`; checkpoint must read idx 1 / set 1 (NOT idx 0).
   - `testHandleAppBackgrounded_midExercise_savesLiveState` — fresh VM, no actions; `handleAppBackgrounded()`; checkpoint must read idx 0 / set 1.
   - `testHandleAppBackgrounded_afterComplete_savesNothing` — single-exercise plan completed; `handleAppBackgrounded()`; `savedCheckpoint(forPlanId:)` must be `nil`.
   - `testHandleAppForegrounded_duringRest_reconciles` — frozen-clock rest (as in WS5-02 tests), jump `+40`, `handleAppForegrounded()`; assert `timeRemaining == 20`.

**Do NOT** — tear down or recreate timer subscriptions on backgrounding (refuted framing — suspension already handles it, and teardown-only would not fix the freeze); touch PT_HelperApp/OnboardingView scenePhase handlers; add background-task or notification scheduling (WS2 owns notifications).

**Files to touch**
- `ios/PT-Helper/PT-Helper/Views/GuidedWorkoutView.swift`
- `ios/PT-Helper/PT-Helper/ViewModels/GuidedWorkoutViewModel.swift`
- `ios/PT-Helper/PT-HelperTests/ViewModels/GuidedWorkoutViewModelTests.swift`

**Acceptance criteria**
- [ ] `grep -c "scenePhase" ios/PT-Helper/PT-Helper/Views/GuidedWorkoutView.swift` returns exactly `2` (property + onChange).
- [ ] `grep -c "saveCheckpoint(forNextExercise: true)" ios/PT-Helper/PT-Helper/ViewModels/GuidedWorkoutViewModel.swift` returns exactly `2` (completeSet + handleAppBackgrounded).
- [ ] All 4 new tests pass; WS5-01's `testCheckpoint_resumeAfterFinalSet_doesNotDoubleCount` still passes (regression gate on the restKind guard).
- [ ] Full UnitPlan green.
- [ ] No visual delta expected (behavioral modifiers only) — no screenshot compare required.

**Verify**
```bash
xcodebuild build -project ios/PT-Helper/PT-Helper.xcodeproj \
  -scheme PT-Helper -destination 'platform=iOS Simulator,name=iPhone 16'

xcodebuild test -project ios/PT-Helper/PT-Helper.xcodeproj \
  -scheme PT-Helper -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:PT-HelperTests/GuidedWorkoutViewModelTests

xcodebuild test -project ios/PT-Helper/PT-Helper.xcodeproj \
  -scheme PT-Helper -destination 'platform=iOS Simulator,name=iPhone 16'
```

**Depends on / Blocks** — Depends on WS5-01 (`saveCheckpoint(forNextExercise:)`) and WS5-02 (`reconcileRestFromWallClock()`, `now` seam). Blocks nothing.

---

### [WS5-04] Delete the dead TimerViewModel/TimerView/ExerciseTimer trio
`P2` · `effort: S` · `risk: low — zero production references verified; only risk is a missed reference, gated by build`

**Problem** — `TimerView` has zero production call sites anywhere in the app, making its entire dependency chain (`TimerViewModel`, `ExerciseTimer`, and their test files) dead code that still costs build time, test time, and maintenance attention. This supersedes the originally-planned "add `@MainActor` to TimerViewModel" (S3 REFRAMED verdict: the missing annotation is a Swift-6 hygiene gap on the main run loop, not a live data race — and moot once deleted). This trio is NOT on D-1's dead-tree list (Dashboard/AssessTab/legacy 4-tab/LegacyUITests/showcase), so WS5 owns it; no overlap with WS1.

**Evidence** (all verified at 5fd0abb)
- `ios/PT-Helper/PT-Helper/ViewModels/TimerViewModel.swift:4` — `class TimerViewModel: ObservableObject`, the only 1 of 15 ViewModels without `@MainActor`; sink :21–26 → `updateTimer()` :38–45 mutates `@Published` state.
- `ios/PT-Helper/PT-Helper/Views/TimerView.swift:4` — `@ObservedObject var viewModel: TimerViewModel` — the ONLY consumer; grep for `TimerView`/`TimerViewModel` outside these two files matches ONLY `PT-HelperTests/ViewModels/TimerViewModelTests.swift`.
- `ios/PT-Helper/PT-Helper/Models/Timer.swift:3` — `class ExerciseTimer`; grep shows its only consumers are `TimerViewModel.swift` and `PT-HelperTests/Models/ExerciseTimerTests.swift`.
- `ios/PT-Helper/PT-Helper.xcodeproj/project.pbxproj` — grep for `TimerView|Timer.swift|ExerciseTimer` returns zero hits (Xcode 16 `PBXFileSystemSynchronizedRootGroup` — no manual pbxproj edits needed for deletion either).
- Test plans: `SmokePlan.xctestplan` `selectedTests` (11 entries) contains no Timer tests; `UnitPlan.xctestplan` `skippedTests` is only `BodyMapCollisionTests`; FullPlan/PreReleasePlan have no per-test lists — deleting the test files breaks no plan.

**Change spec**
1. `git rm` these five files:
   - `ios/PT-Helper/PT-Helper/Views/TimerView.swift`
   - `ios/PT-Helper/PT-Helper/ViewModels/TimerViewModel.swift`
   - `ios/PT-Helper/PT-Helper/Models/Timer.swift`
   - `ios/PT-Helper/PT-HelperTests/ViewModels/TimerViewModelTests.swift`
   - `ios/PT-Helper/PT-HelperTests/Models/ExerciseTimerTests.swift`
2. No pbxproj edit (synchronized groups auto-discover removals; verified zero explicit references).
3. Update `/Users/noyfisher/IOS-Projects/PT-Helper-Agent-v1/CLAUDE.md` architecture inventory to stay truthful (exact edits):
   - `**Models/** (21 files)` → `**Models/** (20 files)`; in the `Workout:` line remove `` `Timer` `` (leaving `` `WorkoutSession`, `Achievement` ``).
   - `**ViewModels/** (15 files)` → `**ViewModels/** (14 files)`; remove `` `TimerViewModel`, `` from the ViewModel list line.
4. Do not touch `TimerViewModel`-unrelated timer code: `GuidedWorkoutViewModel`'s timers and `Models/SessionEvent`/etc. are out of scope; the only files removed are the five listed.

**Do NOT** — add `@MainActor` to TimerViewModel "just in case" before deleting (pointless churn); delete any other file WS1's D-1 list owns (Dashboard/AssessTab/legacy 4-tab/LegacyUITests/showcase harness); rename or repurpose `GuidedWorkoutView`'s rest ring to "replace" TimerView.

**Files to touch**
- `ios/PT-Helper/PT-Helper/Views/TimerView.swift` (delete)
- `ios/PT-Helper/PT-Helper/ViewModels/TimerViewModel.swift` (delete)
- `ios/PT-Helper/PT-Helper/Models/Timer.swift` (delete)
- `ios/PT-Helper/PT-HelperTests/ViewModels/TimerViewModelTests.swift` (delete)
- `ios/PT-Helper/PT-HelperTests/Models/ExerciseTimerTests.swift` (delete)
- `/Users/noyfisher/IOS-Projects/PT-Helper-Agent-v1/CLAUDE.md` (inventory counts)

**Acceptance criteria**
- [ ] `grep -rn "TimerViewModel\|ExerciseTimer" ios/PT-Helper/PT-Helper ios/PT-Helper/PT-HelperTests ios/PT-Helper/PT-HelperUITests` returns `0` lines.
- [ ] `grep -rn "TimerView" ios/PT-Helper/PT-Helper ios/PT-Helper/PT-HelperTests ios/PT-Helper/PT-HelperUITests` returns `0` lines.
- [ ] The five files no longer exist on disk (`ls` each → no such file).
- [ ] Build succeeds and full UnitPlan is green with the reduced test set (no plan references the deleted classes).

**Verify**
```bash
xcodebuild build -project ios/PT-Helper/PT-Helper.xcodeproj \
  -scheme PT-Helper -destination 'platform=iOS Simulator,name=iPhone 16'

xcodebuild test -project ios/PT-Helper/PT-Helper.xcodeproj \
  -scheme PT-Helper -destination 'platform=iOS Simulator,name=iPhone 16'
```

**Depends on / Blocks** — nothing (fully independent of WS5-01/02/03).

---

**Skipped (P3, low value):**
- `@MainActor` annotation on TimerViewModel — superseded by WS5-04 deletion (S3 REFRAMED: hygiene gap, not a live race).
- Background timer teardown for battery — REFUTED framing (S4): main-run-loop timers suspend with the process; only the ~30s SessionLogUpload window ticks, immaterial.
- `max(seconds, 5)` floor in `startRestTimer` silently inflating sub-5s rests — cosmetic, no user report, preserved as-is by WS5-02.
- Inline rest chip instead of full-screen rest (deferred #52) — settled DROP in gap-hunt dispositions.

## WS6: Last-analysis resurfacing

Scope: restore the orphaned "Your Last Analysis" card (shipped 80f2caa, orphaned same day by merge cfb94c0) as a Progress-tab entry point that pushes a read-only `AnalysisResultView`, per settled decision D-6. Two items: the card itself (WS6-01) and the sign-out PHI clear that must land with it (WS6-02). Size S, risk LOW, required test plans: UnitPlan + SmokePlan.

**Shared context (all paths relative to `ios/PT-Helper/PT-Helper/` unless noted; all line numbers verified at 5fd0abb).** `AnalysisResultStore` (Services/AnalysisResultStore.swift) is a `@MainActor` singleton holding `@Published var lastResult: AnalysisResult?` (:14), file-backed at ApplicationSupport/`dashboardLastAnalysisResult.json` with `.completeFileProtection` (:30-38), loaded in `init` (:26-28), with a `clear()` that removes the file (:53-57). Every `AnalysisResultView` appearance saves into it (Views/AnalysisResultView.swift:100-103). `ThreeTabView` holds it (:12) and injects it via `.environmentObject` (:85), but the only readers are dead trees slated for D-1 deletion: `AssessTab.swift:105` and `Views/Dashboard/AnalysisDashboardView.swift:7,33` (neither is instantiated by any live view — `grep -rn "AssessTab("` returns zero live hits). The recovered reference UI is `AssessTab.swift:103-121` (card integration + `navigationDestination` push) and `:269-327` (`lastAnalysisCard(for:)` + `matchColor(_:)`). Because the D-1 workstream may delete `AssessTab.swift` before WS6 runs, WS6-01 embeds the full card implementation below — Sonnet must NOT need `AssessTab.swift` to exist. The Progress tab is `ProgressTab` → `ProgressTabContent` (Views/ProgressTab.swift:6-41, :45-636) inside its own `NavigationStack` (:15). Test seeding: `--uitesting --skip-onboarding --seed-mock-data` saves a seeded result whose top condition is `commonName: "Runner's Knee"`, confidence 78 → `MatchStrength.strong` = "Strong Match" (Services/TestDataSeeder.swift:175-187, :225; Services/ResponseValidationPipeline.swift:63-95).

---

### [WS6-01] Add read-only "Your Last Analysis" card to the Progress tab
`P1` · `effort: S` · `risk: LOW — additive UI on one live screen + a default-false flag on AnalysisResultView; only live caller (AnalyzingView:141) is untouched by the default`

**Problem** — A completed AI analysis persists across relaunches but no live screen surfaces it: after relaunch the only re-entry to a past analysis is regenerating from a saved plan (virtual-user finding F2, regressed again). The fix that shipped for F2 (80f2caa, 2026-06-10) was orphaned the same day when merge cfb94c0 swapped in the HomeTab shell. D-6 settles the new home: a card on the Progress tab pushing a read-only `AnalysisResultView`.

**Evidence**
- `Services/AnalysisResultStore.swift:14,26-28,30-38` — `@Published lastResult`, loaded from file in init, saved on every result view appearance; data is there, unread.
- `Views/AnalysisResultView.swift:100-103` — `.onAppear { AnalysisResultStore.shared.save(analysisResult); cardsAppeared = true }` populates the store on every appearance.
- `Views/AnalysisResultView.swift:4-6` — memberwise params `analysisResult` / `validationWarnings` / `redFlagAlerts`; no read-only concept exists yet.
- `Views/AnalysisResultView.swift:54-55` — `buildRehabPlanButton` and `navigationButtons` in the content stack; these are the interactive elements a read-only push must hide.
- `Views/AnalysisResultView.swift:554-574` — `navigationButtons` = `DismissButton` ("Back to Assessment") + a "Home" button posting `.popToRoot`; both are assessment-flow affordances, wrong from a Progress push.
- `Views/AnalyzingView.swift:141-149` — the ONLY live `AnalysisResultView(` call site; uses labeled params, unaffected by a new defaulted property.
- `Views/ProgressTab.swift:63-142` — `ProgressTabContent.body`: `ScrollView > VStack(spacing: AppSpacing.lg)` opens at :64-65; error/empty/data if-else spans :66-118; insertion point is the top of the VStack (before :66).
- `Views/ProgressTab.swift:50,53-55` — existing `@ObservedObject private var streakService = StreakService.shared` singleton-observation pattern and `@State` block to extend.
- `Views/AssessTab.swift:103-121,269-327` (historical provenance at 5fd0abb; the card code is embedded verbatim in the change spec below — do NOT grep this post-WS1, since D-1's WS1-06 may have deleted `AssessTab.swift` by the time WS6 runs, and this item is order-independent of that deletion) — recovered card UI: `if let` guard, `CoilDividerHeader(title: "Your Last Analysis")`, Button + `SessionLogger` log + `navigationDestination(isPresented:)` push, `lastAnalysisCard(for:)` (~49 LOC) and `matchColor(_:)`.
- `Services/ResponseValidationPipeline.swift:63-72,87-95` — `MatchStrength` (rawValues "Strong Match"/"Possible Match"/"Less Likely") and `ConfidenceCalibrator.matchStrength(for:)` used by the card.
- `Services/TestDataSeeder.swift:175-187,215-225` — seeded result: top condition "Runner's Knee" @78 ⇒ deterministic screenshot state.

**Change spec**

1. `Views/AnalysisResultView.swift` — add a read-only flag. After line 6 (`var redFlagAlerts: [ValidationWarning] = []`), add:
   ```swift
   /// True when pushed from the Progress tab's "Your Last Analysis" card (D-6):
   /// hides plan generation + assessment-flow navigation and skips the store re-save.
   var isReadOnly: Bool = false
   ```
   Defaulted false so the sole live call site (AnalyzingView:141) compiles unchanged.
2. Same file — wrap lines 54-55 (`buildRehabPlanButton` / `navigationButtons` inside the VStack):
   ```swift
   if !isReadOnly {
       buildRehabPlanButton
       navigationButtons
   }
   ```
   Rationale: hiding these two members is the entire read-only surface — everything else in the view (summary, condition cards, red-flag banners, info alerts, disclaimer) is display-only. The `showRehabPlan`/`showPreferencesSheet`/`showRiskAcknowledgement` state and sheets stay declared but become unreachable; do not delete them.
3. Same file — guard the store save at lines 100-103 so re-viewing does not rewrite the file and re-publish `lastResult` while the card driving the push observes it:
   ```swift
   .onAppear {
       if !isReadOnly { AnalysisResultStore.shared.save(analysisResult) }
       cardsAppeared = true
   }
   ```
4. `Views/ProgressTab.swift`, `ProgressTabContent` — add state. Below line 50 (`@ObservedObject private var streakService = StreakService.shared`), add `@ObservedObject private var analysisStore = AnalysisResultStore.shared` (matches the file's existing singleton-observation pattern; avoids threading a new constructor param through `ProgressTab`). In the `@State` block (:53-55), add `@State private var navigateToLastAnalysis = false`.
5. Same file — insert the section as the FIRST element of the body `VStack` (immediately after line 65 `VStack(spacing: AppSpacing.lg) {`, before the `if let loadError` at :66): `lastAnalysisSection`. Rationale (fork closed): placing it above the sessions if-else makes it render in the empty, error, AND data states — the F2 repro is precisely a user with an analysis but no logged workouts, who would otherwise see only "No Data Yet".
6. Same file — add the implementation after the `// MARK: - Outcome Prompt (Tier 3 PR D)` block (after :203), embedded verbatim (recovered from AssessTab:103-121/269-327 with fonts tokenized and identifiers renamed to the `progress.` screen prefix):
   ```swift
   // MARK: - Last Analysis (D-6, recovered from orphaned AssessTab card — vuser F2)

   /// Re-entry point to the most recent AI analysis. Hidden when no analysis has
   /// been run (nil) or when the stored result is the empty defensive fallback
   /// AnalyzingView can construct (conditions.isEmpty — nothing to display).
   @ViewBuilder
   private var lastAnalysisSection: some View {
       if let lastResult = analysisStore.lastResult, !lastResult.conditions.isEmpty {
           VStack(alignment: .leading, spacing: AppSpacing.md) {
               CoilDividerHeader(title: "Your Last Analysis")

               Button {
                   SessionLogger.shared.logUserAction(.buttonTapped,
                       action: "lastAnalysisOpened",
                       metadata: [:])
                   navigateToLastAnalysis = true
               } label: {
                   lastAnalysisCard(for: lastResult)
               }
               .buttonStyle(.plain)
               .accessibilityIdentifier("progress.lastAnalysisCard")
               .navigationDestination(isPresented: $navigateToLastAnalysis) {
                   AnalysisResultView(analysisResult: lastResult, isReadOnly: true)
               }
           }
       }
   }

   private func lastAnalysisCard(for result: AnalysisResult) -> some View {
       let topCondition = result.conditions.first
       let strength = topCondition.map { ConfidenceCalibrator.matchStrength(for: $0.confidence) }

       return HStack(spacing: AppSpacing.md) {
           Image(systemName: "stethoscope")
               .font(.system(size: 18, weight: .semibold))
               .foregroundColor(AppColors.accent)
               .frame(width: 40, height: 40)
               .background(AppColors.accent.opacity(0.12))
               .cornerRadius(AppCorners.small)

           VStack(alignment: .leading, spacing: 3) {
               Text(topCondition?.commonName ?? "Analysis Results")
                   .font(AppFonts.bodySemiBold)
                   .foregroundColor(AppColors.primaryText)

               HStack(spacing: AppSpacing.xs) {
                   if let strength {
                       Text(strength.rawValue)
                           .font(AppFonts.captionSemiBold)
                           .foregroundColor(matchStrengthColor(strength))
                       Text("•")
                           .font(AppFonts.caption)
                           .foregroundColor(AppColors.mutedText)
                   }
                   Text(result.generatedDate.formatted(.relative(presentation: .named)))
                       .font(AppFonts.caption)
                       .foregroundColor(AppColors.secondaryText)
               }

               Text("View your results")
                   .font(AppFonts.micro)
                   .foregroundColor(AppColors.mutedText)
           }

           Spacer()

           Image(systemName: "chevron.right")
               .font(.system(size: 13, weight: .semibold))
               .foregroundColor(AppColors.accent)
       }
       .padding(.horizontal, AppSpacing.lg)
       .padding(.vertical, AppSpacing.md)
       .background(AppColors.cardBackground)
       .cornerRadius(AppCorners.card)
       .overlay(RoundedRectangle(cornerRadius: AppCorners.card).stroke(AppColors.cardBorder, lineWidth: 1))
       .shadow(color: AppColors.cardShadowColor, radius: 8, y: 2)
   }

   private func matchStrengthColor(_ strength: MatchStrength) -> Color {
       switch strength {
       case .strong: return AppColors.success
       case .moderate: return AppColors.warning
       case .weak: return AppColors.mutedText
       }
   }
   ```
   Closed deltas vs the orphaned original, do not re-open: (a) fonts tokenized — `Inter-SemiBold 14`→`AppFonts.bodySemiBold`, `Inter-SemiBold 12`→`AppFonts.captionSemiBold`, `Inter-Regular 12`→`AppFonts.caption`, `Inter-Regular 11`→`AppFonts.micro` (exact size/weight matches per DesignSystem.swift:277-293, and CLAUDE.md forbids hardcoded typography); (b) hardcoded `14` spacing/padding → `AppSpacing.md` (12pt; nearest token, imperceptible); (c) subtitle "View results & build a rehab plan" → "View your results" (destination is read-only); (d) helper named `matchStrengthColor` because `ProgressTab.swift` has no existing `matchColor` but the name must not collide if one is ever hoisted; (e) `Button + navigationDestination(isPresented:)` kept over `NavigationLink` to preserve the `SessionLogger` tap log (analytics parity with 80f2caa).
7. Nil/empty handling (D-6 "Handle nil/empty state"): the `if let … , !lastResult.conditions.isEmpty` guard in step 6 IS the empty state — no header, no placeholder card, section fully absent. Do not add an empty-state card.

**Do NOT** — do not delete or edit the duplicate card code in `AssessTab.swift` / `Views/Dashboard/` (D-1 dead-tree deletion workstream owns those files); do not sweep other hardcoded fonts in `ProgressTab.swift` (D-5 typography workstream); do not touch sign-out/PHI clearing here (WS6-02 owns it).

**Files to touch**
- `ios/PT-Helper/PT-Helper/Views/ProgressTab.swift`
- `ios/PT-Helper/PT-Helper/Views/AnalysisResultView.swift`
Anything else = STOP and mark BLOCKED.

**Acceptance criteria**
- [ ] `grep -c "progress.lastAnalysisCard" ios/PT-Helper/PT-Helper/Views/ProgressTab.swift` returns `1`.
- [ ] `grep -c "isReadOnly" ios/PT-Helper/PT-Helper/Views/AnalysisResultView.swift` returns `3` (declaration + content guard + onAppear guard).
- [ ] `grep -c "Inter-" ios/PT-Helper/PT-Helper/Views/ProgressTab.swift` returns `0` (new card is token-only).
- [ ] `grep -c "isReadOnly" ios/PT-Helper/PT-Helper/Views/AnalyzingView.swift` returns `0` (live call site untouched; default carries it).
- [ ] Build + UnitPlan + SmokePlan pass (commands below).
- [ ] Simulator, launched with `--uitesting --skip-onboarding --seed-mock-data`: Progress tab shows a "Your Last Analysis" section above the pain chart with a card reading "Runner's Knee" / "Strong Match"; screenshot it.
- [ ] Tapping the card pushes "Analysis Results"; UI snapshot on that screen contains NO element with identifier `analysisResult.buildRehabPlanButton` and no "Back to Assessment" / "Home" buttons.
- [ ] Simulator, launched with `--uitesting --skip-onboarding` only (no seed) after erasing the app container (`xcrun simctl privacy booted reset all com.noyfisher.pthelper` is insufficient — delete/reinstall the app or `xcrun simctl uninstall booted com.noyfisher.pthelper` first): Progress tab shows NO "Your Last Analysis" header.
- [ ] Full analysis flow regression: complete a real/seeded analysis via AnalyzingView path — "Build Rehab Plan" button still present there (isReadOnly defaults false).

**Verify**
```bash
xcodebuild build -project ios/PT-Helper/PT-Helper.xcodeproj \
  -scheme PT-Helper -destination 'platform=iOS Simulator,name=iPhone 16'

xcodebuild test -project ios/PT-Helper/PT-Helper.xcodeproj \
  -scheme PT-Helper -destination 'platform=iOS Simulator,name=iPhone 16'

xcodebuild test -project ios/PT-Helper/PT-Helper.xcodeproj \
  -scheme PT-Helper -testPlan SmokePlan -destination 'platform=iOS Simulator,name=iPhone 16'
```
(Known quirk: if `name=iPhone 16` resolves no destination, retarget the same device with `OS=18.2` — see memory `project_build_simulator_destination`.)
UI check (launch args must go through simctl, not the MCP launcher):
```bash
xcrun simctl launch booted com.noyfisher.pthelper --uitesting --skip-onboarding --seed-mock-data
```
Then navigate to the Progress tab and visually compare against the pre-change baselines `/Users/noyfisher/IOS-Projects/PT-Helper-Agent-v1/ios/PT-Helper/docs/audit-assets-2026-07-17/progress-light.png` and `progress-dark.png` — the ONLY diff should be the new section at the top of the scroll content (both appearances).

**Depends on / Blocks** — Depends on WS6-02 (land the sign-out clear in the same PR or earlier: this card is what turns the stale PHI file into a visible cross-account disclosure). Blocks nothing. Order-independent of the D-1 deletion workstream (card code is embedded above, not imported from AssessTab).

---

### [WS6-02] Clear AnalysisResultStore on sign-out (cross-account PHI guard)
`P1` · `effort: S` · `risk: LOW — one line in an existing cleanup branch + one new unit test; account-deletion path already calls the same method`

**Problem** — `AnalysisResultStore`'s backing file (condition differentials, pain assessments, full `UserProfile` snapshot — PHI) survives sign-out: the auth listener's signed-out branch clears the profile cache, consent mirrors, and onboarding draft, but not this store. Today that is latent (no live reader); the moment WS6-01 ships, user B signing in on user A's device sees user A's diagnosis on the Progress tab. Account deletion already clears it — sign-out must match.

**Evidence**
- `ios/PT-Helper/PT-Helper/RootView.swift:60-85` — `addStateDidChangeListener`; signed-out branch (:72-84) clears `OnboardingViewModel.clearDraft()` (:77), `profileService.clear()` (:83), `ConsentService.clearLocalMirrors()` (:84) — no `AnalysisResultStore` call. This listener is the single choke point every sign-out flows through.
- `ios/PT-Helper/PT-Helper/Views/SettingsView.swift:434-440` — user-facing Sign Out calls only `Auth.auth().signOut()`; no local-data clear of its own (relies on the listener).
- `ios/PT-Helper/PT-Helper/Views/SettingsView.swift:558-570` — `clearAllLocalUserData()` (account-deletion path) DOES call `AnalysisResultStore.shared.clear()` (:562), proving the asymmetry.
- `ios/PT-Helper/PT-Helper/Views/LegalAcceptanceGateView.swift:81` and `RootView.swift:101` — two more `signOut()` paths (ToS decline, virtual-user re-sign-in) that the listener also covers; per-call-site fixes would miss these.
- `ios/PT-Helper/PT-Helper/Services/AnalysisResultStore.swift:53-57` — `clear()` nils `lastResult` and removes the file; `@MainActor`, same isolation as `profileService.clear()` already called directly from this closure (compiles identically).
- `ios/PT-Helper/PT-HelperTests/Services/AnalysisResultStoreTests.swift:30-38` — existing `testClear_removesStoredResult` asserts only the in-memory nil + legacy UserDefaults key; nothing proves the FILE is gone, which is the cross-account invariant.

**Change spec**

1. `RootView.swift` — in the signed-out branch of the auth listener, immediately after line 83 (`profileService.clear()`), add:
   ```swift
   // PHI: the last-analysis file must not survive into another account's
   // session — the Progress tab's "Your Last Analysis" card reads it (WS6-01).
   AnalysisResultStore.shared.clear()
   ```
   Fork closed: the listener, not the three `signOut()` call sites, is the fix location — it is the one path all sign-outs (Settings, ToS-decline gate, vuser token swap, server-side token revocation) funnel through, and it already owns the analogous `profileService`/consent clears. The account-deletion path becomes harmlessly redundant (clear() is idempotent); do not remove `SettingsView.swift:562`.
2. `ios/PT-Helper/PT-HelperTests/Services/AnalysisResultStoreTests.swift` — add one test to the existing class (self-contained: ends with the store cleared, so it cannot pollute the shared backing file for sibling tests):
   ```swift
   func testClear_thenFreshStore_loadsNil() {
       let store = AnalysisResultStore()
       store.save(TestFixtures.makeAnalysisResult())
       store.clear()

       let freshStore = AnalysisResultStore()
       XCTAssertNil(freshStore.lastResult,
           "clear() must remove the backing file so a new account's store starts empty")
   }
   ```

**Do NOT** — do not refactor `clearAllLocalUserData()`, do not rewrite the existing tests' stale legacy-UserDefaults-key assertions (noted below as skipped P3), and do not touch the vuser sign-in flow in `RootView.swift:95-109`.

**Files to touch**
- `ios/PT-Helper/PT-Helper/RootView.swift`
- `ios/PT-Helper/PT-HelperTests/Services/AnalysisResultStoreTests.swift`
Anything else = STOP and mark BLOCKED.

**Acceptance criteria**
- [ ] `grep -c "AnalysisResultStore.shared.clear()" ios/PT-Helper/PT-Helper/RootView.swift` returns `1`.
- [ ] `grep -c "testClear_thenFreshStore_loadsNil" ios/PT-Helper/PT-HelperTests/Services/AnalysisResultStoreTests.swift` returns `1`.
- [ ] Single-class run passes: `-only-testing:PT-HelperTests/AnalysisResultStoreTests` (command below).
- [ ] Build + UnitPlan + SmokePlan pass (commands below).
- [ ] Manual (post-WS6-01, simulator): seed data → confirm card on Progress tab → Settings → Sign Out → sign in again → Progress tab shows NO "Your Last Analysis" section.

**Verify**
```bash
xcodebuild test -project ios/PT-Helper/PT-Helper.xcodeproj \
  -scheme PT-Helper -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:PT-HelperTests/AnalysisResultStoreTests

xcodebuild build -project ios/PT-Helper/PT-Helper.xcodeproj \
  -scheme PT-Helper -destination 'platform=iOS Simulator,name=iPhone 16'

xcodebuild test -project ios/PT-Helper/PT-Helper.xcodeproj \
  -scheme PT-Helper -destination 'platform=iOS Simulator,name=iPhone 16'

xcodebuild test -project ios/PT-Helper/PT-Helper.xcodeproj \
  -scheme PT-Helper -testPlan SmokePlan -destination 'platform=iOS Simulator,name=iPhone 16'
```
(Same `name=iPhone 16` destination quirk note as WS6-01. No functions changes — no npm step.)

**Depends on / Blocks** — Depends on nothing. Blocks WS6-01 (must ship with or before it).

---

**Skipped (P3, low value):**
- Harden `AnalysisResultStoreTests` legacy assumptions: `testKey` UserDefaults assertions (:6,25,37,53) predate the file-backed migration and test isolation currently rides on alphabetical execution order; works today, pure hygiene — not worth a spec item.
- SmokePlan membership for the new test: SmokePlan is a hand-picked 11-test list (`SmokePlan.xctestplan` `selectedTests`); the new test lands in UnitPlan automatically and adding it to the smoke list is a judgment call for the release owner, not an execution item.

## WS7: Contrast + accessibility

**Scope (3 lines):** Fix light-mode WCAG text-contrast failures caused by `AppColors.accent` (#0FB5B0, 2.54:1 on white) used as a text color, via a new adaptive `accentText` token and a mechanical 35-site sweep; fix the two inverse failures (white-on-accent chip/badge fills, and the 1.61:1 Progress chart axis labels). Add the two missing VoiceOver affordances: a spoken summary on the one live unlabeled chart (ReAssessmentComparisonView) and `accessibilityLabel`s on 9 icon-only buttons. Size M, risk LOW (color token swaps + additive labels). Test plan: SmokePlan + visual compare against `/Users/noyfisher/IOS-Projects/PT-Helper-Agent-v1/ios/PT-Helper/docs/audit-assets-2026-07-17/`.

**Shared context (read once, applies to every item).** All paths below are relative to `/Users/noyfisher/IOS-Projects/PT-Helper-Agent-v1/ios/PT-Helper/PT-Helper/` unless absolute. Token facts, verified at 5fd0abb in `DesignSystem.swift`: `CoilPalette.accent = dyn(#0FB5B0, #2CC7C2)` (line 32) — light variant is 2.54:1 on white, FAILS AA 4.5:1 for text; `CoilPalette.accentDeep = dyn(#0B7A78, #17A6A2)` (line 33, comment says "CTA / text on white") — 5.16:1 on white, 5.7:1 as text on dark cards, PASSES both modes; `CoilPalette.accentDeeper = dyn(#075E5C, #0B7A78)` (line 35) — 7.60:1 on white and 5.17:1 with white text on its dark variant, PASSES both modes as a FILL under white text. `AppColors.ctaBackground = Color(CoilPalette.accentDeep)` (line 98) has exactly 9 uses, all backgrounds/shadows; `AppColors.accentDark = Color(CoilPalette.accentDeeper)` (line 103) has ZERO uses; `AppColors.accentText` does not exist yet (grep confirms 0 hits) — WS7-01 creates it. Fixed-dark surfaces where plain `accent` already passes (~6.6:1) and must NOT be swapped: LoginView (dark hero), IntroCarouselView (dark hero, WS4 reskins it per D-4), everything inside OnboardingView (forces `.preferredColorScheme(.dark)` at `Views/OnboardingView.swift:142`), and the FloatingTabBar (background `AppColors.navBackground` = fixed ink, `Views/ThreeTabView.swift:281`). Dead files that WS1 deletes (D-1) are excluded from every item here: `Views/AssessTab.swift`, `Views/PlansTab.swift`, `Views/MainTabView.swift`, `Views/ProgressChartView.swift`, plus two orphans found during verification — `Views/QuickHealthUpdateView.swift` (only callers are AssessTab:168 and MainTabView:191, both dead) and `Views/TimerView.swift` (zero callers outside its own preview at :160). Audit ratios are pixel-sampled ±0.2. Build/test commands: memory (assumed, re-verified as memory only) says `name=iPhone 16` destination can fail OS resolution — if the verbatim CLAUDE.md command errors with "unable to find destination", append `,OS=18.2` to the destination string.

---

### [WS7-01] Sweep accent-as-text to a new adaptive `accentText` token (35 sites)
`P1` · `effort: M` · `risk: mechanical token swap; only regression vector is swapping a fixed-dark-surface site, which the exclusion list fences off`

**Problem** — Teal `AppColors.accent` is used as the foreground color of user-facing text at 34 live call sites plus the rest-timer digit color; in light mode that renders #0FB5B0 on white/near-white at 2.54:1, failing WCAG AA (4.5:1). The audit measured real screens: "GET STARTED" 2.54:1, rest countdown digits 2.32:1, "Set 1/3" chip 2.13:1. Users in bright light or with low vision cannot read primary CTAs and status text.

**Evidence**
- `DesignSystem.swift:32` — `accent = dyn(hex(0x0FB5B0), hex(0x2CC7C2))`; light variant computes to 2.54:1 on white.
- `DesignSystem.swift:33` — `accentDeep = dyn(hex(0x0B7A78), hex(0x17A6A2)) // CTA / text on white` — the palette already contains the correct text-safe pair (5.16:1 light, 5.7:1 dark-on-dark-cards); no `AppColors` text alias for it exists.
- 86 live `foregroundColor/foregroundStyle(AppColors.accent)` sites total; the 34 text-bearing in-scope ones are enumerated in the table below (each line verified to contain `AppColors.accent` at 5fd0abb).
- `Views/GuidedWorkoutView.swift:493` — `case 0.66...: return AppColors.accent` inside `timerColor`; feeds the 52pt rest digits at :404 (audit: 2.32:1, `workoutrest-light.png`).
- Audit baselines: `docs/audit-assets-2026-07-17/gateway-light.png`, `workoutrest-light.png`, `workout-light.png`, `home-light.png`.

**Change spec**
1. In `DesignSystem.swift`, insert after line 104 (`static let accentTint …`), inside the `// MARK: Accent variants` block:
   `static let accentText = Color(CoilPalette.accentDeep)  // AA text: 5.16:1 on white, 5.7:1 on dark cards`
   Rationale for a new alias instead of reusing `ctaBackground` (same underlying value): `ctaBackground`'s 9 existing uses are all fills; a text site reading `foregroundColor(AppColors.ctaBackground)` is a maintenance trap. `accentDark` is NOT used because its dark variant (#0B7A78) is only ~3.4:1 as text on dark cards — it would break dark mode.
2. At every line in the table below, replace the token `AppColors.accent` with `AppColors.accentText` (the modifier — `foregroundColor` vs `foregroundStyle` — stays as-is). No other edits on those lines.
3. In `Views/GuidedWorkoutView.swift:493`, change `return AppColors.accent` to `return AppColors.accentText` (the `timerColor` accent phase; `warning`/`danger` phases at :494-495 are out of scope).

**Sweep table** (file → lines to swap → `AppColors.accentText` count after → residual `(foregroundColor|foregroundStyle)(AppColors.accent` count after (icon-only tints, deliberately untouched)):

| File | Swap lines | accentText after | residual accent-fg after |
|---|---|---|---|
| Views/AnalysisResultView.swift | 296, 308, 313, 329 | 4 | 1 (:118) |
| Views/AssessmentGatewayView.swift | 127 | 1 | 2 (:103, :131) |
| Views/BodyMap3DView.swift | 203, 463 | 2 | 1 (:246) |
| Views/Components/ExpandableSummaryView.swift | 55 | 1 | 0 |
| Views/Components/RegionPainInputView.swift | 40 | 1 | 2 (:24, :137) |
| Views/Components/SeriousWarningModal.swift | 92 | 1 | 0 |
| Views/EditRehabPlanView.swift | 56 | 1 | 1 (:40) |
| Views/ExerciseSwapSheet.swift | 229, 343 | 2 | 1 (:86) |
| Views/FormAnalysisView.swift | 149, 378 | 2 | 5 (:67, :144, :605, :615, :632) |
| Views/GuidedWorkoutView.swift | 199, 543, 579 (+ :493 via step 3) | 4 | 2 (:590, :614) |
| Views/HealthDataConsentView.swift | 55 | 1 | 0 |
| Views/HomeTab.swift | 104 | 1 | 0 |
| Views/LegalAcceptanceGateView.swift | 131, 134 | 2 | 0 |
| Views/PainWizardSteps.swift | 414 | 1 | 0 |
| Views/ProgressTab.swift | 245, 619 | 2 | 3 (:172, :453, :594) |
| Views/RecoveryInsightsCardView.swift | 119 | 1 | 1 (:122) |
| Views/RecoveryInsightsDetailView.swift | 256 | 1 | 1 (:219) |
| Views/RehabPlanView.swift | 110, 513, 678 | 3 | 2 (:643, :883) |
| Views/WellnessDetailView.swift | 370 | 1 | 3 (:277, :322, :367) |
| Views/WellnessGoalPickerView.swift | 163 | 1 | 1 (:160) |
| Views/WellnessPlanView.swift | 161 | 1 | 0 |
| Views/WellnessResultView.swift | 173 | 1 | 2 (:85, :210) |

**Explicit exclusion list** (accent-as-foreground sites that stay `AppColors.accent` — do not touch):
- Fixed-dark surfaces where accent passes (~6.6:1) and `accentText` would REGRESS to ~3.3:1: `LoginView.swift:56`; `Views/OnboardingSteps/BasicInfoStepView.swift:167,175`, `Views/OnboardingSteps/InjuryHistoryStepView.swift:43,146`, `Views/OnboardingSteps/MedicalHistoryStepView.swift:53` (all hosted in OnboardingView which forces `.dark` at `Views/OnboardingView.swift:142`); `Views/ThreeTabView.swift:303` ("Assess" caption on the fixed-ink FloatingTabBar).
- `Views/IntroCarouselView.swift:162,250,329,374` — dark hero; WS4 owns the IntroCarousel reskin (settled D-4).
- All 39 icon-only `Image` tints (the residual column above, plus `RootView.swift:140`, `Views/FormCheckTab.swift:69,87`, `Views/SettingsView.swift:67,135,197`, `Views/Components/OutcomePromptView.swift:36`, `Views/ReAssessmentPromptView.swift:14`, `Views/WellnessAnalyzingView.swift:73`, `Views/OnboardingSteps/InjuryHistoryStepView.swift:28`, `Views/OnboardingSteps/MedicalHistoryStepView.swift:107`, `Views/QuickHealthUpdateView.swift:166`) — decorative/adjacent-to-text glyphs; 2.54:1 vs the 3:1 non-text bar is marginal and a brand-wide icon darkening is not in scope.
- Chart marks `Views/ProgressTab.swift:453` (PointMark) and the LineMark/AreaMark gradients at :429-446 — graphical objects whose data is redundantly available via the chart's VoiceOver summary (:474-476) and the session list; keep brand teal.
- `DesignSystem.swift:401` (SecondaryButtonStyle text) and `:524` (EmptyStateView 48pt icon) — SecondaryButtonStyle has 18 call sites on MIXED light/dark surfaces (e.g. `Views/AnalyzingView.swift:311` dark, `Views/AnalysisResultView.swift:468` light); swapping the shared style regresses the dark-surface callers. The audit flagged no secondary-button failure. Leave until the dark-canvas inconsistency item (design-system WS) normalizes surfaces.
- Dead files (WS1 deletes): `Views/AssessTab.swift` (8 sites), `Views/PlansTab.swift` (2), `Views/ProgressChartView.swift` (1).

**Do NOT** — touch `warning`/`danger` timer phases, secondary-gray text tokens (`mutedText`/`secondaryText` shortfalls are a skipped P3), chart axis labels (WS7-02 owns), chip/badge FILLS (WS7-03 owns), or any file in the exclusion list.

**Files to touch** — `DesignSystem.swift` + exactly the 22 files in the sweep table. Anything else = STOP and mark BLOCKED.

**Acceptance criteria**
- [ ] `grep -c "static let accentText" /Users/noyfisher/IOS-Projects/PT-Helper-Agent-v1/ios/PT-Helper/PT-Helper/DesignSystem.swift` returns `1`.
- [ ] `cd /Users/noyfisher/IOS-Projects/PT-Helper-Agent-v1/ios/PT-Helper/PT-Helper && grep -rn "AppColors\.accentText" --include='*.swift' . | wc -l` returns `36` (1 definition + 34 fg swaps + 1 `timerColor` return).
- [ ] Per-file `grep -c "AppColors.accentText"` matches the "accentText after" column for all 22 files.
- [ ] Per-file `grep -cE "(foregroundColor|foregroundStyle)\(AppColors\.accent\b" <file>` matches the "residual" column for all 22 files.
- [ ] `grep -rn "AppColors.accentText" LoginView.swift Views/IntroCarouselView.swift Views/OnboardingSteps/ Views/ThreeTabView.swift` returns 0 lines (exclusions untouched).
- [ ] Visual compare: re-capture Assessment gateway, guided-workout rest screen, and Home in light mode; "GET STARTED", rest digits, and "Today" chip render dark teal (#0B7A78), versus baselines `gateway-light.png`, `workoutrest-light.png`, `home-light.png` in `/Users/noyfisher/IOS-Projects/PT-Helper-Agent-v1/ios/PT-Helper/docs/audit-assets-2026-07-17/`.
- [ ] SmokePlan passes.

**Verify**
```bash
cd /Users/noyfisher/IOS-Projects/PT-Helper-Agent-v1
xcodebuild build -project ios/PT-Helper/PT-Helper.xcodeproj \
  -scheme PT-Helper -destination 'platform=iOS Simulator,name=iPhone 16'
xcodebuild test -project ios/PT-Helper/PT-Helper.xcodeproj \
  -scheme PT-Helper -testPlan SmokePlan -destination 'platform=iOS Simulator,name=iPhone 16'
```
Then visual compare vs `/Users/noyfisher/IOS-Projects/PT-Helper-Agent-v1/ios/PT-Helper/docs/audit-assets-2026-07-17/{gateway-light,workoutrest-light,home-light}.png`.

**Depends on / Blocks** — Depends on nothing. Coordinate-only: WS4 (IntroCarousel excluded here), WS1 (dead files excluded here). Blocks nothing.

---

### [WS7-02] Fix Progress pain-trend chart axis labels (1.61:1 — worst contrast failure in the audit)
`P1` · `effort: S` · `risk: two-line style swap inside one chart; no data or layout change`

**Problem** — The pain-trend chart's date and y-scale labels render light teal (~#87DAD7) on the white card in light mode — 1.61:1, effectively invisible and the single worst measurement of the audit. Users cannot read what dates or pain levels the chart covers.

**Evidence**
- `Views/ProgressTab.swift:461-462` — `AxisValueLabel()` + `.foregroundStyle(.secondary)` (y-axis).
- `Views/ProgressTab.swift:467-468` — `AxisValueLabel(format: …)` + `.foregroundStyle(.secondary)` (x-axis). The hierarchical `.secondary` resolves against an accent-tinted inherited foreground style inside `Chart`, producing the measured pale teal rather than system gray.
- `DesignSystem.swift:50/75` — `secondaryText = dyn(#4B5A5E, #9DB2B3)`: 7.15:1 on white, passes both modes.
- Audit: `docs/audit-assets-2026-07-17/progress-light.png` ("hardest contrast failure found"); `progress-dark.png` (dark adapts correctly today — must stay correct).

**Change spec**
1. `Views/ProgressTab.swift:462`: replace `.foregroundStyle(.secondary)` with `.foregroundStyle(AppColors.secondaryText)`.
2. `Views/ProgressTab.swift:468`: replace `.foregroundStyle(.secondary)` with `.foregroundStyle(AppColors.secondaryText)`.
   Rationale: pin the axis labels to a concrete adaptive token instead of a hierarchical style whose resolution depends on the chart's inherited foreground; `secondaryText` is the app's standard secondary-text token and passes AA in both modes.

**Do NOT** — restyle the gridlines (`mutedText.opacity(0.3)` at :460 is decorative and fine), the chart marks (WS7-01 exclusion), or the chart's existing a11y modifiers at :474-476.

**Files to touch** — `Views/ProgressTab.swift` only. Anything else = STOP and mark BLOCKED.

**Acceptance criteria**
- [ ] `grep -c "foregroundStyle(.secondary)" /Users/noyfisher/IOS-Projects/PT-Helper-Agent-v1/ios/PT-Helper/PT-Helper/Views/ProgressTab.swift` returns `0`.
- [ ] `grep -c "AxisValueLabel" /Users/noyfisher/IOS-Projects/PT-Helper-Agent-v1/ios/PT-Helper/PT-Helper/Views/ProgressTab.swift` still returns `2` (no structural change).
- [ ] Visual compare: light-mode Progress tab re-capture shows gray (not teal) axis labels vs baseline `/Users/noyfisher/IOS-Projects/PT-Helper-Agent-v1/ios/PT-Helper/docs/audit-assets-2026-07-17/progress-light.png`; dark re-capture unchanged vs `progress-dark.png`.
- [ ] SmokePlan passes.

**Verify**
```bash
cd /Users/noyfisher/IOS-Projects/PT-Helper-Agent-v1
xcodebuild build -project ios/PT-Helper/PT-Helper.xcodeproj \
  -scheme PT-Helper -destination 'platform=iOS Simulator,name=iPhone 16'
xcodebuild test -project ios/PT-Helper/PT-Helper.xcodeproj \
  -scheme PT-Helper -testPlan SmokePlan -destination 'platform=iOS Simulator,name=iPhone 16'
```
Then visual compare vs `/Users/noyfisher/IOS-Projects/PT-Helper-Agent-v1/ios/PT-Helper/docs/audit-assets-2026-07-17/progress-light.png` and `progress-dark.png`.

**Depends on / Blocks** — nothing.

---

### [WS7-03] Darken chip/badge selected fills so white text passes AA (CoilBadge + ChipButton)
`P2` · `effort: S` · `risk: 3-line DesignSystem change; visually darkens every selected chip and the Active badge in both modes (intended)`

**Problem** — The inverse of WS7-01: white 12-13pt text sits ON an `accent` fill in two shared components — `CoilBadge` ("Active Plan" on Home, "Active" on My Plan) and `ChipButton`'s selected state (20 live call sites: every selected tag in pain/wellness/onboarding forms). White on #0FB5B0 is ~2.5:1 in light mode and ~2.1:1 on the dark variant #2CC7C2 — it fails AA in BOTH modes today.

**Evidence**
- `DesignSystem.swift:107-109` — `chipSelectedBg = Color(CoilPalette.accent)`, `chipSelectedBorder = Color(CoilPalette.accent)`, `chipSelectedText = Color.white`.
- `DesignSystem.swift:718-724` — ChipButton renders `AppColors.ctaText` (white) on `chipSelectedBg`; 20 call sites (`grep -rn "ChipButton(" Views/ | wc -l` = 20).
- `DesignSystem.swift:454-461` — CoilBadge: white `ctaText` on `.background(AppColors.accent)` (line 461). Live callers: `Views/HomeTab.swift:256`, `Views/MyPlanTab.swift:160` (AssessTab:205 is dead).
- Contrast math: white on `accentDeeper` dyn(#075E5C, #0B7A78) = 7.55:1 light / 5.17:1 dark — the only palette pair passing 4.5:1 with white text in BOTH modes (accentDeep's dark variant #17A6A2 is only ~3.0:1).
- Audit: `docs/audit-assets-2026-07-17/home-light.png` ("ACTIVE PLAN chip white-on-teal 2.54:1").

**Change spec**
1. `DesignSystem.swift:107`: change `chipSelectedBg     = Color(CoilPalette.accent)` to `chipSelectedBg     = Color(CoilPalette.accentDeeper)`.
2. `DesignSystem.swift:108`: change `chipSelectedBorder = Color(CoilPalette.accent)` to `chipSelectedBorder = Color(CoilPalette.accentDeeper)` (border must match the new fill or selected chips get a mismatched halo).
3. `DesignSystem.swift:461`: in CoilBadge, change `.background(AppColors.accent)` to `.background(AppColors.accentDark)` (`accentDark` is the existing `AppColors` alias of `CoilPalette.accentDeeper`, currently unused — this is its intended first use).
   Rationale: single-point fix in the shared components covers all 22 render sites; `accentDeeper` is chosen over `accentDeep` because only it passes with white text in dark mode.

**Do NOT** — touch `PrimaryButtonStyle`/`ctaBackground` (already 5.16:1 light; its dark-mode 15pt-bold white-on-#17A6A2 is large-text 3:1 borderline and out of scope), the dead `QuickHealthUpdateView` hand-rolled chips (:180-186 — file is orphaned, WS1's problem), or ChipButton's unselected state.

**Files to touch** — `DesignSystem.swift` only. Anything else = STOP and mark BLOCKED.

**Acceptance criteria**
- [ ] `grep -n "CoilPalette.accentDeeper" /Users/noyfisher/IOS-Projects/PT-Helper-Agent-v1/ios/PT-Helper/PT-Helper/DesignSystem.swift` shows hits on lines defining `accentDark`, `chipSelectedBg`, `chipSelectedBorder` (3 total besides the palette definition).
- [ ] `grep -c "background(AppColors.accentDark)" /Users/noyfisher/IOS-Projects/PT-Helper-Agent-v1/ios/PT-Helper/PT-Helper/DesignSystem.swift` returns `1` (CoilBadge).
- [ ] Visual compare: light-mode Home re-capture shows the "ACTIVE PLAN" badge on a dark-teal fill vs baseline `/Users/noyfisher/IOS-Projects/PT-Helper-Agent-v1/ios/PT-Helper/docs/audit-assets-2026-07-17/home-light.png`; a selected chip screen (e.g. pain wizard factors or wellness goal picker) shows dark-teal selected fills.
- [ ] SmokePlan passes (chip selection semantics unchanged — `accessibilityAddTraits(.isSelected)` at DesignSystem.swift:733 untouched).

**Verify**
```bash
cd /Users/noyfisher/IOS-Projects/PT-Helper-Agent-v1
xcodebuild build -project ios/PT-Helper/PT-Helper.xcodeproj \
  -scheme PT-Helper -destination 'platform=iOS Simulator,name=iPhone 16'
xcodebuild test -project ios/PT-Helper/PT-Helper.xcodeproj \
  -scheme PT-Helper -testPlan SmokePlan -destination 'platform=iOS Simulator,name=iPhone 16'
```
Then visual compare vs `/Users/noyfisher/IOS-Projects/PT-Helper-Agent-v1/ios/PT-Helper/docs/audit-assets-2026-07-17/home-light.png` and `wellnesspicker-light.png`.

**Depends on / Blocks** — nothing (independent of WS7-01; different sites).

---

### [WS7-04] Add accessibilityLabels to 9 icon-only buttons
`P2` · `effort: S` · `risk: purely additive modifiers; UI tests key off accessibilityIdentifier, which is untouched`

**Problem** — Nine live icon-only buttons expose no `accessibilityLabel`, so VoiceOver reads either nothing useful or a generic SF Symbol name ("Circle", "Xmark") — a blind user cannot pause a workout, edit a plan, or remove a selected body region. `accessibilityIdentifier` (present on several) is a test hook and is NOT read by VoiceOver.

**Evidence** (each verified icon-only, label-less at 5fd0abb)
- `Views/GuidedWorkoutView.swift:55-58` — pause/play toolbar Button (`vm.togglePause()`), identifier only.
- `Views/RehabPlanView.swift:191-194` — `pencil.circle` edit-plan toolbar Button, identifier only.
- `Views/WellnessDetailView.swift:275` and `:320` — `plus.circle.fill` add-custom-activity / add-custom-habit Buttons.
- `Views/ProgressTab.swift:170-174` — `gearshape.fill` settings Button, identifier only.
- `Views/NotesView.swift:124-132` — `trash` delete-note Button.
- `Views/BodyMap3DView.swift:288-297` — `xmark.circle.fill` deselect-region Button inside the selected-regions chip row (`region.name` in scope at :285).
- `Views/EditRehabPlanView.swift:38-42` — `pencil.circle` edit-exercise Button (`exercise` in scope from ForEach at :26, `exercise.name` used at :29).
- `Views/Components/RegionPainInputView.swift:78-82` — `xmark.circle.fill` remove-region Button (`Self.displayName(for:)` static exists at :157).
- Copy-from examples already in the codebase: `Views/ProgressTab.swift:318` (`"Delete session"`), `Views/ThreeTabView.swift:331`.

**Change spec** — add exactly these modifiers (labels are final copy, do not reword):
1. `Views/GuidedWorkoutView.swift` — after line 58 (`.accessibilityIdentifier("workout.pauseButton")`): `.accessibilityLabel(vm.isPaused ? "Resume workout" : "Pause workout")`.
2. `Views/RehabPlanView.swift` — after line 194 (`.accessibilityIdentifier("rehabPlan.editButton")`): `.accessibilityLabel("Edit plan")`.
3. `Views/WellnessDetailView.swift` — after the `.disabled(…)` at line 279: `.accessibilityLabel("Add custom activity")`.
4. `Views/WellnessDetailView.swift` — after the `.disabled(…)` at line 324: `.accessibilityLabel("Add custom habit")`.
5. `Views/ProgressTab.swift` — after line 174 (`.accessibilityIdentifier("progress.settingsButton")`): `.accessibilityLabel("Settings")`.
6. `Views/NotesView.swift` — after line 132 (`.buttonStyle(.plain)`): `.accessibilityLabel("Delete note")`.
7. `Views/BodyMap3DView.swift` — after line 297 (closing `}` of the xmark Button): `.accessibilityLabel("Deselect \(region.name)")`.
8. `Views/EditRehabPlanView.swift` — after line 42 (`.buttonStyle(.plain)`): `.accessibilityLabel("Edit \(exercise.name)")`.
9. `Views/Components/RegionPainInputView.swift` — after line 82 (closing `}` of the xmark Button): `.accessibilityLabel("Remove \(Self.displayName(for: region))")`.

**Do NOT** — add labels to the dead `Views/TimerView.swift` (:43/:74/:142) or `Views/QuickHealthUpdateView.swift` (:163/:180/:215/:299) — both files are unreachable (zero live callers) and WS1 owns their fate; do not relabel the RehabPlanView ShareLink at :182-188 (SF Symbol supplies "Share"); do not change any `accessibilityIdentifier`.

**Files to touch** — `Views/GuidedWorkoutView.swift`, `Views/RehabPlanView.swift`, `Views/WellnessDetailView.swift`, `Views/ProgressTab.swift`, `Views/NotesView.swift`, `Views/BodyMap3DView.swift`, `Views/EditRehabPlanView.swift`, `Views/Components/RegionPainInputView.swift`. Anything else = STOP and mark BLOCKED.

**Acceptance criteria**
- [ ] `cd /Users/noyfisher/IOS-Projects/PT-Helper-Agent-v1/ios/PT-Helper/PT-Helper && grep -rn 'accessibilityLabel("Pause workout")\|accessibilityLabel(vm.isPaused' Views/GuidedWorkoutView.swift | wc -l` returns `1`.
- [ ] Each of the 9 label strings above greps to exactly 1 hit in its named file (`"Edit plan"`, `"Add custom activity"`, `"Add custom habit"`, `"Settings"`, `"Delete note"`, `"Deselect \(`, `"Edit \(exercise.name)"`, `"Remove \(`).
- [ ] `grep -rn "accessibilityLabel" Views/TimerView.swift Views/QuickHealthUpdateView.swift | wc -l` returns `0` (dead files untouched).
- [ ] SmokePlan passes and the UI-test identifier greps are unchanged: `grep -c 'accessibilityIdentifier("workout.pauseButton")' Views/GuidedWorkoutView.swift` returns `1`.

**Verify**
```bash
cd /Users/noyfisher/IOS-Projects/PT-Helper-Agent-v1
xcodebuild build -project ios/PT-Helper/PT-Helper.xcodeproj \
  -scheme PT-Helper -destination 'platform=iOS Simulator,name=iPhone 16'
xcodebuild test -project ios/PT-Helper/PT-Helper.xcodeproj \
  -scheme PT-Helper -testPlan SmokePlan -destination 'platform=iOS Simulator,name=iPhone 16'
```
No visual change expected — no visual compare needed.

**Depends on / Blocks** — Depends on nothing. Informs WS1: TimerView.swift and QuickHealthUpdateView.swift verified orphaned during this item's discovery (zero live callers) — WS1 should confirm-and-delete.

---

### [WS7-05] Add a VoiceOver summary to the ReAssessment comparison chart
`P2` · `effort: S` · `risk: additive a11y modifiers + one private computed property on one view`

**Problem** — The before/after pain-comparison bar chart is the ONLY live chart with zero accessibility: VoiceOver users get nothing from the grouped red/green bars. (ProgressTab's pain-trend chart is already correctly labeled at :474-476; ProgressChartView is legacy-only and reclassified to WS1's deletion list.)

**Evidence**
- `Views/ReAssessmentComparisonView.swift:55-77` — `Chart` with grouped `BarMark`s (Before = `AppColors.danger.opacity(0.7)`, After = `AppColors.success.opacity(0.7)` per `.chartForegroundStyleScale` at :76); no accessibility modifiers anywhere in the file.
- `Views/ReAssessmentComparisonView.swift:6-7` — `let initial: AssessmentSnapshot`, `let latest: AssessmentSnapshot`; `Models/AssessmentSnapshot.swift:9` — `regionPainLevels: [String: Double]`.
- `Views/ReAssessmentComparisonView.swift:154-157` — `allRegions: [String]` (sorted union of region keys).
- `Views/ProgressTab.swift:324-333` — `painTrendAccessibilityValue`: the in-codebase template this mirrors.
- Live caller: `Views/RehabPlanView.swift:101`.

**Change spec**
1. In `Views/ReAssessmentComparisonView.swift`, after line 77 (`.frame(height: 220)`), add exactly:
   ```swift
   .accessibilityElement(children: .ignore)
   .accessibilityLabel("Pain comparison chart")
   .accessibilityValue(comparisonChartAccessibilityValue)
   ```
   Chosen approach: full spoken summary (NOT `accessibilityHidden`) — the workstream mandate is VoiceOver summaries for live charts; the text rows at `regionComparisonRow` remain as redundant visual/AT access.
2. Add this private computed property alongside `allRegions` (insert after line 158, the closing brace of `allRegions`):
   ```swift
   private var comparisonChartAccessibilityValue: String {
       guard !allRegions.isEmpty else { return "No region data to compare." }
       return allRegions.map { region -> String in
           let before = Int(initial.regionPainLevels[region] ?? 0)
           let after = Int(latest.regionPainLevels[region] ?? 0)
           let delta = before - after
           let change = delta > 0 ? "improved by \(delta)"
                      : (delta < 0 ? "worse by \(-delta)" : "unchanged")
           return "\(RegionPainInputView.displayName(for: region)): before \(before), after \(after) out of 10, \(change)."
       }.joined(separator: " ")
   }
   ```
   Exact rendered example (final copy): `"Left Knee: before 6, after 3 out of 10, improved by 3. Lower Back: before 4, after 4 out of 10, unchanged."` — region names via `RegionPainInputView.displayName(for:)` (static, exists at `Views/Components/RegionPainInputView.swift:157`), values match the chart's own `beforeVal`/`afterVal` sources (`initial`/`latest.regionPainLevels[region] ?? 0`).

**Do NOT** — restyle the chart's colors or axes, touch the `regionComparisonRow` text rows (:123+), add a11y to ProgressChartView (legacy, WS1 deletes), or re-label ProgressTab's already-labeled chart.

**Files to touch** — `Views/ReAssessmentComparisonView.swift` only. Anything else = STOP and mark BLOCKED.

**Acceptance criteria**
- [ ] `grep -c 'accessibilityLabel("Pain comparison chart")' /Users/noyfisher/IOS-Projects/PT-Helper-Agent-v1/ios/PT-Helper/PT-Helper/Views/ReAssessmentComparisonView.swift` returns `1`.
- [ ] `grep -c "comparisonChartAccessibilityValue" /Users/noyfisher/IOS-Projects/PT-Helper-Agent-v1/ios/PT-Helper/PT-Helper/Views/ReAssessmentComparisonView.swift` returns `2` (declaration + use).
- [ ] `grep -c "accessibilityElement(children: .ignore)" /Users/noyfisher/IOS-Projects/PT-Helper-Agent-v1/ios/PT-Helper/PT-Helper/Views/ReAssessmentComparisonView.swift` returns `1`.
- [ ] SmokePlan passes; no visual change (a11y modifiers only).

**Verify**
```bash
cd /Users/noyfisher/IOS-Projects/PT-Helper-Agent-v1
xcodebuild build -project ios/PT-Helper/PT-Helper.xcodeproj \
  -scheme PT-Helper -destination 'platform=iOS Simulator,name=iPhone 16'
xcodebuild test -project ios/PT-Helper/PT-Helper.xcodeproj \
  -scheme PT-Helper -testPlan SmokePlan -destination 'platform=iOS Simulator,name=iPhone 16'
```
No visual change expected — no visual compare needed.

**Depends on / Blocks** — nothing.

---

**Skipped (P3, low value):**
- "Beginner" green-on-pale-green difficulty chip 3.91:1 (plandetail-light.png) — marginal miss that requires a design-system-wide success-on-tint token decision, not a swap; bundle with the dark-canvas normalization item in the design-system WS.
- Secondary-gray small-text shortfalls 3.28:1/3.59:1 (home/plan cards) — a global `mutedText` retune touches every screen; visual-regression-heavy for a marginal gain.
- 39 icon-only accent tints + `EmptyStateView` 48pt icon (DesignSystem.swift:524) at 2.54:1 vs the 3:1 non-text bar — decorative/adjacent-to-text; excluded by WS7-01's closed decision.
- White "+" glyph on the accent FloatingTabBar circle (ThreeTabView.swift:295-297) — 24pt-bold brand mark on dark chrome; marginal and identity-bearing.
- "Image Diagnostics (DEBUG)" teal row 2.54:1 — `#if DEBUG`-gated, never ships.
- Onboarding placeholder invisibility (1.10:1) — real and severe, but the onboarding WS owns it per the audit's `suggestedWs`; fenced out of WS7-01's exclusion list on dark-surface grounds anyway.

## WS8: Offline fail-fast + API resilience

Scope: (1) copy the proven offline fail-fast guard into every AI-calling ViewModel that lacks it, with per-flow friendly copy; (2) collapse the 3x-duplicated request boilerplate in `ClaudeAPIService` into one shared private helper (which also fixes a telemetry blind spot on the agent endpoints); (3) add the pre-decided retry policy (1 retry, 2s delay, transport/5xx only, never 429) inside that helper. Size M, risk MEDIUM (touches all AI entry points), required test plan: UnitPlan.

**Shared context (read once, applies to all items).** All AI traffic flows through `ios/PT-Helper/PT-Helper/Services/ClaudeAPIService.swift` (568 lines @ 5fd0abb), which exposes exactly 3 methods via `ClaudeAPIServiceProtocol` (`:101-105`): `sendMessage(requestType:userMessage:)` (`:160-323`, 90s timeout), `requestAgentInsights()` (`:328-432`, 180s), `requestAgentFormAnalysis(exerciseName:userMessage:)` (`:438-549`, 180s). Each makes a single `URLSession.shared.data(for:)` call (`:217`, `:370`, `:487`) with zero retry anywhere; 429 throws `ClaudeAPIError.rateLimited` immediately (`:270`, `:396`, `:513`). Exactly 7 ViewModels call the service (grep `apiService\|sendMessage\|requestAgent` over `ViewModels/`): InjuryAnalysis, RehabPlan, WellnessAnalysis, WellnessPlan, ExerciseSwap, RecoveryInsights, FormAnalysis. Only the first two have the offline guard (`InjuryAnalysisViewModel.swift:131-138`, `RehabPlanViewModel.swift:145-151`). **Fact correction carried into WS8-01:** the audit's "6 missing VMs" list included `ReAssessmentViewModel` — verified at 5fd0abb it makes **zero** AI calls (Firestore-only: `saveAssessment`/`loadAssessments`, `ReAssessmentViewModel.swift:40-98`); Firestore's SDK queues writes offline and serves reads from cache, and `ThreeTabView.swift:24` already shows the "changes will sync" banner, so it gets **no guard** — the real missing set is 5 VMs. `NetworkMonitor` (`Services/NetworkMonitor.swift:8-16`) is a `@MainActor` singleton with `@Published var isConnected: Bool = true` — unit tests may set it directly. `MockClaudeAPIService` (`PT-HelperTests/Mocks/MockClaudeAPIService.swift:10`) already counts calls to all 3 protocol methods. Known simulator quirk (assumed from memory, re-verify if hit): if `-destination 'platform=iOS Simulator,name=iPhone 16'` errors with "unable to find device", append `,OS=18.2`.

---

### [WS8-01] Add offline fail-fast guards to the 5 ungated AI ViewModels
`P1` · `effort: M` · `risk: behavior change — offline users now get an instant error instead of a 90–180s spinner (and, for wellness plans, instead of an eventual fallback plan)
**Problem** — Offline users in 5 of the 7 AI flows watch the full loading spinner until URLSession times out (90s proxy / 180s agent endpoints) before seeing a generic network error. The fix already exists and shipped in 2 ViewModels (audit #58); the other 5 were never covered, so the app's offline behavior is inconsistent flow-to-flow.
**Evidence** —
- `ViewModels/InjuryAnalysisViewModel.swift:131-138` — the canonical guard (template below), placed *after* the emergency pre-screen, *before* `isAnalyzing = true`.
- `ViewModels/RehabPlanViewModel.swift:145-151` — second shipped guard; note it deliberately fires *before* the fallback-plan `catch` (`:221`) — offline ⇒ error, not fallback. This precedent settles the same question for WellnessPlanViewModel.
- `grep -c 'NetworkMonitor\|isConnected'` returns 0 in all five: `ViewModels/WellnessAnalysisViewModel.swift`, `WellnessPlanViewModel.swift`, `ExerciseSwapViewModel.swift`, `RecoveryInsightsViewModel.swift`, `FormAnalysisViewModel.swift`.
- `Views/WellnessAnalyzingView.swift:116` — checks `isConnected` only *after* failure to word the error; not a gate. `Views/ThreeTabView.swift:24` — passive banner only.
- `ViewModels/ReAssessmentViewModel.swift:40-98` — Firestore-only, zero `apiService` references ⇒ excluded (closed decision, see shared context).
- Error surfaces already exist for every flow: `WellnessAnalyzingView.swift:137-140` (Try Again → `retryAnalysis()`), `ExerciseSwapSheet.swift:63-64`, `RecoveryInsightsCardView.swift` / `RecoveryInsightsDetailView.swift` render `vm.error`, `FormAnalysisView` renders `FormAnalysisState.error` (`Models/FormAnalysis.swift:314-321`).
**Change spec** —
Template (this is the shipped pattern from `InjuryAnalysisViewModel.swift:131-138`; adapt only property names + message):
```swift
// Fail fast when offline instead of making the user watch a doomed
// spinner before a generic network error (WS8-01, extends audit #58).
guard NetworkMonitor.shared.isConnected else {
    <errorProperty> = "<per-flow copy>"
    <loading teardown>
    return
}
```
1. **WellnessAnalysisViewModel** — insert into `startAnalysis()` immediately after the closing brace of the emergency pre-screen block `if !emergencyAlerts.isEmpty { … return }` (`:107-116`) and before `let goalNames` (`:117`). Ordering rationale: mirrors InjuryAnalysisViewModel — emergency detection must never be blocked by connectivity. Guard body: `analysisError = "You're offline. Connect to the internet to run your wellness assessment, then tap Try Again."`; `isAnalyzing = false`; `showAnalyzingScreen = true`; `return`. (`showAnalyzingScreen = true` is required so `WellnessAnalyzingView`'s errorView — which already branches to the wifi.slash icon at `:116` — is presented.)
2. **WellnessPlanViewModel** — insert into `generateWellnessPlan(from:)` immediately after `guard !isGenerating else { return }` (`:72`), before `let goalCategories` (`:73`). Guard body: `generationError = "You're offline. Connect to the internet to build your wellness plan, then try again."`; `isGenerating = false`; `return`. Intentional behavior change (settled by RehabPlanViewModel precedent): offline no longer waits 90s and serves the local `wellnessFallbackExercises` plan via the `catch` at `:137` — it fails fast instead.
3. **ExerciseSwapViewModel** — insert into `fetchSubstitutes()` immediately after `guard let reason = selectedReason else { return }` (`:107`), before `isLoading = true` (`:108`). Guard body: `error = "You're offline. Connect to the internet to find substitute exercises, then try again."`; `isLoading = false`; `return`. Do not set `noSafeSubstituteAvailable` (that flag means "AI answered but every candidate was contraindicated").
4. **RecoveryInsightsViewModel** — insert into `generateInsights(sessions:plans:profile:forceRegenerate:)` immediately after the closing brace of the minimum-session guard `guard recent.count >= Self.minimumSessionCount else { … }` (`:101-104`), before `isLoading = true` (`:106`). Guard body: `error = "You're offline. Connect to the internet to load your recovery insights, then try again."`; `isLoading = false`; `return`. (Cache guard at `:98` stays first — a valid cached insight still renders offline.)
5. **FormAnalysisViewModel** — insert into `analyzeVideo(url:exercise:)` immediately after `defer { try? FileManager.default.removeItem(at: url) }` (`:89`), before `state = .processing(progress: 0)` (`:91`). Guard body: `state = .error("You're offline. Connect to the internet to analyze your form, then try again.")`; `return`. Placement after the `defer` is intentional: the recorded video is still deleted (preserves the no-footage-accumulation invariant documented at `:86-88`); the user re-records after reconnecting. Rationale for guarding before pose detection even though it is on-device: the pipeline's only deliverable is AI feedback (step 6, `:239-267`), so 30–60s of doomed CPU work is worse than failing fast.
6. **Tests** — add exactly one offline test per VM to the five existing test files (all already construct the VM with `MockClaudeAPIService`; all test classes are `@MainActor` per convention). Shared pattern — the offline set and the entry call must have no `await` between them (the guard runs in the first suspension-free segment, so the NWPathMonitor task cannot interleave):
```swift
func test<Entry>_offline_failsFastWithoutAPICall() async {
    _ = NetworkMonitor.shared          // force singleton init
    await Task.yield()                 // drain the NWPathMonitor init update
    NetworkMonitor.shared.isConnected = false
    defer { NetworkMonitor.shared.isConnected = true }
    // arrange: reuse the file's existing fixtures/helpers
    // act: call the entry method
    // assert: exact error copy, loading flag false, mock call counts == 0
}
```
   - `WellnessAnalysisViewModelTests`: `testStartAnalysis_offline_failsFastWithoutAPICall` — save one assessment fixture then `saveAndAnalyze(_:)` (must pass the `completed.isEmpty` guard at `:95`); assert `analysisError` == copy, `isAnalyzing == false`, `showAnalyzingScreen == true`, `mockAPI.sendMessageCallCount == 0`.
   - `WellnessPlanViewModelTests`: `testGenerateWellnessPlan_offline_setsErrorWithoutFallbackPlan` — use `TestFixtures.makeWellnessAnalysisResult()`; assert `generationError` == copy, `isGenerating == false`, `wellnessPlan == nil` (proves the fallback catch did NOT run), count == 0.
   - `ExerciseSwapViewModelTests`: `testFetchSubstitutes_offline_setsErrorWithoutAPICall` — set `selectedReason` first; `await vm.fetchSubstitutes()`; assert `error` == copy, `isLoading == false`, `noSafeSubstituteAvailable == false`, count == 0.
   - `RecoveryInsightsViewModelTests`: `testGenerateInsights_offline_setsErrorWithoutAPICall` — pass `makeSessions(count: 3)` (meets `minimumSessionCount = 3`, `:51`) and `forceRegenerate: true`; assert `error` == copy, `isLoading == false`, `sendMessageCallCount == 0` AND `requestAgentInsightsCallCount == 0`.
   - `FormAnalysisViewModelTests`: `testAnalyzeVideo_offline_setsErrorState` — `await vm.analyzeVideo(url: URL(fileURLWithPath: "/nonexistent.mov"), exercise: <existing fixture>)` (guard fires before any file access, dummy URL is fine); assert `state == .error("You're offline. Connect to the internet to analyze your form, then try again.")` (FormAnalysisState.== compares error strings), both mock counts == 0.
**Do NOT** — touch `ClaudeAPIService.swift` (WS8-02/03 own it), any View file, `ThreeTabView`'s banner, `ReAssessmentViewModel`, or the two already-guarded VMs.
**Files to touch** —
- `ios/PT-Helper/PT-Helper/ViewModels/WellnessAnalysisViewModel.swift`
- `ios/PT-Helper/PT-Helper/ViewModels/WellnessPlanViewModel.swift`
- `ios/PT-Helper/PT-Helper/ViewModels/ExerciseSwapViewModel.swift`
- `ios/PT-Helper/PT-Helper/ViewModels/RecoveryInsightsViewModel.swift`
- `ios/PT-Helper/PT-Helper/ViewModels/FormAnalysisViewModel.swift`
- `ios/PT-Helper/PT-HelperTests/ViewModels/WellnessAnalysisViewModelTests.swift`
- `ios/PT-Helper/PT-HelperTests/ViewModels/WellnessPlanViewModelTests.swift`
- `ios/PT-Helper/PT-HelperTests/ViewModels/ExerciseSwapViewModelTests.swift`
- `ios/PT-Helper/PT-HelperTests/ViewModels/RecoveryInsightsViewModelTests.swift`
- `ios/PT-Helper/PT-HelperTests/ViewModels/FormAnalysisViewModelTests.swift`
Anything else = STOP and mark BLOCKED.
**Acceptance criteria** —
- [ ] `grep -rc "NetworkMonitor.shared.isConnected" ios/PT-Helper/PT-Helper/ViewModels/ | grep -v ':0'` lists exactly 7 files (the 5 above + InjuryAnalysis + RehabPlan), each count 1.
- [ ] `grep -c "NetworkMonitor" ios/PT-Helper/PT-Helper/ViewModels/ReAssessmentViewModel.swift` returns 0 (untouched).
- [ ] Each of the 5 copy strings above greps to exactly 1 hit in its VM file (exact-match, straight apostrophe in "You're" matching the existing two guards).
- [ ] The 5 new tests pass; all pre-existing tests in the 5 touched test files still pass (known pre-existing failure `RehabPlanViewModelTests/testGenerateRehabPlan_success_populatesPlan` is out of scope — fails on baseline).
- [ ] Manual: launch with `--uitesting --skip-onboarding --seed-mock-data --simulate-offline` and trigger each of the 5 flows — error copy appears instantly (< 1s), no spinner dwell.
**Verify** —
```bash
xcodebuild build -project ios/PT-Helper/PT-Helper.xcodeproj \
  -scheme PT-Helper -destination 'platform=iOS Simulator,name=iPhone 16'

xcodebuild test -project ios/PT-Helper/PT-Helper.xcodeproj \
  -scheme PT-Helper -destination 'platform=iOS Simulator,name=iPhone 16'

# Focused re-run of the touched classes:
xcodebuild test -project ios/PT-Helper/PT-Helper.xcodeproj \
  -scheme PT-Helper -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:PT-HelperTests/WellnessAnalysisViewModelTests \
  -only-testing:PT-HelperTests/WellnessPlanViewModelTests \
  -only-testing:PT-HelperTests/ExerciseSwapViewModelTests \
  -only-testing:PT-HelperTests/RecoveryInsightsViewModelTests \
  -only-testing:PT-HelperTests/FormAnalysisViewModelTests
```
Visual: compare error states against the offline reference shots in `ios/PT-Helper/docs/audit-assets-2026-07-17/` if present for these flows; otherwise screenshot the 5 error states as the new baseline.
**Depends on / Blocks** — depends on nothing; blocks nothing (independent of WS8-02/03).

---

### [WS8-02] Extract shared `performProxyRequest` helper in ClaudeAPIService
`P1` · `effort: M` · `risk: refactor of the single choke point for all AI traffic; mitigated by unchanged protocol + existing test suites
**Problem** — `sendMessage`, `requestAgentInsights`, and `requestAgentFormAnalysis` are ≥90% structural copies (~200 duplicated lines: auth token, request build, telemetry, status switch, decode, extract, clean). The copies have already diverged dangerously: 401/429 failures on the two agent endpoints emit **no** SessionLogger telemetry, so they are invisible in session logs. Every future fix (including WS8-03's retry) would otherwise need to land 3 times.
**Current-behavior map** (all refs `Services/ClaudeAPIService.swift` @ 5fd0abb):

| Behavior | `sendMessage` `:160-323` | `requestAgentInsights` `:328-432` | `requestAgentFormAnalysis` `:438-549` |
|---|---|---|---|
| URL | `APIConfig.claudeProxyURL` `:164` | `APIConfig.agentInsightsURL` `:332` | `APIConfig.agentFormAnalysisURL` `:442` |
| Telemetry endpoint name | `"claudeProxy"` | `"agentInsights"` | `"agentFormAnalysis"` |
| Telemetry requestType | `requestType.rawValue` | `"recovery_insights_agent"` | `"form_analysis_agent"` |
| Timeout | 90s `:183` | 180s `:349` | 180s `:464` |
| BG task name | `"claudeProxy-\(requestType.rawValue)"` `:161` | `"agentInsights"` `:329` | `"agentFormAnalysis"` `:439` |
| Body | `ClaudeProxyRequest` JSON `:190-198` | `"{}"` `:352` | `AgentFormAnalysisRequest` (method-local struct `:457-460`) `:467-469` |
| Transport-error telemetry | yes `:219-229` | yes `:372-382` | yes `:489-499` |
| 401/429/default telemetry | **yes** `:242-286` | **NO** — bare throws `:393-399` | **NO** — bare throws `:510-516` |
| Success telemetry extras | `statusCode`+`responseLength` `:309-319` | `responseLength` only `:419-429` | `responseLength` only `:536-546` |
| Decode-fail log message | "ClaudeResponse decode failed" `:296` | "AgentInsights decode failed" `:407` | "AgentFormAnalysis decode failed" `:524` |

**Invariants to preserve** — (a) `ClaudeAPIServiceProtocol` signatures `:101-105` unchanged (MockClaudeAPIService and all 7 VMs untouched); (b) per-endpoint timeout, BG-task name, telemetry endpoint/requestType strings, and body content exactly as in the table; (c) error mapping: URL→`invalidURL`, no user / token failure→`authenticationRequired`, transport→`networkError`, 401→`authenticationRequired`, 429→`rateLimited`, other→`invalidResponse(status, body)`, decode→`decodingError`, empty text→`noContent`; (d) `cleanJSONResponse` applied to the returned text; (e) `beginBackgroundTask`/`endBackgroundTask` bracket every call.
**Consolidation target** — one private config struct + one private helper; public methods become thin wrappers:
```swift
private struct ProxyCall {
    let urlString: String
    let endpointName: String        // SessionLogger endpoint
    let telemetryRequestType: String
    let timeout: TimeInterval
    let bgTaskName: String
}

private func performProxyRequest(_ call: ProxyCall, body: Data) async throws -> String
```
**Change spec** —
1. Add `ProxyCall` and `performProxyRequest(_:body:)` to `ClaudeAPIService` below `endBackgroundTask` (`:151-156`). Helper performs, in order: BG task begin + `defer` end; URL guard; auth (currentUser + `getIDToken()`); build `URLRequest` (POST, `call.timeout`, Bearer + Content-Type headers, `body`); `requestBytes`/`started`/`elapsedMsInt` setup; `.apiCallStarted` telemetry; `URLSession.shared.data(for:)` with the existing transport-error catch (telemetry + `networkError`); `HTTPURLResponse` cast; status switch; decode `ClaudeResponse`; extract first text block; `.apiCallSucceeded` telemetry; `return ClaudeAPIService.cleanJSONResponse(text)`.
2. Status switch in the helper uses `sendMessage`'s richer variant (`:238-288`) verbatim, parameterized: telemetry `endpoint: call.endpointName`, `requestType: call.telemetryRequestType`; default-case log becomes `AppLogger.api.error("\(call.endpointName) error (\(statusCode)): \(errorBody)")`. **Intentional additive changes** (record in commit message): agent endpoints gain 401/429/default failure telemetry (fixes the S32 blind spot); agent success telemetry gains `"statusCode": "200"`; decode-fail log message becomes `"\(call.endpointName) decode failed. Raw body (\(data.count) bytes): …"`.
3. Rewrite `sendMessage` as: BG-task-free wrapper (BG task now lives in the helper) that builds the `ClaudeProxyRequest` body via `JSONEncoder` (still `try`, outside any do/catch, as today `:197-198`) and returns `try await performProxyRequest(ProxyCall(urlString: APIConfig.claudeProxyURL, endpointName: "claudeProxy", telemetryRequestType: requestType.rawValue, timeout: 90, bgTaskName: "claudeProxy-\(requestType.rawValue)"), body: bodyData)`.
4. Rewrite `requestAgentInsights` likewise: body `"{}".data(using: .utf8)!`, `ProxyCall(urlString: APIConfig.agentInsightsURL, endpointName: "agentInsights", telemetryRequestType: "recovery_insights_agent", timeout: 180, bgTaskName: "agentInsights")`.
5. Rewrite `requestAgentFormAnalysis` likewise: keep the method-local `AgentFormAnalysisRequest` struct, encode it, `ProxyCall(urlString: APIConfig.agentFormAnalysisURL, endpointName: "agentFormAnalysis", telemetryRequestType: "form_analysis_agent", timeout: 180, bgTaskName: "agentFormAnalysis")`.
6. Delete the three now-dead duplicated bodies. `cleanJSONResponse` (`:552-567`), `makeTelemetryMetadata` (`:115-132`), `beginBackgroundTask`/`endBackgroundTask` stay as-is.
**Do NOT** — add any retry/backoff (WS8-03), change `ClaudeAPIServiceProtocol` or any ViewModel, introduce URLSession injection, or alter `APIConfig`.
**Files to touch** —
- `ios/PT-Helper/PT-Helper/Services/ClaudeAPIService.swift`
Anything else = STOP and mark BLOCKED.
**Acceptance criteria (prove-no-regression)** —
- [ ] `grep -c "URLSession.shared.data(for:" ios/PT-Helper/PT-Helper/Services/ClaudeAPIService.swift` returns 1.
- [ ] `grep -c "func elapsedMsInt" …/ClaudeAPIService.swift` returns 1; `grep -c "await beginBackgroundTask" …/ClaudeAPIService.swift` returns 1.
- [ ] `grep -c '"statusCode": "429"' …/ClaudeAPIService.swift` returns 1 (the shared switch — one place now serves all three endpoints, closing the agent telemetry gap).
- [ ] Protocol untouched: `git diff` shows no change to lines `101-105` region (`ClaudeAPIServiceProtocol`).
- [ ] `ClaudeAPIServiceTests`, `ClaudeAPIErrorTests`, `ClaudeAPIServiceTelemetryTests` all pass unmodified; full UnitPlan run is green (modulo the known baseline failure noted in WS8-01).
- [ ] Manual smoke on simulator (online): run one injury analysis end-to-end — succeeds, and SessionLogger shows `apiCallStarted`/`apiCallSucceeded` for `claudeProxy` as before.
**Verify** —
```bash
xcodebuild build -project ios/PT-Helper/PT-Helper.xcodeproj \
  -scheme PT-Helper -destination 'platform=iOS Simulator,name=iPhone 16'

xcodebuild test -project ios/PT-Helper/PT-Helper.xcodeproj \
  -scheme PT-Helper -destination 'platform=iOS Simulator,name=iPhone 16'

xcodebuild test -project ios/PT-Helper/PT-Helper.xcodeproj \
  -scheme PT-Helper -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:PT-HelperTests/ClaudeAPIServiceTests \
  -only-testing:PT-HelperTests/ClaudeAPIErrorTests \
  -only-testing:PT-HelperTests/ClaudeAPIServiceTelemetryTests
```
**Depends on / Blocks** — depends on nothing; blocks WS8-03.

---

### [WS8-03] Add service-level retry: 1 retry, 2s delay, transport/5xx only, never 429
`P2` · `effort: S` · `risk: doubles worst-case latency on genuinely-down endpoints (90s→~182s for proxy); bounded by 1 retry and eligibility rules
**Problem** — A single transient blip (dropped cellular packet, cold-start 500 from the Cloud Function) hard-fails an analysis the user then has to manually re-run. All recovery today is manual Try Again buttons. Policy is pre-decided by the audit: 1 retry, 2s backoff, idempotent request types only, never retry 429 (the server's rate window is 60s — a 2s wait cannot succeed and would double-bill the quota).
**Evidence** —
- `Services/ClaudeAPIService.swift` — `grep -n "retry"` returns zero logic hits at 5fd0abb; single-shot calls at `:217/:370/:487`; immediate `.rateLimited` throws at `:270/:396/:513`; no Retry-After parsing anywhere (server doesn't send one — do not add parsing).
- `ViewModels/ExerciseSwapViewModel.swift:79-81,:121` — `maxSaferSubstituteRetries = 3` with a 5s-per-attempt race (`fetchSubstituteResponseWithTimeout`, `:197-222`); a 2s service-level sleep inside a 5s attempt budget would starve it and stack retries 3×2.
- `ViewModels/RecoveryInsightsViewModel.swift:118,:155` and `ViewModels/FormAnalysisViewModel.swift:244,:259` — both agent callers already have agent→single-call fallback; retrying a 180s agent endpoint would stack up to ~6 min before fallback and spawn duplicate Managed Agent sessions server-side.
**Change spec** (all closed decisions):
1. Eligibility (closes "idempotent request types only"): retry applies **only** inside `performProxyRequest` when the call is eligible. `sendMessage` is eligible for every `AIRequestType` **except** `.exercise_substitute` (its VM owns retry, evidence above). Both agent endpoints are **never** eligible (VM fallback + Managed Agent session cost, evidence above). All proxy request types are idempotent server-side (`claudeProxy` is a pure generate-and-return; no user-data writes), so cost — not correctness — is the only retry consideration.
2. Add to `ClaudeAPIService` (internal, `nonisolated`, for direct unit testing):
```swift
static let maxAttempts = 2                       // 1 initial + 1 retry
static let retryDelaySeconds: TimeInterval = 2   // fixed first backoff step
static func isServiceRetryEligible(_ requestType: AIRequestType) -> Bool {
    requestType != .exercise_substitute
}
static func isRetryableStatus(_ statusCode: Int) -> Bool {
    (500...599).contains(statusCode)
}
```
3. Add `let retryEligible: Bool` to `ProxyCall` (from WS8-02). `sendMessage` passes `Self.isServiceRetryEligible(requestType)`; both agent methods pass `false`.
4. Restructure `performProxyRequest`'s transport-call + status-switch region into a `for attempt in 1...Self.maxAttempts` loop. Per attempt: on transport error (URLSession throw) or on `isRetryableStatus(statusCode)`, if `call.retryEligible && attempt < Self.maxAttempts`: emit the existing `.apiCallFailed` telemetry for that failure with an added extras key `"attempt": "\(attempt)"`, then `try? await Task.sleep(for: .seconds(Self.retryDelaySeconds))`; if `Task.isCancelled` after the sleep, throw the original mapped error (never swallow cancellation into a retry); else `continue`. Otherwise throw exactly as today. Non-retryable outcomes short-circuit unchanged and are **never** retried: 429 (`rateLimited`), 401, non-5xx defaults, `HTTPURLResponse` cast failure, decode failures, `noContent` (parse-stage failures come after a successful transport — retrying them re-bills for the same likely-deterministic output).
5. Add the extras key `"attempt": "\(attempt)"` to the success telemetry too (value `"1"` on first-try success), so retry rate is measurable in session logs.
6. Tests in `PT-HelperTests/Services/ClaudeAPIServiceTests.swift` (pure statics, no networking):
   - `testIsServiceRetryEligible_allRequestTypes` — exhaustive over all 9 `AIRequestType` cases: only `.exercise_substitute` is `false`.
   - `testIsRetryableStatus_matrix` — `true` for 500, 502, 503, 599; `false` for 200, 400, 401, 404, 429, 600.
   - `testRetryConstants` — `maxAttempts == 2`, `retryDelaySeconds == 2`.
7. R3 honesty note for the executor: the loop itself cannot be unit-tested without URLSession injection (deliberately out of scope, see Do NOT) — it is verified by build + the decision-logic tests + code review. State this in the PR description.
**Do NOT** — retry 429 under any framing; parse Retry-After; add retry loops to any ViewModel; introduce URLSession/URLProtocol injection into `ClaudeAPIService`; touch `functions/` (server rate limiting is out of scope).
**Files to touch** —
- `ios/PT-Helper/PT-Helper/Services/ClaudeAPIService.swift`
- `ios/PT-Helper/PT-HelperTests/Services/ClaudeAPIServiceTests.swift`
Anything else = STOP and mark BLOCKED.
**Acceptance criteria** —
- [ ] `grep -c "maxAttempts" ios/PT-Helper/PT-Helper/Services/ClaudeAPIService.swift` ≥ 2 (declaration + loop use); `grep -c "Task.sleep" …/ClaudeAPIService.swift` returns 1.
- [ ] `grep -n "case 429" …/ClaudeAPIService.swift` shows exactly 1 hit, and it throws `.rateLimited` with no retry path reachable from it.
- [ ] `grep -c "retryEligible" …/ClaudeAPIService.swift` ≥ 3 (struct field + 3 call sites → sendMessage true-expr, two agent `false`).
- [ ] The 3 new tests pass; full UnitPlan green (modulo known baseline failure).
- [ ] `ExerciseSwapViewModelTests` unchanged and green (proves the swap flow's own retry/timeout behavior is untouched).
**Verify** —
```bash
xcodebuild build -project ios/PT-Helper/PT-Helper.xcodeproj \
  -scheme PT-Helper -destination 'platform=iOS Simulator,name=iPhone 16'

xcodebuild test -project ios/PT-Helper/PT-Helper.xcodeproj \
  -scheme PT-Helper -destination 'platform=iOS Simulator,name=iPhone 16'

xcodebuild test -project ios/PT-Helper/PT-Helper.xcodeproj \
  -scheme PT-Helper -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:PT-HelperTests/ClaudeAPIServiceTests \
  -only-testing:PT-HelperTests/ExerciseSwapViewModelTests
```
**Depends on / Blocks** — depends on WS8-02 (retry lands inside `performProxyRequest`); blocks nothing.

---

**Skipped (P3, low value):**
- Retry-After header parsing for 429 — server never sends the header, and the settled policy forbids 429 retry; parsing would be dead code.
- URLSession/URLProtocol injection to unit-test the retry loop end-to-end — new test infrastructure for one bounded loop already covered by pure-function tests + build gate.
- ReAssessmentViewModel offline treatment — makes zero AI calls (verified `:40-98`); Firestore SDK queues writes and serves cached reads offline, and the `ThreeTabView:24` banner already explains sync behavior.
- Consolidating `WellnessAnalyzingView:116`'s post-failure `isConnected` phrasing with the new guard — redundant after WS8-01 but harmless; it still improves wording for mid-flight connection drops.

## WS9: Typography + token sweep

**Scope (3 lines).** Mechanically replace raw SwiftUI font/spacing/corner literals with `DesignSystem.swift` tokens across live (non-dead, non-test) view files, and fold hand-rolled "card" modifier stacks into `.cardStyle()`. Per D-5 the font sweep touches **text-attached** sites only — icon-sizing fonts on `Image(systemName:)` are excluded (rule + grep published below). Risk is LOW/mechanical; the only real hazard is a point-size shift changing a screen's look, gated per-PR by SmokePlan + the per-screen audit screenshots in `ios/PT-Helper/docs/audit-assets-2026-07-17/`.

**Shared context (read once; every item below references these tables).** All counts verified at `5fd0abb` with the exclusion regex `EXCL='AssessTab|Views/Dashboard/|PlansTab\.swift|ContentView\.swift|ShowcaseHostView|DesignSystem\.swift|PT-HelperTests|PT-HelperUITests'` (dead trees per D-1 + DesignSystem definitions + test targets). Live totals: **502** raw `.font(` sites (138 `.font(.system(size:`, 30 `Font.custom(`, 302 Dynamic-Type presets, ~32 misc), **65** numeric `.padding` sites, **22** numeric corner literals (9 `.cornerRadius(n)` + 13 `RoundedRectangle(cornerRadius: n)`), **57** hand-rolled `.background(AppColors.cardBackground)` + 2 `.fill(...)`, of which **33** are full card "quadruples". `IntroCarouselView.swift` is **owned by WS4** (COIL re-skin, D-4) — every literal in it is out-of-scope here; `Views/Debug/MissingImagesDebugView.swift` is `#if DEBUG`-gated (release-safe, low value); `ProgressChartView.swift` is legacy-only and dies in WS1 — **do not touch these three files in WS9**.

**D-5 icon-exclusion rule + published grep (single source of truth for what the font sweep skips).** A raw `.font(...)` is EXCLUDED when its nearest enclosing view constructor (upward scan within the file) is `Image(...)` — that font is sizing an SF Symbol, not text. Classify every raw font deterministically with this copy-paste command (verified to reproduce the split 165 IMAGE / 337 TEXT ≈ seed's 164 icon / 320 text + 18 ambiguous, ±1):
```bash
cd ios/PT-Helper/PT-Helper
EXCL='AssessTab|Views/Dashboard/|PlansTab\.swift|ContentView\.swift|ShowcaseHostView|DesignSystem\.swift|PT-HelperTests|PT-HelperUITests'
for f in $(grep -rl '\.font(' --include='*.swift' . | grep -vE "$EXCL"); do
  awk '/Image\(systemName:|Image\(/{ctor="IMAGE"}
       /Text\(|Label\(|TextField\(|SecureField\(|navigationTitle|Button\(action|Button\("/{ctor="TEXT"}
       /\.font\(/ && $0 !~ /AppFonts\./ {print ctor" "FILENAME":"FNR}' "$f"
done   # IMAGE lines = excluded; TEXT lines = sweep scope
```
Sonnet MUST read the ±3 lines of context at each site and skip `Image`-attached fonts. The ~18 ambiguous container-level fonts (e.g. a `.font()` on a `VStack` cascading to children) get case-by-case review: if all descendants are text, tokenize; if it feeds an icon, skip.

**MASTER FONT TOKEN-MAPPING TABLE (raw size/weight → AppFonts token).** Tokens verified present in `DesignSystem.swift:262-300`. Industry-Bold family = `display 36 / heroTitle 28 / title 24 / sectionTitle 20 / statNumber 28 / cardTitle 14 / fieldLabel 11 / badge 10`; Inter family = `body/bodyMedium/bodySemiBold 14 · small/smallMedium/smallSemiBold 13 · caption/captionMedium/captionSemiBold 12 · micro/microMedium 11`. Every AppFonts token already carries `relativeTo:` so Dynamic-Type scaling is preserved after substitution.

| Raw form | Weight/qualifier | → AppFonts token |
|---|---|---|
| `.font(.system(size: 36+))` or `size:*, design:.rounded` on a **number** | bold | `AppFonts.display` (hero stat) or `AppFonts.statNumber` (28, in-card stat) |
| `.font(.system(size: 28))` | bold | `AppFonts.heroTitle` (title) / `AppFonts.statNumber` (number) |
| `.font(.system(size: 24))` | bold | `AppFonts.title` |
| `.font(.system(size: 20))` | bold/semibold | `AppFonts.sectionTitle` |
| `.font(.system(size: 15–17))` | regular / medium / semibold | `AppFonts.body` / `.bodyMedium` / `.bodySemiBold` |
| `.font(.system(size: 14))` | regular / medium / semibold | `AppFonts.body` / `.bodyMedium` / `.bodySemiBold` |
| `.font(.system(size: 13))` | regular / medium / semibold | `AppFonts.small` / `.smallMedium` / `.smallSemiBold` |
| `.font(.system(size: 12))` | regular / medium / semibold | `AppFonts.caption` / `.captionMedium` / `.captionSemiBold` |
| `.font(.system(size: 11))` | regular / medium | `AppFonts.micro` / `.microMedium` (uppercase field label → `.fieldLabel`) |
| `.font(.system(size: 10))` | bold/uppercase | `AppFonts.badge` |
| `Font.custom("Industry-Bold", size: N)` | — | nearest Industry token by point size: 36→`display`, 32→`heroTitle`, 28→`heroTitle`/`statNumber`, 24→`title`, 20→`sectionTitle`, 16→`cardTitle`(role=card title) or `sectionTitle`(role=section), 14→`cardTitle`, 13→`cardTitle`, 11→`fieldLabel`, 10→`badge` |
| `Font.custom("Inter-Regular"/"Inter-Medium"/"Inter-SemiBold", size: N)` | — | 15→`body`/`bodyMedium`/`bodySemiBold`, 14→same, 13→`small*`, 12→`caption*` |
| `.font(.largeTitle)` | — | `AppFonts.display` |
| `.font(.title)` | — | `AppFonts.title` (`.heroTitle` if it's a screen H1) |
| `.font(.title2)` | — | `AppFonts.title` |
| `.font(.title3)` | — | `AppFonts.sectionTitle` |
| `.font(.headline)` | (semibold) | `AppFonts.cardTitle` |
| `.font(.body)` | — | `AppFonts.body` |
| `.font(.callout)` | — | `AppFonts.bodyMedium` |
| `.font(.subheadline)` | — | `AppFonts.small` (`.smallSemiBold` if `.bold()`/`.semibold()` chained) |
| `.font(.footnote)` | — | `AppFonts.caption` |
| `.font(.caption)` | — | `AppFonts.caption` |
| `.font(.caption2)` | — | `AppFonts.micro` (uppercase mini-badge → `.badge`) |

Rule for a **weight modifier chained after** a preset (`.font(.subheadline).fontWeight(.semibold)` or `.bold()`): pick the SemiBold/Medium token variant and delete the trailing weight modifier. Dynamic-preset → AppFonts is a **brand-normalizing substitution**: point size may shift to the COIL canonical value and the family moves SF → Inter/Industry (this is the intent — the audit found stray serif/SF text off the brand ramp). Screenshots are the regression gate.

**PADDING VALUE → TOKEN TABLE** (`AppSpacing`, `DesignSystem.swift:229-244`). Exact: `2→nano · 4→xs · 6→tight · 8→sm · 10→comfortable · 12→md · 16→lg · 20→xl · 24→wide · 28→xxl · 32→huge · 40→xxxl`. Composed (no exact ladder token — use idiomatic composed form already used in DesignSystem, e.g. `CoilBadge` uses `AppSpacing.nano + 1`, `QuickActionCard` uses `AppSpacing.md + 2`): `3→AppSpacing.nano + 1 · 5→AppSpacing.xs + 1 · 14→AppSpacing.md + 2 · 18→AppSpacing.lg + 2`. Out of scope: `52`, `140` (IntroCarousel only — WS4).

**CORNER VALUE → TOKEN TABLE** (`AppCorners`, `DesignSystem.swift:248-256`). Exact: `8→small · 12→medium · 16→card · 20→large · 24→xl · 28→xxl · 100→pill`. Composed: `10→AppCorners.small + 2 · 14→AppCorners.medium + 2 · 7→AppCorners.small - 1 · 6→AppCorners.small - 2`. Sub-6pt decorative radii (`2/3/4` on chips, thumbnails, progress bars) are **out of scope** — leave them; they are decorative micro-shapes, not tokenized card/input radii (adjacent concern).

**Shared VERIFY boilerplate (used verbatim by every item; commands copied verbatim from `CLAUDE.md`).**
```bash
# Build
xcodebuild build -project ios/PT-Helper/PT-Helper.xcodeproj \
  -scheme PT-Helper -destination 'platform=iOS Simulator,name=iPhone 16'
# Smoke tests (required per-PR test plan)
xcodebuild test -project ios/PT-Helper/PT-Helper.xcodeproj \
  -scheme PT-Helper -testPlan SmokePlan -destination 'platform=iOS Simulator,name=iPhone 16'
```
(Known env gotcha: if `name=iPhone 16` resolves to the wrong runtime, pin the iPhone 16 sim by `OS=18.2` or its UDID — see memory `project_build_simulator_destination`. No functions changes in WS9, so no `npm` step.) Visual compare = screenshot the touched screen on the simulator and diff against its `docs/audit-assets-2026-07-17/*.png` counterpart; only intended point-size/family shifts may differ.

---

### [WS9-01] Tokenize text fonts in the 7 worst-offender screens (+ own the master mapping table)
`P2` · `effort: M` · `risk: point-size shift on a stat number / title changes screen look — caught by screenshot diff`
**Problem** — These seven screens hold the densest raw-font clusters in the app, and the audit found off-brand serif/SF text intrusions (guided-workout titles, score numbers) that break the COIL Industry/Inter ramp. Tokenizing them lifts the live V5 scoreboard the most per PR and normalizes the most-viewed surfaces. This item also carries the master mapping table above as the single source of truth for WS9-02.
**Evidence** — counts at `5fd0abb`, `grep -rn '\.font(' | grep -v 'AppFonts\.'` per file:
- `Views/BodyMap3DView.swift` — 31 raw fonts (19 text / 10 icon / 2 ambiguous); most icon-attached, ~19 text sites to convert.
- `Views/FormAnalysisView.swift` — 29 raw (22 text / 7 icon); e.g. `:543` `.font(.system(size: 36, weight: .bold, design: .rounded))` on the score number `Text("\(feedback.overallScore)")` → `AppFonts.display`; `:66/:143/:465` are `Image(systemName:).font(.system(size:))` icons → SKIP.
- `Views/SettingsView.swift` — 24 raw (13 text / 11 icon).
- `Views/RehabPlanView.swift` — 24 raw (20 text / 3 icon / 1 ambiguous).
- `Views/WellnessPlanView.swift` — 20 raw (11 text / 7 icon / 2 ambiguous).
- `Views/QuickHealthUpdateView.swift` — 18 raw (13 text / 2 icon / 3 ambiguous).
- `Views/GuidedWorkoutView.swift` — 14 raw (7 text / 7 icon); the serif-looking "Wall Sits" title in `workout-light.png` is one of these text sites.
**Change spec** —
1. For each of the 7 files, run the D-5 classifier command (shared context) to list its TEXT vs IMAGE font lines.
2. For every TEXT-classified `.font(...)`, replace with the token from the MASTER FONT TOKEN-MAPPING TABLE. Delete any now-redundant trailing `.fontWeight(...)`/`.bold()` when you picked the weighted token variant.
3. Leave every IMAGE-classified `.font(.system(size:))` **exactly as-is** (D-5). For the handful of ambiguous container-level fonts, apply the shared-context ambiguity rule (all-text descendants → tokenize; feeds an icon → skip).
4. Do not add new AppFonts tokens — round non-canonical custom sizes to the nearest existing token per the table (chosen by role). If a site genuinely has no reasonable token (novel size on load-bearing text), leave it and list it in the PR description under "no-token sites" rather than inventing one.
**Do NOT** — touch `.padding`/`.cornerRadius`/`.background` literals here (WS9-03/04 own those); do not touch the other ~55 files (WS9-02); do not modify `DesignSystem.swift` (no new tokens).
**Files to touch** — `Views/BodyMap3DView.swift`, `Views/FormAnalysisView.swift`, `Views/SettingsView.swift`, `Views/RehabPlanView.swift`, `Views/WellnessPlanView.swift`, `Views/QuickHealthUpdateView.swift`, `Views/GuidedWorkoutView.swift`. Anything else = STOP and mark BLOCKED.
**Acceptance criteria** —
- [ ] D-5 classifier over these 7 files reports **0 TEXT** lines (only IMAGE remain): rerun the shared classifier scoped to the 7 files → TEXT count = 0.
- [ ] `grep -rn 'Font\.custom(' Views/BodyMap3DView.swift Views/FormAnalysisView.swift Views/SettingsView.swift Views/RehabPlanView.swift Views/WellnessPlanView.swift Views/QuickHealthUpdateView.swift Views/GuidedWorkoutView.swift` returns 0 (all custom fonts tokenized).
- [ ] Build succeeds; SmokePlan passes.
- [ ] Screenshot diff of `workout-light.png` (GuidedWorkout title now Industry, not serif) and `progress`/form score number vs audit assets shows only intended family/size change, no layout break.
**Verify** — shared VERIFY boilerplate + visual compare vs `docs/audit-assets-2026-07-17/workout-light.png`, `progress-light.png`.
**Depends on / Blocks** — Depends on nothing. Blocks nothing (WS9-02 reuses the table but can start in parallel on disjoint files).

---

### [WS9-02] Tokenize text fonts across the remaining live screens (long tail)
`P2` · `effort: L` · `risk: many files, low per-file complexity; may split into 2 PRs (components vs screens)`
**Problem** — After WS9-01 the remaining ~230 text-attached raw fonts sit across ~55 live files (dashboards, onboarding, components, wellness, recovery). They keep the scoreboard off zero and leave sporadic SF/serif text (e.g. the "Your Health Data" serif consent heading, profile display name) off the COIL ramp. Purely mechanical with the table already fixed.
**Evidence** — all live files with raw fonts EXCEPT the 7 in WS9-01 and the three excluded files. Representative clusters (text/icon/ambig, `5fd0abb`): `RecoveryInsightsDetailView 6/6/0`, `RecoveryInsightsCardView 8/3/0`, `ReAssessmentComparisonView 8/3/0`, `AnalyzingView 7/4/0`, `ProgressTab 4/7/0`, `AnalysisResultView 5/6/0`, `WellnessDetailView 8/1/0`, `HealthDataConsentView 4/3/0` (serif heading site), `ThreeTabView 3/4/0`, plus the onboarding-step, component, and wellness files enumerated in the seed's full per-file table. `Font.custom` long-tail includes `PainWizardSteps.swift:228 .font(Font.custom(isSelected ? "Inter-SemiBold" : "Inter-Regular", size: 15))` → `isSelected ? AppFonts.bodySemiBold : AppFonts.body`.
**Change spec** —
1. Enumerate scope: `grep -rl '\.font(' --include='*.swift' Views | grep -vE "$EXCL"` minus the 7 WS9-01 files minus `IntroCarouselView.swift`, `Debug/MissingImagesDebugView.swift`, `ProgressChartView.swift`.
2. Split into two PRs by directory for reviewability: **WS9-02a** = `Views/Components/**` + `Views/OnboardingSteps/**`; **WS9-02b** = remaining top-level `Views/*.swift` + `LoginView.swift`.
3. Apply the identical procedure to WS9-01 steps 1-4 (classifier → MASTER FONT TOKEN-MAPPING TABLE → skip icons → no new tokens). Handle the ternary `Font.custom` case shown in Evidence by tokenizing both arms.
**Do NOT** — touch padding/corner/card literals; touch `IntroCarouselView`/`MissingImagesDebugView`/`ProgressChartView`; touch the 7 WS9-01 files; add AppFonts tokens.
**Files to touch** — every live `Views/**/*.swift` + `LoginView.swift` carrying a text-attached raw font, EXCEPT the 7 WS9-01 files and the 3 excluded files. Exhaustive list = the `grep -rl` in step 1 minus those exclusions; any file outside that computed set = STOP and mark BLOCKED.
**Acceptance criteria** —
- [ ] App-wide D-5 classifier (shared context, full scope) reports **0 TEXT** raw-font lines outside the 3 excluded files — i.e. the only remaining raw `.font(` are IMAGE-classified (icons) or inside `IntroCarouselView`/`MissingImagesDebugView`/`ProgressChartView`.
- [ ] `grep -rn 'Font\.custom(' --include='*.swift' Views | grep -vE "$EXCL|IntroCarouselView"` returns 0.
- [ ] Build succeeds; SmokePlan passes on each sub-PR.
- [ ] Screenshot diff of `healthconsent-light.png` (serif heading normalized), `profile-light.png` (display name), `wellnesspicker-light.png` vs audit assets shows only intended type changes.
**Verify** — shared VERIFY boilerplate (run per sub-PR) + visual compare vs `docs/audit-assets-2026-07-17/healthconsent-light.png`, `profile-light.png`, `wellnesspicker-light.png`, `progress-light.png`.
**Depends on / Blocks** — Depends on WS9-01 only for the shared table (may run in parallel; disjoint files). Blocks nothing.

---

### [WS9-03] Tokenize numeric padding + corner-radius literals
`P3` · `effort: M` · `risk: composed-token rounding (14→md+2 etc.) shifts spacing ≤2pt — visually negligible, screenshot-checked`
**Problem** — 65 numeric `.padding` and 22 numeric corner literals bypass the `AppSpacing`/`AppCorners` ladders, so spacing/rounding drifts screen-to-screen and can't be retuned centrally. Mechanical mapping tables are fixed in shared context.
**Evidence** — at `5fd0abb`: 65 padding sites (worst live-in-scope after removing WS4/debug: `SettingsView 12`, `PainWizardSteps 7`, `ReportConcernView 3`, `GuidedWorkoutView 3` incl. `:200 .padding(.horizontal, 10)`→`AppSpacing.comfortable`); 22 corner sites — `.cornerRadius(n)`: `GuidedWorkoutView ×3, ProfileReviewStepView, NotesView, ExerciseIllustration, AdaptiveProgressionBannerView ×1` (+ IntroCarousel/debug excluded); `RoundedRectangle(cornerRadius: n)`: `HomeTab ×4, RehabPlanView ×2, RecoveryInsightsDetailView ×2, WellnessResultView, GuidedWorkoutView, AnalysisResultView ×1` (+ IntroCarousel ×2 excluded). Distinct padding values in use: 2,3,4,5,6,8,10,12,14,16,18,20,24,32,40 (52/140 are IntroCarousel). Distinct corner values: 2,3,4,6,7,10,14,100.
**Change spec** —
1. Replace every in-scope numeric `.padding(...)` per the PADDING VALUE → TOKEN TABLE (exact tokens, and the composed forms `3→nano+1`, `5→xs+1`, `14→md+2`, `18→lg+2`). Preserve the edge argument (`.top`/`.horizontal`/etc.) — only the numeric changes.
2. Replace every in-scope numeric corner literal (both `.cornerRadius(n)` and `RoundedRectangle(cornerRadius: n)`) per the CORNER VALUE → TOKEN TABLE. Leave sub-6pt decorative radii (2/3/4) untouched.
3. Skip `IntroCarouselView.swift` (WS4), `Debug/MissingImagesDebugView.swift` (debug), `ProgressChartView.swift` (dies WS1) entirely.
4. Any literal with no table entry and >2pt from the nearest token on load-bearing layout: keep it, add it to the PR "unmapped literals" list — do NOT guess.
**Do NOT** — touch `.font` literals (WS9-01/02) or `.background(AppColors.cardBackground)` card stacks (WS9-04); do not add new AppSpacing/AppCorners rungs.
**Files to touch** — every live file matching the padding/corner greps EXCEPT the 3 excluded files. Compute via the two grep -rl commands in shared context minus `$EXCL` minus IntroCarousel/debug/ProgressChart. Anything else = STOP and mark BLOCKED.
**Acceptance criteria** —
- [ ] `grep -rnE '\.padding\(([0-9]+(\.[0-9]+)?\)|\.(top|bottom|leading|trailing|horizontal|vertical|all)\s*,\s*[0-9]+(\.[0-9]+)?\))' --include='*.swift' . | grep -vE "$EXCL|IntroCarouselView|MissingImagesDebugView|ProgressChartView"` returns **0** (or only entries on the documented "unmapped literals" list).
- [ ] `{ grep -rnE '\.cornerRadius\([0-9]' ... ; grep -rnE 'RoundedRectangle\(cornerRadius:\s*[0-9]' ... ; } | grep -vE "$EXCL|IntroCarouselView|MissingImagesDebugView|ProgressChartView"` returns only sub-6pt decorative radii (documented) — **no** value ≥6 remains.
- [ ] Build succeeds; SmokePlan passes.
- [ ] Screenshot diff of `settings-light.png`, `home-light.png` (RoundedRectangle cards) vs audit assets shows no perceptible spacing/rounding change.
**Verify** — shared VERIFY boilerplate + visual compare vs `docs/audit-assets-2026-07-17/settings-light.png`, `home-light.png`.
**Depends on / Blocks** — nothing.

---

### [WS9-04] Fold hand-rolled card stacks into `.cardStyle()`
`P3` · `effort: S` · `risk: shadow/padding mismatch between a hand-rolled stack and cardStyle's elevation — mapped explicitly below`
**Problem** — `.cardStyle()` has only **2** live uses versus **57** hand-rolled `.background(AppColors.cardBackground)` stacks; **33** of those are the exact card "quadruple" (`background + cornerRadius(AppCorners.card) + overlay stroke(cardBorder) + shadow`) that `.cardStyle()` was built to replace (`DesignSystem.swift:313-350`). Consolidating removes ~130 lines of copy-paste and makes card elevation centrally tunable. The canonical target is `ProgressTab.swift:478-482` (`.padding(AppSpacing.lg)` + the quadruple = byte-for-byte `cardStyle(.subtle)`).
**Evidence** — 33 full-card quadruples across 18 live files at `5fd0abb` (grep: `.background(AppColors.cardBackground)` with `cornerRadius(AppCorners.card)` within 4 lines): `FormAnalysisView 6, ProgressTab 5, RehabPlanView 3, ExerciseSwapSheet 2, AchievementsView 2, GuidedWorkoutView 2, Components/ExercisePhaseStepperView 2, and ×1: HealthCheckPromptView, AdaptiveProgressionBannerView, AnalyzingView, WellnessAnalyzingView, GuidedWorkoutSummaryView, FormCheckTab, PainDetailView, MyPlanTab, Components/RegionPainInputView, Components/StreakBadgeView`. The other 24 `cardBackground` sites are partial/decorative (chips, circles, badges — e.g. `GuidedWorkoutView` compact-action circle) and are NOT cards.
**Change spec** —
1. Enumerate the 33 quadruples with the done-grep in step 5.
2. For each quadruple whose leading modifier is `.padding(AppSpacing.lg)` (canonical quintuple): delete the 5 modifiers (`.padding(AppSpacing.lg)` + `.background(AppColors.cardBackground)` + `.cornerRadius(AppCorners.card)` + `.overlay(RoundedRectangle(cornerRadius: AppCorners.card).stroke(AppColors.cardBorder, lineWidth: 1))` + `.shadow(...)`) and replace with a single `.cardStyle(elevation)`.
3. Map the shadow to the elevation enum (`DesignSystem.swift:332-343`): `radius 8, y 2 → .subtle` (the default, omit arg) · `radius 12, y 4 → .raised` · `radius ≥20 → .hero` · `radius 0 → .flat`. Match on the shadow the site actually uses.
4. If a quadruple's leading padding is NOT `.padding(AppSpacing.lg)` (different value or asymmetric horizontal/vertical), it is not a clean `.cardStyle()` match (cardStyle bakes in `padding(AppSpacing.lg)`) — LEAVE it and list under "manual-review cards" in the PR. Do NOT force it. Leave all 24 partial/decorative `cardBackground` sites untouched.
**Do NOT** — convert `CardSection`-wrapped content (already healthy at 55 uses); touch decorative small-shape `cardBackground` fills; change `.cardStyle()`'s definition; touch font/padding/corner literals owned by WS9-01/02/03.
**Files to touch** — the ≤18 files listed in Evidence (only those with a qualifying quintuple). Any file outside that set = STOP and mark BLOCKED.
**Acceptance criteria** —
- [ ] Done-grep returns **0** convertible quintuples: `for f in $(grep -rl '\.background(AppColors.cardBackground' --include='*.swift' Views | grep -vE "$EXCL"); do awk '/\.background\(AppColors.cardBackground/{flag=NR} flag && NR<=flag+4 && /cornerRadius\(AppCorners.card/{print FILENAME":"FNR; flag=0}' "$f"; done` returns only the documented "manual-review cards" (non-`AppSpacing.lg` padding), everything else converted.
- [ ] `.cardStyle(` live-use count rises from 2 to ≥ (2 + converted count); `grep -rn '\.cardStyle(' --include='*.swift' Views | wc -l`.
- [ ] Build succeeds; SmokePlan passes.
- [ ] Screenshot diff of `progress-light.png` (pain-trend card), `plandetail-light.png` vs audit assets shows pixel-identical cards (cardStyle reproduces the same quadruple).
**Verify** — shared VERIFY boilerplate + visual compare vs `docs/audit-assets-2026-07-17/progress-light.png`, `plandetail-light.png`.
**Depends on / Blocks** — Best sequenced AFTER WS9-03 (so corner/padding literals are already tokenized and the quintuple grep matches cleanly), but independent files; not a hard dependency.

---

**Skipped (P3, low value):**
- Tokenizing `Views/Debug/MissingImagesDebugView.swift` fonts/padding (9 fonts, 3 padding, 1 corner) — `#if DEBUG`-gated, never ships; not worth Sonnet's time.
- Sub-6pt decorative corner radii (values 2/3/4 on chips/thumbnails/progress bars) — no matching token, forcing composed forms (`small - 6`) reads worse than the literal; leave as-is.
- The ~24 partial/decorative `.background(AppColors.cardBackground)` sites (non-quadruple chips/badges/circles) — `.cardStyle()` would wrongly add card padding/shadow to small shapes; out of scope by design (S45 caveat).

## WS10: Home-screen truth

**Scope (3 lines).** The Home tab ships two pieces of theatre: a 21-day scrollable "week" strip whose day selection changes nothing but a header label (per-day programming does not exist), and a 7-item "Preventative" checklist that is hardcoded, unpersonalized, and invisible to every progress/streak/analytics surface. This workstream makes the strip honest (fixed current-week showing REAL completion dots from session history), stops the strip from implying per-day content, gates the Preventative checklist on an active plan, and closes a matching account-deletion data leak. Per-day exercise programming stays an Appendix-A bet — do not build it here.

**Shared context.** Everything lives in one file, `ios/PT-Helper/PT-Helper/Views/HomeTab.swift` (plus one account-deletion fix in `SettingsView.swift`). At 5fd0abb `HomeTab` owns `@State selectedDate` (HomeTab.swift:9) which drives three things — `WeeklyDateStrip` (:26), `ProgramDayView(date:)` (:39), and `PreventativeTasksView(date:)` (:41). Verified: `ProgramDayView` uses `date` only for its header label `dayLabel` (:242-247, :252) and renders the identical `plan.exercises.prefix(8)` list and the same Start CTA for all 21 selectable days (:268, :280); `DayCell` (:157-194) has no completion marker. The real per-day completion source is `WorkoutViewModel.sessions` (`@Published [WorkoutSession]`, WorkoutViewModel.swift:7) — `WorkoutSession` carries `date: Date` and `isCompleted: Bool` (WorkoutSession.swift:5,8). That view-model is already created as an `@StateObject` at ThreeTabView.swift:10 and injected `.environmentObject(workoutViewModel)` at ThreeTabView.swift:82, so `HomeTab` only needs to add `@EnvironmentObject`. `sessions` is a one-shot Firestore fetch at init (WorkoutViewModel.swift:19,23-28) that stays fresh in-session via a local insert in `addSession` (:89); `fetchSessions()` is public and already re-called by ProgressTab (ProgressTab.swift:74). All affected symbols (`WeeklyDateStrip`, `DayCell`, `ProgramDayView`, `PreventativeTasksView`, `HomeTabPicker`, `HomeContentTab`) have exactly one instantiation site, all inside HomeTab.swift (grep-verified). `AppColors.success`, `.accent`, `.mutedText`, `.navBackground`, `.cardBorder` all exist in DesignSystem.swift (:67,68,76,90,112). Test plans use `skippedTests` (UnitPlan.xctestplan skips only `BodyMapCollisionTests`), so any new test class in the `PT-HelperTests` target is auto-included. Fixture `TestFixtures.makeSession(daysAgo:isCompleted:)` exists (TestFixtures.swift:489-505).

---

### [WS10-01] Replace the cosmetic 21-day date strip with an honest completion-dot week strip
`P2` · `effort: M` · `risk: single-file view rework; strip becomes read-only, so any external code assuming a selectable date would break (none exists — grep-verified)`

**Problem** — The Home strip lets the user scroll and tap across 21 days (−10…+10), but tapping any day shows the identical active-plan exercise list and Start button; only the "Today's / Yesterday's / <Weekday>'s Program" header changes. This dresses up per-day programming that the app does not have, and it lets users "check off" preventative tasks on future dates. The strip should instead tell the truth: the current week, with a real dot on the days a workout was actually completed.

**Evidence**
- `HomeTab.swift:9` — `@State private var selectedDate: Date = Date()`, the fake driver.
- `HomeTab.swift:26,39,41` — `selectedDate` feeds `WeeklyDateStrip`, `ProgramDayView(date:)`, `PreventativeTasksView(date:)`.
- `HomeTab.swift:63-70` — `scrollableDays` builds the misleading ±10-day (21-cell) range.
- `HomeTab.swift:157-194` — `DayCell` renders only weekday + number; no completion marker.
- `HomeTab.swift:242-247,252,268,280` — `ProgramDayView` uses `date` only for `dayLabel`; same exercises + same CTA for every date.
- `WorkoutViewModel.swift:7,89` — `@Published sessions` with local insert on save (fresh in-session).
- `ThreeTabView.swift:82` — `.environmentObject(workoutViewModel)` already injected into the Home subtree.
- `WorkoutSession.swift:5,8` — `date` + `isCompleted` are the fields the dot logic reads.

**Change spec** (all edits in HomeTab.swift unless noted)
1. **Add the pure completion helper** (so the one piece of new logic is unit-testable). At the top of HomeTab.swift, after `import SwiftUI`, add:
   ```swift
   enum HomeStripLogic {
       /// True iff a completed workout session falls on `day`.
       static func hasCompletedSession(on day: Date, in sessions: [WorkoutSession],
                                       calendar: Calendar = .current) -> Bool {
           sessions.contains { $0.isCompleted && calendar.isDate($0.date, inSameDayAs: day) }
       }
   }
   ```
   Rationale: keeps the dot rule pure, `@MainActor`-free, and coverable by UnitPlan.
2. **Remove the fake driver.** Delete `@State private var selectedDate` (:9). Add `@EnvironmentObject private var workoutViewModel: WorkoutViewModel` to `HomeTab` (it is already injected at ThreeTabView.swift:82 — do not add a new `@StateObject`).
3. **Rename + rewrite the strip.** Rename `WeeklyDateStrip` → `WeekCompletionStrip`. Change its input from `@Binding var selectedDate: Date` to a value input `let sessions: [WorkoutSession]`. Update the call site at :26 to `WeekCompletionStrip(sessions: workoutViewModel.sessions)`.
4. **Fixed rolling 7-day window, today at the trailing edge, non-interactive.** Replace `scrollableDays` (:63-70) with offsets `(-6...0)` mapped from `Calendar.current.startOfDay(for: Date())`. Rationale for −6…0 (not the calendar week and not ±future): every cell is today-or-past, so a missing dot unambiguously means "no completed session that day" — no future cell can ever carry a dot, which is exactly the false affordance being removed.
5. **Drop all scrolling + selection chrome.** Remove the `ScrollViewReader`, the horizontal `ScrollView`, the edge-fade `.mask(...)`, the `.onAppear { proxy.scrollTo(...) }`, the `.onTapGesture` day-selection, and the month-row "Today" jump `Button` (:90-107, :113-146). Lay the 7 `DayCell`s in a single non-scrolling `HStack(spacing: AppSpacing.xs)` centered with `.frame(maxWidth: .infinity)`. Keep the month label but source it from `Date()` (today) instead of the deleted `selectedDate`. Keep `.background(AppColors.navBackground)`.
6. **Give `DayCell` a completion dot.** Change `DayCell` params to `let date`, `let isToday`, `let isCompleted` (remove `isSelected`). Below the day-number `Text`, add a 6pt dot: `Circle().fill(AppColors.success)` when `isCompleted`, else `Circle().stroke(AppColors.cardBorder, lineWidth: 1)` (hollow placeholder keeps vertical rhythm). Retain the existing today treatment: day number in `AppColors.accent` and the accent ring overlay when `isToday`. Compute `isCompleted` at the call site via `HomeStripLogic.hasCompletedSession(on: day, in: sessions)`.
7. **De-date `ProgramDayView`.** Remove its `let date: Date` property and the `dayLabel` computed var (:237, :242-247); hardcode the header to `CoilDividerHeader(title: "Today's Program")` (:252). Update the call at :39 to `ProgramDayView(plan: activePlan)`.
8. **De-date `PreventativeTasksView`.** Remove its `let date: Date` property (:365); compute `dateKey` from `Date()` (today) inside `saveState`/`loadState` (:379-383, :450, :455). Remove the now-dead `.onChange(of: date)` (:444); keep `.onAppear { loadState() }`. Update the call at :41 to `PreventativeTasksView()`. This also removes the future-date checkoff bug for free.
9. **Refresh on appear.** Add `.onAppear { workoutViewModel.fetchSessions() }` to the `HomeTab` body (mirrors ProgressTab.swift:74) so completion dots reflect sessions written on other devices / before relaunch. In-session completions already show via the local insert at WorkoutViewModel.swift:89.
10. **Add a unit test.** New file `ios/PT-Helper/PT-HelperTests/HomeStripLogicTests.swift` with ≥3 cases using `TestFixtures.makeSession`: (a) a completed session `daysAgo: 0` → `hasCompletedSession(on: today)` is `true`; (b) a session with `isCompleted: false` on a day → `false`; (c) a completed session `daysAgo: 3` → `true` only for that day, `false` for an adjacent day.

**Do NOT** — Do not add rest-day markers, per-day exercise variation, or any day-tap navigation (per-day programming is an Appendix-A bet, WS-owned elsewhere). Do not touch the XL-Dynamic-Type weekday truncation, the `ACTIVE PLAN` chip contrast, the `3 sets · 30 seconds reps` copy, or exercise-image duplication — those belong to the polish / design-system / images workstreams. Do not add the `if activePlan != nil` gate here (that is WS10-02).

**Files to touch**
- `ios/PT-Helper/PT-Helper/Views/HomeTab.swift`
- `ios/PT-Helper/PT-HelperTests/HomeStripLogicTests.swift` (new)
- Anything else → STOP and mark BLOCKED.

**Acceptance criteria**
- [ ] `grep -c "selectedDate" ios/PT-Helper/PT-Helper/Views/HomeTab.swift` returns `0`.
- [ ] `grep -cE "\(-10\.\.\.10\)|scrollableDays|ScrollViewReader|scrollTo" ios/PT-Helper/PT-Helper/Views/HomeTab.swift` returns `0` (21-day scroller fully removed).
- [ ] `grep -c "onTapGesture" ios/PT-Helper/PT-Helper/Views/HomeTab.swift` returns `0` (strip is read-only).
- [ ] `grep -c "HomeStripLogic" ios/PT-Helper/PT-Helper/Views/HomeTab.swift` returns `≥2` (helper defined + used) and `WeekCompletionStrip` appears exactly twice (definition + call).
- [ ] `@EnvironmentObject private var workoutViewModel: WorkoutViewModel` present in HomeTab.swift; `@StateObject.*WorkoutViewModel` absent from HomeTab.swift.
- [ ] New `HomeStripLogicTests` runs and passes under UnitPlan (≥3 cases).
- [ ] Build succeeds; UnitPlan + SmokePlan green.
- [ ] Visual: launched with `--uitesting --skip-onboarding --seed-mock-data`, the Home strip shows a fixed 7-cell current-week (no horizontal scroll) with green `AppColors.success` dots on days that have completed seeded sessions and hollow dots otherwise — differs intentionally from the dot-less baseline `ios/PT-Helper/docs/audit-assets-2026-07-17/home-light.png`.

**Verify** (verbatim from CLAUDE.md; note memory `project_build_simulator_destination` — if `name=iPhone 16` fails on OS mismatch, target the iPhone 16 sim by `OS=18.2` or its UDID)
```bash
# Build
xcodebuild build -project ios/PT-Helper/PT-Helper.xcodeproj \
  -scheme PT-Helper -destination 'platform=iOS Simulator,name=iPhone 16'

# UnitPlan (default)
xcodebuild test -project ios/PT-Helper/PT-Helper.xcodeproj \
  -scheme PT-Helper -destination 'platform=iOS Simulator,name=iPhone 16'

# SmokePlan
xcodebuild test -project ios/PT-Helper/PT-Helper.xcodeproj \
  -scheme PT-Helper -testPlan SmokePlan -destination 'platform=iOS Simulator,name=iPhone 16'

# Just the new logic test
xcodebuild test -project ios/PT-Helper/PT-Helper.xcodeproj \
  -scheme PT-Helper -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:PT-HelperTests/HomeStripLogicTests
```
Visual compare against `ios/PT-Helper/docs/audit-assets-2026-07-17/home-light.png` (and `home-dynamictype-xl.png` to confirm no new clipping beyond the pre-existing, out-of-scope weekday truncation).

**Depends on / Blocks** — Depends on nothing. Blocks WS10-02 (which edits the same body region after the strip rework lands).

---

### [WS10-02] Gate the Preventative section on an active plan (hide it when there is no plan)
`P2` · `effort: S` · `risk: pure visibility gate in one view; no data or schema change`

**Problem** — The Program/Preventative picker and its 7-item checklist render for every user regardless of state, including users with no active plan and no reason to see a generic "Foam roll / Hydration" list. Gap-hunt provenance shows the checklist is an independently-authored placeholder (commit e6c35fe) with zero personalization, no plan/AI data source, and no read path in Progress, StreakService, or analytics — and `RehabPlan` carries no habit/preventative field to derive real content from (RehabPlan.swift:10-30, verified). The honest, in-scope move is therefore to tie the checklist's *presence* to the active plan: show it only when the user is following one, hide the whole picker otherwise. (Deriving real per-plan habits requires a server prompt + schema change and is an Appendix-A AI bet — not built here.)

**Evidence**
- `HomeTab.swift:14-17` — `activePlan` computed property already exists (`rehabPlans.first(where: planType == .rehab) ?? .first`).
- `HomeTab.swift:28-42` — the `HomeTabPicker` + `switch selectedContentTab` render unconditionally, even when `activePlan == nil`.
- `HomeTab.swift:300-317` — `ProgramDayView.noPlanState` already provides the correct empty state (assessment CTA) when `plan == nil`.
- `HomeTab.swift:367-375` — `taskDefinitions`: 7 static generic strings, no plan/profile input.
- Gap-hunt: `git log -S 'Morning movement'` → single commit e6c35fe with no rationale; the sophisticated preventative system (BodyRiskAnalyzer etc.) lives only on the unmerged `PreventativePTFeature` branch (`git merge-base --is-ancestor 9f0ab23 HEAD` → NOT ANCESTOR) — out of scope.
- App-wide grep `preventiveTasks|Preventative` → zero references outside HomeTab.swift (dead-end feature).

**Change spec** (all edits in HomeTab.swift; apply after WS10-01)
1. In the `HomeTab` body, wrap the picker + content switch (post-WS10-01: the `HomeTabPicker(selected:)` at :29 through the `switch selectedContentTab` block at :37-42) so the picker and the `.preventative` branch only render when `activePlan != nil`:
   - When `activePlan != nil`: render `HomeTabPicker` and the full `switch` (Program / Preventative) exactly as today.
   - When `activePlan == nil`: render neither the picker nor `PreventativeTasksView`; render only `ProgramDayView(plan: nil)` (which shows `noPlanState`). Do not show a Preventative segment the user cannot meaningfully use.
   Chosen approach: an `if activePlan != nil { HomeTabPicker(...) }` guard around the picker, plus a guard in the content area that routes to `ProgramDayView(plan: nil)` directly when `activePlan == nil` (bypassing `selectedContentTab`). Rationale: minimal, no new state, and `selectedContentTab` can safely stay `.program` since the picker that could flip it is hidden.
2. Keep the 7 `taskDefinitions` strings unchanged — deriving real habits from the plan is an Appendix-A AI bet, and there is no plan-side data to read (RehabPlan.swift has no habits field). This item only changes *when* the checklist appears, not its content.

**Do NOT** — Do not delete `PreventativeTasksView` or its persistence (it is live, not dead code — D-1's delete list does not include it). Do not add habit generation, per-plan task derivation, or wire the checklist into StreakService/analytics (Appendix-A / feature scope). Do not touch the strip (WS10-01) or the account-deletion cleanup (WS10-03).

**Files to touch**
- `ios/PT-Helper/PT-Helper/Views/HomeTab.swift`
- Anything else → STOP and mark BLOCKED.

**Acceptance criteria**
- [ ] `grep -c "activePlan != nil" ios/PT-Helper/PT-Helper/Views/HomeTab.swift` returns `≥1` (the gate exists).
- [ ] Build succeeds; UnitPlan + SmokePlan green.
- [ ] Visual (no plan): launched with `--uitesting --skip-onboarding` (no seeded plans), the Home tab shows the "No Active Program" empty state and NO Program/Preventative picker.
- [ ] Visual (with plan): launched with `--uitesting --skip-onboarding --seed-mock-data`, the picker is present and the Preventative tab shows the checklist as before.

**Verify** (verbatim from CLAUDE.md)
```bash
xcodebuild build -project ios/PT-Helper/PT-Helper.xcodeproj \
  -scheme PT-Helper -destination 'platform=iOS Simulator,name=iPhone 16'

xcodebuild test -project ios/PT-Helper/PT-Helper.xcodeproj \
  -scheme PT-Helper -destination 'platform=iOS Simulator,name=iPhone 16'

xcodebuild test -project ios/PT-Helper/PT-Helper.xcodeproj \
  -scheme PT-Helper -testPlan SmokePlan -destination 'platform=iOS Simulator,name=iPhone 16'
```
Visual compare the no-plan launch against the picker-present state in `ios/PT-Helper/docs/audit-assets-2026-07-17/home-light.png`.

**Depends on / Blocks** — Depends on WS10-01 (edits the same body region; land the strip rework first). Blocks nothing.

---

### [WS10-03] Clear `preventiveTasks_*` UserDefaults keys on account deletion
`P3` · `effort: S` · `risk: additive line in an existing cleanup method; no behavior change outside deletion`

**Problem** — Preventative-checklist state is JSON-encoded per day under `UserDefaults` keys `preventiveTasks_<yyyy-MM-dd>`, but `clearAllLocalUserData` — the routine that wipes local state on account deletion — clears profile, consents, drafts, and workout state yet never removes these keys. A deleted-and-recreated account inherits the previous user's checked-off preventative history. After WS10-01 only today's key is ever written going forward, but keys already written by prior builds (up to ±10 days) persist, so this is a real, if small, privacy leak.

**Evidence**
- `SettingsView.swift:557-570` — `clearAllLocalUserData()` removes a fixed set of keys/services; no `preventiveTasks_*` handling.
- `HomeTab.swift:450` — `UserDefaults.standard.set(data, forKey: "preventiveTasks_\(dateKey)")` is the writer.
- Gap-hunt (S47): app-wide grep confirms these keys are read/written only in HomeTab.swift; nothing else prunes them.

**Change spec**
1. Inside `clearAllLocalUserData()` (SettingsView.swift, after line 569, before the closing brace at :570), add a prefix sweep:
   ```swift
   for key in UserDefaults.standard.dictionaryRepresentation().keys
       where key.hasPrefix("preventiveTasks_") {
       UserDefaults.standard.removeObject(forKey: key)
   }
   ```
   Rationale: `UserDefaults` has no prefix-delete API, so enumerate-and-filter is the standard approach; matches the sibling `removeObject(forKey:)` calls already in the method.

**Do NOT** — Do not restyle the Delete Account row, touch the Image Diagnostics contrast, or alter any other Settings row (those belong to design-system / polish). Do not change how the checklist writes keys (WS10-01 already scoped writes to today).

**Files to touch**
- `ios/PT-Helper/PT-Helper/Views/SettingsView.swift`
- Anything else → STOP and mark BLOCKED.

**Acceptance criteria**
- [ ] `grep -c 'hasPrefix("preventiveTasks_")' ios/PT-Helper/PT-Helper/Views/SettingsView.swift` returns `1`.
- [ ] The sweep sits inside `clearAllLocalUserData()` (between the last existing `removeObject` and the method's closing brace).
- [ ] Build succeeds; UnitPlan + SmokePlan green.

**Verify** (verbatim from CLAUDE.md)
```bash
xcodebuild build -project ios/PT-Helper/PT-Helper.xcodeproj \
  -scheme PT-Helper -destination 'platform=iOS Simulator,name=iPhone 16'

xcodebuild test -project ios/PT-Helper/PT-Helper.xcodeproj \
  -scheme PT-Helper -destination 'platform=iOS Simulator,name=iPhone 16'

xcodebuild test -project ios/PT-Helper/PT-Helper.xcodeproj \
  -scheme PT-Helper -testPlan SmokePlan -destination 'platform=iOS Simulator,name=iPhone 16'
```

**Depends on / Blocks** — Depends on nothing (independent of WS10-01/02). Blocks nothing.

---

**Skipped (P3, low value)**
- Wiring the Preventative checklist into StreakService / Progress / analytics so it stops being an invisible silo — deliberately out of scope: it turns a placeholder into a real tracked feature (a product bet), which belongs in Appendix A, not a truth-cleanup. WS10-02 instead hides it when it has no basis to exist.
- Pruning historical `preventiveTasks_*` keys during normal use (unbounded-growth concern from S47): after WS10-01 only one key per genuinely-active calendar day is ever written, so growth is now legitimate and negligible; not worth a background reaper.

## WS11: Performance

**Scope.** Move the rehab-plan image-validation path (cold fuzzy matching + catalog re-decode) off the main thread now that V4 confirmed it executes on `@MainActor`; stop `ProgressTab` from recomputing chart/stat data 2–4× per render and delete the dead `totalMinutes` reduce; configure the 3D body-model collision shapes + zone proxies once on a cached template so per-open work drops to a clone; bound the currently-unbounded workout-session Firestore fetch. The `UserDefaults` full-dictionary prefix-scan item (S28) is **dropped** — V4 refuted it as a perf finding (see end of section).

**Shared context.** Three MainActor entry chains funnel every rehab/wellness plan through `ResponseValidationPipeline.validateRehabPlan` (a plain `struct`, pure synchronous static func) → `ImageAvailabilityValidator.validate` → `ExerciseImageService.shared.resolveImageMatch`, whose cold path runs up to ~10 full O(catalog ≈ 1225-key) scans per unmatched name (layers 4–8, `ExerciseImageService.swift:363-400`). `ExerciseImageService` is `final class … @unchecked Sendable`; its `mapping` and `bundledAliases` dictionaries are written only in `loadMapping()` (init-time, `:632`/`:641`) and read-only thereafter, while `firestoreAliases` and `fuzzyMatchCache` are `NSLock`-guarded (`:359`, `:364`) — so `resolveImageMatch` is thread-safe to call off the main thread. The project builds in Swift 5 language mode (`SWIFT_VERSION = 5.0`), so wrapping these value-in/value-out calls in `Task.detached` compiles without Sendable errors. Because the fuzzy cache is warmed by the first resolve, all downstream resolves (`preloadImages`, `logMissingImages`) are already O(1) cache hits and need no change. All WS11 items are iOS-only (no Cloud Functions), so no `npm` verification applies. These are behavior-preserving perf refactors: screens must be pixel-identical to the audit screenshots.

---

### [WS11-01] Move rehab/wellness image validation off the main thread
`P1` · `effort: M` · `risk: concurrency — Task.detached must use .detached (not Task{}, which inherits MainActor); output plan must be byte-identical`

**Problem** — On first plan generation every exercise name is a cache-miss, so `validateRehabPlan` runs up to ~10 catalog-wide fuzzy scans per exercise **plus** a full ~1225-entry JSON re-decode, entirely on the main thread, stalling the primary AI flow. Worst case is app cold start with up to 5 unrepaired saved plans, which runs 5 × (JSON decode + per-exercise cold scans) inside a single MainActor listener turn. The work is a pure function of value types and is trivially relocatable off-main.

**Evidence** — verified at 5fd0abb:
- `ViewModels/RehabPlanViewModel.swift:65` (`@MainActor` class), `:171` (`Task {}` inherits MainActor), `:180` + `:268` (sync `ResponseValidationPipeline.validateRehabPlan` on both success and fallback paths) — cold resolve runs main-thread.
- `ViewModels/WellnessPlanViewModel.swift:36` (`@MainActor`), `:99` + `:165` (sync `validateRehabPlan`, success + fallback).
- `ViewModels/SavedPlansViewModel.swift:7` (`@MainActor`), `:95` (`Task { @MainActor }` in Firestore listener), `:113` (`self.runRepairPass(on: parsed)`), `:216` (`func runRepairPass` — sync), `:236` (`ImageAvailabilityValidator.validate`), `:29` (`maxRepairsPerSession = 5`).
- `Services/ResponseValidationPipeline.swift:1337` (`struct ResponseValidationPipeline` — not `@MainActor`), `:1447-1452` (`static func validateRehabPlan` — pure value in/out), `:1004` (`loadCatalog()` re-decodes bundled JSON per call), `:999-1015` (`ImageAvailabilityValidator.validate` → `resolveImageMatch` per exercise).
- `Services/ExerciseImageService.swift:11` (`@unchecked Sendable`), `:337-400` (`resolveImageMatch` cold path, NSLock-guarded), `:632`/`:641` (`mapping`/`bundledAliases` written only in `loadMapping()`).

**Change spec** — Sonnet executes, does not redesign:
1. **RehabPlanViewModel** — at `:180` and `:268`, replace the direct `ResponseValidationPipeline.validateRehabPlan(...)` call with `await Task.detached(priority: .userInitiated) { ResponseValidationPipeline.validateRehabPlan(plan, conditions: conditions, userProfile: …, userPainRegions: …) }.value`, preserving the exact argument list already present at each site. Use `Task.detached` (NOT `Task {}`) — the enclosing `Task {}` at `:171` inherits the main actor, so only `.detached` actually leaves it. The `self.rehabPlan = …` / `self.rehabPlanWarnings = …` assignments after the `await` resume on the main actor automatically (the ViewModel is `@MainActor`), so leave them unchanged.
2. **WellnessPlanViewModel** — apply the identical `Task.detached(priority: .userInitiated) { … }.value` wrap at `:99` and `:165`, preserving each call's arguments.
3. **SavedPlansViewModel** — change `runRepairPass(on:)` (`:216`) to `private func runRepairPass(on plans: [RehabPlan]) async`. Inside the loop, wrap only the `ImageAvailabilityValidator.validate(...)` call (`:236`) in `let result = await Task.detached(priority: .userInitiated) { ImageAvailabilityValidator.validate(exercises: original.exercises, userConditions: [], userPainRegions: []) }.value`. Leave the `repairedThisSession.insert` (`:228`) BEFORE the await and the `updatePlan(...)` mutations (`:248`/`:257`) AFTER it on the main actor — do not move those off-main (they touch `@Published rehabPlans` + the Firestore SDK). Update the caller at `:113` to `await self.runRepairPass(on: parsed)` (it is already inside `Task { @MainActor }` at `:95`).
4. Rationale for wrapping the whole `validateRehabPlan`/`validate` call rather than just the resolver: `loadCatalog()`'s JSON re-decode (`:1004`) is a second main-thread cost in the same function; one seam moves both off-main, and the pipeline is a pure static func on a non-isolated `struct`.

**Do NOT** — do not touch `logMissingImages` (`RehabPlanViewModel.swift:769-785`) or `preloadImages` (`ExerciseImageService.swift:121`); both run after the cache is warm and are already O(1). Do not memoize/rewrite the catalog load or add caching inside `ExerciseImageService`/`ResponseValidationPipeline` (that is a deeper refactor out of this item's scope). Do not change substitution logic — output must be identical.

**Files to touch** — `ios/PT-Helper/PT-Helper/ViewModels/RehabPlanViewModel.swift`, `ios/PT-Helper/PT-Helper/ViewModels/WellnessPlanViewModel.swift`, `ios/PT-Helper/PT-Helper/ViewModels/SavedPlansViewModel.swift`. Anything else = STOP and mark BLOCKED.

**Acceptance criteria**
- [ ] `grep -rn "Task.detached" ios/PT-Helper/PT-Helper/ViewModels/RehabPlanViewModel.swift ios/PT-Helper/PT-Helper/ViewModels/WellnessPlanViewModel.swift ios/PT-Helper/PT-Helper/ViewModels/SavedPlansViewModel.swift` returns exactly 5 hits (2 + 2 + 1).
- [ ] `grep -n "func runRepairPass" ios/PT-Helper/PT-Helper/ViewModels/SavedPlansViewModel.swift` shows the signature ends in `async`, and `grep -n "await self.runRepairPass" ios/PT-Helper/PT-Helper/ViewModels/SavedPlansViewModel.swift` returns 1 hit.
- [ ] Build succeeds (no Sendable/actor-isolation errors).
- [ ] UnitPlan passes with no NEW failures vs. the 5fd0abb baseline (memory notes `RehabPlanViewModelTests/testGenerateRehabPlan_success_populatesPlan` fails on baseline too — a pre-existing failure there is not a regression).
- [ ] Manual instrument note: with a profile that has ≥1 saved plan whose exercises are cold, generate a plan while attached to Instruments (Time Profiler or Hangs); the main thread shows no `validateRehabPlan`/`resolveImageMatch`/`loadCatalog` frames. Record the before/after main-thread hang duration in the ledger.

**Verify**
```
xcodebuild build -project ios/PT-Helper/PT-Helper.xcodeproj \
  -scheme PT-Helper -destination 'platform=iOS Simulator,name=iPhone 16'

xcodebuild test -project ios/PT-Helper/PT-Helper.xcodeproj \
  -scheme PT-Helper -destination 'platform=iOS Simulator,name=iPhone 16'
```
(If `name=iPhone 16` resolves to an OS ≠ 18.2 and fails to launch, target the iPhone 16 sim by OS=18.2 or UDID — memory `project_build_simulator_destination`.)

**Depends on / Blocks** — nothing.

---

### [WS11-02] Stop recomputing ProgressTab chart/stat data every render
`P1` · `effort: S` · `risk: low — pure perf refactor; output values unchanged, screen pixel-identical`

**Problem** — `ProgressTab` recomputes O(sessions) work inside `body` on every render pass, over an unbounded `sessions` array: `filteredChartData` is evaluated twice per render, `averagePain`'s reduce runs twice per render, and a dead `totalMinutes` reduce lingers from a since-replaced stat card. Every `@Published` change on any injected EnvironmentObject re-runs `body`, so a long-history user pays 2 filters + 2 reduces per re-render for data that is identical within a render pass.

**Evidence** — verified at 5fd0abb:
- `Views/ProgressTab.swift:485-490` (`filteredChartData` — `:489` is an O(n) filter when a region chip is selected), consumed at `:325` (`painTrendAccessibilityValue`) and `:422` (`Chart(filteredChartData …)`) — two evaluations per render.
- `Views/ProgressTab.swift:570-574` (`averagePain` reduce), consumed at `:505` (stat card value) and `:577` (`averagePainColor`) — two evaluations per render.
- `Views/ProgressTab.swift:584-586` (`totalMinutes` reduce) — DEAD: `grep` confirms the only reference in the codebase is its own definition (the "Total Min" card was replaced by "Day Streak" per audit #38, `:506-511`).
- `Views/ThreeTabView.swift:55` (`ProgressTab` is the live Tab 2).

**Change spec**
1. Delete the dead `totalMinutes` computed property (`ProgressTab.swift:584-586`) outright — do not optimize it.
2. **averagePain → VM (matches "memoize into the VM" scope).** In `WorkoutViewModel` add `@Published private(set) var averagePain: Double = 0`. Recompute it wherever `sessions` is assigned: the Firestore path at `WorkoutViewModel.swift:41` (`self.sessions = …`) and the mock path at `:16` (`self.sessions = …`). Extract the existing reduce into a `private func recomputeDerivedStats()` that sets `averagePain = sessions.isEmpty ? 0 : sessions.reduce(0.0){ $0 + $1.painLevel } / Double(sessions.count)`, and call it immediately after each `sessions` assignment (also after the delete path if one mutates `sessions` — grep `self.sessions =` and cover every assignment). In `ProgressTab`, delete the `averagePain` computed var (`:570-574`) and change `:505` to read `workoutViewModel.averagePain`; update `averagePainColor` (`:576-582`) to switch on `workoutViewModel.averagePain`. Rationale: `averagePain` depends only on `sessions` (VM-owned), so it caches cleanly in the VM.
3. **filteredChartData → compute once per render, in-view (NOT the VM).** At the top of the `else` branch in `body` (after `:87`, before `regionFilterPicker` at `:89`), introduce `let chartData = filteredChartData`. Change `painTrendChart` to accept the array (`private func painTrendChart(_ data: [WorkoutSession]) -> some View`), have `cardChartContent` take and use it in `Chart(data, id: \.id)`, and pass the same array into the accessibility value (`painTrendAccessibilityValue(for: data)`). Keep `filteredChartData` itself as the single source (called exactly once now). Rationale: `filteredChartData` depends on `selectedRegion`, which is view `@State` (`:53`); hoisting it into a per-render `let` removes the double evaluation without dragging view state into the VM (a larger, out-of-scope refactor).

**Do NOT** — do not add a Firestore `.limit()` here (that behavior change is WS11-04). Do not restyle, relabel, or reorder any card — this item changes only computation frequency, not layout or values.

**Files to touch** — `ios/PT-Helper/PT-Helper/Views/ProgressTab.swift`, `ios/PT-Helper/PT-Helper/ViewModels/WorkoutViewModel.swift`. Anything else = STOP and mark BLOCKED.

**Acceptance criteria**
- [ ] `grep -n "totalMinutes" ios/PT-Helper/PT-Helper/Views/ProgressTab.swift` returns 0 hits.
- [ ] `grep -cn "filteredChartData" ios/PT-Helper/PT-Helper/Views/ProgressTab.swift` shows the property is referenced exactly once outside its own definition (one `let chartData = filteredChartData`).
- [ ] `grep -n "workoutViewModel.averagePain" ios/PT-Helper/PT-Helper/Views/ProgressTab.swift` returns ≥1 hit; `grep -n "private var averagePain" ios/PT-Helper/PT-Helper/Views/ProgressTab.swift` returns 0 hits.
- [ ] Build + UnitPlan pass with no new failures.
- [ ] Progress tab is pixel-identical to `ios/PT-Helper/docs/audit-assets-2026-07-17/progress-light.png` and `progress-dark.png` (same stat numbers, same chart, same Day-Streak card) with a seeded mock-data profile.

**Verify**
```
xcodebuild build -project ios/PT-Helper/PT-Helper.xcodeproj \
  -scheme PT-Helper -destination 'platform=iOS Simulator,name=iPhone 16'

xcodebuild test -project ios/PT-Helper/PT-Helper.xcodeproj \
  -scheme PT-Helper -destination 'platform=iOS Simulator,name=iPhone 16'
```
Visual compare: launch with `--uitesting --skip-onboarding --seed-mock-data`, screenshot Progress tab, diff against `progress-light.png`/`progress-dark.png`.

**Depends on / Blocks** — nothing. (Related: WS11-04 touches the same `WorkoutViewModel.fetchSessions`; land WS11-02 first to avoid a merge conflict in that file.)

---

### [WS11-03] Configure body-model collision shapes + proxies once on a cached template
`P2` · `effort: M` · `risk: MEDIUM — depends on clone(recursive:) preserving generated collision shapes, InputTargetComponent, and added proxy children; wrong-tap regressions are the failure mode`

**Problem** — `BodyModelCache` parses the 5.3 MB USDZ once but every `BodyMap3DView` creation deep-clones it and then, on `@MainActor`, regenerates convex-hull collision shapes per tappable region and rebuilds arm/leg/occluded zone proxies — identical work recomputed on every open. The collision shapes and zone proxies are pure functions of the (fixed) model geometry and the (static, hardcoded) region-key set, so they can be built once on the cached template and inherited by each clone.

**Evidence** — verified at 5fd0abb:
- `Services/BodyModelCache.swift:6` (`actor`), `:24-26` (parse-once + `entity.clone(recursive:true)` per `loadModel`), `:30` (`clear()` — grep confirms **zero callers**; the only `BodyModelCache` references anywhere are `loadModel` at `BodyMap3DView.swift:320` and the definition).
- `Views/BodyMap3DView.swift:316-332` (RealityView `make` closure: `loadModel` then `configureCollisionShapes` / `createProxyEntities` / `createArmZoneProxies` / `createLegZoneProxies` per open), `:814-842` (`@MainActor configureCollisionShapes`; `:831` `generateCollisionShapes(recursive:true)` per region; `:837` per-view `originalMaterials` capture), `:849-857` + `:905-912` + `:971` (proxy builders), `:1470-1483` (`applyRegionColor` — deterministic, color from `BodyMapConstants.regionColors`).
- `ViewModels/BodyMapViewModel.swift:64-65` (`loadRegions()` assigns a hardcoded static region list → `regionKeys` is constant across every presentation).
- `Views/ThreeTabView.swift:143` and `Views/AssessmentGatewayView.swift:24` (live presentation sites; `Views/MainTabView.swift:198` is legacy-flag only).

**Change spec**
1. **Split `configureCollisionShapes` (`:815`) into geometry vs. per-view material capture.** Create `configureTemplateGeometry(for parent:regionKeys:)` containing the current recursive walk EXCEPT the `originalMaterials[child.name] = mc.materials` line (`:837`): keep `InputTargetComponent` set, the `generateCollisionShapes(recursive:true)` branch (`:831`), and `applyRegionColor` (`:834`) — all deterministic. Add a separate `captureOriginalMaterials(from parent:regionKeys:)` that recursively walks a configured entity and does only `originalMaterials[child.name] = mc.materials` for region children (read-only; no shape generation).
2. **Add a `@MainActor` configured-template cache.** New file `Services/ConfiguredBodyModelCache.swift`: `@MainActor final class ConfiguredBodyModelCache { static let shared = ConfiguredBodyModelCache(); private var template: Entity?; private init() {} func configuredModel(regionKeys: Set<String>, buildTemplate: (Entity) -> Void) async throws -> Entity }`. Behavior: if `template != nil` return `template!.clone(recursive: true)`; else `let raw = try await BodyModelCache.shared.loadModel()`, run `buildTemplate(raw)` (which the view passes as a closure invoking `configureTemplateGeometry` + the three proxy builders), store `template = raw`, return `raw.clone(recursive: true)`. Keep this on `@MainActor` — do NOT move the RealityKit setup into the `BodyModelCache` actor (collision generation / `visualBounds` are main-actor-affined; the seed itself notes the rebuild is `@MainActor`).
3. **Rewrite the RealityView `make` closure (`:319-338`).** Replace the four per-open setup calls with `let entity = try await ConfiguredBodyModelCache.shared.configuredModel(regionKeys: regionKeys) { tpl in configureTemplateGeometry(for: tpl, regionKeys: regionKeys); createProxyEntities(for: tpl, regionKeys: regionKeys); createArmZoneProxies(for: tpl, regionKeys: regionKeys); createLegZoneProxies(for: tpl, regionKeys: regionKeys) }` then, per open, `captureOriginalMaterials(from: entity, regionKeys: regionKeys)`. Preserve the existing `entity.scale`, pivot, `content.add(pivot)`, `pivotEntity`/`bodyEntity`/`isLoading` assignments unchanged.
4. **Wire `clear()` to memory pressure.** In `configuredModel`, since the configured template supersedes the raw one for this screen, also clear it under memory pressure: register (once, in `ConfiguredBodyModelCache.init`) a `UIApplication.didReceiveMemoryWarningNotification` observer that sets `template = nil` and calls `await BodyModelCache.shared.clear()`. This gives the previously-dead `clear()` (`BodyModelCache.swift:30`) a real caller.

**Do NOT** — do not touch tap-hit resolution, gesture handlers, `originalMaterials`-based selection restore (`:1256`, `:1446-1456`), or `BodyMapConstants`. Do not change region definitions in `BodyMapViewModel`. Adjacent body-map correctness (RealityKit-push crash, arm zoning) is owned elsewhere — this item only relocates *when* setup runs, not the setup math.

**Files to touch** — `ios/PT-Helper/PT-Helper/Services/BodyModelCache.swift` (only if `clear()` needs `async`/access tweaks), `ios/PT-Helper/PT-Helper/Services/ConfiguredBodyModelCache.swift` (new), `ios/PT-Helper/PT-Helper/Views/BodyMap3DView.swift`. Anything else = STOP and mark BLOCKED.

**Acceptance criteria**
- [ ] `grep -rn "generateCollisionShapes\|createArmZoneProxies\|createLegZoneProxies\|createProxyEntities" ios/PT-Helper/PT-Helper/Views/BodyMap3DView.swift` shows each is invoked only from the template-build closure path, not the per-open per-view path.
- [ ] `grep -rn "BodyModelCache.shared.clear\|template = nil" ios/PT-Helper/PT-Helper/Services/ConfiguredBodyModelCache.swift` returns ≥1 hit (dead `clear()` now has a caller).
- [ ] Build passes; **FullPlan** passes (`BodyMapCollisionTests` live in FullPlan, excluded from UnitPlan per CLAUDE.md) with no new failures.
- [ ] Manual tap-through on simulator: open the body map (Assess → gateway), tap every region (head, neck, chest, abdomen, upper/lower back, both shoulders/arms/legs) and confirm each selects the correct region; close and reopen twice and re-verify — proves `clone(recursive:)` preserves collision shapes + proxies across opens.
- [ ] Body map is pixel-identical to `ios/PT-Helper/docs/audit-assets-2026-07-17/bodymap-light.png` / `bodymap-dark.png`.
- [ ] Manual instrument note: Time Profiler on a second body-map open shows the collision/proxy builders absent from the main thread (only the clone remains). Record before/after open-setup time.

**Verify**
```
xcodebuild build -project ios/PT-Helper/PT-Helper.xcodeproj \
  -scheme PT-Helper -destination 'platform=iOS Simulator,name=iPhone 16'

xcodebuild test -project ios/PT-Helper/PT-Helper.xcodeproj \
  -scheme PT-Helper -testPlan FullPlan -destination 'platform=iOS Simulator,name=iPhone 16'
```
Visual compare: launch, navigate Assess → body map, screenshot, diff against `bodymap-light.png`/`bodymap-dark.png`.

**Depends on / Blocks** — nothing.

---

### [WS11-04] Bound the workout-session Firestore fetch
`P3` · `effort: S` · `risk: low, but behavior-changing — a windowing cap changes what a >cap-session user's chart covers`

**Problem** — `WorkoutViewModel.fetchSessions` reads the entire `workoutSessions` collection with no `.limit()`, so a daily-workout user (~365+ docs/yr) fetches an ever-growing array on every launch — a Firestore read-cost/billing concern and the compounding factor behind WS11-02's O(sessions) render work. The Progress chart and stats only need a recent window.

**Evidence** — verified at 5fd0abb:
- `ViewModels/WorkoutViewModel.swift:23-28` (`fetchSessions` → `.order(by: "date", descending: true).getDocuments` with NO `.limit(...)`; `sessions` array unbounded).
- Consumers (`ProgressTab.swift` chart/stats) never page beyond what is fetched — a cap is safe for the current UI.

**Change spec**
1. Insert `.limit(to: 180)` between `.order(by: "date", descending: true)` (`:27`) and `.getDocuments` (`:28`). Chosen value + rationale: 180 ≈ six months of daily sessions — comfortably covers the pain-trend chart and all summary stats while capping read cost; the query is already `descending` by date so the 180 most-recent sessions are returned. Define it as `private static let sessionFetchLimit = 180` and use `.limit(to: Self.sessionFetchLimit)` so the window is named and greppable.
2. Do not add pagination or an "older sessions" affordance — the current UI has no consumer for it; that would be a feature, not this perf cap.

**Do NOT** — do not touch the two other `workoutSessions` queries (`WorkoutViewModel.swift:79`, `:121`) unless they also lack a bound and feed an unbounded array (they write/delete single docs — leave them). Do not change `SavedPlansViewModel.rehabPlansFetchLimit` — different collection.

**Files to touch** — `ios/PT-Helper/PT-Helper/ViewModels/WorkoutViewModel.swift`. Anything else = STOP and mark BLOCKED.

**Acceptance criteria**
- [ ] `grep -n "sessionFetchLimit\|.limit(to:" ios/PT-Helper/PT-Helper/ViewModels/WorkoutViewModel.swift` shows the constant `= 180` and its use inside `fetchSessions`.
- [ ] Build + UnitPlan pass with no new failures.
- [ ] With a seeded profile of <180 sessions, Progress tab is unchanged (pixel-identical to `progress-light.png`) — confirms the cap is inert for normal histories.

**Verify**
```
xcodebuild build -project ios/PT-Helper/PT-Helper.xcodeproj \
  -scheme PT-Helper -destination 'platform=iOS Simulator,name=iPhone 16'

xcodebuild test -project ios/PT-Helper/PT-Helper.xcodeproj \
  -scheme PT-Helper -destination 'platform=iOS Simulator,name=iPhone 16'
```

**Depends on / Blocks** — depends on WS11-02 only for merge ordering (same file, `WorkoutViewModel.swift`); no logical dependency.

---

### Dropped findings

- **S28 — UserDefaults full-dictionary prefix scan (REFUTED by V4, not a perf issue).** `GuidedWorkoutViewModel.clearAllLocalWorkoutState` does scan `UserDefaults.standard.dictionaryRepresentation()` (`GuidedWorkoutViewModel.swift:89-92`), but its only production caller is `SettingsView.swift:565` inside the account-deletion cleanup — it runs at most once per account lifetime, sandwiched between network-bound Firestore/Auth deletions that dwarf it. The hot-path familiarity counters (`:74-82`) use direct key access, not the scan, and dictionary-scan is the standard idiom for prefix-deleting unregistered dynamic keys (a key registry would add persistent state for no user-visible benefit). No change; the workstream's "indexed key list" sub-goal is intentionally not pursued.

## WS12: Backend/functions hygiene

**Scope (3 items).** (1) Close an exploitable client-callable AI request type (`nightly_report`) that admits free-form, schema-unfenced relay through the app's paid Anthropic key. (2) Restore a working, project-owned ESLint so the documented `npm run lint` command actually runs. (3) Extract the ~360 lines of inline system-prompt/model-config text out of `functions/src/index.ts` into a side-effect-free `src/prompts.ts` module, with tests proving byte-identical output and no key drift. All three live entirely under `functions/` — no iOS code changes.

**Shared context.** Everything runs against `functions/` at `5fd0abb`. Baselines verified this session: `npm run build` → exit 0 (regenerates `src/generated/exerciseCatalog.ts` via the `prebuild` step, then `tsc`); `npx jest` → 5 suites / **84 tests pass, 0 snapshots**; `npm run lint` → **fails today** (`sh: eslint: command not found`). Two Jest suites import from `../src/index` at module scope (`test/age.test.ts:8` → `computeAgeFromDob`; `test/rate-limit.test.ts:14` → `rateLimitWindowKey, RATE_LIMIT_MAX, isRateLimited`), so any refactor MUST keep `index.ts` compiling and re-exporting those four symbols unchanged. **No Jest test references `SYSTEM_PROMPTS`, `MODEL_CONFIG`, or `ALLOWED_REQUEST_TYPES`** (grep → zero matches in `test/`), so prompt-key drift or allow-list drift would pass the suite silently unless WS12-03 adds the parity tests below. `src/generated/exerciseCatalog.ts` (`EXERCISE_CATALOG_CSV`) is the existing precedent for a separate generated/data module — a sibling `prompts.ts` is the same low-risk pattern. **Deploy:** runtime-affecting items (WS12-01, WS12-03) do NOT take effect in production until `firebase deploy --only functions` runs against the target project — call this out to the human; WS12-02 is dev-tooling only and needs no deploy. **Correction to the seed brief:** the seed's proposed fix said to also drop `recovery_insights` from the client allow-list "because iOS never calls sendMessage with it." That is **REFUTED by code** — `RecoveryInsightsViewModel.swift:152-157` calls `apiService.sendMessage(requestType: .recovery_insights, …)` as the documented "Fallback: single-call recovery insights via claudeProxy," and `sendMessage` posts to `APIConfig.claudeProxyURL` (`ClaudeAPIService.swift:160-164`). `recovery_insights` therefore MUST stay client-allowed. Only `nightly_report` is orphaned (no client caller, scheduled-function-only).

---

### [WS12-01] Remove `nightly_report` from the client-callable request allow-list
`P1` · `effort: S` · `risk: allow-list is security-critical; an off-by-one in the type list would break a live client flow or re-open the hole — mitigated by the explicit 9-type literal + parity assertions.`

**Problem** — Any authenticated Firebase user can POST `{requestType:"nightly_report", messages:[{role:"user", content:"<≤10K chars>"}]}` to `claudeProxy` and it passes every guard, because the allow-list is derived from *all* `SYSTEM_PROMPTS` keys. `nightly_report` is one of the two types with no Zod response schema, so this is the only path through `claudeProxy` that returns raw, shape-unconstrained Haiku output — a free-form relay on the app's paid Anthropic key that bypasses the per-type JSON fencing every legitimate client type is subject to. Blast radius is bounded (no user/analytics data leaks — the nightly metrics are supplied by the scheduled function, not the prompt; abuse is capped by 20 req/min + per-user quota + global `AI_DAILY_BUDGET`), but it is a plainly exploitable misuse of the key that should not ship.

**Evidence** — (all verified at `5fd0abb`)
- `functions/src/index.ts:723` — `const ALLOWED_REQUEST_TYPES = new Set(Object.keys(SYSTEM_PROMPTS));` → the allow-list is *every* prompt key, including `nightly_report`.
- `functions/src/index.ts:832-836` — the ONLY `requestType` gate in `claudeProxy` (`if (!ALLOWED_REQUEST_TYPES.has(body.requestType))`); an exhaustive read of the handler (auth :785-800, rate-limit :805-809, budget :813-816, body :822-851, quota :874-894, minors :900-907, request build :902-941, response :976-1006) finds no downstream `nightly_report`-specific guard.
- `functions/src/index.ts:572` — `nightly_report:` is a `SYSTEM_PROMPTS` key; `:615` — its `MODEL_CONFIG` entry (haiku-4-5, 2048 tokens, temp 0.3).
- `functions/src/response-schemas.ts:173-181` + doc `:167-171` — `RESPONSE_SCHEMAS` deliberately omits `nightly_report` and `recovery_insights`; `validateClaudeResponse` passes their output through raw.
- `functions/src/index.ts:1492` — the scheduled `sendNightlyReport` reads `SYSTEM_PROMPTS.nightly_report` **directly** (not via `ALLOWED_REQUEST_TYPES`), so removing the key from the client allow-list does NOT affect the nightly job.
- `ios/PT-Helper/PT-Helper/Services/ClaudeAPIService.swift:68-76` — the iOS `AIRequestType` enum has **no** `nightly_report` case → no client flow sends it.

**Change spec** —
1. In `functions/src/index.ts`, **replace** line 723 (`const ALLOWED_REQUEST_TYPES = new Set(Object.keys(SYSTEM_PROMPTS));`) with an **explicit literal** of the 9 client-facing types (chosen approach: an explicit deny-by-default list is safer than "all keys minus X" because a future new server-only prompt key can't silently become client-callable):
   ```ts
   // Client-callable request types. Deny-by-default: server-only prompts
   // (e.g. nightly_report, used solely by the scheduled sendNightlyReport job)
   // are intentionally excluded so clients cannot relay through the paid key.
   const ALLOWED_REQUEST_TYPES = new Set<string>([
     "analysis", "analysis_verify", "rehab_plan", "exercise_substitute",
     "recovery_insights", "form_analysis", "wellness_analysis",
     "wellness_verify", "wellness_plan",
   ]);
   ```
   Keep `recovery_insights` IN the list — it is the live claudeProxy fallback for `RecoveryInsightsViewModel` (see shared-context correction).
2. Leave the gate at `:832-836` and the error message at `:834` untouched — it reads the new `ALLOWED_REQUEST_TYPES` and will now list 9 types.
3. Add a Jest guard in `functions/test/` (new file `test/allowed-request-types.test.ts`, or fold into WS12-03's `prompts.test.ts` if that lands first) asserting: (a) the allow-list has exactly 9 members; (b) it does NOT contain `nightly_report`; (c) every member is a key of `SYSTEM_PROMPTS` (no typo'd type that would 400 legitimately-listed clients). Import `ALLOWED_REQUEST_TYPES` — this requires exporting it: add `export` to the `const` at `:723`.

**Do NOT** — do not add a Zod response schema for `recovery_insights` or `nightly_report`, do not touch `RESPONSE_SCHEMAS` or the client-side `ShadowModeJSONParser` validation (residual-schema concern is out of scope), and do not modify the scheduled `sendNightlyReport` path. Do not delete the `nightly_report` entry from `SYSTEM_PROMPTS`/`MODEL_CONFIG` — the scheduled job still needs it.

**Files to touch** — `functions/src/index.ts`; `functions/test/allowed-request-types.test.ts` (new) OR `functions/test/prompts.test.ts` (if merged with WS12-03). Anything else = STOP and mark BLOCKED.

**Acceptance criteria** —
- [ ] `grep -n "Object.keys(SYSTEM_PROMPTS)" functions/src/index.ts` returns **0** matches (the derived allow-list is gone).
- [ ] `grep -c '"nightly_report"' functions/src/index.ts` — `nightly_report` appears only as a `SYSTEM_PROMPTS`/`MODEL_CONFIG` key and in the scheduled path, NOT in `ALLOWED_REQUEST_TYPES` (verify by reading the literal at ~723).
- [ ] New test asserts allow-list size === 9 and `.has("nightly_report") === false` and passes.
- [ ] `npx jest` → all suites pass (85+ tests; was 84).
- [ ] `npm run build` → exit 0.

**Verify** —
```bash
cd /Users/noyfisher/IOS-Projects/PT-Helper-Agent-v1/functions && npm run build && npx jest
grep -n "Object.keys(SYSTEM_PROMPTS)" src/index.ts   # must print nothing
```
No `npm run lint` leg here by design: WS12-01 is ordered *before* WS12-02 (which installs ESLint), so lint would fail today with `sh: eslint: command not found` and break copy-paste-runnability. Lint coverage on this file arrives with WS12-02; the omission is intentional, not an oversight.
Then (deploy — surface to human, do not run unprompted): `cd functions && firebase deploy --only functions` to close the hole in production.

**Depends on / Blocks** — Depends on nothing. Blocks nothing (do this first; it is the smallest and highest-priority change).

---

### [WS12-02] Restore a working, project-owned ESLint (config + devDependency + bounded fixes)
`P2` · `effort: M` · `risk: recommended rule set could surface a flood of violations and balloon the diff; capped by choosing a lean config + a hard remediation budget below.`

**Problem** — `npm run lint` has never worked: it fails with `sh: eslint: command not found` (reproduced at `5fd0abb` with `node_modules` installed). `eslint` is absent from `devDependencies`, no project ESLint config exists (the only `eslint.config.*` in the tree is `.codacy/tools-configs/eslint.config.mjs`, an untracked Codacy-CLI artifact — `git ls-files .codacy/` lists only `codacy.yaml`), and git history contains zero commits ever adding an eslint config or devDep. CLAUDE.md documents `npm run lint  # ESLint` as a real command, so the docs are currently wrong and there is no lint gate on functions code.

**Evidence** — (verified at `5fd0abb`)
- `functions/package.json` `scripts.lint` = `"eslint src/**/*.ts"`; `devDependencies` = `@types/jest, @types/node, jest, ts-jest, ts-node, typescript` — no eslint, no parser, no plugins.
- `ls functions/node_modules/.bin | grep -i eslint` → no binary (repro: `cd functions && npm run lint` → `sh: eslint: command not found`).
- `git log --oneline -- '*eslintrc*' 'eslint.config.*'` → empty; `git log -S '"eslint"' -- functions/package.json` → empty (never existed).
- `functions/src/index.ts:623` (`/* eslint-disable @typescript-eslint/no-unused-vars */`) and `:715` (`// eslint-disable-next-line @typescript-eslint/no-unused-vars`) — dead pragmas written for a linter that was never installed; they confirm the intended rule is `@typescript-eslint/no-unused-vars`. (Seed cited `:627/:721`; verified actual lines are `623/715`.)
- `grep -rn ': any\| as any\|<any>' functions/src` → **0** — no `no-explicit-any` violations to worry about; the recommended TS rule set should be quiet here.

**Change spec** — (chosen stack: ESLint 9 flat config + the `typescript-eslint` meta-package — the current canonical setup and what the `@typescript-eslint/*` pragmas already assume)
1. Add devDependencies to `functions/package.json`: `"eslint": "^9"`, `"typescript-eslint": "^8"`, `"@eslint/js": "^9"`. Run `npm install` in `functions/`.
2. Create `functions/eslint.config.js` (CommonJS — the package has no `"type":"module"`):
   ```js
   const js = require("@eslint/js");
   const tseslint = require("typescript-eslint");

   module.exports = tseslint.config(
     { ignores: ["lib/**", "src/generated/**", "scripts/**", "test/**"] },
     js.configs.recommended,
     ...tseslint.configs.recommended,
     {
       files: ["src/**/*.ts"],
       rules: {
         "@typescript-eslint/no-explicit-any": "off",
         "@typescript-eslint/no-unused-vars": ["error", { argsIgnorePattern: "^_", varsIgnorePattern: "^_" }],
       },
     },
   );
   ```
   Rationale for the ignores: `src/generated/exerciseCatalog.ts` is machine-generated (81 KB), `lib/` is build output, `scripts/`+`test/` are outside the `src/**/*.ts` lint target anyway. Use the non-type-checked `configs.recommended` (NOT `recommended-type-checked`) to keep lint fast and avoid needing `parserOptions.project`.
3. Change `scripts.lint` in `functions/package.json` from `"eslint src/**/*.ts"` to **`"eslint src"`** — directory mode lets the flat-config `files`/`ignores` govern which files are linted and avoids the ESLint-9 "file matched by CLI glob but ignored" warning that the old shell-expanded glob would trigger on `src/generated/`.
4. Run `npm run lint`. **Remediation budget (do not exceed):** for each violation, either (a) it is a trivial mechanical fix (remove an unused import, add `const`, prefix an intentionally-unused var with `_`) — fix it; or (b) it is noise for this codebase's style — disable that specific rule at config level with a one-line comment. If any violation indicates a **real runtime bug** (e.g. `no-fallthrough`, `no-constant-condition`, `no-dupe-keys`), STOP and flag it to the human rather than silently rewriting logic. **Total hand-edited source lines across all fixes must stay ≤ 30**; if the recommended set produces a larger cleanup, dial the offending rule to `"off"`/`"warn"` at config level instead and note it — this item is hygiene, not a refactor.
5. Confirm the two existing pragmas at `index.ts:623` and `:715` are now live (they suppress the intentionally-unused `_OUTPUT_SCHEMAS`/schema consts). Leave them.

**Do NOT** — do not touch `jest.config.js`, `tsconfig.json`, or any `.ts` logic beyond the ≤30-line remediation budget; do not add Prettier or a formatting pass; do not lint or reformat `test/`, `scripts/`, or `src/generated/`; do not edit CLAUDE.md (the documented command becomes correct once this lands).

**Files to touch** — `functions/package.json`, `functions/package-lock.json` (from `npm install`), `functions/eslint.config.js` (new), and up to ≤30 lines across existing `functions/src/*.ts` files for violation fixes. Anything beyond that = STOP and mark BLOCKED.

**Acceptance criteria** —
- [ ] `cd functions && npm run lint` → exit 0, zero errors.
- [ ] `test -f functions/eslint.config.js` → present; `node -e "require('./functions/eslint.config.js')"` → no throw.
- [ ] `grep '"eslint"' functions/package.json` → present in devDependencies.
- [ ] `git diff --stat` shows source-file line changes summing to ≤ 30 (excluding `package.json`/lockfile/new config).
- [ ] `npm run build` → exit 0 and `npx jest` → 84+ tests pass (no regression from the fixes).

**Verify** —
```bash
cd /Users/noyfisher/IOS-Projects/PT-Helper-Agent-v1/functions && npm install && npm run build && npm run lint && npx jest
```
(No `firebase deploy` — this item changes dev tooling only, not runtime code.)

**Depends on / Blocks** — Depends on nothing. Blocks nothing, but do it before/with the others so the workstream's shared test plan (`npm run build && npm run lint && npx jest`) can pass end-to-end; until it lands, the `npm run lint` leg fails for every item.

---

### [WS12-03] Extract system prompts + model config into a side-effect-free `src/prompts.ts` module
`P2` · `effort: M` · `risk: a dropped/renamed prompt key or a stray byte change is invisible to the current suite — fenced by the byte-frozen snapshot + key-parity tests specified below.`

**Problem** — `functions/src/index.ts` is 1996 lines, ~360 of which are inline template-literal prompt text and model config (`SYSTEM_PROMPTS`, `MODEL_CONFIG`, `AI_IDENTITY_LINE`, `MINOR_SAFETY_PROMPT`). This bloats the request-handler file, makes prompt review noisy, and — because no test references these symbols — a bad edit (dropped key, altered wording, allow-list drift) ships silently. Extracting them to a `prompts.ts` sibling (mirroring the existing `generated/exerciseCatalog.ts` pattern) and adding parity/byte tests fixes both the ergonomics and the silent-drift gap.

**Evidence** — (verified at `5fd0abb`)
- `functions/src/index.ts:263-264` — `AI_IDENTITY_LINE` const (interpolated into every prompt via `${AI_IDENTITY_LINE}` at lines 269,305,337,373,398,422,478,507,543).
- `functions/src/index.ts:266-602` — `SYSTEM_PROMPTS` literal, **10 keys** at :267 `analysis`, :303 `analysis_verify`, :335 `rehab_plan`, :371 `exercise_substitute`, :396 `recovery_insights`, :420 `form_analysis`, :476 `wellness_analysis`, :505 `wellness_verify`, :541 `wellness_plan`, :572 `nightly_report`; closes `};` at :602.
- `functions/src/index.ts:604-616` — `MODEL_CONFIG` (comment :604, const :605, close :616), same 10 keys.
- `functions/src/index.ts:737-743` — `MINOR_SAFETY_PROMPT` const.
- Consumers inside `index.ts`: `SYSTEM_PROMPTS` at :902 (claudeProxy), :1492 (scheduled nightly), :1704 (agent recovery), :1885 (agent form); `MODEL_CONFIG` at :903, :1493, :1705, :1886; `MINOR_SAFETY_PROMPT` at :923. (Plus :723 if WS12-01 hasn't yet replaced the derived allow-list.)
- `functions/src/generated/exerciseCatalog.ts:1-6` — precedent: `export const EXERCISE_CATALOG_CSV = …` imported into `index.ts`; separate-module pattern already proven.
- `functions/test/` — zero references to `SYSTEM_PROMPTS`/`MODEL_CONFIG` (grep); `age.test.ts:8` + `rate-limit.test.ts:14` import `../src/index` at module scope, so `index.ts` must keep compiling and keep exporting `computeAgeFromDob`/`rateLimitWindowKey`/`RATE_LIMIT_MAX`/`isRateLimited`.

**Change spec** — (byte-identical is proven mechanically via a Jest snapshot captured BEFORE the move, then re-verified after)
1. **First, freeze the baseline.** Create `functions/test/prompts.test.ts` importing `{ SYSTEM_PROMPTS, MODEL_CONFIG, MINOR_SAFETY_PROMPT }` **from `../src/index`** (their current home) and add:
   - `it("system prompts are byte-frozen", () => expect(SYSTEM_PROMPTS).toMatchSnapshot());`
   - `it("model config is byte-frozen", () => expect(MODEL_CONFIG).toMatchSnapshot());`
   - `it("minor safety prompt is byte-frozen", () => expect(MINOR_SAFETY_PROMPT).toMatchSnapshot());`
   These symbols must be `export`ed for the import to resolve — add `export` to the `const` declarations at `index.ts:266`, `:605`, `:737` (and `:263` `AI_IDENTITY_LINE` is NOT needed by tests; keep it internal).
   Run `npx jest prompts` once to generate `functions/test/__snapshots__/prompts.test.ts.snap` — this file is now a byte-exact record of the current prompt text. **Commit this snapshot as the frozen baseline.**
2. **Create `functions/src/prompts.ts`** (side-effect-free — no imports that run code, no disk reads, no `admin.*`). Move verbatim, preserving exact whitespace/newlines:
   - `AI_IDENTITY_LINE` (from :263-264),
   - `SYSTEM_PROMPTS` (from :266-602),
   - `MODEL_CONFIG` (from :604-616),
   - `MINOR_SAFETY_PROMPT` (from :737-743).
   Export all four with `export const`. Keep the `Record<...>` type annotations identical.
3. **In `index.ts`**, delete the four moved blocks and replace with `import { AI_IDENTITY_LINE, SYSTEM_PROMPTS, MODEL_CONFIG, MINOR_SAFETY_PROMPT } from "./prompts";` (omit `AI_IDENTITY_LINE` from the import if it is genuinely unused after the move — verify with a grep; it is only referenced inside the moved `SYSTEM_PROMPTS`, so index.ts will NOT need it — import only the three that index.ts consumes). Every consumer site (:902, :903, :923, :1492, :1493, :1704, :1705, :1885, :1886) keeps its identical `SYSTEM_PROMPTS[…]`/`MODEL_CONFIG[…]`/`MINOR_SAFETY_PROMPT` usage.
4. **Repoint the snapshot test:** change `prompts.test.ts`'s import from `../src/index` to `../src/prompts`. Re-run `npx jest prompts` — the three snapshots MUST still match (proves byte-identical move). If any snapshot fails, a byte changed during the move — fix the moved text, do NOT update the snapshot.
5. **Add key-parity assertions** to `prompts.test.ts` (guards the silent-drift gap the shared context flagged):
   - `Object.keys(SYSTEM_PROMPTS)` sorted deep-equals the sorted 10-key list `["analysis","analysis_verify","exercise_substitute","form_analysis","nightly_report","recovery_insights","rehab_plan","wellness_analysis","wellness_plan","wellness_verify"]`.
   - `Object.keys(MODEL_CONFIG)` sorted deep-equals the same 10.
   - cross-check: every key in `RESPONSE_SCHEMAS` (import from `../src/response-schemas`) is present in BOTH `SYSTEM_PROMPTS` and `MODEL_CONFIG` (i.e. every client-validated type has a prompt + a model config).
6. If WS12-01 is already merged, move its allow-list guard test into this file too (optional consolidation); otherwise leave WS12-01's test standalone.

**Do NOT** — do not alter one byte of prompt wording, whitespace, or key names (this is a pure move; behavior is byte-identical); do not move `RESPONSE_SCHEMAS`/`ANALYSIS_SCHEMA`/`_OUTPUT_SCHEMAS` or any Zod schema (those stay put — `response-schemas.ts` owns response validation); do not move the rate-limit/age functions or change their exports; do not add any import-time side effect to `prompts.ts` (two suites import `index.ts` transitively — a bad relative path or disk read would fail under Jest's cwd).

**Files to touch** — `functions/src/prompts.ts` (new), `functions/src/index.ts` (delete 4 blocks, add 1 import, add `export` on the 3 test-consumed consts), `functions/test/prompts.test.ts` (new), `functions/test/__snapshots__/prompts.test.ts.snap` (generated). Anything else = STOP and mark BLOCKED.

**Acceptance criteria** —
- [ ] `test -f functions/src/prompts.ts` → present; `grep -c "export const" functions/src/prompts.ts` → ≥ 4.
- [ ] `grep -n "SYSTEM_PROMPTS: Record\|MODEL_CONFIG: Record\|MINOR_SAFETY_PROMPT =" functions/src/index.ts` → **0** matches (definitions moved out); `grep -n 'from "./prompts"' functions/src/index.ts` → 1 match.
- [ ] The three `toMatchSnapshot` assertions pass against `../src/prompts` (byte-identical proven); the key-parity + RESPONSE_SCHEMAS cross-check assertions pass.
- [ ] `npx jest` → all suites pass (84 prior + new prompts suite); `Snapshots:` line shows 3 written/passed.
- [ ] `npm run build` → exit 0 (index.ts still compiles; age/rate-limit suites still import `../src/index` fine).
- [ ] `npm run lint` → exit 0 (requires WS12-02; `prompts.ts` passes the same rules).

**Verify** —
```bash
cd /Users/noyfisher/IOS-Projects/PT-Helper-Agent-v1/functions && npm run build && npm run lint && npx jest
# byte-identity + parity focus:
cd /Users/noyfisher/IOS-Projects/PT-Helper-Agent-v1/functions && npx jest prompts
grep -n "SYSTEM_PROMPTS: Record" src/index.ts   # must print nothing
```
Then (deploy — surface to human): `cd functions && firebase deploy --only functions`. Output is byte-identical, so this is a behavioral no-op — but the refactor still needs deploying to ship.

**Depends on / Blocks** — Depends on nothing functionally; **do after WS12-01** so the `ALLOWED_REQUEST_TYPES` line (`index.ts:723`) is touched only once. Soft-depends on WS12-02 for the `npm run lint` leg of its Verify block to pass. Blocks nothing.

---

_No P3 items skipped — all three items are in-scope and load-bearing._

## WS13: Test health + testability seams

**Scope (3 lines).** Convert the 12 `Task.sleep` waits (+ one fixed-delay `asyncAfter`) in the unit-test target to deterministic await/expectation patterns; add the ONE protocol seam a downstream workstream genuinely needs (NotificationService, for WS2) plus tests for the newly-wired NotificationService and ConsentService behavior; and add two post-merge integrity gates (SmokePlan refs after WS1; FullPlan/PreReleasePlan intent). No production behavior changes beyond two access-modifier relaxations and one protocol extraction; no `functions/src/` files; no UI, so no visual compare.

**Shared context (read once).** WS13 runs LAST — it verifies and hardens what WS1/WS2/WS3 land, so several items depend on those. Settled seam determinations from this session's audit (do not re-derive): (a) the injury/wellness analyzers can be awaited directly because their `Task` bodies make NO post-result singleton-network call — they use the injected `apiService` mock end-to-end (InjuryAnalysisViewModel.swift:171-227, WellnessAnalysisViewModel.swift:130-182); (b) `RehabPlanViewModel`'s task CANNOT be awaited to completion in a test because after it sets `rehabPlan` it awaits `CrossModelVerificationService.shared.verify` — a REAL singleton network call (RehabPlanViewModel.swift:208 → :333) that fires for the graph-unknown fixture exercises ("Exercise 1/2/3", TestFixtures.swift:265) — so its tests gate on the `$isGenerating` published flag instead; (c) `NotificationService` (UNUserNotificationCenter-bound) is the only WS-touched singleton that needs a protocol seam for call-site testability; (d) ConsentService needs NO production seam — its deterministic surface is `ConsentPolicy.needsLegalReacceptance` (pure) + UserDefaults-mirror reads, both testable against `.shared`; (e) WS8's singletons are already seam-ready — `NetworkMonitor.shared.isConnected` is a settable `@Published` (NetworkMonitor.swift:11; flipped at TestDataSeeder.swift:116) and `ClaudeAPIServiceProtocol` (ClaudeAPIService.swift:101) already abstracts the client — so WS13 adds no seam for WS8; WS5's correctness work is in `GuidedWorkoutViewModel`/`TimerViewModel` (not singletons) and needs a clock injection that is WS5's own concern. The three `Task.sleep` in MockClaudeAPIService.swift (:60/:91/:111) are the mock's intentional `simulatedDelay` — NEVER touch them. New test files auto-add via `PBXFileSystemSynchronizedRootGroup` (no pbxproj edits). Sim-destination caveat (from repo memory): if `-destination 'platform=iOS Simulator,name=iPhone 16'` fails to resolve, target the iPhone 16 sim by `OS=18.2` or its UDID — the CLAUDE.md commands are reproduced verbatim below regardless.

---

### [WS13-01] Convert the 12 `Task.sleep` VM waits (+ Timer fixed-delay) to deterministic await/expectation patterns
`P2` · `effort: M` · `risk: low — 2 access-modifier relaxations + test-only edits; no logic change`
**Problem** — Four VM test files burn ~6.7s of unconditional wall-clock per run sleeping for internal `Task`s to "probably" finish, and the fixed sleeps are flaky by design (a slow CI tick can miss the window, and auto-memory already records `RehabPlanViewModelTests/testGenerateRehabPlan_success_populatesPlan` as an intermittent baseline failure). Flaky/slow tests erode the build-gated-"done" safety net (protocol R3) and let real regressions hide behind timing noise.
**Evidence** — verified at 5fd0abb:
- `InjuryAnalysisViewModelTests.swift:329,348,367,407,414` — 5 × `try await Task.sleep(nanoseconds: 500_000_000)` after `vm.saveAndAnalyze(...)`/`vm.retryAnalysis()`.
- `RehabPlanViewModelTests.swift:196,212,227,242,256` — 5 × `try await Task.sleep(nanoseconds: 500_000_000)` after `vm.generateRehabPlan(...)`.
- `WellnessAnalysisViewModelRoutingTests.swift:31` — 1 × `try await Task.sleep(nanoseconds: 500_000_000)` after `vm.saveAndAnalyze(...)`.
- `TimerViewModelTests.swift:82` — `try await Task.sleep(nanoseconds: 1_200_000_000)` waiting on a real 1 s `Timer` tick; sibling `testTimerStopsAtZero` at :88-104 uses `DispatchQueue.main.asyncAfter(deadline: .now() + 3)` (fixed 3 s wall wait).
- `InjuryAnalysisViewModel.swift:19` / `WellnessAnalysisViewModel.swift:26` — `private var analysisTask: Task<Void, Never>?` (assigned :164 / :130) — private, so tests cannot await it.
- `RehabPlanViewModel.swift:171` — unretained `Task {` (no stored handle); sets `rehabPlan` at :186, `isGenerating=false` at :188, THEN awaits `performCrossModelVerification` (:208 → `CrossModelVerificationService.shared.verify` :333) — a real network call, so the whole task is NOT safe to await.
- `TimerViewModel.swift:5` — `@Published var timer: ExerciseTimer` (Combine-observable).
- `MockClaudeAPIService.swift:60,91,111` — intentional `simulatedDelay` sleeps — EXCLUDED.

**Change spec** —
1. Production (Injury/Wellness only): change `private var analysisTask` → `private(set) var analysisTask` at `InjuryAnalysisViewModel.swift:19` and `WellnessAnalysisViewModel.swift:26`. Rationale: `@testable import` exposes `internal` getters, so `private(set)` makes the task readable-but-not-settable from tests; the tasks are safe to await (context (a)). No RehabPlan/Timer production change.
2. Add test helper file `ios/PT-Helper/PT-HelperTests/Helpers/AsyncWaitHelpers.swift` with an `XCTestCase` extension that awaits a `@Published` publisher reaching a predicate (a `Published.Publisher` re-emits its current value on subscribe, so this fulfils immediately if the state is already satisfied and otherwise waits):
   ```swift
   import XCTest
   import Combine
   extension XCTestCase {
       /// Awaits until `publisher` emits a value satisfying `predicate`, else fails at `timeout`.
       func wait<P: Publisher>(for publisher: P, until predicate: @escaping (P.Output) -> Bool,
                               timeout: TimeInterval = 5) async where P.Failure == Never {
           let exp = expectation(description: "publisher satisfies predicate")
           var done = false
           let c = publisher.sink { value in
               if !done, predicate(value) { done = true; exp.fulfill() }
           }
           await fulfillment(of: [exp], timeout: timeout)
           c.cancel()
       }
   }
   ```
3. Injury (5 sites) — replace each `try await Task.sleep(nanoseconds: 500_000_000)` with `await vm.analysisTask?.value`. For the retry test (:407,414) both awaits stay: `startAnalysis()` reassigns `analysisTask` on retry, so each await targets the correct task. Method signatures already `async throws` — keep them.
4. Wellness (1 site, :31) — replace with `await vm.analysisTask?.value`.
5. RehabPlan (5 sites) — replace each sleep with `await wait(for: vm.$isGenerating, until: { $0 == false })`. Rationale: every assertion in these tests (`rehabPlan`, `generationError`, `rehabPlanWarnings`, `mock.sendMessageCallCount`) concerns state set BEFORE `isGenerating` flips false (RehabPlanViewModel.swift:186-188 / :274-276), which is BEFORE the cross-model network await — so gating on `$isGenerating` is both deterministic and network-free.
6. Timer (:82) — replace with `vm.start(); await wait(for: vm.$timer, until: { $0.timeRemaining < 300 }); XCTAssertLessThan(vm.timer.timeRemaining, 300); vm.stop()`. Also convert `testTimerStopsAtZero` (:88-104): replace the `asyncAfter`+`wait(for:timeout:)` block with `await wait(for: vm.$timer, until: { !$0.isRunning }, timeout: 5)` then the two existing assertions; make the method `async`.
7. Do not alter any test's assertions or the emergency/cancel tests that have no sleep.

**Do NOT** — do not add a stored `generationTask` to RehabPlanViewModel, do not restructure `performCrossModelVerification` into a detached task, and do not make TimerViewModel `@MainActor` (that is WS5's item).
**Files to touch** — `ios/PT-Helper/PT-Helper/ViewModels/InjuryAnalysisViewModel.swift`, `ios/PT-Helper/PT-Helper/ViewModels/WellnessAnalysisViewModel.swift`, `ios/PT-Helper/PT-HelperTests/Helpers/AsyncWaitHelpers.swift` (new), `ios/PT-Helper/PT-HelperTests/ViewModels/InjuryAnalysisViewModelTests.swift`, `ios/PT-Helper/PT-HelperTests/ViewModels/RehabPlanViewModelTests.swift`, `ios/PT-Helper/PT-HelperTests/ViewModels/WellnessAnalysisViewModelRoutingTests.swift`, `ios/PT-Helper/PT-HelperTests/ViewModels/TimerViewModelTests.swift`. Anything else = STOP and mark BLOCKED.
**Acceptance criteria** —
- [ ] `grep -rn "Task.sleep" ios/PT-Helper/PT-HelperTests/ViewModels/InjuryAnalysisViewModelTests.swift ios/PT-Helper/PT-HelperTests/ViewModels/RehabPlanViewModelTests.swift ios/PT-Helper/PT-HelperTests/ViewModels/WellnessAnalysisViewModelRoutingTests.swift ios/PT-Helper/PT-HelperTests/ViewModels/TimerViewModelTests.swift` returns **0**.
- [ ] `grep -n "asyncAfter" ios/PT-Helper/PT-HelperTests/ViewModels/TimerViewModelTests.swift` returns **0**.
- [ ] `grep -c "Task.sleep" ios/PT-Helper/PT-HelperTests/Mocks/MockClaudeAPIService.swift` still returns **3** (mock delays untouched).
- [ ] `grep -n "private(set) var analysisTask" ios/PT-Helper/PT-Helper/ViewModels/InjuryAnalysisViewModel.swift ios/PT-Helper/PT-Helper/ViewModels/WellnessAnalysisViewModel.swift` returns **2**.
- [ ] UnitPlan passes with the 4 converted classes green (no timeouts, no skips).
**Verify** —
```
xcodebuild test -project ios/PT-Helper/PT-Helper.xcodeproj \
  -scheme PT-Helper -destination 'platform=iOS Simulator,name=iPhone 16'
```
Then the full suite:
```
xcodebuild test -project ios/PT-Helper/PT-Helper.xcodeproj \
  -scheme PT-Helper -testPlan FullPlan -destination 'platform=iOS Simulator,name=iPhone 16'
```
**Depends on / Blocks** — Depends on nothing. Blocks nothing (independent of WS02/WS03).

---

### [WS13-02] Extract a `NotificationLifecycleScheduling` seam and test WS2's newly-wired notification behavior
`P2` · `effort: M` · `risk: low — protocol extraction + DI at WS2's call sites; production defaults to .shared`
**Problem** — Before WS2, `scheduleReminders(for:)` and `updateReminderTime(...)` had ZERO callers and the Settings toggles only logged analytics (audit finding #1: a no-op notification facade). WS2 wires them to the toggles and plan lifecycle, but with no seam there is no way to prove the wiring holds — a future edit could silently revert it to the facade with tests still green.
**Evidence** — verified at 5fd0abb:
- `NotificationService.swift:9-10` — `@MainActor class NotificationService: ObservableObject { static let shared = NotificationService() }` (private `init` :44).
- `NotificationService.swift:82` `scheduleReminders(for:)`, `:129` `cancelReminders(for:)`, `:135` `cancelAllReminders()`, `:150` `scheduleInactivityNudge()`, `:169` `cancelInactivityNudge()`, `:174` `updateReminderTime(hour:minute:plans:)` (5fd0abb signature; WS2-02 drops `plans:` → `updateReminderTime(hour:minute:)`, so the seam below lists the post-WS2 signature) — the lifecycle methods WS2 calls; all bound to `UNUserNotificationCenter.current()`.
- No existing test references `NotificationService` (`grep -rln NotificationService ios/PT-Helper/PT-HelperTests` → empty).
**Change spec** (this is a verify-and-harden item over WS2's wiring — the wiring already exists at execution time) —
1. In `NotificationService.swift`, declare `@MainActor protocol NotificationLifecycleScheduling` above the class. **Name deliberately distinct from WS2-01's center seam `NotificationScheduling`, which WS2-01 already declared in this same file (`protocol NotificationScheduling: AnyObject`, conformed by `UNUserNotificationCenter`) — reusing that name here would be an invalid redeclaration and a compile error.** List exactly the lifecycle methods WS2 invokes: `scheduleReminders(for:)`, `cancelReminders(for:)`, `cancelAllReminders()`, `scheduleInactivityNudge()`, `cancelInactivityNudge()`, `updateReminderTime(hour:minute:)` (post-WS2-02 signature — the `plans:` param was dropped). If WS2 added a reassessment-scheduling method, grep `func schedule` in `NotificationService.swift` and add that signature too. Conform the class: `class NotificationService: ObservableObject, NotificationLifecycleScheduling` — the method bodies already satisfy it, so this is a declaration-only change.
2. Map WS2's call sites: `grep -rn "NotificationService.shared.\(scheduleReminders\|updateReminderTime\|cancelReminders\|cancelAllReminders\|scheduleInactivityNudge\)" ios/PT-Helper/PT-Helper`. At each owning type, add a `let notifications: NotificationLifecycleScheduling` dependency defaulting to `NotificationService.shared` in its initializer, and route the call through it. Rationale: mirrors the existing `apiService: ClaudeAPIServiceProtocol = .shared` DI pattern already used across the VMs, so it is idiomatic and low-risk.
3. Add spy `ios/PT-Helper/PT-HelperTests/Mocks/MockNotificationScheduling.swift`: a `final class MockNotificationScheduling: NotificationLifecycleScheduling` recording per-method call counts and last arguments (e.g. `scheduledPlanIds: [UUID]`, `cancelledPlanIds: [UUID]`, `cancelAllCount: Int`). (Filename/class name do not collide with WS2-01's `MockNotificationCenter`, so they need no rename; only the conformance points at the renamed lifecycle protocol.)
4. Add `ios/PT-Helper/PT-HelperTests/Services/NotificationWiringTests.swift` (`@MainActor`). **Distinct filename by design: WS2-01 already created `NotificationServiceTests.swift` and WS2-02/WS2-03/WS2-04 appended to it — do NOT re-create or overwrite that file.** Assert the call-site wiring at WS2's trigger points using the spy — at minimum: (a) the plan-lifecycle trigger WS2 chose (e.g. activating/saving a plan) calls `scheduleReminders(for:)` with that plan's id; (b) turning the master/workout toggle off calls the cancel path; (c) the reminder-time change calls `updateReminderTime` with the new hour/minute. Discover the exact trigger surface from WS2's landed code; assert against the spy, never the real center.
**Do NOT** — do not seam `UNUserNotificationCenter` itself or test notification-content correctness (streak title / pluralization) here; do not change WS2's chosen trigger points or toggle semantics (WS2 owns those).
**Files to touch** — `ios/PT-Helper/PT-Helper/Services/NotificationService.swift`, the WS2 call-site files surfaced by the step-2 grep, `ios/PT-Helper/PT-HelperTests/Mocks/MockNotificationScheduling.swift` (new), `ios/PT-Helper/PT-HelperTests/Services/NotificationWiringTests.swift` (new — must NOT be WS2's `NotificationServiceTests.swift`). Any other file = STOP and mark BLOCKED.
**Acceptance criteria** —
- [ ] `grep -n "protocol NotificationLifecycleScheduling" ios/PT-Helper/PT-Helper/Services/NotificationService.swift` returns 1 (WS2-01's `NotificationScheduling` center seam is a separate declaration in the same file — do not conflate them); `grep -n "NotificationLifecycleScheduling" <each WS2 call-site file>` shows the injected property.
- [ ] `NotificationWiringTests` contains ≥ 3 test methods and all pass under UnitPlan.
- [ ] Reverting WS2's wiring (locally, as a smoke experiment) makes at least one `NotificationWiringTests` case fail — i.e. the tests actually guard the wiring.
**Verify** —
```
xcodebuild test -project ios/PT-Helper/PT-Helper.xcodeproj \
  -scheme PT-Helper -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:PT-HelperTests/NotificationWiringTests
```
Then UnitPlan + FullPlan (commands as in WS13-01).
**Depends on / Blocks** — Depends on **WS2** (its wiring must be landed to test). Blocks nothing.

---

### [WS13-03] Test ConsentService's newly-added withdraw path + policy/mirror contract (no production seam)
`P2` · `effort: S` · `risk: low — additive tests; UserDefaults key save/restore in setUp/tearDown`
**Problem** — WS3 adds the consent-withdraw path promised by `docs/CONSUMER_HEALTH_DATA_POLICY.md:37`, plus consolidates consent/ToS state onto `ConsentService`. None of ConsentService's decision surface is currently tested, so the new withdraw behavior and the re-acceptance/health-data gating could regress unnoticed.
**Evidence** — verified at 5fd0abb:
- `ConsentService.swift:10-11` — `@MainActor final class ConsentService: ObservableObject { static let shared = ConsentService() }`; `:32` `needsLegalReacceptance` (delegates to `ConsentPolicy`), `:40-43` `hasHealthDataConsent` (mirror key `consent.healthDataPolicyVersion` vs `LegalContent.healthDataPolicyVersion`), `:131-134` `static func clearLocalMirrors()`, mirror keys at `:23-24`.
- `ConsentPolicy.swift:5-8` — `static func needsLegalReacceptance(recordedVersion:currentVersion:) -> Bool { recordedVersion != currentVersion }` (pure; `currentVersion` injectable).
- `LegalContent.swift:14` — `static let healthDataPolicyVersion = "2026.07"`.
- No existing test references `ConsentService` (`grep -rln ConsentService ios/PT-Helper/PT-HelperTests` → empty).
**Change spec** —
1. No production change to ConsentService: its testable surface (`ConsentPolicy.needsLegalReacceptance`, `hasHealthDataConsent`, `clearLocalMirrors`, and WS3's withdraw method) reads/writes UserDefaults live and needs no seam. (Closed decision — the "does this already need a seam?" check: it does not.)
2. Add `ios/PT-Helper/PT-HelperTests/Services/ConsentServiceTests.swift` (`@MainActor`). In `setUp`/`tearDown`, snapshot and restore `UserDefaults.standard` keys `"consent.tosVersion"` and `"consent.healthDataPolicyVersion"` so the process-global store is left pristine.
3. Tests: (a) `ConsentPolicy.needsLegalReacceptance` truth table — nil→true, older version→true, `LegalContent.tosVersion`→false (pass `currentVersion:` explicitly to stay independent of the constant). (b) `hasHealthDataConsent`: set the mirror key to `LegalContent.healthDataPolicyVersion` → expect true; clear it / set a stale value → expect false. (c) `clearLocalMirrors()`: populate both mirror keys, call it, expect both `nil`.
4. Withdraw path (WS3's new behavior): grep `ConsentService.swift` for the WS3 withdraw method (e.g. `withdrawHealthDataConsent`). Assert that after calling it, `ConsentService.shared.hasHealthDataConsent == false` and the `"consent.healthDataPolicyVersion"` mirror key is cleared. Invariant this asserts on WS3: the mirror clear must be UNGATED by auth (so offline withdrawal works and is observable in a signed-out test); if WS3 gated it behind the `uid` guard, STOP and flag to WS3 rather than weakening the test.
**Do NOT** — do not add a Firestore/Auth mock or assert on the Firestore withdrawal record (no signed-in user in the unit target); do not implement the withdraw method itself (WS3 owns it); do not seam `UserDefaults` into ConsentService.
**Files to touch** — `ios/PT-Helper/PT-HelperTests/Services/ConsentServiceTests.swift` (new) only. Any production edit needed to make a test pass = STOP and mark BLOCKED (reconcile with WS3 first).
**Acceptance criteria** —
- [ ] `ConsentServiceTests` covers the four groups above (≥ 5 test methods) and passes under UnitPlan.
- [ ] A withdraw test exists and asserts `hasHealthDataConsent == false` post-withdraw.
- [ ] `defaults read` of the two `consent.*` keys is unchanged after the suite runs (tearDown restore verified — no test pollution).
**Verify** —
```
xcodebuild test -project ios/PT-Helper/PT-Helper.xcodeproj \
  -scheme PT-Helper -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:PT-HelperTests/ConsentServiceTests
```
Then UnitPlan + FullPlan (commands as in WS13-01).
**Depends on / Blocks** — Depends on **WS3** (withdraw method must exist). Blocks nothing.

---

### [WS13-04] Post-WS1 SmokePlan integrity gate
`P3` · `effort: S` · `risk: low — a verification pass; edits only if a ref actually broke`
**Current-behavior map** — `SmokePlan.xctestplan:22-34` hardcodes 11 class-qualified identifiers. Xcode does NOT error on a stale `selectedTests` entry — a renamed/removed test silently drops from the smoke run, shrinking coverage invisibly. Audit at 5fd0abb confirms all 11 resolve today and that **none** live in a WS1 deletion tree (they are model/VM/service unit tests), and WS13-01 renames none of them (it edits only sleep bodies, not the SmokePlan-referenced `testInitialState`, `testInitialState_SingleRegion`, `testSaveAndAdvance`, etc.). So the expected outcome is "still green, unchanged."
**Invariant to preserve** — SmokePlan executes exactly its 11 named tests after WS1 lands.
**Consolidation target** — none (do not restructure the plan); this is a guard.
**Change spec** —
1. Run SmokePlan (Verify block). Confirm the run reports **11 tests executed**, 0 skipped-because-missing.
2. For each identifier `Class/method()` in `SmokePlan.xctestplan:23-33`, confirm the method still exists: grep the file that declares `class Class` for `func method(`. If WS1 (or any prior WS) renamed/removed one, re-point the identifier to the current name; if the underlying test was intentionally deleted, replace it with the nearest equivalent smoke-level test in the same class and note the swap in the ledger.
3. If all 11 resolve unchanged, record "SmokePlan verified intact post-WS1" and touch nothing.
**Do NOT** — do not add/remove tests from the smoke set or change any other plan file; scope is the 11 existing refs only.
**Files to touch** — `ios/PT-Helper/SmokePlan.xctestplan` (only if a ref must be re-pointed). Otherwise no file changes.
**Acceptance criteria (prove-no-regression)** —
- [ ] SmokePlan run reports exactly **11** tests executed, all passing.
- [ ] Every identifier in `SmokePlan.xctestplan` maps to exactly one existing `func` (per the step-2 greps).
**Verify** —
```
xcodebuild test -project ios/PT-Helper/PT-Helper.xcodeproj \
  -scheme PT-Helper -testPlan SmokePlan -destination 'platform=iOS Simulator,name=iPhone 16'
```
**Depends on / Blocks** — Depends on **WS1** (deletions must be landed). Blocks nothing.

---

### [WS13-05] Document FullPlan vs PreReleasePlan intent
`P3` · `effort: S` · `risk: none — documentation only`
**Current-behavior map** — verified at 5fd0abb: `FullPlan.xctestplan` and `PreReleasePlan.xctestplan` declare identical `testTargets` (PT-HelperTests + PT-HelperUITests, no `selectedTests`/`skippedTests`). The ONLY differences are `PreReleasePlan` `codeCoverageEnabled: true` (:12) and `defaultTestExecutionTimeAllowance: 600` (:14) vs `FullPlan`'s 300 (:13, no coverage key), plus cosmetic config name/id. They are not accidental duplicates — Full is the fast pre-merge gate, PreRelease the thorough release gate — but that rationale lives nowhere in the repo, so the pair reads as redundant.
**Invariant to preserve** — both plans keep running all unit + UI + collision tests; do NOT delete either (both are referenced by CLAUDE.md and the scheme).
**Consolidation target** — a one-line intent note in CLAUDE.md's "Pre-Release Process" section (the existing test-plan sentence), making the distinction explicit rather than merging the plans.
**Change spec** —
1. In `CLAUDE.md`, extend the test-plan description so it reads that FullPlan is the **pre-merge gate** (all tests, no coverage, 300 s) and PreReleasePlan is the **release gate** (same tests + code coverage, 600 s) — i.e. they intentionally run identical targets and differ only by coverage + timeout. Keep it to one or two sentences.
2. Do not edit the `.xctestplan` JSON (no comment support).
**Do NOT** — do not delete, merge, or re-scope either plan; do not touch SmokePlan/UnitPlan wording (WS13-04 / not in scope).
**Files to touch** — `CLAUDE.md` only.
**Acceptance criteria** —
- [ ] `grep -n "pre-merge gate" CLAUDE.md` and `grep -n "release gate" CLAUDE.md` each return ≥ 1.
- [ ] Both `.xctestplan` files are byte-unchanged (`git diff --stat` shows only `CLAUDE.md`).
**Verify** — no build impact (docs only); confirm `git diff --name-only` lists only `CLAUDE.md`. Sanity-run the two plans are still loadable:
```
xcodebuild test -project ios/PT-Helper/PT-Helper.xcodeproj \
  -scheme PT-Helper -testPlan FullPlan -destination 'platform=iOS Simulator,name=iPhone 16'
```
**Depends on / Blocks** — Depends on nothing. Blocks nothing.

---

## Appendix A — Feature-bet briefs (explicitly NOT specced)

These are product bets, deliberately scoped out per **D-3**. Each is one paragraph of framing, not an implementation spec. Do not build them from this appendix — they exist to record why a tempting-looking gap was parked rather than fixed.

- **HealthKit import/export.** HealthKit is entirely absent from the codebase. A real integration would let COIL read weight/activity/heart-rate to seed the profile and write completed workouts back as mindful-minutes/workout samples, reducing onboarding friction and closing the loop with Apple's Fitness ecosystem. It is a bet, not a fix, because it needs new entitlements, a permissions-consent surface that intersects the MHMDA work (WS3), and a data-mapping model that does not exist — a multi-week effort with its own privacy review.

- **Rest-timer Live Activity.** After WS5-02 anchors the rest countdown to a wall-clock end-Date, the same end-Date could drive a Dynamic Island / Lock Screen Live Activity so users see the countdown without returning to the app. High delight, but it needs an ActivityKit widget extension, a new target, and background-update plumbing — infrastructure the app has never had. Park until the WS5 timer refactor is proven in production.

- **Home-screen widgets / App Intents.** A "today's plan" or "current streak" widget, and App Intents for "start my workout" from Siri/Spotlight, would extend COIL onto the Home Screen and into system search. This is a WidgetKit + AppIntents extension with its own data-sharing story (App Group container) — pure net-new surface area, not a repair of anything broken.

- **Form-clip retention + playback.** *(Gap-hunt #93 — CONFIRMED unresolved; disposition: Appendix-A bet.)* `FormAnalysisViewModel.analyzeVideo(url:exercise:)` opens with `defer { try? FileManager.default.removeItem(at: url) }` (FormAnalysisViewModel.swift:85-89), deleting the recorded clip the instant analysis finishes — before the results screen renders — so users can never review their footage alongside the AI feedback. A real feature would retain clips (with a retention/PHI policy, storage budget, and a playback UI that scrubs to flagged frames). Large, and it reopens the health-data-retention question, so it is a bet, not the small no-footage-accumulation invariant the current code deliberately preserves.

- **Localization.** The app is English-only with hardcoded UI strings throughout. Full localization (string catalogs, RTL layout, localized legal content, locale-aware date/number formatting) is a broad, mechanical-but-large effort touching nearly every view. Out of scope for a correctness/polish audit.

- **Richer data export.** Today export is a single rehab-plan PDF (PDFExportService). A richer story — full history export (sessions, assessments, pain trends) as CSV/JSON/PDF for the user or their clinician — is a data-portability feature that also dovetails with MHMDA data-access rights. Worth doing eventually; not a bug.

- **Per-day workout programming.** *(Open question resolved below — no repo evidence it is an intended feature.)* The Home date strip currently implies different exercises on different days, but every selectable day renders the identical `plan.exercises.prefix(8)` list (HomeTab `ProgramDayView`); `RehabPlan.weeklySchedule` only encodes which weekdays are workout-vs-rest, not per-day content. WS10 makes the strip honest (D-7). Genuine per-day *content* variation (different exercises assigned to different days, progression-aware) is a real product feature requiring a schema change and an AI-programming model — parked here, explicitly not built by WS10.

- **Structured wellness habits (server).** *(Gap-hunt #39 — CONFIRMED unresolved; disposition: Appendix-A bet.)* The `wellness_plan` server prompt says "Include a mix of exercises AND daily habits/micro-practices" (functions/src/index.ts:541,554-555) but the RESPONSE FORMAT JSON schema (index.ts:569-570) has only `planName/exercises/totalWeeks/notes` — no habits field — and the client decoder `AIWellnessPlanResponse` (WellnessPlanViewModel.swift:8) has none either. Delivering real structured habits needs a coordinated server prompt + schema change + client model + UI, plus a deploy — a feature bet, not a string tweak.

### Gap-hunt dispositions — deferred prior-audit items (state at `5fd0abb`)

Each prior deferred item was state-checked against current code and routed. `already-done` = fixed at source; `WSn item` = folded into a live workstream; `drop` = confirmed-unresolved but deliberately not pursued; `AppendixA bet` = above.

| Ref | Status | Disposition |
|---|---|---|
| #15 multi-region "Apply to All" hidden at end | PARTIAL — discoverability hint added (PainDetailView.swift:121-129, comment "audit #15"); original up-front toggle NOT built; the action button is still summary-only (PainWizardSteps.swift:194-208) | already-done |
| #16 forced two-tap zoom on 3D body map | CONFIRMED unresolved — overview taps always `drillIntoZone` first (BodyMap3DView.swift:1016-1037); no single-dominant-region shortcut (BodyZone.swift:54-58) | drop |
| #17 no skip/remove-region affordance mid-wizard | CONFIRMED unresolved — grep for Skip/skipRegion/abandon in PainDetailView.swift → zero hits | drop |
| #20 body map opens cold, no "same areas as last time" | CONFIRMED unresolved — still "No areas selected" on every open (BodyMap3DView.swift:272,749); no previousRegions/recentRegions | drop |
| #26 Dashboard shows raw confidence % | REFUTED as still-open — fixed at source (commit e2d670b deleted DashConfidenceChart.swift; DashDifferentialsTable.swift:59 uses `ConfidenceCalibrator.matchStrength`) AND the whole Dashboard tree is dead code (MainTabView.swift:13-20 `useDashboardUI` hardcoded false) | already-done |
| #33 Re-Assessment Prompts toggle no-op | PARTIAL — Inactivity Nudges now wired for real (NotificationService.swift:150-168 called from WorkoutViewModel.swift:100); Re-Assessment Prompts still a pure no-op (SettingsView.swift:204-210 logs analytics only; `reassessmentRemindersEnabled` has zero other readers) | **WS2-03** |
| #34 no first-workout / activation nudge | CONFIRMED unresolved, deliberately deferred — `git log -S '.scheduleReminders('` → zero callers ever; commit 9e9d223 lists it under "Deferred (need cross-cutting … plan-lifecycle wiring)" | **WS2-04** |
| #36 recovery digest evaporates on restart | CONFIRMED unresolved, explicitly deferred — RecoveryInsightsViewModel.swift:34-35 comment "In-memory only — resets on app restart"; no persistence/auto-generation; commit 9e9d223 deferred list | drop |
| #39 wellness plan promises habits, delivers exercises | CONFIRMED unresolved — server prompt vs schema mismatch (index.ts:541/569-570); client model has no habits field (WellnessPlanViewModel.swift:8) | AppendixA bet |
| #40 multi-goal wellness intake forces full 9-section form per goal | CONFIRMED unresolved — no Apply-to-all/shared/person-level/carryOver logic in WellnessDetailView.swift | drop |
| #41 saving a wellness plan dead-ends | CONFIRMED unresolved — WellnessPlanView.swift:24-28 alert has only a "Got it" cancel button; no "Start My First Workout" deep-link | drop |
| #42 wellness has no persistent re-entry card | CONFIRMED unresolved, and its precedent lives in dead code — the pain "Your Last Analysis" card #42 wanted a parallel of lives only in AssessTab.swift:105-119, which has zero live instantiation sites | **WS6 item** (pain side; wellness parallel remains a drop) |
| #44 wellness re-asks time commitment | CONFIRMED unresolved — CommitmentLevel (WellnessDetailView.swift:233-236) and SessionLength (WellnessResultView.swift:288-298) are two unreconciled selections | drop |
| #51 rest timer drifts / freezes backgrounded | CONFIRMED unresolved — GuidedWorkoutViewModel.swift:378-415 still a decrementing `Timer.publish` tick, not end-Date anchored; no scenePhase handling; elapsed timer (:424-431) confirms the Date-anchored fix template | **WS5-02** |
| #52 inter-set rest forced full-screen | CONFIRMED unresolved — both RestKind cases route through the same 220pt full-screen ring (GuidedWorkoutViewModel.swift:154-167, GuidedWorkoutView.swift:384-442); no inline chip | drop |
| #93 no clip review alongside form feedback | CONFIRMED unresolved (large bet) — clip deleted the instant analysis finishes (FormAnalysisViewModel.swift:85-89 `defer removeItem`) | AppendixA bet |

### Open questions — resolved from repo evidence

- **Is per-day workout programming an intended future feature, or should the Home date strip become an honest today-strip?** No repo evidence that per-day *exercise* programming is planned — grep of `ios/PT-Helper/docs/`, top-level `docs/`, and memory for "per-day"/"daily program"/"day-specific" turns up nothing outside the audit docs. Code confirms the strip is cosmetic: `HomeTab.ProgramDayView` (HomeTab.swift:249-303) renders the identical `plan.exercises.prefix(8)` list for every tapped date; only the header label changes. `RehabPlan.weeklySchedule: [[String]]` (RehabPlan.swift:14) encodes only which weekdays are workout-vs-rest (consumed by NotificationService reminders + RecoveryInsights adherence math) — `createWeeklySchedule` (RehabPlanViewModel.swift:671-696) assigns the SAME exercise-ID list to fixed weekdays, not per-day content. **Resolution:** D-7 commits the honest today-strip (WS10); true per-day content variation is a parked Appendix-A bet.

- **Where did the hardcoded preventative-care checklist (HomeTab:367-375) come from?** No design doc or PR rationale. Git pickaxe traces the exact 7-item list to a single commit e6c35fe ("fix(nav): dismiss assessment cover…", Jun 6 2026), whose message is entirely about a fullScreenCover bug and only mentions in passing that it "renames legacy HomeTab → LegacyHomeTab and wires the new HomeTab" — the checklist arrived wholesale, static, unpersonalized (identical for every user). A far more sophisticated AI-driven preventative system (BodyRiskAnalyzer, PostureCheckViewModel, DailySnackScheduler, ~4300 LOC, commit 9f0ab23) exists only on the unmerged `PreventativePTFeature` branch (`git merge-base --is-ancestor 9f0ab23 HEAD` → NOT ANCESTOR) and shares no literal item text with the checklist. **Resolution:** the checklist is an independently-authored placeholder; WS10-02 gates it on an active plan rather than deleting or enriching it.

- **Was the notification wiring (`scheduleReminders`) ever connected?** No — never, on any branch. `git log --all -S '.scheduleReminders('` returns zero commits adding a call site; the only bare-identifier hit is the commit that created NotificationService.swift (606debe, Mar 3 2026), which adds no caller. A later commit 9e9d223 wired ONE real notification (`scheduleInactivityNudge`, WorkoutViewModel.swift:100) and its message explicitly documents the rest as a conscious deferral: "Deferred (need cross-cutting … plan-lifecycle wiring or separate VM work): #33 reassessment reminders, #34 first-workout activation nudge, #36 recovery-digest persistence." **Resolution:** a documented to-do, not an intentional kill — supports D-8 (wire it via WS2).

- **Is there any existing dark/tinted app-icon or launch-screen asset?** No custom launch-screen asset exists, currently or historically — build settings use `INFOPLIST_KEY_UILaunchScreen_Generation = YES` (auto-generated blank; pbxproj:472,503), no storyboard or launch-image entries have ever existed. `AppIcon.appiconset/Contents.json` declares default/dark/tinted appearance slots, but all three point to the same `AppIcon.png`; commit f1c56e1 (COIL mark) regenerated only that one PNG. **Resolution:** matches the audit's P3 note; WS4-02 generates the dark/tinted icon variants and a branded launch screen from the existing flat-color icon.

---

## Appendix B — VERIFIED-GOOD / DO-NOT-TOUCH inventory

An anti-regression fence. These behaviors were verified correct at `5fd0abb`. Do NOT "improve", refactor, or "clean up" any of them while executing this spec — several are load-bearing templates the fixes above deliberately mirror.

### S5 — RestKind inter-set / inter-exercise routing (CONFIRMED correct)

The `RestKind` mechanism is present and correct. `enum RestKind` (GuidedWorkoutViewModel.swift:47-52) with published `restKind`/`restDuration` (:52-54); `completeSet` routes `.interExercise` at :159 and `.interSet` at :164-170 (inter-set rest capped at `min(restSeconds, 60)` :168-169); crucially `currentSet` is advanced (:166) and checkpointed (:167) **BEFORE** the inter-set rest starts, so `endRest`'s interSet branch correctly just returns to phase `.exercise` (:347-349), while the interExercise branch advances via `moveToNextExercise` (:350-351). The rest-phase UI keys off `restKind` for the correct "Up Next" preview (GuidedWorkoutView.swift:441-446). **CAUTION for WS5-01:** preserve the :166-167 ordering (set advanced *before* save) — the inter-set checkpoint path is the CORRECT template the inter-exercise path must mirror (advance state, then save). `skipRest` (:186-191) routes through the same switch, so skipping either rest kind lands correctly; inter-set kill-and-resume already behaves correctly (resumes on the next set, rest simply lost) — confirming the boundary bug is exclusive to the exercise-advance paths (WS5-01).

### S6 — Resume prompt + 24h checkpoint expiry (CONFIRMED correct)

The "Resume Workout?" prompt (GuidedWorkoutView.swift:63-88) and 24h checkpoint expiry (`savedCheckpoint`, GuidedWorkoutViewModel.swift:305-314, `86400` at :310) work correctly aside from WS5-01: `planId` is matched (:308), stale checkpoints return nil, "Start Fresh" clears (:82), restore rebuilds elapsed time correctly (accumulatedTime → totalElapsedTime, fresh `lastResumeTime`, :323-325) and clamps the index (:318). Three P3-grade notes (none blocking, do not fix here unless a routed item owns them): (1) `.workoutStarted` is logged in `onAppear` (:64) even when the resume prompt is about to show, so resumed workouts double-count as "started" alongside `.workoutResumed` (:76) — see Appendix D; (2) the checkpoint is a single global UserDefaults slot (`"GuidedWorkoutCheckpoint"`) — starting a workout on a different plan silently overwrites another plan's in-progress checkpoint on the first set completion; (3) `restoreFromCheckpoint` always lands at phase `.exercise` (:326) by design, which is exactly the surface WS5-01 exploits.

### Other verified-good subsystems (DO NOT TOUCH)

- **AI request-type parity 9/9** — the iOS `AIRequestType` enum and server `SYSTEM_PROMPTS`/`MODEL_CONFIG` client-facing keys line up exactly; no orphaned or missing client type.
- **Firestore rate limiting + billing shutoff + agent fallbacks** — `claudeProxy` enforces 20 req/min/user + per-user quota + global `AI_DAILY_BUDGET`; both Managed-Agent callers (recovery insights, form analysis) have a single-call fallback. Healthy; WS8/WS12 must not weaken these.
- **Force-unwrap hygiene** — no unsafe force-unwraps on the audited paths.
- **SavedPlansViewModel listener deinit** — the real-time Firestore listener is correctly torn down; do not re-add a deinit or double-remove.
- **JSON decode off-main** — response decoding already runs off the main thread where it matters; WS11 targets only the image-validation path, not this.
- **PHI file-protection in AnalysisResultStore** — the backing file uses `.completeFileProtection` (AnalysisResultStore.swift:30-38); preserve this when WS6 touches the store.
- **Adaptive dark-mode wiring** — the two-tier COIL token system resolves correctly in both appearances; no forced-light remnants remain on the audited surfaces (the dark-canvas *inconsistency* on two screens is a separate P3, Appendix C/D).
- **functions TypeScript typing + secrets** — `functions/src` is well-typed, secrets are clean, no deploy drift; WS12's prompt extraction must be byte-identical and must not disturb the rate-limit/age exports two Jest suites import.

---

## Appendix C — Screenshot inventory

Simulator visual pass: **complete**. 37 PNGs captured, covering 16 of 17 matrix screens in light/dark plus Dynamic-Type-XL spot checks. All files live in `/Users/noyfisher/IOS-Projects/PT-Helper-Agent-v1/ios/PT-Helper/docs/audit-assets-2026-07-17/` (the **Path** column below is the basename). Ratios are pixel-sampled estimates (2nd/98th percentile of tight text crops) — treat as ±0.2.

| Screen | Mode | Path | Issues |
|---|---|---|---|
| IntroCarousel p1 | light | intro1-light.png | White status-bar strip above dark hero (safe area not painted in light mode); red/maroon radial glow reads off-palette vs teal COIL brand |
| IntroCarousel p1 | dark | intro1-dark.png | Clean — status bar blends in dark |
| IntroCarousel p2 | light | intro2-light.png | Same white status-bar strip; page indicator (01/03) missing on this page; large empty vertical space |
| IntroCarousel p3 | light | intro3-light.png | Page indicator jumps to center-above-title (pages 1-2 have bottom-left bars) — inconsistent placement |
| Login | light | login-light.png | Hero background shows hard vertical/horizontal seams between gradient panels; screen forces dark by design (light capture identical to dark) |
| Login | dark | login-dark.png | — |
| Onboarding step 1 (About You) | light | onboarding1-light.png | Text-field placeholders nearly invisible (1.10:1); privacy caption crowds/overlaps CONTINUE glow; copy "keep dosing safe" odd for a PT app; "Skip" and "1/6" stack awkwardly |
| Onboarding step 1 (About You) | dark | onboarding1-dark.png | Forces dark scheme; identical to light capture |
| Home tab | light | home-light.png | Copy bug "3 sets · 30 seconds reps"; Wall Sits/Clamshells share the same side-bend illustration, Straight Leg Raises shows a barbell-deadlift icon; ACTIVE PLAN chip white-on-teal 2.54:1 |
| Home tab | dark | home-dark.png | Adapts correctly; dark-green thumbnails lose some contrast on dark circles (minor) |
| Home tab | dynamictype-xl | home-dynamictype-xl.png | Calendar weekday labels truncate (WED→"W…", MON→"M…"); everything else scales without clipping |
| Plan tab (MyPlan) | light | plan-light.png | Grammar "1 exercises"; both seeded plans show ACTIVE badge simultaneously |
| Plan tab (MyPlan) | dark | plan-dark.png | Injury/Wellness segmented control selected state renders muddy gray instead of white/teal |
| Plan detail (RehabPlanView) | light | plandetail-light.png | Page background stays DARK in light mode (white cards on dark) while sibling Plan list is light — inconsistent two-tone; "Beginner" green-on-pale-green chip 3.91:1 |
| Plan detail (RehabPlanView) | dark | plandetail-dark.png | — |
| Progress tab | light | progress-light.png | Pain-trend chart axis labels light teal #87DAD7 on white ≈1.61:1 — hardest contrast failure found |
| Progress tab | dark | progress-dark.png | Chart and stat cards adapt correctly |
| Profile tab (top of Settings) | light | profile-light.png | Profile tab IS the Settings screen (title "Settings" + modal "Done" on a tab); dark page background in light mode; user name "Test" set in serif font — off brand |
| Profile tab (top of Settings) | dark | profile-dark.png | — |
| Settings (scrolled) | light | settings-light.png | "Image Diagnostics (DEBUG)" teal-on-white 2.54:1 (DEBUG-gated, release-safe); Delete Account row uses default dark label with red icon — destructive action not styled destructively |
| Settings (scrolled) | dark | settings-dark.png | — |
| Settings | dynamictype-xl | settings-dynamictype-xl.png | Scales gracefully, no clipping |
| Assessment gateway (center +) | light | gateway-light.png | Bottom ~55% empty (cards top-anchored); "GET STARTED" teal-on-white CTA 2.54:1; no re-entry to a previously completed analysis (net-new P1) |
| Assessment gateway (center +) | dark | gateway-dark.png | "Something Hurts" card loses dark-vs-white differentiation from the wellness card (both dark) |
| BodyMap3D | light | bodymap-light.png | 3D viewport renders as a flat mid-gray slab clashing with light page bg (visible seams); "No areas selected" appears twice; RealityKit rendered fine as fullScreenCover root (no crash) |
| BodyMap3D | dark | bodymap-dark.png | Viewport blends seamlessly in dark — light mode should match this treatment |
| Guided workout active | light | workout-light.png | "30 seconds reps" chip copy; "Wall Sits" title in serif; generic side-bend illustration for a wall sit; "Set 1/3" teal chip 2.13:1 |
| Guided workout active | dark | workout-dark.png | — |
| Guided workout REST countdown | light | workoutrest-light.png | Huge teal countdown digits on light bg 2.32:1 (below even the 3:1 large-text bar) |
| Guided workout REST countdown | dark | workoutrest-dark.png | Dark version is excellent |
| WellnessGoalPickerView | light | wellnesspicker-light.png | Goal icons use multicolor pastel circles (lavender/peach/blue/pink) — drifts from teal system palette |
| WellnessGoalPickerView | dark | wellnesspicker-dark.png | Pastel icon circles turn to murky desaturated discs in dark — icon tint barely visible |
| HealthDataConsentView (pre-onboarding) | light | healthconsent-light.png | "Your Health Data" serif heading; green gear icon off-palette; withdraw-consent contact is a personal Gmail; disabled Continue is pale teal w/ white text (very low affordance) |
| HealthDataConsentView (pre-onboarding) | dark | healthconsent-dark.png | — |
| Privacy Policy (LegalDocumentView via Settings) | light | legalprivacy-light.png | Raw markdown rendered literally ("# Privacy Policy", "## Overview", "###" visible as text); old brand name "PT Helper" throughout |
| Privacy Policy (LegalDocumentView via Settings) | dark | legalprivacy-dark.png | Same raw-markdown + old-brand issues |

### Net-new findings (surfaced by the visual pass)

- **P1 — Completed AI analysis is unreachable in the FloatingTabBar shell (F2 regression).** The "Your Last Analysis" re-entry card (AssessTab.swift ~line 105, explicitly commented as the F2 fix) lives only in AssessTab, which has ZERO references in the current shell. ThreeTabView's `assessmentDestination` presents only AssessmentGatewayView / BodyMap3DView / WellnessGoalPickerView, and the gateway shows just the two path cards. `AnalysisResultView` is otherwise reachable only transiently from AnalyzingView right after a run — so once the user leaves the result screen, the seeded/persisted analysis can never be viewed again. Verified on-device. → **WS6.** (evidence: AssessTab.swift, ThreeTabView.swift, gateway-light.png)
- **P2 — Legal documents render raw markdown and retain "PT Helper" branding.** LegalDocumentView shows LegalContent markdown as literal text (visible hash marks) and the body says 'PT Helper ("the App")'. Affects Privacy Policy and (shared view) presumably ToS + Consumer Health Data Policy. → rename is **WS4-03** (D-2 legal-gated); raw-markdown rendering is a content/polish follow-up. (evidence: legalprivacy-light.png / -dark.png)
- **P2 — Light-mode teal accent fails WCAG wherever used as text/fill on light backgrounds.** Systemic token-level issue: accent #0FB5B0 on white = 2.54:1 (GET STARTED, Image Diagnostics, ACTIVE PLAN chip); chart-label teal #87DAD7 on white = 1.61:1 (worst); "Set 1/3" chip 2.13:1; rest-timer digits 2.32:1. Dark mode passes everywhere (teal-on-dark 6.8:1). Fix belongs in DesignSystem.swift (a darker accent-on-light token like the ~#0B7A78 already used by the Start Guided Workout button, 5.16:1). → **WS7.**
- **P2 — Onboarding placeholders invisible (1.10:1) and caption collides with CONTINUE.** "First Name"/"Last Name (optional)"/"Enter weight" placeholders measure ~1.10:1 against their field fill (#1C292D on #262F34); the privacy caption sits under the weight field overlapped by the CONTINUE glow; "keep dosing safe" is odd copy. → onboarding polish (see WS7 skipped list). (evidence: onboarding1-light.png)
- **P2 — Intro carousel leaves a white status-bar strip in light mode.** All three pages are dark-hero but in light appearance the top safe area renders white; dark mode is seamless. → **WS4-01.** (evidence: intro1/2-light.png, intro1-dark.png)
- **P3 — Light-mode page-background inconsistency.** Home/Plan/Progress use a light body under the dark header, but RehabPlanView and Profile/Settings render a fully dark page with white cards. → design-system normalization (WS7 skipped / follow-up). (evidence: plandetail-light.png, profile-light.png, home-light.png)
- **P3 — Exercise illustrations: generic fallback icons and duplicates despite the 1364-image library.** Wall Sits and Clamshells share a side-bend figure; Straight Leg Raises shows a barbell deadlift. Either ExerciseImageService fuzzy matching misses these canonical names for the seeded plan or the seeded mock bypasses the real pipeline. → images follow-up. (evidence: home-light.png, workout-light.png)
- **P3 — Serif font intrusions break the sans-serif brand type ramp.** Profile display name "Test", guided-workout title "Wall Sits" (+ rest Up-Next card), and consent heading "Your Health Data" render serif. → normalize in **WS9**. (evidence: profile-light.png, workout-light.png, healthconsent-light.png, workoutrest-light.png)
- **P3 — Assorted copy/polish:** "3 sets · 30 seconds reps" (seconds pluralized as reps); "1 exercises"; both seeded plans carry ACTIVE badges; body map "No areas selected" twice; XXXL weekday truncation; BodyMap3D flat mid-gray viewport in light; login hero gradient panel seams. → polish backlog. (evidence: home-light.png, plan-light.png, bodymap-light.png, home-dynamictype-xl.png)

### Contrast checks (pixel-sampled)

| Site | Measured | Verdict |
|---|---|---|
| Progress pain-trend chart axis labels (teal #87DAD7 on white) | 1.61:1 | FAIL (needs 4.5:1; worst of the audit) |
| Onboarding About You field placeholders (#1C292D on #262F34) | 1.10:1 | FAIL (effectively invisible) |
| Guided workout "Set 1/3" teal chip text on pale-teal chip | 2.13:1 | FAIL (needs 4.5:1) |
| Rest countdown teal timer digits on light bg | 2.32:1 | FAIL (large text, still below 3:1) |
| Assessment gateway "GET STARTED" teal CTA on white (accent #0FB5B0) | 2.54:1 | FAIL (needs 4.5:1) |
| Settings "Image Diagnostics (DEBUG)" teal on white | 2.54:1 | FAIL (DEBUG-only, low ship risk) |
| Home "ACTIVE PLAN" white text on teal chip | 2.54:1 | FAIL (needs 4.5:1) |
| Plan detail "Beginner" green on pale-green chip | 3.91:1 | FAIL for small text (passes 3:1 large-text bar) |
| Home "3 exercises" secondary gray on light bg | 3.28:1 | FAIL for small text |
| Plan tab date line gray on white card | 3.59:1 | FAIL for small text (marginal) |
| Home "START GUIDED WORKOUT" white on dark-teal button (#0B7A78) | 5.16:1 | PASS (use this darker teal as the accent-on-light token) |
| Assessment gateway "START ASSESSMENT" teal on dark card | 6.84:1 | PASS |
| Intro p1 gray tagline on dark hero | 6.91:1 | PASS |

### Environment notes

Coverage: 16 of 17 matrix screens (37 PNGs). **SKIPPED:** (14) `AnalysisResultView` — unreachable in the current FloatingTabBar shell (see P1 net-new; the only re-entry card lives in dead AssessTab; the legacy dashboard path is `--use-legacy-ui`-only). (17) `QuickHealthUpdateView` — presented only from AssessTab (dead) and legacy MainTabView; Settings' "Update Health Info" opens the profile editor instead. HealthDataConsentView was captured in-app (it gates the `--uitesting` onboarding path) rather than via `--showcase`. Intro pages 2-3 captured light-only (page 1 has both; renders identically dark). Login and Onboarding force `.dark` by design, so their light/dark pairs are intentionally identical. During the run an iOS "Apple Account Verification" system dialog appeared over the first Home capture and was dismissed via "Not Now" (no credentials entered); RealityKit body map rendered fine in the real flow (no crash); the guided workout was ended via "Discard Without Saving" so no checkpoint remains; the body-map coach mark and the uitesting user's consent checkboxes were consumed during the run. Simulator restored to appearance=light, content_size=medium; app left installed at the coil-rebrand build (COIL v1.0 (14)).

---

## Appendix D — Unrouted / unverified findings parking lot

P3s, extra findings without a home, and cross-references. One line each. No UNVERIFIED seeds were left over (the verification wave resolved every seed to CONFIRMED / REFUTED / REFRAMED). Most items below are already routed to a workstream — the routing is noted so nothing is silently lost.

- **P3 — `preventiveTasks_*` UserDefaults keys survive account deletion and grow unboundedly.** `clearAllLocalUserData` (SettingsView.swift:558-570) enumerates every other local store but not `preventiveTasks_*` (written per-date at HomeTab.swift:450,455). 3-line prefix-scan fix mirroring `clearAllLocalWorkoutState`. → **routed: WS10-03.**
- **P3 — TimerView + TimerViewModel are dead code.** Zero call sites app-wide (TimerView.swift; only consumers of TimerViewModel are TimerView + its test). Deleting the trio also resolves the sole missing-`@MainActor` ViewModel without a code change. → **routed: WS5-04.**
- **P3 — Resumed workouts double-count in analytics as new starts.** `.workoutStarted` fires unconditionally in `onAppear` (GuidedWorkoutView.swift:64) before the resume prompt resolves, so every resume emits both `.workoutStarted` and `.workoutResumed` (:76), inflating start→completion funnels. Defer the `.workoutStarted` log to the Start-Fresh / no-checkpoint branch. → suggested **WS5** (same onAppear block; not yet a spec item — flag to WS5 owner).
- **P2 — Sign-out leaves last-analysis PHI file on device (cross-account landmine).** RootView sign-out (RootView.swift:72-85) clears profile/consent/draft but never `AnalysisResultStore.clear()`; account deletion does (SettingsView.swift:562). Latent until WS6-01 ships a live reader. Same gap applies to GuidedWorkout checkpoints and SeriousWarningAcknowledgements (also deletion-only cleanups). → **routed: WS6-02.**
- **P3 — FCM push pipeline is a dead end.** Client uploads every user's FCM token to Firestore (NotificationService.swift:186-222) and carries a full deep-link machine (PT_HelperApp `userInfo["tab"]` → ThreeTabView routing table :157-169), but no Cloud Function ever sends a push (grep of functions/src for messaging/fcm → zero), and local notifications set no `tab` userInfo. Either ship a sender or stop uploading tokens (a privacy win). → decide in **WS2** (push-vs-local strategy).
- **P3 — Health-data consent has no decline path — a hard wall for new users.** HealthDataConsentView (HealthDataConsentView.swift:81-104) offers only Continue (disabled until both boxes ticked, `interactiveDismissDisabled`), presented as an undismissable fullScreenCover before Skip-onboarding is reachable (OnboardingView.swift:129-135). MHMDA consent must be freely given; the three in-context gates already demonstrate the better pattern. → partially addressed by **WS3-01** (adds a "Sign out instead" option); the broader product/legal decision is flagged, not yet specced.
- **P3 — `--showcase` harness compiles into and is reachable in RELEASE builds.** PT_HelperApp.swift:31 checks the arg with no `#if DEBUG` guard, unlike every `TestDataSeeder` flag (DEBUG-gated per the rationale at TestDataSeeder.swift:8-12). Moot once **WS1-02** deletes it; if that deletion slips past a release, wrap the conditional in `#if DEBUG` in the interim. → **routed: WS1-02.**
- **P2 — Stale-profile health-check feature is unreachable from the live shell.** The "3+ months inactive → re-check profile before assessing" feature lives only on dead paths: `UserProfileService.monthsSinceLastActivity()` (:81) is called only from legacy MainTabView + zero-caller AssessTab; HealthCheckPromptView/QuickHealthUpdateView instantiate only from dead code. Returning users now run AI analyses against stale health data with no re-confirmation. **Product decision needed before the dead-code sweep:** rewire into ThreeTabView or consciously delete. → surfaces during **WS1-05/06** (blocking product decision, flag to owner).
- **P2 — `WorkoutViewModel.fetchSessions` reads ALL workout sessions with no query limit.** No `.limit(to:)` / pagination (WorkoutViewModel.swift:26-28), unlike rehabPlans (capped at 50). Grows unbounded in read billing/memory and amplifies ProgressTab per-render costs. → **routed: WS11-04** (adds `.limit(to: 180)`).
- **P3 — `ImageAvailabilityValidator` re-decodes the bundled catalog JSON on every validate call.** `loadCatalog()` (ResponseValidationPipeline.swift:980-1004) re-reads/decodes ~1225 entries per call, synchronously on main, though ExerciseImageService already holds it decoded (ExerciseImageService.swift:624-646). Up to 6 redundant decodes on a cold start. → related to **WS11-01** (moving validation off-main mitigates the main-thread cost; a static cache is the deeper fix, noted for WS11 owner).
- **P3 — `BodyModelCache.clear()` is dead — promised memory-warning eviction never wired.** `clear()` (BodyModelCache.swift:29-32) has zero callers despite its comment. → **routed: WS11-03** gives it a real caller (memory-warning observer).
- **Visual net-new findings (F2 regression, legal raw-markdown/branding, light-mode teal contrast, onboarding placeholders, intro white strip, dark-canvas inconsistency, exercise-illustration duplicates, serif intrusions, assorted copy/polish)** are catalogued in full in **Appendix C** with routing (WS6 / WS4 / WS7 / WS9 / polish backlog). Not duplicated here.
