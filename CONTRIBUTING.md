# Contributing to COIL

## Prerequisites

- **Xcode 16+** — the project uses `PBXFileSystemSynchronizedRootGroup`, so new
  Swift files are auto-discovered and no `.pbxproj` edits are needed
- **iOS 18.2 deployment target** — an iPhone 16 simulator on iOS 18.2 is the
  reference device
- **Node 22** for the Cloud Functions (`functions/package.json` `engines`)
- **Firebase CLI** (`npm install -g firebase-tools`)
- **Ruby + bundler** — only for fastlane (`ios/PT-Helper/Gemfile`); not needed to
  build or test the app
- **Python 3** for the exercise-image pipeline in `scripts/`
  (`scripts/requirements.txt`)

Getting the app running: clone, open `ios/PT-Helper/COIL.xcodeproj`, drop your
`GoogleService-Info.plist` into `ios/PT-Helper/COIL/`, build and run.

## Where things live

- `ios/LAYOUT.md` — the iOS file map: every Model, ViewModel, View, Service and
  test file with a one-line description
- `functions/README.md` — the Cloud Functions backend: every deployed function,
  the source map, and the build/test/deploy commands
- `scripts/README.md` — the exercise-image pipeline: what each script does and
  the order they run in

## Build & test

```bash
# Build
xcodebuild build -project ios/PT-Helper/COIL.xcodeproj \
  -scheme COIL -destination 'platform=iOS Simulator,name=iPhone 16'

# Run all unit tests (default: UnitPlan)
xcodebuild test -project ios/PT-Helper/COIL.xcodeproj \
  -scheme COIL -destination 'platform=iOS Simulator,name=iPhone 16'

# Full suite including collision tests (300s timeout)
xcodebuild test -project ios/PT-Helper/COIL.xcodeproj \
  -scheme COIL -testPlan FullPlan -destination 'platform=iOS Simulator,name=iPhone 16'

# Pre-release suite: all unit + UI tests with code coverage (600s timeout)
xcodebuild test -project ios/PT-Helper/COIL.xcodeproj \
  -scheme COIL -testPlan PreReleasePlan -destination 'platform=iOS Simulator,name=iPhone 16'

# A single test class or method
xcodebuild test -project ios/PT-Helper/COIL.xcodeproj \
  -scheme COIL -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:COILTests/UserProfileTests/testDefaultUserProfile
```

> On some machines `name=iPhone 16` resolves to the wrong runtime and the build
> fails to find a destination. Append `,OS=18.2` — e.g.
> `-destination 'platform=iOS Simulator,name=iPhone 16,OS=18.2'` — or target the
> simulator by UDID.

### Test plans and their roles

| Plan | Role |
|---|---|
| `UnitPlan` | **PR gate.** All unit tests; runs on every push/PR to `main` |
| `FullPlan` | **Nightly.** Unit + body-map collision + UI tests; failures are triaged the next morning, they don't block |
| `PreReleasePlan` | **Release gate.** Same targets as FullPlan plus code coverage; run manually before a TestFlight build |
| `SmokePlan` | Local quick check only. It is an 11-test allow-list over a ~1,140-method suite — do not reintroduce it as a CI gate |

### Cloud Functions

```bash
cd functions
npm ci
npm run lint
npm run build             # prebuild codegen + tsc → lib/
npm test                  # jest unit suite, no emulator needed
npm run test:rules        # Firestore security rules (Firebase emulator + Java 21)
npm run test:integration  # integration suite (Firebase emulator + Java 21)
```

## Conventions

- **Design tokens only.** Colors, spacing, typography, corner radii and
  animations come from `DesignSystem.swift` (`AppColors`, `AppSpacing`,
  `AppFonts`, `AppCorners`, `AppAnimations`). Never hardcode a color or a
  spacing value. Use `CardSection` for form sections, `.cardStyle()` for card
  elevation, `ChipButton` for selectable tags.
- **Test naming:** `test<What>_<Condition>_<Expected>`, e.g.
  `testClassifySurgery_sameRegion_recentWithRestrictions`. Fixtures come from
  `ios/PT-Helper/COILTests/TestFixtures.swift`; ViewModels need `@MainActor` in tests.
- **Accessibility identifiers:** `screenName.elementName`, e.g.
  `workout.completeSetButton`. Identify the leaf control, not the wrapper — an
  identifier on a container can hide its children from XCUI.
- **AI prompts are server-side.** System prompts and per-request-type model
  configuration live in `functions/src/prompts.ts` (`SYSTEM_PROMPTS`,
  `MODEL_CONFIG`), so a prompt change ships with a function deploy rather than an
  App Store release. `functions/src/index.ts` only imports them.
- **Session logging:** add `.trackScreen("ScreenName")` to new views.

## Git workflow

1. Branch from `main`; rebase on `main` often and keep branches small.
2. `UnitPlan` green locally before opening a PR — it is the gate CI enforces.
3. `FullPlan` green before merging.
4. Stage by explicit path. Never `git add .` or `git commit -a` — parallel
   sessions share one git index in the main checkout.
5. Running more than one session at a time? One git worktree per session, one
   simulator per session, and never two Firebase deploys at once. Recipes are in
   `ios/PT-Helper/docs/parallel-sessions.md`.

Before submitting: tests pass, the build is warning-free (warnings are errors in
this project), new behavior has tests, and no hardcoded design values.
